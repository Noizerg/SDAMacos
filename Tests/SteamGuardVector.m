#import <Foundation/Foundation.h>
#import "SteamGuard.h"
#import "SteamAccounts.h"
#import "AccountsKeychain.h"
#import <Security/Security.h>
#import "MaFileImport.h"
#import "FolderImportFixtures.h"

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
                          @"identity_secret": @"DO_NOT_SAVE",
                          @"Session": @{@"SteamID": steamID, @"AccessToken": @"DO_NOT_SAVE"}};
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
                containsString:@"DO_NOT_SAVE"], @"session and identity secrets are excluded");
        SteamAccounts *restored = [SteamAccounts fromData:encoded error:NULL];
        Check(restored.accounts.count == 2 && [restored.selectedID isEqual:alice.identifier],
              @"accounts and selection survive serialization");
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
        NSLog(@"Steam Guard, multi-account storage, migration and folder import tests: OK");
    }
    return 0;
}
