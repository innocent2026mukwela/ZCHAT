import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TwoStepService {
  static final _db = FirebaseFirestore.instance;
  static String get _uid => FirebaseAuth.instance.currentUser!.uid;

  static String _hash(String pin) =>
      sha256.convert(utf8.encode(pin)).toString();

  static Future<bool> isEnabled() async {
    try {
      try {
        await _db.enableNetwork();
      } catch (_) {}
      final doc = await _db.collection('users').doc(_uid).get(
            const GetOptions(source: Source.serverAndCache),
          );
      final h = doc.data()?['twoStepPinHash'] as String?;
      return h != null && h.isNotEmpty;
    } catch (_) {
      // Offline / unavailable — do not block login; treat as PIN off.
      try {
        final cached = await _db.collection('users').doc(_uid).get(
              const GetOptions(source: Source.cache),
            );
        final h = cached.data()?['twoStepPinHash'] as String?;
        return h != null && h.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  static Future<void> setPin(String pin) async {
    await _db.collection('users').doc(_uid)
        .update({'twoStepPinHash': _hash(pin)});
  }

  static Future<void> disablePin() async {
    await _db.collection('users').doc(_uid)
        .update({'twoStepPinHash': FieldValue.delete()});
  }

  static Future<bool> verify(String pin) async {
    final doc = await _db.collection('users').doc(_uid).get();
    final stored = doc.data()?['twoStepPinHash'] as String?;
    if (stored == null) return true; // no pin set
    return stored == _hash(pin);
  }
}
