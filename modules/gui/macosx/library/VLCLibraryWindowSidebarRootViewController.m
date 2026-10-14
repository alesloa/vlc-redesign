/*****************************************************************************
 * VLCLibraryWindowSidebarRootViewController.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2024 VLC authors and VideoLAN
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

#import "VLCLibraryWindowSidebarRootViewController.h"

#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSTextField+VLCAdditions.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSWindow+VLCAdditions.h"

#import "library/VLCInputItem.h"
#import "library/VLCLibraryWindow.h"
#import "library/VLCLibraryWindowBookmarksSidebarViewController.h"
#import "library/VLCLibraryWindowChaptersSidebarViewController.h"
#import "library/VLCLibraryWindowPlayQueueSidebarViewController.h"
#import "library/VLCLibraryWindowSidebarChildViewController.h"
#import "library/VLCLibraryWindowTitlesSidebarViewController.h"

#import "main/VLCMain.h"

#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"

#import "views/VLCRoundedCornerTextField.h"
#import "views/VLCUIUnits.h"
#import <vlc_media_library.h>

@interface VLCLibraryWindowSidebarRootViewController ()

@property (readwrite) NSViewController<VLCLibraryWindowSidebarChildViewController> *currentChildVc;
@property NSArray<NSViewController<VLCLibraryWindowSidebarChildViewController> *> *tabControllers;
@property NSStackView *tabStack;

@end

@implementation VLCLibraryWindowSidebarRootViewController

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    self = [super initWithNibName:@"VLCLibraryWindowSidebarRootView" bundle:nil];
    if (self) {
        _libraryWindow = libraryWindow;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.identifier = @"VLCRedesignedLibraryContent";
    self.view.wantsLayer = YES;
    [self setupPlayQueueTitle];
    [self setupCounterLabel];

    self.topInternalConstraint.constant = [self topConstraintConstant];

    self.mainVideoModeEnabled = NO;

    _playQueueSidebarViewController =
        [[VLCLibraryWindowPlayQueueSidebarViewController alloc] initWithLibraryWindow:self.libraryWindow];
    _chaptersSidebarViewController =
        [[VLCLibraryWindowChaptersSidebarViewController alloc] initWithLibraryWindow:self.libraryWindow];
    _titlesSidebarViewController =
        [[VLCLibraryWindowTitlesSidebarViewController alloc] initWithLibraryWindow:self.libraryWindow];
    if (vlc_ml_instance_get(getIntf()) != NULL)
        _bookmarksSidebarViewController = [[VLCLibraryWindowBookmarksSidebarViewController alloc] initWithLibraryWindow:self.libraryWindow];

    self.targetView.translatesAutoresizingMaskIntoConstraints = NO;

    self.viewSelector.segmentDistribution = NSSegmentDistributionFillEqually;
    // Figma 6320:13763: full-width 50px tab row, 20px icons, 12px labels.
    _tabStack = [[NSStackView alloc] init];
    _tabStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _tabStack.distribution = NSStackViewDistributionFillEqually;
    _tabStack.spacing = 1;
    _tabStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tabStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.viewSelector.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:6],
        [self.viewSelector.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-6],
        [self.viewSelector.heightAnchor constraintEqualToConstant:50],
        [_tabStack.topAnchor constraintEqualToAnchor:self.viewSelector.topAnchor],
        [_tabStack.leadingAnchor constraintEqualToAnchor:self.viewSelector.leadingAnchor],
        [_tabStack.trailingAnchor constraintEqualToAnchor:self.viewSelector.trailingAnchor],
        [_tabStack.bottomAnchor constraintEqualToAnchor:self.viewSelector.bottomAnchor]
    ]];

    [self setupViewSelectorSegments];
    [self updateViewSelectorState];
    [self viewSelectorAction:self.viewSelector];

    NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(titleListChanged:)
                               name:VLCPlayerTitleListChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(mediaItemChanged:)
                               name:VLCPlayerCurrentMediaItemChanged
                             object:nil];
}

- (void)setupPlayQueueTitle
{
    _playQueueHeaderLabel = [NSTextField defaultLabelWithString:@""];
    self.playQueueHeaderLabel.font = NSFont.VLCLibrarySubsectionHeaderFont;
    self.playQueueHeaderLabel.textColor = NSColor.headerTextColor;

    [self.view addSubview:self.playQueueHeaderLabel];

    _playQueueHeaderTopConstraint = 
        [self.playQueueHeaderLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor
                                                            constant:VLCUIUnits.libraryWindowContentSafeTopInset + VLCUIUnits.smallSpacing];
    [NSLayoutConstraint activateConstraints:@[
        self.playQueueHeaderTopConstraint,
        [self.playQueueHeaderLabel.bottomAnchor constraintEqualToAnchor:self.targetView.topAnchor
                                                               constant:-VLCUIUnits.smallSpacing],
        [self.playQueueHeaderLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                                constant:VLCUIUnits.largeSpacing] 
    ]];
}

- (void)setupViewSelectorSegments
{
    NSViewController *selected = self.currentChildVc ?: self.playQueueSidebarViewController;
    NSMutableArray *controllers = [NSMutableArray arrayWithObject:self.playQueueSidebarViewController];
    if (self.bookmarksSidebarViewController) [controllers addObject:self.bookmarksSidebarViewController];
    [controllers addObject:self.chaptersSidebarViewController];
    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    if (player.numberOfTitlesOfCurrentMedia > 0) [controllers addObject:self.titlesSidebarViewController];
    self.tabControllers = controllers;
    self.viewSelector.segmentCount = controllers.count;
    for (NSView *view in self.tabStack.arrangedSubviews.copy) [view removeFromSuperview];
    for (NSInteger i = 0; i < controllers.count; i++) {
        NSViewController<VLCLibraryWindowSidebarChildViewController> *controller = controllers[i];
        [self.viewSelector setLabel:controller.title forSegment:i];
        NSButton *button = [NSButton buttonWithTitle:controller.title target:self action:@selector(selectTab:)];
        button.tag = i;
        button.bordered = NO;
        button.font = [NSFont vlc_redesignFontOfSize:12 weight:NSFontWeightRegular];
        button.identifier = @"VLCRedesignedSettingsCategory";
        NSString *icon = controller == self.playQueueSidebarViewController ? @"player-tab-queue" : controller == self.bookmarksSidebarViewController ? @"player-tab-bookmarks" : @"player-tab-chapters";
        button.image = [NSImage vlc_redesignImageNamed:icon];
        button.image.size = NSMakeSize(20, 20);
        button.imagePosition = NSImageLeft;
        [button setButtonType:NSButtonTypePushOnPushOff];
        [self.tabStack addArrangedSubview:button];
    }
    NSUInteger index = [controllers indexOfObjectIdenticalTo:selected];
    self.viewSelector.selectedSegment = index == NSNotFound ? 0 : index;
}

- (void)selectTab:(NSButton *)sender
{
    self.viewSelector.selectedSegment = sender.tag;
    [self viewSelectorAction:self.viewSelector];
}

- (void)setupCounterLabel
{
    _counterLabel = [[VLCRoundedCornerTextField alloc] init];
    self.counterLabel.useStrongRounding = NO;
    self.counterLabel.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
    self.counterLabel.backgroundColor = NSColor.clearColor;
    self.counterLabel.textColor = NSColor.VLCControlForegroundColor;
    self.counterLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.counterLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.counterLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                                 forOrientation:NSLayoutConstraintOrientationVertical];

    [self.view addSubview:self.counterLabel];

    _counterLabelInHeaderConstraint = 
        [self.counterLabel.centerYAnchor constraintEqualToAnchor:self.playQueueHeaderLabel.centerYAnchor];
    _counterLabelInChildViewConstraint =
        [self.counterLabel.topAnchor constraintEqualToAnchor:self.targetView.topAnchor
                                                    constant:20];
    
    [NSLayoutConstraint activateConstraints:@[
        self.counterLabelInHeaderConstraint,
        [self.counterLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor
                                                        constant:VLCUIUnits.largeSpacing]
    ]];
}

- (void)titleListChanged:(NSNotification *)notification
{
    [self updateViewSelectorState];
}

- (void)mediaItemChanged:(NSNotification *)notification
{
    [self updateViewSelectorState];
}

- (void)updateViewSelectorState
{
    [self setupViewSelectorSegments];
    self.viewSelector.hidden = YES;
    self.playQueueHeaderLabel.hidden = YES;
    self.playQueueHeaderTopConstraint.active = NO;
    self.counterLabelInHeaderConstraint.active = NO;
    self.counterLabelInChildViewConstraint.active = YES;
    self.topInternalConstraint.active = YES;
    [self viewSelectorAction:self.viewSelector];
}

- (IBAction)viewSelectorAction:(id)sender
{
    NSInteger index = self.viewSelector.selectedSegment;
    if (index < 0 || index >= self.tabControllers.count) index = 0;
    [self setChildViewController:self.tabControllers[index]];
    for (NSButton *button in self.tabStack.arrangedSubviews) {
        BOOL selected = button.tag == index;
        button.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
        button.wantsLayer = YES;
        button.layer.cornerRadius = 6;
        button.layer.backgroundColor = (selected ? NSColor.VLCSelectedRowColor : NSColor.clearColor).CGColor;
        button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title attributes:@{
            NSForegroundColorAttributeName: selected ? NSColor.VLCPrimaryForegroundColor : NSColor.VLCControlForegroundColor,
            NSFontAttributeName:button.font
        }];
        [button vlc_applyRedesignStyle];
    }
}

- (void)setChildViewController:(NSViewController<VLCLibraryWindowSidebarChildViewController> *)viewController
{
    self.currentChildVc.counterLabel = nil; // Stop old vc manipulating the counter label
    self.currentChildVc = viewController;
    
    self.counterLabel.hidden = !viewController.supportsItemCount;
    if (viewController.supportsItemCount) {
        viewController.counterLabel = self.counterLabel;
    }

    self.playQueueHeaderLabel.stringValue = viewController.title;

    NSView * const view = viewController.view;
    self.targetView.subviews = @[view];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view applyConstraintsToFillSuperview];
}

- (void)setMainVideoModeEnabled:(BOOL)mainVideoModeEnabled
{
    _mainVideoModeEnabled = mainVideoModeEnabled;
    [self updateTopConstraints];
}

- (CGFloat)topConstraintConstant
{
    CGFloat constant = VLCUIUnits.smallSpacing;
    if (@available(macOS 11.0, *)) {
        // Safe area layout guide already accounts for titlebar height
        if (!self.mainVideoModeEnabled) {
            constant += VLCUIUnits.libraryWindowContentSafeTopInset;
        }
    } else if (!self.mainVideoModeEnabled && self.libraryWindow.styleMask & NSWindowStyleMaskFullSizeContentView) {
        // Compensate for full content view window's titlebar height, prevent top being cut off
        constant += self.libraryWindow.titlebarHeight;
    }
    return constant;
}

- (void)updateTopConstraints
{
    const CGFloat internalTopConstraintConstant = [self topConstraintConstant];
    self.topInternalConstraint.constant = internalTopConstraintConstant;
    self.playQueueHeaderTopConstraint.constant = internalTopConstraintConstant;
}

@end
