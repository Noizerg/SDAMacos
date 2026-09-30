#import "SteamGuard.h"
#import <CommonCrypto/CommonHMAC.h>

static NSString * const SteamAlphabet = @"23456789BCDFGHJKMNPQRTVWXY";

static NSString *NormalizeSecret(NSString *secret) {
    return [secret stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

BOOL SteamGuardSecretIsValid(NSString *secret) {
    NSString *normalized = NormalizeSecret(secret);
    NSData *data = [[NSData alloc] initWithBase64EncodedString:normalized options:0];
    return data.length > 0;
}

NSString *SteamGuardCode(NSString *secret, NSTimeInterval timestamp) {
    NSString *normalized = NormalizeSecret(secret);
    NSData *key = [[NSData alloc] initWithBase64EncodedString:normalized options:0];
    if (key.length == 0) return nil;

    uint64_t counter = (uint64_t)floor(timestamp / 30.0);
    uint8_t message[8];
    for (NSInteger index = 7; index >= 0; index--) {
        message[index] = (uint8_t)(counter & 0xff);
        counter >>= 8;
    }

    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, key.bytes, key.length, message, sizeof(message), digest);
    NSInteger offset = digest[CC_SHA1_DIGEST_LENGTH - 1] & 0x0f;
    uint32_t value = ((uint32_t)digest[offset] << 24)
        | ((uint32_t)digest[offset + 1] << 16)
        | ((uint32_t)digest[offset + 2] << 8)
        | (uint32_t)digest[offset + 3];
    value &= 0x7fffffff;

    NSMutableString *result = [NSMutableString stringWithCapacity:5];
    for (NSInteger index = 0; index < 5; index++) {
        unichar character = [SteamAlphabet characterAtIndex:value % SteamAlphabet.length];
        [result appendFormat:@"%C", character];
        value /= (uint32_t)SteamAlphabet.length;
    }
    return result;
}

NSInteger SteamGuardSecondsRemaining(NSTimeInterval timestamp) {
    NSInteger elapsed = ((NSInteger)floor(timestamp)) % 30;
    return 30 - elapsed;
}
