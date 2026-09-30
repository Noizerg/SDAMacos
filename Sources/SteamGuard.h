#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * _Nullable SteamGuardCode(NSString *secret, NSTimeInterval timestamp);
FOUNDATION_EXPORT BOOL SteamGuardSecretIsValid(NSString *secret);
FOUNDATION_EXPORT NSInteger SteamGuardSecondsRemaining(NSTimeInterval timestamp);

NS_ASSUME_NONNULL_END
