#pragma once
#include <sentry.h>
#include <string>
inline std::string &test_envelope() { static std::string envelope; return envelope; }
inline void test_send(sentry_envelope_t *envelope, void *) {
    size_t length = 0;
    char *data = sentry_envelope_serialize(envelope, &length);
    test_envelope().assign(data, length);
    sentry_free(data);
    sentry_envelope_free(envelope);
}
inline void test_transport(sentry_options_t *options) {
    sentry_options_set_transport(options, sentry_transport_new(test_send));
}
inline bool test_binary_attachment() {
    const char bytes[] = {0, (char)255, 42};
    return test_envelope().find(std::string(bytes, 3)) != std::string::npos;
}
