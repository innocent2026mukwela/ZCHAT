import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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

// ── Outgoing call screen ──────────────────────────────────────────────────────

class OutgoingCallScreen extends StatefulWidget {
  final String calleeUid;
  final String calleeName;
  final bool   isVideo;

  const OutgoingCallScreen({
    super.key,
    required this.calleeUid,
    required this.calleeName,
    required this.isVideo,
  });

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen>
    with TickerProviderStateMixin {

  // ── State ──────────────────────────────────────────────────────────────────
  String  _status   = 'Connecting…';   // shown under the name
  bool    _ringing  = false;
  bool    _launched = false;           // Zego already pushed
  String? _callDocId;
  String? _roomId;

  late final AnimationController _pulse;
  late final AnimationController _ring;
  Timer? _ringingTimer;
  Timer? _noAnswerTimer;
  StreamSubscription<DocumentSnapshot>? _callSub;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
        ..repeat(reverse: true);
    _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
        ..repeat(reverse: true);
    _initiateCall();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _ring.dispose();
    _ringingTimer?.cancel();
    _noAnswerTimer?.cancel();
    _callSub?.cancel();
    super.dispose();
  }

  // ── Call flow ──────────────────────────────────────────────────────────────

  Future<void> _initiateCall() async {
    try {
      final docId = await CallService.initiateCall(
        calleeUid:  widget.calleeUid,
        calleeName: widget.calleeName,
        type: widget.isVideo ? CallType.video : CallType.voice,
      );

      // Fetch the roomId from the newly created call doc
      final snap = await FirebaseFirestore.instance.collection('calls').doc(docId).get();
      final room = snap.data()?['roomId'] as String? ?? docId;

      if (!mounted) return;
      setState(() { _callDocId = docId; _roomId = room; });

      // After 2 s switch to "Ringing…"
      _ringingTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() { _status = 'Ringing…'; _ringing = true; });
      });

      // Auto-cancel after 40 s (no answer)
      _noAnswerTimer = Timer(const Duration(seconds: 40), _cancelCall);

      // Watch for callee answering (status → 'answered')
      _callSub = FirebaseFirestore.instance
          .collection('calls').doc(docId)
          .snapshots()
          .listen((s) {
        if (!s.exists || !mounted) return;
        final status = s.data()?['status'] as String?;
        if (status == 'answered' && !_launched) _launchZego();
        if (status == 'declined') _handleDeclined();
      });

    } catch (e) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _launchZego() async {
    if (_launched || _roomId == null) return;
    _launched = true;

    final perms = widget.isVideo
        ? [Permission.microphone, Permission.camera]
        : [Permission.microphone];
    final results = await perms.request();
    final denied = results.entries.where((e) => !e.value.isGranted).map((e) => e.key).toList();

    if (denied.isNotEmpty) {
      _launched = false;
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
      await _cancelCall();
      return;
    }

    final me = FirebaseAuth.instance.currentUser!;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ZegoUIKitPrebuiltCall(
        appID:    kZegoAppId,
        appSign:  kZegoAppSign,
        userID:   me.uid,
        userName: me.displayName ?? me.uid,
        callID:   _roomId!,
        config:   widget.isVideo
            ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
            : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall(),
      ),
    ));
  }

  Future<void> _cancelCall() async {
    _ringingTimer?.cancel();
    _noAnswerTimer?.cancel();
    _callSub?.cancel();
    if (_callDocId != null) {
      await FirebaseFirestore.instance
          .collection('calls').doc(_callDocId!)
          .update({'status': 'missed'}).catchError((_) {});
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _handleDeclined() {
    _callSub?.cancel();
    _ringingTimer?.cancel();
    _noAnswerTimer?.cancel();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E1829),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Call declined', style: TextStyle(color: Colors.white)),
        content: Text('${widget.calleeName} declined the call.',
            style: TextStyle(color: Colors.white.withAlpha(160))),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); Navigator.pop(context); },
            child: const Text('OK', style: TextStyle(color: Color(0xFF4F8AFF))),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final avatarColor = _col(widget.calleeName);
    final initials    = _initials(widget.calleeName);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          // Pulsing rings behind avatar
          Center(child: _PulseRings(controller: _pulse, color: avatarColor)),
          SafeArea(
            child: Column(children: [
              const SizedBox(height: 80),

              // Call type label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withAlpha(30)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    widget.isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                    color: Colors.white.withAlpha(180), size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isVideo ? 'Video Call' : 'Voice Call',
                    style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13),
                  ),
                ]),
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 48),

              // Avatar
              CircleAvatar(
                radius: 56,
                backgroundColor: avatarColor,
                child: Text(initials,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 32)),
              ).animate().scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), duration: 400.ms),

              const SizedBox(height: 24),

              // Name
              Text(
                widget.calleeName,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 12),

              // Status with animated dots when ringing
              _StatusRow(label: _status, ringing: _ringing, ringAnim: _ring)
                  .animate().fadeIn(delay: 300.ms),

              const Spacer(),

              // End call button
              GestureDetector(
                onTap: _cancelCall,
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

// ── Animated status row ───────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  final String label;
  final bool   ringing;
  final AnimationController ringAnim;
  const _StatusRow({required this.label, required this.ringing, required this.ringAnim});

  @override
  Widget build(BuildContext context) {
    if (!ringing) {
      return Text(label,
          style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 16));
    }
    return AnimatedBuilder(
      animation: ringAnim,
      builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.notifications_active_rounded,
            color: Color.lerp(const Color(0xFF86EFAC), Colors.white, ringAnim.value)!,
            size: 18),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
              color: Color.lerp(const Color(0xFF86EFAC), Colors.white, ringAnim.value)!,
              fontSize: 16, fontWeight: FontWeight.w600,
            )),
      ]),
    );
  }
}
