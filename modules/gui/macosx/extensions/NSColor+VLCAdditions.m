/*****************************************************************************
 * NSColor+VLCAdditions.m: MacOS X interface module
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

#import "NSColor+VLCAdditions.h"

@implementation NSColor (VLCAdditions)

// Figma NbLN6ylrDsmWVVTS8Jo10z: Player 187:328 (dark), 2425:13624 (light),
// Settings 3046:9282. Named tokens are mirrored here without changing VLC settings.
static NSColor *redesign_color(NSString *name, unsigned int dark, unsigned int light)
{
    NSColor *(^color)(unsigned int) = ^NSColor *(unsigned int rgb) {
        return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.
                                  green:((rgb >> 8) & 0xff) / 255.
                                   blue:(rgb & 0xff) / 255. alpha:1.];
    };
    if (@available(macOS 10.14, *)) {
        return [NSColor colorWithName:name dynamicProvider:^NSColor *(NSAppearance *appearance) {
            NSString *match = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
            return color([match isEqualToString:NSAppearanceNameDarkAqua] ? dark : light);
        }];
    }
    return color(light);
}

+ (NSColor *)VLCAccentColor
{
    // Optional swatch selection is UI-only. Values are exported in Figma 1902:3670.
    NSInteger selected = [NSUserDefaults.standardUserDefaults integerForKey:@"VLCInterfaceAccentColor"];
    if (selected > 0) return [NSColor colorWithSRGBRed:((selected >> 16) & 0xff) / 255.
                                              green:((selected >> 8) & 0xff) / 255.
                                               blue:(selected & 0xff) / 255. alpha:1.];
    return redesign_color(@"VLCAccentMain", 0xD37918, 0xE8851A);
}

+ (NSColor *)VLCOrangeElementColor
{
    return self.VLCAccentColor;
}

+ (NSColor *)VLCWindowBackgroundColor
{
    return redesign_color(@"VLCBackgroundB1", 0x0E0E0E, 0xD5D5D5);
}

+ (NSColor *)VLCSurfaceBackgroundColor
{
    return redesign_color(@"VLCBackgroundA4", 0x191919, 0xE7E7E7);
}

+ (NSColor *)VLCHeaderBackgroundColor
{
    // Player187:328 Dark/BG/A3 and Light Player2425:13624 Light/BG/A3.
    return redesign_color(@"VLCHeaderBackground", 0x1B1B1B, 0xD5D5D5);
}

+ (NSColor *)VLCPrimaryForegroundColor
{
    // Figma Settings3046:9282 Dark/FG/1 and Light Player2425:13624 Light/FG/A2.
    return redesign_color(@"VLCPrimaryForeground", 0xEAEAEA, 0x2E2E2E);
}

+ (NSColor *)VLCControlForegroundColor
{
    return redesign_color(@"VLCForegroundA1", 0x969696, 0x2E2E2E);
}

+ (NSColor *)VLCSecondaryForegroundColor
{
    return redesign_color(@"VLCForegroundA2", 0x8F8F8F, 0x6B6B6B);
}

+ (NSColor *)VLCAccentFillColor
{
    return redesign_color(@"VLCAccentFill", 0x371F06, 0xD8BA9A);
}

+ (NSColor *)VLCAccentDimColor
{
    // Figma Settings3046:9282 Accent/Dim, Light Player2425:13624 Accent/Logo.
    if ([NSUserDefaults.standardUserDefaults integerForKey:@"VLCInterfaceAccentColor"] > 0)
        return self.VLCSubtlerAccentColor;
    return redesign_color(@"VLCAccentDim", 0xAB6314, 0xC2711A);
}

+ (NSColor *)VLCInputBackgroundColor
{
    // Figma Dark/BG/B2 and Light/BG/B2.
    return redesign_color(@"VLCInputBackground", 0x090909, 0xDEDEDE);
}

+ (NSColor *)VLCSelectedRowColor
{
    return redesign_color(@"VLCSelectedRow", 0x222222, 0xDEDEDE);
}

+ (NSColor *)VLCSubtlerAccentColor
{
    return [NSColor.VLCAccentColor colorWithAlphaComponent:0.8];
}

+ (NSColor *)VLClibrarySubtitleColor
{
    return NSColor.secondaryLabelColor;
}

+ (NSColor *)VLClibraryAnnotationColor
{
    return [NSColor whiteColor];
}

+ (NSColor *)VLClibraryAnnotationBackgroundColor
{
    return [NSColor colorWithRed:0. green:0. blue:0. alpha:.2];
}

+ (NSColor *)VLClibrarySeparatorLightColor
{
    return [NSColor colorWithRed:0.89 green:0.91 blue:0.93 alpha:1.];
}

+ (NSColor *)VLClibrarySeparatorDarkColor
{
    return [NSColor colorWithRed:0.11 green:0.09 blue:0.07 alpha:1.];
}

+ (NSColor *)VLClibraryProgressIndicatorBackgroundColor
{
    return [NSColor colorWithRed:37./255. green:41./255. blue:44./255. alpha:.8];
}

+ (NSColor *)VLCSliderFillColor
{
    return NSColor.VLCAccentColor;
}

+ (NSColor *)VLCSliderLightBackgroundColor
{
    return [NSColor colorWithSRGBRed:222. / 255. green:222. / 255. blue:222. / 255. alpha:1.];
}

+ (NSColor *)VLCSliderDarkBackgroundColor
{
    return [NSColor colorWithSRGBRed:9. / 255. green:9. / 255. blue:9. / 255. alpha:1.];
}

+ (NSColor *)VLCLightSubtleBorderColor
{
    return [NSColor colorWithCalibratedWhite:0.85 alpha:1.0];
}

+ (NSColor *)VLCDarkSubtleBorderColor
{
    return [NSColor colorWithCalibratedWhite:0.3 alpha:1.0];
}

+ (NSColor *)VLCSubtleBorderColor
{
    return [NSColor colorNamed:@"VLCSubtleBorderColor"];
}

@end
