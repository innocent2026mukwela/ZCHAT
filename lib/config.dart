import 'package:flutter/foundation.dart';

/// Central app configuration.
///
/// Override at run/build time via `--dart-define`:
///
///   Android emulator:             `--dart-define=BACKEND_URL=http://10.0.2.2:5000`
///   Physical device (same Wi-Fi): `--dart-define=BACKEND_URL=http://PC_LAN_IP:5000`
///   Chrome / desktop:             `--dart-define=BACKEND_URL=http://localhost:5000`
///   Production:                   `--dart-define=BACKEND_URL=https://api.yourdomain`
///
/// Zego / Tenor credentials must be supplied via dart-define — no production
/// secrets are baked into source defaults.
///
/// Local auth (no Node backend required):
///
///   Default ON — OTP is generated locally (shown as a session code in OTP UI).
///   Profiles are marked `demo: true` and discoverable via New Chat suggested contacts.
///   Turn off for real backend OTP:
///     `flutter run --dart-define=DEMO_AUTH=false`
///
/// Media uploads still need Storage rules deployed (see README / storage.rules).
/// AI features still need BACKEND_URL reachable.
class AppConfig {
  /// When true, login skips the Node OTP API and uses a local demo OTP plus
  /// Firebase Anonymous Auth. Disable for production: `--dart-define=DEMO_AUTH=false`.
  static const demoAuth = bool.fromEnvironment(
    'DEMO_AUTH',
    defaultValue: true,
  );

  static const backendBase = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:5000',
  );

  /// Tenor (Google) API key for the in-chat GIF picker.
  ///   `--dart-define=TENOR_KEY=AIza...`
  /// When empty, the GIF picker is hidden.
  static const tenorKey = String.fromEnvironment('TENOR_KEY', defaultValue: '');

  static bool get gifEnabled => tenorKey.isNotEmpty;

  /// ZegoCloud credentials for voice/video / live classroom.
  /// Empty by default — pass via dart-define for calls to work:
  ///
  ///   `--dart-define=ZEGO_APP_ID=123456789`
  ///   `--dart-define=ZEGO_APP_SIGN=<64-hex sign>`
  static const zegoAppId =
      int.fromEnvironment('ZEGO_APP_ID', defaultValue: 0);
  static const zegoAppSign = String.fromEnvironment(
    'ZEGO_APP_SIGN',
    defaultValue: '',
  );

  static bool get zegoConfigured =>
      zegoAppId != 0 && zegoAppSign.isNotEmpty;

  /// Logs configuration warnings once at startup (debug / profile only).
  static void validateAtStartup() {
    if (kReleaseMode) return;
    if (demoAuth) {
      debugPrint(
        '[AppConfig] DEMO_AUTH=true — login uses local OTP + anonymous Firebase. '
        'Disable with --dart-define=DEMO_AUTH=false',
      );
    }
    if (!zegoConfigured) {
      debugPrint(
        '[AppConfig] Zego credentials not set — voice/video calls disabled. '
        'Pass --dart-define=ZEGO_APP_ID=… and ZEGO_APP_SIGN=…',
      );
    }
    if (backendBase.contains('localhost') || backendBase.contains('127.0.0.1')) {
      debugPrint(
        '[AppConfig] Backend: $backendBase '
        '(override with --dart-define=BACKEND_URL=… for device/emulator)',
      );
    }
  }
}
