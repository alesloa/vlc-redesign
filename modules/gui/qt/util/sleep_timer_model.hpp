/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
#ifndef VLC_SLEEP_TIMER_MODEL_HPP
#define VLC_SLEEP_TIMER_MODEL_HPP

#include <QObject>
#include <QPointer>
#include <QElapsedTimer>
#include <QTimer>
#include "vlctick.hpp"

class MainCtx;
Q_MOC_INCLUDE("maininterface/mainctx.hpp")

// A GUI timer for the Figma Sleep Timer action. Its only playback operation
// is the existing playlist Stop; the duration is supplied by the user.
class SleepTimerModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(MainCtx* ctx READ ctx WRITE setCtx NOTIFY ctxChanged FINAL)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged FINAL)
    Q_PROPERTY(double minutes READ minutes NOTIFY minutesChanged FINAL)
    Q_PROPERTY(VLCDuration remaining READ remaining NOTIFY remainingChanged FINAL)
public:
    explicit SleepTimerModel(QObject* parent = nullptr);
    MainCtx* ctx() const;
    void setCtx(MainCtx* ctx);
    bool active() const { return m_active; }
    double minutes() const { return m_minutes; }
    VLCDuration remaining() const;
    Q_INVOKABLE bool start(double minutes);
    Q_INVOKABLE void cancel();
signals:
    void ctxChanged();
    void activeChanged();
    void minutesChanged();
    void remainingChanged();
private:
    void tick();
    QPointer<MainCtx> m_ctx;
    QElapsedTimer m_elapsed;
    QTimer m_timer;
    qint64 m_duration = 0;
    double m_minutes = 0;
    bool m_active = false;
};
#endif
