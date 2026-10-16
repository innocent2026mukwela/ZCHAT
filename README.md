# ZCHAT

Campus messaging, virtual classroom, and AI study tools.

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) 3.24+ (project tested with 3.47)
- A running ZCHAT backend (OTP auth, AI, notifications) — default `http://localhost:5000`
- Firebase project configured via `lib/firebase_options.dart` / platform config files
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

| Define         | Purpose                          | Default                 |
|----------------|----------------------------------|-------------------------|
| `BACKEND_URL`  | Auth / AI / notification API     | `http://localhost:5000` |
| `DEMO_AUTH`    | Local OTP + anonymous Firebase   | `true`                  |
| `ZEGO_APP_ID`  | Zego app id (int)                | `0` (calls disabled)    |
| `ZEGO_APP_SIGN`| Zego app sign                    | empty                   |
| `TENOR_KEY`    | Tenor GIF API key                | empty                   |

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

## Firebase Storage (media uploads)

Status photos/videos and chat images/videos upload to Firebase Storage. Anonymous demo users are fine **if** Storage rules allow any signed-in user (`request.auth != null`) on the paths the client uses (`chat_images/`, `chat_videos/`, `chat_docs/`, `status/`, `statuses/`, `voice_notes/`, `papers/`, …).

Deploy the repo rules:

```bash
firebase deploy --only storage
```

If rules are missing or outdated, the app shows a clear upload error (it does **not** fake success). See `storage.rules`.

## AI assistant

AI features call the Node backend (`BACKEND_URL`). With demo auth and no API running, AI screens show **“AI requires backend”** instead of spinning forever. Start the API (or point `BACKEND_URL` at a live server) for the real path.

## Notes

- Chat message bodies are AES-encrypted per chat; encrypt failures fail closed (message is not sent as plaintext).
- Classroom session scheduling writes to Firestore; students see sessions in the course classroom list. Dedicated push for “class starting” is not claimed in the UI unless FCM delivery is wired for that event.
- Past papers: first open downloads the PDF into app documents (`papers/{id}.pdf`) and reuses the local file when available.
