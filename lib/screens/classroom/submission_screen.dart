import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/ai_service.dart';
import '../../utils/glass.dart';

class SubmissionScreen extends StatefulWidget {
  final String assignmentId;
  const SubmissionScreen({super.key, required this.assignmentId});
  @override
  State<SubmissionScreen> createState() => _SubmissionScreenState();
}

class _SubmissionScreenState extends State<SubmissionScreen> {
  final _ctrl     = TextEditingController();
  String? _fileName;
  bool _submitted = false;
  bool _loading   = false;
  Map<String, dynamic>? _aiFeedback;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _fileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Add text or attach a file'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    setState(() => _loading = true);
    try {
      final fb = await AiService.getAssignmentFeedback(
        submissionText: text.isNotEmpty ? text : 'File attachment: $_fileName',
        assignmentTitle: 'Lab 3 – Recursion',
        totalMarks: 25,
      );
      if (mounted) { setState(() { _loading = false; _submitted = true; _aiFeedback = fb; }); }
    } catch (_) {
      if (mounted) { setState(() { _loading = false; _submitted = true; }); }
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
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(color: Colors.white.withAlpha(12), border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20)))),
                  child: SafeArea(bottom: false, child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                      const Text('Submit Assignment', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    ]),
                  )),
                ),
              ),
            ),
            Expanded(child: _submitted ? _successView() : _formView()),
          ]),
        ]),
      ),
    );
  }

  Widget _formView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GlassCard(
          borderRadius: BorderRadius.circular(16),
          bgColor: const Color(0xFF2563EB).withAlpha(20),
          borderColor: const Color(0xFF2563EB).withAlpha(60),
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(width: 4, height: 44, decoration: BoxDecoration(color: const Color(0xFF4F8AFF), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Lab 3 – Recursion', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              SizedBox(height: 2),
              Text('CS 3201 – Data Structures', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
          ]),
        ).animate().fadeIn(),

        const SizedBox(height: 8),
        Row(children: [
          _Chip(icon: Icons.schedule_rounded, label: 'Due May 10, 23:59', color: const Color(0xFFFBBF24)),
          const SizedBox(width: 8),
          _Chip(icon: Icons.star_outline_rounded, label: '25 marks', color: const Color(0xFF4F8AFF)),
        ]).animate(delay: 40.ms).fadeIn(),

        const SizedBox(height: 20),
        Text('Your Answer', style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(color: Colors.white.withAlpha(15), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withAlpha(35))),
              child: TextField(
                controller: _ctrl, maxLines: 8,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6),
                decoration: InputDecoration(
                  hintText: 'Type your answer here…', hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                  border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                  filled: false, contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ),
        ).animate(delay: 80.ms).fadeIn(),

        const SizedBox(height: 20),
        Text('Attach File', style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => setState(() => _fileName = 'Assignment_${widget.assignmentId}.pdf'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _fileName != null ? const Color(0xFF2563EB).withAlpha(20) : Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _fileName != null ? const Color(0xFF4F8AFF).withAlpha(150) : Colors.white.withAlpha(30), width: _fileName != null ? 1.5 : 1),
            ),
            child: Column(children: [
              Icon(_fileName != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                size: 34, color: _fileName != null ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(140)),
              const SizedBox(height: 8),
              Text(_fileName ?? 'Tap to attach PDF, DOC, or image',
                style: TextStyle(color: _fileName != null ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(140), fontWeight: FontWeight.w500),
                textAlign: TextAlign.center),
            ]),
          ),
        ).animate(delay: 120.ms).fadeIn(),

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity, height: 54,
          child: ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), disabledBackgroundColor: const Color(0xFF2563EB).withAlpha(100), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: _loading
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Submit Assignment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ).animate(delay: 160.ms).fadeIn(),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _successView() {
    final fb = _aiFeedback;
    final grade      = fb?['grade'];
    final feedbackTx = fb?['feedback'] as String?;
    final strengths  = (fb?['strengths'] as List?)?.cast<String>() ?? [];
    final improvs    = (fb?['improvements'] as List?)?.cast<String>() ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        GlassCard(
          borderRadius: BorderRadius.circular(50),
          bgColor: const Color(0xFF86EFAC).withAlpha(30),
          borderColor: const Color(0xFF86EFAC).withAlpha(80),
          padding: const EdgeInsets.all(28),
          child: const Icon(Icons.check_rounded, size: 52, color: Color(0xFF86EFAC)),
        ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
        const SizedBox(height: 24),
        const Text('Submitted!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)).animate(delay: 200.ms).fadeIn(),
        const SizedBox(height: 8),
        Text('Your assignment has been submitted.\nYour lecturer will review it soon.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(160), height: 1.6)).animate(delay: 300.ms).fadeIn(),

        if (fb != null) ...[
          const SizedBox(height: 28),
          GlassCard(
            borderRadius: BorderRadius.circular(16),
            bgColor: const Color(0xFF7C3AED).withAlpha(18),
            borderColor: const Color(0xFFB794F4).withAlpha(50),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFFB794F4), size: 14),
                const SizedBox(width: 6),
                const Text('AI Feedback', style: TextStyle(color: Color(0xFFB794F4), fontWeight: FontWeight.w800, fontSize: 14)),
                if (grade != null) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFF86EFAC).withAlpha(30), borderRadius: BorderRadius.circular(8)),
                    child: Text('$grade / 25', style: const TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ],
              ]),
              if (feedbackTx != null) ...[
                const SizedBox(height: 10),
                Text(feedbackTx, style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13, height: 1.5)),
              ],
              if (strengths.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Strengths', style: TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                ...strengths.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('• ', style: TextStyle(color: Color(0xFF86EFAC))),
                    Expanded(child: Text(s, style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 12))),
                  ]),
                )),
              ],
              if (improvs.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('To Improve', style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 4),
                ...improvs.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('• ', style: TextStyle(color: Color(0xFFFBBF24))),
                    Expanded(child: Text(s, style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 12))),
                  ]),
                )),
              ],
            ]),
          ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.05, end: 0),
        ],

        const SizedBox(height: 28),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: const Text('Back to Assignments', style: TextStyle(fontWeight: FontWeight.w700)),
        )).animate(delay: 500.ms).fadeIn(),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _Chip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withAlpha(60))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color), const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    ]),
  );
}
