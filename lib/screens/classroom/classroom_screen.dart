import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../utils/glass.dart';

class ClassroomScreen extends StatelessWidget {
  final String courseId;
  const ClassroomScreen({super.key, required this.courseId});

  static const _sessions = [
    _S(title: 'Introduction to Recursion', date: 'Today 14:00',    status: 'live'),
    _S(title: 'Sorting Algorithms',        date: 'Tomorrow 10:00', status: 'scheduled'),
    _S(title: 'Binary Trees Overview',     date: 'May 3, 09:00',   status: 'ended'),
    _S(title: 'Graph Theory Basics',       date: 'Apr 29, 14:00',  status: 'ended'),
    _S(title: 'Dynamic Programming',       date: 'Apr 22, 14:00',  status: 'ended'),
  ];

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
                      IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white), onPressed: () {}),
                    ]),
                  )),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // Stats
                  Row(children: [
                    _StatCard('12', 'Sessions',    Icons.cast_for_education_outlined, const Color(0xFF4F8AFF)),
                    const SizedBox(width: 8),
                    _StatCard('5',  'Assignments', Icons.assignment_outlined,         const Color(0xFFB794F4)),
                    const SizedBox(width: 8),
                    _StatCard('34', 'Students',    Icons.group_outlined,              const Color(0xFF86EFAC)),
                    const SizedBox(width: 8),
                    _StatCard('74%','Avg Score',   Icons.bar_chart_rounded,           const Color(0xFFFBBF24)),
                  ]).animate().fadeIn(),

                  const SizedBox(height: 16),

                  // Live session card
                  GlassCard(
                    borderRadius: BorderRadius.circular(18),
                    padding: const EdgeInsets.all(18),
                    bgColor: const Color(0xFF2563EB).withAlpha(30),
                    borderColor: const Color(0xFF2563EB).withAlpha(80),
                    child: Row(children: [
                      Container(padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(60), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.cast_for_education_rounded, color: Colors.white, size: 26)),
                      const SizedBox(width: 14),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Start Live Session', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                        Text('Students notified instantly', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ])),
                      ElevatedButton(
                        onPressed: () => context.push('/classroom/$courseId/live/room-001'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), minimumSize: const Size(70, 36), padding: const EdgeInsets.symmetric(horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        child: const Text('Start', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ]),
                  ).animate(delay: 60.ms).fadeIn(),

                  const SizedBox(height: 20),

                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Sessions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    TextButton(onPressed: () {}, child: const Text('See all', style: TextStyle(color: Color(0xFF4F8AFF)))),
                  ]),
                  const SizedBox(height: 8),

                  ..._sessions.asMap().entries.map((e) {
                    final i = e.key; final s = e.value;
                    final live = s.status == 'live';
                    final scheduled = s.status == 'scheduled';
                    return GlassCard(
                      borderRadius: BorderRadius.circular(14),
                      bgColor: live ? Colors.red.withAlpha(15) : null,
                      borderColor: live ? Colors.red.withAlpha(60) : null,
                      padding: const EdgeInsets.all(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () { if (!s.status.contains('ended')) context.push('/classroom/$courseId/live/room-00${i+1}'); },
                        child: Row(children: [
                          Container(width: 42, height: 42,
                            decoration: BoxDecoration(color: live ? Colors.red.withAlpha(40) : Colors.white.withAlpha(15), borderRadius: BorderRadius.circular(12)),
                            child: Icon(live ? Icons.fiber_manual_record_rounded : scheduled ? Icons.schedule_rounded : Icons.play_circle_outline_rounded,
                              color: live ? Colors.redAccent : scheduled ? const Color(0xFFFBBF24) : Colors.white.withAlpha(140), size: 20)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 3),
                            Row(children: [
                              Icon(Icons.schedule_rounded, size: 11, color: Colors.white.withAlpha(140)),
                              const SizedBox(width: 4),
                              Text(s.date, style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(140))),
                            ]),
                          ])),
                          if (live) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                            child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)))
                          else if (scheduled) const Icon(Icons.notifications_none_rounded, color: Color(0xFFFBBF24))
                          else Icon(Icons.play_circle_filled_rounded, color: Colors.white.withAlpha(80), size: 20),
                        ]),
                      ),
                    ).animate(delay: (i * 50).ms).fadeIn().slideY(begin: 0.05, end: 0);
                  }),
                ],
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _S { final String title, date, status; const _S({required this.title, required this.date, required this.status}); }

class _StatCard extends StatelessWidget {
  final String value, label; final IconData icon; final Color color;
  const _StatCard(this.value, this.label, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: GlassCard(borderRadius: BorderRadius.circular(12), padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 9)),
      ])),
  );
}
