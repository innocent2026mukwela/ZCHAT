import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Talks to the ZCHAT backend /api/users endpoints.
/// In [AppConfig.demoAuth] mode (or when the backend is unreachable), contact
/// checks fall back to a direct Firestore lookup by `phoneNumber`.
class UsersApi {
  static const _serverBase = AppConfig.backendBase;
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
  static Future<List<Map<String, dynamic>>> checkContacts(List<String> phones) async {
    if (phones.isEmpty) return [];

    if (!AppConfig.demoAuth) {
      try {
        final res = await http
            .post(
              Uri.parse('$_baseUrl/check-contacts'),
              headers: await _headers(),
              body: jsonEncode({'phones': phones}),
            )
            .timeout(const Duration(seconds: 20));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          return (json['users'] as List? ?? []).cast<Map<String, dynamic>>();
        }
      } catch (_) {
        // Fall through to Firestore so demos/offline still work.
      }
    }

    return _checkContactsFirestore(phones);
  }

  /// Demo / offline path: match contacts against `users.phoneNumber` in Firestore.
  static Future<List<Map<String, dynamic>>> _checkContactsFirestore(
      List<String> phones) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final unique = phones.where((p) => p.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return [];

    final results = <Map<String, dynamic>>[];
    // whereIn allows at most 30 values per query.
    for (var i = 0; i < unique.length; i += 30) {
      final end = (i + 30 < unique.length) ? i + 30 : unique.length;
      final chunk = unique.sublist(i, end);
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          if (doc.id == myUid) continue;
          final data = doc.data();
          results.add({
            'uid': doc.id,
            'phoneNumber': data['phoneNumber'] as String? ?? '',
            'fullName': data['fullName'] as String? ?? data['displayName'] as String? ?? '',
            'role': data['role'] as String? ?? 'student',
            'photoUrl': data['photoUrl'] as String? ?? '',
            'privacyPhoto': data['privacyPhoto'] as String? ?? 'My contacts',
          });
        }
      } catch (_) {
        // Missing index / rules — skip this chunk.
      }
    }
    return results;
  }

  /// Recent demo accounts on this Firebase project (for New Chat when
  /// [AppConfig.demoAuth] is true). Excludes the current user.
  static Future<List<Map<String, dynamic>>> listDemoPeers({int limit = 40}) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('demo', isEqualTo: true)
          .limit(limit)
          .get();
      return snap.docs
          .where((d) => d.id != myUid)
          .map((d) {
            final data = d.data();
            return {
              'uid': d.id,
              'phoneNumber': data['phoneNumber'] as String? ?? '',
              'fullName': data['fullName'] as String? ?? data['displayName'] as String? ?? 'User',
              'role': data['role'] as String? ?? 'student',
              'photoUrl': data['photoUrl'] as String? ?? '',
              'privacyPhoto': data['privacyPhoto'] as String? ?? 'My contacts',
            };
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Client-side search over Firestore users by name or phone prefix.
  /// Intended for demo mode when the contact-check backend is unavailable.
  static Future<List<Map<String, dynamic>>> searchUsersLocal(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      Query<Map<String, dynamic>> ref = FirebaseFirestore.instance.collection('users');
      if (AppConfig.demoAuth) {
        ref = ref.where('demo', isEqualTo: true);
      }
      final snap = await ref.limit(80).get();
      return snap.docs
          .where((d) => d.id != myUid)
          .map((d) {
            final data = d.data();
            return {
              'uid': d.id,
              'phoneNumber': data['phoneNumber'] as String? ?? '',
              'fullName': data['fullName'] as String? ?? data['displayName'] as String? ?? '',
              'role': data['role'] as String? ?? 'student',
              'photoUrl': data['photoUrl'] as String? ?? '',
              'privacyPhoto': data['privacyPhoto'] as String? ?? 'My contacts',
            };
          })
          .where((u) {
            final name = (u['fullName'] as String).toLowerCase();
            final phone = (u['phoneNumber'] as String).toLowerCase();
            return name.contains(q) || phone.contains(q);
          })
          .toList();
    } catch (_) {
      return [];
    }
  }
}
