#import "MaFileImport.h"

SteamAccount *SteamAccountFromFile(NSURL *url, NSError **error) {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    return data ? [SteamAccount accountFromMaFile:data
        fallbackName:url.URLByDeletingPathExtension.lastPathComponent error:error] : nil;
}

@implementation MaFileImportResult

+ (instancetype)fromFolder:(NSURL *)folder accounts:(SteamAccounts *)accounts error:(NSError **)error {
    NSArray<NSURL *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder
        includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:error];
    if (!contents) return nil;
    contents = [contents sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
    }];

    MaFileImportResult *result = [[self alloc] init];
    SteamAccounts *candidate = accounts;
    NSMutableArray<NSString *> *skippedFiles = [NSMutableArray array];
    for (NSURL *url in contents) {
        if ([url.pathExtension caseInsensitiveCompare:@"maFile"] != NSOrderedSame) continue;
        @autoreleasepool {
            NSNumber *isDirectory = nil;
            [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
            if (isDirectory.boolValue) continue;
            SteamAccount *account = SteamAccountFromFile(url, NULL);
            if (!account) {
                [skippedFiles addObject:url.lastPathComponent];
                continue;
            }
            SteamAccounts *next = [candidate addingAccount:account];
            if (next.accounts.count > candidate.accounts.count) result->_addedCount++;
            else result->_updatedCount++;
            candidate = next;
        }
    }
    result->_accounts = candidate;
    result->_skippedFiles = skippedFiles.copy;
    return result;
}

@end
