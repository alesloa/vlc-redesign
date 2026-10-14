/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
#include "sleep_timer_model.hpp"
#include "maininterface/mainctx.hpp"
#include "playlist/playlist_controller.hpp"
#include "qt.hpp"
#include <cmath>
#include <limits>

SleepTimerModel::SleepTimerModel(QObject* parent) : QObject(parent)
{
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, &SleepTimerModel::tick);
}

MainCtx* SleepTimerModel::ctx() const { return m_ctx; }

void SleepTimerModel::setCtx(MainCtx* ctx)
{
    if (m_ctx == ctx)
        return;
    if (m_ctx)
        disconnect(m_ctx, nullptr, this, nullptr);
    cancel();
    m_ctx = ctx;
    if (m_ctx)
        connect(m_ctx, &QObject::destroyed, this, &SleepTimerModel::cancel);
    emit ctxChanged();
}

VLCDuration SleepTimerModel::remaining() const
{
    return VLCDuration::fromMS(m_active ? std::max<qint64>(0, m_duration - m_elapsed.elapsed()) : 0);
}

bool SleepTimerModel::start(double minutes)
{
    const double milliseconds = minutes * 60000.0;
    if (!m_ctx || !m_ctx->getIntf() || !m_ctx->getIntf()->p_mainPlaylistController
        || !std::isfinite(milliseconds) || milliseconds < 1
        // VLCTick's displayed hours/minutes/seconds use int values. Keep the
        // user interval representable by that existing time presentation API.
        || milliseconds >= double(std::numeric_limits<int>::max()) * 1000.0)
        return false;
    m_duration = qint64(milliseconds);
    m_minutes = minutes;
    m_elapsed.start();
    m_active = true;
    emit minutesChanged();
    emit activeChanged();
    tick();
    return true;
}

void SleepTimerModel::cancel()
{
    m_timer.stop();
    if (!m_active)
        return;
    m_active = false;
    emit activeChanged();
    emit remainingChanged();
}

void SleepTimerModel::tick()
{
    if (!m_active)
        return;
    const auto remainingMs = m_duration - m_elapsed.elapsed();
    if (remainingMs <= 0)
    {
        cancel();
        if (m_ctx && m_ctx->getIntf() && m_ctx->getIntf()->p_mainPlaylistController)
            m_ctx->getIntf()->p_mainPlaylistController->stop();
        return;
    }
    emit remainingChanged();
    // Chunk long user durations rather than truncating QTimer's int interval.
    m_timer.start(int(std::min<qint64>(remainingMs, 1000)));
}
