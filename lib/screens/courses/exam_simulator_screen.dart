import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/ai_service.dart';
import '../../services/courses_service.dart';
import '../../utils/glass.dart';

class ExamSimulatorScreen extends StatefulWidget {
  final String courseId;
  final String paperTitle;

  const ExamSimulatorScreen({
    super.key,
    required this.courseId,
    required this.paperTitle,
  });

  @override
  State<ExamSimulatorScreen> createState() => _ExamSimulatorScreenState();
}

class _ExamSimulatorScreenState extends State<ExamSimulatorScreen> {
  bool _started = false;
  bool _submitted = false;
  int _secondsLeft = 5400;
  Timer? _timer;
  final Map<int, int> _answers = {};

  List<_ExamQuestion>? _questions;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() { _questions = null; _loadError = null; });
    try {
      final data = await AiService.generateExamQuestions(
          courseCode: await CoursesService.descriptiveLabel(widget.courseId), numQuestions: 8);
      if (!mounted) { return; }
      final questions = data.map((m) {
        final opts = (m['options'] as List?)?.cast<String>() ?? [];
        final rawAns = m['answer'];
        int ans = 0;
        if (rawAns is int) {
          ans = rawAns;
        } else if (rawAns is String) {
          final letter = rawAns.trim().toUpperCase();
          if (letter == 'A') { ans = 0; }
          else if (letter == 'B') { ans = 1; }
          else if (letter == 'C') { ans = 2; }
          else if (letter == 'D') { ans = 3; }
          else { ans = int.tryParse(rawAns) ?? 0; }
        }
        return _ExamQuestion(
          topic: m['topic'] as String? ?? 'General',
          question: m['question'] as String? ?? '',
          options: opts,
          answer: ans.clamp(0, opts.isEmpty ? 0 : opts.length - 1),
        );
      }).where((q) => q.question.isNotEmpty && q.options.length >= 2).toList();
      if (mounted) { setState(() => _questions = questions); }
    } catch (e) {
      if (mounted) { setState(() => _loadError = e.toString().replaceFirst('Exception: ', '')); }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => _started = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        _submit();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _submit() async {
    _timer?.cancel();
    setState(() => _submitted = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final qs = _questions ?? [];
    final total = qs.isEmpty ? 1 : qs.length;
    final pct = (_score / total * 100).round();
    final weakTopics = qs
        .asMap()
        .entries
        .where((e) => _answers[e.key] != e.value.answer)
        .map((e) => e.value.topic)
        .toSet()
        .toList();
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('examAttempts')
          .add({
        'courseId': widget.courseId,
        'paperTitle': widget.paperTitle,
        'score': _score,
        'total': total,
        'percentage': pct,
        'weakTopics': weakTopics,
        'answers': _answers.map((k, v) => MapEntry(k.toString(), v)),
        'timeTakenSeconds': 5400 - _secondsLeft,
        'submittedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Non-fatal: results are already shown on screen
    }
  }

  int get _score {
    final qs = _questions ?? [];
    var score = 0;
    for (var i = 0; i < qs.length; i++) {
      if (_answers[i] == qs[i].answer) { score++; }
    }
    return score;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(
          children: [
            const GlowOrbs(),
            Column(
              children: [
                _AppBar(
                  title: _submitted ? 'Practice Results' : 'AI Practice',
                  subtitle: _started && !_submitted ? _formatTime(_secondsLeft) : widget.courseId,
                ),
                Expanded(
                  child: _submitted
                      ? _results()
                      : _started
                          ? _examOrLoading()
                          : _instructions(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _instructions() {
    final isLoading = _questions == null && _loadError == null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        GlassCard(
          borderRadius: BorderRadius.circular(20),
          padding: const EdgeInsets.all(20),
          bgColor: const Color(0xFF7C3AED).withAlpha(18),
          borderColor: const Color(0xFFB794F4).withAlpha(65),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Practice under exam conditions',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _Rule(Icons.auto_awesome_outlined, 'AI-generated questions for this course'),
              _Rule(Icons.timer_outlined, 'Time limit: 1h 30m'),
              _Rule(Icons.save_outlined, 'Results and weak topics saved to your profile'),
              _Rule(Icons.analytics_outlined, 'Results identify weak topics for a study path'),
              if (isLoading) ...[
                const SizedBox(height: 16),
                Row(children: [
                  const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(color: Color(0xFFB794F4), strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text('Generating questions…', style: TextStyle(color: Colors.white.withAlpha(155), fontSize: 13)),
                ]),
              ],
              if (_loadError != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withAlpha(70)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_loadError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                    TextButton(
                      onPressed: _loadQuestions,
                      style: TextButton.styleFrom(foregroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _questions != null ? _start : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    disabledBackgroundColor: const Color(0xFF7C3AED).withAlpha(80),
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Start Practice', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.06, end: 0),
      ],
    );
  }

  Widget _examOrLoading() {
    if (_loadError != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(160))),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _loadQuestions, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)), child: const Text('Retry')),
        ]),
      ));
    }
    if (_questions == null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: Color(0xFFB794F4)),
        const SizedBox(height: 16),
        Text('Generating exam questions…', style: TextStyle(color: Colors.white.withAlpha(160))),
      ]));
    }
    return _exam();
  }

  Widget _exam() {
    final qs = _questions!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        for (var i = 0; i < qs.length; i++) _QuestionCard(
          index: i,
          question: qs[i],
          selected: _answers[i],
          onSelected: (value) => setState(() => _answers[i] = value),
        ).animate(delay: (i * 70).ms).fadeIn().slideY(begin: 0.04, end: 0),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Submit Exam', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  Widget _results() {
    final qs = _questions ?? [];
    final total = qs.isEmpty ? 1 : qs.length;
    final pct = (_score / total * 100).round();
    final weakTopics = qs
        .asMap()
        .entries
        .where((entry) => _answers[entry.key] != entry.value.answer)
        .map((entry) => entry.value.topic)
        .toSet()
        .toList();

    // Compute actual time used from countdown
    final secondsUsed = 5400 - _secondsLeft;
    final timeTaken = _formatTime(secondsUsed);

    // Compute strong area from correctly answered questions
    final topicCounts = <String, int>{};
    for (var i = 0; i < qs.length; i++) {
      if (_answers[i] == qs[i].answer) {
        topicCounts[qs[i].topic] = (topicCounts[qs[i].topic] ?? 0) + 1;
      }
    }
    final strongArea = topicCounts.isEmpty
        ? 'None'
        : topicCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        GlassCard(
          borderRadius: BorderRadius.circular(22),
          padding: const EdgeInsets.all(22),
          bgColor: const Color(0xFF2563EB).withAlpha(18),
          borderColor: const Color(0xFF4F8AFF).withAlpha(70),
          child: Column(
            children: [
              Text('$pct%', style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 46, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('$_score/$total correct',
                  style: TextStyle(color: Colors.white.withAlpha(175), fontWeight: FontWeight.w600)),
              const SizedBox(height: 18),
              _ResultRow('Time taken', timeTaken),
              _ResultRow('Strong area', strongArea),
              _ResultRow('Needs work', weakTopics.isEmpty ? 'None' : weakTopics.join(', ')),
            ],
          ),
        ).animate().fadeIn().scale(begin: const Offset(0.96, 0.96)),
        const SizedBox(height: 14),
        GlassCard(
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI feedback', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              weakTopics.isEmpty
                  ? 'Good coverage. Try a harder paper next.'
                  : 'Focus on ${weakTopics.join(', ')} before the next attempt. Review notes, then retry similar questions.',
              style: TextStyle(color: Colors.white.withAlpha(170), height: 1.45),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => context.push('/adaptive-plan/${widget.courseId}'),
          icon: const Icon(Icons.route_outlined),
          label: const Text('Generate Study Path'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }
}

class AdaptiveLearningPathScreen extends StatefulWidget {
  final String courseId;
  final List<String> weakTopics;

  const AdaptiveLearningPathScreen({super.key, required this.courseId, this.weakTopics = const []});

  @override
  State<AdaptiveLearningPathScreen> createState() => _AdaptiveLearningPathScreenState();
}

class _AdaptiveLearningPathScreenState extends State<AdaptiveLearningPathScreen> {
  List<_Activity>? _activities;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _activities = null; _error = null; });
    try {
      final data = await AiService.generateAdaptivePlan(
          courseId: await CoursesService.descriptiveLabel(widget.courseId), weakTopics: widget.weakTopics);
      if (!mounted) { return; }
      final activities = data.map((m) => _Activity(
        topic: m['topic'] as String? ?? 'Topic',
        mastery: (m['mastery'] as num?)?.toInt() ?? 50,
        task: m['task'] as String? ?? '',
        hours: (m['hours'] as num?)?.toDouble() ?? 1.0,
      )).toList();
      setState(() => _activities = activities);
    } catch (e) {
      if (mounted) { setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Column(children: [
            _AppBar(title: 'Adaptive Study Path', subtitle: 'Weak topics first',
              actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _load)]),
            Expanded(child: _body()),
          ]),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(160))),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _load, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)), child: const Text('Retry')),
        ]),
      ));
    }
    if (_activities == null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: Color(0xFFB794F4)),
        const SizedBox(height: 16),
        Text('Building your study plan…', style: TextStyle(color: Colors.white.withAlpha(160))),
      ]));
    }
    final acts = _activities!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      children: [
        GlassCard(
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.all(16),
          bgColor: const Color(0xFF86EFAC).withAlpha(14),
          borderColor: const Color(0xFF86EFAC).withAlpha(55),
          child: Text(
            '${widget.courseId} plan generated by AI based on your weak topics.',
            style: TextStyle(color: Colors.white.withAlpha(180), height: 1.4),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < acts.length; i++)
          _ActivityCard(activity: acts[i])
              .animate(delay: (i * 80).ms)
              .fadeIn()
              .slideY(begin: 0.05, end: 0),
      ],
    );
  }
}

class _AppBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const _AppBar({required this.title, required this.subtitle, this.actions = const []});

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
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ]),
                ),
                ...actions,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Rule(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, color: const Color(0xFFB794F4), size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: Colors.white.withAlpha(170)))),
      ]),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final int index;
  final _ExamQuestion question;
  final int? selected;
  final ValueChanged<int> onSelected;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Q${index + 1} • ${question.topic}',
            style: const TextStyle(color: Color(0xFFB794F4), fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(question.question, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.35)),
        const SizedBox(height: 12),
        for (var i = 0; i < question.options.length; i++)
          GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected == i ? const Color(0xFF4F8AFF).withAlpha(40) : Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected == i ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(25), width: selected == i ? 1.5 : 1),
              ),
              child: Row(children: [
                Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected == i ? const Color(0xFF4F8AFF) : Colors.transparent,
                    border: Border.all(color: selected == i ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(80)),
                  ),
                  child: selected == i ? const Icon(Icons.check, size: 11, color: Colors.white) : null,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(question.options[i], style: TextStyle(color: Colors.white.withAlpha(selected == i ? 255 : 190), fontSize: 13))),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  const _ResultRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Text(label, style: TextStyle(color: Colors.white.withAlpha(130))),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _ActivityCard extends StatefulWidget {
  final _Activity activity;
  const _ActivityCard({required this.activity});

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(14),
        bgColor: _done ? const Color(0xFF86EFAC).withAlpha(16) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircularProgressIndicator(
            value: activity.mastery / 100,
            color: activity.mastery < 60 ? const Color(0xFFFBBF24) : const Color(0xFF86EFAC),
            backgroundColor: Colors.white.withAlpha(18),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${activity.topic} • ${activity.mastery}% mastery',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(activity.task, style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13, height: 1.35)),
            const SizedBox(height: 6),
            Text('${activity.hours} hours estimated',
                style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 12, fontWeight: FontWeight.w700)),
          ])),
          Checkbox(
            value: _done,
            activeColor: const Color(0xFF86EFAC),
            onChanged: (value) => setState(() => _done = value ?? false),
          ),
        ]),
      ),
    );
  }
}

class _ExamQuestion {
  final String topic;
  final String question;
  final List<String> options;
  final int answer;

  const _ExamQuestion({
    required this.topic,
    required this.question,
    required this.options,
    required this.answer,
  });
}

class _Activity {
  final String topic;
  final int mastery;
  final String task;
  final double hours;

  const _Activity({
    required this.topic,
    required this.mastery,
    required this.task,
    required this.hours,
  });
}
