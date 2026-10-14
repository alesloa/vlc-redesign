/*****************************************************************************
 * VLCPlaybackProgressSlider.m
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

#import "VLCPlaybackProgressSlider.h"

#import "extensions/NSString+Helpers.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSView+VLCAdditions.h"
#import "main/CompatibilityFixes.h"
#import "main/VLCMain.h"
#import "library/VLCInputItem.h"
#import "playqueue/VLCPlayQueueController.h"
#import "playqueue/VLCPlayerController.h"
#import "views/VLCPlaybackProgressSliderCell.h"
#import <vlc_preparser.h>

@interface VLCSeekPreviewRequest : NSObject
@property (weak) VLCPlaybackProgressSlider *slider;
@property vlc_preparser_req *request;
@property NSUInteger generation;
@end
@implementation VLCSeekPreviewRequest
@end
@interface VLCPlaybackProgressSlider (SeekPreview)
- (void)receivePreview:(NSImage *)image request:(VLCSeekPreviewRequest *)request;
@end
static void seekPreviewEnded(vlc_preparser_req *handle, int status, picture_t *picture, void *opaque)
{
    @autoreleasepool {
        VLCSeekPreviewRequest *request = CFBridgingRelease(opaque);
        NSImage *image = status == VLC_SUCCESS && picture ?
            [NSImage imageFromVLCPicture:picture vlcObject:VLC_OBJECT(getIntf()) size:NSMakeSize(252,142)] : nil;
        // The caller's handle remains owned until this main-queue completion,
        // so mouse exit can safely Cancel even after the core callback finished.
        dispatch_async(dispatch_get_main_queue(), ^{
            [request.slider receivePreview:image request:request];
            request.request = NULL;
            vlc_preparser_req_Release(handle);
        });
    }
}

@implementation VLCPlaybackProgressSlider {
    NSTrackingArea *_hoverTrackingArea;
    NSWindow *_hoverWindow;
    NSTextField *_hoverLabel;
    NSImageView *_hoverImage;
    VLCSeekPreviewRequest *_previewRequest;
    NSTimer *_previewTimer;
    NSUInteger _previewGeneration;
    CGFloat _hoverX;
    vlc_tick_t _hoverTime;
    BOOL _hovering;
    BOOL _interfaceTerminating;
}

+ (Class)cellClass
{
    return VLCPlaybackProgressSliderCell.class;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    if (self) {
        NSAssert([self.cell isKindOfClass:[VLCPlaybackProgressSlider cellClass]],
                 @"VLCPlaybackProgressSlider cell is not a VLCPlaybackProgressSliderCell");
        self.scrollable = YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interfaceWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(previewMediaChanged:) name:VLCPlayerCurrentMediaItemChanged object:nil];
        if (@available(macOS 10.14, *)) {
            [self viewDidChangeEffectiveAppearance];
            self.clipsToBounds = YES;
        } else {
            [(VLCPlaybackProgressSliderCell*)self.cell setSliderStyleLight];
        }

    }
    return self;
}

- (void)scrollWheel:(NSEvent *)event
{
    if (!self.scrollable) {
        return [super scrollWheel:event];
    }

    double increment;
    CGFloat deltaY = [event scrollingDeltaY];
    double range = [self maxValue] - [self minValue];

    // Scroll less for high precision, else it's too fast
    if (event.hasPreciseScrollingDeltas) {
        increment = (range * 0.002) * deltaY;
    } else {
        if (deltaY == 0.0) {
            return;
        }
        increment = (range * 0.01 * deltaY);
    }

    // If scrolling is inversed, increment in other direction
    if (!event.isDirectionInvertedFromDevice) {
        increment = -increment;
    }

    self.doubleValue = self.doubleValue - increment;
    [self sendAction:self.action to:self.target];
}

// Workaround for 10.7
// http://stackoverflow.com/questions/3985816/custom-nsslidercell
- (void)setNeedsDisplayInRect:(NSRect)invalidRect
{
    [super setNeedsDisplayInRect:self.bounds];
}

- (BOOL)indefinite
{
    return [(VLCPlaybackProgressSliderCell*)self.cell indefinite];
}

- (void)setIndefinite:(BOOL)indefinite
{
    [(VLCPlaybackProgressSliderCell*)self.cell setIndefinite:indefinite];
}

- (BOOL)knobHidden
{
    return [(VLCPlaybackProgressSliderCell*)self.cell knobHidden];
}

- (void)setKnobHidden:(BOOL)knobHidden
{
    [(VLCPlaybackProgressSliderCell*)self.cell setKnobHidden:knobHidden];
}

- (BOOL)isFlipped
{
    return NO;
}

- (void)viewDidChangeEffectiveAppearance
{
    if (self.shouldShowDarkAppearance) {
        [(VLCPlaybackProgressSliderCell*)self.cell setSliderStyleDark];
    } else {
        [(VLCPlaybackProgressSliderCell*)self.cell setSliderStyleLight];
    }
    [self applyHoverAppearance];
}

#pragma mark -
#pragma mark Hover tracking

- (void)installHoverTrackingAreaIfNeeded
{
    if (_hoverTrackingArea != nil) {
        return;
    }
    _hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                      options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingInVisibleRect | NSTrackingActiveInKeyWindow
                                                        owner:self
                                                     userInfo:nil];
    [self addTrackingArea:_hoverTrackingArea];
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    [self installHoverTrackingAreaIfNeeded];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (self.window == nil) {
        [self hideHoverWindow];
        return;
    }
    [self installHoverTrackingAreaIfNeeded];
}

- (void)dealloc
{
    [self hideHoverWindow];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (BOOL)hoverIsAvailable
{
    return self.enabled && !self.indefinite && self.mediaDuration > 0;
}

- (void)createHoverWindowIfNeeded
{
    if (_hoverWindow != nil) {
        return;
    }

    _hoverLabel = [NSTextField labelWithString:@""];
    // Figma2151:9673/9674: 272x189 panel, 252x142 image, 15px time,
    // 10px padding/gap, 14px panel and 4px image radii.
    _hoverLabel.font = [NSFont vlc_redesignFontOfSize:15 weight:NSFontWeightRegular];
    _hoverLabel.alignment = NSTextAlignmentCenter;
    _hoverLabel.textColor = NSColor.controlTextColor;

    NSView * const contentView = [[NSView alloc] initWithFrame:NSZeroRect];
    contentView.wantsLayer = YES;
    contentView.layer.borderWidth = 0.5;
    contentView.layer.cornerRadius = 14.0;
    [contentView addSubview:_hoverLabel];
    _hoverImage = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _hoverImage.imageScaling = NSImageScaleProportionallyUpOrDown;
    _hoverImage.hidden = YES; _hoverImage.wantsLayer = YES;
    _hoverImage.layer.cornerRadius = 4; _hoverImage.layer.masksToBounds = YES;
    [contentView addSubview:_hoverImage];

    _hoverWindow = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 60, 20)
                                              styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    _hoverWindow.contentView = contentView;
    _hoverWindow.opaque = NO;
    _hoverWindow.backgroundColor = NSColor.clearColor;
    _hoverWindow.hasShadow = YES;
    _hoverWindow.ignoresMouseEvents = YES;
    _hoverWindow.releasedWhenClosed = NO;

    [self applyHoverAppearance];
}

- (void)applyHoverAppearance
{
    if (_hoverWindow == nil) {
        return;
    }
    NSView * const contentView = _hoverWindow.contentView;
    if (@available(macOS 11.0, *)) {
        _hoverWindow.appearance = self.effectiveAppearance;
        [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
            contentView.layer.backgroundColor =
                [NSColor.VLCSurfaceBackgroundColor colorWithAlphaComponent:0.95].CGColor;
            contentView.layer.borderColor = NSColor.gridColor.CGColor;
        }];
        return;
    }
    if (@available(macOS 10.14, *)) {
        _hoverWindow.appearance = self.effectiveAppearance;
    }
    contentView.layer.backgroundColor =
        [NSColor.VLCSurfaceBackgroundColor colorWithAlphaComponent:0.95].CGColor;
    contentView.layer.borderColor = NSColor.gridColor.CGColor;
}

- (void)hideHoverWindow
{
    _hovering = NO;
    [self cancelPreviewRequest];
    _hoverImage.image = nil; _hoverImage.hidden = YES;
    if (_hoverWindow == nil) {
        return;
    }
    NSWindow * const parent = _hoverWindow.parentWindow;
    if (parent != nil) {
        [parent removeChildWindow:_hoverWindow];
    }
    [_hoverWindow orderOut:nil];
}

- (void)showHoverAtSliderX:(CGFloat)xInSlider time:(vlc_tick_t)time
{
    NSWindow * const parentWindow = self.window;
    if (parentWindow == nil) {
        return;
    }

    [self createHoverWindowIfNeeded];

    _hoverLabel.stringValue = [NSString stringWithTimeFromTicks:time];
    [_hoverLabel sizeToFit];

    const NSSize textSize = _hoverLabel.frame.size;
    const CGFloat horizontalPadding = 10.0;
    const CGFloat verticalPadding = 10.0;
    const CGFloat verticalGap = 10.0;
    const BOOL imageAvailable = _hoverImage.image != nil;
    const NSSize windowSize = NSMakeSize(imageAvailable ? 272 : textSize.width + horizontalPadding * 2.0,
                                         imageAvailable ? 189 : textSize.height + verticalPadding * 2.0);
    _hoverLabel.frame = NSMakeRect(horizontalPadding, verticalPadding,
                                   windowSize.width - horizontalPadding * 2, textSize.height);
    _hoverImage.hidden = !imageAvailable;
    if (imageAvailable) _hoverImage.frame = NSMakeRect(10, 37, 252, 142);

    const NSRect sliderOnScreen =
        [parentWindow convertRectToScreen:[self convertRect:self.bounds toView:nil]];
    const CGFloat anchorScreenX = NSMinX(sliderOnScreen) + xInSlider;

    CGFloat originX = anchorScreenX - windowSize.width / 2.0;
    originX = MAX(NSMinX(sliderOnScreen),
                  MIN(originX, NSMaxX(sliderOnScreen) - windowSize.width));
    const CGFloat originY = NSMaxY(sliderOnScreen) + verticalGap;

    [_hoverWindow setFrame:NSMakeRect(originX, originY,
                                      windowSize.width, windowSize.height)
                   display:YES];

    if (_hoverWindow.parentWindow != parentWindow) {
        [parentWindow addChildWindow:_hoverWindow ordered:NSWindowAbove];
    } else if (!_hoverWindow.visible) {
        [_hoverWindow orderFront:nil];
    }
}

- (void)reportHoverAtPoint:(NSPoint)locationInSelf
{
    if (![self hoverIsAvailable]) {
        [self hideHoverWindow];
        return;
    }

    const NSRect trackRect = [(NSSliderCell *)self.cell barRectFlipped:NO];
    if (NSWidth(trackRect) <= 0) {
        [self hideHoverWindow];
        return;
    }

    CGFloat fraction = (locationInSelf.x - NSMinX(trackRect)) / NSWidth(trackRect);
    if (fraction < 0.0) {
        fraction = 0.0;
    } else if (fraction > 1.0) {
        fraction = 1.0;
    }

    const vlc_tick_t time = (vlc_tick_t)(fraction * self.mediaDuration);
    _hovering = YES; _hoverX = locationInSelf.x; _hoverTime = time;
    _hoverImage.image = nil;
    [self showHoverAtSliderX:locationInSelf.x time:time];
    [self cancelPreviewRequest];
    if (!_interfaceTerminating) _previewTimer = [NSTimer scheduledTimerWithTimeInterval:.12 target:self selector:@selector(requestSeekPreview:) userInfo:nil repeats:NO];
}

- (void)cancelPreviewRequest
{
    ++_previewGeneration;
    [_previewTimer invalidate]; _previewTimer = nil;
    VLCSeekPreviewRequest *request = _previewRequest; _previewRequest = nil;
    vlc_preparser_t *thumbnailer = getThumbnailer();
    if (request.request && thumbnailer) vlc_preparser_Cancel(thumbnailer, request.request);
}

- (void)requestSeekPreview:(NSTimer *)timer
{
    _previewTimer = nil;
    if (_interfaceTerminating || !_hovering) return;
    VLCPlayerController *player = VLCMain.sharedInstance.playQueueController.playerController;
    vlc_preparser_t *thumbnailer = getThumbnailer();
    if (!thumbnailer || !player.activeVideoPlayback || !player.currentMedia.vlcInputItem) return;
    VLCSeekPreviewRequest *request = [[VLCSeekPreviewRequest alloc] init];
    request.slider = self; request.generation = _previewGeneration;
    void *context = CFBridgingRetain(request);
    const struct vlc_thumbnailer_arg arguments = { .seek = {.type = VLC_THUMBNAILER_SEEK_TIME, .time = _hoverTime, .speed = VLC_THUMBNAILER_SEEK_FAST}, .hw_dec = false };
    static const struct vlc_thumbnailer_cbs callbacks = { .on_ended = seekPreviewEnded };
    request.request = vlc_preparser_req_NewThumbnail(thumbnailer, player.currentMedia.vlcInputItem, &arguments, &callbacks, context);
    if (request.request && vlc_preparser_Submit(thumbnailer, request.request) == VLC_SUCCESS) { _previewRequest = request; return; }
    if (request.request) vlc_preparser_req_Release(request.request);
    CFBridgingRelease(context);
}

- (void)receivePreview:(NSImage *)image request:(VLCSeekPreviewRequest *)request
{
    if (_previewRequest == request) _previewRequest = nil;
    if (_interfaceTerminating || !_hovering || request.generation != _previewGeneration || !image) return;
    _hoverImage.image = image;
    [self showHoverAtSliderX:_hoverX time:_hoverTime];
}

- (void)previewMediaChanged:(NSNotification *)notification { [self hideHoverWindow]; }
- (void)interfaceWillTerminate:(NSNotification *)notification { _interfaceTerminating = YES; [self hideHoverWindow]; }

- (void)mouseEntered:(NSEvent *)event
{
    [self reportHoverAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseMoved:(NSEvent *)event
{
    [self reportHoverAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseExited:(NSEvent *)event
{
    [self hideHoverWindow];
}

- (void)mouseDown:(NSEvent *)event
{
    // NSSlider runs its own tracking loop here; mouseMoved is not delivered
    // during the drag, so the hover would otherwise show a stale time.
    [self hideHoverWindow];
    [super mouseDown:event];
}

- (void)setMediaDuration:(vlc_tick_t)mediaDuration
{
    _mediaDuration = mediaDuration;
    if (![self hoverIsAvailable]) {
        [self hideHoverWindow];
    }
}

@end
