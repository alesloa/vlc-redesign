/*****************************************************************************
 * VLCPlayQueueTableViewCell.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2019 VLC authors and VideoLAN
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan -dot- org>
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

#import "VLCPlayQueueTableCellView.h"

#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"

#import "library/VLCLibraryImageCache.h"
#import "library/VLCInputItem.h"
#import "library/VLCLibraryDataTypes.h"

#import "main/VLCMain.h"

#import "playqueue/VLCPlayQueueItem.h"

#import "views/VLCImageView.h"

#import <vlc_common.h>
#import <vlc_configuration.h>

NSString * const VLCDisplayTrackNumberPlayQueueKey = @"VLCDisplayTrackNumberPlayQueueKey";
NSString * const VLCDisplayTrackNumberPlayQueueSettingChanged = @"VLCDisplayTrackNumberPlayQueueSettingChanged";
@interface VLCQueueDragGlyph : NSImageView
@end
@implementation VLCQueueDragGlyph
- (NSView *)hitTest:(NSPoint)point {return nil;}
@end
@interface VLCPlayQueueTableCellView ()
@property VLCQueueDragGlyph *dragGlyph;
@property NSButton *removeButton;
@end

@implementation VLCPlayQueueTableCellView
- (instancetype)initWithFrame:(NSRect)frame
{
    self=[super initWithFrame:frame];if(!self)return nil;
    // Figma Queue463:831:32px row,24px drag/remove glyphs,14px caption,
    //12px timestamp. Playlist values and actions remain the existing model.
    _dragGlyph=[[VLCQueueDragGlyph alloc] init];_dragGlyph.image=[NSImage vlc_redesignImageNamed:@"queue-drag"];
    _removeButton=[NSButton buttonWithTitle:@"" target:self action:@selector(removeRepresentedItem:)];
    _removeButton.image=[NSImage vlc_redesignImageNamed:@"queue-remove"];
    _removeButton.bordered=NO;_removeButton.toolTip=_NS("Remove from Play Queue");_removeButton.accessibilityLabel=_removeButton.toolTip;
    NSTextField *title=[NSTextField labelWithString:@""],*duration=[NSTextField labelWithString:@""];
    title.lineBreakMode=NSLineBreakByTruncatingTail;duration.alignment=NSTextAlignmentRight;
    for(NSView *view in @[_dragGlyph,title,duration,_removeButton])[self addSubview:view];
    self.mediaTitleTextField=title;self.durationTextField=duration;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateRepresentation) name:VLCDisplayTrackNumberPlayQueueSettingChanged object:nil];
    [self updateFonts];return self;
}
- (void)layout
{
    [super layout];if(!self.dragGlyph)return;
    CGFloat width=self.bounds.size.width,center=(self.bounds.size.height-24)/2;
    self.dragGlyph.frame=NSMakeRect(0,center,24,24);
    self.removeButton.frame=NSMakeRect(MAX(0,width-24),center,24,24);
    self.durationTextField.frame=NSMakeRect(MAX(32,width-104),(self.bounds.size.height-18)/2,72,18);
    self.mediaTitleTextField.frame=NSMakeRect(32,(self.bounds.size.height-20)/2,MAX(0,width-144),20);
}
- (void)removeRepresentedItem:(id)sender
{
    VLCPlayQueueItem *item=self.representedPlayQueueItem;
    if(item && self.removalHandler)self.removalHandler(item.uniqueID);
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(updateRepresentation)
                                               name:VLCDisplayTrackNumberPlayQueueSettingChanged
                                             object:nil];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self updateFonts];
    [self updateColouredElements];
}

- (void)setRepresentsCurrentPlayQueueItem:(BOOL)representsCurrentPlayQueueItem
{
    _representsCurrentPlayQueueItem = representsCurrentPlayQueueItem;

    [self updateFonts];
    [self updateColouredElements];
}

- (void)updateFonts
{
    if(self.dragGlyph) {
        self.mediaTitleTextField.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
        self.durationTextField.font=[NSFont vlc_redesignFontOfSize:12 weight:NSFontWeightRegular];return;
    }
    NSFont * const displayedFont = _representsCurrentPlayQueueItem ?
        [NSFont boldSystemFontOfSize:NSFont.systemFontSize] :
        [NSFont systemFontOfSize:NSFont.systemFontSize];

    NSFont * const sublineDisplayedFont = _representsCurrentPlayQueueItem ?
        [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize] :
        [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    self.mediaTitleTextField.font = displayedFont;
    self.secondaryMediaTitleTextField.font = displayedFont;
    self.durationTextField.font = displayedFont;
    self.artistTextField.font = sublineDisplayedFont;
}

- (void)updateColouredElements
{
    self.mediaTitleTextField.textColor=NSColor.VLCControlForegroundColor;
    self.durationTextField.textColor=NSColor.VLCSecondaryForegroundColor;
    if(@available(macOS 10.14,*)){
        self.dragGlyph.contentTintColor=self.representsCurrentPlayQueueItem?NSColor.VLCAccentColor:NSColor.VLCSecondaryForegroundColor;
        self.removeButton.contentTintColor=NSColor.VLCSecondaryForegroundColor;
    }
    self.audioMediaTypeIndicator.textColor = _representsCurrentPlayQueueItem ?
        NSColor.labelColor :
        NSColor.secondaryLabelColor;
}

- (void)setRepresentedPlayQueueItem:(VLCPlayQueueItem *)item
{
    _representedPlayQueueItem = item;
    [self updateRepresentation];
}

- (void)updateRepresentation
{
    VLCPlayQueueItem * const item = self.representedPlayQueueItem;

    self.audioArtworkImageView.contentGravity = VLCImageViewContentGravityResizeAspect;
    self.mediaImageView.contentGravity = VLCImageViewContentGravityResizeAspect;

    __weak typeof(self) weakSelf = self;
    if(self.audioArtworkImageView || self.mediaImageView)[VLCLibraryImageCache thumbnailForPlayQueueItem:item withCompletion:^(NSImage * const thumbnail) {
        if (!weakSelf || item != weakSelf.representedPlayQueueItem) {
            return;
        }
        weakSelf.audioArtworkImageView.image = thumbnail;
        weakSelf.mediaImageView.image = thumbnail;
    }];

    const BOOL validArtistString = item.artistName && item.artistName.length > 0;
    const BOOL validAlbumString = item.albumName && item.albumName.length > 0;
    VLCInputItem * const inputItem = item.inputItem;
    VLCMediaLibraryMediaItem * const mediaItem = item.mediaLibraryItem;
    NSString * const libraryTitle = mediaItem.title;
    NSString * const inputTitle = inputItem.title;
    const BOOL validTitleString = libraryTitle.length > 0 || inputTitle.length > 0;

    NSString *playTitle = libraryTitle.length > 0 ? libraryTitle : inputTitle ?: item.title;
    if (validTitleString) {
        NSString * const trackNumberString = inputItem.trackNumber;
        if ([NSUserDefaults.standardUserDefaults boolForKey:VLCDisplayTrackNumberPlayQueueKey] && trackNumberString && trackNumberString.length > 0 && ![trackNumberString isEqualToString:@"0"]) {
            playTitle = [NSString stringWithFormat:@"%@ · %@", trackNumberString, playTitle];
        }
    }

    NSString *songDetailString = @"";
    if(self.dragGlyph){self.mediaTitleTextField.stringValue=playTitle ?: @"";
        self.mediaTitleTextField.toolTip=playTitle;self.durationTextField.stringValue=item.duration==VLC_TICK_INVALID?@"":[NSString stringWithTimeFromTicks:item.duration];
        [self updateFonts];[self updateColouredElements];return;}

    if (validArtistString && validAlbumString) {
        songDetailString = [NSString stringWithFormat:@"%@ · %@", item.artistName, item.albumName];
    } else if (validArtistString) {
        songDetailString = item.artistName;
    }

    if (songDetailString && ![songDetailString isEqualToString:@""]) {
        self.mediaTitleTextField.hidden = YES;
        self.secondaryMediaTitleTextField.hidden = NO;
        self.artistTextField.hidden = NO;
        self.secondaryMediaTitleTextField.stringValue = playTitle;
        self.artistTextField.stringValue = songDetailString;
        self.audioMediaTypeIndicator.hidden = NO;

        self.audioArtworkImageView.hidden = NO;
        self.mediaImageView.hidden = YES;
    } else {
        self.mediaTitleTextField.hidden = NO;
        self.secondaryMediaTitleTextField.hidden = YES;
        self.artistTextField.hidden = YES;
        self.mediaTitleTextField.stringValue = playTitle;
        self.audioMediaTypeIndicator.hidden = YES;

        self.audioArtworkImageView.hidden = YES;
        self.mediaImageView.hidden = NO;
    }

    self.durationTextField.stringValue = [NSString stringWithTimeFromTicks:item.duration];
}

@end
