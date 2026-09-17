import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../router.dart';
import 'ai_service.dart';
import 'chat_service.dart';
import 'voice_intents.dart';

enum VoiceState { idle, listening, thinking, speaking, result }

/// The "Hey Zee" voice assistant. A singleton state machine that owns the mic
/// (speech-to-text) and voice (text-to-speech) so only one thing uses audio at a
/// time. Activated manually today (a "Talk to Zee" button); the Porcupine wake
/// word will call [activate] once the keyword + AccessKey are supplied.
class VoiceAssistantService extends ChangeNotifier {
  VoiceAssistantService._();
  static final VoiceAssistantService instance = VoiceAssistantService._();

  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _ttsReady = false;
  bool _paused = false; // set true during calls / voice-note recording

  VoiceState state = VoiceState.idle;
  String transcript = ''; // what the user said
  String answer = '';     // the assistant's reply (streamed / spoken)
  bool canContinueInChat = false; // show "Continue in chat" on an assist answer

  bool get isBusy => state != VoiceState.idle;

  Future<void> init() async {
    if (_ttsReady) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(_onSpeechDone);
      _ttsReady = true;
    } catch (_) {/* TTS optional */}
  }

  /// Called during Zego calls / voice-note recording so the assistant releases
  /// the mic; wake-word listening (when added) should also honour this.
  void pause() { _paused = true; if (isBusy) cancel(); }
  void resume() { _paused = false; }

  // ── Activation ──────────────────────────────────────────────────────────
  Future<void> activate() async {
    if (_paused || isBusy) return;
    await init();
    transcript = '';
    answer = '';
    canContinueInChat = false;

    final available = await _stt.initialize().timeout(
      const Duration(seconds: 6), onTimeout: () => false);
    if (!available) {
      _fail('Microphone unavailable — check permissions.');
      return;
    }
    _set(VoiceState.listening);
    _stt.listen(
      onResult: (r) {
        transcript = r.recognizedWords;
        notifyListeners();
        if (r.finalResult) _process(transcript);
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
      ),
    );
  }

  Future<void> cancel() async {
    try { await _stt.stop(); } catch (_) {}
    try { await _tts.stop(); } catch (_) {}
    _set(VoiceState.idle);
  }

  // ── Command handling ────────────────────────────────────────────────────
  Future<void> _process(String prompt) async {
    try { await _stt.stop(); } catch (_) {}
    final p = prompt.trim();
    if (p.isEmpty) { _set(VoiceState.idle); return; }

    final intent = VoiceIntents.parse(p);
    switch (intent.type) {
      case VoiceIntentType.navigate:
        _navigate(intent);
      case VoiceIntentType.readMessages:
        await _readMessages(intent);
      case VoiceIntentType.assist:
        await _assist(p);
    }
  }

  void _navigate(VoiceIntent intent) {
    try { appRouter.go(intent.route!); } catch (_) {}
    answer = 'Opening ${intent.routeLabel}.';
    _set(VoiceState.speaking);
    _speak(answer);
    // Navigation dismisses itself shortly after the confirmation.
    Timer(const Duration(milliseconds: 1400), () { if (state == VoiceState.speaking) _set(VoiceState.idle); });
  }

  Future<void> _readMessages(VoiceIntent intent) async {
    _set(VoiceState.thinking);
    try {
      final chats = await ChatService.chatsStream().first
          .timeout(const Duration(seconds: 8), onTimeout: () => <Map<String, dynamic>>[]);
      answer = _summariseChats(chats, intent.nameFilter);
    } catch (_) {
      answer = 'I could not read your messages right now.';
    }
    canContinueInChat = false;
    _set(VoiceState.result);
    _speak(answer);
  }

  String _summariseChats(List<Map<String, dynamic>> chats, String? nameFilter) {
    if (nameFilter != null) {
      Map<String, dynamic>? match;
      for (final c in chats) {
        if (ChatService.getChatDisplayName(c).toLowerCase().contains(nameFilter.toLowerCase())) {
          match = c; break;
        }
      }
      if (match == null) return "I couldn't find a chat with $nameFilter.";
      final dn = ChatService.getChatDisplayName(match);
      final last = (match['lastMessage'] as String? ?? '').trim();
      return last.isEmpty
          ? 'There are no messages in your chat with $dn yet.'
          : 'Your latest with $dn: $last';
    }
    final unread = chats.where((c) => ChatService.getUnreadCount(c) > 0).toList();
    if (unread.isEmpty) return 'You have no unread messages.';
    final total = unread.fold<int>(0, (s, c) => s + ChatService.getUnreadCount(c));
    final parts = unread.take(5)
        .map((c) => '${ChatService.getUnreadCount(c)} from ${ChatService.getChatDisplayName(c)}')
        .join(', ');
    return 'You have $total unread ${total == 1 ? 'message' : 'messages'}: $parts.';
  }

  Future<void> _assist(String prompt) async {
    if (FirebaseAuth.instance.currentUser == null) {
      _fail('Please sign in to use ZChat AI.');
      return;
    }
    _set(VoiceState.thinking);
    final convId = await _primaryConversationId();
    final buffer = StringBuffer();
    try {
      await for (final evt in AiService.chatStream(
        messages: [{'role': 'user', 'content': prompt}],
        conversationId: convId,
      )) {
        final delta = evt['delta'] as String?;
        if (delta != null) {
          buffer.write(delta);
          answer = buffer.toString();
          if (state != VoiceState.speaking) {
            _set(VoiceState.speaking);
          } else {
            notifyListeners();
          }
        } else if (evt['done'] == true) {
          final id = evt['conversationId'] as String?;
          if (id != null) await _savePrimaryConversationId(id);
        } else if (evt['error'] != null) {
          answer = '${evt['error']}';
        }
      }
    } catch (e) {
      answer = e.toString().replaceFirst('Exception: ', '');
    }
    if (answer.trim().isEmpty) answer = 'Sorry, I could not answer that.';
    canContinueInChat = true;
    _set(VoiceState.result);
    _speak(answer);
  }

  // ── Primary conversation (shared with the pinned ZChat AI chat) ──────────
  String get _primaryKey => 'ai_primary_convo_${FirebaseAuth.instance.currentUser?.uid ?? 'anon'}';
  Future<String?> _primaryConversationId() async {
    try { return (await SharedPreferences.getInstance()).getString(_primaryKey); } catch (_) { return null; }
  }
  Future<void> _savePrimaryConversationId(String id) async {
    try { await (await SharedPreferences.getInstance()).setString(_primaryKey, id); } catch (_) {}
  }

  // ── TTS ─────────────────────────────────────────────────────────────────
  Future<void> _speak(String text) async {
    if (!_ttsReady || text.trim().isEmpty) return;
    final clean = text.replaceAll(RegExp(r'[*_`#>]'), ''); // strip markdown for speech
    try { await _tts.stop(); await _tts.speak(clean); } catch (_) {}
  }

  void _onSpeechDone() {
    // Navigation already schedules its own dismiss; leave result/idle as-is.
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  void _fail(String message) {
    answer = message;
    canContinueInChat = false;
    _set(VoiceState.result);
    _speak(message);
  }

  void _set(VoiceState s) { state = s; notifyListeners(); }
}
