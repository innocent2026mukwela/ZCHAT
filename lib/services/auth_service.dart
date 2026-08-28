import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles authentication via the ZCHAT backend's OTP endpoints, bridging
/// into Firebase Auth with a custom token.
/// 10.0.2.2 = Android emulator loopback to host machine.
/// For a physical device on the same Wi-Fi, use your machine's LAN IP.
class AuthService {
  static const _baseUrl = 'http://172.20.10.14:5000/api/auth';

  static final _auth = FirebaseAuth.instance;
  static final _db   = FirebaseFirestore.instance;

  // ── Current user ──────────────────────────────────────────────────────────

  static User? get currentUser => _auth.currentUser;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Send OTP ──────────────────────────────────────────────────────────────

  static Future<void> sendOtp(String phoneNumber) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/send-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phoneNumber': phoneNumber}),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> verifyOtp(
      String phoneNumber, String otp) async {
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

    return {
      'uid': _auth.currentUser!.uid,
      'needsProfile': json['needsProfile'],
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
