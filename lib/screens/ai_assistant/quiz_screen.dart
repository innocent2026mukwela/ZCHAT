import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/ai_service.dart';
import '../../services/courses_service.dart';
import '../../utils/glass.dart';

class QuizScreen extends StatefulWidget {
  final String courseId;
  const QuizScreen({super.key, required this.courseId});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<_Q>? _questions;
  String? _error;

  int _cur = 0, _score = 0;
  int? _selected;
  bool _answered = false, _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _questions = null; _error = null; _cur = 0; _score = 0; _selected = null; _answered = false; _done = false; });
    try {
      final data = await AiService.generateExamQuestions(
          courseCode: await CoursesService.descriptiveLabel(widget.courseId));
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
        return _Q(
          q: m['question'] as String? ?? '',
          topic: m['topic'] as String?,
          opts: opts,
          ans: ans.clamp(0, opts.isEmpty ? 0 : opts.length - 1),
        );
      }).where((q) => q.q.isNotEmpty && q.opts.length >= 2).toList();
      setState(() => _questions = questions);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _select(int i) {
    if (_answered) return;
    setState(() { _selected = i; _answered = true; if (i == _questions![_cur].ans) _score++; });
  }

  void _next() {
    if (_cur < _questions!.length - 1) {
      setState(() { _cur++; _selected = null; _answered = false; });
    } else {
      setState(() => _done = true);
    }
  }

  void _restart() => _load();

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
              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(color: Colors.white.withAlpha(12), border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20)))),
                  child: SafeArea(bottom: false, child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.canPop() ? context.pop() : context.go('/ai')),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Quiz – ${widget.courseId}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                        if (_questions != null && !_done)
                          Text('Question ${_cur + 1} of ${_questions!.length}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ])),
                      if (_questions != null && !_done) Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withAlpha(35))),
                        child: Text('$_score pts', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ]),
                  )),
                )),
            ),
            if (_questions != null && !_done) ClipRect(
              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: LinearProgressIndicator(
                  value: (_cur + 1) / _questions!.length,
                  backgroundColor: Colors.white.withAlpha(15), color: const Color(0xFFB794F4), minHeight: 3)),
            ),
            Expanded(child: _body()),
          ]),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(160))),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _load, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)), child: const Text('Retry')),
          ]),
        ),
      );
    }

    if (_questions == null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: Color(0xFFB794F4)),
          const SizedBox(height: 16),
          Text('Generating quiz…', style: TextStyle(color: Colors.white.withAlpha(160))),
        ]),
      );
    }

    return _done ? _resultView() : _questionView();
  }

  Widget _questionView() {
    final q = _questions![_cur];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GlassCard(
          borderRadius: BorderRadius.circular(18),
          bgColor: const Color(0xFF7C3AED).withAlpha(20),
          borderColor: const Color(0xFF7C3AED).withAlpha(60),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF7C3AED).withAlpha(60), borderRadius: BorderRadius.circular(8)),
                child: Text('Question ${_cur + 1}', style: const TextStyle(color: Color(0xFFB794F4), fontSize: 11, fontWeight: FontWeight.w700))),
              if (q.topic != null) ...[
                const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(8)),
                  child: Text(q.topic!, style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 11))),
              ],
            ]),
            const SizedBox(height: 12),
            Text(q.q, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, height: 1.5)),
          ]),
        ).animate().fadeIn().slideY(begin: -0.05, end: 0),

        const SizedBox(height: 20),

        ...q.opts.asMap().entries.map((e) {
          final i = e.key;
          Color bg = Colors.white.withAlpha(12);
          Color border = Colors.white.withAlpha(30);
          Color text = Colors.white;
          Widget? trail;

          if (_answered) {
            if (i == q.ans) { bg = const Color(0xFF86EFAC).withAlpha(30); border = const Color(0xFF86EFAC); text = const Color(0xFF86EFAC); trail = const Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC)); }
            else if (i == _selected) { bg = Colors.redAccent.withAlpha(30); border = Colors.redAccent; text = Colors.redAccent; trail = const Icon(Icons.cancel_rounded, color: Colors.redAccent); }
          } else if (_selected == i) { bg = const Color(0xFF7C3AED).withAlpha(40); border = const Color(0xFFB794F4); }

          return GestureDetector(
            onTap: () => _select(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 1.5)),
              child: Row(children: [
                Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: border.withAlpha(30), border: Border.all(color: border)),
                  child: Center(child: Text(['A','B','C','D'][i], style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: text)))),
                const SizedBox(width: 12),
                Expanded(child: Text(e.value, style: TextStyle(fontSize: 14, color: text, fontWeight: FontWeight.w500))),
                trail ?? const SizedBox.shrink(),
              ]),
            ),
          ).animate(delay: (i * 60).ms).fadeIn().slideX(begin: 0.05, end: 0);
        }),

        if (_answered) ...[
          const SizedBox(height: 12),
          GlassCard(
            borderRadius: BorderRadius.circular(12),
            bgColor: _selected == q.ans ? const Color(0xFF86EFAC).withAlpha(20) : Colors.redAccent.withAlpha(15),
            borderColor: _selected == q.ans ? const Color(0xFF86EFAC).withAlpha(80) : Colors.redAccent.withAlpha(60),
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(_selected == q.ans ? Icons.lightbulb_rounded : Icons.info_outline_rounded,
                color: _selected == q.ans ? const Color(0xFF86EFAC) : Colors.redAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                _selected == q.ans ? 'Correct! Well done 🎉' : 'Not quite. Answer: "${q.opts[q.ans]}"',
                style: TextStyle(fontSize: 13, color: _selected == q.ans ? const Color(0xFF86EFAC) : Colors.redAccent, fontWeight: FontWeight.w600))),
            ]),
          ).animate().fadeIn(),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _next,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: Text(_cur < _questions!.length - 1 ? 'Next →' : 'See Results', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          )).animate().fadeIn().slideY(begin: 0.2, end: 0),
        ],
      ]),
    );
  }

  Widget _resultView() {
    final pct = (_score / _questions!.length * 100).round();
    final pass = pct >= 60;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          GlassCard(
            borderRadius: BorderRadius.circular(80),
            bgColor: pass ? const Color(0xFF86EFAC).withAlpha(20) : const Color(0xFFFBBF24).withAlpha(20),
            borderColor: pass ? const Color(0xFF86EFAC).withAlpha(80) : const Color(0xFFFBBF24).withAlpha(80),
            padding: const EdgeInsets.all(32),
            child: Text('$pct%', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: pass ? const Color(0xFF86EFAC) : const Color(0xFFFBBF24))),
          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
          const SizedBox(height: 20),
          Text(pass ? 'Excellent! 🎉' : 'Keep Practising! 💪', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)).animate(delay: 200.ms).fadeIn(),
          const SizedBox(height: 6),
          Text('$_score out of ${_questions!.length} correct', style: TextStyle(fontSize: 15, color: Colors.white.withAlpha(160))).animate(delay: 260.ms).fadeIn(),
          const SizedBox(height: 40),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _restart,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('New Quiz', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          )).animate(delay: 350.ms).fadeIn(),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: BorderSide(color: Colors.white.withAlpha(40)), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('Back', style: TextStyle(fontWeight: FontWeight.w600)),
          )).animate(delay: 400.ms).fadeIn(),
        ]),
      ),
    );
  }
}

class _Q {
  final String q;
  final String? topic;
  final List<String> opts;
  final int ans;
  const _Q({required this.q, required this.opts, required this.ans, this.topic});
}
