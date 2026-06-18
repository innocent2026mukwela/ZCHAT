import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BroadcastService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static String get _uid => _auth.currentUser!.uid;

  static Stream<List<Map<String, dynamic>>> myChannelsStream() {
    return _db
        .collection('broadcasts')
        .where('adminUid', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  static Stream<List<Map<String, dynamic>>> subscribedChannelsStream() {
    return _db
        .collection('broadcasts')
        .where('subscribers', arrayContains: _uid)
        .orderBy('lastTime', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  static Future<String> createChannel(String name, String description) async {
    final me = _auth.currentUser!;
    final doc = await _db.collection('broadcasts').add({
      'name':        name,
      'description': description,
      'adminUid':    _uid,
      'adminName':   me.displayName ?? 'Unknown',
      'subscribers': [],
      'lastMessage': '',
      'lastTime':    FieldValue.serverTimestamp(),
      'createdAt':   FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> subscribe(String channelId) async {
    await _db.collection('broadcasts').doc(channelId).update({
      'subscribers': FieldValue.arrayUnion([_uid]),
    });
  }

  static Future<void> unsubscribe(String channelId) async {
    await _db.collection('broadcasts').doc(channelId).update({
      'subscribers': FieldValue.arrayRemove([_uid]),
    });
  }

  static Future<void> sendBroadcast(String channelId, String text) async {
    final me = _auth.currentUser!;
    final msgRef = _db.collection('broadcasts').doc(channelId).collection('messages').doc();
    final batch  = _db.batch();
    batch.set(msgRef, {
      'id':        msgRef.id,
      'text':      text,
      'senderUid': _uid,
      'senderName': me.displayName ?? 'Unknown',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('broadcasts').doc(channelId), {
      'lastMessage': text,
      'lastTime':    FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static Stream<List<Map<String, dynamic>>> messagesStream(String channelId) {
    return _db
        .collection('broadcasts').doc(channelId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  static Stream<List<Map<String, dynamic>>> discoverStream() {
    return _db
        .collection('broadcasts')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
