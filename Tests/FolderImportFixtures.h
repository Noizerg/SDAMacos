#import <Foundation/Foundation.h>

static NSURL *NewTestFolder(void) {
    NSURL *folder = [NSFileManager.defaultManager.temporaryDirectory
        URLByAppendingPathComponent:[@"steam-guard-folder-test-" stringByAppendingString:NSUUID.UUID.UUIDString]
        isDirectory:YES];
    BOOL created = [NSFileManager.defaultManager createDirectoryAtURL:folder
        withIntermediateDirectories:NO attributes:nil error:NULL];
    NSCAssert(created, @"Could not create isolated fixture directory");
    return folder;
}

static void WriteTestFile(NSURL *folder, NSString *name, NSData *data) {
    BOOL written = [data writeToURL:[folder URLByAppendingPathComponent:name] atomically:YES];
    NSCAssert(written, @"Could not write synthetic fixture");
}

static NSData *TestMaFile(NSString *name, NSString *secret, NSString *steamID) {
    return [NSJSONSerialization dataWithJSONObject:
        @{@"account_name": name, @"shared_secret": secret, @"Session": @{@"SteamID": steamID}}
        options:0 error:NULL];
}

static NSURL *FolderImportFixture(void) {
    NSURL *folder = NewTestFolder();
    WriteTestFile(folder, @"01-alice.maFile", TestMaFile(@"alice", @"dGhpcmQgdGVzdCBzZWNyZXQ=", @"111"));
    NSData *bob = TestMaFile(@"bob", @"YW5vdGhlciB0ZXN0IHNlY3JldA==", @"222");
    WriteTestFile(folder, @"02-bob.MAFILE", bob);
    WriteTestFile(folder, @"03-bob.maFile", bob);
    WriteTestFile(folder, @"04-broken.maFile", [@"not JSON" dataUsingEncoding:NSUTF8StringEncoding]);
    WriteTestFile(folder, @"05-missing-secret.maFile", [@"{}" dataUsingEncoding:NSUTF8StringEncoding]);
    WriteTestFile(folder, @"ignore.json", bob);
    NSURL *nested = [folder URLByAppendingPathComponent:@"nested.maFile" isDirectory:YES];
    BOOL created = [NSFileManager.defaultManager createDirectoryAtURL:nested
        withIntermediateDirectories:NO attributes:nil error:NULL];
    NSCAssert(created, @"Could not create nested fixture directory");
    WriteTestFile(nested, @"inner.maFile", TestMaFile(@"nested", @"bmVzdGVkIHRlc3Qgc2VjcmV0", @"333"));
    return folder;
}

static void RemoveTestFolder(NSURL *folder) {
    BOOL removed = [NSFileManager.defaultManager removeItemAtURL:folder error:NULL];
    NSCAssert(removed, @"Could not remove isolated fixture directory");
}
