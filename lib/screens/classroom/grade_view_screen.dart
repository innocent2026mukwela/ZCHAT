import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../utils/glass.dart';

class GradeViewScreen extends StatelessWidget {
  final String assignmentId;
  const GradeViewScreen({super.key, required this.assignmentId});

  @override
  Widget build(BuildContext context) {
    const grade = 82.0;
    const total = 100.0;

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
                    padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                      const Text('Grade & Feedback', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    ]),
                  )),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  // Score card
                  GlassCard(
                    borderRadius: BorderRadius.circular(24),
                    bgColor: const Color(0xFF2563EB).withAlpha(15),
                    borderColor: const Color(0xFF2563EB).withAlpha(60),
                    padding: const EdgeInsets.all(28),
                    child: Column(children: [
                      CircularPercentIndicator(
                        radius: 72, lineWidth: 9,
                        percent: grade / total,
                        center: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('${grade.toInt()}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white)),
                          Text('/ ${total.toInt()}', style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 14)),
                        ]),
                        progressColor: const Color(0xFF4F8AFF),
                        backgroundColor: Colors.white.withAlpha(25),
                        circularStrokeCap: CircularStrokeCap.round,
                      ).animate().scale(duration: 700.ms, curve: Curves.elasticOut),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(60), borderRadius: BorderRadius.circular(20)),
                        child: const Text('Distinction', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      ).animate(delay: 300.ms).fadeIn(),
                      const SizedBox(height: 8),
                      Text('Lab 3 – Recursion', style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13)).animate(delay: 350.ms).fadeIn(),
                    ]),
                  ).animate().fadeIn(),

                  const SizedBox(height: 16),

                  // Quick stats
                  Row(children: [
                    _Quick('3rd',    'Rank',      Icons.leaderboard_rounded,   const Color(0xFFFBBF24)),
                    const SizedBox(width: 8),
                    _Quick('68%',   'Class Avg', Icons.bar_chart_rounded,     const Color(0xFF4F8AFF)),
                    const SizedBox(width: 8),
                    _Quick('On time','Submitted', Icons.check_circle_rounded,  const Color(0xFF86EFAC)),
                  ]).animate(delay: 100.ms).fadeIn(),

                  const SizedBox(height: 16),

                  _FeedbackCard(
                    title: 'Lecturer Feedback', icon: Icons.comment_outlined, color: const Color(0xFF4F8AFF),
                    child: Text(
                      'Good work overall. Your explanation of base cases was clear and well-structured. The recursive calls were correctly implemented. A bit more detail on time complexity would earn full marks.',
                      style: TextStyle(color: Colors.white.withAlpha(220), height: 1.7, fontSize: 14)),
                  ).animate(delay: 150.ms).fadeIn(),

                  const SizedBox(height: 12),

                  _FeedbackCard(
                    title: 'AI Analysis', icon: Icons.auto_awesome_outlined, color: const Color(0xFFB794F4),
                    child: Column(children: [
                      _FRow(Icons.thumb_up_outlined,   const Color(0xFF86EFAC), 'Strong base case definition'),
                      _FRow(Icons.thumb_up_outlined,   const Color(0xFF86EFAC), 'Correct recursive structure'),
                      _FRow(Icons.trending_up_rounded, const Color(0xFFFBBF24), 'Improve complexity analysis'),
                      _FRow(Icons.trending_up_rounded, const Color(0xFFFBBF24), 'Add more edge case handling'),
                    ]),
                  ).animate(delay: 200.ms).fadeIn(),

                  const SizedBox(height: 12),

                  _FeedbackCard(
                    title: 'Plagiarism Check', icon: Icons.security_outlined, color: const Color(0xFF86EFAC),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 18),
                      const SizedBox(width: 8),
                      const Text('12% similarity – Original work', style: TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.w600)),
                    ]),
                  ).animate(delay: 250.ms).fadeIn(),

                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  final String value, label; final IconData icon; final Color color;
  const _Quick(this.value, this.label, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: GlassCard(borderRadius: BorderRadius.circular(12), padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 10)),
      ])),
  );
}

class _FeedbackCard extends StatelessWidget {
  final String title; final IconData icon; final Color color; final Widget child;
  const _FeedbackCard({required this.title, required this.icon, required this.color, required this.child});
  @override
  Widget build(BuildContext context) => GlassCard(
    borderRadius: BorderRadius.circular(14),
    bgColor: color.withAlpha(10),
    borderColor: color.withAlpha(50),
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 15)),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 12),
      child,
    ]),
  );
}

class _FRow extends StatelessWidget {
  final IconData icon; final Color color; final String label;
  const _FRow(this.icon, this.color, this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
        child: Icon(icon, size: 11, color: color)),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(220))),
    ]),
  );
}
