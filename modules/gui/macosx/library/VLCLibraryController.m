/*****************************************************************************
 * VLCLibraryController.m: MacOS X interface module
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

#import "VLCLibraryController.h"

#import "extensions/NSString+Helpers.h"

#import "main/VLCMain.h"

#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"

#import "library/VLCInputItem.h"
#import "library/VLCLibraryModel.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibraryMediaCollectionController.h"
#import "library/VLCMediaLibraryFolderObserver.h"

#import "playqueue/VLCPlayQueueItem.h"
#import "playqueue/VLCPlayQueueModel.h"

#import <vlc_media_library.h>
#import <vlc_modules.h>

typedef int (*folder_action_f)(vlc_medialibrary_t*, const char*);

@interface VLCLibraryController()
{
    vlc_medialibrary_t *_p_libraryInstance;
}
@end

@implementation VLCLibraryController

- (instancetype)init
{
    self = [super init];
    if (self) {
        if (self.shouldUseMediaLibrary) {
            _p_libraryInstance = vlc_ml_instance_get(getIntf());
        } else {
            return self;
        }

        if (!_p_libraryInstance && self.shouldUseMediaLibrary) {
            msg_Info(getIntf(), "VLC runs without media library support");

            NSUserDefaults * const defaults = NSUserDefaults.standardUserDefaults;
            NSString * const suppressKey = @"VLCSuppressMediaLibraryFailedAlert";
            if (![defaults boolForKey:suppressKey]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSAlert * const alert = [[NSAlert alloc] init];
                    alert.messageText = _NS("Media Library Unavailable");
                    alert.informativeText = _NS("The media library module could not be loaded. "
                                                "Library features such as browsing your media "
                                                "collection will not be available.");
                    alert.alertStyle = NSAlertStyleWarning;
                    [alert addButtonWithTitle:_NS("OK")];
                    alert.showsSuppressionButton = YES;
                    alert.suppressionButton.title = _NS("Do not show this message again");
                    [alert runModal];
                    if (alert.suppressionButton.state == NSControlStateValueOn) {
                        [defaults setBool:YES forKey:suppressKey];
                    }
                });
            }

            return self;
        }

        // Reset suppression so the alert reappears if a future load fails.
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"VLCSuppressMediaLibraryFailedAlert"];
        _libraryModel = [[VLCLibraryModel alloc] initWithLibrary:_p_libraryInstance];
        _unsorted = YES;

        NSNotificationCenter *defaultNotificationCenter = NSNotificationCenter.defaultCenter;
        [defaultNotificationCenter addObserver:self
                                      selector:@selector(playbackStateChanged:)
                                          name:VLCPlayerStateChanged
                                        object:nil];
        [defaultNotificationCenter addObserver:self
                                      selector:@selector(monitoredFolderChanged:)
                                          name:VLCMediaLibraryFolderFSEvent
                                        object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    _p_libraryInstance = NULL;
}

- (void)playbackStateChanged:(NSNotification *)aNotification
{
    if (!_p_libraryInstance) {
        return;
    }
    VLCPlayerController *playerController = aNotification.object;
    if (playerController.playerState == VLC_PLAYER_STATE_PLAYING) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
            vlc_ml_pause_background(self->_p_libraryInstance);
        });
    } else {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
            vlc_ml_resume_background(self->_p_libraryInstance);
        });
    }
}

- (void)monitoredFolderChanged:(NSNotification *)notification
{
    NSURL * const folderURL = (NSURL *)notification.object;
    [self reloadFolderWithFileURL:folderURL];
}

- (int)appendItemToPlayQueue:(VLCMediaLibraryMediaItem *)mediaItem playImmediately:(BOOL)playImmediately
{
    if (!_p_libraryInstance) {
        return VLC_EACCES;
    }
    input_item_t *p_inputItem = VLCMediaLibraryInputItemWithStoredTracks(_p_libraryInstance, mediaItem.libraryID);
    if (!p_inputItem) {
        msg_Err(getIntf(), "No input item found for media id %lli", mediaItem.libraryID);
        return VLC_ENOENT;
    }
    int ret = [VLCMain.sharedInstance.playQueueController addInputItem:p_inputItem atPosition:-1 startPlayback:playImmediately];
    input_item_Release(p_inputItem);
    return ret;
}

- (int)appendItemsToPlayQueue:(NSArray <VLCMediaLibraryMediaItem *> *)mediaItemArray playFirstItemImmediately:(BOOL)playFirstItemImmediately
{
    if (!_p_libraryInstance) {
        return VLC_EACCES;
    }

    NSUInteger itemCount = [mediaItemArray count];
    int ret = VLC_SUCCESS;
    for (NSUInteger x = 0; x < itemCount; x++) {
        if (unlikely(x == 0 && playFirstItemImmediately)) {
            ret = [self appendItemToPlayQueue:mediaItemArray[x] playImmediately:YES];
        } else {
            ret = [self appendItemToPlayQueue:mediaItemArray[x] playImmediately:NO];
        }
        if (unlikely(ret != VLC_SUCCESS)) {
            break;
        }
    }
    return ret;
}

#pragma mark - folder management

- (int)performFolderAction:(folder_action_f)action withFileUrl:(NSURL *)fileURL
{
    if (!_p_libraryInstance) {
        return VLC_EACCES;
    }
    if (!fileURL) {
        return VLC_EINVAL;
    }

    return action(_p_libraryInstance, fileURL.absoluteString.UTF8String);
}

- (int)addFolderWithFileURL:(NSURL *)fileURL
{
    return [self performFolderAction:vlc_ml_add_folder withFileUrl:fileURL];
}

- (int)banFolderWithFileURL:(NSURL *)fileURL
{
    return [self performFolderAction:vlc_ml_ban_folder withFileUrl:fileURL];
}

- (int)unbanFolderWithFileURL:(NSURL *)fileURL
{
    return [self performFolderAction:vlc_ml_unban_folder withFileUrl:fileURL];
}

- (int)removeFolderWithFileURL:(NSURL *)fileURL
{
    return [self performFolderAction:vlc_ml_remove_folder withFileUrl:fileURL];
}

- (int)reloadFolderWithFileURL:(NSURL *)fileURL
{
    if (!_p_libraryInstance) {
        return VLC_EACCES;
    }
    if (!fileURL) {
        return VLC_EINVAL;
    }
    return vlc_ml_reload_folder(_p_libraryInstance, fileURL.absoluteString.UTF8String);
}

- (void)reloadMediaLibraryFoldersForInputItems:(NSArray<VLCInputItem *> *)inputItems
{
    NSArray<VLCMediaLibraryEntryPoint *> * const entryPoints = self.libraryModel.listOfMonitoredFolders;
    NSMutableSet<NSString *> * const reloadMRLs = NSMutableSet.set;
    NSMutableSet<VLCInputItem *> * const checkedInputItems = NSMutableSet.set;

    for (VLCMediaLibraryEntryPoint * const entryPoint in entryPoints) {
        for (VLCInputItem * const inputItem in inputItems) {
            if ([checkedInputItems containsObject:inputItem]) {
                continue;
            }

            if ([inputItem.decodedMRL hasPrefix:entryPoint.decodedMRL]) {
                [reloadMRLs addObject:entryPoint.MRL];
                [checkedInputItems addObject:inputItem];
                break;
            }
        }
    }

    for (NSString * const entryPointMRL in reloadMRLs) {
        NSURL * const entryPointURL = [NSURL URLWithString:entryPointMRL];
        [self reloadFolderWithFileURL:entryPointURL];
    }
}

- (int)clearHistory
{
    if (!_p_libraryInstance) {
        return VLC_EACCES;
    }
    return vlc_ml_clear_history(_p_libraryInstance, VLC_ML_HISTORY_TYPE_GLOBAL);
}

#pragma mark - Playlist creation

- (void)showCreatePlaylistDialogForPlayQueue
{
    VLCPlayQueueController * const playQueueController = VLCMain.sharedInstance.playQueueController;
    NSArray<VLCPlayQueueItem *> * const items = playQueueController.playQueueModel.playQueueItems;
    [self showCreatePlaylistDialogForPlayQueueItems:items];
}

- (void)showCreatePlaylistDialogForPlayQueueItems:(NSArray<VLCPlayQueueItem *> *)items
{
    NSMutableArray *URLs = [NSMutableArray array];
    for (VLCPlayQueueItem *item in items) if (item.url) [URLs addObject:item.url];
    [self showCreatePlaylistDialogWithURLs:URLs];
}

- (void)showCreatePlaylistDialogForMediaItems:(NSArray<VLCMediaLibraryMediaItem *> *)mediaItems
{
    NSMutableArray *URLs = [NSMutableArray array];
    for (VLCMediaLibraryMediaItem *item in mediaItems) for (VLCMediaLibraryFile *file in item.files)
        if (file.fileType == VLC_ML_FILE_TYPE_MAIN && file.fileURL) { [URLs addObject:file.fileURL]; break; }
    [self showCreatePlaylistDialogWithURLs:URLs];
}

- (void)showCreatePlaylistDialogWithURLs:(NSArray<NSURL *> *)URLs
{
    if (!_p_libraryInstance) return;
    VLCLibraryMediaCollectionController *dialog = [[VLCLibraryMediaCollectionController alloc] initForNetwork:NO initialURLs:URLs];
    while (!VLCMain.sharedInstance.isTerminating && [dialog runModal] == NSModalResponseOK)
        if ([self createPlaylistWithName:dialog.playlistName mediaURLs:dialog.mediaURLs coverURL:dialog.coverURL]) break;
}

- (void)showCollectionResult:(int)result
{
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @(result).stringValue;
    [alert addButtonWithTitle:_NS("OK")]; [alert runModal];
}

- (BOOL)createPlaylistWithName:(NSString *)name mediaURLs:(NSArray<NSURL *> *)URLs coverURL:(NSURL *)coverURL
{
    VLCMain *owner = VLCMain.sharedInstance;
    if (!_p_libraryInstance || !name.length || !owner || owner.isTerminating) return NO;
    NSMutableArray<NSNumber *> *mediaIDs = [NSMutableArray array];
    for (NSURL *url in URLs) {
        // A queue/library selection usually already has an ML identity. The
        // create API rejects that URI; retain its original identity and order.
        __attribute__((objc_precise_lifetime)) NSString *mrlString = url.absoluteString;
        const char *mrl = mrlString.UTF8String;
        vlc_ml_media_t *media = vlc_ml_get_media_by_mrl(_p_libraryInstance, mrl);
        if (!media) {
            int result = vlc_ml_control(_p_libraryInstance,
                url.isFileURL ? VLC_ML_NEW_EXTERNAL_MEDIA : VLC_ML_NEW_STREAM, mrl, &media);
            // A scan can register the same URI between lookup and creation.
            if (!media) media = vlc_ml_get_media_by_mrl(_p_libraryInstance, mrl);
            if (!media && result != VLC_SUCCESS) {
                [self showCollectionResult:result]; return NO;
            }
        }
        if (!media) return NO;
        [mediaIDs addObject:@(media->i_id)]; vlc_ml_media_release(media);
    }
    vlc_ml_playlist_t *playlist = NULL;
    int createResult = vlc_ml_control(_p_libraryInstance, VLC_ML_PLAYLIST_CREATE, name.UTF8String, &playlist);
    if (createResult != VLC_SUCCESS) { [self showCollectionResult:createResult]; return NO; }
    if (!playlist) return NO;
    int64_t playlistID = playlist->i_id; vlc_ml_playlist_release(playlist);
    for (NSNumber *mediaID in mediaIDs) {
        int64_t value = mediaID.longLongValue;
        int result = vlc_ml_playlist_append(_p_libraryInstance, playlistID, &value, 1);
        if (result != VLC_SUCCESS) {
            // Remove only the ID created by this attempted Save. A retry must
            // not leave a partial playlist behind or affect an existing one.
            vlc_ml_playlist_delete(_p_libraryInstance, playlistID);
            // The ML API supplies a result code, without explanatory error copy.
            [self showCollectionResult:result]; return NO;
        }
    }
    if (coverURL.isFileURL) {
        // A GUI preference stores the owner's actual cover URL against the API's
        // real playlist ID. No media-library schema or playback state changes.
        NSString *key = [NSString stringWithFormat:@"VLCRedesignPlaylistCover.%lld", playlistID];
        [NSUserDefaults.standardUserDefaults setObject:coverURL.absoluteString forKey:key];
        VLCMediaLibraryPlaylist *updated = [VLCMediaLibraryPlaylist playlistForLibraryID:playlistID];
        if (updated) [NSNotificationCenter.defaultCenter postNotificationName:VLCLibraryModelPlaylistUpdated object:updated];
    }
    return YES;
}

- (void)showRenamePlaylistDialogForPlaylist:(VLCMediaLibraryPlaylist *)playlist
{
    if (playlist == nil || playlist.readOnly) {
        return;
    }

    NSString * const playlistName = [self runRenamePlaylistDialogForPlaylist:playlist];
    if (!playlistName) {
        return;
    }

    [playlist renameTo:playlistName];
}

- (nullable NSString *)runCreatePlaylistDialog
{
    return [self runPlaylistNameDialogWithTitle:_NS("Create New Playlist")
                                informativeText:_NS("Enter a name for the new playlist:")
                             primaryButtonTitle:_NS("Create")
                                    initialName:nil
                             requireNameChange:NO];
}

- (nullable NSString *)runRenamePlaylistDialogForPlaylist:(VLCMediaLibraryPlaylist *)playlist
{
    return [self runPlaylistNameDialogWithTitle:_NS("Rename playlist")
                                informativeText:_NS("Please enter the new playlist name:")
                             primaryButtonTitle:_NS("Rename")
                                    initialName:playlist.displayString
                             requireNameChange:YES];
}

- (nullable NSString *)runPlaylistNameDialogWithTitle:(NSString *)title
                                      informativeText:(NSString *)informativeText
                                   primaryButtonTitle:(NSString *)primaryButtonTitle
                                          initialName:(nullable NSString *)initialName
                                   requireNameChange:(BOOL)requireNameChange
{
    NSAlert * const alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = informativeText;
    NSButton * const primaryButton = [alert addButtonWithTitle:primaryButtonTitle];
    primaryButton.enabled = NO;
    [alert addButtonWithTitle:_NS("Cancel")];

    NSTextField * const input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = initialName ?: @"";
    input.placeholderString = _NS("Playlist Name");
    alert.accessoryView = input;
    alert.window.initialFirstResponder = input;

    NSCharacterSet * const whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString * const currentName =
        [(initialName ?: @"") stringByTrimmingCharactersInSet:whitespace];
    id observer = [NSNotificationCenter.defaultCenter
        addObserverForName:NSControlTextDidChangeNotification
                   object:input
                    queue:NSOperationQueue.mainQueue
               usingBlock:^(NSNotification * __unused note) {
        NSString * const newName =
            [input.stringValue stringByTrimmingCharactersInSet:whitespace];
        primaryButton.enabled = newName.length > 0 &&
            (!requireNameChange || ![newName isEqualToString:currentName]);
    }];

    const NSModalResponse response = [alert runModal];
    [NSNotificationCenter.defaultCenter removeObserver:observer];

    if (response != NSAlertFirstButtonReturn) {
        return nil;
    }

    NSString * const name = [input.stringValue stringByTrimmingCharactersInSet:whitespace];
    if (name.length == 0 || (requireNameChange && [name isEqualToString:currentName])) {
        return nil;
    }
    return name;
}

- (BOOL)createPlaylistWithName:(NSString *)playlistName fromPlayQueueItems:(NSArray<VLCPlayQueueItem *> *)items
{
    if (!_p_libraryInstance || !playlistName || playlistName.length == 0) {
        return NO;
    }
    
    vlc_ml_playlist_t * const playlist = vlc_ml_playlist_create(_p_libraryInstance, playlistName.UTF8String);
    if (!playlist) {
        msg_Err(getIntf(), "Failed to create playlist with name: %s", playlistName.UTF8String);
        return NO;
    }
    
    const int64_t playlistId = playlist->i_id;
    vlc_ml_playlist_release(playlist);
    
    for (VLCPlayQueueItem * const item in items) {
        VLCMediaLibraryMediaItem * const mediaLibraryItem = item.mediaLibraryItem;
        
        if (!mediaLibraryItem) {
            msg_Warn(getIntf(), "No media library item found for playqueue item with name '%s'", item.title.UTF8String);
            continue;
        }
        
        const int64_t mediaId = mediaLibraryItem.libraryID;
        const int result = vlc_ml_playlist_append(_p_libraryInstance, playlistId, &mediaId, 1);
        if (result != VLC_SUCCESS) {
            msg_Warn(getIntf(), "Failed to add media library item %lld to playlist", mediaLibraryItem.libraryID);
        }
    }
    
    return YES;
}

- (BOOL)createPlaylistWithName:(NSString *)playlistName fromMediaItems:(NSArray<VLCMediaLibraryMediaItem *> *)mediaItems
{
    if (!_p_libraryInstance || !playlistName || playlistName.length == 0) {
        return NO;
    }

    vlc_ml_playlist_t * const playlist = vlc_ml_playlist_create(_p_libraryInstance, playlistName.UTF8String);
    if (!playlist) {
        msg_Err(getIntf(), "Failed to create playlist with name: %s", playlistName.UTF8String);
        return NO;
    }

    const int64_t playlistId = playlist->i_id;
    vlc_ml_playlist_release(playlist);

    VLCMediaLibraryPlaylist * const mlPlaylist =
        [VLCMediaLibraryPlaylist playlistForLibraryID:playlistId];
    [mlPlaylist appendMediaItems:mediaItems];

    return YES;
}

- (void)sortByCriteria:(enum vlc_ml_sorting_criteria_t)sortCriteria andDescending:(bool)descending
{
    _unsorted = NO;
    _lastSortingCriteria = sortCriteria;
    _descendingLibrarySorting = descending;
    [_libraryModel sortByCriteria:sortCriteria andDescending:descending];
}

- (void)filterByString:(NSString*)filterString
{
    self.libraryModel.filterString = filterString;
}

- (BOOL)shouldUseMediaLibrary
{
    return module_exists("medialibrary") && var_InheritBool(getIntf(), "media-library");
}

@end
