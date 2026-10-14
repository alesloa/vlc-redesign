/*****************************************************************************
 * VLCLibraryWindowNavigationSidebarViewController.h: MacOS X interface module
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

#import "VLCLibraryWindowNavigationSidebarViewController.h"

#import "extensions/NSAnimationContext+VLCAdditions.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSWindow+VLCAdditions.h"

#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibraryModel.h"
#import "library/VLCLibraryNavigationData.h"
#import "library/VLCLibrarySegment.h"
#import "library/VLCLibrarySegmentBookmarkedLocation.h"
#import "library/VLCLibraryWindow.h"
#import "library/VLCLibraryWindowNavigationSidebarOutlineView.h"

#import "main/VLCMain.h"

#import "views/VLCStatusNotifierView.h"
#import "views/VLCUIUnits.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

// This needs to match whatever identifier has been set in the library window XIB
static NSString * const VLCLibrarySegmentCellIdentifier = @"VLCLibrarySegmentCellIdentifier";

@interface VLCLibraryWindowNavigationSidebarViewController ()

@property BOOL ignoreSegmentSelectionChanges;
@property (readonly) NSEdgeInsets scrollViewInsets;
@property (readonly) NSMutableDictionary<NSString *, dispatch_source_t> *observedPathDispatchSources;
@property NSMutableSet<NSString *> *pendingObservedPaths;
@property NSArray<NSDictionary *> *pinnedEntries;
@property NSUInteger pinsLoadGeneration;

@end

@implementation VLCLibraryWindowNavigationSidebarViewController

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    self = [super initWithNibName:@"VLCLibraryWindowNavigationSidebarView" bundle:nil];
    if (self) {
        _libraryWindow = libraryWindow;
        _segments = VLCLibrarySegment.librarySegments;
        _ignoreSegmentSelectionChanges = NO;
        _observedPathDispatchSources = NSMutableDictionary.dictionary;
        _pendingObservedPaths = NSMutableSet.set;
    }
    return self;
}

- (void)viewDidLoad
{
    _treeController = [[NSTreeController alloc] init];
    self.treeController.objectClass = VLCLibrarySegment.class;
    self.treeController.countKeyPath = @"childCount";
    self.treeController.childrenKeyPath = @"childNodes";
    self.treeController.leafKeyPath = @"leaf";

    // Full library reference 970:2703: 40px rows, 14px Inter and neutral surfaces.
    self.outlineView.rowSizeStyle = NSTableViewRowSizeStyleCustom;
    self.outlineView.rowHeight = 40;
    self.outlineView.indentationPerLevel = 14;
    self.outlineView.backgroundColor = NSColor.VLCWindowBackgroundColor;
    self.outlineViewScrollView.drawsBackground = NO;
    self.view.wantsLayer = YES;
    self.view.identifier = @"VLCRedesignedLibraryContent";
    self.view.layer.backgroundColor = NSColor.VLCWindowBackgroundColor.CGColor;
    self.view.layer.cornerRadius = 6;
    self.outlineView.allowsMultipleSelection = NO;
    self.outlineView.allowsEmptySelection = NO;
    self.outlineView.allowsColumnSelection = NO;
    self.outlineView.allowsColumnReordering = NO;

    if (@available(macOS 26.0, *)) {
        // The native glass sidebar already supplies its leading/bottom inset.
        // Match the owner's requested perimeter at the two remaining edges
        // without changing the split item's width or its original content.
        NSView *panel = self.view;
        NSView *perimeter = [[NSView alloc] initWithFrame:panel.frame];
        // The existing appearance pass resolves the same window background
        // for the perimeter and original inner library panel.
        perimeter.identifier = @"VLCRedesignedNavigationPerimeter";
        perimeter.autoresizingMask = panel.autoresizingMask;
        perimeter.wantsLayer = YES;
        perimeter.layer.backgroundColor = NSColor.VLCWindowBackgroundColor.CGColor;
        perimeter.layer.masksToBounds = YES;
        panel.translatesAutoresizingMaskIntoConstraints = NO;
        panel.layer.masksToBounds = YES;
        [perimeter addSubview:panel];
        CGFloat inset = VLCUIUnits.mediumSpacing;
        [NSLayoutConstraint activateConstraints:@[
            [panel.leadingAnchor constraintEqualToAnchor:perimeter.leadingAnchor],
            [panel.bottomAnchor constraintEqualToAnchor:perimeter.bottomAnchor],
            [panel.topAnchor constraintEqualToAnchor:perimeter.topAnchor constant:inset],
            [panel.trailingAnchor constraintEqualToAnchor:perimeter.trailingAnchor constant:-inset]
        ]];
        self.view = perimeter;
    }

    [self internalNodesChanged:nil];

    const NSEdgeInsets scrollViewInsets = self.outlineViewScrollView.contentInsets;
    _scrollViewInsets =
        NSEdgeInsetsMake(scrollViewInsets.top + VLCUIUnits.libraryWindowContentSafeTopInset,
                         scrollViewInsets.left,
                         scrollViewInsets.bottom,
                         scrollViewInsets.right);

    self.statusNotifierView.postsFrameChangedNotifications = YES;

    NSNotificationCenter * const defaultCenter = NSNotificationCenter.defaultCenter;
    [defaultCenter addObserver:self
                      selector:@selector(internalNodesChanged:)
                          name:VLCLibraryBookmarkedLocationsChanged
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(internalNodesChanged:)
                          name:VLCLibraryModelListOfGroupsReset
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(internalNodesChanged:)
                          name:VLCLibraryModelGroupUpdated
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(internalNodesChanged:)
                          name:VLCLibraryModelGroupDeleted
                        object:nil];
    [defaultCenter addObserver:self selector:@selector(internalNodesChanged:) name:VLCLibraryNavigationDataChanged object:nil];
    [defaultCenter addObserver:self selector:@selector(internalNodesChanged:) name:VLCLibraryModelPlaylistUpdated object:nil];
    [defaultCenter addObserver:self selector:@selector(internalNodesChanged:) name:VLCLibraryModelPlaylistDeleted object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(statusViewActivated:)
                          name:VLCStatusNotifierViewActivated
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(statusViewDeactivated:)
                          name:VLCStatusNotifierViewDeactivated
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(statusViewSizeChanged:)
                          name:NSViewFrameDidChangeNotification
                        object:nil];
}

- (void)internalNodesChanged:(NSNotification *)notification
{
    [self applySegmentsWithPins];
    NSUInteger generation = ++self.pinsLoadGeneration;
    __weak typeof(self) weakSelf = self;
    [VLCLibraryNavigationData.sharedInstance loadPinsWithCompletion:^(NSArray<NSDictionary *> *entries) {
        typeof(self) self = weakSelf;
        if (!self || self.pinsLoadGeneration != generation) return;
        self.pinnedEntries = entries;
        [self applySegmentsWithPins];
    }];
}

- (void)applySegmentsWithPins
{
    const VLCLibrarySegmentType currentSegmentType = self.libraryWindow.librarySegmentType;
    NSTreeNode *selectedNode = self.outlineView.selectedRow >= 0 ? [self.outlineView itemAtRow:self.outlineView.selectedRow] : nil;
    VLCLibrarySegment *selectedSegment = selectedNode.representedObject;
    NSString *selectedPin = [selectedSegment.representedObject isKindOfClass:NSDictionary.class] && selectedSegment.segmentType == currentSegmentType
        ? [(NSDictionary *)selectedSegment.representedObject objectForKey:@"serialized"] : nil;

    NSMutableSet<NSNumber *> * const expandedSegmentTypes = NSMutableSet.set;
    for (VLCLibrarySegment * const segment in self.treeController.content) {
        NSTreeNode * const node = [self nodeForSegmentType:segment.segmentType];
        if ([self.outlineView isItemExpanded:node]) {
            [expandedSegmentTypes addObject:@(segment.segmentType)];
        }
    }

    self.ignoreSegmentSelectionChanges = YES;

    NSMutableArray *segments = VLCLibrarySegment.librarySegments.mutableCopy;
    if (self.pinnedEntries.count && VLCMain.sharedInstance.libraryController.libraryModel != nil) {
        // Actual user pin order is retained; display values resolve from ML.
        NSUInteger position = MIN(6, segments.count);
        [segments insertObject:VLCLibrarySegment.pinsHeaderSegment atIndex:position++];
        for (NSDictionary *entry in self.pinnedEntries)
            [segments insertObject:[VLCLibrarySegment segmentForPinnedEntry:entry] atIndex:position++];
    }
    _segments = segments;
    [self.treeController bind:@"contentArray" toObject:self withKeyPath:@"segments" options:nil];
    [self.outlineView bind:@"content"
                  toObject:self.treeController
               withKeyPath:@"arrangedObjects"
                   options:nil];
    [self.outlineView reloadData];

    self.ignoreSegmentSelectionChanges = NO;

    [self updateBookmarkObservation];

    for (VLCLibrarySegment * const segment in self.treeController.content) {
        if ([expandedSegmentTypes containsObject:@(segment.segmentType)]) {
            NSTreeNode * const node = [self nodeForSegmentType:segment.segmentType];
            [self.outlineView expandItem:node];
        }
    }

    self.ignoreSegmentSelectionChanges = YES;
    [self selectSegment:currentSegmentType];
    if (selectedPin) {
        for (NSInteger row = 0; row < self.outlineView.numberOfRows; ++row) {
            NSTreeNode *node = [self.outlineView itemAtRow:row];
            VLCLibrarySegment *segment = node.representedObject;
            if ([segment.representedObject isKindOfClass:NSDictionary.class] &&
                [[(NSDictionary *)segment.representedObject objectForKey:@"serialized"] isEqualToString:selectedPin]) {
                [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; break;
            }
        }
    }
    self.ignoreSegmentSelectionChanges = NO;
}

- (void)updateBookmarkObservation
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray<NSString *> *bookmarkedLocations = [defaults stringArrayForKey:VLCLibraryBookmarkedLocationsKey] ?: @[];
    NSMutableArray *deleted = self.observedPathDispatchSources.allKeys.mutableCopy;
    [deleted removeObjectsInArray:bookmarkedLocations];
    for (NSString *location in deleted) {
        dispatch_source_cancel(self.observedPathDispatchSources[location]);
        [self.observedPathDispatchSources removeObjectForKey:location];
    }
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t globalQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    for (NSString *locationMrl in bookmarkedLocations) {
        if (self.observedPathDispatchSources[locationMrl] || [self.pendingObservedPaths containsObject:locationMrl]) continue;
        [self.pendingObservedPaths addObject:locationMrl];
        NSURL *locationUrl = [NSURL URLWithString:locationMrl];
        // Filesystem permission and unavailable-volume waits must not freeze the GUI.
        dispatch_async(globalQueue, ^{
            const int descriptor = open(locationUrl.path.UTF8String, O_EVTONLY);
            if (descriptor == -1) {
                dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf.pendingObservedPaths removeObject:locationMrl]; });
                return;
            }
            struct stat fileStat;
            const int statResult = fstat(descriptor, &fileStat);
            dispatch_source_t fileDispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, descriptor, DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME, globalQueue);
        dispatch_source_set_event_handler(fileDispatchSource, ^{
            const unsigned long eventFlags = dispatch_source_get_data(fileDispatchSource);
            if (eventFlags & DISPATCH_VNODE_RENAME && statResult != -1) {
                NSURL * const parentLocationUrl = locationUrl.URLByDeletingLastPathComponent;
                NSString * const parentLocationPath = parentLocationUrl.path;
                NSArray<NSString *> * const files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:parentLocationPath error:nil];
                NSString *newFileName = nil;

                for (NSString * const file in files) {
                    NSString * const fullChildPath = [parentLocationPath stringByAppendingPathComponent:file];
                    struct stat currentFileStat;
                    if (stat(fullChildPath.UTF8String, &currentFileStat) == -1) {
                        continue;
                    } else if (currentFileStat.st_ino == fileStat.st_ino) {
                        newFileName = fullChildPath.lastPathComponent;
                        break;
                    }
                }

                if (newFileName != nil) {
                    NSMutableArray<NSString *> * const mutableBookmarkedLocations = [defaults stringArrayForKey:VLCLibraryBookmarkedLocationsKey].mutableCopy;
                    const NSUInteger locationIndex = [mutableBookmarkedLocations indexOfObject:locationMrl];
                    NSString * const newLocationMrl = [parentLocationUrl URLByAppendingPathComponent:newFileName].absoluteString;
                    if (locationIndex != NSNotFound) {
                        [mutableBookmarkedLocations replaceObjectAtIndex:locationIndex withObject:newLocationMrl];
                        [defaults setObject:mutableBookmarkedLocations forKey:VLCLibraryBookmarkedLocationsKey];
                    }
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf internalNodesChanged:nil];
            });
        });
        dispatch_source_set_cancel_handler(fileDispatchSource, ^{
            close(descriptor);
        });

            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                [strongSelf.pendingObservedPaths removeObject:locationMrl];
                NSArray *current = [defaults stringArrayForKey:VLCLibraryBookmarkedLocationsKey];
                if (strongSelf == nil || ![current containsObject:locationMrl] || strongSelf.observedPathDispatchSources[locationMrl]) {
                    dispatch_source_cancel(fileDispatchSource);
                } else {
                    strongSelf.observedPathDispatchSources[locationMrl] = fileDispatchSource;
                }
                dispatch_resume(fileDispatchSource);
            });
        });
    }
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    for (dispatch_source_t source in self.observedPathDispatchSources.allValues) dispatch_source_cancel(source);
}

- (void)statusViewActivated:(NSNotification *)notification
{
    const CGFloat statusNotifierHeight = self.statusNotifierView.frame.size.height;
    self.outlineViewScrollView.contentInsets =
        NSEdgeInsetsMake(self.scrollViewInsets.top,
                         self.scrollViewInsets.left,
                         self.scrollViewInsets.bottom + statusNotifierHeight,
                         self.scrollViewInsets.right);
    self.statusNotifierView.hidden = NO;

    [NSAnimationContext runAnimationRespectingPreferencesWithChanges:^(NSAnimationContext * const __unused context) {
        self.statusNotifierView.animator.alphaValue = 1.0;
    } completionHandler:nil];
}

- (void)statusViewDeactivated:(NSNotification *)notification
{
    [NSAnimationContext runAnimationRespectingPreferencesWithChanges:^(NSAnimationContext * const __unused context) {
        self.statusNotifierView.animator.alphaValue = 0.0;
    } completionHandler:^{
        self.statusNotifierView.hidden = YES;
        self.outlineViewScrollView.contentInsets = self.scrollViewInsets;
    }];
}

- (void)statusViewSizeChanged:(NSNotification *)notification
{
    if (self.statusNotifierView.hidden) {
        return;
    }

    const CGFloat statusNotifierHeight = self.statusNotifierView.frame.size.height;
    self.outlineViewScrollView.contentInsets =
        NSEdgeInsetsMake(self.scrollViewInsets.top,
                         self.scrollViewInsets.left,
                         self.scrollViewInsets.bottom + statusNotifierHeight,
                         self.scrollViewInsets.right);
}

- (NSTreeNode *)nodeForSegmentType:(VLCLibrarySegmentType)segmentType
{
    NSArray<NSTreeNode *> *nodes = self.treeController.arrangedObjects.childNodes;
    while (nodes.count != 0) {
        NSMutableArray<NSTreeNode *> * const nextLevelNodes = NSMutableArray.array;

        const NSInteger nodeIdx = [nodes indexOfObjectPassingTest:^BOOL(NSTreeNode * const obj,
                                                                        const NSUInteger __unused idx,
                                                                        BOOL * const __unused stop) {
            VLCLibrarySegment * const segment = obj.representedObject;
            const BOOL matching = segment.segmentType == segmentType;
            if (!matching) {
                [nextLevelNodes addObjectsFromArray:obj.childNodes];
            }
            return matching;
        }];

        if (nodeIdx != NSNotFound) {
            return nodes[nodeIdx];
        }

        nodes = nextLevelNodes.copy;
    }
    return nil;
}

- (void)expandParentsOfNode:(NSTreeNode *)targetNode
{
    NSMutableArray * const parentNodes = NSMutableArray.array;
    NSTreeNode *currentNode = targetNode.parentNode;
    while (currentNode != nil) {
        [parentNodes insertObject:currentNode atIndex:0];
        currentNode = currentNode.parentNode;
    }

    for (NSTreeNode * const node in parentNodes) {
        [self.outlineView expandItem:node];
    }
}

- (void)selectSegment:(NSInteger)segmentType
{
    NSAssert(segmentType > VLCLibraryLowSentinelSegment &&
             segmentType < VLCLibraryHighSentinelSegment,
             @"Invalid segment type value provided");

    if (segmentType == VLCLibraryHeaderSegmentType) {
        return;
    }

    VLCLibrarySegment * const segment = [VLCLibrarySegment segmentWithSegmentType:segmentType];
    if (segment.mediaLibraryRequired &&
        VLCMain.sharedInstance.libraryController.libraryModel == nil) {
        segmentType = VLCLibraryBrowseSegmentType;
    }

    NSTreeNode *targetNode = [self nodeForSegmentType:segmentType];
    if (targetNode == nil) {
        // Fallback to Browse if the segment is not available
        segmentType = VLCLibraryBrowseSegmentType;
        targetNode = [self nodeForSegmentType:segmentType];
    }

    self.libraryWindow.librarySegmentType = segmentType;

    if (segmentType == VLCLibraryMusicSegmentType) {
        [self.outlineView expandItem:[self nodeForSegmentType:VLCLibraryMusicSegmentType]];
    }

    [self expandParentsOfNode:targetNode];
    const NSInteger segmentIndex = [self.outlineView rowForItem:targetNode];
    if (segmentIndex < 0) return;
    [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:segmentIndex]
                  byExtendingSelection:NO];
}

- (void)synchronizeSelectedSegment:(NSInteger)segmentType
{
    NSInteger row = self.outlineView.selectedRow;
    NSTreeNode *node = row >= 0 ? [self.outlineView itemAtRow:row] : nil;
    VLCLibrarySegment *selected = node.representedObject;
    // Keep a selected pin when it already represents the active category.
    if (selected && selected.segmentType == segmentType) {
        [self refreshSelectionTint];
        return;
    }
    BOOL ignored = self.ignoreSegmentSelectionChanges;
    self.ignoreSegmentSelectionChanges = YES;
    [self selectSegment:segmentType];
    self.ignoreSegmentSelectionChanges = ignored;
    [self refreshSelectionTint];
}

- (void)updateIconTintForCell:(NSTableCellView *)cell segment:(VLCLibrarySegment *)segment selected:(BOOL)selected
{
    if (@available(macOS 10.14, *)) {
        BOOL unavailable = segment.mediaLibraryRequired && VLCMain.sharedInstance.libraryController.libraryModel == nil;
        cell.imageView.contentTintColor = unavailable ? NSColor.tertiaryLabelColor
            : selected ? NSColor.VLCAccentColor : NSColor.VLCControlForegroundColor;
    }
}

- (void)refreshSelectionTint
{
    for (NSInteger row = 0; row < self.outlineView.numberOfRows; ++row) {
        NSTableCellView *cell = [self.outlineView viewAtColumn:0 row:row makeIfNecessary:NO];
        NSTreeNode *node = [self.outlineView itemAtRow:row];
        [self updateIconTintForCell:cell segment:node.representedObject selected:[self.outlineView isRowSelected:row]];
    }
}

# pragma mark - NSOutlineView delegation

- (NSView *)outlineView:(NSOutlineView *)outlineView
     viewForTableColumn:(NSTableColumn *)tableColumn
                   item:(id)item
{
    NSAssert(outlineView == _outlineView, @"VLCLibraryWindowNavigationSidebarController should only be a delegate for the libraryWindow nav sidebar outline view!");

    const BOOL isHeader = [self outlineView:outlineView isGroupItem:item];
    NSTableCellView * const cellView = isHeader
        ? [outlineView makeViewWithIdentifier:@"VLCLibrarySegmentHeaderCellIdentifier" owner:self]
        : [outlineView makeViewWithIdentifier:@"VLCLibrarySegmentCellIdentifier" owner:self];
    NSAssert(cellView != nil, @"Provided cell view for navigation outline view should be valid!");
    [cellView.textField bind:NSValueBinding toObject:cellView withKeyPath:@"objectValue.displayString" options:nil];
    [cellView.imageView bind:NSImageBinding toObject:cellView withKeyPath:@"objectValue.displayImage" options:nil];
    cellView.textField.font = [NSFont vlc_redesignFontOfSize:14 weight:isHeader ? NSFontWeightMedium : NSFontWeightRegular];
    cellView.textField.textColor = isHeader ? NSColor.VLCPrimaryForegroundColor : NSColor.VLCControlForegroundColor;
    if (isHeader) {
        // The original prototype's 14px box was sized for its 11pt font. Keep
        // the real section heading centered with room for the current font.
        BOOL centered = NO;
        for (NSLayoutConstraint *constraint in cellView.constraints)
            if ([constraint.identifier isEqualToString:@"VLCLibraryHeadingCenter"]) centered = YES;
        if (!centered) {
            NSTextField *field = cellView.textField;
            field.translatesAutoresizingMaskIntoConstraints = NO;
            NSLayoutConstraint *center = [field.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor];
            center.identifier = @"VLCLibraryHeadingCenter";
            CGFloat height = ceil([[NSLayoutManager new] defaultLineHeightForFont:field.font]) + 2;
            [NSLayoutConstraint activateConstraints:@[
                [field.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor],
                [field.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor], center,
                [field.heightAnchor constraintEqualToConstant:height]
            ]];
        }
    }

    NSTreeNode * const treeNode = (NSTreeNode *)item;
    VLCLibrarySegment * const segment = (VLCLibrarySegment *)treeNode.representedObject;
    [self updateIconTintForCell:cellView segment:segment selected:[outlineView isRowSelected:[outlineView rowForItem:item]]];
    const BOOL mediaLibraryUnavailable =
        segment.mediaLibraryRequired &&
        VLCMain.sharedInstance.libraryController.libraryModel == nil;
    if (mediaLibraryUnavailable) {
        cellView.textField.textColor = NSColor.tertiaryLabelColor;
        if (@available(macOS 10.14, *)) {
            cellView.imageView.contentTintColor = NSColor.tertiaryLabelColor;
        }
    }

    return cellView;
}

- (NSIndexSet *)outlineView:(NSOutlineView *)outlineView selectionIndexesForProposedSelection:(nonnull NSIndexSet *)proposedSelectionIndexes
{
    NSAssert(outlineView == _outlineView, @"VLCLibraryWindowNavigationSidebarController should only be a delegate for the libraryWindow nav sidebar outline view!");

    if (proposedSelectionIndexes.count > 0) {
        NSTreeNode * const node = [self.outlineView itemAtRow:proposedSelectionIndexes.firstIndex];
        VLCLibrarySegment * const segment = (VLCLibrarySegment *)node.representedObject;

        if (segment.segmentType == VLCLibraryHeaderSegmentType) {
            return NSIndexSet.indexSet;
        }

        const BOOL mediaLibraryUnavailable =
            segment.mediaLibraryRequired &&
            VLCMain.sharedInstance.libraryController.libraryModel == nil;
        if (mediaLibraryUnavailable) {
            return [outlineView selectedRowIndexes];
        }
    }

    return proposedSelectionIndexes;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    [self refreshSelectionTint];
    if (self.ignoreSegmentSelectionChanges) {
        return;
    }
    
    NSTreeNode * const node = (NSTreeNode *)[_outlineView itemAtRow:_outlineView.selectedRow];
    NSParameterAssert(node != nil);
    VLCLibrarySegment * const segment = (VLCLibrarySegment *)node.representedObject;
    NSObject * const representedObject = segment.representedObject;
    NSParameterAssert(representedObject != nil);

    if (segment.segmentType == VLCLibraryMusicSegmentType) {
        [self.outlineView expandItem:[self nodeForSegmentType:VLCLibraryMusicSegmentType]];
        NSTreeNode * const artistsNode = [self nodeForSegmentType:VLCLibraryArtistsMusicSubSegmentType];
        const NSInteger artistsIndex = [self.outlineView rowForItem:artistsNode];
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:artistsIndex]
                      byExtendingSelection:NO];
        return;
    } else if ([representedObject isKindOfClass:NSNumber.class]) {
        self.libraryWindow.librarySegmentType = segment.segmentType;
    } else if ([representedObject isKindOfClass:VLCLibrarySegmentBookmarkedLocation.class]) {
        VLCLibrarySegmentBookmarkedLocation * const bookmarkedLocation =
            (VLCLibrarySegmentBookmarkedLocation *)representedObject;
        self.libraryWindow.librarySegmentType = bookmarkedLocation.segmentType;
        [self.libraryWindow browseFolderByMrl:bookmarkedLocation.mrl];
    } else if ([representedObject isKindOfClass:NSDictionary.class]) {
        id item = [(NSDictionary *)representedObject objectForKey:@"item"];
        if ([item isKindOfClass:NSURL.class]) {
            self.libraryWindow.librarySegmentType = VLCLibraryBrowseSegmentType;
            [self.libraryWindow browseFolderByMrl:[item absoluteString]];
        } else if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
            [VLCMain.sharedInstance.libraryController appendItemToPlayQueue:item playImmediately:YES];
        } else if (item) [self.libraryWindow presentLibraryItem:item];
    } else if ([representedObject isKindOfClass:VLCMediaLibraryGroup.class]) {
        [self.libraryWindow presentLibraryItem:(VLCMediaLibraryGroup *)representedObject];
    }
    
    // Refresh disclosure triangles when selection changes
    [(VLCLibraryWindowNavigationSidebarOutlineView *)self.outlineView refreshDisclosureCaret];
}

- (BOOL)outlineView:(NSOutlineView*)outlineView isGroupItem:(id)item
{
    NSTreeNode * const treeNode = (NSTreeNode *)item;
    VLCLibrarySegment * const segment = (VLCLibrarySegment *)treeNode.representedObject;
    return segment.segmentType == VLCLibraryHeaderSegmentType;
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item
{
    if ([self outlineView:outlineView isGroupItem:item]) {
        NSFont *font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightMedium];
        return MAX(outlineView.rowHeight, ceil([[NSLayoutManager new] defaultLineHeightForFont:font]) + 2);
    }
    return outlineView.rowHeight;
}

- (BOOL)outlineView:(nonnull NSOutlineView *)outlineView shouldCollapseItem:(nonnull id)item
{
    NSAssert(outlineView == _outlineView, @"VLCLibraryWindowNavigationSidebarController should only be a delegate for the libraryWindow nav sidebar outline view!");

    // Don't allow collapsing the parent segment of the selected segment, if selection is a child
    NSTreeNode * const treeNode = (NSTreeNode *)item;
    VLCLibrarySegment * const segment = (VLCLibrarySegment *)treeNode.representedObject;
    NSTreeNode * const selectedSegmentItem = (NSTreeNode *)[self.outlineView itemAtRow:self.outlineView.selectedRow];
    VLCLibrarySegment * const selectedSegment = (VLCLibrarySegment *)selectedSegmentItem.representedObject;
    const NSInteger childNodeIndex = [segment.childNodes indexOfObjectPassingTest:^BOOL(NSTreeNode * const _Nonnull obj, const NSUInteger __unused idx, BOOL * const _Nonnull __unused stop) {
        VLCLibrarySegment * const childSegment = (VLCLibrarySegment *)obj;
        return childSegment.segmentType == selectedSegment.segmentType;
    }];
    return childNodeIndex == NSNotFound;
}

@end
