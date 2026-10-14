/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/
#ifndef VLC_INTERFACE_OPTIONS_MODEL_HPP
#define VLC_INTERFACE_OPTIONS_MODEL_HPP

#include <QAbstractListModel>
#include <QPointer>
#include <QVariant>
#include <QVector>

class MainCtx;
struct module_config_t;
Q_MOC_INCLUDE("maininterface/mainctx.hpp")

// A deferred preferences editor using ConfigControl's metadata/save path.
// Explicit filter groups also use the existing Effects APIs after Apply.
class InterfaceOptionsModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(MainCtx* ctx READ ctx WRITE setCtx NOTIFY ctxChanged FINAL)
    Q_PROPERTY(Group group READ group WRITE setGroup NOTIFY groupChanged FINAL)
    Q_PROPERTY(int count READ count NOTIFY countChanged FINAL)
    Q_PROPERTY(bool dirty READ dirty NOTIFY dirtyChanged FINAL)
    Q_PROPERTY(QString filterTitle READ filterTitle NOTIFY groupChanged FINAL)
    Q_PROPERTY(bool filterAvailable READ filterAvailable NOTIFY groupChanged FINAL)
    Q_PROPERTY(bool filterEnabled READ filterEnabled WRITE setFilterEnabled NOTIFY filterEnabledChanged FINAL)

public:
    enum Group {
        SubtitleFormatting, AudioEqualizer, VideoAdjustment,
        AudioDefaults, EqualizerFilter, CompressorFilter, SpatializerFilter,
        StereoWidenerFilter, PitchFilter, AdjustmentFilter, SharpenFilter,
        BandingFilter, GrainFilter, CropFilter, ExtractionFilter,
        ColorThresholdFilter, NegateFilter, PosterizeFilter, GradientFilter,
        SepiaFilter, TransformFilter, RotateFilter
    };
    Q_ENUM(Group)
    enum Role {
        TitleRole = Qt::UserRole + 1, HelpRole, KindRole, ValueRole,
        ChoicesRole, MinimumRole, MaximumRole, HasRangeRole, ColorRole, BandsRole
    };

    explicit InterfaceOptionsModel(QObject* parent = nullptr);
    MainCtx* ctx() const;
    void setCtx(MainCtx* ctx);
    Group group() const { return m_group; }
    void setGroup(Group group);
    int count() const { return m_rows.size(); }
    bool dirty() const;
    QString filterTitle() const;
    bool filterAvailable() const;
    bool filterEnabled() const { return m_filterEnabled; }
    void setFilterEnabled(bool enabled);
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE bool setValue(int row, const QVariant& value);
    Q_INVOKABLE bool setBand(int row, int band, double value);
    Q_INVOKABLE bool apply();
    Q_INVOKABLE bool applyBatch(const QVariantList& models);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE QVariantMap snapshot() const;
    Q_INVOKABLE bool restoreSnapshot(const QVariantMap& snapshot);

signals:
    void ctxChanged();
    void groupChanged();
    void countChanged();
    void dirtyChanged();
    void filterEnabledChanged();

private:
    struct Row {
        const module_config_t* option;
        QString kind;
        QVariant value;
        QVariant original;
        QVariantList choices;
    };
    void reload();
    QVariantList bands(const Row& row) const;
    const char* filterModule() const;
    bool audioFilter() const;
    void applyLiveFilter();
    void writeConfiguration();
    QPointer<MainCtx> m_ctx;
    Group m_group = SubtitleFormatting;
    QVector<Row> m_rows;
    bool m_filterEnabled = false;
    bool m_originalFilterEnabled = false;
};

#endif
