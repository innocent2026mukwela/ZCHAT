import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import '../../services/call_service.dart';
import '../../services/zego_service.dart';
import '../../utils/glass.dart';

const _kPalette = [
  Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFF2E7D32),
  Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
];
Color _col(String n) => _kPalette[n.codeUnits.fold(0, (a, c) => a + c) % _kPalette.length];
String _initials(String n) {
  final p = n.trim().split(' ');
  if (p.length >= 2) return '${p[0][0]}${p[1][0]}'.toUpperCase();
  return n.substring(0, n.length.clamp(0, 2)).toUpperCase();
}

// ── Incoming call screen ──────────────────────────────────────────────────────

class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerName;
  final bool   isVideo;
  final String roomId;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.isVideo,
    required this.roomId,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {

  late final AnimationController _pulse;
  late final AnimationController _ring;
  StreamSubscription<dynamic>? _callSub;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
        ..repeat(reverse: true);
    _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
        ..repeat(reverse: true);

    // Watch for caller cancelling before we answer
    _callSub = CallService.incomingCallStream().listen((data) {
      if (data == null && mounted && !_handled) {
        _handled = true;
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _ring.dispose();
    _callSub?.cancel();
    super.dispose();
  }

  Future<void> _answer() async {
    if (_handled) return;
    _handled = true;
    _callSub?.cancel();

    final perms = widget.isVideo
        ? [Permission.microphone, Permission.camera]
        : [Permission.microphone];
    final results = await perms.request();
    final denied = results.entries.where((e) => !e.value.isGranted).map((e) => e.key).toList();

    if (denied.isNotEmpty) {
      _handled = false;
      if (!mounted) return;
      final names = denied.map((p) => p == Permission.camera ? 'Camera' : 'Microphone').join(' & ');
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0E1829),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Permission required', style: TextStyle(color: Colors.white)),
          content: Text('$names access is needed for this call. Please allow it in Settings.',
              style: TextStyle(color: Colors.white.withAlpha(160))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            TextButton(onPressed: () { Navigator.pop(context); openAppSettings(); }, child: const Text('Open Settings', style: TextStyle(color: Color(0xFF4F8AFF)))),
          ],
        ),
      );
      return;
    }

    await CallService.answerCall(widget.callId);

    if (!mounted) return;
    final me = FirebaseAuth.instance.currentUser!;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ZegoUIKitPrebuiltCall(
        appID:    kZegoAppId,
        appSign:  kZegoAppSign,
        userID:   me.uid,
        userName: me.displayName ?? me.uid,
        callID:   widget.roomId,
        config:   widget.isVideo
            ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
            : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall(),
      ),
    ));
  }

  Future<void> _decline() async {
    if (_handled) return;
    _handled = true;
    _callSub?.cancel();
    await CallService.declineCall(widget.callId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final avatarColor = _col(widget.callerName);
    final initials    = _initials(widget.callerName);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Center(child: _PulseRings(controller: _pulse, color: avatarColor)),
          SafeArea(
            child: Column(children: [
              const SizedBox(height: 60),

              // Incoming call label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withAlpha(30)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedBuilder(
                    animation: _ring,
                    builder: (_, _) => Icon(
                      widget.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: Color.lerp(const Color(0xFF86EFAC), Colors.white, _ring.value)!,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
                    style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13),
                  ),
                ]),
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 48),

              // Avatar with pulsing glow
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) => Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                      color: avatarColor.withAlpha((60 + 60 * _pulse.value).round()),
                      blurRadius: 24 + 16 * _pulse.value,
                      spreadRadius: 4 + 4 * _pulse.value,
                    )],
                  ),
                  child: child,
                ),
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: avatarColor,
                  child: Text(initials,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 32)),
                ),
              ).animate().scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), duration: 400.ms),

              const SizedBox(height: 24),

              Text(
                widget.callerName,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 8),

              Text(
                widget.isVideo ? 'wants to video call you' : 'is calling you',
                style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 15),
              ).animate().fadeIn(delay: 300.ms),

              const Spacer(),

              // Decline / Answer buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Decline
                    Column(children: [
                      GestureDetector(
                        onTap: _decline,
                        child: Container(
                          width: 72, height: 72,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Color(0x66EF4444), blurRadius: 24, spreadRadius: 4)],
                          ),
                          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 34),
                        ),
                      ).animate(delay: 400.ms).scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1)),
                      const SizedBox(height: 10),
                      Text('Decline', style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13)),
                    ]),

                    // Answer
                    Column(children: [
                      GestureDetector(
                        onTap: _answer,
                        child: Container(
                          width: 72, height: 72,
                          decoration: const BoxDecoration(
                            color: Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Color(0x6622C55E), blurRadius: 24, spreadRadius: 4)],
                          ),
                          child: Icon(
                            widget.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                            color: Colors.white, size: 34,
                          ),
                        ),
                      ).animate(delay: 450.ms).scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1)),
                      const SizedBox(height: 10),
                      Text('Answer', style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13)),
                    ]),
                  ],
                ),
              ),

              const SizedBox(height: 64),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Pulsing rings ─────────────────────────────────────────────────────────────

class _PulseRings extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  const _PulseRings({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final v = controller.value;
        return Stack(alignment: Alignment.center, children: [
          _Ring(radius: 80 + 40 * v,  opacity: 0.15 * (1 - v), color: color),
          _Ring(radius: 80 + 70 * v,  opacity: 0.10 * (1 - v), color: color),
          _Ring(radius: 80 + 110 * v, opacity: 0.06 * (1 - v), color: color),
        ]);
      },
    );
  }
}

class _Ring extends StatelessWidget {
  final double radius, opacity;
  final Color  color;
  const _Ring({required this.radius, required this.opacity, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: radius * 2, height: radius * 2,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color.withAlpha((opacity * 255).round()), width: 2),
    ),
  );
}
