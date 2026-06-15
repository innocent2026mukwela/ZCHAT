import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Reusable microphone button that wraps speech-to-text start/stop and
/// streams recognized words back via [onResult] as the user speaks.
class VoiceInputButton extends StatefulWidget {
  final void Function(String text) onResult;
  final double size;

  const VoiceInputButton({super.key, required this.onResult, this.size = 20});

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final _stt = SpeechToText();
  bool _listening = false;

  Future<void> _toggle() async {
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
        widget.onResult(result.recognizedWords);
        if (result.finalResult && mounted) {
          setState(() => _listening = false);
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _listening ? Icons.mic_off_rounded : Icons.mic_rounded,
        color: _listening ? Colors.redAccent : const Color(0xFFB794F4),
        size: widget.size,
      ),
      onPressed: _toggle,
    );
  }
}
