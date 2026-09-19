import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../utils/glass.dart';
import '../../widgets/bottom_nav_bar.dart';

/// "ZChat AI" hub — entry point for all AI academic-assistant features.
/// Shows recent conversations and quick links into each tool. Course-specific
/// tools ask the student to pick one of their courses first.
class AiHomeScreen extends StatefulWidget {
  const AiHomeScreen({super.key});
  @override
  State<AiHomeScreen> createState() => _AiHomeScreenState();
}

class _AiHomeScreenState extends State<AiHomeScreen> {
  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      safeArea: true,
      bottomNavigationBar: const AppBottomNavBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildNewChatButton(context),
          const SizedBox(height: 24),
          _buildSectionTitle('Tools'),
          const SizedBox(height: 12),
          _buildToolsGrid(context),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const Align(
      alignment: Alignment.centerLeft,
      child: ZBrandLockup(word: 'ZCHAT AI', symbolSize: 50, fontSize: 26, tagline: 'Your AI assistant'),
    ).animate().fadeIn().slideY(begin: -0.05, end: 0);
  }

  Widget _buildNewChatButton(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/ai/chat'),
      child: GlassCard(
        borderRadius: BorderRadius.circular(18),
        bgColor: const Color(0xFF7C3AED),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.white.withAlpha(30), shape: BoxShape.circle),
            child: const Icon(Icons.add_comment_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New chat', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              Text('Ask anything about your courses', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
        ]),
      ),
    ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.06, end: 0);
  }

  Widget _buildSectionTitle(String text) => Text(
    text,
    style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
  );

  /// Course-specific tools (quiz, summaries, exam, plan) need a course. Ask the
  /// student to pick one of their timetable courses, then navigate to
  /// [routeFor] with the chosen subject. Falls back to a general session if the
  /// student has no courses yet.
  Future<void> _pickCourseThen(String Function(String courseId) routeFor) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final subjects = <String>[];
    if (uid != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users').doc(uid).collection('timetable').get();
        final seen = <String>{};
        for (final d in snap.docs) {
          final s = (d.data()['subject'] as String? ?? '').trim();
          if (s.isNotEmpty && seen.add(s)) subjects.add(s);
        }
        subjects.sort();
      } catch (_) {}
    }
    if (!mounted) return;

    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Add your courses in the Planner timetable first.'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'Planner', onPressed: () => context.push('/planner')),
      ));
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Choose a course',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in subjects)
                  ListTile(
                    leading: const Icon(Icons.menu_book_rounded, color: Color(0xFFB794F4)),
                    title: Text(s, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      context.push(routeFor(Uri.encodeComponent(s)));
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _buildToolsGrid(BuildContext context) {
    final tools = [
      _Tool('AI Chat', 'Ask questions & get help', Icons.smart_toy_rounded, const Color(0xFF7C3AED),
          () => context.push('/ai/chat')),
      _Tool('Practice Quiz', 'Test yourself with MCQs', Icons.quiz_rounded, const Color(0xFF2563EB),
          () => _pickCourseThen((c) => '/ai/quiz/$c')),
      _Tool('Course Summaries', 'AI-generated study cards', Icons.menu_book_rounded, const Color(0xFF0EA5E9),
          () => _pickCourseThen((c) => '/ai/summaries/$c')),
      _Tool('Past Papers', 'Browse & practice', Icons.description_rounded, const Color(0xFF16A34A),
          () => context.push('/courses')),
      _Tool('AI Practice', 'Timed AI practice', Icons.timer_rounded, const Color(0xFFF59E0B),
          () => _pickCourseThen((c) => '/exam-simulator/$c')),
      _Tool('Study Planner', 'AI-personalised plans', Icons.event_note_rounded, const Color(0xFFEC4899),
          () => _pickCourseThen((c) => '/adaptive-plan/$c')),
      _Tool('Group Summarizer', 'Catch up on group chats', Icons.groups_rounded, const Color(0xFF14B8A6),
          () => context.push('/ai/group-summarizer')),
      _Tool('Study Insights', 'Personalised recommendations', Icons.insights_rounded, const Color(0xFF8B5CF6),
          () => context.push('/ai/insights')),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tools.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (ctx, i) {
        final t = tools[i];
        return GestureDetector(
          onTap: t.onTap,
          child: GlassCard(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: t.color.withAlpha(45), shape: BoxShape.circle),
                child: Icon(t.icon, color: t.color, size: 18),
              ),
              const Spacer(),
              Text(t.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(t.subtitle, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ).animate(delay: (i * 30).ms).fadeIn().slideY(begin: 0.06, end: 0);
      },
    );
  }
}

class _Tool {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _Tool(this.title, this.subtitle, this.icon, this.color, this.onTap);
}
