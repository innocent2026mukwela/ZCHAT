import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/ai_service.dart';
import '../../utils/glass.dart';

class SummaryScreen extends StatefulWidget {
  final String courseId;
  const SummaryScreen({super.key, required this.courseId});
  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  List<Map<String, dynamic>>? _summaries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _summaries = null; _error = null; });
    try {
      final data = await AiService.generateCourseSummary(courseId: widget.courseId);
      if (mounted) setState(() => _summaries = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
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
            ClipRect(
              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(color: Colors.white.withAlpha(12), border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20)))),
                  child: SafeArea(bottom: false, child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 8, 12),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Summaries – ${widget.courseId}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        const Text('AI-generated lecture notes', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ])),
                      IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: _load),
                      IconButton(icon: const Icon(Icons.quiz_outlined, color: Colors.white), onPressed: () => context.push('/ai/quiz/${widget.courseId}')),
                    ]),
                  )),
                )),
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

    if (_summaries == null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(color: Color(0xFFB794F4)),
          const SizedBox(height: 16),
          Text('Generating summaries…', style: TextStyle(color: Colors.white.withAlpha(160))),
        ]),
      );
    }

    if (_summaries!.isEmpty) {
      return Center(child: Text('No summaries generated.', style: TextStyle(color: Colors.white.withAlpha(120))));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _summaries!.length,
      itemBuilder: (ctx, i) => _SummaryCard(s: _summaries![i], index: i),
    );
  }
}

class _SummaryCard extends StatefulWidget {
  final Map<String, dynamic> s;
  final int index;
  const _SummaryCard({required this.s, required this.index});
  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final title   = s['title']  as String? ?? 'Topic';
    final body    = s['body']   as String? ?? '';
    final tip     = s['tip']    as String? ?? '';
    final date    = s['date']   as String? ?? '';
    final topics  = (s['topics'] as List?)?.cast<String>() ?? [];

    return GlassCard(
      borderRadius: BorderRadius.circular(16),
      bgColor: const Color(0xFF7C3AED).withAlpha(10),
      borderColor: const Color(0xFF7C3AED).withAlpha(40),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: const Color(0xFF7C3AED).withAlpha(40), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.auto_awesome_outlined, color: Color(0xFFB794F4), size: 16)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              Text(date, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(140))),
            ])),
            Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: Colors.white.withAlpha(160)),
          ])),
        ),
        if (topics.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Wrap(spacing: 6, runSpacing: 6, children: topics.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF7C3AED).withAlpha(30), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF7C3AED).withAlpha(60))),
              child: Text(t, style: const TextStyle(fontSize: 11, color: Color(0xFFB794F4), fontWeight: FontWeight.w600)),
            )).toList()),
          ),
        if (body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(body, maxLines: _expanded ? null : 2, overflow: _expanded ? null : TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withAlpha(_expanded ? 220 : 160), fontSize: 13, height: 1.6)),
          ),
        if (tip.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFBBF24).withAlpha(20), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFBBF24).withAlpha(50))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_rounded, size: 13, color: Color(0xFFFBBF24)),
                const SizedBox(width: 7),
                Expanded(child: Text('Exam Tip: $tip', style: const TextStyle(fontSize: 12, color: Color(0xFFFBBF24), fontWeight: FontWeight.w500, height: 1.4))),
              ]),
            ),
          ),
      ]),
    ).animate(delay: (widget.index * 80).ms).fadeIn().slideY(begin: 0.05, end: 0);
  }
}
