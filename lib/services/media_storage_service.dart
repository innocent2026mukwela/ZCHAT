import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Thrown when SUPABASE_URL / SUPABASE_ANON_KEY were not passed via dart-define.
class MediaStorageNotConfiguredException implements Exception {
  @override
  String toString() => 'Media storage not configured';
}

/// Uploads chat / status / paper media to a Supabase Storage bucket.
///
/// Firebase Auth + Firestore stay unchanged; only binary files move here so
/// the team can stay on the free Firebase Spark plan (no Blaze / Storage).
class MediaStorageService {
  MediaStorageService._();

  static bool _initialized = false;

  static bool get isConfigured => AppConfig.supabaseConfigured;

  /// Call once from [main] when keys are present. Safe to call again.
  static Future<void> init() async {
    if (!isConfigured || _initialized) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    _initialized = true;
  }

  /// Uploads [file] to `[SUPABASE_BUCKET]/[path]` and returns a public URL.
  ///
  /// Throws [MediaStorageNotConfiguredException] when keys are missing.
  static Future<String> uploadFile({
    required File file,
    required String path,
    String? contentType,
  }) async {
    if (!isConfigured) {
      throw MediaStorageNotConfiguredException();
    }
    if (!_initialized) await init();

    final storage = Supabase.instance.client.storage.from(AppConfig.supabaseBucket);
    final objectPath = path.startsWith('/') ? path.substring(1) : path;

    try {
      await storage.upload(
        objectPath,
        file,
        fileOptions: FileOptions(
          contentType: contentType ?? _guessContentType(objectPath),
          upsert: true,
        ),
      );
    } on StorageException catch (e) {
      final msg = e.message.trim();
      throw Exception(msg.isNotEmpty ? msg : 'Upload failed (${e.statusCode})');
    }

    return storage.getPublicUrl(objectPath);
  }

  static String? _guessContentType(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'm4a':
        return 'audio/mp4';
      case 'pdf':
        return 'application/pdf';
      default:
        return null;
    }
  }
}
