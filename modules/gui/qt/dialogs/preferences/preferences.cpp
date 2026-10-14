/*****************************************************************************
 * preferences.cpp : Preferences
 *****************************************************************************
 * Copyright (C) 2006-2007 the VideoLAN team
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Jean-Baptiste Kempf <jb@videolan.org>
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

#include "dialogs/preferences/preferences.hpp"

#include "expert_view.hpp"
#include "dialogs/preferences/complete_preferences.hpp"
#include "dialogs/preferences/simple_preferences.hpp"
#include "dialogs/dialogs/dialogmodel.hpp"
#include "dialogs/dialogs_provider.hpp"
#include "dialogs/plugins/plugins.hpp"
#include "widgets/native/searchlineedit.hpp"
#include "widgets/native/qvlcframe.hpp"
#include "maininterface/mainctx.hpp"

#include <QHBoxLayout>
#include <QGroupBox>
#include <QRadioButton>
#include <QPushButton>
#include <QMessageBox>
#include <QDialogButtonBox>
#include <QStackedWidget>
#include <QSplitter>
#include <QShortcut>
#include <QEvent>
#include <QToolButton>
#include <QStyle>
#include <QTextDocument>
#include <QScrollArea>
#include <QTreeWidgetItemIterator>
#include <QListWidget>
#include <QTableWidget>
#include <QHeaderView>
#include <QInputDialog>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDataStream>
#include <QSet>
#include <QSignalBlocker>
#include <QUuid>
#include <QStyleFactory>
#include <QIconEngine>
#include <QPainter>
#include "util/colorizedsvgicon.hpp"
#include <QLocale>
#include <cmath>
#include <limits>
#include "dialogs/toolbar/controlbar_profile_model.hpp"
#include "maininterface/mainctx_submodels.hpp"
#include "util/color_scheme_model.hpp"
#include <vlc_plugin.h>

#include <vlc_configuration.h>
#include <vlc_modules.h>
#include <vlc_config_cat.h>

PrefsDialog::PrefsDialog( QWindow *parent, qt_intf_t *_p_intf, bool hotkeysOnly )
            : QVLCDialog( parent, _p_intf ), m_hotkeysOnly( hotkeysOnly )
{
    setWindowTitle( qtr( "Preferences" ) );
    setWindowRole( "vlc-preferences" );
    setWindowModality( Qt::WindowModal );

    /* Whether we want it or not, we need to destroy on close to get
       consistency when reset */
    setAttribute( Qt::WA_DeleteOnClose );

    p_list = NULL;

    QGridLayout *main_layout = new QGridLayout( this );
    setLayout( main_layout );

    /* View (panel) selection */
    types = new QGroupBox( qtr("Show settings") );
    types->setAlignment( Qt::AlignHCenter );
    QHBoxLayout *types_l = new QHBoxLayout;
    types_l->setSpacing( 3 );
    types_l->setContentsMargins(3, 3, 3, 3);
    simple = new QRadioButton( qtr( "Simple" ), types );
    simple->setToolTip( qtr( "Switch to simple preferences view" ) );
    all = new QRadioButton( qtr("All"), types );
    all->setToolTip( qtr( "Switch to full preferences view" ) );
    expert = new QRadioButton( qtr("Expert"), types );
    expert->setToolTip( qtr( "Switch to expert preferences view" ) );
    types_l->addWidget( simple );
    types_l->addWidget( all );
    types_l->addWidget( expert );
    types->setLayout( types_l );
    types->setAccessibleName( types->title() );
    types->setTitle( QString() );
    types->setStyleSheet( QStringLiteral("QGroupBox { margin: 0; padding: 0; border: 0; }") );
    simple->setChecked( true );

    QWidget *header = new QWidget( this );
    header->setObjectName( QStringLiteral("preferencesHeader") );
    auto header_layout = new QHBoxLayout( header );
    header_layout->setContentsMargins( 8, 7, 14, 7 );
    header->setFixedHeight( 50 );
    settings_search = new QLineEdit( header );
    settings_search->setPlaceholderText( qtr("Search") );
    settings_search->setClearButtonEnabled( true );
    settings_search->setObjectName( QStringLiteral("preferencesSearch") );
    // Search/Help labels reuse strings already published in preferences/help.
    settings_search->setAccessibleName( qtr("Search") );
    settings_search->setMinimumHeight( 36 );
    settings_search->setFixedWidth( 200 );
    settings_search->addAction( QIcon(QStringLiteral(":/redesign/icons/settings-search.svg")), QLineEdit::LeadingPosition );
    header_layout->addWidget( settings_search );
    m_headerTitle = new QLabel( header );
    m_headerTitle->setContentsMargins( 24, 0, 0, 0 );
    QFont header_font = QApplication::font();
    header_font.setPixelSize( 16 );
    m_headerTitle->setFont( header_font );
    header_layout->addWidget( m_headerTitle, 1 );
    header_layout->addWidget( types );
    auto close_button = new QToolButton( header );
    close_button->setIcon( QIcon(QStringLiteral(":/redesign/icons/settings-close.svg")) );
    close_button->setIconSize( QSize(24, 24) );
    close_button->setAccessibleName( qtr("Close") );
    close_button->setObjectName( QStringLiteral("preferencesClose") );
    close_button->setAutoRaise( true );
    close_button->setFixedSize( 32, 32 );
    header_layout->addWidget( close_button );
    connect( close_button, &QToolButton::clicked, this, &PrefsDialog::cancel );

    /* Buttons */
    QDialogButtonBox *buttonsBox = new QDialogButtonBox();
    QPushButton *save = new QPushButton( qtr( "&Save" ) );
    save->setToolTip( qtr( "Save and close the dialog" ) );
    QPushButton *cancel = new QPushButton( qtr( "&Cancel" ) );
    QPushButton *reset = new QPushButton( qtr( "&Reset Preferences" ) );

    buttonsBox->addButton( save, QDialogButtonBox::AcceptRole );
    buttonsBox->addButton( cancel, QDialogButtonBox::RejectRole );
    buttonsBox->addButton( reset, QDialogButtonBox::ResetRole );

    /* View (panel) stack */
    stack = new QStackedWidget();

    /* Simple view (panel) */
    simple_split_widget = new QWidget();
    simple_split_widget->setLayout( new QHBoxLayout );

    simple_tree_panel = new QWidget;
    simple_tree_panel->setLayout( new QVBoxLayout );
    simple_tree_panel->setFixedWidth( 202 ); // 200px Figma sidebar plus the existing 1px layout margins.
    simple_tree = NULL;
    simple_panels_stack = new QStackedWidget;
    for( int i = 0; i < SPrefsMax ; i++ )
        simple_panels[i] = NULL;

    simple_split_widget->layout()->addWidget( simple_tree_panel );
    static_cast<QHBoxLayout *>(simple_split_widget->layout())->addWidget( simple_panels_stack, 1 );

    // Empty-search copy comes from playlist/qml/PlaylistPane.qml.
    no_results = new QLabel( qtr("No results"), simple_split_widget );
    no_results->setAlignment( Qt::AlignCenter );
    no_results->setSizePolicy( QSizePolicy::Expanding, QSizePolicy::Expanding );
    no_results->hide();
    simple_split_widget->layout()->addWidget( no_results );

    simple_tree_panel->layout()->setContentsMargins(1, 1, 1, 1);
    simple_panels_stack->setContentsMargins( 24, 20, 24, 20 );
    simple_split_widget->layout()->setContentsMargins(8, 8, 8, 8);

    stack->insertWidget( SIMPLE, simple_split_widget );

    /* Advanced view (panel) */
    advanced_split_widget = new QSplitter();

    advanced_tree_panel = new QWidget;
    advanced_tree_panel->setLayout( new QVBoxLayout );
    tree_filter = NULL;
    current_filter = NULL;
    advanced_tree = NULL;
    advanced_panels_stack = new QStackedWidget;

    advanced_split_widget->addWidget( advanced_tree_panel );
    advanced_split_widget->addWidget( advanced_panels_stack );

    advanced_split_widget->setSizes(QList<int>() << 230 << 620);
    advanced_split_widget->setChildrenCollapsible( false );
    advanced_tree_panel->sizePolicy().setHorizontalStretch(1);
    advanced_panels_stack->sizePolicy().setHorizontalStretch(2);

    stack->insertWidget( ADVANCED, advanced_split_widget );

    /* Expert view (panel) */
    expert_widget = new QWidget;
    expert_widget_layout = new QGridLayout;
    expert_widget->setLayout( expert_widget_layout );

    expert_table_filter = nullptr;
    expert_table = nullptr;

    expert_text = new QLabel;

    expert_text->setWordWrap(true);

    QFont textFont = QApplication::font();
    textFont.setPixelSize( 16 );
    textFont.setWeight( QFont::DemiBold );
    expert_text->setFont( textFont );

    expert_widget_layout->addWidget( expert_text, 2, 0, 1, 2 );

    stack->insertWidget( EXPERT, expert_widget );

    QWidget *help = new QWidget( this );
    help->setObjectName( QStringLiteral("preferencesHelp") );
    auto help_layout = new QHBoxLayout( help );
    help_layout->setContentsMargins( 12, 8, 12, 8 );
    QLabel *help_icon = new QLabel( help );
    help_icon->setPixmap( QPixmap(QStringLiteral(":/redesign/icons/settings-info.svg")) );
    help_icon->setAccessibleName( qtr("Help") );
    help_description = new QLabel( help );
    help_description->setWordWrap( true );
    help_description->setTextFormat( Qt::PlainText );
    help_description->setTextInteractionFlags( Qt::TextSelectableByMouse );
    auto help_scroll = new QScrollArea( help );
    help_scroll->setFrameShape( QFrame::NoFrame );
    help_scroll->setWidgetResizable( true );
    help_scroll->setMinimumHeight( 48 );
    help_scroll->setMaximumHeight( 96 );
    help_scroll->setWidget( help_description );
    help_layout->addWidget( help_icon, 0, Qt::AlignTop );
    help_layout->addWidget( help_scroll, 1 );
    m_groupAdvanced = new QPushButton( qtr("Advanced Options"), header );
    m_groupAdvanced->setToolTip( all->toolTip() );
    header_layout->insertWidget( header_layout->count() - 1, m_groupAdvanced );
    connect( m_groupAdvanced, &QPushButton::clicked, this, &PrefsDialog::showGroupAdvanced );
    m_groupAdvanced->hide(); // The source-backed reveal now sits inside each category.

    /* Layout  */
    main_layout->addWidget( header, 0, 0 );
    main_layout->addWidget( stack, 1, 0 );
    main_layout->addWidget( help, 2, 0 );
    help->hide(); // Figma uses the adjacent information actions rather than a permanent inspector.
    auto footer = new QWidget(this);
    footer->setFixedHeight(72);
    auto footerLayout = new QHBoxLayout(footer);
    footerLayout->setContentsMargins(20,20,20,20);
    buttonsBox->removeButton(save);
    buttonsBox->removeButton(cancel);
    buttonsBox->removeButton(reset);
    cancel->setFixedSize(100,32);
    save->setFixedSize(100,32);
    // Preserve the original button box's AcceptRole default after moving
    // its real Save action into the supplied footer. The shared :default
    // style supplies the primary accent without changing enabled state.
    save->setDefault(true);
    reset->setFixedHeight(32);
    footerLayout->addWidget(cancel);
    footerLayout->addWidget(reset);
    footerLayout->addStretch();
    footerLayout->addWidget(save);
    buttonsBox->setParent(footer);
    buttonsBox->hide();
    main_layout->addWidget(footer,3,0);
    main_layout->setRowStretch( 1, 1 );
    main_layout->setContentsMargins(0,0,0,0);
    main_layout->setVerticalSpacing( 0 );

    switch( hotkeysOnly ? 0 : var_InheritInteger( p_intf, "qt-initial-prefs-view" ) )
    {
        case 2:  setExpert();   break;
        case 1:  setAdvanced(); break;
        default: setSimple();   break;
    }

    BUTTONACT( save, &PrefsDialog::save );
    BUTTONACT( cancel, &PrefsDialog::cancel );
    BUTTONACT( reset, &PrefsDialog::reset );

    BUTTONACT( simple, &PrefsDialog::setSimple );
    BUTTONACT( all, &PrefsDialog::setAdvanced );
    BUTTONACT( expert, &PrefsDialog::setExpert );

    connect( settings_search, &QLineEdit::textChanged,
             this, &PrefsDialog::searchSettings );
    auto search_shortcut = new QShortcut( QKeySequence( QKeySequence::Find ), this );
    connect( search_shortcut, &QShortcut::activated,
             this, [this]() {
        if( m_hotkeysOnly )
        {
            if( auto search = findChild<QLineEdit *>(QStringLiteral("hotkeyEditorSearch")) )
                search->setFocus();
        }
        else
            settings_search->setFocus();
    } );

    if( hotkeysOnly )
    {
        // The dedicated shortcut window reuses the existing editable panel.
        simple_tree->setCurrentCategory( SPrefsGroupControls );
        simple_tree_panel->hide();
        settings_search->hide();
        types->hide();
        m_headerTitle->setContentsMargins( 0, 0, 0, 0 );
        m_headerTitle->setText( qtr("Keyboard Shortcuts") );
        simple_panels_stack->setContentsMargins( 20, 0, 20, 0 );
        simple_panels[SPrefsHotkeys]->setShortcutsOnly( true );
        // The supplied shortcut modal combines a50px title row and the
        // original search/scope controls in a96px header.
        main_layout->removeWidget(header);
        header->setObjectName(QStringLiteral("keyboardShortcutsTitle"));
        auto combinedHeader = new QWidget(this);
        combinedHeader->setObjectName(QStringLiteral("preferencesHeader"));
        combinedHeader->setFixedHeight(96);
        auto combinedLayout = new QVBoxLayout(combinedHeader);
        combinedLayout->setContentsMargins(0,0,0,0);
        combinedLayout->setSpacing(0);
        combinedLayout->addWidget(header);
        auto searchWidget = new QWidget(combinedHeader);
        auto searchLayout = new QHBoxLayout(searchWidget);
        searchLayout->setContentsMargins(20,0,20,10);
        searchLayout->setSpacing(20);
        simple_panels[SPrefsHotkeys]->moveShortcutsSearchTo(searchLayout);
        combinedLayout->addWidget(searchWidget);
        main_layout->addWidget(combinedHeader,0,0);

        m_groupAdvanced->hide();
        setWindowTitle( qtr("Keyboard Shortcuts") );
    }

    QVLCTools::restoreWidgetPosition( p_intf, hotkeysOnly ? "Hotkeys" : "Preferences", this,
                                    QSize(1048, hotkeysOnly ? 800 : 865) );
}

PrefsDialog::~PrefsDialog()
{
    qDeleteAll( m_extensionsControls );
    module_list_free( p_list );
}

void PrefsDialog::installHelp( QWidget *panel )
{
    panel->installEventFilter( this );
    for( auto widget : panel->findChildren<QWidget *>() )
        widget->installEventFilter( this );
}

void PrefsDialog::updateHelp( QWidget *widget )
{
    while( widget && widget != this )
    {
        if( !widget->toolTip().isEmpty() )
        {
            // Descriptions come from the existing module option help text.
            QTextDocument document;
            document.setHtml( widget->toolTip() );
            help_description->setText( document.toPlainText() );
            return;
        }
        widget = widget->parentWidget();
    }
}

bool PrefsDialog::eventFilter( QObject *watched, QEvent *event )
{
    if( event->type() == QEvent::Enter || event->type() == QEvent::FocusIn )
        if( auto widget = qobject_cast<QWidget *>( watched ) )
            updateHelp( widget );
    return QVLCDialog::eventFilter( watched, event );
}

void PrefsDialog::searchSettings( const QString &text )
{
    if( stack->currentIndex() == ADVANCED )
    {
        tree_filter->setText( text );
        return;
    }
    if( stack->currentIndex() == EXPERT )
    {
        expert_table_filter->setText( text );
        return;
    }
    if( !simple_tree || m_hotkeysOnly )
        return;

    int first_match = -1;
    int current_match = -1;
    for( int i = 0; i < SPrefsGroupMax; ++i )
    {
        int panel = SPrefsCatList::groupPanel( i );
        if( panel == SPrefsMediaLibrary && !vlc_ml_instance_get(p_intf) )
            panel = SPrefsInterface;
        bool matches = text.isEmpty() || SPrefsCatList::groupTitle(i).contains(text, Qt::CaseInsensitive);
        if( !matches && panel >= 0 )
            matches = ensureSimplePanel(panel)->matches( text, i );
        else if( !matches && i == SPrefsGroupExtensions )
            matches = qtr("Addons Manager").contains(text, Qt::CaseInsensitive) ||
                      qtr("Active Extensions").contains(text, Qt::CaseInsensitive) ||
                      qtr("Plugins").contains(text, Qt::CaseInsensitive);
        simple_tree->setCategoryVisible( i, matches );
        if( matches )
        {
            if( first_match == -1 )
                first_match = i;
            if( m_currentGroup == i )
                current_match = i;
        }
    }
    no_results->setVisible( first_match == -1 );
    simple_panels_stack->setVisible( first_match != -1 );
    if( first_match != -1 )
        simple_tree->setCurrentCategory( current_match == -1 ? first_match : current_match );
}

void PrefsDialog::showGroupAdvanced()
{
    int subcategory = SPrefsCatList::groupSubcategory( m_currentGroup );
    const char *module = nullptr;
    if( m_currentGroup == SPrefsGroupGeneral || m_currentGroup == SPrefsGroupInterface )
    {
        subcategory = SUBCAT_INTERFACE_MAIN;
        module = "qt";
    }
    else if( m_currentGroup == SPrefsGroupPerformance )
        module = "avcodec";
    else if( m_currentGroup == SPrefsGroupPrivacy )
    {
        // This existing privacy option lives in the play-queue configuration block.
        if( auto option = config_FindConfig("metadata-network-access") )
            settings_search->setText( qfut(option->psz_text) );
    }
    setAdvanced();
    // Keep the complete preference tree; select the source category for this group.
    PrefsTreeItem *fallback = nullptr;
    for( QTreeWidgetItemIterator item(advanced_tree); *item; ++item )
    {
        auto node = static_cast<PrefsTreeItem *>(*item);
        if( node->subcat_id == subcategory && !node->isHidden() )
        {
            if( !fallback )
                fallback = node;
            if( !module || (node->module_name && !strcmp(node->module_name, module)) )
            {
                fallback = node;
                break;
            }
        }
    }
    if( fallback )
    {
        advanced_tree->setCurrentItem( fallback );
        advanced_tree->scrollToItem( fallback );
    }
}

void PrefsDialog::setExpert()
{
    /* Lazy creation */
    if( !expert_table )
    {
        if ( !p_list )
            p_list = module_list_get( &count );

        expert_table_filter = new SearchLineEdit( expert_widget );
        expert_table_filter->setMinimumHeight( 26 );
        expert_table_filter->hide(); // Shared header owns search in every view.
        expert_table_filter_modified = new QCheckBox( qtr( "Modified only" ), expert_widget );

        ExpertPrefsTableModel *table_model = new ExpertPrefsTableModel( p_list, count, this );
        expert_table = new ExpertPrefsTable( expert_widget );
        expert_table->setModel( table_model );
        expert_table->resizeColumnToContents( ExpertPrefsTableModel::NameField );

        expert_widget_layout->addWidget( expert_table_filter, 0, 0 );
        expert_widget_layout->addWidget( expert_table_filter_modified, 0, 1 );
        expert_widget_layout->addWidget( expert_table, 1, 0, 1, 2 );

        connect( expert_table->selectionModel(), &QItemSelectionModel::currentChanged,
                 this, &PrefsDialog::changeExpertDesc );
        connect( expert_table_filter, &SearchLineEdit::textChanged,
                 this, &PrefsDialog::expertTableFilterChanged );
        connect( expert_table_filter_modified, &QCheckBox::toggled,
                 this, &PrefsDialog::expertTableFilterModifiedToggled );

        /* Set initial selection */
        expert_table->setCurrentIndex(
                expert_table->model()->index( 0, 0, QModelIndex() ) );
    }

    expert->setChecked( true );
    stack->setCurrentIndex( EXPERT );
    setWindowTitle( qtr( "Expert Preferences" ) );
    m_headerTitle->setText( qtr("Expert Preferences") );
    expert_table_filter->setText( settings_search->text() );
    m_groupAdvanced->setVisible( false );
}

void PrefsDialog::setAdvanced()
{
    /* Lazy creation */
    if( !advanced_tree )
    {
        if ( !p_list )
            p_list = module_list_get( &count );

        advanced_tree = new PrefsTree( p_intf, advanced_tree_panel, p_list, count );

        tree_filter = new SearchLineEdit( advanced_tree_panel );
        tree_filter->setMinimumHeight( 26 );
        tree_filter->hide();

        current_filter = new QCheckBox( qtr("Only show current") );
        current_filter->setToolTip(
                    qtr("Only show modules related to current playback") );

        advanced_tree_panel->layout()->addWidget( tree_filter );
        advanced_tree_panel->layout()->addWidget( current_filter );
        advanced_tree_panel->layout()->addWidget( advanced_tree );
        advanced_tree_panel->setSizePolicy( QSizePolicy::Maximum, QSizePolicy::Preferred );

        connect( advanced_tree, &PrefsTree::currentItemChanged, this, &PrefsDialog::changeAdvPanel );
        connect( tree_filter, &SearchLineEdit::textChanged, this, &PrefsDialog::advancedTreeFilterChanged );
        connect( current_filter, &QtCheckboxChanged, this, &PrefsDialog::onlyLoadedToggled );

        /* Set initial selection */
        advanced_tree->setCurrentIndex(
                advanced_tree->model()->index( 0, 0, QModelIndex() ) );
    }

    all->setChecked( true );
    stack->setCurrentIndex( ADVANCED );
    setWindowTitle( qtr( "Advanced Preferences" ) );
    m_headerTitle->setText( qtr("Advanced Preferences") );
    tree_filter->setText( settings_search->text() );
    m_groupAdvanced->setVisible( false );
}

void PrefsDialog::setSimple()
{
    /* If no simple_tree, create one, connect it */
    if( !simple_tree )
    {
        simple_tree = new SPrefsCatList( p_intf, simple_tree_panel );
        connect( simple_tree, &SPrefsCatList::currentItemChanged,
                 this, &PrefsDialog::changeSimplePanel );
        auto sidebar = new QScrollArea( simple_tree_panel );
        sidebar->setFrameShape( QFrame::NoFrame );
        sidebar->setWidgetResizable( true );
        sidebar->setFixedWidth( 200 );
        sidebar->setHorizontalScrollBarPolicy( Qt::ScrollBarAlwaysOff );
        sidebar->setWidget( simple_tree );
        simple_tree_panel->layout()->addWidget( sidebar );
        simple_tree_panel->setSizePolicy( QSizePolicy::Preferred, QSizePolicy::Preferred );
    }

    if( ! simple_panels[SPrefsDefaultCat] )
        changeSimplePanel( SPrefsGroupGeneral );

    simple->setChecked( true );
    stack->setCurrentIndex( SIMPLE );
    setWindowTitle( qtr( "Simple Preferences" ) );
    m_groupAdvanced->setVisible( false );
    searchSettings( settings_search->text() );
}

/* Switching from on simple panel to another */
SPrefsPanel *PrefsDialog::ensureSimplePanel( int number )
{
    if( ! simple_panels[number] )
    {
        SPrefsPanel *insert = new SPrefsPanel( p_intf, simple_panels_stack, number ) ;
        simple_panels_stack->insertWidget( number, insert );
        simple_panels[number] = insert;
        connect( insert, &SPrefsPanel::advancedRequested, this, &PrefsDialog::showGroupAdvanced );
        installHelp( insert );
    }
    return simple_panels[number];
}

void PrefsDialog::changeSimplePanel( int group )
{
    m_currentGroup = group;
    // Header strings are copied from the corresponding Figma settings frames.
    const char *titles[] = {N_("Global Settings"), N_("Interface Settings"), N_("Privacy Settings"),
        N_("Mouse, Keyboard & Remote Controls"), N_("Playback Preferences"), N_("Video Defaults"),
        N_("Audio Defaults"), N_("Subtitle Defaults"), N_("Playlists, Folders & Files"), N_("Network Connections & Security"),
        N_("Performance Settings"), N_("Recording, Casting & Streaming Out"), N_("Add-ons & Scripts")};
    m_headerTitle->setText( qfut(titles[group]) );
    int panel = SPrefsCatList::groupPanel( group );
    if( panel == SPrefsMediaLibrary && !vlc_ml_instance_get(p_intf) )
        panel = SPrefsInterface;
    if( panel >= 0 )
    {
        auto source_panel = ensureSimplePanel( panel );
        source_panel->showGroup( group );
        installHelp( source_panel );
        simple_panels_stack->setCurrentWidget( source_panel );
    }
    else
    {
        if( !m_extensionsWidget )
        {
            m_extensionsWidget = new QWidget( simple_panels_stack );
            auto layout = new QVBoxLayout( m_extensionsWidget );
            auto title = new QLabel( qtr("Add-ons"), m_extensionsWidget ); // Figma 6575:17137.
            QFont title_font = QApplication::font();
            title_font.setPixelSize( 16 );
            title->setFont( title_font );
            layout->addWidget( title );
            auto addons = new AddonsTab( p_intf, true );
            addons->setParent( m_extensionsWidget );
            addons->setWindowFlags( Qt::Widget );
            layout->addWidget( addons, 1 );
            if( auto option = config_FindConfig("qt-autoload-extensions") )
            {
                auto options = new QWidget( m_extensionsWidget );
                auto options_layout = new QGridLayout( options );
                if( auto control = ConfigControl::createControl(option, options, options_layout) )
                    m_extensionsControls.append( control );
                layout->addWidget( options );
            }
            // These actions route to the original manager and its original tabs.
            const QString names[] = {qtr("Addons Manager"), qtr("Active Extensions"), qtr("Plugins")};
            auto managers = new QHBoxLayout;
            for( int tab = 1; tab < 3; ++tab )
            {
                auto button = new QPushButton( names[tab], m_extensionsWidget );
                button->setMinimumHeight( 44 );
                managers->addWidget( button );
                connect( button, &QPushButton::clicked, this, [this, tab]() {
                    if( !m_extensionsManager )
                        m_extensionsManager = std::make_unique<PluginDialog>( p_intf );
                    QVLCDialog::setWindowTransientParent( m_extensionsManager.get(), windowHandle(), p_intf );
                    m_extensionsManager->showTab( tab );
                } );
            }
            layout->addLayout( managers );
            installHelp( m_extensionsWidget );
            simple_panels_stack->addWidget( m_extensionsWidget );
        }
        simple_panels_stack->setCurrentWidget( m_extensionsWidget );
    }
    for( auto button : simple_tree->findChildren<QToolButton *>() )
        if( button->isChecked() )
            updateHelp( button );
}

/* Changing from one Advanced Panel to another */
void PrefsDialog::changeAdvPanel( QTreeWidgetItem *item )
{
    if( item == NULL ) return;
    PrefsTreeItem *node = static_cast<PrefsTreeItem *>( item );

    if( !node->panel )
    {
        node->panel = new AdvPrefsPanel( p_intf, advanced_panels_stack, node );
        advanced_panels_stack->addWidget( node->panel );
        installHelp( node->panel );
    }
    advanced_panels_stack->setCurrentWidget( node->panel );
    help_description->setText( node->help );
}

/* Changing from one Expert item description to another */
void PrefsDialog::changeExpertDesc( const QModelIndex &current, const QModelIndex &previous )
{
    Q_UNUSED( previous );
    if( !current.isValid() )
       return;
    ExpertPrefsTableItem *item = expert_table->myModel()->itemAt( current );

    expert_text->setText( item->getTitle() );
    help_description->setText( item->getDescription() );
}

/* Actual apply and save for the preferences */
void PrefsDialog::save()
{
    if( stack->currentIndex() == SIMPLE )
    {
        msg_Dbg( p_intf, "Saving the simple preferences" );
        for( int i = 0 ; i< SPrefsMax; i++ ){
            if( simple_panels[i] )
                simple_panels[i]->apply();
        }
        for( auto control : m_extensionsControls )
            control->doApply();
    }
    else if( stack->currentIndex() == ADVANCED )
    {
        msg_Dbg( p_intf, "Saving the advanced preferences" );
        advanced_tree->applyAll();
    }
    else if( stack->currentIndex() == EXPERT )
    {
        msg_Dbg( p_intf, "Saving the expert preferences" );
        expert_table->applyAll();
    }

    /* Save to file */
    const bool configurationSaved = config_SaveConfigFile( p_intf ) == 0;
    if( !configurationSaved )
    {
        DialogErrorModel::getInstance(p_intf)->pushError(
            qtr( "Cannot save Configuration" ),
            qtr("Preferences file could not be saved")
        );
        if (p_intf->b_isDialogProvider)
        {
            //at this point we are closing the preference dialog which is modal,
            //we need to postpone the dialog raising up
            QMetaObject::invokeMethod(DialogsProvider::getInstance(), [](){
                DialogsProvider::getInstance()->messagesDialog(1);
            }, Qt::QueuedConnection);
        }
    }

    if( p_intf->p_mi )
        p_intf->p_mi->reloadPrefs();
    if( configurationSaved )
        DialogsProvider::getInstance()->settingsProfileUpdated();
    accept();

    // Don't save widget position if reset is pending
    if( !p_intf->preferencesResetPending )
        QVLCTools::saveWidgetPosition( p_intf, m_hotkeysOnly ? "Hotkeys" : "Preferences", this );

    if( p_intf->preferencesResetPending )
    {
        int restart = QMessageBox::question(
                          this,
                          qtr( "Restart Required" ),
                          qtr( "VLC needs to be restarted for the reset to take full effect.\n\nRestart now?" ),
                          QMessageBox::Yes | QMessageBox::No,
                          QMessageBox::Yes);
        
        if( restart == QMessageBox::Yes )
        {
            // Quit VLC
            emit p_intf->p_mi->askToQuit();
        }
        else
        {
            // User chose not to restart - clear the flag
            p_intf->preferencesResetPending = false;
        }
    }

}

/* Clean the preferences, dunno if it does something really */
void PrefsDialog::cancel()
{
    bool wasResetting = p_intf->preferencesResetPending;
    
    // Clear the reset flag
    p_intf->preferencesResetPending = false;
    
    if( !wasResetting )
        QVLCTools::saveWidgetPosition( p_intf, m_hotkeysOnly ? "Hotkeys" : "Preferences", this );
    reject();
}

/* Reset all the preferences, when you click the button */
void PrefsDialog::reset()
{
    int ret = QMessageBox::question(
                 this,
                 qtr( "Reset Preferences" ),
                 qtr( "Are you sure you want to reset your VLC media player preferences?" ),
                 QMessageBox::Ok | QMessageBox::Cancel,
                 QMessageBox::Ok);

    if( ret == QMessageBox::Ok )
    {
        config_ResetAll();
        config_SaveConfigFile( p_intf );
        getSettings()->clear();
        p_intf->preferencesResetPending = true;
        p_intf->p_mi->reloadPrefs();
        p_intf->p_mi->reloadFromSettings();

#ifdef _WIN32
        simple_panels[0]->cleanLang();
#endif

    }
}

void PrefsDialog::expertTableFilterModifiedToggled( bool checked )
{
    expert_table->filter( expert_table_filter->text(), checked );
}

void PrefsDialog::expertTableFilterChanged( const QString & text )
{
    expert_table->filter( text, expert_table_filter_modified->isChecked() );
}

void PrefsDialog::advancedTreeFilterChanged( const QString & text )
{
    advanced_tree->filter( text );
}

void PrefsDialog::onlyLoadedToggled()
{
    advanced_tree->setLoadedOnly( current_filter->isChecked() );
}

namespace {
class ProfileCheckIconEngine final : public QIconEngine
{
public:
    explicit ProfileCheckIconEngine(QWidget *widget):m_widget(widget) {}
    QIconEngine *clone() const override {return new ProfileCheckIconEngine(m_widget.data());}
    void paint(QPainter *painter,const QRect &rect,QIcon::Mode mode,QIcon::State state) override
    {
        if(!m_widget) return;
        const auto color=m_widget->palette().color(mode==QIcon::Disabled?QPalette::Disabled:QPalette::Active,QPalette::WindowText);
        // Reuse VLC's original check glyph, tinting its literal black fill
        // from the current widget palette so both themes remain readable.
        ColorizedSvgIcon icon(QStringLiteral(":/redesign/icons/checkbox-check.svg"),{},{},{},
            {{QStringLiteral("fill=\"black\""),QStringLiteral("fill=\"%1\"").arg(color.name())}});
        icon.paint(painter,rect,Qt::AlignCenter,mode,state);
    }
private:
    QPointer<QWidget> m_widget;
};

// Shared with the native GUI: QSettings maps these slashes to dots in macOS
// CFPreferences. The names shown in the UI are exclusively user-provided.
const QString profilesKey = QStringLiteral("SettingsProfiles/items");
const QString currentProfileKey = QStringLiteral("SettingsProfiles/current");

QJsonArray readSettingsProfiles(qt_intf_t *intf)
{
    intf->mainSettings->sync();
    return QJsonDocument::fromJson(intf->mainSettings->value(profilesKey).toString().toUtf8()).array();
}

QSet<QByteArray> browsablePreferenceNames()
{
    QSet<QByteArray> names;
    size_t count=0;
    module_t **modules=module_list_get(&count);
    if(!modules) return names;
    for(size_t i=0;i<count;++i)
    {
        unsigned optionCount=0;
        module_config_t *options=module_config_get(modules[i],&optionCount);
        auto category=CAT_UNKNOWN;
        for(unsigned j=0;j<optionCount;++j)
        {
            const auto &option=options[j];
            if(option.i_type==CONFIG_SUBCATEGORY)
                category=vlc_config_cat_FromSubcat(static_cast<vlc_config_subcat>(option.value.i));
            // Identical GUI scope to the original complete/expert views:
            // hidden/unknown subcategories are launch/internal configuration.
            if(category!=CAT_HIDDEN && category!=CAT_UNKNOWN &&
               CONFIG_ITEM(option.i_type) && option.psz_name && option.psz_text)
                names.insert(QByteArray(option.psz_name));
        }
        module_config_free(options);
    }
    module_list_free(modules);
    return names;
}

QJsonArray configurationSnapshot()
{
    QJsonArray result;
    const auto browsable=browsablePreferenceNames();
    QSet<QByteArray> included;
    size_t count = 0;
    module_t **modules = module_list_get(&count);
    if (!modules) return result;
    for (size_t i = 0; i < count; ++i)
    {
        unsigned optionCount = 0;
        module_config_t *options = module_config_get(modules[i], &optionCount);
        for (unsigned j = 0; j < optionCount; ++j)
        {
            const auto &listed = options[j];
            if (!CONFIG_ITEM(listed.i_type) || !listed.psz_name || !listed.psz_text)
                continue;
            const QByteArray name(listed.psz_name);
            if (!browsable.contains(name) || included.contains(name)) continue;
            // Use the same canonical descriptor as Apply and config_Get/Put;
            // module enumeration supplies the discoverable option names.
            const auto canonical = config_FindConfig(listed.psz_name);
            if (!canonical || !CONFIG_ITEM(canonical->i_type)) continue;
            const auto &option = *canonical;
            included.insert(name);
            QJsonValue value;
            if (IsConfigIntegerType(option.i_type))
                value = QString::number(config_GetInt(option.psz_name));
            else if (IsConfigFloatType(option.i_type))
                value = QString::number(config_GetFloat(option.psz_name), 'g', std::numeric_limits<float>::max_digits10);
            else if (IsConfigStringType(option.i_type))
            {
                char *text = config_GetPsz(option.psz_name);
                value = text ? QJsonValue(QString::fromUtf8(text)) : QJsonValue(QJsonValue::Null);
                free(text);
            }
            else continue;
            result.append(QJsonObject{{QStringLiteral("name"), QString::fromUtf8(name)},
                                      {QStringLiteral("type"), option.i_type},
                                      {QStringLiteral("value"), value}});
        }
        module_config_free(options);
    }
    module_list_free(modules);
    return result;
}

bool isProfileGuiKey(const QString &key)
{
    // Profile layout/preferences never includes media, covers, history, pins,
    // update dates, recovery state, or the profiles themselves.
    return key.startsWith(QStringLiteral("MainWindow/")) ||
           key.startsWith(QStringLiteral("ControlbarProfileModel/"));
}

QString encodeGuiValue(const QVariant &value)
{
    QByteArray bytes;
    QDataStream stream(&bytes, QIODevice::WriteOnly);
    stream.setVersion(QDataStream::Qt_6_0);
    stream << value;
    return QString::fromLatin1(bytes.toBase64());
}

bool decodeGuiValue(const QJsonValue &encoded, QVariant &value)
{
    if (!encoded.isString()) return false;
    const auto decoded = QByteArray::fromBase64Encoding(encoded.toString().toLatin1(), QByteArray::AbortOnBase64DecodingErrors);
    if (!decoded) return false;
    QDataStream stream(decoded.decoded);
    stream.setVersion(QDataStream::Qt_6_0);
    stream >> value;
    return stream.status() == QDataStream::Ok && stream.atEnd();
}

QVariantMap currentGuiValues(qt_intf_t *intf)
{
    QVariantMap result;
    for (const QString &key : intf->mainSettings->allKeys())
        if (isProfileGuiKey(key)) result.insert(key, intf->mainSettings->value(key));
    if (auto ctx = intf->p_mi)
    {
        // These are the same source keys and live values saved by MainCtx's
        // destructor. Capture current layout without prematurely writing it.
        result.insert(QStringLiteral("MainWindow/ShowRemainingTime"), ctx->isShowRemainingTime());
        result.insert(QStringLiteral("MainWindow/interface-scale"), QString::number(ctx->getIntfUserScaleFactor()));
        result.insert(QStringLiteral("MainWindow/grid-view"), ctx->hasGridView());
        result.insert(QStringLiteral("MainWindow/grouping"), static_cast<int>(ctx->grouping()));
        result.insert(QStringLiteral("MainWindow/player-playlist-width"), QString::number(ctx->getPlayerPlaylistWidth()));
        result.insert(QStringLiteral("MainWindow/artist-albums-width"), QString::number(ctx->artistAlbumsWidth()));
        result.insert(QStringLiteral("MainWindow/album-sections"), ctx->albumSections());
        result.insert(QStringLiteral("MainWindow/lyrics-mode"), ctx->lyricsMode());
        result.insert(QStringLiteral("MainWindow/color-scheme-index"), ctx->getColorScheme()->currentIndex());
        for (auto panel : {ctx->getPlayqueuePanel(), ctx->getNavigationPanel()})
        {
            const QString prefix = panel == ctx->getPlayqueuePanel()
                ? QStringLiteral("MainWindow/playqueue-panel-") : QStringLiteral("MainWindow/navigation-panel-");
            result.insert(prefix + QStringLiteral("visible"), panel->isVisible());
            result.insert(prefix + QStringLiteral("width"), QString::number(panel->width()));
            if (panel == ctx->getPlayqueuePanel()) result.insert(prefix + QStringLiteral("docked"), panel->isDocked());
        }
        result.insert(QStringLiteral("ControlbarProfileModel/SelectedProfile"), ctx->controlbarProfileModel()->selectedProfile());
    }
    return result;
}

QJsonObject guiSnapshot(qt_intf_t *intf)
{
    QJsonObject result;
    const auto values = currentGuiValues(intf);
    for (auto i = values.cbegin(); i != values.cend(); ++i)
        result.insert(i.key(), encodeGuiValue(i.value()));
    return result;
}

QJsonObject snapshotInto(QJsonObject profile, qt_intf_t *intf)
{
    auto configuration=profile.value(QStringLiteral("configuration")).toArray();
    QHash<QString,qsizetype> positions;
    for(qsizetype i=0;i<configuration.size();++i)
        positions.insert(configuration[i].toObject().value(QStringLiteral("name")).toString(),i);
    for(const auto &entry:configurationSnapshot())
    {
        const QString name=entry.toObject().value(QStringLiteral("name")).toString();
        if(positions.contains(name)) configuration[positions.value(name)]=entry;
        else {positions.insert(name,configuration.size());configuration.append(entry);}
    }
    // A native/Qt/other-platform option unavailable in this build keeps its
    // original typed record when the active profile is refreshed here.
    profile.insert(QStringLiteral("configuration"),configuration);
    profile.insert(QStringLiteral("guiQt"), guiSnapshot(intf));
    // Keep the original object, including the native GUI snapshot and fields
    // created by a later version or another platform.
    return profile;
}

bool writeConfiguration(const QJsonArray &configuration, bool apply = true)
{
    struct Setting { QByteArray name; int type; QJsonValue value; int64_t integer; float floating; };
    QVector<Setting> settings;
    const auto browsable=browsablePreferenceNames();
    for (const auto &entry : configuration)
    {
        const auto object = entry.toObject();
        const QByteArray name = object.value(QStringLiteral("name")).toString().toUtf8();
        const auto option = config_FindConfig(name.constData());
        // A platform-specific plugin may not be installed. Keep its serialized
        // record and only apply values whose original metadata is available.
        if (!option || !browsable.contains(name)) continue;
        if (object.value(QStringLiteral("type")).toInt(-1) != option->i_type) return false;
        Setting setting{name, option->i_type, object.value(QStringLiteral("value")), 0, 0};
        bool valid = false;
        if (IsConfigIntegerType(option->i_type) && setting.value.isString())
            setting.integer = setting.value.toString().toLongLong(&valid, 10);
        else if (IsConfigFloatType(option->i_type) && setting.value.isString())
        {
            setting.floating = QLocale::c().toFloat(setting.value.toString(), &valid);
            valid = valid && std::isfinite(setting.floating);
        }
        else if (IsConfigStringType(option->i_type))
            valid = setting.value.isString() || setting.value.isNull();
        if (!valid) return false;
        settings.append(setting);
    }
    // Validate the entire snapshot before mutating any original option.
    if (!apply) return true;
    for (const auto &setting : settings)
    {
        if (IsConfigIntegerType(setting.type)) config_PutInt(setting.name.constData(), setting.integer);
        else if (IsConfigFloatType(setting.type)) config_PutFloat(setting.name.constData(), setting.floating);
        else
        {
            const auto text = setting.value.toString().toUtf8();
            config_PutPsz(setting.name.constData(), setting.value.isNull() ? nullptr : text.constData());
        }
    }
    return true;
}

void replaceGuiValues(QSettings *settings, const QVariantMap &values)
{
    for (const QString &key : settings->allKeys())
        if (isProfileGuiKey(key)) settings->remove(key);
    for (auto i = values.cbegin(); i != values.cend(); ++i) settings->setValue(i.key(), i.value());
}
} // namespace

QVariantList SettingsProfilesDialog::profiles(qt_intf_t *intf)
{
    QVariantList result;
    for (const auto &entry : readSettingsProfiles(intf))
    {
        const auto profile = entry.toObject();
        if (profile.value(QStringLiteral("id")).isString() && profile.value(QStringLiteral("name")).isString())
            result.append(QVariantMap{{QStringLiteral("id"), profile.value(QStringLiteral("id")).toString()},
                                      {QStringLiteral("name"), profile.value(QStringLiteral("name")).toString()}});
    }
    return result;
}

QString SettingsProfilesDialog::currentProfile(qt_intf_t *intf)
{
    return intf->mainSettings->value(currentProfileKey).toString();
}

bool SettingsProfilesDialog::updateCurrent(qt_intf_t *intf)
{
    const QString current = currentProfile(intf);
    if (current.isEmpty()) return false;
    auto items = readSettingsProfiles(intf);
    for (qsizetype i = 0; i < items.size(); ++i)
        if (items[i].toObject().value(QStringLiteral("id")).toString() == current)
        {
            items[i] = snapshotInto(items[i].toObject(), intf);
            intf->mainSettings->setValue(profilesKey, QString::fromUtf8(QJsonDocument(items).toJson(QJsonDocument::Compact)));
            intf->mainSettings->sync();
            return intf->mainSettings->status() == QSettings::NoError;
        }
    return false;
}

SettingsProfilesDialog::SettingsProfilesDialog(QWindow *parent, qt_intf_t *intf, const QString &selectedId)
    : QVLCDialog(parent, intf), m_profiles(readSettingsProfiles(intf)), m_current(currentProfile(intf))
{
    // Source copy: Figma 6648:20666 Profile/New and existing VLC toolbar
    // Profile Name prompt; action/table labels are original Qt preferences.
    setObjectName(QStringLiteral("settingsProfilesDialog"));
    setWindowTitle(qtr("Profile"));
    setWindowModality(Qt::WindowModal);
    setAttribute(Qt::WA_DeleteOnClose);
    resize(1048, 800);
    auto shell = new QVBoxLayout(this);
    shell->setContentsMargins(0,0,0,0);
    shell->setSpacing(0);
    auto header = new QWidget(this);
    header->setObjectName(QStringLiteral("preferencesHeader"));
    header->setFixedHeight(50);
    auto heading = new QHBoxLayout(header);
    heading->setContentsMargins(20,9,9,9);
    heading->addWidget(new QLabel(qtr("Profile"), header),1);
    auto close = new QToolButton(header);
    close->setIcon(QIcon(QStringLiteral(":/redesign/icons/settings-close.svg")));
    close->setIconSize(QSize(24,24));
    close->setFixedSize(32,32);
    close->setAccessibleName(qtr("Close"));
    connect(close,&QToolButton::clicked,this,&QDialog::reject);
    heading->addWidget(close);
    shell->addWidget(header);
    auto body = new QWidget(this);
    auto bodyLayout = new QHBoxLayout(body);
    bodyLayout->setContentsMargins(8,8,20,20);
    bodyLayout->setSpacing(24);
    auto sidebar = new QWidget(body);
    sidebar->setObjectName(QStringLiteral("preferencesSidebar"));
    sidebar->setFixedWidth(200);
    auto navigation = new QVBoxLayout(sidebar);
    navigation->setContentsMargins(6,6,6,6);
    m_list = new QListWidget(sidebar);
    m_list->setObjectName(QStringLiteral("settingsProfilesList"));
    m_list->setSelectionMode(QAbstractItemView::SingleSelection);
    m_list->setStyleSheet(QStringLiteral("QListWidget { border: 0; } QListWidget::item { height: 40px; padding: 0 14px; margin-bottom: 8px; }"));
    navigation->addWidget(m_list,1);
    auto create = new QPushButton(qtr("New"),sidebar);
    create->setObjectName(QStringLiteral("settingsProfilesNew"));
    create->setFixedHeight(32);
    m_delete = new QPushButton(qtr("Delete"),sidebar);
    m_delete->setObjectName(QStringLiteral("settingsProfilesDelete"));
    m_delete->setFixedHeight(32);
    navigation->addWidget(create);
    navigation->addWidget(m_delete);
    bodyLayout->addWidget(sidebar);
    auto content = new QWidget(body);
    auto contentLayout = new QVBoxLayout(content);
    contentLayout->setContentsMargins(0,12,0,0);
    contentLayout->setSpacing(20);
    m_search = new QLineEdit(content);
    m_search->setObjectName(QStringLiteral("settingsProfilesSearch"));
    m_search->setPlaceholderText(qtr("Search"));
    m_search->setClearButtonEnabled(true);
    m_search->setFixedHeight(36);
    m_search->addAction(QIcon(QStringLiteral(":/redesign/icons/settings-search.svg")),QLineEdit::LeadingPosition);
    contentLayout->addWidget(m_search);
    m_values = new QTableWidget(content);
    m_values->setObjectName(QStringLiteral("settingsProfilesValues"));
    m_values->setColumnCount(3);
    m_values->setHorizontalHeaderLabels({qtr("Option"),qtr("Value"),QString()});
    m_values->horizontalHeader()->setSectionResizeMode(0,QHeaderView::Stretch);
    m_values->horizontalHeader()->setSectionResizeMode(1,QHeaderView::Stretch);
    m_values->horizontalHeader()->setSectionResizeMode(2,QHeaderView::Fixed);
    m_values->setColumnWidth(2,36);
    m_values->horizontalHeader()->setMinimumHeight(36);
    m_values->verticalHeader()->hide();
    m_values->verticalHeader()->setDefaultSectionSize(40);
    m_values->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_values->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_values->setShowGrid(false);
    contentLayout->addWidget(m_values,1);
    bodyLayout->addWidget(content,1);
    shell->addWidget(body,1);
    auto footerWidget = new QWidget(this);
    footerWidget->setFixedHeight(72);
    auto footer = new QHBoxLayout(footerWidget);
    footer->setContentsMargins(20,20,20,20);
    auto cancel = new QPushButton(qtr("Cancel"),footerWidget);
    m_save = new QPushButton(qtr("Save"),footerWidget);
    m_save->setObjectName(QStringLiteral("settingsProfilesSave"));
    m_apply = new QPushButton(qtr("Apply"),footerWidget);
    m_apply->setObjectName(QStringLiteral("settingsProfilesApply"));
    for (auto button : {cancel,m_save,m_apply}) button->setFixedSize(100,32);
    footer->addWidget(cancel);
    footer->addStretch();
    footer->addWidget(m_save);
    footer->addWidget(m_apply);
    shell->addWidget(footerWidget);
    connect(cancel,&QPushButton::clicked,this,&QDialog::reject);
    connect(create,&QPushButton::clicked,this,&SettingsProfilesDialog::newProfile);
    connect(m_delete,&QPushButton::clicked,this,&SettingsProfilesDialog::deleteProfile);
    connect(m_save,&QPushButton::clicked,this,&SettingsProfilesDialog::saveProfile);
    connect(m_apply,&QPushButton::clicked,this,&SettingsProfilesDialog::applyProfile);
    connect(m_list,&QListWidget::currentRowChanged,this,&SettingsProfilesDialog::reviewProfile);
    connect(m_search,&QLineEdit::textChanged,this,&SettingsProfilesDialog::filterValues);
    const auto showInformation=[this](int row,int column){
        if(column==2) showPreferenceHelp(m_values,m_values->item(row,column)->toolTip());
    };
    connect(m_values,&QTableWidget::cellClicked,this,showInformation);
    connect(m_values,&QTableWidget::cellActivated,this,showInformation);
    refreshList(selectedId.isEmpty() ? m_current : selectedId);
}

void SettingsProfilesDialog::refreshList(const QString &selectedId)
{
    const QSignalBlocker block(m_list);
    m_list->clear();
    int selected = -1;
    for (const auto &entry : m_profiles)
    {
        const auto profile = entry.toObject();
        if (!profile.value(QStringLiteral("id")).isString() || !profile.value(QStringLiteral("name")).isString()) continue;
        auto item = new QListWidgetItem(profile.value(QStringLiteral("name")).toString(),m_list);
        item->setData(Qt::UserRole,profile.value(QStringLiteral("id")).toString());
        if (item->data(Qt::UserRole).toString() == m_current) item->setIcon(QIcon(new ProfileCheckIconEngine(m_list)));
        if (item->data(Qt::UserRole).toString() == selectedId) selected = m_list->count()-1;
    }
    m_list->setCurrentRow(selected < 0 && m_list->count() ? 0 : selected);
    reviewProfile();
}

void SettingsProfilesDialog::selectProfile(const QString &id)
{
    for (int i=0;i<m_list->count();++i)
        if (m_list->item(i)->data(Qt::UserRole).toString()==id) {m_list->setCurrentRow(i);break;}
}

void SettingsProfilesDialog::reviewProfile()
{
    m_values->setRowCount(0);
    const auto item = m_list->currentItem();
    m_delete->setEnabled(item);
    m_apply->setEnabled(item);
    m_save->setEnabled(item || !m_profiles.isEmpty());
    if (!item) return;
    const QString selectedId = item->data(Qt::UserRole).toString();
    QJsonObject selected;
    for (const auto &entry : m_profiles)
        if (entry.toObject().value(QStringLiteral("id")).toString()==selectedId) selected=entry.toObject();
    const auto options = selected.value(QStringLiteral("configuration")).toArray();
    const auto browsable=browsablePreferenceNames();
    for (const auto &entry : options)
    {
        const auto setting = entry.toObject();
        const QString name = setting.value(QStringLiteral("name")).toString();
        const auto option = config_FindConfig(name.toUtf8().constData());
        if(option && !browsable.contains(name.toUtf8())) continue;
        const int row=m_values->rowCount();
        m_values->insertRow(row);
        const QString caption = option && option->psz_text ? qfut(option->psz_text) : name;
        auto label = new QTableWidgetItem(caption);
        label->setData(Qt::UserRole,name);
        const QString help = option && option->psz_longtext ? qfut(option->psz_longtext) : caption;
        label->setToolTip(help);
        m_values->setItem(row,0,label);
        QString value=setting.value(QStringLiteral("value")).toString();
        if (setting.value(QStringLiteral("type")).toInt()==CONFIG_ITEM_PASSWORD && !value.isEmpty())
            value=QStringLiteral(u"•••••"); // Same mask as ExpertPrefsTableItem.
        auto rendered=new QTableWidgetItem(value);
        m_values->setItem(row,1,rendered);
        auto information=new QTableWidgetItem(QIcon(QStringLiteral(":/redesign/icons/settings-info.svg")),QString());
        information->setToolTip(help);
        information->setData(Qt::AccessibleTextRole,qtr("Help"));
        m_values->setItem(row,2,information);
    }
    filterValues();
}

void SettingsProfilesDialog::filterValues()
{
    const QString text=m_search->text().trimmed();
    for (int row=0;row<m_values->rowCount();++row)
        m_values->setRowHidden(row,!text.isEmpty() &&
            !m_values->item(row,0)->text().contains(text,Qt::CaseInsensitive) &&
            !m_values->item(row,0)->data(Qt::UserRole).toString().contains(text,Qt::CaseInsensitive) &&
            !m_values->item(row,0)->toolTip().contains(text,Qt::CaseInsensitive) &&
            !m_values->item(row,1)->text().contains(text,Qt::CaseInsensitive));
}

void SettingsProfilesDialog::newProfile()
{
    bool accepted=false;
    const QString name=QInputDialog::getText(this,qtr("Profile Name"),qtr("Please enter the new profile name:"),QLineEdit::Normal,QString(),&accepted).trimmed();
    if (!accepted || name.isEmpty()) return;
    const QString id=QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_profiles.append(snapshotInto(QJsonObject{{QStringLiteral("id"),id},{QStringLiteral("name"),name}},p_intf));
    refreshList(id);
}

void SettingsProfilesDialog::deleteProfile()
{
    const auto item=m_list->currentItem();
    if (!item) return;
    const QString id=item->data(Qt::UserRole).toString();
    for (qsizetype i=m_profiles.size();i-->0;)
        if (m_profiles[i].toObject().value(QStringLiteral("id")).toString()==id) m_profiles.removeAt(i);
    if (m_current==id) m_current.clear();
    refreshList(QString());
    m_save->setEnabled(true); // Deleting the final profile is still a staged change.
}

void SettingsProfilesDialog::reportSaveError()
{
    DialogErrorModel::getInstance(p_intf)->pushError(qtr("Cannot save Configuration"),qtr("Preferences file could not be saved"));
}

bool SettingsProfilesDialog::persist()
{
    p_intf->mainSettings->setValue(profilesKey,QString::fromUtf8(QJsonDocument(m_profiles).toJson(QJsonDocument::Compact)));
    p_intf->mainSettings->setValue(currentProfileKey,m_current);
    p_intf->mainSettings->sync();
    if (p_intf->mainSettings->status()!=QSettings::NoError) {reportSaveError();return false;}
    return true;
}

void SettingsProfilesDialog::saveProfile()
{
    if (const auto item=m_list->currentItem(); item && item->data(Qt::UserRole).toString()==m_current)
        for (qsizetype i=0;i<m_profiles.size();++i)
            if (m_profiles[i].toObject().value(QStringLiteral("id")).toString()==item->data(Qt::UserRole).toString())
                m_profiles[i]=snapshotInto(m_profiles[i].toObject(),p_intf);
    // Save commits staged New/Delete and refreshes the active profile only.
    // A dormant reviewed snapshot must not be overwritten simply because
    // deleting another profile selected it. Apply switches the active profile.
    if (persist()) {emit profilesChanged();accept();}
}

void SettingsProfilesDialog::applyProfile()
{
    const auto item=m_list->currentItem();
    if (!item) return;
    QJsonObject selected;
    const QString id=item->data(Qt::UserRole).toString();
    for (const auto &entry:m_profiles)
        if (entry.toObject().value(QStringLiteral("id")).toString()==id) selected=entry.toObject();
    if (!selected.value(QStringLiteral("configuration")).isArray()) return;
    const auto configuration=selected.value(QStringLiteral("configuration")).toArray();
    if (!writeConfiguration(configuration,false)) {reportSaveError();return;}
    QVariantMap gui;
    const auto encoded=selected.value(QStringLiteral("guiQt")).toObject();
    for (auto i=encoded.begin();i!=encoded.end();++i)
    {
        if (!isProfileGuiKey(i.key())) continue;
        QVariant value;
        if (!decodeGuiValue(i.value(),value)) {reportSaveError();return;}
        gui.insert(i.key(),value);
    }
    // Close any older preference transaction via its original Cancel path
    // before writing the selected snapshot, so theme resetters cannot later
    // replace the newly selected appearance.
    emit aboutToApply();
    const QString previousSelection=m_current;
    const QJsonArray previousConfiguration=configurationSnapshot();
    const auto previousGui=currentGuiValues(p_intf);
    const QVariant previousItems=p_intf->mainSettings->value(profilesKey);
    const QVariant previousCurrent=p_intf->mainSettings->value(currentProfileKey);
    if (!writeConfiguration(configuration)) {reportSaveError();return;}
    const auto rollback=[&]() {
        writeConfiguration(previousConfiguration);
        replaceGuiValues(p_intf->mainSettings,previousGui);
        if(previousItems.isValid()) p_intf->mainSettings->setValue(profilesKey,previousItems); else p_intf->mainSettings->remove(profilesKey);
        if(previousCurrent.isValid()) p_intf->mainSettings->setValue(currentProfileKey,previousCurrent); else p_intf->mainSettings->remove(currentProfileKey);
        p_intf->mainSettings->sync();
        m_current=previousSelection;
    };
    if (selected.contains(QStringLiteral("guiQt"))) replaceGuiValues(p_intf->mainSettings,gui);
    m_current=id;
    if (!persist()) {rollback();return;}
    if (config_SaveConfigFile(p_intf)!=0) {rollback();reportSaveError();return;}
    if (auto ctx=p_intf->p_mi)
    {
        ctx->reloadPrefs();
        ctx->reloadFromSettings();
        ctx->controlbarProfileModel()->reload();
        ctx->controlbarProfileModel()->setSelectedProfile(p_intf->mainSettings->value(QStringLiteral("ControlbarProfileModel/SelectedProfile")).toInt());
    }
    const QString style=p_intf->mainSettings->value(QStringLiteral("MainWindow/QtStyle"),qApp->property("initialStyle")).toString();
    if (QStyleFactory::keys().contains(style,Qt::CaseInsensitive)) QApplication::setStyle(style);
    emit profilesChanged();
    accept();
}
