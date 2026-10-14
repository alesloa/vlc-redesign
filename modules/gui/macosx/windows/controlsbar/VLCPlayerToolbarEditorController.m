/* Figma 6587:18867/2107:5604 supplies the 1048x655 Customize Player shell,
 * 94px header, 72px footer and 86px palette tiles with 32px icon/16px gap.
 * Every caption and image comes from the existing native NSButton supplied by
 * VLCMainVideoViewController. Only its 13 real controls are offered. */
#import "VLCPlayerToolbarEditorController.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"
#import "preferences/VLCSettingsProfileManager.h"
#import <math.h>

NSString *const VLCPlayerToolbarLayoutKey = @"VLCPlayerToolbarLayout";
NSString *const VLCPlayerToolbarLayoutChanged = @"VLCPlayerToolbarLayoutChanged";
static NSString *const VLCPlayerToolbarDragType = @"org.videolan.vlc.native-toolbar-control";

// Native titlebar chrome is retained; the Figma content colors resolve again
// when this window's actual effective appearance changes.
@interface VLCPlayerToolbarRootView : NSView
@end
@implementation VLCPlayerToolbarRootView
- (void)viewDidChangeEffectiveAppearance {[super viewDidChangeEffectiveAppearance];[self vlc_applyRedesignStyle];}
@end

@interface VLCPlayerToolbarActionButton : NSButton
@property BOOL primary;
@end
@implementation VLCPlayerToolbarActionButton
- (void)drawRect:(NSRect)dirty
{
    [NSGraphicsContext saveGraphicsState];if(!self.enabled)CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext,.5);
    [(self.primary?NSColor.VLCAccentFillColor:NSColor.VLCHeaderBackgroundColor) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6] fill];
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:self.primary?NSColor.VLCAccentColor:NSColor.VLCSecondaryForegroundColor};
    NSSize size=[self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint((self.bounds.size.width-size.width)/2,(self.bounds.size.height-size.height)/2) withAttributes:attributes];[NSGraphicsContext restoreGraphicsState];
}
- (void)viewDidChangeEffectiveAppearance {[super viewDidChangeEffectiveAppearance];self.needsDisplay=YES;}
@end
static VLCPlayerToolbarActionButton *ToolbarAction(NSString *title,id target,SEL action)
{
    VLCPlayerToolbarActionButton *button=[VLCPlayerToolbarActionButton new];button.title=title;button.target=target;button.action=action;return button;
}

@interface VLCPlayerToolbarEditorController (Dragging)
- (void)removeControl:(NSButton *)sender;
- (void)toggleControl:(NSButton *)sender;
- (void)insertControl:(NSString *)key atIndex:(NSUInteger)index;
- (void)insertControl:(NSString *)key inGroup:(NSNumber *)group atIndex:(NSUInteger)index;
- (BOOL)control:(NSString *)key belongsToGroup:(NSNumber *)group;
@end

@interface VLCPlayerToolbarDraggableButton : NSButton<NSDraggingSource>
@property (weak) VLCPlayerToolbarEditorController *editor;
@property BOOL paletteItem;
@end
@implementation VLCPlayerToolbarDraggableButton
- (void)drawRect:(NSRect)dirty
{
    BOOL primary=[self.identifier isEqualToString:@"play"];
    NSColor *color=primary?[NSColor colorWithSRGBRed:22./255. green:22./255. blue:22./255. alpha:1]:NSColor.VLCControlForegroundColor;
    if(primary){[NSColor.VLCAccentColor setFill];[[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6] fill];}
    NSImage *image=[self.image imageTintedWithColor:color];
    [image drawInRect:NSMakeRect((self.bounds.size.width-24)/2,(self.bounds.size.height-24)/2,24,24) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:self.flipped hints:nil];
}
- (void)viewDidChangeEffectiveAppearance {[super viewDidChangeEffectiveAppearance];self.needsDisplay=YES;}
- (void)mouseDown:(NSEvent *)event
{
    // A click retains keyboard/accessibility toggle behavior. A real drag
    // stages a layout edit, without invoking the source playback action.
    NSPoint start=event.locationInWindow;
    for (;;) {
        NSEvent *next=[self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged|NSEventMaskLeftMouseUp];
        if(!next)return;
        if(next.type==NSEventTypeLeftMouseUp){[self performClick:self];return;}
        NSPoint point=next.locationInWindow;
        if(hypot(point.x-start.x,point.y-start.y)<3)continue;
        NSPasteboardItem *payload=[NSPasteboardItem new];
        [payload setString:self.identifier forType:VLCPlayerToolbarDragType];
        NSDraggingItem *item=[[NSDraggingItem alloc] initWithPasteboardWriter:payload];
        NSImage *image=[[NSImage alloc] initWithSize:self.bounds.size];
        [image lockFocus];[self drawRect:self.bounds];[image unlockFocus];
        [item setDraggingFrame:self.bounds contents:image];
        [self beginDraggingSessionWithItems:@[item] event:next source:self];return;
    }
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    return self.paletteItem?NSDragOperationCopy:NSDragOperationMove;
}
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)point operation:(NSDragOperation)operation
{
    if(!self.paletteItem && operation==NSDragOperationNone && !NSPointInRect(point,self.window.frame))
        [self.editor removeControl:self];
}
@end

@interface VLCPlayerToolbarPaletteButton : VLCPlayerToolbarDraggableButton
@end
@implementation VLCPlayerToolbarPaletteButton
- (BOOL)isFlipped {return YES;}
- (void)drawRect:(NSRect)dirty
{
    NSColor *color=self.state==NSControlStateValueOn?NSColor.VLCAccentColor:NSColor.VLCControlForegroundColor;
    NSRect icon=NSMakeRect((self.bounds.size.width-32)/2,0,32,32);
    NSBezierPath *outline=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(icon,.5,.5) xRadius:6 yRadius:6];
    CGFloat dash[]={3,3};[outline setLineDash:dash count:2 phase:0];
    [[color colorWithAlphaComponent:.35] setStroke];[outline stroke];
    NSImage *image=[self.image imageTintedWithColor:color];
    [image drawInRect:NSInsetRect(icon,4,4) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.alignment=NSTextAlignmentCenter;paragraph.lineBreakMode=NSLineBreakByWordWrapping;paragraph.minimumLineHeight=17;paragraph.maximumLineHeight=17;
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular],NSForegroundColorAttributeName:NSColor.VLCControlForegroundColor,NSParagraphStyleAttributeName:paragraph};
    [self.title drawWithRect:NSMakeRect(0,48,self.bounds.size.width,34) options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
}
- (void)viewDidChangeEffectiveAppearance {[super viewDidChangeEffectiveAppearance];self.needsDisplay=YES;}
@end

@interface VLCPlayerToolbarPalette : NSView
@property (weak) VLCPlayerToolbarEditorController *editor;
@property NSArray<VLCPlayerToolbarPaletteButton *> *tiles;
@property NSLayoutConstraint *contentHeight;
@end
@implementation VLCPlayerToolbarPalette
- (instancetype)initWithFrame:(NSRect)frame
{
    self=[super initWithFrame:frame];if(self)[self registerForDraggedTypes:@[VLCPlayerToolbarDragType]];return self;
}
- (BOOL)isFlipped {return YES;}
- (void)layout
{
    [super layout];NSUInteger columns=MAX(1,(NSUInteger)floor((self.bounds.size.width+24)/110));
    CGFloat height=self.tiles.count?ceil((double)self.tiles.count/columns)*120-38:0;
    if(self.contentHeight.constant!=height)self.contentHeight.constant=height;
    for(NSUInteger index=0;index<self.tiles.count;index++)
        self.tiles[index].frame=NSMakeRect((index%columns)*110,(index/columns)*120,86,82);
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info
{
    VLCPlayerToolbarDraggableButton *source=info.draggingSource;
    return [source isKindOfClass:VLCPlayerToolbarDraggableButton.class]&&!source.paletteItem?NSDragOperationMove:NSDragOperationNone;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info
{
    VLCPlayerToolbarDraggableButton *source=info.draggingSource;
    if(![source isKindOfClass:VLCPlayerToolbarDraggableButton.class]||source.paletteItem)return NO;
    [self.editor removeControl:source];return YES;
}
@end

@interface VLCPlayerToolbarPreviewStack : NSStackView
@property (weak) VLCPlayerToolbarEditorController *editor;
@property NSNumber *sourceGroup;
@property NSInteger insertionIndex;
@end
@implementation VLCPlayerToolbarPreviewStack
- (instancetype)initWithFrame:(NSRect)frame
{
    self=[super initWithFrame:frame];if(self){[self registerForDraggedTypes:@[VLCPlayerToolbarDragType]];_insertionIndex=-1;}return self;
}
- (BOOL)validDrag:(id<NSDraggingInfo>)info
{
    return [info.draggingSource isKindOfClass:VLCPlayerToolbarDraggableButton.class]&&
        [self.editor control:[info.draggingPasteboard stringForType:VLCPlayerToolbarDragType] belongsToGroup:self.sourceGroup];
}
- (NSUInteger)indexForDrag:(id<NSDraggingInfo>)info
{
    NSPoint point=[self convertPoint:info.draggingLocation fromView:nil];NSUInteger index=0;
    for(NSView *view in self.arrangedSubviews)if(point.x>NSMidX(view.frame))index++;return index;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {return [self draggingUpdated:info];}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info
{
    if(![self validDrag:info])return NSDragOperationNone;
    self.insertionIndex=[self indexForDrag:info];self.needsDisplay=YES;
    return ((VLCPlayerToolbarDraggableButton *)info.draggingSource).paletteItem?NSDragOperationCopy:NSDragOperationMove;
}
- (void)draggingExited:(id<NSDraggingInfo>)info {self.insertionIndex=-1;self.needsDisplay=YES;}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info
{
    if(![self validDrag:info])return NO;
    NSString *key=[info.draggingPasteboard stringForType:VLCPlayerToolbarDragType];
    NSUInteger index=[self indexForDrag:info];self.insertionIndex=-1;
    [self.editor insertControl:key inGroup:self.sourceGroup atIndex:index];self.needsDisplay=YES;return YES;
}
- (void)drawRect:(NSRect)dirty
{
    if(self.insertionIndex<0)return;
    CGFloat x=8;
    if(self.arrangedSubviews.count)x=self.insertionIndex<(NSInteger)self.arrangedSubviews.count?NSMinX(self.arrangedSubviews[self.insertionIndex].frame)-4:NSMaxX(self.arrangedSubviews.lastObject.frame)+4;
    [NSColor.VLCAccentColor setFill];NSRectFill(NSMakeRect(x,8,2,MAX(0,self.bounds.size.height-16)));
}
@end

@interface VLCPlayerToolbarEditorController ()
@property NSDictionary<NSString *,NSButton *> *buttons;
@property NSMutableArray<NSString *> *identifiers;
@property NSMutableSet<NSString *> *enabledIdentifiers;
@property NSDictionary<NSString *,NSNumber *> *sourceGroups;
@property NSArray<NSNumber *> *groupOrder;
@property VLCPlayerToolbarPalette *palette;
@property NSStackView *preview;
@property NSScrollView *previewScroll;
@property NSLayoutConstraint *previewNaturalWidth;
@end

@implementation VLCPlayerToolbarEditorController
- (instancetype)initWithButtons:(NSDictionary<NSString *,NSButton *> *)buttons
{
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1048,655)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self=[super initWithWindow:window];if(!self)return nil;
    _buttons=buttons;
    NSArray *saved=[NSUserDefaults.standardUserDefaults arrayForKey:VLCPlayerToolbarLayoutKey];
    NSArray *defaults=@[@"previous",@"play",@"next",@"audio",@"subtitles",@"settings",@"queue",@"fullscreen",@"pip"];
    NSArray *available=@[@"previous",@"play",@"next",@"video",@"bookmarks",@"lyrics",@"float",@"fullscreen",@"pip",@"audio",@"subtitles",@"settings",@"queue"];
    _enabledIdentifiers=[NSMutableSet setWithArray:saved?:defaults];_identifiers=[NSMutableArray array];
    for(NSString *key in saved?:defaults)if(buttons[key]&&![_identifiers containsObject:key])[_identifiers addObject:key];
    for(NSString *key in available)if(buttons[key]&&![_identifiers containsObject:key])[_identifiers addObject:key];
    // The player reorders controls within their original NSStackView only.
    // Preserve those source groups in the preview and each drop destination.
    NSMutableArray<NSValue *> *parents=[NSMutableArray array];NSMutableDictionary *groups=[NSMutableDictionary dictionary];
    NSMutableArray *order=[NSMutableArray array];
    for(NSString *key in available){NSButton *button=buttons[key];if(!button)continue;NSValue *parent=[NSValue valueWithNonretainedObject:button.superview?:button];NSUInteger index=[parents indexOfObject:parent];if(index==NSNotFound){index=parents.count;[parents addObject:parent];[order addObject:@(index)];}groups[key]=@(index);}
    _sourceGroups=groups;_groupOrder=order;
    window.title=_NS("Customize Player");window.backgroundColor=NSColor.VLCWindowBackgroundColor;window.releasedWhenClosed=NO;window.contentMinSize=NSMakeSize(680,480);
    NSView *root=[[VLCPlayerToolbarRootView alloc] initWithFrame:window.contentView.bounds];window.contentView=root;
    NSView *header=[NSView new];header.identifier=@"VLCRedesignedDialogHeader";header.wantsLayer=YES;header.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:header];
    NSTextField *title=[NSTextField labelWithString:window.title];title.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];title.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:title];
    NSButton *close=[NSButton buttonWithTitle:@"" target:self action:@selector(cancel:)];close.image=[NSImage vlc_redesignImageNamed:@"settings-close"];close.image.size=NSMakeSize(24,24);close.bordered=NO;close.accessibilityLabel=_NS("Close");close.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:close];
    NSTextField *instructions=[NSTextField wrappingLabelWithString:_NS("Drag items around and out of the box below to re-order them. Drag items into the box to remove them from the player.")];
    instructions.font=title.font;instructions.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:instructions];
    NSView *footer=[NSView new];footer.translatesAutoresizingMaskIntoConstraints=NO;[root addSubview:footer];
    NSButton *cancel=ToolbarAction(_NS("Cancel"),self,@selector(cancel:));cancel.keyEquivalent=@"\e";
    NSButton *reset=ToolbarAction(_NS("Reset"),self,@selector(reset:));
    VLCPlayerToolbarActionButton *save=ToolbarAction(_NS("Save"),self,@selector(save:));save.keyEquivalent=@"\r";save.primary=YES;
    for(NSButton *button in @[cancel,reset,save]){button.bordered=NO;button.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightSemibold];button.translatesAutoresizingMaskIntoConstraints=NO;[footer addSubview:button];}
    NSScrollView *scroll=[NSScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;scroll.hasVerticalScroller=YES;scroll.drawsBackground=NO;[root addSubview:scroll];
    _palette=[[VLCPlayerToolbarPalette alloc] initWithFrame:NSMakeRect(0,0,980,202)];_palette.editor=self;_palette.translatesAutoresizingMaskIntoConstraints=NO;
    NSMutableArray *tiles=[NSMutableArray array];
    for(NSString *key in available){NSButton *source=buttons[key];NSString *caption=[self labelForIdentifier:key];if(!source||!caption.length)continue;
        VLCPlayerToolbarPaletteButton *tile=[VLCPlayerToolbarPaletteButton new];tile.editor=self;tile.paletteItem=YES;tile.identifier=key;tile.title=caption;tile.image=source.image;tile.bordered=NO;tile.toolTip=caption;tile.accessibilityLabel=source.accessibilityLabel.length?source.accessibilityLabel:caption;tile.target=self;tile.action=@selector(toggleControl:);[tile setButtonType:NSButtonTypeToggle];[tiles addObject:tile];[_palette addSubview:tile];}
    _palette.tiles=tiles;scroll.documentView=_palette;
    _palette.contentHeight=[_palette.heightAnchor constraintEqualToConstant:202];_palette.contentHeight.active=YES;[_palette.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active=YES;_palette.needsLayout=YES;
    _previewScroll=[NSScrollView new];_previewScroll.translatesAutoresizingMaskIntoConstraints=NO;_previewScroll.hasHorizontalScroller=YES;_previewScroll.autohidesScrollers=YES;_previewScroll.drawsBackground=NO;[root addSubview:_previewScroll];
    _preview=[[NSStackView alloc] initWithFrame:NSMakeRect(0,0,980,64)];_preview.translatesAutoresizingMaskIntoConstraints=NO;_preview.orientation=NSUserInterfaceLayoutOrientationHorizontal;_preview.alignment=NSLayoutAttributeCenterY;_preview.spacing=16;_preview.edgeInsets=NSEdgeInsetsMake(8,8,8,8);_preview.wantsLayer=YES;_preview.identifier=@"VLCRedesignedSettingsCard";_preview.layer.cornerRadius=6;_previewScroll.documentView=_preview;
    [_preview.heightAnchor constraintEqualToConstant:64].active=YES;[_preview.widthAnchor constraintGreaterThanOrEqualToAnchor:_previewScroll.contentView.widthAnchor].active=YES;
    // The source controls set a minimum document width, not a maximum
    // viewport/window width. An equality here caused AppKit to shrink the
    // 1048px shell to the 518px preview plus its outer margins.
    _previewNaturalWidth=[_preview.widthAnchor constraintGreaterThanOrEqualToConstant:980];_previewNaturalWidth.active=YES;
    [_preview setHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_preview setHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:root.topAnchor],[header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[header.heightAnchor constraintEqualToConstant:94],
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:19],[title.topAnchor constraintEqualToAnchor:header.topAnchor constant:16.5],
        [close.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-9],[close.topAnchor constraintEqualToAnchor:header.topAnchor constant:9],[close.widthAnchor constraintEqualToConstant:32],[close.heightAnchor constraintEqualToConstant:32],
        [instructions.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[instructions.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-19],[instructions.topAnchor constraintEqualToAnchor:header.topAnchor constant:53],[instructions.heightAnchor constraintEqualToConstant:32],
        [footer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],[footer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],[footer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],[footer.heightAnchor constraintEqualToConstant:72],
        [save.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-20],[save.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],[cancel.trailingAnchor constraintEqualToAnchor:save.leadingAnchor constant:-12],[cancel.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        [reset.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:20],[reset.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:34],[scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:34],[scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-34],
        [scroll.bottomAnchor constraintEqualToAnchor:_previewScroll.topAnchor constant:-20],
        [_previewScroll.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],[_previewScroll.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],[_previewScroll.heightAnchor constraintEqualToConstant:64],[_previewScroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-34]
    ]];
    for(NSButton *button in @[cancel,reset,save])[NSLayoutConstraint activateConstraints:@[[button.widthAnchor constraintEqualToConstant:100],[button.heightAnchor constraintEqualToConstant:32]]];
    [root vlc_applyRedesignStyle];[self updatePreview];[window setContentSize:NSMakeSize(1048,655)];[window center];return self;
}
- (NSString *)labelForIdentifier:(NSString *)key
{
    // Short captions are the existing setupPlayerCustomization labels in
    // VLCMainVideoViewController.m; the original longer accessibility names
    // remain on each tile. These are the same source actions, not extra slots.
    NSDictionary *labels=@{@"previous":_NS("Previous"),@"play":_NS("Play"),@"next":_NS("Next"),@"audio":_NS("Audio"),@"subtitles":_NS("Subtitles"),@"video":_NS("Video"),@"bookmarks":_NS("Bookmarks"),@"lyrics":_NS("Lyrics"),@"float":_NS("Float on Top"),@"settings":_NS("Playback"),@"fullscreen":_NS("Fullscreen"),@"pip":_NS("Picture in Picture"),@"queue":_NS("Queue")};
    NSButton *button=self.buttons[key];return labels[key]?: (button.accessibilityLabel.length?button.accessibilityLabel:button.toolTip.length?button.toolTip:button.title);
}
- (void)toggleControl:(NSButton *)sender
{
    if([self.enabledIdentifiers containsObject:sender.identifier])[self.enabledIdentifiers removeObject:sender.identifier];
    else [self.enabledIdentifiers addObject:sender.identifier];[self updatePreview];
}
- (void)updatePreview
{
    for(NSView *view in self.preview.arrangedSubviews.copy){[self.preview removeArrangedSubview:view];[view removeFromSuperview];}
    CGFloat naturalWidth=16+MAX(0,(NSInteger)self.groupOrder.count-1)*16;
    for(NSNumber *sourceGroup in self.groupOrder){
        VLCPlayerToolbarPreviewStack *group=[VLCPlayerToolbarPreviewStack new];group.editor=self;group.sourceGroup=sourceGroup;group.orientation=NSUserInterfaceLayoutOrientationHorizontal;group.alignment=NSLayoutAttributeCenterY;group.spacing=8;group.edgeInsets=NSEdgeInsetsMake(8,8,8,8);
        [group.heightAnchor constraintEqualToConstant:48].active=YES;[group.widthAnchor constraintGreaterThanOrEqualToConstant:32].active=YES;
        for(NSString *key in self.identifiers){if(![self.enabledIdentifiers containsObject:key]||![self control:key belongsToGroup:sourceGroup])continue;
            VLCPlayerToolbarDraggableButton *preview=[VLCPlayerToolbarDraggableButton new];preview.editor=self;preview.identifier=key;preview.image=self.buttons[key].image;preview.bordered=NO;preview.toolTip=[self labelForIdentifier:key];preview.accessibilityLabel=preview.toolTip;preview.target=self;preview.action=@selector(removeControl:);
            BOOL primary=[key isEqual:@"play"];[preview.widthAnchor constraintEqualToConstant:primary?54:32].active=YES;[preview.heightAnchor constraintEqualToConstant:primary?28:32].active=YES;
            // Drawing resolves the real shared accent per effective appearance.
            preview.imagePosition=NSImageOnly;
            [group addArrangedSubview:preview];
        }
        CGFloat groupWidth=16+MAX(0,(NSInteger)group.arrangedSubviews.count-1)*8;
        for(NSButton *button in group.arrangedSubviews)groupWidth+=[button.identifier isEqual:@"play"]?54:32;
        naturalWidth+=MAX(32,groupWidth);[self.preview addArrangedSubview:group];
    }
    for(VLCPlayerToolbarPaletteButton *tile in self.palette.tiles){tile.state=[self.enabledIdentifiers containsObject:tile.identifier]?NSControlStateValueOn:NSControlStateValueOff;tile.needsDisplay=YES;}
    self.previewNaturalWidth.constant=naturalWidth;[self.preview vlc_applyRedesignStyle];[self.preview layoutSubtreeIfNeeded];
}
- (BOOL)control:(NSString *)key belongsToGroup:(NSNumber *)group {return key&&group&&[self.sourceGroups[key] isEqual:group];}
- (void)removeControl:(NSButton *)sender {[self.enabledIdentifiers removeObject:sender.identifier];[self updatePreview];}
- (void)insertControl:(NSString *)key inGroup:(NSNumber *)group atIndex:(NSUInteger)index
{
    if(![self control:key belongsToGroup:group])return;
    NSMutableArray *selected=[NSMutableArray array];
    for(NSString *candidate in self.identifiers)if([self.enabledIdentifiers containsObject:candidate]&&![candidate isEqual:key]&&[self control:candidate belongsToGroup:group])[selected addObject:candidate];
    // The insertion cursor counted the dragged item before removal.
    NSUInteger current=[self.identifiers indexOfObject:key];NSUInteger sourcePosition=0;
    if([self.enabledIdentifiers containsObject:key])for(NSUInteger i=0;i<current;i++)if([self.enabledIdentifiers containsObject:self.identifiers[i]]&&[self control:self.identifiers[i] belongsToGroup:group])sourcePosition++;
    if([self.enabledIdentifiers containsObject:key]&&sourcePosition<index)index--;
    [self.identifiers removeObject:key];NSUInteger destination=index<selected.count?[self.identifiers indexOfObject:selected[index]]:selected.count?[self.identifiers indexOfObject:selected.lastObject]+1:self.identifiers.count;
    [self.identifiers insertObject:key atIndex:destination];[self.enabledIdentifiers addObject:key];[self updatePreview];
}
- (void)insertControl:(NSString *)key atIndex:(NSUInteger)index
{
    if(!self.buttons[key])return;NSMutableArray *selected=[NSMutableArray array];
    for(NSString *candidate in self.identifiers)if([self.enabledIdentifiers containsObject:candidate]&&![candidate isEqual:key])[selected addObject:candidate];
    [self.identifiers removeObject:key];NSUInteger destination=index<selected.count?[self.identifiers indexOfObject:selected[index]]:self.identifiers.count;
    [self.identifiers insertObject:key atIndex:destination];[self.enabledIdentifiers addObject:key];[self updatePreview];
}
- (void)cancel:(id)sender {[self.window close];}
- (void)reset:(id)sender
{
    NSArray *defaults=@[@"previous",@"play",@"next",@"audio",@"subtitles",@"settings",@"queue",@"fullscreen",@"pip"];
    self.enabledIdentifiers=[NSMutableSet setWithArray:defaults];NSMutableArray *order=[NSMutableArray arrayWithArray:defaults];
    for(NSString *key in self.identifiers)if(![order containsObject:key])[order addObject:key];self.identifiers=order;[self updatePreview];
}
- (void)save:(id)sender
{
    NSMutableArray *layout=[NSMutableArray array];for(NSString *key in self.identifiers)if([self.enabledIdentifiers containsObject:key])[layout addObject:key];
    [NSUserDefaults.standardUserDefaults setObject:layout forKey:VLCPlayerToolbarLayoutKey];
    [NSNotificationCenter.defaultCenter postNotificationName:VLCPlayerToolbarLayoutChanged object:nil];
    [VLCSettingsProfileManager.sharedInstance saveActiveProfile];[self.window close];
}
@end
