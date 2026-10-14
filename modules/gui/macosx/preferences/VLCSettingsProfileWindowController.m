/* Figma6648:20666 supplies Profile/New. The1048x800 shell,50px header,
 *200px sidebar and72px footer follow the shared Figma settings dialog.
 * Labels/help come from existing VLC preferences/SettingsProfilesDialog;
 * names and values come from saved owner snapshots and original VLC metadata. */
#import "VLCSettingsProfileWindowController.h"
#import "VLCSettingsProfileManager.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import <vlc_configuration.h>
#import <vlc_plugin.h>

@interface VLCSettingsProfileManager (Editor)
- (NSMutableArray *)profiles;
- (NSString *)currentID;
- (BOOL)writeProfiles:(NSArray *)profiles current:(NSString *)identifier applied:(BOOL)applied;
- (NSDictionary *)profile:(NSDictionary *)profile updatingWithSnapshot:(NSDictionary *)snapshot;
- (BOOL)isGUIKey:(NSString *)key;
- (void)refreshGUI;
@end

@interface VLCSettingsProfileWindowController ()
@property NSMutableArray<NSMutableDictionary *> *profiles;
@property NSString *activeID;
@property NSInteger selectedRow;
@property NSStackView *navigation;
@property NSTableView *table;
@property NSSearchField *search;
@property NSArray<NSDictionary *> *rows;
@property NSArray<NSDictionary *> *visibleRows;
@property NSButton *deleteButton;
@property NSButton *saveButton;
@end
@interface VLCProfileNavigationStackView : NSStackView
@end
@implementation VLCProfileNavigationStackView
- (BOOL)isFlipped {return YES;}
@end

@implementation VLCSettingsProfileWindowController
- (instancetype)init
{
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1048,800)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self=[super initWithWindow:window]; if(!self)return nil;
    window.title=_NS("Profile"); window.releasedWhenClosed=NO;
    window.minSize=NSMakeSize(640,420); window.backgroundColor=NSColor.VLCWindowBackgroundColor;
    VLCSettingsProfileManager *manager=VLCSettingsProfileManager.sharedInstance;
    _profiles=[manager profiles]; _activeID=[manager currentID]; _selectedRow=0;
    for(NSUInteger index=0;index<_profiles.count;index++)
        if([_profiles[index][@"id"] isEqual:_activeID]) _selectedRow=index+1;
    NSView *root=window.contentView;
    NSView *header=[NSView new]; header.identifier=@"VLCRedesignedDialogHeader"; header.wantsLayer=YES;
    header.translatesAutoresizingMaskIntoConstraints=NO; [root addSubview:header];
    NSTextField *title=[NSTextField labelWithString:window.title]; title.translatesAutoresizingMaskIntoConstraints=NO;
    title.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
    [header addSubview:title];
    NSButton *close=[NSButton buttonWithTitle:@"" target:self action:@selector(cancel:)];
    close.image=[NSImage vlc_redesignImageNamed:@"settings-close"]; close.image.size=NSMakeSize(24,24);
    close.bordered=NO; close.accessibilityLabel=_NS("Close"); close.translatesAutoresizingMaskIntoConstraints=NO;
    [header addSubview:close];
    NSView *sidebar=[NSView new]; sidebar.identifier=@"VLCRedesignedSettingsSidebar";
    sidebar.wantsLayer=YES;
    sidebar.translatesAutoresizingMaskIntoConstraints=NO; [root addSubview:sidebar];
    NSScrollView *navigationScroll=[NSScrollView new]; navigationScroll.translatesAutoresizingMaskIntoConstraints=NO;
    navigationScroll.hasVerticalScroller=YES; navigationScroll.drawsBackground=NO; [sidebar addSubview:navigationScroll];
    _navigation=[VLCProfileNavigationStackView new]; _navigation.orientation=NSUserInterfaceLayoutOrientationVertical;
    _navigation.alignment=NSLayoutAttributeLeading; _navigation.spacing=8; _navigation.translatesAutoresizingMaskIntoConstraints=NO;
    navigationScroll.documentView=_navigation;
    NSButton *create=[NSButton buttonWithTitle:_NS("New") target:self action:@selector(newProfile:)];
    _deleteButton=[NSButton buttonWithTitle:_NS("Delete") target:self action:@selector(deleteProfile:)];
    for(NSButton *button in @[create,_deleteButton]) {button.translatesAutoresizingMaskIntoConstraints=NO;[sidebar addSubview:button];}
    _search=[NSSearchField new]; _search.placeholderString=_NS("Search"); _search.delegate=self;
    _search.translatesAutoresizingMaskIntoConstraints=NO; [root addSubview:_search];
    NSScrollView *scroll=[NSScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.hasVerticalScroller=YES; scroll.drawsBackground=NO; [root addSubview:scroll];
    _table=[NSTableView new]; _table.dataSource=self; _table.delegate=self; _table.rowHeight=40;
    _table.columnAutoresizingStyle=NSTableViewUniformColumnAutoresizingStyle;
    for(NSArray *definition in @[@[@"option",_NS("Option"),@390],@[@"value",_NS("Value"),@330],@[@"info",@"",@36]]) {
        NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:definition[0]];
        column.title=definition[1]; column.width=[definition[2] doubleValue];
        column.minWidth=[column.identifier isEqual:@"info"]?36:100;
        if([column.identifier isEqual:@"info"])column.maxWidth=36;
        [_table addTableColumn:column];
    }
    scroll.documentView=_table;
    NSView *footer=[NSView new]; footer.translatesAutoresizingMaskIntoConstraints=NO; [root addSubview:footer];
    NSButton *cancel=[NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancel:)]; cancel.keyEquivalent=@"\e";
    _saveButton=[NSButton buttonWithTitle:_NS("Save") target:self action:@selector(saveProfile:)];
    NSButton *apply=[NSButton buttonWithTitle:_NS("Apply") target:self action:@selector(applyProfile:)]; apply.keyEquivalent=@"\r";
    for(NSButton *button in @[cancel,_saveButton,apply]){button.translatesAutoresizingMaskIntoConstraints=NO;[footer addSubview:button];}
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:root.topAnchor],[header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[header.heightAnchor constraintEqualToConstant:50],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],[title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [close.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-9],[close.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:32],[close.heightAnchor constraintEqualToConstant:32],
        [footer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[footer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],[footer.heightAnchor constraintEqualToConstant:72],
        [sidebar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:8],[sidebar.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [sidebar.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-20],[sidebar.widthAnchor constraintEqualToConstant:200],
        [navigationScroll.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:6],[navigationScroll.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-6],
        [navigationScroll.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:6],[navigationScroll.bottomAnchor constraintEqualToAnchor:create.topAnchor constant:-8],
        [_navigation.widthAnchor constraintEqualToAnchor:navigationScroll.widthAnchor],
        [_navigation.heightAnchor constraintGreaterThanOrEqualToAnchor:navigationScroll.contentView.heightAnchor],
        [create.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:6],[create.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-6],
        [create.bottomAnchor constraintEqualToAnchor:_deleteButton.topAnchor constant:-8],[create.heightAnchor constraintEqualToConstant:32],
        [_deleteButton.leadingAnchor constraintEqualToAnchor:create.leadingAnchor],[_deleteButton.trailingAnchor constraintEqualToAnchor:create.trailingAnchor],
        [_deleteButton.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor constant:-6],[_deleteButton.heightAnchor constraintEqualToConstant:32],
        [_search.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:24],[_search.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [_search.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:20],[_search.heightAnchor constraintEqualToConstant:36],
        [scroll.leadingAnchor constraintEqualToAnchor:_search.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:_search.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:20],[scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-20],
        [cancel.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:20],[cancel.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        [apply.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-20],[apply.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        [_saveButton.trailingAnchor constraintEqualToAnchor:apply.leadingAnchor constant:-12],[_saveButton.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor]
    ]];
    for(NSButton *button in @[cancel,_saveButton,apply]) [NSLayoutConstraint activateConstraints:@[[button.widthAnchor constraintEqualToConstant:100],[button.heightAnchor constraintEqualToConstant:32]]];
    [self rebuildNavigation]; [root vlc_applyRedesignStyle]; [window center]; return self;
}
- (void)rebuildNavigation
{
    for(NSView *view in self.navigation.arrangedSubviews.copy){[self.navigation removeArrangedSubview:view];[view removeFromSuperview];}
    NSMutableArray *names=[NSMutableArray arrayWithObject:_NS("Default")];
    for(NSDictionary *profile in self.profiles)[names addObject:profile[@"name"]];
    self.selectedRow=MIN(MAX(0,self.selectedRow),(NSInteger)names.count-1);
    for(NSUInteger index=0;index<names.count;index++) {
        NSButton *button=[NSButton buttonWithTitle:names[index] target:self action:@selector(selectProfile:)];
        button.tag=index; button.bordered=NO; button.alignment=NSTextAlignmentLeft;
        button.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
        button.identifier=@"VLCRedesignedSettingsCategory"; button.wantsLayer=YES; button.layer.cornerRadius=2;
        button.state=index==self.selectedRow?NSControlStateValueOn:NSControlStateValueOff;
        [self.navigation addArrangedSubview:button];
        [NSLayoutConstraint activateConstraints:@[[button.widthAnchor constraintEqualToAnchor:self.navigation.widthAnchor],[button.heightAnchor constraintEqualToConstant:40]]];
    }
    NSView *spacer=[NSView new]; [self.navigation addArrangedSubview:spacer];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [self.navigation vlc_applyRedesignStyle]; [self reviewProfile];
}
- (NSDictionary *)selectedSnapshot
{
    return self.selectedRow==0 ? [VLCSettingsProfileManager.sharedInstance configurationSnapshotUsingDefaults:YES] : self.profiles[self.selectedRow-1];
}
- (void)selectProfile:(NSButton *)sender {self.selectedRow=sender.tag;[self rebuildNavigation];}
- (void)reviewProfile
{
    self.deleteButton.enabled=self.selectedRow>0;
    self.saveButton.enabled=self.profiles.count>0 || self.activeID.length>0;
    NSDictionary *snapshot=[self selectedSnapshot];
    NSMutableSet *browsable=[NSMutableSet set];
    for(NSDictionary *entry in [VLCSettingsProfileManager.sharedInstance configurationSnapshotUsingDefaults:NO][@"configuration"]) [browsable addObject:entry[@"name"]];
    NSMutableArray *rows=[NSMutableArray array];
    for(id entry in snapshot[@"configuration"]) {
        if(![entry isKindOfClass:NSDictionary.class] || ![entry[@"name"] isKindOfClass:NSString.class])continue;
        NSString *name=entry[@"name"]; module_config_t *option=config_FindConfig(name.UTF8String);
        if(option && ![browsable containsObject:name])continue;
        NSString *caption=option && option->psz_text?_NS(option->psz_text):name;
        NSString *help=option && option->psz_longtext?_NS(option->psz_longtext):caption;
        id saved=entry[@"value"]; NSString *value=[saved isKindOfClass:NSString.class]?saved:@"";
        if([entry[@"type"] intValue]==CONFIG_ITEM_PASSWORD && value.length)value=@"•••••";
        [rows addObject:@{@"name":name,@"caption":caption,@"help":help,@"value":value}];
    }
    self.rows=rows; [self filterValues];
}
- (void)filterValues
{
    NSString *query=self.search.stringValue;
    self.visibleRows=[self.rows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *row,NSDictionary *bindings){
        return !query.length || [row[@"name"] localizedCaseInsensitiveContainsString:query] ||
            [row[@"caption"] localizedCaseInsensitiveContainsString:query] || [row[@"help"] localizedCaseInsensitiveContainsString:query] || [row[@"value"] localizedCaseInsensitiveContainsString:query];
    }]];
    [self.table reloadData];
}
- (void)controlTextDidChange:(NSNotification *)notification {[self filterValues];}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {return self.visibleRows.count;}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    NSDictionary *entry=self.visibleRows[row];
    if([column.identifier isEqual:@"info"]) {
        NSButton *button=[NSButton buttonWithTitle:@"" target:self action:@selector(showInformation:)];
        button.image=[NSImage vlc_redesignImageNamed:@"settings-info"]; button.image.size=NSMakeSize(18,18);
        button.bordered=NO; button.tag=row; button.toolTip=entry[@"help"]; button.accessibilityLabel=_NS("Help");
        return button;
    }
    NSTextField *field=[NSTextField labelWithString:entry[[column.identifier isEqual:@"option"]?@"caption":@"value"]];
    field.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular]; field.textColor=NSColor.VLCControlForegroundColor;
    field.lineBreakMode=NSLineBreakByTruncatingTail; field.toolTip=entry[@"help"]; return field;
}
- (void)showInformation:(NSButton *)sender
{
    if(sender.tag<0 || sender.tag>=self.visibleRows.count)return;
    NSDictionary *row=self.visibleRows[sender.tag]; NSAlert *alert=[NSAlert new];
    alert.messageText=row[@"caption"]; alert.informativeText=row[@"help"]; [alert addButtonWithTitle:_NS("Close")]; [alert runModal];
}
- (void)newProfile:(id)sender
{
    NSAlert *alert=[NSAlert new];alert.messageText=_NS("Duplicate current profile for a new profile");alert.informativeText=_NS("Enter a name for the new profile:");
    NSButton *save=[alert addButtonWithTitle:_NS("Save")];save.enabled=NO;[alert addButtonWithTitle:_NS("Cancel")];
    NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,320,36)];alert.accessoryView=field;alert.window.initialFirstResponder=field;
    id observer=[NSNotificationCenter.defaultCenter addObserverForName:NSControlTextDidChangeNotification object:field queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){save.enabled=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length>0;}];
    NSModalResponse response=[alert runModal];[NSNotificationCenter.defaultCenter removeObserver:observer];if(response!=NSAlertFirstButtonReturn)return;
    NSString *name=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!name.length)return;
    for(NSDictionary *profile in self.profiles)if([profile[@"name"] isEqual:name]){NSAlert *duplicate=[NSAlert new];duplicate.messageText=_NS("Please enter a unique name for the new profile.");duplicate.informativeText=_NS("Multiple profiles with the same name are not allowed.");[duplicate addButtonWithTitle:_NS("OK")];[duplicate runModal];return;}
    NSMutableDictionary *snapshot=[[VLCSettingsProfileManager.sharedInstance configurationSnapshotUsingDefaults:NO] mutableCopy];
    snapshot[@"id"]=NSUUID.UUID.UUIDString;snapshot[@"name"]=name;[self.profiles addObject:snapshot];self.selectedRow=self.profiles.count;[self rebuildNavigation];
}
- (void)deleteProfile:(id)sender
{
    if(self.selectedRow<=0 || self.selectedRow>self.profiles.count)return;
    NSDictionary *profile=self.profiles[self.selectedRow-1];if([profile[@"id"] isEqual:self.activeID])self.activeID=@"";
    [self.profiles removeObjectAtIndex:self.selectedRow-1];self.selectedRow=MIN(self.selectedRow,(NSInteger)self.profiles.count);
    [self rebuildNavigation];self.saveButton.enabled=YES;
}
- (void)reportSaveError
{
    // Copy is the original VLC preferences save-error response.
    NSAlert *alert=[NSAlert new];alert.messageText=_NS("Cannot save Configuration");alert.informativeText=_NS("Preferences file could not be saved");[alert addButtonWithTitle:_NS("Close")];[alert runModal];
}
- (void)saveProfile:(id)sender
{
    VLCSettingsProfileManager *manager=VLCSettingsProfileManager.sharedInstance;
    if(self.selectedRow>0){NSUInteger index=self.selectedRow-1;NSDictionary *profile=self.profiles[index];
        if([profile[@"id"] isEqual:self.activeID])self.profiles[index]=[[manager profile:profile updatingWithSnapshot:[manager configurationSnapshotUsingDefaults:NO]] mutableCopy];}
    if([manager writeProfiles:self.profiles current:self.activeID applied:NO])[self.window close];else[self reportSaveError];
}
- (void)applyProfile:(id)sender
{
    VLCSettingsProfileManager *manager=VLCSettingsProfileManager.sharedInstance;
    NSDictionary *snapshot=[self selectedSnapshot];if(![manager applySnapshot:snapshot beforeWriting:^{[manager cancelOlderPreferenceTransaction];}]){[self reportSaveError];return;}
    if(self.selectedRow==0)for(NSString *key in NSUserDefaults.standardUserDefaults.dictionaryRepresentation)if([manager isGUIKey:key])[NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    if(config_SaveConfigFile(getIntf())!=VLC_SUCCESS){[self reportSaveError];return;}
    NSString *identifier=self.selectedRow==0?@"":snapshot[@"id"];
    [manager refreshGUI];if([manager writeProfiles:self.profiles current:identifier applied:YES])[self.window close];else[self reportSaveError];
}
- (void)cancel:(id)sender {[self.window close];}
@end
