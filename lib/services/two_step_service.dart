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
    final doc = await _db.collection('users').doc(_uid).get();
    final h = doc.data()?['twoStepPinHash'] as String?;
    return h != null && h.isNotEmpty;
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
