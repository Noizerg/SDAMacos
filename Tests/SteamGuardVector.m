#import <Foundation/Foundation.h>
#import "SteamGuard.h"
#import "SteamAccounts.h"
#import "AccountsKeychain.h"
#import <Security/Security.h>
#import "MaFileImport.h"
#import "FolderImportFixtures.h"
#import "SteamConfirmations.h"

static NSData *TradeFixture(void) {
    return [NSJSONSerialization dataWithJSONObject:
        @{@"success": @YES, @"conf": @[
            @{@"type": @2, @"id": @"18446744073709551614", @"nonce": @"18446744073709551613",
              @"creator_id": @"9999", @"headline": @"Trade with Test", @"summary": @[@"Send: 1 item", @"Receive: 2 items"]},
            @{@"type": @3, @"id": @"20", @"nonce": @"30", @"creator_id": @"40"},
            @{@"type": @6, @"id": @"50", @"nonce": @"60", @"creator_id": @"70"} ]}
        options:0 error:NULL];
}

@interface MockConfirmations : SteamConfirmations
@property(nonatomic, strong) NSMutableArray<NSURLRequest *> *requests;
@property(nonatomic) BOOL expired;
@property(nonatomic) BOOL refuseConfirmation;
@end

@implementation MockConfirmations
- (instancetype)initWithAccount:(SteamAccount *)account {
    if ((self = [super initWithAccount:account])) self.requests = [NSMutableArray array];
    return self;
}
- (NSData *)performRequest:(NSURLRequest *)request error:(NSError **)error {
    (void)error;
    [self.requests addObject:request];
    if ([request.URL.host isEqual:@"api.steampowered.com"]) {
        return [@"{\"response\":{\"server_time\":1700000000}}" dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (self.expired) return [@"{\"success\":false,\"needauth\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    if ([request.URL.path hasSuffix:@"ajaxop"]) {
        return [(self.refuseConfirmation ? @"{\"success\":false}" : @"{\"success\":true}")
                dataUsingEncoding:NSUTF8StringEncoding];
    }
    return TradeFixture();
}
@end

static NSDictionary *RequestQuery(NSURLRequest *request) {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO].queryItems) {
        query[item.name] = item.value;
    }
    return query;
}

// test.sh renames these APIs at compile time. No real Keychain is accessed.
static NSMutableDictionary<NSString *, NSData *> *TestKeychain;
static OSStatus ReadFailure;
static OSStatus WriteFailure;

OSStatus SecItemCopyMatching(CFDictionaryRef queryRef, CFTypeRef *result) {
    if (ReadFailure) return ReadFailure;
    NSDictionary *query = (__bridge NSDictionary *)queryRef;
    NSData *data = TestKeychain[query[(__bridge id)kSecAttrAccount]];
    if (!data) return errSecItemNotFound;
    if (result) *result = CFBridgingRetain(data);
    return errSecSuccess;
}

OSStatus SecItemUpdate(CFDictionaryRef queryRef, CFDictionaryRef attributesRef) {
    if (WriteFailure) return WriteFailure;
    NSDictionary *query = (__bridge NSDictionary *)queryRef;
    NSDictionary *attributes = (__bridge NSDictionary *)attributesRef;
    NSString *key = query[(__bridge id)kSecAttrAccount];
    if (!TestKeychain[key]) return errSecItemNotFound;
    TestKeychain[key] = attributes[(__bridge id)kSecValueData];
    return errSecSuccess;
}

OSStatus SecItemAdd(CFDictionaryRef attributesRef, CFTypeRef *result) {
    (void)result;
    if (WriteFailure) return WriteFailure;
    NSDictionary *attributes = (__bridge NSDictionary *)attributesRef;
    NSString *key = attributes[(__bridge id)kSecAttrAccount];
    if (TestKeychain[key]) return errSecDuplicateItem;
    TestKeychain[key] = attributes[(__bridge id)kSecValueData];
    return errSecSuccess;
}

OSStatus SecItemDelete(CFDictionaryRef queryRef) {
    NSDictionary *query = (__bridge NSDictionary *)queryRef;
    NSString *key = query[(__bridge id)kSecAttrAccount];
    if (!TestKeychain[key]) return errSecItemNotFound;
    [TestKeychain removeObjectForKey:key];
    return errSecSuccess;
}

static void Check(BOOL passed, NSString *message) {
    if (!passed) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static SteamAccount *Import(NSString *name, NSString *secret, NSString *steamID) {
    NSDictionary *json = @{@"account_name": name, @"shared_secret": secret,
                          @"identity_secret": @"MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=",
                          @"device_id": @"android:test-device",
                          @"revocation_code": @"DO_NOT_SAVE",
                          @"Session": @{@"SteamID": steamID, @"AccessToken": @"TEST_ACCESS_TOKEN",
                                        @"RefreshToken": @"DO_NOT_SAVE"}};
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:NULL];
    return [SteamAccount accountFromMaFile:data fallbackName:@"filename" error:NULL];
}

int main(void) {
    @autoreleasepool {
        NSString *code = SteamGuardCode(@"MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=", 59);
        if (![code isEqualToString:@"PV9M4"]) {
            NSLog(@"Expected PV9M4, got %@", code);
            return 1;
        }
        Check(SteamGuardSecondsRemaining(59) == 1 && SteamGuardSecondsRemaining(60) == 30,
              @"30-second boundary");

        NSString *secretA = @"MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=";
        NSString *secretB = @"YW5vdGhlciB0ZXN0IHNlY3JldA==";
        SteamAccount *alice = Import(@"alice", secretA, @"111");
        SteamAccount *bob = Import(@"bob", secretB, @"222");
        Check([alice.name isEqual:@"alice"], @"name comes from maFile");
        SteamAccounts *accounts = [[SteamAccounts.empty addingAccount:alice] addingAccount:bob];
        Check(accounts.accounts.count == 2 && [accounts.selectedAccount.name isEqual:@"bob"],
              @"adding a second account selects it and preserves the first");
        SteamAccounts *selected = [accounts selectingAccount:alice.identifier];
        Check([SteamGuardCode(selected.selectedAccount.secret, 59) isEqual:@"PV9M4"],
              @"switching uses the selected account's secret");
        Check(![SteamGuardCode(accounts.selectedAccount.secret, 59) isEqual:@"PV9M4"],
              @"the second account has its own code");
        NSData *encoded = [selected encodedData:NULL];
        Check(![[[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]
                containsString:@"DO_NOT_SAVE"], @"unused revocation and refresh secrets are excluded");
        SteamAccounts *restored = [SteamAccounts fromData:encoded error:NULL];
        Check(restored.accounts.count == 2 && [restored.selectedID isEqual:alice.identifier],
              @"accounts and selection survive serialization");
        Check([restored.selectedAccount.identitySecret isEqual:alice.identitySecret] &&
              [restored.selectedAccount.deviceID isEqual:alice.deviceID] &&
              [restored.selectedAccount.webLogin isEqual:alice.webLogin],
              @"confirmation credentials survive Keychain serialization");
        NSError *loginError = nil;
        Check(![alice withWebLogin:@"222%7C%7COTHER_ACCOUNT" sessionID:nil error:&loginError] && loginError,
              @"web login for another account is rejected");
        Check(![alice withWebLogin:@"111%7C%7Ctoken;\r\nInjected=value" sessionID:nil error:NULL],
              @"cookie header injection is rejected");
        SteamAccount *webAccount = [alice withWebLogin:@"111||FRESH_BROWSER_TOKEN" sessionID:@"test-session" error:NULL];
        SteamAccounts *webAccounts = [accounts replacingAccount:webAccount];
        Check(webAccounts.accounts.count == 2 && [webAccounts.selectedID isEqual:accounts.selectedID] &&
              [webAccounts.accounts[0].webLogin isEqual:@"111%7C%7CFRESH_BROWSER_TOKEN"],
              @"saving a web session keeps other accounts and current selection");
        Check([[[webAccounts addingAccount:alice].selectedAccount webLogin] isEqual:webAccount.webLogin],
              @"reimport preserves the newer browser session");
        SteamAccounts *updated = [accounts addingAccount:Import(@"Alice", secretB, @"111")];
        Check(updated.accounts.count == 2 && [updated.selectedID isEqual:alice.identifier],
              @"reimport updates by SteamID without a duplicate");
        SteamAccounts *removed = selected.removingSelectedAccount;
        Check(removed.accounts.count == 1 && [removed.selectedAccount.name isEqual:@"bob"],
              @"removal affects only the selected account");
        Check(removed.removingSelectedAccount.accounts.count == 0 &&
              !removed.removingSelectedAccount.selectedAccount, @"removing the last account");
        Check(accounts.accounts.count == 2, @"candidate edits do not mutate previous state");

        NSData *nameless = [NSJSONSerialization dataWithJSONObject:@{@"shared_secret": secretA}
                                                        options:0 error:NULL];
        Check([[SteamAccount accountFromMaFile:nameless fallbackName:@"file-name" error:NULL].name
               isEqual:@"file-name"], @"missing account name uses filename");
        Check(![SteamAccount accountFromMaFile:[@"[]" dataUsingEncoding:NSUTF8StringEncoding]
                                 fallbackName:@"file" error:NULL], @"invalid maFile is rejected");
        Check(![SteamAccount accountWithName:@"bad" secret:@"not base64!" error:NULL],
              @"invalid secret is rejected");
        Check(![SteamAccounts fromData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding] error:NULL],
              @"invalid stored data is rejected");

        NSURL *folder = FolderImportFixture();
        SteamAccounts *original = [SteamAccounts.empty addingAccount:alice];
        MaFileImportResult *batch = [MaFileImportResult fromFolder:folder accounts:original error:NULL];
        Check(batch && batch.addedCount == 1 && batch.updatedCount == 2 && batch.skippedFiles.count == 2,
              @"batch counts new accounts, repeated imports and invalid files");
        Check(batch.accounts.accounts.count == 2 && [batch.accounts.selectedAccount.name isEqual:@"bob"],
              @"batch adds uppercase-extension files and selects the last successful import");
        Check([batch.accounts.accounts[0].identifier isEqual:alice.identifier] &&
              [batch.accounts.accounts[0].secret isEqual:@"dGhpcmQgdGVzdCBzZWNyZXQ="],
              @"batch reimport updates the existing account without duplicating it");
        Check(original.accounts.count == 1 && [original.selectedAccount.secret isEqual:secretA],
              @"batch candidates leave the existing collection untouched");
        Check([batch.skippedFiles isEqual:@[@"04-broken.maFile", @"05-missing-secret.maFile"]],
              @"skipped files are reported by filename");
        MaFileImportResult *again = [MaFileImportResult fromFolder:folder accounts:batch.accounts error:NULL];
        Check(again.addedCount == 0 && again.updatedCount == 3 && again.accounts.accounts.count == 2,
              @"reimporting the folder does not add duplicates");
        RemoveTestFolder(folder);

        NSURL *empty = NewTestFolder();
        MaFileImportResult *emptyBatch = [MaFileImportResult fromFolder:empty accounts:original error:NULL];
        Check(emptyBatch && emptyBatch.addedCount == 0 && emptyBatch.updatedCount == 0 &&
              emptyBatch.skippedFiles.count == 0 && emptyBatch.accounts == original,
              @"empty folders preserve the account list");
        RemoveTestFolder(empty);
        NSError *folderError = nil;
        Check(![MaFileImportResult fromFolder:empty accounts:original error:&folderError] && folderError,
              @"missing or inaccessible folder is a reported error");

        Check([SteamConfirmationKey(secretA, 1700000000, @"conf") isEqual:@"uOi1VQCWymi7kGGUQW8vh0odoS0="] &&
              [SteamConfirmationKey(secretA, 1700000000, @"accept") isEqual:@"iCH9YIuBQ95e4zGIeuEiXxQLDiU="],
              @"confirmation HMAC matches independently generated vectors");
        NSArray *trades = [SteamConfirmations parseTrades:TradeFixture() error:NULL];
        Check(trades.count == 1 && [((SteamTradeConfirmation *)trades[0]).identifier isEqual:@"18446744073709551614"],
              @"trade-only parsing keeps full unsigned IDs and excludes market/account recovery confirmations");
        NSError *confirmationError = nil;
        Check(![SteamConfirmations parseTrades:[@"<html>login</html>" dataUsingEncoding:NSUTF8StringEncoding]
                                        error:&confirmationError] && confirmationError,
              @"login HTML is not treated as an empty successful list");
        Check(![SteamConfirmations parseTrades:[@"{\"success\":true,\"conf\":[{\"type\":2}]}"
                                                dataUsingEncoding:NSUTF8StringEncoding] error:NULL],
              @"trades without IDs are not actionable");
        MockConfirmations *client = [[MockConfirmations alloc] initWithAccount:webAccount];
        Check([client fetchTrades:NULL].count == 1 && client.requests.count == 2,
              @"fetch synchronizes server time then retrieves the trade list");
        NSURLRequest *listRequest = client.requests.lastObject;
        NSDictionary *listQuery = RequestQuery(listRequest);
        Check([listRequest.URL.host isEqual:@"steamcommunity.com"] && [listQuery[@"a"] isEqual:@"111"] &&
              [listQuery[@"k"] isEqual:SteamConfirmationKey(secretA, 1700000000, @"conf")] &&
              [listQuery[@"tag"] isEqual:@"conf"] && [listQuery[@"m"] isEqual:@"react"],
              @"signed list request is bound to the chosen account and server time");
        Check(![client.requests[0] valueForHTTPHeaderField:@"Cookie"] &&
              [[listRequest valueForHTTPHeaderField:@"Cookie"] containsString:@"111%7C%7CFRESH_BROWSER_TOKEN"],
              @"account cookies go only to Steam Community, not the time endpoint");
        Check([client confirmTrade:trades[0] error:NULL], @"explicit confirmation parses success");
        NSDictionary *allowQuery = RequestQuery(client.requests.lastObject);
        Check([allowQuery[@"op"] isEqual:@"allow"] && [allowQuery[@"tag"] isEqual:@"accept"] &&
              [allowQuery[@"cid"] isEqual:@"18446744073709551614"] &&
              [allowQuery[@"ck"] isEqual:@"18446744073709551613"] &&
              [allowQuery[@"k"] isEqual:SteamConfirmationKey(secretA, 1700000000, @"accept")],
              @"only the selected confirmation ID and nonce are sent with an accept signature");
        Check([client confirmTrade:trades[0] error:NULL] &&
              [RequestQuery(client.requests.lastObject)[@"t"] isEqual:@"1700000001"],
              @"successive confirmations use distinct action timestamps");
        client.expired = YES;
        confirmationError = nil;
        Check(![client fetchTrades:&confirmationError] && confirmationError.code == 3,
              @"expired sessions ask for a new Steam login");
        client.expired = NO;
        client.refuseConfirmation = YES;
        Check(![client confirmTrade:trades[0] error:NULL], @"server refusal is not reported as success");
        MockConfirmations *missingCredentials = [[MockConfirmations alloc] initWithAccount:
            [SteamAccount accountWithName:@"manual" secret:secretA error:NULL]];
        Check(![missingCredentials fetchTrades:NULL] && missingCredentials.requests.count == 0,
              @"shared-secret-only accounts never issue confirmation requests");

        TestKeychain = [NSMutableDictionary dictionary];
        Check(LoadSteamAccounts(NULL).accounts.count == 0, @"fresh install");
        TestKeychain[@"shared-secret"] = [secretA dataUsingEncoding:NSUTF8StringEncoding];
        SteamAccounts *migrated = LoadSteamAccounts(NULL);
        Check(migrated.accounts.count == 1 && [migrated.selectedAccount.secret isEqual:secretA],
              @"legacy secret migrates intact");
        Check(TestKeychain[@"accounts-v1"] && !TestKeychain[@"shared-secret"],
              @"legacy entry is removed only after new storage succeeds");
        SteamAccounts *renamed = [migrated addingAccount:alice];
        Check(renamed.accounts.count == 1 && [renamed.selectedAccount.name isEqual:@"alice"],
              @"reimport names the migrated account without duplicating it");
        Check(SaveSteamAccounts(selected, NULL), @"multi-account save");
        Check([LoadSteamAccounts(NULL).selectedID isEqual:alice.identifier], @"selection survives reload");
        Check(SaveSteamAccounts(SteamAccounts.empty, NULL) && LoadSteamAccounts(NULL).accounts.count == 0,
              @"an empty saved collection stays empty");

        [TestKeychain removeAllObjects];
        TestKeychain[@"shared-secret"] = [secretA dataUsingEncoding:NSUTF8StringEncoding];
        WriteFailure = errSecAuthFailed;
        NSError *error = nil;
        Check(!LoadSteamAccounts(&error) && error && TestKeychain[@"shared-secret"] &&
              !TestKeychain[@"accounts-v1"], @"failed migration preserves legacy data");
        WriteFailure = 0;
        ReadFailure = errSecInteractionNotAllowed;
        error = nil;
        Check(!LoadSteamAccounts(&error) && error && !TestKeychain[@"accounts-v1"],
              @"denied Keychain access is not treated as an empty account list");
        NSLog(@"Steam Guard, accounts, folder import and confirmation tests: OK (no real network/trades)");
    }
    return 0;
}
