#import "ConfirmationsWindow.h"
#import "SteamGuard.h"
#import <WebKit/WebKit.h>

static void ShowNotice(NSString *title, NSString *message) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@interface SteamLoginWindow : NSWindowController <WKNavigationDelegate, NSWindowDelegate>
@property(nonatomic, strong) SteamAccount *account;
@property(nonatomic, strong) SteamAccount *result;
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic, strong) NSButton *doneButton;
- (instancetype)initWithAccount:(SteamAccount *)account;
- (SteamAccount *)run;
@end

@implementation SteamLoginWindow

- (instancetype)initWithAccount:(SteamAccount *)account {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 780, 660)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        self.account = account;
        window.title = [@"Вход в Steam — " stringByAppendingString:account.name];
        window.releasedWhenClosed = NO;
        window.delegate = self;
        [window center];
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
        self.web = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 64, 780, 596) configuration:config];
        self.web.navigationDelegate = self;
        [window.contentView addSubview:self.web];
        NSButton *code = [NSButton buttonWithTitle:@"Скопировать код Steam Guard" target:self action:@selector(copyLoginCode)];
        code.frame = NSMakeRect(20, 16, 245, 32);
        [window.contentView addSubview:code];
        self.doneButton = [NSButton buttonWithTitle:@"Я вошёл — продолжить" target:self action:@selector(finishLogin)];
        self.doneButton.frame = NSMakeRect(530, 16, 230, 32);
        [window.contentView addSubview:self.doneButton];
    }
    return self;
}

- (SteamAccount *)run {
    [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://steamcommunity.com/login/home/"]]];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp runModalForWindow:self.window];
    [self.web stopLoading];
    [self.window orderOut:nil];
    return self.result;
}

- (void)copyLoginCode {
    NSString *code = SteamGuardCode(self.account.secret, NSDate.date.timeIntervalSince1970);
    if (!code) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:code forType:NSPasteboardTypeString];
}

- (void)finishLogin {
    self.doneButton.enabled = NO;
    [self.web.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (NSApp.modalWindow != self.window) return;
            self.doneButton.enabled = YES;
            NSString *login = nil, *sessionID = nil;
            for (NSHTTPCookie *cookie in cookies) {
                NSString *domain = [cookie.domain hasPrefix:@"."] ? [cookie.domain substringFromIndex:1] : cookie.domain;
                if (![domain isEqual:@"steamcommunity.com"]) continue;
                if ([cookie.name isEqual:@"steamLoginSecure"]) login = cookie.value;
                if ([cookie.name isEqual:@"sessionid"]) sessionID = cookie.value;
            }
            if (!login) {
                ShowNotice(@"Вход ещё не завершён", @"Войдите в Steam на открытой странице, затем нажмите «Я вошёл — продолжить».");
                return;
            }
            NSError *error = nil;
            self.result = [self.account withWebLogin:login sessionID:sessionID error:&error];
            if (!self.result) { ShowNotice(@"Не удалось сохранить вход", error.localizedDescription); return; }
            [NSApp stopModal];
        });
    }];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
 decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    NSString *host = url.host.lowercaseString;
    BOOL steam = [host isEqual:@"steamcommunity.com"] || [host hasSuffix:@".steamcommunity.com"] ||
        [host isEqual:@"steampowered.com"] || [host hasSuffix:@".steampowered.com"];
    BOOL frame = action.targetFrame && !action.targetFrame.mainFrame;
    if ([url.scheme isEqual:@"https"] && (steam || frame)) {
        if (!action.targetFrame) { [webView loadRequest:action.request]; decisionHandler(WKNavigationActionPolicyCancel); }
        else decisionHandler(WKNavigationActionPolicyAllow);
    } else decisionHandler(WKNavigationActionPolicyCancel);
}

- (void)windowWillClose:(NSNotification *)notification {
    if (NSApp.modalWindow == self.window) [NSApp abortModal];
}
@end

@interface ConfirmationsWindow ()
@property(nonatomic, strong) SteamAccount *account;
@property(nonatomic, strong) SteamConfirmations *client;
@property(nonatomic, copy) BOOL (^saveSession)(SteamAccount *);
@property(nonatomic, copy) NSArray<SteamTradeConfirmation *> *trades;
@property(nonatomic, strong) NSTableView *table;
@property(nonatomic, strong) NSTextView *details;
@property(nonatomic, strong) NSTextField *state;
@property(nonatomic, strong) NSButton *reloadButton;
@property(nonatomic, strong) NSButton *loginButton;
@property(nonatomic, strong) NSButton *confirmButton;
@property(nonatomic, strong) NSButton *openButton;
@property(nonatomic) BOOL busy;
@end

@implementation ConfirmationsWindow

- (instancetype)initWithAccount:(SteamAccount *)account saveSession:(BOOL (^)(SteamAccount *))saveSession {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 520)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        self.account = account;
        self.saveSession = saveSession;
        self.client = [[SteamConfirmations alloc] initWithAccount:account];
        self.trades = @[];
        window.title = [@"Подтверждение сделок — " stringByAppendingString:account.name];
        window.releasedWhenClosed = NO;
        window.delegate = self;
        [window center];
        self.state = [NSTextField labelWithString:@"Нажмите «Обновить», чтобы загрузить ожидающие обмены."];
        self.state.frame = NSMakeRect(20, 474, 580, 26);
        [window.contentView addSubview:self.state];

        NSScrollView *list = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 238, 580, 220)];
        list.hasVerticalScroller = YES;
        self.table = [[NSTableView alloc] initWithFrame:list.bounds];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"trade"];
        column.title = @"Ожидающие подтверждения обменов";
        column.width = 558;
        [self.table addTableColumn:column];
        self.table.rowHeight = 40;
        self.table.dataSource = self;
        self.table.delegate = self;
        self.table.allowsMultipleSelection = NO;
        list.documentView = self.table;
        [window.contentView addSubview:list];

        NSScrollView *detailScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 94, 580, 130)];
        detailScroll.hasVerticalScroller = YES;
        self.details = [[NSTextView alloc] initWithFrame:detailScroll.bounds];
        self.details.editable = NO;
        self.details.font = [NSFont systemFontOfSize:13];
        self.details.textContainerInset = NSMakeSize(8, 8);
        self.details.autoresizingMask = NSViewWidthSizable;
        detailScroll.documentView = self.details;
        [window.contentView addSubview:detailScroll];

        self.loginButton = [NSButton buttonWithTitle:@"Войти в Steam" target:self action:@selector(login)];
        self.loginButton.frame = NSMakeRect(20, 50, 160, 32);
        [window.contentView addSubview:self.loginButton];
        self.reloadButton = [NSButton buttonWithTitle:@"Обновить" target:self action:@selector(reload)];
        self.reloadButton.frame = NSMakeRect(190, 50, 110, 32);
        [window.contentView addSubview:self.reloadButton];
        self.openButton = [NSButton buttonWithTitle:@"Открыть обмен в Steam" target:self action:@selector(openTrade)];
        self.openButton.frame = NSMakeRect(310, 50, 290, 32);
        [window.contentView addSubview:self.openButton];
        self.confirmButton = [NSButton buttonWithTitle:@"Подтвердить выбранный обмен…" target:self action:@selector(confirmSelected)];
        self.confirmButton.frame = NSMakeRect(170, 10, 280, 32);
        [window.contentView addSubview:self.confirmButton];
        [self updateControls];
    }
    return self;
}

- (void)run {
    [self.window makeKeyAndOrderFront:nil];
    [NSApp runModalForWindow:self.window];
    [self.window orderOut:nil];
}

- (SteamTradeConfirmation *)selectedTrade {
    NSInteger row = self.table.selectedRow;
    return row >= 0 && (NSUInteger)row < self.trades.count ? self.trades[row] : nil;
}

- (void)updateControls {
    self.reloadButton.enabled = !self.busy;
    self.loginButton.enabled = !self.busy;
    self.table.enabled = !self.busy;
    self.confirmButton.enabled = !self.busy && self.selectedTrade != nil;
    self.openButton.enabled = !self.busy && self.selectedTrade != nil;
    [self.window standardWindowButton:NSWindowCloseButton].enabled = !self.busy;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.trades.count; }

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    SteamTradeConfirmation *trade = self.trades[row];
    return [NSString stringWithFormat:@"%@ — обмен №%@", trade.headline, trade.offerID];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    SteamTradeConfirmation *trade = self.selectedTrade;
    self.details.string = trade ? [NSString stringWithFormat:@"Аккаунт: %@\n%@\nОбмен №%@\n%@",
        self.account.name, trade.headline, trade.offerID, [trade.summary componentsJoinedByString:@"\n"]] : @"";
    [self updateControls];
}

- (void)reload {
    if (self.busy) return;
    // Clear old rows so a failed refresh cannot leave actionable stale trades.
    self.trades = @[];
    [self.table reloadData];
    self.details.string = @"";
    self.busy = YES;
    self.state.stringValue = @"Загрузка подтверждений…";
    [self updateControls];
    SteamConfirmations *client = self.client;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSArray *trades = [client fetchTrades:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            if (trades) {
                self.trades = trades;
                self.state.stringValue = trades.count ? [NSString stringWithFormat:@"Ожидающих обменов: %lu", (unsigned long)trades.count] : @"Нет обменов, ожидающих мобильного подтверждения.";
            } else self.state.stringValue = @"Не удалось загрузить подтверждения";
            [self.table reloadData];
            [self updateControls];
            if (error) ShowNotice(@"Ошибка Steam", error.localizedDescription);
        });
    });
}

- (void)login {
    if (self.busy) return;
    SteamLoginWindow *login = [[SteamLoginWindow alloc] initWithAccount:self.account];
    SteamAccount *updated = [login run];
    if (!updated || !self.saveSession(updated)) return;
    self.account = updated;
    self.client = [[SteamConfirmations alloc] initWithAccount:updated];
    self.trades = @[];
    [self.table reloadData];
    [self reload];
}

- (void)openTrade {
    SteamTradeConfirmation *trade = self.selectedTrade;
    if (!trade || self.busy) return;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:
        [NSString stringWithFormat:@"https://steamcommunity.com/tradeoffer/%@/", trade.offerID]]];
}

- (void)confirmSelected {
    SteamTradeConfirmation *trade = self.selectedTrade;
    if (!trade || self.busy) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Подтвердить этот обмен?";
    alert.informativeText = [NSString stringWithFormat:@"Аккаунт: %@\n%@\nОбмен №%@\n%@\n\nПроверьте получателя и предметы. Подтверждение будет отправлено в Steam.",
        self.account.name, trade.headline, trade.offerID, [trade.summary componentsJoinedByString:@"\n"]];
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Отмена"];
    [alert addButtonWithTitle:@"Подтвердить обмен"];
    if ([alert runModal] != NSAlertSecondButtonReturn) return;
    self.busy = YES;
    self.state.stringValue = @"Отправка подтверждения…";
    [self updateControls];
    SteamConfirmations *client = self.client;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL success = [client confirmTrade:trade error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            // Always discard the acted-on rows, including ambiguous network failures.
            self.trades = @[];
            self.details.string = @"";
            [self.table reloadData];
            [self updateControls];
            if (success) { ShowNotice(@"Подтверждение отправлено", @"Steam принял подтверждение выбранного обмена."); [self reload]; }
            else { self.state.stringValue = @"Обновите список и проверьте состояние обмена"; ShowNotice(@"Подтверждение не завершено", error.localizedDescription); }
        });
    });
}

- (void)windowWillClose:(NSNotification *)notification {
    if (NSApp.modalWindow == self.window) [NSApp abortModal];
}
@end
