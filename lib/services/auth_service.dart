import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config.dart';

/// Handles authentication via the ZCHAT backend's OTP endpoints, bridging
/// into Firebase Auth with a custom token.
///
/// When [AppConfig.demoAuth] is true, OTP is generated locally (no Node
/// backend) and sign-in uses Firebase Anonymous Auth + a Firestore profile.
/// 10.0.2.2 = Android emulator loopback to host machine.
/// For a physical device on the same Wi-Fi, use your machine's LAN IP.
class AuthService {
  static const _baseUrl = '${AppConfig.backendBase}/api/auth';

  static final _auth = FirebaseAuth.instance;
  static final _db   = FirebaseFirestore.instance;
  static final _rng  = Random();

  /// Last OTP generated in demo mode (for UI display). Null outside demo.
  static String? lastDemoOtp;
  static String? _demoPhone;

  // ── Current user ──────────────────────────────────────────────────────────

  static User? get currentUser => _auth.currentUser;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Send OTP ──────────────────────────────────────────────────────────────

  /// Sends (or in demo mode, generates) an OTP for [phoneNumber].
  /// Returns the demo OTP string when [AppConfig.demoAuth] is true; otherwise null.
  static Future<String?> sendOtp(String phoneNumber) async {
    if (AppConfig.demoAuth) {
      lastDemoOtp = _generateDemoOtp();
      _demoPhone = phoneNumber;
      debugPrint('[AuthService] Demo OTP for $phoneNumber: $lastDemoOtp');
      return lastDemoOtp;
    }

    lastDemoOtp = null;
    _demoPhone = null;

    final res = await http.post(
      Uri.parse('$_baseUrl/send-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phoneNumber': phoneNumber}),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    return null;
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> verifyOtp(
      String phoneNumber, String otp) async {
    if (AppConfig.demoAuth) {
      return _verifyDemoOtp(phoneNumber, otp);
    }

    final res = await http.post(
      Uri.parse('$_baseUrl/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phoneNumber': phoneNumber, 'otp': otp}),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    await _auth.signInWithCustomToken(json['firebaseToken'] as String);

    // Custom-token sign-in leaves FirebaseAuth.phoneNumber null, so persist the
    // verified phone (from the backend user record, falling back to the number
    // just entered) onto the Firestore profile. Contact matching and user
    // search rely on users/{uid}.phoneNumber.
    final uid = _auth.currentUser!.uid;
    final backendUser = json['user'] as Map<String, dynamic>?;
    final phone = backendUser?['phone_number'] as String? ?? phoneNumber;
    await _db.collection('users').doc(uid).set(
      {'phoneNumber': phone}, SetOptions(merge: true));

    return {
      'uid': uid,
      'needsProfile': json['needsProfile'],
    };
  }

  /// Demo path: any 6-digit code works. Signs in anonymously and writes a
  /// demo user profile so the rest of the app can use [currentUser].
  static Future<Map<String, dynamic>> _verifyDemoOtp(
      String phoneNumber, String otp) async {
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      throw Exception('Enter a 6-digit code.');
    }

    try {
      await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      throw Exception(
        'Demo sign-in failed (${e.code}). '
        'Enable Anonymous sign-in in the Firebase Console '
        '(Authentication → Sign-in method → Anonymous).',
      );
    }

    final uid = _auth.currentUser!.uid;
    final phone = phoneNumber.isNotEmpty ? phoneNumber : (_demoPhone ?? '');

    final existing = await _db.collection('users').doc(uid).get();
    final existingData = existing.data();
    final needsProfile = existingData?['profileComplete'] != true;

    await _db.collection('users').doc(uid).set({
      'phoneNumber': phone,
      'demo': true,
      'fullName': existingData?['fullName'] ?? 'Demo User',
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return {
      'uid': uid,
      'needsProfile': needsProfile,
    };
  }

  static String _generateDemoOtp() =>
      (_rng.nextInt(900000) + 100000).toString();

  // ── Complete profile ──────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> completeProfile({
    required String fullName,
    required String role,
    String? university,
    String? studentNumber,
    String? school,
    String? program,
    String? staffId,
    String? department,
    String? lecturerEmail,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated.');

    final data = {
      'uid':             user.uid,
      'fullName':        fullName,
      'role':            role,
      'university':      university,
      'studentNumber':   studentNumber,
      'school':          school,
      'program':         program,
      'staffId':         staffId,
      'department':      department,
      'lecturerEmail':   lecturerEmail,
      'profileComplete': true,
      // Keep demo profiles discoverable for New Chat peer list / search.
      if (AppConfig.demoAuth) 'demo': true,
      'createdAt':       FieldValue.serverTimestamp(),
      'updatedAt':       FieldValue.serverTimestamp(),
    };

    await _db.collection('users').doc(user.uid).set(data, SetOptions(merge: true));
    try {
      await user.updateDisplayName(fullName);
    } catch (e) {
      // Profile doc is the source of truth; Auth displayName is best-effort.
      debugPrint('[AuthService] updateDisplayName failed: $e');
    }
    return data;
  }

  // ── Get current user profile ──────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getMe() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final doc = await _db.collection('users').doc(user.uid).get();
    return doc.exists ? doc.data() : null;
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  static Future<void> logout() async {
    lastDemoOtp = null;
    _demoPhone = null;
    await _auth.signOut();
  }

  // ── Error helper ─────────────────────────────────────────────────────────

  static String _errorMessage(http.Response res) {
    try {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return json['error'] as String? ?? 'Something went wrong. Please try again.';
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }
}
