/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif
#include "interface_presets_model.hpp"
#include "interface_options_model.hpp"
#include "maininterface/mainctx.hpp"
#include "medialibrary/medialib.hpp"
#include "medialibrary/mlhelper.hpp"
#include "medialibrary/mlqmltypes.hpp"
#include "qt.hpp"
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <algorithm>

static const QString settingsKey = QStringLiteral("Player/InterfacePresets");

static QVariantMap mergeFields(QVariantMap previous, const QVariantMap& current)
{
    for (auto field = current.cbegin(); field != current.cend(); ++field)
        previous.insert(field.key(), field.value());
    return previous;
}

static QVariantMap mergeSnapshot(const QVariantMap& previous, const QVariantMap& current)
{
    auto result = mergeFields(previous, current);
    auto groups = previous.value(QStringLiteral("groups")).toList();
    for (const auto& value : current.value(QStringLiteral("groups")).toList())
    {
        const auto group = value.toMap();
        auto found = std::find_if(groups.begin(), groups.end(), [&group](const QVariant& old) {
            return old.toMap().value(QStringLiteral("group"), -1) == group.value(QStringLiteral("group"), -2);
        });
        if (found == groups.end())
            groups.append(value);
        else
        {
            const auto old = found->toMap();
            auto merged = mergeFields(old, group);
            merged.insert(QStringLiteral("options"), mergeFields(old.value(QStringLiteral("options")).toMap(),
                                                                   group.value(QStringLiteral("options")).toMap()));
            *found = merged;
        }
    }
    result.insert(QStringLiteral("groups"), groups);
    if (current.contains(QStringLiteral("sync")))
        result.insert(QStringLiteral("sync"), mergeFields(previous.value(QStringLiteral("sync")).toMap(),
                                                           current.value(QStringLiteral("sync")).toMap()));
    return result;
}

InterfacePresetsModel::InterfacePresetsModel(QObject* parent) : QAbstractListModel(parent) {}
MainCtx* InterfacePresetsModel::ctx() const { return m_ctx; }

void InterfacePresetsModel::setCtx(MainCtx* ctx)
{
    if (m_ctx == ctx) return;
    m_ctx = ctx;
    m_settings = ctx && ctx->getIntf() ? ctx->getIntf()->mainSettings : nullptr;
    reload();
    updateScope();
    emit ctxChanged();
}

void InterfacePresetsModel::setSection(Section section)
{
    if (section == m_section || section < Subtitles || section > Video) return;
    m_section = section;
    refreshVisible();
    emit sectionChanged();
}

void InterfacePresetsModel::setMediaUrl(const QUrl& url)
{
    if (url == m_mediaUrl) return;
    m_mediaUrl = url;
    updateScope();
    emit mediaUrlChanged();
}

int InterfacePresetsModel::rowCount(const QModelIndex& parent) const { return parent.isValid() ? 0 : count(); }
QHash<int, QByteArray> InterfacePresetsModel::roleNames() const { return {{NameRole, "name"}, {ScopeRole, "scopeTitle"}}; }
QVariant InterfacePresetsModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= count()) return {};
    const auto& record = m_records[m_visible[index.row()]];
    if (role == NameRole || role == Qt::DisplayRole) return record.value(QStringLiteral("name"));
    if (role == ScopeRole) return record.value(QStringLiteral("scopeTitle"));
    return {};
}
QVariantMap InterfacePresetsModel::get(int row) const { return row >= 0 && row < count() ? m_records[m_visible[row]] : QVariantMap(); }

void InterfacePresetsModel::reload()
{
    QVector<QVariantMap> records;
    if (m_settings)
    {
        const auto array = QJsonDocument::fromJson(m_settings->value(settingsKey).toString().toUtf8()).array();
        for (const auto& entry : array)
        {
            const auto record = entry.toObject().toVariantMap();
            const int section = record.value(QStringLiteral("section"), -1).toInt();
            if (section >= Subtitles && section <= Video && !record.value(QStringLiteral("name")).toString().isEmpty()
                && !record.value(QStringLiteral("snapshot")).toMap().isEmpty())
                records.append(record);
        }
    }
    refreshVisible(&records);
}

void InterfacePresetsModel::refreshVisible(const QVector<QVariantMap>* records)
{
    beginResetModel();
    if (records) m_records = *records;
    m_visible.clear();
    for (int i = 0; i < m_records.size(); ++i)
        if (m_records[i].value(QStringLiteral("section")).toInt() == int(m_section)
            && (m_records[i].value(QStringLiteral("scopeKey")).toString().isEmpty()
                || m_records[i].value(QStringLiteral("scopeKey")).toString() == m_scopeKey))
            m_visible.append(i);
    endResetModel();
    emit countChanged();
}

bool InterfacePresetsModel::persist(const QVector<QVariantMap>& records)
{
    if (!m_settings) return false;
    QJsonArray array;
    for (const auto& record : records) array.append(QJsonObject::fromVariantMap(record));
    m_settings->setValue(settingsKey, QString::fromUtf8(QJsonDocument(array).toJson(QJsonDocument::Compact)));
    m_settings->sync();
    if (m_settings->status() != QSettings::NoError) return false;
    refreshVisible(&records);
    return true;
}

bool InterfacePresetsModel::save(const QString& name, const QVariantMap& snapshot, bool scoped)
{
    if (name.trimmed().isEmpty() || snapshot.value(QStringLiteral("groups")).toList().isEmpty()
        || (scoped && !scopeAvailable())) return false;
    // Keys/values are produced by existing InterfaceOptionsModel snapshots;
    // the label is entered by the user and the scope is verified source data.
    const QString key = scoped ? m_scopeKey : QString();
    auto records = m_records;
    QVariantMap record{{QStringLiteral("name"), name.trimmed()}, {QStringLiteral("section"), int(m_section)},
        {QStringLiteral("scopeKey"), key}, {QStringLiteral("scopeTitle"), scoped ? m_scopeTitle : QString()},
        {QStringLiteral("snapshot"), snapshot}};
    for (auto& existing : records)
        if (existing.value(QStringLiteral("section")).toInt() == int(m_section)
            && existing.value(QStringLiteral("scopeKey")).toString() == key
            && existing.value(QStringLiteral("name")).toString() == name.trimmed())
        {
            // A preset may travel between Qt/AppKit or installations with
            // different modules. Replace only supplied, source-backed fields
            // while retaining provider-specific groups/options and metadata.
            const auto preserved = existing;
            existing = mergeFields(existing, record);
            existing.insert(QStringLiteral("snapshot"), mergeSnapshot(preserved.value(QStringLiteral("snapshot")).toMap(), snapshot));
            return persist(records);
        }
    records.append(record);
    return persist(records);
}

bool InterfacePresetsModel::remove(int row)
{
    if (row < 0 || row >= count()) return false;
    auto records = m_records;
    records.removeAt(m_visible[row]);
    return persist(records);
}

void InterfacePresetsModel::setScope(const QString& key, const QString& title)
{
    if (key == m_scopeKey && title == m_scopeTitle) return;
    m_scopeKey = key;
    m_scopeTitle = title;
    refreshVisible();
    emit scopeChanged();
}

void InterfacePresetsModel::updateScope()
{
    const quint64 revision = ++m_scopeRevision;
    if (m_mediaUrl.isLocalFile())
    {
        const QDir folder(QFileInfo(m_mediaUrl.toLocalFile()).absolutePath());
        setScope(QStringLiteral("folder:") + QString::fromUtf8(QUrl::fromLocalFile(folder.absolutePath()).toEncoded(QUrl::FullyEncoded)),
                 folder.dirName().isEmpty() ? folder.absolutePath() : folder.dirName());
    }
    else setScope({}, {});
    auto* ml = m_ctx ? m_ctx->getMediaLibrary() : nullptr;
    if (!ml || m_mediaUrl.isEmpty()) return;
    const QByteArray uri = m_mediaUrl.toEncoded(QUrl::FullyEncoded);
    struct Scope { QString key; QString title; };
    ml->runOnMLThread<Scope>(this, [uri](vlc_medialibrary_t* library, Scope& scope) {
        ml_unique_ptr<vlc_ml_media_t> media(vlc_ml_get_media_by_mrl(library, uri.constData()));
        if (!media || media->i_subtype != VLC_ML_MEDIA_SUBTYPE_SHOW_EPISODE) return;
        const auto query = vlc_ml_query_params_create();
        ml_unique_ptr<vlc_ml_show_list_t> shows(vlc_ml_list_shows(library, &query));
        if (!shows) return;
        for (const auto& show : ml_range_iterate<vlc_ml_show_t>(shows))
        {
            ml_unique_ptr<vlc_ml_media_list_t> episodes(vlc_ml_list_show_episodes(library, &query, show.i_id));
            if (!episodes) continue;
            for (const auto& episode : ml_range_iterate<vlc_ml_media_t>(episodes))
                if (episode.i_id == media->i_id)
                {
                    scope.key = MLItemId(show.i_id, VLC_ML_PARENT_SHOW).toString();
                    scope.title = show.psz_name ? qfu(show.psz_name) : QString();
                    return;
                }
        }
    }, [this, revision](quint64, Scope& scope) {
        if (revision == m_scopeRevision && !scope.key.isEmpty()) setScope(scope.key, scope.title);
    });
}
