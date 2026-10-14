/* Inline advanced sections requested by the owner's transcript. Every label,
 * value, choice, range and help text comes from installed VLC configuration metadata. */
#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_modules.h>
#include <vlc_plugin.h>
#include <vlc_config_cat.h>
#import "VLCInlineAdvancedPreferences.h"
#import "prefs_widgets.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSImage+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"

@interface VLCInlinePreferenceRow : NSView
@property VLCConfigControl *control;
@property NSButton *helpButton;
@end

@interface VLCPreferenceSourceHelp : NSObject
@property (weak) NSView *sourceView;
@property NSString *text;
@end
@implementation VLCPreferenceSourceHelp
@end
@implementation VLCInlinePreferenceRow
- (void)layout
{
    [super layout];
    NSRect frame = self.control.frame;
    frame.origin = NSMakePoint(0, (self.bounds.size.height - frame.size.height) / 2);
    frame.size.width = MAX(0, self.bounds.size.width - 28);
    self.control.frame = frame;
    [self.control alignWithXPosition:MIN(200, frame.size.width / 2)];
    self.helpButton.frame = NSMakeRect(self.bounds.size.width - 20, (self.bounds.size.height - 18) / 2, 18, 18);
}
@end

@interface VLCInlineAdvancedPreferences ()
@property NSMutableArray<NSValue *> *descriptorBlocks;
@property NSMutableDictionary<NSString *, NSMutableArray<NSValue *> *> *descriptorsByCategory;
@property NSMutableArray<VLCConfigControl *> *controls;
@property NSMutableDictionary<NSString *, NSStackView *> *categoryStacks;
@property NSMutableSet<NSString *> *expandedCategories;
@property NSPopover *helpPopover;
@property NSMapTable<VLCConfigControl *, id> *originalValues;
@end

@implementation VLCInlineAdvancedPreferences
- (instancetype)initWithExcludedOptionNames:(NSSet<NSString *> *)excludedNames
{
    self = [super init];
    if (!self) return nil;
    _descriptorBlocks = [NSMutableArray array];
    _descriptorsByCategory = [NSMutableDictionary dictionary];
    _controls = [NSMutableArray array];
    _categoryStacks = [NSMutableDictionary dictionary];
    _expandedCategories = [NSMutableSet set];
    _originalValues = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableSet *seen = [excludedNames mutableCopy];
    size_t count = 0;
    module_t **modules = module_list_get(&count);
    for (size_t i = 0; i < count; i++) {
        unsigned int size = 0;
        module_config_t *items = module_config_get(modules[i], &size);
        if (!items) continue;
        [_descriptorBlocks addObject:[NSValue valueWithPointer:items]];
        enum vlc_config_subcat subcategory = SUBCAT_UNKNOWN;
        for (unsigned int j = 0; j < size; j++) {
            module_config_t *item = &items[j];
            if (item->i_type == CONFIG_SUBCATEGORY) { subcategory = item->value.i; continue; }
            if (!CONFIG_ITEM(item->i_type) || item->psz_name == NULL || item->psz_text == NULL) continue;
            enum vlc_config_cat category = vlc_config_cat_FromSubcat(subcategory);
            if (category == CAT_HIDDEN || category == CAT_UNKNOWN) continue;
            NSString *key = toNSStr(item->psz_name);
            if ([seen containsObject:key] || [key hasPrefix:@"key-"] || [key hasPrefix:@"global-key-"]) continue;
            [seen addObject:key];
            NSString *group = [self categoryForOption:key subcategory:subcategory];
            if (!_descriptorsByCategory[group]) _descriptorsByCategory[group] = [NSMutableArray array];
            [_descriptorsByCategory[group] addObject:[NSValue valueWithPointer:item]];
        }
    }
    module_list_free(modules);
    return self;
}
- (void)dealloc
{
    // Controls retain raw metadata pointers, so release them before metadata arrays.
    self.controls = nil;
    self.categoryStacks = nil;
    for (NSValue *block in self.descriptorBlocks) module_config_free(block.pointerValue);
}
- (NSString *)categoryForOption:(NSString *)key subcategory:(enum vlc_config_subcat)subcategory
{
    if ([key containsString:@"privacy"] || [key containsString:@"metadata-network"] || [key hasPrefix:@"lastfm"] || [key isEqualToString:@"stats"]) return @"privacy";
    if ([key hasPrefix:@"jump-"] || [key containsString:@"mouse"] || subcategory == SUBCAT_INTERFACE_HOTKEYS) return @"controls";
    if ([key hasPrefix:@"ml-"] || [key hasPrefix:@"media-library"] || [key containsString:@"preparse"] || [key hasPrefix:@"playlist-autostart"] || subcategory == SUBCAT_PLAYLIST_SD || subcategory == SUBCAT_PLAYLIST_EXPORT) return @"library";
    if ([key hasPrefix:@"input-record"] || [key hasPrefix:@"sout-"] || vlc_config_cat_FromSubcat(subcategory) == CAT_SOUT) return @"recording";
    if ([key containsString:@"caching"] || [key hasPrefix:@"http-"] || [key hasPrefix:@"rtsp-"] || [key hasPrefix:@"udp-"] || [key hasPrefix:@"network-"] || subcategory == SUBCAT_INPUT_ACCESS || subcategory == SUBCAT_ADVANCED_NETWORK) return @"network";
    if ([key hasPrefix:@"clock-"] || [key hasPrefix:@"avcodec-"] || [key hasPrefix:@"videotoolbox"] || subcategory == SUBCAT_INPUT_VCODEC || subcategory == SUBCAT_INPUT_ACODEC || subcategory == SUBCAT_INPUT_DEMUX) return @"performance";
    if (subcategory == SUBCAT_INPUT_SCODEC || subcategory == SUBCAT_VIDEO_SUBPIC || [key hasPrefix:@"sub-"] || [key hasPrefix:@"subs"] || [key hasPrefix:@"freetype-"]) return @"subtitles";
    if (vlc_config_cat_FromSubcat(subcategory) == CAT_AUDIO) return @"audio";
    if (vlc_config_cat_FromSubcat(subcategory) == CAT_VIDEO) return @"video";
    if (subcategory == SUBCAT_INTERFACE_MAIN || [key hasPrefix:@"macosx-"]) return @"interface";
    if (subcategory == SUBCAT_INTERFACE_CONTROL || [key hasPrefix:@"lua-"]) return @"extensions";
    if (vlc_config_cat_FromSubcat(subcategory) == CAT_PLAYLIST || subcategory == SUBCAT_INPUT_GENERAL || subcategory == SUBCAT_INPUT_STREAM_FILTER) return @"playback";
    return @"general";
}
- (NSView *)viewForCategory:(NSString *)category
{
    if (self.categoryStacks[category]) return self.categoryStacks[category];
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.detachesHiddenViews = YES;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.categoryStacks[category] = stack;
    if (self.descriptorsByCategory[category].count == 0) return stack;
    NSButton *toggle = [NSButton buttonWithTitle:_NS("Advanced") target:self action:@selector(toggleAdvanced:)];
    toggle.identifier = category;
    toggle.bordered = NO;
    toggle.alignment = NSTextAlignmentLeft;
    toggle.font = [NSFont vlc_redesignFontOfSize:16 weight:NSFontWeightRegular];
    toggle.image = [NSImage vlc_redesignImageNamed:@"settings-chevron"];
    toggle.image.size = NSMakeSize(18, 18);
    toggle.imagePosition = NSImageRight;
    [stack addArrangedSubview:toggle];
    [toggle.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [toggle.heightAnchor constraintEqualToConstant:42].active = YES;
    return stack;
}
- (void)toggleAdvanced:(NSButton *)sender
{
    NSString *category = sender.identifier;
    NSStackView *stack = self.categoryStacks[category];
    BOOL expanded = [self.expandedCategories containsObject:category];
    if (expanded) [self.expandedCategories removeObject:category]; else [self.expandedCategories addObject:category];
    if (!expanded && stack.arrangedSubviews.count == 1) {
        NSView *sizingParent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, MAX(540, stack.bounds.size.width), 44)];
        for (NSValue *descriptor in self.descriptorsByCategory[category]) {
            VLCConfigControl *control = [VLCConfigControl newControl:descriptor.pointerValue withView:sizingParent];
            if (!control) continue;
            [control resetValues];
            [self.controls addObject:control];
            [self.originalValues setObject:[self valueForControl:control] forKey:control];
            VLCInlinePreferenceRow *row = [[VLCInlinePreferenceRow alloc] init];
            row.translatesAutoresizingMaskIntoConstraints = NO;
            row.control = control;
            [row addSubview:control];
            NSString *help = control.p_item->psz_longtext ? _NS(control.p_item->psz_longtext) : _NS(control.p_item->psz_text);
            NSButton *info = [NSButton buttonWithTitle:@"" target:self action:@selector(showSourceHelp:)];
            info.image = [NSImage vlc_redesignImageNamed:@"settings-info"];
            info.bordered = NO;
            info.toolTip = help;
            info.accessibilityLabel = _NS("Help");
            row.helpButton = info;
            [row addSubview:info];
            [stack addArrangedSubview:row];
            [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
            [row.heightAnchor constraintEqualToConstant:MAX(44, control.frame.size.height + 12)].active = YES;
            [row vlc_applyRedesignStyle];
        }
    }
    for (NSView *row in stack.arrangedSubviews) if (row != sender) row.hidden = expanded;
    sender.state = expanded ? NSControlStateValueOff : NSControlStateValueOn;
}
- (void)showSourceHelp:(NSButton *)sender
{
    [self presentHelp:sender.toolTip fromView:sender];
}
- (void)presentHelp:(NSString *)text fromView:(NSView *)source
{
    if (text.length == 0) return;
    [self.helpPopover close];
    NSViewController *content = [[NSViewController alloc] init];
    NSTextView *field = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 328, 40)];
    field.editable = NO; field.drawsBackground = NO;
    field.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightRegular];
    field.textColor = NSColor.VLCPrimaryForegroundColor;
    field.string = text;
    field.textContainer.containerSize = NSMakeSize(328, CGFLOAT_MAX);
    field.textContainer.widthTracksTextView = YES;
    [field.layoutManager ensureLayoutForTextContainer:field.textContainer];
    CGFloat height = MAX(40, [field.layoutManager usedRectForTextContainer:field.textContainer].size.height + 12);
    field.frame = NSMakeRect(0, 0, 328, height);
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 16, 328, MIN(440, height))];
    scroll.hasVerticalScroller = YES; scroll.drawsBackground = NO;
    scroll.documentView = field;
    content.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, scroll.frame.size.height + 32)];
    [content.view addSubview:scroll];
    self.helpPopover = [[NSPopover alloc] init];
    self.helpPopover.behavior = NSPopoverBehaviorTransient;
    self.helpPopover.contentViewController = content;
    [self.helpPopover showRelativeToRect:source.bounds ofView:source preferredEdge:NSRectEdgeMaxX];
}
- (void)collectSourceHelp:(NSView *)view intoArray:(NSMutableOrderedSet<NSString *> *)texts
{
    if ([view isKindOfClass:NSControl.class] && view.toolTip.length > 0) [texts addObject:view.toolTip];
    for (NSView *child in view.subviews) [self collectSourceHelp:child intoArray:texts];
}
- (void)showHelpForView:(NSView *)view relativeToView:(NSView *)source
{
    NSMutableOrderedSet *texts = [NSMutableOrderedSet orderedSet];
    [self collectSourceHelp:view intoArray:texts];
    [self presentHelp:[texts.array componentsJoinedByString:@"\n\n"] fromView:source];
}
- (BOOL)hasSourceHelpForView:(NSView *)view
{
    NSMutableOrderedSet *texts = [NSMutableOrderedSet orderedSet];
    [self collectSourceHelp:view intoArray:texts];
    return texts.count > 0;
}
- (void)addSourceHelpToView:(NSView *)view
{
    if ([view isKindOfClass:NSControl.class] && view.toolTip.length > 0) {
        NSMenu *menu = view.menu ?: [[NSMenu alloc] initWithTitle:_NS("Help")];
        for (NSMenuItem *item in menu.itemArray) if (item.action == @selector(showMenuHelp:)) return;
        NSMenuItem *help = [[NSMenuItem alloc] initWithTitle:_NS("Help") action:@selector(showMenuHelp:) keyEquivalent:@""];
        help.target = self;
        VLCPreferenceSourceHelp *source = [[VLCPreferenceSourceHelp alloc] init];
        source.sourceView = view;
        source.text = view.toolTip;
        help.representedObject = source;
        [menu addItem:help];
        view.menu = menu;
    }
    for (NSView *child in view.subviews) [self addSourceHelpToView:child];
}
- (void)showMenuHelp:(NSMenuItem *)sender
{
    VLCPreferenceSourceHelp *source = sender.representedObject;
    if (source.sourceView.window) [self presentHelp:source.text fromView:source.sourceView];
}
- (id)valueForControl:(VLCConfigControl *)control
{
    if (IsConfigStringType(control.p_item->i_type)) {
        char *value = control.stringValue;
        id result = value ? toNSStr(value) : NSNull.null;
        free(value);
        return result;
    }
    if (IsConfigFloatType(control.p_item->i_type)) return @(control.floatValue);
    return @(control.intValue);
}
- (void)applyChanges
{
    // Merely opening Advanced must never rewrite untouched configuration values.
    for (VLCConfigControl *control in self.controls) {
        id value = [self valueForControl:control];
        if (![value isEqual:[self.originalValues objectForKey:control]]) {
            [control applyChanges];
            [self.originalValues setObject:value forKey:control];
        }
    }
}
- (void)resetValues
{
    for (VLCConfigControl *control in self.controls) {
        [control resetValues];
        [self.originalValues setObject:[self valueForControl:control] forKey:control];
    }
}
@end
