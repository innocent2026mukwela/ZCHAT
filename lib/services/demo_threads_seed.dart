import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'threads_service.dart';

/// One-time sample ZFeed posts + replies for local OTP / anonymous auth
/// ([AppConfig.demoAuth]).
///
/// Firestore rules require `authorUid == request.auth.uid` on create, so every
/// post/reply is written under the signed-in uid. Varied campus display names
/// are stored on the denormalized author fields (`authorName`, handle, avatar).
/// Posts are marked `sampleSeed: true` so [ThreadsService] keeps those names
/// instead of overwriting from `users/{uid}`.
class DemoThreadsSeed {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static bool _running = false;

  static const _prefsKeyPrefix = 'sample_threads_seeded_';

  /// Call when the Threads / zFeed screen first opens. Safe to invoke repeatedly.
  static Future<void> ensureSeeded() async {
    if (!AppConfig.demoAuth) return;
    if (_running) return;

    final user = _auth.currentUser;
    if (user == null) return;
    final myUid = user.uid;

    _running = true;
    try {
      if (await _alreadySeeded(myUid)) return;

      final now = DateTime.now();
      for (var i = 0; i < _posts.length; i++) {
        await _seedPost(
          myUid: myUid,
          postIndex: i,
          post: _posts[i],
          now: now,
        );
      }

      await _markSeeded(myUid);
      debugPrint('[DemoThreadsSeed] Seeded ${_posts.length} posts for $myUid');
    } catch (e, st) {
      debugPrint('[DemoThreadsSeed] Seed failed: $e\n$st');
    } finally {
      _running = false;
    }
  }

  static Future<bool> _alreadySeeded(String myUid) async {
    try {
      final doc = await _db.collection('users').doc(myUid).get();
      if (doc.data()?['sampleThreadsSeeded'] == true) return true;
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('$_prefsKeyPrefix$myUid') == true) return true;
    } catch (_) {}

    return false;
  }

  static Future<void> _markSeeded(String myUid) async {
    try {
      await _db.collection('users').doc(myUid).set(
        {'sampleThreadsSeeded': true},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[DemoThreadsSeed] Could not set sampleThreadsSeeded: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefsKeyPrefix$myUid', true);
    } catch (_) {}
  }

  static Future<void> _seedPost({
    required String myUid,
    required int postIndex,
    required _SeedPost post,
    required DateTime now,
  }) async {
    // Deterministic ids so a partial seed + retry does not duplicate posts.
    final postRef =
        _db.collection('threads').doc('sample_${myUid}_$postIndex');
    final existing = await postRef.get();
    if (existing.exists) return;

    final createdAt = now.subtract(post.ago);
    final author = post.author;
    final colorVal = _colorForKey(author.key);
    final initials = ThreadsService.initials(author.name);
    final handle = '@${author.name.toLowerCase().replaceAll(' ', '.')}';
    final hashtags = ThreadsService.extractHashtags(post.content);

    final stepMinutes = post.comments.length > 1
        ? (post.commentSpanMinutes ~/ (post.comments.length - 1)).clamp(1, 120)
        : 8;
    final step = Duration(minutes: stepMinutes);

    // Post + replies in one batch so a failure never leaves an orphan shell.
    final batch = _db.batch();
    batch.set(postRef, {
      'authorUid': myUid,
      'authorName': author.name,
      'authorHandle': handle,
      'authorRole': 'student',
      'authorPhotoUrl': '',
      'avatarInitials': initials,
      'avatarColorVal': colorVal,
      'content': post.content,
      'imageUrl': '',
      'hashtags': hashtags,
      'likes': post.likes,
      'replies': post.comments.length,
      'reposts': post.reposts,
      'likedBy': post.likedByMe ? [myUid] : <String>[],
      'repostedBy': <String>[],
      'isVerified': false,
      'sampleSeed': true,
      'createdAt': Timestamp.fromDate(createdAt),
    });

    for (var i = 0; i < post.comments.length; i++) {
      final c = post.comments[i];
      final replyAt = createdAt.add(step * (i + 1));
      final replyRef =
          postRef.collection('replies').doc('sample_reply_$i');
      final cInitials = ThreadsService.initials(c.author.name);
      final cHandle =
          '@${c.author.name.toLowerCase().replaceAll(' ', '.')}';
      batch.set(replyRef, {
        'authorUid': myUid,
        'authorName': c.author.name,
        'authorHandle': cHandle,
        'authorRole': 'student',
        'authorPhotoUrl': '',
        'avatarInitials': cInitials,
        'avatarColorVal': _colorForKey(c.author.key),
        'text': c.text,
        'likes': c.likes,
        'likedBy': <String>[],
        'sampleSeed': true,
        'createdAt': Timestamp.fromDate(replyAt),
      });
    }
    await batch.commit();
  }

  static int _colorForKey(String key) {
    const colors = [
      Color(0xFF1565C0),
      Color(0xFF6A1B9A),
      Color(0xFF2E7D32),
      Color(0xFFAD1457),
      Color(0xFFE65100),
      Color(0xFF00695C),
      Color(0xFF4527A0),
      Color(0xFF283593),
    ];
    final idx = key.codeUnits.fold(0, (acc, c) => acc + c) % colors.length;
    return colors[idx].toARGB32();
  }

  // Stable campus voices (shared vibe with chat sample peers).
  static const _chuma = _SeedAuthor('chuma', 'Chuma Banda');
  static const _mutale = _SeedAuthor('mutale', 'Mutale Phiri');
  static const _thandiwe = _SeedAuthor('thandiwe', 'Thandiwe Mwale');
  static const _joseph = _SeedAuthor('joseph', 'Joseph Tembo');
  static const _natasha = _SeedAuthor('natasha', 'Natasha Zulu');
  static const _lombe = _SeedAuthor('lombe', 'Lombe Chileshe');
  static const _mwansa = _SeedAuthor('mwansa', 'Mwansa Kaunda');

  static const _posts = <_SeedPost>[
    _SeedPost(
      author: _chuma,
      ago: Duration(minutes: 35),
      likes: 12,
      reposts: 1,
      likedByMe: false,
      commentSpanMinutes: 28,
      content:
          'Anyone have CS201 past papers from last two years? Especially the recursion + trees sections. Drop a Drive link if you can 🙏 #CS201 #PastPapers',
      comments: [
        _SeedComment(
          _mutale,
          'I have 2023 and 2024 mid-years — DM me and I will share the folder.',
          likes: 3,
        ),
        _SeedComment(
          _joseph,
          'Also check the departmental noticeboard scan someone posted last semester.',
          likes: 1,
        ),
        _SeedComment(
          _thandiwe,
          'Tutorial sheet for week 6 is basically the same style as the exam.',
          likes: 2,
        ),
      ],
    ),
    _SeedPost(
      author: _mutale,
      ago: Duration(hours: 2),
      likes: 8,
      reposts: 0,
      likedByMe: true,
      commentSpanMinutes: 40,
      content:
          'Study group for STAT211 finals — Saturday 09:00 at the main library (level 2 quiet zone). Bring your notes and calculator. Spots for 6. Who is in? #STAT211 #StudyGroup',
      comments: [
        _SeedComment(_natasha, 'I am in. Can we cover hypothesis testing first?', likes: 1),
        _SeedComment(_chuma, 'Count me in — I will bring the formula sheet.', likes: 0),
        _SeedComment(_lombe, 'Is it okay if I join a bit late after lab?', likes: 0),
        _SeedComment(_mutale, 'Yes, late is fine. We will leave a seat.', likes: 2),
      ],
    ),
    _SeedPost(
      author: _thandiwe,
      ago: Duration(hours: 5),
      likes: 24,
      reposts: 4,
      likedByMe: false,
      commentSpanMinutes: 90,
      content:
          'Career Fair next Wednesday at the Great East Road campus hall, 10:00–16:00. Banking, telecoms, and a few NGOs confirmed. Bring CVs printed double-sided. #CampusEvents #Careers',
      comments: [
        _SeedComment(
          _joseph,
          'Do we need student ID at the door?',
          likes: 0,
        ),
        _SeedComment(
          _thandiwe,
          'Yes — and dress smart casual at least.',
          likes: 5,
        ),
        _SeedComment(
          _mwansa,
          'Airtel and Zanaco were there last year. Hoping they return.',
          likes: 2,
        ),
      ],
    ),
    _SeedPost(
      author: _joseph,
      ago: Duration(hours: 9),
      likes: 5,
      reposts: 0,
      likedByMe: false,
      commentSpanMinutes: 50,
      content:
          'Quick question: is the engineering library open past 20:00 on weekdays this term? The main one closes early during exams week and I need a quiet desk. #Library #CampusLife',
      comments: [
        _SeedComment(
          _lombe,
          'Engineering stays open until 22:00 Mon–Thu. Fri until 18:00.',
          likes: 4,
        ),
        _SeedComment(
          _natasha,
          'Confirm at the front desk though — they sometimes change for holidays.',
          likes: 1,
        ),
      ],
    ),
    _SeedPost(
      author: _natasha,
      ago: Duration(days: 1, hours: 2),
      likes: 31,
      reposts: 6,
      likedByMe: false,
      commentSpanMinutes: 120,
      content:
          'Lost a navy notebook with CIRCUIT THEORY written on the cover near School of Engineering block B yesterday afternoon. If you picked it up please reply here — lab report notes inside 😭 #LostAndFound',
      comments: [
        _SeedComment(
          _chuma,
          'I saw a navy book on the bench by the photocopy shop — check there?',
          likes: 2,
        ),
        _SeedComment(
          _mutale,
          'Security office also keeps lost items until Friday.',
          likes: 3,
        ),
        _SeedComment(
          _natasha,
          'Update: found it at security! Thank you both 🙌',
          likes: 8,
        ),
      ],
    ),
    _SeedPost(
      author: _lombe,
      ago: Duration(days: 1, hours: 8),
      likes: 15,
      reposts: 2,
      likedByMe: false,
      commentSpanMinutes: 70,
      content:
          'Debate Society open mic tonight 18:30 at the Student Centre. Theme: “Should attendance be mandatory for lectures?” Free entry, tea after. Come argue or just listen. #Debate #CampusEvents',
      comments: [
        _SeedComment(_mwansa, 'I am speaking for the opposition — wish me luck.', likes: 4),
        _SeedComment(_thandiwe, 'Will be there. Save me a seat near the front.', likes: 1),
        _SeedComment(_joseph, 'Is there a WhatsApp group for next topics?', likes: 0),
        _SeedComment(_lombe, 'Yes — link on the Society noticeboard and Instagram bio.', likes: 2),
        _SeedComment(_chuma, 'Might drop in after tutorial.', likes: 0),
      ],
    ),
    _SeedPost(
      author: _mwansa,
      ago: Duration(days: 2, hours: 4),
      likes: 9,
      reposts: 1,
      likedByMe: true,
      commentSpanMinutes: 60,
      content:
          'Does anyone understand question 4 on the EEE203 assignment (phasors)? My answer keeps differing from the tutorial memo by a factor of √2. #EEE203 #Help',
      comments: [
        _SeedComment(
          _joseph,
          'Check if you converted peak to RMS before the division step.',
          likes: 6,
        ),
        _SeedComment(
          _mutale,
          'Same mistake last week — that √2 is exactly the peak/RMS mix-up.',
          likes: 3,
        ),
        _SeedComment(
          _mwansa,
          'That was it. Thanks — finally matches the memo.',
          likes: 2,
        ),
      ],
    ),
  ];
}

class _SeedAuthor {
  final String key;
  final String name;
  const _SeedAuthor(this.key, this.name);
}

class _SeedPost {
  final _SeedAuthor author;
  final Duration ago;
  final int likes;
  final int reposts;
  final bool likedByMe;
  final int commentSpanMinutes;
  final String content;
  final List<_SeedComment> comments;

  const _SeedPost({
    required this.author,
    required this.ago,
    required this.likes,
    required this.reposts,
    required this.likedByMe,
    required this.commentSpanMinutes,
    required this.content,
    required this.comments,
  });
}

class _SeedComment {
  final _SeedAuthor author;
  final String text;
  final int likes;

  const _SeedComment(this.author, this.text, {this.likes = 0});
}
