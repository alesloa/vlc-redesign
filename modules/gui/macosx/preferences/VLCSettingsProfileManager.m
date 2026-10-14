/* Figma6648:20666 supplies named profiles and New. Names are owner input;
 * configuration names/types/values are original VLC metadata/current/default
 * values. Qt's shared SettingsProfiles JSON lives in its existing preferences
 * domain; NativeFormat stores slash keys as dots. Unknown entry members stay
 * intact. guiMac values are original property-list data encoded without loss. */
#import "VLCSettingsProfileManager.h"
#import "VLCSettingsProfileWindowController.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import "main/VLCApplication.h"
#import "preferences/VLCSimplePrefsController.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import <vlc_configuration.h>
#import <vlc_modules.h>
#import <vlc_plugin.h>
#import <vlc_config_cat.h>
#import <math.h>

NSString * const VLCSettingsProfileChanged=@"VLCSettingsProfileChanged";
static CFStringRef const profileDomain=CFSTR("com.vlc.vlc-qt-interface");
static CFStringRef const profilesKey=CFSTR("SettingsProfiles.items");
static CFStringRef const currentKey=CFSTR("SettingsProfiles.current");
@interface VLCSettingsProfileManager ()
@property VLCSettingsProfileWindowController *profileWindowController;
@end
@implementation VLCSettingsProfileManager
+ (instancetype)sharedInstance { static VLCSettingsProfileManager *manager; static dispatch_once_t once; dispatch_once(&once,^{manager=[self new];}); return manager; }
- (NSMutableArray<NSMutableDictionary *> *)profiles
{
    id value=CFBridgingRelease(CFPreferencesCopyAppValue(profilesKey,profileDomain));
    NSData *data=[value isKindOfClass:NSString.class] ? [value dataUsingEncoding:NSUTF8StringEncoding] : nil;
    id parsed=data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    NSMutableArray *profiles=[NSMutableArray array];
    if([parsed isKindOfClass:NSArray.class]) for(id profile in parsed) if([profile isKindOfClass:NSDictionary.class] && [profile[@"id"] isKindOfClass:NSString.class] && [profile[@"name"] isKindOfClass:NSString.class]) [profiles addObject:[profile mutableCopy]];
    return profiles;
}
- (NSString *)currentID { id value=CFBridgingRelease(CFPreferencesCopyAppValue(currentKey,profileDomain)); return [value isKindOfClass:NSString.class] ? value : @""; }
- (NSString *)currentName { NSString *identifier=self.currentID; for(NSDictionary *profile in self.profiles) if([profile[@"id"] isEqualToString:identifier]) return profile[@"name"]; return _NS("Default"); }
- (BOOL)writeProfiles:(NSArray *)profiles current:(NSString *)identifier applied:(BOOL)applied
{
    NSData *data=[NSJSONSerialization dataWithJSONObject:profiles options:0 error:nil]; if(!data) return NO;
    NSString *json=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    CFPreferencesSetAppValue(profilesKey,(__bridge CFStringRef)json,profileDomain);
    CFPreferencesSetAppValue(currentKey,(__bridge CFStringRef)identifier,profileDomain);
    if (!CFPreferencesAppSynchronize(profileDomain)) return NO;
    [NSNotificationCenter.defaultCenter postNotificationName:VLCSettingsProfileChanged object:self userInfo:@{@"applied":@(applied)}];
    return YES;
}
- (BOOL)isGUIKey:(NSString *)key
{
    // Exact keys from Native's existing interface, toolbar, library, playback,
    // and audio/video effect providers. A future provider's similarly prefixed
    // JSON member stays opaque instead of being erased or applied by this GUI.
    static NSSet *known; static dispatch_once_t once;
    dispatch_once(&once,^{
        NSMutableSet *keys=[NSMutableSet setWithArray:@[
            @"VLCInterfaceAppearance",@"VLCInterfaceAccentColor",@"VLCPlayerToolbarLayout",
            @"VLCUseClassicVideoPlayerLayoutKey",@"VLCDisplayTrackNumberPlayQueueKey",
            @"VLCPlaybackEndViewEnabledKey",@"VLCPlayerShowLyricsKey",@"language",
            @"VLCLibraryBookmarkedLocations",@"VLCLibraryPlayQueueMode",
            @"VLCLibraryCollectionViewItemAdjustmentKey",@"VLCLibrarySplitViewDetailViewWidth",
            @"VLCLibrarySongsTableViewHiddenColumns",@"AudioEffectProfiles",@"AudioEffectProfileNames",
            @"AudioEffectSelectedProfile",@"AudioEffectApplyProfileOnStartup",@"VideoEffectProfiles",
            @"VideoEffectProfileNames",@"VideoEffectSelectedProfile",@"VideoEffectApplyProfileOnStartup",
            @"EQValues",@"EQPreampValues",@"EQTitles",@"EQNames"
        ]];
        for(NSString *partial in @[@"HomeLibraryViewMode",@"FavoritesLibraryViewMode",@"VideoLibraryViewMode",
            @"ShowsLibraryViewMode",@"MoviesLibraryViewMode",@"AlbumLibraryViewMode",@"GenreLibraryViewMode",
            @"SongsLibraryViewMode",@"ArtistLibraryViewMode",@"PlaylistLibraryViewMode",@"MusicOnlyPlaylistLibraryViewMode",
            @"VideoOnlyPlaylistLibraryViewMode",@"BrowseLibraryViewMode",@"StreamLibraryViewMode",
            @"GroupsLibraryViewMode",@"SearchLibraryViewMode",@"RecentLibraryViewMode"])
            [keys addObject:[@"VLCLibraryWindow." stringByAppendingString:partial]];
        known=keys.copy;
    });
    if([known containsObject:key] || [key hasPrefix:@"NSWindow Frame "])return YES;
    return [[NSUserDefaults.standardUserDefaults volatileDomainForName:NSRegistrationDomain] objectForKey:key]!=nil &&
        ([key hasPrefix:@"VLCInterface"] || [key hasPrefix:@"VLCLibrary"] || [key hasPrefix:@"AudioEffect"] || [key hasPrefix:@"VideoEffect"] || [key hasPrefix:@"EQ"]);
}
- (NSDictionary *)configurationSnapshotUsingDefaults:(BOOL)defaults
{
    NSMutableArray *configuration=[NSMutableArray array]; NSMutableSet *names=[NSMutableSet set]; size_t count; module_t **modules=module_list_get(&count);
    for(size_t index=0;index<count;index++) {
        unsigned number; module_config_t *options=module_config_get(modules[index],&number);
        enum vlc_config_subcat subcategory=SUBCAT_UNKNOWN;
        for(unsigned optionIndex=0;optionIndex<number;optionIndex++) {
            module_config_t *option=&options[optionIndex];
            if(option->i_type==CONFIG_SUBCATEGORY){subcategory=option->value.i;continue;}
            enum vlc_config_cat category=vlc_config_cat_FromSubcat(subcategory);
            if(category==CAT_HIDDEN || category==CAT_UNKNOWN || !CONFIG_ITEM(option->i_type) || !option->psz_name || !option->psz_text) continue;
            NSString *name=toNSStr(option->psz_name); if([names containsObject:name]) continue;
            // Several modules reuse a name with differing declaration types.
            // The config API reads the canonical descriptor, so use that exact
            // type/default/range for snapshots and validation as well.
            option=config_FindConfig(option->psz_name); if(!option) continue; [names addObject:name];
            id value;
            if(IsConfigStringType(option->i_type)) {
                char *current=defaults ? NULL : config_GetPsz(option->psz_name); const char *string=defaults ? option->orig.psz : current;
                value=string ? toNSStr(string) : NSNull.null; free(current);
            } else if(IsConfigFloatType(option->i_type)) value=[NSString stringWithFormat:@"%.9g",defaults ? option->orig.f : config_GetFloat(option->psz_name)];
            else value=[NSString stringWithFormat:@"%lld",(long long)(defaults ? option->orig.i : config_GetInt(option->psz_name))];
            [configuration addObject:@{@"name":name,@"type":@(option->i_type),@"value":value}];
        }
        module_config_free(options);
    }
    module_list_free(modules);
    NSMutableDictionary *values=[(defaults ? [NSUserDefaults.standardUserDefaults volatileDomainForName:NSRegistrationDomain] : NSUserDefaults.standardUserDefaults.dictionaryRepresentation) mutableCopy];
    // Appearance is previewed live by the existing Preferences transaction.
    // New/Save captures its original committed values until that transaction saves.
    if(!defaults && self.preferenceAppearanceBaseline)[values addEntriesFromDictionary:self.preferenceAppearanceBaseline];
    NSMutableDictionary *gui=[NSMutableDictionary dictionary];
    for(NSString *key in values) if([self isGUIKey:key]) { NSData *data=[NSPropertyListSerialization dataWithPropertyList:@{@"value":values[key]} format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil]; if(data) gui[key]=[data base64EncodedStringWithOptions:0]; }
    return @{@"configuration":configuration,@"guiMac":gui};
}
- (nullable id)validatedValue:(id)value forOption:(module_config_t *)option
{
    if(IsConfigStringType(option->i_type)) return [value isKindOfClass:NSString.class] || value==NSNull.null ? value : nil;
    if(![value isKindOfClass:NSString.class]) return nil;
    NSScanner *scanner=[NSScanner scannerWithString:value];
    if(IsConfigFloatType(option->i_type)) { double number; if(![scanner scanDouble:&number] || !scanner.isAtEnd || !isfinite(number) || !isfinite((float)number)) return nil; if(option->min.f!=option->max.f && (number<option->min.f || number>option->max.f)) return nil; return @(number); }
    long long number; if(![scanner scanLongLong:&number] || !scanner.isAtEnd) return nil;
    if(option->i_type==CONFIG_ITEM_BOOL && number!=0 && number!=1) return nil;
    if(option->min.i!=option->max.i && (number<option->min.i || number>option->max.i)) return nil;
    return @(number);
}
- (BOOL)applySnapshot:(NSDictionary *)snapshot
{
    return [self applySnapshot:snapshot beforeWriting:nil];
}
- (BOOL)applySnapshot:(NSDictionary *)snapshot beforeWriting:(void (^)(void))beforeWriting
{
    id configuration=snapshot[@"configuration"]; if(![configuration isKindOfClass:NSArray.class]) return NO;
    NSMutableSet *browsable=[NSMutableSet set];
    for(NSDictionary *entry in [self configurationSnapshotUsingDefaults:NO][@"configuration"]) [browsable addObject:entry[@"name"]];
    NSMutableArray *validated=[NSMutableArray array];
    for(id entry in configuration) {
        if(![entry isKindOfClass:NSDictionary.class] || ![entry[@"name"] isKindOfClass:NSString.class] || ![entry[@"type"] isKindOfClass:NSNumber.class]) return NO;
        module_config_t *option=config_FindConfig([entry[@"name"] UTF8String]); if(!option) continue; // Preserve options from another platform/provider in the stored JSON.
        // Original preferences omit hidden volatile launch flags. In particular,
        // a profile must not replace the config-file path before saving itself.
        if(![browsable containsObject:entry[@"name"]]) continue;
        if(option->i_type!=[entry[@"type"] intValue]) return NO;
        id value=[self validatedValue:entry[@"value"] forOption:option]; if(!value) return NO;
        [validated addObject:@{@"option":[NSValue valueWithPointer:option],@"value":value}];
    }
    // Validate the entire GUI envelope before changing either configuration
    // store. A damaged known-platform value must not partially apply a profile.
    NSMutableDictionary *guiValues=[NSMutableDictionary dictionary];
    id gui=snapshot[@"guiMac"];
    if (gui && ![gui isKindOfClass:NSDictionary.class]) return NO;
    for(id key in gui) {
        if(![key isKindOfClass:NSString.class]) return NO;
        if(![self isGUIKey:key]) continue;
        if(![gui[key] isKindOfClass:NSString.class]) return NO;
        NSData *data=[[NSData alloc] initWithBase64EncodedString:gui[key] options:0];
        id envelope=data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil] : nil;
        if(![envelope isKindOfClass:NSDictionary.class] || !envelope[@"value"]) return NO;
        id expected=[NSUserDefaults.standardUserDefaults objectForKey:key], value=envelope[@"value"];
        for(Class type in @[NSString.class,NSNumber.class,NSArray.class,NSDictionary.class,NSData.class,NSDate.class])
            if([expected isKindOfClass:type] && ![value isKindOfClass:type])return NO;
        if([key isEqualToString:@"VLCPlayerToolbarLayout"] && ![value isKindOfClass:NSArray.class])return NO;
        guiValues[key]=envelope[@"value"];
    }
    if(beforeWriting)beforeWriting();
    for(NSDictionary *entry in validated) {
        module_config_t *option=[entry[@"option"] pointerValue]; id value=entry[@"value"];
        if(IsConfigStringType(option->i_type)) config_PutPsz(option->psz_name,value==NSNull.null ? NULL : [value UTF8String]);
        else if(IsConfigFloatType(option->i_type)) config_PutFloat(option->psz_name,[value floatValue]);
        else config_PutInt(option->psz_name,[value longLongValue]);
    }
    if(gui) {
        // Optional layout keys that are absent in this snapshot must fall back
        // to their original registered defaults when switching profiles.
        for(NSString *key in NSUserDefaults.standardUserDefaults.dictionaryRepresentation)
            if([self isGUIKey:key] && !guiValues[key])[NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        for(NSString *key in guiValues) [NSUserDefaults.standardUserDefaults setObject:guiValues[key] forKey:key];
    }
    return YES;
}
- (NSString *)reviewTextForSnapshot:(NSDictionary *)snapshot resetGUI:(BOOL)resetGUI
{
    // Captions come from original descriptors; both values are current API or
    // saved owner values. Unknown cross-platform options are retained on disk,
    // omitted from this platform's review and never written to its config.
    NSDictionary *current=[self configurationSnapshotUsingDefaults:NO];
    NSMutableDictionary *oldValues=[NSMutableDictionary dictionary];
    for(NSDictionary *entry in current[@"configuration"]) oldValues[entry[@"name"]]=entry[@"value"];
    NSMutableArray *changes=[NSMutableArray array];
    for(NSDictionary *entry in snapshot[@"configuration"]) {
        NSString *name=entry[@"name"]; if(![name isKindOfClass:NSString.class]) continue;
        module_config_t *option=config_FindConfig(name.UTF8String); if(!option || !option->psz_text || option->i_type!=[entry[@"type"] intValue]) continue;
        if(!oldValues[name]) continue;
        id value=entry[@"value"],old=oldValues[name]; if([old isEqual:value]) continue;
        // Match the original secure preference control: identify the changed
        // password setting without exposing either secret in the review.
        if(option->i_type==CONFIG_ITEM_PASSWORD) { [changes addObject:_NS(option->psz_text)]; continue; }
        [changes addObject:[NSString stringWithFormat:@"%@\n%@  →  %@",_NS(option->psz_text),old==NSNull.null ? @"" : [old description],value==NSNull.null ? @"" : [value description]]];
    }
    NSDictionary *oldGUI=current[@"guiMac"],*newGUI=snapshot[@"guiMac"];
    NSMutableSet *keys=[NSMutableSet setWithArray:newGUI.allKeys ?: @[]]; if(resetGUI) [keys addObjectsFromArray:oldGUI.allKeys];
    for(NSString *key in [[keys allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if(![self isGUIKey:key] || [oldGUI[key] isEqual:newGUI[key]]) continue;
        NSMutableArray *values=[NSMutableArray array];
        for(id encoded in @[oldGUI[key] ?: NSNull.null,newGUI[key] ?: NSNull.null]) {
            NSData *data=[encoded isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
            NSDictionary *envelope=data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil] : nil;
            [values addObject:[envelope[@"value"] description] ?: @""];
        }
        [changes addObject:[NSString stringWithFormat:@"%@\n%@  →  %@",key,values[0],values[1]]];
    }
    return [changes componentsJoinedByString:@"\n\n"];
}
- (BOOL)reviewSnapshot:(NSDictionary *)snapshot name:(NSString *)name resetGUI:(BOOL)resetGUI
{
    if (![snapshot isKindOfClass:NSDictionary.class] ||
        ![name isKindOfClass:NSString.class] || name.length == 0)
        return NO;
    NSAlert *alert=[NSAlert new]; alert.messageText=name; alert.informativeText=_NS("Preferences");
    [alert addButtonWithTitle:_NS("Apply")]; [alert addButtonWithTitle:_NS("Cancel")];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,640,360)]; scroll.hasVerticalScroller=YES;
    NSTextView *text=[[NSTextView alloc] initWithFrame:scroll.bounds]; text.editable=NO; text.selectable=YES;
    text.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular]; text.textColor=NSColor.VLCPrimaryForegroundColor; text.backgroundColor=NSColor.VLCInputBackgroundColor;
    text.string=[self reviewTextForSnapshot:snapshot resetGUI:resetGUI]; text.textContainerInset=NSMakeSize(12,12);
    text.autoresizingMask=NSViewWidthSizable; text.verticallyResizable=YES; text.horizontallyResizable=NO;
    text.textContainer.widthTracksTextView=YES; scroll.documentView=text; alert.accessoryView=scroll;
    [alert.window.contentView vlc_applyRedesignStyle];
    return [alert runModal]==NSAlertFirstButtonReturn;
}
- (void)applyProfile:(NSMenuItem *)sender
{
    NSMutableArray *profiles=self.profiles; NSDictionary *selected=sender.representedObject;
    if (![selected isKindOfClass:NSDictionary.class] ||
        ![selected[@"id"] isKindOfClass:NSString.class])
        return;
    if(![self reviewSnapshot:selected name:selected[@"name"] resetGUI:NO]) return;
    if(![self applySnapshot:selected beforeWriting:^{[self cancelOlderPreferenceTransaction];}]) return;
    config_SaveConfigFile(getIntf()); [self refreshGUI]; [self writeProfiles:profiles current:selected[@"id"] applied:YES];
}
- (void)refreshGUI
{
    [(VLCApplication *)NSApp applyInterfaceAppearance];
    [NSNotificationCenter.defaultCenter postNotificationName:@"VLCPlayerToolbarLayoutChanged" object:self];
    [NSNotificationCenter.defaultCenter postNotificationName:@"VLCLibraryBookmarkedLocationsChanged" object:self];
}
- (void)cancelOlderPreferenceTransaction
{
    VLCSimplePrefsController *preferences=VLCMain.sharedInstance.simplePreferences;
    if(preferences.window.visible)[preferences buttonAction:preferences.cancelButton];
    self.preferenceAppearanceBaseline=nil;
}
- (void)applyDefaults:(id)sender
{
    NSDictionary *snapshot=[self configurationSnapshotUsingDefaults:YES];
    if(![self reviewSnapshot:snapshot name:_NS("Default") resetGUI:YES] || ![self applySnapshot:snapshot beforeWriting:^{[self cancelOlderPreferenceTransaction];}]) return;
    for(NSString *key in NSUserDefaults.standardUserDefaults.dictionaryRepresentation) if([self isGUIKey:key]) [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    config_SaveConfigFile(getIntf()); [self refreshGUI]; [self writeProfiles:self.profiles current:@"" applied:YES];
}
- (void)newProfile:(id)sender
{
    NSAlert *alert=[NSAlert new]; alert.messageText=_NS("Duplicate current profile for a new profile"); alert.informativeText=_NS("Enter a name for the new profile:");
    NSButton *save=[alert addButtonWithTitle:_NS("Save")]; save.enabled=NO; [alert addButtonWithTitle:_NS("Cancel")];
    NSTextField *name=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,320,36)]; alert.accessoryView=name; alert.window.initialFirstResponder=name;
    id observer=[NSNotificationCenter.defaultCenter addObserverForName:NSControlTextDidChangeNotification object:name queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){save.enabled=[name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length>0;}];
    NSModalResponse response=[alert runModal]; [NSNotificationCenter.defaultCenter removeObserver:observer]; if(response!=NSAlertFirstButtonReturn) return;
    NSString *title=[name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!title.length) return;
    NSMutableArray *profiles=self.profiles; for(NSDictionary *profile in profiles) if([profile[@"name"] isEqualToString:title]) {NSAlert *duplicate=[NSAlert new]; duplicate.messageText=_NS("Please enter a unique name for the new profile."); duplicate.informativeText=_NS("Multiple profiles with the same name are not allowed."); [duplicate addButtonWithTitle:_NS("OK")]; [duplicate runModal]; return;}
    NSMutableDictionary *snapshot=[[self configurationSnapshotUsingDefaults:NO] mutableCopy]; snapshot[@"name"]=title; snapshot[@"id"]=NSUUID.UUID.UUIDString; [profiles addObject:snapshot]; [self writeProfiles:profiles current:snapshot[@"id"] applied:NO];
}
- (void)saveCurrent:(id)sender
{
    NSMutableArray *profiles=self.profiles; NSString *identifier=self.currentID;
    for(NSMutableDictionary *profile in profiles) if([profile[@"id"] isEqualToString:identifier]) {
        [profile addEntriesFromDictionary:[self profile:profile updatingWithSnapshot:[self configurationSnapshotUsingDefaults:NO]]];
        [self writeProfiles:profiles current:identifier applied:NO]; return;
    }
}
- (NSDictionary *)profile:(NSDictionary *)profile updatingWithSnapshot:(NSDictionary *)snapshot
{
    // A profile can contain installed options from another OS/provider. Merge
    // refreshed canonical values by exact key, preserving absent-platform data
    // and unknown JSON members for the frontend that owns them.
    NSMutableDictionary *updated=[profile mutableCopy]; NSMutableDictionary *byName=[NSMutableDictionary dictionary];
    for(id entry in [profile[@"configuration"] isKindOfClass:NSArray.class] ? profile[@"configuration"] : @[])
        if([entry isKindOfClass:NSDictionary.class] && [entry[@"name"] isKindOfClass:NSString.class]) byName[entry[@"name"]]=entry;
    for(NSDictionary *entry in snapshot[@"configuration"]) byName[entry[@"name"]]=entry;
    updated[@"configuration"]=[byName.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] compare:b[@"name"]];}];
    NSMutableDictionary *gui=[profile[@"guiMac"] isKindOfClass:NSDictionary.class] ? [profile[@"guiMac"] mutableCopy] : [NSMutableDictionary dictionary];
    for(NSString *key in [gui.allKeys copy]) if([self isGUIKey:key]) [gui removeObjectForKey:key];
    [gui addEntriesFromDictionary:snapshot[@"guiMac"] ?: @{}]; updated[@"guiMac"]=gui;
    return updated;
}
- (void)saveActiveProfile { [self saveCurrent:nil]; }
- (void)showProfiles:(id)sender
{
    if(!self.profileWindowController.window.visible)self.profileWindowController=[VLCSettingsProfileWindowController new];
    [self.profileWindowController showWindow:sender];
    [self.profileWindowController.window makeKeyAndOrderFront:sender];
}
- (void)deleteCurrent:(id)sender
{
    NSMutableArray *profiles=self.profiles; NSString *identifier=self.currentID;
    NSIndexSet *indices=[profiles indexesOfObjectsPassingTest:^BOOL(NSDictionary *profile,NSUInteger index,BOOL *stop){return [profile[@"id"] isEqualToString:identifier];}];
    [profiles removeObjectsAtIndexes:indices]; [self writeProfiles:profiles current:@"" applied:NO];
}
- (NSMenu *)menu
{
    NSMenu *menu=[[NSMenu alloc] init]; NSString *identifier=self.currentID;
    NSMenuItem *defaults=[[NSMenuItem alloc] initWithTitle:_NS("Default") action:@selector(applyDefaults:) keyEquivalent:@""]; defaults.target=self; defaults.state=identifier.length ? NSControlStateValueOff : NSControlStateValueOn; [menu addItem:defaults];
    for(NSDictionary *profile in self.profiles) {NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:profile[@"name"] action:@selector(applyProfile:) keyEquivalent:@""]; item.target=self; item.representedObject=profile; item.state=[profile[@"id"] isEqualToString:identifier] ? NSControlStateValueOn : NSControlStateValueOff; [menu addItem:item];}
    [menu addItem:NSMenuItem.separatorItem]; NSMenuItem *new=[[NSMenuItem alloc] initWithTitle:_NS("New") action:@selector(newProfile:) keyEquivalent:@""]; new.target=self; [menu addItem:new];
    if(identifier.length) for(NSArray *action in @[@[_NS("Save"),NSStringFromSelector(@selector(saveCurrent:))],@[_NS("Delete"),NSStringFromSelector(@selector(deleteCurrent:))]]) {NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:action[0] action:NSSelectorFromString(action[1]) keyEquivalent:@""]; item.target=self; [menu addItem:item];}
    return menu;
}
@end
