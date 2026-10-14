/*****************************************************************************
 * VLCLibraryWindowChaptersSidebarViewController.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2024 VLC authors and VideoLAN
 *
 * Authors: Claudio Cambra <developer@claudiocambra.com>
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

#import "VLCLibraryWindowChaptersSidebarViewController.h"

#import "extensions/NSString+Helpers.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSView+VLCAdditions.h"
#import "library/VLCLibraryDataTypes.h"
#import "main/VLCMain.h"
#import "playqueue/VLCPlayerChapter.h"
#import "playqueue/VLCPlayerController.h"
#import "playqueue/VLCPlayQueueController.h"

@interface VLCChapterSidebarTable : NSTableView
@end
@implementation VLCChapterSidebarTable
- (void)keyDown:(NSEvent *)event
{
    unichar key = event.characters.length ? [event.characters characterAtIndex:0] : 0;
    if (key == NSEnterCharacter || key == NSCarriageReturnCharacter) {
        // Chapters are read-only player metadata, not editable queue items.
        // Forward the original chapter selection action rather than the Queue
        // subclass's Return/Delete handlers for an unrelated playlist index.
        [NSApp sendAction:self.action to:self.target from:self];
    } else {
        [super keyDown:event];
    }
}
@end

@interface VLCLibraryWindowChaptersSidebarViewController ()

@property (readwrite) NSUInteger internalItemCount;

@end

@implementation VLCLibraryWindowChaptersSidebarViewController

@synthesize counterLabel = _counterLabel;

- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow
{
    return [super initWithLibraryWindow:libraryWindow
                                nibName:@"VLCLibraryWindowChaptersView"];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _chaptersArrayController = [[NSArrayController alloc] init];

    [self.tableView deselectAll:self];
    // Queue463:831 and its Chapters tab share32px rows/12px gaps,20px
    // margins and a separate utility/count row. Keep all original bindings.
    self.view.identifier = @"VLCRedesignedLibraryContent";
    self.view.wantsLayer = YES;
    self.tableView.identifier = @"VLCRedesignedSidebarTable";
    self.tableView.headerView = nil;
    NSScrollView *scroll = self.tableView.enclosingScrollView;
    NSMutableArray *legacyConstraints = [NSMutableArray array];
    for (NSLayoutConstraint *constraint in self.view.constraints) {
        if (constraint.firstItem == scroll || constraint.secondItem == scroll ||
            constraint.firstItem == self.titleSeparator || constraint.secondItem == self.titleSeparator)
            [legacyConstraints addObject:constraint];
    }
    [NSLayoutConstraint deactivateConstraints:legacyConstraints];
    self.titleSeparator.hidden = YES;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:50.],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20.],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20.],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-20.]
    ]];
    [self.view vlc_applyRedesignStyle];
    [self.tableView bind:NSContentBinding
                toObject:self.chaptersArrayController
             withKeyPath:@"arrangedObjects" 
                 options:nil];
    [self.tableView bind:NSSelectionIndexesBinding 
                toObject:self.chaptersArrayController
             withKeyPath:@"selectionIndexes"
                 options:nil];
    [self.tableView bind:NSSortDescriptorsBinding 
                toObject:self.chaptersArrayController
             withKeyPath:@"sortDescriptors"
                 options:nil];

    [self updateChapterList];
    [self updateSelectedChapter];
    
    NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(titleListChanged:)
                               name:VLCPlayerTitleListChanged
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(chapterSelectionChanged:)
                               name:VLCPlayerChapterSelectionChanged
                             object:nil];
}

- (NSString *)title
{
    return _NS("Chapters");
}

- (BOOL)supportsItemCount
{
    return YES;
}

- (void)setCounterLabel:(NSTextField *)counterLabel
{
    _counterLabel = counterLabel;
    self.counterLabel.stringValue = [NSString stringWithFormat:@"%lu", self.internalItemCount];
}

- (void)titleListChanged:(NSNotification *)notification
{
    [self updateChapterList];
}

- (void)updateChapterList
{
    VLCPlayerController * const playerController =
        VLCMain.sharedInstance.playQueueController.playerController;

    const struct vlc_player_title * const title = playerController.selectedTitle;
    if (title == NULL) {
        self.internalItemCount = 0;
        self.counterLabel.stringValue = @"0";
        self.chaptersArrayController.content = @[];
        return;
    }
    const struct vlc_player_chapter * const pp_chapters = title->chapters;
    const size_t chapterCount = title->chapter_count;

    self.internalItemCount = chapterCount;
    NSMutableArray * const chapters = [NSMutableArray arrayWithCapacity:chapterCount];
    for (size_t i = 0; i < chapterCount; i++) {
        struct vlc_player_chapter p_chapter = pp_chapters[i];
        const vlc_tick_t nextTime = (i + 1 < chapterCount)
            ? pp_chapters[i + 1].time
            : title->length;
        const vlc_tick_t duration = nextTime - p_chapter.time;
        VLCPlayerChapter * const chapter =
            [[VLCPlayerChapter alloc] initWithChapter:&p_chapter duration:duration];
        [chapters addObject:chapter];
    }
    self.chaptersArrayController.content = chapters.copy;
    self.counterLabel.stringValue = [NSString stringWithFormat:@"%lu", chapterCount];
}

- (IBAction)tableViewAction:(id)sender
{
    const NSUInteger selectedIndex = self.chaptersArrayController.selectionIndex;
    if (selectedIndex == NSNotFound || selectedIndex >= self.internalItemCount) {
        return;
    }

    VLCMain.sharedInstance.playQueueController.playerController.selectedChapterIndex =
        selectedIndex;
}

- (void)chapterSelectionChanged:(NSNotification *)notification
{
    [self updateSelectedChapter];
}

- (void)updateSelectedChapter
{
    const NSUInteger selectedChapterIndex =
        VLCMain.sharedInstance.playQueueController.playerController.selectedChapterIndex;
    NSIndexSet * const indexSet = selectedChapterIndex < self.internalItemCount ?
        [NSIndexSet indexSetWithIndex:selectedChapterIndex] : [NSIndexSet indexSet];
    [self.tableView selectRowIndexes:indexSet byExtendingSelection:NO];
}

- (void)viewDidLayout
{
    [super viewDidLayout];
    CGFloat width = self.tableView.enclosingScrollView.contentSize.width;
    if (width <= 0.) return;
    [self.tableView setFrameSize:NSMakeSize(width, NSHeight(self.tableView.frame))];
    if (self.tableView.tableColumns.count == 2) {
        NSTableColumn *time = self.tableView.tableColumns.lastObject;
        time.minWidth = 76.; time.maxWidth = 76.; time.width = 76.;
        self.tableView.tableColumns.firstObject.width = MAX(100., width - 76.);
    }
}

# pragma mark - NSTableView delegation

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row
{
    if ([tableColumn.identifier isEqualToString:@"VLCLibraryWindowChaptersTableViewNameColumnIdentifier"]) {
        NSTableCellView * const cellView =
            [tableView makeViewWithIdentifier:@"VLCLibraryWindowChaptersTableViewNameCellIdentifier"
                                        owner:self];
        [cellView.textField bind:NSValueBinding
                            toObject:cellView
                         withKeyPath:@"objectValue.name"
                             options:nil];
        cellView.textField.font = [NSFont vlc_redesignFontOfSize:14. weight:NSFontWeightRegular];
        cellView.textField.textColor = NSColor.VLCControlForegroundColor;
        cellView.textField.translatesAutoresizingMaskIntoConstraints = YES;
        cellView.textField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
        cellView.textField.frame = NSMakeRect(0., 6., tableColumn.width, 20.);
        return cellView;
    } else if ([tableColumn.identifier isEqualToString:@"VLCLibraryWindowChaptersTableViewTimeColumnIdentifier"]) {
        NSTableCellView * const cellView =
            [tableView makeViewWithIdentifier:@"VLCLibraryWindowChaptersTableViewTimeCellIdentifier"
                                        owner:self];
        [cellView.textField bind:NSValueBinding
                            toObject:cellView
                         withKeyPath:@"objectValue.durationString"
                             options:nil];
        cellView.textField.font = [NSFont vlc_redesignFontOfSize:12. weight:NSFontWeightRegular];
        cellView.textField.textColor = NSColor.VLCSecondaryForegroundColor;
        cellView.textField.alignment = NSTextAlignmentRight;
        cellView.textField.translatesAutoresizingMaskIntoConstraints = YES;
        cellView.textField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
        cellView.textField.frame = NSMakeRect(0., 7., tableColumn.width, 18.);
        return cellView;
    }

    NSAssert(NO, @"Provided cell view for chapters table view should be valid!");
    return nil;
}

@end
