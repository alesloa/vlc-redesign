/*****************************************************************************
 * playlists.hpp : playlists
 ****************************************************************************
 * Copyright (C) 2021 the VideoLAN team
 *
 * Authors: Benjamin Arnaud <bunjee@omega.gg>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifndef QVLC_PLAYLISTS_H_
#define QVLC_PLAYLISTS_H_ 1

// VLC includes
#include "medialibrary/mlplaylistlistmodel.hpp"
#include <widgets/native/qvlcframe.hpp>
#include <QSet>

// Forward declarations
class QTreeView;
class QLineEdit;
class QLabel;
class QPushButton;
class QPlainTextEdit;
class QListWidget;
class QTableWidget;
class QComboBox;
class QToolButton;
class MediaLib;

// Figma 1911:7545: manual mappings use actual media-library video IDs and
// user-selected local subtitle URLs. No association is written before Save.
class BulkSubtitleDialog : public QVLCDialog
{
    Q_OBJECT
public:
    explicit BulkSubtitleDialog( qt_intf_t *, const QVariantList &media,
                                 const QString &title, QWindow *parent = nullptr );
    void reject() override;
private:
    struct Row
    {
        MLItemId id;
        QString title;
        QUrl mrl;
        QList<QUrl> storedSubtitles;
        QComboBox *choice = nullptr;
    };
    void chooseSubtitles( int row = -1 );
    void addSubtitles( const QList<QUrl> &, int row = -1 );
    void updateSave();
    void save();
    void subtitleAdded( const MLItemId &, const QUrl &, bool );
    MediaLib *m_ml;
    QTableWidget *m_table;
    QLineEdit *m_context;
    QPushButton *m_source;
    QPushButton *m_save;
    QPushButton *m_cancel;
    QToolButton *m_close;
    QVector<Row> m_rows;
    QList<QUrl> m_subtitles;
    QSet<QString> m_pending;
    bool m_failed = false;
};

// Figma 6259:14954 and 6216:13614 define these two distinct media intents.
// All titles, descriptions and placeholders below are from those frames.
class MediaCollectionDialog : public QVLCDialog
{
    Q_OBJECT
public:
    explicit MediaCollectionDialog( qt_intf_t *, bool network, QWindow *parent = nullptr );
    QString playlistName() const;
    QVariantList mediaUrls() const;
    QUrl customCover() const { return m_cover; }
private:
    void chooseFiles();
    void chooseCover();
    void updateAcceptButton();
    bool m_network;
    QLineEdit *m_name;
    QPlainTextEdit *m_urls = nullptr;
    QListWidget *m_files = nullptr;
    QPushButton *m_coverButton = nullptr;
    QPushButton *m_accept = nullptr;
    QUrl m_cover;
};

class PlaylistsDialog : public QVLCDialog
{
    Q_OBJECT

public: // Ctor / dtor
    explicit PlaylistsDialog(qt_intf_t *_p_intf,
                             const QVariantList & media,
                             MLPlaylistListModel::PlaylistType type = MLPlaylistListModel::PLAYLIST_TYPE_ALL,
                             QWindow *parent = nullptr);

    ~PlaylistsDialog();

public slots:
    void accept() override;

private slots:
    void onClicked      ();
    void onDoubleClicked();

    void onTextEdited();

private:
    QVariantList m_ids;

    MLPlaylistListModel * m_model;

    QTreeView * m_playlists;
    QLineEdit * m_lineEdit;

    QLabel * m_label;

    QPushButton * m_button;
};

#endif
