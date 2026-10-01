#import "SteamConfirmations.h"
#import <CommonCrypto/CommonHMAC.h>

static NSError *ConfirmationError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"SteamGuardLite.Confirmations" code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSString *SteamConfirmationKey(NSString *identitySecret, uint64_t time, NSString *tag) {
    NSData *key = [[NSData alloc] initWithBase64EncodedString:identitySecret options:0];
    if (!key.length) return nil;
    uint8_t bytes[8];
    for (NSInteger index = 7; index >= 0; index--) { bytes[index] = time & 255; time >>= 8; }
    NSMutableData *message = [NSMutableData dataWithBytes:bytes length:8];
    NSData *tagBytes = [tag dataUsingEncoding:NSUTF8StringEncoding];
    [message appendData:[tagBytes subdataWithRange:NSMakeRange(0, MIN((NSUInteger)32, tagBytes.length))]];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, key.bytes, key.length, message.bytes, message.length, digest);
    return [[NSData dataWithBytes:digest length:sizeof(digest)] base64EncodedStringWithOptions:0];
}

static NSString *NumericID(id value) {
    NSString *text = [value isKindOfClass:NSNumber.class] ? [value stringValue] : value;
    if (![text isKindOfClass:NSString.class] || !text.length ||
        [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location != NSNotFound) return nil;
    return text;
}

static NSString *Query(NSDictionary<NSString *, NSString *> *values) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *name in [values.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@", name,
                          [values[name] stringByAddingPercentEncodingWithAllowedCharacters:allowed]]];
    }
    return [parts componentsJoinedByString:@"&"];
}

static NSDictionary *ResponseJSON(NSData *data, NSError **error) {
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![json isKindOfClass:NSDictionary.class]) {
        if (error) *error = ConfirmationError(2, @"Steam вернул неожиданный ответ. Попробуйте войти в Steam заново.");
        return nil;
    }
    return json;
}

static BOOL Successful(NSDictionary *json, NSError **error) {
    if ([json[@"needauth"] respondsToSelector:@selector(boolValue)] && [json[@"needauth"] boolValue]) {
        if (error) *error = ConfirmationError(3, @"Сессия Steam истекла. Нажмите «Войти в Steam».");
        return NO;
    }
    if (![json[@"success"] respondsToSelector:@selector(boolValue)] || ![json[@"success"] boolValue]) {
        if (error) *error = ConfirmationError(4, @"Steam отклонил запрос. Обновите список; при повторной ошибке войдите в Steam заново и проверьте .maFile.");
        return NO;
    }
    return YES;
}

@interface SteamTradeConfirmation ()
@property(nonatomic, readwrite, copy) NSString *identifier;
@property(nonatomic, readwrite, copy) NSString *nonce;
@property(nonatomic, readwrite, copy) NSString *offerID;
@property(nonatomic, readwrite, copy) NSString *headline;
@property(nonatomic, readwrite, copy) NSArray<NSString *> *summary;
@end
@implementation SteamTradeConfirmation
@end

@interface SteamConfirmations ()
@property(nonatomic) uint64_t lastActionTime;
@end

@implementation SteamConfirmations

- (instancetype)initWithAccount:(SteamAccount *)account {
    if ((self = [super init])) _account = account;
    return self;
}

- (BOOL)validate:(NSError **)error {
    if (!self.account.identitySecret || !self.account.deviceID) {
        if (error) *error = ConfirmationError(1, @"Импортируйте .maFile этого аккаунта повторно: нужны identity_secret и device_id для подтверждений.");
        return NO;
    }
    if (!self.account.webLogin || !self.account.steamID) {
        if (error) *error = ConfirmationError(3, @"Нажмите «Войти в Steam» для выбранного аккаунта.");
        return NO;
    }
    return YES;
}

- (NSData *)performRequest:(NSURLRequest *)request error:(NSError **)error {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil;
    config.URLCache = nil;
    config.HTTPShouldSetCookies = NO;
    config.timeoutIntervalForRequest = 25;
    config.timeoutIntervalForResource = 30;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData *received = nil;
    __block BOOL failed = NO;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:
        ^(NSData *data, NSURLResponse *response, NSError *networkError) {
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            failed = networkError || status != 200;
            received = data;
            dispatch_semaphore_signal(done);
        }];
    [task resume];
    BOOL timeout = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 35 * NSEC_PER_SEC)) != 0;
    if (timeout) [task cancel];
    [session finishTasksAndInvalidate];
    if (timeout || failed || !received) {
        // Don't expose a signed URL, cookies or response fragments in error messages.
        if (error) *error = ConfirmationError(5, @"Не удалось связаться со Steam. Проверьте интернет и повторите обновление списка. Если ошибка возникла при подтверждении, сначала проверьте состояние сделки в Steam.");
        return nil;
    }
    return received;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    // Never forward an authenticated confirmation request to a login/other host.
    completionHandler(nil);
}

- (uint64_t)serverTime:(NSError **)error {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://api.steampowered.com/ITwoFactorService/QueryTime/v1/"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [@"steamid=0" dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    NSData *data = [self performRequest:request error:error];
    if (!data) return 0;
    NSDictionary *json = ResponseJSON(data, error);
    NSDictionary *response = [json[@"response"] isKindOfClass:NSDictionary.class] ? json[@"response"] : nil;
    NSString *value = NumericID(response[@"server_time"]);
    uint64_t time = value.longLongValue;
    if (!time && error) *error = ConfirmationError(2, @"Не удалось получить время Steam. Повторите запрос.");
    return time;
}

- (NSURLRequest *)requestForEndpoint:(NSString *)endpoint tag:(NSString *)tag
                              extra:(NSDictionary *)extra error:(NSError **)error {
    if (![self validate:error]) return nil;
    uint64_t time = [self serverTime:error];
    if (!time) return nil;
    if ([tag isEqual:@"accept"]) {
        time = MAX(time, self.lastActionTime + 1);
        self.lastActionTime = time;
    }
    NSMutableDictionary *params = [@{@"p": self.account.deviceID, @"a": self.account.steamID,
        @"k": SteamConfirmationKey(self.account.identitySecret, time, tag),
        @"t": [NSString stringWithFormat:@"%llu", (unsigned long long)time],
        @"m": @"react", @"tag": tag} mutableCopy];
    [params addEntriesFromDictionary:extra];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:
        @"https://steamcommunity.com/mobileconf/%@?%@", endpoint, Query(params)]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    NSString *cookie = [NSString stringWithFormat:@"steamLoginSecure=%@; mobileClient=android; mobileClientVersion=777777%%203.6.4",
                        self.account.webLogin];
    if (self.account.sessionID) cookie = [cookie stringByAppendingFormat:@"; sessionid=%@", self.account.sessionID];
    [request setValue:cookie forHTTPHeaderField:@"Cookie"];
    [request setValue:@"okhttp/4.9.2" forHTTPHeaderField:@"User-Agent"];
    return request;
}

+ (NSArray<SteamTradeConfirmation *> *)parseTrades:(NSData *)data error:(NSError **)error {
    NSDictionary *json = ResponseJSON(data, error);
    if (!json || !Successful(json, error)) return nil;
    id rows = json[@"conf"] ?: @[];
    if (![rows isKindOfClass:NSArray.class]) {
        if (error) *error = ConfirmationError(2, @"Некорректный список подтверждений Steam.");
        return nil;
    }
    NSMutableArray *trades = [NSMutableArray array];
    for (id row in rows) {
        if (![row isKindOfClass:NSDictionary.class]) {
            if (error) *error = ConfirmationError(2, @"Некорректные данные сделки Steam.");
            return nil;
        }
        if (![row[@"type"] respondsToSelector:@selector(integerValue)] || [row[@"type"] integerValue] != 2) continue;
        NSString *identifier = NumericID(row[@"id"]), *nonce = NumericID(row[@"nonce"]);
        NSString *offer = NumericID(row[@"creator_id"]);
        if (!identifier || !nonce || !offer) {
            if (error) *error = ConfirmationError(2, @"В подтверждении отсутствуют идентификаторы сделки. Обновите список.");
            return nil;
        }
        SteamTradeConfirmation *trade = [[SteamTradeConfirmation alloc] init];
        trade.identifier = identifier;
        trade.nonce = nonce;
        trade.offerID = offer;
        trade.headline = [row[@"headline"] isKindOfClass:NSString.class] ? row[@"headline"] : @"Обмен Steam";
        NSMutableArray *summary = [NSMutableArray array];
        if ([row[@"summary"] isKindOfClass:NSArray.class]) {
            for (id line in row[@"summary"]) if ([line isKindOfClass:NSString.class]) [summary addObject:line];
        }
        trade.summary = summary;
        [trades addObject:trade];
    }
    return trades;
}

- (NSArray<SteamTradeConfirmation *> *)fetchTrades:(NSError **)error {
    NSURLRequest *request = [self requestForEndpoint:@"getlist" tag:@"conf" extra:@{} error:error];
    NSData *data = request ? [self performRequest:request error:error] : nil;
    return data ? [SteamConfirmations parseTrades:data error:error] : nil;
}

- (BOOL)confirmTrade:(SteamTradeConfirmation *)trade error:(NSError **)error {
    NSURLRequest *request = [self requestForEndpoint:@"ajaxop" tag:@"accept"
        extra:@{@"op": @"allow", @"cid": trade.identifier, @"ck": trade.nonce} error:error];
    NSData *data = request ? [self performRequest:request error:error] : nil;
    NSDictionary *json = data ? ResponseJSON(data, error) : nil;
    return json && Successful(json, error);
}

@end
