/**
 * DROP-IN CORS for Innocent's unza-z-chat-backend / server.js
 *
 * WHY THIS FILE EXISTS
 * --------------------
 * ZCHAT-main (Flutter) has no backend folder. The Node API lives only on
 * Innocent's PC:
 *   C:\Users\TINOTECH\Desktop\FINAL YEAR PROJECT\unza-z-chat-backend\server.js
 * Cursor on Ruth's PC cannot edit that path (different Windows user / disk).
 *
 * HOW TO USE (pick one)
 * ---------------------
 * A) One-click (preferred on Innocent's PC, from a ZCHAT clone):
 *      powershell -ExecutionPolicy Bypass -File .\tools\fix_backend_cors.ps1
 *
 * B) Manual: paste the block below into server.js AFTER `const cors = require('cors')`
 *    and BEFORE your routes. DELETE any older `app.use(cors({ origin: ... }))`
 *    that calls `callback(new Error('Not allowed by CORS'))` (that becomes HTTP 500).
 */

'use strict';

const cors = require('cors');

/** Allow Flutter Chrome on any localhost / 127.0.0.1 port. Never throw. */
const zchatCorsOptions = {
  origin: function (origin, callback) {
    if (
      !origin ||
      origin === 'null' ||
      (typeof origin === 'string' && origin.startsWith('file://')) ||
      /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)
    ) {
      return callback(null, true);
    }
    // Quiet deny — callback(new Error(...)) → 500 → Chrome "No Access-Control-Allow-Origin"
    return callback(null, false);
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type', 'X-ZChat-Demo-Auth'],
};

/**
 * Call once after `const app = express()`:
 *
 *   const { applyZchatCors } = require('./server_cors_dropin'); // or paste inline
 *   applyZchatCors(app);
 *
 * Or paste without require:
 *
 *   app.use(cors(zchatCorsOptions));
 *   app.options('*', cors(zchatCorsOptions));
 */
function applyZchatCors(app) {
  app.use(cors(zchatCorsOptions));
  app.options('*', cors(zchatCorsOptions));
}

module.exports = { zchatCorsOptions, applyZchatCors };

/* ─── READY-TO-PASTE (if you prefer not to require this file) ───────────

const cors = require('cors');

const zchatCorsOptions = {
  origin: function (origin, callback) {
    if (
      !origin ||
      origin === 'null' ||
      (typeof origin === 'string' && origin.startsWith('file://')) ||
      /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)
    ) {
      return callback(null, true);
    }
    return callback(null, false);
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type', 'X-ZChat-Demo-Auth'],
};

app.use(cors(zchatCorsOptions));
app.options('*', cors(zchatCorsOptions));

──────────────────────────────────────────────────────────────────────── */
