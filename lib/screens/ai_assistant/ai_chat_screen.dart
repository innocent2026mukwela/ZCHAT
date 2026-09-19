import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ai_service.dart';
import '../../utils/glass.dart';
import '../../widgets/ai_markdown.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/voice_input_button.dart';

class AiChatScreen extends StatefulWidget {
  /// When set, the screen loads and continues this existing conversation.
  /// When null, a new conversation is started on the first message.
  final String? conversationId;

  /// When true, this is the persistent "ZChat AI" assistant opened from the
  /// top of the Chats list: it restores the user's primary conversation on
  /// open and remembers it across sessions.
  final bool pinned;

  const AiChatScreen({super.key, this.conversationId, this.pinned = false});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _tts    = FlutterTts();
  bool _loading    = false;
  bool _hasText    = false;
  bool _loadingHistory = false;
  int? _speakingIdx;
  String? _course; // null = General mode
  String? _conversationId;
  String? _pendingImagePath; // an image attached to the next message
  final List<String> _courses = [];

  bool get _canSend => (_hasText || _pendingImagePath != null) && !_loading;

  final List<_Msg> _messages = [];

  static const _defaultSuggestions = [
    'What can you help me with?',
    'Draft a message for me',
    'Explain a tricky concept simply',
    'Give me some study tips',
    'Help me plan my day',
    'Brainstorm some ideas',
  ];

  List<String> get _activeSuggestions {
    final c = _course;
    if (c == null) return _defaultSuggestions;
    return [
      'Explain a key concept in $c',
      'Give me practice questions for $c',
      'What are common exam topics in $c?',
      'Summarise the main topics in $c',
      'How should I study for $c?',
      'What are the most important topics in $c?',
    ];
  }

  // Conversation history sent to Claude on every turn (role + content pairs).
  // Content is text-only here; an attached image is sent with the live turn but
  // stored as its caption so we never resend the image bytes on later turns.
  final List<Map<String, dynamic>> _history = [];

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    final imagePath = _pendingImagePath;
    if (trimmed.isEmpty && imagePath == null) return;

    // Build this turn's content: an image (base64) + optional caption, else text.
    dynamic outgoingContent = trimmed;
    if (imagePath != null) {
      try {
        final bytes = await File(imagePath).readAsBytes();
        final media = imagePath.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
        outgoingContent = [
          {'type': 'image', 'source': {'type': 'base64', 'media_type': media, 'data': base64Encode(bytes)}},
          if (trimmed.isNotEmpty) {'type': 'text', 'text': trimmed},
        ];
      } catch (_) {
        outgoingContent = trimmed; // fall back to text-only if the file can't be read
      }
    }

    // Add user message to UI
    setState(() {
      _messages.add(_Msg(text: trimmed, isAi: false, imagePath: imagePath));
      _loading = true;
      _hasText = false;
      _pendingImagePath = null;
    });
    _ctrl.clear();

    // Send prior text history + this turn (image included); persist only the
    // caption to history so future turns never resend the image bytes.
    final outgoing = List<Map<String, dynamic>>.from(_history)
      ..add({'role': 'user', 'content': outgoingContent});
    _history.add({'role': 'user', 'content': trimmed.isNotEmpty ? trimmed : '[image]'});
    _scrollDown();

    final buffer = StringBuffer();
    int? aiIdx; // index of the streaming AI message, created on the first token
    try {
      await for (final evt in AiService.chatStream(
        messages: outgoing,
        courseId: _course?.replaceAll(' ', ''),
        conversationId: _conversationId,
      )) {
        if (!mounted) return;
        final delta = evt['delta'] as String?;
        if (delta != null) {
          buffer.write(delta);
          setState(() {
            if (aiIdx == null) {
              _loading = false; // first token → replace the typing dots with text
              _messages.add(_Msg(text: buffer.toString(), isAi: true));
              aiIdx = _messages.length - 1;
            } else {
              _messages[aiIdx!] = _Msg(text: buffer.toString(), isAi: true);
            }
          });
          _scrollDown();
        } else if (evt['done'] == true) {
          _conversationId = evt['conversationId'] as String? ?? _conversationId;
          // Remember this as the primary conversation for the pinned assistant.
          if (widget.pinned && _conversationId != null) _savePrimaryId(_conversationId!);
        } else if (evt['error'] != null) {
          setState(() {
            _loading = false;
            final m = _Msg(text: '${evt['error']}', isAi: true);
            if (aiIdx == null) { _messages.add(m); aiIdx = _messages.length - 1; }
            else { _messages[aiIdx!] = m; }
          });
        }
      }
      final reply = buffer.toString().trim();
      if (reply.isNotEmpty) {
        _history.add({'role': 'assistant', 'content': reply});
      } else if (aiIdx == null && mounted) {
        setState(() => _messages.add(_Msg(text: 'No response received. Please try again.', isAi: true)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final m = _Msg(text: e.toString().replaceFirst('Exception: ', ''), isAi: true);
        if (aiIdx == null) { _messages.add(m); } else { _messages[aiIdx!] = m; }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _scrollDown();
  }

  // Primary-assistant conversation id is remembered per user so the pinned
  // "ZChat AI" chat continues where you left off across sessions.
  String get _primaryKey => 'ai_primary_convo_${FirebaseAuth.instance.currentUser?.uid ?? 'anon'}';

  Future<void> _savePrimaryId(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_primaryKey, id);
    } catch (_) {}
  }

  Future<void> _restorePrimaryConversation() async {
    try {
      final p  = await SharedPreferences.getInstance();
      final id = p.getString(_primaryKey);
      if (id != null && id.isNotEmpty && mounted) _loadConversation(id);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadCourses();
    if (widget.conversationId != null) {
      _loadConversation(widget.conversationId!);
    } else if (widget.pinned) {
      _restorePrimaryConversation();
    }
  }

  Future<void> _loadConversation(String id) async {
    setState(() => _loadingHistory = true);
    try {
      final convo = await AiService.fetchConversation(id);
      final msgs = List<Map<String, dynamic>>.from(convo['messages'] as List? ?? []);
      if (!mounted) return;
      setState(() {
        _conversationId = convo['conversationId'] as String? ?? id;
        _messages.clear();
        _history.clear();
        for (final m in msgs) {
          final role = m['role'] as String;
          final content = m['content'] as String;
          _history.add({'role': role, 'content': content});
          _messages.add(_Msg(text: content, isAi: role == 'assistant'));
        }
        _loadingHistory = false;
      });
      _scrollDown();
    } catch (e) {
      if (mounted) {
        setState(() => _loadingHistory = false);
        _messages.add(_Msg(text: 'Could not load conversation history.', isAi: true));
      }
    }
  }

  Future<void> _loadCourses() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
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
    } catch (_) {
      // Course list is non-critical; AI still works in General mode
    }
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    // 0.5 is half-speed on web/Android ("slow motion"); tune per platform.
    await _tts.setSpeechRate(kIsWeb ? 1.0 : (Platform.isIOS ? 0.5 : 0.9));
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() { if (mounted) setState(() => _speakingIdx = null); });
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

  void _onVoiceResult(String text) {
    setState(() {
      _ctrl.text = text;
      _hasText = text.trim().isNotEmpty;
    });
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
      if (picked != null && mounted) setState(() => _pendingImagePath = picked.path);
    } catch (_) {/* permission denied / cancelled */}
  }

  void _showRecentConversations() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1A4A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Column(children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Recent conversations', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
          ),
          Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
            future: AiService.fetchConversations(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFFB794F4)));
              }
              final convos = snap.data ?? [];
              if (convos.isEmpty) {
                return Center(child: Text('No recent conversations',
                  style: TextStyle(color: Colors.white.withAlpha(140))));
              }
              return ListView.builder(
                controller: scrollCtrl,
                itemCount: convos.length,
                itemBuilder: (c, i) {
                  final convo = convos[i];
                  final title = (convo['title'] as String?)?.trim();
                  final preview = (convo['last_question'] as String?)?.trim();
                  final label = (title != null && title.isNotEmpty)
                      ? title : (preview != null && preview.isNotEmpty ? preview : 'Conversation');
                  final answer = (convo['last_answer'] as String?)?.trim() ?? '';
                  return ListTile(
                    leading: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFB794F4)),
                    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: answer.isNotEmpty
                        ? Text(answer, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12))
                        : null,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      final id = convo['id'] as String?;
                      if (id != null) _loadConversation(id);
                    },
                  );
                },
              );
            },
          )),
        ]),
      ),
    );
  }

  void _scrollDown() => Future.delayed(const Duration(milliseconds: 100), () {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  });

  @override
  void dispose() {
    _tts.stop();
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
                        onPressed: () => context.canPop() ? context.pop() : context.go('/ai'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Row(children: [
                        const ZSymbol(size: 36),
                        const SizedBox(width: 11),
                        Expanded(child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const ZWordmark(text: 'ZCHAT AI', fontSize: 17),
                            const SizedBox(height: 3),
                            Row(children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              Text('Online', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 11, fontWeight: FontWeight.w500)),
                            ]),
                          ],
                        )),
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
                          PopupMenuItem(value: 'recent', child: Text('Recent conversations', style: TextStyle(color: Colors.white.withAlpha(220)))),
                          PopupMenuItem(value: 'new', child: Text('New chat', style: TextStyle(color: Colors.white.withAlpha(220)))),
                          PopupMenuItem(value: 'quiz', child: Text('Generate Quiz', style: TextStyle(color: Colors.white.withAlpha(220)))),
                          PopupMenuItem(value: 'summary', child: Text('View Summaries', style: TextStyle(color: Colors.white.withAlpha(220)))),
                        ],
                        onSelected: (v) {
                          if (v == 'recent') _showRecentConversations();
                          if (v == 'new') setState(() { _messages.clear(); _history.clear(); _conversationId = null; });
                          if (v == 'quiz') context.push('/ai/quiz/${_course ?? 'General'}');
                          if (v == 'summary') context.push('/ai/summaries/${_course ?? 'General'}');
                        },
                      ),
                    ]),
                  )),
                ),
              ),
            ),
            Expanded(
              child: _loadingHistory
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFB794F4)))
                  : (_messages.isEmpty && !_loading)
                      ? ListView(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 28, 14, 12),
                          children: [_Suggestions(suggestions: _activeSuggestions, onTap: _send)],
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: _messages.length + (_loading ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (_loading && i == _messages.length) return const _Typing();
                            return _Bubble(msg: _messages[i], index: i, onSpeak: _speak, speakingIdx: _speakingIdx);
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
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_pendingImagePath != null) _pendingImagePreview(),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withAlpha(35))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const SizedBox(width: 4),
                      VoiceInputButton(onResult: _onVoiceResult),
                      IconButton(
                        icon: Icon(Icons.image_outlined, color: Colors.white.withAlpha(160), size: 22),
                        onPressed: _pickImage,
                        tooltip: 'Attach a photo',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
                          onSubmitted: (_) { if (_canSend) _send(_ctrl.text); },
                        ),
                      ),
                    ]),
                  )),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _canSend ? () => _send(_ctrl.text) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _canSend ? const Color(0xFF7C3AED) : Colors.white.withAlpha(20),
                  shape: BoxShape.circle,
                  boxShadow: _canSend ? [BoxShadow(color: const Color(0xFF7C3AED).withAlpha(100), blurRadius: 12)] : [],
                ),
                child: Icon(Icons.send_rounded, color: _canSend ? Colors.white : Colors.white.withAlpha(120), size: 20),
              ),
            ),
          ]),
        ])),
      ),
    ),
  );

  Widget _pendingImagePreview() => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
    child: Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(File(_pendingImagePath!), width: 52, height: 52, fit: BoxFit.cover),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text('Photo attached — add a question or send',
        style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13))),
      IconButton(
        icon: Icon(Icons.close_rounded, color: Colors.white.withAlpha(160), size: 20),
        onPressed: () => setState(() => _pendingImagePath = null),
      ),
    ]),
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
          if (_courses.isEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () { Navigator.pop(context); context.push('/planner'); },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(20), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(40))),
                child: Row(children: [
                  const Icon(Icons.calendar_today_rounded, color: Color(0xFF4F8AFF), size: 16),
                  const SizedBox(width: 10),
                  Expanded(child: Text('No courses found. Tap to set up your timetable.', style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12, height: 1.4))),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 16),
                ]),
              ),
            ),
          ],
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
              const Expanded(child: Text('ZChat AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFB794F4)))),
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
          if (!msg.isAi && msg.imagePath != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(File(msg.imagePath!), fit: BoxFit.cover),
              ),
            ),
            if (msg.text.isNotEmpty) const SizedBox(height: 8),
          ],
          if (msg.isAi)
            AiMarkdown(msg.text)
          else if (msg.text.isNotEmpty)
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
      onTap: () => onTap(s),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withAlpha(15), borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF7C3AED).withAlpha(80))),
        child: Text(s, style: const TextStyle(fontSize: 12, color: Color(0xFFB794F4), fontWeight: FontWeight.w500))),
    )).toList()),
    const SizedBox(height: 16),
  ]).animate().fadeIn(delay: 300.ms);
}

class _Msg {
  final String text;
  final bool isAi;
  final String? imagePath; // local path of an attached photo (user messages)
  const _Msg({required this.text, required this.isAi, this.imagePath});
}
