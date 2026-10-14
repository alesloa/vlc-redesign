#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
/* A sidebar presentation of the existing native effects controller. */
@interface VLCPlayerEffectsView : NSStackView
- (instancetype)initWithEffectsController:(NSWindowController *)controller audio:(BOOL)audio;
- (instancetype)initWithEffectsController:(NSWindowController *)controller audio:(BOOL)audio includeProfileControls:(BOOL)includeProfiles;
- (void)refreshControls;
/* Reuses the existing effects window; it does not change effect state. */
- (void)installInWindow:(NSWindow *)window;
@end
NS_ASSUME_NONNULL_END
