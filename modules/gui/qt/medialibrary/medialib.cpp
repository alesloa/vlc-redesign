/*****************************************************************************
 * Copyright (C) 2019 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * ( at your option ) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#include "medialib.hpp"
#include "mlhelper.hpp"
#include "playlist/playlist_controller.hpp"
#include "util/shared_input_item.hpp"

#include <utility>

#include <QQmlEngine>
#include <QFileInfo>
#include <QHash>
#include <QSet>
#include <algorithm>

// The ML exposes stored subtitle/soundtrack files separately from the input
// item. Attach them at this GUI conversion boundary before normal playlist use.
// Core selection, timing and external-track loading remain unchanged.
static SharedInputItem inputItemWithStoredSlaves(vlc_medialibrary_t* ml, int64_t id,
                                                const vlc_ml_media_t* metadata = nullptr)
{
    SharedInputItem item(vlc_ml_get_input_item(ml, id), false);
    if (!item)
        return {};

    ml_unique_ptr<vlc_ml_media_t> ownedMetadata;
    if (!metadata)
    {
        ownedMetadata.reset(vlc_ml_get_media(ml, id));
        metadata = ownedMetadata.get();
    }
    if (!metadata || !metadata->p_files)
        return item;

    for (const auto& file : ml_range_iterate<vlc_ml_file_t>(metadata->p_files))
    {
        if (!file.psz_mrl || !file.b_present ||
            (file.i_type != VLC_ML_FILE_TYPE_SUBTITLE && file.i_type != VLC_ML_FILE_TYPE_SOUNDTRACK))
            continue;

        // Future core-provided slaves must not be added twice.
        bool alreadyAttached = false;
        vlc_mutex_lock(&item->lock);
        for (int i = 0; i < item->i_slaves; ++i)
            if (!strcmp(item->pp_slaves[i]->psz_uri, file.psz_mrl))
                alreadyAttached = true;
        vlc_mutex_unlock(&item->lock);
        if (alreadyAttached)
            continue;

        const auto type = file.i_type == VLC_ML_FILE_TYPE_SUBTITLE ? SLAVE_TYPE_SPU : SLAVE_TYPE_GENERIC;
        auto* slave = input_item_slave_New(file.psz_mrl, type, SLAVE_PRIORITY_USER);
        if (slave && input_item_AddSlave(item.get(), slave) != VLC_SUCCESS)
            input_item_slave_Delete(slave);
    }
    return item;
}

QSettings* MediaLib::interfaceSettings() const
{
    return m_intf->mainSettings;
}

MediaLib::MediaLib(qt_intf_t *_intf, vlc::playlist::PlaylistController* playlistController, QObject *_parent)
    : QObject( _parent )
    , m_intf( _intf )
    , m_playlistController(playlistController)
    , m_ml( vlc_ml_instance_get( _intf ) )
    , m_event_cb( nullptr, [this](vlc_ml_event_callback_t* cb ) {
        vlc_ml_event_unregister_callback( m_ml, cb );
      })
{
    m_event_cb.reset( vlc_ml_event_register_callback( m_ml, MediaLib::onMediaLibraryEvent,
                                                      this ) );
    m_runner = new ThreadRunner();
}

MediaLib::~MediaLib()
{
    m_runner->destroy();
}

static void convertMLItemToPlaylistMedias(vlc_medialibrary_t* ml, const MLItemId & itemId, const QStringList &options, QVector<vlc::playlist::Media>& medias)
{
    //invalid item
    if (itemId.id == 0)
        return;

    if (itemId.type == VLC_ML_PARENT_UNKNOWN)
    {
        SharedInputItem item = inputItemWithStoredSlaves(ml, itemId.id);
        if (item)
            medias.push_back(vlc::playlist::Media(item.get(), options));
    }
    else
    {
        vlc_ml_query_params_t query = vlc_ml_query_params_create();
        ml_unique_ptr<vlc_ml_media_list_t> media_list(vlc_ml_list_media_of( ml, &query, itemId.type, itemId.id));
        if (media_list == nullptr || media_list->i_nb_items == 0)
            return;

        auto mediaRange = ml_range_iterate<vlc_ml_media_t>( media_list );
        for (const auto& media : mediaRange)
        {
            SharedInputItem item = inputItemWithStoredSlaves(ml, media.i_id, &media);
            if (item)
                medias.push_back(vlc::playlist::Media(item.get(), options));
        }
    }
}

static void convertQUrlToPlaylistMedias(QUrl mrl, const QStringList& options, QVector<vlc::playlist::Media>& medias)
{
    vlc::playlist::Media media{ mrl.toString(QUrl::FullyEncoded), mrl.fileName(), options };
    medias.push_back(media);
}

static void convertQStringToPlaylistMedias(const QString &mrl, const QStringList& options, QVector<vlc::playlist::Media>& medias)
{
    vlc::playlist::Media media{ mrl, mrl, options };
    medias.push_back(media);
}


static void convertQVariantListToPlaylistMedias(vlc_medialibrary_t* ml, QVariantList itemIdList, const QStringList& options, QVector<vlc::playlist::Media>& medias)
{
    for (const QVariant& varValue: itemIdList)
    {
        if (varValue.canConvert<QUrl>())
        {
            auto mrl = varValue.value<QUrl>();
            convertQUrlToPlaylistMedias(mrl, options, medias);
        }
        else if (varValue.canConvert<QString>())
        {
            auto mrl = varValue.value<QString>();
            convertQStringToPlaylistMedias(mrl, options, medias);
        }
        else if (varValue.canConvert<MLItemId>())
        {
            MLItemId itemId = varValue.value<MLItemId>();
            convertMLItemToPlaylistMedias(ml, itemId, options, medias);
        }
        // else ignore
    }
}

MLItemId MediaLib::deserializeMlItemIdFromString(const QString& serialized_id) {
    return MLItemId::fromString(serialized_id);
}

void MediaLib::addToPlaylist(const QString& mrl, const QStringList &options)
{
    QVector<vlc::playlist::Media> medias;
    convertQStringToPlaylistMedias(mrl, options, medias);
    m_playlistController->append(medias, false);
}

void MediaLib::addToPlaylist(const QUrl& mrl, const QStringList &options)
{
    QVector<vlc::playlist::Media> medias;
    convertQUrlToPlaylistMedias(mrl, options, medias);
    m_playlistController->append(medias, false);
}

// A specific item has been asked to be added to the playlist
void MediaLib::addToPlaylist(const MLItemId & itemId, const QStringList &options)
{
    struct Context {
        QVector<vlc::playlist::Media> medias;
    };
    runOnMLThread<Context>(this,
    //ML thread
    [itemId, options]
    (vlc_medialibrary_t* ml, Context& ctx){
        convertMLItemToPlaylistMedias(ml, itemId, options, ctx.medias);
    },
    //UI thread
    [this](quint64, Context& ctx){
        if (!ctx.medias.empty())
            m_playlistController->append(ctx.medias, false);
    });
}

void MediaLib::addToPlaylist(const QVariantList& itemIdList, const QStringList &options)
{
    struct Context {
        QVector<vlc::playlist::Media> medias;
    };
    runOnMLThread<Context>(this,
    //ML thread
    [itemIdList, options]
    (vlc_medialibrary_t* ml, Context& ctx)
    {
        convertQVariantListToPlaylistMedias(ml, itemIdList, options, ctx.medias);
    },
    //UI thread
    [this](quint64, Context& ctx){
        if (!ctx.medias.empty())
            m_playlistController->append(ctx.medias, false);
    });
}

// A specific item has been asked to be played,
// so it's added to the playlist and played
void MediaLib::addAndPlay(const MLItemId & itemId, const QStringList &options )
{
    struct Context {
        QVector<vlc::playlist::Media> medias;
    };
    runOnMLThread<Context>(this,
    //ML thread
    [itemId, options]
    (vlc_medialibrary_t* ml, Context& ctx)
    {
        convertMLItemToPlaylistMedias(ml, itemId, options, ctx.medias);
    },
    //UI thread
    [this](quint64, Context& ctx){
        if (!ctx.medias.empty())
            m_playlistController->append(ctx.medias, true);
    });


}

void MediaLib::addAndPlay(const QString& mrl, const QStringList &options)
{
    vlc::playlist::Media media{ mrl, mrl, options };
    m_playlistController->append( QVector<vlc::playlist::Media>{media}, true );
}

void MediaLib::addAndPlay(const QUrl& mrl, const QStringList &options)
{
    vlc::playlist::Media media{ mrl.toString(QUrl::FullyEncoded), mrl.fileName(), options };
    m_playlistController->append( QVector<vlc::playlist::Media>{media}, true );
}


void MediaLib::addAndPlay(const QVariantList& itemIdList, const QStringList &options)
{
    struct Context {
        QVector<vlc::playlist::Media> medias;
    };
    runOnMLThread<Context>(this,
    //ML thread
    [itemIdList, options]
    (vlc_medialibrary_t* ml, Context& ctx)
    {
        convertQVariantListToPlaylistMedias(ml, itemIdList, options, ctx.medias);
    },
    //UI thread
    [this](quint64, Context& ctx){
        if (!ctx.medias.empty())
            m_playlistController->append(ctx.medias, true);
    });
}

void MediaLib::insertIntoPlaylist(const size_t index, const QVariantList &itemIdList, const QStringList &options)
{
    struct Context {
        QVector<vlc::playlist::Media> medias;
    };
    runOnMLThread<Context>(this,
    //ML thread
    [itemIdList, options]
    (vlc_medialibrary_t* ml, Context& ctx )
    {
        convertQVariantListToPlaylistMedias(ml, itemIdList, options, ctx.medias);
    },
    //UI thread
    [this, index]
    (quint64, Context& ctx) {
        if (!ctx.medias.isEmpty())
            m_playlistController->insert( index, ctx.medias );
    });
}

void MediaLib::reload()
{
    runOnMLThread(this,
    //ML thread
    [](vlc_medialibrary_t* ml){
        vlc_ml_reload_folder(ml, nullptr);
    });
}

void MediaLib::frequentArtists(int limit, QJSValue callback)
{
    if (!callback.isCallable())
        return;
    struct Ctx { QVariantList rows; };
    runOnMLThread<Ctx>(this, [limit](vlc_medialibrary_t* ml, Ctx& ctx) {
        if (limit <= 0)
            return;
        auto query = vlc_ml_query_params_create();
        query.i_sort = VLC_ML_SORTING_PLAYCOUNT;
        query.b_desc = true;
        query.i_nbResults = 128; // Internal read batch, never a displayed value.
        QHash<int64_t, uint64_t> counts;
        QSet<int64_t> seen;
        bool complete = false;
        while (!complete)
        {
            ml_unique_ptr<vlc_ml_media_list_t> media(vlc_ml_list_audio_media(ml, &query));
            if (!media || media->i_nb_items == 0)
                break;
            for (const auto& track : ml_range_iterate<vlc_ml_media_t>(media))
            {
                if (track.i_playcount == 0) { complete = true; break; }
                if (seen.contains(track.i_id))
                    continue;
                seen.insert(track.i_id);
                if (track.i_subtype == VLC_ML_MEDIA_SUBTYPE_ALBUMTRACK && track.album_track.i_artist_id > 0)
                    counts[track.album_track.i_artist_id] += track.i_playcount;
            }
            if (media->i_nb_items < query.i_nbResults)
                break;
            query.i_offset += query.i_nbResults;
        }
        std::vector<std::pair<int64_t, uint64_t>> ranked;
        ranked.reserve(counts.size());
        for (auto count = counts.cbegin(); count != counts.cend(); ++count)
            ranked.emplace_back(count.key(), count.value());
        std::sort(ranked.begin(), ranked.end(), [](const auto& first, const auto& second) {
            return first.second != second.second ? first.second > second.second : first.first < second.first;
        });
        for (const auto& count : ranked)
        {
            ml_unique_ptr<vlc_ml_artist_t> artist(vlc_ml_get_artist(ml, count.first));
            if (!artist || !artist->psz_name || !*artist->psz_name)
                continue;
            const MLItemId id(artist->i_id, VLC_ML_PARENT_ARTIST);
            ctx.rows.append(QVariantMap{{QStringLiteral("id"), QVariant::fromValue(id)},
                {QStringLiteral("mediaId"), QVariant::fromValue(id)},
                {QStringLiteral("serialized"), id.toString()},
                {QStringLiteral("title"), qfu(artist->psz_name)},
                {QStringLiteral("cover"), qfu(artist->thumbnails[VLC_ML_THUMBNAIL_SMALL].psz_mrl)},
                {QStringLiteral("kind"), QStringLiteral("artist")}});
            if (ctx.rows.size() >= limit)
                break;
        }
    }, [this, callback](quint64, Ctx& ctx) mutable {
        if (auto engine = qjsEngine(this))
            callback.call({engine->toScriptValue(ctx.rows)});
    });
}

void MediaLib::mlInputItem(const QVector<MLItemId>& itemIdVector, QJSValue callback)
{
    if (!callback.isCallable()) // invalid argument
    {
        msg_Warn(m_intf, "callback is not callbable");
        return;
    }

    struct Ctx {
        std::vector<SharedInputItem> items;
    };

    if (itemIdVector.empty())
    {
        //call the callback with and empty list
        auto jsEngine = qjsEngine(this);
        if (!jsEngine)
            return;
        auto jsArray = jsEngine->newArray(0);
        callback.call({jsArray});
        return;
    }

    auto it = m_inputItemQuery.find(itemIdVector);

    if (it == m_inputItemQuery.end())
    {
        it = m_inputItemQuery.insert(itemIdVector, {callback});
    }
    else
    {
        // be patient

        for (const auto& it2 : it.value())
        {
            if (callback.strictlyEquals(it2))
                return;
        }

        it.value().push_back(callback); // FIXME: Use an ordered set
        return;
    }

    runOnMLThread<Ctx>(this,
    //ML thread
    [itemIdVector](vlc_medialibrary_t* ml, Ctx& ctx){
        for (auto mlId : itemIdVector)
        {
            // NOTE: When we have a parent it's a collection of media(s).
            if (mlId.type == VLC_ML_PARENT_UNKNOWN)
            {
                if (auto item = inputItemWithStoredSlaves(ml, mlId.id))
                    ctx.items.push_back(std::move(item));
            }
            else
            {
                ml_unique_ptr<vlc_ml_media_list_t> list;

                vlc_ml_query_params_t query = vlc_ml_query_params_create();

                list.reset(vlc_ml_list_media_of(ml, &query, mlId.type, mlId.id));

                if (list == nullptr)
                    continue;

                for (const vlc_ml_media_t & media : ml_range_iterate<vlc_ml_media_t>(list))
                    if (auto item = inputItemWithStoredSlaves(ml, media.i_id, &media))
                        ctx.items.push_back(std::move(item));
            }
        }
    },
    //UI thread
    [this, it](quint64, Ctx& ctx) mutable
    {
        auto jsEngine = qjsEngine(this);
        if (!jsEngine)
            return;

        auto jsArray = jsEngine->newArray(ctx.items.size());

        int i  = 0;
        for (const auto& inputItem : ctx.items)
        {
            jsArray.setProperty(i, jsEngine->toScriptValue(inputItem));
            i++;
        }

        for (const auto& cb : std::as_const(it.value()))
        {
            cb.call({jsArray});
        }

        m_inputItemQuery.erase(it);
    });
}

void MediaLib::addExternalSubtitle(const MLItemId& itemId, const QUrl& subtitle)
{
    enum slave_type type;
    const QFileInfo file(subtitle.toLocalFile());
    const QByteArray encoded = subtitle.toEncoded(QUrl::FullyEncoded);
    if (!itemId.isValid() || itemId.hasParent() || !subtitle.isLocalFile()
        || !file.isFile() || !file.isReadable()
        || !input_item_slave_GetType(encoded.constData(), &type) || type != SLAVE_TYPE_SPU)
    {
        emit externalSubtitleAdded(itemId, subtitle, false);
        return;
    }
    struct Context { bool success = false; };
    runOnMLThread<Context>(this,
        [itemId, encoded](vlc_medialibrary_t* ml, Context& ctx)
        {
            ml_unique_ptr<vlc_ml_media_t> media(vlc_ml_get_media(ml, itemId.id));
            if (media && media->i_type == VLC_ML_MEDIA_TYPE_VIDEO)
            {
                // The ML rejects a duplicate external MRL. A verified existing
                // association already satisfies the user's explicit mapping.
                if (media->p_files)
                    for (const auto& file : ml_range_iterate<vlc_ml_file_t>(media->p_files))
                        if (file.i_type == VLC_ML_FILE_TYPE_SUBTITLE && file.b_present && file.psz_mrl &&
                            !strcmp(file.psz_mrl, encoded.constData()))
                            ctx.success = true;
                if (!ctx.success)
                    ctx.success = vlc_ml_media_add_external_mrl(ml, itemId.id, encoded.constData(),
                                                              VLC_ML_FILE_TYPE_SUBTITLE) == VLC_SUCCESS;
            }
        },
        [this, itemId, subtitle](quint64, Context& ctx)
        {
            emit externalSubtitleAdded(itemId, subtitle, ctx.success);
        });
}

vlc_ml_event_callback_t* MediaLib::registerEventListener( void (*callback)(void*, const vlc_ml_event_t*), void* data)
{
    return vlc_ml_event_register_callback( m_ml , callback , data ) ;
}

void MediaLib::unregisterEventListener(vlc_ml_event_callback_t* cb)
{
    vlc_ml_event_unregister_callback( m_ml , cb );
}

void MediaLib::onMediaLibraryEvent( void* data, const vlc_ml_event_t* event )
{
    MediaLib* self = static_cast<MediaLib*>( data );
    switch ( event->i_type )
    {
        case VLC_ML_EVENT_PARSING_PROGRESS_UPDATED:
        {
            int percent =  event->parsing_progress.i_percent;
            QMetaObject::invokeMethod(self, [self, percent]() {
                self->m_parsingProgress = percent;
                self->emit parsingProgressChanged(percent);
            });
            break;
        }
        case VLC_ML_EVENT_DISCOVERY_STARTED:
        {
            QMetaObject::invokeMethod(self, [self]() {
                self->m_discoveryPending = true;
                self->emit discoveryPendingChanged(self->m_discoveryPending);
                self->emit discoveryStarted();
            });
            break;
        }
        case VLC_ML_EVENT_DISCOVERY_PROGRESS:
        {
            const QUrl entryPoint{ event->discovery_progress.psz_entry_point };
            const QString entryPointStr = entryPoint.isLocalFile()
                                              ? entryPoint.toLocalFile()
                                              : entryPoint.toDisplayString();

            QMetaObject::invokeMethod(self, [self, entryPointStr]() {
                self->m_discoveryEntryPoint = entryPointStr;
                self->emit discoveryEntryPointChanged(entryPointStr);
            });
            break;
        }
        case VLC_ML_EVENT_DISCOVERY_COMPLETED:
        {
            QMetaObject::invokeMethod(self, [self]() {
                self->m_discoveryPending = false;
                self->emit discoveryPendingChanged(self->m_discoveryPending);
                self->emit discoveryCompleted();
            });
            break;
        }
        case VLC_ML_EVENT_BACKGROUND_IDLE_CHANGED:
        {
            bool idle = event->background_idle_changed.b_idle;
            QMetaObject::invokeMethod(self, [self, idle]() {
                self->m_idle = idle;
                self->emit idleChanged();
            });
            break;
        }
        default:
            break;
    }
}

quint64 MediaLib::runOnMLThread(const QObject* obj,
                std::function< void(vlc_medialibrary_t* ml)> mlCb,
                std::function< void()> uiCb,
                const char* queue)
{
    struct NoCtx{};
    return m_runner->runOnThread<NoCtx>(obj,
    [mlCb, ml=m_ml](NoCtx&){
        mlCb(ml);
    },
    [uiCb](quint64, NoCtx&){
        uiCb();
    },
    queue);
}

quint64 MediaLib::runOnMLThread(const QObject* obj,
                std::function< void(vlc_medialibrary_t* ml)> mlCb,
                std::function< void(quint64)> uiCb, const char* queue)
{
    struct NoCtx{};
    return m_runner->runOnThread<NoCtx>(obj,
    [mlCb, ml=m_ml](NoCtx&){
        mlCb(ml);
    },
    [uiCb](quint64 requestId, NoCtx&){
        uiCb(requestId);
    },
    queue);
}

quint64 MediaLib::runOnMLThread(const QObject* obj,
                std::function< void(vlc_medialibrary_t* ml)> mlCb,
                const char* queue)
{
    struct NoCtx{};
    return m_runner->runOnThread<NoCtx>(obj,
    [mlCb, ml=m_ml](NoCtx&){
        mlCb(ml);
    },
    [](quint64, NoCtx&){
    },
    queue);
}

void MediaLib::cancelMLTask(const QObject* object, quint64 taskId)
{
    m_runner->cancelTask(object, taskId);
}

