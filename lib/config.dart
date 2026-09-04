/// Central app configuration.
///
/// The backend base URL is overridable at run/build time via a --dart-define,
/// so the same code targets every platform without editing source:
///
///   Android emulator:             `--dart-define=BACKEND_URL=http://10.0.2.2:5000`
///   Physical device (same Wi-Fi): `--dart-define=BACKEND_URL=http://PC_LAN_IP:5000`
///   Production:                   `--dart-define=BACKEND_URL=https://api.yourdomain`
///
/// The default targets the current dev LAN IP (used by Codemagic iOS builds).
class AppConfig {
  static const backendBase = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://172.20.10.14:5000',
  );
}
