# Manual CORS fix (8 lines)

If the PowerShell script is scary or fails, open `server.js` on the backend PC and
**replace only the `origin:` function** inside `cors({ ... })` with these exact 8 lines:

```js
origin: function (origin, callback) {
  if (!origin ||
      /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
    return callback(null, true);
  }
  // Quiet deny - never throw (throw = HTTP 500)
  callback(null, false);
}
```

Then restart: `npm start`.

Do **not** keep `callback(new Error('Not allowed by CORS'))` - that becomes status 500
and Chrome reports missing Access-Control-Allow-Origin.
