import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Per-chat AES-256-CBC encryption.
///
/// Keys live on `chats/{chatId}.encryptionKey` (base64) and are readable only
/// by chat members via Firestore rules. Encrypt **fails closed** (throws) so
/// messages are never silently stored as plaintext. Decrypt shows a clear
/// placeholder when ciphertext cannot be recovered — never pretends success.
class EncryptionService {
  static final _db   = FirebaseFirestore.instance;
  static final _rand = Random.secure();
  static final _cache = <String, enc.Key>{};

  static const decryptFailedPlaceholder = '[Unable to decrypt message]';

  static Future<enc.Key> _getKey(String chatId) async {
    if (chatId.isEmpty) {
      throw StateError('Cannot encrypt without a chat id.');
    }
    if (_cache.containsKey(chatId)) return _cache[chatId]!;

    final doc    = await _db.collection('chats').doc(chatId).get();
    final stored = doc.data()?['encryptionKey'] as String?;

    if (stored != null && stored.isNotEmpty) {
      final key = enc.Key(Uint8List.fromList(base64.decode(stored)));
      _cache[chatId] = key;
      return key;
    }

    // Generate a fresh 256-bit key and persist it
    final bytes  = Uint8List.fromList(List<int>.generate(32, (_) => _rand.nextInt(256)));
    final newKey = enc.Key(bytes);
    await _db.collection('chats').doc(chatId)
        .set({'encryptionKey': base64.encode(bytes)}, SetOptions(merge: true));
    _cache[chatId] = newKey;
    return newKey;
  }

  /// Encrypts [plaintext]. Throws on failure — callers must not fall back to
  /// storing plaintext.
  static Future<String> encrypt(String chatId, String plaintext) async {
    if (plaintext.isEmpty) return plaintext;
    final key       = await _getKey(chatId);
    final iv        = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypts ciphertext. Legacy plaintext (no `iv:payload` shape) is returned
  /// as-is. Corrupt / wrong-key payloads yield [decryptFailedPlaceholder].
  static Future<String> decrypt(String chatId, String ciphertext) async {
    if (ciphertext.isEmpty) return ciphertext;
    if (!_looksEncrypted(ciphertext)) return ciphertext; // legacy plaintext
    try {
      final parts = ciphertext.split(':');
      if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
        return decryptFailedPlaceholder;
      }
      final key       = await _getKey(chatId);
      final iv        = enc.IV.fromBase64(parts[0]);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(parts[1], iv: iv);
    } catch (e, st) {
      developer.log('Decrypt failed for chat $chatId',
          name: 'EncryptionService', error: e, stackTrace: st);
      return decryptFailedPlaceholder;
    }
  }

  /// True when the value matches our `iv:ciphertext` encoding (both base64-ish).
  static bool _looksEncrypted(String value) {
    final idx = value.indexOf(':');
    if (idx <= 0 || idx >= value.length - 1) return false;
    // Avoid treating plain text that happens to contain a colon as ciphertext.
    final left = value.substring(0, idx);
    final right = value.substring(idx + 1);
    if (left.contains(' ') || right.contains(' ')) return false;
    if (left.length < 16 || right.length < 16) return false;
    return true;
  }

  static void invalidateCache(String chatId) => _cache.remove(chatId);
}
