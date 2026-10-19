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
/// Sample message bodies are stored as plaintext (legacy path).
/// [EncryptionService.decrypt] already accepts non-ciphertext text, and skipping
/// encrypt avoids a common failure mode where key write / encrypt throws and
/// leaves the chat list empty while ZFeed sample posts still appear.
class DemoChatSeed {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static bool _running = false;

  static const _prefsKeyPrefix = 'sample_chats_seeded_';

  /// Call after auth when the chat list first loads. Safe to invoke multiple times.
  static Future<void> ensureSeeded() async {
    if (!AppConfig.demoAuth) return;
    if (_running) return;

    // DEMO_AUTH cold start / hot restart can mount Home a tick before anon
    // auth restores — wait briefly so we seed under the real uid.
    var user = _auth.currentUser;
    if (user == null) {
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
      // Gate on real sample chats (members query), not just a prefs/Firestore
      // flag. Stale sampleChatsSeeded after encrypt failure skipped seeding
      // forever while ZFeed dummy posts still appeared.
      if (await _hasSampleChats(myUid)) {
        await _markSeeded(myUid);
        return;
      }

      final myName = await _resolveMyName(myUid);
      final now = DateTime.now();

      for (final peer in _peers) {
        await _seedChat(myUid: myUid, myName: myName, peer: peer, now: now);
      }

      if (!await _hasSampleChats(myUid)) {
        throw StateError(
          'Sample chats were not readable after seed '
          '(check Firestore rules / network for chats writes).',
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

  /// True when this user already has at least one `sampleSeed` chat in the list.
  static Future<bool> _hasSampleChats(String myUid) async {
    try {
      final snap = await _db
          .collection('chats')
          .where('members', arrayContains: myUid)
          .limit(40)
          .get();
      return snap.docs.any((d) => d.data()['sampleSeed'] == true);
    } catch (e) {
      debugPrint('[DemoChatSeed] hasSampleChats check failed: $e');
      return false;
    }
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
    // Dedicated sample ids (not the sorted uid pair used by real 1:1 chats).
    // After deleteChat() removes the user from `members`, the old doc still
    // exists but is unreadable — fall through to a fresh sample_* id.
    var chatId = 'sample_${myUid}_${peer.uid}';
    var chatRef = _db.collection('chats').doc(chatId);

    DocumentSnapshot<Map<String, dynamic>>? existing;
    try {
      existing = await chatRef.get();
    } catch (e) {
      debugPrint(
        '[DemoChatSeed] Cannot read $chatId (likely left members): $e — new id',
      );
      chatId =
          'sample_${myUid}_${peer.uid}_${DateTime.now().millisecondsSinceEpoch}';
      chatRef = _db.collection('chats').doc(chatId);
      existing = null;
    }
    final thread = peer.messages;
    final last = thread.last;
    final lastAt = now.subtract(peer.lastAgo);
    final unread = peer.unreadForMe;

    // Stagger message times ending at [lastAt].
    final stepMinutes = thread.length > 1
        ? (peer.spanMinutes ~/ (thread.length - 1)).clamp(1, 180)
        : 5;
    final step = Duration(minutes: stepMinutes);

    // One batch so a mid-seed failure never leaves an orphan chat shell without
    // messages (and never depends on EncryptionService round-trips).
    final batch = _db.batch();
    final chatPayload = <String, dynamic>{
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
    };

    var needMessages = true;
    if (existing == null || !existing.exists) {
      batch.set(chatRef, chatPayload);
    } else {
      final data = existing.data() ?? {};
      final members = List<String>.from(data['members'] as List? ?? []);
      final missingMe = !members.contains(myUid);
      final incomplete = data['sampleSeed'] != true ||
          (data['lastMessage'] as String? ?? '').isEmpty;

      if (missingMe) {
        // Self-join path only — rules hasOnly these membership keys when the
        // caller is not yet in resource.data.members. Full chatPayload merge
        // would be denied.
        batch.update(chatRef, {
          'members': FieldValue.arrayUnion([myUid]),
          'memberUids': FieldValue.arrayUnion([myUid]),
          'memberNames.$myUid': myName,
          'unreadCount.$myUid': unread,
          'archived.$myUid': false,
        });
      } else if (incomplete) {
        // Already a member — may update any fields.
        batch.set(chatRef, chatPayload, SetOptions(merge: true));
      }

      final msgs = await chatRef.collection('messages').limit(1).get();
      needMessages = msgs.docs.isEmpty;
      if (!needMessages && !missingMe && !incomplete) return;
    }

    if (needMessages) {
      for (var i = 0; i < thread.length; i++) {
        final msg = thread[i];
        final createdAt = lastAt.subtract(step * (thread.length - 1 - i));
        final fromMe = msg.fromMe;
        final senderUid = fromMe ? myUid : peer.uid;
        final senderName = fromMe ? myName : peer.name;
        // Deterministic ids so retries do not duplicate messages.
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
          // Plaintext on purpose for sample seeds (see class doc).
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
