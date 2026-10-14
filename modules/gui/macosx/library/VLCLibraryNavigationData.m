#import "VLCLibraryNavigationData.h"
#import "library/VLCLibraryController.h"
#import "library/VLCLibraryModel.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#include <math.h>

static BOOL navigationInterfaceIsUnavailable(void)
{
    VLCMain *existingOwner = VLCMain.sharedInstance;
    return existingOwner == nil || existingOwner.isTerminating;
}

NSString * const VLCLibraryNavigationDataChanged = @"VLCLibraryNavigationDataChanged";
static CFStringRef const navigationDomain = CFSTR("com.vlc.vlc-qt-interface");
static CFStringRef const pinsKey = CFSTR("MediaLibrary.Pins");
static CFStringRef const visitsKey = CFSTR("MediaLibrary.CollectionVisits");

static VLCMediaLibraryArtist *navigationArtistWithID(int64_t identifier)
{
    VLCMain *existingOwner = VLCMain.sharedInstance;
    if (existingOwner == nil || existingOwner.isTerminating) return nil;
    vlc_medialibrary_t *library = getMediaLibrary();
    if (library == NULL) return nil;
    vlc_ml_artist_t *source = vlc_ml_get_artist(library, identifier);
    if (source == NULL) return nil;
    VLCMediaLibraryArtist *artist = [[VLCMediaLibraryArtist alloc] initWithArtist:source];
    vlc_ml_artist_release(source);
    return artist;
}

@interface VLCLibraryNavigationData ()
@property dispatch_queue_t workQueue;
@end

@implementation VLCLibraryNavigationData
+ (instancetype)sharedInstance
{
    static VLCLibraryNavigationData *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [self new]; });
    return instance;
}
- (instancetype)init
{
    self = [super init];
    if (self) _workQueue = dispatch_queue_create("org.videolan.vlc.library-navigation", DISPATCH_QUEUE_SERIAL);
    return self;
}
+ (id)representedItem:(id)item { return [item isKindOfClass:NSDictionary.class] ? item[@"item"] : item; }
+ (NSString *)titleForItem:(id)item
{
    if ([item isKindOfClass:NSDictionary.class]) return item[@"title"] ?: @"";
    id represented = [self representedItem:item];
    return [represented isKindOfClass:NSURL.class] ? [represented lastPathComponent] : [represented displayString] ?: @"";
}
+ (NSString *)serializedIDForItem:(id)item
{
    if ([item isKindOfClass:NSDictionary.class]) return item[@"serialized"];
    NSString *type = nil;
    if ([item isKindOfClass:VLCMediaLibraryPlaylist.class]) type = @"VLC_ML_PARENT_PLAYLIST";
    else if ([item isKindOfClass:VLCMediaLibraryArtist.class]) type = @"VLC_ML_PARENT_ARTIST";
    else if ([item isKindOfClass:VLCMediaLibraryAlbum.class]) type = @"VLC_ML_PARENT_ALBUM";
    else if ([item isKindOfClass:VLCMediaLibraryGenre.class]) type = @"VLC_ML_PARENT_GENRE";
    else if ([item isKindOfClass:VLCMediaLibraryGroup.class]) type = @"VLC_ML_PARENT_GROUP";
    else if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) type = @"UNKNOWN";
    if (type == nil || [item libraryID] <= 0) return nil;
    return [NSString stringWithFormat:@"%@ - %lld", type, [item libraryID]];
}
- (id)readJSON:(CFStringRef)key expectedClass:(Class)expectedClass
{
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(key, navigationDomain));
    if ([value isKindOfClass:NSString.class]) value = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    return [value isKindOfClass:expectedClass] ? value : nil;
}
- (void)writeJSON:(id)value key:(CFStringRef)key
{
    if (navigationInterfaceIsUnavailable()) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (data == nil) return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    CFPreferencesSetAppValue(key, (__bridge CFStringRef)json, navigationDomain);
    if (CFPreferencesAppSynchronize(navigationDomain))
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!navigationInterfaceIsUnavailable())
                [NSNotificationCenter.defaultCenter postNotificationName:VLCLibraryNavigationDataChanged object:self];
        });
}
- (NSDictionary *)entryForSerialized:(NSString *)serialized
{
    VLCMain *existingOwner = VLCMain.sharedInstance;
    if (existingOwner == nil || existingOwner.isTerminating) return nil;
    if (![serialized isKindOfClass:NSString.class]) return nil;
    NSArray *parts = [serialized componentsSeparatedByString:@" - "];
    if (parts.count != 2) return nil;
    NSScanner *scanner = [NSScanner scannerWithString:parts[1]];
    long long identifier;
    if (![scanner scanLongLong:&identifier] || !scanner.isAtEnd || identifier <= 0) return nil;
    NSString *type = parts[0], *title = nil, *icon = nil;
    id item = nil;
    if ([type isEqualToString:@"VLC_ML_PARENT_FOLDER"]) {
        vlc_medialibrary_t *library = getMediaLibrary();
        if (library == NULL) return nil;
        vlc_ml_folder_t *folder = vlc_ml_get_folder(library, identifier);
        if (folder == NULL) return nil;
        if (folder->b_present && folder->psz_mrl) {
            item = [NSURL URLWithString:toNSStr(folder->psz_mrl)];
            title = folder->psz_name ? toNSStr(folder->psz_name) : [item lastPathComponent];
        }
        vlc_ml_folder_release(folder);
        icon = @"folder";
    } else if ([type isEqualToString:@"VLC_ML_PARENT_PLAYLIST"]) {
        item = [VLCMediaLibraryPlaylist playlistForLibraryID:identifier]; icon = @"playlists";
    } else if ([type isEqualToString:@"VLC_ML_PARENT_ARTIST"]) {
        item = navigationArtistWithID(identifier); icon = @"library-artist";
    } else if ([type isEqualToString:@"VLC_ML_PARENT_ALBUM"]) item = [VLCMediaLibraryAlbum albumWithID:identifier];
    else if ([type isEqualToString:@"VLC_ML_PARENT_GENRE"]) item = [VLCMediaLibraryGenre genreWithID:identifier];
    else if ([type isEqualToString:@"VLC_ML_PARENT_GROUP"]) item = [VLCMediaLibraryGroup groupWithID:identifier];
    else if ([type isEqualToString:@"UNKNOWN"]) item = [VLCMediaLibraryMediaItem mediaItemForLibraryID:identifier];
    if (item == nil) return nil;
    title = title ?: [item displayString];
    if (title.length == 0) return nil;
    return @{@"serialized":serialized, @"item":item, @"title":title, @"icon":icon ?: @"videos"};
}
- (void)loadPinsWithCompletion:(void (^)(NSArray<NSDictionary *> *))completion
{
    dispatch_async(self.workQueue, ^{
        VLCMain *existingOwner = VLCMain.sharedInstance;
        if (existingOwner == nil || existingOwner.isTerminating) return;
        NSMutableArray *entries = [NSMutableArray array];
        if (!navigationInterfaceIsUnavailable() && getMediaLibrary() != NULL)
            for (NSString *serialized in [self readJSON:pinsKey expectedClass:NSArray.class]) {
                NSDictionary *entry = [self entryForSerialized:serialized];
                if (entry) [entries addObject:entry];
            }
        dispatch_async(dispatch_get_main_queue(), ^{ if (!navigationInterfaceIsUnavailable()) completion(entries); });
    });
}
- (NSString *)resolveSerializedIDForItem:(id)item
{
    VLCMain *existingOwner = VLCMain.sharedInstance;
    if (existingOwner == nil || existingOwner.isTerminating) return nil;
    NSString *serialized = [self.class serializedIDForItem:item];
    if (serialized) return serialized;
    NSURL *url = [self.class representedItem:item];
    if (![url isKindOfClass:NSURL.class]) return nil;
    vlc_medialibrary_t *library = getMediaLibrary();
    if (library == NULL) return nil;
    vlc_ml_folder_list_t *folders = vlc_ml_list_folders(library, NULL);
    if (folders == NULL) return nil;
    for (size_t index = 0; index < folders->i_nb_items; ++index) {
        const vlc_ml_folder_t *folder = &folders->p_items[index];
        if (folder->psz_mrl && [[NSURL URLWithString:toNSStr(folder->psz_mrl)] isEqual:url]) {
            serialized = [NSString stringWithFormat:@"VLC_ML_PARENT_FOLDER - %lld", folder->i_id];
            break;
        }
    }
    vlc_ml_folder_list_release(folders);
    return serialized;
}
- (BOOL)isPinnedItem:(id)item
{
    NSString *serialized = [self.class serializedIDForItem:item];
    return serialized != nil && [[self readJSON:pinsKey expectedClass:NSArray.class] containsObject:serialized];
}
- (void)togglePinForItem:(id)item
{
    [self setPinned:![self isPinnedItem:item] forItem:item];
}
- (void)setPinned:(BOOL)pinned forItem:(id)item
{
    dispatch_async(self.workQueue, ^{
        if (navigationInterfaceIsUnavailable()) return;
        NSString *serialized = [self resolveSerializedIDForItem:item];
        if (serialized == nil) return;
        NSMutableArray *pins = [[self readJSON:pinsKey expectedClass:NSArray.class] mutableCopy] ?: [NSMutableArray array];
        if (!pinned) [pins removeObject:serialized]; else if (![pins containsObject:serialized]) [pins addObject:serialized];
        [self writeJSON:pins key:pinsKey];
    });
}
- (void)recordVisitToItem:(id)item
{
    dispatch_async(self.workQueue, ^{
        if (navigationInterfaceIsUnavailable()) return;
        NSString *serialized = [self resolveSerializedIDForItem:item];
        if (![serialized hasPrefix:@"VLC_ML_PARENT_FOLDER"] && ![serialized hasPrefix:@"VLC_ML_PARENT_PLAYLIST"]) return;
        NSMutableDictionary *visits = [[self readJSON:visitsKey expectedClass:NSDictionary.class] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSMutableDictionary *previous = [visits[serialized] isKindOfClass:NSDictionary.class] ? [visits[serialized] mutableCopy] : [NSMutableDictionary dictionary];
        double count = [previous[@"count"] respondsToSelector:@selector(doubleValue)] ? [previous[@"count"] doubleValue] : 0;
        if (!isfinite(count)) count = 0;
        previous[@"count"] = @(MIN(9007199254740991., MAX(0., floor(count)) + 1.));
        previous[@"lastVisit"] = @(floor(NSDate.date.timeIntervalSince1970 * 1000.));
        visits[serialized] = previous;
        [self writeJSON:visits key:visitsKey];
    });
}
- (void)loadHomeWithCompletion:(void (^)(NSArray<NSDictionary *> *))completion
{
    if (navigationInterfaceIsUnavailable()) return;
    VLCLibraryModel *model = VLCMain.sharedInstance.libraryController.libraryModel;
    NSArray *videos = model.listOfRecentMedia ?: @[], *audio = model.listOfRecentAudioMedia ?: @[];
    NSArray *allAudio = model.listOfAudioMedia ?: @[];
    dispatch_async(self.workQueue, ^{
        if (navigationInterfaceIsUnavailable()) return;
        NSMutableArray *folders = [NSMutableArray array], *playlists = [NSMutableArray array], *artists = [NSMutableArray array], *streams = [NSMutableArray array];
        NSMutableDictionary *visits = [NSMutableDictionary dictionary];
        NSDictionary *savedVisits = [self readJSON:visitsKey expectedClass:NSDictionary.class] ?: @{};
        for (NSString *key in savedVisits) {
            id value = savedVisits[key];
            if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSDictionary.class] &&
                [value[@"count"] isKindOfClass:NSNumber.class] && isfinite([value[@"count"] doubleValue]) && [value[@"count"] doubleValue] > 0)
                visits[key] = value;
        }
        NSArray *ordered = [visits.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            double first = [visits[a][@"count"] doubleValue], second = [visits[b][@"count"] doubleValue];
            if (first != second) return first > second ? NSOrderedAscending : NSOrderedDescending;
            double lastFirst = [visits[a][@"lastVisit"] respondsToSelector:@selector(doubleValue)] ? [visits[a][@"lastVisit"] doubleValue] : 0;
            double lastSecond = [visits[b][@"lastVisit"] respondsToSelector:@selector(doubleValue)] ? [visits[b][@"lastVisit"] doubleValue] : 0;
            return lastFirst > lastSecond ? NSOrderedAscending : lastFirst < lastSecond ? NSOrderedDescending : [a compare:b];
        }];
        for (NSString *serialized in ordered) {
            if (![visits[serialized] isKindOfClass:NSDictionary.class] || [visits[serialized][@"count"] doubleValue] <= 0) continue;
            NSMutableArray *target = [serialized hasPrefix:@"VLC_ML_PARENT_FOLDER"] ? folders : [serialized hasPrefix:@"VLC_ML_PARENT_PLAYLIST"] ? playlists : nil;
            NSDictionary *entry = target ? [self entryForSerialized:serialized] : nil;
            if (entry) [target addObject:entry];
        }
        NSMutableDictionary<NSNumber *, NSNumber *> *counts = [NSMutableDictionary dictionary];
        for (VLCMediaLibraryMediaItem *item in allAudio)
            if (item.artistID > 0 && item.playCount > 0) counts[@(item.artistID)] = @([counts[@(item.artistID)] unsignedLongLongValue] + item.playCount);
        NSArray *artistIDs = [counts.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            NSComparisonResult order = [counts[b] compare:counts[a]]; return order == NSOrderedSame ? [a compare:b] : order;
        }];
        for (NSNumber *identifier in artistIDs) {
            VLCMediaLibraryArtist *artist = navigationArtistWithID(identifier.longLongValue);
            if (artist) [artists addObject:artist];
        }
        NSMutableArray *recentVideos = [NSMutableArray array], *recentAudio = [NSMutableArray array];
        for (NSArray *items in @[videos, audio]) for (VLCMediaLibraryMediaItem *item in items) {
            BOOL network = NO;
            for (VLCMediaLibraryFile *file in item.files) if (file.fileType == VLC_ML_FILE_TYPE_MAIN && ![NSURL URLWithString:file.MRL].isFileURL) network = YES;
            if (network) [streams addObject:item];
            else if (item.mediaType == VLC_ML_MEDIA_TYPE_VIDEO) [recentVideos addObject:item];
            else if (item.mediaType == VLC_ML_MEDIA_TYPE_AUDIO) [recentAudio addObject:item];
        }
        // Section labels come from Figma Home 1106:5633 / 6261:15078; every
        // row beneath them comes from the original ML records or actual visits.
        NSMutableArray *sections = [NSMutableArray array];
        NSArray *titles = @[_NS("Continue Watching"), _NS("Listen Again"), _NS("Frequently Visited Folders"), _NS("Frequently Visited Playlists"), _NS("Frequently Listened Artists"), _NS("Latest Streams")];
        NSArray *items = @[recentVideos, recentAudio, folders, playlists, artists, streams];
        NSArray *icons = @[@"videos", @"music", @"folder", @"playlists", @"library-artist", @"network"];
        for (NSUInteger index = 0; index < items.count; ++index)
            if ([items[index] count]) [sections addObject:@{@"title":titles[index], @"items":items[index], @"icon":icons[index]}];
        dispatch_async(dispatch_get_main_queue(), ^{ if (!navigationInterfaceIsUnavailable()) completion(sections); });
    });
}
@end
