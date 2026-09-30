// Exercise the real window/controller using synthetic accounts and an in-memory store.
#define main SteamGuardApplicationMain
#import "../Sources/main.m"
#undef main
#import "FolderImportFixtures.h"

static SteamAccounts *SavedAccounts;
static BOOL FailSave;
static NSUInteger SaveCalls;

SteamAccounts *LoadSteamAccounts(NSError **error) {
    (void)error;
    return SavedAccounts ? SavedAccounts : SteamAccounts.empty;
}

BOOL SaveSteamAccounts(SteamAccounts *accounts, NSError **error) {
    SaveCalls++;
    if (FailSave) {
        if (error) *error = [NSError errorWithDomain:@"Test" code:1 userInfo:nil];
        return NO;
    }
    SavedAccounts = accounts;
    return YES;
}

@interface TestDelegate : AppDelegate
@property(nonatomic) NSInteger errorsShown;
@property(nonatomic, strong) MaFileImportResult *folderResult;
@end

@implementation TestDelegate
- (void)showError:(NSError *)error {
    (void)error;
    self.errorsShown++;
}
- (void)showFolderImportResult:(MaFileImportResult *)result {
    self.folderResult = result;
}
@end

static void Check(BOOL passed, NSString *message) {
    if (!passed) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static void WaitForImport(TestDelegate *delegate) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (delegate.importing && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    Check(!delegate.importing, @"background import completes");
}

static SteamAccount *Fixture(NSString *name, NSString *secret, NSString *steamID) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:
        @{@"account_name": name, @"shared_secret": secret, @"Session": @{@"SteamID": steamID}}
        options:0 error:NULL];
    return [SteamAccount accountFromMaFile:json fallbackName:@"test" error:NULL];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        TestDelegate *delegate = [[TestDelegate alloc] init];
        [delegate createWindow];
        delegate.accountsLoaded = YES;
        delegate.accounts = SteamAccounts.empty;
        [delegate updateAccountPicker];
        [delegate refresh];
        Check(!delegate.codeCopyButton.enabled && !delegate.accountPicker.enabled &&
              delegate.removeButton.hidden, @"empty-state controls");

        SteamAccount *alice = Fixture(@"test-alice", @"MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=", @"111");
        SteamAccount *bob = Fixture(@"test-bob", @"YW5vdGhlciB0ZXN0IHNlY3JldA==", @"222");
        [delegate commitAccounts:[[SteamAccounts.empty addingAccount:alice] addingAccount:bob]];
        Check(delegate.accountPicker.numberOfItems == 2 && delegate.accountPicker.enabled &&
              [delegate.accountPicker.titleOfSelectedItem isEqual:@"test-bob"],
              @"picker lists both accounts and selects the imported one");
        Check(delegate.codeCopyButton.enabled && delegate.currentCode.length == 5 &&
              !delegate.removeButton.hidden, @"code is displayed and controls enabled");
        [delegate.accountPicker selectItemAtIndex:0];
        [delegate selectAccount];
        Check([delegate.accounts.selectedID isEqual:alice.identifier] &&
              [delegate.codeLabel.stringValue isEqual:SteamGuardCode(alice.secret, NSDate.date.timeIntervalSince1970)] &&
              [SavedAccounts.selectedID isEqual:alice.identifier],
              @"picker change updates code and saves selection");

        FailSave = YES;
        [delegate.accountPicker selectItemAtIndex:1];
        [delegate selectAccount];
        Check(delegate.errorsShown == 1 && [delegate.accounts.selectedID isEqual:alice.identifier] &&
              delegate.accountPicker.indexOfSelectedItem == 0,
              @"failed save restores the selected account in the picker");
        FailSave = NO;

        SteamAccount *sameName = Fixture(@"test-alice", @"dGhpcmQgdGVzdCBzZWNyZXQ=", @"333");
        [delegate commitAccounts:[delegate.accounts addingAccount:sameName]];
        Check(delegate.accountPicker.numberOfItems == 3 &&
              [delegate.accountPicker.selectedItem.representedObject isEqual:sameName.identifier],
              @"same display names do not collapse different SteamIDs in the menu");

        Check(delegate.folderImportButton.action == @selector(importFolder), @"folder button is wired to importer");
        delegate.accounts = [SteamAccounts.empty addingAccount:alice];
        [delegate updateAccountPicker];
        [delegate refresh];
        NSURL *folder = FolderImportFixture();
        SaveCalls = 0;
        [delegate importFolderAtURL:folder];
        Check(delegate.importing && !delegate.folderImportButton.enabled &&
              !delegate.accountPicker.enabled && !delegate.removeButton.enabled,
              @"bulk import prevents concurrent account edits");
        WaitForImport(delegate);
        Check(SaveCalls == 1 && delegate.accounts.accounts.count == 2 && delegate.folderResult &&
              delegate.folderResult.addedCount == 1 && delegate.folderResult.updatedCount == 2,
              @"folder import persists the whole batch once and shows its report");
        Check(delegate.folderImportButton.enabled && delegate.accountPicker.enabled &&
              [delegate.accountPicker.titleOfSelectedItem isEqual:@"bob"],
              @"picker refreshes and controls unlock after batch import");

        delegate.folderResult = nil;
        SteamAccounts *beforeFailure = delegate.accounts;
        FailSave = YES;
        SaveCalls = 0;
        [delegate importFolderAtURL:folder];
        WaitForImport(delegate);
        Check(SaveCalls == 1 && delegate.accounts == beforeFailure && !delegate.folderResult &&
              delegate.errorsShown == 2 && delegate.folderImportButton.enabled,
              @"failed batch save preserves all accounts and shows no success report");
        FailSave = NO;
        RemoveTestFolder(folder);

        NSURL *emptyFolder = NewTestFolder();
        SaveCalls = 0;
        [delegate importFolderAtURL:emptyFolder];
        WaitForImport(delegate);
        Check(SaveCalls == 0 && delegate.folderResult && delegate.accounts == beforeFailure,
              @"empty folder reports its result without a Keychain write");
        RemoveTestFolder(emptyFolder);

        delegate.folderResult = nil;
        [delegate importFolderAtURL:emptyFolder];
        WaitForImport(delegate);
        Check(SaveCalls == 0 && delegate.errorsShown == 3 && !delegate.folderResult &&
              delegate.folderImportButton.enabled && delegate.accounts == beforeFailure,
              @"folder read errors unlock controls and preserve the account list");

        [delegate.window layoutIfNeeded];
        for (NSView *view in delegate.window.contentView.subviews) {
            Check(NSContainsRect(delegate.window.contentView.bounds, view.frame), @"controls fit inside the window");
        }
        [delegate.window orderOut:nil];
        NSLog(@"Multi-account window and bulk import tests: OK (synthetic data only)");
    }
    return 0;
}
