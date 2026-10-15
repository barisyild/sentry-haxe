#pragma once
#include <sentry.h>

// Manual events have already passed Haxe's beforeSend. Restore their scope fields
// after sentry-native merges the global crash scope, so redacted data stays removed.
// No Haxe objects, locks or callbacks are accessed from native crash handlers.
inline sentry_value_t sentry_haxe_before_send(sentry_value_t event, void *, void *) {
    sentry_value_t processed = sentry_value_get_by_key(event, "_sentry_haxe_processed");
    if (sentry_value_is_null(processed)) return event;
    const char *keys[] = {"user", "tags", "extra", "breadcrumbs", "fingerprint", "level", "environment", "transaction"};
    for (unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) {
        sentry_value_t value = sentry_value_get_by_key(processed, keys[i]);
        if (sentry_value_is_null(value)) sentry_value_remove_by_key(event, keys[i]);
        else { sentry_value_incref(value); sentry_value_set_by_key(event, keys[i], value); }
    }
    // Keep SDK-owned OS/device contexts, while replacing the keys managed by Haxe.
    sentry_value_t contexts = sentry_value_get_by_key(event, "contexts");
    if (sentry_value_is_null(contexts)) {
        contexts = sentry_value_new_object();
        sentry_value_set_by_key(event, "contexts", contexts);
    }
    sentry_value_t managed = sentry_value_get_by_key(processed, "managed_context_keys");
    for (size_t i = 0; i < sentry_value_get_length(managed); ++i)
        sentry_value_remove_by_key(contexts, sentry_value_as_string(sentry_value_get_by_index(managed, i)));
    sentry_value_t supplied = sentry_value_get_by_key(processed, "contexts");
    sentry_value_t names = sentry_value_get_by_key(processed, "context_keys");
    for (size_t i = 0; i < sentry_value_get_length(names); ++i) {
        const char *key = sentry_value_as_string(sentry_value_get_by_index(names, i));
        sentry_value_t value = sentry_value_get_by_key(supplied, key);
        sentry_value_incref(value);
        sentry_value_set_by_key(contexts, key, value);
    }
    sentry_value_remove_by_key(event, "_sentry_haxe_processed");
    return event;
}
inline void sentry_haxe_configure(sentry_options_t *options) {
    sentry_options_set_before_send(options, sentry_haxe_before_send, nullptr);
}
