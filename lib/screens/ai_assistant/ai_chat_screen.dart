import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/ai_service.dart';
import '../../utils/glass.dart';
import '../../widgets/bottom_nav_bar.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _tts    = FlutterTts();
  final _stt    = SpeechToText();
  bool _loading    = false;
  bool _hasText    = false;
  bool _listening  = false;
  int? _speakingIdx;
  String? _course; // null = General mode
  final List<String> _courses = [];

  final List<_Msg> _messages = [
    _Msg(text: "Hi! I'm your AI study assistant. Ask me anything about your courses — I'll explain concepts, solve problems, and help you prepare for exams. 📚", isAi: true),
  ];

  static const _suggestions = [
    '📊 Explain recursion with examples',
    '⚡ What is Big-O notation?',
    '🌳 Summarise binary search trees',
    '🔢 Sorting algorithm practice',
    '💡 How does dynamic programming work?',
    '🎯 Exam tips for Data Structures',
  ];

  // Conversation history sent to Claude on every turn (role + content pairs)
  final List<Map<String, String>> _history = [];

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Add user message to UI and history
    setState(() {
      _messages.add(_Msg(text: trimmed, isAi: false));
      _loading = true;
      _hasText = false;
    });
    _ctrl.clear();
    _history.add({'role': 'user', 'content': trimmed});
    _scrollDown();

    try {
      final reply = await AiService.chat(
        messages: List.from(_history),
        courseId: _course?.replaceAll(' ', ''),
      );
      if (!mounted) return;
      _history.add({'role': 'assistant', 'content': reply});
      setState(() { _loading = false; _messages.add(_Msg(text: reply, isAi: true)); });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _messages.add(_Msg(text: '⚠️ ${e.toString().replaceFirst('Exception: ', '')}', isAi: true));
      });
    }
    _scrollDown();
  }

  @override
  void initState() {
    super.initState();
    _initTts();
    _initStt();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('timetable').get();
    final seen = <String>{};
    for (final doc in snap.docs) {
      final subject = (doc.data()['subject'] as String? ?? '').trim();
      if (subject.isNotEmpty) seen.add(subject);
    }
    if (mounted) {
      setState(() {
        _courses
          ..clear()
          ..addAll(seen.toList()..sort());
      });
    }
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() { if (mounted) setState(() => _speakingIdx = null); });
  }

  Future<void> _initStt() async {
    await _stt.initialize();
  }

  Future<void> _speak(String text, int index) async {
    if (_speakingIdx == index) {
      await _tts.stop();
      if (mounted) setState(() => _speakingIdx = null);
      return;
    }
    await _tts.stop();
    if (mounted) setState(() => _speakingIdx = index);
    await _tts.speak(text);
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _stt.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _stt.initialize();
    if (!available) return;
    if (mounted) setState(() => _listening = true);
    _stt.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _ctrl.text = result.recognizedWords;
            _hasText = result.recognizedWords.trim().isNotEmpty;
          });
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  void _scrollDown() => Future.delayed(const Duration(milliseconds: 100), () {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  });

  @override
  void dispose() {
    _tts.stop();
    _stt.stop();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      bottomNavigationBar: const AppBottomNavBar(),
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                    child: Row(children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        onPressed: () => context.go('/home'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Row(children: [
                        Image.asset(
                          'assets/icons/zchat_logo_cutout.png',
                          height: 26,
                          fit: BoxFit.contain,
                          errorBuilder: (ctx, e, s) => const Text('ZCHAT', style: TextStyle(color: Color(0xFF2EA3FF), fontSize: 16, fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(width: 6),
                        const Text('Tutor', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      ])),
                      GestureDetector(
                        onTap: () => _showCourseSelector(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withAlpha(35))),
                          child: Row(children: [
                            Text(_course ?? 'General', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 3),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 14),
                          ]),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                        color: const Color(0xFF0A1A4A),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'quiz', child: Text('Generate Quiz', style: TextStyle(color: Colors.white.withAlpha(220)))),
                          PopupMenuItem(value: 'summary', child: Text('View Summaries', style: TextStyle(color: Colors.white.withAlpha(220)))),
                          PopupMenuItem(value: 'clear', child: Text('Clear Chat', style: TextStyle(color: Colors.white.withAlpha(220)))),
                        ],
                        onSelected: (v) {
                          if (v == 'quiz') context.push('/ai/quiz/${_course ?? 'General'}');
                          if (v == 'summary') context.push('/ai/summaries/${_course ?? 'General'}');
                          if (v == 'clear') setState(() { _messages.clear(); _history.clear(); _messages.add(_Msg(text: 'Chat cleared. Ask me anything! 🎯', isAi: true)); });
                        },
                      ),
                    ]),
                  )),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                itemCount: _messages.length + (_loading ? 1 : 0) + (_messages.length == 1 ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i == 1 && _messages.length == 1) return _Suggestions(suggestions: _suggestions, onTap: _send);
                  final mi = (_messages.length == 1 && i > 1) ? i - 1 : i;
                  if (_loading && mi == _messages.length) return const _Typing();
                  if (mi >= _messages.length) return const SizedBox();
                  return _Bubble(msg: _messages[mi], index: mi, onSpeak: _speak, speakingIdx: _speakingIdx);
                },
              ),
            ),
            _buildInput(),
          ]),
        ]),
      ),
    );
  }

  Widget _buildInput() => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        decoration: BoxDecoration(color: Colors.white.withAlpha(12), border: Border(top: BorderSide(color: Colors.white.withAlpha(20)))),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: SafeArea(top: false, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withAlpha(35))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        _listening ? Icons.mic_off_rounded : Icons.mic_rounded,
                        color: _listening ? Colors.redAccent : const Color(0xFFB794F4),
                        size: 20,
                      ),
                      onPressed: _toggleListen,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _ctrl, maxLines: null,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Ask anything…', hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                          border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10), filled: false,
                        ),
                        onChanged: (v) => setState(() => _hasText = v.trim().isNotEmpty),
                        onSubmitted: _send,
                      ),
                    ),
                  ]),
                )),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _hasText ? () => _send(_ctrl.text) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _hasText ? const Color(0xFF7C3AED) : Colors.white.withAlpha(20),
                shape: BoxShape.circle,
                boxShadow: _hasText ? [BoxShadow(color: const Color(0xFF7C3AED).withAlpha(100), blurRadius: 12)] : [],
              ),
              child: Icon(Icons.send_rounded, color: _hasText ? Colors.white : Colors.white.withAlpha(120), size: 20),
            ),
          ),
        ])),
      ),
    ),
  );

  void _showCourseSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1A4A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Select Course', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('General', style: TextStyle(color: Colors.white)),
            subtitle: Text('Ask anything — no course context', style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12)),
            trailing: _course == null ? const Icon(Icons.check_rounded, color: Color(0xFF4F8AFF)) : null,
            onTap: () { setState(() => _course = null); Navigator.pop(context); },
          ),
          ..._courses.map((c) => ListTile(
            title: Text(c, style: const TextStyle(color: Colors.white)),
            trailing: _course == c ? const Icon(Icons.check_rounded, color: Color(0xFF4F8AFF)) : null,
            onTap: () { setState(() => _course = c); Navigator.pop(context); },
          )),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  final int index;
  final Future<void> Function(String, int)? onSpeak;
  final int? speakingIdx;
  const _Bubble({required this.msg, required this.index, this.onSpeak, this.speakingIdx});

  @override
  Widget build(BuildContext context) {
    final isSpeaking = speakingIdx == index;
    return Align(
      alignment: msg.isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(top: 4, bottom: 4, left: msg.isAi ? 0 : 52, right: msg.isAi ? 52 : 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: msg.isAi ? Colors.white.withAlpha(18) : const Color(0xFF7C3AED).withAlpha(200),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isAi ? 4 : 16), bottomRight: Radius.circular(msg.isAi ? 16 : 4)),
          border: Border.all(color: Colors.white.withAlpha(msg.isAi ? 25 : 40)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (msg.isAi) ...[
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, size: 11, color: Color(0xFFB794F4)),
              const SizedBox(width: 4),
              const Expanded(child: Text('AI Tutor', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFB794F4)))),
              GestureDetector(
                onTap: () => onSpeak?.call(msg.text, index),
                child: Icon(
                  isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                  size: 15,
                  color: isSpeaking ? Colors.redAccent : Colors.white.withAlpha(120),
                ),
              ),
            ]),
            const SizedBox(height: 6),
          ],
          Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
        ]),
      ),
    ).animate(delay: (index * 20).ms).fadeIn().slideY(begin: 0.08, end: 0);
  }
}

class _Typing extends StatefulWidget {
  const _Typing();
  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  @override
  void initState() { super.initState(); _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(); }
  @override
  void dispose() { _anim.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomRight: Radius.circular(16)), border: Border.all(color: Colors.white.withAlpha(25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => AnimatedBuilder(
        animation: _anim,
        builder: (_, s) {
          final phase = (_anim.value - i * 0.15).clamp(0.0, 1.0);
          return Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: 8, height: 8,
            decoration: BoxDecoration(color: const Color(0xFFB794F4).withAlpha((phase * 200 + 55).toInt()), shape: BoxShape.circle));
        },
      ))),
    ),
  ).animate().fadeIn();
}

class _Suggestions extends StatelessWidget {
  final List<String> suggestions; final void Function(String) onTap;
  const _Suggestions({required this.suggestions, required this.onTap});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text('Suggested', style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(140), fontWeight: FontWeight.w600))),
    Wrap(spacing: 8, runSpacing: 8, children: suggestions.map((s) => GestureDetector(
      onTap: () => onTap(s.replaceAll(RegExp(r'^\S+ '), '')),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withAlpha(15), borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF7C3AED).withAlpha(80))),
        child: Text(s, style: const TextStyle(fontSize: 12, color: Color(0xFFB794F4), fontWeight: FontWeight.w500))),
    )).toList()),
    const SizedBox(height: 16),
  ]).animate().fadeIn(delay: 300.ms);
}

class _Msg { final String text; final bool isAi; const _Msg({required this.text, required this.isAi}); }
