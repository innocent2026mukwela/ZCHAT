import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../utils/glass.dart';

class AssignmentListScreen extends StatefulWidget {
  final String courseId;
  const AssignmentListScreen({super.key, required this.courseId});
  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentListScreenState extends State<AssignmentListScreen> {
  String _filter = 'All';

  static const _assignments = [
    _A(title: 'Lab 3 – Recursion',       due: 'May 10, 23:59', status: 'open',      marks: 25),
    _A(title: 'Assignment 2 – Sorting',  due: 'May 5, 23:59',  status: 'submitted', marks: 30),
    _A(title: 'Quiz 1 – Arrays & Lists', due: 'Apr 28, 20:00', status: 'graded',    marks: 15),
    _A(title: 'Lab 2 – Linked Lists',    due: 'Apr 20, 23:59', status: 'graded',    marks: 25),
    _A(title: 'Assignment 1 – Big-O',    due: 'Apr 10, 23:59', status: 'graded',    marks: 20),
  ];

  static Color _statusColor(String s) => switch (s) {
    'open'      => const Color(0xFFFBBF24),
    'submitted' => const Color(0xFF4F8AFF),
    'graded'    => const Color(0xFF86EFAC),
    _           => Colors.white54,
  };

  List<_A> get _filtered => _filter == 'All' ? _assignments : _assignments.where((a) => a.status == _filter.toLowerCase()).toList();

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
                  child: SafeArea(bottom: false, child: Column(children: [
                    Padding(padding: const EdgeInsets.fromLTRB(4, 8, 16, 0), child: Row(children: [
                      IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                      Expanded(child: Text('${widget.courseId} – Assignments', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
                    ])),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: ['All', 'Open', 'Submitted', 'Graded'].map((f) {
                          final sel = _filter == f;
                          return GestureDetector(
                            onTap: () => setState(() => _filter = f),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: sel ? const Color(0xFF2563EB) : Colors.white.withAlpha(18),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: sel ? const Color(0xFF2563EB) : Colors.white.withAlpha(35)),
                                boxShadow: sel ? [BoxShadow(color: const Color(0xFF2563EB).withAlpha(80), blurRadius: 10)] : [],
                              ),
                              child: Text(f, style: TextStyle(color: Colors.white, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
                            ),
                          );
                        }).toList()),
                      ),
                    ),
                  ])),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final a = _filtered[i];
                  final color = _statusColor(a.status);
                  return GlassCard(
                    borderRadius: BorderRadius.circular(14),
                    bgColor: a.status == 'open' ? const Color(0xFFFBBF24).withAlpha(10) : null,
                    borderColor: a.status == 'open' ? const Color(0xFFFBBF24).withAlpha(60) : null,
                    padding: const EdgeInsets.all(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        if (a.status == 'open')   context.push('/classroom/submit/assign-00${i+1}');
                        if (a.status == 'graded') context.push('/classroom/grades/assign-00${i+1}');
                      },
                      child: Row(children: [
                        Container(width: 44, height: 44,
                          decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withAlpha(60))),
                          child: Icon(Icons.assignment_outlined, color: color, size: 20)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(height: 5),
                          Row(children: [
                            Icon(Icons.schedule_rounded, size: 11, color: Colors.white.withAlpha(140)),
                            const SizedBox(width: 4),
                            Text('Due: ${a.due}', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(140))),
                            const SizedBox(width: 8),
                            Icon(Icons.star_outline_rounded, size: 11, color: Colors.white.withAlpha(140)),
                            const SizedBox(width: 3),
                            Text('${a.marks} marks', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(140))),
                          ]),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withAlpha(60))),
                          child: Text(a.status.toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ),
                  ).animate(delay: (i * 50).ms).fadeIn().slideY(begin: 0.05, end: 0);
                },
              ),
            ),
          ]),
          Positioned(
            bottom: 16, right: 16,
            child: FloatingActionButton.extended(
              backgroundColor: const Color(0xFF2563EB),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('New Assignment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              onPressed: () {},
            ),
          ),
        ]),
      ),
    );
  }
}

class _A { final String title, due, status; final int marks; const _A({required this.title, required this.due, required this.status, required this.marks}); }
