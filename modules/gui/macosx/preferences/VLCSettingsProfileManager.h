#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
extern NSString * const VLCSettingsProfileChanged;
@interface VLCSettingsProfileManager : NSObject
@property (class, readonly) VLCSettingsProfileManager *sharedInstance;
@property (readonly) NSString *currentName;
@property (nullable) NSDictionary<NSString *, NSNumber *> *preferenceAppearanceBaseline;
- (NSMenu *)menu;
- (NSDictionary *)configurationSnapshotUsingDefaults:(BOOL)defaults;
- (BOOL)applySnapshot:(NSDictionary *)snapshot;
- (BOOL)applySnapshot:(NSDictionary *)snapshot beforeWriting:(nullable void (^)(void))beforeWriting;
- (void)cancelOlderPreferenceTransaction;
- (void)saveActiveProfile;
- (void)showProfiles:(id)sender;
@end
NS_ASSUME_NONNULL_END
