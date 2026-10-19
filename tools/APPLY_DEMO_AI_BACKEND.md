# Innocent — apply demo AI backend (5 PowerShell steps)

Flutter shows **AI requires backend** when Chrome cannot reach Node on port 5000 **or** CORS blocks the request. Auth (401) alone does **not** trigger that home-screen message.

Backend folder (on your PC):

`C:\Users\TINOTECH\Desktop\FINAL YEAR PROJECT\unza-z-chat-backend`

Flutter folder:

`C:\Users\user\Desktop\ZCHAT-main`  
(or wherever you cloned `innocent2026mukwela/ZCHAT`)

---

## Step 1 — Copy the patch file

In **PowerShell**:

```powershell
$backend = "C:\Users\TINOTECH\Desktop\FINAL YEAR PROJECT\unza-z-chat-backend"
$flutter = "C:\Users\user\Desktop\ZCHAT-main"   # adjust if your clone path differs

New-Item -ItemType Directory -Force -Path "$backend\middleware" | Out-Null
Copy-Item "$flutter\tools\backend_accept_demo_auth.js" `
  "$backend\middleware\backend_accept_demo_auth.js" -Force
```

---

## Step 2 — Edit `server.js` (exact lines)

Near the top (after `express` / `cors` / `firebase-admin` are required):

```js
const {
  corsOptions,
  demoAuthMiddleware,
} = require('./middleware/backend_accept_demo_auth');
```

**CORS** — replace any existing `app.use(cors(...))` with:

```js
app.use(cors(corsOptions));
app.options('*', cors(corsOptions));
```

**Auth** — after `admin` is initialized, protect AI routes (and remove any `sign_in_provider === 'anonymous'` → 401):

```js
const requireAuth = demoAuthMiddleware(admin);
app.use('/api/ai', requireAuth);
```

If you already have an auth middleware, either replace it with `requireAuth` on `/api/ai`, or inside it call `resolveDemoOrFirebaseUser` instead of rejecting anonymous.

---

## Step 3 — Backend `.env` (Gemini / Google AI Studio)

This project’s AI replies go through the **Node** backend to **Google Gemini** (free tier / AI Studio).  
ZCHAT-main (Flutter) does **not** call Gemini or Anthropic directly — it only POSTs to `http://localhost:5000/api/ai/...`.

In the backend root `.env` add (keep your existing Firebase lines):

```env
ALLOW_DEMO_AUTH=true
GEMINI_API_KEY=your-google-ai-studio-key
```

Get a free key: [Google AI Studio](https://aistudio.google.com/apikey).

**Do not use `ANTHROPIC_API_KEY`** unless your `server.js` explicitly reads that name (this team’s stack is Gemini).

If chat still says the API key is missing after setting `GEMINI_API_KEY`, check what your backend actually reads:

```powershell
cd "C:\Users\TINOTECH\Desktop\FINAL YEAR PROJECT\unza-z-chat-backend"
Select-String -Path .\server.js,.\routes\*.js,.\*.js -Pattern 'process\.env\.(GEMINI|GOOGLE|API_KEY)' -ErrorAction SilentlyContinue
```

Some Node samples also accept `GOOGLE_API_KEY` as an alias — only add that if the grep above shows it.

---

## Step 4 — Start Node on port 5000

```powershell
cd "C:\Users\TINOTECH\Desktop\FINAL YEAR PROJECT\unza-z-chat-backend"
npm start
```

Confirm it listens on **5000**. Quick check in another PowerShell window:

```powershell
Invoke-WebRequest http://localhost:5000/api/health -UseBasicParsing
# or: http://localhost:5000/health  or  http://localhost:5000/
```

---

## Step 5 — Run Flutter with BACKEND_URL

```powershell
cd "C:\Users\user\Desktop\ZCHAT-main"
flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:5000 --dart-define=DEMO_AUTH=true
```

Or with the demo defines file (if present):

```powershell
flutter run -d chrome --dart-define-from-file=dart_defines.demo.json
```

Open the **AI** tab → should load (not “AI requires backend”). Then send a message to confirm `GEMINI_API_KEY` works.

---

## If it still fails

| Symptom | Cause |
|--------|--------|
| Still “AI requires backend” | Node not on 5000, or CORS origin/headers wrong — DevTools Network will show failed/CORS |
| AI opens but chat says auth rejected | Middleware not applied / still rejecting anonymous — re-check Step 2 |
| Auth OK but no reply | Missing or wrong Gemini env var — set `GEMINI_API_KEY` (or the exact name `process.env` uses in `server.js`) |
