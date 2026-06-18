import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/planner_service.dart';
import '../../utils/glass.dart';
import '../../widgets/bottom_nav_bar.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});
  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _role = 'student';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadRole();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _loadRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (mounted) setState(() => _role = doc.data()?['role'] as String? ?? 'student');
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
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(12),
                    border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
                  ),
                  child: SafeArea(bottom: false, child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Row(children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          onPressed: () => context.go('/home'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          _role == 'lecturer' ? 'Teaching Planner' : 'Study Planner',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                        )),
                        IconButton(
                          icon: const Icon(Icons.add_rounded, color: Colors.white),
                          onPressed: () => _showAddSheet(context),
                        ),
                      ]),
                    ),
                    TabBar(
                      controller: _tabs,
                      indicatorColor: const Color(0xFF4F8AFF),
                      indicatorWeight: 2.5,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white.withAlpha(110),
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                      dividerColor: Colors.transparent,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        Tab(text: _role == 'lecturer' ? 'SCHEDULE'      : 'TIMETABLE'),
                        Tab(text: _role == 'lecturer' ? 'LESSON PLAN'   : 'STUDY PLAN'),
                        Tab(text: _role == 'lecturer' ? 'TEACHING NOTES': 'STUDY GUIDES'),
                        const Tab(text: 'REMINDERS'),
                      ],
                    ),
                  ])),
                ),
              ),
            ),
            Expanded(child: TabBarView(controller: _tabs, children: [
              _TimetableTab(role: _role),
              _StudyPlanTab(),
              _StudyGuidesTab(),
              _RemindersTab(role: _role),
            ])),
          ]),
        ]),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    final tab = _tabs.index;
    if (tab == 0)      _showTimetableForm(context);
    else if (tab == 1) _showStudyPlanForm(context);
    else if (tab == 2) _showStudyGuideForm(context);
  }

  void _showTimetableForm(BuildContext context, [Map<String, dynamic>? existing]) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TimetableForm(role: _role, existing: existing),
    );
  }

  void _showStudyPlanForm(BuildContext context, [Map<String, dynamic>? existing]) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StudyPlanForm(existing: existing),
    );
  }

  void _showStudyGuideForm(BuildContext context, [Map<String, dynamic>? existing]) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StudyGuideForm(existing: existing),
    );
  }
}

// ── Timetable Tab ─────────────────────────────────────────────────────────────

class _TimetableTab extends StatelessWidget {
  final String role;
  const _TimetableTab({required this.role});

  static const _dayColors = [
    Color(0xFF4F8AFF), Color(0xFF86EFAC), Color(0xFFB794F4),
    Color(0xFFFBBF24), Color(0xFFF87171), Color(0xFF67E8F9),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: PlannerService.timetableStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2));
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load timetable', style: TextStyle(color: Colors.white.withAlpha(140))));
        }
        final slots = snap.data ?? [];
        if (slots.isEmpty) {
          return _EmptyState(
            icon: Icons.calendar_today_rounded,
            title: role == 'lecturer' ? 'No teaching schedule yet' : 'No timetable yet',
            subtitle: 'Tap + to add your ${role == 'lecturer' ? 'teaching' : 'class'} schedule',
          );
        }

        // Group by day
        final grouped = <int, List<Map<String, dynamic>>>{};
        for (final s in slots) {
          final d = s['dayIndex'] as int? ?? 1;
          grouped.putIfAbsent(d, () => []).add(s);
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            for (final day in PlannerService.dayIndexes)
              if (grouped.containsKey(day)) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 4),
                  child: Text(PlannerService.days[day - 1],
                    style: TextStyle(color: _dayColors[day - 1], fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
                ),
                ...grouped[day]!.map((s) => _SlotTile(slot: s, color: _dayColors[day - 1], role: role)),
                const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }
}

class _SlotTile extends StatelessWidget {
  final Map<String, dynamic> slot;
  final Color color;
  final String role;
  const _SlotTile({required this.slot, required this.color, required this.role});

  @override
  Widget build(BuildContext context) {
    final subject = slot['subject'] as String? ?? '';
    final venue   = slot['venue']   as String? ?? '';
    final start   = slot['startTime'] as String? ?? '';
    final end     = slot['endTime']   as String? ?? '';
    final type    = slot['type'] as String? ?? '';
    final reminder = slot['reminder'] as bool? ?? false;

    return GlassCard(
      borderRadius: BorderRadius.circular(12),
      bgColor: color.withAlpha(10),
      borderColor: color.withAlpha(40),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(width: 4, height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(subject, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 3),
          Row(children: [
            Icon(Icons.schedule_rounded, size: 12, color: Colors.white.withAlpha(140)),
            const SizedBox(width: 4),
            Text('$start – $end', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(140))),
            if (venue.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.location_on_outlined, size: 12, color: Colors.white.withAlpha(140)),
              const SizedBox(width: 2),
              Text(venue, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(140))),
            ],
          ]),
          if (type.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                child: Text(type, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
              ),
            ),
        ])),
        Column(children: [
          if (reminder) Icon(Icons.notifications_active_rounded, size: 16, color: color),
          const SizedBox(height: 4),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: Colors.white.withAlpha(160), size: 18),
            color: const Color(0xFF1A2550),
            onSelected: (v) async {
              if (v == 'edit') {
                showModalBottomSheet(
                  context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                  builder: (_) => _TimetableForm(role: role, existing: slot),
                );
              } else if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF0A1A4A),
                    title: const Text('Delete slot?', style: TextStyle(color: Colors.white)),
                    content: Text('Remove "${slot['subject'] ?? ''}" from your timetable?',
                        style: const TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                );
                if (ok == true) PlannerService.deleteTimetableSlot(slot['id'] as String);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit',   child: Text('Edit',   style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
            ],
          ),
        ]),
      ]),
    );
  }
}

// ── Study Plan Tab ────────────────────────────────────────────────────────────

class _StudyPlanTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: PlannerService.studyPlansStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2));
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load study plans', style: TextStyle(color: Colors.white.withAlpha(140))));
        }
        final plans = snap.data ?? [];
        if (plans.isEmpty) {
          return const _EmptyState(
            icon: Icons.menu_book_rounded,
            title: 'No study sessions yet',
            subtitle: 'Tap + to schedule a study session',
          );
        }

        final pending = plans.where((p) => p['done'] != true).toList();
        final done    = plans.where((p) => p['done'] == true).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: [
            if (pending.isNotEmpty) ...[
              _SectionHeader('UPCOMING (${pending.length})'),
              ...pending.asMap().entries.map((e) => _StudyPlanTile(plan: e.value, index: e.key)),
            ],
            if (done.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionHeader('COMPLETED (${done.length})'),
              ...done.asMap().entries.map((e) => _StudyPlanTile(plan: e.value, index: e.key, isDone: true)),
            ],
          ],
        );
      },
    );
  }
}

class _StudyPlanTile extends StatelessWidget {
  final Map<String, dynamic> plan;
  final int index;
  final bool isDone;
  const _StudyPlanTile({required this.plan, required this.index, this.isDone = false});

  @override
  Widget build(BuildContext context) {
    final topic    = plan['topic']    as String? ?? '';
    final course   = plan['course']   as String? ?? '';
    final ts       = plan['dateTime'] as Timestamp?;
    final duration = plan['duration'] as String? ?? '';
    final reminder = plan['reminder'] as bool? ?? false;
    final done     = plan['done']     as bool? ?? false;
    final dateStr  = ts != null ? DateFormat('EEE, MMM d · h:mm a').format(ts.toDate()) : '';

    return GlassCard(
      borderRadius: BorderRadius.circular(12),
      bgColor: done ? Colors.white.withAlpha(5) : const Color(0xFF2563EB).withAlpha(10),
      borderColor: done ? Colors.white.withAlpha(15) : const Color(0xFF4F8AFF).withAlpha(40),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        GestureDetector(
          onTap: () => PlannerService.toggleStudyPlanDone(plan['id'] as String, !done),
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? const Color(0xFF86EFAC) : Colors.transparent,
              border: Border.all(color: done ? const Color(0xFF86EFAC) : Colors.white.withAlpha(60), width: 2),
            ),
            child: done ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(topic, style: TextStyle(
            color: done ? Colors.white.withAlpha(100) : Colors.white,
            fontWeight: FontWeight.w600, fontSize: 14,
            decoration: done ? TextDecoration.lineThrough : null,
            decorationColor: Colors.white.withAlpha(100),
          )),
          const SizedBox(height: 3),
          Row(children: [
            if (dateStr.isNotEmpty) ...[
              Icon(Icons.calendar_today_rounded, size: 11, color: Colors.white.withAlpha(120)),
              const SizedBox(width: 4),
              Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(120))),
            ],
            if (duration.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.timer_outlined, size: 11, color: Colors.white.withAlpha(120)),
              const SizedBox(width: 2),
              Text(duration, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(120))),
            ],
          ]),
          if (course.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(40), borderRadius: BorderRadius.circular(4)),
                child: Text(course, style: const TextStyle(fontSize: 10, color: Color(0xFF93C5FD), fontWeight: FontWeight.w700)),
              ),
            ),
        ])),
        Column(children: [
          if (reminder) Icon(Icons.notifications_active_rounded, size: 16, color: Colors.white.withAlpha(160)),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: Colors.white.withAlpha(160), size: 18),
            color: const Color(0xFF1A2550),
            onSelected: (v) async {
              if (v == 'edit') {
                showModalBottomSheet(
                  context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                  builder: (_) => _StudyPlanForm(existing: plan),
                );
              } else if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF0A1A4A),
                    title: const Text('Delete session?', style: TextStyle(color: Colors.white)),
                    content: Text('Remove "${plan['topic'] ?? ''}" from your study plan?',
                        style: const TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                );
                if (ok == true) PlannerService.deleteStudyPlan(plan['id'] as String);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit',   child: Text('Edit',   style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
            ],
          ),
        ]),
      ]),
    ).animate(delay: (index * 30).ms).fadeIn();
  }
}

// ── Study Guides Tab ──────────────────────────────────────────────────────────

class _StudyGuidesTab extends StatelessWidget {
  static const _colors = [
    Color(0xFF4F8AFF), Color(0xFF86EFAC), Color(0xFFB794F4),
    Color(0xFFFBBF24), Color(0xFFF87171), Color(0xFF67E8F9),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: PlannerService.studyGuidesStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2));
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load study guides', style: TextStyle(color: Colors.white.withAlpha(140))));
        }
        final guides = snap.data ?? [];
        if (guides.isEmpty) {
          return const _EmptyState(
            icon: Icons.auto_stories_rounded,
            title: 'No study guides yet',
            subtitle: 'Tap + to create your first study guide',
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          children: guides.asMap().entries.map((e) {
            final i = e.key;
            final g = e.value;
            final title   = g['title']   as String? ?? '';
            final course  = g['course']  as String? ?? '';
            final content = g['content'] as String? ?? '';
            final color   = _colors[i % _colors.length];

            return GlassCard(
              borderRadius: BorderRadius.circular(14),
              bgColor: color.withAlpha(10),
              borderColor: color.withAlpha(40),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.auto_stories_rounded, color: color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    if (course.isNotEmpty) Text(course, style: TextStyle(fontSize: 12, color: color)),
                  ])),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: Colors.white.withAlpha(160), size: 18),
                    color: const Color(0xFF1A2550),
                    onSelected: (v) async {
                      if (v == 'edit') {
                        showModalBottomSheet(
                          context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
                          builder: (_) => _StudyGuideForm(existing: g),
                        );
                      } else if (v == 'delete') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: const Color(0xFF0A1A4A),
                            title: const Text('Delete guide?', style: TextStyle(color: Colors.white)),
                            content: Text('Remove "$title"?',
                                style: const TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                              TextButton(onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
                            ],
                          ),
                        );
                        if (ok == true) PlannerService.deleteStudyGuide(g['id'] as String);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit',   child: Text('Edit',   style: TextStyle(color: Colors.white))),
                      const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                ]),
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(content, style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13, height: 1.5),
                    maxLines: 4, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ).animate(delay: (i * 40).ms).fadeIn().slideY(begin: 0.05, end: 0);
          }).toList(),
        );
      },
    );
  }
}

// ── Reminders Tab ─────────────────────────────────────────────────────────────

class _RemindersTab extends StatelessWidget {
  final String role;
  const _RemindersTab({required this.role});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        // Class reminders from timetable
        _SectionHeader(role == 'lecturer' ? 'TEACHING REMINDERS' : 'CLASS REMINDERS'),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: PlannerService.timetableStream(),
          builder: (_, snap) {
            final slots = (snap.data ?? []).where((s) => s['reminder'] == true).toList();
            if (slots.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('No class reminders set.\nEdit a timetable entry and enable reminder.',
                  style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 13, height: 1.5)),
              );
            }
            return Column(children: slots.map((s) => _ReminderTile(
              icon: Icons.school_rounded,
              color: const Color(0xFF4F8AFF),
              title: s['subject'] as String? ?? '',
              subtitle: '${PlannerService.days[(s['dayIndex'] as int? ?? 1) - 1]}  ·  ${s['startTime'] ?? ''}  ·  10 min before',
              onDisable: () => PlannerService.updateTimetableSlot(s['id'] as String, {...s, 'reminder': false}),
            )).toList());
          },
        ),

        const SizedBox(height: 16),
        _SectionHeader('STUDY REMINDERS'),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: PlannerService.studyPlansStream(),
          builder: (_, snap) {
            final plans = (snap.data ?? [])
                .where((p) => p['reminder'] == true && p['done'] != true)
                .toList();
            if (plans.isEmpty) {
              return Text('No study reminders set.\nEdit a study session and enable reminder.',
                style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 13, height: 1.5));
            }
            return Column(children: plans.map((p) {
              final ts = p['dateTime'] as Timestamp?;
              final dateStr = ts != null ? DateFormat('EEE, MMM d · h:mm a').format(ts.toDate()) : '';
              return _ReminderTile(
                icon: Icons.menu_book_rounded,
                color: const Color(0xFF86EFAC),
                title: p['topic'] as String? ?? '',
                subtitle: '$dateStr  ·  10 min before',
                onDisable: () => PlannerService.updateStudyPlan(p['id'] as String, {...p, 'reminder': false}),
              );
            }).toList());
          },
        ),

        const SizedBox(height: 24),
        GlassCard(
          borderRadius: BorderRadius.circular(12),
          bgColor: const Color(0xFF2563EB).withAlpha(10),
          borderColor: const Color(0xFF4F8AFF).withAlpha(40),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, color: Colors.white.withAlpha(160), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'All reminders fire 10 minutes before the session. Enable reminders when adding or editing a timetable or study entry.',
              style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12, height: 1.5),
            )),
          ]),
        ),
      ],
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onDisable;
  const _ReminderTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onDisable});

  @override
  Widget build(BuildContext context) => GlassCard(
    borderRadius: BorderRadius.circular(12),
    bgColor: color.withAlpha(10),
    borderColor: color.withAlpha(40),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withAlpha(25), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 16)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(120))),
      ])),
      IconButton(
        icon: Icon(Icons.notifications_off_outlined, color: Colors.white.withAlpha(140), size: 18),
        tooltip: 'Disable reminder',
        onPressed: onDisable,
      ),
    ]),
  );
}

// ── Forms ─────────────────────────────────────────────────────────────────────

class _TimetableForm extends StatefulWidget {
  final String role;
  final Map<String, dynamic>? existing;
  const _TimetableForm({required this.role, this.existing});
  @override
  State<_TimetableForm> createState() => _TimetableFormState();
}

class _TimetableFormState extends State<_TimetableForm> {
  final _subjectCtrl = TextEditingController();
  final _venueCtrl   = TextEditingController();
  int    _dayIndex   = 1;
  String _startTime  = '08:00';
  String _endTime    = '10:00';
  String _type       = 'Lecture';
  bool   _reminder   = true;
  bool   _saving     = false;

  late List<String> _types;

  @override
  void initState() {
    super.initState();
    _types = widget.role == 'lecturer'
        ? ['Lecture', 'Tutorial', 'Lab', 'Office Hours']
        : ['Lecture', 'Tutorial', 'Lab', 'Practical'];
    final e = widget.existing;
    if (e != null) {
      _subjectCtrl.text = e['subject'] as String? ?? '';
      _venueCtrl.text   = e['venue']   as String? ?? '';
      _dayIndex         = e['dayIndex'] as int? ?? 1;
      _startTime        = e['startTime'] as String? ?? '08:00';
      _endTime          = e['endTime']   as String? ?? '10:00';
      _type             = e['type']      as String? ?? _types[0];
      _reminder         = e['reminder']  as bool? ?? true;
    }
  }

  @override
  void dispose() { _subjectCtrl.dispose(); _venueCtrl.dispose(); super.dispose(); }

  Future<void> _pickTime(bool isStart) async {
    final parts = (isStart ? _startTime : _endTime).split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (t != null) setState(() {
      final s = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      if (isStart) _startTime = s; else _endTime = s;
    });
  }

  Future<void> _save() async {
    if (_subjectCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final data = {
      'subject':   _subjectCtrl.text.trim(),
      'venue':     _venueCtrl.text.trim(),
      'dayIndex':  _dayIndex,
      'startTime': _startTime,
      'endTime':   _endTime,
      'type':      _type,
      'reminder':  _reminder,
    };
    try {
      if (widget.existing != null) {
        await PlannerService.updateTimetableSlot(widget.existing!['id'] as String, data);
      } else {
        await PlannerService.addTimetableSlot(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FormSheet(
      title: widget.existing != null
          ? 'Edit ${widget.role == 'lecturer' ? 'Teaching Slot' : 'Class'}'
          : 'Add ${widget.role == 'lecturer' ? 'Teaching Slot' : 'Class'}',
      saving: _saving,
      onSave: _save,
      children: [
        _GlassInput(controller: _subjectCtrl, hint: widget.role == 'lecturer' ? 'Course / Subject' : 'Subject / Course', icon: Icons.book_outlined),
        const SizedBox(height: 10),
        _GlassInput(controller: _venueCtrl, hint: 'Venue / Room (optional)', icon: Icons.location_on_outlined),
        const SizedBox(height: 10),
        // Day selector
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: PlannerService.days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final selected = _dayIndex == i + 1;
              return GestureDetector(
                onTap: () => setState(() => _dayIndex = i + 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF2563EB) : Colors.white.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selected ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(30)),
                  ),
                  child: Text(PlannerService.days[i].substring(0, 3),
                    style: TextStyle(color: Colors.white, fontWeight: selected ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _TimeButton(label: 'Start', time: _startTime, onTap: () => _pickTime(true))),
          const SizedBox(width: 10),
          Expanded(child: _TimeButton(label: 'End',   time: _endTime,   onTap: () => _pickTime(false))),
        ]),
        const SizedBox(height: 10),
        // Type chips
        Wrap(spacing: 8, children: _types.map((t) {
          final sel = _type == t;
          return GestureDetector(
            onTap: () => setState(() => _type = t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFF7C3AED).withAlpha(60) : Colors.white.withAlpha(15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? const Color(0xFFB794F4) : Colors.white.withAlpha(30)),
              ),
              child: Text(t, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
            ),
          );
        }).toList()),
        const SizedBox(height: 10),
        _ReminderToggle(value: _reminder, onChanged: (v) => setState(() => _reminder = v)),
      ],
    );
  }
}

class _StudyPlanForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _StudyPlanForm({this.existing});
  @override
  State<_StudyPlanForm> createState() => _StudyPlanFormState();
}

class _StudyPlanFormState extends State<_StudyPlanForm> {
  final _topicCtrl    = TextEditingController();
  final _courseCtrl   = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _notesCtrl    = TextEditingController();
  DateTime? _dateTime;
  bool _reminder = true;
  bool _saving   = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _topicCtrl.text    = e['topic']    as String? ?? '';
      _courseCtrl.text   = e['course']   as String? ?? '';
      _durationCtrl.text = e['duration'] as String? ?? '';
      _notesCtrl.text    = e['notes']    as String? ?? '';
      final ts = e['dateTime'] as Timestamp?;
      _dateTime = ts?.toDate();
      _reminder = e['reminder'] as bool? ?? true;
    }
  }

  @override
  void dispose() {
    _topicCtrl.dispose(); _courseCtrl.dispose();
    _durationCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateTime ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime ?? DateTime.now()),
    );
    if (time == null) return;
    setState(() => _dateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (_topicCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final data = {
      'topic':    _topicCtrl.text.trim(),
      'course':   _courseCtrl.text.trim(),
      'duration': _durationCtrl.text.trim(),
      'notes':    _notesCtrl.text.trim(),
      'dateTime': _dateTime != null ? Timestamp.fromDate(_dateTime!) : null,
      'reminder': _reminder,
    };
    try {
      if (widget.existing != null) {
        await PlannerService.updateStudyPlan(widget.existing!['id'] as String, data);
      } else {
        await PlannerService.addStudyPlan(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FormSheet(
      title: widget.existing != null ? 'Edit Study Session' : 'Add Study Session',
      saving: _saving,
      onSave: _save,
      children: [
        _GlassInput(controller: _topicCtrl,    hint: 'Topic (e.g. Merge Sort)',    icon: Icons.menu_book_rounded),
        const SizedBox(height: 10),
        _GlassInput(controller: _courseCtrl,   hint: 'Course (e.g. CS 3201)',      icon: Icons.school_outlined),
        const SizedBox(height: 10),
        _GlassInput(controller: _durationCtrl, hint: 'Duration (e.g. 2 hours)',    icon: Icons.timer_outlined),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickDateTime,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(30)),
            ),
            child: Row(children: [
              Icon(Icons.event_rounded, color: Colors.white.withAlpha(140), size: 18),
              const SizedBox(width: 10),
              Text(
                _dateTime != null
                    ? DateFormat('EEE, MMM d · h:mm a').format(_dateTime!)
                    : 'Pick date & time',
                style: TextStyle(color: _dateTime != null ? Colors.white : Colors.white.withAlpha(100), fontSize: 14),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        _GlassInput(controller: _notesCtrl, hint: 'Notes (optional)', icon: Icons.notes_rounded, maxLines: 3),
        const SizedBox(height: 10),
        _ReminderToggle(value: _reminder, onChanged: (v) => setState(() => _reminder = v)),
      ],
    );
  }
}

class _StudyGuideForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _StudyGuideForm({this.existing});
  @override
  State<_StudyGuideForm> createState() => _StudyGuideFormState();
}

class _StudyGuideFormState extends State<_StudyGuideForm> {
  final _titleCtrl   = TextEditingController();
  final _courseCtrl  = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text   = e['title']   as String? ?? '';
      _courseCtrl.text  = e['course']  as String? ?? '';
      _contentCtrl.text = e['content'] as String? ?? '';
    }
  }

  @override
  void dispose() { _titleCtrl.dispose(); _courseCtrl.dispose(); _contentCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final data = {
      'title':   _titleCtrl.text.trim(),
      'course':  _courseCtrl.text.trim(),
      'content': _contentCtrl.text.trim(),
    };
    try {
      if (widget.existing != null) {
        await PlannerService.updateStudyGuide(widget.existing!['id'] as String, data);
      } else {
        await PlannerService.addStudyGuide(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
    title: widget.existing != null ? 'Edit Study Guide' : 'New Study Guide',
    saving: _saving,
    onSave: _save,
    children: [
      _GlassInput(controller: _titleCtrl,   hint: 'Title',          icon: Icons.title_rounded),
      const SizedBox(height: 10),
      _GlassInput(controller: _courseCtrl,  hint: 'Course (e.g. CS 3201)', icon: Icons.school_outlined),
      const SizedBox(height: 10),
      _GlassInput(controller: _contentCtrl, hint: 'Notes / content…', icon: Icons.notes_rounded, maxLines: 6),
    ],
  );
}

// ── Shared form shell ─────────────────────────────────────────────────────────

class _FormSheet extends StatelessWidget {
  final String title;
  final bool saving;
  final VoidCallback onSave;
  final List<Widget> children;
  const _FormSheet({required this.title, required this.saving, required this.onSave, required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1A4A).withAlpha(230),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: saving ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            )),
          ])),
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _GlassInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;
  const _GlassInput({required this.controller, required this.hint, required this.icon, this.maxLines = 1});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withAlpha(15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withAlpha(30)),
    ),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withAlpha(80), fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.white.withAlpha(140), size: 18),
        border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
  );
}

class _TimeButton extends StatelessWidget {
  final String label, time;
  final VoidCallback onTap;
  const _TimeButton({required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Row(children: [
        Icon(Icons.schedule_rounded, color: Colors.white.withAlpha(140), size: 16),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 10)),
          Text(time,  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      ]),
    ),
  );
}

class _ReminderToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ReminderToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withAlpha(10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withAlpha(25)),
    ),
    child: Row(children: [
      Icon(Icons.notifications_outlined, color: Colors.white.withAlpha(160), size: 18),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Reminder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        Text('Notify 10 minutes before', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 11)),
      ])),
      Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFF4F8AFF)),
    ]),
  );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6));
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 56, color: Colors.white.withAlpha(60)),
      const SizedBox(height: 16),
      Text(title,    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13, height: 1.5)),
    ]),
  ));
}
