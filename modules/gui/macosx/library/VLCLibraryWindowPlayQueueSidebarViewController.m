/*****************************************************************************
 * VLCLibraryWindowPlayQueueSidebarViewController.m: MacOS X interface module
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

#import "VLCLibraryWindowPlayQueueSidebarViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "extensions/NSAppearance+VLCAdditions.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSWindow+VLCAdditions.h"

#import "library/VLCLibraryWindow.h"

#import "main/VLCMain.h"

#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayQueueDataSource.h"
#import "playqueue/VLCPlayQueueModel.h"
#import "playqueue/VLCPlayQueueItem.h"
#import "playqueue/VLCPlayQueueSortingMenuController.h"

#import "views/VLCDragDropView.h"
#import "views/VLCRoundedCornerTextField.h"
#import "views/VLCUIUnits.h"

#import "windows/VLCOpenWindowController.h"

@implementation VLCLibraryWindowPlayQueueSidebarViewController
{
    CAGradientLayer *_scrollViewGradientMask;
    NSSearchField *_queueSearch;
}

@synthesize counterLabel = _counterLabel;

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    return [super initWithLibraryWindow:libraryWindow
                                nibName:@"VLCLibraryWindowPlayQueueView"];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.dragDropView.dropTarget = self.libraryWindow;

    _playQueueController = VLCMain.sharedInstance.playQueueController;
    _dataSource = [[VLCPlayQueueDataSource alloc] init];
    self.dataSource.playQueueController = self.playQueueController;
    self.dataSource.tableView = self.tableView;
    self.dataSource.dragDropView = self.dragDropView;
    self.dataSource.counterTextField = self.counterLabel;
    [self.dataSource prepareForUse];
    if (!self.playQueueController.playQueueDataSource)
        self.playQueueController.playQueueDataSource = self.dataSource;
    [self.dataSource playQueueUpdated];

    self.tableView.dataSource = self.dataSource;
    self.tableView.delegate = self.dataSource;
    self.tableView.identifier = @"VLCRedesignedQueueTable";
    self.tableView.rowHeight = 32;
    self.tableView.intercellSpacing=NSMakeSize(0,12);
    [self.tableView reloadData];

    self.openMediaButton.title = _NS("Open media...");

    // Allow the drop zone image to shrink when the sidebar is contracted
    for (NSView * const subview in self.dragDropView.subviews) {
        if ([subview isKindOfClass:[VLCDropDisabledImageView class]]) {
            for (NSLayoutConstraint * const constraint in subview.constraints) {
                if (constraint.firstAttribute == NSLayoutAttributeWidth ||
                    constraint.firstAttribute == NSLayoutAttributeHeight) {
                    constraint.priority = NSLayoutPriorityDefaultLow;
                }
            }
            [subview.widthAnchor constraintEqualToAnchor:subview.heightAnchor].active = YES;
            [subview setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];
            [subview setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                             forOrientation:NSLayoutConstraintOrientationVertical];
            break;
        }
    }
    [self.dragDropView.bottomAnchor
        constraintGreaterThanOrEqualToAnchor:self.openMediaButton.bottomAnchor
                                    constant:VLCUIUnits.smallSpacing].active = YES;

    self.shuffleButton.toolTip = _NS("Shuffle");
    self.repeatButton.toolTip = _NS("Repeat");
    self.sortButton.toolTip = _NS("Sort Play Queue");
    self.clearButton.toolTip = _NS("Clear Play Queue");

    [self repeatStateUpdated:nil];
    [self shuffleStateUpdated:nil];

    NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(shuffleStateUpdated:)
                               name:VLCPlaybackOrderChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(repeatStateUpdated:)
                               name:VLCPlaybackRepeatChanged
                             object:nil];

    [self setupQueueShell];
}
- (void)setupQueueShell
{
    // Figma Queue463:831:20px margins,24px actions and32px rows/12px gaps.
    // Search/Insert/Sort/Clear reuse the real queue and original file chooser.
    NSTableView *table=self.tableView;VLCDragDropView *drop=self.dragDropView;
    NSArray *buttons=@[self.shuffleButton,self.repeatButton,self.sortButton,self.clearButton];
    NSButton *insert=self.openMediaButton;
    for(NSView *view in self.view.subviews.copy)[view removeFromSuperview];
    self.view.identifier=@"VLCRedesignedQueuePane";
    self.view.wantsLayer=YES;
    NSStackView *actions=[NSStackView stackViewWithViews:buttons];actions.spacing=12;actions.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:actions];
    for(NSButton *button in buttons){button.bordered=NO;[NSLayoutConstraint activateConstraints:@[[button.widthAnchor constraintEqualToConstant:24],[button.heightAnchor constraintEqualToConstant:24]]];}
    self.sortButton.image=[NSImage vlc_redesignImageNamed:@"library-sort"] ?: self.sortButton.image;
    self.clearButton.image=[NSImage vlc_redesignImageNamed:@"queue-remove"];
    _queueSearch=[NSSearchField new];_queueSearch.placeholderString=_NS("Search");_queueSearch.delegate=self;
    _queueSearch.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
    _queueSearch.bezelStyle=NSTextFieldSquareBezel;
    _queueSearch.bezeled=NO;
    _queueSearch.wantsLayer=YES;
    _queueSearch.layer.cornerRadius=6;
    _queueSearch.identifier=@"VLCRedesignedSettingsCard";
    _queueSearch.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:_queueSearch];
    insert.title=_NS("Insert");insert.target=self;insert.action=@selector(insertMedia:);insert.translatesAutoresizingMaskIntoConstraints=NO;
    insert.bordered=NO;insert.wantsLayer=YES;insert.layer.cornerRadius=6;
    insert.identifier=@"VLCRedesignedSettingsSidebar";
    insert.attributedTitle=[[NSAttributedString alloc] initWithString:insert.title attributes:@{NSForegroundColorAttributeName:NSColor.VLCControlForegroundColor,NSFontAttributeName:[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular]}];
    [self.view addSubview:insert];
    NSScrollView *scroll=[NSScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.hasVerticalScroller=YES;
    scroll.drawsBackground=NO;scroll.documentView=table;table.headerView=nil;[self.view addSubview:scroll];
    drop.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:drop];
    [NSLayoutConstraint activateConstraints:@[
        [actions.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],[actions.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_queueSearch.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],[_queueSearch.trailingAnchor constraintEqualToAnchor:insert.leadingAnchor constant:-8],
        [_queueSearch.topAnchor constraintEqualToAnchor:actions.bottomAnchor constant:20],[_queueSearch.heightAnchor constraintEqualToConstant:32],
        [insert.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],[insert.centerYAnchor constraintEqualToAnchor:_queueSearch.centerYAnchor],
        [insert.widthAnchor constraintEqualToConstant:76],[insert.heightAnchor constraintEqualToConstant:32],
        [scroll.leadingAnchor constraintEqualToAnchor:_queueSearch.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:insert.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:_queueSearch.bottomAnchor constant:12],[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-20],
        [drop.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],[drop.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [drop.topAnchor constraintEqualToAnchor:scroll.topAnchor],[drop.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor]
    ]];
    self.scrollView=scroll;[self.view vlc_applyRedesignStyle];
}
- (void)viewDidLayout
{
    [super viewDidLayout];
    // Reparenting the original table out of its old510px nib clip must also
    // fit the live column to this pane, otherwise its duration/remove buttons
    // remain beyond the400px pane's visible trailing edge.
    CGFloat width = self.scrollView.contentSize.width;
    if (width <= 0.) return;
    self.tableView.autoresizingMask = NSViewWidthSizable;
    [self.tableView setFrameSize:NSMakeSize(width, NSHeight(self.tableView.frame))];
    self.tableView.tableColumns.firstObject.width = width;
    [self.tableView sizeLastColumnToFit];
}
- (void)controlTextDidChange:(NSNotification *)notification
{
    if(notification.object==_queueSearch)self.dataSource.searchQuery=_queueSearch.stringValue;
}
- (void)insertMedia:(id)sender
{
    NSUInteger selected=[self.dataSource modelIndexForVisibleRow:self.tableView.selectedRow];
    uint64_t identifier=selected==NSNotFound?0:[self.playQueueController.playQueueModel playQueueItemAtIndex:selected].uniqueID;
    [VLCMain.sharedInstance.open openFileWithAction:^(NSArray *files){
        NSArray *items=self.playQueueController.playQueueModel.playQueueItems;
        NSUInteger position=items.count;
        if(identifier){NSUInteger index=[items indexOfObjectPassingTest:^BOOL(VLCPlayQueueItem *item,NSUInteger index,BOOL *stop){return item.uniqueID==identifier;}];if(index!=NSNotFound)position=index+1;}
        [self.playQueueController addPlayQueueItems:files atPosition:position startPlayback:NO];
    }];
}

- (void)setupScrollViewGradientMask
{
    const CGFloat gradientHeight = VLCUIUnits.mediumSpacing;

    _scrollViewGradientMask = [CAGradientLayer layer];
    _scrollViewGradientMask.colors = @[
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:0.0].CGColor,
        (__bridge id)[NSColor colorWithWhite:1.0 alpha:1.0].CGColor
    ];
    _scrollViewGradientMask.startPoint = CGPointMake(0.5, 0.0);
    _scrollViewGradientMask.endPoint = CGPointMake(0.5, 1.0);
    _scrollViewGradientMask.locations = @[@0.0, @(gradientHeight / self.scrollView.bounds.size.height)];

    self.scrollView.wantsLayer = YES;
    self.scrollView.layer.mask = _scrollViewGradientMask;
    _scrollViewGradientMask.frame = self.scrollView.bounds;

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(scrollViewFrameDidChange:)
                                               name:NSViewFrameDidChangeNotification
                                             object:self.scrollView];
}

- (void)scrollViewFrameDidChange:(NSNotification *)notification
{
    if (!_scrollViewGradientMask) {
        return;
    }
    _scrollViewGradientMask.frame = self.scrollView.bounds;
}

- (void)setupBlurredHeaderFooter
{
    const CGFloat footerHeight = self.footerContainerView.frame.size.height;
    [self setupScrollViewGradientMask];

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
    if (@available(macOS 26.0, *)) {
        [self.bottomButtonsSeparator removeFromSuperview];

        NSGlassEffectView * const glassFooterView = [[NSGlassEffectView alloc] init];
        glassFooterView.translatesAutoresizingMaskIntoConstraints = NO;
        glassFooterView.contentView = self.buttonStack;
        glassFooterView.cornerRadius = CGFLOAT_MAX;

        self.footerContainerView.subviews = @[glassFooterView];
        self.footerContainerView.clipsToBounds = NO;
        [glassFooterView applyConstraintsToFillSuperview];

        self.buttonStack.edgeInsets = NSEdgeInsetsMake(
            VLCUIUnits.mediumSpacing,
            VLCUIUnits.largeSpacing,
            VLCUIUnits.mediumSpacing,
            VLCUIUnits.largeSpacing
        );

        self.scrollViewDefaultBottomConstraint.active = NO;
        self.footerContainerViewDefaultBottomConstraint.active = NO;
        self.footerContainerViewLeadingConstraint.constant = VLCUIUnits.largeSpacing;
        self.footerContainerViewTrailingConstraint.constant = VLCUIUnits.largeSpacing;

        NSLayoutConstraint * const footerBottomConstraint =
            [self.buttonStack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor
                                                          constant:-VLCUIUnits.largeSpacing];

        const CGFloat footerTopLine = footerHeight + -footerBottomConstraint.constant + VLCUIUnits.smallSpacing;

        [NSLayoutConstraint activateConstraints:@[
            [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
            [self.dragDropView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor
                                                           constant:-footerTopLine],
            footerBottomConstraint
        ]];

        self.scrollView.automaticallyAdjustsContentInsets = NO;
        self.scrollView.contentInsets = NSEdgeInsetsMake(0, 0, footerTopLine, 0);
    } else 
#endif
    if (@available(macOS 10.14, *)) {
        NSVisualEffectView * const footerBlurView = [[NSVisualEffectView alloc] initWithFrame:self.footerContainerView.bounds];
        footerBlurView.translatesAutoresizingMaskIntoConstraints = NO;
        footerBlurView.material = NSVisualEffectMaterialHeaderView;
        footerBlurView.blendingMode = NSVisualEffectBlendingModeWithinWindow;

        NSMutableArray<NSLayoutConstraint *> * const constraintsToDeactivate = [NSMutableArray array];
        for (NSLayoutConstraint * const constraint in self.footerContainerView.constraints) {
            if (constraint.firstItem == self.buttonStack || constraint.secondItem == self.buttonStack) {
                [constraintsToDeactivate addObject:constraint];
            }
        }
        [NSLayoutConstraint deactivateConstraints:constraintsToDeactivate];

        [self.footerContainerView addSubview:footerBlurView];
        [footerBlurView applyConstraintsToFillSuperview];
        [footerBlurView addSubview:self.buttonStack];
        [self.buttonStack applyConstraintsToFillSuperview];

        self.buttonStack.edgeInsets = NSEdgeInsetsMake(
            VLCUIUnits.mediumSpacing,
            VLCUIUnits.largeSpacing,
            VLCUIUnits.mediumSpacing,
            VLCUIUnits.largeSpacing
        );

        self.scrollViewDefaultBottomConstraint.active = NO;

        [NSLayoutConstraint activateConstraints:@[
            [self.scrollView.bottomAnchor constraintEqualToAnchor:self.footerContainerView.bottomAnchor]
        ]];

        self.scrollView.automaticallyAdjustsContentInsets = NO;
        self.scrollView.contentInsets = NSEdgeInsetsMake(0, 0, footerHeight, 0);
    }
}

- (NSString *)title
{
    // Figma node 6320:13763 labels the existing play queue tab "Queue".
    return _NS("Queue");
}

- (BOOL)supportsItemCount
{
    return YES;
}

- (void)setCounterLabel:(NSTextField *)counterLabel
{
    _counterLabel = counterLabel;
    self.dataSource.counterTextField = counterLabel;
}

#pragma mark - appearance setters

- (void)updateColorsBasedOnAppearance:(NSAppearance *)appearance
{
    [super updateColorsBasedOnAppearance:appearance];

    const BOOL isDark = appearance.shouldShowDarkAppearance;

    // If we try to pull the view's effectiveAppearance we are going to get the previous 
    // appearance's name despite responding to the effectiveAppearance change (???) so it is a
    // better idea to pull from the general system theme preference, which is always up-to-date
    if (isDark) {
        self.bottomButtonsSeparator.borderColor = NSColor.VLClibrarySeparatorDarkColor;
    } else {
        self.bottomButtonsSeparator.borderColor = NSColor.VLClibrarySeparatorLightColor;
    }
    // Resolve concrete layer colors after the view inherits the new app
    // appearance, including System; original separator updates remain intact.
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (weakSelf.isViewLoaded) [weakSelf.view vlc_applyRedesignStyle];
    });
}

#pragma mark - table view interaction

- (IBAction)tableDoubleClickAction:(id)sender
{
    const NSInteger selectedRow = self.tableView.selectedRow;
    if (selectedRow == -1) {
        return;
    }
    NSUInteger index=[self.dataSource modelIndexForVisibleRow:selectedRow];
    if(index!=NSNotFound)[VLCMain.sharedInstance.playQueueController playItemAtIndex:index];
}

#pragma mark - open media handling

- (IBAction)openMedia:(id)sender
{
    [VLCMain.sharedInstance.open openFileGeneric];
}

#pragma mark - playmode state display and interaction

- (IBAction)shuffleAction:(id)sender
{
    if (_playQueueController.playbackOrder == VLC_PLAYLIST_PLAYBACK_ORDER_NORMAL) {
        _playQueueController.playbackOrder = VLC_PLAYLIST_PLAYBACK_ORDER_RANDOM;
    } else {
        _playQueueController.playbackOrder = VLC_PLAYLIST_PLAYBACK_ORDER_NORMAL;
    }
}

- (void)shuffleStateUpdated:(NSNotification *)aNotification
{
    NSImage *exported=[NSImage vlc_redesignImageNamed:@"queue-shuffle"];
    if(exported) {
        BOOL active=self.playQueueController.playbackOrder!=VLC_PLAYLIST_PLAYBACK_ORDER_NORMAL;
        self.shuffleButton.image=exported;
        if(@available(macOS 10.14,*))self.shuffleButton.contentTintColor=active ? NSColor.VLCAccentColor : NSColor.VLCControlForegroundColor;
        else if(active)self.shuffleButton.image=[exported imageTintedWithColor:NSColor.VLCAccentColor];
        return;
    }
    if (@available(macOS 11.0, *)) {
        self.shuffleButton.image = [NSImage imageWithSystemSymbolName:@"shuffle"
                                             accessibilityDescription:@"Shuffle"];
        self.shuffleButton.contentTintColor =
            self.playQueueController.playbackOrder == VLC_PLAYLIST_PLAYBACK_ORDER_NORMAL ?
                nil : NSColor.VLCAccentColor;
    } else {
        self.shuffleButton.image =
            self.playQueueController.playbackOrder == VLC_PLAYLIST_PLAYBACK_ORDER_NORMAL ?
                NSImage.VLCShuffleOffImage :
                [NSImage.VLCShuffleOnImage imageTintedWithColor:NSColor.VLCAccentColor];
    }
}

- (IBAction)repeatAction:(id)sender
{
    const enum vlc_playlist_playback_repeat repeatState = self.playQueueController.playbackRepeat;
    switch (repeatState) {
        case VLC_PLAYLIST_PLAYBACK_REPEAT_ALL:
            self.playQueueController.playbackRepeat = VLC_PLAYLIST_PLAYBACK_REPEAT_NONE;
            break;
        case VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT:
            self.playQueueController.playbackRepeat = VLC_PLAYLIST_PLAYBACK_REPEAT_ALL;
            break;
        default:
            self.playQueueController.playbackRepeat = VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT;
            break;
    }
}

- (void)repeatStateUpdated:(NSNotification *)aNotification
{
    const enum vlc_playlist_playback_repeat repeatState = self.playQueueController.playbackRepeat;
    NSImage *exported=[NSImage vlc_redesignImageNamed:@"queue-repeat"];
    if(exported && repeatState!=VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT) {
        self.repeatButton.image=exported;
        if(@available(macOS 10.14,*))self.repeatButton.contentTintColor=repeatState==VLC_PLAYLIST_PLAYBACK_REPEAT_ALL ? NSColor.VLCAccentColor : NSColor.VLCControlForegroundColor;
        else if(repeatState==VLC_PLAYLIST_PLAYBACK_REPEAT_ALL)self.repeatButton.image=[exported imageTintedWithColor:NSColor.VLCAccentColor];
        return;
    }

    if (@available(macOS 11.0, *)) {
        switch (repeatState) {
            case VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT:
                self.repeatButton.image = [NSImage imageWithSystemSymbolName:@"repeat.1"
                                                    accessibilityDescription:@"Repeat current"];
                self.repeatButton.contentTintColor = NSColor.VLCAccentColor;
                break;
            case VLC_PLAYLIST_PLAYBACK_REPEAT_ALL:
                self.repeatButton.image = [NSImage imageWithSystemSymbolName:@"repeat"
                                                    accessibilityDescription:@"Repeat"];
                self.repeatButton.contentTintColor = NSColor.VLCAccentColor;
                break;
            default:
                self.repeatButton.image = [NSImage imageWithSystemSymbolName:@"repeat"
                                                    accessibilityDescription:@"Repeat"];
                self.repeatButton.contentTintColor = nil;
                break;
        }
    } else {
        switch (repeatState) {
            case VLC_PLAYLIST_PLAYBACK_REPEAT_ALL:
                self.repeatButton.image =
                    [NSImage.VLCRepeatAllImage imageTintedWithColor:NSColor.VLCAccentColor];
                break;
            case VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT:
                self.repeatButton.image =
                    [NSImage.VLCRepeatOneImage imageTintedWithColor:NSColor.VLCAccentColor];
                break;
            default:
                self.repeatButton.image = NSImage.VLCRepeatOffImage;
                break;
        }
    }
}

- (IBAction)sortPlayQueue:(id)sender
{
    if (!self.sortingMenuController) {
        _sortingMenuController = [[VLCPlayQueueSortingMenuController alloc] init];
    }
    [NSMenu popUpContextMenu:self.sortingMenuController.playQueueSortingMenu
                   withEvent:NSApp.currentEvent
                     forView:sender];
}

- (IBAction)clearPlayQueue:(id)sender
{
    [self.playQueueController clearPlayQueue];
}

@end
