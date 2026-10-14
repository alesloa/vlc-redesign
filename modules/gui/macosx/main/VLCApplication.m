/*****************************************************************************
 * VLCApplication.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2002-2019 VLC authors and VideoLAN
 *
 * Authors: Derk-Jan Hartman <hartman at videolan.org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
 *          Pierre d'Herbemont <pdherbemont # videolan org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
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

/*****************************************************************************
 * Preamble
 *****************************************************************************/

#import "VLCApplication.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "library/VLCLibraryController.h"
#import "extensions/NSString+Helpers.h"
#import "main/VLCMain.h"
#import <CoreText/CoreText.h>
#import "preferences/VLCSimplePrefsController.h"

#import <vlc_configuration.h>
#import <vlc_interface.h>

/*****************************************************************************
 * VLCApplication implementation
 *****************************************************************************/

@interface VLCWelcomeCanvasView : NSView
@end

@implementation VLCWelcomeCanvasView
- (BOOL)isFlipped { return YES; }
@end

@interface VLCApplication () <NSWindowDelegate>
{
    NSURL *_appLocationURL;
    NSImage *_vlcAppIconImage;
    intf_thread_t *_intf;
    NSWindow *_welcomeWindow;
    NSInteger _welcomePage;
    NSTextField *_welcomeMediaFolderField;
    NSURL *_welcomeMediaFolderURL;
}

@end

@implementation VLCApplication

- (instancetype)init
{
    self = [super init];
    if (self) {
        [NSNotificationCenter.defaultCenter addObserver:self
                                                 selector:@selector(appBecameActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(styleWindow:)
                                                   name:NSWindowDidBecomeKeyNotification
                                                 object:nil];
        // Inter is the Figma typeface; registration is scoped to this VLC process.
        for (NSString *name in @[@"Inter-Regular", @"Inter-Medium", @"Inter-SemiBold", @"Inter-Light"]) {
            NSURL *fontURL = [NSBundle.mainBundle URLForResource:name withExtension:@"ttf"];
            if (fontURL != nil) CTFontManagerRegisterFontsForURL((__bridge CFURLRef)fontURL, kCTFontManagerScopeProcess, NULL);
        }
        [self applyInterfaceAppearance];
        /* we need to keep a file reference to the app's current location so we can find out where
         * it ends-up after being relocated or rename */
        _appLocationURL = [[[NSBundle mainBundle] bundleURL] fileReferenceURL];

        if (config_GetInt("macosx-icon-change")) {
            NSCalendar *const gregorian =
                [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
            const NSUInteger dayOfYear = [gregorian ordinalityOfUnit:NSCalendarUnitDay
                                                              inUnit:NSCalendarUnitYear
                                                             forDate:[NSDate date]];

            if (dayOfYear >= 354) {
                _winterHolidaysTheming = YES;
            }
        }

    }
    return self;
}

- (NSInteger)interfaceAppearance
{
    return [NSUserDefaults.standardUserDefaults integerForKey:@"VLCInterfaceAppearance"];
}

- (void)applyInterfaceAppearance
{
    if (@available(macOS 10.14, *)) {
        switch (self.interfaceAppearance) {
            case 1: self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; break;
            case 2: self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; break;
            default: self.appearance = nil; break;
        }
    }
    NSAppearance *previousDrawingAppearance = NSAppearance.currentAppearance;
    if (@available(macOS 10.14, *)) NSAppearance.currentAppearance = self.effectiveAppearance;
    for (NSWindow *window in self.windows) {
        window.backgroundColor = NSColor.VLCWindowBackgroundColor;
        [window.contentView vlc_applyRedesignStyle];
    }
    NSAppearance.currentAppearance = previousDrawingAppearance;
    if (_welcomeWindow != nil) [self applyWelcomeTypography:_welcomeWindow.contentView];
}

- (void)changeInterfaceAppearance:(NSPopUpButton *)sender
{
    [NSUserDefaults.standardUserDefaults setInteger:sender.indexOfSelectedItem forKey:@"VLCInterfaceAppearance"];
    [self applyInterfaceAppearance];
}

static NSTextField *welcome_label(NSString *text, CGFloat size, NSFontWeight weight)
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.stringValue = text;
    label.font = [NSFont vlc_redesignFontOfSize:size weight:weight];
    label.bordered = NO;
    label.editable = NO;
    label.selectable = NO;
    label.drawsBackground = NO;
    label.textColor = NSColor.VLCControlForegroundColor;
    label.identifier = weight == NSFontWeightLight ? @"VLCWelcomeLightCopy" : @"VLCWelcomeCopy";
    return label;
}

// Figma1902:3978/3980/3990: three100px theme tiles in116px selection rings.
static NSImage *welcome_theme_image(NSInteger appearance, BOOL selected)
{
    return [NSImage imageWithSize:NSMakeSize(116., 116.) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        if (selected) {
            [NSColor.VLCAccentColor setStroke];
            NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 2., 2.) xRadius:22. yRadius:22.];
            ring.lineWidth = 4.;
            [ring stroke];
        }
        NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 8., 8.) xRadius:12. yRadius:12.];
        NSColor *light = [NSColor colorWithSRGBRed:175. / 255. green:175. / 255. blue:175. / 255. alpha:1.];
        NSColor *dark = [NSColor colorWithSRGBRed:27. / 255. green:27. / 255. blue:27. / 255. alpha:1.];
        [(appearance == 1 ? light : dark) setFill];
        [tile fill];
        if (appearance == 0) {
            [NSGraphicsContext saveGraphicsState];
            [tile addClip];
            [light setFill];
            NSBezierPath *half = [NSBezierPath bezierPath];
            [half moveToPoint:NSMakePoint(24., 8.)];
            [half lineToPoint:NSMakePoint(108., 8.)];
            [half lineToPoint:NSMakePoint(108., 108.)];
            [half lineToPoint:NSMakePoint(84., 108.)];
            [half closePath];
            [half fill];
            [NSGraphicsContext restoreGraphicsState];
        }
        return YES;
    }];
}

static void welcome_place(NSView *view, NSView *parent, CGFloat top, CGFloat width, CGFloat height)
{
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.centerXAnchor constraintEqualToAnchor:parent.centerXAnchor],
        [view.topAnchor constraintEqualToAnchor:parent.topAnchor constant:top],
        [view.widthAnchor constraintEqualToConstant:width],
        [view.heightAnchor constraintEqualToConstant:height]
    ]];
}

// The onboarding preview depicts the supplied player's chrome. It contains no
// sample media metadata, timestamps or models, and exposes no playback actions.
static NSImage *welcome_player_preview(void)
{
    return [NSImage imageWithSize:NSMakeSize(1056., 594.) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        [NSColor.VLCInputBackgroundColor setFill]; NSRectFill(rect);
        [NSColor.VLCHeaderBackgroundColor setFill]; NSRectFill(NSMakeRect(0., 0., rect.size.width, 22.));
        [NSColor.VLCSurfaceBackgroundColor setFill]; NSRectFill(NSMakeRect(0., 564., rect.size.width, 30.));
        [[NSImage vlc_redesignImageNamed:@"onboarding-cone"] drawInRect:NSMakeRect(7., 4., 14., 14.)];
        NSArray<NSString *> *icons = @[@"previous", @"play-accent", @"next"];
        for (NSUInteger i = 0; i < icons.count; ++i) {
            CGFloat x = 14. + i * 32.;
            if (i == 1) {
                [NSColor.VLCAccentColor setFill];
                [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x - 6., 570., 28., 18.) xRadius:4. yRadius:4.] fill];
            }
            [[NSImage vlc_redesignImageNamed:icons[i]] drawInRect:NSMakeRect(x, 572., 16., 14.)];
        }
        [NSColor.VLCInputBackgroundColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(140., 571., 720., 16.) xRadius:4. yRadius:4.] fill];
        [NSColor.VLCAccentDimColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(142., 573., 50., 12.) xRadius:2. yRadius:2.] fill];
        [NSColor.VLCAccentColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(188., 573., 4., 12.) xRadius:2. yRadius:2.] fill];
        [[NSImage vlc_redesignImageNamed:@"volume-high"] drawInRect:NSMakeRect(884., 571., 18., 16.)];
        NSArray<NSString *> *trailing = @[@"menu-customize", @"playback-settings", @"queue"];
        for (NSUInteger i = 0; i < trailing.count; ++i)
            [[NSImage vlc_redesignImageNamed:trailing[i]] drawInRect:NSMakeRect(968. + i * 28., 571., 16., 16.)];
        return YES;
    }];
}

// Welcome and page copy is from Figma 1899:3055, 1902:3670 and 1902:6770.
// Shortcut descriptions/values always come from VLC's active configuration.
- (void)showWelcomeIfNeeded
{
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"VLCRedesignWelcomeCompleted"] || _welcomeWindow != nil) return;
    _welcomePage = 0;
    NSRect visible = NSScreen.mainScreen.visibleFrame;
    NSSize size = NSMakeSize(MIN(1090., MAX(780., visible.size.width - 80.)),
                            MIN(759., MAX(640., visible.size.height - 80.)));
    _welcomeWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0., 0., size.width, size.height)
                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                 backing:NSBackingStoreBuffered defer:NO];
    _welcomeWindow.releasedWhenClosed = NO;
    _welcomeWindow.delegate = self;
    _welcomeWindow.titlebarAppearsTransparent = YES;
    _welcomeWindow.contentMinSize = NSMakeSize(780., 640.);
    _welcomeWindow.title = _NS("Welcome");
    _welcomeMediaFolderURL = [NSFileManager.defaultManager URLsForDirectory:NSMoviesDirectory inDomains:NSUserDomainMask].firstObject;
    [self renderWelcomePage];
    [_welcomeWindow center];
    [_welcomeWindow makeKeyAndOrderFront:self];
}

- (NSButton *)welcomeButton:(NSString *)title action:(SEL)action
{
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.bordered = NO;
    button.wantsLayer = YES;
    button.identifier = @"VLCWelcomeButton";
    button.layer.cornerRadius = 6.;
    button.layer.backgroundColor = NSColor.VLCSurfaceBackgroundColor.CGColor;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.font = [NSFont vlc_redesignFontOfSize:16. weight:NSFontWeightSemibold];
    [button.heightAnchor constraintEqualToConstant:32.].active = YES;
    return button;
}

- (void)renderWelcomePage
{
    NSView *root = [[NSView alloc] initWithFrame:_welcomeWindow.contentView.bounds];
    _welcomeWindow.contentView = root;
    _welcomeWindow.backgroundColor = NSColor.VLCWindowBackgroundColor;
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    NSView *page = [[VLCWelcomeCanvasView alloc] initWithFrame:NSMakeRect(0., 0., root.bounds.size.width, 647.)];
    page.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = page;
    [root addSubview:scroll];
    NSLayoutConstraint *pageHeight = [page.heightAnchor constraintEqualToConstant:647.];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-112.],
        [page.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        pageHeight
    ]];
    if (_welcomePage == 0) {
        BOOL compactHeight = root.bounds.size.height < 740.;
        if (compactHeight) pageHeight.constant = MAX(469., root.bounds.size.height - 112.);
        NSImageView *cone = [[NSImageView alloc] init];
        cone.image = [NSImage vlc_redesignImageNamed:@"onboarding-cone"] ?: self.vlcAppIconImage;
        welcome_place(cone, page, compactHeight ? 56. : 116., compactHeight ? 116. : 141., compactHeight ? 116. : 141.);
        NSTextField *title = welcome_label(_NS("Welcome to VLC!"), 32., NSFontWeightLight);
        title.identifier = @"VLCWelcomeTitle";
        title.alignment = NSTextAlignmentCenter;
        welcome_place(title, page, compactHeight ? 195. : 286., 595., 39.);
        NSTextField *introduction = welcome_label(_NS("VLC is a free and open source cross-platform multimedia player and framework that plays most multimedia files as well as DVDs, Audio CDs, VCDs, and various streaming protocols."), 16., NSFontWeightLight);
        introduction.maximumNumberOfLines = 0;
        introduction.cell.wraps = YES;
        introduction.cell.scrollable = NO;
        welcome_place(introduction, page, compactHeight ? 260. : 362., 595., 84.);
        if (VLCMain.sharedInstance.libraryController.libraryModel != nil) {
            NSTextField *folderLabel = welcome_label(_NS("Choose a Media Folder to get started with"), 14., NSFontWeightRegular);
            welcome_place(folderLabel, page, compactHeight ? 376. : 500., 595., 17.);
            _welcomeMediaFolderField = [[NSTextField alloc] init];
            _welcomeMediaFolderField.editable = NO;
            _welcomeMediaFolderField.selectable = YES;
            _welcomeMediaFolderField.stringValue = _welcomeMediaFolderURL.path ?: @"";
            _welcomeMediaFolderField.font = [NSFont vlc_redesignFontOfSize:16. weight:NSFontWeightRegular];
            _welcomeMediaFolderField.translatesAutoresizingMaskIntoConstraints = NO;
            [_welcomeMediaFolderField.heightAnchor constraintEqualToConstant:36.].active = YES;
            [_welcomeMediaFolderField.widthAnchor constraintEqualToConstant:471.].active = YES;
            NSButton *browse = [self welcomeButton:_NS("Browse") action:@selector(browseWelcomeFolder:)];
            NSStackView *folder = [NSStackView stackViewWithViews:@[_welcomeMediaFolderField, browse]];
            folder.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            folder.alignment = NSLayoutAttributeCenterY;
            folder.distribution = NSStackViewDistributionFill;
            folder.spacing = 10.;
            welcome_place(folder, page, compactHeight ? 409. : 533., 595., 36.);
            [browse.widthAnchor constraintEqualToConstant:114.].active = YES;
        }
    } else if (_welcomePage == 1) {
        NSImageView *preview = [[NSImageView alloc] init];
        preview.image = welcome_player_preview();
        preview.imageScaling = NSImageScaleAxesIndependently;
        [preview setContentCompressionResistancePriority:1. forOrientation:NSLayoutConstraintOrientationHorizontal];
        [preview setContentHuggingPriority:1. forOrientation:NSLayoutConstraintOrientationHorizontal];
        [preview setContentCompressionResistancePriority:1. forOrientation:NSLayoutConstraintOrientationVertical];
        [preview setContentHuggingPriority:1. forOrientation:NSLayoutConstraintOrientationVertical];
        preview.accessibilityElement = NO;
        preview.identifier = @"VLCWelcomePreview";
        preview.translatesAutoresizingMaskIntoConstraints = NO;
        [page addSubview:preview];
        [NSLayoutConstraint activateConstraints:@[
            [preview.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:17.],
            [preview.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-17.],
            [preview.topAnchor constraintEqualToAnchor:page.topAnchor constant:18.],
            [preview.heightAnchor constraintEqualToAnchor:preview.widthAnchor multiplier:594. / 1056.]
        ]];
        // Keep the theme captions above the preview's lower controls as its
        // Figma 1056x594 image scales down with the window width.
        CGFloat previewControlsTop = 18. + (root.bounds.size.width - 34.) * 564. / 1056.;
        CGFloat themeOffset = MAX(0., 286. + 157. + 20. - previewControlsTop);
        NSTextField *title = welcome_label(_NS("Select your preferred theme and color."), 24., NSFontWeightLight);
        title.alignment = NSTextAlignmentCenter;
        welcome_place(title, page, 173. - themeOffset, 595., 42.);
        NSMutableArray<NSView *> *themes = [[NSMutableArray alloc] init];
        NSArray<NSString *> *names = @[_NS("Light"), _NS("Dark"), _NS("System")];
        NSInteger appearances[] = {1, 2, 0};
        for (NSUInteger index = 0; index < names.count; ++index) {
            NSButton *theme = [NSButton buttonWithTitle:@"" target:self action:@selector(changeWelcomeTheme:)];
            theme.tag = appearances[index];
            theme.bordered = NO;
            theme.image = welcome_theme_image(theme.tag, theme.tag == self.interfaceAppearance);
            theme.imageScaling = NSImageScaleNone;
            theme.accessibilityLabel = names[index];
            theme.translatesAutoresizingMaskIntoConstraints = NO;
            if (@available(macOS 10.14, *)) theme.enabled = YES;
            else theme.enabled = NO;
            [NSLayoutConstraint activateConstraints:@[[theme.widthAnchor constraintEqualToConstant:116.], [theme.heightAnchor constraintEqualToConstant:116.]]];
            NSTextField *label = welcome_label(names[index], 16., NSFontWeightLight);
            label.alignment = NSTextAlignmentCenter;
            [label.heightAnchor constraintEqualToConstant:24.].active = YES;
            NSStackView *column = [NSStackView stackViewWithViews:@[theme, label]];
            column.orientation = NSUserInterfaceLayoutOrientationVertical;
            column.spacing = 17.;
            [themes addObject:column];
        }
        NSStackView *themeRow = [NSStackView stackViewWithViews:themes];
        themeRow.identifier = @"VLCWelcomeThemes";
        themeRow.spacing = 40.;
        welcome_place(themeRow, page, 286. - themeOffset, 428., 157.);
        // Original exported64px swatches and values from Figma1902:3670.
        NSArray<NSString *> *colors = @[@"orange", @"red", @"yellow", @"green", @"cyan", @"blue", @"purple", @"pink", @"gray"];
        NSArray<NSNumber *> *values = @[@0, @0xE15032, @0xC49E23, @0x19A234, @0x18AAD3, @0x185DD3, @0x8E42FF, @0xF052B3, @0xAFAFAF];
        NSInteger selected = [NSUserDefaults.standardUserDefaults integerForKey:@"VLCInterfaceAccentColor"];
        NSMutableArray<NSView *> *swatches = [[NSMutableArray alloc] init];
        for (NSUInteger index = 0; index < colors.count; ++index) {
            NSButton *swatch = [NSButton buttonWithTitle:@"" target:self action:@selector(changeWelcomeAccent:)];
            swatch.tag = values[index].integerValue;
            swatch.bordered = NO;
            NSString *name = [@"onboarding-accent-" stringByAppendingString:colors[index]];
            if (selected == swatch.tag) name = [name stringByAppendingString:@"-active"];
            swatch.image = [NSImage vlc_redesignImageNamed:name];
            swatch.imageScaling = NSImageScaleProportionallyDown;
            swatch.accessibilityLabel = colors[index];
            swatch.translatesAutoresizingMaskIntoConstraints = NO;
            [NSLayoutConstraint activateConstraints:@[[swatch.widthAnchor constraintEqualToConstant:64.], [swatch.heightAnchor constraintEqualToConstant:64.]]];
            [swatches addObject:swatch];
        }
        NSStackView *colorRow = [NSStackView stackViewWithViews:swatches];
        colorRow.spacing = 16.;
        colorRow.translatesAutoresizingMaskIntoConstraints = NO;
        NSScrollView *colorsScroll = [[NSScrollView alloc] init];
        colorsScroll.translatesAutoresizingMaskIntoConstraints = NO;
        colorsScroll.hasHorizontalScroller = YES;
        [colorsScroll setContentCompressionResistancePriority:1. forOrientation:NSLayoutConstraintOrientationHorizontal];
        colorsScroll.drawsBackground = NO;
        // A fixed document frame scrolls independently of the viewport width.
        // Its704px swatch row must not become the window's minimum width.
        NSView *colorDocument = [[NSView alloc] initWithFrame:NSMakeRect(0., 0., 704., 64.)];
        [colorDocument addSubview:colorRow];
        colorsScroll.documentView = colorDocument;
        [root addSubview:colorsScroll];
        [NSLayoutConstraint activateConstraints:@[
            [colorRow.widthAnchor constraintEqualToConstant:704.],
            [colorRow.heightAnchor constraintEqualToConstant:64.],
            [colorRow.leadingAnchor constraintEqualToAnchor:colorDocument.leadingAnchor],
            [colorRow.topAnchor constraintEqualToAnchor:colorDocument.topAnchor],
            [colorsScroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:41.],
            [colorsScroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-40.],
            [colorsScroll.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-386.],
            [colorsScroll.heightAnchor constraintEqualToConstant:64.]
        ]];
    } else {
        NSTextField *title = welcome_label(_NS("Learn the basic keyboard shortcuts."), 24., NSFontWeightRegular);
        title.alignment = NSTextAlignmentCenter;
        welcome_place(title, page, 60., 700., 42.);
        // Actual native bindings and configuration captions, never Figma's
        // illustrative key values. Missing or unbound actions are omitted.
        const char *keys[] = {"key-play-pause", "key-jump-short", "key-jump+short", "key-prev", "key-next", "key-frame-next", "key-subtitle-track", "key-audio-track", "key-toggle-fullscreen", "key-vol-up", "key-vol-down", "key-snapshot", "key-record"};
        NSMutableArray<NSView *> *columns = [[NSMutableArray alloc] init];
        NSMutableArray<NSView *> *rows = [[NSMutableArray alloc] init];
        BOOL compact = root.bounds.size.width < 980.;
        for (NSUInteger index = 0; index < sizeof(keys) / sizeof(keys[0]); ++index) {
            const module_config_t *configuration = config_FindConfig(keys[index]);
            if (configuration == NULL || configuration->psz_text == NULL) continue;
            char *value = config_GetPsz(keys[index]);
            if (value != NULL && value[0] != '\0') {
                NSTextField *label = welcome_label(NSTR(configuration->psz_text), 16., NSFontWeightLight);
                label.lineBreakMode = NSLineBreakByTruncatingTail;
                label.toolTip = label.stringValue;
                label.translatesAutoresizingMaskIntoConstraints = NO;
                [label.widthAnchor constraintEqualToConstant:220.].active = YES;
                NSTextField *shortcut = welcome_label(OSXStringKeyToString(toNSStr(value)), 16., NSFontWeightLight);
                shortcut.identifier = @"VLCWelcomeKeycap";
                shortcut.alignment = NSTextAlignmentCenter;
                shortcut.translatesAutoresizingMaskIntoConstraints = NO;
                [shortcut.widthAnchor constraintGreaterThanOrEqualToConstant:80.].active = YES;
                NSView *keycap = [[NSView alloc] init];
                keycap.identifier = @"VLCWelcomeKeycapSurface";
                keycap.translatesAutoresizingMaskIntoConstraints = NO;
                keycap.wantsLayer = YES;
                keycap.layer.cornerRadius = 12.;
                keycap.layer.borderWidth = 3.;
                [keycap addSubview:shortcut];
                [NSLayoutConstraint activateConstraints:@[
                    [keycap.heightAnchor constraintEqualToConstant:42.],
                    [keycap.widthAnchor constraintGreaterThanOrEqualToConstant:153.],
                    [shortcut.leadingAnchor constraintEqualToAnchor:keycap.leadingAnchor constant:12.],
                    [shortcut.trailingAnchor constraintEqualToAnchor:keycap.trailingAnchor constant:-12.],
                    [shortcut.centerYAnchor constraintEqualToAnchor:keycap.centerYAnchor]
                ]];
                NSStackView *row = [NSStackView stackViewWithViews:@[label, keycap]];
                row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
                row.spacing = 20.;
                [rows addObject:row];
                if (!compact && rows.count == 7) {
                    NSStackView *column = [NSStackView stackViewWithViews:rows];
                    column.orientation = NSUserInterfaceLayoutOrientationVertical;
                    column.alignment = NSLayoutAttributeLeading;
                    column.spacing = 28.;
                    [columns addObject:column];
                    rows = [[NSMutableArray alloc] init];
                }
            }
            free(value);
        }
        if (rows.count != 0) {
            NSStackView *column = [NSStackView stackViewWithViews:rows];
            column.orientation = NSUserInterfaceLayoutOrientationVertical;
            column.alignment = NSLayoutAttributeLeading;
            column.spacing = 28.;
            [columns addObject:column];
            if (compact) pageHeight.constant = MAX(647., 154. + rows.count * 70.);
        }
        NSStackView *shortcuts = [NSStackView stackViewWithViews:columns];
        shortcuts.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        shortcuts.alignment = NSLayoutAttributeTop;
        shortcuts.spacing = 150.;
        shortcuts.translatesAutoresizingMaskIntoConstraints = NO;
        [page addSubview:shortcuts];
        [NSLayoutConstraint activateConstraints:@[
            [shortcuts.centerXAnchor constraintEqualToAnchor:page.centerXAnchor],
            [shortcuts.topAnchor constraintEqualToAnchor:page.topAnchor constant:154.]
        ]];
        NSButton *all = [self welcomeButton:_NS("Find the full list in the menu.") action:@selector(showWelcomeHotkeys:)];
        all.bordered = NO;
        all.layer.backgroundColor = nil;
        all.identifier = @"VLCWelcomeLink";
        all.translatesAutoresizingMaskIntoConstraints = NO;
        [root addSubview:all];
        [NSLayoutConstraint activateConstraints:@[
            [all.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:62.],
            [all.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-72.]
        ]];
    }
    NSButton *privacy = [self welcomeButton:_NS("Privacy / Network Interaction") action:@selector(showWelcomePreferences:)];
    [root addSubview:privacy];
    NSButton *next = [self welcomeButton:_welcomePage == 2 ? _NS("Finish") : _NS("Next") action:@selector(advanceWelcome:)];
    next.keyEquivalent = @"\r";
    next.identifier = @"VLCWelcomePrimaryButton";
    [root addSubview:next];
    [NSLayoutConstraint activateConstraints:@[
        [next.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-62.],
        [next.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-56.],
        [next.widthAnchor constraintEqualToConstant:100.],
        [privacy.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:62.],
        [privacy.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-16.]
    ]];
    if (_welcomePage != 0) {
        NSButton *back = [self welcomeButton:_NS("Back") action:@selector(backWelcome:)];
        [root addSubview:back];
        [NSLayoutConstraint activateConstraints:@[
            [back.trailingAnchor constraintEqualToAnchor:next.leadingAnchor constant:-8.],
            [back.bottomAnchor constraintEqualToAnchor:next.bottomAnchor],
            [back.widthAnchor constraintEqualToConstant:100.]
        ]];
    }
    [root vlc_applyRedesignStyle];
    [self applyWelcomeTypography:root];
}

- (void)applyWelcomeTypography:(NSView *)view
{
    if ([view isKindOfClass:NSButton.class] && [view.identifier hasPrefix:@"VLCWelcome"]) {
        NSButton *button = (NSButton *)view;
        NSAppearance *previous = NSAppearance.currentAppearance;
        if (@available(macOS 10.14, *)) NSAppearance.currentAppearance = view.effectiveAppearance;
        BOOL primary = [view.identifier isEqualToString:@"VLCWelcomePrimaryButton"];
        BOOL link = [view.identifier isEqualToString:@"VLCWelcomeLink"];
        NSColor *foreground = primary ? [NSColor colorWithSRGBRed:22. / 255. green:22. / 255. blue:22. / 255. alpha:1.] : NSColor.VLCControlForegroundColor;
        button.layer.backgroundColor = link ? nil : (primary ? NSColor.VLCAccentColor : NSColor.VLCSurfaceBackgroundColor).CGColor;
        button.font = [NSFont vlc_redesignFontOfSize:16. weight:link ? NSFontWeightRegular : NSFontWeightSemibold];
        button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title attributes:@{
            NSForegroundColorAttributeName:foreground, NSFontAttributeName:button.font
        }];
        if (@available(macOS 10.14, *)) button.contentTintColor = foreground;
        NSAppearance.currentAppearance = previous;
    }
    if ([view isKindOfClass:NSTextField.class] && [view.identifier hasPrefix:@"VLCWelcome"]) {
        NSTextField *label = (NSTextField *)view;
        BOOL light = [view.identifier isEqualToString:@"VLCWelcomeLightCopy"] || [view.identifier isEqualToString:@"VLCWelcomeTitle"] || [view.identifier isEqualToString:@"VLCWelcomeKeycap"];
        label.font = [NSFont vlc_redesignFontOfSize:label.font.pointSize weight:light ? NSFontWeightLight : NSFontWeightRegular];
        label.textColor = [view.identifier isEqualToString:@"VLCWelcomeTitle"] || [view.identifier isEqualToString:@"VLCWelcomeKeycap"] ? NSColor.VLCPrimaryForegroundColor : NSColor.VLCSecondaryForegroundColor;
    }
    if ([view.identifier isEqualToString:@"VLCWelcomeKeycapSurface"]) {
        NSAppearance *previous = NSAppearance.currentAppearance;
        if (@available(macOS 10.14, *)) NSAppearance.currentAppearance = view.effectiveAppearance;
        view.layer.backgroundColor = NSColor.VLCSurfaceBackgroundColor.CGColor;
        view.layer.borderColor = NSColor.VLCSubtleBorderColor.CGColor;
        NSAppearance.currentAppearance = previous;
    }
    for (NSView *child in view.subviews) [self applyWelcomeTypography:child];
}

- (void)browseWelcomeFolder:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = _NS("Add Folder");
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    NSWindow *window = _welcomeWindow;
    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (self->_welcomeWindow != window) return;
        if (response == NSModalResponseOK && panel.URL != nil &&
            [VLCMain.sharedInstance.libraryController addFolderWithFileURL:panel.URL] == VLC_SUCCESS) {
            self->_welcomeMediaFolderURL = panel.URL;
            self->_welcomeMediaFolderField.stringValue = panel.URL.path;
        }
    }];
}

- (void)changeWelcomeTheme:(NSButton *)sender
{
    [NSUserDefaults.standardUserDefaults setInteger:sender.tag forKey:@"VLCInterfaceAppearance"];
    [self applyInterfaceAppearance];
    [self renderWelcomePage];
}

- (void)changeWelcomeAppearance:(NSSegmentedControl *)sender
{
    [NSUserDefaults.standardUserDefaults setInteger:sender.selectedSegment forKey:@"VLCInterfaceAppearance"];
    [self applyInterfaceAppearance];
}

- (void)changeWelcomeAccent:(NSButton *)sender
{
    [NSUserDefaults.standardUserDefaults setInteger:sender.tag forKey:@"VLCInterfaceAccentColor"];
    [self applyInterfaceAppearance];
    [self renderWelcomePage];
}

- (void)showWelcomeHotkeys:(id)sender
{
    // Forward the existing promoted menu action to its actual controller.
    for (NSMenuItem *menu in NSApp.mainMenu.itemArray)
        for (NSMenuItem *item in menu.submenu.itemArray)
            if (item.action == @selector(showHotkeys:) && item.enabled) {
                [NSApp sendAction:item.action to:item.target from:sender];
                return;
            }
    [VLCMain.sharedInstance.simplePreferences showSimplePrefs];
    [VLCMain.sharedInstance.simplePreferences showHotkeySettings];
}

- (void)advanceWelcome:(id)sender
{
    if (_welcomePage == 2) [self completeWelcome:sender];
    else { ++_welcomePage; [self renderWelcomePage]; }
}

- (void)backWelcome:(id)sender
{
    if (_welcomePage > 0) { --_welcomePage; [self renderWelcomePage]; }
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
    if (notification.object == _welcomeWindow) [self renderWelcomePage];
}

- (void)windowWillClose:(NSNotification *)notification
{
    if (notification.object == _welcomeWindow) {
        _welcomeWindow = nil;
        _welcomeMediaFolderField = nil;
    }
}

- (void)showWelcomePreferences:(id)sender
{
    [VLCMain.sharedInstance.simplePreferences showSimplePrefs];
    [VLCMain.sharedInstance.simplePreferences showPrivacySettings];
}

- (void)completeWelcome:(id)sender
{
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"VLCRedesignWelcomeCompleted"];
    [_welcomeWindow close];
    _welcomeWindow = nil;
}

- (void)styleWindow:(NSNotification *)notification
{
    NSWindow *window = notification.object;
    window.backgroundColor = NSColor.VLCWindowBackgroundColor;
    [window.contentView vlc_applyRedesignStyle];
    if (window == _welcomeWindow) [self applyWelcomeTypography:window.contentView];
}

- (void)setIntf:(intf_thread_t*)intf
{
    _intf = intf;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSImage *)vlcAppIconImage
{
    NSAssert(NSThread.isMainThread, @"I must be called from the main thread only!");

    // If we already have an image, immediately return that
    if (_vlcAppIconImage != nil)
        return _vlcAppIconImage;

    if (self.winterHolidaysTheming) {
        /* After day 354 of the year, the usual VLC cone is replaced by another cone
         * wearing a Father Xmas hat.
         * Note: this icon doesn't represent an endorsement of The Coca-Cola Company.
         */
        _vlcAppIconImage = NSImage.VLCXmasAppIconImage;
    }

    if (_vlcAppIconImage == nil)
        _vlcAppIconImage = NSImage.VLCAppIconImage;

    return _vlcAppIconImage;
}

- (void)appBecameActive:(NSNotification *)aNotification
{
    if ([[[NSBundle mainBundle] bundleURL] checkResourceIsReachableAndReturnError:nil]) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setAlertStyle:NSAlertStyleCritical];
    [alert setMessageText:_NS("VLC has been moved or renamed")];
    [alert setInformativeText:_NS("To prevent errors, VLC must be relaunched.\n\nIf you cannot quit immediately, click Continue, then quit and relaunch as soon as possible to avoid problems.")];
    [alert addButtonWithTitle:_NS("Restart")];
    [alert addButtonWithTitle:_NS("Quit")];
    [alert addButtonWithTitle:_NS("Continue (Not Recommended)")];

    NSInteger alertButton = [alert runModal];

    if (alertButton == NSAlertThirdButtonReturn) {
        return;
    }

    if (alertButton == NSAlertFirstButtonReturn) {
        /* terminate and restart
         * NOTE you may not use [VLCMain relaunchApplication] here as it depends on the app not having moved and WILL crash */
        [NSWorkspace.sharedWorkspace launchApplicationAtURL:_appLocationURL.absoluteURL
                                                      options:NSWorkspaceLaunchNewInstance
                                                configuration:@{}
                                                        error:nil];
    }

    [self terminate:self];
}

// when user selects the quit menu from dock it sends a terminate:
// but we need to send a stop: to properly exits libvlc.
// However, we are not able to change the action-method sent by this standard menu item.
// thus we override terminate: to send a stop:
- (void)terminate:(id)sender
{
    [self activateIgnoringOtherApps:YES];
    libvlc_Quit(vlc_object_instance(_intf));
}

@end
