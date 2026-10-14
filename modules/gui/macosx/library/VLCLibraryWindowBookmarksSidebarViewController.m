/* GUI-only bookmark sidebar. Geometry comes from Figma node 6320:13763;
 * labels and actions come from VLCBookmarksWindowController and its data source. */
#import "VLCLibraryWindowBookmarksSidebarViewController.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "main/VLCMain.h"
#import "panels/bookmarks/VLCBookmark.h"
#import "panels/bookmarks/VLCBookmarksTableViewDataSource.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import <vlc_media_library.h>

@interface VLCBookmarkSidebarTable : NSTableView
@property (copy) void (^didReload)(void);
@property (copy) void (^activateSelection)(void);
@property (copy) void (^removeSelection)(void);
@end
@implementation VLCBookmarkSidebarTable
- (void)reloadData { [super reloadData]; if (self.didReload) self.didReload(); }
- (void)keyDown:(NSEvent *)event
{
    // Preserve the original Queue's Return/Delete keyboard conventions.
    unichar key = event.characters.length ? [event.characters characterAtIndex:0] : 0;
    if (key == NSEnterCharacter || key == NSCarriageReturnCharacter) {
        if (self.activateSelection) self.activateSelection();
    } else if (key == NSDeleteCharacter || key == NSDeleteFunctionKey ||
               key == NSDeleteCharFunctionKey || key == NSBackspaceCharacter) {
        if (self.removeSelection) self.removeSelection();
    } else {
        [super keyDown:event];
    }
}
@end

@interface VLCLibraryWindowBookmarksSidebarViewController ()
@property VLCBookmarksTableViewDataSource *bookmarkDataSource;
@property VLCBookmarkSidebarTable *tableView;
@property NSButton *addButton;
@property NSButton *removeButton;
@end

@implementation VLCLibraryWindowBookmarksSidebarViewController
- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    return [super initWithNibName:nil bundle:nil];
}
- (NSString *)title { return _NS("Bookmarks"); }
- (BOOL)supportsItemCount { return YES; }
- (void)loadView
{
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 500)];
    self.view.wantsLayer = YES;
    self.view.identifier = @"VLCRedesignedLibraryContent";
    self.view.layer.backgroundColor = NSColor.VLCWindowBackgroundColor.CGColor;
    NSStackView *actions = [[NSStackView alloc] init];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 4;
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    _addButton = [self actionButton:_NS("Add") image:@"add" action:@selector(addBookmark:)];
    _removeButton = [self actionButton:_NS("Remove") image:@"remove" action:@selector(removeBookmarks:)];
    [actions addArrangedSubview:_removeButton];
    [actions addArrangedSubview:_addButton];
    [self.view addSubview:actions];
    _tableView = [[VLCBookmarkSidebarTable alloc] init];
    _tableView.identifier = @"VLCRedesignedSidebarTable";
    _tableView.rowHeight = 32;
    _tableView.intercellSpacing = NSMakeSize(0, 12);
    _tableView.headerView = nil;
    _tableView.backgroundColor = NSColor.VLCWindowBackgroundColor;
    _tableView.allowsMultipleSelection = YES;
    _tableView.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.target = self;
    _tableView.doubleAction = @selector(gotoBookmark:);
    NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:VLCBookmarksTableViewNameTableColumnIdentifier];
    name.width = 250; name.minWidth = 60;
    NSTableColumn *time = [[NSTableColumn alloc] initWithIdentifier:VLCBookmarksTableViewTimeTableColumnIdentifier];
    time.width = 116; time.minWidth = 116; time.maxWidth = 116;
    [_tableView addTableColumn:name]; [_tableView addTableColumn:time];
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = _tableView;
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [actions.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:6],
        [actions.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [actions.heightAnchor constraintEqualToConstant:32],
        [scroll.topAnchor constraintEqualToAnchor:actions.bottomAnchor constant:6],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-20]
    ]];
    __weak typeof(self) weakSelf = self;
    _tableView.didReload = ^{ [weakSelf updateState]; };
    _tableView.activateSelection = ^{ [weakSelf gotoBookmarkAtRow:weakSelf.tableView.selectedRow]; };
    _tableView.removeSelection = ^{ [weakSelf removeBookmarks:nil]; };
    // A missing optional library never becomes a clickable bookmark action.
    if (vlc_ml_instance_get(getIntf()) != NULL)
        _bookmarkDataSource = [[VLCBookmarksTableViewDataSource alloc] initWithTableView:_tableView];
    [_tableView reloadData];
    [self.view vlc_applyRedesignStyle];
}
- (NSButton *)actionButton:(NSString *)title image:(NSString *)imageName action:(SEL)action
{
    NSButton *button = [NSButton buttonWithTitle:@"" target:self action:action];
    button.image = [NSImage vlc_redesignImageNamed:imageName];
    button.image.size = NSMakeSize(24, 24);
    button.bordered = NO;
    button.toolTip = title;
    [button setAccessibilityLabel:title];
    [button.widthAnchor constraintEqualToConstant:32].active = YES;
    [button.heightAnchor constraintEqualToConstant:32].active = YES;
    return button;
}
- (void)setCounterLabel:(NSTextField *)counterLabel { _counterLabel = counterLabel; [self updateState]; }
- (void)viewDidLayout
{
    [super viewDidLayout];
    CGFloat width = self.tableView.enclosingScrollView.contentSize.width;
    if (width <= 0.) return;
    [self.tableView setFrameSize:NSMakeSize(width, NSHeight(self.tableView.frame))];
    self.tableView.tableColumns.firstObject.width = MAX(60., width - self.tableView.tableColumns.lastObject.width);
}
- (void)updateState
{
    self.counterLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)self.bookmarkDataSource.bookmarks.count];
    self.addButton.enabled = self.bookmarkDataSource.libraryItemId > 0;
    self.removeButton.enabled = self.tableView.selectedRowIndexes.count > 0;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.bookmarkDataSource.bookmarks.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    VLCBookmark *bookmark = [self.bookmarkDataSource bookmarkForRow:row];
    NSTextField *field = [NSTextField labelWithString:@""];
    field.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
    field.textColor = NSColor.VLCControlForegroundColor;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.toolTip = bookmark.bookmarkDescription;
    if ([column.identifier isEqualToString:VLCBookmarksTableViewTimeTableColumnIdentifier]) {
        // Bookmark timestamps are milliseconds in the existing ML API.
        int64_t seconds = bookmark.bookmarkTime / 1000;
        field.stringValue = [NSString stringWithFormat:@"%02lld:%02lld:%02lld:%03lld", seconds / 3600, seconds / 60 % 60, seconds % 60, bookmark.bookmarkTime % 1000];
        field.alignment = NSTextAlignmentRight;
        field.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    } else {
        field.stringValue = bookmark.bookmarkName ?: @"";
        field.editable = YES;
        field.selectable = YES;
        field.tag = row;
        field.cell.representedObject = [bookmark copy];
        field.target = self;
        field.action = @selector(renameBookmark:);
    }
    return field;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification { [self updateState]; }
- (void)addBookmark:(id)sender { [self.bookmarkDataSource addBookmark]; }
- (void)removeBookmarks:(id)sender
{
    NSMutableArray *selected = [NSMutableArray array];
    [self.tableView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        VLCBookmark *bookmark = [self.bookmarkDataSource bookmarkForRow:row];
        if (bookmark) [selected addObject:bookmark];
    }];
    for (VLCBookmark *bookmark in selected) [self.bookmarkDataSource removeBookmark:bookmark];
}
- (void)renameBookmark:(NSTextField *)sender
{
    VLCBookmark *original = sender.cell.representedObject;
    if (!original || original.mediaLibraryItemId != self.bookmarkDataSource.libraryItemId) return;
    VLCBookmark *edited = [original copy]; edited.bookmarkName = sender.stringValue;
    [self.bookmarkDataSource editBookmark:edited originalBookmark:original];
}
- (void)gotoBookmark:(id)sender
{
    [self gotoBookmarkAtRow:self.tableView.clickedRow];
}
- (void)gotoBookmarkAtRow:(NSInteger)row
{
    VLCBookmark *bookmark = [self.bookmarkDataSource bookmarkForRow:row];
    if (bookmark) [VLCMain.sharedInstance.playQueueController.playerController setTimeFast:VLC_TICK_FROM_MS(bookmark.bookmarkTime)];
}
@end
