import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'ai_service.dart';

class ChatService {
  static final _db      = FirebaseFirestore.instance;
  static final _auth    = FirebaseAuth.instance;
  static final _storage = FirebaseStorage.instance;

  static String get _myUid => _auth.currentUser!.uid;

  // ── Chat creation ────────────────────────────────────────────────────────

  static Future<String> getOrCreateChat(String otherUid) async {
    final ids = [_myUid, otherUid]..sort();
    final chatId = ids.join('_');

    final ref = _db.collection('chats').doc(chatId);
    final snap = await ref.get();
    if (!snap.exists) {
      final myDoc    = await _db.collection('users').doc(_myUid).get();
      final otherDoc = await _db.collection('users').doc(otherUid).get();
      final myName    = myDoc.data()?['fullName']    as String?
                     ?? myDoc.data()?['displayName'] as String? ?? 'Unknown';
      final otherName = otherDoc.data()?['fullName']    as String?
                     ?? otherDoc.data()?['displayName'] as String? ?? 'Unknown';

      await ref.set({
        'id': chatId,
        'type': 'direct',
        'members': ids,
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

  static Future<String> createGroupChat(String name, List<String> memberUids) async {
    final ref = _db.collection('chats').doc();
    final allMembers = [...memberUids, _myUid];
    await ref.set({
      'id': ref.id,
      'type': 'group',
      'members': allMembers,
      'name': name,
      'lastMessage': '',
      'lastSenderUid': '',
      'lastTime': FieldValue.serverTimestamp(),
      'unreadCount': {for (final uid in allMembers) uid: 0},
      'pinned': false,
      'archived': {for (final uid in allMembers) uid: false},
    });
    return ref.id;
  }

  // ── Messaging ────────────────────────────────────────────────────────────

  static Future<void> sendMessage(
    String chatId,
    String text, {
    String? replyToId,
    String? replyToText,
    String type = 'text',
    String? imageUrl,
    String? audioUrl,
    String? voiceDuration,
  }) async {
    final msgRef  = _db.collection('chats').doc(chatId).collection('messages').doc();
    final chatRef = _db.collection('chats').doc(chatId);

    final batch = _db.batch();

    final senderName = _auth.currentUser?.displayName
        ?? _auth.currentUser?.email ?? 'Unknown';

    batch.set(msgRef, {
      'id':            msgRef.id,
      'chatId':        chatId,
      'senderUid':     _myUid,
      'senderName':    senderName,
      'text':          text,
      'type':          type,
      'imageUrl':      imageUrl,
      'audioUrl':      audioUrl,
      'voiceDuration': voiceDuration,
      'reactions':     {},
      'readBy':        [_myUid],
      'createdAt':     FieldValue.serverTimestamp(),
      'replyToId':     replyToId,
      'replyToText':   replyToText,
      'deleted':       false,
      'edited':        false,
    });

    final chatSnap = await chatRef.get();
    if (chatSnap.exists) {
      final members = List<String>.from(chatSnap['members'] as List);
      final unreadUpdate = <String, dynamic>{};
      for (final uid in members) {
        if (uid != _myUid) unreadUpdate['unreadCount.$uid'] = FieldValue.increment(1);
      }
      final preview = type == 'image' ? '📷 Photo' : text;
      batch.update(chatRef, {
        'lastMessage':   preview,
        'lastSenderUid': _myUid,
        'lastTime':      FieldValue.serverTimestamp(),
        ...unreadUpdate,
      });
    }

    await batch.commit();

    if (chatSnap.exists) {
      final members    = List<String>.from(chatSnap['members'] as List);
      final senderName = _auth.currentUser?.displayName ?? 'Someone';
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

  // ── Image upload + send ──────────────────────────────────────────────────

  static Future<void> sendImage(String chatId, File imageFile) async {
    final ext  = imageFile.path.split('.').last;
    final path = 'chat_images/$chatId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref  = _storage.ref().child(path);
    await ref.putFile(imageFile);
    final url = await ref.getDownloadURL();
    await sendMessage(chatId, '📷 Photo', type: 'image', imageUrl: url);
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

  // ── Read / unread / pin / archive ────────────────────────────────────────

  static Future<void> markRead(String chatId) async {
    await _db.collection('chats').doc(chatId)
        .update({'unreadCount.$_myUid': 0});
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

  // ── Edit message ─────────────────────────────────────────────────────────

  static Future<void> editMessage(String chatId, String msgId, String newText) async {
    await _db.collection('chats').doc(chatId).collection('messages').doc(msgId)
        .update({'text': newText, 'edited': true});
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

  static Future<void> starMessage(String chatId, String msgId, String text) async {
    await _db.collection('users').doc(_myUid).collection('starred').doc(msgId).set({
      'chatId': chatId, 'msgId': msgId,
      'text': text, 'starredAt': FieldValue.serverTimestamp(),
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

  static Future<void> addGroupMember(String chatId, String uid, String name) async {
    await _db.collection('chats').doc(chatId).update({
      'members': FieldValue.arrayUnion([uid]),
      'memberNames.$uid': name,
      'unreadCount.$uid': 0,
      'archived.$uid': false,
    });
  }

  static Future<void> removeGroupMember(String chatId, String uid) async {
    await _db.collection('chats').doc(chatId).update({
      'members': FieldValue.arrayRemove([uid]),
    });
  }

  static Future<void> leaveGroup(String chatId) async {
    await removeGroupMember(chatId, _myUid);
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

  static Stream<List<Map<String, dynamic>>> messagesStream(String chatId) {
    return _db
        .collection('chats').doc(chatId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
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
