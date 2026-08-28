import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Talks to the ZCHAT backend /api/users endpoints.
/// Change [_serverBase] to your production server URL when deploying.
class UsersApi {
  static const _serverBase = 'http://172.20.10.14:5000';
  static const _baseUrl    = '$_serverBase/api/users';

  static Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Returns the registered ZCHAT users among [phones] (E.164 format).
  /// Each entry: { uid, phoneNumber, fullName, role, photoUrl }.
  /// Unlike a direct Firestore query, this only reveals membership for numbers
  /// the caller already has, and never exposes the full user table.
  static Future<List<Map<String, dynamic>>> checkContacts(List<String> phones) async {
    if (phones.isEmpty) return [];
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/check-contacts'),
            headers: await _headers(),
            body: jsonEncode({'phones': phones}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return (json['users'] as List? ?? []).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
