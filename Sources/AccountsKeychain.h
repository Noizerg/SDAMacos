#import "SteamAccounts.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT SteamAccounts * _Nullable LoadSteamAccounts(NSError **error);
FOUNDATION_EXPORT BOOL SaveSteamAccounts(SteamAccounts *accounts, NSError **error);

NS_ASSUME_NONNULL_END
