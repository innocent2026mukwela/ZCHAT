import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import '../../services/ai_service.dart';
import '../../services/zego_service.dart';
import '../../utils/glass.dart';
import '../../widgets/lecturer_bottom_nav_bar.dart';

// ── Lecturer Home ─────────────────────────────────────────────────────────────

class LecturerHomeScreen extends StatefulWidget {
  const LecturerHomeScreen({super.key});
  @override
  State<LecturerHomeScreen> createState() => _LecturerHomeScreenState();
}

class _LecturerHomeScreenState extends State<LecturerHomeScreen> {
  bool _searchMode = false;
  String _query = '';
  final _searchCtrl = TextEditingController();
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  Stream<List<Map<String, dynamic>>> get _chatsStream =>
      FirebaseFirestore.instance
          .collection('chats')
          .where('memberUids', arrayContains: _uid)
          .orderBy('lastMessageAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map((d) {
                final data = d.data();
                data['id'] = d.id;
                return data;
              }).toList());

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _LecturerScaffold(
      title: 'Lecturer Home',
      actions: [
        if (_searchMode)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search chats…',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(120)),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
          ),
        IconButton(
          icon: Icon(_searchMode ? Icons.close_rounded : Icons.search_rounded, color: Colors.white),
          onPressed: () => setState(() {
            _searchMode = !_searchMode;
            if (!_searchMode) { _query = ''; _searchCtrl.clear(); }
          }),
        ),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onPressed: () => context.push('/profile'),
        ),
      ],
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _chatsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)));
          }
          if (snap.hasError) {
            return Center(child: Text('Could not load chats',
                style: TextStyle(color: Colors.white.withAlpha(140))));
          }
          var chats = snap.data ?? [];
          if (_query.isNotEmpty) {
            chats = chats.where((c) {
              final name = (c['name'] as String? ?? '').toLowerCase();
              final last = (c['lastMessage'] as String? ?? '').toLowerCase();
              return name.contains(_query) || last.contains(_query);
            }).toList();
          }
          if (chats.isEmpty) {
            return Center(
              child: Text(
                _query.isNotEmpty ? 'No chats found' : 'No chats yet',
                style: TextStyle(color: Colors.white.withAlpha(140)),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              final chatId   = chat['id'] as String? ?? '';
              final isGroup  = chat['isGroup'] as bool? ?? false;
              final name     = chat['name'] as String? ?? (isGroup ? 'Group' : 'Chat');
              final lastMsg  = chat['lastMessage'] as String? ?? '';
              final unread   = (chat['unreadCount'] as Map?)?.entries
                  .where((e) => e.key == _uid)
                  .fold<int>(0, (s, e) => s + ((e.value as int?) ?? 0)) ?? 0;
              final ts       = chat['lastMessageAt'] as Timestamp?;
              final timeStr  = ts != null ? _formatTime(ts.toDate()) : '';

              return InkWell(
                onTap: () => context.push('/chats/$chatId?name=${Uri.encodeComponent(name)}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withAlpha(12)))),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: isGroup ? const Color(0xFF00695C) : const Color(0xFF6A1B9A),
                      child: Icon(isGroup ? Icons.groups_rounded : Icons.person_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                        Text(timeStr, style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 11)),
                      ]),
                      const SizedBox(height: 4),
                      Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12)),
                    ])),
                    if (unread > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                        child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ]),
                ),
              ).animate(delay: (index * 35).ms).fadeIn().slideY(begin: 0.05, end: 0);
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return DateFormat('HH:mm').format(dt);
    }
    final diff = now.difference(dt).inDays;
    if (diff < 7) return DateFormat('EEE').format(dt);
    return DateFormat('dd/MM').format(dt);
  }
}

// ── Lecturer Courses ──────────────────────────────────────────────────────────

class LecturerCoursesScreen extends StatefulWidget {
  const LecturerCoursesScreen({super.key});
  @override
  State<LecturerCoursesScreen> createState() => _LecturerCoursesScreenState();
}

class _LecturerCoursesScreenState extends State<LecturerCoursesScreen> {
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  String _query = '';
  final _searchCtrl = TextEditingController();

  Stream<List<Map<String, dynamic>>> get _coursesStream =>
      FirebaseFirestore.instance
          .collection('courses')
          .where('lecturerUid', isEqualTo: _uid)
          .snapshots()
          .map((s) => s.docs.map((d) {
                final data = d.data();
                data['id'] = d.id;
                return data;
              }).toList());

  static const _palette = [
    Color(0xFF2563EB), Color(0xFF00695C), Color(0xFF6A1B9A),
    Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF4527A0),
  ];

  Color _courseColor(String id) =>
      _palette[id.codeUnits.fold(0, (a, c) => a + c) % _palette.length];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _addCourse() {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add Course', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 16),
          TextField(
            controller: codeCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Course Code (e.g. CS 3201)',
              labelStyle: TextStyle(color: Colors.white.withAlpha(160)),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withAlpha(40)), borderRadius: BorderRadius.circular(10)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4F8AFF)), borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Course Name',
              labelStyle: TextStyle(color: Colors.white.withAlpha(160)),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withAlpha(40)), borderRadius: BorderRadius.circular(10)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4F8AFF)), borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                final code = codeCtrl.text.trim();
                final name = nameCtrl.text.trim();
                if (code.isEmpty || name.isEmpty) return;
                try {
                  await FirebaseFirestore.instance.collection('courses').add({
                    'code': code, 'name': name,
                    'lecturerUid': _uid, 'enrolledCount': 0, 'createdAt': FieldValue.serverTimestamp(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Could not create course: ${e.toString().replaceFirst("Exception: ", "")}'),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                }
              },
              child: const Text('Create Course', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _LecturerScaffold(
      title: 'Courses',
      actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          onPressed: _addCourse,
        ),
      ],
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _coursesStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)));
          }
          if (snap.hasError) {
            return Center(child: Text('Could not load courses',
                style: TextStyle(color: Colors.white.withAlpha(140))));
          }
          var courses = snap.data ?? [];
          if (_query.isNotEmpty) {
            courses = courses.where((c) {
              final code = (c['code'] as String? ?? '').toLowerCase();
              final name = (c['name'] as String? ?? '').toLowerCase();
              return code.contains(_query) || name.contains(_query);
            }).toList();
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
            children: [
              GlassCard(
                borderRadius: BorderRadius.circular(16),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search your courses',
                    hintStyle: TextStyle(color: Colors.white.withAlpha(105)),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(155)),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) => setState(() => _query = v.toLowerCase()),
                ),
              ),
              const SizedBox(height: 14),
              if (courses.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.school_outlined, color: Colors.white.withAlpha(80), size: 48),
                      const SizedBox(height: 12),
                      Text('No courses yet. Tap + to add one.', style: TextStyle(color: Colors.white.withAlpha(140))),
                    ]),
                  ),
                )
              else
                for (var i = 0; i < courses.length; i++) ...[
                  _buildCourseCard(courses[i], i, context),
                ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course, int index, BuildContext context) {
    final id      = course['id'] as String;
    final code    = course['code'] as String? ?? '';
    final name    = course['name'] as String? ?? '';
    final count   = course['enrolledCount'] as int? ?? 0;
    final color   = _courseColor(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: BorderRadius.circular(18),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: color.withAlpha(45), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withAlpha(85))),
            child: Center(child: Text(code.split(' ').first, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text('$code · $count students', style: TextStyle(color: Colors.white.withAlpha(155), fontSize: 12)),
          ])),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            onPressed: () => context.push('/classroom/$id'),
          ),
        ]),
      ).animate(delay: (index * 50).ms).fadeIn().slideY(begin: 0.05, end: 0),
    );
  }
}

// ── Lecturer Classroom ────────────────────────────────────────────────────────

class LecturerClassroomScreen extends StatelessWidget {
  const LecturerClassroomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LecturerScaffold(
      title: 'Classroom',
      actions: [IconButton(icon: const Icon(Icons.history_rounded, color: Colors.white), onPressed: () => context.push('/courses'))],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
        children: [
          _LiveClassCard(),
          const SizedBox(height: 14),
          _ActionGrid(actions: [
            _LecturerAction(Icons.present_to_all_rounded, 'Share screen', 'Mirror slides or demos', onTap: () => context.push('/courses')),
            _LecturerAction(Icons.fiber_manual_record_rounded, 'Record', 'Save session replay', onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Recording starts automatically when you begin a live session.'),
                backgroundColor: Color(0xFF2563EB), behavior: SnackBarBehavior.floating,
              ));
            }),
            _LecturerAction(Icons.qr_code_2_rounded, 'Attendance', 'Generate class code', onTap: () => _showAttendanceQr(context)),
            _LecturerAction(Icons.upload_file_rounded, 'Resources', 'Send files to class', onTap: () => context.push('/courses')),
          ]),
        ],
      ),
    );
  }
}

// ── Lecturer AI ───────────────────────────────────────────────────────────────

class LecturerAiScreen extends StatelessWidget {
  const LecturerAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LecturerScaffold(
      title: 'AI Tools',
      actions: [IconButton(icon: const Icon(Icons.tune_rounded, color: Colors.white), onPressed: () => context.push('/ai'))],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
        children: [
          const _AiPromptCard(),
          const SizedBox(height: 14),
          _ActionGrid(actions: [
            _LecturerAction(Icons.quiz_outlined, 'Generate quiz', 'From topic or notes', onTap: () => context.push('/ai')),
            _LecturerAction(Icons.grading_rounded, 'Grade help', 'Rubric-based feedback', onTap: () => context.push('/ai')),
            _LecturerAction(Icons.summarize_outlined, 'Summarize', 'Class chat or PDFs', onTap: () => context.push('/ai')),
            _LecturerAction(Icons.campaign_outlined, 'Announcement', 'Clean up message tone', onTap: () => context.push('/ai')),
          ]),
        ],
      ),
    );
  }
}

// ── Lecturer Planner ──────────────────────────────────────────────────────────

class LecturerPlannerScreen extends StatelessWidget {
  const LecturerPlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LecturerScaffold(
      title: 'Planner',
      actions: [
        IconButton(
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          onPressed: () => context.push('/planner'),
        ),
      ],
      child: const _LecturerPlannerBody(),
    );
  }
}

class _LecturerPlannerBody extends StatelessWidget {
  const _LecturerPlannerBody();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('planner')
          .orderBy('date')
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Could not load planner',
              style: TextStyle(color: Colors.white.withAlpha(140))));
        }
        final docs = snap.data?.docs ?? [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
          children: [
            _PlannerSummary(count: docs.length),
            const SizedBox(height: 14),
            if (docs.isEmpty)
              Center(child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Text('No planned items. Tap + to add.', style: TextStyle(color: Colors.white.withAlpha(140))),
              ))
            else
              for (var i = 0; i < docs.length; i++) ...[
                _PlanRow(
                  title: docs[i]['title'] as String? ?? '',
                  time: docs[i]['dateLabel'] as String? ?? '',
                  source: docs[i]['source'] as String? ?? 'Planner',
                  index: i,
                  onTap: () => context.push('/planner'),
                ),
              ],
          ],
        );
      },
    );
  }
}

// ── Shared scaffold ───────────────────────────────────────────────────────────

class _LecturerScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;

  const _LecturerScaffold({required this.title, required this.child, this.actions});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: const LecturerBottomNavBar(),
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Column(children: [
            _LecturerAppBar(title: title, actions: actions),
            Expanded(child: child),
          ]),
        ]),
      ),
    );
  }
}

class _LecturerAppBar extends StatelessWidget {
  static const _brandAsset = 'assets/icons/zchat_logo_cutout.png';
  final String title;
  final List<Widget>? actions;

  const _LecturerAppBar({required this.title, this.actions});

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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(children: [
                Image.asset(_brandAsset, width: 92, fit: BoxFit.contain,
                  errorBuilder: (_, e, s) => const Text('ZCHAT',
                    style: TextStyle(color: Color(0xFF2EA3FF), fontWeight: FontWeight.w900))),
                const SizedBox(width: 10),
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
                if (actions != null) ...actions!,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

void _showAttendanceQr(BuildContext context) {
  final uid     = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
  final classId = 'class_${uid}_${DateTime.now().millisecondsSinceEpoch ~/ 600000}';
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF0E1829),
      title: const Text('Attendance QR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: QrImageView(data: classId, version: QrVersions.auto, size: 200),
        ),
        const SizedBox(height: 12),
        Text('Students scan to mark attendance', style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(classId, style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 10), textAlign: TextAlign.center),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Color(0xFF4F8AFF))))],
    ),
  );
}

// ── Live class card ───────────────────────────────────────────────────────────

class _LiveClassCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'lecturer';
    final roomId = 'class_${uid}_${DateTime.now().millisecondsSinceEpoch ~/ 600000}';

    return GlassCard(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(45), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.videocam_rounded, color: Color(0xFF93C5FD)),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Next live class', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
            SizedBox(height: 3),
            Text('Tap to start a live classroom session', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity, height: 48,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ZegoUIKitPrebuiltCall(
                appID: kZegoAppId,
                appSign: kZegoAppSign,
                userID: uid,
                userName: 'Lecturer',
                callID: roomId,
                config: ZegoUIKitPrebuiltCallConfig.groupVideoCall(),
              ),
            )),
            icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
            label: const Text('Start Class', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB), elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ]),
    ).animate().fadeIn().slideY(begin: 0.04, end: 0);
  }
}

// ── Action grid ───────────────────────────────────────────────────────────────

class _ActionGrid extends StatelessWidget {
  final List<_LecturerAction> actions;
  const _ActionGrid({required this.actions});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 1.22, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        return GestureDetector(
          onTap: action.onTap,
          child: GlassCard(
            borderRadius: BorderRadius.circular(18),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Icon(action.icon, color: const Color(0xFF93C5FD), size: 26),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(action.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(action.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withAlpha(145), fontSize: 11)),
              ]),
            ]),
          ),
        ).animate(delay: (index * 45).ms).fadeIn().scale(begin: const Offset(0.97, 0.97));
      },
    );
  }
}

// ── AI Prompt card ────────────────────────────────────────────────────────────

class _AiPromptCard extends StatefulWidget {
  const _AiPromptCard();
  @override
  State<_AiPromptCard> createState() => _AiPromptCardState();
}

class _AiPromptCardState extends State<_AiPromptCard> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _send() async {
    final prompt = _ctrl.text.trim();
    if (prompt.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      final result = await AiService.chat(messages: [{'role': 'user', 'content': prompt}]);
      final reply = result['reply'] as String;
      if (!mounted) return;
      _ctrl.clear();
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0E1829),
          title: const Text('AI Response', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(child: Text(reply, style: TextStyle(color: Colors.white.withAlpha(220)))),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(context); context.push('/ai'); },
              child: const Text('Open AI Chat', style: TextStyle(color: Color(0xFF4F8AFF))),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: Colors.white70))),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        const Icon(Icons.auto_awesome_rounded, color: Color(0xFF93C5FD)),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Ask AI to prepare lecturer material',
              hintStyle: TextStyle(color: Colors.white.withAlpha(105)),
              border: InputBorder.none, filled: false, isDense: true,
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        _loading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F8AFF)))
          : IconButton(icon: const Icon(Icons.send_rounded, color: Color(0xFF4F8AFF)), onPressed: _send),
      ]),
    ).animate().fadeIn();
  }
}

// ── Planner summary ───────────────────────────────────────────────────────────

class _PlannerSummary extends StatelessWidget {
  final int count;
  const _PlannerSummary({required this.count});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        const Icon(Icons.event_available_rounded, color: Color(0xFF93C5FD), size: 30),
        const SizedBox(width: 12),
        Expanded(child: Text(
          count == 0 ? 'No planned tasks this week' : '$count upcoming lecturer task${count == 1 ? '' : 's'} this week',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
        )),
      ]),
    ).animate().fadeIn().slideY(begin: 0.04, end: 0);
  }
}

class _PlanRow extends StatelessWidget {
  final String title, time, source;
  final int index;
  final VoidCallback onTap;

  const _PlanRow({required this.title, required this.time, required this.source, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassTile(
        leading: const Icon(Icons.schedule_rounded, color: Color(0xFF93C5FD)),
        title: Text(title),
        subtitle: Text('$time - $source'),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
        onTap: onTap,
      ).animate(delay: (index * 45).ms).fadeIn().slideX(begin: 0.04, end: 0),
    );
  }
}

// ── Data types ────────────────────────────────────────────────────────────────

class _LecturerAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _LecturerAction(this.icon, this.title, this.subtitle, {this.onTap});
}
