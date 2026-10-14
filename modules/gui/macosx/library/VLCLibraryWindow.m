/*****************************************************************************
 * VLCLibraryWindow.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2019 VLC authors and VideoLAN
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan -dot- org>
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

#import "VLCLibraryWindow.h"

#import <vlc_common.h>
#import <vlc_configuration.h>
#import <vlc_media_library.h>
#import <vlc_url.h>

#import "VLCLibraryDataTypes.h"

#import "extensions/NSAnimationContext+VLCAdditions.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSWindow+VLCAdditions.h"

#import "library/VLCInputItem.h"
#import "library/VLCLibraryAbstractMediaLibrarySegmentViewController.h"
#import "library/VLCLibraryCollectionViewSupplementaryElementView.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryNavigationData.h"
#import "library/VLCLibraryDynamicToolbarFlagsCapable.h"
#import "library/VLCLibraryDynamicViewModeCapable.h"
#import "library/VLCLibraryModel.h"
#import "library/VLCLibrarySegment.h"
#import "library/VLCLibrarySortingMenuController.h"
#import "library/VLCLibraryWindowChaptersSidebarViewController.h"
#import "library/VLCLibraryWindowNavigationSidebarViewController.h"
#import "library/VLCLibraryWindowPersistentPreferences.h"
#import "library/VLCLibraryWindowSidebarRootViewController.h"
#import "library/VLCLibraryWindowSplitViewController.h"
#import "library/VLCLibraryWindowToolbarDelegate.h"

#import "library/audio-library/VLCLibraryAlbumTableCellView.h"
#import "library/audio-library/VLCLibraryAudioDataSource.h"
#import "library/audio-library/VLCLibraryAudioViewController.h"

#import "library/groups-library/VLCLibraryGroupsViewController.h"

#import "library/home-library/VLCLibraryHomeViewController.h"

#import "library/playlist-library/VLCLibraryPlaylistViewController.h"

#import "library/video-library/VLCLibraryVideoDataSource.h"
#import "library/video-library/VLCLibraryVideoViewController.h"

#import "main/VLCApplication.h"
#import "main/VLCMain.h"

#import "media-source/VLCLibraryMediaSourceViewController.h"
#import "media-source/VLCLibraryMediaSourceViewNavigationStack.h"
#import "media-source/VLCMediaSourceBaseDataSource.h"

#import "menus/VLCMainMenu.h"

#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayQueueModel.h"

#import "views/VLCBottomBarView.h"
#import "views/VLCDragDropView.h"
#import "views/VLCImageView.h"
#import "views/VLCLoadingOverlayView.h"
#import "views/VLCNoResultsLabel.h"
#import "views/VLCPlaybackEndViewController.h"
#import "views/VLCRoundedCornerTextField.h"
#import "views/VLCTrackingView.h"
#import "views/VLCUIUnits.h"

#import "windows/VLCDetachedAudioWindow.h"
#import "windows/VLCOpenInputMetadata.h"
#import "windows/VLCOpenWindowController.h"

#ifdef ENABLE_MACOSX_UI_SHADERS
# import "views/VLCSnowEffectView.h"
#endif

#import "windows/controlsbar/VLCMainWindowControlsBar.h"

#import "windows/video/VLCMainVideoViewController.h"
#import "windows/video/VLCVideoOutputProvider.h"
#import "windows/video/VLCVoutView.h"

const NSUInteger VLCLibrarySearchMaxMatchingTitles = 5;
const CGFloat VLCLibraryWindowMinimalWidth = 604.;
const CGFloat VLCLibraryWindowMinimalHeight = 307.;
const NSUserInterfaceItemIdentifier VLCLibraryWindowIdentifier = @"VLCLibraryWindow";
NSString * const VLCLibraryWindowEmbeddedVideoPlaybackActiveKey = @"embeddedVideoPlaybackActive";

@interface VLCLibraryWindow () <NSControlTextEditingDelegate>
{
    NSInteger _currentSelectedViewModeSegment;
    VLCVideoWindowCommon *_temporaryAudioDecorativeWindow;
    NSView *_acquiredVideoView;
}

@property NSTimer *searchInputTimer;
@property NSMutableArray<NSDictionary *> *libraryNavigationStates;
@property NSInteger libraryNavigationIndex;
@property BOOL restoringLibraryNavigation;
@property NSUInteger libraryNavigationMutationDepth;
@property id<VLCMediaLibraryItemProtocol> navigationLibraryItem;
@property NSURL *navigationFolder;

@end

static int ShowFullscreenController(vlc_object_t * __unused p_this,
                                    const char * __unused psz_variable,
                                    vlc_value_t __unused old_val,
                                    vlc_value_t __unused new_val,
                                    void * __unused param)
{
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:VLCVideoWindowShouldShowFullscreenController
                                                                object:nil];
        });

        return VLC_SUCCESS;
    }
}

static int ShowController(vlc_object_t * __unused p_this,
                          const char * __unused psz_variable,
                          vlc_value_t __unused old_val,
                          vlc_value_t __unused new_val,
                          void * __unused param)
{
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:VLCWindowShouldShowController
                                                                object:nil];
        });

        return VLC_SUCCESS;
    }
}

@interface VLCLibraryWindow ()

@property BOOL presentLoadingOverlayOnVideoPlaybackHide;

@end

@implementation VLCLibraryWindow

- (void)awakeFromNib
{
    [super awakeFromNib];
    self.identifier = VLCLibraryWindowIdentifier;
    self.minSize = NSMakeSize(VLCLibraryWindowMinimalWidth, VLCLibraryWindowMinimalHeight);

    self.tabbingMode = NSWindowTabbingModeDisallowed;

    VLCMain *mainInstance = VLCMain.sharedInstance;
    _playQueueController = [mainInstance playQueueController];

    // The redesigned library uses ordinary views for its header and background.
    // Accept file drops there as well as in the existing video and Queue targets.
    [self registerForDraggedTypes:@[
        VLCMediaLibraryMediaItemPasteboardType,
        VLCMediaLibraryMediaItemUTI,
        NSPasteboardTypeURL,
        NSPasteboardTypeFileURL,
        NSPasteboardTypeString,
        NSFilenamesPboardType
    ]];

    libvlc_int_t *libvlc = vlc_object_instance(getIntf());
    var_AddCallback(libvlc, "intf-toggle-fscontrol", ShowFullscreenController, (__bridge void *)self);
    var_AddCallback(libvlc, "intf-show", ShowController, (__bridge void *)self);

    _libraryTargetView = [[NSView alloc] init];
    _libraryNavigationStates = [NSMutableArray array];
    _libraryNavigationIndex = -1;

    self.videoViewController.view.frame = self.mainSplitView.frame;
    self.videoViewController.view.hidden = YES;
    self.videoViewController.displayLibraryControls = YES;
    [self hideControlsBarImmediately];

    NSNotificationCenter *notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(shouldShowController:)
                               name:VLCWindowShouldShowController
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(playerStateChanged:)
                               name:VLCPlayerCurrentMediaItemChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(playerCurrentMediaItemChanged:)
                               name:VLCPlayerCurrentMediaItemChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(playerStateChanged:)
                               name:VLCPlayerStateChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(playerTrackSelectionChanged:)
                               name:VLCPlayerTrackSelectionChanged
                             object:nil];

    [self setViewForSelectedSegment];
    [self recordLibraryNavigation];
    [self setupLoadingOverlayView];

    self.librarySearchField.delegate = self;
}

- (void)dealloc
{
    [self unregisterDraggedTypes];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    libvlc_int_t *libvlc = vlc_object_instance(getIntf());
    var_DelCallback(libvlc, "intf-toggle-fscontrol", ShowFullscreenController, (__bridge void *)self);
    var_DelCallback(libvlc, "intf-show", ShowController, (__bridge void *)self);
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
    [coder encodeInteger:_librarySegmentType forKey:@"macosx-library-selected-segment"];
}

- (void)setupLoadingOverlayView
{
    _loadingOverlayView = [[VLCLoadingOverlayView alloc] init];
    self.loadingOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
}

#pragma mark - misc. user interactions

- (void)updateGridVsListViewModeSegmentedControl
{
    _currentSelectedViewModeSegment = [self currentViewMode];
    _gridVsListSegmentedControl.selectedSegment = _currentSelectedViewModeSegment;
}

- (NSInteger)currentViewMode
{
    if ([self.librarySegmentViewController conformsToProtocol:@protocol(VLCLibraryDynamicViewModeCapable)]) {
        id<VLCLibraryDynamicViewModeCapable> const capableViewController =
            (id<VLCLibraryDynamicViewModeCapable>)self.librarySegmentViewController;
        return capableViewController.viewMode;
    }
    return [VLCLibrarySegment segmentWithSegmentType:self.librarySegmentType].viewMode;
}

- (void)setCurrentViewMode:(NSInteger)viewMode
{
    if ([self.librarySegmentViewController conformsToProtocol:@protocol(VLCLibraryDynamicViewModeCapable)]) {
        id<VLCLibraryDynamicViewModeCapable> const capableViewController =
            (id<VLCLibraryDynamicViewModeCapable>)self.librarySegmentViewController;
        capableViewController.viewMode = (VLCLibraryViewModeSegment)viewMode;
    } else {
        [VLCLibrarySegment segmentWithSegmentType:self.librarySegmentType].viewMode = viewMode;
    }
}

- (void)updateToolbarDisplayFlags
{
    NSParameterAssert([self.librarySegmentViewController conformsToProtocol:@protocol(VLCLibraryDynamicToolbarFlagsCapable)]);
    id<VLCLibraryDynamicToolbarFlagsCapable> const capableViewController =
        (id<VLCLibraryDynamicToolbarFlagsCapable>)self.librarySegmentViewController;
    [self.toolbarDelegate applyVisiblityFlags:capableViewController.toolbarDisplayFlags];
}

- (void)applyToolbarDisplayFlagsForSegment:(VLCLibrarySegment *)segment
{
    VLCLibraryWindowToolbarDisplayFlags flags;
    if ([self.librarySegmentViewController conformsToProtocol:@protocol(VLCLibraryDynamicToolbarFlagsCapable)]) {
        id<VLCLibraryDynamicToolbarFlagsCapable> const capableViewController =
            (id<VLCLibraryDynamicToolbarFlagsCapable>)self.librarySegmentViewController;
        flags = capableViewController.toolbarDisplayFlags;
    } else {
        flags = segment.toolbarDisplayFlags;
    }
    [self.toolbarDelegate applyVisiblityFlags:flags];
    [self updateLibraryNavigationControls];
}

- (void)setViewForSelectedSegment
{
    const VLCLibrarySegmentType segmentType = self.librarySegmentType;
    VLCLibrarySegment * const segment = [VLCLibrarySegment segmentWithSegmentType:segmentType];
    [self applySegmentView:segment];
}

- (void)applySegmentView:(VLCLibrarySegment *)segment
{
    self.librarySearchField.placeholderString = segment.searchFieldPlaceholder;
    if (![self.librarySegmentViewController isKindOfClass:segment.libraryViewControllerClass]) {
        _librarySegmentViewController = [segment newLibraryViewController];
    }
    [self applyToolbarDisplayFlagsForSegment:segment];
    [segment presentLibraryViewUsingController:self.librarySegmentViewController];
    [self invalidateRestorableState];
}

- (void)setLibrarySegmentType:(NSInteger)segmentType
{
    if (segmentType == _librarySegmentType) {
        return;
    }

    _librarySegmentType = segmentType;
    self.navigationLibraryItem = nil;
    self.navigationFolder = nil;
    [self setViewForSelectedSegment];
    [self updateGridVsListViewModeSegmentedControl];
    [self.splitViewController.navSidebarViewController synchronizeSelectedSegment:segmentType];
    [self recordLibraryNavigation];
}

- (void)recordLibraryNavigation
{
    if (self.libraryNavigationStates == nil || self.restoringLibraryNavigation || self.libraryNavigationMutationDepth > 0) return;
    NSDictionary *state = @{@"segment":@(self.librarySegmentType), @"item":(id)self.navigationLibraryItem ?: NSNull.null, @"folder":self.navigationFolder ?: NSNull.null};
    if (self.libraryNavigationIndex >= 0 && [self.libraryNavigationStates[self.libraryNavigationIndex] isEqual:state]) { [self updateLibraryNavigationControls]; return; }
    while (self.libraryNavigationStates.count > self.libraryNavigationIndex + 1) [self.libraryNavigationStates removeLastObject];
    [self.libraryNavigationStates addObject:state];
    self.libraryNavigationIndex = self.libraryNavigationStates.count - 1;
    [self updateLibraryNavigationControls];
}
- (void)restoreLibraryNavigation
{
    if (self.libraryNavigationIndex < 0 || self.libraryNavigationIndex >= self.libraryNavigationStates.count) return;
    NSDictionary *state = self.libraryNavigationStates[self.libraryNavigationIndex];
    self.restoringLibraryNavigation = YES;
    id item = state[@"item"] == NSNull.null ? nil : state[@"item"];
    NSURL *folder = state[@"folder"] == NSNull.null ? nil : state[@"folder"];
    BOOL sameSegment = self.librarySegmentType == [state[@"segment"] integerValue];
    self.librarySegmentType = [state[@"segment"] integerValue];
    if (item) [self presentLibraryItem:item]; else if (folder) [self browseFolderByMrl:folder.absoluteString];
    else {
        // Back from a collection to its category can retain the same segment.
        // Restore the category view as well as its selected navigation row.
        self.navigationLibraryItem = nil;
        self.navigationFolder = nil;
        if (sameSegment) {
            [self setViewForSelectedSegment];
            [self updateGridVsListViewModeSegmentedControl];
        }
        [self.splitViewController.navSidebarViewController selectSegment:self.librarySegmentType];
    }
    self.restoringLibraryNavigation = NO;
    [self updateLibraryNavigationControls];
}
- (void)updateLibraryNavigationControls
{
    BOOL backwards = self.libraryNavigationIndex > 0;
    BOOL forwards = self.libraryNavigationIndex >= 0 && self.libraryNavigationIndex + 1 < self.libraryNavigationStates.count;
    if ([self.librarySegmentViewController isKindOfClass:VLCLibraryMediaSourceViewController.class]) {
        VLCLibraryMediaSourceViewNavigationStack *stack = [(VLCLibraryMediaSourceViewController *)self.librarySegmentViewController navigationStack];
        backwards |= stack.backwardsAvailable; forwards |= stack.forwardsAvailable;
    }
    self.backwardsNavigationButton.enabled = backwards || self.embeddedVideoPlaybackActive;
    self.forwardsNavigationButton.enabled = forwards;
    if ([self.librarySegmentViewController isKindOfClass:VLCLibraryHomeViewController.class])
        [(VLCLibraryHomeViewController *)self.librarySegmentViewController updateNavigationControls];
    NSString *category = [VLCLibrarySegment segmentWithSegmentType:self.librarySegmentType].displayString ?: @"";
    NSString *selection = self.navigationFolder ? self.navigationFolder.lastPathComponent : self.navigationLibraryItem.displayString;
    NSString *title = selection.length ? [NSString stringWithFormat:@"%@ / %@", category, selection] : category;
    VLCLibraryModel *model = VLCMain.sharedInstance.libraryController.libraryModel;
    NSNumber *count = nil;
    if ([self.navigationLibraryItem isKindOfClass:VLCMediaLibraryPlaylist.class]) count = @([(VLCMediaLibraryPlaylist *)self.navigationLibraryItem numberOfMedia]);
    else if ([self.navigationLibraryItem conformsToProtocol:@protocol(VLCMediaLibraryAudioGroupProtocol)]) count = @([(id<VLCMediaLibraryAudioGroupProtocol>)self.navigationLibraryItem numberOfTracks]);
    else if ([self.navigationLibraryItem isKindOfClass:VLCMediaLibraryGroup.class]) count = @([(VLCMediaLibraryGroup *)self.navigationLibraryItem numberOfTotalItems]);
    else if (!self.navigationFolder && !self.navigationLibraryItem && model) {
        switch (self.librarySegmentType) {
            case VLCLibraryHomeSegmentType: count = @(model.numberOfVideoMedia + model.numberOfAudioMedia); break;
            case VLCLibraryVideoSegmentType: count = @(model.numberOfVideoMedia); break;
            case VLCLibraryMusicSegmentType: case VLCLibrarySongsMusicSubSegmentType: count = @(model.numberOfAudioMedia); break;
            case VLCLibraryArtistsMusicSubSegmentType: count = @(model.numberOfArtists); break;
            case VLCLibraryAlbumsMusicSubSegmentType: count = @(model.numberOfAlbums); break;
            case VLCLibraryGenresMusicSubSegmentType: count = @(model.numberOfGenres); break;
            case VLCLibraryGroupsSegmentType: count = @(model.numberOfGroups); break;
            case VLCLibraryPlaylistsSegmentType: count = @([model numberOfPlaylistsOfType:VLC_ML_PLAYLIST_TYPE_ALL]); break;
            case VLCLibraryPlaylistsMusicOnlyPlaylistsSubSegmentType: count = @([model numberOfPlaylistsOfType:VLC_ML_PLAYLIST_TYPE_AUDIO_ONLY]); break;
            case VLCLibraryPlaylistsVideoOnlyPlaylistsSubSegmentType: count = @([model numberOfPlaylistsOfType:VLC_ML_PLAYLIST_TYPE_VIDEO_ONLY]); break;
            case VLCLibraryRecentSegmentType: count = @(VLCMediaLibraryRecentItems(model).count); break;
            default: break;
        }
    }
    [self.toolbarDelegate updateLibraryHeaderWithTitle:title count:count];
}

- (IBAction)gridVsListSegmentedControlAction:(id)sender
{
    if (_gridVsListSegmentedControl.selectedSegment == _currentSelectedViewModeSegment) {
        return;
    }

    _currentSelectedViewModeSegment = _gridVsListSegmentedControl.selectedSegment;
    [self setCurrentViewMode:_currentSelectedViewModeSegment];
    [self setViewForSelectedSegment];
}

- (void)displayLibraryView:(NSView *)view
{
    view.translatesAutoresizingMaskIntoConstraints = NO;
    if ([self.libraryTargetView.subviews containsObject:self.loadingOverlayView]) {
        self.libraryTargetView.subviews = @[view, self.loadingOverlayView];
    } else {
        self.libraryTargetView.subviews = @[view];
    }

    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:self.libraryTargetView.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:self.libraryTargetView.bottomAnchor],
        [view.leftAnchor constraintEqualToAnchor:self.libraryTargetView.leftAnchor],
        [view.rightAnchor constraintEqualToAnchor:self.libraryTargetView.rightAnchor]
    ]];

#ifdef ENABLE_MACOSX_UI_SHADERS
    if (VLCMain.sharedInstance.metalLibrary && ((VLCApplication *)NSApplication.sharedApplication).winterHolidaysTheming) {
        VLCSnowEffectView * const snowView =
            [[VLCSnowEffectView alloc] initWithFrame:self.contentView.bounds];
        [self.libraryTargetView addSubview:snowView];
        snowView.translatesAutoresizingMaskIntoConstraints = NO;
        [snowView applyConstraintsToFillSuperview];
    }
#endif
}

- (void)displayLibraryPlaceholderViewWithImage:(NSImage *)image
                              usingConstraints:(NSArray<NSLayoutConstraint *> *)constraints
                             displayingMessage:(NSString *)message
{
    for (NSLayoutConstraint * const constraint in self.placeholderImageViewConstraints) {
        constraint.active = NO;
    }
    _placeholderImageViewConstraints = constraints;
    for (NSLayoutConstraint * const constraint in constraints) {
        constraint.active = YES;
    }

    [self displayLibraryView:self.emptyLibraryView];
    self.placeholderImageView.image = image;
    self.placeholderLabel.stringValue = message;
}

- (void)displayNoResultsMessage
{
    if (self.noResultsLabel == nil) {
        _noResultsLabel = [[VLCNoResultsLabel alloc] init];
        _noResultsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    }

    if ([self.libraryTargetView.subviews containsObject:self.loadingOverlayView]) {
        self.libraryTargetView.subviews = @[self.noResultsLabel, self.loadingOverlayView];
    } else {
        self.libraryTargetView.subviews = @[_noResultsLabel];
    }

    [NSLayoutConstraint activateConstraints:@[
        [self.noResultsLabel.centerXAnchor constraintEqualToAnchor:self.libraryTargetView.centerXAnchor],
        [self.noResultsLabel.centerYAnchor constraintEqualToAnchor:self.libraryTargetView.centerYAnchor]
    ]];
}

- (void)presentLibraryItem:(id<VLCMediaLibraryItemProtocol>)libraryItem
{
    VLCLibrarySegment * const segment = [VLCLibrarySegment segmentForLibraryItem:libraryItem];
    if (segment == nil) return;
    ++self.libraryNavigationMutationDepth;
    [self.splitViewController.navSidebarViewController selectSegment:segment.segmentType];
    if ([self.librarySegmentViewController conformsToProtocol:@protocol(VLCLibraryItemPresentingCapable)]) {
        [(VLCLibraryAbstractSegmentViewController<VLCLibraryItemPresentingCapable> *)self.librarySegmentViewController presentLibraryItem:libraryItem];
    }
    self.navigationLibraryItem = libraryItem;
    self.navigationFolder = nil;
    --self.libraryNavigationMutationDepth;
    [self recordLibraryNavigation];
    if (!self.restoringLibraryNavigation) [VLCLibraryNavigationData.sharedInstance recordVisitToItem:libraryItem];
}

- (void)browseFolderByMrl:(NSString *)mrl
{
    ++self.libraryNavigationMutationDepth;
    [self goToBrowseSection:self];
    [(VLCLibraryMediaSourceViewController *)self.librarySegmentViewController browseFolderByMrl:mrl];
    self.navigationFolder = [NSURL URLWithString:mrl]; self.navigationLibraryItem = nil;
    --self.libraryNavigationMutationDepth;
    [self recordLibraryNavigation];
    if (!self.restoringLibraryNavigation && self.navigationFolder) [VLCLibraryNavigationData.sharedInstance recordVisitToItem:self.navigationFolder];
}

- (IBAction)sortLibrary:(id)sender
{
    if (!_librarySortingMenuController) {
        _librarySortingMenuController = [[VLCLibrarySortingMenuController alloc] init];
    }
    [NSMenu popUpContextMenu:_librarySortingMenuController.librarySortingMenu withEvent:[NSApp currentEvent] forView:sender];
}

- (void)stopSearchTimer
{
    [self.searchInputTimer invalidate];
    self.searchInputTimer = nil;
}

- (IBAction)filterLibrary:(id)sender
{
    [self stopSearchTimer];
    self.searchInputTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                            target:self
                                                           selector:@selector(updateFilterString)
                                                           userInfo:nil
                                                            repeats:NO];

    if (self.librarySegmentType == VLCLibraryHomeSegmentType) {
        return;
    }

    // Trigger completions
    NSText * const fieldEditor = self.librarySearchField.currentEditor;
    if (fieldEditor) {
        [fieldEditor complete:sender];
    }
}

- (void)updateFilterString
{
    if (self.librarySegmentType == VLCLibraryHomeSegmentType) {
        return;
    }

    [VLCMain.sharedInstance.libraryController filterByString:_librarySearchField.stringValue];
}

- (void)clearFilterString
{
    [self stopSearchTimer];
    _librarySearchField.stringValue = @"";
    [self updateFilterString];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    VLCMain *owner = VLCMain.sharedInstance;
    if (owner == nil || owner.isTerminating) return NSDragOperationNone;
    NSDragOperation mask = sender.draggingSourceOperationMask;
    return (mask & (NSDragOperationCopy | NSDragOperationGeneric)) ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender
{
    VLCMain *owner = VLCMain.sharedInstance;
    return owner != nil && !owner.isTerminating && sender.draggingPasteboard != nil;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    return [self handlePasteBoardFromDragSession:sender.draggingPasteboard];
}

- (BOOL)handlePasteBoardFromDragSession:(NSPasteboard *)paste
{
    VLCMain *owner = VLCMain.sharedInstance;
    if (owner == nil || owner.isTerminating || paste == nil) return NO;
    return [VLCFileDragRecognisingView handlePasteboardFromDragSessionAsPlayQueueItems:paste];
}

- (IBAction)goToBrowseSection:(id)sender
{
    [self.splitViewController.navSidebarViewController selectSegment:VLCLibraryBrowseSegmentType];
}

- (IBAction)backwardsNavigationAction:(id)sender
{
    if (self.embeddedVideoPlaybackActive) { [self disableVideoPlaybackAppearance]; return; }
    if ([self.librarySegmentViewController isKindOfClass:VLCLibraryMediaSourceViewController.class] && [(VLCLibraryMediaSourceViewController *)self.librarySegmentViewController navigationStack].backwardsAvailable)
        [[(VLCLibraryMediaSourceViewController *)self.librarySegmentViewController navigationStack] backwards];
    else if (self.libraryNavigationIndex > 0) { --self.libraryNavigationIndex; [self restoreLibraryNavigation]; }
}

- (IBAction)forwardsNavigationAction:(id)sender
{
    if ([self.librarySegmentViewController isKindOfClass:VLCLibraryMediaSourceViewController.class] && [(VLCLibraryMediaSourceViewController *)self.librarySegmentViewController navigationStack].forwardsAvailable)
        [[(VLCLibraryMediaSourceViewController *)self.librarySegmentViewController navigationStack] forwards];
    else if (self.libraryNavigationIndex + 1 < self.libraryNavigationStates.count) { ++self.libraryNavigationIndex; [self restoreLibraryNavigation]; }
}

#pragma mark - video output controlling

- (void)playerStateChanged:(NSNotification *)notification
{
    if (_playQueueController.playerController.playerState == VLC_PLAYER_STATE_STOPPED) {
        [self hideControlsBar];
        return;
    }

    if (!self.embeddedVideoPlaybackActive) {
        [self showControlsBar];
    }
}

- (void)playerCurrentMediaItemChanged:(NSNotification *)notification
{
    NSParameterAssert(notification);
    VLCPlayerController * const controller = notification.object;
    NSAssert(controller != nil,
             @"Player current media item changed notification should have valid player controller");

    // Live video playback in controls bar artwork button handling
    if (self.splitViewController.mainVideoModeEnabled) {
        return;
    }

    if (controller.currentMediaIsAudioOnly && _acquiredVideoView) {
        [self.videoViewController returnVideoView:_acquiredVideoView];
        _acquiredVideoView = nil;
    } else if (!controller.currentMediaIsAudioOnly && _acquiredVideoView == nil) {
        [self configureArtworkButtonLiveVideoView];
    }
}

- (void)playerTrackSelectionChanged:(NSNotification *)notification
{
    [self updateArtworkButtonEnabledState];
}

- (void)updateArtworkButtonEnabledState
{
    VLCPlayerController * const playerController = self.playerController;
    const BOOL videoTrackDisabled =
        !playerController.videoTracksEnabled || !playerController.selectedVideoTrack.selected;
    const BOOL audioTrackDisabled =
        !playerController.audioTracksEnabled || !playerController.selectedAudioTrack.selected;
    const BOOL currentItemIsAudio =
        playerController.videoTracks.count == 0 && playerController.audioTracks.count > 0;
    const BOOL pipOpen = self.videoViewController.pipIsActive;
    const BOOL artworkButtonDisabled =
        (videoTrackDisabled && audioTrackDisabled) ||
        (videoTrackDisabled && !currentItemIsAudio) ||
        pipOpen;
    self.artworkButton.enabled = !artworkButtonDisabled;
    self.artworkButton.hidden = artworkButtonDisabled;
    self.controlsBar.thumbnailTrackingView.enabled = !artworkButtonDisabled;
    for (NSView * const view in self.controlsBar.thumbnailTrackingView.viewsToHide) {
        view.hidden = artworkButtonDisabled;
    }
}

- (void)configureArtworkButtonLiveVideoView
{
    VLCPlayerController * const playerController = self.playerController;
    const BOOL videoTrackDisabled =
        !playerController.videoTracksEnabled || !playerController.selectedVideoTrack.selected;

    if (videoTrackDisabled || !var_InheritBool(getIntf(), "embedded-video"))
        return;

    _acquiredVideoView = [self.videoViewController acquireVideoView];
    if (_acquiredVideoView) {
        [self.controlsBar.artworkImageView addSubview:_acquiredVideoView
                                           positioned:NSWindowBelow
                                           relativeTo:self.artworkButton];
        [_acquiredVideoView applyConstraintsToFillSuperview];
    }
}

- (void)hideControlsBarImmediately
{
    self.controlsBar.bottomBarView.hidden = YES;
    self.controlsBar.bottomBarView.alphaValue = 0;
}

- (void)hideControlsBar
{
     [NSAnimationContext runAnimationRespectingPreferencesWithDuration:VLCUIUnits.controlsFadeAnimationDuration
                                                               changes:^(NSAnimationContext * const context) {
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.controlsBar.bottomBarView.animator.alphaValue = 0;
    } completionHandler:^{
        self.controlsBar.bottomBarView.hidden = self.controlsBar.bottomBarView.alphaValue == 0;
    }];
}

- (void)showControlsBarImmediately
{
    self.controlsBar.bottomBarView.hidden = NO;
    self.controlsBar.bottomBarView.alphaValue = 1;
}

- (void)showControlsBar
{
    self.controlsBar.bottomBarView.hidden = NO;

    [NSAnimationContext runAnimationRespectingPreferencesWithDuration:VLCUIUnits.controlsFadeAnimationDuration
                                                              changes:^(NSAnimationContext * const __unused context) {
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        self.controlsBar.bottomBarView.animator.alphaValue = 1;
    } completionHandler:nil];
}

- (BOOL)shouldShowControlsBarForPlaybackContext
{
    VLCPlayerController * const playerController = self.playQueueController.playerController;
    return playerController.playerState != VLC_PLAYER_STATE_STOPPED &&
           self.playQueueController.playQueueModel.numberOfPlayQueueItems > 0;
}

- (void)presentExternalWindows
{
    VLCVideoOutputProvider * const voutProvider = VLCMain.sharedInstance.voutProvider;
    NSArray<NSWindow *> * const voutWindows = voutProvider.voutWindows.allValues;

    if (voutWindows.count == 0 && self.playerController.videoTracks.count == 0) {
        // If we have no video windows in the video provider but are being asked to present a window
        // then we are dealing with an audio item and the user wants to see the decorative artwork
        // window for said audio
        [VLCMain.sharedInstance.detachedAudioWindow makeKeyAndOrderFront:self];
        return;
    }

    for (NSWindow * const window in voutWindows) {
        [window makeKeyAndOrderFront:self];
    }
}

- (void)presentVideoView
{
    for (NSView *subview in _libraryTargetView.subviews) {
        [subview removeFromSuperview];
    }

    NSLog(@"Presenting video view in main library window.");

    NSView * const videoView = self.videoViewController.view;
    videoView.translatesAutoresizingMaskIntoConstraints = NO;
    videoView.hidden = NO;
    // The library rail can temporarily leave less space than the player's window minimum.
    // Prepare the existing controls before mounting their required layout constraints.
    [self.videoViewController prepareControlsForWidth:NSWidth(_libraryTargetView.bounds)];

    [_libraryTargetView addSubview:videoView];
    [videoView applyConstraintsToFillSuperview];
}

- (void)enableVideoPlaybackAppearance
{
    VLCPlayerController * const playerController = self.playerController;
    const BOOL videoTrackDisabled =
        !playerController.videoTracksEnabled || !playerController.selectedVideoTrack.selected;
    const BOOL audioTrackDisabled =
        !playerController.audioTracksEnabled || !playerController.selectedAudioTrack.selected;
    const BOOL currentItemIsAudio =
        playerController.videoTracks.count == 0 && playerController.audioTracks.count > 0;
    if ((videoTrackDisabled && audioTrackDisabled) || (videoTrackDisabled && !currentItemIsAudio)) {
        return;
    }

    const BOOL isEmbedded = var_InheritBool(getIntf(), "embedded-video");
    if (!isEmbedded) {
        [self presentExternalWindows];
        return;
    }

    // Preserve the GUI theme selected in onboarding or General when video is reattached.
    self.appearance = NSApp.appearance;

    if (_acquiredVideoView) {
        [self.videoViewController returnVideoView:_acquiredVideoView];
        _acquiredVideoView = nil;
    }

    [self presentVideoView];
    [self enableVideoTitleBarMode];
    [self hideControlsBarImmediately];
    [self.videoViewController showControls];

    self.splitViewController.mainVideoModeEnabled = YES;

    [self willChangeValueForKey:VLCLibraryWindowEmbeddedVideoPlaybackActiveKey];
    _embeddedVideoPlaybackActive = YES;
    [self didChangeValueForKey:VLCLibraryWindowEmbeddedVideoPlaybackActiveKey];

    if ([self.librarySegmentViewController isKindOfClass:VLCLibraryAbstractMediaLibrarySegmentViewController.class]) {
        [(VLCLibraryAbstractMediaLibrarySegmentViewController *)self.librarySegmentViewController disconnect];
    }
}

- (void)disableVideoPlaybackAppearance
{
    self.appearance = nil;

    [self makeFirstResponder:self.splitViewController.multifunctionSidebarViewController.view];
    [VLCMain.sharedInstance.voutProvider updateWindowLevelForHelperWindows:NSNormalWindowLevel];

    // restore alpha value to 1 for the case that macosx-opaqueness is set to < 1
    self.alphaValue = 1.0;
    [self disableVideoTitleBarMode];
    [self setViewForSelectedSegment];
    if ([self shouldShowControlsBarForPlaybackContext]) {
        [self showControlsBarImmediately];
    } else {
        [self hideControlsBarImmediately];
    }
    [self updateArtworkButtonEnabledState];

    if (!self.playQueueController.playerController.currentMediaIsAudioOnly) {
        [self configureArtworkButtonLiveVideoView];
    }

    self.splitViewController.mainVideoModeEnabled = NO;

    [self willChangeValueForKey:VLCLibraryWindowEmbeddedVideoPlaybackActiveKey];
    _embeddedVideoPlaybackActive = NO;
    [self didChangeValueForKey:VLCLibraryWindowEmbeddedVideoPlaybackActiveKey];

    if (self.presentLoadingOverlayOnVideoPlaybackHide) {
        [self showLoadingOverlay];
    }

    if ([self.librarySegmentViewController isKindOfClass:VLCLibraryAbstractMediaLibrarySegmentViewController.class]) {
        [(VLCLibraryAbstractMediaLibrarySegmentViewController *)self.librarySegmentViewController connect];
    }
}

- (void)showLoadingOverlay
{
    if ([self.libraryTargetView.subviews containsObject:self.loadingOverlayView]) {
        return;
    } else if ([self.libraryTargetView.subviews containsObject:self.videoViewController.view]) {
        self.presentLoadingOverlayOnVideoPlaybackHide = YES;
        return;
    }

    self.loadingOverlayView.wantsLayer = YES;
    self.loadingOverlayView.alphaValue = 0.0;

    NSArray * const views = [self.libraryTargetView.subviews arrayByAddingObject:self.loadingOverlayView];
    self.libraryTargetView.subviews = views;
    [self.loadingOverlayView applyConstraintsToFillSuperview];

    [NSAnimationContext runAnimationRespectingPreferencesWithDuration:0.5
                                                              changes:^(NSAnimationContext * const __unused context) {
        self.loadingOverlayView.animator.alphaValue = 1.0;
    } completionHandler:nil];

    [self.loadingOverlayView.indicator startAnimation:self];

}

- (void)hideLoadingOverlay
{
    self.presentLoadingOverlayOnVideoPlaybackHide = NO;

    if (![self.libraryTargetView.subviews containsObject:self.loadingOverlayView]) {
        return;
    }

    self.loadingOverlayView.wantsLayer = YES;
    self.loadingOverlayView.alphaValue = 1.0;

    [NSAnimationContext runAnimationRespectingPreferencesWithDuration:1.0
                                                              changes:^(NSAnimationContext * const __unused context) {
        self.loadingOverlayView.animator.alphaValue = 0.0;
    } completionHandler:^{
        NSMutableArray * const mutableSubviews = self.libraryTargetView.subviews.mutableCopy;
        [mutableSubviews removeObject:self.loadingOverlayView];
        self.libraryTargetView.subviews = mutableSubviews;
        [self.loadingOverlayView.indicator stopAnimation:self];
    }];
}

- (void)mouseMoved:(NSEvent *)o_event
{
    if (self.embeddedVideoPlaybackActive) {
        NSPoint mouseLocation = [o_event locationInWindow];
        NSView *videoView = self.videoViewController.view;
        NSRect videoViewRect = [videoView convertRect:videoView.frame toView:self.contentView];

        if ([self.contentView mouse:mouseLocation inRect:videoViewRect]) {
            [NSNotificationCenter.defaultCenter postNotificationName:VLCVideoWindowShouldShowFullscreenController
                                                                object:self];
        }
    }

    [super mouseMoved:o_event];
}

#pragma mark - NSControlTextEditingDelegate

- (NSArray<NSString *> *)control:(NSControl *)control
                         textView:(NSTextView *)textView
                      completions:(NSArray<NSString *> *)words
              forPartialWordRange:(NSRange)charRange
              indexOfSelectedItem:(NSInteger *)index
{
    // Get the partial word being completed
    NSString * const currentText = textView.string;
    NSString * const partialWord = [currentText substringWithRange:charRange];

    if (partialWord.length == 0) {
        return @[];
    }

    // Get cached titles from library model
    VLCLibraryModel * const libraryModel = VLCMain.sharedInstance.libraryController.libraryModel;
    if (!libraryModel) {
        return @[];
    }

    NSArray<NSString *> * const allTitles = libraryModel.listOfMediaTitles;
    NSMutableArray<NSString *> * const matchingTitles = [NSMutableArray arrayWithCapacity:VLCLibrarySearchMaxMatchingTitles];

    // Filter titles that match the partial word
    for (NSString * const title in allTitles) {
        if (![title.lowercaseString hasPrefix:partialWord.lowercaseString]) {
            continue;
        }
        [matchingTitles addObject:title];
        if (matchingTitles.count >= VLCLibrarySearchMaxMatchingTitles) {
            break;
        }
    }

    *index = -1;
    return matchingTitles;
}

#pragma mark -
#pragma mark respond to core events

- (void)shouldShowController:(NSNotification *)aNotification
{
    [self makeKeyAndOrderFront:nil];

    if (self.videoViewController.view.isHidden) {
        [self showControlsBar];
        NSView *standardWindowButtonsSuperView = [self standardWindowButton:NSWindowCloseButton].superview;
        standardWindowButtonsSuperView.hidden = NO;
    }
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    [super windowWillEnterFullScreen:notification];

    if (self.splitViewController.mainVideoModeEnabled) {
        [self hideControlsBar];
    }

    if (self.splitViewController.mainVideoModeEnabled) {
        self.splitViewController.multifunctionSidebarItem.animator.collapsed = YES;
    }
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    [super windowDidEnterFullScreen:notification];
    if (!self.splitViewController.mainVideoModeEnabled) {
        [self showControlsBar];
    }
}

@end
