import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ThreadsService {
  static final _db  = FirebaseFirestore.instance;
  static final _col = _db.collection('threads');
  static User get _me => FirebaseAuth.instance.currentUser!;

  // ── Feed streams ─────────────────────────────────────────────────────────

  /// Public "For You" feed — all posts, newest first
  static Stream<List<Map<String, dynamic>>> forYouStream() =>
      _col.orderBy('createdAt', descending: true).limit(60).snapshots().map(
        (s) => s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList());

  /// Following feed — posts from users you follow
  static Stream<List<Map<String, dynamic>>> followingStream() async* {
    final uid = _me.uid;
    final followingSnap = await _db
        .collection('users').doc(uid).collection('following').get();
    final uids = followingSnap.docs.map((d) => d.id).toList();
    if (uids.isEmpty) { yield []; return; }
    yield* _col
        .where('authorUid', whereIn: uids.take(30).toList())
        .orderBy('createdAt', descending: true)
        .limit(40)
        .snapshots()
        .map((s) => s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList());
  }

  // ── Follow system ─────────────────────────────────────────────────────────

  static Future<void> followUser(String targetUid, String targetName) async {
    final me = _me;
    final batch = _db.batch();
    // Add to my following
    batch.set(
      _db.collection('users').doc(me.uid).collection('following').doc(targetUid),
      {'name': targetName, 'followedAt': FieldValue.serverTimestamp()},
    );
    // Add to their followers
    batch.set(
      _db.collection('users').doc(targetUid).collection('followers').doc(me.uid),
      {'name': me.displayName ?? 'User', 'followedAt': FieldValue.serverTimestamp()},
    );
    await batch.commit();
  }

  static Future<void> unfollowUser(String targetUid) async {
    final me = _me;
    final batch = _db.batch();
    batch.delete(_db.collection('users').doc(me.uid).collection('following').doc(targetUid));
    batch.delete(_db.collection('users').doc(targetUid).collection('followers').doc(me.uid));
    await batch.commit();
  }

  static Future<bool> isFollowing(String targetUid) async {
    final doc = await _db
        .collection('users').doc(_me.uid).collection('following').doc(targetUid).get();
    return doc.exists;
  }

  static Future<Map<String, int>> getFollowCounts(String uid) async {
    final fs = await _db.collection('users').doc(uid).collection('following').count().get();
    final fr = await _db.collection('users').doc(uid).collection('followers').count().get();
    return {'following': fs.count ?? 0, 'followers': fr.count ?? 0};
  }

  // ── Posts ─────────────────────────────────────────────────────────────────

  static Future<void> createPost(String content) async {
    final user = _me;
    final name = user.displayName ?? 'User';
    // Fetch role from Firestore
    final userDoc = await _db.collection('users').doc(user.uid).get();
    final role     = userDoc.data()?['role']     as String? ?? 'student';
    final photoUrl = userDoc.data()?['photoUrl'] as String? ?? '';

    await _col.add({
      'authorUid':      user.uid,
      'authorName':     name,
      'authorHandle':   '@${name.toLowerCase().replaceAll(' ', '.')}',
      'authorRole':     role,
      'authorPhotoUrl': photoUrl,
      'avatarInitials': _initials(name),
      'avatarColorVal': _colorForUid(user.uid),
      'content':        content,
      'likes':          0,
      'replies':        0,
      'reposts':        0,
      'likedBy':        [],
      'repostedBy':     [],
      'isVerified':     role == 'lecturer',
      'createdAt':      FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deletePost(String postId) async {
    await _col.doc(postId).delete();
  }

  static Future<void> toggleLike(String postId, bool isLiked) async {
    final uid = _me.uid;
    await _col.doc(postId).update({
      'likedBy': isLiked ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid]),
      'likes':   FieldValue.increment(isLiked ? -1 : 1),
    });
  }

  static Future<void> toggleRepost(String postId, bool isReposted) async {
    final uid = _me.uid;
    await _col.doc(postId).update({
      'repostedBy': isReposted ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid]),
      'reposts':    FieldValue.increment(isReposted ? -1 : 1),
    });
  }

  // ── Replies ───────────────────────────────────────────────────────────────

  static Future<void> addReply(String postId, String text) async {
    final user = _me;
    final name = user.displayName ?? 'User';
    final userDoc  = await _db.collection('users').doc(user.uid).get();
    final role     = userDoc.data()?['role']     as String? ?? 'student';
    final photoUrl = userDoc.data()?['photoUrl'] as String? ?? '';

    final batch    = _db.batch();
    final postRef  = _col.doc(postId);
    final replyRef = _col.doc(postId).collection('replies').doc();

    batch.update(postRef, {'replies': FieldValue.increment(1)});
    batch.set(replyRef, {
      'authorUid':      user.uid,
      'authorName':     name,
      'authorHandle':   '@${name.toLowerCase().replaceAll(' ', '.')}',
      'authorRole':     role,
      'authorPhotoUrl': photoUrl,
      'avatarInitials': _initials(name),
      'avatarColorVal': _colorForUid(user.uid),
      'text':           text,
      'likes':          0,
      'likedBy':        [],
      'createdAt':      FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  static Future<void> toggleReplyLike(String postId, String replyId, bool isLiked) async {
    final uid = _me.uid;
    await _col.doc(postId).collection('replies').doc(replyId).update({
      'likedBy': isLiked ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid]),
      'likes':   FieldValue.increment(isLiked ? -1 : 1),
    });
  }

  static Stream<List<Map<String, dynamic>>> repliesStream(String postId) =>
      _col.doc(postId).collection('replies').orderBy('createdAt').snapshots().map(
        (s) => s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList());

  // ── User profile cache ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> fetchAuthorProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  static String initials(String name) => _initials(name);

  static int _colorForUid(String uid) {
    const colors = [
      Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFF2E7D32),
      Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
      Color(0xFF4527A0), Color(0xFF283593),
    ];
    final idx = uid.codeUnits.fold(0, (acc, c) => acc + c) % colors.length;
    return colors[idx].toARGB32();
  }

  static int colorForUid(String uid) => _colorForUid(uid);

  static String timeAgo(Timestamp? ts) {
    if (ts == null) return 'now';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inSeconds < 60)  return '${diff.inSeconds}s';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m';
    if (diff.inHours < 24)    return '${diff.inHours}h';
    if (diff.inDays < 7)      return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }
}
