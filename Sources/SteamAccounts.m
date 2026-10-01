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
@property(nonatomic, readwrite, copy) NSString *identitySecret;
@property(nonatomic, readwrite, copy) NSString *deviceID;
@property(nonatomic, readwrite, copy) NSString *webLogin;
@property(nonatomic, readwrite, copy) NSString *sessionID;
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
    SteamAccount *result = [[self alloc] initWithID:account.identifier name:account.name secret:account.secret steamID:steamID];
    NSString *identity = CleanString(json[@"identity_secret"]);
    if (identity && SteamGuardSecretIsValid(identity)) result.identitySecret = identity;
    result.deviceID = CleanString(json[@"device_id"]);
    NSString *login = CleanString(session[@"SteamLoginSecure"]);
    NSString *token = CleanString(session[@"AccessToken"]);
    if (!login && token && steamID) login = [NSString stringWithFormat:@"%@%%7C%%7C%@", steamID, token];
    if (login) {
        SteamAccount *loggedIn = [result withWebLogin:login sessionID:CleanString(session[@"SessionID"]) error:NULL];
        if (loggedIn) result = loggedIn;
    }
    return result;
}

- (SteamAccount *)withWebLogin:(NSString *)login sessionID:(NSString *)sessionID error:(NSError **)error {
    NSString *decoded = login.stringByRemovingPercentEncoding;
    NSArray *parts = [decoded componentsSeparatedByString:@"||"];
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    BOOL numeric = parts.count == 2 && [parts[0] length] > 0 &&
        [parts[0] rangeOfCharacterFromSet:digits.invertedSet].location == NSNotFound;
    NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@";\r\n"];
    if (!numeric || ![parts[1] length] || [login rangeOfCharacterFromSet:unsafe].location != NSNotFound ||
        (sessionID && [sessionID rangeOfCharacterFromSet:unsafe].location != NSNotFound) ||
        (self.steamID && ![self.steamID isEqual:parts[0]])) {
        if (error) *error = AccountError(@"Сессия принадлежит другому аккаунту или некорректна. Войдите в выбранный аккаунт Steam.");
        return nil;
    }
    SteamAccount *result = [[SteamAccount alloc] initWithID:self.identifier name:self.name secret:self.secret steamID:parts[0]];
    result.identitySecret = self.identitySecret;
    result.deviceID = self.deviceID;
    result.webLogin = [NSString stringWithFormat:@"%@%%7C%%7C%@", parts[0], parts[1]];
    result.sessionID = sessionID;
    return result;
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
        SteamAccount *restored = [[SteamAccount alloc] initWithID:identifier name:validated.name
                                                     secret:validated.secret steamID:CleanString(item[@"steamID"])];
        NSString *identity = CleanString(item[@"identitySecret"]);
        if (identity && SteamGuardSecretIsValid(identity)) restored.identitySecret = identity;
        restored.deviceID = CleanString(item[@"deviceID"]);
        NSString *login = CleanString(item[@"webLogin"]);
        if (login) {
            restored = [restored withWebLogin:login sessionID:CleanString(item[@"sessionID"]) error:error];
            if (!restored) return nil;
        }
        [accounts addObject:restored];
    }
    return [[self alloc] initWithAccounts:accounts selectedID:CleanString(json[@"selectedID"])];
}

- (NSData *)encodedData:(NSError **)error {
    NSMutableArray *items = [NSMutableArray array];
    for (SteamAccount *account in self.accounts) {
        NSMutableDictionary *item = [@{@"id": account.identifier, @"name": account.name,
                                       @"secret": account.secret} mutableCopy];
        if (account.steamID) item[@"steamID"] = account.steamID;
        if (account.identitySecret) item[@"identitySecret"] = account.identitySecret;
        if (account.deviceID) item[@"deviceID"] = account.deviceID;
        if (account.webLogin) item[@"webLogin"] = account.webLogin;
        if (account.sessionID) item[@"sessionID"] = account.sessionID;
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
        BOOL sameIdentity = !existing.steamID || !incoming.steamID || [existing.steamID isEqual:incoming.steamID];
        added.identitySecret = incoming.identitySecret ?: (sameIdentity ? existing.identitySecret : nil);
        added.deviceID = incoming.deviceID ?: (sameIdentity ? existing.deviceID : nil);
        // Keep a working browser login on reimport; maFile sessions may be old.
        added.webLogin = sameIdentity && existing.webLogin ? existing.webLogin : incoming.webLogin;
        added.sessionID = sameIdentity && existing.webLogin ? existing.sessionID : incoming.sessionID;
        accounts[match] = added;
    } else {
        [accounts addObject:added];
    }
    return [[SteamAccounts alloc] initWithAccounts:accounts selectedID:added.identifier];
}

- (SteamAccounts *)selectingAccount:(NSString *)identifier {
    return [[SteamAccounts alloc] initWithAccounts:self.accounts selectedID:identifier];
}

- (SteamAccounts *)replacingAccount:(SteamAccount *)account {
    NSMutableArray *items = self.accounts.mutableCopy;
    for (NSUInteger index = 0; index < items.count; index++) {
        if ([[items[index] identifier] isEqual:account.identifier]) {
            items[index] = account;
            return [[SteamAccounts alloc] initWithAccounts:items selectedID:self.selectedID];
        }
    }
    return self;
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
