/*****************************************************************************
 * VLCMainVideoViewControlsBar.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2023 VLC authors and VideoLAN
 *
 * Authors: Claudio Cambra <developer@claudiocambra.com>
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

#import "VLCMainVideoViewControlsBar.h"
#import "views/VLCRedesignBooleanControl.h"
#import "windows/controlsbar/VLCPlayerPresetManager.h"

#import "extensions/NSString+Helpers.h"
#import "views/VLCUIUnits.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "preferences/VLCSimplePrefsWindow.h"

#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"

#import "main/VLCMain.h"

#import "menus/VLCMainMenu.h"

#import "panels/VLCBookmarksWindowController.h"

#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"

#import "windows/video/VLCMainVideoViewController.h"
#import "windows/video/VLCVideoOutputProvider.h"
#import "windows/video/VLCVideoWindowCommon.h"
#import "windows/controlsbar/VLCSleepTimer.h"
#import "views/VLCTimeFormatter.h"
#import "views/VLCPlayerEffectsView.h"
#import "panels/VLCAudioEffectsWindowController.h"
#import "panels/VLCVideoEffectsWindowController.h"

@interface VLCMainVideoViewControlsBar () <NSPopoverDelegate>
{
    VLCPlayQueueController *_playQueueController;
    VLCPlayerController *_playerController;
    NSPopover *_settingsPopover;
    NSSegmentedControl *_settingsTabs;
    NSView *_settingsHeader;
    NSStackView *_settingsTabButtons;
    NSStackView *_settingsBody;
    VLCPlayerPresetManager *_presetManager;
    NSScrollView *_settingsScrollView;
    NSArray<NSMenuItem *> *_settingsMenuItems;
    NSMenu *_settingsRootMenu;
    NSSlider *_settingsDelaySlider;
    NSTextField *_settingsDelayValue;
    NSSlider *_settingsRateSlider;
    NSTextField *_settingsRateValue;
    NSButton *_settingsReverseButton;
    NSButton *_settingsStatisticsButton;
    NSButton *_settingsSleepTimerButton;
    __weak VLCMainVideoViewController *_settingsVideoController;
    BOOL _settingsPreviousAutohide;
}

@property (readonly) NSImageSymbolConfiguration *mainButtonsSymbolConfig API_AVAILABLE(macos(26.0));

@end

@implementation VLCMainVideoViewControlsBar

- (void)awakeFromNib
{
    [super awakeFromNib];

    self.bookmarksButton.toolTip = _NS("Bookmarks");
    self.bookmarksButton.accessibilityLabel = self.bookmarksButton.toolTip;

    self.subtitlesButton.toolTip = _NS("Subtitles");
    self.subtitlesButton.accessibilityLabel = self.subtitlesButton.toolTip;

    self.audioButton.toolTip = _NS("Audio");
    self.audioButton.accessibilityLabel = self.audioButton.toolTip;

    self.videoButton.toolTip = _NS("Video");
    self.videoButton.accessibilityLabel = self.videoButton.toolTip;

    self.lyricsButton.toolTip = _NS("Lyrics");
    self.lyricsButton.accessibilityLabel = self.lyricsButton.toolTip;

    self.playbackRateButton.toolTip = _NS("Playback Rate");
    self.playbackRateButton.accessibilityLabel = self.playbackRateButton.toolTip;

    self.floatOnTopButton.toolTip = _NS("Float on Top");
    self.floatOnTopButton.accessibilityLabel = self.floatOnTopButton.toolTip;

    self.pipButton.toolTip = _NS("Picture in Picture");
    self.pipButton.accessibilityLabel = self.pipButton.toolTip;

    // Keep playback controls quiet and rectangular; retain every existing action.
    NSPointerArray *buttons = NSPointerArray.weakObjectsPointerArray;
    [buttons addPointer:(__bridge void *)self.playButton];
    [buttons addPointer:(__bridge void *)self.backwardButton];
    [buttons addPointer:(__bridge void *)self.forwardButton];
    [buttons addPointer:(__bridge void *)self.jumpBackwardButton];
    [buttons addPointer:(__bridge void *)self.jumpForwardButton];
    [buttons addPointer:(__bridge void *)self.bookmarksButton];
    [buttons addPointer:(__bridge void *)self.subtitlesButton];
    [buttons addPointer:(__bridge void *)self.audioButton];
    [buttons addPointer:(__bridge void *)self.videoButton];
    [buttons addPointer:(__bridge void *)self.lyricsButton];
    [buttons addPointer:(__bridge void *)self.fullscreenButton];
    [buttons addPointer:(__bridge void *)self.floatOnTopButton];
    [buttons addPointer:(__bridge void *)self.playbackRateButton];
    [buttons addPointer:(__bridge void *)self.pipButton];
    [buttons addPointer:(__bridge void *)self.muteVolumeButton];
    [buttons compact];
    for (NSButton *button in buttons) {
        button.bordered = NO;
        button.wantsLayer = YES;
        button.layer.cornerRadius = VLCUIUnits.cornerRadius;
        if (@available(macOS 11.0, *)) {
            NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:16. weight:NSFontWeightMedium];
            button.image = [button.image imageWithSymbolConfiguration:configuration];
            button.alternateImage = [button.alternateImage imageWithSymbolConfiguration:configuration];
        }
        if (@available(macOS 10.14, *)) {
            button.contentTintColor = NSColor.VLCControlForegroundColor;
        }
    }

    self.audioButton.image = [NSImage vlc_redesignImageNamed:@"audio"] ?: self.audioButton.image;
    self.subtitlesButton.image = [NSImage vlc_redesignImageNamed:@"subtitles"] ?: self.subtitlesButton.image;
    self.playbackRateButton.image = [NSImage vlc_redesignImageNamed:@"playback-settings"] ?: self.playbackRateButton.image;
    self.videoButton.hidden = YES;
    self.bookmarksButton.hidden = YES;
    self.floatOnTopButton.hidden = YES;
    self.lyricsButton.hidden = YES;
    _playQueueController = VLCMain.sharedInstance.playQueueController;
    _playerController = _playQueueController.playerController;

    VLCLibraryController * const libraryController = VLCMain.sharedInstance.libraryController;
    self.bookmarksButton.hidden = YES;
    self.bookmarksButton.enabled = libraryController.libraryModel != nil;

    NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(floatOnTopChanged:)
                               name:VLCWindowFloatOnTopChangedNotificationName
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(playbackRateChanged:)
                               name:VLCPlayerRateChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(playbackRateChanged:)
                               name:VLCPlayerCapabilitiesChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(updateAvailableButtons:)
                               name:VLCPlayerCurrentMediaItemChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(updateLyricsButton:)
                               name:VLCPlayerShowLyricsChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(updateLyricsButton:)
                               name:VLCPlayerLyricsAvailableChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(fullscreenChanged:)
                               name:VLCPlayerFullscreenChanged
                             object:nil];

    for (NSString *name in @[VLCPlayerAudioDelayChanged, VLCPlayerSubtitlesDelayChanged,
                             VLCPlayerRateChanged, VLCPlayerCapabilitiesChanged]) {
        [notificationCenter addObserver:self selector:@selector(updateSettingsValues:) name:name object:nil];
    }
    [notificationCenter addObserver:self selector:@selector(settingsTracksChanged:) name:VLCPlayerTrackListChanged object:nil];
    [notificationCenter addObserver:self selector:@selector(updateSettingsValues:) name:VLCSleepTimerChanged object:nil];
    [notificationCenter addObserver:self selector:@selector(updateSettingsValues:) name:VLCPlayerStatisticsUpdated object:nil];
    [notificationCenter addObserver:self selector:@selector(settingsTracksChanged:) name:@"VLCPlayerPresetApplied" object:nil];
    [notificationCenter addObserver:self selector:@selector(settingsWindowResized:) name:NSWindowDidResizeNotification object:nil];
    [self update];
}

- (void)update
{
    [super update];
    [self updateFloatOnTopButton];
    [self updatePlaybackRateButton];
    [self updateLyricsButton:nil];
}

- (void)floatOnTopChanged:(NSNotification *)notification
{
    [self updateFloatOnTopButton];
}

- (void)fullscreenChanged:(NSNotification *)notification
{
    [self updateFloatOnTopButton];
}

- (void)updateLyricsButton:(NSNotification *)notification
{
    const BOOL lyricsAvailable = _playerController.lyricsAvailable;
    self.lyricsButton.enabled = lyricsAvailable;
    self.lyricsButton.hidden = YES;
    self.lyricsButton.state = _playerController.showLyrics ? NSControlStateValueOn : NSControlStateValueOff;

    if (@available(macOS 26.0, *)) {
        self.lyricsButton.bezelColor =
            _playerController.showLyrics ? NSColor.controlAccentColor : nil;
    } else if (@available(macOS 10.14, *)) {
        self.lyricsButton.contentTintColor =
            _playerController.showLyrics ? NSColor.controlAccentColor : nil;
    }
}

- (vout_thread_t *)windowVoutThread
{
    NSWindow * const window = self.floatOnTopButton.window;
    if ([window isKindOfClass:VLCVideoWindowCommon.class]) {
        vout_thread_t * const p_vout =
            ((VLCVideoWindowCommon *)window).videoViewController.voutView.voutThread;
        if (p_vout) return p_vout;
    }
    return _playerController.mainVideoOutputThread;
}

- (void)updateFloatOnTopButton
{
    vout_thread_t * const voutThread = [self windowVoutThread];
    if (voutThread == NULL) {
        return;
    }

    const bool floatOnTopEnabled = var_GetBool(voutThread, "video-on-top");
    vout_Release(voutThread);

    const BOOL isFullscreen = _playerController.fullscreen;
    self.floatOnTopButton.enabled = !isFullscreen;

    if (@available(macOS 26.0, *)) {
        self.floatOnTopButton.bezelColor =
            (floatOnTopEnabled && !isFullscreen) ? NSColor.controlAccentColor : nil;
    } else if (@available(macOS 10.14, *)) {
        self.floatOnTopButton.contentTintColor =
            (floatOnTopEnabled && !isFullscreen) ? NSColor.controlAccentColor : nil;
    }
}

- (void)playbackRateChanged:(NSNotification *)notification
{
    [self updatePlaybackRateButton];
}

- (void)updatePlaybackRateButton
{
    self.playbackRateButton.title = @"";
    self.playbackRateButton.image = [NSImage vlc_redesignImageNamed:@"playback-settings"] ?: self.playbackRateButton.image;
    self.playbackRateButton.enabled = YES;
    self.playbackRateButton.accessibilityValue = [NSString stringWithFormat:@"%.2fx", _playerController.playbackRate];
}

- (void)showSettingsTab:(NSInteger)tab sender:(NSButton *)sender
{
    // Deferred menu/hotkey actions can outlive a classic/compact remount.
    // AppKit requires the anchor to belong to a window before showing a pane.
    NSWindow *hostingWindow=sender.window ?: ((NSView *)self.bottomBarView).window;
    if(!hostingWindow || tab<0 || tab>3)return;
    if ([hostingWindow isKindOfClass:VLCVideoWindowCommon.class])
        [((VLCVideoWindowCommon *)hostingWindow).videoViewController closePlayQueuePane];
    if (_settingsPopover == nil) {
        NSViewController *controller = [[NSViewController alloc] init];
        controller.view = [[NSView alloc] initWithFrame:NSMakeRect(0., 0., 400., 420.)];
        NSView *root = controller.view;
        _settingsTabs = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(12., 380., 376., 28.)];
        _settingsTabs.segmentCount = 4;
        _settingsTabs.segmentStyle = NSSegmentStyleRounded;
        _settingsTabs.trackingMode = NSSegmentSwitchTrackingSelectOne;
        // Tab labels are the existing VLC menu labels and the owner-provided transcript's Playback category.
        NSArray<NSString *> *labels = @[_NS("Playback"), _NS("Video"), _NS("Audio"), _NS("Subtitles")];
        for (NSInteger index = 0; index < labels.count; ++index) {
            [_settingsTabs setLabel:labels[index] forSegment:index];
        }
        _settingsTabs.target = self;
        _settingsTabs.action = @selector(settingsTabChanged:);
        _settingsTabs.hidden = YES;
        [root addSubview:_settingsTabs];

        // Figma Audio536:1059/Video498:2937:50px header,20px exported
        // icons,12px captions,85px Video/Audio tabs and flexible outer tabs.
        _settingsHeader = [[NSView alloc] initWithFrame:NSMakeRect(0., 370., 400., 50.)];
        _settingsHeader.identifier = @"VLCRedesignedSettingsCard";
        _settingsHeader.wantsLayer = YES;
        [root addSubview:_settingsHeader];
        _settingsTabButtons = [NSStackView new];
        _settingsTabButtons.translatesAutoresizingMaskIntoConstraints = NO;
        _settingsTabButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        _settingsTabButtons.distribution = NSStackViewDistributionFill;
        _settingsTabButtons.spacing = 1.;
        [_settingsHeader addSubview:_settingsTabButtons];
        NSArray *icons = @[@"player-tab-playback", @"player-tab-video", @"player-tab-audio", @"player-tab-subtitles"];
        for (NSInteger index = 0; index < labels.count; index++) {
            NSButton *button = [NSButton buttonWithTitle:labels[index] target:self action:@selector(settingsHeaderTabChanged:)];
            button.tag = index;
            button.bordered = NO;
            [button setButtonType:NSButtonTypePushOnPushOff];
            button.image = [NSImage vlc_redesignImageNamed:icons[index]];
            button.image.size = NSMakeSize(20., 20.);
            button.imagePosition = NSImageLeft;
            button.font = [NSFont vlc_redesignFontOfSize:12. weight:NSFontWeightRegular];
            button.identifier = @"VLCRedesignedSettingsCategory";
            button.wantsLayer = YES;
            button.layer.cornerRadius = 6.;
            [_settingsTabButtons addArrangedSubview:button];
            [button.heightAnchor constraintEqualToConstant:38.].active = YES;
            if (index == 1 || index == 2) [button.widthAnchor constraintEqualToConstant:85.].active = YES;
        }
        [_settingsTabButtons.arrangedSubviews.firstObject.widthAnchor constraintEqualToAnchor:_settingsTabButtons.arrangedSubviews.lastObject.widthAnchor].active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_settingsTabButtons.leadingAnchor constraintEqualToAnchor:_settingsHeader.leadingAnchor constant:6.],
            [_settingsTabButtons.trailingAnchor constraintEqualToAnchor:_settingsHeader.trailingAnchor constant:-6.],
            [_settingsTabButtons.centerYAnchor constraintEqualToAnchor:_settingsHeader.centerYAnchor]
        ]];

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0., 48., 400., 322.)];
        _settingsScrollView = scroll;
        scroll.hasVerticalScroller = YES;
        scroll.autohidesScrollers = YES;
        // Keep the reference400px pane/360px cards when macOS is configured to
        // always show scrollbars; a legacy scroller reserves16px of this width.
        scroll.scrollerStyle = NSScrollerStyleOverlay;
        scroll.drawsBackground = NO;
        scroll.contentView = [[VLCSimplePrefsClipView alloc] init];
        scroll.contentView.drawsBackground = NO;
        [root addSubview:scroll];
        _settingsBody = [[NSStackView alloc] init];
        _settingsBody.translatesAutoresizingMaskIntoConstraints = NO;
        _settingsBody.orientation = NSUserInterfaceLayoutOrientationVertical;
        _settingsBody.alignment = NSLayoutAttributeCenterX;
        _settingsBody.spacing = VLCUIUnits.mediumSpacing;
        scroll.documentView = _settingsBody;
        [NSLayoutConstraint activateConstraints:@[
            [_settingsBody.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
            [_settingsBody.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
            [_settingsBody.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor]
        ]];

        NSButton *close = [[NSButton alloc] initWithFrame:NSMakeRect(308., 12., 80., 24.)];
        close.title = _NS("Close");
        close.bezelStyle = NSBezelStyleRounded;
        close.target = self;
        close.action = @selector(closePlaybackSettings:);
        [root addSubview:close];
        _settingsPopover = [[NSPopover alloc] init];
        _settingsPopover.contentViewController = controller;
        _settingsPopover.contentSize = root.frame.size;
        _settingsPopover.behavior = NSPopoverBehaviorSemitransient;
        _settingsPopover.delegate = self;
    }
    [_settingsTabs setSelectedSegment:tab];
    [self rebuildSettingsBody];
    if (!_settingsPopover.shown) {
        NSWindow *window = hostingWindow;
        _settingsVideoController = ((VLCVideoWindowCommon *)window).videoViewController;
        [self updateSettingsValues:nil];
        _settingsPreviousAutohide = _settingsVideoController.autohideControls;
        _settingsVideoController.autohideControls = NO;
        const BOOL wide = window.frame.size.width >= 768.;
        NSView *anchor = wide ? window.contentView : (self.bottomBarView != nil ? (NSView *)self.bottomBarView : sender);
        if(anchor.window!=window)return;
        // Align the existing400px pane below the actual media header. Anchoring
        // a tall popover to the footer's midpoint let it extend below the window.
        CGFloat headerHeight = _settingsVideoController.fakeTitleBarHeightConstraint.constant;
        CGFloat centerY = NSMaxY(anchor.bounds) - headerHeight - _settingsPopover.contentSize.height / 2.;
        if (anchor.isFlipped) centerY = NSMinY(anchor.bounds) + headerHeight + _settingsPopover.contentSize.height / 2.;
        NSRectEdge edge = wide ? NSRectEdgeMinX : NSRectEdgeMaxY;
        NSRect rect = wide ? NSMakeRect(NSMaxX(anchor.bounds) - 1., centerY, 1., 1.) : NSMakeRect(NSMidX(anchor.bounds), NSMaxY(anchor.bounds), 1., 1.);
        [_settingsPopover showRelativeToRect:rect ofView:anchor preferredEdge:edge];
        [self fitSettingsPopoverToWindow:window];
    }
}

- (void)fitSettingsPopoverToWindow:(NSWindow *)window
{
    if (!_settingsPopover.shown || !window) return;
    NSView *root = _settingsPopover.contentViewController.view;
    NSWindow *pane = root.window;
    // Use the actual AppKit panel border/arrow extent, measured after showing.
    CGFloat chromeHeight = MAX(0., NSHeight(pane.frame) - NSHeight(root.bounds));
    CGFloat headerHeight = _settingsVideoController.fakeTitleBarHeightConstraint.constant;
    CGFloat available = NSHeight(window.contentView.bounds) - headerHeight - NSHeight(((NSView *)self.bottomBarView).bounds) - chromeHeight;
    CGFloat height = MAX(180., available);
    _settingsPopover.contentSize = NSMakeSize(400., height);
    _settingsHeader.frame = NSMakeRect(0., height - 50., 400., 50.);
    _settingsScrollView.frame = NSMakeRect(0., 48., 400., MAX(1., height - 98.));
    if (window.frame.size.width >= 768.) {
        NSView *anchor = window.contentView;
        CGFloat centerY = NSMaxY(anchor.bounds) - headerHeight - (height + chromeHeight) / 2.;
        if (anchor.isFlipped) centerY = NSMinY(anchor.bounds) + headerHeight + (height + chromeHeight) / 2.;
        _settingsPopover.positioningRect = NSMakeRect(NSMaxX(anchor.bounds) - 1., centerY, 1., 1.);
    }
}

- (NSTextField *)settingsLabel:(NSString *)title
{
    NSTextField *label = [[NSTextField alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.stringValue = title;
    label.bordered = NO;
    label.editable = NO;
    label.drawsBackground = NO;
    label.font = [NSFont vlc_redesignFontOfSize:14. weight:NSFontWeightMedium];
    label.textColor = NSColor.VLCControlForegroundColor;
    return label;
}

- (void)rebuildSettingsBody
{
    for (NSView *view in [_settingsBody.arrangedSubviews copy]) {
        [_settingsBody removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    _settingsDelaySlider = nil;
    _settingsDelayValue = nil;
    _settingsRateSlider = nil;
    _settingsRateValue = nil;
    _settingsReverseButton = nil;
    _settingsStatisticsButton = nil;
    _settingsSleepTimerButton = nil;
    const NSInteger tab = _settingsTabs.selectedSegment;
    for (NSButton *button in _settingsTabButtons.arrangedSubviews) {
        button.state = button.tag == tab ? NSControlStateValueOn : NSControlStateValueOff;
        button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title attributes:@{
            NSFontAttributeName:button.font,
            NSForegroundColorAttributeName:button.tag == tab ? NSColor.VLCPrimaryForegroundColor : NSColor.VLCSecondaryForegroundColor
        }];
        [button vlc_applyRedesignStyle];
    }
    VLCMainMenu *mainMenu = VLCMain.sharedInstance.mainMenu;
    NSArray<NSMenu *> *menus = @[mainMenu.controlsMenu, mainMenu.videoMenu, mainMenu.audioMenu, mainMenu.subtitlesMenu];
    _settingsRootMenu = menus[tab];
    [_settingsRootMenu update];

    if(tab>0) {
        if(!_presetManager)_presetManager=[[VLCPlayerPresetManager alloc] initWithPlayer:_playerController];
        NSView *presets=[_presetManager viewForSection:tab==3 ? 0 : tab==2 ? 1 : 2];
        [_settingsBody addArrangedSubview:presets];[presets.widthAnchor constraintEqualToAnchor:_settingsBody.widthAnchor constant:-40.].active=YES;
    }

    if (tab == 3 || tab == 2) {
        // Synchronization copy, units and -60..60 second range are from SyncTracks.xib and its controller.
        NSTextField *label = [self settingsLabel:tab == 3 ? _NS("Subtitle track synchronization:") : _NS("Audio track synchronization:")];
        [_settingsBody addArrangedSubview:label];
        _settingsDelayValue = [self settingsLabel:@""];
        [_settingsBody addArrangedSubview:_settingsDelayValue];
        _settingsDelaySlider = [[NSSlider alloc] init];
        _settingsDelaySlider.translatesAutoresizingMaskIntoConstraints = NO;
        _settingsDelaySlider.minValue = -60.;
        _settingsDelaySlider.maxValue = 60.;
        _settingsDelaySlider.continuous = YES;
        _settingsDelaySlider.target = self;
        _settingsDelaySlider.action = @selector(settingsDelayChanged:);
        [_settingsBody addArrangedSubview:_settingsDelaySlider];
        [_settingsDelaySlider.widthAnchor constraintEqualToAnchor:_settingsBody.widthAnchor constant:-40.].active = YES;
    } else if (tab == 0) {
        _settingsStatisticsButton = [[VLCRedesignBooleanControl alloc] init];
        [_settingsStatisticsButton setButtonType:NSButtonTypeSwitch];
        _settingsStatisticsButton.title = _NS("Show Statistics");
        _settingsStatisticsButton.target = self;
        _settingsStatisticsButton.action = @selector(settingsStatisticsChanged:);
        [_settingsBody addArrangedSubview:_settingsStatisticsButton];
        [_settingsStatisticsButton.widthAnchor constraintEqualToAnchor:_settingsBody.widthAnchor constant:-40.].active = YES;
        [_settingsStatisticsButton.heightAnchor constraintEqualToConstant:32].active = YES;
        // Figma 2238:9432 exposes Reverse; the existing native model already reports its capability.
        _settingsReverseButton = [[VLCRedesignBooleanControl alloc] init];
        [_settingsReverseButton setButtonType:NSButtonTypeSwitch];
        _settingsReverseButton.title = _NS("Reverse");
        _settingsReverseButton.target = self;
        _settingsReverseButton.action = @selector(settingsReverseChanged:);
        [_settingsBody addArrangedSubview:_settingsReverseButton];
        [_settingsReverseButton.widthAnchor constraintEqualToAnchor:_settingsBody.widthAnchor constant:-40.].active = YES;
        [_settingsReverseButton.heightAnchor constraintEqualToConstant:32].active = YES;
        [_settingsBody addArrangedSubview:[self settingsLabel:_NS("Sleep Timer")]];
        _settingsSleepTimerButton = [NSButton buttonWithTitle:_NS("Off") target:self action:@selector(showSleepTimer:)];
        [_settingsBody addArrangedSubview:_settingsSleepTimerButton];
        [_settingsSleepTimerButton.widthAnchor constraintEqualToAnchor:_settingsBody.widthAnchor constant:-40.].active = YES;
        [_settingsSleepTimerButton.heightAnchor constraintEqualToConstant:36].active = YES;
        [_settingsBody addArrangedSubview:[self settingsLabel:_NS("Playback rate")]];
        _settingsRateValue = [self settingsLabel:@""];
        [_settingsBody addArrangedSubview:_settingsRateValue];
        // Preserve the native player's existing logarithmic playback-rate mapping.
        _settingsRateSlider = [[NSSlider alloc] init];
        _settingsRateSlider.translatesAutoresizingMaskIntoConstraints = NO;
        _settingsRateSlider.minValue = -34.;
        _settingsRateSlider.maxValue = 34.;
        _settingsRateSlider.numberOfTickMarks = 17;
        _settingsRateSlider.continuous = YES;
        _settingsRateSlider.target = self;
        _settingsRateSlider.action = @selector(rateSliderAction:);
        [_settingsBody addArrangedSubview:_settingsRateSlider];
        [_settingsRateSlider.widthAnchor constraintEqualToAnchor:_settingsBody.widthAnchor constant:-40.].active = YES;
    }

    if (tab == 1 || tab == 2) {
        NSWindowController *controller = tab == 2 ? VLCMain.sharedInstance.audioEffectsPanel : VLCMain.sharedInstance.videoEffectsPanel;
        VLCPlayerEffectsView *effects = [[VLCPlayerEffectsView alloc] initWithEffectsController:controller audio:tab == 2];
        [_settingsBody addArrangedSubview:effects]; [effects.widthAnchor constraintEqualToAnchor:_settingsBody.widthAnchor].active = YES;
    }
    NSMutableArray<NSMenuItem *> *items = [_settingsRootMenu.itemArray mutableCopy];
    if (tab == 2) [items addObject:mainMenu.audioeffects];
    if (tab == 1) [items addObject:mainMenu.videoeffects];
    if (tab == 0) [items addObjectsFromArray:@[mainMenu.info, mainMenu.bookmarks]];
    _settingsMenuItems = items;
    for (NSUInteger index = 0; index < items.count; ++index) {
        NSMenuItem *item = items[index];
        if (item.separatorItem || item.hidden || item.title.length == 0 || (tab == 0 && item == mainMenu.rate)) continue;
        NSButton *button = [[NSButton alloc] init];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.title = item.title;
        button.alignment = NSTextAlignmentLeft;
        button.bordered = NO;
        button.font = [NSFont vlc_redesignFontOfSize:14. weight:NSFontWeightRegular];
        button.enabled = item.enabled;
        button.state = item.state;
        button.target = self;
        button.action = @selector(settingsMenuItemSelected:);
        button.tag = index;
        [_settingsBody addArrangedSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToAnchor:_settingsBody.widthAnchor constant:-40.],
            [button.heightAnchor constraintEqualToConstant:28.]
        ]];
    }
    // Width relations require a common ancestor. Labels are constructed before
    // insertion, so activate their body-width constraint only after mounting.
    for (NSView *view in _settingsBody.arrangedSubviews) {
        if ([view isKindOfClass:NSTextField.class])
            [view.widthAnchor constraintEqualToAnchor:_settingsBody.widthAnchor constant:-40.].active = YES;
    }
    [_settingsBody vlc_applyRedesignStyle];
    [self updateSettingsValues:nil];
}

- (void)settingsTracksChanged:(NSNotification *)notification
{
    if (_settingsPopover.shown) {
        _settingsVideoController.autohideControls = NO;
        [self rebuildSettingsBody];
    }
}

- (void)settingsWindowResized:(NSNotification *)notification
{
    NSWindow *window=((NSView *)self.bottomBarView).window;
    if(notification.object==window && _settingsPopover.shown) [self fitSettingsPopoverToWindow:window];
}

- (void)settingsTabChanged:(id)sender
{
    [self rebuildSettingsBody];
}

- (void)settingsHeaderTabChanged:(NSButton *)sender
{
    if (sender.tag < 0 || sender.tag >= _settingsTabs.segmentCount) return;
    _settingsTabs.selectedSegment = sender.tag;
    [self settingsTabChanged:_settingsTabs];
}

- (void)settingsDelayChanged:(NSSlider *)sender
{
    const vlc_tick_t delay = vlc_tick_from_sec(sender.doubleValue);
    if (_settingsTabs.selectedSegment == 3) _playerController.subtitlesDelay = delay;
    else _playerController.audioDelay = delay;
    [self updateSettingsValues:nil];
}

- (void)updateSettingsValues:(NSNotification *)notification
{
    _settingsStatisticsButton.enabled = _playerController.statistics != nil;
    _settingsStatisticsButton.state = _settingsVideoController.statisticsVisible ? NSControlStateValueOn : NSControlStateValueOff;
    _settingsSleepTimerButton.title = VLCSleepTimer.sharedInstance.active ? [NSString stringWithTime:(int64_t)ceil(VLCSleepTimer.sharedInstance.remainingSeconds)] : _NS("Off");
    if (_settingsDelaySlider != nil) {
        const vlc_tick_t delay = _settingsTabs.selectedSegment == 3 ? _playerController.subtitlesDelay : _playerController.audioDelay;
        const double seconds = secf_from_vlc_tick(delay);
        _settingsDelaySlider.doubleValue = seconds;
        _settingsDelaySlider.enabled = _playerController.currentMedia != nil;
        _settingsDelayValue.stringValue = [NSString stringWithFormat:@"%.3f s", seconds];
    }
    if (_settingsRateSlider != nil) {
        const double rate = _playerController.playbackRate;
        _settingsReverseButton.enabled = _playerController.rateChangable && _playerController.rewindable;
        _settingsReverseButton.state = rate < 0 ? NSControlStateValueOn : NSControlStateValueOff;
        _settingsRateSlider.enabled = _playerController.rateChangable && rate != 0.;
        if (rate != 0.) _settingsRateSlider.doubleValue = 17. * log(fabs(rate)) / log(2.);
        _settingsRateValue.stringValue = [NSString stringWithFormat:@"%.2fx", fabs(rate)];
    }
}
- (void)settingsStatisticsChanged:(NSButton *)sender
{
    _settingsVideoController.statisticsVisible = sender.state == NSControlStateValueOn;
}

- (BOOL)sleepTimerDurationForString:(NSString *)string value:(NSTimeInterval *)seconds
{
    // Reuse the existing VLC hours:minutes:seconds parser, rejecting ambiguous
    // or overflowing input before its millisecond conversion.
    NSArray<NSString *> *parts = [string componentsSeparatedByString:@":"];
    if (parts.count == 0 || parts.count > 3) return NO;
    long double total = 0;
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    for (NSString *part in parts) {
        if (!part.length || [part rangeOfCharacterFromSet:digits.invertedSet].location != NSNotFound) return NO;
        total = total * 60 + part.doubleValue;
    }
    if (total <= 0 || total > INT64_MAX / 1000) return NO;
    VLCTimeFormatter *formatter = [[VLCTimeFormatter alloc] init];
    NSNumber *milliseconds = nil; NSString *error = nil;
    if (![formatter getObjectValue:&milliseconds forString:string errorDescription:&error]) return NO;
    *seconds = milliseconds.doubleValue / 1000;
    return *seconds > 0;
}

- (void)showSleepTimer:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Sleep Timer");
    alert.informativeText = _NS("Time");
    NSButton *apply = [alert addButtonWithTitle:_NS("Apply")];
    [alert addButtonWithTitle:_NS("Cancel")];
    [alert addButtonWithTitle:_NS("Off")];
    NSTextField *duration = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,320,36)];
    duration.stringValue = VLCSleepTimer.sharedInstance.active ? [NSString stringWithTime:(int64_t)ceil(VLCSleepTimer.sharedInstance.remainingSeconds)] : @"";
    alert.accessoryView = duration; alert.window.initialFirstResponder = duration;
    NSTimeInterval value = 0;
    apply.enabled = [self sleepTimerDurationForString:duration.stringValue value:&value];
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:NSControlTextDidChangeNotification object:duration queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NSTimeInterval seconds = 0;
        apply.enabled = [self sleepTimerDurationForString:duration.stringValue value:&seconds];
    }];
    NSModalResponse response = [alert runModal];
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    if (response == NSAlertThirdButtonReturn) [VLCSleepTimer.sharedInstance cancel];
    else if (response == NSAlertFirstButtonReturn && [self sleepTimerDurationForString:duration.stringValue value:&value])
        [VLCSleepTimer.sharedInstance setDuration:value playQueue:_playQueueController];
    [self updateSettingsValues:nil];
}
- (void)settingsReverseChanged:(NSButton *)sender
{
    if (!_playerController.rateChangable || !_playerController.rewindable) return;
    float magnitude = fabsf(_playerController.playbackRate);
    if (magnitude == 0) return;
    _playerController.playbackRate = sender.state == NSControlStateValueOn ? -magnitude : magnitude;
}

- (void)settingsMenuItemSelected:(NSButton *)sender
{
    NSMenuItem *item = _settingsMenuItems[sender.tag];
    if (item.submenu != nil) {
        [item.submenu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0., NSMaxY(sender.bounds)) inView:sender];
    } else if (item.view != nil) {
        // Native menu-hosted controls retain their original view and target instead of being duplicated.
        [_settingsRootMenu popUpMenuPositioningItem:item atLocation:NSMakePoint(0., NSMaxY(sender.bounds)) inView:sender];
    } else if (item.action != NULL) {
        [NSApp sendAction:item.action to:item.target from:item];
    }
    [self rebuildSettingsBody];
}

- (void)closePlaybackSettings:(id)sender
{
    BOOL animated = _settingsPopover.animates;
    _settingsPopover.animates = NO;
    [_settingsPopover close];
    _settingsPopover.animates = animated;
}

- (void)popoverDidClose:(NSNotification *)notification
{
    _settingsVideoController.autohideControls = _settingsPreviousAutohide;
    _settingsVideoController = nil;
}

- (IBAction)openPlaybackRate:(id)sender
{
    [self showSettingsTab:0 sender:sender];
}

- (IBAction)rateSliderAction:(id)sender
{
    NSSlider * const slider = (NSSlider *)sender;
    float rate = pow(2, (double)slider.intValue / 17);
    _playerController.playbackRate = _playerController.playbackRate < 0 ? -rate : rate;
}

- (IBAction)openBookmarks:(id)sender
{
    [VLCMain.sharedInstance.bookmarks toggleWindow:sender];
}

- (IBAction)openSubtitlesMenu:(id)sender
{
    [self showSettingsTab:3 sender:sender];
}

- (IBAction)openAudioMenu:(id)sender
{
    [self showSettingsTab:2 sender:sender];
}

- (IBAction)openVideoMenu:(id)sender
{
    [self showSettingsTab:1 sender:sender];
}

- (IBAction)toggleFloatOnTop:(id)sender
{
    vout_thread_t * const p_vout = [self windowVoutThread];
    if (!p_vout) {
        return;
    }
    var_ToggleBool(p_vout, "video-on-top");
    vout_Release(p_vout);
}

- (IBAction)toggleLyrics:(id)sender
{
    _playerController.showLyrics = !_playerController.showLyrics;
}

- (void)updateAvailableButtons:(id)sender
{
    // The video controller already applies the new item's own auto-hide policy.
    _settingsVideoController = nil;
    [_settingsPopover close];
    const BOOL currentItemIsAudio = _playerController.currentMediaIsAudioOnly;
    self.videoButton.hidden = YES;
    self.subtitlesButton.hidden = currentItemIsAudio;

    if (!VLCMain.sharedInstance.libraryController.shouldUseMediaLibrary) {
        self.bookmarksButton.hidden = YES;
    }

    [self updateLyricsButton:nil];
}

- (void)playerStateUpdated:(NSNotification *)notification
{
    [super playerStateUpdated:notification];
    if (@available(macOS 26.0, *)) {
        if (self.mainButtonsSymbolConfig == nil)
            return;
        self.playButton.image = [self.playButton.image imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
        self.playButton.alternateImage = [self.playButton.alternateImage imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
    }
}

- (void)updateCurrentItemDisplayControls:(NSNotification *)notification
{
    [super updateCurrentItemDisplayControls:notification];
    if (@available(macOS 26.0, *)) {
        if (self.mainButtonsSymbolConfig == nil)
            return;
        self.forwardButton.image = [self.forwardButton.image imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
        self.forwardButton.alternateImage = [self.forwardButton.alternateImage imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
        self.backwardButton.image = [self.backwardButton.image imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
        self.backwardButton.alternateImage = [self.backwardButton.alternateImage imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
        self.jumpForwardButton.image = [self.jumpForwardButton.image imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
        self.jumpForwardButton.alternateImage = [self.jumpForwardButton.alternateImage imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
        self.jumpBackwardButton.image = [self.jumpBackwardButton.image imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
        self.jumpBackwardButton.alternateImage = [self.jumpBackwardButton.alternateImage imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
    }
}

- (void)updateMuteVolumeButtonImage
{
    [super updateMuteVolumeButtonImage];
    if (@available(macOS 26.0, *)) {
        if (self.mainButtonsSymbolConfig == nil)
            return;
        self.muteVolumeButton.image = [self.muteVolumeButton.image imageWithSymbolConfiguration:self.mainButtonsSymbolConfig];
    }
}

@end
