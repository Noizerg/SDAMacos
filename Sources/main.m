#import <Cocoa/Cocoa.h>
#import "SteamGuard.h"
#import "AccountsKeychain.h"
#import "MaFileImport.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *codeLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSButton *codeCopyButton;
@property(nonatomic, strong) NSButton *removeButton;
@property(nonatomic, strong) NSButton *importButton;
@property(nonatomic, strong) NSButton *folderImportButton;
@property(nonatomic, strong) NSButton *enterButton;
@property(nonatomic, strong) NSPopUpButton *accountPicker;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) SteamAccounts *accounts;
@property(nonatomic) BOOL accountsLoaded;
@property(nonatomic) BOOL importing;
@property(nonatomic, copy) NSString *currentCode;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self createMainMenu];
    [self createWindow];
    [self refresh];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(refresh)
                                                userInfo:nil
                                                 repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self loadAccounts];
}

- (void)loadAccounts {
    self.importButton.enabled = NO;
    self.folderImportButton.enabled = NO;
    self.enterButton.enabled = NO;
    self.statusLabel.stringValue = @"Загрузка аккаунтов…";
    // Keychain may ask for permission; show the window before starting a read.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        SteamAccounts *accounts = LoadSteamAccounts(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!accounts) {
                self.statusLabel.stringValue = @"Не удалось загрузить аккаунты";
                self.importButton.title = @"Повторить загрузку";
                self.importButton.action = @selector(loadAccounts);
                self.importButton.enabled = YES;
                [self showError:error];
                return;
            }
            self.accounts = accounts;
            self.accountsLoaded = YES;
            self.importButton.title = @"Импортировать .maFile…";
            self.importButton.action = @selector(importMaFile);
            self.importButton.enabled = YES;
            self.folderImportButton.enabled = YES;
            self.enterButton.enabled = YES;
            [self updateAccountPicker];
            [self refresh];
        });
    });
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.timer invalidate];
}

- (void)refresh {
    if (!self.accountsLoaded) return;
    SteamAccount *selected = self.accounts.selectedAccount;
    if (!selected) {
        self.currentCode = nil;
        self.codeLabel.stringValue = @"-----";
        self.statusLabel.stringValue = self.importing ? @"Импорт аккаунтов из папки…" :
            @"Импортируйте .maFile или введите shared_secret";
        self.codeCopyButton.enabled = NO;
        self.removeButton.hidden = YES;
        return;
    }

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSString *newCode = SteamGuardCode(selected.secret, now);
    if (!newCode) {
        self.currentCode = nil;
        self.codeLabel.stringValue = @"Ошибка";
        self.statusLabel.stringValue = @"Не удалось сгенерировать код";
        self.codeCopyButton.enabled = NO;
        return;
    }

    self.currentCode = newCode;
    self.codeLabel.stringValue = newCode;
    self.statusLabel.stringValue = self.importing ? @"Импорт аккаунтов из папки…" :
        [NSString stringWithFormat:@"Новый код через %ld сек.", (long)SteamGuardSecondsRemaining(now)];
    self.codeCopyButton.enabled = YES;
    self.removeButton.hidden = NO;
}

- (void)createMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *applicationItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:applicationItem];

    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"Steam Guard Lite"];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Выйти из Steam Guard Lite"
                                                   action:@selector(terminate:)
                                            keyEquivalent:@"q"];
    quit.target = NSApp;
    [applicationMenu addItem:quit];
    applicationItem.submenu = applicationMenu;
    NSApp.mainMenu = mainMenu;
}

- (void)createWindow {
    NSRect frame = NSMakeRect(0, 0, 400, 390);
    self.window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"Steam Guard Lite";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    NSView *content = self.window.contentView;

    NSTextField *heading = [NSTextField labelWithString:@"Steam Guard"];
    heading.frame = NSMakeRect(20, 342, 360, 28);
    heading.alignment = NSTextAlignmentCenter;
    heading.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    [content addSubview:heading];

    self.accountPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(30, 295, 340, 32) pullsDown:NO];
    self.accountPicker.target = self;
    self.accountPicker.action = @selector(selectAccount);
    self.accountPicker.enabled = NO;
    self.accountPicker.accessibilityLabel = @"Аккаунт Steam";
    [self.accountPicker addItemWithTitle:@"Нет аккаунтов"];
    [content addSubview:self.accountPicker];

    self.codeLabel = [NSTextField labelWithString:@"-----"];
    self.codeLabel.frame = NSMakeRect(20, 224, 360, 56);
    self.codeLabel.alignment = NSTextAlignmentCenter;
    self.codeLabel.font = [NSFont monospacedSystemFontOfSize:42 weight:NSFontWeightSemibold];
    self.codeLabel.selectable = YES;
    [content addSubview:self.codeLabel];

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.frame = NSMakeRect(20, 195, 360, 22);
    self.statusLabel.alignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [content addSubview:self.statusLabel];

    self.codeCopyButton = [NSButton buttonWithTitle:@"Скопировать код"
                                              target:self action:@selector(copyCode)];
    self.codeCopyButton.frame = NSMakeRect(125, 148, 150, 34);
    self.codeCopyButton.keyEquivalent = @"\r";
    [content addSubview:self.codeCopyButton];

    self.importButton = [NSButton buttonWithTitle:@"Импортировать .maFile…"
                                                 target:self action:@selector(importMaFile)];
    self.importButton.frame = NSMakeRect(20, 102, 175, 32);
    [content addSubview:self.importButton];

    self.enterButton = [NSButton buttonWithTitle:@"Ввести shared_secret…"
                                                target:self action:@selector(enterSecret)];
    self.enterButton.frame = NSMakeRect(205, 102, 175, 32);
    [content addSubview:self.enterButton];

    self.folderImportButton = [NSButton buttonWithTitle:@"Импорт из папки…"
                                                  target:self action:@selector(importFolder)];
    self.folderImportButton.frame = NSMakeRect(100, 62, 200, 32);
    self.folderImportButton.enabled = NO;
    [content addSubview:self.folderImportButton];

    self.removeButton = [NSButton buttonWithTitle:@"Удалить выбранный аккаунт"
                                             target:self action:@selector(removeSecret)];
    self.removeButton.frame = NSMakeRect(90, 20, 220, 30);
    self.removeButton.bezelStyle = NSBezelStyleInline;
    self.removeButton.contentTintColor = NSColor.secondaryLabelColor;
    self.removeButton.hidden = YES;
    self.codeCopyButton.enabled = NO;
    [content addSubview:self.removeButton];
}

- (void)updateAccountPicker {
    [self.accountPicker removeAllItems];
    for (SteamAccount *account in self.accounts.accounts) {
        // Use individual menu items: NSPopUpButton's title helper merges equal titles.
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:account.name action:nil keyEquivalent:@""];
        item.representedObject = account.identifier;
        [self.accountPicker.menu addItem:item];
        if ([account.identifier isEqualToString:self.accounts.selectedID]) {
            [self.accountPicker selectItem:item];
        }
    }
    self.accountPicker.enabled = self.accounts.accounts.count > 0 && !self.importing;
    if (!self.accounts.accounts.count) [self.accountPicker addItemWithTitle:@"Нет аккаунтов"];
}

- (BOOL)commitAccounts:(SteamAccounts *)accounts {
    NSError *error = nil;
    if (!SaveSteamAccounts(accounts, &error)) {
        [self showError:error];
        [self updateAccountPicker];
        return NO;
    }
    self.accounts = accounts;
    [self updateAccountPicker];
    [self refresh];
    return YES;
}

- (void)selectAccount {
    if (!self.accountsLoaded || self.importing) return;
    NSString *identifier = self.accountPicker.selectedItem.representedObject;
    if (!identifier || [identifier isEqualToString:self.accounts.selectedID]) return;
    [self commitAccounts:[self.accounts selectingAccount:identifier]];
}

- (void)copyCode {
    // Recompute at click time so a boundary cannot copy the previous interval.
    [self refresh];
    if (!self.currentCode) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:self.currentCode forType:NSPasteboardTypeString];
    self.statusLabel.stringValue = @"✓ Код скопирован";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self refresh]; });
}

- (void)importMaFile {
    if (!self.accountsLoaded || self.importing) return;
    [NSApp activateIgnoringOtherApps:YES];
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.title = @"Выберите Steam .maFile";
    panel.prompt = @"Импортировать";
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;

    NSError *error = nil;
    SteamAccount *account = SteamAccountFromFile(panel.URL, &error);
    if (!account) { [self showError:error]; return; }
    [self commitAccounts:[self.accounts addingAccount:account]];
}

- (void)importFolder {
    if (!self.accountsLoaded || self.importing) return;
    [NSApp activateIgnoringOtherApps:YES];
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.title = @"Выберите папку с .maFile";
    panel.prompt = @"Импортировать";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    [self importFolderAtURL:panel.URL];
}

- (void)setImportControlsEnabled:(BOOL)enabled {
    self.importButton.enabled = enabled;
    self.folderImportButton.enabled = enabled;
    self.enterButton.enabled = enabled;
    self.removeButton.enabled = enabled;
    self.accountPicker.enabled = enabled && self.accounts.accounts.count > 0;
}

- (void)importFolderAtURL:(NSURL *)folder {
    if (!self.accountsLoaded || self.importing) return;
    self.importing = YES;
    [self setImportControlsEnabled:NO];
    self.statusLabel.stringValue = @"Импорт аккаунтов из папки…";
    SteamAccounts *original = self.accounts;
    // Parse in the background, then save the complete batch in one Keychain update.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        MaFileImportResult *result = [MaFileImportResult fromFolder:folder accounts:original error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL saved = NO;
            if (result && result.addedCount + result.updatedCount > 0) {
                saved = [self commitAccounts:result.accounts];
            }
            self.importing = NO;
            [self setImportControlsEnabled:YES];
            [self refresh];
            if (!result) [self showError:error];
            else if (saved || result.addedCount + result.updatedCount == 0) [self showFolderImportResult:result];
        });
    });
}

- (void)showFolderImportResult:(MaFileImportResult *)result {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Импорт из папки завершён";
    NSMutableString *text = [NSMutableString stringWithFormat:
        @"Добавлено аккаунтов: %lu\nОбработано повторных импортов: %lu\nПропущено файлов: %lu",
        (unsigned long)result.addedCount, (unsigned long)result.updatedCount,
        (unsigned long)result.skippedFiles.count];
    if (result.addedCount + result.updatedCount + result.skippedFiles.count == 0) {
        [text appendString:@"\n\nВ выбранной папке нет файлов .maFile. Вложенные папки не обрабатываются."];
    } else if (result.skippedFiles.count) {
        [text appendString:@"\n\nНе удалось прочитать или импортировать:\n"];
        [text appendString:[[result.skippedFiles subarrayWithRange:
            NSMakeRange(0, MIN((NSUInteger)8, result.skippedFiles.count))] componentsJoinedByString:@"\n"]];
        if (result.skippedFiles.count > 8) [text appendFormat:@"\n…и ещё %lu",
                                          (unsigned long)(result.skippedFiles.count - 8)];
    }
    alert.informativeText = text;
    [alert addButtonWithTitle:@"OK"];
    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
}

- (void)enterSecret {
    if (!self.accountsLoaded || self.importing) return;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Добавить аккаунт";
    alert.informativeText = @"Секрет хранится только в Связке ключей этого Mac.";
    [alert addButtonWithTitle:@"Сохранить"];
    [alert addButtonWithTitle:@"Отмена"];
    NSView *fields = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 64)];
    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 40, 340, 24)];
    nameField.placeholderString = @"Имя аккаунта Steam";
    [fields addSubview:nameField];
    NSSecureTextField *field = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 340, 24)];
    field.placeholderString = @"Base64 shared_secret";
    [fields addSubview:field];
    alert.accessoryView = fields;
    alert.window.initialFirstResponder = nameField;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSError *error = nil;
    SteamAccount *account = [SteamAccount accountWithName:nameField.stringValue
                                                  secret:field.stringValue error:&error];
    if (!account) { [self showError:error]; return; }
    [self commitAccounts:[self.accounts addingAccount:account]];
}

- (void)removeSecret {
    if (self.importing) return;
    SteamAccount *selected = self.accounts.selectedAccount;
    if (!selected) return;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Удалить аккаунт «%@»?", selected.name];
    alert.informativeText = @"Его секрет будет удалён из приложения. Остальные аккаунты останутся.";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Удалить"];
    [alert addButtonWithTitle:@"Отмена"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    [self commitAccounts:self.accounts.removingSelectedAccount];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows {
    if (!hasVisibleWindows) [self.window makeKeyAndOrderFront:nil];
    return YES;
}

- (void)showError:(NSError *)error {
    [NSApp activateIgnoringOtherApps:YES];
    [[NSAlert alertWithError:error] runModal];
}

@end

// NSApplication does not retain its delegate, so keep it alive for the process.
static AppDelegate *ApplicationDelegate;

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        ApplicationDelegate = [[AppDelegate alloc] init];
        application.delegate = ApplicationDelegate;
        [application run];
    }
    return 0;
}
