import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/communities_service.dart';
import '../../services/chat_service.dart';
import '../../utils/glass.dart';

class CommunityDetailScreen extends StatelessWidget {
  final String communityId;
  const CommunityDetailScreen({super.key, required this.communityId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('communities').doc(communityId).snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)));
              }
              if (!snap.data!.exists) {
                return const Center(child: Text('Community not found', style: TextStyle(color: Colors.white70)));
              }
              final c = {...snap.data!.data()!, 'id': communityId};
              return _body(context, c);
            },
          ),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> c) {
    final name    = c['name'] as String? ?? 'Community';
    final desc    = c['desc'] as String? ?? c['description'] as String? ?? '';
    final members = (c['memberUids'] as List?)?.length ?? 0;
    final admin   = CommunitiesService.isAdmin(c);
    final annId   = c['announcementChatId'] as String? ?? '';
    final subtitle = [c['school'], c['program']].where((s) => s != null && (s as String).isNotEmpty).join(' · ');

    return Column(children: [
      // Header
      ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: Container(
        decoration: BoxDecoration(color: Colors.white.withAlpha(12), border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20)))),
        child: SafeArea(bottom: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 14),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.pop()),
            Container(width: 44, height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(45), borderRadius: BorderRadius.circular(12)),
              child: Text(c['icon'] as String? ?? '🏛️', style: const TextStyle(fontSize: 22))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('$members member${members == 1 ? '' : 's'}${subtitle.isNotEmpty ? ' · $subtitle' : ''}',
                  style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              color: const Color(0xFF0A1A4A),
              onSelected: (v) async {
                if (v == 'leave') {
                  await CommunitiesService.leave(communityId);
                  if (context.mounted) context.pop();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'leave', child: Text('Leave community', style: TextStyle(color: Colors.redAccent.withAlpha(230)))),
              ],
            ),
          ]),
        )),
      ))),

      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
        if (desc.isNotEmpty) ...[
          Text(desc, style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 13, height: 1.4)),
          const SizedBox(height: 16),
        ],
        // Announcements
        Text('ANNOUNCEMENTS', style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        const SizedBox(height: 8),
        _tile(context, icon: Icons.campaign_rounded, color: const Color(0xFFFB923C),
          title: '$name · Announcements', subtitle: admin ? 'You can post here' : 'Admins post here',
          onTap: annId.isEmpty ? null : () => context.push('/chats/${Uri.encodeComponent(annId)}?name=${Uri.encodeComponent('$name · Announcements')}')),
        const SizedBox(height: 18),
        // Groups
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('GROUPS', style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          if (admin) TextButton.icon(
            onPressed: () => _linkGroup(context, c),
            icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF4F8AFF)),
            label: const Text('Link a group', style: TextStyle(color: Color(0xFF4F8AFF), fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 4),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: CommunitiesService.groups(c),
          builder: (ctx, gs) {
            final groups = gs.data ?? [];
            if (gs.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF))));
            }
            if (groups.isEmpty) {
              return Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(admin ? 'No groups linked yet. Tap "Link a group".' : 'No groups yet.',
                    style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 13)));
            }
            return Column(children: groups.map((g) {
              final gname = g['name'] as String? ?? 'Group';
              return _tile(context, icon: Icons.group_rounded, color: const Color(0xFF4F8AFF),
                title: gname, subtitle: 'Group chat',
                onTap: () async {
                  await CommunitiesService.joinGroupChat(g['id'] as String);
                  if (context.mounted) context.push('/chats/${Uri.encodeComponent(g['id'] as String)}?name=${Uri.encodeComponent(gname)}');
                });
            }).toList());
          },
        ),
      ])),
    ]);
  }

  Widget _tile(BuildContext context, {required IconData icon, required Color color, required String title, required String subtitle, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        borderRadius: BorderRadius.circular(14),
        padding: EdgeInsets.zero,
        child: ListTile(
          onTap: onTap,
          leading: Container(width: 42, height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withAlpha(45), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20)),
          title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 12)),
          trailing: Icon(Icons.chevron_right_rounded, color: Colors.white.withAlpha(90)),
        ),
      ),
    );
  }

  Future<void> _linkGroup(BuildContext context, Map<String, dynamic> c) async {
    final chats = await ChatService.chatsStream().first;
    final groups = chats.where((ch) => ch['type'] == 'group').toList();
    final linked = List<String>.from(c['groupChatIds'] as List? ?? []);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2))),
        const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('Link a group', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)))),
        if (groups.isEmpty)
          Padding(padding: const EdgeInsets.all(20), child: Text('You have no group chats to link. Create a group first.', style: TextStyle(color: Colors.white.withAlpha(140)))),
        Flexible(child: ListView(shrinkWrap: true, children: groups.map((g) {
          final gid = g['id'] as String;
          final already = linked.contains(gid);
          return ListTile(
            leading: const Icon(Icons.group_rounded, color: Colors.white70),
            title: Text(g['name'] as String? ?? 'Group', style: const TextStyle(color: Colors.white)),
            trailing: already ? const Icon(Icons.check_rounded, color: Color(0xFF86EFAC)) : const Icon(Icons.add_rounded, color: Color(0xFF4F8AFF)),
            onTap: already ? null : () async { await CommunitiesService.linkGroup(c['id'] as String, gid); if (context.mounted) Navigator.pop(context); },
          );
        }).toList())),
        const SizedBox(height: 8),
      ])),
    );
  }
}
