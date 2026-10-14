/* Native presentation of Figma6259:14954 and6216:13614. */
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface VLCLibraryMediaCollectionController : NSWindowController <NSWindowDelegate, NSTextFieldDelegate, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initForNetwork:(BOOL)network initialURLs:(NSArray<NSURL *> *)URLs;
- (NSModalResponse)runModal;
@property (readonly) NSString *playlistName;
@property (readonly) NSArray<NSURL *> *mediaURLs;
@property (readonly, nullable) NSURL *coverURL;
@property BOOL allowsPlaylistSaving;
@end
NS_ASSUME_NONNULL_END
