import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/ai_service.dart';
import '../../utils/glass.dart';

class StudyInsightsScreen extends StatefulWidget {
  const StudyInsightsScreen({super.key});
  @override
  State<StudyInsightsScreen> createState() => _StudyInsightsScreenState();
}

class _StudyInsightsScreenState extends State<StudyInsightsScreen> {
  final _db  = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser?.uid;

  bool _loading = true;
  String? _error;

  int _aiChatCount    = 0;
  int _courseCount    = 0;
  int _starredCount   = 0;
  List<Map<String, dynamic>> _plan = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_uid == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      // Parallel Firestore fetches
      final results = await Future.wait([
        _db.collection('users').doc(_uid).collection('timetable').get(),
        _db.collection('users').doc(_uid).collection('starred').get(),
      ]);

      final timetableSnap = results[0];
      final starredSnap   = results[1];
      final courses = <String>{};
      for (final d in timetableSnap.docs) {
        final s = (d.data()['subject'] as String?)?.trim() ?? '';
        if (s.isNotEmpty) courses.add(s);
      }

      // Backend: AI history + adaptive plan
      final historyData = await AiService.fetchHistory(limit: 10);
      List<Map<String, dynamic>> planData = [];
      if (courses.isNotEmpty) {
        try {
          planData = await AiService.generateAdaptivePlan(courseId: courses.first);
        } catch (_) {
          // non-fatal: plan section shows empty
        }
      }

      if (!mounted) return;
      setState(() {
        _courseCount  = courses.length;
        _starredCount = starredSnap.docs.length;
        _history      = historyData;
        _aiChatCount  = historyData.length;
        _plan         = planData;
        _loading      = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

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
            _buildAppBar(context),
            Expanded(child: _buildBody(context)),
          ]),
        ]),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(12),
            border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          child: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Study Insights', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('Personalised recommendations', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                onPressed: _load,
              ),
            ]),
          )),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: Color(0xFF8B5CF6)),
        SizedBox(height: 16),
        Text('Analysing your study data…', style: TextStyle(color: Colors.white54)),
      ]));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(160))),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _load,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            child: const Text('Retry'),
          ),
        ]),
      ));
    }
    return RefreshIndicator(
      color: const Color(0xFF8B5CF6),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          _buildStats(),
          const SizedBox(height: 20),
          if (_history.isNotEmpty) ...[
            _sectionTitle('Recent AI Activity'),
            const SizedBox(height: 10),
            _buildHistorySection(context),
            const SizedBox(height: 20),
          ],
          if (_plan.isNotEmpty) ...[
            _sectionTitle('AI-Recommended Focus Areas'),
            const SizedBox(height: 10),
            _buildPlanSection(context),
          ],
          if (_plan.isEmpty && _courseCount == 0) ...[
            const SizedBox(height: 24),
            _buildOnboardingHint(context),
          ],
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Row(children: [
      _StatTile('$_courseCount', 'Courses', Icons.menu_book_rounded, const Color(0xFF4F8AFF)),
      const SizedBox(width: 10),
      _StatTile('$_aiChatCount', 'AI Chats', Icons.smart_toy_rounded, const Color(0xFF8B5CF6)),
      const SizedBox(width: 10),
      _StatTile('$_starredCount', 'Starred', Icons.star_rounded, const Color(0xFFFBBF24)),
    ]).animate().fadeIn();
  }

  Widget _buildHistorySection(BuildContext context) {
    return Column(
      children: _history.take(5).toList().asMap().entries.map((e) {
        final i = e.key;
        final item = e.value;
        final q = (item['last_question'] as String? ?? '').trim();
        final a = (item['last_answer'] as String? ?? '').trim();
        final id = item['id'] as String?;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassTile(
            leading: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withAlpha(35), shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF8B5CF6), size: 16),
            ),
            title: Text(q.isNotEmpty ? q : 'Conversation', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            subtitle: a.isNotEmpty
                ? Text(a, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(130)))
                : null,
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
            onTap: () => context.push('/ai/chat', extra: id),
          ),
        ).animate(delay: (i * 40).ms).fadeIn();
      }).toList(),
    );
  }

  Widget _buildPlanSection(BuildContext context) {
    return Column(
      children: _plan.take(4).toList().asMap().entries.map((e) {
        final i    = e.key;
        final item = e.value;
        final topic   = item['topic']   as String? ?? 'Topic';
        final mastery = (item['mastery'] as num?)?.toInt() ?? 50;
        final task    = item['task']    as String? ?? '';
        final hours   = (item['hours']  as num?)?.toDouble() ?? 1.0;
        final color   = mastery < 50 ? const Color(0xFFF87171)
            : mastery < 75 ? const Color(0xFFFBBF24)
            : const Color(0xFF86EFAC);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              SizedBox(
                width: 40, height: 40,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                    value: mastery / 100,
                    color: color,
                    backgroundColor: Colors.white.withAlpha(18),
                    strokeWidth: 3.5,
                  ),
                  Text('$mastery', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(topic, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 3),
                Text(task, style: TextStyle(color: Colors.white.withAlpha(155), fontSize: 12, height: 1.3),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('${hours}h estimated', style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 11, fontWeight: FontWeight.w600)),
              ])),
            ]),
          ),
        ).animate(delay: (i * 60).ms).fadeIn().slideY(begin: 0.05, end: 0);
      }).toList(),
    );
  }

  Widget _buildOnboardingHint(BuildContext context) {
    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(20),
      bgColor: const Color(0xFF8B5CF6).withAlpha(16),
      borderColor: const Color(0xFF8B5CF6).withAlpha(50),
      child: Column(children: [
        const Icon(Icons.insights_rounded, color: Color(0xFF8B5CF6), size: 40),
        const SizedBox(height: 14),
        const Text('Add courses to unlock insights',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        Text('Add your class schedule in the Planner so AI can personalise your study recommendations.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withAlpha(155), height: 1.4, fontSize: 13)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => context.push('/planner'),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Go to Planner'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF8B5CF6),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]),
    ).animate().fadeIn();
  }

  Widget _sectionTitle(String text) => Text(text,
      style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5));
}

class _StatTile extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  const _StatTile(this.value, this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: GlassCard(
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 5),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 10)),
      ]),
    ),
  );
}
