#import <Cocoa/Cocoa.h>
#import "SteamConfirmations.h"

@interface ConfirmationsWindow : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
- (instancetype)initWithAccount:(SteamAccount *)account saveSession:(BOOL (^)(SteamAccount *))saveSession;
- (void)run;
@end
