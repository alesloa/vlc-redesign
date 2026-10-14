/*****************************************************************************
 * VLCPlayQueueDataSource.m: MacOS X interface module
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

#import "VLCPlayQueueDataSource.h"

#import "extensions/NSPasteboardItem+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayQueueTableCellView.h"
#import "playqueue/VLCPlayQueueItem.h"
#import "playqueue/VLCPlayQueueModel.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryDataTypes.h"
#import "views/VLCDragDropView.h"
#import "views/VLCFileDragRecognisingView.h"

static NSString *VLCPlayQueueCellIdentifier = @"VLCPlayQueueCellIdentifier";

@interface VLCPlayQueueDataSource ()
{
    VLCPlayQueueModel *_playQueueModel;
    NSArray<VLCPlayQueueItem *> *_visibleItems;
}
@end

@implementation VLCPlayQueueDataSource

- (void)setPlayQueueController:(VLCPlayQueueController *)playQueueController
{
    [_playQueueController unregisterPlayQueueDataSource:self];
    _playQueueController = playQueueController;
    _playQueueModel = _playQueueController.playQueueModel;
    [_playQueueController registerPlayQueueDataSource:self];
    [self rebuildVisibleItems];
}
- (void)rebuildVisibleItems
{
    NSArray *items=_playQueueModel.playQueueItems ?: @[]; NSString *query=self.searchQuery ?: @"";
    _visibleItems=!query.length?items.copy:[items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(VLCPlayQueueItem *item,NSDictionary *bindings){
        return [item.title localizedCaseInsensitiveContainsString:query] || [item.path localizedCaseInsensitiveContainsString:query] ||
            [item.artistName localizedCaseInsensitiveContainsString:query] || [item.albumName localizedCaseInsensitiveContainsString:query];
    }]];
}
- (void)setSearchQuery:(NSString *)query {_searchQuery=[query copy];[self playQueueUpdated];}
- (VLCPlayQueueItem *)itemForVisibleRow:(NSInteger)row
{
    return row>=0 && row<_visibleItems.count?_visibleItems[row]:nil;
}
- (NSUInteger)modelIndexForVisibleRow:(NSInteger)row
{
    VLCPlayQueueItem *item=[self itemForVisibleRow:row]; if(!item)return NSNotFound;
    return [_playQueueModel.playQueueItems indexOfObjectPassingTest:^BOOL(VLCPlayQueueItem *candidate,NSUInteger index,BOOL *stop){return candidate.uniqueID==item.uniqueID;}];
}
- (NSIndexSet *)modelIndexesForViewIndexes:(NSIndexSet *)indexes
{
    NSMutableIndexSet *mapped=[NSMutableIndexSet indexSet];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index,BOOL *stop){NSUInteger target=[self modelIndexForVisibleRow:index];if(target!=NSNotFound)[mapped addIndex:target];}];return mapped;
}
- (void)removeItemWithUniqueID:(uint64_t)identifier
{
    NSUInteger index=[_playQueueModel.playQueueItems indexOfObjectPassingTest:^BOOL(VLCPlayQueueItem *item,NSUInteger index,BOOL *stop){return item.uniqueID==identifier;}];
    if(index!=NSNotFound)[self.playQueueController removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:index]];
}

- (void)setCounterTextField:(NSTextField *)counterTextField
{
    _counterTextField = counterTextField;
    self.counterTextField.stringValue =
        [NSString stringWithFormat:@"%lu %@", _playQueueModel.numberOfPlayQueueItems,_NS("Items")];
}

- (void)prepareForUse
{
    [_tableView registerForDraggedTypes:@[
        VLCMediaLibraryMediaItemPasteboardType,
        VLCMediaLibraryMediaItemUTI,
        VLCPlaylistItemPasteboardType,
        NSPasteboardTypeURL,
        NSPasteboardTypeFileURL,
        NSPasteboardTypeString,
        NSFilenamesPboardType
    ]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _visibleItems.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    VLCPlayQueueTableCellView *cellView =
        [tableView makeViewWithIdentifier:VLCPlayQueueCellIdentifier owner:self];

    if (cellView == nil) {
        cellView = [[VLCPlayQueueTableCellView alloc] initWithFrame:NSMakeRect(0,0,tableColumn.width,32)];
        if (cellView == nil) {
            msg_Err(getIntf(), "Failed to load nib file to show playlist items");
            return nil;
        }
        cellView.identifier = VLCPlayQueueCellIdentifier;
    }

    VLCPlayQueueItem * const item = [self itemForVisibleRow:row];
    if (!item) {
        msg_Err(getIntf(), "playlist model did not return an item for representation");
        return cellView;
    }

    cellView.representedPlayQueueItem = item;
    cellView.representsCurrentPlayQueueItem = _playQueueController.currentPlayQueueIndex == [self modelIndexForVisibleRow:row];
    __weak typeof(self) weakSelf=self;
    cellView.removalHandler=^(uint64_t identifier){[weakSelf removeItemWithUniqueID:identifier];};

    return cellView;
}

- (void)playQueueUpdated
{
    NSMutableSet *selectedIDs=[NSMutableSet set];
    [self.tableView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger index,BOOL *stop){VLCPlayQueueItem *item=[self itemForVisibleRow:index];if(item)[selectedIDs addObject:@(item.uniqueID)];}];
    [self rebuildVisibleItems];
    const NSUInteger numberOfPlayQueueItems = _playQueueModel.numberOfPlayQueueItems;
    self.dragDropView.hidden = numberOfPlayQueueItems > 0 ? YES : NO;
    self.counterTextField.stringValue = [NSString stringWithFormat:@"%lu %@", numberOfPlayQueueItems,_NS("Items")];
    [_tableView reloadData];
    NSMutableIndexSet *selection=[NSMutableIndexSet indexSet];
    [_visibleItems enumerateObjectsUsingBlock:^(VLCPlayQueueItem *item,NSUInteger index,BOOL *stop){if([selectedIDs containsObject:@(item.uniqueID)])[selection addIndex:index];}];
    [self.tableView selectRowIndexes:selection byExtendingSelection:NO];
}

- (void)playQueueItemsInsertedAtIndex:(NSUInteger)index count:(NSUInteger)count
{
    if(self.searchQuery.length){[self playQueueUpdated];return;}
    [self rebuildVisibleItems];
    const NSUInteger numberOfPlayQueueItems = _playQueueModel.numberOfPlayQueueItems;
    self.dragDropView.hidden = numberOfPlayQueueItems > 0 ? YES : NO;
    self.counterTextField.stringValue = [NSString stringWithFormat:@"%lu %@", numberOfPlayQueueItems,_NS("Items")];

    if (count == 0) {
        return;
    }

    NSAssert(index <= numberOfPlayQueueItems - count,
             @"Inserted play queue rows must be within the model bounds");
    NSIndexSet * const indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, count)];
    [_tableView insertRowsAtIndexes:indexes withAnimation:NSTableViewAnimationEffectNone];
}

- (void)playQueueItemsUpdatedAtIndex:(NSUInteger)index count:(NSUInteger)count
{
    if(self.searchQuery.length){[self playQueueUpdated];return;}
    [self rebuildVisibleItems];
    if (count == 0) {
        return;
    }

    const NSUInteger numberOfPlayQueueItems = _playQueueModel.numberOfPlayQueueItems;
    NSAssert(index <= numberOfPlayQueueItems - count,
             @"Updated play queue rows must be within the model bounds");
    NSIndexSet * const indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, count)];
    [_tableView reloadDataForRowIndexes:indexes columnIndexes:[NSIndexSet indexSetWithIndex:0]];
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    NSPasteboardItem * const pboardItem = [[NSPasteboardItem alloc] init];
    VLCPlayQueueItem * const playlistItem = [self itemForVisibleRow:row];
    if(!playlistItem)return nil;
    [pboardItem setString:[@(playlistItem.uniqueID) stringValue] forType:VLCPlaylistItemPasteboardType];
    return pboardItem;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
    // Make drops at the end of the table go to the end.
    if (row == -1) {
        row = tableView.numberOfRows;
        dropOperation = NSTableViewDropAbove;
        [tableView setDropRow:row dropOperation:dropOperation];
    }

    // We don't ever want to drop onto a row, only between rows.
    if (dropOperation == NSTableViewDropOn) {
        [tableView setDropRow:row + 1 dropOperation:NSTableViewDropAbove];
    }

    return info.draggingSource==tableView?NSDragOperationMove:NSDragOperationCopy;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation
{
    // A filtered view row represents an actual playlist identity, not its model
    // position. Insert at that live identity, or at the real end of the queue.
    NSUInteger insertion=row<0 || row>=_visibleItems.count?_playQueueModel.numberOfPlayQueueItems:[self modelIndexForVisibleRow:row];
    if(insertion==NSNotFound)return NO;
    NSMutableArray<NSNumber *> *IDs = [NSMutableArray array];
    for (NSPasteboardItem *item in info.draggingPasteboard.pasteboardItems) {
        NSString *value = [item stringForType:VLCPlaylistItemPasteboardType];
        if (value) { unsigned long long identifier; NSScanner *scanner = [NSScanner scannerWithString:value]; if ([scanner scanUnsignedLongLong:&identifier] && scanner.isAtEnd) [IDs addObject:@(identifier)]; }
    }
    if (IDs.count) {
        return [_playQueueController moveItemsWithIDs:IDs toPosition:insertion] == VLC_SUCCESS;
    }

    /* Collect library media items from all pasteboard items.
     * Table view drags create one NSPasteboardItem per selected row, so we
     * must iterate all of them to capture every dragged item. */
    NSMutableArray<VLCMediaLibraryMediaItem *> * const allMediaItems = [NSMutableArray array];

    for (NSPasteboardItem * const pboardItem in info.draggingPasteboard.pasteboardItems) {
        NSData *itemData = [pboardItem dataForType:VLCMediaLibraryMediaItemPasteboardType];
        if (!itemData) {
            itemData = [pboardItem dataForType:VLCMediaLibraryMediaItemUTI];
        }
        if (!itemData) {
            continue;
        }

        NSArray<VLCMediaLibraryMediaItem *> * const items = [VLCMediaLibraryMediaItem mediaItemsFromPasteboardData:itemData];
        if (items) {
            [allMediaItems addObjectsFromArray:items];
        }
    }

    /* Collection view drags write a single aggregated payload directly on the
     * dragging pasteboard instead of creating one NSPasteboardItem per item. */
    if (allMediaItems.count == 0) {
        NSData *itemData = [info.draggingPasteboard dataForType:VLCMediaLibraryMediaItemPasteboardType];
        if (!itemData) {
            itemData = [info.draggingPasteboard dataForType:VLCMediaLibraryMediaItemUTI];
        }

        if (itemData) {
            NSArray<VLCMediaLibraryMediaItem *> * const items = [VLCMediaLibraryMediaItem mediaItemsFromPasteboardData:itemData];
            if (items) {
                [allMediaItems addObjectsFromArray:items];
            }
        }
    }

    if (allMediaItems.count > 0) {
        NSInteger insertionIndex = insertion;
        for (VLCMediaLibraryMediaItem * const mediaItem in allMediaItems) {
            [_playQueueController addInputItem:mediaItem.inputItem.vlcInputItem
                                    atPosition:insertionIndex
                                 startPlayback:NO];
            insertionIndex++;
        }
        return YES;
    }

    return [VLCFileDragRecognisingView
        handlePasteboardFromDragSessionAsPlayQueueItems:info.draggingPasteboard
                                            atPosition:insertion
                                         startPlayback:NO];
}

- (NSArray<NSTableViewRowAction *> *)tableView:(NSTableView *)tableView
                              rowActionsForRow:(NSInteger)row
                                          edge:(NSTableRowActionEdge)edge
{
    if (edge == NSTableRowActionEdgeTrailing) {
        VLCPlayQueueItem * const item = [self itemForVisibleRow:row];
        if (item == nil) {
            return @[];
        }

        NSTableViewRowAction * const removeAction =
            [NSTableViewRowAction rowActionWithStyle:NSTableViewRowActionStyleDestructive
                                                title:_NS("Remove from Play Queue")
                                               handler:^(NSTableViewRowAction * const __unused action, const NSInteger row) {
                [self removeItemWithUniqueID:item.uniqueID];
            }];
        return @[removeAction];
    }
    return @[];
}

- (void)scrollToCurrentPlayQueueItem
{
    if (_visibleItems.count)
        [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _visibleItems.count)]
                             columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    VLCPlayQueueItem *current=[_playQueueModel playQueueItemAtIndex:_playQueueController.currentPlayQueueIndex];
    NSUInteger row=[_visibleItems indexOfObjectPassingTest:^BOOL(VLCPlayQueueItem *item,NSUInteger index,BOOL *stop){return current && item.uniqueID==current.uniqueID;}];
    if(row!=NSNotFound)[_tableView scrollRowToVisible:row];
}

@end
