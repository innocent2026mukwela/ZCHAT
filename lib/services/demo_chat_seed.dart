import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// One-time sample 1:1 chats for local OTP / anonymous auth ([AppConfig.demoAuth]).
///
/// Writes real `chats/{id}` + `messages` so [ChatService] streams work unchanged.
/// Peer profile stubs are best-effort — Firestore rules only allow `users/{self}`
/// writes, so display names live on `memberNames` when stubs cannot be created.
///
/// Unlike live chat sends, sample messages are stored as plaintext (legacy path
/// accepted by [EncryptionService.decrypt]). That avoids a second
/// `encryptionKey` merge write, which was aborting the whole seed when it failed
/// while [DemoThreadsSeed] (no encryption) still succeeded.
class DemoChatSeed {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static bool _running = false;

  /// Bumped so devices that marked v1 seeded without visible chats re-run.
  static const _prefsKeyPrefix = 'sample_chats_seeded_v2_';

  /// Call after auth when the chat list first loads. Safe to invoke multiple times.
  static Future<void> ensureSeeded() async {
    if (!AppConfig.demoAuth) return;
    if (_running) return;

    var user = _auth.currentUser;
    if (user == null) {
      // Cold start / hot restart can mount Home before auth restores.
      try {
        user = await _auth
            .authStateChanges()
            .where((u) => u != null)
            .first
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        debugPrint('[DemoChatSeed] No auth user — skip seed');
        return;
      }
    }
    final myUid = user!.uid;

    _running = true;
    try {
      final flagged = await _alreadySeeded(myUid);
      final visible = await _sampleChatVisible(myUid);
      if (flagged && visible) return;
      if (flagged && !visible) {
        debugPrint(
          '[DemoChatSeed] Stale seed flag for $myUid — re-seeding',
        );
        await _clearSeeded(myUid);
      }

      final myName = await _resolveMyName(myUid);
      final now = DateTime.now();

      for (final peer in _peers) {
        await _seedChat(myUid: myUid, myName: myName, peer: peer, now: now);
      }

      if (!await _sampleChatVisible(myUid)) {
        throw StateError(
          'Sample chats were not readable after seed '
          '(check Firestore rules / network).',
        );
      }

      await _markSeeded(myUid);
      debugPrint('[DemoChatSeed] Seeded ${_peers.length} chats for $myUid');
    } catch (e, st) {
      debugPrint('[DemoChatSeed] Seed failed: $e\n$st');
    } finally {
      _running = false;
    }
  }

  /// True when the first sample chat exists and lists [myUid] in `members`
  /// (the field [ChatService.chatsStream] queries).
  static Future<bool> _sampleChatVisible(String myUid) async {
    try {
      final ids = [myUid, _peers.first.uid]..sort();
      final chatId = ids.join('_');
      final doc = await _db.collection('chats').doc(chatId).get();
      if (!doc.exists) return false;
      final members = List<String>.from(doc.data()?['members'] as List? ?? []);
      return members.contains(myUid);
    } catch (e) {
      debugPrint('[DemoChatSeed] Visibility check failed: $e');
      return false;
    }
  }

  static Future<bool> _alreadySeeded(String myUid) async {
    try {
      final doc = await _db.collection('users').doc(myUid).get();
      if (doc.data()?['sampleChatsSeeded'] == true) return true;
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('$_prefsKeyPrefix$myUid') == true) return true;
      // Legacy v1 flag — treat as seeded only if chats are actually visible
      // (checked by caller); still return true so we clear+reseed when missing.
      if (prefs.getBool('sample_chats_seeded_$myUid') == true) return true;
    } catch (_) {}

    return false;
  }

  static Future<void> _clearSeeded(String myUid) async {
    try {
      await _db.collection('users').doc(myUid).set(
        {'sampleChatsSeeded': FieldValue.delete()},
        SetOptions(merge: true),
      );
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefsKeyPrefix$myUid');
      await prefs.remove('sample_chats_seeded_$myUid');
    } catch (_) {}
  }

  static Future<void> _markSeeded(String myUid) async {
    try {
      await _db.collection('users').doc(myUid).set(
        {'sampleChatsSeeded': true},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[DemoChatSeed] Could not set sampleChatsSeeded: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefsKeyPrefix$myUid', true);
      await prefs.remove('sample_chats_seeded_$myUid');
    } catch (_) {}
  }

  static Future<String> _resolveMyName(String myUid) async {
    try {
      final doc = await _db.collection('users').doc(myUid).get();
      final data = doc.data();
      final name = (data?['fullName'] as String?)?.trim();
      if (name != null && name.isNotEmpty) return name;
      final display = (data?['displayName'] as String?)?.trim();
      if (display != null && display.isNotEmpty) return display;
    } catch (_) {}
    return _auth.currentUser?.displayName?.trim().isNotEmpty == true
        ? _auth.currentUser!.displayName!
        : 'You';
  }

  static Future<void> _seedChat({
    required String myUid,
    required String myName,
    required _SeedPeer peer,
    required DateTime now,
  }) async {
    await _tryWritePeerStub(peer);

    final ids = [myUid, peer.uid]..sort();
    final chatId = ids.join('_');
    final chatRef = _db.collection('chats').doc(chatId);

    final existing = await chatRef.get();
    if (existing.exists) {
      final data = existing.data() ?? {};
      final members = List<String>.from(data['members'] as List? ?? []);
      if (!members.contains(myUid)) {
        // Self-join only: rules allow these keys when auth.uid is not yet a member.
        // Do not touch sampleSeed here — that fails the hasOnly() gate.
        await chatRef.update({
          'members': FieldValue.arrayUnion([myUid]),
          'memberUids': FieldValue.arrayUnion([myUid]),
          'memberNames.$myUid': myName,
          'unreadCount.$myUid': peer.unreadForMe,
          'archived.$myUid': false,
        });
      }
      // Chat shell already present — do not duplicate messages.
      return;
    }

    final thread = peer.messages;
    final last = thread.last;
    final lastAt = now.subtract(peer.lastAgo);
    final unread = peer.unreadForMe;

    final stepMinutes = thread.length > 1
        ? (peer.spanMinutes ~/ (thread.length - 1)).clamp(1, 180)
        : 5;
    final step = Duration(minutes: stepMinutes);

    // One batch: chat + messages (same reliability pattern as DemoThreadsSeed).
    final batch = _db.batch();
    batch.set(chatRef, {
      'id': chatId,
      'type': 'direct',
      'members': ids,
      'memberUids': ids,
      'memberNames': {myUid: myName, peer.uid: peer.name},
      'name': '',
      'lastMessage': last.text,
      'lastSenderUid': last.fromMe ? myUid : peer.uid,
      'lastTime': Timestamp.fromDate(lastAt),
      'unreadCount': {myUid: unread, peer.uid: 0},
      'pinned': false,
      'archived': {myUid: false, peer.uid: false},
      'sampleSeed': true,
    });

    for (var i = 0; i < thread.length; i++) {
      final msg = thread[i];
      final createdAt = lastAt.subtract(step * (thread.length - 1 - i));
      final fromMe = msg.fromMe;
      final senderUid = fromMe ? myUid : peer.uid;
      final senderName = fromMe ? myName : peer.name;
      final msgRef = chatRef.collection('messages').doc('sample_msg_$i');

      final readBy = <String>[senderUid];
      if (fromMe || unread == 0) {
        if (!readBy.contains(myUid)) readBy.add(myUid);
      }

      batch.set(msgRef, {
        'id': msgRef.id,
        'chatId': chatId,
        'senderUid': senderUid,
        'senderName': senderName,
        // Plaintext: EncryptionService.decrypt accepts legacy non-iv payloads.
        'text': msg.text,
        'type': 'text',
        'imageUrl': null,
        'audioUrl': null,
        'voiceDuration': null,
        'reactions': {},
        'readBy': readBy,
        'mentions': [],
        'createdAt': Timestamp.fromDate(createdAt),
        'replyToId': null,
        'replyToText': null,
        'replyToSenderName': null,
        'deleted': false,
        'edited': false,
        'viewOnce': false,
        'viewOnceViewedBy': [],
        'sampleSeed': true,
      });
    }

    await batch.commit();
  }

  /// Best-effort peer profile for New Chat / presence. Ignored if rules deny.
  static Future<void> _tryWritePeerStub(_SeedPeer peer) async {
    try {
      await _db.collection('users').doc(peer.uid).set({
        'uid': peer.uid,
        'fullName': peer.name,
        'displayName': peer.name,
        'phoneNumber': peer.phone,
        'role': 'student',
        'demo': true,
        'profileComplete': true,
        'photoUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Expected under default rules (only self-writes on users/{uid}).
    }
  }

  static const _peers = <_SeedPeer>[
    _SeedPeer(
      uid: 'seed_peer_1',
      name: 'Chuma Banda',
      phone: '+260977100001',
      lastAgo: Duration(minutes: 12),
      spanMinutes: 90,
      unreadForMe: 2,
      messages: [
        _SeedMsg(true, 'Hey Chuma, did you get the CS201 notes?'),
        _SeedMsg(false, 'Yeah, I saved them yesterday'),
        _SeedMsg(false, 'Want me to send the PDF?'),
        _SeedMsg(true, 'Please — the ones from week 4'),
        _SeedMsg(false, 'Sending now, check your drive'),
        _SeedMsg(false, 'Also the tutorial questions are in there'),
      ],
    ),
    _SeedPeer(
      uid: 'seed_peer_2',
      name: 'Mutale Phiri',
      phone: '+260966200002',
      lastAgo: Duration(hours: 2),
      spanMinutes: 240,
      unreadForMe: 0,
      messages: [
        _SeedMsg(false, 'Are we still meeting at the library?'),
        _SeedMsg(true, 'Yes — 3pm by the main entrance'),
        _SeedMsg(false, 'Cool. I will bring the group slides'),
        _SeedMsg(true, 'Perfect, see you there'),
        _SeedMsg(false, 'On my way now'),
      ],
    ),
    _SeedPeer(
      uid: 'seed_peer_3',
      name: 'Thandiwe Mwale',
      phone: '+260955300003',
      lastAgo: Duration(hours: 5),
      spanMinutes: 360,
      unreadForMe: 0,
      messages: [
        _SeedMsg(true, 'How was the STAT exam?'),
        _SeedMsg(false, 'Tough but fair — section B was long'),
        _SeedMsg(true, 'Same here. Did you attempt the hypothesis Q?'),
        _SeedMsg(false, 'I did. Hope I got the p-value right'),
        _SeedMsg(true, 'We should revise together next time'),
        _SeedMsg(false, 'Deal. Saturday morning?'),
        _SeedMsg(true, 'Saturday works for me'),
      ],
    ),
    _SeedPeer(
      uid: 'seed_peer_4',
      name: 'Joseph Tembo',
      phone: '+260977400004',
      lastAgo: Duration(days: 1, hours: 3),
      spanMinutes: 480,
      unreadForMe: 1,
      messages: [
        _SeedMsg(false, 'Bro the lab report deadline moved to Friday'),
        _SeedMsg(true, 'For real? Who said?'),
        _SeedMsg(false, 'Dr. Mwanza posted on the course page'),
        _SeedMsg(true, 'Okay I will finish tonight then'),
        _SeedMsg(false, 'Same. Ping me if you get stuck on the graphs'),
      ],
    ),
    _SeedPeer(
      uid: 'seed_peer_5',
      name: 'Natasha Zulu',
      phone: '+260966500005',
      lastAgo: Duration(days: 2),
      spanMinutes: 200,
      unreadForMe: 0,
      messages: [
        _SeedMsg(true, 'Natasha, is the choir practice still on?'),
        _SeedMsg(false, 'Yes — Great East Road campus, 17:30'),
        _SeedMsg(true, 'I will be a bit late from class'),
        _SeedMsg(false, 'No stress, we start with warm-ups'),
        _SeedMsg(true, 'Thanks! See you'),
        _SeedMsg(false, 'Bring your music folder if you have it'),
      ],
    ),
  ];
}

class _SeedPeer {
  final String uid;
  final String name;
  final String phone;
  final Duration lastAgo;
  final int spanMinutes;
  final int unreadForMe;
  final List<_SeedMsg> messages;

  const _SeedPeer({
    required this.uid,
    required this.name,
    required this.phone,
    required this.lastAgo,
    required this.spanMinutes,
    required this.unreadForMe,
    required this.messages,
  });
}

class _SeedMsg {
  final bool fromMe;
  final String text;
  const _SeedMsg(this.fromMe, this.text);
}
