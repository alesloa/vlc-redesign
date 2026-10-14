/*****************************************************************************
* NSMenu+ItemAddition.m: MacOS X interface module
*****************************************************************************
* Copyright (C) 2020 VLC authors and VideoLAN
*
* Author: Felix Paul Kühne <fkuehne at videolan dot org>
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

#import "NSMenu+VLCAdditions.h"
#import "NSFont+VLCAdditions.h"

@implementation NSMenu (VLCAdditions)

- (void)vlc_applyRedesignMenuStyle
{
    // Figma application/context menu 6062:13354: Inter14. Native menu
    // tracking, enabled states, checkmarks, key equivalents and actions remain AppKit's.
    self.font = [NSFont vlc_redesignFontOfSize:14. weight:NSFontWeightRegular];
    for (NSMenuItem *item in self.itemArray) [item.submenu vlc_applyRedesignMenuStyle];
}

- (void)addMenuItemsFromArray:(NSArray <NSMenuItem *>*)array
{
    if (!array) {
        return;
    }

    for (NSMenuItem *item in array) {
        [self addItem:item];
    }
}

@end
