/*****************************************************************************
 * Copyright (C) 2021 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * ( at your option ) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#include "firstrunwizard.hpp"
#include "util/color_scheme_model.hpp"
#include "maininterface/mainctx.hpp"
#include "dialogs/toolbar/controlbar_profile_model.hpp"
#include "medialibrary/medialib.hpp"
#include "dialogs/preferences/preferences_widgets.hpp"

#include <QPushButton>
#include <QButtonGroup>
#include <QFileDialog>
#include <QTreeWidget>
#include <QHeaderView>
#include <QVBoxLayout>
#include <QGridLayout>
#include <QLineEdit>
#include <QLabel>
#include <QPainter>
#include <QPainterPath>
#include <QApplication>
#include <QLinearGradient>
#include <QKeySequence>

#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_url.h>
#include <vlc_cxx_helpers.hpp>

FirstRunWizard::FirstRunWizard( qt_intf_t *_p_intf, QWidget *parent)
               : QWizard( parent )
{
    p_intf = _p_intf;

    /* Set windown properties */
    setWindowTitle( qtr( "Welcome" ) );
    setWindowModality( Qt::WindowModal );

    // NOTE: Aero style seems to be incompatible with
    //       Qt Modern Windows Style dark mode
    setWizardStyle(QWizard::ModernStyle);
    // Navigation labels are published by the onboarding Figma frames.
    setButtonText( QWizard::NextButton, qtr("Next") );
    setButtonText( QWizard::BackButton, qtr("Back") );
    setButtonText( QWizard::FinishButton, qtr("Finish") );

    /* Build the Ui */
    ui.setupUi( this );
    // QWizard owns its internal layout; it does not expose a QWidget layout
    // during construction. Apply Figma's footer margins through the public API.
    setContentsMargins( 0, 0, 62, 56 );
    for( auto role : {QWizard::NextButton, QWizard::BackButton, QWizard::FinishButton} )
        button(role)->setFixedSize( 100, 32 );

    // Qt's native wizard header derives point sizes from the application font;
    // use the existing source labels in the page when the app uses pixel fonts.
    ui.welcomePage->setTitle( QString() );
    ui.folderPage->setTitle( QString() );
    ui.colorSchemePage->setTitle( QString() );
    ui.layoutPage->setTitle( QString() );
    ui.colorLabel->hide();
    ui.policy->setFrameShape( QFrame::NoFrame );

    // Welcome copy, cone and geometry are from Figma 1899:3055.
    auto intro = new QWizardPage( this );
    auto intro_layout = new QVBoxLayout( intro );
    intro_layout->setContentsMargins( 62, 72, 62, 24 );
    intro_layout->setSpacing( 32 );
    auto cone = new QLabel( intro );
    cone->setPixmap( QPixmap(QStringLiteral(":/redesign/icons/onboarding-cone.svg")) );
    cone->setFixedSize( 141, 141 );
    intro_layout->addWidget( cone, 0, Qt::AlignHCenter );
    auto welcome = new QLabel( qtr("Welcome to VLC!"), intro );
    QFont welcome_font = QApplication::font();
    welcome_font.setPixelSize( 32 );
    welcome_font.setWeight( QFont::Light );
    welcome->setFont( welcome_font );
    intro_layout->addWidget( welcome, 0, Qt::AlignHCenter );
    auto introduction = new QLabel( qtr("VLC is a free and open source cross-platform multimedia player and framework "
        "that plays most multimedia files as well as DVDs, Audio CDs, VCDs, and various streaming protocols."), intro );
    introduction->setWordWrap( true );
    introduction->setFixedWidth( 595 );
    QFont body_font = QApplication::font();
    body_font.setPixelSize( 16 );
    body_font.setWeight( QFont::Light );
    introduction->setFont( body_font );
    QSizePolicy wrapped_policy( QSizePolicy::Fixed, QSizePolicy::MinimumExpanding );
    wrapped_policy.setHeightForWidth( true );
    introduction->setSizePolicy( wrapped_policy );
    introduction->setMinimumHeight( introduction->heightForWidth(595) );
    intro_layout->addWidget( introduction, 0, Qt::AlignHCenter );
    auto folder_area = new QWidget( intro );
    folder_area->setFixedWidth( 595 );
    auto folder_layout = new QGridLayout( folder_area );
    folder_layout->setContentsMargins( 0, 0, 0, 0 );
    folder_layout->setHorizontalSpacing( 10 );
    folder_layout->setVerticalSpacing( 16 );
    folder_layout->addWidget( new QLabel(qtr("Choose a Media Folder to get started with"), folder_area), 0, 0, 1, 2 );
    m_introFolder = new QLineEdit( folder_area );
    m_introFolder->setReadOnly( true );
    m_introFolder->setMinimumHeight( 36 );
    folder_layout->addWidget( m_introFolder, 1, 0 );
    auto browse_folder = new QPushButton( qtr("Browse"), folder_area );
    browse_folder->setMinimumHeight( 36 );
    browse_folder->setFixedWidth( 114 );
    folder_layout->addWidget( browse_folder, 1, 1 );
    folder_area->setVisible( vlc_ml_instance_get(p_intf) != nullptr );
    connect( browse_folder, &QPushButton::clicked, this, &FirstRunWizard::MLaddNewFolder );
    intro_layout->addWidget( folder_area, 0, Qt::AlignHCenter );
    intro_layout->addStretch();
    setPage( INTRO_PAGE, intro );
    setStartId( INTRO_PAGE );
    resize( 1090, 759 );

    // Figma 1902:6770 defines the two-column guide; values use live config.
    auto shortcuts_page = new QWizardPage( this );
    auto shortcuts_layout = new QVBoxLayout( shortcuts_page );
    shortcuts_layout->setContentsMargins( 62, 44, 62, 24 );
    shortcuts_layout->setSpacing( 40 );
    auto guide_title = new QLabel( qtr("Learn the basic keyboard shortcuts."), shortcuts_page );
    QFont guide_font = QApplication::font();
    guide_font.setPixelSize( 24 );
    guide_title->setFont( guide_font );
    shortcuts_layout->addWidget( guide_title, 0, Qt::AlignHCenter );
    auto shortcuts = new QWidget( shortcuts_page );
    shortcuts->setObjectName( QStringLiteral("onboardingShortcuts") );
    auto shortcut_grid = new QGridLayout( shortcuts );
    shortcut_grid->setHorizontalSpacing( 20 ); // Figma's space between labels and bindings.
    shortcut_grid->setVerticalSpacing( 16 );
    struct GuideRow { const char *title; const char *first; const char *second; int column; };
    const GuideRow actions[] = {
        {N_("Play / Pause"), "key-play-pause", nullptr, 0},
        {N_("Seek Backward / Forward"), "key-jump-short", "key-jump+short", 0},
        {N_("Previous / Next Item"), "key-prev", "key-next", 0},
        {N_("Previous / Next Frame"), "key-frame-previous", "key-frame-next", 0},
        {N_("Cycle Subtitle Track"), "key-subtitle-track", nullptr, 0},
        {N_("Cycle Audio Track"), "key-audio-track", nullptr, 0},
        {N_("Toggle Fullscreen"), "key-toggle-fullscreen", nullptr, 1},
        {N_("Increase / Decrease Volume"), "key-vol-up", "key-vol-down", 1},
        {N_("Show / Hide Queue"), nullptr, nullptr, 1},
        {N_("Take a Snapshot"), "key-snapshot", nullptr, 1},
        {N_("Record"), "key-record", nullptr, 1}
    };
    int rows[] = {0, 0};
    for( const auto &action : actions )
    {
        if( action.first && !config_FindConfig(action.first) )
            continue;
        auto label = new QLabel( qfut(action.title), shortcuts );
        label->setFont( body_font );
        label->setMinimumWidth( label->fontMetrics().horizontalAdvance(label->text()) );
        auto caps = new QWidget( shortcuts );
        // Actual configured combinations can be much longer than Figma's
        // sample keys. Give paired bindings separate rows rather than cropping.
        auto caps_layout = new QBoxLayout( action.second ? QBoxLayout::TopToBottom : QBoxLayout::LeftToRight, caps );
        caps_layout->setContentsMargins( 0, 0, 0, 6 );
        caps_layout->setSpacing( action.second ? 6 : 10 );
        for( const char *name : {action.first, action.second} )
        {
            if( !name && action.first )
                continue;
            QString keys;
            if( name )
            {
                auto binding = vlc::wrap_cptr( config_GetPsz(name) );
                keys = qfu(binding.get());
            }
            else
                // The original menus/qml/GlobalShortcuts.qml sequence, displayed
                // by Qt's platform-native formatter (Command on macOS).
                keys = QKeySequence(QStringLiteral("Ctrl+L")).toString(QKeySequence::NativeText);
            auto cap = new QLabel( keys.replace('\t', QStringLiteral(", ")), caps );
            cap->setObjectName( QStringLiteral("onboardingKeycap") );
            cap->setAlignment( Qt::AlignCenter );
            cap->setFont( body_font );
            cap->setMinimumWidth( cap->fontMetrics().horizontalAdvance(cap->text()) + 30 );
            cap->setSizePolicy( QSizePolicy::MinimumExpanding, QSizePolicy::Preferred );
            cap->setMinimumHeight( 40 );
            cap->setStyleSheet( QStringLiteral("border-radius: 12px; padding: 4px 12px;") );
            caps_layout->addWidget( cap );
            if( !action.first )
                break;
        }
        if( !action.second )
            caps_layout->addStretch();
        shortcut_grid->addWidget( label, rows[action.column], action.column * 2 );
        shortcut_grid->addWidget( caps, rows[action.column]++, action.column * 2 + 1 );
    }
    shortcuts_layout->addWidget( shortcuts );
    shortcuts_layout->addStretch();
    shortcuts_layout->addWidget( new QLabel(qtr("Find the full list in the menu."), shortcuts_page) );
    setPage( HOTKEYS_PAGE, shortcuts_page );
    for( auto label : {ui.privacy, ui.folderLabel, ui.layoutLabel} )
    {
        label->setFont( guide_font );
        label->setWordWrap( true );
        label->setMinimumHeight( label->fontMetrics().height() );
    }
    ui.addButton->setMinimumSize( 32, 32 );
    ui.addButton->setMaximumSize( 32, 32 );
    ui.addButton->setStyleSheet( QStringLiteral("padding: 0;") );

    /* Set the privacy and network policy */
    ui.policy->setHtml( qtr( "<p>In order to protect your privacy, <i>VLC media player</i> "
        "does <b>not</b> collect personal data or transmit them, "
        "not even in anonymized form, to anyone."
        "</p>\n"
        "<p>Nevertheless, <i>VLC</i> is able to automatically retrieve "
        "information about the media in your play queue from third party "
        "Internet-based services. This includes cover art, track names, "
        "artist names and other meta-data."
        "</p>\n"
        "<p>Consequently, this may entail identifying some of your media files to third party "
        "entities. Therefore the <i>VLC</i> developers require your express "
        "consent for the media player to access the Internet automatically."
        "</p>\n" ) );
    ui.policy->setReadOnly( true );

    /* Set up the button group for colour schemes. */
    /* Creating in Qt Designer has unstable ordering when calling buttons() */
    colorSchemeGroup = new QButtonGroup( this );
    colorSchemeGroup->addButton( ui.systemButton );
    colorSchemeGroup->addButton( ui.lightButton );
    colorSchemeGroup->addButton( ui.darkButton );
    colorSchemeGroup->setExclusive( true );

    colorSchemeImages = new QButtonGroup( this );
    colorSchemeImages->addButton( ui.daynightImage );
    colorSchemeImages->addButton( ui.lightImage );
    colorSchemeImages->addButton( ui.darkImage );

    // The theme-card geometry, fills, type and copy are from Figma 1902:3670.
    // Keep the original radio choices and model IDs, including System by default.
    delete ui.colorSchemePage->layout();
    ui.colorSchemePage->setTitle( QString() );
    auto theme_layout = new QVBoxLayout( ui.colorSchemePage );
    theme_layout->setContentsMargins( 62, 44, 62, 24 );
    theme_layout->setSpacing( 40 );
    auto theme_title = new QLabel( qtr("Select your preferred theme and color."), ui.colorSchemePage );
    auto theme_font = guide_font;
    theme_font.setWeight( QFont::Light );
    theme_title->setFont( theme_font );
    theme_layout->addWidget( theme_title, 0, Qt::AlignHCenter );
    theme_layout->addStretch();
    auto theme_cards = new QHBoxLayout;
    theme_cards->setSpacing( 40 );
    theme_cards->addStretch();
    for( auto pair : {qMakePair(ui.lightImage, ui.lightButton), qMakePair(ui.darkImage, ui.darkButton),
                     qMakePair(ui.daynightImage, ui.systemButton)} )
    {
        auto card = new QVBoxLayout;
        card->setSpacing( 22 );
        const qreal ratio = devicePixelRatioF();
        QPixmap sample( QSize(100, 100) * ratio );
        sample.setDevicePixelRatio( ratio );
        sample.fill( Qt::transparent );
        QPainter painter( &sample );
        painter.setRenderHint( QPainter::Antialiasing );
        QPainterPath shape;
        shape.addRoundedRect( QRectF(0, 0, 100, 100), 12, 12 );
        if( pair.first == ui.daynightImage )
        {
            // Figma's 238.72740368986226deg hard-stop diagonal theme sample.
            QLinearGradient fill( QPointF(100, 19.64), QPointF(0, 80.36) );
            fill.setColorAt( 0, QColor("#AFAFAF") );
            fill.setColorAt( 0.52411, QColor("#AFAFAF") );
            fill.setColorAt( 0.52412, QColor("#222222") );
            fill.setColorAt( 1, QColor("#222222") );
            painter.fillPath( shape, fill );
        }
        else
            painter.fillPath( shape, pair.first == ui.lightImage ? QColor("#AFAFAF") : QColor("#222222") );
        painter.end();
        pair.first->setIcon( QIcon(sample) );
        pair.first->setObjectName( QStringLiteral("onboardingThemeCard") );
        pair.first->setIconSize( QSize(100, 100) );
        pair.first->setFixedSize( 124, 124 );
        pair.first->setCheckable( true );
        pair.first->setAutoExclusive( true );
        pair.first->setStyleSheet( QStringLiteral("QPushButton { background: transparent;"
            "border-radius: 19px; padding: 8px; }") );
        pair.second->setFont( body_font );
        card->addWidget( pair.first, 0, Qt::AlignHCenter );
        card->addWidget( pair.second, 0, Qt::AlignHCenter );
        connect( pair.second, &QRadioButton::toggled, pair.first, &QPushButton::setChecked );
        pair.first->setChecked( pair.second->isChecked() );
        theme_cards->addLayout( card );
    }
    theme_cards->addStretch();
    theme_layout->addLayout( theme_cards );
    ui.explainerLabel->setFixedWidth( 595 );
    ui.explainerLabel->setSizePolicy( wrapped_policy );
    ui.explainerLabel->setMinimumHeight( ui.explainerLabel->heightForWidth(595) );
    theme_layout->addWidget( ui.explainerLabel, 0, Qt::AlignHCenter );
    theme_layout->addStretch();
    if( auto option = config_FindConfig("qt-accent-color") )
    {
        m_accentValue = new QLineEdit( ui.colorSchemePage );
        m_accentValue->setText( qfu(option->value.psz) );
        m_accentValue->hide();
        theme_layout->addWidget( createAccentColorSelector(ui.colorSchemePage, m_accentValue, 64), 0, Qt::AlignLeft );
    }

    /* Setup the layout page */
    ui.modernImage->hide();
    ui.classicImage->hide();
    ui.layoutGroup->setId( ui.modernButton, 0 );
    ui.layoutGroup->setId( ui.classicButton, 1 );

    layoutImages = new QButtonGroup( this );
    layoutImages->addButton( ui.modernImage );
    layoutImages->addButton( ui.classicImage );
    layoutImages->setId( ui.modernImage, MODERN );
    layoutImages->setId( ui.classicImage, CLASSIC );

    /* Set the tooltips for each of the layout choices */
    ui.classicButton->setToolTip( qtr("<ul>"
                                      "<li>No client-side decoration</li>"
                                      "<li>Toolbar menu</li>"
                                      "<li>Pinned video controls</li>"
                                      "</ul>") );

    ui.modernButton->setToolTip( qtr("<ul>"
                                     "<li>Client-side decoration</li>"
                                     "<li>No toolbar menu</li>"
                                     "<li>Video controls unpinned</li>"
                                     "</ul>") );

    /* Remove the cancel button */
    setOption( QWizard::NoCancelButton );

    /* Create new instance of MLFoldersModel */
    if ( vlc_ml_instance_get( p_intf ) )
    {
        const auto foldersModel = new MLFoldersModel( this );
        foldersModel->setCtx( p_intf->p_mi );
        ui.entryPoints->setMLFoldersModel( foldersModel );
        mlFoldersEditor = ui.entryPoints;
        mlFoldersModel = foldersModel;
    }
    else
    {
        ui.enableMl->setChecked( false );
    }

    /* Disable the ML button as toggling doesn't actually do anything */
    ui.enableMl->setEnabled(false);
    ui.enableMl->hide(); // Keep its existing route/default state, without a nonfunctional control.

    /* Slots and Signals */
    connect( ui.addButton, &QPushButton::clicked, this, &FirstRunWizard::MLaddNewFolder );
    connect( colorSchemeGroup, qOverload<QAbstractButton*>( &QButtonGroup::buttonClicked ), this, &FirstRunWizard::updateColorLabel );
    connect( colorSchemeImages, qOverload<QAbstractButton*>( &QButtonGroup::buttonClicked ), this, &FirstRunWizard::imageColorSchemeClick );
    connect( ui.layoutGroup, qOverload<QAbstractButton*>( &QButtonGroup::buttonClicked ), this, &FirstRunWizard::updateLayoutLabel );
    connect( layoutImages, qOverload<QAbstractButton*>( &QButtonGroup::buttonClicked ), this, &FirstRunWizard::imageLayoutClick );
    connect( this->button(QWizard::FinishButton), &QPushButton::clicked, this, &FirstRunWizard::finish );
}

/**
 * Function called when the finish button is pressed.
 * Processes all inputted settings according to chosen options
 */
void FirstRunWizard::finish()
{
    /* Welcome Page settings  */
    config_PutInt( "metadata-network-access", ui.privacyCheckbox->isChecked() );
    config_PutInt( "qt-privacy-ask", 0 );

    /* Colour Page settings */
    p_intf->p_mi->getColorScheme()->setCurrentIndex( colorSchemeGroup->checkedId() );
    if( m_accentValue )
        config_PutPsz( "qt-accent-color", qtu(m_accentValue->text()) );

    /* Layout Page settings */
    config_PutInt( "qt-menubar", ui.layoutGroup->checkedId() );
    config_PutInt( "qt-titlebar", ui.layoutGroup->checkedId() );

    config_PutInt( "qt-pin-controls", ui.layoutGroup->checkedId() );

    {
        ControlbarProfileModel* controlbarModel = p_intf->p_mi->controlbarProfileModel();
        assert(controlbarModel);

        ControlbarProfileModel::Style style;
        if( ui.layoutGroup->checkedId() )
            style = ControlbarProfileModel::Style::CLASSIC_STYLE;
        else
            style = ControlbarProfileModel::Style::DEFAULT_STYLE;

        std::unique_ptr<ControlbarProfile> profile( controlbarModel->generateProfileFromStyle( style ) );
        assert( profile );
        const std::optional<int> index = controlbarModel->findModel( profile.get() );
        if( index )
            controlbarModel->setSelectedProfile( *index );
        else
            controlbarModel->insertProfile( std::move( profile ), true );
    }

    /* Commit changes to the scanned folders for the Media Library */
    if( vlc_ml_instance_get( p_intf ) && mlFoldersEditor )
        mlFoldersEditor->commit();

    /* Reload the indexing service for the media library */
    if( p_intf->p_mi->getMediaLibrary() )
        p_intf->p_mi->getMediaLibrary()->reload();

    p_intf->p_mi->reloadPrefs();
    p_intf->p_mi->controlbarProfileModel()->save();
    config_SaveConfigFile( p_intf );
}

/**
 * Opens a QFileDialog for the user to select a folder to add to the Media Library
 * If a folder is selected, add it to the list of folders under MLFoldersEditor
 */
void FirstRunWizard::MLaddNewFolder()
{
    if( !mlFoldersEditor )
        return;
    QUrl newEntryPoint = QFileDialog::getExistingDirectoryUrl( this, qtr("Choose a folder to add to the Media Library"),
                                                               QUrl( QDir::homePath() ));

    if( !newEntryPoint.isEmpty() )
    {
        addDefaults(); // Preserve the original folder-page defaults before adding a choice.
        if( !mlFoldersEditor->contains( newEntryPoint ) )
            mlFoldersEditor->add( newEntryPoint );
        m_introFolder->setText( newEntryPoint.toDisplayString(QUrl::PreferLocalFile) );
    }
}

/**
 * Automatically updates the label on the color scheme page depending
 * on the currently selected radio button choice
 * @param id The id of the button we are updating the label of
 */
void FirstRunWizard::updateColorLabel( QAbstractButton* btn )
{
    switch ( colorSchemeGroup->id(btn) )
    {
        case ColorSchemeModel::System:
            ui.explainerLabel->setText( qtr( "<i>VLC will automatically switch to dark mode accordingly with system settings</i>" ) );
            break;
        case ColorSchemeModel::Day:
            ui.explainerLabel->setText( qtr( "<i>VLC will automatically use light mode</i>" ) );
            break;
        case ColorSchemeModel::Night:
            ui.explainerLabel->setText( qtr( "<i>VLC will automatically use dark mode</i>" ) );
            break;
    }
}

/**
 * Automatically updates the label depending on the currently selected layout
 * @param id The id of the button we are updating the label of
 */
void FirstRunWizard::updateLayoutLabel( QAbstractButton* btn )
{
    switch ( ui.layoutGroup->id( btn ) )
    {
        case MODERN:
            ui.layoutExplainer->setText( qtr( "<i>VLC will use a modern layout with no menubar or pinned controls but with client-side decoration</i>" ) );
            break;
        case CLASSIC:
            ui.layoutExplainer->setText( qtr( "<i>VLC will use a classic layout with a menubar and pinned controls but with no client-side decoration</i>" ) );
            break;
    }
}

/**
 * Checks the correct button when the corresponding image is clicked
 * for the color scheme page.
 * @param id The id of the image that was clicked
 */
void FirstRunWizard::imageColorSchemeClick( QAbstractButton* btn )
{
    QAbstractButton* groupBtn = colorSchemeGroup->buttons().at( colorSchemeImages->id( btn ) );
    assert( groupBtn );
    groupBtn->setChecked( true );
    updateColorLabel( groupBtn );
}

/**
 * Checks the correct button when the corresponding image is clicked
 * for the layouts page.
 * @param id The id of the image that was clicked
 */
void FirstRunWizard::imageLayoutClick( QAbstractButton* btn )
{
    QAbstractButton* layoutBtn = ui.layoutGroup->buttons().at( layoutImages->id( btn ) );
    assert( layoutBtn );
    layoutBtn->setChecked( true );
    updateLayoutLabel( layoutBtn );
}

/**
 * Defines the navigation of pages for the wizard
 * @return int - the page id to go to or -1 if we are done
 */
int FirstRunWizard::nextId() const
{
    switch ( currentId() )
    {
        case INTRO_PAGE:
            return WELCOME_PAGE;
        case WELCOME_PAGE:
            if( ui.enableMl->isChecked() )
                return FOLDER_PAGE;
            else
                return COLOR_SCHEME_PAGE;
        case FOLDER_PAGE:
            return COLOR_SCHEME_PAGE;
        case COLOR_SCHEME_PAGE:
            return LAYOUT_PAGE;
        case LAYOUT_PAGE:
            return HOTKEYS_PAGE;
        default:
            return -1;
    }
}

/**
 * Sets up the buttons and options for the color scheme page
 * Needs to be set up later or else the main interface hasn't been created yet
 * Color schemes are always in the order system/auto, day then night
 */
void FirstRunWizard::initializePage( int id )
{
    if(id == COLOR_SCHEME_PAGE)
    {
        QVector<ColorSchemeModel::Item> schemes = p_intf->p_mi->getColorScheme()->getSchemes();
        auto schemeButtons = colorSchemeGroup->buttons();
        auto schemeImages = colorSchemeImages->buttons();

        /* Number of buttons should be equal to the schemes we can choose from */
        assert( schemes.size() == schemeButtons.size() );
        assert( schemes.size() == schemeImages.size() );

        for( int i = 0; i < schemes.size(); i++ )
        {
            colorSchemeGroup->setId( schemeButtons.at(i), schemes.at(i).scheme );
            colorSchemeImages->setId( schemeImages.at(i), schemes.at(i).scheme );
            // Display names come from Figma 1902:3670; model IDs stay unchanged.
            schemeButtons.at(i)->setText( schemes.at(i).scheme == ColorSchemeModel::System ? qtr("System") :
                schemes.at(i).scheme == ColorSchemeModel::Day ? qtr("Light") : qtr("Dark") );
            if( !i ) updateColorLabel( schemeButtons.at(i) );
        }
    }
    else if ( id == FOLDER_PAGE )
        addDefaults();
}

/**
 * Processes the default options on rejection of the FirstRun Wizard.
 * The default options are:
 * - Yes to metadata
 * - System/Auto colour scheme
 * - Modern VLC layout
 */
void FirstRunWizard::reject()
{
    assert(p_intf->p_mi);
    /* Welcome Page settings  */
    config_PutInt( "metadata-network-access", 1 );
    config_PutInt( "qt-privacy-ask", 0 );

    /* Colour Page settings */
    p_intf->p_mi->getColorScheme()->setCurrentIndex( 0 );

    /* Layout Page settings */
    config_PutInt( "qt-menubar", 0 );
    config_PutInt( "qt-titlebar", 0 );
    p_intf->p_mi->setPinVideoControls( 0 );

    if( p_intf->p_mi->getMediaLibrary() )
        p_intf->p_mi->getMediaLibrary()->reload();

    config_SaveConfigFile( p_intf );
    p_intf->p_mi->reloadPrefs();
    p_intf->p_mi->controlbarProfileModel()->save();

    done( QDialog::Rejected );
}

/**
 * Adds the default folders to the media library
 */
void FirstRunWizard::addDefaults()
{
    // Return if we already set the defaults or something is null
    if( mlDefaults || !mlFoldersEditor || mlFoldersEditor->rowCount() )
        return;

    for( auto&& target : { VLC_VIDEOS_DIR, VLC_MUSIC_DIR } )
    {
        auto folder = vlc::wrap_cptr( config_GetUserDir( target ) );
        if( folder == nullptr )
            continue;
        auto folderMrl = vlc::wrap_cptr( vlc_path2uri( folder.get(), nullptr ) );
        if ( !mlFoldersEditor->contains( QUrl( folderMrl.get() ) ) )
            mlFoldersEditor->add( QUrl( folderMrl.get() ) );
    }

    mlDefaults = true;
}
