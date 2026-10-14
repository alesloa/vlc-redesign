/* Names are owner input; scope is actual ML show membership or media folder;
 * captions are VLC source/transcript; values are existing config/live output.
 * Save has no playback effect. Only explicit Apply calls original APIs. */
#import "VLCPlayerPresetManager.h"
#import "playqueue/VLCPlayerController.h"
#import "preferences/VLCSettingsProfileManager.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "library/VLCInputItem.h"
#import "main/VLCMain.h"
#import <vlc_configuration.h>
#import <vlc_plugin.h>
#import <vlc_modules.h>
#import <vlc_aout.h>
#import <math.h>
#import "../../../../audio_filter/equalizer_presets.h"
static CFStringRef const presetDomain=CFSTR("com.vlc.vlc-qt-interface");
static CFStringRef const presetKey=CFSTR("Player.InterfacePresets");
static NSArray<NSDictionary *> *presetGroups(void)
{
    // Numeric group IDs and keys are the existing Qt GUI schema, kept hidden.
    static NSArray *groups; static dispatch_once_t once; dispatch_once(&once,^{ groups=@[
        @{@"group":@0,@"filter":@"",@"names":@[@"freetype-font",@"sub-text-scale",@"freetype-color",@"freetype-outline-thickness",@"freetype-outline-color",@"sub-margin",@"sub-position",@"secondary-sub-alignment",@"secondary-sub-margin",@"subsdec-encoding",@"sub-language",@"sub-track"]},
        @{@"group":@1,@"filter":@"",@"names":@[@"audio-track",@"audio-language",@"equalizer-preset",@"equalizer-preamp",@"equalizer-bands",@"equalizer-2pass"]},
        @{@"group":@2,@"filter":@"",@"names":@[@"transform-type",@"rotate-angle",@"contrast",@"brightness",@"hue",@"saturation",@"gamma"]},
        @{@"group":@3,@"filter":@"",@"names":@[@"audio-track",@"audio-language"]},
        @{@"group":@4,@"filter":@"equalizer",@"names":@[@"equalizer-preset",@"equalizer-preamp",@"equalizer-bands",@"equalizer-2pass"]},
        @{@"group":@5,@"filter":@"compressor",@"names":@[@"compressor-rms-peak",@"compressor-attack",@"compressor-release",@"compressor-threshold",@"compressor-ratio",@"compressor-knee",@"compressor-makeup-gain"]},
        @{@"group":@6,@"filter":@"spatializer",@"names":@[@"spatializer-roomsize",@"spatializer-width",@"spatializer-wet",@"spatializer-dry",@"spatializer-damp"]},
        @{@"group":@7,@"filter":@"stereowiden",@"names":@[@"stereowiden-delay",@"stereowiden-feedback",@"stereowiden-crossfeed",@"stereowiden-dry-mix"]},
        @{@"group":@8,@"filter":@"scaletempo_pitch",@"names":@[@"pitch-shift"]},
        @{@"group":@9,@"filter":@"adjust",@"names":@[@"hue",@"brightness",@"contrast",@"saturation",@"gamma"]},
        @{@"group":@10,@"filter":@"sharpen",@"names":@[@"sharpen-sigma"]},
        @{@"group":@11,@"filter":@"gradfun",@"names":@[@"gradfun-radius",@"gradfun-strength"]},
        @{@"group":@12,@"filter":@"grain",@"names":@[@"grain-variance",@"grain-period-min",@"grain-period-max"]},
        @{@"group":@13,@"filter":@"croppadd",@"names":@[@"croppadd-croptop",@"croppadd-cropbottom",@"croppadd-cropleft",@"croppadd-cropright"]},
        @{@"group":@14,@"filter":@"extract",@"names":@[@"extract-component"]},
        @{@"group":@15,@"filter":@"colorthres",@"names":@[@"colorthres-color",@"colorthres-saturationthres",@"colorthres-similaritythres"]},
        @{@"group":@16,@"filter":@"invert",@"names":@[]},
        @{@"group":@17,@"filter":@"posterize",@"names":@[@"posterize-level"]},
        @{@"group":@18,@"filter":@"gradient",@"names":@[@"gradient-mode",@"gradient-color",@"gradient-cartoon"]},
        @{@"group":@19,@"filter":@"sepia",@"names":@[@"sepia-intensity"]},
        @{@"group":@20,@"filter":@"transform",@"names":@[@"transform-type"]},
        @{@"group":@21,@"filter":@"rotate",@"names":@[@"rotate-angle",@"rotate-use-motion"]}
    ];}); return groups;
}
static NSArray<NSNumber *> *sectionGroups(NSInteger section)
{ return section==0 ? @[@0] : section==1 ? @[@3,@4,@5,@6,@7,@8] : @[@2,@20,@21,@9,@10,@11,@12,@13,@14,@15,@16,@17,@18,@19]; }
static NSString *updatedFilterChain(NSString *chain,NSString *filter,BOOL enabled)
{
    NSMutableArray *entries=[[chain componentsSeparatedByString:@":"] mutableCopy];
    [entries removeObject:@""]; BOOL found=NO;
    for(NSString *entry in [entries copy]) if([[[entry componentsSeparatedByString:@"{"] firstObject] isEqual:filter]) {found=YES;if(!enabled)[entries removeObject:entry];}
    if(enabled&&!found)[entries addObject:filter]; return [entries componentsJoinedByString:@":"];
}
@interface VLCPlayerPresetManager ()
@property (weak) VLCPlayerController *player;
@property NSInteger section;
@property NSArray<NSDictionary *> *records;
@property NSPopUpButton *choice;
@property NSButton *scopeChoice;
@property NSButton *applyButton;
@property NSButton *deleteButton;
@property NSDictionary *scope;
@end
@implementation VLCPlayerPresetManager
- (instancetype)initWithPlayer:(VLCPlayerController *)player {self=[super init];if(self)_player=player;return self;}
- (NSArray *)allRecords
{
    id value=CFBridgingRelease(CFPreferencesCopyAppValue(presetKey,presetDomain));
    NSData *data=[value isKindOfClass:NSString.class] ? [value dataUsingEncoding:NSUTF8StringEncoding] : nil;
    id parsed=data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    return [parsed isKindOfClass:NSArray.class] ? parsed : @[];
}
- (BOOL)persist:(NSArray *)records
{
    NSData *data=[NSJSONSerialization dataWithJSONObject:records options:0 error:nil];if(!data)return NO;
    CFPreferencesSetAppValue(presetKey,(__bridge CFStringRef)[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding],presetDomain);
    BOOL saved=CFPreferencesAppSynchronize(presetDomain);if(saved)[self reloadChoices];return saved;
}
- (NSDictionary *)currentScope
{
    NSURL *url=[NSURL URLWithString:self.player.currentMedia.MRL]; NSMutableDictionary *scope=[NSMutableDictionary dictionary];
    if(url.isFileURL) {NSURL *folder=url.URLByDeletingLastPathComponent;scope[@"key"]=[@"folder:" stringByAppendingString:[NSURL fileURLWithPath:folder.path isDirectory:NO].absoluteString];scope[@"title"]=folder.lastPathComponent.length ? folder.lastPathComponent : folder.path;}
    VLCMediaLibraryMediaItem *item=self.player.currentMediaLibraryItem; vlc_medialibrary_t *library=getMediaLibrary();
    if(item.showEpisode && library && !VLCMain.sharedInstance.isTerminating) {
        vlc_ml_query_params_t query=vlc_ml_query_params_create(); vlc_ml_show_list_t *shows=vlc_ml_list_shows(library,&query);
        if(shows) {
            for(size_t i=0;i<shows->i_nb_items;i++) {
                vlc_ml_show_t *show=&shows->p_items[i]; vlc_ml_media_list_t *episodes=vlc_ml_list_show_episodes(library,&query,show->i_id);BOOL match=NO;
                if(episodes) {for(size_t j=0;j<episodes->i_nb_items;j++) if(episodes->p_items[j].i_id==item.libraryID){match=YES;break;} vlc_ml_media_list_release(episodes);}
                if(match && show->psz_name) {scope[@"key"]=[NSString stringWithFormat:@"VLC_ML_PARENT_SHOW - %lld",(long long)show->i_id];scope[@"title"]=toNSStr(show->psz_name);break;}
            }
            vlc_ml_show_list_release(shows);
        }
    }
    return scope;
}
- (NSDictionary *)captureStateForSection:(NSInteger)section
{
    NSMutableArray *groups=[NSMutableArray array]; audio_output_t *audio=section==1 ? self.player.mainAudioOutput : NULL;
    vout_thread_t *video=section==2 ? self.player.mainVideoOutputThread : NULL; vlc_object_t *output=audio ? VLC_OBJECT(audio) : video ? VLC_OBJECT(video) : NULL;
    for(NSNumber *number in sectionGroups(section)) {
        if(number.integerValue==2)continue; // Read legacy adapter records; save distinct current transform/rotate groups.
        NSDictionary *definition=presetGroups()[number.integerValue]; NSString *filter=definition[@"filter"];
        if(filter.length && !module_find(filter.UTF8String)) continue;
        NSMutableDictionary *options=[NSMutableDictionary dictionary];
        for(NSString *name in definition[@"names"]) {
            module_config_t *option=config_FindConfig(name.UTF8String);if(!option)continue;int type=output ? var_Type(output,name.UTF8String)&VLC_VAR_CLASS : 0; id value;
            if(IsConfigStringType(option->i_type)) {char *string=type==VLC_VAR_STRING ? var_GetString(output,name.UTF8String) : config_GetPsz(name.UTF8String);value=string ? toNSStr(string) : @"";free(string);}
            else if(IsConfigFloatType(option->i_type)) value=@(type==VLC_VAR_FLOAT ? var_GetFloat(output,name.UTF8String) : config_GetFloat(name.UTF8String));
            else value=@(type==VLC_VAR_BOOL ? var_GetBool(output,name.UTF8String) : type==VLC_VAR_INTEGER ? var_GetInteger(output,name.UTF8String) : config_GetInt(name.UTF8String));
            options[name]=value;
        }
        BOOL enabled=NO;
        if(filter.length) {const char *key=section==1 ? "audio-filter" : "video-filter";char *string=output && (var_Type(output,key)&VLC_VAR_CLASS)==VLC_VAR_STRING ? var_GetString(output,key) : config_GetPsz(key);NSString *chain=string ? toNSStr(string) : @"";free(string);for(NSString *entry in [chain componentsSeparatedByString:@":"]) if([[[entry componentsSeparatedByString:@"{"] firstObject] isEqual:filter])enabled=YES;}
        if(options.count || filter.length) [groups addObject:@{@"group":number,@"options":options,@"filterEnabled":@(enabled)}];
    }
    if(audio)aout_Release(audio);if(video)vout_Release(video);
    NSDictionary *sync=section==0 ? @{@"primary":@(MS_FROM_VLC_TICK(self.player.subtitlesDelay)),@"secondary":@(MS_FROM_VLC_TICK(self.player.secondarySubtitlesDelay)),@"fps":@(self.player.subtitlesFPS)} : section==1 ? @{@"audio":@(MS_FROM_VLC_TICK(self.player.audioDelay))} : @{};
    return @{@"groups":groups,@"sync":sync};
}
- (BOOL)validDelay:(id)value
{if(![value isKindOfClass:NSNumber.class])return NO;double number=[value doubleValue];return isfinite(number)&&floor(number)==number&&number>=INT32_MIN&&number<=INT32_MAX;}
- (BOOL)applyState:(NSDictionary *)snapshot section:(NSInteger)section
{
    if(![snapshot isKindOfClass:NSDictionary.class] || section<0 || section>2)return NO;
    if(![snapshot[@"groups"] isKindOfClass:NSArray.class] || ![snapshot[@"sync"] isKindOfClass:NSDictionary.class])return NO;
    NSDictionary *sync=snapshot[@"sync"];
    if(section==0 && (![self validDelay:sync[@"primary"]] || ![self validDelay:sync[@"secondary"]] || ![sync[@"fps"] isKindOfClass:NSNumber.class] || !isfinite([sync[@"fps"] doubleValue]) || [sync[@"fps"] doubleValue]<0 || [sync[@"fps"] doubleValue]>100))return NO;
    if(section==1 && ![self validDelay:sync[@"audio"]])return NO;
    NSMutableDictionary *values=[NSMutableDictionary dictionary];NSMutableArray *available=[NSMutableArray array];NSArray *allowed=sectionGroups(section);
    for(id group in snapshot[@"groups"]) {
        if(![group isKindOfClass:NSDictionary.class] || ![group[@"group"] isKindOfClass:NSNumber.class] || ![group[@"options"] isKindOfClass:NSDictionary.class])return NO;
        NSNumber *number=group[@"group"];if(![allowed containsObject:number])continue;NSDictionary *definition=presetGroups()[number.integerValue];NSString *filter=definition[@"filter"];
        if(filter.length && (!module_find(filter.UTF8String) || ![group[@"filterEnabled"] isKindOfClass:NSNumber.class]))continue;
        for(NSString *name in definition[@"names"]) {id value=group[@"options"][name];module_config_t *option=config_FindConfig(name.UTF8String);if(!value||!option)continue;
            if(IsConfigStringType(option->i_type)) {
                if(![value isKindOfClass:NSString.class])return NO;
                if([name isEqualToString:@"equalizer-bands"]) {
                    NSArray *bands=[[value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *band,NSDictionary *bindings){return band.length>0;}]];
                    if(bands.count>EQZ_BANDS_MAX)return NO;
                    for(NSString *band in bands) {NSScanner *scanner=[NSScanner scannerWithString:band];double gain;if(![scanner scanDouble:&gain]||!scanner.isAtEnd||!isfinite(gain)||gain<-20||gain>20)return NO;}
                }
            }
            else if(![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue]) || (IsConfigIntegerType(option->i_type)&&floor([value doubleValue])!=[value doubleValue]))return NO;
            NSString *encoded=IsConfigStringType(option->i_type) ? value : IsConfigFloatType(option->i_type) ? [NSString stringWithFormat:@"%.9g",[value doubleValue]] : [value stringValue];
            values[name]=@{@"name":name,@"type":@(option->i_type),@"value":encoded};
        }
        if(filter.length) {NSString *key=section==1 ? @"audio-filter" : @"video-filter";module_config_t *option=config_FindConfig(key.UTF8String);if(!option)continue;
            char *string=values[key] ? NULL : config_GetPsz(key.UTF8String);NSString *chain=values[key][@"value"] ?: (string ? toNSStr(string) : @"");free(string);
            values[key]=@{@"name":key,@"type":@(option->i_type),@"value":updatedFilterChain(chain,filter,[group[@"filterEnabled"] boolValue])};}
        [available addObject:group];
    }
    // Validate every known value before any config/live output change.
    if(![VLCSettingsProfileManager.sharedInstance applySnapshot:@{@"configuration":values.allValues}])return NO;
    if(getIntf())config_SaveConfigFile(getIntf());
    audio_output_t *audio=section==1 ? self.player.mainAudioOutput : NULL;vout_thread_t *video=section==2 ? self.player.mainVideoOutputThread : NULL;vlc_object_t *output=audio ? VLC_OBJECT(audio) : video ? VLC_OBJECT(video) : NULL;
    for(NSDictionary *group in available) {NSDictionary *definition=presetGroups()[[group[@"group"] integerValue]];NSString *filter=definition[@"filter"];
        if(audio && filter.length)aout_EnableFilter(audio,filter.UTF8String,[group[@"filterEnabled"] boolValue]);
        if(video && filter.length && (var_Type(video,"video-filter")&VLC_VAR_CLASS)==VLC_VAR_STRING) {char *string=var_GetString(video,"video-filter");NSString *chain=updatedFilterChain(string ? toNSStr(string) : @"",filter,[group[@"filterEnabled"] boolValue]);free(string);var_SetString(video,"video-filter",chain.UTF8String);}
        // Original whitelist order restores equalizer-preset before custom bands/preamp.
        for(NSString *name in definition[@"names"]) {id value=group[@"options"][name];if(!value || !output || !values[name])continue;int type=var_Type(output,name.UTF8String)&VLC_VAR_CLASS;
            if(type==VLC_VAR_STRING)var_SetString(output,name.UTF8String,[value UTF8String]);else if(type==VLC_VAR_FLOAT)var_SetFloat(output,name.UTF8String,[value floatValue]);else if(type==VLC_VAR_BOOL)var_SetBool(output,name.UTF8String,[value boolValue]);else if(type==VLC_VAR_INTEGER)var_SetInteger(output,name.UTF8String,[value longLongValue]);}
    }
    if(audio)aout_Release(audio);if(video)vout_Release(video);
    if(section==0){self.player.subtitlesDelay=VLC_TICK_FROM_MS([sync[@"primary"] longLongValue]);self.player.secondarySubtitlesDelay=VLC_TICK_FROM_MS([sync[@"secondary"] longLongValue]);self.player.subtitlesFPS=[sync[@"fps"] floatValue];id scale=values[@"sub-text-scale"][@"value"];if(scale)self.player.subtitleTextScalingFactor=[scale intValue];}
    else if(section==1)self.player.audioDelay=VLC_TICK_FROM_MS([sync[@"audio"] longLongValue]);
    return YES;
}
- (void)reloadChoices
{
    self.scope=[self currentScope];NSMutableArray *visible=[NSMutableArray array];
    for(id record in self.allRecords) if([record isKindOfClass:NSDictionary.class] && [record[@"name"] isKindOfClass:NSString.class] && [record[@"section"] isKindOfClass:NSNumber.class] && [record[@"snapshot"] isKindOfClass:NSDictionary.class] && [record[@"scopeKey"] isKindOfClass:NSString.class] && [record[@"section"] integerValue]==self.section && (![record[@"scopeKey"] length] || [record[@"scopeKey"] isEqual:self.scope[@"key"]]))[visible addObject:record];
    self.records=visible;[self.choice removeAllItems];
    if(!visible.count){[self.choice addItemWithTitle:_NS("Presets")];self.choice.enabled=NO;}
    else{for(NSDictionary *record in visible)[self.choice addItemWithTitle:record[@"name"]];self.choice.enabled=YES;[self.choice selectItemAtIndex:-1];}
    self.scopeChoice.title=self.scope[@"title"] ?: @"";self.scopeChoice.hidden=!self.scope[@"key"];self.scopeChoice.state=NSControlStateValueOff;[self selectionChanged:nil];
}
- (NSView *)viewForSection:(NSInteger)section
{
    self.section=section;NSStackView *view=[NSStackView stackViewWithViews:@[]];view.orientation=NSUserInterfaceLayoutOrientationVertical;view.alignment=NSLayoutAttributeLeading;view.spacing=6;view.translatesAutoresizingMaskIntoConstraints=NO;
    NSTextField *caption=[NSTextField labelWithString:_NS("Presets")];caption.font=[NSFont vlc_redesignFontOfSize:16 weight:NSFontWeightRegular];[view addArrangedSubview:caption];
    self.choice=[[NSPopUpButton alloc] init];self.choice.target=self;self.choice.action=@selector(selectionChanged:);[view addArrangedSubview:self.choice];[self.choice.widthAnchor constraintEqualToAnchor:view.widthAnchor].active=YES;[self.choice.heightAnchor constraintEqualToConstant:36].active=YES;
    self.scopeChoice=[NSButton checkboxWithTitle:@"" target:nil action:nil];[view addArrangedSubview:self.scopeChoice];
    NSButton *save=[NSButton buttonWithTitle:_NS("Save") target:self action:@selector(save:)];self.applyButton=[NSButton buttonWithTitle:_NS("Apply") target:self action:@selector(apply:)];self.deleteButton=[NSButton buttonWithTitle:_NS("Delete") target:self action:@selector(delete:)];
    NSStackView *actions=[NSStackView stackViewWithViews:@[save,self.applyButton,self.deleteButton]];actions.spacing=6;[view addArrangedSubview:actions];
    [self reloadChoices];[view vlc_applyRedesignStyle];return view;
}
- (void)selectionChanged:(id)sender
{BOOL selected=self.choice.indexOfSelectedItem>=0&&self.records.count>0;self.applyButton.enabled=selected;self.deleteButton.enabled=selected;}
- (NSDictionary *)state:(NSDictionary *)state mergingSaved:(NSDictionary *)saved
{
    // Preserve groups/option keys belonging to an unavailable OS/provider.
    NSMutableDictionary *merged=[saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableDictionary *groups=[NSMutableDictionary dictionary];
    for(id group in [saved[@"groups"] isKindOfClass:NSArray.class] ? saved[@"groups"] : @[])
        if([group isKindOfClass:NSDictionary.class] && [group[@"group"] isKindOfClass:NSNumber.class]) groups[group[@"group"]]=group;
    for(NSDictionary *group in state[@"groups"]) {
        NSDictionary *old=groups[group[@"group"]];NSMutableDictionary *updated=old ? [old mutableCopy] : [NSMutableDictionary dictionary];
        NSMutableDictionary *options=[old[@"options"] isKindOfClass:NSDictionary.class] ? [old[@"options"] mutableCopy] : [NSMutableDictionary dictionary];
        [options addEntriesFromDictionary:group[@"options"]];[updated addEntriesFromDictionary:group];updated[@"options"]=options;groups[group[@"group"]]=updated;
    }
    merged[@"groups"]=[groups.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"group"] compare:b[@"group"]];}];
    NSMutableDictionary *sync=[saved[@"sync"] isKindOfClass:NSDictionary.class] ? [saved[@"sync"] mutableCopy] : [NSMutableDictionary dictionary];[sync addEntriesFromDictionary:state[@"sync"]];merged[@"sync"]=sync;
    return merged;
}
- (void)save:(id)sender
{
    NSAlert *alert=[NSAlert new];alert.messageText=_NS("Duplicate current profile for a new profile");alert.informativeText=_NS("Enter a name for the new profile:");NSButton *save=[alert addButtonWithTitle:_NS("Save")];save.enabled=NO;[alert addButtonWithTitle:_NS("Cancel")];
    NSTextField *name=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,320,36)];alert.accessoryView=name;alert.window.initialFirstResponder=name;
    id observer=[NSNotificationCenter.defaultCenter addObserverForName:NSControlTextDidChangeNotification object:name queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){save.enabled=[name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length>0;}];
    NSModalResponse response=[alert runModal];[NSNotificationCenter.defaultCenter removeObserver:observer];if(response!=NSAlertFirstButtonReturn)return;
    NSString *title=[name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!title.length)return;NSDictionary *state=[self captureStateForSection:self.section];if(![state[@"groups"] count])return;
    NSString *key=self.scopeChoice.state==NSControlStateValueOn ? self.scope[@"key"] : @"";if(!key)return;
    NSMutableArray *records=[self.allRecords mutableCopy];NSMutableDictionary *record=[@{@"name":title,@"section":@(self.section),@"scopeKey":key,@"scopeTitle":key.length ? self.scope[@"title"] : @"",@"snapshot":state} mutableCopy];
    NSUInteger index=[records indexOfObjectPassingTest:^BOOL(id existing,NSUInteger index,BOOL *stop){return [existing isKindOfClass:NSDictionary.class] && [existing[@"section"] isKindOfClass:NSNumber.class] && [existing[@"section"] integerValue]==self.section && [existing[@"name"] isEqual:title] && [existing[@"scopeKey"] isEqual:key];}];
    if(index==NSNotFound)[records addObject:record];else{NSMutableDictionary *merged=[records[index] mutableCopy];record[@"snapshot"]=[self state:state mergingSaved:merged[@"snapshot"]];[merged addEntriesFromDictionary:record];records[index]=merged;}[self persist:records];
}
- (void)apply:(id)sender
{NSInteger index=self.choice.indexOfSelectedItem;if(index<0||index>=self.records.count)return;NSDictionary *record=self.records[index];if([self applyState:record[@"snapshot"] section:self.section]) [NSNotificationCenter.defaultCenter postNotificationName:@"VLCPlayerPresetApplied" object:self];}
- (void)delete:(id)sender
{NSInteger index=self.choice.indexOfSelectedItem;if(index<0||index>=self.records.count)return;NSMutableArray *records=[self.allRecords mutableCopy];[records removeObject:self.records[index]];[self persist:records];}
@end
