/*****************************************************************************
 * NSWindow+VLCAdditions.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2023 VLC authors and VideoLAN
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

#import "NSWindow+VLCAdditions.h"
#import "NSView+VLCAdditions.h"
#import "NSFont+VLCAdditions.h"
#import "NSColor+VLCAdditions.h"
#import "NSImage+VLCAdditions.h"
#import "NSString+Helpers.h"

@interface VLCOpaqueDialogBackgroundView : NSView
@end

@implementation VLCOpaqueDialogBackgroundView
- (BOOL)isOpaque { return YES; }
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)drawRect:(NSRect)dirtyRect
{
    // This is the same appearance-aware surface used by Global Settings.
    [[NSColor.VLCWindowBackgroundColor colorWithAlphaComponent:1.] setFill];
    NSRectFill(dirtyRect);
}
- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
    [self.superview vlc_applyRedesignStyle];
}
@end

@implementation NSWindow (Helpers)

- (void)vlc_applyOpaqueRedesignSurface
{
    self.styleMask &= ~NSWindowStyleMaskHUDWindow;
    self.opaque = YES;
    self.alphaValue = 1.;
    self.titlebarAppearsTransparent = NO;
    self.backgroundColor = [NSColor.VLCWindowBackgroundColor colorWithAlphaComponent:1.];

    NSView *body = self.contentView;
    if (!body) return;
    BOOL hasBackground = NO;
    for (NSView *view in body.subviews) {
        if ([view isKindOfClass:VLCOpaqueDialogBackgroundView.class]) {
            view.needsDisplay = YES;
            hasBackground = YES;
            break;
        }
    }
    if (!hasBackground) {
        VLCOpaqueDialogBackgroundView *background = [[VLCOpaqueDialogBackgroundView alloc] initWithFrame:body.bounds];
        background.identifier = @"VLCOpaqueDialogBackground";
        background.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [body addSubview:background positioned:NSWindowBelow relativeTo:nil];
    }
    [body vlc_applyRedesignStyle];
}

- (void)vlc_applyRedesignDialogShell
{
    NSView *body = self.contentView;
    if (!body || !(self.styleMask & NSWindowStyleMaskTitled)) return;
    if ([body.identifier isEqualToString:@"VLCRedesignedSecondaryDialog"]) {
        [self vlc_applyOpaqueRedesignSurface];
        return;
    }
    // Figma settings and secondary dialogs share a 50px title/close header.
    // The caption comes from this existing VLC window; the body keeps all its
    // original outlets, validation, inputs, modal actions and constraints.
    NSSize size = body.frame.size;
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0., 0., size.width, size.height + 50.)];
    root.identifier = @"VLCRedesignedSecondaryDialog";
    NSView *header = [NSView new];
    header.identifier = @"VLCRedesignedDialogHeader";
    header.wantsLayer = YES;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *caption = [NSTextField labelWithString:self.title ?: @""];
    caption.font = [NSFont vlc_redesignFontOfSize:16. weight:NSFontWeightSemibold];
    [caption bind:NSValueBinding toObject:self withKeyPath:@"title" options:nil];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton *close = [NSButton buttonWithTitle:@"" target:self action:@selector(vlc_closeRedesignDialog:)];
    close.bordered = NO;
    close.image = [NSImage vlc_redesignImageNamed:@"settings-close"];
    close.toolTip = _NS("Close");
    close.accessibilityLabel = close.toolTip;
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:caption];
    [header addSubview:close];
    self.contentView = root;
    body.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:body];
    [root addSubview:header];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:root.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:50.],
        [caption.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.],
        [caption.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [caption.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-12.],
        [close.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-12.],
        [close.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:24.],
        [close.heightAnchor constraintEqualToConstant:24.],
        [body.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [body.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [body.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [body.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
    ]];
    self.titleVisibility = NSWindowTitleHidden;
    self.titlebarAppearsTransparent = YES;
    self.backgroundColor = NSColor.VLCWindowBackgroundColor;
    if (self.contentMinSize.height > 0.) self.contentMinSize = NSMakeSize(self.contentMinSize.width, self.contentMinSize.height + 50.);
    [self setContentSize:root.frame.size];
    [root vlc_applyRedesignStyle];
    [self vlc_applyOpaqueRedesignSurface];
}

- (void)vlc_closeRedesignDialog:(id)sender
{
    // Open Media stops its modal loop; Jump to Time delivers the original
    // sheet Cancel callback. Forward to those existing buttons when present.
    NSWindowController *controller = self.windowController;
    SEL cancelSelector = NSSelectorFromString(@"cancelButton");
    if ([controller respondsToSelector:cancelSelector]) {
        NSButton *cancel = (NSButton *)[controller performSelector:cancelSelector];
        if (cancel.enabled && cancel.action && (NSApp.modalWindow == self || self.sheetParent)) {
            [cancel performClick:sender]; return;
        }
    }
    if (NSApp.modalWindow == self) [NSApp stopModalWithCode:NSModalResponseCancel];
    if (self.sheetParent) [self.sheetParent endSheet:self returnCode:NSModalResponseCancel];
    [self performClose:sender];
}

- (CGFloat)titlebarHeight
{
    const NSView * const titlebarView = [self standardWindowButton:NSWindowCloseButton].superview;
    return titlebarView.frame.size.height;
}

@end
