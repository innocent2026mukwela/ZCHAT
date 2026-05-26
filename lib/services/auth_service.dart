import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db   = FirebaseFirestore.instance;

  // Stores the verificationId between sendOtp and verifyOtp calls
  static String? _verificationId;

  // ── Current user ──────────────────────────────────────────────────────────

  static User? get currentUser => _auth.currentUser;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Send OTP ──────────────────────────────────────────────────────────────

  static Future<void> sendOtp(String phoneNumber) async {
    final completer = Completer<void>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),

      // Auto-retrieval (Android only — SMS auto-filled)
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
        if (!completer.isCompleted) completer.complete();
      },

      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) {
          completer.completeError(Exception(_friendlyError(e.code, e.message)));
        }
      },

      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        if (!completer.isCompleted) completer.complete();
      },

      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> verifyOtp(
      String phoneNumber, String otp) async {
    if (_verificationId == null) {
      throw Exception('Session expired. Please request a new code.');
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: otp,
    );

    final result = await _auth.signInWithCredential(credential);
    final user   = result.user!;

    // Check if the user has a profile in Firestore
    final doc = await _db.collection('users').doc(user.uid).get();
    final needsProfile = !doc.exists || doc.data()?['profileComplete'] != true;

    return {
      'uid': user.uid,
      'needsProfile': needsProfile,
    };
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
      'uid':             user.uid,
      'phoneNumber':     user.phoneNumber,
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
      'createdAt':       FieldValue.serverTimestamp(),
      'updatedAt':       FieldValue.serverTimestamp(),
    };

    await _db.collection('users').doc(user.uid).set(data, SetOptions(merge: true));
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
    await _auth.signOut();
  }

  // ── Friendly error messages ───────────────────────────────────────────────

  static String _friendlyError(String code, String? message) {
    switch (code) {
      case 'invalid-phone-number':
        return 'Invalid phone number. Please check and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      default:
        return message ?? 'Something went wrong. Please try again.';
    }
  }
}

