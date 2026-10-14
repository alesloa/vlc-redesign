/* Show Statistics is from Figma Playback2238:9432. Every label, conversion and
 * displayed value is from VLCInformationWindowController and VLCInputStats. */
#import "VLCPlayerStatisticsView.h"
#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "playqueue/VLCPlayerController.h"

@interface VLCPlayerStatisticsView ()
@property (weak) VLCPlayerController *player;
@property NSMutableDictionary<NSString *, NSTextField *> *fields;
@end
@implementation VLCPlayerStatisticsView
- (instancetype)initWithPlayerController:(VLCPlayerController *)player
{
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    self.player = player;
    self.fields = [NSMutableDictionary dictionary];
    self.hasVerticalScroller = YES; self.drawsBackground = YES;
    self.backgroundColor = NSColor.VLCWindowBackgroundColor;
    self.wantsLayer = YES; self.layer.cornerRadius = 6; self.layer.masksToBounds = YES;
    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 6; stack.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    self.documentView = stack;
    [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor].active = YES;
    [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor].active = YES;
    [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor].active = YES;
    NSArray *sections = @[
        @[_NS("Input"), @[@"inputReadBytes",_NS("Read at media")], @[@"inputReadPackets",_NS("Read packets")], @[@"inputBitrate",_NS("Input bitrate")], @[@"demuxReadBytes",_NS("Demuxed")], @[@"demuxReadPackets",_NS("Demuxed packets")], @[@"demuxBitrate",_NS("Stream bitrate")], @[@"demuxCorrupted",_NS("Corrupted")], @[@"demuxDiscontinuity",_NS("Discontinuities")]],
        @[_NS("Video"), @[@"decodedVideo",_NS("Decoded blocks")], @[@"displayedPictures",_NS("Displayed frames")], @[@"lostPictures",_NS("Lost frames")], @[@"latePictures",_NS("Late frames")]],
        @[_NS("Audio"), @[@"decodedAudio",_NS("Decoded blocks")], @[@"playedAudioBuffers",_NS("Played buffers")], @[@"lostAudioBuffers",_NS("Lost buffers")]]
    ];
    for (NSArray *section in sections) {
        NSTextField *heading = [NSTextField labelWithString:section.firstObject];
        heading.font = [NSFont vlc_redesignFontOfSize:14 weight:NSFontWeightMedium];
        heading.textColor = NSColor.VLCPrimaryForegroundColor;
        [stack addArrangedSubview:heading];
        for (NSArray *description in [section subarrayWithRange:NSMakeRange(1, section.count-1)]) {
            NSStackView *row = [[NSStackView alloc] init]; row.spacing = 12;
            NSTextField *label = [NSTextField labelWithString:description[1]];
            label.font = [NSFont vlc_redesignFontOfSize:12 weight:NSFontWeightRegular];
            label.textColor = NSColor.VLCControlForegroundColor;
            NSTextField *value = [NSTextField labelWithString:@""];
            value.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
            value.textColor = NSColor.VLCPrimaryForegroundColor; value.alignment = NSTextAlignmentRight;
            [label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
            [row addArrangedSubview:label]; [row addArrangedSubview:value];
            [stack addArrangedSubview:row];
            [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-24].active = YES;
            self.fields[description[0]] = value;
        }
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateStatistics:) name:VLCPlayerStatisticsUpdated object:player];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateStatistics:) name:VLCPlayerCurrentMediaItemChanged object:player];
    [self updateStatistics:nil];
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)updateStatistics:(NSNotification *)notification
{
    VLCInputStats *stats = notification.userInfo[VLCPlayerInputStats] ?: self.player.statistics;
    for (NSString *key in self.fields) {
        NSNumber *value = stats ? [stats valueForKey:key] : nil;
        if (!value) self.fields[key].stringValue = @"";
        else if ([key hasSuffix:@"Bytes"]) self.fields[key].stringValue = [NSString stringWithFormat:@"%.0f KiB",value.doubleValue/1024];
        else if ([key hasSuffix:@"Bitrate"]) self.fields[key].stringValue = [NSString stringWithFormat:@"%.0f kb/s",value.doubleValue*8000];
        else self.fields[key].stringValue = value.stringValue;
    }
}
@end
