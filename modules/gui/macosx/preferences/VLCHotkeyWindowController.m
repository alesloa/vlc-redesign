/* Figma2437:14832 supplies Keyboard Shortcuts, search/filter copy, 96px header,
 * 72px footer, 40px rows and 100x32 actions. Actions/bindings/ranges and reserved
 * combinations come from VLC's existing key metadata and native preferences.
 * Global shortcuts are unavailable on macOS (globalhotkeys only win32/xcb). */
#import "VLCHotkeyWindowController.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "views/VLCRedesignBooleanControl.h"
#import "main/VLCMain.h"
#import <vlc_configuration.h>
#import <vlc_modules.h>
#import <vlc_plugin.h>

@interface VLCHotkeyWindowController ()
@property NSArray<NSString *> *names;
@property NSArray<NSString *> *descriptions;
@property NSArray<NSString *> *originalKeys;
@property NSMutableArray<NSString *> *keys;
@property NSArray<NSNumber *> *visibleRows;
@property NSSearchField *search;
@property NSPopUpButton *searchScope;
@property NSTableView *table;
@property NSButton *mediaKeys;
@property NSInteger originalMediaKeys;
@property VLCHotkeyChangeWindow *captureWindow;
@property NSTextField *captureKeys;
@property NSTextField *captureMessage;
@property NSButton *captureAccept;
@property NSUInteger editingRow;
@property NSString *candidate;
@end
@implementation VLCHotkeyWindowController
- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1048,800) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window]; if (!self) return nil;
    window.title = _NS("Keyboard Shortcuts"); window.releasedWhenClosed = NO; window.minSize = NSMakeSize(560,420); window.backgroundColor = NSColor.VLCWindowBackgroundColor;
    NSMutableArray *names = [NSMutableArray array], *descriptions = [NSMutableArray array], *keys = [NSMutableArray array];
    unsigned count; module_config_t *options = module_config_get(module_get_main(), &count);
    for (unsigned index=0;index<count;index++) {
        module_config_t *option = &options[index];
        if (option->i_type != CONFIG_ITEM_KEY || !strncmp(option->psz_name,"global-",7) || EMPTY_STR(option->psz_text)) continue;
        [names addObject:toNSStr(option->psz_name)]; [descriptions addObject:NSTR(option->psz_text)];
        [keys addObject:option->value.psz ? toNSStr(option->value.psz) : @""];
    }
    module_config_free(options); _names=names.copy; _descriptions=descriptions.copy; _originalKeys=keys.copy; _keys=keys;
    NSView *root = window.contentView;
    NSView *header = [[NSView alloc] init]; header.identifier=@"VLCRedesignedPlayerHeader"; header.wantsLayer=YES; header.translatesAutoresizingMaskIntoConstraints=NO; [root addSubview:header];
    NSTextField *title=[NSTextField labelWithString:window.title]; title.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular]; title.translatesAutoresizingMaskIntoConstraints=NO; [header addSubview:title];
    NSButton *close=[NSButton buttonWithTitle:@"" target:self action:@selector(cancel:)]; close.image=[NSImage vlc_redesignImageNamed:@"settings-close"]; close.image.size=NSMakeSize(24,24); close.bordered=NO; close.accessibilityLabel=_NS("Close"); close.translatesAutoresizingMaskIntoConstraints=NO; [header addSubview:close];
    _search=[[NSSearchField alloc] init]; _search.delegate=self; _search.placeholderString=_NS("Search Keyboard Shortcuts..."); _search.translatesAutoresizingMaskIntoConstraints=NO; [header addSubview:_search];
    _searchScope=[[NSPopUpButton alloc] init]; [_searchScope addItemsWithTitles:@[_NS("All Fields"),_NS("Action"),_NS("Hotkey")]]; _searchScope.target=self; _searchScope.action=@selector(filter:); _searchScope.translatesAutoresizingMaskIntoConstraints=NO; [header addSubview:_searchScope];
    NSScrollView *scroll=[[NSScrollView alloc] init]; scroll.translatesAutoresizingMaskIntoConstraints=NO; scroll.hasVerticalScroller=YES; scroll.drawsBackground=NO; [root addSubview:scroll];
    _table=[[NSTableView alloc] init]; _table.rowHeight=40; _table.backgroundColor=NSColor.VLCWindowBackgroundColor; _table.dataSource=self; _table.delegate=self; _table.target=self; _table.doubleAction=@selector(edit:); _table.columnAutoresizingStyle=NSTableViewUniformColumnAutoresizingStyle;
    NSTableColumn *action=[[NSTableColumn alloc] initWithIdentifier:@"action"]; action.title=_NS("Action"); action.width=580; action.minWidth=240; [_table addTableColumn:action];
    NSTableColumn *key=[[NSTableColumn alloc] initWithIdentifier:@"key"]; key.title=_NS("Hotkey"); key.width=400; key.minWidth=160; [_table addTableColumn:key]; scroll.documentView=_table;
    NSView *footer=[[NSView alloc] init]; footer.translatesAutoresizingMaskIntoConstraints=NO; [root addSubview:footer];
    NSButton *cancel=[NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancel:)]; cancel.keyEquivalent=@"\e"; cancel.translatesAutoresizingMaskIntoConstraints=NO; [footer addSubview:cancel];
    NSButton *save=[NSButton buttonWithTitle:_NS("Save") target:self action:@selector(save:)]; save.keyEquivalent=@"\r"; save.translatesAutoresizingMaskIntoConstraints=NO; [footer addSubview:save];
    if (config_FindConfig("macosx-mediakeys")) {
        _mediaKeys=[[VLCRedesignBooleanControl alloc] init]; [_mediaKeys setButtonType:NSButtonTypeSwitch]; _mediaKeys.title=_NS("Control playback with media keys"); _originalMediaKeys=config_GetInt("macosx-mediakeys"); _mediaKeys.state=_originalMediaKeys; _mediaKeys.translatesAutoresizingMaskIntoConstraints=NO; [footer addSubview:_mediaKeys];
        // The original NSButton intrinsic width does not include the redesign's
        // 68px toggle. Reserve room for the source label, yielding at small sizes.
        NSLayoutConstraint *mediaKeysWidth=[_mediaKeys.widthAnchor constraintGreaterThanOrEqualToConstant:400];
        mediaKeysWidth.priority=NSLayoutPriorityDefaultHigh;
        mediaKeysWidth.active=YES;
        [NSLayoutConstraint activateConstraints:@[[_mediaKeys.leadingAnchor constraintEqualToAnchor:cancel.trailingAnchor constant:16],[_mediaKeys.trailingAnchor constraintLessThanOrEqualToAnchor:save.leadingAnchor constant:-16],[_mediaKeys.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],[_mediaKeys.heightAnchor constraintEqualToConstant:32]]];
    }
    [NSLayoutConstraint activateConstraints:@[[header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[header.topAnchor constraintEqualToAnchor:root.topAnchor],[header.heightAnchor constraintEqualToConstant:96],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],[title.centerYAnchor constraintEqualToAnchor:header.topAnchor constant:25],[close.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-9],[close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],[close.widthAnchor constraintEqualToConstant:32],[close.heightAnchor constraintEqualToConstant:32],
        [_search.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:9],[_search.topAnchor constraintEqualToAnchor:header.topAnchor constant:53],[_search.heightAnchor constraintEqualToConstant:34],[_search.trailingAnchor constraintEqualToAnchor:_searchScope.leadingAnchor constant:-10],[_searchScope.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-9],[_searchScope.centerYAnchor constraintEqualToAnchor:_search.centerYAnchor],[_searchScope.widthAnchor constraintEqualToConstant:200],[_searchScope.heightAnchor constraintEqualToConstant:34],
        [footer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[footer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[footer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],[footer.heightAnchor constraintEqualToConstant:72],
        [cancel.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:20],[cancel.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],[cancel.widthAnchor constraintEqualToConstant:100],[cancel.heightAnchor constraintEqualToConstant:32],[save.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-20],[save.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],[save.widthAnchor constraintEqualToConstant:100],[save.heightAnchor constraintEqualToConstant:32],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],[scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],[scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:20],[scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-20]]];
    [self filter:nil]; [root vlc_applyRedesignStyle]; [window center]; return self;
}
- (void)filter:(id)sender
{
    NSMutableArray *rows=[NSMutableArray array]; NSString *query=self.search.stringValue; NSInteger scope=self.searchScope.indexOfSelectedItem;
    for(NSUInteger row=0;row<self.keys.count;row++) {
        BOOL match=!query.length || (scope!=2 && [self.descriptions[row] localizedCaseInsensitiveContainsString:query]) || (scope!=1 && [OSXStringKeyToString(self.keys[row]) localizedCaseInsensitiveContainsString:query]);
        if(match) [rows addObject:@(row)];
    }
    self.visibleRows=rows; [self.table reloadData];
}
- (void)controlTextDidChange:(NSNotification *)notification { [self filter:nil]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.visibleRows.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    NSUInteger source=self.visibleRows[row].unsignedIntegerValue;
    NSTextField *field=[NSTextField labelWithString:[column.identifier isEqualToString:@"action"] ? self.descriptions[source] : OSXStringKeyToString(self.keys[source])];
    if ([column.identifier isEqualToString:@"action"]) field.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
    else if (@available(macOS 10.15, *)) field.font=[NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightRegular];
    else field.font=[NSFont userFixedPitchFontOfSize:14];
    field.textColor=NSColor.VLCControlForegroundColor; field.lineBreakMode=NSLineBreakByTruncatingTail; field.toolTip=_NS("Double-click an action to change the associated hotkey:"); return field;
}
- (void)edit:(id)sender
{
    NSInteger row=self.table.clickedRow>=0 ? self.table.clickedRow : self.table.selectedRow; if(row<0 || row>=self.visibleRows.count) return;
    self.editingRow=self.visibleRows[row].unsignedIntegerValue; self.candidate=nil;
    VLCHotkeyChangeWindow *window=[[VLCHotkeyChangeWindow alloc] initWithContentRect:NSMakeRect(0,0,520,240) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.captureWindow=window; window.title=_NS("Change Hotkey"); window.releasedWhenClosed=NO; window.hotkeyChangeDelegate=self; window.backgroundColor=NSColor.VLCWindowBackgroundColor;
    NSView *root=window.contentView; NSTextField *instruction=[NSTextField wrappingLabelWithString:[NSString stringWithFormat:_NS("Press new keys for\n\"%@\""),self.descriptions[self.editingRow]]]; instruction.frame=NSMakeRect(20,165,480,55); [root addSubview:instruction];
    self.captureKeys=[NSTextField labelWithString:OSXStringKeyToString(self.keys[self.editingRow])]; self.captureKeys.frame=NSMakeRect(20,130,480,28); [root addSubview:self.captureKeys];
    self.captureMessage=[NSTextField wrappingLabelWithString:@""]; self.captureMessage.frame=NSMakeRect(20,65,480,55); [root addSubview:self.captureMessage];
    NSButton *cancel=[NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancelCapture:)]; cancel.frame=NSMakeRect(20,20,100,32); [root addSubview:cancel];
    NSButton *clear=[NSButton buttonWithTitle:_NS("Clear") target:self action:@selector(clearCapture:)]; clear.frame=NSMakeRect(130,20,100,32); [root addSubview:clear];
    self.captureAccept=[NSButton buttonWithTitle:_NS("OK") target:self action:@selector(acceptCapture:)]; self.captureAccept.frame=NSMakeRect(400,20,100,32); self.captureAccept.enabled=NO; [root addSubview:self.captureAccept];
    [root vlc_applyRedesignStyle]; [window center]; [window makeFirstResponder:window]; [NSApp runModalForWindow:window]; [window orderOut:nil]; self.captureWindow=nil;
}
- (BOOL)changeHotkeyTo:(NSString *)key
{
    // Verbatim reserved combinations from VLCSimplePrefsController's native editor.
    NSArray *reserved=@[@"Command-c",@"Command-x",@"Command-v",@"Command-a",@"Command-,",@"Command-h",@"Command-Alt-h",@"Command-Shift-o",@"Command-o",@"Command-d",@"Command-n",@"Command-s",@"Command-l",@"Command-r",@"Command-3",@"Command-m",@"Command-w",@"Command-Shift-w",@"Command-Shift-c",@"Command-Shift-p",@"Command-i",@"Command-e",@"Command-Shift-e",@"Command-b",@"Command-Shift-m",@"Command-Ctrl-m",@"Command-?",@"Command-Alt-?",@"Command-Shift-f"];
    if([reserved containsObject:key]) {self.captureKeys.stringValue=_NS("Invalid combination"); self.captureMessage.stringValue=_NS("Regrettably, these keys cannot be assigned as hotkey shortcuts."); self.captureAccept.enabled=NO; self.candidate=nil; return NO;}
    self.captureKeys.stringValue=OSXStringKeyToString(key); NSUInteger duplicate=[self.keys indexOfObject:key];
    if(duplicate==NSNotFound) duplicate=[self.keys indexOfObject:[key stringByReplacingOccurrencesOfString:@"-" withString:@"+"]];
    self.captureMessage.stringValue=duplicate!=NSNotFound && duplicate!=self.editingRow ? [NSString stringWithFormat:_NS("This combination is already taken by \"%@\"."),self.descriptions[duplicate]] : @"";
    self.candidate=key; self.captureAccept.enabled=YES; return YES;
}
- (void)cancelCapture:(id)sender { [NSApp stopModal]; }
- (void)clearCapture:(id)sender { self.keys[self.editingRow]=@""; [self filter:nil]; [NSApp stopModal]; }
- (void)acceptCapture:(id)sender
{
    if(!self.candidate) return;
    for(NSUInteger row=0;row<self.keys.count;row++) if(row!=self.editingRow && ([self.keys[row] isEqualToString:self.candidate] || [self.keys[row] isEqualToString:[self.candidate stringByReplacingOccurrencesOfString:@"-" withString:@"+"]])) self.keys[row]=@"";
    self.keys[self.editingRow]=self.candidate; [self filter:nil]; [NSApp stopModal];
}
- (void)cancel:(id)sender { [self.window close]; }
- (void)save:(id)sender
{
    if(VLCMain.sharedInstance.isTerminating) return;
    for(NSUInteger row=0;row<self.keys.count;row++) if(![self.keys[row] isEqualToString:self.originalKeys[row]]) config_PutPsz(self.names[row].UTF8String,self.keys[row].UTF8String);
    if(self.mediaKeys && self.mediaKeys.state!=self.originalMediaKeys) config_PutInt("macosx-mediakeys",self.mediaKeys.state);
    config_SaveConfigFile(getIntf()); [self.window close];
}
@end
