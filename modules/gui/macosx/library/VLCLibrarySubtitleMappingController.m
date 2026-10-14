/* Figma1911:7545/3336:11929 supplies Add Subtitles, From Computer and target
 * labels, 1048x800 shell, 96px header, 72px footer and 40px rows. Media names
 * are ML file metadata; subtitle names are owner-selected NSOpenPanel URLs. */
#import "VLCLibrarySubtitleMappingController.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "library/VLCLibraryDataTypes.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import <vlc_input_item.h>
#import <vlc_interface.h>

@interface VLCLibrarySubtitleMappingController ()
@property NSArray<VLCMediaLibraryMediaItem *> *mediaItems;
@property NSMutableDictionary<NSNumber *, NSURL *> *selectedURLs;
@property NSMutableDictionary<NSNumber *, NSURL *> *pendingURLs;
@property NSMutableDictionary<NSNumber *, NSNumber *> *results;
@property NSTableView *tableView;
@property NSButton *saveButton;
@end
@implementation VLCLibrarySubtitleMappingController
- (instancetype)initWithMediaItems:(NSArray<VLCMediaLibraryMediaItem *> *)items targetTitle:(NSString *)targetTitle
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1048,800) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window]; if (!self) return nil;
    window.releasedWhenClosed = NO; window.title = _NS("Add Subtitles");
    window.minSize = NSMakeSize(560,380); window.backgroundColor = NSColor.VLCWindowBackgroundColor;
    _mediaItems = [items copy]; _selectedURLs = [NSMutableDictionary dictionary];
    _pendingURLs = [NSMutableDictionary dictionary]; _results = [NSMutableDictionary dictionary];
    for (VLCMediaLibraryMediaItem *item in items) for (VLCMediaLibraryFile *file in item.files)
        if (file.fileType == VLC_ML_FILE_TYPE_SUBTITLE && file.present) { _selectedURLs[@(item.libraryID)] = file.fileURL; break; }
    NSView *root = window.contentView;
    NSView *header = [[NSView alloc] init]; header.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:header];
    NSTextField *title = [NSTextField labelWithString:window.title];
    title.font = [NSFont vlc_redesignFontOfSize:20 weight:NSFontWeightRegular]; title.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:title];
    NSButton *close = [NSButton buttonWithTitle:@"" target:self action:@selector(cancel:)];
    close.bordered = NO; close.image = [NSImage vlc_redesignImageNamed:@"settings-close"]; close.image.size = NSMakeSize(24,24);
    close.accessibilityLabel = _NS("Close"); close.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:close];
    NSTextField *source = [NSTextField labelWithString:_NS("From Computer")];
    source.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular]; source.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:source];
    NSTextField *target = [NSTextField labelWithString:targetTitle];
    target.font = source.font; target.translatesAutoresizingMaskIntoConstraints = NO; [header addSubview:target];
    NSScrollView *scroll = [[NSScrollView alloc] init]; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.drawsBackground = NO; scroll.hasVerticalScroller = YES;
    _tableView = [[NSTableView alloc] init]; _tableView.headerView = nil;
    _tableView.backgroundColor = NSColor.VLCWindowBackgroundColor;
    _tableView.rowHeight = 40; _tableView.intercellSpacing = NSMakeSize(12,0);
    _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _tableView.dataSource = self; _tableView.delegate = self;
    NSTableColumn *media = [[NSTableColumn alloc] initWithIdentifier:@"media"]; media.width = 490; media.minWidth = 180;
    NSTableColumn *subtitle = [[NSTableColumn alloc] initWithIdentifier:@"subtitle"]; subtitle.width = 490; subtitle.minWidth = 180;
    [_tableView addTableColumn:media]; [_tableView addTableColumn:subtitle];
    scroll.documentView = _tableView; [root addSubview:scroll];
    NSView *footer = [[NSView alloc] init]; footer.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:footer];
    NSButton *cancel = [NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancel:)]; cancel.keyEquivalent = @"\e";
    _saveButton = [NSButton buttonWithTitle:_NS("Save") target:self action:@selector(save:)]; _saveButton.keyEquivalent = @"\r"; _saveButton.enabled = NO;
    cancel.translatesAutoresizingMaskIntoConstraints = NO; _saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:cancel]; [footer addSubview:_saveButton];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:root.topAnchor], [header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor], [header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor], [header.heightAnchor constraintEqualToConstant:96],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:24], [title.centerYAnchor constraintEqualToAnchor:header.topAnchor constant:25],
        [close.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16], [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor], [close.widthAnchor constraintEqualToConstant:32], [close.heightAnchor constraintEqualToConstant:32],
        [source.leadingAnchor constraintEqualToAnchor:title.leadingAnchor], [source.topAnchor constraintEqualToAnchor:header.topAnchor constant:59], [source.heightAnchor constraintEqualToConstant:34],
        [target.leadingAnchor constraintEqualToAnchor:source.trailingAnchor constant:24], [target.centerYAnchor constraintEqualToAnchor:source.centerYAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor], [footer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor], [footer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor], [footer.heightAnchor constraintEqualToConstant:72],
        [_saveButton.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-24], [_saveButton.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor], [_saveButton.widthAnchor constraintEqualToConstant:100], [_saveButton.heightAnchor constraintEqualToConstant:32],
        [cancel.trailingAnchor constraintEqualToAnchor:_saveButton.leadingAnchor constant:-12], [cancel.centerYAnchor constraintEqualToAnchor:_saveButton.centerYAnchor], [cancel.widthAnchor constraintEqualToConstant:100], [cancel.heightAnchor constraintEqualToConstant:32],
        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:12], [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-12], [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24], [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24]
    ]];
    [root vlc_applyRedesignStyle]; [window center]; return self;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.mediaItems.count; }
- (NSString *)filenameForMedia:(VLCMediaLibraryMediaItem *)item
{
    for (VLCMediaLibraryFile *file in item.files) if (file.fileType == VLC_ML_FILE_TYPE_MAIN) return file.fileURL.lastPathComponent ?: item.displayString;
    return item.displayString;
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    VLCMediaLibraryMediaItem *item = self.mediaItems[row];
    if ([column.identifier isEqualToString:@"media"]) {
        NSTextField *field = [NSTextField labelWithString:[self filenameForMedia:item] ?: @""];
        field.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular]; field.textColor = NSColor.VLCControlForegroundColor;
        field.lineBreakMode = NSLineBreakByTruncatingMiddle; return field;
    }
    NSStackView *cell = [[NSStackView alloc] init]; cell.spacing = 12;
    NSTextField *link = [NSTextField labelWithString:@"—"]; // Existing native separator glyph.
    link.textColor = NSColor.separatorColor; [cell addArrangedSubview:link];
    NSButton *picker = [NSButton buttonWithTitle:self.selectedURLs[@(item.libraryID)].lastPathComponent ?: @"" target:self action:@selector(selectSubtitle:)];
    picker.image = [NSImage vlc_redesignImageNamed:@"menu-file"]; picker.image.size = NSMakeSize(24,24); picker.imagePosition = NSImageLeft;
    picker.alignment = NSTextAlignmentLeft; picker.bordered = NO; picker.tag = row; picker.toolTip = _NS("Add Subtitles"); picker.accessibilityLabel = picker.title.length ? picker.title : picker.toolTip;
    picker.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular]; picker.wantsLayer = YES; picker.layer.cornerRadius = 6;
    picker.cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSAppearance *previous = NSAppearance.currentAppearance; NSAppearance.currentAppearance = picker.effectiveAppearance;
    picker.layer.backgroundColor = NSColor.VLCInputBackgroundColor.CGColor; NSAppearance.currentAppearance = previous;
    [cell addArrangedSubview:picker]; [picker.heightAnchor constraintEqualToConstant:36].active = YES;
    [picker setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSNumber *result = self.results[@(item.libraryID)];
    if (result && result.intValue != VLC_SUCCESS) {
        // The API only returns a VLC result code. Render that exact value.
        NSTextField *status = [NSTextField labelWithString:result.stringValue]; status.textColor = NSColor.systemRedColor;
        [cell addArrangedSubview:status];
    }
    [cell vlc_applyRedesignStyle]; return cell;
}
- (void)selectSubtitle:(NSButton *)sender
{
    if (sender.tag < 0 || sender.tag >= self.mediaItems.count) return;
    NSNumber *mediaID = @(self.mediaItems[sender.tag].libraryID);
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = NO; panel.allowsMultipleSelection = NO;
    panel.allowedFileTypes = [NSString extensionsArrayFromVLCStyleString:EXTENSIONS_SUBTITLE];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        self.selectedURLs[mediaID] = panel.URL; self.pendingURLs[mediaID] = panel.URL;
        [self.results removeObjectForKey:mediaID]; self.saveButton.enabled = YES; [self.tableView reloadData];
    }];
}
- (void)save:(id)sender
{
    vlc_medialibrary_t *library = getMediaLibrary();
    if (!library || VLCMain.sharedInstance.isTerminating) return;
    for (NSNumber *mediaID in self.pendingURLs.allKeys) {
        NSURL *url = self.pendingURLs[mediaID];
        int result = vlc_ml_media_add_external_mrl(library, mediaID.longLongValue, url.absoluteString.UTF8String, VLC_ML_FILE_TYPE_SUBTITLE);
        self.results[mediaID] = @(result);
        if (result == VLC_SUCCESS) [self.pendingURLs removeObjectForKey:mediaID];
    }
    if (!self.pendingURLs.count) [self.window close];
    else [self.tableView reloadData];
}
- (void)cancel:(id)sender { [self.window close]; }
@end
