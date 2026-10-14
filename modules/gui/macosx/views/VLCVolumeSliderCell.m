/*****************************************************************************
 * VLCVolumeSliderCell.m
 *****************************************************************************
 * Copyright (C) 2017 VLC authors and VideoLAN
 *
 * Authors: Marvin Scholz <epirat07 at gmail dot com>
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

#import "VLCVolumeSliderCell.h"

#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "main/CompatibilityFixes.h"

@interface VLCVolumeSliderCell () {
    BOOL _isRTL;
    NSColor *_emptySliderBackgroundColor;
}
@end

@implementation VLCVolumeSliderCell

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setSliderStyleLight];
        _isRTL = ([self userInterfaceLayoutDirection] == NSUserInterfaceLayoutDirectionRightToLeft);
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setSliderStyleLight];
        _isRTL = ([self userInterfaceLayoutDirection] == NSUserInterfaceLayoutDirectionRightToLeft);
    }
    return self;
}

- (void)setSliderStyleLight
{
    _emptySliderBackgroundColor = NSColor.VLCSliderLightBackgroundColor;
}

- (void)setSliderStyleDark
{
    _emptySliderBackgroundColor = NSColor.VLCSliderDarkBackgroundColor;
}

- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped
{
    NSImage *background = [NSImage vlc_redesignImageNamed:@"volume-background"];
    NSImage *fill = [NSImage vlc_redesignImageNamed:@"volume-fill"];
    if (background == nil || fill == nil) {
        [super drawBarInside:rect flipped:flipped];
        return;
    }
    // Figma volume 244:210: 89x27.3633 background, centered 86x24.56 fill.
    const NSRect bounds = self.controlView.bounds;
    NSRect backgroundRect = NSMakeRect(NSMidX(bounds) + .5 - background.size.width / 2.,
                                      NSMidY(bounds) - background.size.height / 2.,
                                      background.size.width, background.size.height);
    NSRect fillRect = NSMakeRect(NSMidX(bounds) + .5 - fill.size.width / 2.,
                                NSMidY(bounds) - fill.size.height / 2.,
                                fill.size.width, fill.size.height);
    const double fraction = self.maxValue > self.minValue ?
        MAX(0., MIN(1., (self.doubleValue - self.minValue) / (self.maxValue - self.minValue))) : 0.;
    [background drawInRect:backgroundRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1. respectFlipped:flipped hints:nil];
    NSRect clip = fillRect;
    clip.size.width *= fraction;
    if (_isRTL) clip.origin.x = NSMaxX(fillRect) - clip.size.width;
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:clip] addClip];
    [fill drawInRect:fillRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1. respectFlipped:flipped hints:nil];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawKnob:(NSRect)knobRect
{
    // The Figma volume cone is the handle. Preserve NSSlider's tracking/keyboard target without a second native thumb.
}

@end
