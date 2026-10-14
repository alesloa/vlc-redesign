#import <Cocoa/Cocoa.h>
#import "preferences/VLCHotkeyChangeWindow.h"
@interface VLCHotkeyWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, VLCHotkeyChangeDelegate>
@end
