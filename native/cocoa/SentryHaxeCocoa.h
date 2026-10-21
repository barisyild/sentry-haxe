#pragma once
#include <hxcpp.h>
#import <Foundation/Foundation.h>
#import <MetricKit/MetricKit.h>
// Module import avoids colliding with hxcpp's generated include/sentry/Sentry.h
// on case-insensitive macOS filesystems.
@import Sentry;
#if __has_include(<Sentry/Sentry-Swift.h>)
#import <Sentry/Sentry-Swift.h>
#endif

namespace sentry_haxe {

// hxcpp uses manual reference counting. Also permit this header in ARC host projects.
template<typename T> inline T owned(T value) {
#if __has_feature(objc_arc)
    return value;
#else
    return [value autorelease];
#endif
}

inline NSDictionary *json(::String text) {
    NSData *bytes = [[NSString stringWithUTF8String:text.utf8_str()] dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
}
inline id field(NSDictionary *data, NSString *key) {
    id value = data[key];
    return value == [NSNull null] ? nil : value;
}
inline SentryLevel level(NSString *value) {
    if ([value isEqualToString:@"fatal"]) return kSentryLevelFatal;
    if ([value isEqualToString:@"error"]) return kSentryLevelError;
    if ([value isEqualToString:@"warning"]) return kSentryLevelWarning;
    if ([value isEqualToString:@"debug"]) return kSentryLevelDebug;
    return kSentryLevelInfo;
}
inline SentryUser *user(NSDictionary *data) {
    if (!data) return nil;
    SentryUser *result = owned([[SentryUser alloc] init]);
    result.userId = field(data, @"id");
    result.username = field(data, @"username");
    result.email = field(data, @"email");
    result.ipAddress = field(data, @"ip_address");
    result.data = field(data, @"data");
    return result;
}
inline NSArray<SentryBreadcrumb *> *breadcrumbs(NSArray *items) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *item in items) {
        SentryBreadcrumb *b = owned([[SentryBreadcrumb alloc] initWithLevel:level(field(item, @"level")) category:field(item, @"category") ?: @"default"]);
        b.message = field(item, @"message");
        b.type = field(item, @"type");
        b.data = field(item, @"data");
        if (field(item, @"timestamp")) b.timestamp = [NSDate dateWithTimeIntervalSince1970:[item[@"timestamp"] doubleValue]];
        [result addObject:b];
    }
    return result;
}
inline SentryStacktrace *stacktrace(NSDictionary *data) {
    if (!data) return nil;
    NSMutableArray *frames = [NSMutableArray array];
    for (NSDictionary *item in data[@"frames"]) {
        SentryFrame *f = owned([[SentryFrame alloc] init]);
        f.fileName = field(item, @"filename");
        f.function = field(item, @"function");
        f.module = field(item, @"module");
        f.lineNumber = field(item, @"lineno");
        f.columnNumber = field(item, @"colno");
        f.inApp = field(item, @"in_app");
        [frames addObject:f];
    }
    return owned([[SentryStacktrace alloc] initWithFrames:frames registers:@{}]);
}
inline SentryEvent *event(NSDictionary *data) {
    SentryEvent *result = owned([[SentryEvent alloc] initWithLevel:level(field(data, @"level"))]);
    if (field(data, @"event_id")) result.eventId = owned([[SentryId alloc] initWithUUIDString:data[@"event_id"]]);
    if (field(data, @"timestamp")) result.timestamp = [NSDate dateWithTimeIntervalSince1970:[data[@"timestamp"] doubleValue]];
    result.platform = field(data, @"platform") ?: @"other";
    result.releaseName = field(data, @"release");
    result.environment = field(data, @"environment");
    result.dist = field(data, @"dist");
    result.logger = field(data, @"logger");
    result.transaction = field(data, @"transaction");
    result.tags = field(data, @"tags");
    result.extra = field(data, @"extra");
    result.context = field(data, @"contexts");
    result.fingerprint = field(data, @"fingerprint");
    result.user = user(field(data, @"user"));
    result.breadcrumbs = breadcrumbs(field(data, @"breadcrumbs"));
    id message = field(data, @"message");
    if (message) result.message = owned([[SentryMessage alloc] initWithFormatted:[message isKindOfClass:[NSString class]] ? message : field(message, @"formatted") ?: @""]);
    NSMutableArray *exceptions = [NSMutableArray array];
    for (NSDictionary *item in field(data, @"exception")[@"values"]) {
        SentryException *e = owned([[SentryException alloc] initWithValue:field(item, @"value") ?: @"" type:field(item, @"type") ?: @"Error"]);
        e.stacktrace = stacktrace(field(item, @"stacktrace"));
        NSDictionary *mechanism = field(item, @"mechanism");
        if (mechanism) {
            e.mechanism = owned([[SentryMechanism alloc] initWithType:field(mechanism, @"type") ?: @"generic"]);
            e.mechanism.handled = field(mechanism, @"handled");
        }
        [exceptions addObject:e];
    }
    if (exceptions.count) result.exceptions = exceptions;
    return result;
}
inline NSUInteger &breadcrumb_limit() {
    static NSUInteger limit = 100;
    return limit;
}
inline void initialize(::String options) {
    @autoreleasepool {
        NSDictionary *data = json(options);
        [SentrySDK startWithConfigureOptions:^(SentryOptions *o) {
            o.dsn = field(data, @"dsn");
            if (field(data, @"release")) o.releaseName = data[@"release"];
            if (field(data, @"environment")) o.environment = data[@"environment"];
            if (field(data, @"dist")) o.dist = data[@"dist"];
            o.debug = [data[@"debug"] boolValue];
            o.maxBreadcrumbs = [data[@"maxBreadcrumbs"] unsignedIntegerValue];
            breadcrumb_limit() = o.maxBreadcrumbs;
            o.shutdownTimeInterval = [data[@"shutdownTimeoutMs"] doubleValue] / 1000.0;
            o.sampleRate = @1.0;
            NSDictionary *native = field(data, @"nativeOptions");
            if (field(native, @"tracesSampleRate")) o.tracesSampleRate = native[@"tracesSampleRate"];
            if (field(native, @"enableAppHangTracking")) o.enableAppHangTracking = [native[@"enableAppHangTracking"] boolValue];
            if (field(native, @"appHangTimeoutInterval")) o.appHangTimeoutInterval = [native[@"appHangTimeoutInterval"] doubleValue];
            if (field(native, @"enableCaptureFailedRequests")) o.enableCaptureFailedRequests = [native[@"enableCaptureFailedRequests"] boolValue];
#if SENTRY_UIKIT_AVAILABLE
            // Cocoa 8 requires this opt-in; newer SDKs use V2 without exposing the old setter.
            if (field(native, @"enableAppHangTrackingV2") && [o respondsToSelector:NSSelectorFromString(@"setEnableAppHangTrackingV2:")])
                [o setValue:native[@"enableAppHangTrackingV2"] forKey:@"enableAppHangTrackingV2"];
            if (field(native, @"enableReportNonFullyBlockingAppHangs"))
                o.enableReportNonFullyBlockingAppHangs = [native[@"enableReportNonFullyBlockingAppHangs"] boolValue];
            if (field(native, @"attachScreenshot")) o.attachScreenshot = [native[@"attachScreenshot"] boolValue];
            if (field(native, @"enableUserInteractionTracing")) o.enableUserInteractionTracing = [native[@"enableUserInteractionTracing"] boolValue];
#endif
#if SENTRY_TARGET_REPLAY_SUPPORTED
            NSDictionary *replay = field(native, @"sessionReplay");
            if (field(replay, @"sessionSampleRate")) o.sessionReplay.sessionSampleRate = [replay[@"sessionSampleRate"] doubleValue];
            if (field(replay, @"onErrorSampleRate")) o.sessionReplay.onErrorSampleRate = [replay[@"onErrorSampleRate"] doubleValue];
            if (field(replay, @"maskAllText")) o.sessionReplay.maskAllText = [replay[@"maskAllText"] boolValue];
            if (field(replay, @"maskAllImages")) o.sessionReplay.maskAllImages = [replay[@"maskAllImages"] boolValue];
#endif
        }];
#if SENTRY_TARGET_PROFILING_SUPPORTED
        if ([field(data, @"nativeOptions")[@"startProfiler"] boolValue]) [SentrySDK startProfiler];
#endif
    }
}
inline NSArray<SentryBreadcrumb *> *serialized_breadcrumbs(NSArray *items) {
    NSMutableArray *result = [NSMutableArray array];
    NSISO8601DateFormatter *iso = owned([[NSISO8601DateFormatter alloc] init]);
    iso.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        SentryBreadcrumb *b = owned([[SentryBreadcrumb alloc] initWithLevel:level(field(item, @"level")) category:field(item, @"category") ?: @"default"]);
        b.message = field(item, @"message");
        b.type = field(item, @"type");
        b.data = field(item, @"data");
        id timestamp = field(item, @"timestamp");
        NSDate *date = [timestamp isKindOfClass:[NSString class]] ? [iso dateFromString:timestamp] : nil;
        if (date) b.timestamp = date;
        [result addObject:b];
    }
    return result;
}
inline ::String capture(::String eventJson, ::String attachmentsJson) {
    @autoreleasepool {
        SentryEvent *e = event(json(eventJson));
        NSArray<SentryBreadcrumb *> *local = e.breadcrumbs;
        e.breadcrumbs = nil;
        NSDictionary *attachments = json(attachmentsJson);
        SentryId *identifier = [SentrySDK captureEvent:e withScopeBlock:^(SentryScope *scope) {
            if (local.count) {
                NSMutableArray<SentryBreadcrumb *> *merged = [NSMutableArray arrayWithArray:serialized_breadcrumbs([scope serialize][@"breadcrumbs"])];
                [merged addObjectsFromArray:local];
                NSUInteger limit = breadcrumb_limit();
                e.breadcrumbs = merged.count > limit ? [merged subarrayWithRange:NSMakeRange(merged.count - limit, limit)] : merged;
            }
            for (NSDictionary *a in attachments[@"items"]) {
                NSData *bytes = owned([[NSData alloc] initWithBase64EncodedString:a[@"data"] options:0]);
                [scope addAttachment:owned([[SentryAttachment alloc] initWithData:bytes filename:a[@"filename"] contentType:a[@"content_type"]])];
            }
        }];
        return ::String(identifier.sentryIdString.UTF8String);
    }
}
inline NSString *text(::String value) {
    const char *utf8 = value.utf8_str();
    return utf8 ? [NSString stringWithUTF8String:utf8] : nil;
}
inline id value(::String jsonValue) {
    NSString *wrapped = [NSString stringWithFormat:@"[%@]", text(jsonValue) ?: @"null"];
    NSArray *items = [NSJSONSerialization JSONObjectWithData:[wrapped dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    id result = items.count ? items[0] : nil;
    return result == [NSNull null] ? nil : result;
}
inline NSMutableSet<NSString *> *managed(NSString *group) {
    static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *keys = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"tags": [NSMutableSet set], @"extra": [NSMutableSet set], @"contexts": [NSMutableSet set]}];
    return keys[group];
}
inline void add_breadcrumb(::String breadcrumbJson) {
    @autoreleasepool {
        NSDictionary *item = json(breadcrumbJson);
        if (![item isKindOfClass:[NSDictionary class]]) return;
        for (SentryBreadcrumb *b in breadcrumbs(@[item])) [SentrySDK addBreadcrumb:b];
    }
}
inline void clear_breadcrumbs() {
    @autoreleasepool { [SentrySDK configureScope:^(SentryScope *scope) { [scope clearBreadcrumbs]; }]; }
}
inline void set_tag(::String key, ::String tagValue) {
    @autoreleasepool {
        NSString *k = text(key), *v = text(tagValue);
        if (!k || !v) return;
        [managed(@"tags") addObject:k];
        [SentrySDK configureScope:^(SentryScope *scope) { [scope setTagValue:v forKey:k]; }];
    }
}
inline void remove_tag(::String key) {
    @autoreleasepool {
        NSString *k = text(key);
        if (!k) return;
        [managed(@"tags") removeObject:k];
        [SentrySDK configureScope:^(SentryScope *scope) { [scope removeTagForKey:k]; }];
    }
}
inline void set_extra(::String key, ::String extraJson) {
    @autoreleasepool {
        NSString *k = text(key);
        if (!k) return;
        id v = value(extraJson);
        [managed(@"extra") addObject:k];
        [SentrySDK configureScope:^(SentryScope *scope) { [scope setExtraValue:v forKey:k]; }];
    }
}
inline void remove_extra(::String key) {
    @autoreleasepool {
        NSString *k = text(key);
        if (!k) return;
        [managed(@"extra") removeObject:k];
        [SentrySDK configureScope:^(SentryScope *scope) { [scope removeExtraForKey:k]; }];
    }
}
inline void remove_context(::String key) {
    @autoreleasepool {
        NSString *k = text(key);
        if (!k) return;
        [managed(@"contexts") removeObject:k];
        [SentrySDK configureScope:^(SentryScope *scope) { [scope removeContextForKey:k]; }];
    }
}
inline void set_context(::String key, ::String contextJson) {
    @autoreleasepool {
        NSString *k = text(key);
        if (!k) return;
        id v = value(contextJson);
        if (!v) { remove_context(key); return; }
        NSDictionary *context = [v isKindOfClass:[NSDictionary class]] ? v : @{@"value": v};
        [managed(@"contexts") addObject:k];
        [SentrySDK configureScope:^(SentryScope *scope) { [scope setContextValue:context forKey:k]; }];
    }
}
inline void set_user(::String userJson) {
    @autoreleasepool {
        id data = value(userJson);
        SentryUser *u = user([data isKindOfClass:[NSDictionary class]] ? data : nil);
        [SentrySDK configureScope:^(SentryScope *scope) { [scope setUser:u]; }];
    }
}
inline void set_level(::String levelJson) {
    @autoreleasepool {
        id v = value(levelJson);
        SentryLevel l = [v isKindOfClass:[NSString class]] ? level(v) : kSentryLevelNone;
        [SentrySDK configureScope:^(SentryScope *scope) { [scope setLevel:l]; }];
    }
}
inline void set_environment(::String environmentJson) {
    @autoreleasepool {
        id v = value(environmentJson);
        NSString *environment = [v isKindOfClass:[NSString class]] ? v : nil;
        [SentrySDK configureScope:^(SentryScope *scope) { [scope setEnvironment:environment]; }];
    }
}
inline void set_fingerprint(::String fingerprintJson) {
    @autoreleasepool {
        id v = value(fingerprintJson);
        NSArray<NSString *> *fingerprint = [v isKindOfClass:[NSArray class]] ? v : nil;
        [SentrySDK configureScope:^(SentryScope *scope) { [scope setFingerprint:fingerprint]; }];
    }
}
inline void clear_scope() {
    @autoreleasepool {
        [SentrySDK configureScope:^(SentryScope *scope) {
            for (NSString *k in managed(@"tags")) [scope removeTagForKey:k];
            for (NSString *k in managed(@"extra")) [scope removeExtraForKey:k];
            for (NSString *k in managed(@"contexts")) [scope removeContextForKey:k];
            [scope setUser:nil];
            [scope setEnvironment:nil];
            [scope setFingerprint:nil];
            [scope setLevel:kSentryLevelNone];
            [scope clearBreadcrumbs];
        }];
        [managed(@"tags") removeAllObjects];
        [managed(@"extra") removeAllObjects];
        [managed(@"contexts") removeAllObjects];
    }
}
inline bool flush(int timeoutMs) { [SentrySDK flush:timeoutMs / 1000.0]; return true; }
inline bool close(int timeoutMs) { [SentrySDK flush:timeoutMs / 1000.0]; [SentrySDK close]; return true; }
}
