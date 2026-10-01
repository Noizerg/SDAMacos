#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SteamAccount : NSObject
@property(nonatomic, readonly, copy) NSString *identifier;
@property(nonatomic, readonly, copy) NSString *name;
@property(nonatomic, readonly, copy) NSString *secret;
@property(nonatomic, readonly, copy, nullable) NSString *steamID;
@property(nonatomic, readonly, copy, nullable) NSString *identitySecret;
@property(nonatomic, readonly, copy, nullable) NSString *deviceID;
@property(nonatomic, readonly, copy, nullable) NSString *webLogin;
@property(nonatomic, readonly, copy, nullable) NSString *sessionID;
- (nullable SteamAccount *)withWebLogin:(NSString *)login sessionID:(nullable NSString *)sessionID error:(NSError **)error;
+ (nullable instancetype)accountFromMaFile:(NSData *)data fallbackName:(NSString *)name error:(NSError **)error;
+ (nullable instancetype)accountWithName:(NSString *)name secret:(NSString *)secret error:(NSError **)error;
@end

@interface SteamAccounts : NSObject
@property(nonatomic, readonly, copy) NSArray<SteamAccount *> *accounts;
@property(nonatomic, readonly, copy, nullable) NSString *selectedID;
@property(nonatomic, readonly, nullable) SteamAccount *selectedAccount;
+ (instancetype)empty;
+ (nullable instancetype)fromData:(NSData *)data error:(NSError **)error;
- (nullable NSData *)encodedData:(NSError **)error;
- (SteamAccounts *)addingAccount:(SteamAccount *)account;
- (SteamAccounts *)selectingAccount:(NSString *)identifier;
- (SteamAccounts *)removingSelectedAccount;
- (SteamAccounts *)replacingAccount:(SteamAccount *)account;
@end

NS_ASSUME_NONNULL_END
