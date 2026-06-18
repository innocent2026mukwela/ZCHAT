import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../services/chat_service.dart';
import '../../services/call_service.dart';
import '../../services/status_service.dart';
import '../../utils/glass.dart';
import '../../utils/helpers.dart';
import '../../widgets/bottom_nav_bar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static final _chatsKey = GlobalKey<_ChatsTabState>();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(gradient: kBgGradient),
          child: Stack(
            children: [
              const GlowOrbs(),
              Column(
                children: [
                  _GlassHomeAppBar(onSearchTap: () => _chatsKey.currentState?._toggleSearch()),
                  Expanded(
                    child: TabBarView(
                      children: [_ChatsTab(key: _chatsKey), const _StatusTab(), const _CallsTab()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        floatingActionButton: _HomeFab(),
        bottomNavigationBar: const AppBottomNavBar(),
      ),
    );
  }
}

// ── Glass app bar with tabs ───────────────────────────────────────────
class _GlassHomeAppBar extends StatelessWidget {
  final VoidCallback? onSearchTap;
  const _GlassHomeAppBar({this.onSearchTap});

  static const _brandAsset = 'assets/icons/zchat_logo_cutout.png';

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(12),
            border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Title row
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                  child: Row(
                    children: [
                      // ZCHAT brand
                      Image.asset(
                        _brandAsset,
                        width: 108,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Text(
                            'ZCHAT',
                            style: TextStyle(
                              color: Color(0xFF2EA3FF),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          );
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.search_rounded, color: Colors.white),
                        onPressed: onSearchTap,
                      ),
                      IconButton(
                        icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
                        onPressed: () => context.push('/status'),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                        color: const Color(0xFF0A1A4A),
                        onSelected: (v) {
                          if (v == 'profile')     context.push('/profile');
                          if (v == 'new_group')   context.push('/new-group');
                          if (v == 'starred')     context.push('/starred');
                          if (v == 'broadcasts')  context.push('/broadcasts');
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'new_group',   child: Text('New group',          style: TextStyle(color: Colors.white.withAlpha(220)))),
                          PopupMenuItem(value: 'broadcasts',  child: Text('Broadcast channels', style: TextStyle(color: Colors.white.withAlpha(220)))),
                          PopupMenuItem(value: 'starred',     child: Text('Starred messages',   style: TextStyle(color: Colors.white.withAlpha(220)))),
                          PopupMenuItem(value: 'profile',     child: Text('Profile',            style: TextStyle(color: Colors.white.withAlpha(220)))),
                        ],
                      ),
                    ],
                  ),
                ),
                // Tabs with missed-call badge
                StreamBuilder<int>(
                  stream: CallService.missedCallsCountStream(),
                  builder: (ctx, snap) {
                    final missed = snap.data ?? 0;
                    return TabBar(
                      indicatorColor: const Color(0xFF4F8AFF),
                      indicatorWeight: 2.5,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white.withAlpha(110),
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.8),
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
                      dividerColor: Colors.transparent,
                      tabs: [
                        const Tab(text: 'CHATS'),
                        const Tab(text: 'STATUS'),
                        Tab(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Text('CALLS', style: TextStyle(fontSize: 13, letterSpacing: 0.8)),
                            if (missed > 0) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('$missed',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ]),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── FAB ───────────────────────────────────────────────────────────────
class _HomeFab extends StatefulWidget {
  @override
  State<_HomeFab> createState() => _HomeFabState();
}

class _HomeFabState extends State<_HomeFab> {
  @override
  Widget build(BuildContext context) {
    final tab = DefaultTabController.of(context).index;
    final icons  = [Icons.edit_rounded, Icons.camera_alt_rounded, Icons.add_call];
    final routes = ['/new-chat', '/status', '/calls'];
    return FloatingActionButton(
      backgroundColor: const Color(0xFF2563EB),
      elevation: 8,
      onPressed: () => context.push(routes[tab]),
      child: Icon(icons[tab], color: Colors.white),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// CHATS TAB
// ══════════════════════════════════════════════════════════════════════
class _ChatsTab extends StatefulWidget {
  const _ChatsTab({super.key});
  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> {
  bool _searching = false;
  String _query = '';
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _archived = <String>{};

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) { _query = ''; _searchCtrl.clear(); }
      else { WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus()); }
    });
  }

  void _archiveChat(String chatId) {
    setState(() => _archived.add(chatId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Chat archived'),
        backgroundColor: const Color(0xFF0A1A4A),
        action: SnackBarAction(
          label: 'Undo',
          textColor: const Color(0xFF4F8AFF),
          onPressed: () => setState(() => _archived.remove(chatId)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _searching
              ? Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(18),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withAlpha(30)),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 12),
                    Icon(Icons.search_rounded, color: Colors.white.withAlpha(140), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Search chats…',
                          hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          filled: false,
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: Colors.white.withAlpha(140), size: 20),
                      onPressed: _toggleSearch,
                    ),
                  ]),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: ChatService.chatsStream(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F8AFF)));
              }

              var chats = (snap.data ?? [])
                  .where((c) => !_archived.contains(c['id'] as String?))
                  .toList();

              if (_query.isNotEmpty) {
                final q = _query.toLowerCase();
                chats = chats.where((c) {
                  final name = ChatService.getChatDisplayName(c).toLowerCase();
                  final msg  = (c['lastMessage'] as String? ?? '').toLowerCase();
                  return name.contains(q) || msg.contains(q);
                }).toList();
              }

              if (chats.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 56, color: Colors.white.withAlpha(40)),
                    const SizedBox(height: 14),
                    if (_query.isNotEmpty)
                      Text('No chats found',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 15))
                    else
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('No conversations yet  Tap ',
                          style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 15)),
                        Icon(Icons.edit_rounded, size: 16, color: Colors.white.withAlpha(100)),
                        Text(' to start one',
                          style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 15)),
                      ]),
                  ]),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 80),
                itemCount: chats.length,
                itemBuilder: (ctx, i) {
                  final chat = chats[i];
                  final chatId   = chat['id'] as String? ?? '';
                  final name     = ChatService.getChatDisplayName(chat);
                  final msg      = chat['lastMessage'] as String? ?? '';
                  final unread   = ChatService.getUnreadCount(chat);
                  final isGroup  = chat['type'] == 'group';
                  final isPinned = ChatService.isPinned(chat);
                  final isMuted  = ChatService.isMuted(chat);
                  final ts       = chat['lastTime'] as Timestamp?;
                  final time     = ChatService.formatTime(ts);

                  return _ChatTile(
                    key: ValueKey(chatId),
                    chatId: chatId,
                    name: name,
                    msg: msg,
                    time: time,
                    unread: unread,
                    isGroup: isGroup,
                    isPinned: isPinned,
                    isMuted: isMuted,
                    index: i,
                    onArchive: () => _archiveChat(chatId),
                    searchQuery: _query,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String chatId;
  final String name;
  final String msg;
  final String time;
  final int unread;
  final bool isGroup;
  final bool isPinned;
  final bool isMuted;
  final int index;
  final VoidCallback onArchive;
  final String searchQuery;

  const _ChatTile({
    super.key,
    required this.chatId,
    required this.name,
    required this.msg,
    required this.time,
    required this.unread,
    required this.isGroup,
    required this.isPinned,
    required this.isMuted,
    required this.index,
    required this.onArchive,
    required this.searchQuery,
  });

  static const _colors = [Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A), Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C)];
  Color get _color => _colors[name.codeUnitAt(0) % _colors.length];

  @override
  Widget build(BuildContext context) {
    final hasUnread = unread > 0;

    return Dismissible(
      key: ValueKey('dismiss_$chatId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: const Color(0xFF1E3A5F),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.archive_outlined, color: Colors.white, size: 26),
          const SizedBox(height: 4),
          Text('Archive', style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12)),
        ]),
      ),
      confirmDismiss: (_) async {
        onArchive();
        return false;
      },
      child: InkWell(
        onTap: () => context.push('/chats/${Uri.encodeComponent(chatId)}?name=${Uri.encodeComponent(name)}'),
        onLongPress: () => _showOptions(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withAlpha(12))),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 26, backgroundColor: _color,
              child: isGroup
                  ? const Icon(Icons.group_rounded, color: Colors.white, size: 22)
                  : Text(name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: _HighlightText(
                    text: name,
                    query: searchQuery,
                    style: TextStyle(fontSize: 15, fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500, color: Colors.white),
                  )),
                  Text(time,
                    style: TextStyle(fontSize: 12,
                      color: hasUnread ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(120),
                      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(child: _HighlightText(
                    text: msg.isEmpty ? 'No messages yet' : msg,
                    query: searchQuery,
                    style: TextStyle(fontSize: 13,
                      color: hasUnread ? Colors.white.withAlpha(220) : Colors.white.withAlpha(140),
                      fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal),
                  )),
                  if (hasUnread) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                      child: Text('$unread',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ]),
            ),
          ]),
        ),
      ),
    ).animate(delay: (index * 25).ms).fadeIn();
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1A4A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ChatOptionsSheet(
        chatId: chatId,
        name: name,
        isPinned: isPinned,
        isMuted: isMuted,
        unread: unread,
        onArchive: onArchive,
      ),
    );
  }
}

// Highlights matching query text in yellow
class _HighlightText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  const _HighlightText({required this.text, required this.query, required this.style});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx == -1) return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Text.rich(
      TextSpan(children: [
        if (idx > 0) TextSpan(text: text.substring(0, idx), style: style),
        TextSpan(
          text: text.substring(idx, idx + q.length),
          style: style.copyWith(
            backgroundColor: const Color(0xFFFFD700).withAlpha(80),
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (idx + q.length < text.length)
          TextSpan(text: text.substring(idx + q.length), style: style),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _ChatOptionsSheet extends StatelessWidget {
  final String chatId;
  final String name;
  final bool isPinned;
  final bool isMuted;
  final int unread;
  final VoidCallback onArchive;

  const _ChatOptionsSheet({
    required this.chatId,
    required this.name,
    required this.isPinned,
    required this.isMuted,
    required this.unread,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      ),
      Divider(color: Colors.white.withAlpha(15), height: 1),
      ListTile(
        leading: Icon(isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: Colors.white70),
        title: Text(isPinned ? 'Unpin chat' : 'Pin chat', style: const TextStyle(color: Colors.white)),
        onTap: () { Navigator.pop(context); ChatService.togglePin(chatId, isPinned); }),
      ListTile(
        leading: Icon(isMuted ? Icons.notifications_outlined : Icons.notifications_off_outlined, color: Colors.white70),
        title: Text(isMuted ? 'Unmute' : 'Mute notifications', style: const TextStyle(color: Colors.white)),
        onTap: () { Navigator.pop(context); ChatService.muteChat(chatId, !isMuted); }),
      ListTile(
        leading: const Icon(Icons.archive_outlined, color: Colors.white70),
        title: const Text('Archive', style: TextStyle(color: Colors.white)),
        onTap: () { Navigator.pop(context); onArchive(); }),
      ListTile(
        leading: Icon(unread > 0 ? Icons.mark_chat_read_outlined : Icons.mark_chat_unread_outlined, color: Colors.white70),
        title: Text(unread > 0 ? 'Mark as read' : 'Mark as unread', style: const TextStyle(color: Colors.white)),
        onTap: () {
          Navigator.pop(context);
          if (unread > 0) { ChatService.markRead(chatId); } else { ChatService.markUnread(chatId); }
        }),
      ListTile(
        leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
        title: const Text('Delete chat', style: TextStyle(color: Colors.redAccent)),
        onTap: () async {
          Navigator.pop(context);
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF0A1A4A),
              title: const Text('Delete chat?', style: TextStyle(color: Colors.white)),
              content: Text('This will delete all messages with $name.',
                  style: TextStyle(color: Colors.white.withAlpha(180))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          );
          if (ok == true) ChatService.deleteChat(chatId);
        }),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════
// STATUS TAB
// ══════════════════════════════════════════════════════════════════════
class _StatusTab extends StatefulWidget {
  const _StatusTab();
  @override
  State<_StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<_StatusTab> {
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  List<Map<String, dynamic>> _myItems        = [];
  List<Map<String, dynamic>> _contactStatuses = [];
  Map<String, dynamic>?      _myProfile;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
    StatusService.myStatusStream().listen((items) {
      if (mounted) setState(() => _myItems = items);
    });
    _loadContacts();
  }

  Future<void> _loadMyProfile() async {
    if (_myUid.isEmpty) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(_myUid).get();
    if (mounted) setState(() => _myProfile = doc.data());
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    try {
      final uids = await _zchatContactUids();
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
      final snap = await FirebaseFirestore.instance
          .collection('users').where('phoneNumber', whereIn: chunk).get();
      for (final doc in snap.docs) {
        if (doc.id != _myUid) uids.add(doc.id);
      }
    }
    return uids;
  }

  @override
  Widget build(BuildContext context) {
    final myName     = _myProfile?['displayName'] as String? ?? _myProfile?['fullName'] as String? ?? 'My status';
    final myPhoto    = _myProfile?['photoUrl'] as String? ?? '';
    final mySubtitle = _myItems.isEmpty
        ? 'Tap to add status update'
        : 'My update · ${timeago.format((_myItems.last['createdAt'] as dynamic)?.toDate() ?? DateTime.now())}';

    final recent = _contactStatuses.where((s) => s['hasUnread'] == true).toList();
    final viewed = _contactStatuses.where((s) => s['hasUnread'] != true).toList();

    return RefreshIndicator(
      onRefresh: _loadContacts,
      color: const Color(0xFF4F8AFF),
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        children: [
          // My status
          _StatusRow(
            leading: Stack(children: [
              CircleAvatar(radius: 26,
                backgroundColor: const Color(0xFF2563EB),
                backgroundImage: myPhoto.isNotEmpty ? NetworkImage(myPhoto) : null,
                child: myPhoto.isEmpty ? const Icon(Icons.person_rounded, color: Colors.white, size: 28) : null),
              Positioned(bottom: 0, right: 0,
                child: Container(width: 20, height: 20,
                  decoration: BoxDecoration(color: const Color(0xFF2563EB), shape: BoxShape.circle, border: Border.all(color: Colors.white.withAlpha(30), width: 2)),
                  child: const Icon(Icons.add, color: Colors.white, size: 12))),
            ]),
            title: myName,
            subtitle: mySubtitle,
            onTap: () => context.push('/status'),
          ),
          Divider(color: Colors.white.withAlpha(15), height: 1),

          if (_loading)
            const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF))))
          else if (_loadError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline_rounded, color: Colors.redAccent.withAlpha(180), size: 36),
                const SizedBox(height: 10),
                Text(_loadError!, textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13)),
                const SizedBox(height: 12),
                TextButton(onPressed: _loadContacts, child: const Text('Retry', style: TextStyle(color: Color(0xFF4F8AFF)))),
              ]),
            )
          else if (_contactStatuses.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(child: Text('No recent updates from contacts',
                style: TextStyle(color: Colors.white.withAlpha(120)))),
            )
          else ...[
            if (recent.isNotEmpty) ...[
              _SectionHeader('Recent updates'),
              ...recent.asMap().entries.map((e) {
                final s     = e.value;
                final items = s['items'] as List? ?? [];
                final ts    = items.isNotEmpty ? (items.last['createdAt'] as dynamic)?.toDate() : null;
                final time  = ts != null ? timeago.format(ts) : '';
                return _StatusRow(
                  leading: _LiveStatusRing(photoUrl: s['photoUrl'] as String? ?? '', name: s['name'] as String? ?? '', hasUnread: true),
                  title: s['name'] as String? ?? '',
                  subtitle: time,
                  trailing: Text('${items.length} update${items.length != 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(120))),
                  onTap: () => context.push('/status'),
                ).animate(delay: (e.key * 40).ms).fadeIn();
              }),
            ],
            if (viewed.isNotEmpty) ...[
              _SectionHeader('Viewed'),
              ...viewed.asMap().entries.map((e) {
                final s     = e.value;
                final items = s['items'] as List? ?? [];
                final ts    = items.isNotEmpty ? (items.last['createdAt'] as dynamic)?.toDate() : null;
                final time  = ts != null ? timeago.format(ts) : '';
                return _StatusRow(
                  leading: _LiveStatusRing(photoUrl: s['photoUrl'] as String? ?? '', name: s['name'] as String? ?? '', hasUnread: false),
                  title: s['name'] as String? ?? '',
                  subtitle: time,
                  onTap: () => context.push('/status'),
                ).animate(delay: (e.key * 40).ms).fadeIn();
              }),
            ],
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withAlpha(140), letterSpacing: 0.6)),
  );
}

class _StatusRow extends StatelessWidget {
  final Widget leading;
  final String title, subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  const _StatusRow({required this.leading, required this.title, required this.subtitle, this.trailing, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withAlpha(10)))),
      child: Row(children: [
        leading,
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(140))),
        ])),
        if (trailing != null) trailing!,
      ]),
    ),
  );
}

class _LiveStatusRing extends StatelessWidget {
  final String photoUrl, name;
  final bool hasUnread;
  const _LiveStatusRing({required this.photoUrl, required this.name, required this.hasUnread});

  static const _palette = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
    Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
  ];

  Color get _color => name.isEmpty ? _palette[0] : _palette[name.codeUnitAt(0) % _palette.length];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2.5),
    decoration: BoxDecoration(
      gradient: hasUnread ? const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF4F8AFF)]) : null,
      color: hasUnread ? null : Colors.white.withAlpha(60),
      shape: BoxShape.circle,
    ),
    child: CircleAvatar(
      radius: 26,
      backgroundColor: _color,
      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
      child: photoUrl.isEmpty
          ? Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18))
          : null,
    ),
  );
}


// ══════════════════════════════════════════════════════════════════════
// CALLS TAB
// ══════════════════════════════════════════════════════════════════════
class _CallsTab extends StatelessWidget {
  const _CallsTab();

  static const _colors = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
    Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
  ];

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CallService.callHistoryStream(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)));
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load calls',
              style: TextStyle(color: Colors.white.withAlpha(120))));
        }
        final calls = snap.data ?? [];
        if (calls.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.call_outlined, size: 52, color: Colors.white.withAlpha(60)),
              const SizedBox(height: 12),
              Text('No recent calls',
                  style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 15)),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          itemCount: calls.length,
          itemBuilder: (ctx2, i) {
            final call     = calls[i];
            final isCaller = call['callerUid'] == myUid;
            final status   = call['status'] as String? ?? '';
            final missed   = status == 'missed' || status == 'declined';
            final isVideo  = call['type'] == 'video';
            final name     = isCaller
                ? (call['calleeName'] as String? ?? 'Unknown')
                : (call['callerName'] as String? ?? 'Unknown');
            final dur      = CallService.formatDuration(call['duration'] as int?);
            final time     = CallService.formatCallTime(call['startedAt'] as Timestamp?);
            final color    = _colors[name.codeUnitAt(0) % _colors.length];

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withAlpha(12)))),
              child: Row(children: [
                CircleAvatar(
                  radius: 26, backgroundColor: color,
                  child: Text(name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 18)),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15,
                        color: missed ? Colors.redAccent : Colors.white)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(
                        isCaller ? Icons.call_made_rounded : Icons.call_received_rounded,
                        size: 13,
                        color: missed ? Colors.redAccent : const Color(0xFF4F8AFF),
                      ),
                      const SizedBox(width: 4),
                      if (isVideo) ...[
                        Icon(Icons.videocam_outlined, size: 13,
                            color: Colors.white.withAlpha(120)),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        dur.isNotEmpty ? '$time  ·  $dur' : time,
                        style: TextStyle(fontSize: 12,
                            color: missed
                                ? Colors.redAccent.withAlpha(200)
                                : Colors.white.withAlpha(140)),
                      ),
                    ]),
                  ],
                )),
                IconButton(
                  icon: const Icon(Icons.message_outlined,
                      color: Color(0xFF4F8AFF), size: 22),
                  tooltip: 'Message',
                  onPressed: () async {
                    final otherUid = isCaller
                        ? call['calleeUid'] as String? ?? ''
                        : call['callerUid'] as String? ?? '';
                    if (otherUid.isEmpty) return;
                    final chatId = await ChatService.getOrCreateChat(otherUid);
                    if (ctx2.mounted) {
                      context.push('/chats/${Uri.encodeComponent(chatId)}?name=${Uri.encodeComponent(name)}');
                    }
                  },
                ),
              ]),
            ).animate(delay: (i * 35).ms).fadeIn();
          },
        );
      },
    );
  }
}
