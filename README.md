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

### Chrome (local backend)

```bash
flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:5000
```

### Android emulator

```bash
flutter run -d emulator-5554 --dart-define=BACKEND_URL=http://10.0.2.2:5000
```

### Physical device (same Wi‑Fi as your PC)

```bash
flutter run --dart-define=BACKEND_URL=http://YOUR_PC_LAN_IP:5000
```

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

## Demo auth (no Node OTP backend)

Demo mode is **on by default** (`DEMO_AUTH=true`). Login shows a local OTP; any 6-digit code signs in with Firebase Anonymous Auth and writes a searchable `users/{uid}` profile (`phoneNumber`, `fullName`, `demo: true`).

**1:1 chat between two demo accounts**

1. Run the app on two devices/browsers against the **same Firebase project**.
2. Sign in with **different phone numbers** (complete profile with distinct names).
3. Open **New Chat** → use the **Demo peers** list (or search by phone/name). Tap a peer to open a direct chat.
4. Contact discovery does **not** need the Node backend in demo mode (Firestore lookup).

Turn demo auth off for real OTP: `--dart-define=DEMO_AUTH=false`.

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

AI features call the Node backend (`BACKEND_URL`). With demo auth and no API running, AI screens show **“AI requires backend”** instead of spinning forever. Start the API (or point `BACKEND_URL` at a live server) for the real path.

## Notes

- Chat message bodies are AES-encrypted per chat; encrypt failures fail closed (message is not sent as plaintext).
- Classroom session scheduling writes to Firestore; students see sessions in the course classroom list. Dedicated push for “class starting” is not claimed in the UI unless FCM delivery is wired for that event.
- Past papers: first open downloads the PDF into app documents (`papers/{id}.pdf`) and reuses the local file when available.
