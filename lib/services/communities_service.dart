import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_service.dart';

/// Communities — a University → School → Program umbrella that groups an
/// Announcements channel (admins-only) with linked course group chats.
///
/// `communities/{id}`: { name, description, icon, university, school, program,
///   adminUids[], memberUids[], announcementChatId, groupChatIds[], createdAt }
class CommunitiesService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static String get _uid => _auth.currentUser!.uid;
  static final _col = _db.collection('communities');

  // ── Create ───────────────────────────────────────────────────────────────
  static Future<String> createCommunity({
    required String name,
    String description = '',
    String icon = '🏛️',
    String university = '',
    String school = '',
    String program = '',
  }) async {
    // Announcement channel: a group chat locked to admins-only.
    final announcementId = await ChatService.createGroupChat('$name · Announcements', const []);
    await ChatService.setGroupSendPolicy(announcementId, true);

    final ref = _col.doc();
    await ref.set({
      'id':               ref.id,
      'name':             name,
      'description':      description,
      'icon':             icon,
      'university':       university,
      'school':           school,
      'program':          program,
      'adminUids':        [_uid],
      'memberUids':       [_uid],
      'announcementChatId': announcementId,
      'groupChatIds':     <String>[],
      'createdBy':        _uid,
      'createdAt':        FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // ── Streams ──────────────────────────────────────────────────────────────
  static Stream<List<Map<String, dynamic>>> myCommunitiesStream() {
    return _col.where('memberUids', arrayContains: _uid).snapshots().map(
        (s) => s.docs.map((d) => {...d.data(), 'id': d.id}).toList());
  }

  /// Browse communities (optionally for a university), excluding ones already joined.
  static Stream<List<Map<String, dynamic>>> browseStream({String? university}) {
    Query<Map<String, dynamic>> q = _col;
    if (university != null && university.isNotEmpty) {
      q = q.where('university', isEqualTo: university);
    }
    return q.snapshots().map((s) => s.docs
        .map((d) => {...d.data(), 'id': d.id})
        .where((c) => !List<String>.from(c['memberUids'] as List? ?? []).contains(_uid))
        .toList());
  }

  static Future<Map<String, dynamic>?> get(String id) async {
    final d = await _col.doc(id).get();
    return d.exists ? {...d.data()!, 'id': d.id} : null;
  }

  // ── Membership ─────────────────────────────────────────────────────────────
  static Future<void> join(String communityId) async {
    final c = await get(communityId);
    if (c == null) return;
    await _col.doc(communityId).update({'memberUids': FieldValue.arrayUnion([_uid])});
    // Join the announcement channel so the member receives announcements.
    final annId = c['announcementChatId'] as String?;
    if (annId != null && annId.isNotEmpty) await _joinChat(annId);
  }

  static Future<void> leave(String communityId) async {
    final c = await get(communityId);
    await _col.doc(communityId).update({
      'memberUids': FieldValue.arrayRemove([_uid]),
      'adminUids':  FieldValue.arrayRemove([_uid]),
    });
    final annId = c?['announcementChatId'] as String?;
    if (annId != null && annId.isNotEmpty) await ChatService.leaveGroup(annId);
  }

  static bool isMember(Map<String, dynamic> c) =>
      List<String>.from(c['memberUids'] as List? ?? []).contains(_uid);
  static bool isAdmin(Map<String, dynamic> c) =>
      List<String>.from(c['adminUids'] as List? ?? []).contains(_uid);

  // ── Linked group chats ─────────────────────────────────────────────────────
  /// Admin links an existing group chat into the community.
  static Future<void> linkGroup(String communityId, String chatId) async {
    await _col.doc(communityId).update({'groupChatIds': FieldValue.arrayUnion([chatId])});
  }

  static Future<void> unlinkGroup(String communityId, String chatId) async {
    await _col.doc(communityId).update({'groupChatIds': FieldValue.arrayRemove([chatId])});
  }

  /// The linked group chats (id + name + type) for display.
  static Future<List<Map<String, dynamic>>> groups(Map<String, dynamic> community) async {
    final ids = List<String>.from(community['groupChatIds'] as List? ?? []);
    final out = <Map<String, dynamic>>[];
    for (final id in ids) {
      final d = await _db.collection('chats').doc(id).get();
      if (d.exists) out.add({...d.data()!, 'id': d.id});
    }
    return out;
  }

  /// Public self-join for a linked group chat (course group).
  static Future<void> joinGroupChat(String chatId) => _joinChat(chatId);

  // Add the current user to a chat's member fields (self-join).
  static Future<void> _joinChat(String chatId) async {
    try {
      final me = await _db.collection('users').doc(_uid).get();
      final name = (me.data()?['fullName'] as String?) ?? (me.data()?['displayName'] as String?) ?? 'Member';
      await _db.collection('chats').doc(chatId).update({
        'members':          FieldValue.arrayUnion([_uid]),
        'memberUids':       FieldValue.arrayUnion([_uid]),
        'memberNames.$_uid': name,
        'unreadCount.$_uid': 0,
        'archived.$_uid':    false,
      });
    } catch (_) {}
  }
}
