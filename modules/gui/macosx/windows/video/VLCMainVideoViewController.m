/*****************************************************************************
 * VLCMainVideoViewController.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2024 VLC authors and VideoLAN
 *
 * Authors: Claudio Cambra <developer@claudiocambra.com>
 *          Maxime Chapelet <umxprime at videolabs dot io>
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

#import "VLCMainVideoViewController.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "views/VLCVolumeSlider.h"
#import "views/VLCTimeField.h"

#import <vlc_common.h>
#import <vlc_aout.h>
#include <math.h>

#import "extensions/NSAnimationContext+VLCAdditions.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSWindow+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"

#import "library/VLCInputItem.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibraryWindow.h"
#import "library/VLCCompactLibraryViewController.h"
#import "library/VLCLibraryWindowSidebarRootViewController.h"
#import "library/VLCLibraryWindowSplitViewController.h"

#import "main/VLCMain.h"

#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"

#import "private/PIPSPI.h"

#import "views/VLCBottomBarView.h"
#import "views/VLCPlaybackEndViewController.h"
#import "views/VLCPlayerStatisticsView.h"
#import "views/VLCUIUnits.h"

#import "windows/controlsbar/VLCMainVideoViewControlsBar.h"
#import "windows/controlsbar/VLCPlayerToolbarEditorController.h"

#import "windows/video/VLCMainVideoViewAudioMediaDecorativeView.h"
#import "windows/video/VLCMainVideoViewOverlayView.h"
#import "windows/video/VLCVideoOutputProvider.h"
#import "windows/video/VLCVideoWindowCommon.h"
#import "windows/video/VLCFullVideoViewWindow.h"

NSString * const VLCUseClassicVideoPlayerLayoutKey = @"VLCUseClassicVideoPlayerLayoutKey";

// A feedback plaque never intercepts clicks intended for the video.
@interface VLCPlaybackFeedbackView : NSView
@end

@implementation VLCPlaybackFeedbackView
- (NSView *)hitTest:(NSPoint)point { return nil; }
@end

@interface PIPVoutViewController : NSViewController
@property (nonatomic) NSRect previousBounds;
@property (nonatomic, copy) void (^boundsChangeHandler)(void);
@end

@implementation PIPVoutViewController

- (void)setView:(NSView *)view {
    [super setView:view];
    self.previousBounds = NSZeroRect;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)viewWillAppear {
    [super viewWillAppear];

    if (self.view.superview) {
        [self.view applyConstraintsToFillSuperview];
    }
}

- (void)viewDidAppear {
    [super viewDidAppear];
}

- (void)viewDidLayout 
{
    [super viewDidLayout];

    NSRect currentBounds = self.view.bounds;
    if (!NSIsEmptyRect(currentBounds) && !NSEqualRects(currentBounds, _previousBounds)) {
            _previousBounds = currentBounds;

            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.boundsChangeHandler) {
                    self.boundsChangeHandler();
                    self.boundsChangeHandler = nil;
                }
            });
    }
}
@end

@interface VLCMainVideoViewController() <PIPViewControllerDelegate, NSPopoverDelegate>
{
    NSTimer *_hideControlsTimer;
    NSLayoutConstraint *_returnButtonBottomConstraint;
    NSLayoutConstraint *_playQueueButtonBottomConstraint;
    NSLayoutConstraint *_videoViewTopToHeaderConstraint;
    PIPViewController *_pipViewController;
    PIPVoutViewController *_voutViewController;

    BOOL _isFadingIn;
    NSLayoutConstraint *_videoViewLeadingToViewConstraint;
    NSLayoutConstraint *_videoViewLeadingToLibraryConstraint;
}

@property NSWindow *retainedWindow;
@property (readonly) BOOL classic;
@property (readwrite) BOOL voutTaken;
@property NSButton *compactLibraryButton;
@property VLCCompactLibraryViewController *compactLibraryController;
@property VLCPlayerToolbarEditorController *toolbarEditor;
@property NSDictionary<NSString *, NSButton *> *customizableButtons;
@property VLCPlayerStatisticsView *statisticsOverlay;
@property NSPopover *queuePopover;
@property BOOL queuePreviousAutohide;
@property VLCPlaybackFeedbackView *playbackFeedbackView;
@property NSTextField *playbackFeedbackMessage;
@property NSTextField *playbackFeedbackDetail;
@property NSTimer *playbackFeedbackTimer;
@property BOOL playbackFeedbackShowsTime;
@property float feedbackAudioVolume;
@property int feedbackAudioMute;
@property BOOL feedbackHasAudioState;

@end

@implementation VLCMainVideoViewController

- (instancetype)init
{
    const BOOL classic = [NSUserDefaults.standardUserDefaults boolForKey:VLCUseClassicVideoPlayerLayoutKey];
    NSString * const nibName = classic ? @"VLCClassicMainVideoView" : @"VLCMainVideoView";
    self = [super initWithNibName:nibName bundle:nil];
    if (self) {
        _classic = classic;
        _isFadingIn = NO;
        _voutTaken = NO;

        NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
        [notificationCenter addObserver:self
                               selector:@selector(playerCurrentMediaItemChanged:)
                                   name:VLCPlayerCurrentMediaItemChanged
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(playerCurrentItemTrackListChanged:)
                                   name:VLCPlayerTrackListChanged
                                 object:nil];
        [notificationCenter addObserver:self
                                   selector:@selector(playerBufferChanged:)
                                   name:VLCPlayerBufferChanged
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(floatOnTopChanged:)
                                   name:VLCWindowFloatOnTopChangedNotificationName
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(shouldShowControls:)
                                   name:VLCVideoWindowShouldShowFullscreenController
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(pictureInPictureChanged:)
                                   name:VLCPlayerPictureInPictureChanged
                                 object:nil];
        [notificationCenter addObserver:self selector:@selector(playbackFeedbackTimeChanged:)
                                   name:VLCPlayerTimeAndPositionChanged object:nil];
        [notificationCenter addObserver:self selector:@selector(playbackFeedbackAudioChanged:)
                                   name:VLCPlayerVolumeChanged object:nil];
        [notificationCenter addObserver:self selector:@selector(playbackFeedbackAudioChanged:)
                                   name:VLCPlayerMuteChanged object:nil];
        [notificationCenter addObserver:self selector:@selector(playbackFeedbackStateChanged:)
                                   name:VLCPlayerStateChanged object:nil];

        Class PIPViewControllerClass = NSClassFromString(@"PIPViewController");
        _pipViewController = [[PIPViewControllerClass alloc] init];
        _pipViewController.delegate = self;
        _pipViewController.userCanResize = true;
    }
    return self;
}

- (void)setupAudioDecorativeView
{
    _audioDecorativeView = [VLCMainVideoViewAudioMediaDecorativeView fromNibWithOwner:self];
    _audioDecorativeView.translatesAutoresizingMaskIntoConstraints = NO;

    if (!self.classic) {
        // The redesigned playback buttons stay inside the bottom bar for audio and video.
        [self updateLyricsInsets];
    }

    VLCPlayerController * const controller =
        VLCMain.sharedInstance.playQueueController.playerController;
    [self updateDecorativeViewVisibilityOnControllerChange:controller];
}

- (void)viewDidLoad
{
    self.loadingIndicator.hidden = YES;

    BOOL floatOnTopActive = NO;
    VLCVideoWindowCommon * const window = (VLCVideoWindowCommon *)self.view.window;
    vout_thread_t * const p_vout = window.videoViewController.voutView.voutThread;
    if (p_vout) {
        floatOnTopActive = var_GetBool(p_vout, "video-on-top");
        vout_Release(p_vout);
    }
    self.floatOnTopIndicatorImageView.hidden = !floatOnTopActive;

    _autohideControls = YES;

    [self setDisplayLibraryControls:NO];
    [self updatePlayQueueToggleState];
    [self updateLibraryControls];

    _returnButtonBottomConstraint = [NSLayoutConstraint constraintWithItem:_returnButton
                                                                 attribute:NSLayoutAttributeBottom
                                                                 relatedBy:NSLayoutRelationEqual
                                                                    toItem:_fakeTitleBar
                                                                 attribute:NSLayoutAttributeBottom
                                                                multiplier:1.
                                                                  constant:0];
    _playQueueButtonBottomConstraint = [NSLayoutConstraint constraintWithItem:_playQueueButton
                                                                    attribute:NSLayoutAttributeBottom
                                                                    relatedBy:NSLayoutRelationEqual
                                                                       toItem:_fakeTitleBar
                                                                    attribute:NSLayoutAttributeBottom
                                                                   multiplier:1.
                                                                     constant:0];

    _returnButtonBottomConstraint.active = NO;
    _playQueueButtonBottomConstraint = nil; // Queue is part of the Figma control row.
    _playQueueButtonBottomConstraint.active = NO;

    self.bottomBarView.wantsLayer = YES;
    // Figma Controls 491:1779 uses Dark/BG/A4 (#191919) at 95% opacity.
    self.bottomBarView.layer.backgroundColor = [NSColor.VLCSurfaceBackgroundColor colorWithAlphaComponent:.95].CGColor;
    self.playQueueButton.image = [NSImage vlc_redesignImageNamed:@"queue"] ?: self.playQueueButton.image;
    self.bottomBarView.layer.cornerRadius = 0.;
    [self setupAudioDecorativeView];
    [self.controlsBar update];
    [self updateFloatOnTopIndicator];
    [self updateLyricsInsets];
    
    [self configureVideoContentConstraints];
    [self setupPlaybackFeedback];
    [self updatePlaybackFeedbackAudioStateDisplayingChanges:NO];
    [self setupCompactLibrary];
    [self setupPlayerCustomization];
    if (self.classic) {
        if (@available(macOS 26.0, *)) {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
            NSGlassEffectContainerView * const glassEffectView = [[NSGlassEffectContainerView alloc] initWithFrame:self.bottomBarView.frame];
            glassEffectView.translatesAutoresizingMaskIntoConstraints = NO;
            [self.classicViewBottomBarContainerView addSubview:glassEffectView];
            [glassEffectView applyConstraintsToFillSuperview];
            [self.bottomBarView removeFromSuperview];
            glassEffectView.contentView = self.bottomBarView;
#endif
        } else {
            NSVisualEffectView * const controlsBackgroundView = [[NSVisualEffectView alloc] initWithFrame:self.bottomBarView.frame];
            controlsBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
            controlsBackgroundView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
            controlsBackgroundView.material = NSVisualEffectMaterialTitlebar;
            [self.bottomBarView addSubview:controlsBackgroundView positioned:NSWindowBelow relativeTo:self.bottomBarView.subviews.firstObject];
            [controlsBackgroundView applyConstraintsToFillSuperview];
        }
    }
}

- (void)configureVideoContentConstraints
{
    NSView *video = self.voutContainingView;
    NSMutableArray<NSLayoutConstraint *> *oldVerticalConstraints = [[NSMutableArray alloc] init];
    for (NSLayoutConstraint *constraint in self.view.constraints) {
        BOOL firstVideo = constraint.firstItem == video &&
            (constraint.firstAttribute == NSLayoutAttributeTop || constraint.firstAttribute == NSLayoutAttributeBottom);
        BOOL secondVideo = constraint.secondItem == video &&
            (constraint.secondAttribute == NSLayoutAttributeTop || constraint.secondAttribute == NSLayoutAttributeBottom);
        if (firstVideo || secondVideo) [oldVerticalConstraints addObject:constraint];
    }
    [NSLayoutConstraint deactivateConstraints:oldVerticalConstraints];
    _videoViewTopToHeaderConstraint = [video.topAnchor constraintEqualToAnchor:self.fakeTitleBar.bottomAnchor];
    // Classic macOS 26 reparents the bar into glass after this setup; its
    // persistent container remains in the original view hierarchy.
    NSView *bottomSafeArea = self.classic ? self.classicViewBottomBarContainerView : self.bottomBarView;
    self.videoViewBottomConstraint = [video.bottomAnchor constraintEqualToAnchor:bottomSafeArea.topAnchor];
    _videoViewBottomToViewConstraint = [video.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    // Keep one video rectangle while the controls fade. The persistent safe
    // area leaves the original OSD below the header and subtitles above the bar.
    [NSLayoutConstraint activateConstraints:@[
        _videoViewTopToHeaderConstraint, self.videoViewBottomConstraint
    ]];
    self.view.wantsLayer = YES;
    self.view.layer.backgroundColor = NSColor.blackColor.CGColor;
}

- (void)setupPlaybackFeedback
{
    self.playbackFeedbackView = [[VLCPlaybackFeedbackView alloc] init];
    self.playbackFeedbackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.playbackFeedbackView.wantsLayer = YES;
    self.playbackFeedbackView.layer.backgroundColor = [NSColor.blackColor colorWithAlphaComponent:.95].CGColor;
    self.playbackFeedbackView.layer.cornerRadius = VLCUIUnits.cornerRadius;
    self.playbackFeedbackView.hidden = YES;

    self.playbackFeedbackMessage = [NSTextField labelWithString:@""];
    self.playbackFeedbackMessage.identifier = @"VLCPlaybackFeedbackMessage";
    self.playbackFeedbackMessage.font = [NSFont vlc_redesignFontOfSize:15 weight:NSFontWeightRegular];
    self.playbackFeedbackDetail = [NSTextField labelWithString:@""];
    self.playbackFeedbackDetail.identifier = @"VLCPlaybackFeedbackDetail";
    self.playbackFeedbackDetail.font = [NSFont vlc_redesignFontOfSize:15 weight:NSFontWeightRegular];
    for (NSTextField *field in @[self.playbackFeedbackMessage, self.playbackFeedbackDetail]) {
        field.textColor = NSColor.whiteColor;
        field.alignment = NSTextAlignmentRight;
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        [field setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    NSStackView *stack = [NSStackView stackViewWithViews:@[self.playbackFeedbackMessage, self.playbackFeedbackDetail]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeTrailing;
    stack.spacing = VLCUIUnits.smallSpacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.playbackFeedbackView addSubview:stack];
    [self.voutContainingView addSubview:self.playbackFeedbackView positioned:NSWindowAbove relativeTo:nil];
    const CGFloat margin = VLCUIUnits.largeSpacing;
    const CGFloat padding = VLCUIUnits.mediumSpacing;
    // All constraints affect only the plaque, leaving the video rectangle fixed.
    [NSLayoutConstraint activateConstraints:@[
        [self.playbackFeedbackView.topAnchor constraintEqualToAnchor:self.voutContainingView.topAnchor constant:margin],
        [self.playbackFeedbackView.trailingAnchor constraintEqualToAnchor:self.voutContainingView.trailingAnchor constant:-margin],
        [self.playbackFeedbackView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.voutContainingView.leadingAnchor constant:margin],
        [stack.topAnchor constraintEqualToAnchor:self.playbackFeedbackView.topAnchor constant:padding],
        [stack.bottomAnchor constraintEqualToAnchor:self.playbackFeedbackView.bottomAnchor constant:-padding],
        [stack.leadingAnchor constraintEqualToAnchor:self.playbackFeedbackView.leadingAnchor constant:padding],
        [stack.trailingAnchor constraintEqualToAnchor:self.playbackFeedbackView.trailingAnchor constant:-padding]
    ]];
}

- (BOOL)playbackFeedbackIsEnabled
{
    if (!self.isViewLoaded)
        return NO;
    vout_thread_t * const vout = self.voutView.voutThread;
    if (!vout)
        return NO;
    const BOOL enabled = var_InheritBool(vout, "osd");
    vout_Release(vout);
    return enabled;
}

- (void)clearCorePlaybackMessage
{
    vout_thread_t * const vout = self.voutView.voutThread;
    if (vout) {
        // Preserve subtitle channels and both fullscreen OSD slider channels.
        vout_FlushSubpictureChannel(vout, VOUT_SPU_CHANNEL_OSD);
        vout_Release(vout);
    }
}

- (void)showPlaybackFeedback
{
    if (![self playbackFeedbackIsEnabled]) {
        [self hidePlaybackFeedback];
        return;
    }
    [self clearCorePlaybackMessage];
    self.playbackFeedbackView.hidden = NO;
    [self.voutContainingView layoutSubtreeIfNeeded];
    [self.playbackFeedbackTimer invalidate];
    // vout_OSDMessageVa uses exactly VLC_TICK_FROM_SEC(1) in video_text.c.
    __weak typeof(self) weakSelf = self;
    self.playbackFeedbackTimer = [NSTimer timerWithTimeInterval:SEC_FROM_VLC_TICK(VLC_TICK_FROM_SEC(1))
                                                       repeats:NO block:^(NSTimer *timer) {
        VLCMainVideoViewController * const controller = weakSelf;
        if (timer == controller.playbackFeedbackTimer)
            [controller hidePlaybackFeedback];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.playbackFeedbackTimer forMode:NSRunLoopCommonModes];
}

- (void)hidePlaybackFeedback
{
    [self.playbackFeedbackTimer invalidate];
    self.playbackFeedbackTimer = nil;
    self.playbackFeedbackView.hidden = YES;
    self.playbackFeedbackShowsTime = NO;
}

- (void)clearPlaybackFeedback
{
    [self hidePlaybackFeedback];
}

- (void)displaySeekFeedback
{
    if (![self playbackFeedbackIsEnabled])
        return;
    self.playbackFeedbackShowsTime = YES;
    self.playbackFeedbackMessage.stringValue = @"";
    self.playbackFeedbackMessage.hidden = YES;
    [self updatePlaybackFeedbackTime];
    [self showPlaybackFeedback];
}

- (void)displayPlaybackFeedback:(NSString *)message
{
    if (![self playbackFeedbackIsEnabled])
        return;
    self.playbackFeedbackShowsTime = NO;
    self.playbackFeedbackMessage.stringValue = message;
    self.playbackFeedbackMessage.hidden = NO;
    self.playbackFeedbackDetail.stringValue = @"";
    self.playbackFeedbackDetail.hidden = YES;
    [self showPlaybackFeedback];
}

- (void)updatePlaybackFeedbackTime
{
    VLCPlayerController * const player = VLCMain.sharedInstance.playQueueController.playerController;
    const vlc_tick_t time = player.time;
    if (time == VLC_TICK_INVALID) {
        self.playbackFeedbackDetail.stringValue = @"";
        self.playbackFeedbackDetail.hidden = YES;
        return;
    }
    self.playbackFeedbackDetail.stringValue = [NSString stringWithTimeFromTicks:time];
    self.playbackFeedbackDetail.hidden = NO;
    [self.voutContainingView layoutSubtreeIfNeeded];
}

- (void)playbackFeedbackTimeChanged:(NSNotification *)notification
{
    if (notification.object != VLCMain.sharedInstance.playQueueController.playerController ||
        self.playbackFeedbackView.hidden || !self.playbackFeedbackShowsTime)
        return;
    if (![self playbackFeedbackIsEnabled]) {
        [self hidePlaybackFeedback];
        return;
    }
    [self updatePlaybackFeedbackTime];
    [self clearCorePlaybackMessage];
}

- (void)updatePlaybackFeedbackAudioStateDisplayingChanges:(BOOL)displayChanges
{
    VLCPlayerController * const player = VLCMain.sharedInstance.playQueueController.playerController;
    audio_output_t * const aout = player.mainAudioOutput;
    if (!aout) {
        if (!self.feedbackHasAudioState) {
            self.feedbackAudioVolume = player.volume;
            self.feedbackAudioMute = player.mute;
            self.feedbackHasAudioState = YES;
        }
        return;
    }
    const float volume = aout_VolumeGet(aout);
    const int muted = aout_MuteGet(aout);
    aout_Release(aout);
    if (!isfinite(volume) || volume < 0.f || muted < 0)
        return;

    const BOOL changed = self.feedbackHasAudioState &&
        (volume != self.feedbackAudioVolume || muted != self.feedbackAudioMute);
    self.feedbackAudioVolume = volume;
    self.feedbackAudioMute = muted;
    self.feedbackHasAudioState = YES;
    if (!displayChanges || !changed || ![self playbackFeedbackIsEnabled])
        return;

    // Match core rounding and copy, using the actual audio output, not slider requests.
    NSString * const percentage = [NSString stringWithFormat:_NS("Volume: %ld%%"), lroundf(volume * 100.f)];
    self.playbackFeedbackShowsTime = NO;
    self.playbackFeedbackMessage.stringValue = muted ? _NS("Muted") : percentage;
    self.playbackFeedbackMessage.hidden = NO;
    self.playbackFeedbackDetail.stringValue = muted ? percentage : @"";
    self.playbackFeedbackDetail.hidden = !muted;
    [self showPlaybackFeedback];
}

- (void)playbackFeedbackAudioChanged:(NSNotification *)notification
{
    if (notification.object == VLCMain.sharedInstance.playQueueController.playerController)
        [self updatePlaybackFeedbackAudioStateDisplayingChanges:YES];
}

- (void)playbackFeedbackStateChanged:(NSNotification *)notification
{
    VLCPlayerController * const player = notification.object;
    if (player == VLCMain.sharedInstance.playQueueController.playerController &&
        player.playerState != VLC_PLAYER_STATE_PLAYING && player.playerState != VLC_PLAYER_STATE_PAUSED)
        [self hidePlaybackFeedback];
}

- (void)dealloc
{
    [self.playbackFeedbackTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setupCompactLibrary
{
    _compactLibraryButton = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleCompactLibrary:)];
    _compactLibraryButton.bordered = NO;
    _compactLibraryButton.image = [NSImage vlc_redesignImageNamed:@"folder"];
    _compactLibraryButton.image.size = NSMakeSize(24, 24);
    _compactLibraryButton.toolTip = _NS("Library");
    _compactLibraryButton.accessibilityLabel = _NS("Library");
    _compactLibraryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.fakeTitleBar addSubview:_compactLibraryButton];
    [NSLayoutConstraint activateConstraints:@[
        [_compactLibraryButton.leadingAnchor constraintEqualToAnchor:self.fakeTitleBar.leadingAnchor constant:50],
        [_compactLibraryButton.centerYAnchor constraintEqualToAnchor:self.fakeTitleBar.bottomAnchor constant:-20],
        [_compactLibraryButton.widthAnchor constraintEqualToConstant:28],
        [_compactLibraryButton.heightAnchor constraintEqualToConstant:28]
    ]];
}

- (void)setupPlayerCustomization
{
    self.customizableButtons = @{@"previous":self.controlsBar.backwardButton, @"play":self.controlsBar.playButton, @"next":self.controlsBar.forwardButton,
        @"audio":self.controlsBar.audioButton, @"subtitles":self.controlsBar.subtitlesButton,
        @"video":self.controlsBar.videoButton, @"bookmarks":self.controlsBar.bookmarksButton,
        @"lyrics":self.controlsBar.lyricsButton, @"float":self.controlsBar.floatOnTopButton,
        @"settings":self.controlsBar.playbackRateButton, @"fullscreen":self.controlsBar.fullscreenButton,
        @"pip":self.controlsBar.pipButton, @"queue":self.playQueueButton};
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerToolbarChanged:) name:VLCPlayerToolbarLayoutChanged object:nil];
    NSDictionary *labels = @{@"previous":_NS("Previous"), @"play":_NS("Play"), @"next":_NS("Next"), @"audio":_NS("Audio"), @"subtitles":_NS("Subtitles"), @"video":_NS("Video"), @"bookmarks":_NS("Bookmarks"), @"lyrics":_NS("Lyrics"), @"float":_NS("Float on Top"), @"settings":_NS("Playback"), @"fullscreen":_NS("Fullscreen"), @"pip":_NS("Picture in Picture"), @"queue":_NS("Queue")};
    for (NSString *key in self.customizableButtons) {
        NSButton *button = self.customizableButtons[key];
        if (button.accessibilityLabel.length == 0) button.accessibilityLabel = labels[key];
    }
    [self playerToolbarChanged:nil];
}
- (void)playerToolbarChanged:(NSNotification *)notification
{
    NSArray *layout = [NSUserDefaults.standardUserDefaults arrayForKey:VLCPlayerToolbarLayoutKey];
    if (layout) {
        NSMutableDictionary<NSValue *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
        for (NSString *key in layout) {
            NSButton *button = self.customizableButtons[key];
            if (![button.superview isKindOfClass:NSStackView.class]) continue;
            NSValue *group = [NSValue valueWithNonretainedObject:button.superview];
            if (!groups[group]) groups[group] = [NSMutableArray array];
            [groups[group] addObject:button];
        }
        for (NSValue *group in groups) {
            NSStackView *stack = group.nonretainedObjectValue;
            for (NSButton *button in groups[group]) {
                [stack removeArrangedSubview:button];
                [stack addArrangedSubview:button];
            }
        }
    }
    [self prepareControlsForWidth:self.controlsBar.bottomBarView.bounds.size.width];
}
- (IBAction)customizePlayer:(id)sender
{
    self.toolbarEditor = [[VLCPlayerToolbarEditorController alloc] initWithButtons:self.customizableButtons];
    [self.toolbarEditor showWindow:sender];
}

- (void)setStatisticsVisible:(BOOL)visible
{
    _statisticsVisible = visible;
    if (!visible) { [self.statisticsOverlay removeFromSuperview]; self.statisticsOverlay = nil; return; }
    if (self.statisticsOverlay) return;
    self.statisticsOverlay = [[VLCPlayerStatisticsView alloc] initWithPlayerController:VLCMain.sharedInstance.playQueueController.playerController];
    self.statisticsOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statisticsOverlay];
    NSLayoutConstraint *width = [self.statisticsOverlay.widthAnchor constraintEqualToConstant:320];
    width.priority = NSLayoutPriorityDefaultHigh;
    NSLayoutConstraint *height = [self.statisticsOverlay.heightAnchor constraintEqualToConstant:400];
    height.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        width, height,
        [self.statisticsOverlay.widthAnchor constraintLessThanOrEqualToAnchor:self.voutContainingView.widthAnchor constant:-32],
        [self.statisticsOverlay.topAnchor constraintEqualToAnchor:self.voutContainingView.topAnchor constant:16],
        [self.statisticsOverlay.trailingAnchor constraintEqualToAnchor:self.voutContainingView.trailingAnchor constant:-16],
        [self.statisticsOverlay.bottomAnchor constraintLessThanOrEqualToAnchor:self.voutContainingView.bottomAnchor constant:-16]
    ]];
}

- (void)toggleCompactLibrary:(id)sender
{
    if (self.compactLibraryController.view.superview) {
        [self closeCompactLibrary];
        return;
    }
    if (!self.compactLibraryController) {
        self.compactLibraryController = [[VLCCompactLibraryViewController alloc] init];
        __weak typeof(self) weakSelf = self;
        self.compactLibraryController.expandLibrary = ^(VLCLibrarySegmentType segment) {
            typeof(self) strongSelf = weakSelf;
            [strongSelf closeCompactLibrary];
            [strongSelf returnToLibrary:strongSelf];
            VLCMain.sharedInstance.libraryWindow.librarySegmentType = segment;
        };
        self.compactLibraryController.expandSelection = ^(VLCLibrarySegmentType segment, NSURL *folder, id parentItem) {
            typeof(self) strongSelf = weakSelf;
            [strongSelf closeCompactLibrary];
            [strongSelf returnToLibrary:strongSelf];
            VLCLibraryWindow *window = VLCMain.sharedInstance.libraryWindow;
            window.librarySegmentType = segment;
            if (folder) [window browseFolderByMrl:folder.absoluteString];
            else if (parentItem) [window presentLibraryItem:parentItem];
        };
    }
    [self showControls];
    [self stopAutohideTimer];
    NSView *library = self.compactLibraryController.view;
    library.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:library];
    NSLayoutConstraint *width = [library.widthAnchor constraintEqualToConstant:427];
    width.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [library.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [library.topAnchor constraintEqualToAnchor:self.fakeTitleBar.bottomAnchor],
        [library.bottomAnchor constraintEqualToAnchor:self.bottomBarView.topAnchor],
        [library.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor multiplier:.7],
        width
    ]];
    NSMutableArray *leading = [NSMutableArray array];
    for (NSLayoutConstraint *constraint in self.view.constraints) {
        if ((constraint.firstItem == self.voutContainingView && constraint.firstAttribute == NSLayoutAttributeLeading) ||
            (constraint.secondItem == self.voutContainingView && constraint.secondAttribute == NSLayoutAttributeLeading)) [leading addObject:constraint];
    }
    [NSLayoutConstraint deactivateConstraints:leading];
    _videoViewLeadingToViewConstraint = [self.voutContainingView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor];
    _videoViewLeadingToLibraryConstraint = [self.voutContainingView.leadingAnchor constraintEqualToAnchor:library.trailingAnchor];
    _videoViewLeadingToLibraryConstraint.active = YES;
    self.compactLibraryButton.state = NSControlStateValueOn;
}

- (void)closeCompactLibrary
{
    _videoViewLeadingToLibraryConstraint.active = NO;
    _videoViewLeadingToViewConstraint.active = YES;
    [self.compactLibraryController.view removeFromSuperview];
    self.compactLibraryButton.state = NSControlStateValueOff;
    [self showControls];
}

- (void)viewDidAppear
{
    [super viewDidAppear];
    NSWindow *window = self.view.window;
    NSSize minimumSize = window.contentMinSize;
    minimumSize.width = MAX(minimumSize.width, 640.);
    minimumSize.height = MAX(minimumSize.height, 120.);
    window.contentMinSize = minimumSize;
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    [self prepareControlsForWidth:self.controlsBar.bottomBarView.bounds.size.width];
}

- (void)prepareControlsForWidth:(CGFloat)width
{
    // Figma's single row retains a useful seek target in narrow windows.
    // Compact controls remain available through the real Playback/Audio/Subtitles menus.
    BOOL compact = width > 0. && width < 780.;
    NSArray<NSView *> *clocks = @[self.controlsBar.timeField, self.controlsBar.trailingTimeField];
    for (NSView *clock in clocks) {
        for (NSView *owner in @[clock, clock.superview]) {
            for (NSLayoutConstraint *constraint in owner.constraints) {
                if (constraint.firstItem == clock && constraint.firstAttribute == NSLayoutAttributeWidth && constraint.secondItem == nil) {
                    CGFloat value = compact ? 0. : 76.;
                    if (constraint.constant != value) constraint.constant = value;
                }
            }
        }
        clock.hidden = compact;
    }
    BOOL narrow = width > 0. && width < 660.;
    self.controlsBar.audioButton.hidden = narrow;
    self.controlsBar.subtitlesButton.hidden = narrow;
    NSView *volumeGroup = self.controlsBar.volumeSlider.superview;
    self.controlsBar.volumeSlider.hidden = narrow;
    for (NSLayoutConstraint *constraint in volumeGroup.constraints) {
        if (constraint.firstItem == volumeGroup && constraint.firstAttribute == NSLayoutAttributeWidth && constraint.secondItem == nil) {
            // NSStackView updates hidden-child edges on the next constraints pass.
            // Permit that transient layout while retaining the exact settled control width.
            constraint.priority = 999.;
            CGFloat value = narrow ? 28. : 120.;
            if (constraint.constant != value) constraint.constant = value;
        }
    }
    NSArray *customLayout = [NSUserDefaults.standardUserDefaults arrayForKey:VLCPlayerToolbarLayoutKey];
    if (customLayout) {
        // Preserve a useful seek area when custom optional buttons exceed the available width.
        NSUInteger visibleBudget = MAX(0, (NSInteger)((width - (compact ? 270 : 470)) / 32));
        NSUInteger visible = 0;
        for (NSString *key in self.customizableButtons) self.customizableButtons[key].hidden = YES;
        for (NSString *key in customLayout) {
            NSButton *button = self.customizableButtons[key];
            if (!button) continue;
            if ([@[@"previous", @"play", @"next"] containsObject:key]) { button.hidden = NO; continue; }
            button.hidden = visible++ >= visibleBudget;
        }
    }
}

- (void)updateLyricsInsets
{
    const CGFloat topInset = self.fakeTitleBar.frame.size.height + VLCUIUnits.largeSpacing;
    const CGFloat bottomInset = self.bottomBarView.frame.size.height + VLCUIUnits.largeSpacing;

    NSScrollView * const scrollView = self.audioDecorativeView.lyricsScrollView;
    scrollView.automaticallyAdjustsContentInsets = NO;
    scrollView.contentInsets = NSEdgeInsetsMake(topInset, 0, bottomInset, 0);
    scrollView.scrollerInsets = NSEdgeInsetsMake(topInset, 0, 0, 0);
}

- (BOOL)isVisualizationActive
{
    BOOL isVisualActive;
    VLCPlayerController * const controller = VLCMain.sharedInstance.playQueueController.playerController;
    audio_output_t * const p_aout = controller.mainAudioOutput;
    if (!p_aout) {
        return NO;
    }
    
    char *psz_visual = var_GetString(p_aout, "visual");
    isVisualActive = psz_visual && psz_visual[0] != '\0';
    
    free(psz_visual);
    aout_Release(p_aout);
    
    return isVisualActive;
}

- (void)updateDecorativeViewVisibilityOnControllerChange:(VLCPlayerController *)controller
{
    const BOOL isAudioOnly = controller.currentMediaIsAudioOnly;
    const BOOL isVisualActive = [self isVisualizationActive];
    const BOOL decorativeViewVisible = isAudioOnly && !isVisualActive;

    // Keep voutView mounted so the macOS vout module always finds an in-window
    // NSView when WindowEnable runs. Otherwise an audio item that later exposes
    // a video track (e.g. m4b chapter slides) races: WindowEnable can land
    // before VLCPlayerTrackListChanged re-attaches voutView, and the vout
    // module then binds its layer to a detached view.
    if (self.voutView.superview != self.voutContainingView) {
        [self.voutContainingView addSubview:self.voutView
                                 positioned:NSWindowBelow
                                 relativeTo:nil];
        [self.voutView applyConstraintsToFillSuperview];
    }

    if (decorativeViewVisible) {
        if (self.audioDecorativeView.superview != self.voutContainingView) {
            [self.voutContainingView addSubview:self.audioDecorativeView];
            [self.audioDecorativeView applyConstraintsToFillSuperview];
        }
    } else {
        [self.audioDecorativeView removeFromSuperview];
    }

    [self setAutohideControls:!decorativeViewVisible && !self.classic];
    self.bottomButtonStackViewConstraint.active = NO;
    if (!self.classic) {
        self.centerButtonStackInViewConstraint.active = YES;
        self.prevButtonSizeConstraint.constant = 30.;
        self.playButtonSizeConstraint.constant = 54.;
        self.nextButtonSizeConstraint.constant = 30.;
        self.jumpBackwardButtonSizeConstraint.constant = 0.;
        self.jumpForwardButtonSizeConstraint.constant = 0.;
    }
    if (decorativeViewVisible) {
        [self applyAudioDecorativeViewForegroundCoverArtViewConstraints];
    }
}

- (void)applyAudioDecorativeViewForegroundCoverArtViewConstraints
{
    if (self.classic) {
        return;
    }
    if (![self.view.subviews containsObject:self.voutContainingView] ||
        ![self.voutContainingView.subviews containsObject:self.audioDecorativeView]) {
        return;
    }

    NSView * const foregroundCoverArtView = self.audioDecorativeView.foregroundCoverArtView;
    [NSLayoutConstraint activateConstraints:@[
        [self.bottomBarView.topAnchor constraintGreaterThanOrEqualToAnchor:foregroundCoverArtView.bottomAnchor constant:VLCUIUnits.largeSpacing],
        [self.fakeTitleBar.bottomAnchor constraintLessThanOrEqualToAnchor:foregroundCoverArtView.topAnchor constant:-VLCUIUnits.largeSpacing]
    ]];
}

- (void)playerCurrentMediaItemChanged:(NSNotification *)notification
{
    NSParameterAssert(notification);
    VLCPlayerController * const controller = notification.object;
    NSAssert(controller != nil, 
             @"Player current media item changed notification should have valid player controller");
    [self updateDecorativeViewVisibilityOnControllerChange:controller];
    [self hidePlaybackFeedback];
    [self updatePlaybackFeedbackAudioStateDisplayingChanges:NO];

    // New item playing, dismiss playback end view
    [self.playbackEndViewController.countdownTimer invalidate];
    [self.playbackEndViewController.view removeFromSuperview];
}

- (void)playerCurrentItemTrackListChanged:(NSNotification *)notification
{
    NSParameterAssert(notification);
    VLCPlayerController * const controller = notification.object;
    NSAssert(controller != nil, 
             @"Player current item track list changed notification should have valid player controller");
    [self updateDecorativeViewVisibilityOnControllerChange:controller];
}

- (void)playerBufferChanged:(NSNotification *)notification
{
    NSParameterAssert(notification);
    NSParameterAssert(notification.userInfo != nil);

    NSNumber * const bufferFillNumber = notification.userInfo[VLCPlayerBufferFill];
    NSAssert(bufferFillNumber != nil, @"Buffer fill number should not be nil");

    const float bufferFill = bufferFillNumber.floatValue;
    self.loadingIndicator.hidden = bufferFill == 1.0;
    if (self.loadingIndicator.hidden) {
        [self.loadingIndicator stopAnimation:self];
    } else {
        [self.loadingIndicator startAnimation:self];
    }
}

- (void)floatOnTopChanged:(NSNotification *)notification
{
    VLCVideoWindowCommon * const videoWindow = (VLCVideoWindowCommon *)notification.object;
    NSAssert(videoWindow != nil, @"Received video window should not be nil!");
    VLCVideoWindowCommon * const selfVideoWindow = (VLCVideoWindowCommon *)self.view.window;

    if (videoWindow != selfVideoWindow) {
        return;
    }

    [self updateFloatOnTopIndicator];
}

- (void)updateFloatOnTopIndicator
{
    vout_thread_t * const voutThread = self.voutView.voutThread;
    if (voutThread == NULL) {
        return;
    }

    const bool floatOnTopEnabled = var_GetBool(voutThread, "video-on-top");
    self.floatOnTopIndicatorImageView.hidden = !floatOnTopEnabled;
}

- (BOOL)mouseOnControls
{
    NSPoint mousePos = [self.view.window mouseLocationOutsideOfEventStream];

    BOOL (^containsMouse)(NSView *) = ^BOOL(NSView *view) {
        if (view == nil) return NO;
        NSPoint localPoint = [view convertPoint:mousePos fromView:nil];
        return [view mouse:localPoint inRect:view.bounds];
    };
    return containsMouse(_centralControlsStackView) ||
        containsMouse(_controlsBar.bottomBarView) ||
        containsMouse(_controlsBar.playingItemDisplayField) ||
        containsMouse(_controlsBar.detailLabel) ||
        containsMouse(_returnButton) ||
        containsMouse(_playQueueButton);
}

- (void)stopAutohideTimer
{
    [_hideControlsTimer invalidate];
}

- (void)startAutohideTimer
{
    /* Do nothing if timer is already in place */
    if (_hideControlsTimer.valid) {
        return;
    }

    /* Get timeout and make sure it is not lower than 1 second */
    long long timeToKeepVisibleInSec = MAX(var_CreateGetInteger(getIntf(), "mouse-hide-timeout") / 1000, 1);

    _hideControlsTimer = [NSTimer scheduledTimerWithTimeInterval:timeToKeepVisibleInSec
                                                          target:self
                                                        selector:@selector(shouldHideControls:)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)shouldHideControls:(id)sender
{
    [self hideControls];
    [NSCursor setHiddenUntilMouseMoves: YES];
}

- (void)hideControls
{
    if (self.voutTaken || self.compactLibraryController.view.superview != nil) {
        return;
    }

    [self stopAutohideTimer];

    if ([self mouseOnControls]) {
        [self showControls];
        return;
    }

    [NSAnimationContext runAnimationRespectingPreferencesWithDuration:VLCUIUnits.controlsFadeAnimationDuration
                                                              changes:^(NSAnimationContext * const _Nonnull __unused context) {
        [self->_mainControlsView.animator setAlphaValue:0.0f];
        [self->_floatOnTopIndicatorImageView.animator setAlphaValue:0.0f];
    } completionHandler:nil];
}

- (void)setAutohideControls:(BOOL)autohide
{
    if (_autohideControls == autohide) {
        return;
    }

    _autohideControls = autohide;

    if (autohide) {
        [self startAutohideTimer];
    } else {
        [self showControls];
    }
}

- (void)shouldShowControls:(NSNotification *)aNotification
{
    [self showControls];
}

- (void)showControls
{
    if (self.voutTaken) {
        return;
    }

    [self stopAutohideTimer];
    [self updatePlayQueueToggleState];
    [self updateLibraryControls];
    if ([self.view.window isKindOfClass:VLCFullVideoViewWindow.class]) [(VLCFullVideoViewWindow *)self.view.window showTitleBar];

    if (!_autohideControls) {
        _mainControlsView.alphaValue = 1.0f;        
        return;
    }


    [NSAnimationContext runAnimationRespectingPreferencesWithDuration:VLCUIUnits.controlsFadeAnimationDuration
                                                              changes:^(NSAnimationContext * const _Nonnull __unused context) {
        self->_isFadingIn = YES;
        [self->_mainControlsView.animator setAlphaValue:1.0f];
        [self->_floatOnTopIndicatorImageView.animator setAlphaValue:1.0f];
    } completionHandler:^{
        self->_isFadingIn = NO;
        [self startAutohideTimer];
    }];
}

- (void)setDisplayLibraryControls:(BOOL)displayLibraryControls
{
    _displayLibraryControls = displayLibraryControls;

    _returnButton.hidden = !displayLibraryControls;
    _playQueueButton.hidden = NO;
}

- (void)updatePlayQueueToggleState
{
    NSWindow *window = self.view.window;
    VLCLibraryWindow * const libraryWindow = [window isKindOfClass:VLCLibraryWindow.class] ? (VLCLibraryWindow *)window : nil;
    if (libraryWindow != nil && _displayLibraryControls) {
        const BOOL sidebarCollapsed = libraryWindow.splitViewController.multifunctionSidebarItem.isCollapsed;
        self.playQueueButton.state = sidebarCollapsed ? NSControlStateValueOff : NSControlStateValueOn;
    } else {
        self.playQueueButton.state = self.queuePopover.shown ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (NSRect)windowButtonsRect
{
    NSWindow * const window = self.view.window;
    NSRect buttonBox = NSZeroRect;

    NSButton * const closeButton = [window standardWindowButton:NSWindowCloseButton];
    if (closeButton) {
        buttonBox = NSUnionRect(buttonBox, closeButton.frame);
    }

    NSButton * const minimizeButton = [window standardWindowButton:NSWindowMiniaturizeButton];
    if (minimizeButton) {
        buttonBox = NSUnionRect(buttonBox, minimizeButton.frame);
    }

    NSButton * const zoomButton = [window standardWindowButton:NSWindowZoomButton];
    if (zoomButton) {
        buttonBox = NSUnionRect(buttonBox, zoomButton.frame);
    }

    return buttonBox;
}

- (void)updateLibraryControls:(NSNotification *)notification
{
    [self updateLibraryControls];
}

- (void)updateLibraryControls
{
    const NSWindow *window = self.view.window;
    const BOOL fullscreen = [(VLCWindow *)window isInNativeFullscreen] || [(VLCWindow *)window fullscreen];
    // Native traffic lights retain their own titlebar; all media header items share the next40px row.
    const CGFloat titlebarSpace = !fullscreen && window.titlebarAppearsTransparent ? window.titlebarHeight : 0.;
    self.fakeTitleBarHeightConstraint.constant = titlebarSpace + 40.;
    self.returnButtonTopConstraint.constant = -20.;
    self.returnButtonLeadingConstraint.constant = 16.;
    _returnButtonBottomConstraint.active = NO;
    _playQueueButtonBottomConstraint.active = NO;
    self.returnButton.controlSize = NSControlSizeRegular;
    self.playQueueButton.controlSize = NSControlSizeRegular;
    self.returnButton.image = [NSImage vlc_redesignImageNamed:@"back"] ?: self.returnButton.image;
    self.fakeTitleBar.wantsLayer = YES;
    self.fakeTitleBar.layer.backgroundColor = NSColor.VLCHeaderBackgroundColor.CGColor;
    _overlayView.drawGradientForTopControls = NO;
    [_overlayView setNeedsDisplay:YES];
}

- (BOOL)pipIsActive
{
    return _voutViewController != nil;
}

- (void)pictureInPictureChanged:(NSNotification *)notification
{
    if (self.pipIsActive) {
        return;
    }

    VLCVideoWindowCommon * const videoWindow =
        [VLCMain.sharedInstance.voutProvider videoWindowForVoutView:self.voutView];
    if (videoWindow.fullscreen && !videoWindow.isInNativeFullscreen) {
        [videoWindow leaveFullscreenWithAnimation:NO];
    }

    NSWindow * const window = self.view.window;
    [window orderOut:window];
    self.retainedWindow = window;

    _voutViewController = [PIPVoutViewController new];
    _voutViewController.view = [self acquireVideoView];
    NSAssert(_voutViewController.view != nil, @"Vout view should not be nil");
    VLCPlayerController * const controller = notification.object;
    _pipViewController.playing = controller.playerState == VLC_PLAYER_STATE_PLAYING;
    
    VLCInputItem * const item = controller.currentMedia;
    input_item_t * const p_input = item.vlcInputItem;
    vlc_mutex_lock(&p_input->lock);
    const struct input_item_es *item_es;
    vlc_vector_foreach_ref(item_es, &p_input->es_vec) {
        if (item_es->es.i_cat != VIDEO_ES) {
            continue;
        }
        const video_format_t * const fmt = &item_es->es.video;
        unsigned int width = fmt->i_visible_width;
        unsigned int height = fmt->i_visible_height;
        if (fmt->i_sar_num && fmt->i_sar_den) {
            height = (height * fmt->i_sar_den) / fmt->i_sar_num;
        }
        _pipViewController.aspectRatio = CGSizeMake(width, height);
        break;
    }
    vlc_mutex_unlock(&p_input->lock);
    _pipViewController.title = window.title;
    
    __weak typeof(self) weakSelf = self;

    void (^presentVcAsPip)(void) = ^() {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf->_voutViewController.presentingViewController == nil) {
            [strongSelf->_pipViewController presentViewControllerAsPictureInPicture:strongSelf->_voutViewController];
        }
    };

    if (!controller.currentMediaIsAudioOnly) {
        _voutViewController.boundsChangeHandler = presentVcAsPip;
    }

    // Present PiP asynchronously. Previously the video path waited for
    // PIPVoutViewController's viewDidLayout to fire via boundsChangeHandler, but
    // on macOS 26 Tahoe the detached view never receives a layout pass, so the
    // handler never fired. The acquired view already has valid bounds so we can
    // present immediately on the next run-loop cycle for both paths.
    dispatch_async(dispatch_get_main_queue(), ^{
        presentVcAsPip();
    });

    if ([window isKindOfClass:VLCLibraryWindow.class]) {
        [self returnToLibrary:self];
    }
}

- (IBAction)togglePlayQueue:(id)sender
{
    NSWindow * const host = self.view.window;
    if (!host) return;
    [self.controlsBar closePlaybackSettings:nil];
    if ([host isKindOfClass:VLCLibraryWindow.class] && self.displayLibraryControls) {
        [((VLCLibraryWindow *)host).splitViewController toggleMultifunctionSidebar:self];
        return;
    }
    if (self.queuePopover.shown) { [self closePlayQueuePane]; return; }
    if (!self.queuePopover) {
        // Figma Queue 463:831 reuses the real Queue/Bookmarks/Chapters controllers.
        VLCLibraryWindowSidebarRootViewController *controller = [[VLCLibraryWindowSidebarRootViewController alloc] initWithLibraryWindow:VLCMain.sharedInstance.libraryWindow];
        (void)controller.view;
        controller.mainVideoModeEnabled = YES;
        self.queuePopover = [[NSPopover alloc] init];
        self.queuePopover.contentViewController = controller;
        self.queuePopover.behavior = NSPopoverBehaviorSemitransient;
        self.queuePopover.delegate = self;
    }
    CGFloat header = self.fakeTitleBarHeightConstraint.constant;
    CGFloat height = MAX(180., NSHeight(host.contentView.bounds) - header - NSHeight(self.bottomBarView.bounds) - 20.);
    self.queuePopover.contentSize = NSMakeSize(MIN(400., MAX(240., NSWidth(host.contentView.bounds) - 20.)), height);
    self.queuePreviousAutohide = self.autohideControls;
    self.autohideControls = NO;
    NSView *anchor = host.contentView;
    CGFloat center = NSMaxY(anchor.bounds) - header - height / 2.;
    if (anchor.isFlipped) center = NSMinY(anchor.bounds) + header + height / 2.;
    [self.queuePopover showRelativeToRect:NSMakeRect(NSMaxX(anchor.bounds) - 1., center, 1., 1.) ofView:anchor preferredEdge:NSRectEdgeMinX];
    [self updatePlayQueueToggleState];
}

- (void)closePlayQueuePane
{
    BOOL animated = self.queuePopover.animates;
    self.queuePopover.animates = NO;
    [self.queuePopover close];
    self.queuePopover.animates = animated;
}

- (void)viewWillDisappear
{
    [super viewWillDisappear];
    [self closePlayQueuePane];
    [self.controlsBar closePlaybackSettings:nil];
}

- (void)popoverDidClose:(NSNotification *)notification
{
    if (notification.object != self.queuePopover) return;
    self.autohideControls = self.queuePreviousAutohide;
    [self updatePlayQueueToggleState];
}

- (IBAction)returnToLibrary:(id)sender
{
    if (self.compactLibraryController.view.superview) [self closeCompactLibrary];
    if (self.playbackEndViewController) { // Stop any pending automatic return to library
        [self.playbackEndViewController.countdownTimer invalidate];
        [self.playbackEndViewController.view removeFromSuperview];
    }
    if (self.view.window.class == VLCLibraryWindow.class) {
        [(VLCLibraryWindow *)self.view.window disableVideoPlaybackAppearance];
    } else {
        [self.view.window close];
    }
}

- (nullable NSView *)acquireVideoView
{
    if (self.voutTaken) {
        return nil;
    }
    self.voutTaken = YES;
    self.statisticsVisible = NO;
    if (self.compactLibraryController.view.superview) [self closeCompactLibrary];
    [self.voutContainingView removeFromSuperview];
    return self.voutContainingView;
}

- (void)returnVideoView:(NSView *)videoView
{
    NSParameterAssert(videoView != nil);
    [videoView removeFromSuperview];
    [self.view addSubview:videoView
               positioned:NSWindowBelow
               relativeTo:self.mainControlsView];
    
    videoView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [videoView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [videoView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    [self configureVideoContentConstraints];

    [self applyAudioDecorativeViewForegroundCoverArtViewConstraints];
    self.voutTaken = NO;
}

- (void)displayPlaybackEndView
{
    if (_playbackEndViewController == nil) {
        _playbackEndViewController = [[VLCPlaybackEndViewController alloc] init];

        NSNotificationCenter * const defaultCenter = NSNotificationCenter.defaultCenter;
        [defaultCenter addObserver:self
                          selector:@selector(playbackEndViewReturnToLibrary:)
                              name:VLCPlaybackEndViewReturnToLibraryNotificationName
                            object:self.playbackEndViewController];
        [defaultCenter addObserver:self
                          selector:@selector(playbackEndViewHide:)
                              name:VLCPlaybackEndViewHideNotificationName
                            object:self.playbackEndViewController];
    }

    self.playbackEndViewController.hideLibraryControls = !self.displayLibraryControls;
    [self.view addSubview:self.playbackEndViewController.view];
    [self.playbackEndViewController.view.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [self.playbackEndViewController.view.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor].active = YES;
    [self.playbackEndViewController.view.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor].active = YES;
    [self.playbackEndViewController.view.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor].active = YES;
    [self.playbackEndViewController startCountdown];
}

- (void)playbackEndViewReturnToLibrary:(NSNotification *)notification
{
    if (self.endViewDismissHandler)
        self.endViewDismissHandler();
    else
        [self returnToLibrary:self];
}

- (void)playbackEndViewHide:(NSNotification *)notification
{
    [self.playbackEndViewController.view removeFromSuperview];
    if (self.endViewDismissHandler)
        self.endViewDismissHandler();
}

#pragma mark - PIPViewControllerDelegate

- (BOOL)pipShouldClose:(PIPViewController *)pip
{
    return YES;
}

- (void)pipWillClose:(PIPViewController *)pip
{
    NSWindow * const window = self.retainedWindow;
    pip.replacementWindow = window;
    pip.replacementRect = self.view.frame;
    if ([window isKindOfClass:VLCLibraryWindow.class]) {
        [(VLCLibraryWindow *)window enableVideoPlaybackAppearance];
    }
    [window makeKeyAndOrderFront:window];
    self.retainedWindow = nil;
}

- (void)pipDidClose:(PIPViewController *)pip
{
    [self returnVideoView:_voutViewController.view];
    _voutViewController = nil;
}

- (void)pipActionPlay:(PIPViewController *)pip
{
    VLCPlayerController * const controller =
        VLCMain.sharedInstance.playQueueController.playerController;
    if (controller.playerState == VLC_PLAYER_STATE_PAUSED) {
        [controller resume];
    } else {
        [controller start];
    }
}

- (void)pipActionStop:(PIPViewController *)pip
{
    VLCPlayerController * const controller =
        VLCMain.sharedInstance.playQueueController.playerController;
    [controller pause];
}

- (void)pipActionPause:(PIPViewController *)pip
{
    VLCPlayerController * const controller =
        VLCMain.sharedInstance.playQueueController.playerController;
    [controller pause];
}

@end
