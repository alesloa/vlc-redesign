/* Copy and geometry come from Figma New Playlist6259:14954 and Network6216:13614.
 * Filenames, URLs, names and cover art come only from the owner's selections.
 * Save/Cancel stage selections; callers perform existing VLC queue/ML actions. */
#import "VLCLibraryMediaCollectionController.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import <vlc_url.h>

@interface VLCCollectionFilesView : NSView
@property (copy) void (^receiveURLs)(NSArray<NSURL *> *);
@end
@implementation VLCCollectionFilesView
- (instancetype)init { self = [super init]; if (self) [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]]; return self; }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender { return NSDragOperationCopy; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSArray *URLs = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    if (!URLs.count || !self.receiveURLs) return NO;
    self.receiveURLs(URLs); return YES;
}
@end

@interface VLCNetworkURLsTextView : NSTextView
@property NSString *placeholder;
@end
@implementation VLCNetworkURLsTextView
- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    if (!self.string.length) [self.placeholder drawAtPoint:NSMakePoint(self.textContainerInset.width, self.textContainerInset.height) withAttributes:@{NSFontAttributeName:self.font, NSForegroundColorAttributeName:NSColor.VLCSecondaryForegroundColor}];
}
@end

@interface VLCLibraryMediaCollectionController ()
@property BOOL network;
@property BOOL modal;
@property NSTextField *nameField;
@property NSTextView *URLsField;
@property NSMutableArray<NSURL *> *selectedFiles;
@property NSButton *saveButton;
@property NSButton *coverButton;
@property NSTableView *filesTable;
@property (readwrite, nullable) NSURL *coverURL;
@end
@implementation VLCLibraryMediaCollectionController
- (NSTextField *)label:(NSString *)copy size:(CGFloat)size
{
    NSTextField *field = [NSTextField wrappingLabelWithString:copy];
    field.font = [NSFont vlc_redesignFontOfSize:size weight:NSFontWeightRegular];
    field.translatesAutoresizingMaskIntoConstraints = NO; return field;
}
- (NSStackView *)description:(NSString *)title copy:(NSString *)copy
{
    NSStackView *stack = [NSStackView stackViewWithViews:@[[self label:title size:16], [self label:copy size:14]]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.alignment = NSLayoutAttributeLeading; stack.spacing = 5; return stack;
}
- (instancetype)initForNetwork:(BOOL)network initialURLs:(NSArray<NSURL *> *)URLs
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,network ? 1048 : 713,network ? 631 : 589) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window]; if (!self) return nil;
    _network = network; _selectedFiles = [URLs mutableCopy]; _allowsPlaylistSaving = YES;
    window.title = network ? _NS("Open Network Stream") : _NS("New Playlist");
    window.minSize = NSMakeSize(560, network ? 490 : 510); window.delegate = self; window.releasedWhenClosed = NO;
    window.backgroundColor = NSColor.VLCWindowBackgroundColor;
    NSView *root = window.contentView;
    NSView *header = [[NSView alloc] init]; header.translatesAutoresizingMaskIntoConstraints = NO;
    header.identifier = @"VLCRedesignedPlayerHeader"; header.wantsLayer = YES; [root addSubview:header];
    NSTextField *title = [self label:window.title size:14]; [header addSubview:title];
    NSButton *close = [NSButton buttonWithTitle:@"" target:self action:@selector(cancel:)];
    close.image = [NSImage vlc_redesignImageNamed:@"settings-close"]; close.image.size = NSMakeSize(24,24); close.bordered = NO;
    close.accessibilityLabel = _NS("Close"); close.translatesAutoresizingMaskIntoConstraints = NO; [header addSubview:close];
    NSStackView *body = [[NSStackView alloc] init]; body.orientation = NSUserInterfaceLayoutOrientationVertical;
    body.alignment = NSLayoutAttributeLeading; body.spacing = 20; body.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:body];
    _nameField = [[NSTextField alloc] init]; _nameField.delegate = self;
    _nameField.placeholderString = network ? _NS("e.g., Favorite TV Channels") : _NS("e.g., Favorite Videos");
    _nameField.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
    [_nameField.heightAnchor constraintEqualToConstant:41].active = YES;
    if (network) {
        [body addArrangedSubview:[self description:_NS("Network URL") copy:_NS("You can enter multiple links to load.")]];
        NSScrollView *scroll = [[NSScrollView alloc] init]; scroll.hasVerticalScroller = YES;
        VLCNetworkURLsTextView *URLField = [[VLCNetworkURLsTextView alloc] init]; URLField.placeholder = _NS("e.g., https://www.example.com/stream.avi");
        _URLsField = URLField; _URLsField.delegate = self; _URLsField.richText = NO;
        _URLsField.font = _nameField.font; _URLsField.textColor = NSColor.VLCControlForegroundColor;
        _URLsField.backgroundColor = NSColor.VLCInputBackgroundColor; _URLsField.textContainerInset = NSMakeSize(12,8);
        _URLsField.accessibilityLabel = _NS("Network URL");
        if (URLs.count) _URLsField.string = [[URLs valueForKey:@"absoluteString"] componentsJoinedByString:@"\n"];
        scroll.documentView = _URLsField; [body addArrangedSubview:scroll];
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
        NSLayoutConstraint *preferred = [scroll.heightAnchor constraintEqualToConstant:194]; preferred.priority = NSLayoutPriorityDefaultHigh; preferred.active = YES;
        [body addArrangedSubview:[self description:_NS("Playlist Name (optional)") copy:_NS("The playlist will be saved and displayed with this title.")]];
        [body addArrangedSubview:_nameField];
    } else {
        NSStackView *details = [[NSStackView alloc] init]; details.spacing = 20; details.alignment = NSLayoutAttributeBottom;
        NSStackView *fields = [NSStackView stackViewWithViews:@[[self description:_NS("Playlist Details") copy:_NS("The playlist will be saved and displayed with this title and thumbnail.")], _nameField]];
        fields.orientation = NSUserInterfaceLayoutOrientationVertical; fields.alignment = NSLayoutAttributeLeading; fields.spacing = 20;
        [_nameField.widthAnchor constraintEqualToAnchor:fields.widthAnchor].active = YES;
        [details addArrangedSubview:fields];
        _coverButton = [NSButton buttonWithTitle:@"" target:self action:@selector(chooseCover:)];
        _coverButton.image = [NSImage vlc_redesignImageNamed:@"add"]; _coverButton.image.size = NSMakeSize(24,24);
        _coverButton.accessibilityLabel = _NS("Thumbnail"); _coverButton.imageScaling = NSImageScaleProportionallyUpOrDown;
        [details addArrangedSubview:_coverButton]; [_coverButton.widthAnchor constraintEqualToConstant:112].active = YES; [_coverButton.heightAnchor constraintEqualToConstant:112].active = YES;
        [body addArrangedSubview:details];
        NSBox *divider = [[NSBox alloc] init]; divider.boxType = NSBoxSeparator; [body addArrangedSubview:divider];
        [body addArrangedSubview:[self description:_NS("Select Files") copy:_NS("These files will be added to the playlist.")]];
        VLCCollectionFilesView *files = [[VLCCollectionFilesView alloc] init];
        __weak typeof(self) weakSelf = self; files.receiveURLs = ^(NSArray<NSURL *> *URLs) { [weakSelf addFiles:URLs]; };
        NSButton *choose = [NSButton buttonWithTitle:_NS("Drag files into the box or click here to select files.") target:self action:@selector(chooseFiles:)];
        choose.image = [NSImage vlc_redesignImageNamed:@"add"]; choose.image.size = NSMakeSize(24,24); choose.imagePosition = NSImageBelow;
        choose.bordered = NO; choose.translatesAutoresizingMaskIntoConstraints = NO; [files addSubview:choose];
        NSScrollView *scroll = [[NSScrollView alloc] init]; scroll.hasVerticalScroller = YES; scroll.drawsBackground = NO;
        scroll.translatesAutoresizingMaskIntoConstraints = NO; [files addSubview:scroll];
        _filesTable = [[NSTableView alloc] init]; _filesTable.headerView = nil; _filesTable.rowHeight = 32;
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"file"]; column.width = 580; [_filesTable addTableColumn:column];
        _filesTable.dataSource = self; _filesTable.delegate = self; scroll.documentView = _filesTable;
        [NSLayoutConstraint activateConstraints:@[[choose.topAnchor constraintEqualToAnchor:files.topAnchor constant:8], [choose.leadingAnchor constraintEqualToAnchor:files.leadingAnchor constant:12], [choose.trailingAnchor constraintEqualToAnchor:files.trailingAnchor constant:-12], [choose.heightAnchor constraintEqualToConstant:40], [scroll.topAnchor constraintEqualToAnchor:choose.bottomAnchor constant:8], [scroll.bottomAnchor constraintEqualToAnchor:files.bottomAnchor constant:-8], [scroll.leadingAnchor constraintEqualToAnchor:files.leadingAnchor constant:12], [scroll.trailingAnchor constraintEqualToAnchor:files.trailingAnchor constant:-12]]];
        [body addArrangedSubview:files]; [files.heightAnchor constraintGreaterThanOrEqualToConstant:112].active = YES;
        NSLayoutConstraint *preferred = [files.heightAnchor constraintEqualToConstant:186]; preferred.priority = NSLayoutPriorityDefaultHigh; preferred.active = YES;
    }
    for (NSView *view in body.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:body.widthAnchor].active = YES;
    NSView *footer = [[NSView alloc] init]; footer.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:footer];
    NSButton *cancel = [NSButton buttonWithTitle:_NS("Cancel") target:self action:@selector(cancel:)]; cancel.keyEquivalent = @"\e";
    _saveButton = [NSButton buttonWithTitle:_NS("Save") target:self action:@selector(accept:)]; _saveButton.keyEquivalent = @"\r";
    cancel.translatesAutoresizingMaskIntoConstraints = NO; _saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:cancel]; [footer addSubview:_saveButton];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor], [header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor], [header.topAnchor constraintEqualToAnchor:root.topAnchor], [header.heightAnchor constraintEqualToConstant:50],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20], [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [close.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-9], [close.centerYAnchor constraintEqualToAnchor:header.centerYAnchor], [close.widthAnchor constraintEqualToConstant:32], [close.heightAnchor constraintEqualToConstant:32],
        [body.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20], [body.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20], [body.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:22], [body.bottomAnchor constraintLessThanOrEqualToAnchor:footer.topAnchor constant:-22],
        [footer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor], [footer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor], [footer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor], [footer.heightAnchor constraintEqualToConstant:72],
        [cancel.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:20], [cancel.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor], [cancel.widthAnchor constraintEqualToConstant:100], [cancel.heightAnchor constraintEqualToConstant:32],
        [_saveButton.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-20], [_saveButton.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor], [_saveButton.widthAnchor constraintEqualToConstant:100], [_saveButton.heightAnchor constraintEqualToConstant:32]
    ]];
    if (network) {
        NSButton *advanced = [NSButton buttonWithTitle:_NS("Advanced") target:self action:@selector(advanced:)]; advanced.translatesAutoresizingMaskIntoConstraints = NO; [footer addSubview:advanced];
        [NSLayoutConstraint activateConstraints:@[[advanced.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor], [advanced.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor]]];
    }
    [root vlc_applyRedesignStyle]; [self updateAccept]; [window center]; return self;
}
- (NSString *)playlistName { return [self.nameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
- (NSArray<NSURL *> *)mediaURLs
{
    if (!self.network) return self.selectedFiles.copy;
    NSMutableArray *URLs = [NSMutableArray array];
    for (NSString *line in [self.URLsField.string componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *value = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (!value.length) continue;
        char *uri = [value containsString:@"://"] ? vlc_uri_fixup(value.UTF8String) : vlc_path2uri(value.UTF8String, NULL);
        if (!uri) continue; NSURL *url = [NSURL URLWithString:toNSStr(uri)]; free(uri); if (url.scheme.length) [URLs addObject:url];
    }
    return URLs;
}
- (void)setAllowsPlaylistSaving:(BOOL)allowed { _allowsPlaylistSaving = allowed; self.nameField.enabled = allowed; [self updateAccept]; }
- (void)updateAccept { self.saveButton.title = self.network && !self.playlistName.length ? _NS("Play") : _NS("Save"); self.saveButton.enabled = self.network ? self.mediaURLs.count > 0 && (!self.playlistName.length || self.allowsPlaylistSaving) : self.playlistName.length > 0 && self.allowsPlaylistSaving; }
- (void)controlTextDidChange:(NSNotification *)notification { [self updateAccept]; }
- (void)textDidChange:(NSNotification *)notification { [self.URLsField setNeedsDisplay:YES]; [self updateAccept]; }
- (void)addFiles:(NSArray<NSURL *> *)URLs { for (NSURL *url in URLs) if (url.isFileURL && ![self.selectedFiles containsObject:url]) [self.selectedFiles addObject:url]; [self.filesTable reloadData]; }
- (void)chooseFiles:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.title = _NS("Select Files"); panel.allowsMultipleSelection = YES; panel.canChooseDirectories = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) { if (response == NSModalResponseOK) [self addFiles:panel.URLs]; }];
}
- (void)chooseCover:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.title = _NS("Thumbnail"); panel.allowedFileTypes = NSImage.imageTypes; panel.canChooseDirectories = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return; NSImage *image = [[NSImage alloc] initWithContentsOfURL:panel.URL]; if (!image) return;
        self.coverURL = panel.URL; self.coverButton.image = image; self.coverButton.toolTip = panel.URL.path;
    }];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.selectedFiles.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    NSTextField *field = [NSTextField labelWithString:self.selectedFiles[row].lastPathComponent ?: self.selectedFiles[row].absoluteString];
    field.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular]; field.textColor = NSColor.VLCControlForegroundColor; field.lineBreakMode = NSLineBreakByTruncatingMiddle; return field;
}
- (NSModalResponse)runModal { self.modal = YES; [self.window makeKeyAndOrderFront:nil]; NSModalResponse response = [NSApp runModalForWindow:self.window]; self.modal = NO; [self.window orderOut:nil]; return response; }
- (void)accept:(id)sender { [self updateAccept]; if (self.saveButton.enabled && self.modal) [NSApp stopModalWithCode:NSModalResponseOK]; }
- (void)cancel:(id)sender { if (self.modal) [NSApp stopModalWithCode:NSModalResponseCancel]; else [self.window close]; }
- (void)advanced:(id)sender { if (self.modal) [NSApp stopModalWithCode:2]; }
- (BOOL)windowShouldClose:(NSWindow *)window { [self cancel:nil]; return !self.modal; }
@end
