# ZCHAT

Campus messaging, virtual classroom, and AI study tools.

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) 3.24+ (project tested with 3.47)
- A running ZCHAT backend (OTP auth, AI, notifications) — default `http://localhost:5000`
- Firebase project configured via `lib/firebase_options.dart` / platform config files (Auth + Firestore; **no Blaze / Firebase Storage required**)
- Free [Supabase](https://supabase.com/) project for chat/status/paper media uploads (see below)
- Optional: [ZegoCloud](https://www.zegocloud.com/) credentials for voice/video and live class

## Setup

```bash
flutter pub get
```

## Run

### Chrome (demo OTP + local AI + status media)

```bash
flutter run -d chrome --dart-define-from-file=dart_defines.demo.json ^
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

`dart_defines.demo.json` sets `DEMO_AUTH=true` and `BACKEND_URL=http://localhost:5000`. After upgrading from the old anonymous demo login, **sign out once and sign in again** so AI gets a fresh non-anonymous ID token.

### Android emulator

```bash
flutter run -d emulator-5554 --dart-define=BACKEND_URL=http://10.0.2.2:5000
```

### Physical phone — FYP demo login (recommended)

Login does **not** need the Node server. Rebuild with demo auth on (default, but pass it explicitly so an old LAN build is replaced):

```bash
flutter run --dart-define-from-file=dart_defines.demo.json
```

Or:

```bash
flutter run --dart-define=DEMO_AUTH=true
```

Then on the phone: enter any valid Zambian number → **Continue** → enter the **6-digit code shown on the Verification screen** (or any 6 digits) → complete profile if asked.

Do **not** pass `BACKEND_URL=http://172.x.x.x:5000` with `DEMO_AUTH=false` unless the phone can reach that PC on the same Wi‑Fi.

### Physical device + real Node OTP (optional)

```bash
flutter run --dart-define=DEMO_AUTH=false --dart-define=BACKEND_URL=http://YOUR_PC_LAN_IP:5000
```

Phone and PC must share Wi‑Fi; allow port **5000** through Windows Firewall; use the PC’s current LAN IP (`ipconfig`).

### Voice / video / live classroom

Pass Zego credentials at run/build time (they are not baked into source):

```bash
flutter run -d chrome ^
  --dart-define=BACKEND_URL=http://localhost:5000 ^
  --dart-define=ZEGO_APP_ID=123456789 ^
  --dart-define=ZEGO_APP_SIGN=your_64_hex_sign
```

### GIF picker (optional)

```bash
--dart-define=TENOR_KEY=AIza...
```

Without `TENOR_KEY`, the in-chat GIF picker stays hidden.

## Configuration

See `lib/config.dart`. All environment overrides use `--dart-define`:

| Define              | Purpose                          | Default                 |
|---------------------|----------------------------------|-------------------------|
| `BACKEND_URL`       | Auth / AI / notification API     | `http://localhost:5000` |
| `DEMO_AUTH`         | Local OTP + anonymous Firebase   | `true`                  |
| `ZEGO_APP_ID`       | Zego app id (int)                | `0` (calls disabled)    |
| `ZEGO_APP_SIGN`     | Zego app sign                    | empty                   |
| `TENOR_KEY`         | Tenor GIF API key                | empty                   |
| `SUPABASE_URL`      | Supabase project URL             | empty (uploads disabled)|
| `SUPABASE_ANON_KEY` | Supabase anon/public key         | empty                   |
| `SUPABASE_BUCKET`   | Storage bucket name              | `zchat-media`           |

## Roles

- **Student** → `/home` after OTP (or profile setup)
- **Lecturer** → `/lecturer/home` after OTP (or profile setup)

## Demo auth (silent local OTP — keeps AI / media working)

Demo mode is **on by default** (`DEMO_AUTH=true`). Login shows a local verification code; any 6-digit code works. **This is not Anonymous-only anymore** (Anonymous broke AI when Node rejects `sign_in_provider=anonymous`).

On verify, the app tries in order:

1. `POST /api/auth/demo-login` `{ phoneNumber }` → `firebaseToken` (best — same custom-token path as real OTP)
2. `POST /api/auth/verify-otp` with the entered code (works if your Node demo/dev mode accepts any OTP)
3. Firebase **Email/Password** account `demo_<digits>@zchat.demo` (stable uid per phone — enable Email/Password in Firebase Console)
4. Firebase Anonymous (last resort; AI may still fail if Node blocks anonymous tokens)

Firestore rules already allow any signed-in user (`request.auth != null`), including demo accounts. Media still uses **Supabase** (not Firebase Storage).

**1:1 chat between two demo accounts**

1. Run the app on two devices/browsers against the **same Firebase project**.
2. Sign in with **different phone numbers** (complete profile with distinct names).
3. Open **New Chat** → use the **Demo peers** list (or search by phone/name). Tap a peer to open a direct chat.
4. Contact discovery does **not** need the Node backend in demo mode (Firestore lookup).

Turn demo auth off for real OTP: `--dart-define=DEMO_AUTH=false`.

### Node backend (lives outside this Flutter repo)

ZCHAT-main has **no** `backend/` folder. On Innocent’s PC the API is usually under a separate “FINAL YEAR PROJECT” / Node folder. For Chrome + DEMO_AUTH:

**CORS** — allow the Flutter web origin (not only `*`'s credentials mode). Example Express:

```js
app.use(cors({
  origin: [/^http:\/\/localhost:\d+$/, /^http:\/\/127\.0\.0\.1:\d+$/],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
```

**AI env (server `.env`)** — typical:

```
ANTHROPIC_API_KEY=...          # or your Claude/OpenAI key name
FIREBASE_PROJECT_ID=...
GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json
# Optional if you add the route the Flutter client calls first:
# DEMO_LOGIN=true
```

**Recommended Node route** (restores old custom-token login without SMS):

`POST /api/auth/demo-login` body `{ "phoneNumber": "+260…" }` → `{ "firebaseToken", "needsProfile", "user" }` using Firebase Admin `createCustomToken`.

Do **not** reject `sign_in_provider === 'anonymous'` without also supporting password/custom — or require Email/Password / demo-login above.

## Supabase Storage (media uploads)

Chat images/videos/docs, voice notes, status photo/video, papers PDFs, avatars, and thread images upload to **Supabase Storage** (free tier). Firestore still stores the returned public URL in the same fields as before. Firebase Auth is unchanged.

If `SUPABASE_URL` / `SUPABASE_ANON_KEY` are empty, uploads fail with **“Media storage not configured”** (no fake success).

### Team setup (verify once)

1. Create a free project at [supabase.com](https://supabase.com/).
2. **Storage → New bucket** → name `zchat-media` → enable **Public bucket** (simplest for demo playback on iOS; public read URLs).
3. **Project Settings → API** → copy **Project URL** and **anon public** key.
4. Run with dart-defines (see below) and test: send a **chat image**, then post a **status photo**.

### Storage policies (FYP demo)

In **Storage → Policies** for `zchat-media`, allow public read and open insert for the demo. Example SQL (SQL editor):

```sql
-- Public read (bucket is public; policy still needed for API list/download in some setups)
create policy "Public read zchat-media"
on storage.objects for select
using (bucket_id = 'zchat-media');

-- Demo-only: anyone with the anon key can upload (NOT for production)
create policy "Anon upload zchat-media"
on storage.objects for insert
with check (bucket_id = 'zchat-media');

-- Optional: allow overwrite / delete during demos
create policy "Anon update zchat-media"
on storage.objects for update
using (bucket_id = 'zchat-media');
```

**Security caveat:** anon upload is **demo-only**. Anyone who has the anon key can write to the bucket. For a later hardening step, add Supabase Auth (or map Firebase UID into path prefixes) and tighten RLS to `auth.uid()` / path prefixes. Prefer a file size limit in the Supabase dashboard if available.

### Run with Supabase

```bash
flutter run -d chrome ^
  --dart-define=BACKEND_URL=http://localhost:5000 ^
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY ^
  --dart-define=SUPABASE_BUCKET=zchat-media
```

### Codemagic / CI

`codemagic.yaml` links the Codemagic environment group named **`supabase`** on both iOS and Android workflows, and passes those values as dart-defines:

```yaml
flutter build apk --debug \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
  --dart-define=SUPABASE_BUCKET=${SUPABASE_BUCKET:-zchat-media}
```

**Innocent / team setup in Codemagic UI:**

1. Teams → Environment variables → create (or open) a group named exactly `supabase`.
2. Add encrypted variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (required). Optional: `SUPABASE_BUCKET` (defaults to `zchat-media`).
3. Ensure that group is available to the app / workflows (yaml already references `groups: [supabase]`).
4. Start a build on `main` after `git pull`.

## AI assistant

AI features call the Node backend (`BACKEND_URL`) with the Firebase ID token. With no API running (or CORS blocking Chrome), AI screens show **“AI requires backend”**. Start the API, allow localhost Chrome origins, and use the demo login path above so the token is not Anonymous-only.

## Notes

- Chat message bodies are AES-encrypted per chat; encrypt failures fail closed (message is not sent as plaintext).
- Classroom session scheduling writes to Firestore; students see sessions in the course classroom list. Dedicated push for “class starting” is not claimed in the UI unless FCM delivery is wired for that event.
- Past papers: first open downloads the PDF into app documents (`papers/{id}.pdf`) and reuses the local file when available.
