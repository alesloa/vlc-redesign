#import <Cocoa/Cocoa.h>
extern NSString *const VLCPlayerToolbarLayoutKey;
extern NSString *const VLCPlayerToolbarLayoutChanged;

// A native GUI layout preference. Buttons keep their existing playback/menu actions.
@interface VLCPlayerToolbarEditorController : NSWindowController
- (instancetype)initWithButtons:(NSDictionary<NSString *, NSButton *> *)buttons;
@end
