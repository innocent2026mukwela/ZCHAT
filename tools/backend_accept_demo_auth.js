/**
 * DROP-IN patch for Innocent's Node API (unza-z-chat-backend / server.js).
 *
 * Problem: Flutter DEMO_AUTH uses Firebase Anonymous Auth (no Email/Password
 * owner access). Many backends reject `sign_in_provider === 'anonymous'`.
 *
 * Fix: accept either a normal Firebase ID token OR the demo header the
 * Flutter client always sends when DEMO_AUTH=true.
 *
 * 1) CORS — allow the demo header (and Chrome localhost origins):
 *
 *    app.use(cors({
 *      origin: [/^http:\/\/localhost:\d+$/, /^http:\/\/127\.0\.0\.1:\d+$/],
 *      allowedHeaders: ['Content-Type', 'Authorization', 'X-ZChat-Demo-Auth'],
 *    }));
 *
 * 2) In your Firebase auth middleware (wherever you call verifyIdToken),
 *    REPLACE the anonymous reject with the helper below — or paste this
 *    function and call it instead of a hard anonymous block:
 *
 *    // BAD (breaks FYP demo):
 *    // if (decoded.firebase?.sign_in_provider === 'anonymous') return res.status(401)...
 *
 *    // GOOD:
 *    const user = await resolveDemoOrFirebaseUser(req, admin);
 *    if (!user) return res.status(401).json({ error: 'Unauthorized' });
 *    req.user = user;
 *
 * 3) Optional .env:
 *    ALLOW_DEMO_AUTH=true
 */

'use strict';

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

module.exports = { resolveDemoOrFirebaseUser };
