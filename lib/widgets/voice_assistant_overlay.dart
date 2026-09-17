import 'dart:ui';
import 'package:flutter/material.dart';
import '../router.dart';
import '../services/voice_assistant_service.dart';

/// The floating "Hey Zee" panel. Mounted once at the app root (above the router)
/// so it can appear over any screen. Renders nothing while the assistant is idle.
class VoiceAssistantOverlay extends StatefulWidget {
  const VoiceAssistantOverlay({super.key});
  @override
  State<VoiceAssistantOverlay> createState() => _VoiceAssistantOverlayState();
}

class _VoiceAssistantOverlayState extends State<VoiceAssistantOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  final _svc = VoiceAssistantService.instance;

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _svc,
      builder: (context, _) {
        if (!_svc.isBusy) return const SizedBox.shrink();
        return Material(
          color: Colors.black.withAlpha(140),
          child: SafeArea(
            child: Stack(children: [
              // Tap the scrim to dismiss
              Positioned.fill(child: GestureDetector(onTap: _svc.cancel, behavior: HitTestBehavior.opaque)),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _panel(),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _panel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [const Color(0xFF7C3AED).withAlpha(60), const Color(0xFF0A1330).withAlpha(230)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withAlpha(40)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _orb(),
              const SizedBox(width: 12),
              Expanded(child: Text(_statusLabel(),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
              IconButton(
                icon: Icon(Icons.close_rounded, color: Colors.white.withAlpha(180)),
                onPressed: _svc.cancel,
              ),
            ]),
            if (_svc.transcript.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('“${_svc.transcript}”',
                style: TextStyle(color: Colors.white.withAlpha(210), fontSize: 15, fontWeight: FontWeight.w600, height: 1.3)),
            ],
            if (_svc.state == VoiceState.thinking) ...[
              const SizedBox(height: 14),
              const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFFB794F4))),
            ],
            if (_svc.answer.isNotEmpty && _svc.state != VoiceState.thinking) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Text(_svc.answer,
                    style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.45)),
                ),
              ),
            ],
            if (_svc.state == VoiceState.result) ...[
              const SizedBox(height: 16),
              Row(children: [
                if (_svc.canContinueInChat)
                  Expanded(child: _btn('Continue in chat', Icons.forum_rounded, () {
                    _svc.cancel();
                    appRouter.push('/ai/assistant');
                  })),
                if (_svc.canContinueInChat) const SizedBox(width: 10),
                Expanded(child: _btn('Ask again', Icons.mic_rounded, () => _svc.activate(), filled: false)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _orb() {
    final listening = _svc.state == VoiceState.listening;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        return Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F8AFF)]),
            boxShadow: [BoxShadow(
              color: const Color(0xFF7C3AED).withAlpha((90 + (listening ? t * 120 : 40)).toInt()),
              blurRadius: 10 + (listening ? t * 14 : 4), spreadRadius: listening ? t * 3 : 1)],
          ),
          child: Icon(listening ? Icons.mic_rounded : Icons.auto_awesome_rounded, color: Colors.white, size: 20),
        );
      },
    );
  }

  String _statusLabel() => switch (_svc.state) {
    VoiceState.listening => 'Listening…',
    VoiceState.thinking  => 'Thinking…',
    VoiceState.speaking  => 'ZChat AI',
    VoiceState.result    => 'ZChat AI',
    VoiceState.idle      => '',
  };

  Widget _btn(String label, IconData icon, VoidCallback onTap, {bool filled = true}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: filled ? const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]) : null,
          color: filled ? null : Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: Colors.white.withAlpha(45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
