// Usage: NODE_PATH=/path/to/node_modules node tests/run-browser.cjs
globalThis.Sentry = require('@sentry/browser');
require('../build/browser-test.js');
