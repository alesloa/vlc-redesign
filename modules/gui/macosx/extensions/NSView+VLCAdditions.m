/*****************************************************************************
 * NSView+VLCAdditions.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2013-2019 VLC authors and VideoLAN
 *
 * Authors: David Fuhrmann <dfuhrmann # videolan.org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
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

#import "NSView+VLCAdditions.h"

#import "NSAppearance+VLCAdditions.h"
#import "NSColor+VLCAdditions.h"
#import "NSFont+VLCAdditions.h"
#import "views/VLCUIUnits.h"

@implementation NSView (VLCAdditions)

+ (instancetype)fromNibWithOwner:(id)owner
{
    return [self fromNibNamed:NSStringFromClass(self) withClass:self withOwner:owner];
}

+ (instancetype)fromNibNamed:(NSString *)nibName withClass:(Class)viewClass withOwner:(id)owner
{
    /* the following code saves us an instance of NSViewController which we don't need */
    NSNib *nib = [[NSNib alloc] initWithNibNamed:nibName bundle:nil];
    NSArray *topLevelObjects;
    if (![nib instantiateWithOwner:owner topLevelObjects:&topLevelObjects]) {
        NSAssert(1, @"Failed to load nib file to show view");
        return nil;
    }

    for (id topLevelObject in topLevelObjects) {
        if ([topLevelObject isKindOfClass:viewClass]) {
            return topLevelObject;
            break;
        }
    }

    return nil;
}

- (BOOL)shouldShowDarkAppearance
{
    return self.effectiveAppearance.shouldShowDarkAppearance;
}

- (void)vlc_applyRedesignStyle
{
    // Dynamic NSColors become concrete CGColors for CALayer. Resolve against
    // this view, including category changes made outside an AppKit draw pass.
    NSAppearance *previousAppearance = NSAppearance.currentAppearance;
    if (@available(macOS 10.14, *)) NSAppearance.currentAppearance = self.effectiveAppearance;
    @try {
        [self vlc_applyRedesignStyleWithCurrentAppearance];
    } @finally {
        NSAppearance.currentAppearance = previousAppearance;
    }
}

- (void)vlc_applyRedesignStyleWithCurrentAppearance
{
    if ([self.identifier isEqualToString:@"VLCRedesignedPlayerHeader"]) {
        self.layer.backgroundColor = NSColor.VLCHeaderBackgroundColor.CGColor;
    }
    if ([self.identifier isEqualToString:@"VLCRedesignedDialogHeader"]) {
        // Figma settings/dialog headers use Dark/BG/B2 (#090909), with the
        // corresponding shared light theme color resolved per effective appearance.
        self.layer.backgroundColor = NSColor.VLCInputBackgroundColor.CGColor;
    }
    if ([self.identifier isEqualToString:@"VLCRedesignedPlaybackBar"]) {
        self.layer.backgroundColor = [NSColor.VLCSurfaceBackgroundColor colorWithAlphaComponent:.95].CGColor;
    }
    if ([self.identifier isEqualToString:@"VLCRedesignedSettingsSidebar"]) {
        self.layer.backgroundColor = NSColor.VLCSurfaceBackgroundColor.CGColor;
    }
    if ([self.identifier isEqualToString:@"VLCRedesignedLibraryContent"] ||
        [self.identifier isEqualToString:@"VLCRedesignedNavigationPerimeter"]) {
        self.layer.backgroundColor = NSColor.VLCWindowBackgroundColor.CGColor;
    }
    if ([self.identifier isEqualToString:@"VLCRedesignedQueuePane"]) {
        // Figma Queue463:831 uses95% of the shared sidebar surface in each theme.
        self.layer.backgroundColor = [NSColor.VLCWindowBackgroundColor colorWithAlphaComponent:.95].CGColor;
    }
    if ([self.identifier isEqualToString:@"VLCRedesignedSettingsCard"]) {
        self.layer.backgroundColor = NSColor.VLCInputBackgroundColor.CGColor;
    }
    if ([self isKindOfClass:NSTextField.class]) {
        NSTextField *field = (NSTextField *)self;
        if (field.font != nil) {
            NSFontTraitMask traits = [NSFontManager.sharedFontManager traitsOfFont:field.font];
            field.font = [NSFont vlc_redesignFontOfSize:field.font.pointSize weight:(traits & NSBoldFontMask) ? NSFontWeightSemibold : NSFontWeightRegular];
        }
        field.textColor = field.enabled ? NSColor.VLCControlForegroundColor : NSColor.disabledControlTextColor;
        // Figma fields use the shared B2 input surface; native formatters,
        // editing delegates, focus rings and validation remain unchanged.
        if (field.drawsBackground) field.backgroundColor = NSColor.VLCInputBackgroundColor;
    } else if ([self isKindOfClass:NSBox.class]) {
        NSBox *box = (NSBox *)self;
        if (box.boxType != NSBoxSeparator && box.titlePosition != NSNoTitle) {
            box.titleFont = [NSFont vlc_redesignFontOfSize:13. weight:NSFontWeightSemibold];
            box.borderType = NSLineBorder;
            box.wantsLayer = YES;
            box.layer.cornerRadius = VLCUIUnits.cornerRadius;
        }
    } else if ([self isKindOfClass:NSScrollView.class]) {
        NSScrollView *scrollView = (NSScrollView *)self;
        scrollView.borderType = NSNoBorder;
        scrollView.scrollerStyle = NSScrollerStyleOverlay;
    } else if ([self isKindOfClass:NSTableView.class]) {
        NSTableView *tableView = (NSTableView *)self;
        BOOL queue = [tableView.identifier isEqualToString:@"VLCRedesignedQueueTable"] ||
                     [tableView.identifier isEqualToString:@"VLCRedesignedSidebarTable"];
        tableView.backgroundColor = queue ? NSColor.VLCWindowBackgroundColor : NSColor.VLCSurfaceBackgroundColor;
        tableView.gridStyleMask = NSTableViewGridNone;
        tableView.intercellSpacing = queue ? NSMakeSize(0., 12.) : NSMakeSize(8., 4.);
        tableView.rowHeight = queue ? 32. : MAX(tableView.rowHeight, 24.);
    } else if ([self isKindOfClass:NSCollectionView.class]) {
        ((NSCollectionView *)self).backgroundColors = @[NSColor.VLCWindowBackgroundColor];
    } else if ([self isKindOfClass:NSButton.class]) {
        NSButton *button = (NSButton *)self;
        NSFontTraitMask traits = [NSFontManager.sharedFontManager traitsOfFont:button.font];
        button.font = [NSFont vlc_redesignFontOfSize:button.font.pointSize weight:(traits & NSBoldFontMask) ? NSFontWeightSemibold : NSFontWeightRegular];
        if (@available(macOS 10.14, *)) {
            if ([button.identifier isEqualToString:@"VLCRedesignedSettingsCategory"]) {
                BOOL selected = button.state == NSControlStateValueOn;
                button.layer.backgroundColor = selected ? NSColor.VLCSelectedRowColor.CGColor : nil;
                button.contentTintColor = selected ? NSColor.VLCPrimaryForegroundColor : NSColor.VLCSecondaryForegroundColor;
                return;
            }
            if ([button.identifier isEqualToString:@"VLCPrimaryPlaybackControl"]) {
                button.layer.backgroundColor = NSColor.VLCAccentColor.CGColor;
                // Figma Controls491:1779 Dark/FG/B1 foreground on the primary accent surface.
                button.contentTintColor = [NSColor colorWithSRGBRed:22. / 255. green:22. / 255. blue:22. / 255. alpha:1.];
                return;
            }
            if (button.layer.backgroundColor != nil) {
                return;
            }
            if ([button.keyEquivalent isEqualToString:@"\r"] && button.bezelStyle == NSBezelStyleRounded) {
                button.bezelColor = NSColor.VLCAccentColor;
            }
            button.contentTintColor = button.state == NSControlStateValueOn ?
                NSColor.VLCAccentColor : NSColor.VLCControlForegroundColor;
            // Native checkbox/radio cells place their mark left of a borderless label.
            if (button.imagePosition == NSImageLeft && !button.bordered) {
                NSMutableAttributedString *title = [button.attributedTitle mutableCopy];
                [title addAttribute:NSForegroundColorAttributeName value:NSColor.VLCControlForegroundColor range:NSMakeRange(0, title.length)];
                button.attributedTitle = title;
            }
        }
    }

    if ([self isKindOfClass:NSTabView.class]) {
        // Unselected native tabs are detached from the visible view tree.
        // Update them too so switching tabs retains the current theme.
        for (NSTabViewItem *item in ((NSTabView *)self).tabViewItems)
            [item.view vlc_applyRedesignStyle];
    }
    for (NSView *view in self.subviews) {
        [view vlc_applyRedesignStyle];
    }
}

- (void)enableSubviews:(BOOL)enabled
{
    for (NSView *view in [self subviews]) {
        [view enableSubviews:enabled];

        // enable NSControl
        if ([view respondsToSelector:@selector(setEnabled:)]) {
            [(NSControl *)view setEnabled:enabled];
        }
        // also "enable / disable" text views
        if ([view respondsToSelector:@selector(setTextColor:)]) {
            if (enabled == NO) {
                [(NSTextField *)view setTextColor:[NSColor disabledControlTextColor]];
            } else {
                [(NSTextField *)view setTextColor:[NSColor controlTextColor]];
            }
        }

    }
}

- (NSArray<NSLayoutConstraint *> *)applyConstraintsToFillSuperview
{
    NSAssert(self.superview, @"View must have a valid superview when applying fill constraints!");
    return [self.superview constraintsToFillView:self activate:YES];
}

- (NSArray<NSLayoutConstraint *> *)constraintsToFillView:(NSView *)view activate:(BOOL)activate
{
    NSArray<NSLayoutConstraint *> * const constraints = @[
        [self.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [self.topAnchor constraintEqualToAnchor:view.topAnchor],
        [self.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]
    ];
    if (activate) {
        [NSLayoutConstraint activateConstraints:constraints];
    }
    return constraints;
}

@end
