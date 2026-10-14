#import <Foundation/Foundation.h>
@class VLCPlayQueueController;
extern NSString *const VLCSleepTimerChanged;

// An application-lifetime GUI timer around the existing playlist Stop action.
@interface VLCSleepTimer : NSObject
@property (class, readonly) VLCSleepTimer *sharedInstance;
@property (readonly) NSTimeInterval remainingSeconds;
@property (readonly) BOOL active;
- (void)setDuration:(NSTimeInterval)duration playQueue:(VLCPlayQueueController *)playQueue;
- (void)cancel;
@end
