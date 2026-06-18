import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Per-chat AES-256 symmetric encryption.
/// Key stored in Firestore under chats/{chatId}.encryptionKey (base64).
/// Firestore security rules restrict access to chat members only.
class EncryptionService {
  static final _db   = FirebaseFirestore.instance;
  static final _rand = Random.secure();
  static final _cache = <String, enc.Key>{};

  static Future<enc.Key> _getKey(String chatId) async {
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

  static Future<String> encrypt(String chatId, String plaintext) async {
    if (plaintext.isEmpty) return plaintext;
    try {
      final key       = await _getKey(chatId);
      final iv        = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(plaintext, iv: iv);
      return '${iv.base64}:${encrypted.base64}';
    } catch (_) {
      return plaintext;
    }
  }

  static Future<String> decrypt(String chatId, String ciphertext) async {
    if (!ciphertext.contains(':')) return ciphertext; // legacy plaintext
    try {
      final parts    = ciphertext.split(':');
      if (parts.length != 2) return ciphertext;
      final key      = await _getKey(chatId);
      final iv       = enc.IV.fromBase64(parts[0]);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(parts[1], iv: iv);
    } catch (_) {
      return ciphertext;
    }
  }

  static void invalidateCache(String chatId) => _cache.remove(chatId);
}
