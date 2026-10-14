/*****************************************************************************
 * extended.cpp : Extended controls - Undocked
 ****************************************************************************
 * Copyright (C) 2006-2008 the VideoLAN team
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

#include <cassert>

#include "extended.hpp"

#include "maininterface/compositor.hpp" /* Needed for external MI size */
#include "player/player_controller.hpp"

#include <QTabWidget>
#include <QGridLayout>
#include <QDialogButtonBox>
#include <QPushButton>
#include <QWindow>
#include <QListWidget>
#include <QTabBar>
#include <QComboBox>
#include <QLabel>
#include <QToolButton>
#include <vlc_configuration.h>
#include <vlc_modules.h>

namespace {
QComboBox *effectsSelector( QTabWidget *tabs, QWidget *parent )
{
    auto selector = new QComboBox(parent);
    selector->setObjectName(QStringLiteral("effectPanelSelector"));
    selector->setFixedSize(320,36);
    for(int i=0;i<tabs->count();++i) selector->addItem(tabs->tabText(i));
    selector->setCurrentIndex(tabs->currentIndex());
    tabs->tabBar()->hide();
    QObject::connect(selector,qOverload<int>(&QComboBox::currentIndexChanged),tabs,&QTabWidget::setCurrentIndex);
    QObject::connect(tabs,&QTabWidget::currentChanged,selector,&QComboBox::setCurrentIndex);
    return selector;
}
}

ExtendedDialog::ExtendedDialog( qt_intf_t *_p_intf )
               : QVLCDialog( nullptr, _p_intf )
{
#ifdef __APPLE__
    setWindowFlags( Qt::Drawer );
#else
    setWindowFlags( Qt::Tool );
#endif

    setWindowOpacity( var_InheritFloat( p_intf, "qt-opacity" ) );
    setWindowTitle( qtr( "Adjustments and Effects" ) );
    setWindowRole( "vlc-extended" );
    setObjectName(QStringLiteral("extendedEffectsDialog"));

    QVBoxLayout *layout = new QVBoxLayout( this );
    layout->setContentsMargins(0,0,0,0);
    layout->setSpacing(0);
    auto header = new QWidget(this);
    header->setObjectName(QStringLiteral("preferencesHeader"));
    header->setFixedHeight(50);
    auto headerLayout = new QHBoxLayout(header);
    headerLayout->setContentsMargins(20,9,9,9);
    auto heading = new QLabel(windowTitle(),header);
    headerLayout->addWidget(heading,1);
    auto headerClose = new QToolButton(header);
    headerClose->setIcon(QIcon(QStringLiteral(":/redesign/icons/settings-close.svg")));
    headerClose->setIconSize(QSize(24,24));
    headerClose->setFixedSize(32,32);
    headerClose->setAccessibleName(qtr("Close"));
    connect(headerClose,&QToolButton::clicked,this,&ExtendedDialog::close);
    headerLayout->addWidget(headerClose);
    layout->addWidget(header);

    mainTabW = new QTabWidget( this );
    mainTabW->setProperty("effectPanels",true);

    /* AUDIO effects */
    QWidget *audioWidget = new QWidget;
    QVBoxLayout *audioLayout = new QVBoxLayout( audioWidget );
    audioLayout->setContentsMargins(0,0,0,0);
    audioLayout->setSpacing(20);
    QTabWidget *audioTab = new QTabWidget( audioWidget );
    audioTab->setProperty("effectPanels",true);

    equal = new Equalizer( p_intf, audioTab );
    connect( equal, &AudioFilterControlWidget::configChanged, this, &ExtendedDialog::putAudioConfig );
    audioTab->addTab( equal, qtr( "Equalizer" ) );

    Compressor *compres = new Compressor( p_intf, audioTab );
    connect( compres, &AudioFilterControlWidget::configChanged, this, &ExtendedDialog::putAudioConfig );
    audioTab->addTab( compres, qtr( "Compressor" ) );

    Expander *expand = new Expander( p_intf, audioTab );
    connect( expand, &AudioFilterControlWidget::configChanged, this, &ExtendedDialog::putAudioConfig );
    audioTab->addTab( expand, qtr( "Expander" ) );

    Limiter *limit = new Limiter( p_intf, audioTab );
    connect( limit, &AudioFilterControlWidget::configChanged, this, &ExtendedDialog::putAudioConfig );
    audioTab->addTab( limit, qtr( "Limiter" ) );

    Spatializer *spatial = new Spatializer( p_intf, audioTab );
    connect( spatial, &AudioFilterControlWidget::configChanged, this, &ExtendedDialog::putAudioConfig );
    audioTab->addTab( spatial, qtr( "Spatializer" ) );

    StereoWidener *stereowiden = new StereoWidener( p_intf, audioTab );
    connect( stereowiden, &AudioFilterControlWidget::configChanged, this, &ExtendedDialog::putAudioConfig );
    audioTab->addTab( stereowiden, qtr( "Stereo Widener" ) );

    QWidget *advancedTab = new QWidget;
    QGridLayout *advancedTabLayout = new QGridLayout;

    PitchShifter *pitchshifter = new PitchShifter( p_intf, audioTab );
    connect( pitchshifter, &AudioFilterControlWidget::configChanged, this, &ExtendedDialog::putAudioConfig );

    StereoPanner *stereopanner = new StereoPanner( p_intf, audioTab );
    connect( stereopanner, &AudioFilterControlWidget::configChanged, this, &ExtendedDialog::putAudioConfig );

    advancedTabLayout->setColumnStretch( 2, 10 );
    advancedTabLayout->addWidget( pitchshifter );
    advancedTabLayout->addWidget( stereopanner );

    advancedTab->setLayout( advancedTabLayout );
    audioTab->addTab( advancedTab, qtr( "Advanced" ) );

    audioLayout->addWidget(effectsSelector(audioTab,audioWidget),0,Qt::AlignLeft);
    audioLayout->addWidget( audioTab,1 );

    mainTabW->insertTab( AUDIO_TAB, audioWidget, qtr( "Audio Effects" ) );

    /* Video Effects */
    QWidget *videoWidget = new QWidget;
    QVBoxLayout *videoLayout = new QVBoxLayout( videoWidget );
    videoLayout->setContentsMargins(0,0,0,0);
    videoLayout->setSpacing(20);
    QTabWidget *videoTab = new QTabWidget( videoWidget );
    videoTab->setProperty("effectPanels",true);

    videoEffect = new ExtVideo( p_intf, videoTab );
    connect( videoEffect, &ExtVideo::configChanged, this, &ExtendedDialog::putVideoConfig );
    videoLayout->addWidget(effectsSelector(videoTab,videoWidget),0,Qt::AlignLeft);
    videoLayout->addWidget( videoTab,1 );

    mainTabW->insertTab( VIDEO_TAB, videoWidget, qtr( "Video Effects" ) );

    syncW = new SyncControls( p_intf, mainTabW );
    mainTabW->insertTab( SYNCHRO_TAB, syncW, qtr( "Synchronization" ) );

    if( module_exists( "v4l2" ) )
    {
        ExtV4l2 *v4l2 = new ExtV4l2( p_intf, mainTabW );
        mainTabW->insertTab( V4L2_TAB, v4l2, qtr( "v4l2 controls" ) );
    }

    auto effects_navigation = new QListWidget( this );
    effects_navigation->setObjectName( QStringLiteral("dialogNavigation") );
    effects_navigation->setFixedWidth(200);
    effects_navigation->setSpacing(8);
    effects_navigation->setFrameShape( QFrame::NoFrame );
    for( int i = 0; i < mainTabW->count(); ++i )
    {
        // Section names are the existing effects/synchronization tab labels.
        auto item = new QListWidgetItem( mainTabW->tabText(i), effects_navigation );
        item->setSizeHint( QSize(0,40) );
    }
    auto effects_layout = new QHBoxLayout;
    effects_layout->setContentsMargins(8,20,24,20);
    effects_layout->setSpacing( 20 );
    effects_layout->addWidget( effects_navigation );
    effects_layout->addWidget( mainTabW, 1 );
    layout->addLayout( effects_layout, 1 );
    mainTabW->tabBar()->hide();
    effects_navigation->setCurrentRow( mainTabW->currentIndex() );
    connect( effects_navigation, &QListWidget::currentRowChanged,
             mainTabW, &QTabWidget::setCurrentIndex );
    connect( mainTabW, &QTabWidget::currentChanged,
             effects_navigation, QOverload<int>::of(&QListWidget::setCurrentRow) );
    connect( mainTabW, &QTabWidget::currentChanged, this, &ExtendedDialog::currentTabChanged );
    connect(mainTabW,&QTabWidget::currentChanged,heading,[this,heading](int index){
        heading->setText(mainTabW->tabText(index));
    });
    heading->setText(mainTabW->tabText(mainTabW->currentIndex()));

    /* Bottom buttons */
    auto footer = new QWidget(this);
    footer->setFixedHeight(72);
    auto footerLayout = new QHBoxLayout(footer);
    footerLayout->setContentsMargins(20,20,20,20);
    auto close = new QPushButton(qtr("&Close"),footer);
    close->setFixedSize(100,32);
    footerLayout->addWidget(close);
    footerLayout->addStretch();
    m_applyButton = new QPushButton( qtr("&Save"), footer );
    m_applyButton->setEnabled( false );
    m_applyButton->setFixedSize(100,32);
    footerLayout->addWidget(m_applyButton);
    layout->addWidget(footer);
    connect(close,&QPushButton::clicked,this,&ExtendedDialog::close);
    connect( m_applyButton, &QPushButton::clicked, this, &ExtendedDialog::saveConfig );

    /* Restore geometry or move this dialog on the left pane of the MI */
    if( !restoreGeometry( getSettings()->value("EPanel/geometry").toByteArray() ) )
    {
        resize( QSize(1048,800) );

        QWindow *window = p_intf->p_compositor->interfaceMainWindow();
        if( window && window->x() > 50 )
            move( ( window->x() - frameGeometry().width() - 10 ), window->y() );
        else
            move ( 450 , 0 );
    }

    connect( THEMIM, &PlayerController::playingStateChanged, this, &ExtendedDialog::changedItem );
}

ExtendedDialog::~ExtendedDialog()
{
    getSettings()->setValue("EPanel/geometry", saveGeometry());
}

void ExtendedDialog::showTab( int i )
{
    mainTabW->setCurrentIndex( i );
    show();
}

int ExtendedDialog::currentTab()
{
    return mainTabW->currentIndex();
}

void ExtendedDialog::changedItem( PlayerController::PlayingState i_status )
{
    if( i_status != PlayerController::PLAYING_STATE_STOPPED ) return;
    syncW->clean();
    videoEffect->clean();
}

void ExtendedDialog::currentTabChanged( int i )
{
    if( i == AUDIO_TAB || i == VIDEO_TAB )
    {
        m_applyButton->setVisible( true );
        m_applyButton->setEnabled( !m_hashConfigs[i].isEmpty() );
        m_applyButton->setFocusPolicy( Qt::StrongFocus );
    }
    else
    {
        m_applyButton->setVisible( false );
        m_applyButton->setFocusPolicy( Qt::NoFocus );
    }
}

void ExtendedDialog::putAudioConfig( const QString& name, const QVariant value )
{
    m_hashConfigs[AUDIO_TAB].insert( name, value );
    m_applyButton->setEnabled( true );
}

void ExtendedDialog::putVideoConfig( const QString& name, const QVariant value )
{
    m_hashConfigs[VIDEO_TAB].insert( name, value );
    m_applyButton->setEnabled( true );
}

void ExtendedDialog::saveConfig()
{
    assert( currentTab() == AUDIO_TAB || currentTab() == VIDEO_TAB );
    QHash<QString, QVariant> *hashConfig = &m_hashConfigs[currentTab()];

    for( QHash<QString, QVariant>::iterator i = hashConfig->begin();
         i != hashConfig->end(); ++i )
    {
        QVariant &value = i.value();
        switch( static_cast<QMetaType::Type>(value.typeId()) )
        {
            case QMetaType::QString:
                config_PutPsz( qtu(i.key()), qtu(value.toString()) );
                break;
            case QMetaType::Int:
            case QMetaType::Bool:
                config_PutInt( qtu(i.key()), value.toInt() ) ;
                break;
            case QMetaType::Double:
            case QMetaType::Float:
                config_PutFloat( qtu(i.key()), value.toFloat() ) ;
                break;
            default:
                vlc_assert_unreachable();
        }
    }
    config_SaveConfigFile( p_intf );
    hashConfig->clear();
    m_applyButton->setEnabled( false );
}
