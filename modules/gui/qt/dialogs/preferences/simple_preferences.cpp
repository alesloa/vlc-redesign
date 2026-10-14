/*****************************************************************************
 * simple_preferences.cpp : "Simple preferences"
 ****************************************************************************
 * Copyright (C) 2006-2010 the VideoLAN team
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Antoine Cellerier <dionoea@videolan.org>
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

#include "simple_preferences.hpp"
#include "preferences_widgets.hpp"
#include "dialogs/dialogs_provider.hpp"
#include "maininterface/mainctx.hpp"
#include "util/accessible_compat_attached.hpp"
#include "util/color_scheme_model.hpp"
#include "util/proxycolumnmodel.hpp"
#include "medialibrary/mlrecentmediamodel.hpp"

#include <vlc_config_cat.h>
#include <vlc_configuration.h>
#include <vlc_aout.h>
#include <vlc_plugin.h>

#include <QString>
#include <QFont>
#include <QToolButton>
#include <QButtonGroup>
#include <QSignalMapper>
#include <QVBoxLayout>
#include <QScrollArea>

#include <QStyleFactory>
#include <QScreen>
#include <QDir>

#include <QSpinBox>
#include <QDoubleSpinBox>
#include <QCheckBox>
#include <QLabel>
#include <QPushButton>
#include <QGridLayout>
#include <QWidget>
#include <QHBoxLayout>
#include <QDialog>
#include <QFileDialog>
#include <QTreeWidget>
#include <QTreeWidgetItem>
#include <QRegularExpression>
#include <QTreeWidgetItemIterator>
#include <QTextDocument>
#include <QStyle>
#include <QEvent>
#include <QSignalBlocker>
#include <QMap>

#include <cassert>
#include <math.h>
#ifdef _WIN32
#include <wrl/client.h>
#endif

#define ICON_HEIGHT 24
#define ICON_WIDTH 24

namespace {
void normalizePreferenceRows( QGridLayout *grid, QWidget *owner )
{
    QMap<int, QList<QLayoutItem *>> rows;
    while( grid->count() )
    {
        int row, column, rowSpan, columnSpan;
        grid->getItemPosition( 0, &row, &column, &rowSpan, &columnSpan );
        auto item = grid->takeAt( 0 );
        if( item->spacerItem() ) delete item;
        else rows[row].append( item );
    }
    for( int row = 0; row < grid->rowCount(); ++row )
    {
        grid->setRowMinimumHeight( row, 0 );
        grid->setRowStretch( row, 0 );
    }
    for( int column = 0; column < grid->columnCount(); ++column )
    {
        grid->setColumnMinimumWidth( column, 0 );
        grid->setColumnStretch( column, 0 );
    }
    grid->setColumnStretch( 0, 1 );
    grid->setHorizontalSpacing( 0 );
    grid->setVerticalSpacing( 10 );
    int row = 0;
    for( const auto &items : rows )
    {
        QList<QLayoutItem *> fields;
        bool caption = false;
        for( auto item : items )
        {
            auto widget = item->widget();
            if( widget && widget->property("preferenceToggleRow").toBool() )
            {
                grid->addItem( item, row++, 0, 1, 11 );
            }
            else if( widget && (qobject_cast<QLabel *>(widget) || widget->property("preferenceCaptionRow").toBool()) )
            {
                if( caption ) ++row;
                caption = true;
                grid->addItem( item, row, 0 );
            }
            else fields.append( item );
        }
        if( fields.isEmpty() ) continue;
        if( !caption && fields.size() == 1 )
            if( auto widget = fields.first()->widget() )
            {
                QString title;
                if( widget->objectName() == "defaultVolume_zone" )
                    title = qtr("Startup volume"); // Figma Audio 3073:15879.
                else if( auto option = config_FindConfig(qtu(widget->property("preferenceOptionName").toString())) )
                    title = qfut(option->psz_text);
                if( !title.isEmpty() ) grid->addWidget( new QLabel(title, owner), row, 0 );
            }
        auto field = new QWidget( owner );
        field->setFixedWidth( 320 );
        auto layout = new QHBoxLayout( field );
        layout->setContentsMargins( 0, 0, 0, 0 );
        layout->setSpacing( 10 );
        for( auto item : fields )
            if( auto widget = item->widget() )
            {
                layout->addWidget( widget );
                delete item;
            }
            else if( auto child = item->layout() )
            {
                child->setParent( nullptr );
                layout->addLayout( child );
            }
        grid->addWidget( field, row++, 10, Qt::AlignRight );
    }
}

struct PreferenceGroup {
    const char *title;
    const char *help;
    const char *icon;
    int panel;
    const char *sections;
    vlc_config_subcat advanced;
};

// Group titles/order come from the owner's supplied redesign video transcript.
// Routing uses the existing simple UI sections and VLC configuration categories.
const PreferenceGroup preferenceGroups[] = {
    {N_("General"), INTF_GENERAL_HELP, ":/prefsmenu/advprefs_intf.svg", SPrefsInterface,
        "langBox|osGroupBox", SUBCAT_INTERFACE_GENERAL},
    {N_("Interface"), INTF_MAIN_HELP, ":/prefsmenu/advprefs_intf.svg", SPrefsInterface,
        "LooknfeelBox", SUBCAT_INTERFACE_MAIN},
    {N_("Privacy"), INTF_HELP, ":/prefsmenu/advprefs_intf.svg", SPrefsInterface,
        "groupBox_2", SUBCAT_PLAYLIST_GENERAL},
    {N_("Controls"), INTF_HOTKEYS_HELP, ":/prefsmenu/spref_hotkeys.png", SPrefsHotkeys,
        "", SUBCAT_INTERFACE_HOTKEYS},
    {N_("Playback"), PGENERAL_HELP, ":/prefsmenu/advprefs_playlist.svg", SPrefsInterface,
        "PlaylistAndInstancesBox", SUBCAT_INPUT_GENERAL},
    {N_("Video"), VIDEO_HELP, ":/prefsmenu/advprefs_video.svg", SPrefsVideo,
        "", SUBCAT_VIDEO_GENERAL},
    {N_("Audio"), AUDIO_HELP, ":/prefsmenu/advprefs_audio.svg", SPrefsAudio,
        "", SUBCAT_AUDIO_GENERAL},
    {N_("Subtitles"), SUBPIC_HELP, ":/prefsmenu/spref_subtitles.png", SPrefsSubtitles,
        "", SUBCAT_VIDEO_SUBPIC},
    {N_("Library"), PLAYLIST_HELP, ":/prefsmenu/spref_medialibrary.png", SPrefsMediaLibrary,
        "", SUBCAT_PLAYLIST_GENERAL},
    {N_("Network"), ACCESS_HELP, ":/prefsmenu/advprefs_codec.svg", SPrefsInputAndCodecs,
        "groupBox_2", SUBCAT_INPUT_ACCESS},
    {N_("Performance"), VDEC_HELP, ":/prefsmenu/advprefs_codec.svg", SPrefsInputAndCodecs,
        "groupBox_3|groupBox|groupBox_4", SUBCAT_INPUT_VCODEC},
    {N_("Recording"), SOUT_HELP, ":/prefsmenu/advprefs_sout.svg", SPrefsInputAndCodecs,
        "groupBox_4", SUBCAT_SOUT_GENERAL},
    {N_("Extensions"), AADVANCED_HELP, ":/prefsmenu/advprefs_extended.svg", -1,
        "", SUBCAT_ADVANCED_MISC}
};
static_assert( sizeof(preferenceGroups) / sizeof(preferenceGroups[0]) == SPrefsGroupMax );
}

#ifdef _WIN32
# include <vlc_charset.h>
# include <shobjidl.h>
#endif
#include <vlc_modules.h>

static struct {
    const char iso[6];
    const char name[34];

} const language_map[] = {
    { "auto",  N_("Auto") },
    { "en",    "American English" },
    { "ar",    "عربي" },
    { "bn",    "বাংলা" },
    { "pt_BR", "Português Brasileiro" },
    { "en_GB", "British English" },
    { "el",    "Νέα Ελληνικά" },
    { "bg",    "български език" },
    { "ca",    "Català" },
    { "zh_TW", "正體中文" },
    { "cs",    "Čeština" },
    { "cy",    "Cymraeg" },
    { "da",    "Dansk" },
    { "nl",    "Nederlands" },
    { "fi",    "Suomi" },
    { "et",    "eesti keel" },
    { "eu",    "Euskara" },
    { "fr",    "Français" },
    { "ga",    "Gaeilge" },
    { "gd",    "Gàidhlig" },
    { "gl",    "Galego" },
    { "ka",    "ქართული" },
    { "de",    "Deutsch" },
    { "he",    "עברית" },
    { "hr",    "hrvatski" },
    { "hu",    "Magyar" },
    { "hy",    "հայերեն" },
    { "is",    "íslenska" },
    { "id",    "Bahasa Indonesia" },
    { "it",    "Italiano" },
    { "ja",    "日本語" },
    { "ko",    "한국어" },
    { "lt",    "lietuvių" },
    { "mn",    "Монгол хэл" },
    { "ms",    "Melayu" },
    { "nb",    "Bokmål" },
    { "nn",    "Nynorsk" },
    { "kk",    "Қазақ тілі" },
    { "km",    "ភាសាខ្មែរ" },
    { "ne",    "नेपाली" },
    { "oc",    "Occitan" },
    { "fa",    "فارسی" },
    { "pl",    "Polski" },
    { "pt_PT", "Português" },
    { "pa",    "ਪੰਜਾਬੀ" },
    { "ro",    "Română" },
    { "ru",    "Русский" },
    { "zh_CN", "简体中文" },
    { "si",    "සිංහල" },
    { "sr",    "српски" },
    { "sk",    "Slovensky" },
    { "sl",    "slovenščina" },
    { "ckb",   "کوردیی سۆرانی" },
    { "es",    "Español" },
    { "sv",    "Svenska" },
    { "te",    "తెలుగు" },
    { "tr",    "Türkçe" },
    { "uk",    "украї́нська мо́ва" },
    { "vi",    "tiếng Việt" },
    { "wa",    "Walon" }
};

static int getDefaultAudioVolume(const char *aout)
{
    if (!strcmp(aout, "") || !strcmp(aout, "any"))
#ifdef _WIN32
        /* All Windows aouts, that can be selected automatically, handle volume
         * saving. In case of automatic mode, we'll save the last volume for
         * every modules. Therefore, all volumes variable we be the same and we
         * can use the first one (mmdevice). */
        return config_GetFloat("mmdevice-volume") * 100.f + .5f;
#else
        return -1;
#endif

    /* Note: For hysterical raisins, this is sorted by decreasing priority
     * order (then alphabetical order). */
    if (!strcmp(aout, "pulse"))
        return -1;

#ifdef __linux__
    if (!strcmp(aout, "alsa") && module_exists("alsa"))
        return cbrtf(config_GetFloat("alsa-gain")) * 100.f + .5f;
#endif
#ifdef _WIN32
    if (!strcmp(aout, "mmdevice"))
        return config_GetFloat("mmdevice-volume") * 100.f + .5f;
#endif
#ifdef __APPLE__
    if (!strcmp(aout, "auhal") && module_exists("auhal"))
        return (config_GetFloat("auhal-volume") * 100.f + .5f)
                 / AOUT_VOLUME_DEFAULT;
#endif

    if (!strcmp(aout, "jack"))
        return cbrtf(config_GetFloat("jack-gain")) * 100.f + 0.5f;

#ifdef __OS2__
    if (!strcmp(aout, "kai"))
        return cbrtf(config_GetFloat("kai-gain")) * 100.f + .5f;
#endif
#ifdef _WIN32
    if (!strcmp(aout, "waveout"))
        return config_GetFloat("waveout-volume") * 100.f + .5f;
#endif

    return -1;
}

static const QString styleSettingsKey = QStringLiteral("MainWindow/QtStyle");

class PropertyResetter
{
public:
    PropertyResetter(QWidget *control, const char * property)
        : m_control {control}
        , m_property {property}
        , m_initialValue {m_control->property(property)}
    {
    }

    void reset()
    {
        bool success = m_control->setProperty(m_property.data(), m_initialValue);
        vlc_assert(success);
    }

private:
    QWidget *m_control;
    const QByteArray m_property;
    const QVariant m_initialValue;
};

/*********************************************************************
 * The List of categories
 *********************************************************************/
SPrefsCatList::SPrefsCatList( qt_intf_t *_p_intf, QWidget *_parent ) :
                                  QWidget( _parent ), p_intf( _p_intf )
{
    QVBoxLayout *layout = new QVBoxLayout();
    setObjectName( QStringLiteral("preferencesSidebar") );

    /* Use autoExclusive buttons and a mapper as QButtonGroup can't
       set focus (keys) when it manages the buttons's exclusivity.
       See QT bugs 131 & 816 and QAbstractButton's source code. */
    QSignalMapper *mapper = new QSignalMapper( layout );
    connect( mapper, &QSignalMapper::mappedInt, this, &SPrefsCatList::switchPanel );
    qreal dpr = devicePixelRatioF();

    const char *iconNames[] = {"general", "interface", "privacy", "controls", "playback", "video",
        "audio", "subtitles", "library", "network", "performance", "recording", "extensions"};
    auto addCategory = [&]( QString label, QString ltooltip, int numb) {
        QToolButton * button = new QToolButton( this );
        /* Scale icon to non native size outside of toolbutton to avoid widget size */
        /* computation using native size */
        QIcon icon;
        for( bool active : {false, true} )
        {
            QPixmap scaled = QPixmap( QStringLiteral(":/redesign/icons/settings-") + QLatin1String(iconNames[numb]) +
                                      (active ? QStringLiteral("-active.svg") : QStringLiteral(".svg")) )
                  .scaledToHeight( ICON_HEIGHT * dpr, Qt::SmoothTransformation );
            if( numb == SPrefsGroupVideo || numb == SPrefsGroupLibrary || numb == SPrefsGroupNetwork )
                scaled = scaled.transformed( QTransform().scale(-1, 1) );
            scaled.setDevicePixelRatio( dpr );
            icon.addPixmap( scaled, QIcon::Normal, active ? QIcon::On : QIcon::Off );
            icon.addPixmap( scaled, QIcon::Active, active ? QIcon::On : QIcon::Off );
        }
        button->setIcon( icon );
        button->setText( label );
        button->setToolTip( ltooltip );
        button->setToolButtonStyle( Qt::ToolButtonTextBesideIcon );
        button->setIconSize( QSize( ICON_WIDTH, ICON_HEIGHT ) );
        button->setFixedHeight( 40 );
        button->setProperty( "preferencesCategory", numb );
        button->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
        button->setAutoRaise( true );
        button->setCheckable( true );
        button->setAutoExclusive( true );
        connect( button, &QToolButton::clicked, mapper, QOverload<>::of(&QSignalMapper::map) );
        mapper->setMapping( button, numb );
        layout->addWidget( button );
    };

    for( int i = 0; i < SPrefsGroupMax; ++i )
    {
        // Section labels are exact strings from Figma Global Settings 3046:9282.
        if( i == SPrefsGroupGeneral || i == SPrefsGroupPlayback || i == SPrefsGroupNetwork )
        {
            auto section = new QLabel( i == SPrefsGroupGeneral ? qtr("App") :
                                      i == SPrefsGroupPlayback ? qtr("Media") : qtr("System"), this );
            section->setObjectName( QStringLiteral("preferencesSection") );
            section->setContentsMargins( 10, 8, 0, 8 );
            section->setEnabled( false );
            layout->addWidget( section );
        }
        addCategory( qfut(preferenceGroups[i].title), qfut(preferenceGroups[i].help), i );
    }

    qobject_cast<QToolButton*>(mapper->mapping(SPrefsGroupGeneral))->setChecked(true);
    layout->addStretch();
    layout->setContentsMargins(6, 6, 6, 6);
    layout->setSpacing( 8 );

    setSizePolicy(QSizePolicy::Preferred,QSizePolicy::Expanding);
    setFixedWidth( 200 );
    setStyleSheet( QStringLiteral("QWidget#preferencesSidebar { border-radius: 6px; }"
        "QToolButton { text-align: left; padding: 4px; border: 0; border-radius: 2px; }") );
    setLayout( layout );
}

void SPrefsCatList::switchPanel( int i )
{
    emit currentItemChanged( i );
}

void SPrefsCatList::setCategoryVisible( int category, bool visible )
{
    for( auto button : findChildren<QToolButton *>() )
        if( button->property("preferencesCategory").toInt() == category )
            button->setVisible( visible );
}

void SPrefsCatList::setCurrentCategory( int category )
{
    for( auto button : findChildren<QToolButton *>() )
        if( button->property("preferencesCategory").toInt() == category )
        {
            button->setChecked( true );
            switchPanel( category );
            return;
        }
}

QString SPrefsCatList::groupTitle( int group )
{
    return qfut( preferenceGroups[group].title );
}

int SPrefsCatList::groupPanel( int group )
{
    return preferenceGroups[group].panel;
}

int SPrefsCatList::groupSubcategory( int group )
{
    return preferenceGroups[group].advanced;
}

QStringList SPrefsCatList::groupSections( int group )
{
    return QString::fromLatin1( preferenceGroups[group].sections ).split('|', Qt::SkipEmptyParts);
}

bool SPrefsPanel::groupContains( QWidget *widget, int group ) const
{
    for( QWidget *ancestor = widget; ancestor && ancestor != m_formPanel; ancestor = ancestor->parentWidget() )
        if( ancestor->property("preferencesGroup").isValid() )
            return ancestor->property("preferencesGroup").toInt() == group;
    auto sections = SPrefsCatList::groupSections( group );
    if( group == SPrefsGroupLibrary && number == SPrefsInterface )
        sections = {QStringLiteral("PlaylistAndInstancesBox")};
    if( sections.isEmpty() )
        return true;

    QWidget *section = nullptr;
    bool record_option = false;
    bool appearance_option = false;
    const QStringList appearanceNames = {"stylesLabel", "stylesCombo",
        "colorSchemeLabel", "colorSchemeComboBox", "scaleFactorLabel", "intfScaleFactorSpinBox",
        "intfScaleFactorSlider"};
    for( QWidget *ancestor = widget; ancestor && ancestor != m_formPanel; ancestor = ancestor->parentWidget() )
    {
        if( qobject_cast<QGroupBox *>(ancestor) )
            section = ancestor;
        record_option |= ancestor->property("preferenceOptionName").toString() == "input-record-path" ||
                         ancestor->objectName() == "recordLabel" || ancestor->objectName() == "recordBrowse";
        appearance_option |= appearanceNames.contains( ancestor->objectName() );
    }
    if( !section || !sections.contains(section->objectName()) )
        return false;
    if( number == SPrefsInterface && section->objectName() == "LooknfeelBox" )
    {
        if( group == SPrefsGroupGeneral )
            return widget == section || appearance_option;
        if( group == SPrefsGroupInterface )
            return !appearance_option;
    }
    if( number == SPrefsInputAndCodecs && section->objectName() == "groupBox_4" )
    {
        if( group == SPrefsGroupRecording )
            return widget == section || record_option;
        if( group == SPrefsGroupPerformance && record_option )
            return false;
    }
    return true;
}

void SPrefsPanel::ensureGroupOptions( int group )
{
    if( m_loadedGroups.contains(group) )
        return;
    m_loadedGroups.insert( group );
    QStringList names;
    // Promote existing options into their transcript groups; no keys/defaults are added.
    switch( group )
    {
        case SPrefsGroupGeneral: names = {"qt-accent-color", "qt-error-dialogs", "qt-verbose",
            "file-logging", "logfile", "log-verbose", "qt-opacity", "logmode", "stats"}; break;
        case SPrefsGroupInterface: names = {"qt-fs-opacity", "qt-name-in-title", "qt-fullscreen-screennumber",
            "qt-start-minimized", "qt-close-to-system-tray"}; break;
        case SPrefsGroupPrivacy: names = {"restore-playback-states"}; break;
        case SPrefsGroupPlayback: names = {"rate", "playlist-autostart", "repeat", "loop", "random",
            "play-and-exit", "input-fast-seek", "start-time", "stop-time"}; break;
        case SPrefsGroupControls: names = {"extrashort-jump-size", "short-jump-size", "medium-jump-size", "long-jump-size"}; break;
        case SPrefsGroupAudio: names = {"audio-track", "audio-desync", "volume-step", "audio-replay-gain-preamp",
            "audio-filter"}; break;
        case SPrefsGroupVideo: names = {"hue", "brightness", "contrast", "saturation", "gamma", "crop",
            "zoom", "video-on-top", "align", "snapshot-width", "snapshot-height", "snapshot-preview",
            "video-filter", "video-splitter"}; break;
        case SPrefsGroupSubtitles: names = {"freetype-bold", "freetype-opacity", "freetype-shadow-opacity", "freetype-shadow-color", "freetype-shadow-angle",
            "freetype-shadow-distance", "freetype-outline-opacity", "freetype-background-color", "freetype-background-opacity", "sub-delay",
            "osd", "osd-timeout", "video-title-timeout"}; break;
        case SPrefsGroupLibrary: names = {"recursive", "ignore-filetypes", "show-hiddenfiles"}; break;
        case SPrefsGroupNetwork: names = {"http-user-agent", "http-referrer", "http-proxy-pwd",
            "gnutls-system-trust", "gnutls-priorities", "file-caching", "disc-caching", "network-caching", "live-caching"}; break;
        case SPrefsGroupPerformance: names = {"avcodec-threads", "drop-late-frames", "high-priority",
            "clock-synchro", "clock-jitter", "cr-average"}; break;
        case SPrefsGroupRecording: names = {"input-record-native", "sout-audio", "sout-video", "sout-spu",
            "sout-keep", "sout-all", "sout-mux-caching"}; break;
        default: return;
    }
    QGroupBox *advanced = nullptr;
    QGridLayout *layout = nullptr;
    bool newSection = true;
    int row = 0;
    const auto finishSection = [&]() {
        if( !advanced )
            return;
        if( row == 0 )
        {
            delete advanced;
            return;
        }
        for( auto label : advanced->findChildren<QLabel *>() )
            label->setWordWrap( true );
        for( auto widget : advanced->findChildren<QWidget *>() )
            if( qobject_cast<QLineEdit *>(widget) || qobject_cast<QComboBox *>(widget) ||
                qobject_cast<QAbstractSpinBox *>(widget) || widget->property("preferenceOptionName").isValid() )
                if( !widget->property("preferenceToggleRow").toBool() )
                    {
                    widget->setMaximumWidth( 320 );
                    widget->setMinimumHeight( 36 );
                    }
        layout->setColumnStretch( 0, 1 );
        layout->setContentsMargins( 0, 0, 0, 0 );
        layout->setVerticalSpacing( 10 );
        advanced->setSizePolicy( QSizePolicy::Expanding, QSizePolicy::Maximum );
        if( group == SPrefsGroupAudio ) normalizePreferenceRows( layout, advanced );
        if( newSection ) m_formPanel->layout()->addWidget( advanced );
        advanced->show(); // Lazy panels may not yet be current in their stack.
    };
    const auto startSection = [&](const QString &title) {
        finishSection();
        if( group == SPrefsGroupGeneral )
        {
            auto box = title == qtr("Appearance") ? m_appearance
                       : title == qtr("Advanced") ? m_appearanceAdvanced : nullptr;
            if( box )
            {
                advanced = box;
                layout = qobject_cast<QGridLayout *>(box->layout());
                row = layout->rowCount();
                newSection = false;
                return;
            }
        }
        if( (group == SPrefsGroupAudio || group == SPrefsGroupSubtitles) && !title.isEmpty() && title != qtr("Advanced") )
            for( auto box : m_formPanel->findChildren<QGroupBox *>() )
                if( box->title() == title && groupContains(box, group) )
                    if( auto existing = qobject_cast<QGridLayout *>(box->layout()) )
                    {
                        advanced = box;
                        layout = existing;
                        row = existing->rowCount();
                        newSection = false;
                        return;
                    }
        newSection = true;
        advanced = new QGroupBox( title, m_formPanel );
        advanced->setProperty( "preferencesGroup", group );
        advanced->setProperty( "preferencesAdvanced", title == qtr("Advanced") );
        if( title.isEmpty() )
            advanced->setStyleSheet( QStringLiteral("QGroupBox { margin-top: 0; padding: 0; }") );
        layout = new QGridLayout( advanced );
        row = 0;
    };
    // Section names are published by the corresponding 13 Figma settings frames.
    const auto sectionFor = [group](const QString &name) -> QString {
        switch( group )
        {
            case SPrefsGroupGeneral:
                if( name == "qt-accent-color" ) return qtr("Appearance");
                if( name == "qt-error-dialogs" ) return qtr("Startup");
                if( name == "qt-verbose" || name == "file-logging" || name == "logfile" || name == "log-verbose" ) return qtr("Diagnostics");
                break;
            case SPrefsGroupInterface:
                if( name == "qt-name-in-title" || name == "qt-fullscreen-screennumber" ) return qtr("Window");
                if( name == "qt-start-minimized" || name == "qt-close-to-system-tray" ) return qtr("Notifications and System Tray");
                break;
            case SPrefsGroupPlayback:
                if( name == "rate" || name == "playlist-autostart" ) return qtr("Startup");
                if( name == "repeat" || name == "loop" || name == "random" || name == "play-and-exit" ) return qtr("Order");
                if( name == "input-fast-seek" ) return qtr("Seeking");
                break;
            case SPrefsGroupControls: return qtr("Skip Amounts");
            case SPrefsGroupAudio:
                if( name == "audio-track" || name == "audio-desync" ) return qtr("Tracks");
                if( name == "volume-step" ) return qtr("Volume");
                if( name == "audio-replay-gain-preamp" ) return qtr("Loudness");
                if( name == "audio-filter" ) return qtr("Effects");
                break;
            case SPrefsGroupVideo:
                if( name == "hue" || name == "brightness" || name == "contrast" || name == "saturation" || name == "gamma" ) return qtr("Picture");
                if( name == "crop" || name == "zoom" || name == "align" ) return qtr("Framing");
                if( name.startsWith("snapshot-") ) return qtr("Snapshots");
                break;
            case SPrefsGroupSubtitles:
                if( name.startsWith("freetype-") ) return qtr("Appearance");
                if( name == "sub-delay" ) return qtr("Timing");
                if( name == "osd" || name == "osd-timeout" || name == "video-title-timeout" ) return qtr("On-Screen Messages");
                break;
            case SPrefsGroupLibrary:
                if( name == "recursive" || name == "show-hiddenfiles" ) return qtr("Opening Files");
                break;
            case SPrefsGroupNetwork:
                if( name.endsWith("-caching") ) return qtr("Buffering");
                if( name == "http-proxy-pwd" ) return qtr("Proxy");
                if( name.startsWith("gnutls-") ) return qtr("Security");
                break;
            case SPrefsGroupPerformance:
                if( name == "avcodec-threads" ) return qtr("Decoding");
                if( name == "drop-late-frames" || name == "high-priority" ) return qtr("Smooth Playback");
                break;
            case SPrefsGroupRecording:
                if( name == "input-record-native" ) return qtr("Recording");
                if( name == "sout-audio" || name == "sout-video" || name == "sout-spu" || name == "sout-keep" ) return qtr("Streaming");
                break;
        }
        return qtr("Advanced");
    };
    QString currentSection;
    bool firstSection = true;
    QSet<QString> boundOptions;
    for( auto existing : controls )
        if( existing->getName() )
            boundOptions.insert( QString::fromLatin1(existing->getName()) );
    for( const QString &name : names )
        if( !boundOptions.contains(name) )
        if( auto option = config_FindConfig(qtu(name)) )
        {
            const auto section = sectionFor( name );
            if( firstSection || section != currentSection )
            {
                startSection( section );
                currentSection = section;
                firstSection = false;
            }
            if( name == QStringLiteral("qt-accent-color") )
            {
                // Keep the original arbitrary QColor input in this group's
                // Advanced section; General's basic row uses Figma's swatches.
                auto raw = m_appearanceAdvanced ? m_appearanceAdvanced : advanced;
                auto rawLayout = qobject_cast<QGridLayout *>(raw->layout());
                const int rawRow = rawLayout->rowCount();
                auto label = new QLabel( qfut(option->psz_text), raw );
                auto value = new QLineEdit( raw );
                rawLayout->addWidget( label, rawRow, 0 );
                rawLayout->addWidget( value, rawRow, 10 );
                configGeneric<StringConfigControl>( "qt-accent-color", label, value );
                auto caption = new QLabel(qtr("Accent color"),advanced); // Figma 3046:9328.
                auto selector = createAccentColorSelector(advanced,value);
                layout->addWidget(caption,row,0);
                layout->addWidget(selector,row++,10);
                addHelp(selector,option,caption);
                continue;
            }
            ConfigControl *control = nullptr;
            QDoubleSpinBox *opacity = nullptr;
            if( name.startsWith("freetype-") && name.endsWith("-opacity") && option->min.i==0 && option->max.i==255 )
            {
                auto label = new QLabel(qfut(option->psz_text),advanced);
                opacity = new QDoubleSpinBox(advanced);
                layout->addWidget(label,row,0);
                layout->addWidget(opacity,row,10);
                control = new OpacityConfigControl(option,label,opacity);
                addHelp(opacity,option,label);
            }
            else if( name == "audio-filter" )
            {
                control = new StringConfigControl( option, advanced );
                control->insertInto( layout, row );
            }
            else
                control = ConfigControl::createControl(option, advanced, layout, row);
            if( control )
            {
                controls.append( control );
                if( name == "freetype-background-opacity" || name == "freetype-shadow-opacity" )
                {
                    if( opacity )
                    {
                        auto toggle = name == "freetype-background-opacity"
                            ? m_subtitlesUI.backgroundCheck : m_subtitlesUI.shadowCheck;
                        connect(opacity,qOverload<double>(&QDoubleSpinBox::valueChanged),toggle,
                                [toggle](double value){toggle->setChecked(value>0);});
                        connect(toggle,&QCheckBox::toggled,opacity,[opacity](bool enabled){
                            if(!enabled) opacity->setValue(0);
                            else if(opacity->value()==0) opacity->setValue(128.0*100.0/255.0);
                        });
                    }
                    else
                        if( auto item = layout->itemAtPosition(row, 10) )
                        if( auto field = qobject_cast<QSpinBox *>(item->widget()) )
                        {
                            auto toggle = name == "freetype-background-opacity"
                                ? m_subtitlesUI.backgroundCheck : m_subtitlesUI.shadowCheck;
                            // Both presentations edit the original opacity setting.
                            // Retain the existing toggle's 128 value when enabling
                            // a fully transparent background/shadow.
                            connect( field, qOverload<int>(&QSpinBox::valueChanged), toggle,
                                     [toggle](int value) { toggle->setChecked(value > 0); } );
                            connect( toggle, &QCheckBox::toggled, field, [field](bool enabled) {
                                if( !enabled ) field->setValue(0);
                                else if( field->value() == 0 ) field->setValue(128);
                            } );
                        }
                }
                // Couple new individual cache fields to the existing Custom/preset workflow.
                if( name.endsWith("-caching") && group == SPrefsGroupNetwork )
                    if( auto item = layout->itemAtPosition(row, 10) )
                    if( auto field = qobject_cast<QSpinBox *>(item->widget()) )
                    {
                        field->setSuffix( QStringLiteral(" ms") ); // Config option metadata specifies milliseconds.
                        connect( field, qOverload<int>(&QSpinBox::valueChanged), this, [this](int) {
                            m_inputCodecUI.cachingCombo->setCurrentIndex(m_inputCodecUI.cachingCombo->findData(CachingCustom));
                        } );
                        const int factor = name == "network-caching" ? 10 / 3 : 1;
                        connect( m_inputCodecUI.cachingCombo, qOverload<int>(&QComboBox::activated), field, [this, field, factor](int index) {
                            const int value = m_inputCodecUI.cachingCombo->itemData(index).toInt();
                            if( value )
                            {
                                QSignalBlocker guard( field );
                                field->setValue( value * factor );
                            }
                        } );
                    }
                if( name == "audio-filter" )
                    if( auto item = layout->itemAtPosition(row, 10) )
                    if( auto field = qobject_cast<QLineEdit *>(item->widget()) )
                    {
                        connect( field, &QLineEdit::textEdited, this, [this](const QString &value) {
                            qs_filter = value.split(':', Qt::SkipEmptyParts);
                            m_audioUI.volNormBox->setChecked(qs_filter.contains("normvol"));
                        } );
                        connect( m_audioUI.volNormBox, &QCheckBox::toggled, field, [field](bool enabled) {
                            auto filters = field->text().split(':', Qt::SkipEmptyParts);
                            filters.removeAll("normvol");
                            if( enabled ) filters.append("normvol");
                            field->setText(filters.join(':'));
                        } );
                        auto labelItem = layout->itemAtPosition(row, 0);
                        addHelp( field, option, labelItem ? qobject_cast<QLabel *>(labelItem->widget()) : nullptr );
                    }
                ++row;
            }
        }
    finishSection();
}

void SPrefsPanel::toggleGroupAdvanced()
{
    bool hasInlineOptions = false;
    for( auto box : m_formPanel->findChildren<QGroupBox *>() )
        hasInlineOptions |= box->property("preferencesGroup").toInt() == m_currentGroup &&
                            box->property("preferencesAdvanced").toBool();
    if( !hasInlineOptions )
    {
        // Every remaining option is still available in the original source category.
        emit advancedRequested();
        return;
    }
    if( m_expandedGroups.contains(m_currentGroup) )
        m_expandedGroups.remove(m_currentGroup);
    else
        m_expandedGroups.insert(m_currentGroup);
    showGroup( m_currentGroup );
}

void SPrefsPanel::setShortcutsOnly( bool only )
{
    m_shortcutsOnly = only;
    if( m_keySelector ) m_keySelector->setEditorVisible( only );
    if( m_shortcutsSummary ) m_shortcutsSummary->setVisible( !only );
    if( m_mouseSettings ) m_mouseSettings->setVisible( !only );
    if( m_advancedOptions ) m_advancedOptions->setVisible( !only );
    if( only )
        for( auto box : m_formPanel->findChildren<QGroupBox *>() )
            if( box->property("preferencesGroup").isValid() ) box->hide();
}

void SPrefsPanel::moveShortcutsSearchTo(QHBoxLayout *layout)
{
    if(m_keySelector) m_keySelector->moveSearchTo(layout);
}

void SPrefsPanel::editShortcuts()
{
    if( !m_keySelector ) return;
    QDialog dialog( this );
    dialog.setWindowTitle( qtr("Keyboard Shortcuts") );
    dialog.setObjectName( QStringLiteral("keyboardShortcutsDialog") );
    dialog.resize( 1048, 800 );
    auto shell = new QVBoxLayout( &dialog );
    shell->setContentsMargins(0,0,0,0);
    shell->setSpacing(0);
    auto header = new QWidget(&dialog);
    header->setObjectName(QStringLiteral("preferencesHeader"));
    header->setFixedHeight(96); // Figma2437:14832 combined title/search header.
    auto headerLayout = new QVBoxLayout(header);
    headerLayout->setContentsMargins(0,0,0,0);
    headerLayout->setSpacing(0);
    auto title = new QWidget(header);
    title->setFixedHeight(50);
    auto heading = new QHBoxLayout(title);
    heading->setContentsMargins(20,9,9,9);
    heading->addWidget(new QLabel(qtr("Keyboard Shortcuts"),title),1);
    auto close = new QToolButton(title);
    close->setIcon(QIcon(QStringLiteral(":/redesign/icons/settings-close.svg")));
    close->setIconSize(QSize(24,24));
    close->setFixedSize(32,32);
    close->setAccessibleName(qtr("Close"));
    connect(close,&QToolButton::clicked,&dialog,&QDialog::reject);
    heading->addWidget(close);
    headerLayout->addWidget(title);
    auto searchWidget = new QWidget(header);
    auto searchLayout = new QHBoxLayout(searchWidget);
    searchLayout->setContentsMargins(20,0,20,10);
    searchLayout->setSpacing(20);
    headerLayout->addWidget(searchWidget);
    shell->addWidget(header);
    auto body = new QWidget(&dialog);
    auto layout = new QGridLayout(body);
    layout->setContentsMargins(20,20,20,0);
    KeySelectorControl editor( &dialog );
    editor.copyKeysFrom( *m_keySelector );
    editor.insertInto( layout );
    editor.moveSearchTo(searchLayout);
    layout->setRowStretch(0,1);
    shell->addWidget(body,1);
    auto footerWidget = new QWidget(&dialog);
    footerWidget->setFixedHeight(72);
    auto footer = new QHBoxLayout(footerWidget);
    footer->setContentsMargins(20,20,20,20);
    auto cancel = new QPushButton( qtr("Cancel"), footerWidget );
    auto save = new QPushButton( qtr("Save"), footerWidget );
    cancel->setFixedSize( 100, 32 ); save->setFixedSize(100, 32);
    save->setDefault( true );
    connect( cancel, &QPushButton::clicked, &dialog, &QDialog::reject );
    connect( save, &QPushButton::clicked, &dialog, &QDialog::accept );
    footer->addWidget( cancel ); footer->addStretch(); footer->addWidget( save );
    shell->addWidget(footerWidget);
    if( dialog.exec() == QDialog::Accepted )
    {
        // Keep edits in the same preference transaction; the parent Save applies them.
        m_keySelector->copyKeysFrom( editor );
        m_shortcutsStatus->setText( m_keySelector->matchesDefaults() ? qtr("Defaults") : qtr("Custom") );
    }
}

void SPrefsPanel::showGroup( int group )
{
    m_currentGroup = group;
    ensureGroupOptions( group );
    m_panelTitle->setText( SPrefsCatList::groupTitle(group) );
    if( m_advancedOptions )
    {
        m_advancedOptions->setChecked( m_expandedGroups.contains(group) );
        if( auto layout = qobject_cast<QVBoxLayout *>(m_formPanel->layout()) )
        {
            layout->removeWidget( m_advancedOptions );
            QList<QWidget *> advancedSections;
            for( int i = 0; i < layout->count(); ++i )
                if( auto widget = layout->itemAt(i)->widget(); widget &&
                    widget->property("preferencesAdvanced").toBool() && groupContains(widget,group) )
                    advancedSections.append(widget);
            for(auto section : advancedSections) layout->removeWidget(section);
            // Keep every basic row first, followed by this group's complete
            // inline advanced section; source widgets remain the same objects.
            layout->addWidget(m_advancedOptions);
            for(auto section : advancedSections) layout->addWidget(section);
        }
    }
    for( auto box : m_formPanel->findChildren<QGroupBox *>() )
    {
        bool nested = false;
        for( QWidget *parent = box->parentWidget(); parent && parent != m_formPanel; parent = parent->parentWidget() )
            nested |= qobject_cast<QGroupBox *>(parent) != nullptr;
        if( nested )
            continue;
        if( !m_groupVisibility.contains(box) )
            m_groupVisibility.insert( box, !box->isHidden() );
        box->setVisible( m_groupVisibility.value(box) && groupContains(box, group) &&
            (!box->property("preferencesAdvanced").toBool() || m_expandedGroups.contains(group)) );
    }

    if( number == SPrefsInputAndCodecs )
    {
        // Separate recording destination from AVI repair/preload without copying controls.
        auto rowContainer = []( QWidget *widget ) {
            QWidget *parent = widget->parentWidget();
            return parent && parent->property("preferenceOptionName").isValid() ? parent : widget;
        };
        const auto rows = {static_cast<QWidget *>(m_inputCodecUI.recordLabel),
            rowContainer(m_inputCodecUI.recordPath), static_cast<QWidget *>(m_inputCodecUI.recordBrowse),
            static_cast<QWidget *>(m_inputCodecUI.aviLabel), rowContainer(m_inputCodecUI.AviRepair),
            rowContainer(m_inputCodecUI.mkvPreloadBox)};
        for( QWidget *widget : rows )
        {
            if( !m_groupVisibility.contains(widget) )
                m_groupVisibility.insert( widget, !widget->isHidden() );
            widget->setVisible( m_groupVisibility.value(widget) && groupContains(widget, group) );
        }
    }
    else if( number == SPrefsInterface )
    {
        // Section titles and compact rows follow the corresponding Figma pages.
        m_interfaceUI.LooknfeelBox->setTitle( group == SPrefsGroupGeneral ? qtr("Appearance") : qtr("Window") );
        const QStringList fields = {"LooknfeelSelection", "toolbarEditor", "resizingBox",
            "notificationCombo", "titleBarCheckBox", "embedVideo", "autoRaiseComboBox",
            "notificationComboLabel", "systrayBox", "stylesLabel", "intfScaleFactorSpinBox",
            "colorSchemeLabel", "minimalviewBox", "autoRaiseLabel", "stylesCombo",
            "intfScaleFactorSlider", "pauseMinimizedBox", "scaleFactorLabel", "menuBarCheck",
            "fsController", "colorSchemeComboBox", "pinVideoControlsCheckbox"};
        for( const QString &field : fields )
            if( auto control = m_formPanel->findChild<QWidget *>(field) )
            {
                QWidget *widget = control->parentWidget()->property("preferenceOptionName").isValid()
                    ? control->parentWidget() : control;
                if( !m_groupVisibility.contains(widget) )
                    m_groupVisibility.insert( widget, !widget->isHidden() );
                widget->setVisible( m_groupVisibility.value(widget) && groupContains(control, group) );
            }
    }
    if( number == SPrefsHotkeys ) setShortcutsOnly( m_shortcutsOnly );
}

bool SPrefsPanel::matches( const QString &text, int group )
{
    ensureGroupOptions( group );
    if( text.isEmpty() || SPrefsCatList::groupTitle(group).contains(text, Qt::CaseInsensitive) )
        return true;

    // Search the same published labels/help users see in each existing panel.
    for( auto widget : findChildren<QWidget *>() )
    {
        if( !groupContains(widget, group) )
            continue;
        QTextDocument description;
        description.setHtml( widget->toolTip() );
        if( description.toPlainText().contains( text, Qt::CaseInsensitive ) )
            return true;
        if( auto label = qobject_cast<QLabel *>( widget ) )
        {
            if( label->text().contains( text, Qt::CaseInsensitive ) )
                return true;
        }
        else if( auto button = qobject_cast<QAbstractButton *>( widget ) )
        {
            if( button->text().contains( text, Qt::CaseInsensitive ) )
                return true;
        }
        else if( auto combo = qobject_cast<QComboBox *>( widget ) )
        {
            for( int i = 0; i < combo->count(); ++i )
                if( combo->itemText( i ).contains( text, Qt::CaseInsensitive ) )
                    return true;
        }
        else if( auto tree = qobject_cast<QTreeWidget *>( widget ) )
        {
            for( QTreeWidgetItemIterator item(tree); *item; ++item )
                for( int column = 0; column < tree->columnCount(); ++column )
                    if( (*item)->text(column).contains( text, Qt::CaseInsensitive ) )
                        return true;
        }
    }
    return false;
}

/*********************************************************************
 * The Panels
 *********************************************************************/

template<typename ControlType, typename WidgetType>
void SPrefsPanel::configGeneric(const char* option, QLabel* label, WidgetType* control)
{
    module_config_t* p_config =  config_FindConfig( option );
    if( p_config )
    {
        auto configcontrol =  new ControlType(p_config, label, control );
        controls.append( configcontrol );
        addHelp( control, p_config, label );
    }
    else
    {
        control->setEnabled( false );
        if( label )
            label->setEnabled( false );
    }
}

template<typename ControlType, typename WidgetType>
void SPrefsPanel::configGenericNoUi(const char* option, QLabel* label, WidgetType* control)
{
    module_config_t* p_config =  config_FindConfig( option );
    if( p_config )
    {
        auto configcontrol =  new ControlType(p_config, label, control );
        controls.append( configcontrol );
        addHelp( control, p_config, label );
    }
    else
    {
        control->setVisible( false );
        if( label )
            label->setEnabled( false );
    }
}

template<typename ControlType>
void SPrefsPanel::configGenericFile(const char* option, QLabel* label, QLineEdit* control, QPushButton* button)
{
    module_config_t* p_config =  config_FindConfig( option );
    if( p_config )
    {
        auto configcontrol =  new ControlType(p_config, label, control, button );
        controls.append( configcontrol );
        addHelp( control, p_config, label );
    }
    else
    {
        control->setEnabled( false );
        if( label )
            label->setEnabled( false );
        if( button )
            button->setEnabled( false );
    }
}

void SPrefsPanel::configBool(const char* option, QAbstractButton* control)
{
    module_config_t* p_config =  config_FindConfig( option );
    if( p_config )
    {
        auto configcontrol =  new BoolConfigControl(p_config, nullptr, control );
        controls.append( configcontrol );
        addHelp( control, p_config );
    }
    else
    {
        control->setEnabled( false );
    }
}

namespace {
class PreferenceHelpButton final : public QToolButton
{
public:
    PreferenceHelpButton( QWidget *control, QWidget *parent )
        : QToolButton( parent ), m_control( control )
    {
        control->installEventFilter( this );
        setHidden( control->isHidden() );
    }

protected:
    bool eventFilter( QObject *watched, QEvent *event ) override
    {
        if( watched == m_control &&
            (event->type() == QEvent::ShowToParent || event->type() == QEvent::HideToParent) )
            setHidden( m_control->isHidden() );
        return QToolButton::eventFilter( watched, event );
    }

private:
    QWidget *m_control;
};
}

void SPrefsPanel::addHelp( QWidget *control, module_config_t *option, QLabel *label )
{
    QWidget *parent = control->parentWidget();
    QLayout *layout = parent ? parent->layout() : nullptr;
    if( !layout )
        return;
    auto container = new QWidget( parent );
    container->setProperty( "preferenceOptionName", QString::fromLatin1(option->psz_name) );
    QLayoutItem *item = layout->replaceWidget( control, container );
    if( !item )
    {
        delete container;
        return;
    }
    delete item;
    auto row = new QHBoxLayout( container );
    row->setContentsMargins( 0, 0, 0, 0 );
    row->setSpacing( 10 );
    const bool toggle = qobject_cast<QCheckBox *>(control) != nullptr;
    container->setProperty( "preferenceToggleRow", toggle );
    if( toggle )
    {
        auto button = qobject_cast<QAbstractButton *>(control);
        auto caption = new QLabel( button->text(), container );
        caption->setWordWrap( true );
        caption->setBuddy( control );
        button->setAccessibleName( button->text() );
        button->setText( QString() );
        button->setFixedSize( 68, 32 );
        row->addWidget( caption );
    }
    else
        row->addWidget( control, 1 );
    auto help = new PreferenceHelpButton( control, container );
    help->setObjectName( QStringLiteral("preferenceInfo") );
    help->setIcon( QIcon(QStringLiteral(":/redesign/icons/settings-info.svg")) );
    help->setIconSize( QSize(18, 18) );
    help->setAccessibleName( qtr("Help") );
    // The rendered explanation is exactly the source module's option help.
    help->setToolTip( formatTooltip( qfut(option->psz_longtext && *option->psz_longtext
                                        ? option->psz_longtext : option->psz_text) ) );
    help->setAutoRaise( true );
    if( !toggle && label && !label->property("preferenceHelpAttached").toBool() &&
        label->parentWidget() && label->parentWidget()->layout() )
    {
        auto caption = new QWidget( label->parentWidget() );
        caption->setProperty( "preferenceOptionName", QString::fromLatin1(option->psz_name) );
        caption->setProperty( "preferenceCaptionRow", true );
        if( auto item = label->parentWidget()->layout()->replaceWidget(label, caption) )
        {
            delete item;
            label->setProperty( "preferenceHelpAttached", true );
            auto captionLayout = new QHBoxLayout( caption );
            captionLayout->setContentsMargins( 0, 0, 0, 0 );
            captionLayout->setSpacing( 10 );
            captionLayout->addWidget( label );
            captionLayout->addWidget( help );
            captionLayout->addStretch();
        }
        else
        {
            delete caption;
            row->addWidget( help );
        }
    }
    else
        row->addWidget( help );
    if( toggle )
    {
        row->addStretch();
        row->addWidget( control );
    }
    connect( help, &QToolButton::clicked, help, [help]() {
        showPreferenceHelp( help, help->toolTip() );
    } );
}

SPrefsPanel::SPrefsPanel( qt_intf_t *_p_intf, QWidget *_parent,
                          int _number ) : QWidget( _parent ), p_intf( _p_intf )
{
    module_config_t *p_config;
    ConfigControl *control;
    number = _number;
    lang = NULL;
    radioGroup = NULL;

    QVBoxLayout *panel_layout = new QVBoxLayout();
    QWidget *panel = new QWidget();
    m_formPanel = panel;
    panel_layout->setContentsMargins(0, 0, 0, 0);

    // Title Label
    QLabel *panel_label = new QLabel;
    m_panelTitle = panel_label;
    QFont labelFont = QApplication::font();
    labelFont.setPixelSize( 16 );
    panel_label->setFont( labelFont );
    panel_label->hide(); // Figma places the category title in the shared header.

    // Title <hr>
    QFrame *title_line = new QFrame;
    title_line->setFrameShape(QFrame::HLine);
    title_line->setFrameShadow(QFrame::Sunken);
    title_line->hide();

    QFont italicFont = QApplication::font();
    italicFont.setItalic( true );

    switch( number )
    {
        /******************************
         * VIDEO Panel Implementation *
         ******************************/
        case SPrefsVideo:
        {
            auto& ui = m_videoUI;
            ui.setupUi( panel );
            panel_label->setText( qtr("Video Settings") );

            configBool( "video", ui.enableVideo );
            ui.videoZone->setEnabled( ui.enableVideo->isChecked() );
            connect( ui.enableVideo, &QCheckBox::toggled,
                     ui.videoZone, &QWidget::setEnabled );

            configBool( "fullscreen", ui.fullscreen );
            configBool( "video-deco", ui.windowDecorations );
            configGeneric<StringListConfigControl>("vout", ui.voutLabel, ui.outputModule);

            ui.fullscreenScreenBox->addItem( qtr("Automatic"), -1 );
            int i_screenCount = 0;
            foreach( QScreen* screen, QGuiApplication::screens() )
            {
                ui.fullscreenScreenBox->addItem( screen->name(), i_screenCount );
                i_screenCount++;
            }
            p_config = config_FindConfig( "qt-fullscreen-screennumber" );
            if( p_config )
            {
                int i_defaultScreen = p_config->value.i + 1;
                if ( i_defaultScreen < 0 || i_defaultScreen > ( ui.fullscreenScreenBox->count() - 1 ) )
                    ui.fullscreenScreenBox->setCurrentIndex( 0 );
                else
                    ui.fullscreenScreenBox->setCurrentIndex(p_config->value.i + 1);
            }

#ifdef _WIN32
            configBool( "directx-hw-yuv", ui.hwYUVBox );
#else
            ui.directXBox->setVisible( false );
#endif

#ifdef __OS2__
            configBool( "kva-fixt23", ui.kvaFixT23 );
            configGeneric<StringListConfigControl>( "kva-video-mode", ui.kvaVideoModeLabel,
                            ui.kvaVideoMode );
#else
            ui.kvaBox->setVisible( false );
#endif

            configGeneric<IntegerListConfigControl>( "deinterlace",  ui.deinterLabel, ui.deinterlaceBox );
            configGeneric<StringListConfigControl>( "deinterlace-mode", ui.deinterModeLabel, ui.deinterlaceModeBox );
            configGeneric<StringConfigControl>( "aspect-ratio", ui.arLabel, ui.arLine );

            configGenericFile<DirectoryConfigControl>( "snapshot-path",  ui.dirLabel,
                                 ui.snapshotsDirectory, ui.snapshotsDirectoryBrowse );
            configGeneric<StringConfigControl>( "snapshot-prefix", ui.prefixLabel, ui.snapshotsPrefix );
            configBool( "snapshot-sequential", ui.snapshotsSequentialNumbering );
            configGeneric<StringListConfigControl>( "snapshot-format", ui.formatLabel, ui.snapshotsFormat );

            break;
        }

        /******************************
         * AUDIO Panel Implementation *
         ******************************/
        case SPrefsAudio:
        {
            auto& ui = m_audioUI;
            ui.setupUi( panel );
            panel_label->setText( qtr("Audio Settings") );

            configBool( "audio", ui.enableAudio );
            ui.audioZone->setEnabled( ui.enableAudio->isChecked() );
            connect( ui.enableAudio, &QCheckBox::toggled,
                     ui.audioZone, &QWidget::setEnabled );

            /* Build if necessary */
            QGridLayout * outputAudioLayout = qobject_cast<QGridLayout *>(ui.outputAudioBox->layout());

            auto audioControl = [this, outputAudioLayout](QString key, const char* property) {
                QLabel* label = new QLabel( qtr( "Device:" ) );
                label->setMinimumSize(QSize(250, 0));
                outputAudioLayout->addWidget( label, outputAudioLayout->rowCount(), 0, 1, 1 );

                QComboBox* device = new QComboBox;
                label->setBuddy( device );
                device->setSizePolicy( QSizePolicy::Ignored, QSizePolicy::Preferred  );
                outputAudioLayout->addWidget( device, outputAudioLayout->rowCount() - 1, 1, 1, -1 );

                audioControlGroups[key] = AudioControlGroup(label, device);
                configGenericNoUi<StringListConfigControl>(property, label, device);
            };

//audioControlFile is only used for oss
#if !defined(_WIN32) && !defined( __OS2__ )
            auto audioControlFile = [this, outputAudioLayout](QString key, const char* property) {
                QLabel* label = new QLabel( qtr( "Device:" ) );
                label->setMinimumSize(QSize(250, 0));
                outputAudioLayout->addWidget( label, outputAudioLayout->rowCount(), 0, 1, 1 );

                QHBoxLayout* hboxLayout = new QHBoxLayout;
                QLineEdit* device = new QLineEdit;
                label->setBuddy( device ); \
                hboxLayout->addWidget( device ); \
                QPushButton * browse = new QPushButton( qtr( "Browse..." ) );
                hboxLayout->addWidget( browse );
                outputAudioLayout->addLayout( hboxLayout, outputAudioLayout->rowCount() - 1, 1, 1, 1, Qt::AlignLeft );

                audioControlGroups[key] = AudioControlGroup(label, device, browse);
                configGenericFile<FileConfigControl>(property, label, device, browse);
            };
#endif

#ifdef _WIN32
            audioControl("directx", "directx-audio-device" );
            audioControl("waveout", "waveout-audio-device" );

#elif defined( __OS2__ )
            audioControl("kai", "kai-audio-device" );
#else
            if( module_exists( "alsa" ) )
                audioControl("alsa", "alsa-audio-device" );

            if( module_exists( "oss" ) )
                audioControlFile("oss", "oss-audio-device" );
#endif

#ifdef _WIN32
            audioControl("mmdevice", "mmdevice-audio-device" );

            configGeneric<IntegerListConfigControl>( "mmdevice-passthrough",
                                                     ui.mmdevicePassthroughLabel, ui.mmdevicePassthroughBox );
#else
            ui.mmdevicePassthroughLabel->setVisible( false );
            ui.mmdevicePassthroughBox->setVisible( false );
#endif

            int i_max_volume = config_GetInt( "qt-max-volume" );

            /* Audio Options */
            ui.volumeValue->setMaximum( i_max_volume );
            ui.defaultVolume->setMaximum( i_max_volume );

            connect( ui.defaultVolume, &QSlider::valueChanged,
                     this, &SPrefsPanel::updateAudioVolume );

            ui.defaultVolume_zone->setEnabled( ui.resetVolumeCheckbox->isChecked() );
            connect( ui.resetVolumeCheckbox, &QCheckBox::toggled,
                     ui.defaultVolume_zone, &QWidget::setEnabled );

            configGeneric<StringConfigControl>( "audio-language" , ui.langLabel, ui.preferredAudioLanguage );

            configBool( "spdif", ui.spdifBox );
            if( !config_FindConfig("spdif") ) ui.spdifBox->hide();

            if( !module_exists( "normvol" ) )
                ui.volNormBox->setEnabled( false );
            else
            {
                configGeneric<FloatConfigControl>( "norm-max-level" , nullptr, ui.volNormSpin );
            }
            configGeneric<StringListConfigControl>( "audio-replay-gain-mode", ui.replayLabel,
                            ui.replayCombo );
            configGeneric<StringListConfigControl>( "audio-visual" , ui.visuLabel,
                            ui.visualisation);
            configBool( "audio-time-stretch", ui.autoscaleBox );

            /* Audio Output Specifics */
            configGeneric<StringListConfigControl>( "aout", ui.outputLabel, ui.outputModule );

            connect( ui.outputModule, QOverload<int>::of(&QComboBox::currentIndexChanged),
                     this, &SPrefsPanel::updateAudioOptions );

            /* File output exists on all platforms */
            configGenericFile<FileConfigControl>( "audiofile-file",  ui.fileLabel,
                                 ui.fileName, ui.fileBrowseButton );

            updateAudioOptions( ui.outputModule->currentIndex() );

            /* LastFM */
            if( module_exists( "audioscrobbler" ) )
            {
                configGeneric<StringConfigControl>( "lastfm-username", ui.lastfm_user_label,
                        ui.lastfm_user_edit );
                configGeneric<StringConfigControl>( "lastfm-password", ui.lastfm_pass_label,
                        ui.lastfm_pass_edit );

                if( config_ExistIntf( "audioscrobbler" ) )
                    ui.lastfm->setChecked( true );
                else
                    ui.lastfm->setChecked( false );

                ui.lastfm_zone->setVisible( ui.lastfm->isChecked() );

                connect( ui.lastfm, &QCheckBox::toggled, ui.lastfm_zone, &QWidget::setVisible );
                connect( ui.lastfm, &QtCheckboxChanged, this, &SPrefsPanel::lastfm_Changed );
            }
            else
            {
                ui.lastfm->hide();
                ui.lastfm_zone->hide();
            }

            /* Normalizer */
            connect( ui.volNormBox, &QCheckBox::toggled, ui.volNormSpin, &QDoubleSpinBox::setEnabled );

            char* psz = config_GetPsz( "audio-filter" );
            qs_filter = qfu( psz ).split( ':', Qt::SkipEmptyParts );

            free( psz );

            bool b_enabled = ( qs_filter.contains( "normvol" ) );
            ui.volNormBox->setChecked( b_enabled );
            ui.volNormSpin->setEnabled( b_enabled && ui.volNormBox->isEnabled() );

            /* Volume Label */
            updateAudioVolume( ui.defaultVolume->value() ); // First time init

            if( auto option = config_FindConfig("volume-save") ) addHelp( ui.resetVolumeCheckbox, option );
            if( auto option = config_FindConfig("audio-filter") ) addHelp( ui.volNormBox, option );
            if( module_exists("audioscrobbler") )
                if( auto option = config_FindConfig("extraintf") ) addHelp( ui.lastfm, option );
            for( auto box : ui.audioZone->findChildren<QGroupBox *>() )
                if( auto layout = qobject_cast<QGridLayout *>(box->layout()) )
                    normalizePreferenceRows( layout, box );

            break;
        }

        /*****************************************
         * INPUT AND CODECS Panel Implementation *
         *****************************************/
        case SPrefsInputAndCodecs:
        {
            auto& ui = m_inputCodecUI;
            ui.setupUi( panel );
            panel_label->setText( qtr("Input & Codecs Settings") );

            /* Disk Devices */
            {
                ui.DVDDeviceComboBox->setToolTip(
                    qtr( "If this property is blank, different values\n"
                         "for DVD, VCD, and CDDA are set.\n"
                         "You can define a unique one or configure them \n"
                         "individually in the advanced preferences." ) );
                bool have_cdda = module_exists( "cdda" );
                char *dvd_discpath = config_GetPsz( "dvd" );
                char *vcd_discpath = config_GetPsz( "vcd" );
                char *cdda_discpath = have_cdda ? config_GetPsz( "cd-audio" ) : nullptr;
                if( dvd_discpath && vcd_discpath && ( !have_cdda || cdda_discpath ) )
                {
                    if( !strcmp( dvd_discpath, vcd_discpath ) &&
                        ( !have_cdda || !strcmp( cdda_discpath, dvd_discpath ) ) )
                    {
                        ui.DVDDeviceComboBox->setEditText( qfu( dvd_discpath ) );
                    }
                }
                free( cdda_discpath );
                free( dvd_discpath );
                free( vcd_discpath );
            }
#if !defined( _WIN32 ) && !defined( __OS2__)
            QStringList DVDDeviceComboBoxStringList = QStringList();
            DVDDeviceComboBoxStringList
                    << "dvd*" << "scd*" << "sr*" << "sg*" << "cd*";
            ui.DVDDeviceComboBox->addItems( QDir( "/dev/" )
                    .entryList( DVDDeviceComboBoxStringList, QDir::System )
                    .replaceInStrings( QRegularExpression(QStringLiteral("^")), "/dev/" )
            );
#endif
            configGeneric<StringConfigControl>( "dvd", ui.DVDLabel,
                            ui.DVDDeviceComboBox->lineEdit() );
            configGenericFile<DirectoryConfigControl>( "input-record-path",  ui.recordLabel,
                                 ui.recordPath, ui.recordBrowse );

            configGeneric<StringConfigControl>( "http-proxy", ui.httpProxyLabel, ui.proxy );
            configGeneric<IntegerConfigControl>( "postproc-q", ui.ppLabel, ui.PostProcLevel );
            configGeneric<IntegerListConfigControl>( "avi-index", ui.aviLabel, ui.AviRepair );

            /* live555 module prefs */
            configBool( "rtsp-tcp", ui.live555TransportRTSP_TCPRadio );
            if ( !module_exists( "live555" ) )
            {
                ui.live555TransportRTSP_TCPRadio->hide();
                ui.live555TransportHTTPRadio->hide();
                ui.live555TransportLabel->hide();
            }
            configGeneric<StringListConfigControl>( "dec-dev", ui.hwAccelLabel, ui.hwAccelModule );
            configBool( "input-fast-seek", ui.fastSeekBox );
            configGeneric<IntegerListConfigControl>( "avcodec-skiploopfilter", ui.filterLabel, ui.loopFilterBox );
            configGeneric<StringListConfigControl>( "sout-x264-tune", ui.x264Label, ui.tuneBox );
            configGeneric<StringListConfigControl>( "sout-x264-preset", ui.x264Label, ui.presetBox );
            configGeneric<StringListConfigControl>( "sout-x264-profile", ui.x264profileLabel, ui.profileBox );
            configGeneric<StringConfigControl>( "sout-x264-level", ui.x264profileLabel, ui.levelBox );
            configBool( "mkv-preload-local-dir", ui.mkvPreloadBox );

            /* Caching */
            /* Add the things to the ComboBox */
            ui.cachingCombo->addItem( qtr("Custom"), QVariant( CachingCustom ) );
            ui.cachingCombo->addItem( qtr("Lowest latency"), QVariant( CachingLowest ) );
            ui.cachingCombo->addItem( qtr("Low latency"), QVariant( CachingLow ) );
            ui.cachingCombo->addItem( qtr("Normal"), QVariant( CachingNormal ) );
            ui.cachingCombo->addItem( qtr("High latency"), QVariant( CachingHigh ) );
            ui.cachingCombo->addItem( qtr("Higher latency"), QVariant( CachingHigher ) );

#define TestCaC( name, factor ) \
    b_cache_equal =  b_cache_equal && \
     ( i_cache * factor == config_GetInt( name ) );
            /* Select the accurate value of the ComboBox */
            bool b_cache_equal = true;
            int i_cache = config_GetInt( "file-caching" );

            TestCaC( "network-caching", 10/3 );
            TestCaC( "disc-caching", 1);
            TestCaC( "live-caching", 1 );
            if( b_cache_equal )
                ui.cachingCombo->setCurrentIndex(
                    ui.cachingCombo->findData( QVariant( i_cache ) ) );
#undef TestCaC

            break;
        }

        /**********************************
         * INTERFACE Panel Implementation *
         **********************************/
        case SPrefsInterface:
        {
            auto& ui = m_interfaceUI;
            ui.setupUi( panel );
            panel_label->setText( qtr("Interface Settings") );

            // The existing radio actions remain available with their source
            // tooltips; remove oversized legacy thumbnail decoration.
            ui.modernImage->hide();
            ui.classicImage->hide();
            ui.skinImage->hide();

#ifndef _WIN32
            ui.langBox->hide();
#else
            for( size_t i = 0; i < ARRAY_SIZE( language_map ); i++)
                ui.langCombo->addItem( qfu( language_map[i].name ), language_map[i].iso );
            connect( ui.langCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &SPrefsPanel::langChanged );

            HKEY h_key;
            char *langReg = NULL;
            if( RegOpenKeyEx( HKEY_CURRENT_USER, TEXT("Software\\VideoLAN\\VLC\\"), 0, KEY_READ, &h_key )
                    == ERROR_SUCCESS )
            {
                WCHAR szData[256];
                DWORD len = 256;
                if( RegQueryValueEx( h_key, TEXT("Lang"), NULL, NULL, (LPBYTE) &szData, &len ) == ERROR_SUCCESS ) {
                    langReg = FromWide( szData );
                    ui.langCombo->setCurrentIndex( ui.langCombo->findData(qfu(langReg)) );
                }
            }
            free( langReg);
#endif

//            ui.defaultLabel->setFont( italicFont );
            ui.skinsLabel->setText(
                    qtr( "This is VLC's skinnable interface. You can download other skins at" )
                    + QString( " <a href=\"https://www.videolan.org/vlc/skins.php\">" )
                    + qtr( "VLC skins website" ) + QString( "</a>." ) );
            ui.skinsLabel->setFont( italicFont );

#ifdef _WIN32
            BUTTONACT( ui.assoButton, &SPrefsPanel::assoDialog );
#else
            ui.osGroupBox->hide();
#endif

            if( !module_exists( "skins2" ) )
            {
                ui.skins->hide();
                ui.skinImage->hide();
            }
            else
            {
                /* interface */
                char *psz_intf = config_GetPsz( "intf" );
                if( psz_intf )
                {
                    if( strstr( psz_intf, "skin" ) )
                        ui.skins->setChecked( true );
                }
                free( psz_intf );
            }

            {
                // Populate styles combobox:
                assert(qApp->property("initialStyle").isValid());
                const QString& initialStyle = qApp->property("initialStyle").toString();
                ui.stylesCombo->addItem( qtr( "System's default (%1)" ).arg( initialStyle ), initialStyle );
                const QStringList& styles = QStyleFactory::keys();
                for ( const auto& i : styles )
                {
                    ui.stylesCombo->addItem( i, i );
                }
                const auto style = getSettings()->value( styleSettingsKey );

                if ( style.isValid() && style.canConvert<QString>() )
                    ui.stylesCombo->setCurrentText( style.toString() );
                ui.stylesCombo->insertSeparator( 1 );
                if ( ui.stylesCombo->currentIndex() < 0 )
                    ui.stylesCombo->setCurrentIndex( 0 ); /* default */
            }

            m_resetters.push_back( std::make_unique<PropertyResetter>( ui.stylesCombo, "currentIndex" ) );

            connect( ui.stylesCombo, QOverload<int>::of(&QComboBox::currentIndexChanged),
                     this, &SPrefsPanel::changeStyle );

            radioGroup = new QButtonGroup(this);
            radioGroup->addButton( ui.modernButton, 0 );
            radioGroup->addButton( ui.classicButton, 1 );
            radioGroup->addButton( ui.skins, 2 );

            configBool( "qt-minimal-view", ui.minimalviewBox );

            /*Update layout radio buttons based on the checkState of the following checkboxes*/
            connect(ui.menuBarCheck, &QtCheckboxChanged, this, &SPrefsPanel::updateLayoutSelection);
            connect(ui.pinVideoControlsCheckbox, &QtCheckboxChanged, this, &SPrefsPanel::updateLayoutSelection);
            connect(ui.titleBarCheckBox, &QtCheckboxChanged, this, &SPrefsPanel::updateLayoutSelection);

            /*Clicking on image will check the corresponding layout radio button*/
            layoutImages = new QButtonGroup( this );
            layoutImages->addButton( ui.modernImage, 0 );
            layoutImages->addButton( ui.classicImage, 1 );
            layoutImages->addButton( ui.skinImage, 2 );

            connect( layoutImages, qOverload<QAbstractButton*>( &QButtonGroup::buttonClicked ), this, &SPrefsPanel::imageLayoutClick );

            /* Set checkboxes depending on the layout selected*/
            connect(radioGroup, &QButtonGroup::idClicked, this, &SPrefsPanel::handleLayoutChange);
            connect(layoutImages, &QButtonGroup::idClicked, this, &SPrefsPanel::handleLayoutChange);

            configBool( "embedded-video", ui.embedVideo );
            configBool( "qt-video-autoresize", ui.resizingBox );
            connect( ui.embedVideo, &QCheckBox::toggled, ui.resizingBox, &QCheckBox::setEnabled );
            ui.resizingBox->setEnabled( ui.embedVideo->isChecked() );

            configBool( "qt-fs-controller", ui.fsController );
            configBool( "qt-system-tray", ui.systrayBox );
            configGeneric<IntegerListConfigControl>( "qt-notification", ui.notificationComboLabel,
                                                      ui.notificationCombo );
            connect( ui.systrayBox, &QCheckBox::toggled, [=]( bool checked ) {
                ui.notificationCombo->setEnabled( checked );
                ui.notificationComboLabel->setEnabled( checked );
            } );
            ui.notificationCombo->setEnabled( ui.systrayBox->isChecked() );

            configBool( "qt-pause-minimized", ui.pauseMinimizedBox );
            configBool( "playlist-tree", ui.treePlaylist );
            configBool( "play-and-pause", ui.playPauseBox );
            configGenericFile<FileConfigControl>( "skins2-last",  ui.skinFileLabel,
                                 ui.fileSkin, ui.skinBrowse );

            configBool( "metadata-network-access", ui.MetadataNetworkAccessMode );
            configBool( "qt-menubar", ui.menuBarCheck );


            configBool( "qt-pin-controls", ui.pinVideoControlsCheckbox );
            m_resetters.push_back(std::make_unique<PropertyResetter>(ui.pinVideoControlsCheckbox, "checked"));
            QObject::connect( ui.pinVideoControlsCheckbox, &QtCheckboxChanged, p_intf->p_mi, &MainCtx::setPinVideoControls );

            ui.colorSchemeComboBox->setModel( p_intf->p_mi->getColorScheme() );
            ui.colorSchemeComboBox->setCurrentText( p_intf->p_mi->getColorScheme()->currentText() );
            m_resetters.push_back(std::make_unique<PropertyResetter>( ui.colorSchemeComboBox, "currentIndex" ));
            QObject::connect( ui.colorSchemeComboBox, QOverload<int>::of(&QComboBox::currentIndexChanged)
                              , p_intf->p_mi->getColorScheme(), &ColorSchemeModel::setCurrentIndex );

            const double intfScaleFloatFactor = 100;
            const auto updateIntfUserScaleFactorFromControls =
                    [this, slider = ui.intfScaleFactorSlider, spinBox = ui.intfScaleFactorSpinBox, intfScaleFloatFactor](const int value)
            {
                if (slider->value() != value)
                {
                    QSignalBlocker s( slider );
                    slider->setValue( value );
                }
                if (spinBox->value() != value)
                {
                    QSignalBlocker s( spinBox );
                    spinBox->setValue( value );
                }
                p_intf->p_mi->setIntfUserScaleFactor( value / intfScaleFloatFactor );
            };

            ui.intfScaleFactorSlider->setRange( p_intf->p_mi->getMinIntfUserScaleFactor() * intfScaleFloatFactor
                                                 , p_intf->p_mi->getMaxIntfUserScaleFactor() * intfScaleFloatFactor);
            ui.intfScaleFactorSpinBox->setRange( p_intf->p_mi->getMinIntfUserScaleFactor() * intfScaleFloatFactor
                                                 , p_intf->p_mi->getMaxIntfUserScaleFactor() * intfScaleFloatFactor);

            updateIntfUserScaleFactorFromControls( p_intf->p_mi->getIntfUserScaleFactor() * intfScaleFloatFactor );
            m_resetters.push_back( std::make_unique<PropertyResetter>( ui.intfScaleFactorSlider, "value" ) );

            QObject::connect( ui.intfScaleFactorSlider, QOverload<int>::of(&QSlider::valueChanged)
                              , p_intf->p_mi , updateIntfUserScaleFactorFromControls );
            QObject::connect( ui.intfScaleFactorSpinBox, QOverload<int>::of(&QSpinBox::valueChanged)
                              , p_intf->p_mi , updateIntfUserScaleFactorFromControls );

            // Figma General 3046:9313 puts Theme/Accent in one Appearance
            // section. Retain the existing combo as the original action and
            // cancel/reset transaction; the segmented buttons drive it.
            m_appearance = new QGroupBox(qtr("Appearance"),panel);
            m_appearance->setObjectName(QStringLiteral("preferencesAppearance"));
            m_appearance->setProperty("preferencesGroup",SPrefsGroupGeneral);
            auto appearance = new QGridLayout(m_appearance);
            appearance->setContentsMargins(0,0,0,0);
            appearance->setVerticalSpacing(10);
            appearance->setColumnStretch(0,1);
            int appearanceRow = 0;
#ifdef _WIN32
            auto languageLabel = ui.langBox->findChild<QLabel *>();
            ui.langBox->layout()->removeWidget(ui.langCombo);
            ui.langBox->layout()->removeWidget(languageLabel);
            languageLabel->setText(qtr("Interface language")); // Figma 3046:9318.
            appearance->addWidget(languageLabel,appearanceRow,0);
            ui.langCombo->setFixedSize(320,36);
            appearance->addWidget(ui.langCombo,appearanceRow++,10);
#endif
            ui.langBox->hide();
            auto nativeGrid = qobject_cast<QGridLayout *>(ui.native_zone->layout());
            nativeGrid->removeWidget(ui.colorSchemeLabel);
            nativeGrid->removeWidget(ui.colorSchemeComboBox);
            ui.colorSchemeLabel->hide();
            ui.colorSchemeComboBox->setParent(m_appearance);
            ui.colorSchemeComboBox->hide();
            auto themeCaption = new QLabel(qtr("Theme"),m_appearance);
            appearance->addWidget(themeCaption,appearanceRow,0);
            auto segments = new QWidget(m_appearance);
            segments->setObjectName(QStringLiteral("preferencesThemeSegments"));
            segments->setFixedSize(320,36);
            auto choices = new QHBoxLayout(segments);
            choices->setContentsMargins(2,2,2,2);
            choices->setSpacing(2);
            auto themeGroup = new QButtonGroup(segments);
            const auto schemes = p_intf->p_mi->getColorScheme()->getSchemes();
            for(const auto scheme : {ColorSchemeModel::Night,ColorSchemeModel::Day,ColorSchemeModel::System})
                for(int index=0;index<schemes.size();++index) if(schemes[index].scheme==scheme) {
                    auto button = new QPushButton(scheme==ColorSchemeModel::Night ? qtr("Dark")
                        : scheme==ColorSchemeModel::Day ? qtr("Light") : qtr("System"),segments);
                    button->setObjectName(QStringLiteral("preferencesThemeChoice"));
                    button->setCheckable(true);
                    button->setAutoDefault(false);
                    button->setFixedHeight(32);
                    button->setProperty("colorSchemeIndex",index);
                    button->setChecked(index==ui.colorSchemeComboBox->currentIndex());
                    choices->addWidget(button,1);
                    themeGroup->addButton(button,index);
                }
            connect(themeGroup,&QButtonGroup::idClicked,ui.colorSchemeComboBox,&QComboBox::setCurrentIndex);
            connect(ui.colorSchemeComboBox,qOverload<int>(&QComboBox::currentIndexChanged),themeGroup,
                [themeGroup](int index){if(auto button=themeGroup->button(index))button->setChecked(true);});
            appearance->addWidget(segments,appearanceRow,10);
            ui.verticalLayout->insertWidget(0,m_appearance);

            // Source style and scale controls remain available in General's
            // Advanced workflow, with their original signals and defaults.
            m_appearanceAdvanced = new QGroupBox(qtr("Advanced"),panel);
            m_appearanceAdvanced->setProperty("preferencesGroup",SPrefsGroupGeneral);
            m_appearanceAdvanced->setProperty("preferencesAdvanced",true);
            auto appearanceAdvanced = new QGridLayout(m_appearanceAdvanced);
            appearanceAdvanced->setContentsMargins(0,0,0,0);
            appearanceAdvanced->setColumnStretch(0,1);
            appearanceAdvanced->setVerticalSpacing(10);
            for(auto widget : {static_cast<QWidget *>(ui.stylesLabel),static_cast<QWidget *>(ui.stylesCombo),
                static_cast<QWidget *>(ui.scaleFactorLabel),static_cast<QWidget *>(ui.intfScaleFactorSlider),
                static_cast<QWidget *>(ui.intfScaleFactorSpinBox)}) nativeGrid->removeWidget(widget);
            ui.stylesCombo->setFixedSize(320,36);
            appearanceAdvanced->addWidget(ui.stylesLabel,0,0);
            appearanceAdvanced->addWidget(ui.stylesCombo,0,10);
            appearanceAdvanced->addWidget(ui.scaleFactorLabel,1,0);
            auto scale = new QWidget(m_appearanceAdvanced);
            scale->setFixedSize(320,36);
            auto scaleLayout = new QHBoxLayout(scale);
            scaleLayout->setContentsMargins(0,0,0,0);
            scaleLayout->setSpacing(10);
            scaleLayout->addWidget(ui.intfScaleFactorSlider,1);
            scaleLayout->addWidget(ui.intfScaleFactorSpinBox);
            appearanceAdvanced->addWidget(scale,1,10);
            ui.verticalLayout->addWidget(m_appearanceAdvanced);

            DialogsProvider *provider = DialogsProvider::getInstance();

            QObject::connect( ui.toolbarEditor, &QAbstractButton::clicked, provider, &DialogsProvider::showToolbarEditorDialog);

            configBool( "qt-titlebar", ui.titleBarCheckBox );

            /* UPDATE options */
#ifdef UPDATE_CHECK
            configBool( "qt-updates-notif", ui.updatesBox );
            configGeneric<IntegerConfigControl>( "qt-updates-days", nullptr, ui.updatesDays );
            ui.updatesDays->setEnabled( ui.updatesBox->isChecked() );
            connect( ui.updatesBox, &QCheckBox::toggled,
                     ui.updatesDays, &QSpinBox::setEnabled );
#else
            ui.updatesBox->hide();
            ui.updatesDays->hide();
#endif
            /* ONE INSTANCE options */
#if !defined( _WIN32 ) && !defined(__APPLE__) && !defined(__OS2__)
            if( !module_exists( "dbus" ) )
            {
                ui.OneInterfaceMode->hide();
                ui.EnqueueOneInterfaceMode->hide();
                ui.oneInstanceFromFile->hide();
            }
            else
#endif
            {
                configBool( "one-instance", ui.OneInterfaceMode );
                configBool( "playlist-enqueue", ui.EnqueueOneInterfaceMode );
                ui.EnqueueOneInterfaceMode->setEnabled( ui.OneInterfaceMode->isChecked() );
                connect( ui.OneInterfaceMode, &QCheckBox::toggled,
                         ui.EnqueueOneInterfaceMode, &QCheckBox::setEnabled );
                configBool( "one-instance-when-started-from-file", ui.oneInstanceFromFile );
            }

            configGeneric<IntegerListConfigControl>( "qt-auto-raise", ui.autoRaiseLabel, ui.autoRaiseComboBox );

            /* RECENTLY PLAYED options */

            const auto hasMedialibrary = p_intf->p_mi->hasMediaLibrary();

            ui.continuePlaybackLabel->setVisible( hasMedialibrary );
            ui.continuePlaybackComboBox->setVisible( hasMedialibrary );
            ui.saveRecentlyPlayed->setVisible( hasMedialibrary );
            ui.clearRecent->setVisible( hasMedialibrary );
            ui.clearRecentSpacer->changeSize( 0, 0 );

            if ( hasMedialibrary )
            {
                configGeneric<IntegerListConfigControl>( "restore-playback-pos", ui.continuePlaybackLabel, ui.continuePlaybackComboBox );
                configBool( "save-recentplay", ui.saveRecentlyPlayed );

                ui.clearRecentSpacer->changeSize( 1, 1, QSizePolicy::Expanding, QSizePolicy::Minimum );
                MLRecentMediaModel *recentsModel = new MLRecentMediaModel( ui.clearRecent );
                recentsModel->setMl( p_intf->p_mi->getMediaLibrary() );
                connect( ui.clearRecent, &QPushButton::clicked, recentsModel, &MLRecentMediaModel::clearHistory );
            }

            normalizePreferenceRows(nativeGrid,ui.native_zone);
            break;
        }

        /**********************************
         * SUBTITLES Panel Implementation *
         **********************************/
        case SPrefsSubtitles:
        {
            auto& ui = m_subtitlesUI;
            ui.setupUi( panel );
            panel_label->setText( qtr("Subtitle & On Screen Display Settings") );
            ui.groupBox_2->setTitle(qtr("Tracks & Languages")); // Figma 3180:18023.
            ui.groupBox->setTitle(qtr("Appearance"));
            ui.groupBox_3->setTitle(qtr("On-Screen Messages"));

            configBool( "osd", ui.OSDBox);
            configBool( "video-title-show", ui.OSDTitleBox);
            configGeneric<IntegerListConfigControl>( "video-title-position",
                            ui.OSDTitlePosLabel, ui.OSDTitlePos );

            configBool( "spu", ui.spuActiveBox);
            ui.spuZone->setEnabled( ui.spuActiveBox->isChecked() );
            connect( ui.spuActiveBox, &QCheckBox::toggled, ui.spuZone, &QWidget::setEnabled );

            configGeneric<StringListConfigControl>( "subsdec-encoding", ui.encodLabel,
                            ui.encoding );
            configGeneric<StringConfigControl>( "sub-language", ui.subLangLabel,
                            ui.preferredLanguage );

            // All subtitle renderers use the core percentage scale. Keep its
            // ranged editor independent of renderer-specific list widgets.
            auto fontSize = qobject_cast<QSpinBox *>( ui.fontSize );
            if( !fontSize )
            {
                QWidget *oldFontSize = ui.fontSize;
                fontSize = new QSpinBox( oldFontSize->parentWidget() );
                fontSize->setObjectName( oldFontSize->objectName() );
                fontSize->setSizePolicy( oldFontSize->sizePolicy() );
                oldFontSize->setObjectName( QStringLiteral("legacyFontSize") );
                delete ui.gridLayout_2->replaceWidget( oldFontSize, fontSize );
                oldFontSize->hide();
                ui.fontSizeLabel->setBuddy( fontSize );
            }
            configGeneric<IntegerRangeConfigControl>( "sub-text-scale",
                            ui.fontSizeLabel, fontSize );
            if( auto option = config_FindConfig("sub-text-scale") )
            {
                ui.fontSizeLabel->setText( qfut(option->psz_text) );
                fontSize->setSuffix( QStringLiteral("%") );
            }

            configGeneric<FontConfigControl>( "freetype-font", ui.fontLabel, ui.font );
            configGeneric<ColorConfigControl>( "freetype-color", ui.fontColorLabel, ui.fontColor );
            if(auto option=config_FindConfig("freetype-outline-thickness"); option&&option->list_count==0)
            {
                // VLC4 exposes thickness as an actual integer range rather
                // than the old list. Preserve every source-supported value.
                auto thickness = new QSpinBox(ui.effect->parentWidget());
                thickness->setObjectName(ui.effect->objectName());
                delete ui.gridLayout_2->replaceWidget(ui.effect,thickness);
                ui.effect->setObjectName(QStringLiteral("legacyOutlineThickness"));
                ui.effect->hide();
                configGeneric<IntegerRangeConfigControl>("freetype-outline-thickness",ui.fontEffectLabel,thickness);
            }
            else configGeneric<IntegerListConfigControl>( "freetype-outline-thickness",
                            ui.fontEffectLabel, ui.effect );
            configGeneric<ColorConfigControl>( "freetype-outline-color", ui.outlineColorLabel,
                            ui.outlineColor );

            configGeneric<IntegerConfigControl>( "sub-margin", ui.subsPosLabel, ui.subsPosition );

            if( module_exists( "freetype" ) )
            {
                ui.shadowCheck->setChecked( config_GetInt( "freetype-shadow-opacity" ) > 0 );
                ui.backgroundCheck->setChecked( config_GetInt( "freetype-background-opacity" ) > 0 );
            }
            else
            {
                ui.shadowCheck->setEnabled( false );
                ui.backgroundCheck->setEnabled( false );
            }
            if( auto option = config_FindConfig("freetype-shadow-opacity") )
                addHelp( ui.shadowCheck, option );
            if( auto option = config_FindConfig("freetype-background-opacity") )
                addHelp( ui.backgroundCheck, option );

            configGeneric<IntegerListConfigControl>( "secondary-sub-alignment",
                            ui.secondarySubsAlignmentLabel, ui.secondarySubsAlignment );
            configGeneric<IntegerConfigControl>( "secondary-sub-margin", ui.secondarySubsPosLabel, ui.secondarySubsPosition );

            // Expose related existing options alongside the basic subtitle controls.
            // Labels, help, defaults and numeric values come from module config.
            auto advanced_subtitles = new QGroupBox( qtr("Loading Subtitles"), ui.spuZone ); // Figma 3180:18035.
            auto advanced_layout = new QGridLayout( advanced_subtitles );
            const char *options[] = {"sub-track", "sub-autodetect-file",
                                     "sub-autodetect-fuzzy", "sub-autodetect-path"};
            int row = 0;
            for( const char *name : options )
                if( auto option = config_FindConfig(name) )
                {
                    QWidget *owner = !strcmp(name,"sub-track") ? ui.groupBox_2 : advanced_subtitles;
                    auto grid = !strcmp(name,"sub-track") ? qobject_cast<QGridLayout *>(ui.groupBox_2->layout()) : advanced_layout;
                    const int line = !strcmp(name,"sub-track") ? grid->rowCount() : row++;
                    if( auto option_control = ConfigControl::createControl(option,owner,grid,line) )
                        controls.append( option_control );
                }
            ui.spuZone->layout()->addWidget( advanced_subtitles );
            for(auto box : {ui.groupBox_2,ui.groupBox,ui.groupBox_3,ui.groupBox_5,advanced_subtitles})
                if(auto grid=qobject_cast<QGridLayout *>(box->layout())) normalizePreferenceRows(grid,box);
            break;
        }

        /********************************
         * HOTKEYS Panel Implementation *
         ********************************/
        case SPrefsHotkeys:
        {
            QGridLayout *gLayout = new QGridLayout;
            panel->setLayout( gLayout );
            int line = 0;

            panel_label->setText( qtr( "Configure Hotkeys" ) );
            m_keySelector = new KeySelectorControl( this );
            control = m_keySelector;
            control->insertInto( gLayout, line );
            controls.append( control );
            m_keySelector->setEditorVisible( false );

            m_shortcutsSummary = new QGroupBox( qtr("Keyboard Shortcuts"), panel );
            auto shortcuts = new QGridLayout( m_shortcutsSummary );
            m_shortcutsStatus = new QLabel( m_keySelector->matchesDefaults() ? qtr("Defaults") : qtr("Custom"), m_shortcutsSummary );
            shortcuts->addWidget( m_shortcutsStatus, 0, 0 );
            auto edit = new QPushButton( qtr("Edit Keyboard Shortcuts"), m_shortcutsSummary );
            connect( edit, &QPushButton::clicked, this, &SPrefsPanel::editShortcuts );
            shortcuts->addWidget( edit, 0, 1 );
            shortcuts->addWidget( new QLabel(qtr("Reset all shortcuts"), m_shortcutsSummary), 1, 0 );
            auto reset = new QPushButton( qtr("Reset"), m_shortcutsSummary );
            connect( reset, &QPushButton::clicked, this, [this]() {
                m_keySelector->resetAllKeys();
                m_shortcutsStatus->setText( qtr("Defaults") );
            } );
            shortcuts->addWidget( reset, 1, 1 );
            shortcuts->setColumnStretch( 0, 1 );
            gLayout->addWidget( m_shortcutsSummary, line++, 0, 1, -1 );

            m_mouseSettings = new QGroupBox( qtr("Mouse"), panel );
            auto mouse = new QGridLayout( m_mouseSettings );
            int mouseLine = 0;

            line++;

            p_config = config_FindConfig( "hotkeys-y-wheel-mode" );
            control = ConfigControl::createControl( p_config, m_mouseSettings, mouse, mouseLine++ );
            controls.append( control );

            line++;

            p_config = config_FindConfig( "hotkeys-x-wheel-mode" );
            control = ConfigControl::createControl( p_config, m_mouseSettings, mouse, mouseLine++ );
            controls.append( control );

#ifdef _WIN32
            line++;

            p_config = config_FindConfig( "qt-disable-volume-keys" );
            control = ConfigControl::createControl( p_config, m_mouseSettings, mouse, mouseLine++ );
            controls.append( control );
#endif
            gLayout->addWidget( m_mouseSettings, line++, 0, 1, -1 );
            break;
        }

        /**************************************
         * MEDIA LIBRARY Panel Implementation *
         **************************************/
        case SPrefsMediaLibrary:
        {
            auto& ui = m_medialibUI;
            ui.setupUi( panel );
            panel_label->setText( qtr("Media Library Settings") );

            if ( vlc_ml_instance_get( p_intf ) != NULL )
            {
                AccessibleCompatAttached::setId( ui.mlGroupBox, "ml-groupbox" );
                auto foldersModel = new MLFoldersModel( this );
                foldersModel->setCtx( p_intf->p_mi );
                ui.entryPoints->setMLFoldersModel( foldersModel );
                mlFoldersEditor = ui.entryPoints;

                auto bannedFoldersModel = new MLBannedFoldersModel( this );
                bannedFoldersModel->setCtx( p_intf->p_mi );
                ui.bannedEntryPoints->setMLFoldersModel( bannedFoldersModel );
                mlBannedFoldersEditor = ui.bannedEntryPoints;

                BUTTONACT( ui.addButton, &SPrefsPanel::MLaddNewFolder );
                BUTTONACT( ui.banButton, &SPrefsPanel::MLBanFolder );

                connect( ui.reloadButton, &QPushButton::clicked
                        , p_intf->p_mi->getMediaLibrary(), &MediaLib::reload);
            }
            else
            {
                ui.mlGroupBox->hide( );
            }

            break;
        }
    }

    for( auto label : panel->findChildren<QLabel *>() )
        label->setWordWrap( true );
    for( auto line : panel->findChildren<QFrame *>() )
        if( line->frameShape() == QFrame::HLine )
            line->hide();
    for( auto widget : panel->findChildren<QWidget *>() )
        if( qobject_cast<QLineEdit *>(widget) || qobject_cast<QComboBox *>(widget) ||
            qobject_cast<QAbstractSpinBox *>(widget) || widget->property("preferenceOptionName").isValid() )
        {
            if( widget->objectName() != "hotkeyEditorSearch" &&
                !qobject_cast<QCheckBox *>(widget) && !widget->property("preferenceToggleRow").toBool() &&
                !widget->property("preferenceCaptionRow").toBool() )
                widget->setMaximumWidth( 320 );
            if( qobject_cast<QLineEdit *>(widget) || qobject_cast<QComboBox *>(widget) ||
                qobject_cast<QAbstractSpinBox *>(widget) )
                widget->setMinimumHeight( 36 );
        }
    for( auto box : panel->findChildren<QGroupBox *>() )
    {
        box->setSizePolicy( QSizePolicy::Expanding, QSizePolicy::Maximum );
        if( auto layout = box->layout() )
        {
            layout->setContentsMargins( 0, 0, 0, 0 );
            layout->setSpacing( 10 );
        }
    }
    if( panel->layout() )
    {
        panel->layout()->setContentsMargins( 0, 0, 0, 0 );
        panel->layout()->setSpacing( 20 );
        panel->layout()->setAlignment( Qt::AlignTop );
        for( int i = panel->layout()->count() - 1; i >= 0; --i )
            if( panel->layout()->itemAt(i)->spacerItem() )
                delete panel->layout()->takeAt(i);
    }
    m_advancedOptions = new QPushButton( qtr("Advanced Options"), panel );
    m_advancedOptions->setObjectName( QStringLiteral("preferencesAdvancedOptions") );
    m_advancedOptions->setIcon( QIcon(QStringLiteral(":/redesign/icons/settings-chevron.svg")) );
    m_advancedOptions->setIconSize( QSize(24, 24) );
    m_advancedOptions->setCheckable( true );
    m_advancedOptions->setMinimumHeight( 38 );
    connect( m_advancedOptions, &QPushButton::clicked, this, &SPrefsPanel::toggleGroupAdvanced );
    if( panel->layout() )
        panel->layout()->addWidget( m_advancedOptions );
    panel_layout->addWidget( panel_label );
    panel_layout->addWidget( title_line );

    QScrollArea *scroller= new QScrollArea;
    scroller->setWidget( panel );
    scroller->setWidgetResizable( true );
    scroller->setFrameStyle( QFrame::NoFrame );
    panel_layout->addWidget( scroller );

    setLayout( panel_layout );
}


void SPrefsPanel::updateAudioOptions( int number )
{

    auto setAudioDeviceVisible = [this](QString key, bool visible) {
        const AudioControlGroup& ctrl = audioControlGroups[key];
        if (ctrl.widget)
            ctrl.widget->setVisible( visible );
        if (ctrl.label)
            ctrl.label->setVisible( visible );
        if (ctrl.button)
            ctrl.button->setVisible( visible );
    };

    QString value = m_audioUI.outputModule->itemData( number ).toString();
#ifdef _WIN32
    /* Since MMDevice is most likely to be used by default, we show MMDevice
     * options by default */
    const bool mmDeviceEnabled = value == "mmdevice" || value == "any";
    m_audioUI.mmdevicePassthroughLabel->setVisible( mmDeviceEnabled );
    m_audioUI.mmdevicePassthroughBox->setVisible( mmDeviceEnabled );
    setAudioDeviceVisible("mmdevice", mmDeviceEnabled);

    setAudioDeviceVisible("waveout", value == "waveout");
#elif defined( __OS2__ )
    setAudioDeviceVisible("kai", value == "kai");
#else
    setAudioDeviceVisible("oss", value == "oss");
    setAudioDeviceVisible("alsa", value == "alsa");

#endif
    m_audioUI.fileControl->setVisible( ( value == "afile" ) );
    m_audioUI.spdifBox->setVisible( ( value == "alsa" || value == "oss" || value == "auhal" ||
                                             value == "waveout" ) );

    int volume = getDefaultAudioVolume(qtu(value));
    bool save = true;

    if (volume >= 0)
        save = config_GetInt("volume-save");

    m_audioUI.resetVolumeCheckbox->setChecked(!save);
    m_audioUI.resetVolumeCheckbox->setEnabled(volume >= 0);

    m_audioUI.defaultVolume->setValue((volume >= 0) ? volume : 100);
    m_audioUI.defaultVolume->setEnabled(volume >= 0);
}


SPrefsPanel::~SPrefsPanel()
{
    if (!m_isApplied)
        clean();

    qDeleteAll( controls ); controls.clear();
    free( lang );
}

/* Checks the layout radio button corresponding the image clicked */
void SPrefsPanel::imageLayoutClick( QAbstractButton* btn )
{
    QAbstractButton* layoutBtn = radioGroup->buttons().at( layoutImages->id( btn ) );
    assert( layoutBtn );
    layoutBtn->setChecked( true );
}

/* Change configurations depending on the layout selected and set check states of radioGroup */
void SPrefsPanel::handleLayoutChange( int id )
{
    auto ui = m_interfaceUI;
    if (id == 0) {
        // Modern layout selected
        ui.styleStackedWidget->setCurrentIndex(0);
        ui.menuBarCheck->setChecked(false);
        ui.titleBarCheckBox->setChecked(false);
        ui.pinVideoControlsCheckbox->setChecked(false);
    }
    else if (id == 1) {
        // Classic layout selected
        ui.styleStackedWidget->setCurrentIndex(0);
        ui.menuBarCheck->setChecked(true);
        ui.titleBarCheckBox->setChecked(true);
        ui.pinVideoControlsCheckbox->setChecked(true);
    }
    else if (id == 2) {
        ui.styleStackedWidget->setCurrentIndex(1);
    }
}

void SPrefsPanel::updateLayoutSelection()
{
    auto ui = m_interfaceUI;
    bool isModern = !ui.menuBarCheck->isChecked()
                    && !ui.titleBarCheckBox->isChecked()
                    && !ui.pinVideoControlsCheckbox->isChecked();

    ui.modernButton->setChecked(isModern);

    bool isClassic = ui.menuBarCheck->isChecked()
                     && ui.titleBarCheckBox->isChecked()
                     && ui.pinVideoControlsCheckbox->isChecked();

    ui.classicButton->setChecked(isClassic);

    if (!isModern && !isClassic) {
        radioGroup->setExclusive(false);
        ui.modernButton->setChecked(false);
        ui.classicButton->setChecked(false);
        radioGroup->setExclusive(true);
    }
}

void SPrefsPanel::updateAudioVolume( int volume )
{
    m_audioUI.volumeValue->setValue( volume );
}


/* Function called from the main Preferences dialog on each SPrefs Panel */
void SPrefsPanel::apply()
{
    m_isApplied = true;

    /* Generic save for ever panel */
    QList<ConfigControl *>::const_iterator i;
    for( i = controls.cbegin() ; i != controls.cend() ; ++i )
    {
        ConfigControl *c = qobject_cast<ConfigControl *>(*i);
        c->doApply();
    }

    switch( number )
    {
    case SPrefsInputAndCodecs:
    {
        /* Device default selection */
        QByteArray devicepath = m_inputCodecUI.DVDDeviceComboBox->currentText().toUtf8();
        if( devicepath.size() > 0 )
        {
            config_PutPsz( "dvd", devicepath.constData() );
            config_PutPsz( "vcd", devicepath.constData() );
            if( module_exists( "cdda" ) )
                config_PutPsz( "cd-audio", devicepath.constData() );
        }

#define CaC( name, factor ) config_PutInt( name, i_comboValue * factor )
        /* Caching */
        QComboBox *cachingCombo = m_inputCodecUI.cachingCombo;
        int i_comboValue = cachingCombo->itemData( cachingCombo->currentIndex() ).toInt();
        if( i_comboValue )
        {
            CaC( "file-caching", 1 );
            CaC( "network-caching", 10/3 );
            CaC( "disc-caching", 1 );
            CaC( "live-caching", 1 );
        }
        break;
#undef CaC
    }

    /* Interfaces */
    case SPrefsInterface:
    {
        if( m_interfaceUI.skins->isChecked() )
            config_PutPsz( "intf", "skins2,any" );
        else
        //if( m_interfaceUI.qt->isChecked() )
            config_PutPsz( "intf", "" );
#if !defined( _WIN32)
        if ( m_interfaceUI.stylesCombo->currentIndex() > 0 )
            getSettings()->setValue( styleSettingsKey, m_interfaceUI.stylesCombo->currentData().toString() );
        else
            getSettings()->remove( styleSettingsKey );
#endif

#ifdef _WIN32
    saveLang();
#endif
        break;
    }

    case SPrefsVideo:
    {
        int i_fullscreenScreen =   m_videoUI.fullscreenScreenBox->currentData().toInt();
        config_PutInt( "qt-fullscreen-screennumber", i_fullscreenScreen );
        break;
    }

    case SPrefsAudio:
    {
        bool b_checked = m_audioUI.volNormBox->isChecked();
        if( b_checked && !qs_filter.contains( "normvol" ) )
            qs_filter.append( "normvol" );
        if( !b_checked && qs_filter.contains( "normvol" ) )
            qs_filter.removeAll( "normvol" );

        config_PutPsz( "audio-filter", qtu( qs_filter.join( ":" ) ) );

        /* Default volume */
        int i_volume = m_audioUI.defaultVolume->value();
        bool b_reset_volume = m_audioUI.resetVolumeCheckbox->isChecked();
        char *psz_aout = config_GetPsz( "aout" );

        float f_gain = powf( i_volume / 100.f, 3 );

#define save_vol_aout( name ) \
            module_exists( name ) && ( !psz_aout || !strcmp( psz_aout, name ) || !strcmp( psz_aout, "any" ) )

        //FIXME this is moot
#if defined( _WIN32 )
        VLC_UNUSED( f_gain );
        if( save_vol_aout( "mmdevice" ) )
            config_PutFloat( "mmdevice-volume", i_volume / 100.f );
        if( save_vol_aout( "waveout" ) )
            config_PutFloat( "waveout-volume", i_volume / 100.f );
#elif defined( Q_OS_MAC )
        VLC_UNUSED( f_gain );
        if( save_vol_aout( "auhal" ) )
            config_PutFloat( "auhal-volume", i_volume / 100.f
                    * AOUT_VOLUME_DEFAULT );
#elif defined( __OS2__ )
        if( save_vol_aout( "kai" ) )
            config_PutFloat( "kai-gain",  f_gain );
#else
        if( save_vol_aout( "alsa" ) )
            config_PutFloat( "alsa-gain", f_gain );
        if( save_vol_aout( "jack" ) )
            config_PutFloat( "jack-gain", f_gain );
#endif
#undef save_vol_aout
        free( psz_aout );

        config_PutInt( "volume-save", !b_reset_volume );

        break;
    }
    case SPrefsSubtitles:
    {
        bool b_checked = m_subtitlesUI.shadowCheck->isChecked();
        if( b_checked && config_GetInt( "freetype-shadow-opacity" ) == 0 ) {
            config_PutInt( "freetype-shadow-opacity", 128 );
        }
        else if (!b_checked ) {
            config_PutInt( "freetype-shadow-opacity", 0 );
        }

        b_checked = m_subtitlesUI.backgroundCheck->isChecked();
        if( b_checked && config_GetInt( "freetype-background-opacity" ) == 0 ) {
            config_PutInt( "freetype-background-opacity", 128 );
        }
        else if (!b_checked ) {
            config_PutInt( "freetype-background-opacity", 0 );
        }
        break;
    }

    case SPrefsMediaLibrary:
    {
        mlFoldersEditor->commit();
        mlBannedFoldersEditor->commit();
    }
    }
}

void SPrefsPanel::clean()
{
    for ( auto &resetter : m_resetters )
        resetter->reset();
}

void SPrefsPanel::lastfm_Changed( int i_state )
{
    if( i_state == Qt::Checked )
        config_AddIntf( "audioscrobbler" );
    else if( i_state == Qt::Unchecked )
        config_RemoveIntf( "audioscrobbler" );
}

void SPrefsPanel::changeStyle()
{
    const QString style = m_interfaceUI.stylesCombo->currentData().toString();

    QMetaObject::invokeMethod( qApp, [style]() {
        // Queue this call in order to prevent
        // updating the preferences dialog when
        // it is rejected:
        QApplication::setStyle( style );
    }, Qt::QueuedConnection );
}

void SPrefsPanel::langChanged( int i )
{
    free( lang );
    lang = strdup( language_map[i].iso );
}

void SPrefsPanel::configML()
{
#ifdef SQL_MEDIA_LIBRARY
    MLConfDialog *mld = new MLConfDialog( this, p_intf );
    mld->exec();
    delete mld;
#endif
}

#ifdef _WIN32
#include <QDialogButtonBox>
#include "util/registry.hpp"

void SPrefsPanel::cleanLang() {
    QVLCRegistry qvReg( HKEY_CURRENT_USER );
    qvReg.DeleteValue( "Software\\VideoLAN\\VLC\\", "Lang" );
    qvReg.DeleteKey( "Software\\VideoLAN\\", "VLC" );
    qvReg.DeleteKey( "Software\\", "VideoLAN" );
}

void SPrefsPanel::saveLang() {
    if( !lang ) return;

    if( !strncmp( lang, "auto", 4 ) ) {
        cleanLang();
    }
    else
    {
        QVLCRegistry qvReg( HKEY_CURRENT_USER );
        qvReg.WriteRegistry( "Software\\VideoLAN\\VLC\\", "Lang", lang );
    }
}

bool SPrefsPanel::addType( const char * psz_ext, QTreeWidgetItem* current,
                           QTreeWidgetItem* parent, QVLCRegistry *qvReg )
{
    bool b_temp;
    const char* psz_VLC = "VLC";
    current = new QTreeWidgetItem( parent, QStringList( psz_ext ) );

    char* psz_reg = qvReg->ReadRegistry( psz_ext, "", "" );
    if( psz_reg == NULL )
        return false;
    if( strstr( psz_reg, psz_VLC ) )
    {
        current->setCheckState( 0, Qt::Checked );
        b_temp = true;
    }
    else
    {
        current->setCheckState( 0, Qt::Unchecked );
        b_temp = false;
    }
    free( psz_reg );
    listAsso.append( current );
    return b_temp;
}

void SPrefsPanel::assoDialog()
{
    HRESULT hr;

    hr = CoInitializeEx( NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE );
    if( SUCCEEDED(hr) )
    {
        {
            Microsoft::WRL::ComPtr<IApplicationAssociationRegistrationUI> p_regui;

            hr = CoCreateInstance(__uuidof(ApplicationAssociationRegistrationUI),
                                NULL, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&p_regui));
            if( SUCCEEDED(hr) )
                p_regui->LaunchAdvancedAssociationUI(L"VLC" );
        }
        CoUninitialize();
    }

    if( SUCCEEDED(hr) )
        return;

    QDialog *d = new QDialog( this );
    d->setWindowTitle( qtr( "File associations" ) );
    QGridLayout *assoLayout = new QGridLayout( d );

    QTreeWidget *filetypeList = new QTreeWidget;
    assoLayout->addWidget( filetypeList, 0, 0, 1, 4 );
    filetypeList->header()->hide();

    QVLCRegistry qvReg( HKEY_CLASSES_ROOT );

    QTreeWidgetItem *audioType = new QTreeWidgetItem( QStringList( qtr( "Audio Files" ) ) );
    QTreeWidgetItem *videoType = new QTreeWidgetItem( QStringList( qtr( "Video Files" ) ) );
    QTreeWidgetItem *otherType = new QTreeWidgetItem( QStringList( qtr( "Playlist Files" ) ) );

    filetypeList->addTopLevelItem( audioType );
    filetypeList->addTopLevelItem( videoType );
    filetypeList->addTopLevelItem( otherType );

    audioType->setExpanded( true ); audioType->setCheckState( 0, Qt::Unchecked );
    videoType->setExpanded( true ); videoType->setCheckState( 0, Qt::Unchecked );
    otherType->setExpanded( true ); otherType->setCheckState( 0, Qt::Unchecked );

    QTreeWidgetItem *currentItem = NULL;

    int i_temp = 0;
#define aTa( name ) i_temp += addType( name, currentItem, audioType, &qvReg )
#define aTv( name ) i_temp += addType( name, currentItem, videoType, &qvReg )
#define aTo( name ) i_temp += addType( name, currentItem, otherType, &qvReg )

    aTa( ".3ga" ); aTa( ".669" ); aTa( ".a52" ); aTa( ".aac" ); aTa( ".ac3" );
    aTa( ".adt" ); aTa( ".adts" ); aTa( ".aif" ); aTa( ".aifc" ); aTa( ".aiff" );
    aTa( ".au" ); aTa( ".amr" ); aTa( ".aob" ); aTa( ".ape" ); aTa( ".caf" );
    aTa( ".cda" ); aTa( ".dts" ); aTa( ".flac" ); aTa( ".it" ); aTa( ".m4a" );
    aTa( ".m4p" ); aTa( ".mid" ); aTa( ".mka" ); aTa( ".mlp" ); aTa( ".mod" );
    aTa( ".mp1" ); aTa( ".mp2" ); aTa( ".mp3" ); aTa( ".mpc" ); aTa( ".mpga" );
    aTa( ".oga" ); aTa( ".oma" ); aTa( ".opus" ); aTa( ".qcp" ); aTa( ".ra" );
    aTa( ".rmi" ); aTa( ".snd" ); aTa( ".s3m" ); aTa( ".spx" ); aTa( ".tta" );
    aTa( ".voc" ); aTa( ".vqf" ); aTa( ".w64" ); aTa( ".wav" ); aTa( ".wma" );
    aTa( ".wv" ); aTa( ".xa" ); aTa( ".xm" );
    audioType->setCheckState( 0, ( i_temp > 0 ) ?
                              ( ( i_temp == audioType->childCount() ) ?
                               Qt::Checked : Qt::PartiallyChecked )
                            : Qt::Unchecked );

    i_temp = 0;
    aTv( ".3g2" ); aTv( ".3gp" ); aTv( ".3gp2" ); aTv( ".3gpp" ); aTv( ".amrec" );
    aTv( ".amv" ); aTv( ".asf" ); aTv( ".avi" ); aTv( ".bik" ); aTv( ".divx" );
    aTv( ".drc" ); aTv( ".dv" ); aTv( ".f4v" ); aTv( ".flv" ); aTv( ".gvi" );
    aTv( ".gxf" ); aTv( ".m1v" ); aTv( ".m2t" ); aTv( ".m2v" ); aTv( ".m2ts" );
    aTv( ".m4v" ); aTv( ".mkv" ); aTv( ".mov" ); aTv( ".mp2v" ); aTv( ".mp4" );
    aTv( ".mp4v" ); aTv( ".mpa" ); aTv( ".mpe" ); aTv( ".mpeg" ); aTv( ".mpeg1" );
    aTv( ".mpeg2" ); aTv( ".mpeg4" ); aTv( ".mpg" ); aTv( ".mpv2" ); aTv( ".mts" );
    aTv( ".mtv" ); aTv( ".mxf" ); aTv( ".nsv" ); aTv( ".nuv" ); aTv( ".ogg" );
    aTv( ".ogm" ); aTv( ".ogx" ); aTv( ".ogv" ); aTv( ".rec" ); aTv( ".rm" );
    aTv( ".rmvb" ); aTv( ".rpl" ); aTv( ".thp" ); aTv( ".tod" ); aTv( ".ts" );
    aTv( ".tts" ); aTv( ".vob" ); aTv( ".vro" ); aTv( ".webm" ); aTv( ".wmv" );
    aTv( ".xesc" );
    videoType->setCheckState( 0, ( i_temp > 0 ) ?
                              ( ( i_temp == videoType->childCount() ) ?
                               Qt::Checked : Qt::PartiallyChecked )
                            : Qt::Unchecked );

    i_temp = 0;
    aTo( ".asx" ); aTo( ".b4s" ); aTo( ".cue" ); aTo( ".ifo" ); aTo( ".m3u" );
    aTo( ".m3u8" ); aTo( ".pls" ); aTo( ".ram" ); aTo( ".sdp" ); aTo( ".vlc" );
    aTo( ".wvx" ); aTo( ".xspf" );
    otherType->setCheckState( 0, ( i_temp > 0 ) ?
                              ( ( i_temp == otherType->childCount() ) ?
                               Qt::Checked : Qt::PartiallyChecked )
                            : Qt::Unchecked );

#undef aTo
#undef aTv
#undef aTa

    connect( filetypeList, &QTreeWidget::itemChanged, this, &SPrefsPanel::updateCheckBoxes );

    QDialogButtonBox *buttonBox = new QDialogButtonBox( d );
    QPushButton *closeButton = new QPushButton( qtr( "&Apply" ) );
    QPushButton *clearButton = new QPushButton( qtr( "&Cancel" ) );
    buttonBox->addButton( closeButton, QDialogButtonBox::AcceptRole );
    buttonBox->addButton( clearButton, QDialogButtonBox::ActionRole );

    assoLayout->addWidget( buttonBox, 1, 2, 1, 2 );

    connect( closeButton, &QPushButton::clicked, [=]() {
        this->saveAsso();
        d->reject();
    } );
    d->resize( 300, 400 );
    d->exec();
    listAsso.clear();
}

void SPrefsPanel::updateCheckBoxes(QTreeWidgetItem* item, int column)
{
    if( column != 0 )
        return;

    /* temporarily block signals to avoid signal loops */
    bool b_signalsBlocked = item->treeWidget()->blockSignals(true);

    /* A parent checkbox was changed */
    if( item->parent() == 0 )
    {
        Qt::CheckState checkState = item->checkState(0);
        for( int i = 0; i < item->childCount(); i++ )
        {
            item->child(i)->setCheckState(0, checkState);
        }
    }

    /* A child checkbox was changed */
    else
    {
        bool b_diff = false;
        for( int i = 0; i < item->parent()->childCount(); i++ )
        {
            if( i != item->parent()->indexOfChild(item) && item->checkState(0) != item->parent()->child(i)->checkState(0) )
            {
                b_diff = true;
                break;
            }
        }

        if( b_diff )
            item->parent()->setCheckState(0, Qt::PartiallyChecked);
        else
            item->parent()->setCheckState(0, item->checkState(0));
    }

    /* Stop signal blocking */
    item->treeWidget()->blockSignals(b_signalsBlocked);
}

void addAsso( QVLCRegistry *qvReg, const char *psz_ext )
{
    QString s_path( "VLC" ); s_path += psz_ext;
    QString s_path2 = s_path;

    /* Save a backup if already assigned */
    char *psz_value = qvReg->ReadRegistry( psz_ext, "", ""  );

    if( !EMPTY_STR(psz_value) && strcmp( qtu(s_path), psz_value ) )
        qvReg->WriteRegistry( psz_ext, "VLC.backup", psz_value );
    free( psz_value );

    /* Put a "link" to VLC.EXT as default */
    qvReg->WriteRegistry( psz_ext, "", qtu( s_path ) );

    /* Create the needed Key if they weren't done in the installer */
    if( !qvReg->RegistryKeyExists( qtu( s_path ) ) )
    {
        qvReg->WriteRegistry( psz_ext, "", qtu( s_path ) );
        qvReg->WriteRegistry( qtu( s_path ), "", "Media file" );
        qvReg->WriteRegistry( qtu( s_path.append( "\\shell" ) ), "", "Play" );

        /* Get the installer path */
        QVLCRegistry qvReg2( HKEY_LOCAL_MACHINE );
        QString str_temp = qvReg2.ReadRegistry( "Software\\VideoLAN\\VLC", "", "" );

        if( str_temp.size() )
        {
            qvReg->WriteRegistry( qtu( s_path.append( "\\Play\\command" ) ),
                "", qtu( str_temp.append(" --started-from-file \"%1\"" ) ) );

            qvReg->WriteRegistry( qtu( s_path2.append( "\\DefaultIcon" ) ),
                        "", qtu( str_temp.append(",0") ) );
        }
    }
}

void delAsso( QVLCRegistry *qvReg, const char *psz_ext )
{
    QString s_path( "VLC"); s_path += psz_ext;
    char *psz_value = qvReg->ReadRegistry( psz_ext, "", "" );

    if( psz_value && !strcmp( qtu(s_path), psz_value ) )
    {
        free( psz_value );
        psz_value = qvReg->ReadRegistry( psz_ext, "VLC.backup", "" );
        if( psz_value )
            qvReg->WriteRegistry( psz_ext, "", psz_value );

        qvReg->DeleteValue( psz_ext, "VLC.backup" );
    }
    free( psz_value );
}

void SPrefsPanel::saveAsso()
{
    QVLCRegistry qvReg( HKEY_CLASSES_ROOT );
    for( int i = 0; i < listAsso.size(); i ++ )
    {
        if( listAsso[i]->checkState( 0 ) > 0 )
        {
            addAsso( &qvReg, qtu( listAsso[i]->text( 0 ) ) );
        }
        else
        {
            delAsso( &qvReg, qtu( listAsso[i]->text( 0 ) ) );
        }
    }
    /* Gruik ? Naaah */
    qobject_cast<QDialog *>(listAsso[0]->treeWidget()->parent())->accept();
}

#endif /* _WIN32 */

void SPrefsPanel::MLaddNewFolder() {
    const QUrl homeDirectory = QUrl::fromLocalFile(QDir::homePath());
    QUrl newEntryPoint = QFileDialog::getExistingDirectoryUrl( this
                                                              , qtr("Please choose an entry point folder")
                                                              , homeDirectory );

    if(! newEntryPoint.isEmpty() )
        mlFoldersEditor->add( newEntryPoint );
}

void SPrefsPanel::MLBanFolder( ) {
    const QUrl homeDirectory = QUrl::fromLocalFile(QDir::homePath());
    QUrl newEntryPoint = QFileDialog::getExistingDirectoryUrl( this
                                                              , qtr("Please choose an entry point folder")
                                                              , homeDirectory );

    if(! newEntryPoint.isEmpty() )
        mlBannedFoldersEditor->add( newEntryPoint );
}
