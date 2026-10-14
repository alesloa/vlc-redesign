/* Figma Home 1106:5633 / 6261:15078 and compact library 848:1997.
 * Section copy comes from those frames; labels, counts, paths, progress and
 * artwork come from actual VLC models or the user's existing folder choices. */
#import "VLCCompactLibraryViewController.h"
#import "VLCLibraryNavigationData.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSPasteboardItem+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "library/VLCLibraryController.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibraryImageCache.h"
#import "library/VLCLibraryModel.h"
#import "library/VLCLibraryMenuController.h"
#import "library/VLCLibraryRepresentedItem.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayQueueController.h"
#import "windows/VLCOpenInputMetadata.h"
#import "views/VLCFileDragRecognisingView.h"
#import "views/VLCUIUnits.h"
#include <math.h>

static BOOL libraryInterfaceIsUnavailable(void)
{
    // sharedInstance returns nil after the original interface owner is killed.
    VLCMain *existingOwner = VLCMain.sharedInstance;
    return existingOwner == nil || existingOwner.isTerminating;
}

@interface VLCRedesignLibraryDropView : VLCFileDragRecognisingView <VLCDragDropTarget>
@end
@implementation VLCRedesignLibraryDropView
- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) self.dropTarget = self;
    return self;
}
- (BOOL)handlePasteBoardFromDragSession:(NSPasteboard *)pasteboard
{
    if (libraryInterfaceIsUnavailable() || pasteboard == nil) return NO;
    // Keep the original window's file/URL parsing and autoplay preference.
    NSWindow *target = self.window;
    if (![target respondsToSelector:@selector(handlePasteBoardFromDragSession:)]) return NO;
    return [(id<VLCDragDropTarget>)target handlePasteBoardFromDragSession:pasteboard];
}
@end

@interface VLCRedesignLibraryFlippedView : NSView
@end
@implementation VLCRedesignLibraryFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface VLCRedesignLibraryIconBackdrop : NSView
@property CGFloat cornerRadius;
@end
@implementation VLCRedesignLibraryIconBackdrop
- (void)drawRect:(NSRect)dirtyRect
{
    // Figma full Home 6261:15078 uses #1E1E1E behind folder/playlist icons.
    NSColor *color = self.shouldShowDarkAppearance
        ? [NSColor colorWithSRGBRed:30 / 255. green:30 / 255. blue:30 / 255. alpha:1]
        : NSColor.VLCSurfaceBackgroundColor;
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.cornerRadius yRadius:self.cornerRadius] fill];
}
- (void)viewDidChangeEffectiveAppearance
{
    if (@available(macOS 10.14, *)) [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}
@end

@interface VLCRedesignLibraryFlowLayout : NSCollectionViewFlowLayout
@end
@implementation VLCRedesignLibraryFlowLayout
- (BOOL)shouldInvalidateLayoutForBoundsChange:(NSRect)newBounds
{
    return fabs(NSWidth(newBounds) - NSWidth(self.collectionView.bounds)) > .5 || [super shouldInvalidateLayoutForBoundsChange:newBounds];
}
- (NSCollectionViewLayoutAttributes *)leftAlignedAttributesAtIndexPath:(NSIndexPath *)path
{
    NSCollectionViewLayoutAttributes *attributes = [[super layoutAttributesForItemAtIndexPath:path] copy];
    if (attributes == nil) return nil;
    NSInteger first = path.item;
    while (first > 0) {
        NSCollectionViewLayoutAttributes *previous = [super layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:first - 1 inSection:path.section]];
        if (!previous || fabs(NSMinY(previous.frame) - NSMinY(attributes.frame)) > .5) break;
        --first;
    }
    CGFloat left = self.sectionInset.left;
    for (NSInteger item = first; item < path.item; ++item) {
        NSCollectionViewLayoutAttributes *previous = [super layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:path.section]];
        left += NSWidth(previous.frame) + self.minimumInteritemSpacing;
    }
    NSRect frame = attributes.frame; frame.origin.x = left; attributes.frame = frame;
    return attributes;
}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)path
{
    return [self leftAlignedAttributesAtIndexPath:path];
}
- (NSArray<NSCollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(NSRect)rect
{
    NSMutableArray *attributes = [NSMutableArray array];
    for (NSCollectionViewLayoutAttributes *item in [super layoutAttributesForElementsInRect:rect]) {
        NSCollectionViewLayoutAttributes *aligned = item.representedElementCategory == NSCollectionElementCategoryItem
            ? [self leftAlignedAttributesAtIndexPath:item.indexPath] : item;
        if (aligned) [attributes addObject:aligned];
    }
    return attributes;
}
@end

@interface VLCRedesignLibraryGrid : NSCollectionView
@property (weak) VLCCompactLibraryViewController *controller;
@end
@interface VLCRedesignLibraryTable : NSTableView
@property (weak) VLCCompactLibraryViewController *controller;
@end
@interface VLCCompactLibraryViewController ()
@property NSTableView *tableView;
@property VLCRedesignLibraryGrid *collectionView;
@property NSScrollView *scrollView;
@property NSSearchField *search;
@property NSTextField *titleLabel;
@property NSTextField *countLabel;
@property NSButton *backButton;
@property NSButton *forwardButton;
@property NSButton *searchButton;
@property NSStackView *rail;
@property NSArray *items;
@property NSArray *visibleItems;
@property NSArray<NSDictionary *> *homeSections;
@property NSArray<NSDictionary *> *visibleSections;
@property NSArray *tableItems;
@property NSMutableArray<NSDictionary *> *history;
@property NSInteger historyIndex;
@property VLCLibrarySegmentType segment;
@property NSURL *folder;
@property id<VLCMediaLibraryItemProtocol> parentItem;
@property BOOL gridMode;
@property BOOL descending;
@property BOOL watchedSorting;
@property NSUInteger folderLoadGeneration;
@property NSMapTable<NSURL *, NSNumber *> *directoryValues;
@property NSMapTable<NSURL *, NSImage *> *fileImages;
@property NSMutableSet<NSURL *> *pendingFileMetadata;
@property NSMutableSet<NSURL *> *unavailableFileMetadata;
@property VLCLibraryMenuController *contextMenuController;
@property NSLayoutConstraint *searchHeight;
@property NSLayoutConstraint *searchGap;
- (void)activateRepresentedItem:(id)item;
- (void)activateGridSelection;
- (void)updateMenuForItems:(NSArray *)items;
- (id)sourceItemAtIndexPath:(NSIndexPath *)path;
@end

@implementation VLCRedesignLibraryGrid
- (void)keyDown:(NSEvent *)event
{
    NSString *key = event.charactersIgnoringModifiers;
    if ([key isEqualToString:@"\r"] || [key isEqualToString:@" "]) [self.controller activateGridSelection];
    else [super keyDown:event];
}
- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSIndexPath *path = [self indexPathForItemAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if ([self.controller sourceItemAtIndexPath:path] && ![self.selectionIndexPaths containsObject:path]) self.selectionIndexPaths = [NSSet setWithObject:path];
    NSMutableArray *items = [NSMutableArray array];
    for (NSIndexPath *index in self.selectionIndexPaths) {
        id source = [self.controller sourceItemAtIndexPath:index];
        if (source) [items addObject:source];
    }
    [self.controller updateMenuForItems:items];
    return self.menu;
}
@end
@implementation VLCRedesignLibraryTable
- (void)keyDown:(NSEvent *)event
{
    NSString *key = event.charactersIgnoringModifiers;
    if ([key isEqualToString:@"\r"] || [key isEqualToString:@" "]) [self.controller performSelector:@selector(activateItem:) withObject:self];
    else [super keyDown:event];
}
@end

@interface VLCRedesignLibraryCard : NSCollectionViewItem
@property id sourceItem;
@property NSImageView *artwork;
@property VLCRedesignLibraryIconBackdrop *iconBackdrop;
@property NSTextField *nameLabel;
@property NSTextField *detail;
@property NSView *progress;
@property BOOL fullLibrary;
@property BOOL iconArtwork;
@property (weak) VLCCompactLibraryViewController *controller;
@end
@implementation VLCRedesignLibraryCard
- (void)loadView
{
    self.view = [[VLCRedesignLibraryFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 160, 132)];
    _iconBackdrop = [VLCRedesignLibraryIconBackdrop new];
    [self.view addSubview:_iconBackdrop];
    _artwork = [NSImageView new]; _artwork.imageScaling = NSImageScaleProportionallyUpOrDown;
    _artwork.wantsLayer = YES; _artwork.layer.cornerRadius = 6; _artwork.layer.masksToBounds = YES;
    _nameLabel = [NSTextField labelWithString:@""]; _nameLabel.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail; _nameLabel.textColor = NSColor.VLCControlForegroundColor;
    _detail = [NSTextField labelWithString:@""]; _detail.font = [NSFont vlc_redesignFontOfSize:12 weight:NSFontWeightRegular];
    _detail.textColor = NSColor.VLCSecondaryForegroundColor; _detail.lineBreakMode = NSLineBreakByTruncatingTail;
    _progress = [NSView new]; _progress.wantsLayer = YES; _progress.layer.backgroundColor = NSColor.VLCAccentColor.CGColor;
    [self.view addSubview:_artwork]; [self.view addSubview:_nameLabel]; [self.view addSubview:_detail]; [self.view addSubview:_progress];
    NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(activate:)];
    click.numberOfClicksRequired = 2; [self.view addGestureRecognizer:click];
}
- (void)viewDidLayout
{
    [super viewDidLayout];
    id item = [VLCLibraryNavigationData representedItem:self.sourceItem];
    BOOL video = [item isKindOfClass:VLCMediaLibraryMediaItem.class] && [(VLCMediaLibraryMediaItem *)item mediaType] == VLC_ML_MEDIA_TYPE_VIDEO;
    CGFloat width = NSWidth(self.view.bounds), artworkHeight = video ? width * 9 / 16 : width;
    CGFloat gap = self.fullLibrary ? 20 : 8;
    _iconBackdrop.frame = NSMakeRect(0, 0, width, artworkHeight);
    _iconBackdrop.cornerRadius = self.fullLibrary ? 12 : 6;
    _iconBackdrop.hidden = !self.iconArtwork;
    _iconBackdrop.needsDisplay = YES;
    _artwork.frame = self.iconArtwork ? NSMakeRect((width - 48) / 2, (artworkHeight - 48) / 2, 48, 48) : NSMakeRect(0, 0, width, artworkHeight);
    _artwork.layer.cornerRadius = self.fullLibrary ? 12 : 6;
    _nameLabel.font = [NSFont vlc_redesignFontOfSize:self.fullLibrary ? 16 : 14 weight:NSFontWeightRegular];
    _detail.font = [NSFont vlc_redesignFontOfSize:self.fullLibrary ? 16 : 12 weight:NSFontWeightRegular];
    if (self.fullLibrary) {
        _nameLabel.alignment = NSTextAlignmentLeft;
        _detail.alignment = NSTextAlignmentLeft;
    }
    _nameLabel.frame = NSMakeRect(0, artworkHeight + gap, width, 20);
    _detail.frame = NSMakeRect(0, artworkHeight + gap + 30, width, 20);
    float progress = [item isKindOfClass:VLCMediaLibraryMediaItem.class] ? [(VLCMediaLibraryMediaItem *)item progress] : 0;
    CGFloat barHeight = self.fullLibrary ? 4 : 3;
    _progress.frame = NSMakeRect(0, artworkHeight - barHeight, width * MIN(1, MAX(0, progress)), barHeight);
    _progress.hidden = !isfinite(progress) || progress <= 0;
}
- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    self.view.wantsLayer = YES; self.view.layer.cornerRadius = 6;
    self.view.layer.backgroundColor = (selected ? NSColor.VLCSelectedRowColor : NSColor.clearColor).CGColor;
}
- (void)activate:(id)sender { [self.controller activateRepresentedItem:self.sourceItem]; }
@end

@interface VLCRedesignLibrarySectionHeader : NSView
@property NSButton *button;
@end
@implementation VLCRedesignLibrarySectionHeader
- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _button = [NSButton buttonWithTitle:@"" target:nil action:nil];
        _button.bordered = NO; _button.alignment = NSTextAlignmentLeft;
        _button.image = [NSImage vlc_redesignImageNamed:@"home-chevron"];
        _button.image.size = NSMakeSize(24, 24); _button.imagePosition = NSImageTrailing;
        _button.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_button];
        [NSLayoutConstraint activateConstraints:@[[_button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [_button.centerYAnchor constraintEqualToAnchor:self.centerYAnchor], [_button.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor]]];
    }
    return self;
}
@end

@implementation VLCCompactLibraryViewController
- (BOOL)isHome { return self.segment == VLCLibraryHomeSegmentType && !self.folder && !self.parentItem; }
- (BOOL)isMusic { return self.segment >= VLCLibraryMusicSegmentType && self.segment <= VLCLibraryGenresMusicSubSegmentType; }
- (void)loadView
{
    self.view = [[VLCRedesignLibraryDropView alloc] initWithFrame:NSMakeRect(0, 0, self.fullLibrary ? 1000 : 427, 600)];
    self.view.wantsLayer = YES; self.view.identifier = @"VLCRedesignedLibraryContent";
    self.view.layer.backgroundColor = NSColor.VLCWindowBackgroundColor.CGColor;
    _history = [NSMutableArray array]; _historyIndex = -1; _gridMode = self.fullLibrary;
    _directoryValues = [NSMapTable strongToStrongObjectsMapTable]; _fileImages = [NSMapTable strongToStrongObjectsMapTable];
    _pendingFileMetadata = [NSMutableSet set]; _unavailableFileMetadata = [NSMutableSet set];
    _rail = [NSStackView new]; _rail.orientation = NSUserInterfaceLayoutOrientationVertical;
    _rail.spacing = 14; _rail.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);
    _rail.wantsLayer = YES; _rail.identifier = @"VLCRedesignedSettingsSidebar";
    _rail.layer.backgroundColor = NSColor.VLCSurfaceBackgroundColor.CGColor;
    _rail.translatesAutoresizingMaskIntoConstraints = NO; _rail.hidden = self.fullLibrary;
    [self.view addSubview:_rail];
    NSArray *segments = @[@(VLCLibraryHomeSegmentType), @(VLCLibraryVideoSegmentType), @(VLCLibraryMusicSegmentType), @(VLCLibraryStreamsSegmentType), @(VLCLibraryPlaylistsSegmentType), @(VLCLibraryRecentSegmentType)];
    NSArray *icons = @[@"home", @"videos", @"music", @"network", @"playlists", @"recent"];
    for (NSUInteger index = 0; index < segments.count; ++index) {
        VLCLibrarySegment *segment = [VLCLibrarySegment segmentWithSegmentType:[segments[index] integerValue]];
        NSButton *button = [self button:segment.displayString icon:icons[index] action:@selector(selectSegment:)];
        button.tag = segment.segmentType; button.enabled = !segment.mediaLibraryRequired || VLCMain.sharedInstance.libraryController.libraryModel != nil;
        [_rail addArrangedSubview:button];
    }
    [_rail addArrangedSubview:[self button:_NS("Add item") icon:@"add" action:@selector(add:)]];
    NSView *railSurface = [NSView new]; railSurface.wantsLayer = YES; railSurface.translatesAutoresizingMaskIntoConstraints = NO;
    railSurface.layer.backgroundColor = NSColor.VLCSurfaceBackgroundColor.CGColor; railSurface.hidden = self.fullLibrary;
    [self.view addSubview:railSurface positioned:NSWindowBelow relativeTo:_rail];
    NSView *content = [NSView new]; content.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:content];
    NSStackView *header = [NSStackView new]; header.translatesAutoresizingMaskIntoConstraints = NO; header.spacing = 10;
    _backButton = [self button:_NS("Back") icon:@"library-back" action:@selector(goBack:)];
    _forwardButton = [self button:_NS("Forward") icon:@"library-forward" action:@selector(goForward:)];
    _titleLabel = [NSTextField labelWithString:@""]; _titleLabel.font = [NSFont vlc_redesignFontOfSize:16 weight:NSFontWeightRegular];
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_titleLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addArrangedSubview:_backButton]; [header addArrangedSubview:_forwardButton]; [header addArrangedSubview:_titleLabel];
    NSButton *moreButton = [self button:_NS("Menu") icon:@"library-more" action:@selector(showMore:)];
    [header addArrangedSubview:moreButton];
    if (!self.fullLibrary) [header addArrangedSubview:[self button:_NS("Library") icon:@"library-expand" action:@selector(expand:)]];
    [content addSubview:header];
    NSStackView *tools = [NSStackView new]; tools.translatesAutoresizingMaskIntoConstraints = NO; tools.spacing = 10;
    _countLabel = [NSTextField labelWithString:@""]; _countLabel.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
    _countLabel.textColor = NSColor.VLCSecondaryForegroundColor;
    [_countLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [tools addArrangedSubview:_countLabel];
    [tools addArrangedSubview:[self button:_NS("Select Sorting Mode") icon:@"library-sort" action:@selector(toggleSort:)]];
    [tools addArrangedSubview:[self button:_NS("Grid View or List View") icon:@"library-view" action:@selector(toggleView:)]];
    _searchButton = [self button:_NS("Search") icon:@"library-search" action:@selector(toggleSearch:)]; [tools addArrangedSubview:_searchButton];
    [content addSubview:tools];
    _search = [NSSearchField new]; _search.translatesAutoresizingMaskIntoConstraints = NO; _search.delegate = self;
    _search.placeholderString = _NS("Search"); _search.hidden = !self.fullLibrary;
    [content addSubview:_search];
    if (self.fullLibrary) {
        // Figma full Home keeps navigation at the leading edge and the actual
        // count/search/actions at the trailing edge; compact keeps two rows.
        [tools removeFromSuperview];
        for (NSView *view in header.arrangedSubviews.copy) [header removeView:view];
        header.distribution = NSStackViewDistributionGravityAreas;
        [header setViews:@[_backButton, _forwardButton, _titleLabel] inGravity:NSStackViewGravityLeading];
        [header setViews:@[tools, moreButton] inGravity:NSStackViewGravityTrailing];
        [tools setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_search removeFromSuperview]; [tools addArrangedSubview:_search]; _searchButton.hidden = YES;
        [_countLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSLayoutConstraint *searchWidth = [_search.widthAnchor constraintEqualToConstant:260]; searchWidth.priority = NSLayoutPriorityDefaultHigh; searchWidth.active = YES;
        [_search.widthAnchor constraintGreaterThanOrEqualToConstant:80].active = YES;
    }
    NSView *divider = [NSView new]; divider.translatesAutoresizingMaskIntoConstraints = NO; divider.wantsLayer = YES;
    divider.layer.backgroundColor = NSColor.VLCSubtleBorderColor.CGColor; [content addSubview:divider];
    VLCRedesignLibraryTable *table = [VLCRedesignLibraryTable new]; table.controller = self;
    _tableView = table; _tableView.headerView = nil; _tableView.rowHeight = 32;
    _tableView.intercellSpacing = NSMakeSize(0, 10); _tableView.backgroundColor = NSColor.VLCWindowBackgroundColor;
    _tableView.delegate = self; _tableView.dataSource = self; _tableView.target = self; _tableView.doubleAction = @selector(activateItem:);
    _tableView.allowsMultipleSelection = YES;
    [_tableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
    [_tableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    _contextMenuController = [VLCLibraryMenuController new]; _tableView.menu = _contextMenuController.libraryMenu;
    _tableView.menu.delegate = self;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"library"];
    column.width = 337; column.minWidth = 40; [_tableView addTableColumn:column];
    _collectionView = [VLCRedesignLibraryGrid new]; _collectionView.controller = self;
    _collectionView.dataSource = self; _collectionView.delegate = self; _collectionView.selectable = YES; _collectionView.allowsMultipleSelection = YES;
    [_collectionView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
    [_collectionView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    _collectionView.backgroundColors = @[NSColor.VLCWindowBackgroundColor]; _collectionView.menu = _contextMenuController.libraryMenu;
    NSCollectionViewFlowLayout *layout = [VLCRedesignLibraryFlowLayout new]; layout.minimumInteritemSpacing = 20; layout.minimumLineSpacing = 20;
    layout.sectionInset = NSEdgeInsetsMake(0, 0, 20, 0); _collectionView.collectionViewLayout = layout;
    [_collectionView registerClass:VLCRedesignLibraryCard.class forItemWithIdentifier:@"library-card"];
    [_collectionView registerClass:VLCRedesignLibrarySectionHeader.class forSupplementaryViewOfKind:NSCollectionElementKindSectionHeader withIdentifier:@"library-header"];
    _scrollView = [NSScrollView new]; _scrollView.translatesAutoresizingMaskIntoConstraints = NO; _scrollView.hasVerticalScroller = YES;
    _scrollView.drawsBackground = NO; [content addSubview:_scrollView];
    _searchHeight = [_search.heightAnchor constraintEqualToConstant:self.fullLibrary ? 32 : 0];
    _searchGap = [_search.topAnchor constraintEqualToAnchor:tools.bottomAnchor constant:self.fullLibrary ? 12 : 0];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [_rail.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [_rail.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_rail.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor], [_rail.widthAnchor constraintEqualToConstant:50],
        [railSurface.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [railSurface.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [railSurface.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor], [railSurface.widthAnchor constraintEqualToConstant:50],
        [content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:self.fullLibrary ? 0 : 50],
        [content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [content.topAnchor constraintEqualToAnchor:self.view.topAnchor], [content.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [header.topAnchor constraintEqualToAnchor:content.topAnchor constant:20 + (self.fullLibrary ? VLCUIUnits.libraryWindowContentSafeTopInset : 0)], [header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [header.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20], [header.heightAnchor constraintEqualToConstant:self.fullLibrary ? 32 : 24],
        [divider.topAnchor constraintEqualToAnchor:self.fullLibrary ? header.bottomAnchor : _search.bottomAnchor constant:20], [divider.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:header.trailingAnchor], [divider.heightAnchor constraintEqualToConstant:1],
        [_scrollView.topAnchor constraintEqualToAnchor:divider.bottomAnchor constant:17], [_scrollView.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:header.trailingAnchor], [_scrollView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]
    ]];
    if (self.fullLibrary) [constraints addObject:_searchHeight];
    else [constraints addObjectsFromArray:@[
        [tools.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:20], [tools.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [tools.trailingAnchor constraintEqualToAnchor:header.trailingAnchor], [tools.heightAnchor constraintEqualToConstant:24],
        _searchGap, [_search.leadingAnchor constraintEqualToAnchor:header.leadingAnchor], [_search.trailingAnchor constraintEqualToAnchor:header.trailingAnchor], _searchHeight
    ]];
    [NSLayoutConstraint activateConstraints:constraints];
    for (NSString *name in @[VLCLibraryModelVideoMediaListReset, VLCLibraryModelAudioMediaListReset, VLCLibraryModelRecentsMediaListReset, VLCLibraryModelRecentAudioMediaListReset, VLCLibraryModelVideoMediaItemUpdated, VLCLibraryModelAudioMediaItemUpdated, VLCLibraryModelRecentsMediaItemUpdated, VLCLibraryModelRecentAudioMediaItemUpdated, VLCLibraryModelVideoMediaItemDeleted, VLCLibraryModelAudioMediaItemDeleted, VLCLibraryModelRecentsMediaItemDeleted, VLCLibraryModelRecentAudioMediaItemDeleted, VLCLibraryModelPlaylistAdded, VLCLibraryModelPlaylistUpdated, VLCLibraryModelPlaylistDeleted, VLCLibraryModelArtistListReset, VLCLibraryModelAlbumListReset, VLCLibraryModelGenreListReset, VLCLibraryModelArtistUpdated, VLCLibraryModelAlbumUpdated, VLCLibraryModelGenreUpdated, VLCLibraryModelArtistDeleted, VLCLibraryModelAlbumDeleted, VLCLibraryModelGenreDeleted, VLCLibraryModelAllCachesDropped, VLCLibraryBookmarkedLocationsChanged, VLCLibraryNavigationDataChanged])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(modelChanged:) name:name object:nil];
    [self navigateToSegment:VLCLibraryHomeSegmentType folder:nil parent:nil]; [self.view vlc_applyRedesignStyle];
    self.tableView.intercellSpacing = NSMakeSize(0, 10);
    self.tableView.backgroundColor = NSColor.VLCWindowBackgroundColor;
    self.countLabel.textColor = NSColor.VLCSecondaryForegroundColor;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (NSButton *)button:(NSString *)title icon:(NSString *)name action:(SEL)action
{
    NSButton *button = [NSButton buttonWithTitle:@"" target:self action:action]; button.bordered = NO;
    button.image = [NSImage vlc_redesignImageNamed:name]; button.image.size = NSMakeSize(24, 24);
    button.toolTip = title; button.accessibilityLabel = title;
    CGFloat size = [@[@"home", @"videos", @"music", @"network", @"playlists", @"recent", @"add"] containsObject:name] ? 32 : 24;
    [button.widthAnchor constraintEqualToConstant:size].active = YES; [button.heightAnchor constraintEqualToConstant:size].active = YES;
    return button;
}
- (void)selectSegment:(NSButton *)sender
{
    if (sender.tag == VLCLibraryBrowseSegmentType || sender.tag == VLCLibraryStreamsSegmentType) { if (self.expandLibrary) self.expandLibrary(sender.tag); return; }
    [self navigateToSegment:sender.tag folder:nil parent:nil];
}
- (void)navigateToSegment:(VLCLibrarySegmentType)segment folder:(NSURL *)folder parent:(id<VLCMediaLibraryItemProtocol>)parent
{
    while (self.history.count > self.historyIndex + 1) [self.history removeLastObject];
    [self.history addObject:@{@"segment":@(segment), @"folder":folder ?: NSNull.null, @"parent":(id)parent ?: NSNull.null}];
    self.historyIndex = self.history.count - 1;
    if (folder || parent) [VLCLibraryNavigationData.sharedInstance recordVisitToItem:(id)folder ?: parent];
    [self restoreHistory];
}
- (void)restoreHistory
{
    if (self.historyIndex < 0 || self.historyIndex >= self.history.count) return;
    NSDictionary *state = self.history[self.historyIndex]; self.segment = [state[@"segment"] integerValue];
    self.folder = state[@"folder"] == NSNull.null ? nil : state[@"folder"];
    self.parentItem = state[@"parent"] == NSNull.null ? nil : state[@"parent"];
    self.backButton.enabled = self.historyIndex > 0; self.forwardButton.enabled = self.historyIndex + 1 < self.history.count;
    self.search.stringValue = @""; [self reloadItems];
}
- (void)goBack:(id)sender { if (self.fullLibrary && self.navigateBack) self.navigateBack(); else if (self.historyIndex > 0) { self.historyIndex--; [self restoreHistory]; } }
- (void)goForward:(id)sender { if (self.fullLibrary && self.navigateForward) self.navigateForward(); else if (self.historyIndex + 1 < self.history.count) { self.historyIndex++; [self restoreHistory]; } }
- (void)updateNavigationWithBackwardsAvailable:(BOOL)backwards forwardsAvailable:(BOOL)forwards { self.backButton.enabled = backwards; self.forwardButton.enabled = forwards; }
- (void)modelChanged:(NSNotification *)notification { [self reloadItems]; }
- (void)reloadItems
{
    if (libraryInterfaceIsUnavailable()) return;
    NSUInteger generation = ++self.folderLoadGeneration; self.homeSections = nil;
    VLCLibraryModel *model = VLCMain.sharedInstance.libraryController.libraryModel;
    if (self.isHome) {
        __weak typeof(self) weakSelf = self;
        [VLCLibraryNavigationData.sharedInstance loadHomeWithCompletion:^(NSArray *sections) {
            typeof(self) self = weakSelf; if (!self || self.folderLoadGeneration != generation || libraryInterfaceIsUnavailable()) return;
            self.homeSections = sections; NSMutableArray *items = [NSMutableArray array];
            for (NSDictionary *section in sections) [items addObjectsFromArray:section[@"items"]];
            self.items = items; [self filterItems];
        }];
        self.items = nil;
    } else if (self.folder) {
        NSURL *folder = self.folder; self.items = nil;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{ typeof(self) self = weakSelf; if (!self || self.folderLoadGeneration != generation || libraryInterfaceIsUnavailable()) return; self.items = items; [self filterItems]; });
        });
    } else if (self.parentItem) {
        id parent = self.parentItem; self.items = nil; __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            VLCMain *existingOwner = VLCMain.sharedInstance;
            if (existingOwner == nil || existingOwner.isTerminating) return;
            NSArray *items = [parent mediaItems];
            dispatch_async(dispatch_get_main_queue(), ^{ typeof(self) self = weakSelf; if (!self || self.folderLoadGeneration != generation || libraryInterfaceIsUnavailable()) return; self.items = items; [self filterItems]; });
        });
    } else {
        switch (self.segment) {
            case VLCLibraryVideoSegmentType: self.items = model.listOfVideoMedia; break;
            case VLCLibraryMusicSegmentType: case VLCLibrarySongsMusicSubSegmentType: self.items = model.listOfAudioMedia; break;
            case VLCLibraryArtistsMusicSubSegmentType: self.items = model.listOfArtists; break;
            case VLCLibraryAlbumsMusicSubSegmentType: self.items = model.listOfAlbums; break;
            case VLCLibraryGenresMusicSubSegmentType: self.items = model.listOfGenres; break;
            case VLCLibraryRecentSegmentType: self.items = VLCMediaLibraryRecentItems(model); break;
            case VLCLibraryPlaylistsSegmentType: self.items = [model listOfPlaylistsOfType:VLC_ML_PLAYLIST_TYPE_ALL]; break;
            default: self.items = @[]; break;
        }
    }
    NSString *category = [VLCLibrarySegment segmentWithSegmentType:self.segment].displayString;
    NSString *name = self.folder ? self.folder.lastPathComponent : self.parentItem.displayString;
    self.titleLabel.stringValue = name.length ? [NSString stringWithFormat:@"%@ / %@", category, name] : category;
    [self filterItems];
    for (NSButton *button in self.rail.arrangedSubviews) {
        BOOL selected = button.action == @selector(selectSegment:) && (button.tag == self.segment || (button.tag == VLCLibraryMusicSegmentType && self.isMusic));
        button.wantsLayer = YES; button.layer.cornerRadius = 4; button.layer.backgroundColor = (selected ? NSColor.VLCSelectedRowColor : NSColor.clearColor).CGColor;
        if (@available(macOS 10.14, *)) button.contentTintColor = selected ? NSColor.VLCAccentColor : NSColor.VLCControlForegroundColor;
    }
}
- (NSString *)nameForItem:(id)item { return [VLCLibraryNavigationData titleForItem:item]; }
- (NSArray *)filteredItems:(NSArray *)items
{
    NSString *query = self.search.stringValue;
    NSArray *filtered = [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary *bindings) { return query.length == 0 || [[self nameForItem:item] localizedCaseInsensitiveContainsString:query]; }]];
    return [filtered sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        id first = [VLCLibraryNavigationData representedItem:a], second = [VLCLibraryNavigationData representedItem:b];
        if (self.watchedSorting && [first isKindOfClass:VLCMediaLibraryMediaItem.class] && [second isKindOfClass:VLCMediaLibraryMediaItem.class]) {
            uint32_t firstCount = [first playCount], secondCount = [second playCount];
            if (firstCount != secondCount) return (firstCount < secondCount) != self.descending ? NSOrderedAscending : NSOrderedDescending;
        }
        NSComparisonResult result = [[self nameForItem:a] localizedStandardCompare:[self nameForItem:b]]; return self.descending ? -result : result;
    }];
}
- (void)filterItems
{
    if (libraryInterfaceIsUnavailable()) return;
    self.visibleItems = [self filteredItems:self.items] ?: @[];
    NSMutableArray *sections = [NSMutableArray array], *rows = [NSMutableArray array];
    if (self.isHome) {
        for (NSDictionary *section in self.homeSections) {
            // Keep history/frequency source ordering until a user explicitly sorts.
            NSArray *items = self.search.stringValue.length || self.watchedSorting ? [self filteredItems:section[@"items"]] : section[@"items"];
            if (!items.count) continue;
            if (self.search.stringValue.length == 0) items = [items subarrayWithRange:NSMakeRange(0, MIN(items.count, self.fullLibrary ? 4 : 3))];
            [sections addObject:@{@"title":section[@"title"], @"items":items, @"icon":section[@"icon"]}];
            [rows addObject:@{@"section":section[@"title"], @"sectionIndex":@(sections.count - 1)}]; [rows addObjectsFromArray:items];
        }
    } else { [sections addObject:@{@"title":@"", @"items":self.visibleItems}]; [rows addObjectsFromArray:self.visibleItems]; }
    self.visibleSections = sections; self.tableItems = rows;
    self.countLabel.stringValue = self.items == nil ? @"" : [NSString stringWithFormat:toNSStr(vlc_ngettext("%lu item", "%lu items", self.visibleItems.count)), (unsigned long)self.visibleItems.count];
    // Attaching/resizing a document view can synchronously ask AppKit for old
    // layout paths. Invalidate its old counts before exposing the new snapshot.
    [self.tableView reloadData]; [self.collectionView reloadData];
    NSView *document = self.gridMode ? self.collectionView : self.tableView;
    if (self.scrollView.documentView != document) self.scrollView.documentView = document;
    if (self.gridMode) {
        self.collectionView.frame = NSMakeRect(0, 0, MAX(40, NSWidth(self.scrollView.contentView.bounds)), MAX(40, NSHeight(self.scrollView.contentView.bounds)));
        self.collectionView.autoresizingMask = NSViewWidthSizable;
        [self.collectionView.collectionViewLayout invalidateLayout];
    }
}
- (void)controlTextDidChange:(NSNotification *)notification { [self filterItems]; }
- (void)toggleSearch:(id)sender
{
    BOOL show = self.search.hidden; self.search.hidden = !show; self.searchHeight.constant = show ? 32 : 0; self.searchGap.constant = show ? 12 : 0;
    if (show) [self.view.window makeFirstResponder:self.search]; else { self.search.stringValue = @""; [self filterItems]; [self focusContent]; }
}
- (void)focusContent { [self.view.window makeFirstResponder:self.gridMode ? self.collectionView : self.tableView]; }
- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (self.gridMode) return;
    NSInteger clicked = self.tableView.clickedRow; NSIndexSet *indices = self.tableView.selectedRowIndexes;
    if (clicked >= 0 && ![indices containsIndex:clicked]) indices = [NSIndexSet indexSetWithIndex:clicked];
    NSMutableArray *items = [NSMutableArray array]; [indices enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { if (index < self.tableItems.count) [items addObject:self.tableItems[index]]; }];
    [self updateMenuForItems:items];
}
- (void)updateMenuForItems:(NSArray *)items
{
    NSMutableArray *represented = [NSMutableArray array];
    for (id source in items) {
        id item = [VLCLibraryNavigationData representedItem:source];
        if (![item conformsToProtocol:@protocol(VLCMediaLibraryItemProtocol)]) continue;
        VLCMediaLibraryParentGroupType parent = [self.parentItem isKindOfClass:VLCMediaLibraryPlaylist.class] ? VLCMediaLibraryParentGroupTypePlaylist : VLCMediaLibraryParentGroupTypeUnknown;
        [represented addObject:[[VLCLibraryRepresentedItem alloc] initWithItem:item parentType:parent parentItem:self.parentItem positionInParent:self.parentItem ? [self.items indexOfObject:item] : NSNotFound]];
    }
    self.contextMenuController.representedInputItems = @[]; self.contextMenuController.representedItems = represented;
    NSMenu *menu = self.contextMenuController.libraryMenu;
    NSMenuItem *old = [menu itemWithTag:97601]; if (old) [menu removeItem:old];
    if (items.count == 1 && [VLCLibraryNavigationData serializedIDForItem:items.firstObject]) {
        NSMenuItem *pin = [[NSMenuItem alloc] initWithTitle:[VLCLibraryNavigationData.sharedInstance isPinnedItem:items.firstObject] ? _NS("Unpin") : _NS("Pin") action:@selector(togglePin:) keyEquivalent:@""];
        pin.tag = 97601; pin.target = self; pin.representedObject = items.firstObject; [menu addItem:pin];
    }
}
- (void)togglePin:(NSMenuItem *)sender { [VLCLibraryNavigationData.sharedInstance togglePinForItem:sender.representedObject]; }
- (NSMenu *)musicCategoriesMenu
{
    // Category labels and IDs come from VLC's existing music navigation model.
    NSMenu *menu = [NSMenu new];
    for (NSNumber *value in @[@(VLCLibraryArtistsMusicSubSegmentType), @(VLCLibraryAlbumsMusicSubSegmentType), @(VLCLibrarySongsMusicSubSegmentType), @(VLCLibraryGenresMusicSubSegmentType)]) {
        VLCLibrarySegment *segment = [VLCLibrarySegment segmentWithSegmentType:value.integerValue];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:segment.displayString action:@selector(selectMusicCategory:) keyEquivalent:@""];
        item.target = self; item.representedObject = value;
        item.state = (self.segment == value.integerValue || (self.segment == VLCLibraryMusicSegmentType && value.integerValue == VLCLibrarySongsMusicSubSegmentType)) ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    return menu;
}
- (void)selectMusicCategory:(NSMenuItem *)sender
{
    VLCLibrarySegmentType segment = [sender.representedObject integerValue];
    if (segment < VLCLibraryArtistsMusicSubSegmentType || segment > VLCLibraryGenresMusicSubSegmentType) return;
    [self navigateToSegment:segment folder:nil parent:nil];
}
- (void)showMore:(NSButton *)sender
{
    NSMenu *menu = [NSMenu new];
    for (NSDictionary *action in @[@{@"title":_NS("Add item"), @"selector":NSStringFromSelector(@selector(add:))}, @{@"title":_NS("Browse"), @"selector":NSStringFromSelector(@selector(showBrowse:))}]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:action[@"title"] action:NSSelectorFromString(action[@"selector"]) keyEquivalent:@""]; item.target = self; [menu addItem:item];
    }
    if (self.isMusic) {
        [menu addItem:NSMenuItem.separatorItem];
        NSMenuItem *categories = [[NSMenuItem alloc] initWithTitle:[VLCLibrarySegment segmentWithSegmentType:VLCLibraryMusicSegmentType].displayString action:nil keyEquivalent:@""];
        categories.submenu = [self musicCategoriesMenu]; [menu addItem:categories];
    }
    if (self.parentItem) { NSMenuItem *pin = [[NSMenuItem alloc] initWithTitle:[VLCLibraryNavigationData.sharedInstance isPinnedItem:self.parentItem] ? _NS("Unpin") : _NS("Pin") action:@selector(togglePin:) keyEquivalent:@""]; pin.target = self; pin.representedObject = self.parentItem; [menu addItem:pin]; }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSMaxY(sender.bounds)) inView:sender];
}
- (void)showBrowse:(id)sender { if (self.expandLibrary) self.expandLibrary(VLCLibraryBrowseSegmentType); }
- (void)toggleSort:(NSButton *)sender
{
    NSMenu *menu = [NSMenu new];
    for (NSNumber *descending in @[@NO, @YES]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:descending.boolValue ? _NS("Descending") : _NS("Ascending") action:@selector(selectAlphabeticalSort:) keyEquivalent:@""];
        item.target = self; item.representedObject = descending; item.state = !self.watchedSorting && self.descending == descending.boolValue ? NSControlStateValueOn : NSControlStateValueOff; [menu addItem:item];
    }
    BOOL media = self.items.count > 0 && !self.isHome;
    for (id item in self.items) if (![[VLCLibraryNavigationData representedItem:item] isKindOfClass:VLCMediaLibraryMediaItem.class]) { media = NO; break; }
    for (NSNumber *descending in @[@NO, @YES]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:descending.boolValue ? _NS("Watched First") : _NS("Unwatched First") action:@selector(selectWatchedSort:) keyEquivalent:@""];
        item.target = self; item.representedObject = descending; item.enabled = media; item.state = self.watchedSorting && self.descending == descending.boolValue ? NSControlStateValueOn : NSControlStateValueOff; [menu addItem:item];
    }
    menu.autoenablesItems = NO; [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSMaxY(sender.bounds)) inView:sender];
}
- (void)selectAlphabeticalSort:(NSMenuItem *)sender { self.descending = [sender.representedObject boolValue]; self.watchedSorting = NO; [self filterItems]; }
- (void)selectWatchedSort:(NSMenuItem *)sender { self.descending = [sender.representedObject boolValue]; self.watchedSorting = YES; [self filterItems]; }
- (void)toggleView:(id)sender { self.gridMode = !self.gridMode; [self filterItems]; [self focusContent]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.tableItems.count; }
- (id<NSPasteboardWriting>)pasteboardWriterForSourceItem:(id)source
{
    if (libraryInterfaceIsUnavailable()) return nil;
    id item = [VLCLibraryNavigationData representedItem:source];
    if ([item conformsToProtocol:@protocol(VLCMediaLibraryItemProtocol)])
        return [NSPasteboardItem pasteboardItemWithLibraryItem:item];
    if ([item isKindOfClass:NSURL.class])
        return [NSPasteboardItem pasteboardItemWithInputItem:[VLCInputItem inputItemFromURL:item]];
    return nil;
}
- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    if (tableView != self.tableView || row < 0 || row >= self.tableItems.count) return nil;
    // Section headings have no represented item and must never become a drag.
    return [self pasteboardWriterForSourceItem:self.tableItems[row]];
}
- (id<NSPasteboardWriting>)collectionView:(NSCollectionView *)collectionView pasteboardWriterForItemAtIndexPath:(NSIndexPath *)path
{
    return collectionView == self.collectionView ? [self pasteboardWriterForSourceItem:[self sourceItemAtIndexPath:path]] : nil;
}
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row { return row >= 0 && row < self.tableItems.count && [self.tableItems[row] isKindOfClass:NSDictionary.class] && self.tableItems[row][@"section"] ? 52 : 32; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return row >= 0 && row < self.tableItems.count && (![self.tableItems[row] isKindOfClass:NSDictionary.class] || self.tableItems[row][@"section"] == nil); }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    if (row < 0 || row >= self.tableItems.count || libraryInterfaceIsUnavailable()) return nil;
    id source = self.tableItems[row];
    if ([source isKindOfClass:NSDictionary.class] && source[@"section"]) {
        VLCRedesignLibrarySectionHeader *header = [[VLCRedesignLibrarySectionHeader alloc] initWithFrame:NSMakeRect(0, 0, column.width, 52)];
        header.button.title = source[@"section"]; header.button.font = [NSFont vlc_redesignFontOfSize:16 weight:NSFontWeightRegular];
        if (@available(macOS 10.14, *)) header.button.contentTintColor = NSColor.VLCControlForegroundColor;
        header.button.target = self; header.button.action = @selector(openSection:); header.button.tag = [source[@"sectionIndex"] integerValue]; return header;
    }
    NSView *cell = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, column.width, 32)];
    NSImageView *image = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)]; image.imageScaling = NSImageScaleProportionallyUpOrDown;
    image.wantsLayer = YES; image.layer.cornerRadius = 2; image.layer.masksToBounds = YES; [cell addSubview:image];
    NSTextField *name = [NSTextField labelWithString:[self nameForItem:source]]; name.frame = NSMakeRect(42, 6, MAX(0, column.width - 42), 20);
    name.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular]; name.textColor = NSColor.VLCSecondaryForegroundColor; name.lineBreakMode = NSLineBreakByTruncatingTail; [cell addSubview:name];
    [self loadArtworkForItem:source imageView:image];
    id item = [VLCLibraryNavigationData representedItem:source];
    if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) {
        float progress = [(VLCMediaLibraryMediaItem *)item progress];
        if (isfinite(progress) && progress > 0) { NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 32 * MIN(1, progress), 3)]; bar.wantsLayer = YES; bar.layer.backgroundColor = NSColor.VLCAccentColor.CGColor; [cell addSubview:bar]; }
    }
    return cell;
}
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)collectionView { return self.visibleSections.count; }
- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return section >= 0 && section < self.visibleSections.count ? [self.visibleSections[section][@"items"] count] : 0; }
- (id)sourceItemAtIndexPath:(NSIndexPath *)path
{
    if (path == nil || path.section >= self.visibleSections.count || libraryInterfaceIsUnavailable()) return nil;
    NSArray *items = self.visibleSections[path.section][@"items"];
    return path.item < items.count ? items[path.item] : nil;
}
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)path
{
    id source = [self sourceItemAtIndexPath:path];
    VLCRedesignLibraryCard *card = source ? (id)[collectionView makeItemWithIdentifier:@"library-card" forIndexPath:path] : [VLCRedesignLibraryCard new];
    (void)card.view;
    card.sourceItem = source; card.controller = self;
    card.fullLibrary = self.fullLibrary;
    card.iconArtwork = [card.sourceItem isKindOfClass:NSDictionary.class] && [card.sourceItem[@"icon"] length] > 0;
    card.nameLabel.stringValue = [self nameForItem:card.sourceItem]; id item = [VLCLibraryNavigationData representedItem:card.sourceItem];
    BOOL audio = [item isKindOfClass:VLCMediaLibraryMediaItem.class] && [(VLCMediaLibraryMediaItem *)item mediaType] == VLC_ML_MEDIA_TYPE_AUDIO;
    card.detail.stringValue = audio ? [item primaryDetailString] ?: @"" : @"";
    card.detail.hidden = !audio;
    [self loadArtworkForItem:card.sourceItem imageView:card.artwork]; [card.view setNeedsLayout:YES]; return card;
}
- (NSView *)collectionView:(NSCollectionView *)collectionView viewForSupplementaryElementOfKind:(NSCollectionViewSupplementaryElementKind)kind atIndexPath:(NSIndexPath *)path
{
    if (path == nil || path.section >= self.visibleSections.count) return [NSView new];
    VLCRedesignLibrarySectionHeader *header = (id)[collectionView makeSupplementaryViewOfKind:kind withIdentifier:@"library-header" forIndexPath:path];
    NSDictionary *section = self.visibleSections[path.section];
    header.button.title = section[@"title"] ?: @""; header.button.font = [NSFont vlc_redesignFontOfSize:self.fullLibrary ? 20 : 16 weight:NSFontWeightRegular];
    if (@available(macOS 10.14, *)) header.button.contentTintColor = NSColor.VLCControlForegroundColor;
    header.button.target = self; header.button.action = @selector(openSection:); header.button.tag = path.section; return header;
}
- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path
{
    id source = [self sourceItemAtIndexPath:path];
    if (source == nil) return NSZeroSize;
    id item = [VLCLibraryNavigationData representedItem:source];
    CGFloat width = self.fullLibrary ? ([item isKindOfClass:VLCMediaLibraryMediaItem.class] && [(VLCMediaLibraryMediaItem *)item mediaType] == VLC_ML_MEDIA_TYPE_VIDEO ? 316 : 200) : MAX(96, floor((NSWidth(self.scrollView.contentView.bounds) - 20) / 2));
    width = MIN(width, MAX(40, NSWidth(self.scrollView.contentView.bounds)));
    BOOL square = ![item isKindOfClass:VLCMediaLibraryMediaItem.class] || [(VLCMediaLibraryMediaItem *)item mediaType] != VLC_ML_MEDIA_TYPE_VIDEO;
    BOOL audio = [item isKindOfClass:VLCMediaLibraryMediaItem.class] && [(VLCMediaLibraryMediaItem *)item mediaType] == VLC_ML_MEDIA_TYPE_AUDIO;
    return NSMakeSize(width, (square ? width : width * 9 / 16) + (self.fullLibrary ? 40 : 28) + (audio ? 30 : 0));
}
- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section { return NSMakeSize(NSWidth(collectionView.bounds), self.isHome ? self.fullLibrary ? 64 : 52 : 0); }
- (void)loadArtworkForItem:(id)source imageView:(NSImageView *)image
{
    if (libraryInterfaceIsUnavailable()) return;
    id item = [VLCLibraryNavigationData representedItem:source]; image.image = nil;
    NSString *identity = [VLCLibraryNavigationData serializedIDForItem:source] ?: ([item isKindOfClass:NSURL.class] ? [item absoluteString] : @"");
    image.identifier = identity;
    if (@available(macOS 10.14, *)) image.contentTintColor = NSColor.VLCControlForegroundColor;
    NSString *icon = [source isKindOfClass:NSDictionary.class] ? source[@"icon"] : nil;
    if (icon) { image.image = [NSImage vlc_redesignImageNamed:icon]; return; }
    if ([item isKindOfClass:NSURL.class]) {
        NSNumber *directory = [self.directoryValues objectForKey:item]; if (self.folder == nil) directory = @YES;
        image.image = directory.boolValue ? [NSImage vlc_redesignImageNamed:@"folder"] : [self.fileImages objectForKey:item];
        if (!directory || (!directory.boolValue && image.image == nil)) [self loadMetadataForFileURL:item];
    } else if ([item conformsToProtocol:@protocol(VLCMediaLibraryItemProtocol)]) {
        __weak NSImageView *weakImage = image; __weak VLCCompactLibraryViewController *weakSelf = self;
        NSUInteger generation = self.folderLoadGeneration;
        [VLCLibraryImageCache thumbnailForLibraryItem:item withCompletion:^(const NSImage *thumbnail) {
            if (!libraryInterfaceIsUnavailable() && weakSelf.folderLoadGeneration == generation && [weakImage.identifier isEqualToString:identity]) weakImage.image = (NSImage *)thumbnail;
        }];
    }
}
- (void)openSection:(NSButton *)sender
{
    if (sender.tag < 0 || sender.tag >= self.visibleSections.count) return;
    NSString *icon = self.visibleSections[sender.tag][@"icon"];
    VLCLibrarySegmentType segment = [icon isEqualToString:@"music"] ? VLCLibraryMusicSegmentType : [icon isEqualToString:@"playlists"] ? VLCLibraryPlaylistsSegmentType : [icon isEqualToString:@"folder"] ? VLCLibraryBrowseSegmentType : [icon isEqualToString:@"library-artist"] ? VLCLibraryArtistsMusicSubSegmentType : [icon isEqualToString:@"network"] ? VLCLibraryStreamsSegmentType : VLCLibraryRecentSegmentType;
    if (self.fullLibrary || segment == VLCLibraryBrowseSegmentType || segment == VLCLibraryStreamsSegmentType || segment == VLCLibraryArtistsMusicSubSegmentType) { if (self.expandLibrary) self.expandLibrary(segment); }
    else [self navigateToSegment:segment folder:nil parent:nil];
}
- (void)activateItem:(id)sender { NSInteger row = self.tableView.clickedRow >= 0 ? self.tableView.clickedRow : self.tableView.selectedRow; if (row >= 0 && row < self.tableItems.count) [self activateRepresentedItem:self.tableItems[row]]; }
- (void)activateGridSelection { NSIndexPath *path = self.collectionView.selectionIndexPaths.anyObject; if (path && path.section < self.visibleSections.count && path.item < [self.visibleSections[path.section][@"items"] count]) [self activateRepresentedItem:self.visibleSections[path.section][@"items"][path.item]]; }
- (void)activateRepresentedItem:(id)source
{
    id item = [VLCLibraryNavigationData representedItem:source]; if (item == nil) return;
    if (self.fullLibrary && self.presentLibraryItem && ![item isKindOfClass:VLCMediaLibraryMediaItem.class]) { self.presentLibraryItem(item); return; }
    if ([item isKindOfClass:NSURL.class]) {
        __weak typeof(self) weakSelf = self; NSUInteger generation = self.folderLoadGeneration;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSNumber *directory = nil; [item getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{ typeof(self) self = weakSelf; if (!self || self.folderLoadGeneration != generation || libraryInterfaceIsUnavailable()) return;
                if (directory.boolValue) [self navigateToSegment:self.segment folder:item parent:nil];
                else if (directory != nil) { VLCOpenInputMetadata *metadata = [VLCOpenInputMetadata inputMetaWithPath:[item path]]; if (metadata) [VLCMain.sharedInstance.playQueueController addPlayQueueItems:@[metadata] atPosition:SIZE_MAX startPlayback:YES]; }
            });
        });
    } else if ([item isKindOfClass:VLCMediaLibraryMediaItem.class]) [VLCMain.sharedInstance.libraryController appendItemToPlayQueue:item playImmediately:YES];
    else [self navigateToSegment:self.segment folder:nil parent:item];
}
- (void)expand:(id)sender { if (self.expandSelection) self.expandSelection(self.segment, self.folder, self.parentItem); else if (self.expandLibrary) self.expandLibrary(self.segment); }
- (void)add:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseFiles = YES; panel.canChooseDirectories = YES; panel.allowsMultipleSelection = YES;
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return; NSArray *urls = panel.URLs;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray *files = [NSMutableArray array], *folders = [NSMutableArray array];
            for (NSURL *url in urls) { NSNumber *directory = nil; [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil]; if (directory.boolValue) [folders addObject:url]; else if (directory != nil) { VLCOpenInputMetadata *metadata = [VLCOpenInputMetadata inputMetaWithPath:url.path]; if (metadata) [files addObject:metadata]; } }
            dispatch_async(dispatch_get_main_queue(), ^{ if (libraryInterfaceIsUnavailable()) return; for (NSURL *folder in folders) [VLCMain.sharedInstance.libraryController addFolderWithFileURL:folder]; if (files.count) [VLCMain.sharedInstance.playQueueController addPlayQueueItems:files atPosition:SIZE_MAX startPlayback:NO]; });
        });
    }];
}
- (void)loadMetadataForFileURL:(NSURL *)url
{
    if ([self.pendingFileMetadata containsObject:url] || [self.unavailableFileMetadata containsObject:url]) return; [self.pendingFileMetadata addObject:url];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSNumber *directory = nil; [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil]; NSImage *icon = directory && !directory.boolValue ? [NSWorkspace.sharedWorkspace iconForFile:url.path] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ typeof(self) self = weakSelf; if (!self || libraryInterfaceIsUnavailable()) return; [self.pendingFileMetadata removeObject:url];
            if (directory) [self.directoryValues setObject:directory forKey:url]; else [self.unavailableFileMetadata addObject:url]; if (icon) [self.fileImages setObject:icon forKey:url]; [self.tableView reloadData]; [self.collectionView reloadData];
        });
    });
}
@end
