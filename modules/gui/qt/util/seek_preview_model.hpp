/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
#ifndef VLC_SEEK_PREVIEW_MODEL_HPP
#define VLC_SEEK_PREVIEW_MODEL_HPP

#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QUrl>
#include <QSize>
#include <QMap>
#include <QList>
#include <memory>

class MainCtx;
class PlayerController;
class QTemporaryDir;
struct vlc_preparser_t;
struct vlc_preparser_req;
Q_MOC_INCLUDE("maininterface/mainctx.hpp")

// Seek images come from VLC's existing thumbnail preparser, never artwork or
// a design sample. One cancellable request and a bounded temporary cache leave
// the actual player's decoder, position and playback state unchanged.
class SeekPreviewModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(MainCtx* ctx READ ctx WRITE setCtx NOTIFY ctxChanged FINAL)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged FINAL)
    Q_PROPERTY(double position READ position WRITE setPosition NOTIFY positionChanged FINAL)
    Q_PROPERTY(QSize outputSize READ outputSize WRITE setOutputSize NOTIFY outputSizeChanged FINAL)
    Q_PROPERTY(QUrl source READ source NOTIFY sourceChanged FINAL)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged FINAL)
public:
    explicit SeekPreviewModel(QObject* parent = nullptr);
    ~SeekPreviewModel() override;
    MainCtx* ctx() const;
    void setCtx(MainCtx* ctx);
    bool active() const { return m_active; }
    void setActive(bool active);
    double position() const { return m_position; }
    void setPosition(double position);
    QSize outputSize() const { return m_size; }
    void setOutputSize(QSize size);
    QUrl source() const { return m_source; }
    bool available() const { return m_available; }
signals:
    void ctxChanged();
    void activeChanged();
    void positionChanged();
    void outputSizeChanged();
    void sourceChanged();
    void availableChanged();
private:
    struct Request;
    static void completed(vlc_preparser_req* request, int status,
                          const bool* results, size_t count, void* opaque);
    void cancelRequest();
    void resetMedia();
    void destroyPreparser();
    void schedule();
    void requestFrame();
    void setSource(const QUrl& source);
    QPointer<MainCtx> m_ctx;
    QPointer<PlayerController> m_player;
    QTimer m_debounce;
    vlc_preparser_t* m_preparser = nullptr;
    vlc_preparser_req* m_request = nullptr;
    std::shared_ptr<QTemporaryDir> m_directory;
    QMap<qint64, QUrl> m_cache;
    QList<qint64> m_lru;
    QString m_uri;
    QUrl m_source;
    // Source: Figma seek image 2151:9674 is 252×142 before display scaling.
    QSize m_size{252, 142};
    quint64 m_revision = 0;
    quint64 m_serial = 0;
    qint64 m_key = -1;
    int m_format = 0;
    QString m_extension;
    double m_position = 0;
    bool m_active = false;
    bool m_available = false;
};
#endif
