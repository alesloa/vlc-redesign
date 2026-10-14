/* GUI navigation data: names, identifiers and artwork come from real ML
 * records; Pins are user choices and visit counters count actual navigation. */
#import <Cocoa/Cocoa.h>
#import "library/VLCLibraryDataTypes.h"

NS_ASSUME_NONNULL_BEGIN
extern NSString * const VLCLibraryNavigationDataChanged;

@interface VLCLibraryNavigationData : NSObject
+ (instancetype)sharedInstance;
- (void)loadHomeWithCompletion:(void (^)(NSArray<NSDictionary *> *sections))completion;
- (void)loadPinsWithCompletion:(void (^)(NSArray<NSDictionary *> *entries))completion;
- (void)recordVisitToItem:(id)item;
- (void)togglePinForItem:(id)item;
- (void)setPinned:(BOOL)pinned forItem:(id)item;
- (BOOL)isPinnedItem:(id)item;
+ (id)representedItem:(id)item;
+ (NSString *)titleForItem:(id)item;
+ (nullable NSString *)serializedIDForItem:(id)item;
@end
NS_ASSUME_NONNULL_END
