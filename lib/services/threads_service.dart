import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/storage_errors.dart';
import 'ai_service.dart';
import 'media_storage_service.dart';

class ThreadsService {
  static final _db  = FirebaseFirestore.instance;
  static final _col = _db.collection('threads');
  static User get _me => FirebaseAuth.instance.currentUser!;

  // ── Notifications ───────────────────────────────────────────────────────────
  static Future<String> _myName() async {
    try {
      final d = await _db.collection('users').doc(_me.uid).get();
      final n = (d.data()?['fullName'] as String?)?.trim();
      return (n != null && n.isNotEmpty) ? n : (_me.displayName ?? 'Someone');
    } catch (_) { return _me.displayName ?? 'Someone'; }
  }

  /// Fire-and-forget push to a post's author (never notifies yourself).
  static Future<void> _notifyAuthor(String postId, {required String body, required String type}) async {
    try {
      final snap = await _col.doc(postId).get();
      final authorUid = snap.data()?['authorUid'] as String?;
      if (authorUid == null || authorUid.isEmpty || authorUid == _me.uid) return;
      final myName = await _myName();
      AiService.sendNotification(
        recipientUid: authorUid, title: myName, body: body,
        data: {'type': type, 'postId': postId},
      ).catchError((_) {});
    } catch (_) {}
  }

  // ── Author freshness cache ─────────────────────────────────────────────────
  // Posts denormalize authorName/authorPhotoUrl at post time, so a profile edit
  // leaves old posts showing stale name/photo. Refresh from users/{uid} with a
  // short TTL to keep reads low. (A Cloud Function fan-out would scale better —
  // see IMPROVEMENTS #8.)
  static final Map<String, Map<String, String>> _authorCache   = {};
  static final Map<String, DateTime>             _authorCacheAt = {};
  static const Duration _authorTtl = Duration(minutes: 5);

  static Future<List<Map<String, dynamic>>> _withFreshAuthors(
      List<Map<String, dynamic>> posts) async {
    final now = DateTime.now();
    final stale = <String>{};
    for (final p in posts) {
      // Keep denormalized names on one-time sample posts (rules force authorUid
      // to the signed-in user; display names are varied on the post itself).
      if (p['sampleSeed'] == true) continue;
      final uid = p['authorUid'] as String?;
      if (uid == null || uid.isEmpty) continue;
      final at = _authorCacheAt[uid];
      if (at == null || now.difference(at) > _authorTtl) stale.add(uid);
    }
    await Future.wait(stale.map((uid) async {
      try {
        final d = (await _db.collection('users').doc(uid).get()).data() ?? {};
        final name = ((d['fullName'] as String?)?.trim().isNotEmpty ?? false)
            ? d['fullName'] as String
            : (d['displayName'] as String? ?? d['name'] as String? ?? '');
        _authorCache[uid]   = {'name': name, 'photo': (d['photoUrl'] ?? d['photoURL'] ?? '') as String};
        _authorCacheAt[uid] = now;
      } catch (_) {}
    }));
    for (final p in posts) {
      if (p['sampleSeed'] == true) continue;
      final fresh = _authorCache[p['authorUid'] as String? ?? ''];
      if (fresh == null) continue;
      if ((fresh['name'] ?? '').isNotEmpty) p['authorName'] = fresh['name'];
      p['authorPhotoUrl'] = fresh['photo'];
    }
    return posts;
  }

  // ── Feed streams ─────────────────────────────────────────────────────────

  /// Public "For You" feed — all posts, newest first
  static Stream<List<Map<String, dynamic>>> forYouStream() =>
      _col.orderBy('createdAt', descending: true).limit(60).snapshots().asyncMap(
        (s) => _withFreshAuthors(
            s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList()));

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
        .asyncMap((s) => _withFreshAuthors(
            s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList()));
  }

  // ── Follow system ─────────────────────────────────────────────────────────

  static Future<void> followUser(String targetUid, String targetName) async {
    final me = _me;
    final myDoc  = await _db.collection('users').doc(me.uid).get();
    final myName = ((myDoc.data()?['fullName'] as String?)?.trim().isNotEmpty ?? false)
        ? myDoc.data()!['fullName'] as String
        : (me.displayName ?? 'User');
    final batch = _db.batch();
    // Add to my following
    batch.set(
      _db.collection('users').doc(me.uid).collection('following').doc(targetUid),
      {'name': targetName, 'followedAt': FieldValue.serverTimestamp()},
    );
    // Add to their followers
    batch.set(
      _db.collection('users').doc(targetUid).collection('followers').doc(me.uid),
      {'name': myName, 'followedAt': FieldValue.serverTimestamp()},
    );
    await batch.commit();
    if (targetUid != me.uid) {
      AiService.sendNotification(
        recipientUid: targetUid, title: myName, body: 'started following you',
        data: {'type': 'feed_follow', 'uid': me.uid},
      ).catchError((_) {});
    }
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

  static Future<void> createPost(String content, {String? imageUrl}) async {
    final user = _me;
    // Custom-token sign-in leaves displayName null — read the real name from the
    // Firestore profile (same doc we already need for role + photo).
    final userDoc  = await _db.collection('users').doc(user.uid).get();
    final data     = userDoc.data() ?? {};
    final name     = ((data['fullName'] as String?)?.trim().isNotEmpty ?? false)
        ? data['fullName'] as String
        : (user.displayName ?? 'User');
    final role     = data['role']     as String? ?? 'student';
    final photoUrl = data['photoUrl'] as String? ?? '';

    await _col.add({
      'authorUid':      user.uid,
      'authorName':     name,
      'authorHandle':   '@${name.toLowerCase().replaceAll(' ', '.')}',
      'authorRole':     role,
      'authorPhotoUrl': photoUrl,
      'avatarInitials': _initials(name),
      'avatarColorVal': _colorForUid(user.uid),
      'content':        content,
      'imageUrl':       imageUrl ?? '',
      'hashtags':       extractHashtags(content),
      'likes':          0,
      'replies':        0,
      'reposts':        0,
      'likedBy':        [],
      'repostedBy':     [],
      'isVerified':     role == 'lecturer',
      'createdAt':      FieldValue.serverTimestamp(),
    });
  }

  /// Uploads a post image to Supabase Storage and returns its public URL.
  static Future<String> uploadPostImage(File file) async {
    final ext  = file.path.split('.').last;
    final path = 'thread_images/${_me.uid}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      return await MediaStorageService.uploadBytes(
        bytes: await file.readAsBytes(),
        path: path,
      );
    } catch (e) {
      throw Exception(friendlyStorageError(e));
    }
  }

  static Future<void> deletePost(String postId) async {
    await _col.doc(postId).delete();
  }

  /// Records a report against a post for later moderation review.
  static Future<void> reportPost(String postId, String authorUid) async {
    await _db.collection('reports').add({
      'postId':       postId,
      'reportedUid':  authorUid,
      'reportedBy':   _me.uid,
      'createdAt':    FieldValue.serverTimestamp(),
    });
  }

  static Future<void> toggleLike(String postId, bool isLiked) async {
    final uid = _me.uid;
    await _col.doc(postId).update({
      'likedBy': isLiked ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid]),
      'likes':   FieldValue.increment(isLiked ? -1 : 1),
    });
    if (!isLiked) _notifyAuthor(postId, body: 'liked your post', type: 'feed_like');
  }

  static Future<void> toggleRepost(String postId, bool isReposted) async {
    final uid = _me.uid;
    await _col.doc(postId).update({
      'repostedBy': isReposted ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid]),
      'reposts':    FieldValue.increment(isReposted ? -1 : 1),
    });
    if (!isReposted) _notifyAuthor(postId, body: 'reposted your post', type: 'feed_repost');
  }

  // ── Replies ───────────────────────────────────────────────────────────────

  static Future<void> addReply(String postId, String text) async {
    final user = _me;
    final userDoc  = await _db.collection('users').doc(user.uid).get();
    final data     = userDoc.data() ?? {};
    final name     = ((data['fullName'] as String?)?.trim().isNotEmpty ?? false)
        ? data['fullName'] as String
        : (user.displayName ?? 'User');
    final role     = data['role']     as String? ?? 'student';
    final photoUrl = data['photoUrl'] as String? ?? '';

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
    final preview = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    _notifyAuthor(postId, body: 'replied: $preview', type: 'feed_reply');
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

  /// A user's own posts, newest first (sorted client-side to avoid needing a
  /// composite index on authorUid + createdAt).
  static Stream<List<Map<String, dynamic>>> userPostsStream(String uid) =>
      _col.where('authorUid', isEqualTo: uid).limit(60).snapshots().map((s) {
        final list = s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
        list.sort((a, b) {
          final at = (a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final bt = (b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        });
        return list;
      });

  static Future<int> getPostCount(String uid) async {
    final agg = await _col.where('authorUid', isEqualTo: uid).count().get();
    return agg.count ?? 0;
  }

  // ── Hashtags ────────────────────────────────────────────────────────────────

  static List<String> extractHashtags(String content) {
    final matches = RegExp(r'#(\w{1,50})').allMatches(content);
    return matches.map((m) => m.group(1)!.toLowerCase()).toSet().take(10).toList();
  }

  // ── Search ────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim().toLowerCase().replaceFirst('@', '');
    if (q.isEmpty) return [];
    final snap = await _db.collection('users').limit(200).get();
    return snap.docs
        .map((d) => <String, dynamic>{'uid': d.id, ...d.data()})
        .where((u) => u['uid'] != _me.uid &&
            (u['fullName'] as String? ?? '').toLowerCase().contains(q))
        .take(30).toList();
  }

  static Future<List<Map<String, dynamic>>> searchPosts(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    if (q.startsWith('#')) {
      final snap = await _col.where('hashtags', arrayContains: q.substring(1)).limit(50).get();
      final list = snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
      _sortByTimeDesc(list);
      return list;
    }
    final snap = await _col.orderBy('createdAt', descending: true).limit(120).get();
    return snap.docs
        .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
        .where((p) => (p['content'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  static Stream<List<Map<String, dynamic>>> hashtagStream(String tag) =>
      _col.where('hashtags', arrayContains: tag.toLowerCase()).limit(50).snapshots().map((s) {
        final list = s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
        _sortByTimeDesc(list);
        return list;
      });

  // ── Bookmarks ─────────────────────────────────────────────────────────────

  static Future<void> toggleBookmark(String postId, bool isBookmarked) async {
    final ref = _db.collection('users').doc(_me.uid).collection('bookmarks').doc(postId);
    isBookmarked
        ? await ref.delete()
        : await ref.set({'postId': postId, 'savedAt': FieldValue.serverTimestamp()});
  }

  static Stream<Set<String>> bookmarkedIdsStream() =>
      _db.collection('users').doc(_me.uid).collection('bookmarks').snapshots()
          .map((s) => s.docs.map((d) => d.id).toSet());

  /// Hydrates saved bookmarks by fetching the live post docs so counts stay fresh.
  static Stream<List<Map<String, dynamic>>> bookmarksStream() =>
      _db.collection('users').doc(_me.uid).collection('bookmarks')
          .orderBy('savedAt', descending: true).limit(60).snapshots().asyncMap((s) async {
        final out = <Map<String, dynamic>>[];
        for (final d in s.docs) {
          final post = await _col.doc(d.id).get();
          if (post.exists) out.add(<String, dynamic>{'id': post.id, ...post.data()!});
        }
        return out;
      });

  // ── Block / Report user ─────────────────────────────────────────────────────

  static Future<void> blockUser(String uid) async {
    await _db.collection('users').doc(_me.uid).collection('blocked').doc(uid)
        .set({'blockedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> unblockUser(String uid) async {
    await _db.collection('users').doc(_me.uid).collection('blocked').doc(uid).delete();
  }

  static Stream<Set<String>> blockedIdsStream() =>
      _db.collection('users').doc(_me.uid).collection('blocked').snapshots()
          .map((s) => s.docs.map((d) => d.id).toSet());

  static Future<void> reportUser(String uid) async {
    await _db.collection('reports').add({
      'type': 'user', 'reportedUid': uid, 'reportedBy': _me.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Profile: replies & reposts ──────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> userRepliesStream(String uid) =>
      _db.collectionGroup('replies').where('authorUid', isEqualTo: uid).limit(50).snapshots().map((s) {
        final list = s.docs.map((d) => <String, dynamic>{
          'id': d.id, 'postId': d.reference.parent.parent?.id, ...d.data()}).toList();
        _sortByTimeDesc(list);
        return list;
      });

  static Stream<List<Map<String, dynamic>>> userRepostsStream(String uid) =>
      _col.where('repostedBy', arrayContains: uid).limit(50).snapshots().map((s) {
        final list = s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
        _sortByTimeDesc(list);
        return list;
      });

  static void _sortByTimeDesc(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final at = (a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final bt = (b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
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
