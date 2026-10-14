/*****************************************************************************
 * VLCLibraryPlaylistDataSource.m: MacOS X interface module
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

#import "VLCLibraryPlaylistDataSource.h"

#import "extensions/NSPasteboardItem+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"

#import "library/VLCLibraryCollectionViewFlowLayout.h"
#import "library/VLCLibraryCollectionViewItem.h"
#import "library/VLCLibraryCollectionViewMediaItemListSupplementaryDetailView.h"
#import "library/VLCLibraryCollectionViewSupplementaryElementView.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibraryMasterDetailViewTableViewDelegate.h"
#import "library/VLCLibraryModel.h"
#import "library/VLCLibraryRepresentedItem.h"

#import "main/VLCMain.h"

typedef NS_ENUM(NSInteger, VLCLibraryDataSourceCacheAction) {
    VLCLibraryDataSourceCacheUpdateAction,
    VLCLibraryDataSourceCacheDeleteAction,
};

@interface VLCLibraryPlaylistDataSource () {
    dispatch_queue_t _playlistQueue;
    NSArray<VLCMediaLibraryPlaylist *> *_playlists;
    NSArray<VLCMediaLibraryPlaylist *> *_viewPlaylists;
}

@end

@implementation VLCLibraryPlaylistDataSource

@synthesize headerDelegate;

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup
{
    _playlistQueue = dispatch_queue_create("org.videolan.vlc.libraryplaylistdatasource.queue", DISPATCH_QUEUE_CONCURRENT);
    _libraryModel = VLCMain.sharedInstance.libraryController.libraryModel;
    [self connect];
    [self reloadData];
}

- (NSArray<VLCMediaLibraryPlaylist *> *)backendPlaylists
{
    __block NSArray<VLCMediaLibraryPlaylist *> *playlists;
    dispatch_sync(_playlistQueue, ^{
        playlists = self->_playlists;
    });
    return playlists;
}

- (NSArray<VLCMediaLibraryPlaylist *> *)playlists
{
    // AppKit reads the snapshot published by the current main-thread update,
    // not a later background commit which has yet to update its row caches.
    return NSThread.isMainThread ? (_viewPlaylists ?: @[]) : [self backendPlaylists];
}

- (BOOL)snapshot:(NSArray<VLCMediaLibraryPlaylist *> *)a matchesIDsIn:(NSArray<VLCMediaLibraryPlaylist *> *)b
{
    if (a.count != b.count) return NO;
    for (NSUInteger index = 0; index < a.count; ++index)
        if (a[index].libraryID != b[index].libraryID) return NO;
    return YES;
}

- (void)setPlaylists:(NSArray<VLCMediaLibraryPlaylist *> *)playlists
{
    dispatch_barrier_async(_playlistQueue, ^{
        self->_playlists = [playlists copy];
    });
}

- (void)connect
{
    NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(playlistsReset:)
                               name:VLCLibraryModelPlaylistAdded
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(playlistUpdated:)
                               name:VLCLibraryModelPlaylistUpdated
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(playlistDeleted:)
                               name:VLCLibraryModelPlaylistDeleted
                             object:nil];
}

- (void)disconnect
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)playlistsReset:(NSNotification *)notification
{
    NSParameterAssert(notification);
    [self reloadData];
}

- (void)playlistUpdated:(NSNotification *)notification
{
    NSParameterAssert(notification);
    VLCMediaLibraryPlaylist * const playlist = (VLCMediaLibraryPlaylist *)notification.object;
    [self applyCacheAction:VLCLibraryDataSourceCacheUpdateAction
            withPlaylistID:playlist.libraryID
                  playlist:playlist];
}

- (void)playlistDeleted:(NSNotification *)notification
{
    NSParameterAssert(notification);
    NSParameterAssert((NSNumber *)notification.object != nil);

    const int64_t playlistId = [(NSNumber *)notification.object longLongValue];
    [self applyCacheAction:VLCLibraryDataSourceCacheDeleteAction
            withPlaylistID:playlistId
                  playlist:nil];
}

- (void)reloadData
{
    NSArray<VLCMediaLibraryPlaylist *> * const listOfPlaylists =
        [self.libraryModel listOfPlaylistsOfType:self.playlistType];
    self.playlists = listOfPlaylists ?: @[];
    [self reloadViews];
    [self updateHeaderInTableView:self.detailTableView forMasterSelection:self.masterTableView];
}

- (void)reloadViews
{
    VLCMain *owner = VLCMain.sharedInstance;
    if (!owner || owner.isTerminating) return;
    _viewPlaylists = [self backendPlaylists];
    [self.masterTableView reloadData];
    [self.detailTableView reloadData];
    
    for (NSCollectionView * const collectionView in self.collectionViews) {
        [(VLCLibraryCollectionViewFlowLayout *)collectionView.collectionViewLayout resetLayout];
        [collectionView reloadData];
    }
}

- (NSIndexSet *)indexesForPlaylistIDs:(NSSet<NSNumber *> *)identifiers
                           snapshot:(NSArray<VLCMediaLibraryPlaylist *> *)snapshot
{
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    [snapshot enumerateObjectsUsingBlock:^(VLCMediaLibraryPlaylist *item, NSUInteger index, BOOL *stop) {
        if ([identifiers containsObject:@(item.libraryID)]) [indexes addIndex:index];
    }];
    return indexes;
}

- (void)reloadViewsAtIndex:(NSUInteger)index
          dueToCacheAction:(VLCLibraryDataSourceCacheAction)action
          previousSnapshot:(NSArray<VLCMediaLibraryPlaylist *> *)previous
           updatedSnapshot:(NSArray<VLCMediaLibraryPlaylist *> *)updated
{
    VLCMain *owner = VLCMain.sharedInstance;
    if (!owner || owner.isTerminating) return;
    NSArray<VLCMediaLibraryPlaylist *> *current = [self backendPlaylists];
    NSArray<VLCMediaLibraryPlaylist *> *shown = _viewPlaylists ?: @[];
    BOOL causal = [self snapshot:shown matchesIDsIn:previous] && [self snapshot:current matchesIDsIn:updated];
    _viewPlaylists = current;
    NSUInteger expectedBefore = current.count + (action == VLCLibraryDataSourceCacheDeleteAction ? 1 : 0);
    NSTableView *master = self.masterTableView;
    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:index];
    NSInteger selectedRow = master.selectedRow;
    NSSet *selectedIDs = selectedRow >= 0 && selectedRow < shown.count ?
        [NSSet setWithObject:@([(VLCMediaLibraryPlaylist *)shown[selectedRow] libraryID])] : [NSSet set];
    // Cache resets and view reattachment can overtake a queued delta. AppKit
    // permits a delta only against the matching pre-mutation row snapshot.
    BOOL matches = causal && master.dataSource == self && master.numberOfRows == expectedBefore && index < expectedBefore;
    if (!matches) [master reloadData];
    else if (action == VLCLibraryDataSourceCacheDeleteAction)
        [master removeRowsAtIndexes:indexSet withAnimation:NSTableViewAnimationEffectNone];
    else if (action == VLCLibraryDataSourceCacheUpdateAction)
        [master reloadDataForRowIndexes:indexSet columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, master.numberOfColumns)]];
    else NSAssert(false, @"Invalid playlist cache action");
    if (master.dataSource == self && master.numberOfRows == current.count)
        [master selectRowIndexes:[self indexesForPlaylistIDs:selectedIDs snapshot:current] byExtendingSelection:NO];
    [self.detailTableView reloadData];
    [self updateHeaderInTableView:self.detailTableView forMasterSelection:master];

    NSIndexPath *path = [NSIndexPath indexPathForItem:index inSection:0];
    NSSet *paths = [NSSet setWithObject:path];
    for (NSCollectionView *collection in self.collectionViews) {
        NSInteger oldCount = collection.numberOfSections == 1 ? [collection numberOfItemsInSection:0] : -1;
        NSArray *shownItems = shown;
        NSMutableSet *IDs = [NSMutableSet set];
        for (NSIndexPath *selection in collection.selectionIndexPaths)
            if (selection.section == 0 && selection.item < shownItems.count)
                [IDs addObject:@([(VLCMediaLibraryPlaylist *)shownItems[selection.item] libraryID])];
        BOOL matches = causal && collection.dataSource == self && oldCount == expectedBefore && index < expectedBefore;
        if (action == VLCLibraryDataSourceCacheDeleteAction || !matches)
            [(VLCLibraryCollectionViewFlowLayout *)collection.collectionViewLayout resetLayout];
        if (!matches) [collection reloadData];
        else if (action == VLCLibraryDataSourceCacheDeleteAction) [collection deleteItemsAtIndexPaths:paths];
        else if (action == VLCLibraryDataSourceCacheUpdateAction) [collection reloadItemsAtIndexPaths:paths];
        else NSAssert(false, @"Invalid playlist cache action");
        NSMutableSet *selection = [NSMutableSet set];
        [[self indexesForPlaylistIDs:IDs snapshot:current] enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
            [selection addObject:[NSIndexPath indexPathForItem:row inSection:0]];
        }];
        if (collection.dataSource == self && collection.numberOfSections == 1 &&
            [collection numberOfItemsInSection:0] == current.count)
            collection.selectionIndexPaths = selection;
    }
}

- (void)applyCacheAction:(VLCLibraryDataSourceCacheAction)action
          withPlaylistID:(const int64_t)playlistID
                playlist:(VLCMediaLibraryPlaylist * _Nullable const)playlist
{
    dispatch_barrier_async(_playlistQueue, ^{
        NSArray *previous = self->_playlists;
        NSMutableArray *mutablePlaylists = [previous mutableCopy];
        if (mutablePlaylists == nil) {
            return;
        }

        const NSUInteger idx =
            [mutablePlaylists indexOfObjectPassingTest:^BOOL(const VLCMediaLibraryPlaylist *item, 
                                                             const NSUInteger __unused index,
                                                             BOOL * const __unused stop) {
            return item.libraryID == playlistID;
        }];

        if (idx == NSNotFound) {
            return;
        }

        switch (action) {
            case VLCLibraryDataSourceCacheUpdateAction:
                NSAssert(playlist != nil, @"Playlist must not be nil for update action");
                if (playlist != nil) {
                    [mutablePlaylists replaceObjectAtIndex:idx withObject:playlist];
                }
                break;
            case VLCLibraryDataSourceCacheDeleteAction:
                [mutablePlaylists removeObjectAtIndex:idx];
                break;
            default:
                NSAssert(false, @"Invalid playlist cache action");
        }
        self->_playlists = [mutablePlaylists copy];
        NSArray *updated = self->_playlists;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadViewsAtIndex:idx dueToCacheAction:action previousSnapshot:previous updatedSnapshot:updated];
        });
    });
}

#pragma mark - table view data source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    VLCMain *owner = VLCMain.sharedInstance;
    if (!owner || owner.isTerminating) return 0;
    if (tableView == self.masterTableView) {
        return self.playlists.count;
    }

    NSArray *snapshot = self.playlists;
    const NSInteger selectedMasterRow = self.masterTableView.selectedRow;
    if (selectedMasterRow >= 0 && selectedMasterRow < snapshot.count) {
        const id<VLCMediaLibraryItemProtocol> item = snapshot[selectedMasterRow];
        return item.mediaItems.count;
    }

    return 0;
}

- (id<VLCMediaLibraryItemProtocol>)libraryItemAtRow:(NSInteger)row
                                       forTableView:(NSTableView *)tableView
{
    VLCMain *owner = VLCMain.sharedInstance;
    if (!owner || owner.isTerminating || row < 0) return nil;
    NSArray *snapshot = self.playlists;
    if (tableView == self.masterTableView) return row < snapshot.count ? snapshot[row] : nil;
    NSInteger selected = self.masterTableView.selectedRow;
    if (tableView == self.detailTableView && selected >= 0 && selected < snapshot.count) {
        NSArray *items = [(id<VLCMediaLibraryItemProtocol>)snapshot[selected] mediaItems];
        return row < items.count ? items[row] : nil;
    }
    return nil;
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    const id<VLCMediaLibraryItemProtocol> libraryItem = [self libraryItemAtRow:row forTableView:tableView];
    return libraryItem ? [NSPasteboardItem pasteboardItemWithLibraryItem:libraryItem] : nil;
}

- (NSInteger)rowForLibraryItem:(id<VLCMediaLibraryItemProtocol>)libraryItem
{
    if (libraryItem == nil) {
        return NSNotFound;
    }
    return [self.playlists indexOfObjectPassingTest:^BOOL(const VLCMediaLibraryPlaylist *playlist, const NSUInteger __unused idx, BOOL * const __unused stop) {
        return playlist.libraryID == libraryItem.libraryID;
    }];
}

#pragma mark - collection view data source

- (void)setCollectionViews:(NSArray<NSCollectionView *> *)collectionViews
{
    _collectionViews = collectionViews;
    for (NSCollectionView * const collectionView in self.collectionViews) {
        [self setupCollectionView:collectionView];
    }
}

- (void)setupCollectionView:(NSCollectionView *)collectionView
{
    [collectionView registerClass:VLCLibraryCollectionViewItem.class
            forItemWithIdentifier:VLCLibraryCollectionViewItemIdentifier];
    [collectionView registerClass:VLCLibraryCollectionViewSupplementaryElementView.class
       forSupplementaryViewOfKind:NSCollectionElementKindSectionHeader
                   withIdentifier:VLCLibrarySupplementaryElementViewIdentifier];

    NSNib * const supplementaryDetailView =
        [[NSNib alloc] initWithNibNamed:@"VLCLibraryCollectionViewMediaItemListSupplementaryDetailView" bundle:nil];
    [collectionView registerNib:supplementaryDetailView
      forSupplementaryViewOfKind:VLCLibraryCollectionViewMediaItemListSupplementaryDetailViewKind
                  withIdentifier:VLCLibraryCollectionViewMediaItemListSupplementaryDetailViewIdentifier];

    NSCollectionViewFlowLayout * const layout = collectionView.collectionViewLayout;
    layout.headerReferenceSize = VLCLibraryCollectionViewSupplementaryElementView.defaultHeaderSize;

    collectionView.dataSource = self;
    [collectionView reloadData];
}

- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section
{
    return self.playlists.count;
}

- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView
{
    return 1;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath
{
    const id<VLCMediaLibraryItemProtocol> libraryItem = [self libraryItemAtIndexPath:indexPath forCollectionView:collectionView];
    if (!libraryItem) {
        NSCollectionViewItem *empty = [NSCollectionViewItem new];
        empty.view = [NSView new];
        return empty;
    }
    VLCLibraryCollectionViewItem * const viewItem =
        [collectionView makeItemWithIdentifier:VLCLibraryCollectionViewItemIdentifier forIndexPath:indexPath];
    // NOTE: Unknown parent type represented items default to playing the represented item only.
    // We want this behaviour as it feels unnatural to handle any parent types for playlists
    VLCLibraryRepresentedItem * const representedItem = [[VLCLibraryRepresentedItem alloc] initWithItem:libraryItem
                                                                                             parentType:VLCMediaLibraryParentGroupTypeUnknown];
    viewItem.representedItem = representedItem;
    return viewItem;
}

- (NSView *)collectionView:(NSCollectionView *)collectionView
viewForSupplementaryElementOfKind:(NSCollectionViewSupplementaryElementKind)kind
               atIndexPath:(NSIndexPath *)indexPath
{
    if([kind isEqualToString:NSCollectionElementKindSectionHeader]) {
        VLCLibraryCollectionViewSupplementaryElementView * const sectionHeadingView = [collectionView makeSupplementaryViewOfKind:kind withIdentifier:VLCLibrarySupplementaryElementViewIdentifier forIndexPath:indexPath];

        sectionHeadingView.stringValue = _NS("Playlists");
        return sectionHeadingView;

    } else if ([kind isEqualToString:VLCLibraryCollectionViewMediaItemListSupplementaryDetailViewKind]) {
        const id<VLCMediaLibraryItemProtocol> item =
            [self libraryItemAtIndexPath:indexPath forCollectionView:collectionView];
        if (!item) return [NSView new];
        NSString * const supplementaryDetailViewIdentifier =
            VLCLibraryCollectionViewMediaItemListSupplementaryDetailViewIdentifier;
        VLCLibraryCollectionViewMediaItemListSupplementaryDetailView * const supplementaryDetailView =
            [collectionView makeSupplementaryViewOfKind:kind
                                         withIdentifier:supplementaryDetailViewIdentifier
                                           forIndexPath:indexPath];
        VLCLibraryRepresentedItem * const representedItem =
            [[VLCLibraryRepresentedItem alloc] initWithItem:item parentType:self.currentParentType];
        supplementaryDetailView.representedItem = representedItem;
        supplementaryDetailView.selectedItem = [collectionView itemAtIndexPath:indexPath];
        return supplementaryDetailView;
    }

    return nil;
}

- (id<VLCMediaLibraryItemProtocol>)libraryItemAtIndexPath:(NSIndexPath *)indexPath
                                        forCollectionView:(NSCollectionView *)collectionView
{
    VLCMain *owner = VLCMain.sharedInstance;
    NSArray *snapshot = self.playlists;
    const NSUInteger indexPathItem = indexPath.item;

    if (!owner || owner.isTerminating || indexPath == nil || indexPath.section != 0 || indexPathItem >= snapshot.count) {
        return nil;
    }

    return snapshot[indexPathItem];
}

- (NSIndexPath *)indexPathForLibraryItem:(id<VLCMediaLibraryItemProtocol>)libraryItem
{
    const NSUInteger idx = [self.playlists indexOfObject:libraryItem];
    if (idx == NSNotFound) {
        return nil;
    }

    return [NSIndexPath indexPathForItem:idx inSection:0];
}

- (NSArray<VLCLibraryRepresentedItem *> *)representedItemsAtIndexPaths:(NSSet<NSIndexPath *> *const)indexPaths
                                                     forCollectionView:(NSCollectionView *)collectionView
{
    NSMutableArray<VLCLibraryRepresentedItem *> * const representedItems =
        [NSMutableArray arrayWithCapacity:indexPaths.count];

    for (NSIndexPath * const indexPath in indexPaths) {
        const id<VLCMediaLibraryItemProtocol> libraryItem =
            [self libraryItemAtIndexPath:indexPath forCollectionView:collectionView];
        if (!libraryItem) continue;
        VLCLibraryRepresentedItem * const representedItem =
            [[VLCLibraryRepresentedItem alloc] initWithItem:libraryItem
                                                 parentType:self.currentParentType];
        [representedItems addObject:representedItem];
    }

    return representedItems;
}

- (VLCMediaLibraryParentGroupType)currentParentType
{
    return VLCMediaLibraryParentGroupTypePlaylist;
}

- (id<VLCMediaLibraryItemProtocol>)parentItemForTableView:(NSTableView *)tableView
{
    if (tableView != self.detailTableView) {
        return nil;
    }

    const NSInteger selectedRow = self.masterTableView.selectedRow;
    if (selectedRow < 0 || (NSUInteger)selectedRow >= self.playlists.count) {
        return nil;
    }

    return self.playlists[selectedRow];
}

- (NSString *)supplementaryDetailViewKind
{
    return VLCLibraryCollectionViewMediaItemListSupplementaryDetailViewKind;
}

- (void)setPlaylistType:(vlc_ml_playlist_type_t)playlistType
{
    if (self.playlistType == playlistType) {
        return;
    }

    _playlistType = playlistType;
    [self reloadData];
}

- (void)updateHeaderInTableView:(NSTableView *)detailTableView forMasterSelection:(NSTableView *)masterTableView
{
    if (self.headerDelegate == nil) {
        return;
    }

    const NSInteger selectedRow = masterTableView.selectedRow;
    if (selectedRow < 0 || (NSUInteger)selectedRow >= self.playlists.count) {
        [self.headerDelegate updateHeaderForTableView:detailTableView
                                  withRepresentedItem:nil
                                        fallbackTitle:_NS("Playlists")
                                       fallbackDetail:_NS("Select a playlist")];
        return;
    }

    const VLCMediaLibraryPlaylist * const playlist = self.playlists[selectedRow];
    VLCLibraryRepresentedItem * const representedItem =
        [[VLCLibraryRepresentedItem alloc] initWithItem:playlist
                                             parentType:self.currentParentType];

    [self.headerDelegate updateHeaderForTableView:detailTableView
                              withRepresentedItem:representedItem
                                    fallbackTitle:playlist.primaryDetailString
                                   fallbackDetail:playlist.secondaryDetailString];
}

@end
