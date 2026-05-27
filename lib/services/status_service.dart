import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class StatusService {
  static final _db      = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;
  static final _auth    = FirebaseAuth.instance;

  static String get _myUid => _auth.currentUser!.uid;

  // ── Post a status ─────────────────────────────────────────────────────────

  static Future<void> postTextStatus(String text) async {
    final now     = DateTime.now();
    final expires = now.add(const Duration(hours: 24));
    await _db
        .collection('statuses')
        .doc(_myUid)
        .collection('items')
        .add({
      'type':      'text',
      'text':      text,
      'imageUrl':  null,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expires),
      'viewedBy':  [],
    });
  }

  static Future<void> postImageStatus(String filePath, {String? caption}) async {
    final now     = DateTime.now();
    final expires = now.add(const Duration(hours: 24));

    final ref = _storage
        .ref()
        .child('statuses/$_myUid/${now.millisecondsSinceEpoch}.jpg');
    await ref.putFile(File(filePath), SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();

    await _db
        .collection('statuses')
        .doc(_myUid)
        .collection('items')
        .add({
      'type':      'image',
      'text':      caption ?? '',
      'imageUrl':  url,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expires),
      'viewedBy':  [],
    });
  }

  static Future<void> postVideoStatus(String videoUrl, {String? caption}) async {
    final expires = DateTime.now().add(const Duration(hours: 24));
    await _db
        .collection('statuses')
        .doc(_myUid)
        .collection('items')
        .add({
      'type':      'video',
      'text':      caption ?? '',
      'imageUrl':  videoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expires),
      'viewedBy':  [],
    });
  }

  // ── My status items (non-expired) ────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> myStatusStream() {
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 24)));
    return _db
        .collection('statuses')
        .doc(_myUid)
        .collection('items')
        .where('createdAt', isGreaterThan: cutoff)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map((d) => {...d.data(), 'id': d.id}).toList());
  }

  // ── Statuses for a list of UIDs (contacts on ZCHAT) ──────────────────────

  static Future<List<Map<String, dynamic>>> fetchContactStatuses(List<String> uids) async {
    if (uids.isEmpty) return [];
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 24)));
    final List<Map<String, dynamic>> result = [];

    for (final uid in uids) {
      if (uid == _myUid) continue;
      final snap = await _db
          .collection('statuses')
          .doc(uid)
          .collection('items')
          .where('createdAt', isGreaterThan: cutoff)
          .orderBy('createdAt')
          .get();

      if (snap.docs.isEmpty) continue;

      // Fetch user info
      final userDoc = await _db.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};

      // Respect the user's status privacy setting
      final statusPrivacy = userData['statusPrivacy'] as String? ?? 'My contacts';
      if (statusPrivacy == 'Nobody') continue;

      result.add({
        'uid':       uid,
        'name':      userData['fullName'] ?? userData['displayName'] ?? userData['name'] ?? 'Unknown',
        'photoUrl':  userData['photoUrl'] ?? userData['photoURL'] ?? '',
        'phone':     userData['phoneNumber'] ?? userData['phone'] ?? '',
        'items':     snap.docs.map((d) => {...d.data(), 'id': d.id}).toList(),
        'latestAt':  snap.docs.last.data()['createdAt'],
        'hasUnread': snap.docs.any((d) => !((d.data()['viewedBy'] as List?)?.contains(_myUid) ?? false)),
      });
    }

    // Sort: unread first, then by latest
    result.sort((a, b) {
      if (a['hasUnread'] && !b['hasUnread']) return -1;
      if (!a['hasUnread'] && b['hasUnread']) return 1;
      final at = (a['latestAt'] as Timestamp?)?.toDate() ?? DateTime(0);
      final bt = (b['latestAt'] as Timestamp?)?.toDate() ?? DateTime(0);
      return bt.compareTo(at);
    });

    return result;
  }

  // ── Mark a status item as viewed ─────────────────────────────────────────

  static Future<void> markViewed(String ownerUid, String itemId) async {
    await _db
        .collection('statuses')
        .doc(ownerUid)
        .collection('items')
        .doc(itemId)
        .update({'viewedBy': FieldValue.arrayUnion([_myUid])});
  }

  // ── Delete my status item ─────────────────────────────────────────────────

  static Future<void> deleteItem(String itemId) async {
    await _db
        .collection('statuses')
        .doc(_myUid)
        .collection('items')
        .doc(itemId)
        .delete();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)   return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    return 'Yesterday';
  }
}
