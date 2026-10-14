#import <Cocoa/Cocoa.h>
#import "VLCLibrarySegment.h"
NS_ASSUME_NONNULL_BEGIN

@interface VLCCompactLibraryViewController : NSViewController<NSTableViewDelegate, NSTableViewDataSource, NSSearchFieldDelegate, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, NSMenuDelegate>
@property (copy, nullable) void (^expandLibrary)(VLCLibrarySegmentType segment);
@property (copy, nullable) void (^expandSelection)(VLCLibrarySegmentType segment, NSURL * _Nullable folder, id _Nullable parentItem);
@property (copy, nullable) void (^presentLibraryItem)(id item);
@property (copy, nullable) void (^navigateBack)(void);
@property (copy, nullable) void (^navigateForward)(void);
@property BOOL fullLibrary;
- (void)reloadItems;
- (void)focusContent;
- (void)updateNavigationWithBackwardsAvailable:(BOOL)backwards forwardsAvailable:(BOOL)forwards;
@end
NS_ASSUME_NONNULL_END
