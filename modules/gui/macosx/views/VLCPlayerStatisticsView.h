#import <Cocoa/Cocoa.h>
@class VLCPlayerController;
@interface VLCPlayerStatisticsView : NSScrollView
- (instancetype)initWithPlayerController:(VLCPlayerController *)player;
@end
