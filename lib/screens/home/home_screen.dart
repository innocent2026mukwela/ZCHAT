import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/chat_service.dart';
import '../../services/call_service.dart';
import '../../utils/glass.dart';
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
                          if (v == 'profile') context.push('/profile');
                          if (v == 'new_group') context.push('/new-group');
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'new_group',    child: Text('New group',      style: TextStyle(color: Colors.white.withAlpha(220)))),
                          PopupMenuItem(value: 'starred',      child: Text('Starred messages',style: TextStyle(color: Colors.white.withAlpha(220)))),
                          PopupMenuItem(value: 'profile',      child: Text('Profile',        style: TextStyle(color: Colors.white.withAlpha(220)))),
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
    final routes = ['/new-chat', '', ''];
    return FloatingActionButton(
      backgroundColor: const Color(0xFF2563EB),
      elevation: 8,
      onPressed: () { if (routes[tab].isNotEmpty) context.push(routes[tab]); },
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
                    Text(
                      _query.isNotEmpty ? 'No chats found' : 'No conversations yet\nTap ✏️ to start one',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 15, height: 1.5),
                    ),
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
      builder: (_) => _ChatOptionsSheet(name: name, onArchive: onArchive),
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
  final String name;
  final VoidCallback onArchive;
  const _ChatOptionsSheet({required this.name, required this.onArchive});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
        decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 8),
      ListTile(
        leading: const Icon(Icons.push_pin_outlined, color: Colors.white70),
        title: const Text('Pin chat', style: TextStyle(color: Colors.white)),
        onTap: () => Navigator.pop(context)),
      ListTile(
        leading: const Icon(Icons.notifications_off_outlined, color: Colors.white70),
        title: const Text('Mute notifications', style: TextStyle(color: Colors.white)),
        onTap: () => Navigator.pop(context)),
      ListTile(
        leading: const Icon(Icons.archive_outlined, color: Colors.white70),
        title: const Text('Archive', style: TextStyle(color: Colors.white)),
        onTap: () { Navigator.pop(context); onArchive(); }),
      ListTile(
        leading: const Icon(Icons.mark_chat_read_outlined, color: Colors.white70),
        title: const Text('Mark as read', style: TextStyle(color: Colors.white)),
        onTap: () => Navigator.pop(context)),
      ListTile(
        leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
        title: const Text('Delete chat', style: TextStyle(color: Colors.redAccent)),
        onTap: () => Navigator.pop(context)),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════
// STATUS TAB
// ══════════════════════════════════════════════════════════════════════
class _StatusTab extends StatelessWidget {
  const _StatusTab();

  static const _recent = [
    _StatusItem(name: 'Chanda Phiri',  time: '10 min ago',  count: 1, color: Color(0xFF1565C0)),
    _StatusItem(name: 'Dr. Mwale',     time: '32 min ago',  count: 3, color: Color(0xFF2E7D32)),
    _StatusItem(name: 'Study Squad',   time: '1 hour ago',  count: 2, color: Color(0xFF6A1B9A)),
    _StatusItem(name: 'Mulenga Banda', time: '2 hours ago', count: 1, color: Color(0xFFAD1457)),
  ];
  static const _muted = [
    _StatusItem(name: 'CS 3201 Group', time: '3 hours ago', count: 1, color: Color(0xFFE65100)),
    _StatusItem(name: 'Math 201',      time: 'Yesterday',   count: 2, color: Color(0xFF00695C)),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      children: [
        // My status
        _StatusRow(
          leading: Stack(children: [
            const CircleAvatar(radius: 26, backgroundColor: Color(0xFF2563EB),
              child: Icon(Icons.person_rounded, color: Colors.white, size: 28)),
            Positioned(bottom: 0, right: 0,
              child: Container(width: 20, height: 20,
                decoration: BoxDecoration(color: const Color(0xFF2563EB), shape: BoxShape.circle, border: Border.all(color: Colors.white.withAlpha(30), width: 2)),
                child: const Icon(Icons.add, color: Colors.white, size: 12))),
          ]),
          title: 'My status',
          subtitle: 'Tap to add status update',
          onTap: () => context.push('/status'),
        ),
        Divider(color: Colors.white.withAlpha(15), height: 1),
        _SectionHeader('Recent updates'),
        ..._recent.asMap().entries.map((e) => _StatusRow(
          leading: _StatusRing(item: e.value),
          title: e.value.name,
          subtitle: e.value.time,
          trailing: Text('${e.value.count} update${e.value.count != 1 ? 's' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(120))),
          onTap: () => _openViewer(context, e.value),
        ).animate(delay: (e.key * 40).ms).fadeIn()),
        _SectionHeader('Muted'),
        ..._muted.asMap().entries.map((e) => _StatusRow(
          leading: _StatusRing(item: e.value, muted: true),
          title: e.value.name,
          subtitle: e.value.time,
          onTap: () => _openViewer(context, e.value),
        ).animate(delay: (e.key * 40).ms).fadeIn()),
        const SizedBox(height: 80),
      ],
    );
  }

  void _openViewer(BuildContext context, _StatusItem item) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, __, ___) => _StatusViewer(item: item),
    ));
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

class _StatusRing extends StatelessWidget {
  final _StatusItem item;
  final bool muted;
  const _StatusRing({required this.item, this.muted = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2.5),
    decoration: BoxDecoration(
      gradient: muted ? null : const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF4F8AFF)]),
      color: muted ? Colors.white.withAlpha(60) : null,
      shape: BoxShape.circle,
    ),
    child: CircleAvatar(radius: 26, backgroundColor: item.color,
      child: Text(item.name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18))),
  );
}

class _StatusItem {
  final String name, time;
  final int count;
  final Color color;
  const _StatusItem({required this.name, required this.time, required this.count, required this.color});
}

class _StatusViewer extends StatefulWidget {
  final _StatusItem item;
  const _StatusViewer({required this.item});
  @override
  State<_StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<_StatusViewer> with SingleTickerProviderStateMixin {
  late AnimationController _prog;
  final _reply = TextEditingController();
  int _cur = 0;
  final _texts = ['Studying hard for finals! 📚', 'Library life 🏛️', 'Coffee + notes = success ☕'];

  @override
  void initState() {
    super.initState();
    _prog = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (_cur < widget.item.count - 1) { setState(() => _cur++); _prog.forward(from: 0); }
          else Navigator.of(context).pop();
        }
      })..forward();
  }

  @override
  void dispose() { _prog.dispose(); _reply.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (d) {
          final half = MediaQuery.of(context).size.width / 2;
          if (d.globalPosition.dx < half) { if (_cur > 0) { setState(() => _cur--); _prog.forward(from: 0); } }
          else { if (_cur < widget.item.count - 1) { setState(() => _cur++); _prog.forward(from: 0); } else Navigator.of(context).pop(); }
        },
        child: Stack(children: [
          Container(width: double.infinity, height: double.infinity, color: widget.item.color.withAlpha(216),
            child: Center(child: Text(_texts[_cur % _texts.length],
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600), textAlign: TextAlign.center)
                .animate().fadeIn(duration: 300.ms))),
          SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: List.generate(widget.item.count, (i) => Expanded(
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ClipRRect(borderRadius: BorderRadius.circular(2),
                    child: i < _cur ? Container(height: 3, color: Colors.white)
                      : i == _cur ? AnimatedBuilder(animation: _prog,
                          builder: (ctx2, s) => LinearProgressIndicator(value: _prog.value,
                            backgroundColor: Colors.white38, valueColor: const AlwaysStoppedAnimation(Colors.white), minHeight: 3))
                      : Container(height: 3, color: Colors.white38))))))),
            Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(children: [
                CircleAvatar(radius: 18, backgroundColor: widget.item.color,
                  child: Text(widget.item.name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(widget.item.time, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
                IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
              ])),
          ])),
          Positioned(bottom: 0, left: 0, right: 0,
            child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(24)),
                  child: TextField(controller: _reply, style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'Reply…', hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero, filled: false)))),
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
              ])))),
        ]),
      ),
    );
  }
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
        final calls = snap.data ?? [];
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)));
        }
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
                  icon: Icon(isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                      color: const Color(0xFF4F8AFF), size: 22),
                  onPressed: () async {
                    final otherUid = isCaller
                        ? call['calleeUid'] as String? ?? ''
                        : call['callerUid'] as String? ?? '';
                    if (otherUid.isEmpty) return;
                    final chatId = await ChatService.getOrCreateChat(otherUid);
                    if (ctx2.mounted) {
                      context.push('/chats/$chatId?name=${Uri.encodeComponent(name)}');
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
