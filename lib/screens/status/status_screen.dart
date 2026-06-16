import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import '../../services/chat_service.dart';
import '../../utils/helpers.dart';
import '../../services/status_service.dart';
import '../../utils/glass.dart';
import '../../widgets/bottom_nav_bar.dart';

// ── Colour helpers ────────────────────────────────────────────────────────────

const _kPalette = [
  Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFF2E7D32),
  Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
  Color(0xFF4527A0), Color(0xFF283593),
];

Color _avatarColor(String name) =>
    _kPalette[name.codeUnits.fold(0, (a, c) => a + c) % _kPalette.length];

String _initials(String name) {
  final parts = name.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
}

// ── Status Screen ─────────────────────────────────────────────────────────────

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});
  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  List<Map<String, dynamic>> _contactStatuses = [];
  List<Map<String, dynamic>> _myItems         = [];
  Map<String, dynamic>?      _myProfile;
  Set<String>                _mutedUids        = {};
  bool    _loading   = true;
  String? _loadError;
  bool    _searching = false;
  String  _search    = '';
  String  _myUid     = '';
  final  _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _loadMyProfile();
    StatusService.myStatusStream().listen((items) {
      if (mounted) setState(() => _myItems = items);
    });
    _load();
  }

  Future<void> _loadMyProfile() async {
    if (_myUid.isEmpty) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(_myUid).get();
    if (mounted) {
      final data = doc.data();
      final muted = List<String>.from(data?['mutedStatuses'] as List? ?? []);
      setState(() { _myProfile = data; _mutedUids = muted.toSet(); });
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final uids     = await _zchatContactUids();
      final statuses = await StatusService.fetchContactStatuses(uids);
      if (mounted) setState(() { _contactStatuses = statuses; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _loadError = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<List<String>> _zchatContactUids() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) return [];
    final contacts = await FlutterContacts.getAll(properties: ContactProperties.allProperties);
    final phones = <String>{};
    for (final c in contacts) {
      for (final p in c.phones) {
        final n = toE164(p.number);
        if (n.isNotEmpty) phones.add(n);
      }
    }
    if (phones.isEmpty) return [];
    final uids = <String>[];
    final list = phones.toList();
    for (int i = 0; i < list.length; i += 30) {
      final chunk = list.sublist(i, (i + 30).clamp(0, list.length));
      final snap  = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        if (doc.id != _myUid) uids.add(doc.id);
      }
    }
    return uids;
  }

  Future<void> _toggleMute(String uid) async {
    final isMuted = _mutedUids.contains(uid);
    setState(() {
      if (isMuted) { _mutedUids.remove(uid); } else { _mutedUids.add(uid); }
    });
    await FirebaseFirestore.instance.collection('users').doc(_myUid).update({
      'mutedStatuses': isMuted
          ? FieldValue.arrayRemove([uid])
          : FieldValue.arrayUnion([uid]),
    });
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddStatusSheet(onDone: _load),
    );
  }

  void _openViewer(Map<String, dynamic> data) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      pageBuilder: (ctx, a1, a2) =>
          _StatusViewer(statusData: data, myUid: _myUid),
    ));
  }

  void _showContactOptions(Map<String, dynamic> s) {
    HapticFeedback.mediumImpact();
    final uid      = s['uid'] as String? ?? '';
    final name     = s['name'] as String? ?? 'User';
    final isMuted  = _mutedUids.contains(uid);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(name, style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          Divider(color: Colors.white.withAlpha(15), height: 1),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70),
            title: const Text('Message', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              context.push('/chats/${Uri.encodeComponent(uid)}?name=${Uri.encodeComponent(name)}');
            },
          ),
          ListTile(
            leading: Icon(isMuted ? Icons.notifications_rounded : Icons.notifications_off_outlined,
                color: Colors.white70),
            title: Text(isMuted ? 'Unmute updates' : 'Mute updates',
                style: const TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _toggleMute(uid); },
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined, color: Colors.white70),
            title: const Text('Hide updates from this contact',
                style: TextStyle(color: Colors.white)),
            onTap: () { Navigator.pop(context); _toggleMute(uid); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  List<Map<String, dynamic>> get _visibleStatuses {
    var list = _contactStatuses
        .where((s) => !_mutedUids.contains(s['uid'] as String? ?? ''))
        .toList();
    if (_search.isNotEmpty) {
      list = list.where((s) =>
          (s['name'] as String? ?? '').toLowerCase().contains(_search.toLowerCase()))
          .toList();
    }
    return list;
  }

  List<Map<String, dynamic>> get _mutedStatuses =>
      _contactStatuses.where((s) => _mutedUids.contains(s['uid'] as String? ?? '')).toList();

  static String _latestImageFromItems(List items) {
    for (final item in items.reversed) {
      final m    = item as Map;
      final type = m['type'] as String? ?? '';
      if (type == 'image' || type == 'video') {
        return m['imageUrl'] as String? ?? '';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final myName     = _myProfile?['fullName'] as String?
        ?? FirebaseAuth.instance.currentUser?.displayName ?? 'Me';
    final myPhoto    = _myProfile?['photoUrl'] as String? ?? '';

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      bottomNavigationBar: const AppBottomNavBar(),
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Column(children: [
            _buildAppBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: const Color(0xFF4F8AFF),
                backgroundColor: const Color(0xFF0E1829),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _MyStatusCard(
                      name:     myName,
                      initials: _initials(myName),
                      photoUrl: myPhoto,
                      color:    _avatarColor(myName),
                      items:    _myItems,
                      onView:   _myItems.isEmpty ? null : () => _openViewer({
                        'uid': _myUid, 'name': myName,
                        'photoUrl': myPhoto, 'items': _myItems, 'hasUnread': false,
                      }),
                      onAdd: _showAddSheet,
                    ).animate().fadeIn(duration: 300.ms),

                    const SizedBox(height: 8),

                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator(
                            color: Color(0xFF4F8AFF), strokeWidth: 2)),
                      )
                    else if (_loadError != null)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
                          const SizedBox(height: 12),
                          Text(_loadError!, textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withAlpha(160))),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _load,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                            child: const Text('Retry'),
                          ),
                        ]),
                      )
                    else if (_visibleStatuses.isEmpty && _mutedStatuses.isEmpty)
                      _buildEmpty()
                    else ...[
                      if (_visibleStatuses.isNotEmpty) ...[
                        _SectionLabel('Recent updates'),
                        ..._visibleStatuses.asMap().entries.map((e) =>
                          _ContactStatusTile(
                            index:          e.key,
                            name:           e.value['name'] as String? ?? 'User',
                            photoUrl:       e.value['photoUrl'] as String? ?? '',
                            time:           StatusService.timeAgo(e.value['latestAt'] as Timestamp?),
                            count:          (e.value['items'] as List).length,
                            hasUnread:      e.value['hasUnread'] as bool,
                            isMuted:        false,
                            latestImageUrl: _latestImageFromItems(e.value['items'] as List),
                            onTap:          () => _openViewer(e.value),
                            onLongPress:    () => _showContactOptions(e.value),
                          ),
                        ),
                      ],
                      if (_mutedStatuses.isNotEmpty) ...[
                        _SectionLabel('Muted updates'),
                        ..._mutedStatuses.asMap().entries.map((e) =>
                          _ContactStatusTile(
                            index:          e.key,
                            name:           e.value['name'] as String? ?? 'User',
                            photoUrl:       e.value['photoUrl'] as String? ?? '',
                            time:           StatusService.timeAgo(e.value['latestAt'] as Timestamp?),
                            count:          (e.value['items'] as List).length,
                            hasUnread:      false,
                            isMuted:        true,
                            latestImageUrl: _latestImageFromItems(e.value['items'] as List),
                            onTap:          () => _openViewer(e.value),
                            onLongPress:    () => _showContactOptions(e.value),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildAppBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(12),
            border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          child: SafeArea(bottom: false, child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => context.go('/home'),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                const Text('Updates', style: TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _searching ? Icons.close_rounded : Icons.search_rounded,
                    color: Colors.white.withAlpha(200),
                  ),
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) { _search = ''; _searchCtrl.clear(); }
                  }),
                ),
                IconButton(
                  icon: Icon(Icons.more_vert_rounded, color: Colors.white.withAlpha(200)),
                  onPressed: () => _showPrivacySheet(),
                ),
              ]),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _searching
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withAlpha(35)),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          onChanged: (v) => setState(() => _search = v),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search updates…',
                            hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: Colors.white.withAlpha(160), size: 20),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(height: 4),
            ),
          ])),
        ),
      ),
    );
  }

  void _showPrivacySheet() {
    final current = _myProfile?['statusPrivacy'] as String? ?? 'contacts';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(2))),
          const Text('Status Privacy', style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final opt in [
            ('everyone', 'Everyone', Icons.public_rounded),
            ('contacts', 'My contacts', Icons.people_rounded),
            ('nobody',   'Nobody',     Icons.block_rounded),
          ])
            ListTile(
              leading: Icon(opt.$3, color: opt.$1 == current
                  ? const Color(0xFF4F8AFF) : Colors.white54),
              title: Text(opt.$2, style: TextStyle(
                  color: opt.$1 == current ? const Color(0xFF4F8AFF) : Colors.white)),
              trailing: opt.$1 == current
                  ? const Icon(Icons.check_rounded, color: Color(0xFF4F8AFF))
                  : null,
              onTap: () async {
                Navigator.pop(context);
                await FirebaseFirestore.instance
                    .collection('users').doc(_myUid)
                    .update({'statusPrivacy': opt.$1});
                await _loadMyProfile();
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
      child: Column(children: [
        Icon(Icons.auto_stories_rounded, size: 52, color: Colors.white.withAlpha(50)),
        const SizedBox(height: 14),
        Text('No updates yet',
            style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 16,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Status updates from your ZCHAT contacts\nwill appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withAlpha(110), height: 1.5, fontSize: 13)),
      ]),
    );
  }
}

// ── My Status Card ────────────────────────────────────────────────────────────

class _MyStatusCard extends StatelessWidget {
  final String name, initials, photoUrl;
  final Color  color;
  final List<Map<String, dynamic>> items;
  final VoidCallback? onView;
  final VoidCallback  onAdd;

  const _MyStatusCard({
    required this.name, required this.initials, required this.photoUrl,
    required this.color, required this.items, required this.onView, required this.onAdd,
  });

  String get _latestImageUrl {
    for (final item in items.reversed) {
      final type = item['type'] as String? ?? '';
      if (type == 'image' || type == 'video') {
        return item['imageUrl'] as String? ?? '';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final hasStatus    = items.isNotEmpty;
    final thumbnailUrl = _latestImageUrl;
    final hasThumbnail = thumbnailUrl.isNotEmpty;

    return GlassCard(
      borderRadius: BorderRadius.circular(0),
      bgColor: Colors.white.withAlpha(8),
      borderColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        GestureDetector(
          onTap: hasStatus ? onView : onAdd,
          child: Stack(children: [
            Container(
              padding: hasStatus ? const EdgeInsets.all(2.5) : EdgeInsets.zero,
              decoration: BoxDecoration(
                gradient: hasStatus
                    ? const LinearGradient(colors: [Color(0xFF4F8AFF), Color(0xFF7C3AED)])
                    : null,
                shape: BoxShape.circle,
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white,
                child: CircleAvatar(
                  radius: hasStatus ? 25.5 : 28,
                  backgroundColor: color,
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty
                      ? Text(initials, style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))
                      : null,
                ),
              ),
            ),
            Positioned(
              bottom: 0, right: 0,
              child: GestureDetector(
                onTap: onAdd,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF070F1E), width: 2),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 13),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('My status', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 3),
          Text(
            hasStatus
                ? '${items.length} update${items.length == 1 ? '' : 's'}'
                : 'Tap + to add a status update',
            style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12),
          ),
        ])),
        if (hasThumbnail)
          GestureDetector(
            onTap: onView,
            child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: thumbnailUrl,
                  width: 52, height: 52,
                  fit: BoxFit.cover,
                  placeholder: (ctx2, url2) => Container(
                    width: 52, height: 52,
                    color: Colors.white.withAlpha(15),
                  ),
                  errorWidget: (ctx2, url2, err) => Container(
                    width: 52, height: 52,
                    color: Colors.white.withAlpha(15),
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white.withAlpha(80), size: 20),
                  ),
                ),
              ),
              if (items.firstWhere(
                    (i) => i['type'] == 'video', orElse: () => {}).isNotEmpty)
                Positioned.fill(
                  child: Center(
                    child: Icon(Icons.play_circle_fill_rounded,
                        color: Colors.white.withAlpha(200), size: 22),
                  ),
                ),
              Positioned(
                top: 4, right: 4,
                child: GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26, width: 1.5),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 11),
                  ),
                ),
              ),
            ]),
          )
        else
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text('Add', style: TextStyle(color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ── Contact Status Tile ───────────────────────────────────────────────────────

class _ContactStatusTile extends StatelessWidget {
  final int    index, count;
  final String name, photoUrl, time, latestImageUrl;
  final bool   hasUnread, isMuted;
  final VoidCallback onTap, onLongPress;

  const _ContactStatusTile({
    required this.index, required this.count, required this.name,
    required this.photoUrl, required this.time, required this.hasUnread,
    required this.isMuted, required this.onTap, required this.onLongPress,
    this.latestImageUrl = '',
  });

  @override
  Widget build(BuildContext context) {
    final col      = _avatarColor(name);
    final initials = _initials(name);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(isMuted ? 5 : 8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withAlpha(hasUnread ? 30 : 15)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              gradient: hasUnread && !isMuted
                  ? const LinearGradient(colors: [Color(0xFF4F8AFF), Color(0xFF7C3AED)])
                  : null,
              color: hasUnread && !isMuted ? null : Colors.white.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: CircleAvatar(
                radius: 21.5,
                backgroundColor: isMuted ? col.withAlpha(120) : col,
                backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty
                    ? Text(initials, style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: TextStyle(
                color: isMuted ? Colors.white.withAlpha(160) : Colors.white,
                fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15,
              ))),
              if (isMuted)
                Icon(Icons.notifications_off_outlined,
                    size: 14, color: Colors.white.withAlpha(80)),
            ]),
            const SizedBox(height: 3),
            Text(time, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12)),
          ])),
          if (latestImageUrl.isNotEmpty)
            Stack(clipBehavior: Clip.none, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: latestImageUrl,
                  width: 48, height: 48,
                  fit: BoxFit.cover,
                  placeholder: (ctx2, url2) => Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  errorWidget: (ctx2, url2, err) => Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white.withAlpha(60), size: 18),
                  ),
                ),
              ),
              if (hasUnread && !isMuted)
                Positioned(
                  top: -4, right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F8AFF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF0E1829), width: 1.5),
                    ),
                    child: Text('$count', style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ),
            ])
          else if (hasUnread && !isMuted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4F8AFF).withAlpha(40),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(80)),
              ),
              child: Text('$count new', style: const TextStyle(
                  color: Color(0xFF4F8AFF), fontSize: 11, fontWeight: FontWeight.w700)),
            )
          else
            Icon(Icons.chevron_right_rounded, color: Colors.white.withAlpha(80)),
        ]),
      ),
    ).animate(delay: (index * 40).ms).fadeIn().slideX(begin: 0.03, end: 0);
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
    child: Text(text, style: TextStyle(
      color: Colors.white.withAlpha(140),
      fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5,
    )),
  );
}

// ── Add Status Sheet ──────────────────────────────────────────────────────────

class _AddStatusSheet extends StatefulWidget {
  final VoidCallback onDone;
  const _AddStatusSheet({required this.onDone});
  @override
  State<_AddStatusSheet> createState() => _AddStatusSheetState();
}

class _AddStatusSheetState extends State<_AddStatusSheet> {
  final _ctrl   = TextEditingController();
  bool _posting = false;

  Future<void> _postText() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    await StatusService.postTextStatus(text);
    if (mounted) { Navigator.pop(context); widget.onDone(); }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 75);
    if (picked == null || !mounted) return;
    setState(() => _posting = true);
    await StatusService.postImageStatus(picked.path, caption: _ctrl.text.trim());
    if (mounted) { Navigator.pop(context); widget.onDone(); }
  }

  Future<void> _pickVideo(ImageSource source) async {
    final picked = await ImagePicker().pickVideo(
        source: source, maxDuration: const Duration(seconds: 30));
    if (picked == null || !mounted) return;
    setState(() => _posting = true);
    try {
      final file = File(picked.path);
      final ref  = FirebaseStorage.instance
          .ref('status_videos/${FirebaseAuth.instance.currentUser!.uid}'
              '/${DateTime.now().millisecondsSinceEpoch}.mp4');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await StatusService.postVideoStatus(url, caption: _ctrl.text.trim());
      if (mounted) { Navigator.pop(context); widget.onDone(); }
    } catch (_) {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E1829),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('New Status', style: TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          GlassCard(
            borderRadius: BorderRadius.circular(14),
            bgColor: Colors.white.withAlpha(10),
            borderColor: Colors.white.withAlpha(30),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "What's on your mind?",
                hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_posting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(color: Color(0xFF4F8AFF)),
            )
          else ...[
            // Row 1: photo options
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withAlpha(50)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withAlpha(50)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _postText,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Post'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            // Row 2: video options
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickVideo(ImageSource.camera),
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: const Text('Record Video'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFBBF24),
                    side: BorderSide(color: const Color(0xFFFBBF24).withAlpha(80)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickVideo(ImageSource.gallery),
                  icon: const Icon(Icons.video_library_outlined, size: 18),
                  label: const Text('Video Gallery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFBBF24),
                    side: BorderSide(color: const Color(0xFFFBBF24).withAlpha(80)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ── Full-screen Status Viewer ─────────────────────────────────────────────────

class _StatusViewer extends StatefulWidget {
  final Map<String, dynamic> statusData;
  final String myUid;
  const _StatusViewer({required this.statusData, required this.myUid});
  @override
  State<_StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<_StatusViewer>
    with SingleTickerProviderStateMixin {
  late AnimationController _progress;
  late List<Map<String, dynamic>> _items;
  int  _cur = 0;
  final _reply = TextEditingController();
  VideoPlayerController? _videoCtrl;

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(
        widget.statusData['items'] as List);
    _progress = AnimationController(
        vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _advance();
      });
    _initCurrent();
    _markCurrent();
  }

  Future<void> _initCurrent() async {
    await _videoCtrl?.dispose();
    _videoCtrl = null;
    final item = _items[_cur];
    final type = item['type'] as String? ?? 'text';
    if (type == 'video') {
      final url = item['imageUrl'] as String? ?? '';
      if (url.isNotEmpty) {
        final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
        await ctrl.initialize();
        _videoCtrl = ctrl;
        if (mounted) {
          setState(() {});
          ctrl.play();
          _progress.duration = ctrl.value.duration;
        }
      }
    } else {
      _progress.duration = const Duration(seconds: 5);
    }
    _progress.forward(from: 0);
  }

  void _advance() {
    if (_cur < _items.length - 1) {
      setState(() => _cur++);
      _initCurrent();
      _markCurrent();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _markCurrent() {
    final ownerUid = widget.statusData['uid'] as String? ?? '';
    if (ownerUid.isNotEmpty && ownerUid != widget.myUid) {
      StatusService.markViewed(ownerUid, _items[_cur]['id'] as String);
    }
  }

  Future<void> _sendReply(BuildContext ctx) async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final ownerUid  = widget.statusData['uid']  as String? ?? '';
    final ownerName = widget.statusData['name'] as String? ?? 'User';
    _reply.clear();
    FocusScope.of(ctx).unfocus();
    _progress.forward();
    final nav    = Navigator.of(ctx);
    final router = GoRouter.of(ctx);
    try {
      final chatId = await ChatService.getOrCreateChat(ownerUid);
      await ChatService.sendMessage(chatId, text);
      if (!mounted) return;
      nav.pop();
      router.push('/chats/${Uri.encodeComponent(chatId)}?name=${Uri.encodeComponent(ownerName)}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not send message: ${e.toString().replaceFirst("Exception: ", "")}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  void _showSeenBy() {
    final viewers = List<String>.from(
        _items[_cur]['viewedBy'] as List? ?? []);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(children: [
              const Icon(Icons.visibility_outlined, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              Text('Seen by ${viewers.length}',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (viewers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Text('No views yet',
                  style: TextStyle(color: Colors.white.withAlpha(140))),
            )
          else
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: viewers.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (_, i) => FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users').doc(viewers[i].toString()).get(),
                  builder: (ctx, snap) {
                    final name  = snap.data?.get('fullName')    as String?
                               ?? snap.data?.get('displayName') as String?
                               ?? 'ZCHAT User';
                    final photo = snap.data?.get('photoUrl') as String? ?? '';
                    final col   = _avatarColor(name);
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: col,
                        backgroundImage:
                            photo.isNotEmpty ? NetworkImage(photo) : null,
                        child: photo.isEmpty
                            ? Text(name[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.w700, fontSize: 12))
                            : null,
                      ),
                      title: Text(name,
                          style: TextStyle(
                              color: Colors.white.withAlpha(200), fontSize: 14)),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    _reply.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item   = _items[_cur];
    final name   = widget.statusData['name']     as String? ?? 'User';
    final photo  = widget.statusData['photoUrl'] as String? ?? '';
    final ts     = item['createdAt'] as Timestamp?;
    final type   = item['type']      as String?   ?? 'text';
    final text   = item['text']      as String?   ?? '';
    final imgUrl = item['imageUrl']  as String?   ?? '';
    final isOwn  = (widget.statusData['uid'] as String? ?? '') == widget.myUid;
    final viewers = List.from(item['viewedBy'] as List? ?? []);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (d) {
          final half = MediaQuery.of(context).size.width / 2;
          if (d.globalPosition.dx < half) {
            if (_cur > 0) {
              setState(() => _cur--);
              _initCurrent();
              _markCurrent();
            }
          } else {
            _advance();
          }
        },
        child: Stack(children: [
          // Content
          SizedBox.expand(
            child: type == 'video' && _videoCtrl != null && _videoCtrl!.value.isInitialized
                ? FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width:  _videoCtrl!.value.size.width,
                      height: _videoCtrl!.value.size.height,
                      child: VideoPlayer(_videoCtrl!),
                    ),
                  )
                : type == 'image' && imgUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imgUrl,
                        fit: BoxFit.contain,
                        placeholder: (c, u) => const Center(
                            child: CircularProgressIndicator(color: Colors.white)),
                        errorWidget: (c, u, e) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54, size: 64),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_avatarColor(name).withAlpha(200), Colors.black],
                          ),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(text,
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 24, fontWeight: FontWeight.w600,
                                  height: 1.4),
                              textAlign: TextAlign.center,
                            ).animate().fadeIn(duration: 300.ms),
                          ),
                        ),
                      ),
          ),

          // Caption over image
          if (type == 'image' && text.isNotEmpty)
            Positioned(
              bottom: 90, left: 16, right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    color: Colors.black.withAlpha(120),
                    child: Text(text,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        textAlign: TextAlign.center),
                  ),
                ),
              ),
            ),

          // Progress bars
          SafeArea(child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: List.generate(_items.length, (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: i < _cur
                        ? Container(height: 3, color: Colors.white)
                        : i == _cur
                            ? AnimatedBuilder(
                                animation: _progress,
                                builder: (ctx, child) =>
                                    LinearProgressIndicator(
                                      value: _progress.value,
                                      backgroundColor: Colors.white30,
                                      valueColor: const AlwaysStoppedAnimation(
                                          Colors.white),
                                      minHeight: 3,
                                    ))
                            : Container(height: 3, color: Colors.white30),
                  ),
                ),
              )),
            ),
          )),

          // Header
          SafeArea(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _avatarColor(name),
                backgroundImage:
                    photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty
                    ? Text(_initials(name),
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w700, fontSize: 12))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(StatusService.timeAgo(ts),
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              )),
              // Seen by (own status only)
              if (isOwn && viewers.isNotEmpty)
                GestureDetector(
                  onTap: _showSeenBy,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withAlpha(40)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.visibility_outlined,
                          color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text('${viewers.length}',
                          style: const TextStyle(color: Colors.white70,
                              fontSize: 12)),
                    ]),
                  ),
                ),
              if (isOwn)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.white70),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await StatusService.deleteItem(
                        _items[_cur]['id'] as String);
                    if (!mounted) return;
                    if (_items.length == 1) {
                      nav.pop();
                    } else {
                      setState(() {
                        _items.removeAt(_cur);
                        if (_cur >= _items.length) _cur = _items.length - 1;
                      });
                      _initCurrent();
                    }
                  },
                ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          )),

          // Reply bar (others' statuses only)
          if (!isOwn)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(top: false, child: Padding(
                padding: EdgeInsets.only(
                  left: 12, right: 12, bottom: 12,
                  top: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 0,
                ),
                child: Builder(builder: (ctx) => Row(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: Colors.white.withAlpha(50)),
                          ),
                          child: TextField(
                            controller: _reply,
                            style: const TextStyle(color: Colors.white),
                            onTap: () => _progress.stop(),
                            onEditingComplete: () => _progress.forward(),
                            decoration: const InputDecoration(
                              hintText: 'Reply…',
                              hintStyle: TextStyle(color: Colors.white54),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                              filled: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Emoji reaction
                  GestureDetector(
                    onTap: () {
                      _progress.stop();
                      _showEmojiReact(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withAlpha(40)),
                      ),
                      child: const Text('😊', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _sendReply(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ])),
              )),
            ),
        ]),
      ),
    );
  }

  void _showEmojiReact(BuildContext ctx) {
    const emojis = ['❤️', '😂', '😮', '😢', '👏', '🔥'];
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: emojis.map((e) => GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _reply.text = e;
                _sendReply(ctx);
              },
              child: Text(e, style: const TextStyle(fontSize: 32)),
            )).toList(),
          ),
        ),
      ),
    );
  }
}
