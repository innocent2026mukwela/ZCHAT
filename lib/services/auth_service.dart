import 'dart:async';
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
/// When [AppConfig.demoAuth] is true (default), OTP is generated locally (no
/// Node backend) and sign-in uses Firebase Anonymous Auth + a Firestore profile.
///
/// If demo auth is off but the Node OTP API is unreachable, [sendOtp] falls
/// back to the same local OTP path so FYP device demos still work.
class AuthService {
  static const _baseUrl = '${AppConfig.backendBase}/api/auth';

  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;
  static final _rng = Random();

  /// Last OTP generated in local/demo mode (for UI display). Null otherwise.
  static String? lastDemoOtp;
  static String? _demoPhone;

  /// Session flag: true after a successful local OTP send (config or fallback).
  static bool _localOtpSession = false;

  /// True when this login session should verify via local OTP (not Node).
  static bool get usingLocalOtp => AppConfig.demoAuth || _localOtpSession;

  // ── Current user ──────────────────────────────────────────────────────────

  static User? get currentUser => _auth.currentUser;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Send OTP ──────────────────────────────────────────────────────────────

  /// Sends (or generates locally) an OTP for [phoneNumber].
  /// Returns the local OTP string when using local auth; otherwise null.
  static Future<String?> sendOtp(String phoneNumber) async {
    if (AppConfig.demoAuth) {
      return _beginLocalOtp(phoneNumber);
    }

    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/send-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phoneNumber': phoneNumber}),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        throw Exception(_errorMessage(res));
      }
      lastDemoOtp = null;
      _demoPhone = null;
      _localOtpSession = false;
      return null;
    } catch (e) {
      if (_isNetworkFailure(e)) {
        // FYP / device demo: Node unreachable → silent local OTP (no URL dump).
        debugPrint(
          '[AuthService] Node OTP unreachable ($e) — using local OTP fallback',
        );
        return _beginLocalOtp(phoneNumber);
      }
      throw Exception(_friendlyError(e));
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> verifyOtp(
      String phoneNumber, String otp) async {
    if (usingLocalOtp) {
      return _verifyDemoOtp(phoneNumber, otp);
    }

    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/verify-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phoneNumber': phoneNumber, 'otp': otp}),
          )
          .timeout(const Duration(seconds: 12));

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
      try {
        await _ensureFirestoreOnline();
        await _withFirestoreRetry(
          () => _db.collection('users').doc(uid).set(
                {'phoneNumber': phone},
                SetOptions(merge: true),
              ),
        );
      } catch (e) {
        // Auth already succeeded — surface a clear message rather than hanging.
        throw Exception(_friendlyFirestoreError(e));
      }

      return {
        'uid': uid,
        'needsProfile': json['needsProfile'],
      };
    } catch (e) {
      if (e is Exception && e.toString().startsWith('Exception: ')) rethrow;
      throw Exception(_friendlyError(e));
    }
  }

  /// Local path: any 6-digit code works. Signs in anonymously and writes a
  /// user profile so the rest of the app can use [currentUser].
  static Future<Map<String, dynamic>> _verifyDemoOtp(
      String phoneNumber, String otp) async {
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      throw Exception('Enter a 6-digit code.');
    }

    try {
      await _auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] Anonymous sign-in failed: ${e.code}');
      throw Exception(
        'Sign-in failed (${e.code}). '
        'Enable Anonymous sign-in in the Firebase Console '
        '(Authentication → Sign-in method → Anonymous).',
      );
    }

    // Auth can succeed a tick before currentUser is non-null on web.
    var user = _auth.currentUser;
    if (user == null) {
      try {
        user = await _auth
            .authStateChanges()
            .where((u) => u != null)
            .first
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        throw Exception(
          'Sign-in did not finish. Check your connection and try again.',
        );
      }
    }
    final uid = user!.uid;
    final phone = phoneNumber.isNotEmpty ? phoneNumber : (_demoPhone ?? '');

    await _ensureFirestoreOnline();

    Map<String, dynamic>? existingData;
    var docExists = false;
    try {
      final existing = await _withFirestoreRetry(
        () => _db.collection('users').doc(uid).get(
              const GetOptions(source: Source.serverAndCache),
            ),
      );
      existingData = existing.data();
      docExists = existing.exists;
    } catch (e) {
      if (!_isFirestoreOffline(e)) {
        throw Exception(_friendlyFirestoreError(e));
      }
      // Offline get: try cache, else treat as new profile (do not hang login).
      debugPrint('[AuthService] Profile get offline — trying cache: $e');
      try {
        final cached = await _db.collection('users').doc(uid).get(
              const GetOptions(source: Source.cache),
            );
        existingData = cached.data();
        docExists = cached.exists;
      } catch (_) {
        existingData = null;
        docExists = false;
      }
    }

    final needsProfile = existingData?['profileComplete'] != true;

    try {
      await _withFirestoreRetry(
        () => _db.collection('users').doc(uid).set({
          'phoneNumber': phone,
          'demo': true,
          'fullName': existingData?['fullName'] ??
              (phone.isNotEmpty ? phone : 'User'),
          if (!docExists) 'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      );
    } catch (e) {
      throw Exception(_friendlyFirestoreError(e));
    }

    return {
      'uid': uid,
      'needsProfile': needsProfile,
    };
  }

  static Future<void> _ensureFirestoreOnline() async {
    try {
      await _db.enableNetwork();
    } catch (e) {
      debugPrint('[AuthService] enableNetwork: $e');
    }
  }

  static bool _isFirestoreOffline(Object e) {
    if (e is FirebaseException) {
      final msg = (e.message ?? '').toLowerCase();
      return e.code == 'unavailable' || msg.contains('offline');
    }
    final s = e.toString().toLowerCase();
    return s.contains('unavailable') ||
        s.contains('client is offline') ||
        s.contains('cloud_firestore/unavailable');
  }

  static String _friendlyFirestoreError(Object e) {
    if (_isFirestoreOffline(e)) {
      return 'Cannot reach Firestore (appears offline). '
          'Check internet, disable adblock for this page, try Edge/Chrome, '
          'then tap the code again.';
    }
    return _friendlyError(e);
  }

  /// Retries transient Firestore offline / unavailable errors.
  static Future<T> _withFirestoreRetry<T>(
    Future<T> Function() op, {
    int attempts = 4,
  }) async {
    Object? last;
    for (var i = 0; i < attempts; i++) {
      try {
        if (i > 0) await _ensureFirestoreOnline();
        return await op();
      } catch (e) {
        last = e;
        if (!_isFirestoreOffline(e) || i == attempts - 1) rethrow;
        debugPrint(
          '[AuthService] Firestore retry ${i + 1}/$attempts: $e',
        );
        await Future.delayed(Duration(milliseconds: 450 * (i + 1)));
      }
    }
    throw last!;
  }

  static String? _beginLocalOtp(String phoneNumber) {
    lastDemoOtp = _generateDemoOtp();
    _demoPhone = phoneNumber;
    _localOtpSession = true;
    debugPrint('[AuthService] Local OTP for $phoneNumber: $lastDemoOtp');
    return lastDemoOtp;
  }

  static String _generateDemoOtp() =>
      (_rng.nextInt(900000) + 100000).toString();

  static bool _isNetworkFailure(Object e) {
    // Avoid dart:io (not available on web) — match by type + message.
    if (e is TimeoutException || e is http.ClientException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('failed to fetch') ||
        s.contains('clientexception') ||
        s.contains('socketexception') ||
        s.contains('httpexception') ||
        s.contains('connection refused') ||
        s.contains('connection timed out') ||
        s.contains('network is unreachable') ||
        s.contains('software caused connection abort') ||
        s.contains('xmlhttprequest');
  }

  /// User-facing text — never dump raw ClientException URLs.
  static String _friendlyError(Object e) {
    if (_isFirestoreOffline(e)) {
      return _friendlyFirestoreError(e);
    }
    if (_isNetworkFailure(e)) {
      return 'Cannot reach the server. Check your connection and try again.';
    }
    final raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    if (raw.toLowerCase().contains('failed to fetch') ||
        raw.contains('://') ||
        raw.toLowerCase().contains('clientexception')) {
      return 'Cannot reach the server. Check your connection and try again.';
    }
    return raw.isEmpty ? 'Something went wrong. Please try again.' : raw;
  }

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
      'uid': user.uid,
      'fullName': fullName,
      'role': role,
      'university': university,
      'studentNumber': studentNumber,
      'school': school,
      'program': program,
      'staffId': staffId,
      'department': department,
      'lecturerEmail': lecturerEmail,
      'profileComplete': true,
      // Keep demo profiles discoverable for New Chat peer list / search.
      if (usingLocalOtp) 'demo': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
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

    try {
      await _ensureFirestoreOnline();
      final doc = await _withFirestoreRetry(
        () => _db.collection('users').doc(user.uid).get(
              const GetOptions(source: Source.serverAndCache),
            ),
        attempts: 3,
      );
      return doc.exists ? doc.data() : null;
    } catch (e) {
      debugPrint('[AuthService] getMe failed: $e');
      try {
        final cached = await _db.collection('users').doc(user.uid).get(
              const GetOptions(source: Source.cache),
            );
        return cached.exists ? cached.data() : null;
      } catch (_) {
        return null;
      }
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  static Future<void> logout() async {
    lastDemoOtp = null;
    _demoPhone = null;
    _localOtpSession = false;
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
