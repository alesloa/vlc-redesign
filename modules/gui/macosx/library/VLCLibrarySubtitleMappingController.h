#import <Cocoa/Cocoa.h>
@class VLCMediaLibraryMediaItem;
@interface VLCLibrarySubtitleMappingController : NSWindowController<NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithMediaItems:(NSArray<VLCMediaLibraryMediaItem *> *)items targetTitle:(NSString *)targetTitle;
@end
