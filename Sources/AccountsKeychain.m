#import "AccountsKeychain.h"
#import <Security/Security.h>

static NSString * const Service = @"local.steamguard.lite";
static NSString * const AccountsKey = @"accounts-v1";
static NSString * const LegacyKey = @"shared-secret";

static NSDictionary *Lookup(NSString *key) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: Service,
             (__bridge id)kSecAttrAccount: key};
}

static NSError *KeychainError(OSStatus status) {
    NSString *message = CFBridgingRelease(SecCopyErrorMessageString(status, NULL));
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:status
                          userInfo:@{NSLocalizedDescriptionKey:
                                         message ? message : @"Ошибка Связки ключей"}];
}

static NSData *ReadData(NSString *key, NSError **error) {
    NSMutableDictionary *query = Lookup(key).mutableCopy;
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef raw = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &raw);
    if (status == errSecItemNotFound) return nil;
    if (status != errSecSuccess) {
        if (error) *error = KeychainError(status);
        return nil;
    }
    return CFBridgingRelease(raw);
}

BOOL SaveSteamAccounts(SteamAccounts *accounts, NSError **error) {
    NSData *data = [accounts encodedData:error];
    if (!data) return NO;
    NSDictionary *lookup = Lookup(AccountsKey);
    NSDictionary *update = @{(__bridge id)kSecValueData: data};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)lookup, (__bridge CFDictionaryRef)update);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *add = lookup.mutableCopy;
        [add addEntriesFromDictionary:update];
        status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
    if (status != errSecSuccess && error) *error = KeychainError(status);
    return status == errSecSuccess;
}

SteamAccounts *LoadSteamAccounts(NSError **error) {
    NSError *readError = nil;
    NSData *data = ReadData(AccountsKey, &readError);
    if (readError) {
        if (error) *error = readError;
        return nil;
    }
    if (data) return [SteamAccounts fromData:data error:error];

    NSData *legacyData = ReadData(LegacyKey, &readError);
    if (readError) {
        if (error) *error = readError;
        return nil;
    }
    if (!legacyData) return SteamAccounts.empty;

    NSString *legacySecret = [[NSString alloc] initWithData:legacyData encoding:NSUTF8StringEncoding];
    SteamAccount *legacy = [SteamAccount accountWithName:@"Сохранённый аккаунт"
                                                 secret:legacySecret error:error];
    if (!legacy) return nil;
    SteamAccounts *migrated = [SteamAccounts.empty addingAccount:legacy];
    if (!SaveSteamAccounts(migrated, error)) return nil;
    // Delete only after the complete new representation has been saved.
    // If deletion is denied, the new entry still wins on every future launch.
    SecItemDelete((__bridge CFDictionaryRef)Lookup(LegacyKey));
    return migrated;
}
