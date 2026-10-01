#import "SteamAccounts.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * _Nullable SteamConfirmationKey(NSString *identitySecret, uint64_t time, NSString *tag);

@interface SteamTradeConfirmation : NSObject
@property(nonatomic, readonly, copy) NSString *identifier;
@property(nonatomic, readonly, copy) NSString *nonce;
@property(nonatomic, readonly, copy) NSString *offerID;
@property(nonatomic, readonly, copy) NSString *headline;
@property(nonatomic, readonly, copy) NSArray<NSString *> *summary;
@end

@interface SteamConfirmations : NSObject <NSURLSessionTaskDelegate>
@property(nonatomic, readonly, strong) SteamAccount *account;
- (instancetype)initWithAccount:(SteamAccount *)account;
// Invoke on a background queue. All requests use an isolated cookie session.
- (nullable NSArray<SteamTradeConfirmation *> *)fetchTrades:(NSError **)error;
- (BOOL)confirmTrade:(SteamTradeConfirmation *)trade error:(NSError **)error;
+ (nullable NSArray<SteamTradeConfirmation *> *)parseTrades:(NSData *)data error:(NSError **)error;
// Injectable transport used by offline tests.
- (nullable NSData *)performRequest:(NSURLRequest *)request error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
