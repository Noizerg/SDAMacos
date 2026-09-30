#import "SteamAccounts.h"
#import "SteamGuard.h"

static NSError *AccountError(NSString *message) {
    return [NSError errorWithDomain:@"SteamGuardLite.Accounts" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *CleanString(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return text.length ? text : nil;
}

@interface SteamAccount ()
- (instancetype)initWithID:(NSString *)identifier name:(NSString *)name
                    secret:(NSString *)secret steamID:(NSString *)steamID;
@end

@implementation SteamAccount

- (instancetype)initWithID:(NSString *)identifier name:(NSString *)name
                    secret:(NSString *)secret steamID:(NSString *)steamID {
    if ((self = [super init])) {
        _identifier = identifier.copy;
        _name = name.copy;
        _secret = secret.copy;
        _steamID = steamID.copy;
    }
    return self;
}

+ (instancetype)accountWithName:(NSString *)name secret:(NSString *)secret error:(NSError **)error {
    NSString *cleanName = CleanString(name);
    NSString *cleanSecret = CleanString(secret);
    if (!cleanName) {
        if (error) *error = AccountError(@"Введите имя аккаунта.");
        return nil;
    }
    if (!cleanSecret || !SteamGuardSecretIsValid(cleanSecret)) {
        if (error) *error = AccountError(@"shared_secret должен быть корректной строкой Base64.");
        return nil;
    }
    // Canonical Base64 makes duplicate detection independent of its spelling.
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:cleanSecret options:0];
    return [[self alloc] initWithID:NSUUID.UUID.UUIDString name:cleanName
                            secret:[decoded base64EncodedStringWithOptions:0] steamID:nil];
}

+ (instancetype)accountFromMaFile:(NSData *)data fallbackName:(NSString *)name error:(NSError **)error {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) return nil;
    if (![json isKindOfClass:NSDictionary.class] || !CleanString(json[@"shared_secret"])) {
        if (error) *error = AccountError(@"В выбранном файле нет поля shared_secret.");
        return nil;
    }
    SteamAccount *account = [self accountWithName:CleanString(json[@"account_name"]) ?: name
                                         secret:json[@"shared_secret"] error:error];
    if (!account) return nil;

    NSDictionary *session = [json[@"Session"] isKindOfClass:NSDictionary.class] ? json[@"Session"] : nil;
    id rawID = session[@"SteamID"];
    NSString *steamID = CleanString(rawID);
    if ([rawID isKindOfClass:NSNumber.class]) steamID = [rawID stringValue];
    // Import only the account identity and shared secret, never session tokens.
    return [[self alloc] initWithID:account.identifier name:account.name secret:account.secret steamID:steamID];
}

@end

@interface SteamAccounts ()
- (instancetype)initWithAccounts:(NSArray<SteamAccount *> *)accounts selectedID:(NSString *)selectedID;
@end

@implementation SteamAccounts

- (instancetype)initWithAccounts:(NSArray<SteamAccount *> *)accounts selectedID:(NSString *)selectedID {
    if ((self = [super init])) {
        _accounts = accounts.copy;
        for (SteamAccount *account in accounts) {
            if ([account.identifier isEqualToString:selectedID]) _selectedID = selectedID.copy;
        }
        if (!_selectedID) _selectedID = accounts.firstObject.identifier;
    }
    return self;
}

+ (instancetype)empty {
    return [[self alloc] initWithAccounts:@[] selectedID:nil];
}

- (SteamAccount *)selectedAccount {
    for (SteamAccount *account in self.accounts) {
        if ([account.identifier isEqualToString:self.selectedID]) return account;
    }
    return nil;
}

+ (instancetype)fromData:(NSData *)data error:(NSError **)error {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) return nil;
    if (![json isKindOfClass:NSDictionary.class] || ![json[@"version"] isEqual:@1] ||
        ![json[@"accounts"] isKindOfClass:NSArray.class]) {
        if (error) *error = AccountError(@"Не удалось прочитать сохранённые аккаунты.");
        return nil;
    }
    NSMutableArray *accounts = [NSMutableArray array];
    NSMutableSet *identifiers = [NSMutableSet set];
    for (id item in json[@"accounts"]) {
        if (![item isKindOfClass:NSDictionary.class]) {
            if (error) *error = AccountError(@"Повреждены данные сохранённого аккаунта.");
            return nil;
        }
        NSString *identifier = CleanString(item[@"id"]);
        SteamAccount *validated = [SteamAccount accountWithName:item[@"name"] secret:item[@"secret"] error:error];
        if (!validated || !identifier || [identifiers containsObject:identifier]) {
            if (error && !*error) *error = AccountError(@"Повреждены данные сохранённого аккаунта.");
            return nil;
        }
        [identifiers addObject:identifier];
        [accounts addObject:[[SteamAccount alloc] initWithID:identifier name:validated.name
                                                     secret:validated.secret steamID:CleanString(item[@"steamID"])]];
    }
    return [[self alloc] initWithAccounts:accounts selectedID:CleanString(json[@"selectedID"])];
}

- (NSData *)encodedData:(NSError **)error {
    NSMutableArray *items = [NSMutableArray array];
    for (SteamAccount *account in self.accounts) {
        NSMutableDictionary *item = [@{@"id": account.identifier, @"name": account.name,
                                       @"secret": account.secret} mutableCopy];
        if (account.steamID) item[@"steamID"] = account.steamID;
        [items addObject:item];
    }
    NSMutableDictionary *json = [@{@"version": @1, @"accounts": items} mutableCopy];
    if (self.selectedID) json[@"selectedID"] = self.selectedID;
    return [NSJSONSerialization dataWithJSONObject:json options:0 error:error];
}

- (SteamAccounts *)addingAccount:(SteamAccount *)incoming {
    NSMutableArray *accounts = self.accounts.mutableCopy;
    NSUInteger match = NSNotFound;
    for (NSUInteger index = 0; index < accounts.count; index++) {
        SteamAccount *existing = accounts[index];
        BOOL sameID = incoming.steamID && [incoming.steamID isEqualToString:existing.steamID];
        BOOL sameName = [incoming.name caseInsensitiveCompare:existing.name] == NSOrderedSame &&
            !(incoming.steamID && existing.steamID && !sameID);
        if (sameID || [incoming.secret isEqualToString:existing.secret] || sameName) {
            match = index;
            break;
        }
    }
    SteamAccount *added = incoming;
    if (match != NSNotFound) {
        SteamAccount *existing = accounts[match];
        added = [[SteamAccount alloc] initWithID:existing.identifier name:incoming.name
                                          secret:incoming.secret steamID:incoming.steamID ?: existing.steamID];
        accounts[match] = added;
    } else {
        [accounts addObject:added];
    }
    return [[SteamAccounts alloc] initWithAccounts:accounts selectedID:added.identifier];
}

- (SteamAccounts *)selectingAccount:(NSString *)identifier {
    return [[SteamAccounts alloc] initWithAccounts:self.accounts selectedID:identifier];
}

- (SteamAccounts *)removingSelectedAccount {
    NSMutableArray *accounts = self.accounts.mutableCopy;
    NSUInteger index = [accounts indexOfObject:self.selectedAccount];
    if (index == NSNotFound) return self;
    [accounts removeObjectAtIndex:index];
    NSString *nextID = accounts.count ? [accounts[MIN(index, accounts.count - 1)] identifier] : nil;
    return [[SteamAccounts alloc] initWithAccounts:accounts selectedID:nextID];
}

@end
