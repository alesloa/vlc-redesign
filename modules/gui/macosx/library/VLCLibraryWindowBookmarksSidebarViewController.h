/* Native presentation of the existing media-library bookmark model. */
#import <Cocoa/Cocoa.h>
#import "library/VLCLibraryWindowSidebarChildViewController.h"

@class VLCLibraryWindow;

@interface VLCLibraryWindowBookmarksSidebarViewController : NSViewController<VLCLibraryWindowSidebarChildViewController, NSTableViewDelegate, NSTableViewDataSource>
@property (readwrite, nonatomic) NSTextField *counterLabel;
- (instancetype)initWithLibraryWindow:(VLCLibraryWindow *)libraryWindow;
@end
