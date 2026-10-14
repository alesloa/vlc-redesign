/*****************************************************************************
 * playlists.cpp : Playlists
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "playlists.hpp"

// VLC includes
#include <vlc_media_library.h>
#include <maininterface/mainctx.hpp>
#include <medialibrary/mlplaylistlistmodel.hpp>
#include <medialibrary/mlqmltypes.hpp>
#include <medialibrary/medialib.hpp>
#include <medialibrary/mlhelper.hpp>
#include <dialogs/dialogs_provider.hpp>

// Qt includes
#include <QGroupBox>
#include <QVBoxLayout>
#include <QTreeView>
#include <QLabel>
#include <QLineEdit>
#include <QDialogButtonBox>
#include <QPushButton>
#include <QPlainTextEdit>
#include <QListWidget>
#include <QToolButton>
#include <QMimeData>
#include <QDropEvent>
#include <QFileDialog>
#include <QImageReader>
#include <QMouseEvent>
#include <QKeyEvent>
#include <QPainter>
#include <QTableWidget>
#include <QHeaderView>
#include <QComboBox>
#include <QStyledItemDelegate>
#include <QStyle>
#include <QFileInfo>
#include <QPointer>
#include <vlc_url.h>

namespace {
class SubtitleMappingDelegate final : public QStyledItemDelegate
{
public:
    using QStyledItemDelegate::QStyledItemDelegate;
    void paint( QPainter *painter, const QStyleOptionViewItem &option,
                const QModelIndex &index ) const override
    {
        QStyledItemDelegate::paint( painter, option, index );
        if( index.column() != 0 ) return;
        const int textEnd = option.rect.left() + 40
            + option.fontMetrics.horizontalAdvance(index.data().toString()) + 14;
        if( textEnd >= option.rect.right() - 20 ) return;
        painter->save();
        QPen pen( option.palette.color(QPalette::Mid) );
        pen.setDashPattern( {6, 6} );
        painter->setPen( pen );
        painter->drawLine( textEnd, option.rect.center().y(), option.rect.right() - 14,
                           option.rect.center().y() );
        painter->restore();
    }
};

QString subtitleRequestKey( const MLItemId &id, const QUrl &url )
{
    // Internal callback correlation only; this identifier is never rendered.
    return QString::number(id.id) + QChar('/') + url.toString(QUrl::FullyEncoded);
}

class CollectionFiles final : public QListWidget
{
public:
    explicit CollectionFiles( QWidget *parent ) : QListWidget( parent )
    {
        setAcceptDrops( true );
        setSelectionMode( QAbstractItemView::ExtendedSelection );
    }
    std::function<void()> choose;
    std::function<void()> changed;
    void addUrls( const QList<QUrl> &urls )
    {
        for( const auto &url : urls )
        {
            if( !url.isLocalFile() ) continue;
            bool exists = false;
            for( int i = 0; i < count(); ++i )
                exists |= item(i)->data(Qt::UserRole).toUrl() == url;
            if( exists ) continue;
            auto row = new QListWidgetItem( url.fileName(), this );
            row->setData( Qt::UserRole, url );
            row->setToolTip( url.toDisplayString() );
        }
        viewport()->update();
        if( changed ) changed();
    }
protected:
    void dragEnterEvent( QDragEnterEvent *event ) override
    {
        if( event->mimeData()->hasUrls() ) event->acceptProposedAction();
    }
    void dragMoveEvent( QDragMoveEvent *event ) override
    {
        if( event->mimeData()->hasUrls() ) event->acceptProposedAction();
    }
    void dropEvent( QDropEvent *event ) override
    {
        addUrls( event->mimeData()->urls() );
        event->acceptProposedAction();
    }
    void mousePressEvent( QMouseEvent *event ) override
    {
        if( !itemAt(event->position().toPoint()) && choose ) choose();
        else QListWidget::mousePressEvent( event );
    }
    void keyPressEvent( QKeyEvent *event ) override
    {
        if( event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace )
        {
            qDeleteAll( selectedItems() );
            if( changed ) changed();
            viewport()->update();
        }
        else if( (event->key() == Qt::Key_Return || event->key() == Qt::Key_Space) && count() == 0 && choose ) choose();
        else QListWidget::keyPressEvent( event );
    }
    void paintEvent( QPaintEvent *event ) override
    {
        QListWidget::paintEvent( event );
        if( count() ) return;
        QPainter painter( viewport() );
        painter.setPen( palette().color(QPalette::WindowText) );
        painter.drawText( viewport()->rect().adjusted(20, 20, -20, -20), Qt::AlignCenter | Qt::TextWordWrap,
                          qtr("Drag files into the box or click here to select files.") );
    }
};
}

BulkSubtitleDialog::BulkSubtitleDialog( qt_intf_t *intf, const QVariantList &media,
                                       const QString &title, QWindow *parent )
    : QVLCDialog( parent, intf ), m_ml( intf->p_mi->getMediaLibrary() )
{
    // Header/actions are from Figma 1911:7545; row strings are ML metadata or
    // file names returned by the existing subtitle file chooser.
    setWindowTitle( qtr("Add Subtitles") );
    setObjectName( QStringLiteral("bulkSubtitleDialog") );
    setWindowRole( "vlc-bulk-subtitles" );
    resize( 1048, 800 );
    auto layout = new QVBoxLayout( this );
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);
    auto header = new QWidget( this );
    header->setObjectName( QStringLiteral("preferencesHeader") );
    header->setFixedHeight( 96 );
    auto headerLayout = new QVBoxLayout( header );
    headerLayout->setContentsMargins(9, 9, 9, 9);
    headerLayout->setSpacing(12);
    auto heading = new QHBoxLayout;
    heading->setContentsMargins(10, 0, 0, 0);
    heading->addWidget( new QLabel(qtr("Add Subtitles"), header), 1 );
    m_close = new QToolButton( header );
    m_close->setObjectName( QStringLiteral("bulkSubtitleClose") );
    m_close->setIcon( QIcon(QStringLiteral(":/redesign/icons/settings-close.svg")) );
    m_close->setIconSize( QSize(24,24) );
    m_close->setFixedSize(32,32);
    m_close->setAccessibleName( qtr("Close") );
    connect(m_close, &QToolButton::clicked, this, &BulkSubtitleDialog::reject);
    heading->addWidget(m_close);
    headerLayout->addLayout(heading);
    auto selectors = new QHBoxLayout;
    selectors->setSpacing(10);
    QString target = qtr("Add Subtitles");
    if( media.size() == 1 )
    {
        const auto id = media.first().value<MLItemId>();
        target = id.type == VLC_ML_PARENT_PLAYLIST ? qtr("To This Playlist")
               : id.hasParent() ? qtr("To This Folder") : qtr("To This File");
    }
    auto targetLabel = new QLabel( target, header );
    targetLabel->setObjectName( QStringLiteral("bulkSubtitleTarget") );
    targetLabel->setFixedSize(200,34);
    targetLabel->setContentsMargins(12,0,8,0);
    selectors->addWidget(targetLabel);
    m_source = new QPushButton( qtr("From Computer"), header );
    m_source->setObjectName( QStringLiteral("bulkSubtitleSource") );
    m_source->setFixedSize(200,34);
    connect(m_source, &QPushButton::clicked, this, [this]() { chooseSubtitles(); });
    selectors->addWidget(m_source);
    m_context = new QLineEdit( title, header );
    m_context->setObjectName( QStringLiteral("bulkSubtitleContext") );
    m_context->setReadOnly(true);
    m_context->setMinimumHeight(34);
    selectors->addWidget(m_context,1);
    headerLayout->addLayout(selectors);
    layout->addWidget(header);

    m_table = new QTableWidget(0, 2, this);
    m_table->setObjectName( QStringLiteral("bulkSubtitleMappings") );
    m_table->setShowGrid(false);
    m_table->setStyleSheet(QStringLiteral("QTableView::item { padding: 0; }"));
    m_table->setFrameShape(QFrame::NoFrame);
    m_table->setSelectionMode(QAbstractItemView::NoSelection);
    m_table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_table->horizontalHeader()->hide();
    m_table->verticalHeader()->hide();
    m_table->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    m_table->verticalHeader()->setDefaultSectionSize(40);
    m_table->setItemDelegate(new SubtitleMappingDelegate(m_table));
    auto body = new QWidget(this);
    auto bodyLayout = new QVBoxLayout(body);
    bodyLayout->setContentsMargins(30,30,30,20); // Figma1911:7562/7615 body insets.
    bodyLayout->setSpacing(0);
    bodyLayout->addWidget(m_table);
    layout->addWidget(body,1);

    auto footer = new QWidget(this);
    footer->setFixedHeight(72);
    auto footerLayout = new QHBoxLayout(footer);
    footerLayout->setContentsMargins(20,20,20,20);
    m_cancel = new QPushButton(qtr("Cancel"),footer);
    m_cancel->setFixedSize(100,32);
    connect(m_cancel,&QPushButton::clicked,this,&BulkSubtitleDialog::reject);
    footerLayout->addWidget(m_cancel);
    footerLayout->addStretch();
    m_save = new QPushButton(qtr("Save"),footer);
    m_save->setObjectName(QStringLiteral("bulkSubtitleSave"));
    m_save->setFixedSize(100,32);
    m_save->setDefault(true);
    connect(m_save,&QPushButton::clicked,this,&BulkSubtitleDialog::save);
    footerLayout->addWidget(m_save);
    layout->addWidget(footer);

    connect(m_ml, &MediaLib::externalSubtitleAdded, this, &BulkSubtitleDialog::subtitleAdded);
    struct Context { QVector<Row> rows; QString title; };
    QList<MLItemId> ids;
    for( const auto &value : media )
        if( const auto id = value.value<MLItemId>(); id.isValid() ) ids.append(id);
    m_ml->runOnMLThread<Context>(this,
        [ids](vlc_medialibrary_t *ml, Context &ctx) {
            QSet<int64_t> added;
            const auto append = [&ctx,&added](const vlc_ml_media_t &item) {
                if( item.i_type != VLC_ML_MEDIA_TYPE_VIDEO || added.contains(item.i_id) ) return;
                added.insert(item.i_id);
                Row row;
                row.id = MLItemId(item.i_id,VLC_ML_PARENT_UNKNOWN);
                row.title = QString::fromUtf8(item.psz_filename ? item.psz_filename : item.psz_title);
                if( item.p_files ) for(size_t f=0; f<item.p_files->i_nb_items; ++f) {
                    const auto &file = item.p_files->p_items[f];
                    if( !file.psz_mrl ) continue;
                    const QUrl url = QUrl::fromEncoded(file.psz_mrl);
                    if( file.i_type == VLC_ML_FILE_TYPE_MAIN ) row.mrl = url;
                    else if( file.i_type == VLC_ML_FILE_TYPE_SUBTITLE ) row.storedSubtitles.append(url);
                }
                if( row.title.isEmpty() ) row.title = row.mrl.fileName();
                ctx.rows.append(std::move(row));
            };
            for( const auto &id : ids ) {
                if( !id.hasParent() ) {
                    ml_unique_ptr<vlc_ml_media_t> item(vlc_ml_get_media(ml,id.id));
                    if(item) append(*item);
                } else {
                    vlc_ml_query_params_t query = vlc_ml_query_params_create();
                    ml_unique_ptr<vlc_ml_media_list_t> list(vlc_ml_list_media_of(ml,&query,id.type,id.id));
                    if(list) for(const auto &item : ml_range_iterate<vlc_ml_media_t>(list)) append(item);
                    if( ids.size() == 1 && id.type == VLC_ML_PARENT_FOLDER ) {
                        ml_unique_ptr<vlc_ml_folder_t> item(vlc_ml_get_folder(ml,id.id));
                        if(item) ctx.title = QString::fromUtf8(item->psz_name);
                    } else if( ids.size() == 1 && id.type == VLC_ML_PARENT_PLAYLIST ) {
                        ml_unique_ptr<vlc_ml_playlist_t> item(vlc_ml_get_playlist(ml,id.id));
                        if(item) ctx.title = QString::fromUtf8(item->psz_name);
                    } else if( ids.size() == 1 && id.type == VLC_ML_PARENT_GROUP ) {
                        ml_unique_ptr<vlc_ml_group_t> item(vlc_ml_get_group(ml,id.id));
                        if(item) ctx.title = QString::fromUtf8(item->psz_name);
                    }
                }
            }
        },
        [this](quint64, Context &ctx) {
            m_rows = std::move(ctx.rows);
            if(m_context->text().isEmpty()) m_context->setText(ctx.title);
            m_table->setRowCount(m_rows.size());
            for(int r=0;r<m_rows.size();++r) {
                auto &row = m_rows[r];
                auto caption = new QTableWidgetItem(QIcon(QStringLiteral(":/redesign/icons/videos.svg")),row.title);
                QStringList sourceUrls{row.mrl.toDisplayString()};
                for(const auto &url : row.storedSubtitles) sourceUrls.append(url.toDisplayString());
                caption->setToolTip(sourceUrls.join(QChar('\n')));
                m_table->setItem(r,0,caption);
                auto cell = new QWidget(m_table);
                auto controls = new QHBoxLayout(cell);
                controls->setContentsMargins(0,2,0,2);
                controls->setSpacing(8);
                row.choice = new QComboBox(cell);
                row.choice->setObjectName(QStringLiteral("bulkSubtitleChoice"));
                row.choice->setProperty("mediaId",QVariant::fromValue(row.id));
                row.choice->setPlaceholderText(qtr("Open subtitles..."));
                row.choice->setMinimumHeight(36);
                connect(row.choice,&QComboBox::currentIndexChanged,this,&BulkSubtitleDialog::updateSave);
                controls->addWidget(row.choice,1);
                auto browse = new QToolButton(cell);
                browse->setIcon(QIcon(QStringLiteral(":/redesign/icons/folder.svg")));
                browse->setToolTip(qtr("Open subtitles..."));
                browse->setFixedSize(32,32);
                connect(browse,&QToolButton::clicked,this,[this,r](){chooseSubtitles(r);});
                controls->addWidget(browse);
                auto clear = new QToolButton(cell);
                clear->setIcon(QIcon(QStringLiteral(":/redesign/icons/settings-close.svg")));
                clear->setToolTip(qtr("Clear"));
                clear->setFixedSize(32,32);
                connect(clear,&QToolButton::clicked,this,[this,r](){m_rows[r].choice->setCurrentIndex(-1);});
                controls->addWidget(clear);
                m_table->setCellWidget(r,1,cell);
            }
            addSubtitles(m_subtitles);
            updateSave();
        });
    updateSave();
}

void BulkSubtitleDialog::chooseSubtitles( int row )
{
    const auto paths = DialogsProvider::getInstance()->showSimpleOpen(qtr("Open subtitles..."),EXT_FILTER_SUBTITLE);
    QList<QUrl> urls;
    for(const auto &path : paths) urls.append(QUrl::fromEncoded(path.toUtf8()));
    addSubtitles(urls,row);
}

void BulkSubtitleDialog::addSubtitles( const QList<QUrl> &urls, int selectedRow )
{
    for(const auto &url : urls) {
        const QFileInfo file(url.toLocalFile());
        enum slave_type type;
        const auto encoded = url.toEncoded();
        if(url.isLocalFile() && file.isFile() && file.isReadable()
           && input_item_slave_GetType(encoded.constData(),&type) && type == SLAVE_TYPE_SPU
           && !m_subtitles.contains(url)) m_subtitles.append(url);
    }
    for(int r=0;r<m_rows.size();++r) {
        auto &row = m_rows[r];
        const auto previous = row.choice->currentData().toUrl();
        const QSignalBlocker blocker(row.choice);
        row.choice->clear();
        for(const auto &url : m_subtitles) {
            row.choice->addItem(QIcon(QStringLiteral(":/redesign/icons/subtitles.svg")),url.fileName(),url);
            row.choice->setItemData(row.choice->count()-1,url.toDisplayString(),Qt::ToolTipRole);
        }
        int selected = row.choice->findData(previous);
        if(r == selectedRow && !urls.isEmpty()) selected = row.choice->findData(urls.first());
        else if(selected < 0) for(int i=0;i<m_subtitles.size();++i)
            if(QFileInfo(row.mrl.fileName()).completeBaseName().compare(
                QFileInfo(m_subtitles[i].fileName()).completeBaseName(),Qt::CaseInsensitive) == 0) {selected=i;break;}
        row.choice->setCurrentIndex(selected);
    }
    updateSave();
}

void BulkSubtitleDialog::updateSave()
{
    bool chosen = false;
    for(const auto &row : m_rows) chosen |= row.choice && row.choice->currentIndex() >= 0;
    const bool idle = m_pending.isEmpty();
    m_save->setEnabled(idle && chosen);
    m_source->setEnabled(idle && !m_rows.isEmpty());
    m_table->setEnabled(idle);
    m_cancel->setEnabled(idle);
    m_close->setEnabled(idle);
}

void BulkSubtitleDialog::save()
{
    if(!m_pending.isEmpty()) return;
    QVector<QPair<MLItemId,QUrl>> requests;
    for(const auto &row : m_rows) if(row.choice->currentIndex() >= 0) {
        const auto url = row.choice->currentData().toUrl();
        m_pending.insert(subtitleRequestKey(row.id,url));
        requests.append({row.id,url});
    }
    if(requests.isEmpty()) return;
    m_failed = false;
    updateSave();
    // Register the entire batch before invoking the adapter: validation may
    // return a synchronous failure; ML writes themselves remain asynchronous.
    for(const auto &request : requests) m_ml->addExternalSubtitle(request.first,request.second);
}

void BulkSubtitleDialog::subtitleAdded( const MLItemId &id, const QUrl &url, bool success )
{
    if(!m_pending.remove(subtitleRequestKey(id,url))) return;
    m_failed |= !success;
    for(auto &row : m_rows) if(row.id == id) {
        row.choice->setToolTip(success ? url.toDisplayString() : qtr("Error") + QChar('\n') + url.toDisplayString());
        if(success) {
            row.storedSubtitles.append(url);
            row.choice->setCurrentIndex(-1);
            m_table->item(&row-m_rows.data(),0)->setIcon(QIcon(QStringLiteral(":/redesign/icons/checkbox-check.svg")));
        }
        else {
            m_table->item(&row-m_rows.data(),0)->setIcon(style()->standardIcon(QStyle::SP_MessageBoxCritical));
        }
    }
    if(m_pending.isEmpty()) {
        updateSave();
        if(!m_failed) accept();
    }
}

void BulkSubtitleDialog::reject()
{
    if(m_pending.isEmpty()) QDialog::reject();
}

MediaCollectionDialog::MediaCollectionDialog( qt_intf_t *intf, bool network, QWindow *parent )
    : QVLCDialog( parent, intf ), m_network( network )
{
    const QString title = network ? qtr("Open Network Stream") : qtr("New Playlist");
    setWindowTitle( title );
    setWindowRole( network ? "vlc-network-stream" : "vlc-new-playlist" );
    setObjectName( network ? QStringLiteral("networkStreamDialog") : QStringLiteral("newPlaylistDialog") );
    resize( network ? QSize(1048, 631) : QSize(713, 589) );
    auto layout = new QVBoxLayout( this );
    layout->setContentsMargins( 0, 0, 0, 0 );
    layout->setSpacing( 0 );
    auto header = new QWidget( this );
    header->setObjectName( QStringLiteral("preferencesHeader") );
    header->setFixedHeight( 50 );
    auto headerLayout = new QHBoxLayout( header );
    headerLayout->setContentsMargins( 20, 9, 9, 9 );
    headerLayout->addWidget( new QLabel(title, header), 1 );
    auto close = new QToolButton( header );
    close->setIcon( QIcon(QStringLiteral(":/redesign/icons/settings-close.svg")) );
    close->setIconSize( QSize(24, 24) );
    close->setFixedSize( 32, 32 );
    close->setAccessibleName( qtr("Close") );
    connect( close, &QToolButton::clicked, this, &QDialog::reject );
    headerLayout->addWidget( close );
    layout->addWidget( header );

    auto body = new QWidget( this );
    auto bodyLayout = new QVBoxLayout( body );
    bodyLayout->setContentsMargins( 20, 22, 20, 22 );
    bodyLayout->setSpacing( 20 );
    const auto description = [body](const QString &heading, const QString &copy) {
        auto section = new QWidget( body );
        auto rows = new QVBoxLayout( section );
        rows->setContentsMargins( 0, 0, 0, 0 );
        rows->setSpacing( 5 );
        auto label = new QLabel( heading, section );
        label->setProperty( "redesignSectionHeading", true );
        QFont font = label->font(); font.setPixelSize(16); label->setFont(font);
        label->setWordWrap( true );
        auto help = new QLabel( copy, section );
        help->setWordWrap( true );
        rows->addWidget( label );
        rows->addWidget( help );
        return section;
    };
    m_name = new QLineEdit( body );
    m_name->setObjectName( QStringLiteral("collectionPlaylistName") );
    m_name->setMinimumHeight( 37 );
    connect( m_name, &QLineEdit::textChanged, this, &MediaCollectionDialog::updateAcceptButton );
    if( network )
    {
        bodyLayout->addWidget( description(qtr("Network URL"), qtr("You can enter multiple links to load.")) );
        m_urls = new QPlainTextEdit( body );
        m_urls->setObjectName( QStringLiteral("collectionNetworkUrls") );
        m_urls->setPlaceholderText( qtr("e.g., https://www.example.com/stream.avi") );
        m_urls->setMinimumHeight( 194 );
        connect( m_urls, &QPlainTextEdit::textChanged, this, &MediaCollectionDialog::updateAcceptButton );
        bodyLayout->addWidget( m_urls );
        if( p_intf->p_mi->hasMediaLibrary() )
        {
            bodyLayout->addWidget( description(qtr("Playlist Name (optional)"), qtr("The playlist will be saved and displayed with this title.")) );
            m_name->setPlaceholderText( qtr("e.g., Favorite TV Channels") );
            bodyLayout->addWidget( m_name );
        }
        else m_name->hide();
    }
    else
    {
        auto details = new QHBoxLayout;
        details->setSpacing( 20 );
        auto fields = new QVBoxLayout;
        fields->setSpacing( 20 );
        fields->addWidget( description(qtr("Playlist Details"), qtr("The playlist will be saved and displayed with this title and thumbnail.")) );
        m_name->setPlaceholderText( qtr("e.g., Favorite Videos") );
        fields->addWidget( m_name );
        details->addLayout( fields, 1 );
        m_coverButton = new QPushButton( body );
        m_coverButton->setObjectName( QStringLiteral("collectionCustomCover") );
        m_coverButton->setIcon( QIcon(QStringLiteral(":/menu/add.svg")) );
        m_coverButton->setIconSize( QSize(24, 24) );
        m_coverButton->setFixedSize( 112, 112 );
        m_coverButton->setAccessibleName( qtr("Thumbnail") ); // Figma Customize Player uses this component name.
        connect( m_coverButton, &QPushButton::clicked, this, &MediaCollectionDialog::chooseCover );
        details->addWidget( m_coverButton );
        bodyLayout->addLayout( details );
        bodyLayout->addWidget( description(qtr("Select Files"), qtr("These files will be added to the playlist.")) );
        auto files = new CollectionFiles( body );
        m_files = files;
        files->setObjectName( QStringLiteral("collectionFiles") );
        files->setMinimumHeight( 186 );
        files->choose = [this]() { chooseFiles(); };
        files->changed = [this]() { updateAcceptButton(); };
        bodyLayout->addWidget( files, 1 );
    }
    bodyLayout->addStretch();
    layout->addWidget( body, 1 );

    auto footer = new QWidget( this );
    footer->setFixedHeight( 72 );
    auto footerLayout = new QHBoxLayout( footer );
    footerLayout->setContentsMargins( 20, 20, 20, 20 );
    auto cancel = new QPushButton( qtr("Cancel"), footer );
    cancel->setFixedSize( 100, 32 );
    connect( cancel, &QPushButton::clicked, this, &QDialog::reject );
    footerLayout->addWidget( cancel );
    footerLayout->addStretch();
    m_accept = new QPushButton( qtr("Save"), footer );
    m_accept->setFixedSize( 100, 32 );
    m_accept->setDefault( true );
    connect( m_accept, &QPushButton::clicked, this, &QDialog::accept );
    footerLayout->addWidget( m_accept );
    layout->addWidget( footer );
    updateAcceptButton();
}

QString MediaCollectionDialog::playlistName() const { return m_name->text().trimmed(); }

QVariantList MediaCollectionDialog::mediaUrls() const
{
    QVariantList result;
    if( m_urls )
        for( const auto &entry : m_urls->toPlainText().split(QChar('\n'), Qt::SkipEmptyParts) )
        {
            const auto value = entry.trimmed();
            if( value.isEmpty() ) continue;
            char *uri = value.contains(QStringLiteral("://")) ? vlc_uri_fixup(qtu(value)) : vlc_path2uri(qtu(value), nullptr);
            if( uri )
            {
                result.append( QUrl(qfu(uri)) );
                free( uri );
            }
        }
    else if( m_files )
        for( int i = 0; i < m_files->count(); ++i ) result.append(m_files->item(i)->data(Qt::UserRole));
    return result;
}

void MediaCollectionDialog::updateAcceptButton()
{
    if( !m_accept ) return;
    m_accept->setText( m_network && playlistName().isEmpty() ? qtr("Play") : qtr("Save") );
    m_accept->setEnabled( m_network ? !mediaUrls().isEmpty() : !playlistName().isEmpty() );
}

void MediaCollectionDialog::chooseFiles()
{
    const auto files = QFileDialog::getOpenFileUrls( this, qtr("Select Files"), p_intf->p_mi->getDialogFilePath() );
    if( files.isEmpty() ) return;
    p_intf->p_mi->setDialogFilePath( files.first().adjusted(QUrl::RemoveFilename) );
    static_cast<CollectionFiles *>(m_files)->addUrls( files );
}

void MediaCollectionDialog::chooseCover()
{
    const auto image = QFileDialog::getOpenFileUrl( this, qtr("Thumbnail"), p_intf->p_mi->getDialogFilePath() );
    if( !image.isLocalFile() || !QImageReader(image.toLocalFile()).canRead() ) return;
    m_cover = image;
    m_coverButton->setIcon( QIcon(image.toLocalFile()) );
    m_coverButton->setIconSize( QSize(100, 100) );
    m_coverButton->setToolTip( image.toDisplayString() );
}

//-------------------------------------------------------------------------------------------------
// Ctor / dtor
//-------------------------------------------------------------------------------------------------

PlaylistsDialog::PlaylistsDialog(qt_intf_t * _p_intf, const QVariantList &media, MLPlaylistListModel::PlaylistType type, QWindow *parent)
    : QVLCDialog(parent, _p_intf)
{
    MainCtx * mainCtx = p_intf->p_mi;

    assert(mainCtx->hasMediaLibrary());

    setWindowRole("vlc-playlists");

    setWindowTitle(qtr("Add to Playlist"));

    setWindowOpacity(var_InheritFloat(p_intf, "qt-opacity"));

    //---------------------------------------------------------------------------------------------
    // Existing Playlists

    QGroupBox * groupBox = new QGroupBox(qtr("Existing Playlist"));

    m_playlists = new QTreeView(this);

    connect(m_playlists, &QTreeView::clicked,       this, &PlaylistsDialog::onClicked);
    connect(m_playlists, &QTreeView::doubleClicked, this, &PlaylistsDialog::onDoubleClicked);

    m_model = new MLPlaylistListModel(m_playlists);
    m_model->setPlaylistType(type);

    m_model->setMl(mainCtx->getMediaLibrary());

    m_playlists->setModel(m_model);

    QVBoxLayout * layoutPlaylists = new QVBoxLayout(groupBox);

    layoutPlaylists->addWidget(m_playlists);

    //---------------------------------------------------------------------------------------------
    // New Playlist

    QLabel * labelNew = new QLabel(this);

    labelNew->setText(qtr("New Playlist"));

    // FIXME: Add and configure a QValidator.
    m_lineEdit = new QLineEdit(this);

    connect(m_lineEdit, &QLineEdit::textEdited, this, &PlaylistsDialog::onTextEdited);

    QHBoxLayout * layoutNew = new QHBoxLayout;

    layoutNew->addWidget(labelNew);
    layoutNew->addWidget(m_lineEdit);

    //---------------------------------------------------------------------------------------------
    // Buttons

    QDialogButtonBox * buttonBox = new QDialogButtonBox(QDialogButtonBox::Ok |
                                                        QDialogButtonBox::Cancel,
                                                        Qt::Horizontal, this);

    m_button = buttonBox->button(QDialogButtonBox::Ok);

    m_button->setEnabled(false);

    connect(buttonBox, &QDialogButtonBox::accepted, this, &PlaylistsDialog::accept);
    connect(buttonBox, &QDialogButtonBox::rejected, this, &PlaylistsDialog::reject);

    m_label = new QLabel(this);

    QHBoxLayout * layoutButtons = new QHBoxLayout;

    layoutButtons->addWidget(m_label);
    layoutButtons->addWidget(buttonBox);

    //---------------------------------------------------------------------------------------------

    QVBoxLayout * layout = new QVBoxLayout(this);

    layout->addWidget(groupBox);
    layout->addLayout(layoutNew);
    layout->addLayout(layoutButtons);

    // FIXME: Is this the right default size ?
    QVLCTools::restoreWidgetPosition(p_intf, "Playlists", this, QSize(320, 320));

    updateGeometry();

    {
        assert(!media.isEmpty());
        m_ids = media;
        m_label->setText(qtr("%1 Media").arg(m_ids.count()));
    }
}

PlaylistsDialog::~PlaylistsDialog()
{
    QVLCTools::saveWidgetPosition(p_intf, "Playlists", this);
}

//-------------------------------------------------------------------------------------------------
// Private slots
//-------------------------------------------------------------------------------------------------

void PlaylistsDialog::onClicked()
{
    // NOTE: We clear the lineEdit when the list is selected.
    m_lineEdit->clear();

    m_button->setEnabled(true);
}

void PlaylistsDialog::onDoubleClicked()
{
    if (m_button->isEnabled() == false)
        return;

    accept();
}

//-------------------------------------------------------------------------------------------------

void PlaylistsDialog::onTextEdited()
{
    // NOTE: We clear the list selection when we edit the 'new playlist' field.
    m_playlists->clearSelection();

    if (m_lineEdit->text().isEmpty())
        m_button->setEnabled(false);
    else
        m_button->setEnabled(true);
}

void PlaylistsDialog::accept()
{

    QString text = m_lineEdit->text();

    if (text.isEmpty())
    {
        const MLItemId playlistId = m_model->getItemId(m_playlists->currentIndex().row());
        m_model->append(playlistId, m_ids);
    }
    else
    {
        m_model->create(text, m_ids);
    }

    // Model is asynchronous, we need to wait for the model to complete processing...
    if (Q_LIKELY(m_model->transactionPending())) // Same thread, TOCTOU is not relevant.
    {
        hide();

        connect(m_model, &MLPlaylistListModel::transactionPendingChanged, this, [this](bool done) {
            if (!done)
                QVLCDialog::accept();
            }, Qt::SingleShotConnection);
    }
    else
    {
        QVLCDialog::accept();
    }
}
