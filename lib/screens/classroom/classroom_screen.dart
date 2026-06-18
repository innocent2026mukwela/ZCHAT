import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../utils/glass.dart';

class ClassroomScreen extends StatelessWidget {
  final String courseId;
  const ClassroomScreen({super.key, required this.courseId});

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
          Column(children: [
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(color: Colors.white.withAlpha(12), border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20)))),
                  child: SafeArea(bottom: false, child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 8, 12),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(courseId, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                        const Text('Classroom', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ])),
                      IconButton(icon: const Icon(Icons.assignment_outlined, color: Colors.white), onPressed: () => context.push('/classroom/$courseId/assignments')),
                      _MoreMenu(courseId: courseId),
                    ]),
                  )),
                ),
              ),
            ),
            Expanded(child: _ClassroomBody(courseId: courseId)),
          ]),
        ]),
      ),
    );
  }
}

class _ClassroomBody extends StatelessWidget {
  final String courseId;
  const _ClassroomBody({required this.courseId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('courses').doc(courseId).snapshots(),
      builder: (context, courseSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('courses').doc(courseId)
              .collection('sessions')
              .orderBy('scheduledAt', descending: true)
              .snapshots(),
          builder: (context, sessionsSnap) {
            if (sessionsSnap.hasError) {
              return Center(child: Text('Could not load sessions', style: TextStyle(color: Colors.white.withAlpha(140))));
            }
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('courses').doc(courseId)
                  .collection('assignments')
                  .snapshots(),
              builder: (context, assignSnap) {
                if (assignSnap.hasError) {
                  return Center(child: Text('Could not load assignments', style: TextStyle(color: Colors.white.withAlpha(140))));
                }
                final sessions   = sessionsSnap.data?.docs ?? [];
                final assigns    = assignSnap.data?.docs ?? [];
                final courseData = courseSnap.data?.data() as Map<String, dynamic>? ?? {};
                final enrolled   = courseData['enrolledCount'] as int? ?? 0;

                // Compute avg score from graded submissions
                final avgScore = courseData['avgScore'] as num?;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    // Stats row
                    Row(children: [
                      _StatCard('${sessions.length}', 'Sessions', Icons.cast_for_education_outlined, const Color(0xFF4F8AFF)),
                      const SizedBox(width: 8),
                      _StatCard('${assigns.length}', 'Assignments', Icons.assignment_outlined, const Color(0xFFB794F4)),
                      const SizedBox(width: 8),
                      _StatCard('$enrolled', 'Students', Icons.group_outlined, const Color(0xFF86EFAC)),
                      const SizedBox(width: 8),
                      _StatCard(avgScore != null ? '${avgScore.toStringAsFixed(0)}%' : 'N/A', 'Avg Score', Icons.bar_chart_rounded, const Color(0xFFFBBF24)),
                    ]).animate().fadeIn(),

                    const SizedBox(height: 16),

                    // Live session card
                    GlassCard(
                      borderRadius: BorderRadius.circular(18),
                      padding: const EdgeInsets.all(18),
                      bgColor: const Color(0xFF2563EB).withAlpha(30),
                      borderColor: const Color(0xFF2563EB).withAlpha(80),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(60), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.cast_for_education_rounded, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Start Live Session', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                          Text('Students notified instantly', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        ])),
                        ElevatedButton(
                          onPressed: () async {
                            final roomId = const Uuid().v4();
                            try {
                              await FirebaseFirestore.instance
                                  .collection('courses')
                                  .doc(courseId)
                                  .collection('sessions')
                                  .add({
                                'title': 'Live Session',
                                'roomId': roomId,
                                'status': 'live',
                                'scheduledAt': FieldValue.serverTimestamp(),
                              });
                              if (context.mounted) {
                                context.push('/classroom/$courseId/live/$roomId');
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('Could not start session: ${e.toString().replaceFirst("Exception: ", "")}'),
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ));
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            minimumSize: const Size(70, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Start', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ]),
                    ).animate(delay: 60.ms).fadeIn(),

                    const SizedBox(height: 20),

                    const Text('Sessions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 8),

                    if (sessions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No sessions yet', style: TextStyle(color: Colors.white.withAlpha(140)))),
                      )
                    else
                      ...sessions.asMap().entries.map((e) {
                        final i = e.key;
                        final data = e.value.data() as Map<String, dynamic>;
                        final title     = data['title'] as String? ?? 'Session';
                        final status    = data['status'] as String? ?? 'ended';
                        final ts        = data['scheduledAt'] as Timestamp?;
                        final dateStr   = ts != null
                            ? DateFormat('MMM d, HH:mm').format(ts.toDate())
                            : '';
                        final live      = status == 'live';
                        final scheduled = status == 'scheduled';
                        final roomId    = data['roomId'] as String? ?? e.value.id;

                        return GlassCard(
                          borderRadius: BorderRadius.circular(14),
                          bgColor: live ? Colors.red.withAlpha(15) : null,
                          borderColor: live ? Colors.red.withAlpha(60) : null,
                          padding: const EdgeInsets.all(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              if (status != 'ended') {
                                context.push('/classroom/$courseId/live/$roomId');
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('This session has ended'),
                                  behavior: SnackBarBehavior.floating,
                                ));
                              }
                            },
                            child: Row(children: [
                              Container(
                                width: 42, height: 42,
                                decoration: BoxDecoration(
                                  color: live ? Colors.red.withAlpha(40) : Colors.white.withAlpha(15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  live ? Icons.fiber_manual_record_rounded : scheduled ? Icons.schedule_rounded : Icons.play_circle_outline_rounded,
                                  color: live ? Colors.redAccent : scheduled ? const Color(0xFFFBBF24) : Colors.white.withAlpha(140),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                const SizedBox(height: 3),
                                Row(children: [
                                  Icon(Icons.schedule_rounded, size: 11, color: Colors.white.withAlpha(140)),
                                  const SizedBox(width: 4),
                                  Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(140))),
                                ]),
                              ])),
                              if (live)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                                  child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                                )
                              else if (scheduled)
                                const Icon(Icons.notifications_none_rounded, color: Color(0xFFFBBF24))
                              else
                                Icon(Icons.play_circle_filled_rounded, color: Colors.white.withAlpha(80), size: 20),
                            ]),
                          ),
                        ).animate(delay: (i * 50).ms).fadeIn().slideY(begin: 0.05, end: 0);
                      }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final String courseId;
  const _MoreMenu({required this.courseId});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
      color: const Color(0xFF0A1A4A),
      onSelected: (v) {
        if (v == 'assignments') context.push('/classroom/$courseId/assignments');
        if (v == 'schedule') _showScheduleSessionSheet(context);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'assignments', child: Text('Assignments', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'schedule', child: Text('Schedule session', style: TextStyle(color: Colors.white))),
      ],
    );
  }

  void _showScheduleSessionSheet(BuildContext context) {
    final titleCtrl = TextEditingController();
    DateTime picked = DateTime.now().add(const Duration(hours: 1));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Schedule Session', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 16),
          TextField(
            controller: titleCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Session title',
              labelStyle: TextStyle(color: Colors.white.withAlpha(160)),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withAlpha(40)), borderRadius: BorderRadius.circular(10)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4F8AFF)), borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final d = await showDatePicker(context: ctx, initialDate: picked, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d == null) return;
              if (!ctx.mounted) return;
              final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(picked));
              if (t == null) return;
              setSt(() => picked = DateTime(d.year, d.month, d.day, t.hour, t.minute));
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: Colors.white.withAlpha(40)), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.schedule_rounded, color: Color(0xFF4F8AFF), size: 18),
                const SizedBox(width: 8),
                Text(DateFormat('MMM d, yyyy · HH:mm').format(picked), style: const TextStyle(color: Colors.white)),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                try {
                  await FirebaseFirestore.instance
                      .collection('courses').doc(courseId)
                      .collection('sessions')
                      .add({'title': title, 'scheduledAt': Timestamp.fromDate(picked), 'status': 'scheduled', 'roomId': '${courseId}_${picked.millisecondsSinceEpoch}'});
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Could not schedule session: ${e.toString().replaceFirst("Exception: ", "")}'),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                }
              },
              child: const Text('Schedule', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      )),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _StatCard(this.value, this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: GlassCard(
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 9)),
      ]),
    ),
  );
}
