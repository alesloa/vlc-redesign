/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 * SPDX-License-Identifier: GPL-2.0-or-later
 *****************************************************************************/
#ifndef VLC_INTERFACE_PRESETS_MODEL_HPP
#define VLC_INTERFACE_PRESETS_MODEL_HPP

#include <QAbstractListModel>
#include <QPointer>
#include <QUrl>
#include <QVariantMap>
#include <QVector>

class MainCtx;
class QSettings;
Q_MOC_INCLUDE("maininterface/mainctx.hpp")

// User-named GUI snapshots contain existing option-model keys and player sync
// values. Saving/deleting a preset never changes playback or configuration.
class InterfacePresetsModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(MainCtx* ctx READ ctx WRITE setCtx NOTIFY ctxChanged FINAL)
    Q_PROPERTY(Section section READ section WRITE setSection NOTIFY sectionChanged FINAL)
    Q_PROPERTY(QUrl mediaUrl READ mediaUrl WRITE setMediaUrl NOTIFY mediaUrlChanged FINAL)
    Q_PROPERTY(QString scopeTitle READ scopeTitle NOTIFY scopeChanged FINAL)
    Q_PROPERTY(QString scopeKey READ scopeKey NOTIFY scopeChanged FINAL)
    Q_PROPERTY(bool scopeAvailable READ scopeAvailable NOTIFY scopeChanged FINAL)
    Q_PROPERTY(int count READ count NOTIFY countChanged FINAL)
public:
    enum Section { Subtitles, Audio, Video };
    Q_ENUM(Section)
    enum Role { NameRole = Qt::UserRole + 1, ScopeRole };
    explicit InterfacePresetsModel(QObject* parent = nullptr);
    MainCtx* ctx() const;
    void setCtx(MainCtx* ctx);
    Section section() const { return m_section; }
    void setSection(Section section);
    QUrl mediaUrl() const { return m_mediaUrl; }
    void setMediaUrl(const QUrl& url);
    QString scopeTitle() const { return m_scopeTitle; }
    QString scopeKey() const { return m_scopeKey; }
    bool scopeAvailable() const { return !m_scopeKey.isEmpty(); }
    int count() const { return m_visible.size(); }
    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE bool save(const QString& name, const QVariantMap& snapshot, bool scoped);
    Q_INVOKABLE bool remove(int row);
    Q_INVOKABLE void reload();
signals:
    void ctxChanged();
    void sectionChanged();
    void mediaUrlChanged();
    void scopeChanged();
    void countChanged();
private:
    void refreshVisible(const QVector<QVariantMap>* records = nullptr);
    void updateScope();
    void setScope(const QString& key, const QString& title);
    bool persist(const QVector<QVariantMap>& records);
    QPointer<MainCtx> m_ctx;
    QPointer<QSettings> m_settings;
    QVector<QVariantMap> m_records;
    QVector<int> m_visible;
    QUrl m_mediaUrl;
    QString m_scopeKey;
    QString m_scopeTitle;
    quint64 m_scopeRevision = 0;
    Section m_section = Subtitles;
};
#endif
