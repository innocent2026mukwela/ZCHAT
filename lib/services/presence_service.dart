import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PresenceService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String get _myUid => _auth.currentUser?.uid ?? '';

  static void setOnline() {
    if (_myUid.isEmpty) return;
    _db.collection('users').doc(_myUid).update({
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    }).catchError((_) {});
  }

  static void setOffline() {
    if (_myUid.isEmpty) return;
    _db.collection('users').doc(_myUid).update({
      'isOnline': false,
      'lastSeen': FieldValue.serverTimestamp(),
    }).catchError((_) {});
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> stream(String uid) =>
      _db.collection('users').doc(uid).snapshots();

  static String formatLastSeen(Timestamp? ts) {
    if (ts == null) return 'last seen a while ago';
    final dt   = ts.toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'last seen just now';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return 'last seen ${diff.inHours}h ago';
    if (diff.inDays    == 1) return 'last seen yesterday';
    return 'last seen ${dt.day}/${dt.month}';
  }
}
