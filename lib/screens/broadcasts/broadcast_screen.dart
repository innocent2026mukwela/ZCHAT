import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../services/broadcast_service.dart';
import '../../utils/glass.dart';
import '../../widgets/bottom_nav_bar.dart';

// ── Broadcast list screen ─────────────────────────────────────────────────────

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});
  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Colors.white),
        title: const Text('Broadcast Channels',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFF4F8AFF),
          labelColor: const Color(0xFF4F8AFF),
          unselectedLabelColor: Colors.white54,
          tabs: const [Tab(text: 'Following'), Tab(text: 'Discover')],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          SafeArea(
            child: TabBarView(controller: _tabs, children: [
              _FollowingTab(),
              _DiscoverTab(),
            ]),
          ),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF4F8AFF),
        icon: const Icon(Icons.campaign_rounded, color: Colors.white),
        label: const Text('Create Channel', style: TextStyle(color: Colors.white)),
        onPressed: _createChannel,
      ),
      bottomNavigationBar: const AppBottomNavBar(),
    );
  }

  void _createChannel() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E1829),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('New Broadcast Channel', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _Field(ctrl: nameCtrl, hint: 'Channel name'),
          const SizedBox(height: 10),
          _Field(ctrl: descCtrl, hint: 'Description (optional)', maxLines: 2),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final id = await BroadcastService.createChannel(
                  nameCtrl.text.trim(), descCtrl.text.trim());
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => BroadcastChannelScreen(channelId: id,
                      channelName: nameCtrl.text.trim(), isAdmin: true),
                ));
              }
            },
            child: const Text('Create', style: TextStyle(color: Color(0xFF4F8AFF))),
          ),
        ],
      ),
    );
  }
}

class _FollowingTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BroadcastService.subscribedChannelsStream(),
      builder: (_, snap) {
        final channels = snap.data ?? [];
        if (channels.isEmpty) {
          return Center(child: Text('Not following any channels yet.',
              style: TextStyle(color: Colors.white.withAlpha(80))));
        }
        return ListView.builder(
          itemCount: channels.length,
          itemBuilder: (_, i) => _ChannelTile(channel: channels[i], myUid: uid),
        );
      },
    );
  }
}

class _DiscoverTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BroadcastService.discoverStream(),
      builder: (_, snap) {
        final channels = snap.data ?? [];
        if (channels.isEmpty) {
          return Center(child: Text('No channels yet.',
              style: TextStyle(color: Colors.white.withAlpha(80))));
        }
        return ListView.builder(
          itemCount: channels.length,
          itemBuilder: (_, i) => _ChannelTile(channel: channels[i], myUid: uid),
        );
      },
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final Map<String, dynamic> channel;
  final String myUid;
  const _ChannelTile({required this.channel, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final id       = channel['id'] as String;
    final name     = channel['name'] as String? ?? 'Channel';
    final desc     = channel['description'] as String? ?? '';
    final last     = channel['lastMessage'] as String? ?? '';
    final ts       = channel['lastTime'] as Timestamp?;
    final ago      = ts != null ? timeago.format(ts.toDate()) : '';
    final isAdmin  = channel['adminUid'] == myUid;
    final subs     = List<String>.from(channel['subscribers'] as List? ?? []);
    final isFollowing = subs.contains(myUid);

    return ListTile(
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF4F8AFF).withAlpha(30),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.campaign_rounded, color: Color(0xFF4F8AFF)),
      ),
      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(last.isNotEmpty ? last : desc,
          style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (ago.isNotEmpty)
          Text(ago, style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 11)),
        if (!isAdmin)
          Text(isFollowing ? 'Following' : 'Follow',
              style: TextStyle(
                color: isFollowing ? Colors.white54 : const Color(0xFF4F8AFF),
                fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => BroadcastChannelScreen(
            channelId: id, channelName: name, isAdmin: isAdmin),
      )),
    );
  }
}

// ── Broadcast channel screen ──────────────────────────────────────────────────

class BroadcastChannelScreen extends StatefulWidget {
  final String channelId, channelName;
  final bool isAdmin;
  const BroadcastChannelScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.isAdmin,
  });

  @override
  State<BroadcastChannelScreen> createState() => _BroadcastChannelScreenState();
}

class _BroadcastChannelScreenState extends State<BroadcastChannelScreen> {
  final _ctrl   = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final has = _ctrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Colors.white),
        title: Text(widget.channelName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          if (!widget.isAdmin)
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('broadcasts').doc(widget.channelId).snapshots(),
              builder: (_, snap) {
                final uid  = FirebaseAuth.instance.currentUser?.uid ?? '';
                final subs = List<String>.from(
                    snap.data?.get('subscribers') as List? ?? []);
                final following = subs.contains(uid);
                return TextButton(
                  onPressed: () => following
                      ? BroadcastService.unsubscribe(widget.channelId)
                      : BroadcastService.subscribe(widget.channelId),
                  child: Text(following ? 'Unfollow' : 'Follow',
                      style: TextStyle(
                          color: following ? Colors.white54 : const Color(0xFF4F8AFF))),
                );
              },
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Column(children: [
            const SizedBox(height: kToolbarHeight + 44),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: BroadcastService.messagesStream(widget.channelId),
                builder: (_, snap) {
                  final msgs = snap.data ?? [];
                  if (msgs.isEmpty) {
                    return Center(child: Text('No messages yet.',
                        style: TextStyle(color: Colors.white.withAlpha(80))));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final m  = msgs[i];
                      final ts = m['createdAt'] as Timestamp?;
                      final dt = ts?.toDate();
                      final time = dt != null
                          ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                          : '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withAlpha(15)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m['text'] as String? ?? '',
                              style: const TextStyle(color: Colors.white, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(time,
                              style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 11)),
                        ]),
                      ).animate().fadeIn(duration: 200.ms);
                    },
                  );
                },
              ),
            ),
            if (widget.isAdmin)
              _BroadcastInput(ctrl: _ctrl, hasText: _hasText,
                  onSend: () {
                    final t = _ctrl.text.trim();
                    if (t.isEmpty) return;
                    BroadcastService.sendBroadcast(widget.channelId, t);
                    _ctrl.clear();
                  }),
            if (!widget.isAdmin)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text('Only admins can send messages in this channel.',
                    style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 13),
                    textAlign: TextAlign.center),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _BroadcastInput extends StatelessWidget {
  final TextEditingController ctrl;
  final bool hasText;
  final VoidCallback onSend;
  const _BroadcastInput({required this.ctrl, required this.hasText, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          child: Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withAlpha(20)),
                ),
                child: TextField(
                  controller: ctrl,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 4, minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Broadcast a message…',
                    hintStyle: TextStyle(color: Colors.white.withAlpha(60)),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedOpacity(
              opacity: hasText ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: hasText ? onSend : null,
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4F8AFF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final int maxLines;
  const _Field({required this.ctrl, required this.hint, this.maxLines = 1});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withAlpha(60)),
      filled: true,
      fillColor: Colors.white.withAlpha(10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    ),
  );
}
