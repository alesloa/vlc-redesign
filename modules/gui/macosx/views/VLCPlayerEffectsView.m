/* Labels, bounds, current values and actions come from the original native
 * effects outlets and VLC module metadata. Figma536:1855/543:990/614:1430,
 * 6114:13610,536:1513/536:1703/612:1223 supplies the360px cards,48px
 * disclosure,16px insets,14px captions and8x24 slider handles. Example gains
 * in Figma are never used as state; each clone forwards the original sender. */
#import "VLCPlayerEffectsView.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSView+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "views/VLCRedesignBooleanControl.h"
#import "views/VLCDefaultValueSliderCell.h"
#import "panels/VLCAudioEffectsWindowController.h"
#import "main/VLCMain.h"
#import <vlc_modules.h>
#import <vlc_configuration.h>
#import <vlc_plugin.h>
#import <math.h>

@interface NSWindowController (VLCOriginalEffectsState)
- (void)refreshCurrentValues;
@end

@interface VLCEffectDocument : NSView
@end
@implementation VLCEffectDocument
- (BOOL)isFlipped { return YES; }
@end

@interface VLCEffectColorWell : NSColorWell
@end
@implementation VLCEffectColorWell
- (void)drawRect:(NSRect)dirty
{
    [NSGraphicsContext saveGraphicsState];
    if (!self.enabled) CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, .45);
    NSBezierPath *swatch = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .75, .75) xRadius:2 yRadius:2];
    [self.color setFill]; [swatch fill];
    [[NSColor.VLCPrimaryForegroundColor colorWithAlphaComponent:.21] setStroke];
    swatch.lineWidth = 1.5; [swatch stroke];
    [NSGraphicsContext restoreGraphicsState];
}
@end

@interface VLCEffectCard : NSStackView
@property BOOL valueField;
@end
@implementation VLCEffectCard
- (void)updateSurface
{
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self.layer.backgroundColor=(self.valueField?NSColor.VLCInputBackgroundColor:NSColor.VLCHeaderBackgroundColor).CGColor;
    }];
}
- (void)viewDidChangeEffectiveAppearance {[super viewDidChangeEffectiveAppearance];[self updateSurface];}
- (void)viewDidMoveToWindow {[super viewDidMoveToWindow];[self updateSurface];}
@end

@interface VLCEffectDisclosure : NSButton
@end
@implementation VLCEffectDisclosure
- (void)drawRect:(NSRect)dirty
{
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular],NSForegroundColorAttributeName:NSColor.VLCSecondaryForegroundColor};
    [self.title drawInRect:NSMakeRect(16,(self.bounds.size.height-18)/2,MAX(0,self.bounds.size.width-56),18) withAttributes:attributes];
    NSImage *chevron=[[NSImage vlc_redesignImageNamed:@"settings-chevron"] imageTintedWithColor:NSColor.VLCSecondaryForegroundColor];
    NSRect icon=NSMakeRect(self.bounds.size.width-34,(self.bounds.size.height-24)/2,24,24);
    [NSGraphicsContext saveGraphicsState];
    if(self.state==NSControlStateValueOn){NSAffineTransform *transform=[NSAffineTransform transform];[transform translateXBy:NSMidX(icon) yBy:NSMidY(icon)];[transform rotateByDegrees:180];[transform translateXBy:-NSMidX(icon) yBy:-NSMidY(icon)];[transform concat];}
    [chevron drawInRect:icon];[NSGraphicsContext restoreGraphicsState];
}
@end

@interface VLCEffectCropLink : NSButton
@end
@implementation VLCEffectCropLink
- (void)drawRect:(NSRect)dirty
{
    NSColor *color=self.state==NSControlStateValueOn?NSColor.VLCAccentColor:NSColor.VLCControlForegroundColor;
    NSImage *image=[self.image imageTintedWithColor:color];
    [image drawInRect:NSMakeRect((self.bounds.size.width-24)/2,(self.bounds.size.height-24)/2,24,24)];
}
@end

/* Keep the existing default-value snapping behavior where the original cell
 * has it; only the bar/handle drawing and horizontal presentation changes. */
@interface VLCEffectSliderCell : VLCDefaultValueSliderCell
@end
@implementation VLCEffectSliderCell
- (CGFloat)knobThickness {return 8;}
- (NSRect)knobRectFlipped:(BOOL)flipped
{
    NSRect bounds=self.controlView.bounds;double span=self.maxValue-self.minValue;
    double amount=span>0?(self.doubleValue-self.minValue)/span:0;amount=MAX(0,MIN(1,amount));
    if(self.controlView.userInterfaceLayoutDirection==NSUserInterfaceLayoutDirectionRightToLeft)amount=1-amount;
    return NSMakeRect(amount*MAX(0,bounds.size.width-8),(bounds.size.height-24)/2,8,24);
}
- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped
{
    NSRect bounds=self.controlView.bounds,bar=NSMakeRect(0,(bounds.size.height-16)/2,bounds.size.width,16);
    [NSGraphicsContext saveGraphicsState];if(!self.enabled)CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext,.45);
    [NSColor.VLCInputBackgroundColor setFill];[[NSBezierPath bezierPathWithRoundedRect:bar xRadius:6 yRadius:6]fill];
    NSRect knob=[self knobRectFlipped:flipped],fill=NSInsetRect(bar,2,2);fill.size.width=MAX(0,MIN(fill.size.width,NSMidX(knob)-2));
    if(self.controlView.userInterfaceLayoutDirection==NSUserInterfaceLayoutDirectionRightToLeft){fill.origin.x=NSMidX(knob);fill.size.width=MAX(0,bar.size.width-2-fill.origin.x);}
    [NSColor.VLCAccentFillColor setFill];[[NSBezierPath bezierPathWithRoundedRect:fill xRadius:4 yRadius:4]fill];[NSGraphicsContext restoreGraphicsState];
}
- (void)drawKnob:(NSRect)rect
{
    [NSGraphicsContext saveGraphicsState];if(!self.enabled)CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext,.45);
    [NSColor.VLCAccentDimColor setFill];[[NSBezierPath bezierPathWithRoundedRect:[self knobRectFlipped:self.controlView.flipped] xRadius:3 yRadius:3]fill];[NSGraphicsContext restoreGraphicsState];
}
@end

@interface VLCPlayerEffectsView ()
@property (weak) NSWindowController *effectsController;
@property NSMapTable<NSControl *,NSControl *> *originalControls;
@property NSMapTable<NSTextField *,NSControl *> *originalValues;
@property NSMapTable<NSTextField *,NSTextField *> *frequencyCaptions;
@property NSMapTable<NSControl *,NSString *> *optionControls;
@property NSMapTable<NSTextField *,NSString *> *optionValues;
@property NSMapTable<NSColorWell *,NSTextField *> *colorFields;
@property NSMutableArray<NSDictionary *> *sections;
@property NSPopUpButton *panelSelector;
@end
@implementation VLCPlayerEffectsView
- (NSTextField *)label:(NSString *)text
{
    NSTextField *label=[NSTextField labelWithString:text?:@""];label.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];label.textColor=NSColor.VLCControlForegroundColor;
    label.lineBreakMode=NSLineBreakByWordWrapping;return label;
}
- (id)source:(NSString *)key
{
    return key&&[self.effectsController respondsToSelector:NSSelectorFromString(key)]?[self.effectsController valueForKey:key]:nil;
}
- (void)sizeSlider:(NSSlider *)slider original:(NSSlider *)original
{
    VLCEffectSliderCell *cell=[VLCEffectSliderCell new];
    slider.cell=cell;slider.sliderType=NSSliderTypeLinear;
    if(original){slider.minValue=original.minValue;slider.maxValue=original.maxValue;slider.numberOfTickMarks=original.numberOfTickMarks;slider.allowsTickMarkValuesOnly=original.allowsTickMarkValuesOnly;slider.continuous=original.continuous;}
    // The original cell validates its default against its bounds. Copy bounds
    // first so negative EQ gains and native pitch defaults keep their snap.
    if([original.cell isKindOfClass:VLCDefaultValueSliderCell.class]){VLCDefaultValueSliderCell *source=(id)original.cell;cell.defaultValue=source.defaultValue;cell.snapsToDefault=source.snapsToDefault;cell.drawTickMarkForDefault=source.drawTickMarkForDefault;}
    [slider.heightAnchor constraintEqualToConstant:24].active=YES;
}
- (NSControl *)mirror:(NSString *)key
{
    NSControl *original=[self source:key];if(!original)return nil;NSControl *mirror;
    if([original isKindOfClass:NSSlider.class]){NSSlider *slider=[NSSlider new];[self sizeSlider:slider original:(id)original];mirror=slider;}
    else if([original isKindOfClass:NSPopUpButton.class]){NSPopUpButton *popup=[[NSPopUpButton alloc]initWithFrame:NSZeroRect pullsDown:NO];mirror=popup;[popup.heightAnchor constraintEqualToConstant:36].active=YES;}
    else if([original isKindOfClass:NSButton.class]){NSButton *button=[key.lowercaseString containsString:@"checkbox"]?[VLCRedesignBooleanControl new]:[NSButton new];if([key.lowercaseString containsString:@"checkbox"])[button setButtonType:NSButtonTypeSwitch];button.title=((NSButton *)original).title;mirror=button;[button.heightAnchor constraintEqualToConstant:32].active=YES;}
    else if([original isKindOfClass:NSTextField.class]){NSTextField *field=[NSTextField new];field.formatter=original.formatter;field.editable=((NSTextField *)original).editable;field.selectable=YES;field.continuous=original.continuous;mirror=field;[field.heightAnchor constraintEqualToConstant:32].active=YES;}
    else if([original isKindOfClass:NSStepper.class]){NSStepper *stepper=[NSStepper new];stepper.minValue=((NSStepper *)original).minValue;stepper.maxValue=((NSStepper *)original).maxValue;stepper.increment=((NSStepper *)original).increment;stepper.valueWraps=((NSStepper *)original).valueWraps;stepper.autorepeat=((NSStepper *)original).autorepeat;mirror=stepper;}
    else return nil;
    mirror.translatesAutoresizingMaskIntoConstraints=NO;mirror.target=self;mirror.action=@selector(controlChanged:);mirror.toolTip=original.toolTip;mirror.font=[NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];mirror.identifier=key;
    [self.originalControls setObject:original forKey:mirror];return mirror;
}
- (void)addControl:(NSString *)key to:(NSStackView *)stack
{
    NSControl *control=[self mirror:key];if(!control)return;[stack addArrangedSubview:control];[control.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
}
- (NSButton *)informationForOption:(NSString *)name
{
    const module_config_t *option=config_FindConfig(name.UTF8String);if(!option||!option->psz_text)return nil;
    NSButton *info=[NSButton buttonWithTitle:@"" target:self action:@selector(showInformation:)];info.image=[NSImage vlc_redesignImageNamed:@"settings-info"];info.image.size=NSMakeSize(18,18);info.bordered=NO;info.identifier=name;info.toolTip=_NS(option->psz_longtext&&*option->psz_longtext?option->psz_longtext:option->psz_text);info.accessibilityLabel=_NS("Help");
    [info.widthAnchor constraintEqualToConstant:20].active=YES;[info.heightAnchor constraintEqualToConstant:20].active=YES;return info;
}
- (void)showInformation:(NSButton *)sender
{
    const module_config_t *metadata=config_FindConfig(sender.identifier.UTF8String);if(!metadata||!metadata->psz_text)return;
    NSAlert *alert=[NSAlert new];alert.messageText=_NS(metadata->psz_text);alert.informativeText=sender.toolTip?:@"";[alert addButtonWithTitle:_NS("Close")];[alert runModal];
}
- (void)addSliderControl:(NSSlider *)slider caption:(NSString *)text valueSource:(NSControl *)source option:(NSString *)option to:(NSStackView *)stack
{
    NSStackView *row=[NSStackView stackViewWithViews:@[]];row.orientation=NSUserInterfaceLayoutOrientationVertical;row.alignment=NSLayoutAttributeLeading;row.spacing=10;
    NSStackView *heading=[NSStackView stackViewWithViews:@[]];heading.spacing=8;heading.alignment=NSLayoutAttributeCenterY;heading.distribution=NSStackViewDistributionFill;
    NSTextField *label=[self label:text];[heading addArrangedSubview:label];[label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *help=option?[self informationForOption:option]:nil;if(help)[heading addArrangedSubview:help];
    NSTextField *value=[self label:@""];value.alignment=NSTextAlignmentRight;[value setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    if ([option isEqualToString:@"equalizer-preamp"] || [option isEqualToString:@"equalizer-bands"]) {
        // Figma 6114:13825 gives the real gain field its 140x36 shell. Its
        // value and action still come from the original bounded EQ slider.
        NSSlider *original = (id)source;
        value.editable=YES; value.selectable=YES;
        NSNumberFormatter *formatter=[NSNumberFormatter new];formatter.numberStyle=NSNumberFormatterDecimalStyle;formatter.minimumFractionDigits=1;formatter.maximumFractionDigits=1;formatter.minimum=@(original.minValue);formatter.maximum=@(original.maxValue);value.formatter=formatter;
        value.target=self;value.action=@selector(controlChanged:);value.font=[NSFont vlc_redesignFontOfSize:12 weight:NSFontWeightRegular];
        [self.originalControls setObject:source forKey:value];
        VLCEffectCard *field=[VLCEffectCard new];field.valueField=YES;field.wantsLayer=YES;field.layer.cornerRadius=6;field.edgeInsets=NSEdgeInsetsMake(0,12,0,18);field.spacing=4;field.alignment=NSLayoutAttributeCenterY;
        [field addArrangedSubview:value];NSTextField *unit=[self label:_NS("dB")];unit.font=value.font;[field addArrangedSubview:unit];[field.widthAnchor constraintEqualToConstant:140].active=YES;[field.heightAnchor constraintEqualToConstant:36].active=YES;[heading addArrangedSubview:field];[field updateSurface];
    } else {
        [heading addArrangedSubview:value];
        if(source)[self.originalValues setObject:source forKey:value];else if(option)[self.optionValues setObject:option forKey:value];
    }
    [heading.arrangedSubviews.lastObject.trailingAnchor constraintEqualToAnchor:heading.trailingAnchor].active=YES;
    [row addArrangedSubview:heading];[heading.widthAnchor constraintEqualToAnchor:row.widthAnchor].active=YES;[row addArrangedSubview:slider];[slider.widthAnchor constraintEqualToAnchor:row.widthAnchor].active=YES;
    [stack addArrangedSubview:row];[row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
}
- (void)addSlider:(NSString *)key label:(NSString *)labelKey value:(NSString *)valueKey option:(NSString *)option caption:(NSString *)caption to:(NSStackView *)stack
{
    NSSlider *slider=(id)[self mirror:key];if(!slider)return;NSTextField *label=[self source:labelKey];NSString *text=caption?:label.stringValue;
    if ([option isEqualToString:@"equalizer-bands"] && text.length) text=[text stringByAppendingFormat:@" %@",_NS("Hz")];
    [self addSliderControl:slider caption:text valueSource:valueKey?[self source:valueKey]:[self source:key] option:option to:stack];
    if ([option isEqualToString:@"equalizer-bands"] && label) {
        NSStackView *row=(id)stack.arrangedSubviews.lastObject;
        NSStackView *heading=(id)row.arrangedSubviews.firstObject;
        [self.frequencyCaptions setObject:label forKey:(NSTextField *)heading.arrangedSubviews.firstObject];
    }
}
- (NSStackView *)group:(NSString *)title
{
    VLCEffectCard *card=[VLCEffectCard new];card.valueField=YES;card.orientation=NSUserInterfaceLayoutOrientationVertical;card.alignment=NSLayoutAttributeCenterX;card.spacing=0;card.detachesHiddenViews=YES;[card setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];card.wantsLayer=YES;card.layer.cornerRadius=6;card.identifier=@"VLCPlayerEffectCard";
    VLCEffectDisclosure *disclosure=[VLCEffectDisclosure new];disclosure.title=_NS("Expand Settings");disclosure.accessibilityLabel=disclosure.title;disclosure.bordered=NO;[disclosure setButtonType:NSButtonTypeToggle];disclosure.target=self;disclosure.action=@selector(toggleGroup:);[card addArrangedSubview:disclosure];[disclosure.widthAnchor constraintEqualToAnchor:card.widthAnchor].active=YES;[disclosure.heightAnchor constraintEqualToConstant:48].active=YES;
    NSStackView *body=[NSStackView stackViewWithViews:@[]];body.orientation=NSUserInterfaceLayoutOrientationVertical;body.alignment=NSLayoutAttributeLeading;body.spacing=20;body.edgeInsets=NSEdgeInsetsMake(12,0,20,0);[body setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];body.hidden=YES;
    // A detached collapsed body retains all source controls but contributes
    // no descendant height constraints to the 48px disclosure shell.
    NSLayoutConstraint *bodyWidth=[body.widthAnchor constraintEqualToAnchor:card.widthAnchor constant:-32];
    [self addArrangedSubview:card];NSLayoutConstraint *width=[card.widthAnchor constraintEqualToConstant:360];width.priority=NSLayoutPriorityDefaultHigh;width.active=YES;[card.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor].active=YES;
    NSLayoutConstraint *collapsedHeight=[card.heightAnchor constraintEqualToConstant:48];collapsedHeight.active=YES;
    [self.sections addObject:@{@"title":title?:@"",@"card":card,@"body":body,@"header":disclosure,@"collapsedHeight":collapsedHeight,@"bodyWidth":bodyWidth}];card.hidden=YES;[card updateSurface];return body;
}
- (void)toggleGroup:(NSButton *)sender
{
    VLCEffectCard *card=(id)sender.superview;NSDictionary *section=nil;
    for(NSDictionary *candidate in self.sections)if(candidate[@"card"]==card){section=candidate;break;}
    if(!section)return;NSView *body=section[@"body"];
    NSLayoutConstraint *collapsedHeight=section[@"collapsedHeight"],*bodyWidth=section[@"bodyWidth"];
    if(body.hidden){
        collapsedHeight.active=NO;[card addArrangedSubview:body];body.hidden=NO;bodyWidth.active=YES;
    }else{
        bodyWidth.active=NO;[card removeArrangedSubview:body];[body removeFromSuperview];body.hidden=YES;collapsedHeight.active=YES;
    }
    card.valueField=body.hidden;[card updateSurface];sender.state=body.hidden?NSControlStateValueOff:NSControlStateValueOn;sender.title=body.hidden?_NS("Expand Settings"):_NS("Collapse Settings");sender.accessibilityLabel=sender.title;sender.needsDisplay=YES;
}
- (void)selectPanel:(id)sender
{
    NSInteger selected=self.panelSelector.indexOfSelectedItem;for(NSUInteger i=0;i<self.sections.count;i++)((NSView *)self.sections[i][@"card"]).hidden=(NSInteger)i!=selected;
    [self refreshControls];
}
- (NSStackView *)field:(NSString *)key label:(NSString *)labelKey
{
    NSStackView *column=[NSStackView stackViewWithViews:@[]];column.orientation=NSUserInterfaceLayoutOrientationVertical;column.alignment=NSLayoutAttributeLeading;column.spacing=6;NSTextField *source=[self source:labelKey];[column addArrangedSubview:[self label:source.stringValue]];
    NSControl *field=[self mirror:key];if(field){NSStackView *row=[NSStackView stackViewWithViews:@[field]];NSString *stepperKey=[key stringByReplacingOccurrencesOfString:@"TextField" withString:@"Stepper"];NSControl *stepper=[self mirror:stepperKey];if(stepper)[row addArrangedSubview:stepper];row.spacing=8;[column addArrangedSubview:row];[row.widthAnchor constraintEqualToAnchor:column.widthAnchor].active=YES;}
    return column;
}
- (void)addField:(NSString *)key label:(NSString *)label to:(NSStackView *)stack
{
    NSStackView *field=[self field:key label:label];[stack addArrangedSubview:field];[field.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active=YES;
}
- (NSStackView *)cropField:(NSString *)side
{
    NSString *valueKey=[NSString stringWithFormat:@"crop%@TextField",side];
    if (![self source:valueKey]) return nil;
    VLCEffectCard *field=[VLCEffectCard new];field.valueField=YES;field.wantsLayer=YES;field.layer.cornerRadius=6;field.edgeInsets=NSEdgeInsetsMake(0,12,0,6);field.spacing=4;field.alignment=NSLayoutAttributeCenterY;
    NSTextField *source=[self source:[NSString stringWithFormat:@"crop%@Label",side]];[field addArrangedSubview:[self label:source.stringValue]];
    NSTextField *value=(id)[self mirror:valueKey];value.bordered=NO;value.drawsBackground=NO;value.alignment=NSTextAlignmentRight;[field addArrangedSubview:value];[value.widthAnchor constraintGreaterThanOrEqualToConstant:32].active=YES;
    // The original crop formatter already supplies the localized pixel suffix.
    [field.heightAnchor constraintEqualToConstant:32].active=YES;[field updateSurface];return field;
}
- (void)addCropPair:(NSArray<NSString *> *)sides sync:(NSString *)key to:(NSStackView *)body
{
    NSStackView *first=[self cropField:sides[0]],*second=[self cropField:sides[1]];NSButton *original=[self source:key];if(!first||!second||!original)return;NSButton *link=[VLCEffectCropLink new];[link setButtonType:NSButtonTypeToggle];link.bordered=NO;link.image=[NSImage vlc_redesignImageNamed:@"settings-crop-link"];link.image.size=NSMakeSize(24,24);link.target=self;link.action=@selector(controlChanged:);link.identifier=key;link.toolTip=original.title;link.accessibilityLabel=original.title;[self.originalControls setObject:original forKey:link];
    NSStackView *row=[NSStackView stackViewWithViews:@[first,second,link]];row.spacing=8;row.alignment=NSLayoutAttributeCenterY;[first.widthAnchor constraintEqualToAnchor:second.widthAnchor].active=YES;[link.widthAnchor constraintEqualToConstant:30].active=YES;[link.heightAnchor constraintEqualToConstant:32].active=YES;[body addArrangedSubview:row];[row.widthAnchor constraintEqualToAnchor:body.widthAnchor].active=YES;
}
- (void)addColor:(NSString *)fieldKey checkbox:(NSString *)checkbox caption:(NSString *)caption option:(NSString *)option to:(NSStackView *)body
{
    NSTextField *original=[self source:fieldKey],*value=(id)[self mirror:fieldKey];NSButton *toggle=(id)[self mirror:checkbox];if(!original||!value||!toggle)return;toggle.title=@"";[toggle.widthAnchor constraintEqualToConstant:68].active=YES;
    VLCEffectCard *field=[VLCEffectCard new];field.valueField=YES;field.wantsLayer=YES;field.layer.cornerRadius=6;field.edgeInsets=NSEdgeInsetsMake(0,12,0,5);field.spacing=10;field.alignment=NSLayoutAttributeCenterY;
    NSStackView *text=[NSStackView stackViewWithViews:@[[self label:@"#"],value]];text.spacing=0;value.bordered=NO;value.drawsBackground=NO;value.alignment=NSTextAlignmentRight;[field addArrangedSubview:text];
    NSColorWell *well=[VLCEffectColorWell new];well.bordered=NO;well.target=self;well.action=@selector(colorChanged:);well.identifier=option;[self.colorFields setObject:original forKey:well];[field addArrangedSubview:well];[well.widthAnchor constraintEqualToConstant:22].active=YES;[well.heightAnchor constraintEqualToConstant:22].active=YES;[field.widthAnchor constraintEqualToConstant:116].active=YES;[field.heightAnchor constraintEqualToConstant:32].active=YES;[field updateSurface];
    NSStackView *row=[NSStackView stackViewWithViews:@[]];row.spacing=4;row.alignment=NSLayoutAttributeCenterY;row.distribution=NSStackViewDistributionFill;NSTextField *label=[self label:caption];[label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];[row addArrangedSubview:label];NSButton *info=[self informationForOption:option];if(info)[row addArrangedSubview:info];[row addArrangedSubview:field];[row setCustomSpacing:8 afterView:field];[row addArrangedSubview:toggle];[body addArrangedSubview:row];[row.widthAnchor constraintEqualToAnchor:body.widthAnchor].active=YES;
}
- (void)colorChanged:(NSColorWell *)sender
{
    NSTextField *original=[self.colorFields objectForKey:sender];if(!original.enabled||VLCMain.sharedInstance.isTerminating)return;NSColor *color=[sender.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];if(!color)return;
    NSInteger rgb=(lround(color.redComponent*255)<<16)|(lround(color.greenComponent*255)<<8)|lround(color.blueComponent*255);original.objectValue=@(rgb);[NSApp sendAction:original.action to:original.target from:original];[self refreshControls];
}
- (void)updateOriginalValueBinding:(NSControl *)original
{
    // Original nib value bindings link crop/geometry fields and steppers to
    // controller setters. A cloned edit must perform that same reverse write
    // before sending the original action (notably synchronized crop sides).
    NSDictionary *binding=[original infoForBinding:NSValueBinding];
    id object=binding[NSObservedObjectKey];NSString *keyPath=binding[NSObservedKeyPathKey];
    if(object&&keyPath.length)[object setValue:original.objectValue forKeyPath:keyPath];
}
- (instancetype)initWithEffectsController:(NSWindowController *)controller audio:(BOOL)audio
{
    return [self initWithEffectsController:controller audio:audio includeProfileControls:NO];
}
- (instancetype)initWithEffectsController:(NSWindowController *)controller audio:(BOOL)audio includeProfileControls:(BOOL)profiles
{
    self=[super init];if(!self)return nil;self.effectsController=controller;self.originalControls=NSMapTable.strongToWeakObjectsMapTable;self.originalValues=NSMapTable.strongToWeakObjectsMapTable;self.frequencyCaptions=NSMapTable.strongToWeakObjectsMapTable;self.optionControls=NSMapTable.strongToStrongObjectsMapTable;self.optionValues=NSMapTable.strongToStrongObjectsMapTable;self.colorFields=NSMapTable.strongToWeakObjectsMapTable;self.sections=[NSMutableArray array];self.orientation=NSUserInterfaceLayoutOrientationVertical;self.alignment=NSLayoutAttributeCenterX;self.spacing=20;self.detachesHiddenViews=YES;[self setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    (void)controller.window;[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(originalSheetEnded:) name:NSWindowDidEndSheetNotification object:controller.window];if([controller respondsToSelector:@selector(refreshCurrentValues)])[controller refreshCurrentValues];
    if(profiles){[self addControl:@"profilePopup" to:self];[self addControl:@"applyProfileCheckbox" to:self];}
    self.panelSelector=[[NSPopUpButton alloc]initWithFrame:NSZeroRect pullsDown:NO];self.panelSelector.target=self;self.panelSelector.action=@selector(selectPanel:);self.panelSelector.identifier=@"VLCNativeEffectsPanelSelector";[self addArrangedSubview:self.panelSelector];[self.panelSelector.widthAnchor constraintEqualToConstant:320].active=YES;[self.panelSelector.heightAnchor constraintEqualToConstant:36].active=YES;
    NSSegmentedControl *segments=[self source:@"segmentView"];
    if(audio){
        if(module_exists("equalizer")){NSStackView *group=[self group:[segments labelForSegment:0]];[self addControl:@"equalizerEnableCheckbox" to:group];[self addControl:@"equalizerPresetsPopup" to:group];[self addControl:@"equalizerTwoPassCheckbox" to:group];[self addSlider:@"equalizerPreampSlider" label:@"equalizerPreampLabel" value:nil option:@"equalizer-preamp" caption:nil to:group];for(NSUInteger band=1;band<=10;band++)[self addSlider:[NSString stringWithFormat:@"equalizerBand%luSlider",band] label:[NSString stringWithFormat:@"equalizerBand%luTextField",band] value:nil option:@"equalizer-bands" caption:nil to:group];}
        for(NSArray *spec in @[@[@"compressor",@1,@7],@[@"spatializer",@2,@5]]){NSString *prefix=spec[0];if(!module_exists(prefix.UTF8String))continue;NSStackView *group=[self group:[segments labelForSegment:[spec[1]integerValue]]];[self addControl:[prefix stringByAppendingString:@"EnableCheckbox"] to:group];NSArray *options=[prefix isEqual:@"compressor"]?@[@"compressor-rms-peak",@"compressor-attack",@"compressor-release",@"compressor-threshold",@"compressor-ratio",@"compressor-knee",@"compressor-makeup-gain"]:@[@"spatializer-roomsize",@"spatializer-width",@"spatializer-wet",@"spatializer-dry",@"spatializer-damp"];for(NSUInteger band=1;band<=[spec[2]unsignedIntegerValue];band++){NSString *base=[NSString stringWithFormat:@"%@Band%lu",prefix,band];[self addSlider:[base stringByAppendingString:@"Slider"] label:[base stringByAppendingString:@"Label"] value:[base stringByAppendingString:@"TextField"] option:options[band-1] caption:nil to:group];}[self addControl:[prefix stringByAppendingString:@"ResetButton"] to:group];}
        if(module_exists("stereo_widen")){NSStackView *group=[self group:_NS("Stereo Widener")];[self addControl:@"filterStereoEnhancerCheckbox" to:group];for(NSString *option in @[@"stereowiden-delay",@"stereowiden-feedback",@"stereowiden-crossfeed",@"stereowiden-dry-mix"]){const module_config_t *metadata=config_FindConfig(option.UTF8String);if(!metadata||!metadata->psz_text)continue;NSSlider *slider=[NSSlider new];[self sizeSlider:slider original:nil];slider.minValue=metadata->min.f;slider.maxValue=metadata->max.f;slider.continuous=YES;slider.target=self;slider.action=@selector(stereoChanged:);slider.identifier=option;[self.optionControls setObject:option forKey:slider];[self addSliderControl:slider caption:_NS(metadata->psz_text) valueSource:nil option:option to:group];}}
        if(module_exists("scaletempo_pitch")||module_exists("stereopan")){NSStackView *group=[self group:[segments labelForSegment:4]];if(module_exists("scaletempo_pitch")){[self addControl:@"advancedEnablePitchCheckBox" to:group];[self addSlider:@"advancedPitchSlider" label:nil value:@"advancedPitchTextField" option:@"pitch-shift" caption:_NS("Pitch Shift") to:group];}if(module_exists("stereopan")){[self addControl:@"advancedEnableStereoPanCheckBox" to:group];[self addSlider:@"advancedStereoPanSlider" label:nil value:@"advancedStereoPanTextField" option:@"pan-control" caption:_NS("Pan control") to:group];}[self addControl:@"advancedResetButton" to:group];}
        NSStackView *filters=nil;for(NSArray *spec in @[@[@"headphone",@"filterHeadPhoneCheckbox"],@[@"normvol",@"filterNormLevelCheckbox"],@[@"karaoke",@"filterKaraokeCheckbox"],@[@"scaletempo",@"filterScaleTempoCheckbox"]]){if(!module_exists([spec[0]UTF8String]))continue;if(!filters)filters=[self group:[segments labelForSegment:3]];[self addControl:spec[1] to:filters];if([spec[0]isEqual:@"normvol"])[self addSlider:@"filterNormLevelSlider" label:@"filterNormLevelLabel" value:nil option:@"norm-max-level" caption:nil to:filters];}
    }else{
        NSStackView *essential=nil;for(NSString *module in @[@"adjust",@"sharpen",@"gradfun",@"grain"]){if(!module_exists(module.UTF8String))continue;if(!essential)essential=[self group:_NS("Essential")];if([module isEqual:@"adjust"]){[self addControl:@"adjustCheckbox" to:essential];for(NSString *suffix in @[@"Hue",@"Brightness",@"Contrast",@"Saturation",@"Gamma"])[self addSlider:[NSString stringWithFormat:@"adjust%@Slider",suffix] label:[NSString stringWithFormat:@"adjust%@Label",suffix] value:nil option:suffix.lowercaseString caption:nil to:essential];[self addControl:@"adjustResetButton" to:essential];}else{NSString *prefix=[module isEqual:@"gradfun"]?@"banding":module;NSString *option=[module isEqual:@"sharpen"]?@"sharpen-sigma":[module isEqual:@"gradfun"]?@"gradfun-radius":@"grain-variance";NSString *caption=[module isEqual:@"sharpen"]?_NS("Sharpen Sigma"):[module isEqual:@"gradfun"]?_NS("Banding Removal Radius"):_NS("Film Grain Variance");[self addControl:[prefix stringByAppendingString:@"Checkbox"] to:essential];[self addSlider:[prefix stringByAppendingString:@"Slider"] label:[prefix stringByAppendingString:@"Label"] value:nil option:option caption:caption to:essential];}}
        NSStackView *crop=[self group:[segments labelForSegment:1]];crop.spacing=16;crop.edgeInsets=NSEdgeInsetsMake(6,0,16,0);[self addCropPair:@[@"Top",@"Bottom"] sync:@"cropSyncTopBottomCheckbox" to:crop];[self addCropPair:@[@"Left",@"Right"] sync:@"cropSyncLeftRightCheckbox" to:crop];
        NSStackView *colors=nil;for(NSArray *spec in @[@[@"extract",@"extract"],@[@"colorthres",@"threshold"],@[@"invert",@"invert"],@[@"posterize",@"posterize"],@[@"gradient",@"gradient"],@[@"sepia",@"sepia"]]){if(!module_exists([spec[0]UTF8String]))continue;if(!colors)colors=[self group:_NS("Colors")];NSString *prefix=spec[1];if([prefix isEqual:@"extract"])[self addColor:@"extractTextField" checkbox:@"extractCheckbox" caption:_NS("Color Extraction") option:@"extract-component" to:colors];else if([prefix isEqual:@"threshold"]){[self addColor:@"thresholdColorTextField" checkbox:@"thresholdCheckbox" caption:_NS("Color Threshold") option:@"colorthres-color" to:colors];[self addSlider:@"thresholdSaturationSlider" label:@"thresholdSaturationLabel" value:nil option:@"colorthres-saturationthres" caption:nil to:colors];[self addSlider:@"thresholdSimilaritySlider" label:@"thresholdSimilarityLabel" value:nil option:@"colorthres-similaritythres" caption:nil to:colors];}else{[self addControl:[prefix stringByAppendingString:@"Checkbox"] to:colors];if([prefix isEqual:@"gradient"]){[self addControl:@"gradientModePopup" to:colors];[self addControl:@"gradientColorCheckbox" to:colors];[self addControl:@"gradientCartoonCheckbox" to:colors];}else if([prefix isEqual:@"posterize"])[self addField:@"posterizeTextField" label:@"posterizeLabel" to:colors];else if([prefix isEqual:@"sepia"]){const module_config_t *metadata=config_FindConfig("sepia-intensity");NSSlider *slider=[NSSlider new];[self sizeSlider:slider original:nil];if(!metadata||!IsConfigIntegerType(metadata->i_type)||![self source:@"sepiaTextField"])continue;slider.minValue=metadata->min.i;slider.maxValue=metadata->max.i;slider.continuous=YES;slider.target=self;slider.action=@selector(controlChanged:);slider.identifier=@"sepiaTextField";[self.originalControls setObject:[self source:@"sepiaTextField"] forKey:slider];[self addSliderControl:slider caption:_NS("Sepia Intensity") valueSource:[self source:@"sepiaTextField"] option:@"sepia-intensity" to:colors];}}}
        NSStackView *geometry=nil;for(NSArray *spec in @[@[@"transform",@"transform"],@[@"magnify",@"zoom"],@[@"puzzle",@"puzzle"],@[@"clone",@"clone"],@[@"wall",@"wall"]]){if(!module_exists([spec[0]UTF8String]))continue;if(!geometry)geometry=[self group:[segments labelForSegment:2]];NSString *prefix=spec[1];[self addControl:[prefix stringByAppendingString:@"Checkbox"] to:geometry];if([prefix isEqual:@"transform"])[self addControl:@"transformPopup" to:geometry];else if([prefix isEqual:@"puzzle"]){[self addField:@"puzzleRowsTextField" label:@"puzzleRowsLabel" to:geometry];[self addField:@"puzzleColumnsTextField" label:@"puzzleColumnsLabel" to:geometry];}else if([prefix isEqual:@"clone"])[self addField:@"cloneNumberTextField" label:@"cloneNumberLabel" to:geometry];else if([prefix isEqual:@"wall"]){[self addField:@"wallNumbersOfRowsTextField" label:@"wallNumbersOfRowsLabel" to:geometry];[self addField:@"wallNumberOfColumnsTextField" label:@"wallNumberOfColumnsLabel" to:geometry];}}
        NSStackView *misc=nil;for(NSArray *spec in @[@[@"motionblur",@"blurCheckbox"],@[@"motiondetect",@"motiondetectCheckbox"],@[@"ripple",@"watereffectCheckbox"],@[@"wave",@"wavesCheckbox"],@[@"psychedelic",@"psychedelicCheckbox"],@[@"anaglyph",@"anaglyphCheckbox"],@[@"marq",@"addTextCheckbox"],@[@"logo",@"addLogoCheckbox"]]){if(!module_exists([spec[0]UTF8String]))continue;if(!misc)misc=[self group:[segments labelForSegment:4]];[self addControl:spec[1] to:misc];if([spec[0]isEqual:@"motionblur"])[self addSlider:@"blurSlider" label:@"blurLabel" value:nil option:@"blur-factor" caption:nil to:misc];else if([spec[0]isEqual:@"marq"]){[self addField:@"addTextTextTextField" label:@"addTextTextLabel" to:misc];[self addControl:@"addTextPositionPopup" to:misc];}else if([spec[0]isEqual:@"logo"]){[self addField:@"addLogoLogoTextField" label:@"addLogoLogoLabel" to:misc];[self addControl:@"addLogoPositionPopup" to:misc];[self addSlider:@"addLogoTransparencySlider" label:@"addLogoTransparencyLabel" value:nil option:@"logo-opacity" caption:nil to:misc];}}
    }
    for(NSDictionary *section in self.sections)[self.panelSelector addItemWithTitle:section[@"title"]];[self selectPanel:nil];[self refreshControls];[self vlc_applyRedesignStyle];return self;
}
- (void)stereoChanged:(NSSlider *)sender
{
    if(VLCMain.sharedInstance.isTerminating)return;VLCAudioEffectsWindowController *controller=(id)self.effectsController;NSString *option=[self.optionControls objectForKey:sender];if(option)[controller redesignSetStereoValue:sender.doubleValue forOption:option];[self refreshControls];
}
- (void)originalSheetEnded:(NSNotification *)notification
{
    // The original sheet action invokes its completion after endSheet, and
    // may restore the original popup selection on Cancel. Refresh afterward.
    __weak typeof(self) weakSelf=self;
    [NSOperationQueue.mainQueue addOperationWithBlock:^{
        if(weakSelf && !VLCMain.sharedInstance.isTerminating)[weakSelf refreshControls];
    }];
}
- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)installInWindow:(NSWindow *)window
{
    // Figma's player-effects frame is 400x821, with 20px outer insets.
    // The existing window, title, delegate and sheets remain in use.
    NSScrollView *scroll=[NSScrollView new];scroll.hasVerticalScroller=YES;
    scroll.autohidesScrollers=YES;scroll.drawsBackground=NO;scroll.borderType=NSNoBorder;
    VLCEffectDocument *document=[VLCEffectDocument new];document.translatesAutoresizingMaskIntoConstraints=NO;
    document.wantsLayer=YES;document.identifier=@"VLCRedesignedLibraryContent";
    scroll.documentView=document;self.translatesAutoresizingMaskIntoConstraints=NO;
    [document addSubview:self];window.contentView=scroll;
    // A short document must remain shorter than the clip view. Requiring it
    // to fill the viewport stretches collapsed disclosure cards.
    NSLayoutConstraint *naturalHeight=[document.heightAnchor constraintEqualToAnchor:self.heightAnchor constant:40];
    [NSLayoutConstraint activateConstraints:@[
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [self.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:20],
        [self.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-20],
        [self.topAnchor constraintEqualToAnchor:document.topAnchor constant:20],
        [document.bottomAnchor constraintGreaterThanOrEqualToAnchor:self.bottomAnchor constant:20],naturalHeight]];
    [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    NSRect visible=(window.screen?:NSScreen.mainScreen).visibleFrame;
    CGFloat decoration=window.frame.size.height-[window contentRectForFrameRect:window.frame].size.height;
    CGFloat height=MIN(821,visible.size.height-decoration);
    window.styleMask|=NSWindowStyleMaskResizable;
    window.contentMinSize=NSMakeSize(400,MIN(window.contentMinSize.height,height));
    [window setContentSize:NSMakeSize(400,height)];[scroll vlc_applyRedesignStyle];
}
- (void)refreshControls
{
    for(NSControl *mirror in self.originalControls){NSControl *original=[self.originalControls objectForKey:mirror];if(!original)continue;mirror.enabled=original.enabled;
        if([mirror isKindOfClass:NSPopUpButton.class]){NSPopUpButton *popup=(id)mirror,*source=(id)original;if(![popup.itemTitles isEqual:source.itemTitles]){[popup removeAllItems];for(NSMenuItem *item in source.itemArray){NSMenuItem *copy=item.copy;copy.target=nil;copy.action=NULL;[popup.menu addItem:copy];}}[popup selectItemAtIndex:source.indexOfSelectedItem];}
        else if([mirror isKindOfClass:NSButton.class])((NSButton *)mirror).state=((NSButton *)original).state;
        else mirror.objectValue=original.objectValue;mirror.needsDisplay=YES;
    }
    for(NSTextField *label in self.originalValues){NSControl *original=[self.originalValues objectForKey:label];if(!original)continue;label.stringValue=[original isKindOfClass:NSTextField.class]?original.stringValue:original.toolTip.length?original.toolTip:[original.objectValue description]?:@"";label.textColor=original.enabled?NSColor.VLCControlForegroundColor:NSColor.VLCSecondaryForegroundColor;}
    for(NSTextField *caption in self.frequencyCaptions){NSTextField *source=[self.frequencyCaptions objectForKey:caption];if(source)caption.stringValue=[source.stringValue stringByAppendingFormat:@" %@",_NS("Hz")];}
    VLCAudioEffectsWindowController *audio=[self.effectsController isKindOfClass:VLCAudioEffectsWindowController.class]?(id)self.effectsController:nil;BOOL enabled=((NSButton *)[self source:@"filterStereoEnhancerCheckbox"]).state==NSControlStateValueOn&&[audio redesignHasAudioOutput];
    for(NSControl *control in self.optionControls){NSNumber *value=[audio redesignStereoValueForOption:[self.optionControls objectForKey:control]];control.enabled=enabled&&value!=nil;if(value)control.objectValue=value;control.needsDisplay=YES;}
    for(NSTextField *label in self.optionValues){NSString *option=[self.optionValues objectForKey:label];NSNumber *value=[audio redesignStereoValueForOption:option];label.stringValue=value?([option isEqual:@"stereowiden-delay"]?[NSString localizedStringWithFormat:@"%.1f ms",value.doubleValue]:[NSString localizedStringWithFormat:@"%.3g",value.doubleValue]):@"";}
    for(NSColorWell *well in self.colorFields){NSTextField *field=[self.colorFields objectForKey:well];NSInteger rgb=field.integerValue;well.color=[NSColor colorWithSRGBRed:((rgb>>16)&255)/255. green:((rgb>>8)&255)/255. blue:(rgb&255)/255. alpha:1];well.enabled=field.enabled;}
}
- (void)controlChanged:(NSControl *)sender
{
    if(VLCMain.sharedInstance.isTerminating)return;NSControl *original=[self.originalControls objectForKey:sender];if(!original||!original.enabled)return;
    if([sender isKindOfClass:NSPopUpButton.class]){NSPopUpButton *popup=(id)original;[popup selectItemAtIndex:((NSPopUpButton *)sender).indexOfSelectedItem];if(popup.selectedItem.action){[self.effectsController showWindow:self];[NSApp sendAction:popup.selectedItem.action to:popup.selectedItem.target from:popup.selectedItem];}else [NSApp sendAction:original.action to:original.target from:original];}
    else{if([sender isKindOfClass:NSButton.class])((NSButton *)original).state=((NSButton *)sender).state;else original.objectValue=sender.objectValue;[self updateOriginalValueBinding:original];[NSApp sendAction:original.action to:original.target from:original];}
    [self refreshControls];
}
@end
