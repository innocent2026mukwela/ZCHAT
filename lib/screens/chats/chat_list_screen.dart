import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/chat_service.dart';
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

// ── Tab enum ──────────────────────────────────────────────────────────────────

enum _Tab { all, unread, groups, archived }

// ── Chat List Screen ──────────────────────────────────────────────────────────

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin {
  String _search    = '';
  bool   _searching = false;
  _Tab   _tab       = _Tab.all;
  final  _searchCtrl = TextEditingController();
  final  _myUid      = FirebaseAuth.instance.currentUser?.uid ?? '';
  late   TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() => _tab = _Tab.values[_tabCtrl.index]);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;
    context.push('/new-chat', extra: {'imagePath': picked.path});
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> all) {
    var list = all;

    // Tab filter
    switch (_tab) {
      case _Tab.unread:
        list = list.where((c) =>
            !ChatService.isArchived(c) && ChatService.getUnreadCount(c) > 0).toList();
        break;
      case _Tab.groups:
        list = list.where((c) =>
            !ChatService.isArchived(c) && (c['type'] as String?) == 'group').toList();
        break;
      case _Tab.archived:
        list = list.where((c) => ChatService.isArchived(c)).toList();
        break;
      case _Tab.all:
        list = list.where((c) => !ChatService.isArchived(c)).toList();
        break;
    }

    // Search filter
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((c) {
        final name = ChatService.getChatDisplayName(c).toLowerCase();
        final last = (c['lastMessage'] as String? ?? '').toLowerCase();
        return name.contains(q) || last.contains(q);
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
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
            _buildHeader(),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: ChatService.chatsStream(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(
                        color: Color(0xFF4F8AFF), strokeWidth: 2));
                  }

                  final allData = snap.data ?? [];
                  final chats   = _filter(allData);
                  final currentTab = _Tab.values[_tabCtrl.index];
                  final archivedCount = currentTab == _Tab.all
                      ? allData.where(ChatService.isArchived).length
                      : 0;

                  if (chats.isEmpty && archivedCount == 0) return _buildEmpty();

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: chats.length + (archivedCount > 0 ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      // First row on All tab: archived banner
                      if (archivedCount > 0 && i == 0) {
                        return _ArchivedBanner(
                          count: archivedCount,
                          onTap: () => _tabCtrl.animateTo(3),
                        );
                      }
                      final idx = archivedCount > 0 ? i - 1 : i;
                      return _ChatTile(
                        chat:  chats[idx],
                        myUid: _myUid,
                        index: idx,
                        onAction: () => setState(() {}),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ]),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'fab_group',
            onPressed: () => context.push('/new-group'),
            backgroundColor: const Color(0xFF0E1829),
            foregroundColor: Colors.white,
            child: const Icon(Icons.group_add_rounded, size: 20),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'fab_chat',
            onPressed: () => context.push('/new-chat'),
            backgroundColor: const Color(0xFF2563EB),
            child: const Icon(Icons.edit_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => context.go('/home'),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                const Text('Chats', style: TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.camera_alt_outlined,
                      color: Colors.white.withAlpha(200)),
                  onPressed: _openCamera,
                ),
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
                  icon: Icon(Icons.more_vert_rounded,
                      color: Colors.white.withAlpha(200)),
                  onPressed: () => context.push('/new-chat'),
                ),
              ]),
            ),
            // Search bar
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _searching
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
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
                            hintText: 'Search chats…',
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
            // Tabs
            TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: const Color(0xFF4F8AFF),
              indicatorWeight: 2,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'All'),
                Tab(text: 'Unread'),
                Tab(text: 'Groups'),
                Tab(text: 'Archived'),
              ],
            ),
          ])),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final labels = {
      _Tab.all:      ('No chats yet', 'Tap the pencil icon to start a conversation.'),
      _Tab.unread:   ('No unread chats', 'You\'re all caught up!'),
      _Tab.groups:   ('No group chats', 'Start a group from the new chat screen.'),
      _Tab.archived: ('No archived chats', 'Long-press a chat to archive it.'),
    };
    final (title, sub) = labels[_tab]!;
    if (_search.isNotEmpty) {
      return Center(child: Text('No chats match "$_search"',
          style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14)));
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_bubble_outline_rounded,
            size: 60, color: Colors.white.withAlpha(50)),
        const SizedBox(height: 16),
        Text(title, style: TextStyle(
            color: Colors.white.withAlpha(180), fontSize: 16,
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(sub, style: TextStyle(
            color: Colors.white.withAlpha(110), fontSize: 13)),
      ]),
    );
  }
}

// ── Chat Tile ─────────────────────────────────────────────────────────────────

// ── Archived banner ───────────────────────────────────────────────────────────

class _ArchivedBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _ArchivedBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(18)),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF4F8AFF).withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.archive_outlined, color: Color(0xFF4F8AFF), size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text('Archived',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF4F8AFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, color: Colors.white.withAlpha(120), size: 20),
      ]),
    ),
  );
}

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> chat;
  final String myUid;
  final int    index;
  final VoidCallback onAction;

  const _ChatTile({
    required this.chat,
    required this.myUid,
    required this.index,
    required this.onAction,
  });

  void _showOptions(BuildContext context) {
    HapticFeedback.mediumImpact();
    final chatId   = chat['id'] as String? ?? '';
    final isPinned = ChatService.isPinned(chat);
    final isArch   = ChatService.isArchived(chat);
    final unread   = ChatService.getUnreadCount(chat);
    final name     = ChatService.getChatDisplayName(chat);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(name, style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          Divider(color: Colors.white.withAlpha(15), height: 1),
          // Pin
          ListTile(
            leading: Icon(isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: Colors.white70),
            title: Text(isPinned ? 'Unpin chat' : 'Pin chat',
                style: const TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              ChatService.togglePin(chatId, isPinned);
              onAction();
            },
          ),
          // Archive
          ListTile(
            leading: Icon(isArch ? Icons.unarchive_outlined : Icons.archive_outlined,
                color: Colors.white70),
            title: Text(isArch ? 'Unarchive' : 'Archive',
                style: const TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              ChatService.toggleArchive(chatId, isArch);
              onAction();
            },
          ),
          // Mark as read/unread
          ListTile(
            leading: Icon(unread > 0
                ? Icons.mark_chat_read_outlined
                : Icons.mark_chat_unread_outlined,
                color: Colors.white70),
            title: Text(unread > 0 ? 'Mark as read' : 'Mark as unread',
                style: const TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              if (unread > 0) {
                ChatService.markRead(chatId);
              } else {
                ChatService.markUnread(chatId);
              }
              onAction();
            },
          ),
          // Delete
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: const Text('Delete chat',
                style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              Navigator.pop(context);
              ChatService.deleteChat(chatId);
              onAction();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name      = ChatService.getChatDisplayName(chat);
    final lastMsg   = chat['lastMessage'] as String? ?? '';
    final isGroup   = (chat['type'] as String?) == 'group';
    final unread    = ChatService.getUnreadCount(chat);
    final hasUnread = unread > 0;
    final isPinned  = ChatService.isPinned(chat);
    final ts        = chat['lastTime'] as Timestamp?;
    final timeStr   = _formatTime(ts);
    final chatId    = chat['id'] as String? ?? '';
    final col       = _avatarColor(name);
    final initials  = _initials(name);

    return Dismissible(
      key: ValueKey(chatId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(180),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
      ),
      confirmDismiss: (_) async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF0E1829),
            title: const Text('Delete chat?',
                style: TextStyle(color: Colors.white)),
            content: Text('This will remove you from "$name".',
                style: TextStyle(color: Colors.white.withAlpha(180))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        );
        if (confirm == true) ChatService.deleteChat(chatId);
        return confirm ?? false;
      },
      child: GestureDetector(
        onTap: () => context.push(
            '/chats/${Uri.encodeComponent(chatId)}?name=${Uri.encodeComponent(name)}'),
        onLongPress: () => _showOptions(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: hasUnread ? Colors.white.withAlpha(12) : Colors.white.withAlpha(6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: Colors.white.withAlpha(hasUnread ? 25 : 12)),
          ),
          child: Row(children: [
            // Avatar
            Stack(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: col,
                child: isGroup
                    ? const Icon(Icons.group_rounded,
                        color: Colors.white, size: 22)
                    : Text(initials, style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
              if (isPinned)
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F8AFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0A1A4A), width: 1.5),
                    ),
                    child: const Icon(Icons.push_pin_rounded,
                        color: Colors.white, size: 9),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            // Content
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(
                  color: Colors.white,
                  fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 15,
                )),
                const SizedBox(height: 3),
                Text(
                  lastMsg.isEmpty ? 'No messages yet' : lastMsg,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasUnread
                        ? Colors.white.withAlpha(200)
                        : Colors.white.withAlpha(120),
                    fontSize: 13,
                    fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ],
            )),
            const SizedBox(width: 8),
            // Trailing
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(timeStr, style: TextStyle(
                  fontSize: 11,
                  color: hasUnread
                      ? const Color(0xFF4F8AFF)
                      : Colors.white.withAlpha(100),
                  fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                )),
                const SizedBox(height: 5),
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$unread', style: const TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w700)),
                  )
                else
                  const SizedBox(height: 18),
              ],
            ),
          ]),
        ),
      ),
    ).animate(delay: (index * 40).ms).fadeIn().slideX(begin: 0.03, end: 0);
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt  = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}';
  }
}
