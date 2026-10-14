/*****************************************************************************
* VLCDetachedAudioWindow.m: macOS user interface
*****************************************************************************
* Copyright (C) 2019 VLC authors and VideoLAN
*
* Author: Felix Paul Kühne <fkuehne at videolan dot org>
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

#import "VLCDetachedAudioWindow.h"

#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"

#import "library/VLCInputItem.h"

#import "main/VLCMain.h"
#import "library/VLCLibraryWindow.h"

#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"

#import "views/VLCTrackingView.h"
#import "views/VLCBottomBarView.h"

#import "windows/controlsbar/VLCControlsBarCommon.h"

#import "windows/video/VLCMainVideoViewAudioMediaDecorativeView.h"
#import "windows/video/VLCMainVideoViewController.h"
#import "windows/controlsbar/VLCMainVideoViewControlsBar.h"
#import "windows/video/VLCMainVideoViewOverlayView.h"

@implementation VLCDetachedAudioWindow

- (void)setupAudioDecorativeView
{
    _decorativeView = self.videoViewController.audioDecorativeView;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    self.title = @"";
    // Figma Music4767:23726 uses the same header and54px controls as video.
    // Reuse their existing actions/state, artwork and source metadata instead
    // of stacking the legacy detached bar's duplicate title over the artwork.
    self.titlebarAppearsTransparent = YES;
    self.videoViewController.displayLibraryControls = NO;
    NSView * const playerView = self.videoViewController.view;
    playerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.contentView = playerView;
    self.controlsBar = self.videoViewController.controlsBar;
    self.overlayView = self.videoViewController.overlayView;
    self.bottomBarView = (VLCBottomBarView *)self.videoViewController.bottomBarView;
    [self setContentSize:VLCMain.sharedInstance.libraryWindow.contentView.bounds.size];
    self.videoViewController.autohideControls = NO;
    [self.videoViewController showControls];
    [self setupAudioDecorativeView];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (BOOL)canBecomeMainWindow
{
    return YES;
}

- (BOOL)isMovableByWindowBackground
{
    return YES;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    if (event.modifierFlags & NSEventModifierFlagCommand && event.keyCode == 13) {
        [self closeAndAnimate:YES];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

@end
