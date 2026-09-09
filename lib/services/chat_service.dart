import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'ai_service.dart';
import 'encryption_service.dart';

class ChatService {
  static final _db      = FirebaseFirestore.instance;
  static final _auth    = FirebaseAuth.instance;
  static final _storage = FirebaseStorage.instance;

  static String get _myUid => _auth.currentUser!.uid;

  // Current user's display name. Custom-token sign-in leaves
  // FirebaseAuth.displayName null, so the real name lives in Firestore. Cached
  // per-uid so account switches don't return a stale name.
  static String? _cachedMyName;
  static String? _cachedMyNameUid;
  static Future<String> _myName() async {
    if (_cachedMyName != null && _cachedMyName!.isNotEmpty && _cachedMyNameUid == _myUid) {
      return _cachedMyName!;
    }
    try {
      final doc = await _db.collection('users').doc(_myUid).get();
      _cachedMyName = (doc.data()?['fullName'] as String?)?.trim().isNotEmpty == true
          ? doc.data()!['fullName'] as String
          : (_auth.currentUser?.displayName ?? 'Unknown');
    } catch (_) {
      _cachedMyName = _auth.currentUser?.displayName ?? 'Unknown';
    }
    _cachedMyNameUid = _myUid;
    return _cachedMyName!;
  }

  // ── Chat creation ────────────────────────────────────────────────────────

  static Future<String> getOrCreateChat(String otherUid) async {
    final ids = [_myUid, otherUid]..sort();
    final chatId = ids.join('_');

    final ref = _db.collection('chats').doc(chatId);
    final snap = await ref.get();
    if (!snap.exists) {
      final myDoc    = await _db.collection('users').doc(_myUid).get();
      final otherDoc = await _db.collection('users').doc(otherUid).get();
      if (!otherDoc.exists) throw Exception('This user no longer has an active account.');
      final myName    = myDoc.data()?['fullName']    as String?
                     ?? myDoc.data()?['displayName'] as String? ?? 'Unknown';
      final otherName = otherDoc.data()?['fullName']    as String?
                     ?? otherDoc.data()?['displayName'] as String? ?? 'Unknown';

      await ref.set({
        'id': chatId,
        'type': 'direct',
        'members': ids,
        'memberUids': ids,
        'memberNames': {_myUid: myName, otherUid: otherName},
        'name': '',
        'lastMessage': '',
        'lastSenderUid': '',
        'lastTime': FieldValue.serverTimestamp(),
        'unreadCount': {_myUid: 0, otherUid: 0},
        'pinned': false,
        'archived': {_myUid: false, otherUid: false},
      });
    }
    return chatId;
  }

  static Future<String> createGroupChat(
    String name,
    List<String> memberUids, {
    String photoUrl = '',
  }) async {
    // Respect each invitee's "Groups" privacy setting (drop anyone set to 'Nobody').
    final allowed = <String>[];
    for (final uid in memberUids) {
      if (await canAddToGroup(uid)) allowed.add(uid);
    }
    final ref = _db.collection('chats').doc();
    final allMembers = [...allowed, _myUid];
    await ref.set({
      'id': ref.id,
      'type': 'group',
      'members': allMembers,
      'memberUids': allMembers,
      'name': name,
      'photoUrl': photoUrl,
      'adminUids': [_myUid],
      'lastMessage': '',
      'lastSenderUid': '',
      'lastTime': FieldValue.serverTimestamp(),
      'unreadCount': {for (final uid in allMembers) uid: 0},
      'pinned': false,
      'archived': {for (final uid in allMembers) uid: false},
    });
    return ref.id;
  }

  static Future<void> updateGroupName(String chatId, String name) async {
    await _db.collection('chats').doc(chatId).update({'name': name});
  }

  // ── Messaging ────────────────────────────────────────────────────────────

  static Future<void> sendMessage(
    String chatId,
    String text, {
    String? replyToId,
    String? replyToText,
    String? replyToSenderName,
    String type = 'text',
    String? imageUrl,
    String? audioUrl,
    String? voiceDuration,
    bool viewOnce = false,
    List<String>? mentions,
  }) async {
    final msgRef  = _db.collection('chats').doc(chatId).collection('messages').doc();
    final chatRef = _db.collection('chats').doc(chatId);

    final batch = _db.batch();

    final senderName = await _myName();

    final encryptedText = await EncryptionService.encrypt(chatId, text);

    batch.set(msgRef, {
      'id':            msgRef.id,
      'chatId':        chatId,
      'senderUid':     _myUid,
      'senderName':    senderName,
      'text':          encryptedText,
      'type':          type,
      'imageUrl':      imageUrl,
      'audioUrl':      audioUrl,
      'voiceDuration': voiceDuration,
      'reactions':     {},
      'readBy':        [_myUid],
      'mentions':      mentions ?? [],
      'createdAt':     FieldValue.serverTimestamp(),
      'replyToId':         replyToId,
      'replyToText':       replyToText,
      'replyToSenderName': replyToSenderName,
      'deleted':       false,
      'edited':        false,
      'viewOnce':      viewOnce,
      'viewOnceViewedBy': [],
    });

    final chatSnap = await chatRef.get();
    if (chatSnap.exists) {
      final members = List<String>.from(chatSnap['members'] as List);
      final unreadUpdate = <String, dynamic>{};
      for (final uid in members) {
        if (uid != _myUid) unreadUpdate['unreadCount.$uid'] = FieldValue.increment(1);
      }
      // Flag mentioned members so the chat list can show an @ badge.
      final mentionUpdate = <String, dynamic>{};
      for (final uid in (mentions ?? const [])) {
        if (uid != _myUid && members.contains(uid)) mentionUpdate['mentioned.$uid'] = true;
      }
      final preview = type == 'image' ? '📷 Photo' : text;
      batch.update(chatRef, {
        'lastMessage':   preview,
        'lastSenderUid': _myUid,
        'lastTime':      FieldValue.serverTimestamp(),
        ...unreadUpdate,
        ...mentionUpdate,
      });
    }

    await batch.commit();

    if (chatSnap.exists) {
      final members = List<String>.from(chatSnap['members'] as List);
      for (final uid in members) {
        if (uid != _myUid) {
          AiService.sendNotification(
            recipientUid: uid,
            title: senderName,
            body: type == 'image' ? '📷 Photo' : text,
            data: {'type': 'new_message', 'chatId': chatId},
          ).catchError((_) {});
        }
      }
    }
  }

  // ── Polls ──────────────────────────────────────────────────────────────────

  static Future<void> sendPoll(String chatId, String question, List<String> options,
      {bool multi = false}) async {
    final msgRef  = _db.collection('chats').doc(chatId).collection('messages').doc();
    final chatRef = _db.collection('chats').doc(chatId);
    final senderName = await _myName();
    final batch = _db.batch();
    batch.set(msgRef, {
      'id': msgRef.id, 'chatId': chatId, 'senderUid': _myUid, 'senderName': senderName,
      'text': '', 'type': 'poll',
      'poll': {
        'question': question,
        'multi':    multi,
        'options':  options.map((o) => {'text': o, 'voters': <String>[]}).toList(),
      },
      'reactions': {}, 'readBy': [_myUid], 'createdAt': FieldValue.serverTimestamp(),
      'deleted': false, 'edited': false,
    });
    await _finishSpecialMessage(batch, chatRef, '📊 $question', senderName, chatId,
        {'type': 'new_message', 'chatId': chatId});
  }

  static Future<void> votePoll(String chatId, String msgId, int optionIndex) async {
    final ref  = _db.collection('chats').doc(chatId).collection('messages').doc(msgId);
    final snap = await ref.get();
    final poll = Map<String, dynamic>.from(snap.data()?['poll'] as Map? ?? {});
    if (poll.isEmpty) return;
    final multi   = poll['multi'] == true;
    final options = List<Map<String, dynamic>>.from(
        (poll['options'] as List? ?? []).map((o) => Map<String, dynamic>.from(o as Map)));
    for (var i = 0; i < options.length; i++) {
      final voters = List<String>.from(options[i]['voters'] as List? ?? []);
      if (i == optionIndex) {
        voters.contains(_myUid) ? voters.remove(_myUid) : voters.add(_myUid);
      } else if (!multi) {
        voters.remove(_myUid); // single-choice: leaving other options
      }
      options[i]['voters'] = voters;
    }
    poll['options'] = options;
    await ref.update({'poll': poll});
  }

  // ── Location ───────────────────────────────────────────────────────────────

  static Future<void> sendLocation(String chatId, double lat, double lng) async {
    final msgRef  = _db.collection('chats').doc(chatId).collection('messages').doc();
    final chatRef = _db.collection('chats').doc(chatId);
    final senderName = await _myName();
    final batch = _db.batch();
    batch.set(msgRef, {
      'id': msgRef.id, 'chatId': chatId, 'senderUid': _myUid, 'senderName': senderName,
      'text': '', 'type': 'location',
      'location': {'lat': lat, 'lng': lng},
      'reactions': {}, 'readBy': [_myUid], 'createdAt': FieldValue.serverTimestamp(),
      'deleted': false, 'edited': false,
    });
    await _finishSpecialMessage(batch, chatRef, '📍 Location', senderName, chatId,
        {'type': 'new_message', 'chatId': chatId});
  }

  // ── Events ─────────────────────────────────────────────────────────────────

  static Future<void> sendEvent(String chatId, {
    required String title,
    required DateTime dateTime,
    String location = '',
    String description = '',
    String? callRoomId,
  }) async {
    final msgRef  = _db.collection('chats').doc(chatId).collection('messages').doc();
    final chatRef = _db.collection('chats').doc(chatId);
    final senderName = await _myName();
    final batch = _db.batch();
    batch.set(msgRef, {
      'id': msgRef.id, 'chatId': chatId, 'senderUid': _myUid, 'senderName': senderName,
      'text': '', 'type': 'event',
      'event': {
        'title':       title,
        'dateTime':    Timestamp.fromDate(dateTime),
        'location':    location,
        'description': description,
        'callRoomId':  callRoomId,
        'rsvp':        {_myUid: 'going'}, // creator is going by default
      },
      'reactions': {}, 'readBy': [_myUid], 'createdAt': FieldValue.serverTimestamp(),
      'deleted': false, 'edited': false,
    });
    await _finishSpecialMessage(batch, chatRef, '📅 $title', senderName, chatId,
        {'type': 'new_message', 'chatId': chatId});
  }

  static Future<void> rsvpEvent(String chatId, String msgId, String response) async {
    // response: 'going' | 'maybe' | 'no'
    await _db.collection('chats').doc(chatId).collection('messages').doc(msgId)
        .update({'event.rsvp.$_myUid': response});
  }

  // Shared tail for structured messages: bump chat preview + unread, then notify.
  static Future<void> _finishSpecialMessage(WriteBatch batch, DocumentReference chatRef,
      String preview, String senderName, String chatId, Map<String, String> notifData) async {
    final chatSnap = await chatRef.get();
    List<String> members = [];
    if (chatSnap.exists) {
      members = List<String>.from((chatSnap.data() as Map)['members'] as List? ?? []);
      final unreadUpdate = <String, dynamic>{};
      for (final uid in members) {
        if (uid != _myUid) unreadUpdate['unreadCount.$uid'] = FieldValue.increment(1);
      }
      batch.update(chatRef, {
        'lastMessage': preview, 'lastSenderUid': _myUid,
        'lastTime': FieldValue.serverTimestamp(), ...unreadUpdate,
      });
    }
    await batch.commit();
    for (final uid in members) {
      if (uid != _myUid) {
        AiService.sendNotification(recipientUid: uid, title: senderName, body: preview, data: notifData)
            .catchError((_) {});
      }
    }
  }

  // ── Image upload + send ──────────────────────────────────────────────────

  static Future<void> sendImage(String chatId, File imageFile,
      {String caption = '', bool viewOnce = false}) async {
    final ext  = imageFile.path.split('.').last;
    final path = 'chat_images/$chatId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref  = _storage.ref().child(path);
    await ref.putFile(imageFile);
    final url  = await ref.getDownloadURL();
    await sendMessage(chatId, caption.isNotEmpty ? caption : '📷 Photo',
        type: 'image', imageUrl: url, viewOnce: viewOnce);
  }

  // ── Reactions / delete ───────────────────────────────────────────────────

  static Future<void> toggleReaction(String chatId, String messageId, String emoji) async {
    final ref  = _db.collection('chats').doc(chatId).collection('messages').doc(messageId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final reactions = Map<String, dynamic>.from(snap['reactions'] as Map? ?? {});
    final users     = List<String>.from(reactions[emoji] as List? ?? []);

    if (users.contains(_myUid)) {
      users.remove(_myUid);
    } else {
      users.add(_myUid);
    }

    if (users.isEmpty) {
      reactions.remove(emoji);
    } else {
      reactions[emoji] = users;
    }
    await ref.update({'reactions': reactions});
  }

  static Future<void> deleteMessage(String chatId, String messageId) async {
    await _db
        .collection('chats').doc(chatId)
        .collection('messages').doc(messageId)
        .update({'deleted': true, 'text': 'This message was deleted'});
  }

  static Future<void> deleteForMe(String chatId, String messageId) async {
    await _db
        .collection('users').doc(_myUid)
        .collection('deletedMessages')
        .doc('${chatId}_$messageId')
        .set({'chatId': chatId, 'messageId': messageId, 'deletedAt': FieldValue.serverTimestamp()});
  }

  static Future<Set<String>> getDeletedForMeIds(String chatId) async {
    final snap = await _db
        .collection('users').doc(_myUid)
        .collection('deletedMessages')
        .where('chatId', isEqualTo: chatId)
        .get();
    return snap.docs.map((d) => d.data()['messageId'] as String).toSet();
  }

  // ── Read / unread / pin / archive ────────────────────────────────────────

  static Future<void> markRead(String chatId) async {
    await _db.collection('chats').doc(chatId)
        .update({'unreadCount.$_myUid': 0, 'mentioned.$_myUid': false});

    // Check if this user has read receipts enabled
    try {
      final myDoc = await _db.collection('users').doc(_myUid).get();
      final readReceipts = (myDoc.data()?['readReceipts'] as bool?) ?? true;
      if (!readReceipts) return;
    } catch (_) {}

    // Add myUid to readBy on recent unread messages
    try {
      final snap = await _db
          .collection('chats').doc(chatId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        final readBy = List<String>.from(doc.data()['readBy'] as List? ?? []);
        if (!readBy.contains(_myUid)) {
          batch.update(doc.reference, {'readBy': FieldValue.arrayUnion([_myUid])});
        }
      }
      await batch.commit();

      // Ping other members so their tick marks update while app is in background
      final chatSnap = await _db.collection('chats').doc(chatId).get();
      final memberUids = List<String>.from(
          (chatSnap.data()?['memberUids'] ?? chatSnap.data()?['members']) as List? ?? []);
      for (final uid in memberUids) {
        if (uid == _myUid) continue;
        // Fire-and-forget so opening a chat isn't blocked on network round-trips.
        AiService.sendNotification(
          recipientUid: uid,
          title: '',
          body: '',
          data: {'readReceipt': 'true', 'chatId': chatId},
        ).catchError((_) {});
      }
    } catch (_) {}
  }

  static Future<void> markUnread(String chatId) async {
    await _db.collection('chats').doc(chatId)
        .update({'unreadCount.$_myUid': 1});
  }

  static Future<void> togglePin(String chatId, bool currentlyPinned) async {
    await _db.collection('chats').doc(chatId)
        .update({'pinned': !currentlyPinned});
  }

  static Future<void> toggleArchive(String chatId, bool currentlyArchived) async {
    await _db.collection('chats').doc(chatId)
        .update({'archived.$_myUid': !currentlyArchived});
  }

  static Future<void> deleteChat(String chatId) async {
    await _db.collection('chats').doc(chatId)
        .update({'members': FieldValue.arrayRemove([_myUid])});
  }

  /// Permanently deletes messages older than [ttl] from a chat (disappearing
  /// messages). Removing the doc clears it for every member, which is the
  /// expected behaviour. Batched + capped so a huge backlog can't stall the UI;
  /// call it again (e.g. on next open) to continue clearing.
  static Future<void> purgeExpiredMessages(String chatId, Duration ttl) async {
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(ttl));
    try {
      final snap = await _db
          .collection('chats').doc(chatId).collection('messages')
          .where('createdAt', isLessThan: cutoff)
          .limit(300)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  // ── Edit message ─────────────────────────────────────────────────────────

  static Future<void> editMessage(String chatId, String msgId, String newText) async {
    final encrypted = await EncryptionService.encrypt(chatId, newText);
    await _db.collection('chats').doc(chatId).collection('messages').doc(msgId)
        .update({'text': encrypted, 'edited': true});
  }

  // ── Typing ───────────────────────────────────────────────────────────────

  static Future<void> setTyping(String chatId, bool isTyping) async {
    final ref = _db.collection('chats').doc(chatId).collection('typing').doc(_myUid);
    if (isTyping) {
      await ref.set({'typing': true, 'updatedAt': FieldValue.serverTimestamp()});
    } else {
      ref.delete().catchError((_) {});
    }
  }

  static Stream<bool> typingStream(String chatId, String otherUid) {
    return _db.collection('chats').doc(chatId).collection('typing').doc(otherUid)
        .snapshots().map((s) => (s.data()?['typing'] as bool?) == true);
  }

  // ── Starred messages ──────────────────────────────────────────────────────

  static Future<void> starMessage(String chatId, String msgId, String text, {String chatName = ''}) async {
    await _db.collection('users').doc(_myUid).collection('starred').doc(msgId).set({
      'chatId': chatId, 'msgId': msgId,
      'text': text, 'chatName': chatName, 'starredAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> unstarMessage(String msgId) async {
    await _db.collection('users').doc(_myUid).collection('starred').doc(msgId).delete();
  }

  static Stream<Set<String>> starredStream() {
    return _db.collection('users').doc(_myUid).collection('starred')
        .snapshots().map((s) => s.docs.map((d) => d.id).toSet());
  }

  // ── Block / Unblock ───────────────────────────────────────────────────────

  static Future<void> blockUser(String otherUid) async {
    await _db.collection('users').doc(_myUid).collection('blocked').doc(otherUid)
        .set({'blockedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> unblockUser(String otherUid) async {
    await _db.collection('users').doc(_myUid).collection('blocked').doc(otherUid).delete();
  }

  static Stream<bool> isBlockedStream(String otherUid) {
    return _db.collection('users').doc(_myUid).collection('blocked').doc(otherUid)
        .snapshots().map((s) => s.exists);
  }

  // ── Mute ─────────────────────────────────────────────────────────────────

  static Future<void> muteChat(String chatId, bool mute) async {
    await _db.collection('chats').doc(chatId).update({'muted.$_myUid': mute});
  }

  static bool isMuted(Map<String, dynamic> chat) {
    final muted = Map<String, dynamic>.from(chat['muted'] as Map? ?? {});
    return (muted[_myUid] as bool?) == true;
  }

  // ── Add/remove group members ──────────────────────────────────────────────

  /// Whether [uid] allows being added to groups (Profile → Privacy → Groups).
  /// Only an explicit 'Nobody' blocks; 'My contacts'/'Everyone'/unset allow.
  static Future<bool> canAddToGroup(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return (doc.data()?['privacyGroups'] as String?) != 'Nobody';
    } catch (_) {
      return true;
    }
  }

  static Future<void> addGroupMember(String chatId, String uid, String name) async {
    if (!await canAddToGroup(uid)) {
      throw Exception('$name does not allow being added to groups.');
    }
    await _db.collection('chats').doc(chatId).update({
      'members':    FieldValue.arrayUnion([uid]),
      'memberUids': FieldValue.arrayUnion([uid]),
      'memberNames.$uid': name,
      'unreadCount.$uid': 0,
      'archived.$uid':    false,
    });
  }

  static Future<void> removeGroupMember(String chatId, String uid) async {
    await _db.collection('chats').doc(chatId).update({
      'members':    FieldValue.arrayRemove([uid]),
      'memberUids': FieldValue.arrayRemove([uid]),
    });
  }

  static Future<void> leaveGroup(String chatId) async {
    await removeGroupMember(chatId, _myUid);
  }

  static Future<void> promoteAdmin(String chatId, String uid) async {
    await _db.collection('chats').doc(chatId).update({
      'adminUids': FieldValue.arrayUnion([uid]),
    });
  }

  static Future<void> demoteAdmin(String chatId, String uid) async {
    await _db.collection('chats').doc(chatId).update({
      'adminUids': FieldValue.arrayRemove([uid]),
    });
  }

  static Future<void> setGroupDescription(String chatId, String description) async {
    await _db.collection('chats').doc(chatId).update({'description': description});
  }

  /// Who can send in a group: 'all' (default) or 'admins' (announcement mode).
  static Future<void> setGroupSendPolicy(String chatId, bool adminsOnly) async {
    await _db.collection('chats').doc(chatId).update({'sendPolicy': adminsOnly ? 'admins' : 'all'});
  }

  static bool isGroupAdmin(Map<String, dynamic> chat, String uid) =>
      List<String>.from(chat['adminUids'] as List? ?? []).contains(uid);

  /// True when the group is admins-only AND the current user is not an admin.
  static bool isSendBlocked(Map<String, dynamic> chat) {
    if (chat['type'] != 'group') return false;
    if ((chat['sendPolicy'] as String?) != 'admins') return false;
    return !isGroupAdmin(chat, _myUid);
  }

  static Future<void> setGroupInviteToken(String chatId, String token) async {
    await _db.collection('chats').doc(chatId).update({'inviteToken': token});
  }

  static Future<void> setRequireApproval(String chatId, bool require) async {
    await _db.collection('chats').doc(chatId).update({'requireApproval': require});
  }

  /// Join a group from an invite link. Returns 'joined', 'requested', or 'member'.
  static Future<String> joinViaInvite(String chatId, String token) async {
    final ref  = _db.collection('chats').doc(chatId);
    final doc  = await ref.get();
    if (!doc.exists) throw Exception('That group no longer exists.');
    final data = doc.data()!;
    if ((data['inviteToken'] as String?) != token || token.isEmpty) {
      throw Exception('This invite link is invalid or has been reset.');
    }
    final members = List<String>.from(data['members'] as List? ?? []);
    if (members.contains(_myUid)) return 'member';

    final myName = await _myName();
    if ((data['requireApproval'] as bool?) == true) {
      await ref.collection('joinRequests').doc(_myUid).set({
        'uid': _myUid, 'name': myName, 'requestedAt': FieldValue.serverTimestamp(),
      });
      return 'requested';
    }
    await ref.update({
      'members':          FieldValue.arrayUnion([_myUid]),
      'memberUids':       FieldValue.arrayUnion([_myUid]),
      'memberNames.$_myUid': myName,
      'unreadCount.$_myUid': 0,
      'archived.$_myUid':    false,
    });
    return 'joined';
  }

  static Stream<List<Map<String, dynamic>>> joinRequestsStream(String chatId) =>
      _db.collection('chats').doc(chatId).collection('joinRequests').snapshots()
          .map((s) => s.docs.map((d) => {...d.data(), 'uid': d.id}).toList());

  static Future<void> approveJoinRequest(String chatId, String uid, String name) async {
    final ref = _db.collection('chats').doc(chatId);
    await ref.update({
      'members':          FieldValue.arrayUnion([uid]),
      'memberUids':       FieldValue.arrayUnion([uid]),
      'memberNames.$uid': name,
      'unreadCount.$uid': 0,
      'archived.$uid':    false,
    });
    await ref.collection('joinRequests').doc(uid).delete();
  }

  static Future<void> rejectJoinRequest(String chatId, String uid) async {
    await _db.collection('chats').doc(chatId).collection('joinRequests').doc(uid).delete();
  }

  // ── Streams ──────────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> chatsStream() {
    return _db
        .collection('chats')
        .where('members', arrayContains: _myUid)
        .snapshots()
        .asyncMap((snap) async {
          final docs = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();

          // Enrich memberNames for direct chats where name is 'Unknown' or missing
          for (final doc in docs) {
            if (doc['type'] == 'group') continue;
            final members     = List<String>.from(doc['members'] as List? ?? []);
            final memberNames = Map<String, dynamic>.from(doc['memberNames'] as Map? ?? {});
            bool needsUpdate  = false;

            for (final uid in members) {
              if (uid == _myUid) continue;
              final stored = memberNames[uid] as String? ?? '';
              if (stored.isEmpty || stored == 'Unknown') {
                final userDoc = await _db.collection('users').doc(uid).get();
                final data    = userDoc.data() ?? {};
                final name    = data['fullName'] as String?
                             ?? data['displayName'] as String?
                             ?? data['phoneNumber'] as String?
                             ?? 'Unknown';
                memberNames[uid] = name;
                needsUpdate      = true;
              }
            }

            doc['memberNames'] = memberNames;

            // Patch Firestore so the name is correct going forward
            if (needsUpdate) {
              _db.collection('chats').doc(doc['id'] as String).update({
                'memberNames': memberNames,
              }).catchError((_) {});
            }
          }

          // Pinned first, then by lastTime desc
          docs.sort((a, b) {
            final aPinned = (a['pinned'] as bool?) == true;
            final bPinned = (b['pinned'] as bool?) == true;
            if (aPinned != bPinned) return aPinned ? -1 : 1;
            final aTime = (a['lastTime'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            final bTime = (b['lastTime'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
            return bTime.compareTo(aTime);
          });
          return docs;
        });
  }

  /// Streams the most recent [limit] messages (newest fetched, returned oldest→
  /// newest for display). Raise [limit] to page in older history. Loading the
  /// whole history on every chat open is slow and costly on long chats.
  static Stream<List<Map<String, dynamic>>> messagesStream(String chatId, {int limit = 50}) {
    return _db
        .collection('chats').doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .asyncMap((snap) async {
          // Fetched newest-first for the limit; reverse to chronological order.
          final docs = snap.docs
              .map((d) => Map<String, dynamic>.from(d.data()))
              .toList()
              .reversed
              .toList();
          for (final doc in docs) {
            final raw = doc['text'] as String? ?? '';
            if (raw.isNotEmpty) doc['text'] = await EncryptionService.decrypt(chatId, raw);
          }
          return docs;
        });
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String getChatDisplayName(Map<String, dynamic> chat) {
    if (chat['type'] == 'group') return chat['name'] as String? ?? 'Group';
    final memberNames = Map<String, dynamic>.from(chat['memberNames'] as Map? ?? {});
    final members     = List<String>.from(chat['members'] as List? ?? []);
    final otherId     = members.firstWhere((id) => id != _myUid, orElse: () => '');
    return memberNames[otherId] as String? ?? 'Unknown';
  }

  static int getUnreadCount(Map<String, dynamic> chat) {
    final unread = Map<String, dynamic>.from(chat['unreadCount'] as Map? ?? {});
    return (unread[_myUid] as num?)?.toInt() ?? 0;
  }

  static bool isArchived(Map<String, dynamic> chat) {
    final archived = Map<String, dynamic>.from(chat['archived'] as Map? ?? {});
    return (archived[_myUid] as bool?) == true;
  }

  static bool isPinned(Map<String, dynamic> chat) =>
      (chat['pinned'] as bool?) == true;

  /// Whether the current user was @mentioned in an unread message of this chat.
  static bool isMentioned(Map<String, dynamic> chat) {
    final m = Map<String, dynamic>.from(chat['mentioned'] as Map? ?? {});
    return (m[_myUid] as bool?) == true;
  }

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final q    = query.toLowerCase();
    final snap = await _db.collection('users').get();
    return snap.docs
        .where((d) => d.id != _myUid)
        .map((d) => d.data())
        .where((data) {
          final name  = (data['fullName']    as String? ?? '').toLowerCase();
          final phone = (data['phoneNumber'] as String? ?? '').toLowerCase();
          return name.contains(q) || phone.contains(q);
        })
        .toList();
  }

  static String formatTime(dynamic ts) {
    if (ts == null) return '';
    final dt  = (ts as Timestamp).toDate();
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}';
  }
}
