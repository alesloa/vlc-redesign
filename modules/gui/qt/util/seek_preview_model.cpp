/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
#include "seek_preview_model.hpp"
#include "maininterface/mainctx.hpp"
#include "player/player_controller.hpp"
#include "util/shared_input_item.hpp"
#include "qt.hpp"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QFile>
#include <QImageReader>
#include <algorithm>
#include <cmath>
#include <vlc_preparser.h>
#include <vlc_cxx_helpers.hpp>

struct SeekPreviewModel::Request
{
    // Only the GUI completion lambda reads this QPointer. Callback threads
    // merely keep its owning context and temporary directory alive.
    QPointer<SeekPreviewModel> owner;
    std::shared_ptr<QTemporaryDir> directory;
    quint64 revision;
    qint64 key;
    QString path;
    QByteArray encodedPath;
};

SeekPreviewModel::SeekPreviewModel(QObject* parent) : QObject(parent)
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(150);
    connect(&m_debounce, &QTimer::timeout, this, &SeekPreviewModel::requestFrame);
}

SeekPreviewModel::~SeekPreviewModel() { destroyPreparser(); }
MainCtx* SeekPreviewModel::ctx() const { return m_ctx; }

void SeekPreviewModel::setCtx(MainCtx* ctx)
{
    if (m_ctx == ctx)
        return;
    if (m_ctx)
        disconnect(m_ctx, nullptr, this, nullptr);
    if (m_player)
        disconnect(m_player, nullptr, this, nullptr);
    destroyPreparser();
    m_ctx = ctx;
    m_player = ctx && ctx->getIntf() ? ctx->getIntf()->p_mainPlayerController : nullptr;
    m_available = false;
    if (m_player)
    {
        connect(m_player, &PlayerController::inputChanged, this, &SeekPreviewModel::resetMedia);
        connect(m_player, &PlayerController::lengthChanged, this, &SeekPreviewModel::schedule);
        connect(m_player, &QObject::destroyed, this, [this] { m_player = nullptr; destroyPreparser(); });
    }
    if (m_ctx)
    {
        connect(m_ctx, &QObject::destroyed, this, [this] {
            m_ctx = nullptr;
            m_player = nullptr;
            destroyPreparser();
            m_available = false;
            emit availableChanged();
            emit ctxChanged();
        });
        if (vlc_preparser_CheckThumbnailerFormat(VLC_THUMBNAILER_FORMAT_PNG) == VLC_SUCCESS)
        {
            m_format = VLC_THUMBNAILER_FORMAT_PNG;
            m_extension = QStringLiteral("png");
            m_available = true;
        }
        else if (vlc_preparser_CheckThumbnailerFormat(VLC_THUMBNAILER_FORMAT_JPEG) == VLC_SUCCESS)
        {
            m_format = VLC_THUMBNAILER_FORMAT_JPEG;
            m_extension = QStringLiteral("jpg");
            m_available = true;
        }
    }
    emit availableChanged();
    emit ctxChanged();
    schedule();
}

void SeekPreviewModel::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
    if (active)
        schedule();
    else
    {
        m_debounce.stop();
        cancelRequest();
    }
}

void SeekPreviewModel::setPosition(double position)
{
    if (!std::isfinite(position))
        return;
    position = std::clamp(position, 0.0, 1.0);
    if (m_position == position)
        return;
    m_position = position;
    emit positionChanged();
    schedule();
}

void SeekPreviewModel::setOutputSize(QSize size)
{
    if (size.isEmpty() || m_size == size)
        return;
    m_size = size;
    resetMedia();
    emit outputSizeChanged();
}

void SeekPreviewModel::setSource(const QUrl& source)
{
    if (m_source == source)
        return;
    m_source = source;
    emit sourceChanged();
}

void SeekPreviewModel::cancelRequest()
{
    ++m_revision;
    if (!m_request)
        return;
    auto* request = m_request;
    m_request = nullptr;
    // Cancellation can invoke completed() synchronously. No lock is held;
    // the completion only queues a GUI lambda and never accesses this object.
    vlc_preparser_Cancel(m_preparser, request);
    vlc_preparser_req_Release(request);
}

void SeekPreviewModel::resetMedia()
{
    m_debounce.stop();
    cancelRequest();
    m_uri.clear();
    m_key = -1;
    m_cache.clear();
    m_lru.clear();
    m_directory.reset();
    setSource({});
    schedule();
}

void SeekPreviewModel::destroyPreparser()
{
    m_debounce.stop();
    cancelRequest();
    if (m_preparser)
        vlc_preparser_Delete(m_preparser);
    m_preparser = nullptr;
    m_cache.clear();
    m_lru.clear();
    m_directory.reset();
    m_uri.clear();
    m_key = -1;
    setSource({});
}

void SeekPreviewModel::schedule()
{
    if (!m_active || !m_available || !m_player)
        return;
    const double seconds = m_player->getLength().toSecf();
    if (!m_player->getLength().valid() || !std::isfinite(seconds) || seconds <= 0)
    {
        m_debounce.stop();
        cancelRequest();
        m_key = -1;
        setSource({});
        return;
    }
    const qint64 key = qint64(std::floor(seconds * m_position));
    if (m_key != key)
    {
        m_key = key;
        cancelRequest();
        setSource({});
    }
    if (m_cache.contains(key))
    {
        m_lru.removeAll(key);
        m_lru.append(key);
        setSource(m_cache.value(key));
        return;
    }
    m_debounce.start();
}

void SeekPreviewModel::requestFrame()
{
    if (!m_active || !m_available || !m_ctx || !m_ctx->getIntf() || !m_player || m_request)
        return;
    SharedInputItem item;
    {
        auto* player = m_player->getPlayer();
        if (!player)
            return;
        vlc_player_locker lock{player};
        auto* current = vlc_player_GetCurrentMedia(player);
        if (current)
            item = SharedInputItem(current);
    }
    if (!item)
        return;
    const QString uri = qfu(item->psz_uri);
    if (m_uri != uri)
    {
        cancelRequest();
        m_cache.clear();
        m_lru.clear();
        m_directory.reset();
        m_uri = uri;
    }
    if (!m_preparser)
    {
        vlc_preparser_cfg cfg{};
        cfg.types = VLC_PREPARSER_TYPE_THUMBNAIL_TO_FILES;
        cfg.max_thumbnailer_threads = 1;
        cfg.timeout = VLC_TICK_FROM_MS(std::max<int64_t>(0,
            var_InheritInteger(m_ctx->getIntf(), "preparse-timeout")));
        m_preparser = vlc_preparser_New(VLC_OBJECT(m_ctx->getIntf()), &cfg);
        if (!m_preparser)
            return;
    }
    if (!m_directory)
        m_directory = std::make_shared<QTemporaryDir>();
    if (!m_directory->isValid())
        return;
    auto* job = new Request{this, m_directory, m_revision, m_key,
        m_directory->filePath(QStringLiteral("frame-%1.%2").arg(++m_serial).arg(m_extension)), {}};
    // The external preparser serializes outputs asynchronously. Keep the
    // path bytes alive until its completion, as well as the temporary folder.
    job->encodedPath = QFile::encodeName(job->path);
    vlc_thumbnailer_arg arg{};
    arg.seek.type = decltype(arg.seek)::VLC_THUMBNAILER_SEEK_TIME;
    arg.seek.time = VLC_TICK_FROM_SEC(m_key);
    arg.seek.speed = decltype(arg.seek)::VLC_THUMBNAILER_SEEK_PRECISE;
    arg.hw_dec = false;
    vlc_thumbnailer_output output{};
    output.format = static_cast<vlc_thumbnailer_format>(m_format);
    output.width = m_size.width();
    output.height = m_size.height();
    output.crop = false;
    output.file_path = job->encodedPath.constData();
    output.creat_mode = 0600;
    static const vlc_thumbnailer_to_files_cbs callbacks{completed};
    m_request = vlc_preparser_req_NewThumbnailToFiles(m_preparser, item.get(), &arg, &output, 1, &callbacks, job);
    if (!m_request || vlc_preparser_Submit(m_preparser, m_request) != VLC_SUCCESS)
    {
        if (m_request)
            vlc_preparser_req_Release(m_request);
        m_request = nullptr;
        delete job; // Failed submission cannot invoke the callback.
    }
}

void SeekPreviewModel::completed(vlc_preparser_req* request, int status,
                                const bool* results, size_t count, void* opaque)
{
    auto job = std::shared_ptr<Request>(static_cast<Request*>(opaque));
    const bool exported = status == VLC_SUCCESS && count > 0 && results && results[0];
    if (auto* app = QCoreApplication::instance())
        QMetaObject::invokeMethod(app, [job, request, exported] {
            if (!job->owner || job->revision != job->owner->m_revision || job->owner->m_request != request)
            {
                QFile::remove(job->path);
                return;
            }
            auto* owner = job->owner.data();
            owner->m_request = nullptr;
            vlc_preparser_req_Release(request);
            if (!exported || !QImageReader(job->path).canRead())
            {
                QFile::remove(job->path);
                return;
            }
            const auto source = QUrl::fromLocalFile(job->path);
            owner->m_cache.insert(job->key, source);
            owner->m_lru.removeAll(job->key);
            owner->m_lru.append(job->key);
            while (owner->m_lru.size() > 24)
                QFile::remove(owner->m_cache.take(owner->m_lru.takeFirst()).toLocalFile());
            if (owner->m_active && owner->m_key == job->key)
                owner->setSource(source);
        }, Qt::QueuedConnection);
}
