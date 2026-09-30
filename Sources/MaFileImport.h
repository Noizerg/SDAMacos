#import "SteamAccounts.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT SteamAccount * _Nullable SteamAccountFromFile(NSURL *url, NSError **error);

@interface MaFileImportResult : NSObject
@property(nonatomic, readonly, strong) SteamAccounts *accounts;
@property(nonatomic, readonly) NSUInteger addedCount;
@property(nonatomic, readonly) NSUInteger updatedCount;
@property(nonatomic, readonly, copy) NSArray<NSString *> *skippedFiles;
+ (nullable instancetype)fromFolder:(NSURL *)folder
                          accounts:(SteamAccounts *)accounts
                             error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
