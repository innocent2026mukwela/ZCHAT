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

  /// Tenor (Google) API key for the in-chat GIF picker. Tenor v1 was shut down
  /// by Google, so v2 requires a key from a Google Cloud project with the
  /// "Tenor API" enabled. Pass it at build time:
  ///
  ///   --dart-define=TENOR_KEY=AIza...
  ///
  /// When empty, the GIF picker is hidden (nothing is hardcoded in source).
  static const tenorKey = String.fromEnvironment('TENOR_KEY', defaultValue: '');

  /// Whether the GIF feature should be offered at all.
  static bool get gifEnabled => tenorKey.isNotEmpty;

  /// ZegoCloud credentials (voice/video calls + live classroom sessions).
  /// Defaults are the shared TEST creds — override for production so no real
  /// secret is baked into source:
  ///
  ///   --dart-define=ZEGO_APP_ID=123456789
  ///   --dart-define=ZEGO_APP_SIGN=<64-hex sign>
  static const zegoAppId =
      int.fromEnvironment('ZEGO_APP_ID', defaultValue: 1781765877);
  static const zegoAppSign = String.fromEnvironment(
    'ZEGO_APP_SIGN',
    defaultValue: 'cdc671cbee473400e34f53d71a0bcae66372a3fd4a22d47af81d8bf485320ea2',
  );
}
