/*****************************************************************************
 * VLCFullVideoViewWindow.m: MacOS X interface module
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

#import "VLCFullVideoViewWindow.h"

#import "VLCMainVideoViewController.h"

#import "extensions/NSAnimationContext+VLCAdditions.h"

#import "main/VLCMain.h"

#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"

#import "views/VLCUIUnits.h"

@interface VLCFullVideoViewWindow ()
{
    BOOL _autohideTitlebar;
    NSTimer *_hideTitlebarTimer;
    BOOL _isFadingIn;
    BOOL _titlebarIsTearingDown;
    NSUInteger _titlebarTimerGeneration;
    __weak VLCMain *_interfaceOwner;
}
@end

@implementation VLCFullVideoViewWindow

- (void)setup
{
    [super setup];
    _autohideTitlebar = NO;
    _interfaceOwner = VLCMain.sharedInstance;

    NSNotificationCenter *notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(shouldShowFullscreenController:)
                               name:VLCVideoWindowShouldShowFullscreenController
                             object:nil];
    [notificationCenter addObserver:self selector:@selector(titlebarWillTerminate:)
                               name:NSApplicationWillTerminateNotification object:nil];
    [notificationCenter addObserver:self selector:@selector(titlebarWindowWillClose:)
                               name:NSWindowWillCloseNotification object:self];

    self.titleVisibility = NSWindowTitleHidden;
    self.styleMask |= NSWindowStyleMaskFullSizeContentView;
    self.ignoresMouseEvents = NO;
    self.acceptsMouseMovedEvents = YES;
}

- (void)stopTitlebarAutohideTimer
{
    [_hideTitlebarTimer invalidate];
    _hideTitlebarTimer = nil;
    ++_titlebarTimerGeneration;
}

- (void)titlebarWillTerminate:(NSNotification *)notification
{
    _titlebarIsTearingDown = YES;
    [self stopTitlebarAutohideTimer];
}

- (void)titlebarWindowWillClose:(NSNotification *)notification
{
    [self stopTitlebarAutohideTimer];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_hideTitlebarTimer invalidate];
}

- (void)startTitlebarAutohideTimer
{
    // Animation completions can run after CloseIntf has retired the interface.
    // Use the existing owner; sharedInstance would create another during teardown.
    VLCMain *owner = _interfaceOwner;
    if (_titlebarIsTearingDown || !owner || owner.isTerminating ||
        !_autohideTitlebar || getIntf() == NULL) {
        return;
    }
    /* Do nothing if timer is already in place */
    if (_hideTitlebarTimer.valid) {
        return;
    }

    /* Get timeout and make sure it is not lower than 1 second */
    long long timeToKeepVisibleInSec = MAX(var_CreateGetInteger(getIntf(), "mouse-hide-timeout") / 1000, 1);

    _hideTitlebarTimer = [NSTimer scheduledTimerWithTimeInterval:timeToKeepVisibleInSec
                                                          target:self
                                                        selector:@selector(hideTitleBar:)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)showTitleBar
{
    [self stopTitlebarAutohideTimer];
    if (_titlebarIsTearingDown) {
        return;
    }
    const NSUInteger generation = _titlebarTimerGeneration;

    NSView *titlebarView = [self standardWindowButton:NSWindowCloseButton].superview;

    if (!_autohideTitlebar) {
        titlebarView.alphaValue = 1.0f;
        return;
    }

    [NSAnimationContext runAnimationRespectingPreferencesWithDuration:VLCUIUnits.controlsFadeAnimationDuration
                                                              changes:^(NSAnimationContext * const _Nonnull __unused context){
        self->_isFadingIn = YES;
        [titlebarView.animator setAlphaValue:1.0f];
    } completionHandler:^{
        self->_isFadingIn = NO;
        if (generation == self->_titlebarTimerGeneration) {
            [self startTitlebarAutohideTimer];
        }
    }];
}

- (void)hideTitleBar:(id)sender
{
    [self stopTitlebarAutohideTimer];
    if (_titlebarIsTearingDown) {
        return;
    }

    if (self.videoViewController.mouseOnControls ||
        !_autohideTitlebar ||
        self.isInNativeFullscreen ||
        self.videoViewController.view.hidden ||
        !self.videoViewController.autohideControls) {

        [self showTitleBar];
        return;
    }

    NSView *titlebarView = [self standardWindowButton:NSWindowCloseButton].superview;

    [NSAnimationContext runAnimationRespectingPreferencesWithDuration:VLCUIUnits.controlsFadeAnimationDuration
                                                              changes:^(NSAnimationContext * const _Nonnull __unused context) {
        [titlebarView.animator setAlphaValue:0.0f];
    } completionHandler:nil];
}

- (void)enableVideoTitleBarMode
{
    self.toolbar.visible = NO;
    self.titlebarAppearsTransparent = YES;

    _autohideTitlebar = YES;
    [self showTitleBar];
}

- (void)disableVideoTitleBarMode
{
    self.toolbar.visible = YES;
    self.titlebarAppearsTransparent = NO;

    _autohideTitlebar = NO;
    [self showTitleBar];
}

- (void)shouldShowFullscreenController:(NSNotification *)aNotification
{
    [self showTitleBar];
}

- (void)mouseMoved:(NSEvent *)event
{
    [super mouseExited:event];

    NSPoint mouseLocation = [event locationInWindow];

    BOOL mouseOutsideWindow = ![self.contentView mouse:mouseLocation inRect:self.contentView.frame];

    if (_autohideTitlebar && mouseOutsideWindow) {
        [self hideTitleBar:self];
    }

    if (self.videoViewController.autohideControls && mouseOutsideWindow) {
        [self.videoViewController hideControls];
    }
}

@end
