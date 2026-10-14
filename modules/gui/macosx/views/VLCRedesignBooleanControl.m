/* Figma Settings 3046:9282, Toggle 536:1013/536:1336: 68x32, 6px outer
 * radius, 26px handles and ON/OFF copy. The label/state belong to the original checkbox. */
#import "VLCRedesignBooleanControl.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"

@implementation VLCRedesignBooleanControl
- (void)drawRect:(NSRect)dirtyRect
{
    BOOL on = self.state == NSControlStateValueOn;
    [NSGraphicsContext saveGraphicsState];
    if (!self.enabled) CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, .45);
    NSRect toggle = NSMakeRect(MAX(0, self.bounds.size.width - 68), (self.bounds.size.height - 32) / 2, 68, 32);
    [NSColor.VLCInputBackgroundColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:toggle xRadius:6 yRadius:6] fill];
    NSRect fill = NSMakeRect(toggle.origin.x + (on ? 3 : 32), toggle.origin.y + 3, 33, 26);
    [(on ? NSColor.VLCAccentFillColor : NSColor.VLCSurfaceBackgroundColor) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:fill xRadius:3 yRadius:3] fill];
    NSColor *inactive = self.shouldShowDarkAppearance ? [NSColor colorWithSRGBRed:64./255. green:64./255. blue:64./255. alpha:1] : [NSColor colorWithSRGBRed:136./255. green:136./255. blue:136./255. alpha:1];
    [(on ? NSColor.VLCAccentDimColor : inactive) setFill];
    NSRect handle = NSMakeRect(toggle.origin.x + (on ? 39 : 3), toggle.origin.y + 3, 26, 26);
    [[NSBezierPath bezierPathWithRoundedRect:handle xRadius:3 yRadius:3] fill];
    NSString *state = on ? _NS("ON") : _NS("OFF");
    [state drawAtPoint:NSMakePoint(toggle.origin.x + (on ? 10 : 36), toggle.origin.y + 8)
        withAttributes:@{NSFontAttributeName:[NSFont vlc_redesignFontOfSize:12 weight:NSFontWeightRegular], NSForegroundColorAttributeName:on ? NSColor.VLCAccentColor : NSColor.VLCSecondaryForegroundColor}];
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.title drawInRect:NSMakeRect(0, (self.bounds.size.height - 20) / 2, MAX(0, toggle.origin.x - 16), 20)
        withAttributes:@{NSFontAttributeName:[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular], NSForegroundColorAttributeName:NSColor.VLCControlForegroundColor, NSParagraphStyleAttributeName:paragraph}];
    [NSGraphicsContext restoreGraphicsState];
}
@end
