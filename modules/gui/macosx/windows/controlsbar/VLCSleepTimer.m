/* Figma Playback2238:9432 supplies Sleep Timer/Off. Duration is supplied by
 * the user; expiry invokes VLCPlayQueueController's existing Stop behavior. */
#import "VLCSleepTimer.h"
#import "playqueue/VLCPlayQueueController.h"
#import <Cocoa/Cocoa.h>
#include <math.h>

NSString *const VLCSleepTimerChanged = @"VLCSleepTimerChanged";
@interface VLCSleepTimer ()
@property NSTimer *timer;
@property NSTimeInterval deadline;
@property (weak) VLCPlayQueueController *playQueue;
@end
@implementation VLCSleepTimer
+ (VLCSleepTimer *)sharedInstance
{
    static VLCSleepTimer *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}
- (instancetype)init
{
    self = [super init];
    if (self) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interfaceWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
    return self;
}
- (BOOL)active { return self.timer != nil; }
- (NSTimeInterval)remainingSeconds { return self.active ? MAX(0, self.deadline - NSProcessInfo.processInfo.systemUptime) : 0; }
- (void)setDuration:(NSTimeInterval)duration playQueue:(VLCPlayQueueController *)playQueue
{
    [self cancel];
    if (!isfinite(duration) || duration <= 0 || !playQueue) return;
    self.playQueue = playQueue;
    self.deadline = NSProcessInfo.processInfo.systemUptime + duration;
    self.timer = [NSTimer timerWithTimeInterval:1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSModalPanelRunLoopMode];
    [NSNotificationCenter.defaultCenter postNotificationName:VLCSleepTimerChanged object:self];
}
- (void)tick:(NSTimer *)timer
{
    if (self.remainingSeconds <= 0) {
        VLCPlayQueueController *queue = self.playQueue;
        [self cancel];
        [queue stopPlayback];
    } else [NSNotificationCenter.defaultCenter postNotificationName:VLCSleepTimerChanged object:self];
}
- (void)cancel
{
    [self.timer invalidate]; self.timer = nil; self.playQueue = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:VLCSleepTimerChanged object:self];
}
- (void)interfaceWillTerminate:(NSNotification *)notification { [self cancel]; }
@end
