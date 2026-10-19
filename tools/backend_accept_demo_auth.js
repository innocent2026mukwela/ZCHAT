/**
 * DROP-IN patch for Innocent's Node API (unza-z-chat-backend / server.js).
 *
 * Problem: Flutter DEMO_AUTH uses Firebase Anonymous Auth. Many backends
 * reject `sign_in_provider === 'anonymous'`, and Chrome CORS often omits
 * `X-ZChat-Demo-Auth`, so the AI tab shows "AI requires backend".
 *
 * Flutter probe note: AiService.isBackendReachable() fails only on
 * connection refused / timeout / CORS ClientException. A 401 still counts
 * as "reachable". The home AI screen message therefore means Node is down
 * OR CORS is blocking — not (yet) an auth rejection.
 *
 * ─── EXACT server.js wiring ─────────────────────────────────────────────
 *
 * 1) Copy this file next to server.js:
 *      unza-z-chat-backend/middleware/backend_accept_demo_auth.js
 *    (or: unza-z-chat-backend/backend_accept_demo_auth.js)
 *
 * 2) Near the top of server.js (after express + cors + firebase-admin):
 *
 *      const cors = require('cors');
 *      const { resolveDemoOrFirebaseUser, demoAuthMiddleware, corsOptions } =
 *        require('./middleware/backend_accept_demo_auth');
 *      // adjust path if you put the file next to server.js:
 *      // require('./backend_accept_demo_auth')
 *
 * 3) CORS — MUST run before routes (replace any existing cors() call):
 *
 *      app.use(cors(corsOptions));
 *      app.options('*', cors(corsOptions)); // preflight for Chrome
 *
 * 4) Auth middleware — REPLACE any block that rejects anonymous, e.g.:
 *
 *      // BAD:
 *      // if (decoded.firebase?.sign_in_provider === 'anonymous') return res.status(401)...
 *
 *      // GOOD (protect /api/ai and other authenticated routes):
 *      const requireAuth = demoAuthMiddleware(admin);
 *      app.use('/api/ai', requireAuth);
 *      // or inside your existing auth middleware:
 *      // const user = await resolveDemoOrFirebaseUser(req, admin);
 *      // if (!user) return res.status(401).json({ error: 'Unauthorized' });
 *      // req.user = user; next();
 *
 * 5) Backend .env (same folder as server.js) — Gemini free tier / AI Studio:
 *      ALLOW_DEMO_AUTH=true
 *      GEMINI_API_KEY=...     # required for AI chat replies (Google Generative AI)
 *      # Some samples also read GOOGLE_API_KEY — only if your server.js does.
 *      # Not Anthropic: do not set ANTHROPIC_API_KEY unless server.js reads it.
 *
 * 6) Restart: npm start   (listen on port 5000)
 */

'use strict';

/** CORS options Flutter Chrome + DEMO_AUTH need. */
const corsOptions = {
  origin: [/^http:\/\/localhost:\d+$/, /^http:\/\/127\.0\.0\.1:\d+$/],
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-ZChat-Demo-Auth'],
  // credentials: false — Flutter http does not need cookies for AI
};

/**
 * @param {import('express').Request} req
 * @param {import('firebase-admin')} admin  firebase-admin already initialized
 * @returns {Promise<{ uid: string, demo?: boolean } | null>}
 */
async function resolveDemoOrFirebaseUser(req, admin) {
  const allowDemo =
    process.env.ALLOW_DEMO_AUTH === 'true' ||
    process.env.DEMO_AUTH === 'true' ||
    process.env.NODE_ENV !== 'production';

  const demoHeader = String(req.headers['x-zchat-demo-auth'] || '');
  const auth = String(req.headers.authorization || '');
  const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';

  // Prefer a real Firebase token when present (anonymous is OK for FYP).
  if (token) {
    try {
      const decoded = await admin.auth().verifyIdToken(token);
      // Do NOT reject anonymous here.
      return {
        uid: decoded.uid,
        demo: decoded.firebase?.sign_in_provider === 'anonymous',
      };
    } catch (err) {
      // Fall through to demo header when token verify fails.
      if (!allowDemo || demoHeader !== '1') {
        console.warn('[auth] verifyIdToken failed:', err?.message || err);
        return null;
      }
    }
  }

  // Flutter DEMO_AUTH always sends X-ZChat-Demo-Auth: 1
  if (allowDemo && demoHeader === '1') {
    return { uid: 'demo-anonymous', demo: true };
  }

  return null;
}

/**
 * Express middleware factory. Use after firebase-admin is initialized:
 *   app.use('/api/ai', demoAuthMiddleware(admin));
 */
function demoAuthMiddleware(admin) {
  return async function demoAuth(req, res, next) {
    try {
      const user = await resolveDemoOrFirebaseUser(req, admin);
      if (!user) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      req.user = user;
      return next();
    } catch (err) {
      console.warn('[auth] demoAuthMiddleware error:', err?.message || err);
      return res.status(401).json({ error: 'Unauthorized' });
    }
  };
}

module.exports = {
  corsOptions,
  resolveDemoOrFirebaseUser,
  demoAuthMiddleware,
};
