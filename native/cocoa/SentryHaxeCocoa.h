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
inline void initialize(::String options) {
    @autoreleasepool {
        NSDictionary *data = json(options);
        [SentrySDK startWithConfigureOptions:^(SentryOptions *o) {
            o.dsn = field(data, @"dsn");
            o.releaseName = field(data, @"release");
            o.environment = field(data, @"environment");
            o.dist = field(data, @"dist");
            o.debug = [data[@"debug"] boolValue];
            o.maxBreadcrumbs = [data[@"maxBreadcrumbs"] unsignedIntegerValue];
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
inline ::String capture(::String eventJson, ::String attachmentsJson) {
    @autoreleasepool {
        SentryEvent *e = event(json(eventJson));
        NSDictionary *attachments = json(attachmentsJson);
        SentryId *identifier = [SentrySDK captureEvent:e withScopeBlock:^(SentryScope *scope) {
            [scope clear];
            for (NSDictionary *a in attachments[@"items"]) {
                NSData *bytes = owned([[NSData alloc] initWithBase64EncodedString:a[@"data"] options:0]);
                [scope addAttachment:owned([[SentryAttachment alloc] initWithData:bytes filename:a[@"filename"] contentType:a[@"content_type"]])];
            }
        }];
        return ::String(identifier.sentryIdString.UTF8String);
    }
}
inline void sync_scope(::String jsonScope) {
    @autoreleasepool {
        NSDictionary *data = json(jsonScope);
        // Only remove keys managed by this adapter; preserve SDK tracing/session metadata.
        static NSDictionary *previous = @{};
        [SentrySDK configureScope:^(SentryScope *scope) {
            [scope setUser:user(field(data, @"user"))];
            for (NSString *key in field(previous, @"tags")) [scope removeTagForKey:key];
            for (NSString *key in field(previous, @"extra")) [scope removeExtraForKey:key];
            for (NSString *key in field(previous, @"contexts")) [scope removeContextForKey:key];
            for (NSString *key in field(data, @"tags")) [scope setTagValue:data[@"tags"][key] forKey:key];
            for (NSString *key in field(data, @"extra")) [scope setExtraValue:data[@"extra"][key] forKey:key];
            for (NSString *key in field(data, @"contexts")) [scope setContextValue:data[@"contexts"][key] forKey:key];
            [scope setEnvironment:field(data, @"environment")];
            [scope setFingerprint:field(data, @"fingerprint")];
            [scope setLevel:field(data, @"level") ? level(data[@"level"]) : kSentryLevelNone];
            [scope clearBreadcrumbs];
            for (SentryBreadcrumb *b in breadcrumbs(field(data, @"breadcrumbs"))) [scope addBreadcrumb:b];
        }];
#if __has_feature(objc_arc)
        previous = data;
#else
        [previous release];
        previous = [data copy];
#endif
    }
}
inline bool flush(int timeoutMs) { [SentrySDK flush:timeoutMs / 1000.0]; return true; }
inline bool close(int timeoutMs) { [SentrySDK flush:timeoutMs / 1000.0]; [SentrySDK close]; return true; }
}
