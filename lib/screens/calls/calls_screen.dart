import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import '../../services/call_service.dart';
import '../../services/chat_service.dart';
import '../../services/zego_service.dart';
import '../../utils/glass.dart';
import '../../widgets/bottom_nav_bar.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

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

// ── Launch helpers ────────────────────────────────────────────────────────────

void _launchZego(
  BuildContext context, {
  required String roomId,
  required bool video,
  bool isGroup = false,
}) {
  final me = FirebaseAuth.instance.currentUser!;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ZegoUIKitPrebuiltCall(
      appID:    kZegoAppId,
      appSign:  kZegoAppSign,
      userID:   me.uid,
      userName: me.displayName ?? me.uid,
      callID:   roomId,
      config:   isGroup
          ? (video
              ? ZegoUIKitPrebuiltCallConfig.groupVideoCall()
              : ZegoUIKitPrebuiltCallConfig.groupVoiceCall())
          : (video
              ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
              : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall()),
    ),
  ));
}

Future<List<Map<String, dynamic>>> _loadZchatContacts() async {
  final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final status = await Permission.contacts.request();

  if (!status.isGranted) {
    final snap = await FirebaseFirestore.instance
        .collection('users').limit(50).get();
    return snap.docs
        .where((d) => d.id != myUid)
        .map((d) => <String, dynamic>{'uid': d.id, ...d.data()})
        .toList();
  }

  final contacts = await FlutterContacts.getAll(properties: ContactProperties.allProperties);
  final phones   = <String>{};
  for (final c in contacts) {
    for (final p in c.phones) {
      final n = _e164(p.number);
      if (n.isNotEmpty) phones.add(n);
    }
  }

  final result = <Map<String, dynamic>>[];
  final list   = phones.toList();
  for (int i = 0; i < list.length; i += 30) {
    final chunk = list.sublist(i, (i + 30).clamp(0, list.length));
    final snap  = await FirebaseFirestore.instance
        .collection('users')
        .where('phoneNumber', whereIn: chunk)
        .get();
    for (final doc in snap.docs) {
      if (doc.id != myUid) result.add({'uid': doc.id, ...doc.data()});
    }
  }
  return result;
}

String _e164(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '';
  if (d.startsWith('260') && d.length >= 12) return '+$d';
  if (d.startsWith('0')   && d.length >= 10) return '+260${d.substring(1)}';
  if (d.length == 9) return '+260$d';
  return '';
}

enum _CallTab { all, missed, groups }

// ── Calls Screen ──────────────────────────────────────────────────────────────

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});
  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen>
    with SingleTickerProviderStateMixin {
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final TabController _tabs;
  bool   _searchOpen = false;
  String _query      = '';
  final _searchCtrl  = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openNewCall() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NewCallSheet(
        onDirect: (uid, name, video) {
          Navigator.pop(context);
          _directCall(uid, name, video);
        },
        onGroup: (uids, names, video) {
          Navigator.pop(context);
          _groupCall(uids, names, video);
        },
      ),
    );
  }

  Future<void> _directCall(String uid, String name, bool video) async {
    try {
      final roomId = await CallService.initiateCall(
        calleeUid: uid, calleeName: name,
        type: video ? CallType.video : CallType.voice,
      );
      if (!mounted) return;
      _launchZego(context, roomId: roomId, video: video);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not start call: ${e.toString().replaceFirst("Exception: ", "")}'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _groupCall(
    List<String> uids,
    Map<String, String> names,
    bool video,
  ) async {
    try {
      final roomId = await CallService.initiateGroupCall(
        calleeUids: uids, calleeNames: names,
        type: video ? CallType.video : CallType.voice,
      );
      if (!mounted) return;
      _launchZego(context, roomId: roomId, video: video, isGroup: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not start group call: ${e.toString().replaceFirst("Exception: ", "")}'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _query = '';
        _searchCtrl.clear();
      }
    });
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
            _buildAppBar(),
            // Search bar (collapsible)
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: _searchOpen
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withAlpha(30)),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          onChanged: (v) => setState(() => _query = v),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search call history…',
                            hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                            prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(160), size: 20),
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.close_rounded, color: Colors.white.withAlpha(160), size: 18),
                                    onPressed: () => setState(() { _query = ''; _searchCtrl.clear(); }),
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // Tabs
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: Colors.white.withAlpha(8),
                  child: TabBar(
                    controller: _tabs,
                    labelColor: const Color(0xFF4F8AFF),
                    unselectedLabelColor: Colors.white.withAlpha(140),
                    indicatorColor: const Color(0xFF4F8AFF),
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: const [
                      Tab(text: 'All'),
                      Tab(text: 'Missed'),
                      Tab(text: 'Groups'),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _CallHistory(myUid: _myUid, tab: _CallTab.all,    query: _query,
                    onCallBack: (uid, name, roomId, video, isGroup) =>
                        _launchZego(context, roomId: roomId, video: video, isGroup: isGroup),
                    onMessage: (uid) => _goToChat(uid),
                  ),
                  _CallHistory(myUid: _myUid, tab: _CallTab.missed, query: _query,
                    onCallBack: (uid, name, roomId, video, isGroup) =>
                        _launchZego(context, roomId: roomId, video: video, isGroup: isGroup),
                    onMessage: (uid) => _goToChat(uid),
                  ),
                  _CallHistory(myUid: _myUid, tab: _CallTab.groups, query: _query,
                    onCallBack: (uid, name, roomId, video, isGroup) =>
                        _launchZego(context, roomId: roomId, video: video, isGroup: isGroup),
                    onMessage: (uid) => _goToChat(uid),
                  ),
                ],
              ),
            ),
          ]),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewCall,
        backgroundColor: const Color(0xFF2563EB),
        child: const Icon(Icons.add_call, color: Colors.white),
      ),
    );
  }

  Future<void> _goToChat(String otherUid) async {
    if (otherUid.isEmpty) return;
    final chatId = await ChatService.getOrCreateChat(otherUid);
    if (!mounted) return;
    context.push('/chats/${Uri.encodeComponent(chatId)}');
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
          child: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => context.go('/home'),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              const Text('Calls', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
                  color: _searchOpen ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(200),
                ),
                onPressed: _toggleSearch,
              ),
            ]),
          )),
        ),
      ),
    );
  }
}

// ── Call History List ─────────────────────────────────────────────────────────

class _CallHistory extends StatelessWidget {
  final String   myUid;
  final _CallTab tab;
  final String   query;
  final void Function(String uid, String name, String roomId, bool video, bool isGroup) onCallBack;
  final void Function(String uid) onMessage;

  const _CallHistory({
    required this.myUid,
    required this.tab,
    required this.query,
    required this.onCallBack,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CallService.callHistoryStream(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2));
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load call history',
              style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14)));
        }

        final all = snap.data ?? [];
        List<Map<String, dynamic>> calls;

        switch (tab) {
          case _CallTab.missed:
            calls = all.where((c) {
              final status   = c['status']    as String? ?? '';
              final isCaller = c['callerUid'] == myUid;
              return status == 'missed' || (status == 'calling' && !isCaller);
            }).toList();
          case _CallTab.groups:
            calls = all.where((c) => c['isGroup'] == true).toList();
          case _CallTab.all:
            calls = all;
        }

        // Apply search filter
        if (query.isNotEmpty) {
          final q = query.toLowerCase();
          calls = calls.where((c) {
            final isCaller = c['callerUid'] == myUid;
            final name = (c['isGroup'] == true
                ? c['groupName'] as String? ?? ''
                : (isCaller
                    ? c['calleeName'] as String? ?? ''
                    : c['callerName'] as String? ?? '')).toLowerCase();
            return name.contains(q);
          }).toList();
        }

        if (calls.isEmpty) {
          return _Empty(
            icon: tab == _CallTab.groups
                ? Icons.group_outlined
                : tab == _CallTab.missed
                    ? Icons.call_missed_rounded
                    : Icons.call_outlined,
            message: tab == _CallTab.groups
                ? 'No group calls yet'
                : tab == _CallTab.missed
                    ? 'No missed calls'
                    : query.isNotEmpty
                        ? 'No calls matching "$query"'
                        : 'No call history yet',
            sub: query.isNotEmpty ? '' : 'Tap + to start a call.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: calls.length,
          itemBuilder: (ctx, i) {
            final call     = calls[i];
            final callId   = call['id'] as String? ?? '';
            final isGroup  = call['isGroup'] == true;
            final isCaller = call['callerUid'] == myUid;

            final displayName = isGroup
                ? (call['groupName'] as String? ?? 'Group Call')
                : (isCaller
                    ? call['calleeName'] as String? ?? 'Unknown'
                    : call['callerName'] as String? ?? 'Unknown');

            final otherUid = isCaller
                ? call['calleeUid'] as String? ?? ''
                : call['callerUid'] as String? ?? '';

            final status       = call['status']    as String? ?? 'ended';
            final isVideo      = (call['type']     as String?) == 'video';
            final ts           = call['startedAt'] as Timestamp?;
            final duration     = CallService.formatDuration(call['duration'] as int?);
            final roomId       = call['roomId']    as String? ?? '';
            final isMissed     = status == 'missed' || (status == 'calling' && !isCaller);
            final participants = call['participants'] as List? ?? [];

            return _CallTile(
              key:             ValueKey(callId),
              index:           i,
              callId:          callId,
              name:            displayName,
              isGroup:         isGroup,
              participantCount: isGroup ? participants.length : 0,
              otherUid:        otherUid,
              roomId:          roomId,
              isOutgoing:      isCaller,
              isMissed:        isMissed,
              isVideo:         isVideo,
              time:            CallService.formatCallTime(ts),
              duration:        duration,
              onCallBack:      (video) => onCallBack(otherUid, displayName, roomId, video, isGroup),
              onMessage:       () => onMessage(otherUid),
              onDelete:        () => CallService.deleteCallRecord(callId),
            );
          },
        );
      },
    );
  }
}

// ── Call Tile ─────────────────────────────────────────────────────────────────

class _CallTile extends StatelessWidget {
  final int    index, participantCount;
  final String callId, name, otherUid, roomId, time, duration;
  final bool   isGroup, isOutgoing, isMissed, isVideo;
  final void Function(bool video) onCallBack;
  final VoidCallback onMessage, onDelete;

  const _CallTile({
    super.key,
    required this.index, required this.callId, required this.name,
    required this.isGroup, required this.participantCount,
    required this.otherUid, required this.roomId, required this.isOutgoing,
    required this.isMissed, required this.isVideo, required this.time,
    required this.duration, required this.onCallBack,
    required this.onMessage, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final col      = _avatarColor(name);
    final initials = _initials(name);
    final dirColor = isMissed ? const Color(0xFFEF4444) : const Color(0xFF86EFAC);
    final dirIcon  = isOutgoing ? Icons.call_made_rounded : Icons.call_received_rounded;

    return Dismissible(
      key: ValueKey('dismiss_$callId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withAlpha(40),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEF4444).withAlpha(60)),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 26),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0E1829),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Delete call', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            content: Text('Remove this call from your history?',
                style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: TextStyle(color: Colors.white.withAlpha(160))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: () => _showInfo(context),
        onLongPress: () => _showOptions(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withAlpha(isMissed ? 25 : 15)),
          ),
          child: Row(children: [
            // Avatar
            Stack(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: col,
                child: isGroup
                    ? const Icon(Icons.group_rounded, color: Colors.white, size: 22)
                    : Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              if (isGroup)
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4527A0),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF070F1E), width: 1.5),
                    ),
                    child: Text('$participantCount',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ),
              if (isMissed)
                Positioned(
                  top: 0, right: 0,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF070F1E), width: 1.5),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, style: TextStyle(
                  color: isMissed ? const Color(0xFFEF4444) : Colors.white,
                  fontWeight: FontWeight.w600, fontSize: 15,
                ))),
                if (isGroup)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4527A0).withAlpha(50),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF7C3AED).withAlpha(80)),
                    ),
                    child: const Text('Group', style: TextStyle(color: Color(0xFFB794F4), fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Icon(dirIcon, size: 13, color: dirColor),
                const SizedBox(width: 4),
                if (isVideo) ...[
                  Icon(Icons.videocam_outlined, size: 13, color: Colors.white.withAlpha(150)),
                  const SizedBox(width: 4),
                ],
                Expanded(child: Text(
                  duration.isNotEmpty ? '$time  ·  $duration' : time,
                  style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(140)),
                  overflow: TextOverflow.ellipsis,
                )),
              ]),
            ])),
            const SizedBox(width: 8),
            // Call-back button
            GestureDetector(
              onTap: () => onCallBack(isVideo),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F8AFF).withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(60)),
                ),
                child: Icon(
                  isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                  color: const Color(0xFF4F8AFF), size: 20,
                ),
              ),
            ),
          ]),
        ),
      ),
    ).animate(delay: (index * 40).ms).fadeIn().slideY(begin: 0.04, end: 0);
  }

  void _showInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CallInfoSheet(
        name:      name,
        isGroup:   isGroup,
        time:      time,
        duration:  duration,
        otherUid:  otherUid,
        onVoice:   () { Navigator.pop(context); onCallBack(false); },
        onVideo:   () { Navigator.pop(context); onCallBack(true); },
        onMessage: !isGroup ? () { Navigator.pop(context); onMessage(); } : null,
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 12),
              _OptionTile(
                icon: Icons.call_outlined,
                label: 'Voice call back',
                color: const Color(0xFF86EFAC),
                onTap: () { Navigator.pop(context); onCallBack(false); },
              ),
              _OptionTile(
                icon: Icons.videocam_outlined,
                label: 'Video call back',
                color: const Color(0xFF4F8AFF),
                onTap: () { Navigator.pop(context); onCallBack(true); },
              ),
              if (!isGroup)
                _OptionTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Message',
                  color: Colors.white.withAlpha(200),
                  onTap: () { Navigator.pop(context); onMessage(); },
                ),
              _OptionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete call',
                color: const Color(0xFFEF4444),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF0E1829),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Delete call?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      content: Text('Remove this call from your history?',
                          style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 14)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false),
                            child: Text('Cancel', style: TextStyle(color: Colors.white.withAlpha(160)))),
                        TextButton(onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700))),
                      ],
                    ),
                  );
                  if (ok == true) onDelete();
                },
              ),
              const SizedBox(height: 8),
            ]),
          ),
        );
      },
    );
  }
}

// ── Call Info Sheet ───────────────────────────────────────────────────────────

class _CallInfoSheet extends StatelessWidget {
  final String     name, time, duration, otherUid;
  final bool       isGroup;
  final VoidCallback onVoice, onVideo;
  final VoidCallback? onMessage;

  const _CallInfoSheet({
    required this.name, required this.isGroup, required this.time,
    required this.duration, required this.otherUid,
    required this.onVoice, required this.onVideo, this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final col      = _avatarColor(name);
    final initials = _initials(name);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 24),
        CircleAvatar(
          radius: 36, backgroundColor: col,
          child: isGroup
              ? const Icon(Icons.group_rounded, color: Colors.white, size: 34)
              : Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22)),
        ),
        const SizedBox(height: 12),
        Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        if (isGroup)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Group call', style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13)),
          ),
        const SizedBox(height: 4),
        Text(time, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13)),
        if (duration.isNotEmpty)
          Text('Duration: $duration', style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13)),
        const SizedBox(height: 28),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _SheetAction(icon: Icons.call_outlined,     label: 'Voice',   color: const Color(0xFF86EFAC), onTap: onVoice),
          _SheetAction(icon: Icons.videocam_outlined, label: 'Video',   color: const Color(0xFF4F8AFF), onTap: onVideo),
          if (onMessage != null)
            _SheetAction(icon: Icons.chat_bubble_outline_rounded, label: 'Message',
              color: Colors.white.withAlpha(200), onTap: onMessage!),
        ]),
      ]),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _SheetAction({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle,
          border: Border.all(color: color.withAlpha(60))),
        child: Icon(icon, color: color, size: 26),
      ),
      const SizedBox(height: 8),
      Text(label, style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Option tile ───────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _OptionTile({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 14),
        Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}

// ── New Call Sheet ────────────────────────────────────────────────────────────

class _NewCallSheet extends StatefulWidget {
  final void Function(String uid, String name, bool video) onDirect;
  final void Function(List<String> uids, Map<String, String> names, bool video) onGroup;

  const _NewCallSheet({required this.onDirect, required this.onGroup});

  @override
  State<_NewCallSheet> createState() => _NewCallSheetState();
}

class _NewCallSheetState extends State<_NewCallSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _filtered = [];
  final Set<String>         _selected  = {};
  bool   _loading = true;
  String _query   = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadContacts();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final result = await _loadZchatContacts();
      if (mounted) setState(() { _contacts = result; _filtered = result; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _search(String q) => setState(() {
    _query    = q;
    _filtered = q.isEmpty ? _contacts : _contacts.where((c) {
      final n = (_displayName(c)).toLowerCase();
      return n.contains(q.toLowerCase());
    }).toList();
  });

  String _displayName(Map<String, dynamic> c) =>
      c['fullName'] as String? ?? c['displayName'] as String? ?? 'User';

  void _startGroupCall(bool video) {
    if (_selected.isEmpty) return;
    final names = {
      for (final c in _contacts.where((c) => _selected.contains(c['uid'] as String? ?? '')))
        (c['uid'] as String): _displayName(c),
    };
    widget.onGroup(_selected.toList(), names, video);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.80,
      decoration: const BoxDecoration(
        color: Color(0xFF0E1829),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Padding(padding: const EdgeInsets.only(top: 14),
          child: Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2))))),
        const SizedBox(height: 14),
        const Text('New Call', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),

        // Tabs: Direct / Group
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(20)),
          ),
          child: TabBar(
            controller: _tabs,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withAlpha(120),
            indicator: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelPadding: EdgeInsets.zero,
            tabs: const [Tab(text: 'Direct'), Tab(text: 'Group')],
          ),
        ),
        const SizedBox(height: 10),

        // Search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(30)),
            ),
            child: TextField(
              onChanged: _search,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search contacts…',
                hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(160), size: 20),
                border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),

        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              // Direct call tab
              _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2))
                  : _filtered.isEmpty
                      ? _EmptyContacts(_query)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final c     = _filtered[i];
                            final uid   = c['uid']      as String? ?? '';
                            final name  = _displayName(c);
                            final photo = c['photoUrl'] as String? ?? '';
                            return _ContactRow(
                              uid: uid, name: name, photoUrl: photo,
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                _CallBtn(icon: Icons.call_outlined,     color: const Color(0xFF86EFAC), onTap: () => widget.onDirect(uid, name, false)),
                                const SizedBox(width: 8),
                                _CallBtn(icon: Icons.videocam_outlined, color: const Color(0xFF4F8AFF), onTap: () => widget.onDirect(uid, name, true)),
                              ]),
                            );
                          },
                        ),

              // Group call tab
              Column(children: [
                if (_selected.isNotEmpty)
                  _SelectedChips(
                    selected: _selected,
                    contacts: _contacts,
                    displayName: _displayName,
                    onRemove: (uid) => setState(() => _selected.remove(uid)),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2))
                      : _filtered.isEmpty
                          ? _EmptyContacts(_query)
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              itemCount: _filtered.length,
                              itemBuilder: (ctx, i) {
                                final c     = _filtered[i];
                                final uid   = c['uid']      as String? ?? '';
                                final name  = _displayName(c);
                                final photo = c['photoUrl'] as String? ?? '';
                                final sel   = _selected.contains(uid);
                                return _ContactRow(
                                  uid: uid, name: name, photoUrl: photo,
                                  onTap: () => setState(() {
                                    if (sel) { _selected.remove(uid); } else { _selected.add(uid); }
                                  }),
                                  trailing: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 24, height: 24,
                                    decoration: BoxDecoration(
                                      color: sel ? const Color(0xFF2563EB) : Colors.transparent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: sel ? const Color(0xFF2563EB) : Colors.white.withAlpha(60),
                                        width: 2,
                                      ),
                                    ),
                                    child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
                                  ),
                                );
                              },
                            ),
                ),
                if (_selected.isNotEmpty)
                  _GroupCallBar(count: _selected.length, onVoice: () => _startGroupCall(false), onVideo: () => _startGroupCall(true)),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Selected chips row ────────────────────────────────────────────────────────

class _SelectedChips extends StatelessWidget {
  final Set<String> selected;
  final List<Map<String, dynamic>> contacts;
  final String Function(Map<String, dynamic>) displayName;
  final void Function(String uid) onRemove;

  const _SelectedChips({
    required this.selected, required this.contacts,
    required this.displayName, required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final list = contacts.where((c) => selected.contains(c['uid'] as String? ?? '')).toList();
    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final c    = list[i];
          final uid  = c['uid'] as String? ?? '';
          final name = displayName(c);
          final col  = _avatarColor(name);
          return GestureDetector(
            onTap: () => onRemove(uid),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: col.withAlpha(40),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: col.withAlpha(80)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(radius: 10, backgroundColor: col,
                  child: Text(_initials(name), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700))),
                const SizedBox(width: 5),
                Text(name.split(' ').first, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 5),
                Icon(Icons.close_rounded, color: Colors.white.withAlpha(180), size: 13),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── Group call start bar ──────────────────────────────────────────────────────

class _GroupCallBar extends StatelessWidget {
  final int count;
  final VoidCallback onVoice, onVideo;
  const _GroupCallBar({required this.count, required this.onVoice, required this.onVideo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
      ),
      child: Row(children: [
        Expanded(child: Text(
          '$count participant${count == 1 ? '' : 's'} selected',
          style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13),
        )),
        _CallBtn(icon: Icons.call_outlined,     color: const Color(0xFF86EFAC), label: 'Voice', onTap: onVoice),
        const SizedBox(width: 10),
        _CallBtn(icon: Icons.videocam_outlined, color: const Color(0xFF4F8AFF), label: 'Video', onTap: onVideo),
      ]),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  final String  uid, name, photoUrl;
  final Widget  trailing;
  final VoidCallback? onTap;

  const _ContactRow({
    required this.uid, required this.name, required this.photoUrl,
    required this.trailing, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col      = _avatarColor(name);
    final initials = _initials(name);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withAlpha(15)),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 22, backgroundColor: col,
            backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            child: photoUrl.isEmpty
                ? Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))),
          trailing,
        ]),
      ),
    );
  }
}

class _CallBtn extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap; final String? label;
  const _CallBtn({required this.icon, required this.color, required this.onTap, this.label});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: label != null
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
          : const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(label != null ? 12 : 10),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: label != null
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(label!, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
            ])
          : Icon(icon, color: color, size: 18),
    ),
  );
}

class _EmptyContacts extends StatelessWidget {
  final String query;
  const _EmptyContacts(this.query);
  @override
  Widget build(BuildContext context) => Center(child: Text(
    query.isEmpty ? 'No ZCHAT contacts found' : 'No match for "$query"',
    style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14),
  ));
}

class _Empty extends StatelessWidget {
  final IconData icon; final String message, sub;
  const _Empty({required this.icon, required this.message, required this.sub});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 60, color: Colors.white.withAlpha(50)),
      const SizedBox(height: 16),
      Text(message, style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      if (sub.isNotEmpty)
        Text(sub, style: TextStyle(color: Colors.white.withAlpha(110), fontSize: 13)),
    ]),
  );
}
