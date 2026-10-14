#import <Cocoa/Cocoa.h>

// Keeps VLC's configuration descriptors alive for native, lazy category controls.
@interface VLCInlineAdvancedPreferences : NSObject
- (instancetype)initWithExcludedOptionNames:(NSSet<NSString *> *)excludedNames;
- (NSView *)viewForCategory:(NSString *)category;
- (void)applyChanges;
- (void)resetValues;
- (void)addSourceHelpToView:(NSView *)view;
- (void)showHelpForView:(NSView *)view relativeToView:(NSView *)source;
- (BOOL)hasSourceHelpForView:(NSView *)view;
@end
