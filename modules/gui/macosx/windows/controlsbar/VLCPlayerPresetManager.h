#import <Cocoa/Cocoa.h>
@class VLCPlayerController;
// Source: owner's transcript requests named Subtitle/Audio/Video presets. The
// shared schema/whitelists come from Qt's GUI InterfaceOptions/PresetsModel.
@interface VLCPlayerPresetManager : NSObject
- (instancetype)initWithPlayer:(VLCPlayerController *)player;
- (NSView *)viewForSection:(NSInteger)section;
- (NSDictionary *)captureStateForSection:(NSInteger)section;
- (BOOL)applyState:(NSDictionary *)snapshot section:(NSInteger)section;
@end
