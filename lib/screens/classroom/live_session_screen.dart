import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import '../../config.dart';
import '../../services/zego_service.dart';
import '../../utils/glass.dart';

/// A real multi-party classroom, backed by the same Zego infrastructure as the
/// 1-to-1/group calls. Everyone who opens the same [roomId] joins one video
/// room, so a lecturer's session and its students share `callID = roomId`.
class LiveSessionScreen extends StatefulWidget {
  final String courseId;
  final String roomId;
  const LiveSessionScreen({super.key, required this.courseId, required this.roomId});
  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  bool _ready = false;
  String? _error;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (kIsWeb) {
      setState(() => _error = 'Live sessions run on the mobile app (video calling is not supported on web).');
      return;
    }

    if (!AppConfig.zegoConfigured) {
      setState(() => _error =
          'Live sessions are not configured. Set ZEGO_APP_ID and ZEGO_APP_SIGN via --dart-define.');
      return;
    }

    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      setState(() => _error = 'You must be signed in to join a live session.');
      return;
    }

    // Camera + mic are required for a classroom.
    final results = await [Permission.microphone, Permission.camera].request();
    final denied = results.entries.where((e) => !e.value.isGranted).map((e) => e.key).toList();
    if (denied.isNotEmpty) {
      if (!mounted) return;
      final names = denied.map((p) => p == Permission.camera ? 'Camera' : 'Microphone').join(' & ');
      setState(() => _error = '$names access is needed to join. Enable it in Settings, then reopen the session.');
      return;
    }

    // Custom-token sign-in leaves displayName null, so resolve the real name.
    var name = me.displayName ?? '';
    if (name.isEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(me.uid).get();
        name = (doc.data()?['fullName'] as String?)?.trim() ?? '';
      } catch (_) {}
    }
    if (name.isEmpty) name = 'Student';

    if (mounted) setState(() { _userName = name; _ready = true; });
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (_ready && me != null) {
      return ZegoUIKitPrebuiltCall(
        appID:    kZegoAppId,
        appSign:  kZegoAppSign,
        userID:   me.uid,
        userName: _userName,
        callID:   widget.roomId,
        config:   ZegoUIKitPrebuiltCallConfig.groupVideoCall()
          ..topMenuBar.isVisible = true
          ..topMenuBar.title = widget.courseId,
      );
    }

    // Loading / permission / error state
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.courseId, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const Text('Live Session', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  ])),
                ]),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: _error != null ? _errorView() : _loadingView(),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _loadingView() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(color: Color(0xFF4F8AFF)),
      const SizedBox(height: 20),
      Text('Joining the session…',
          style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 15)),
    ],
  );

  Widget _errorView() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.videocam_off_rounded, size: 56, color: Colors.white.withAlpha(70)),
      const SizedBox(height: 16),
      Text(_error!, textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 14, height: 1.5)),
      const SizedBox(height: 20),
      if (!kIsWeb)
        Wrap(spacing: 10, children: [
          TextButton(
            onPressed: () { setState(() { _error = null; }); _prepare(); },
            child: const Text('Retry', style: TextStyle(color: Color(0xFF4F8AFF))),
          ),
          TextButton(
            onPressed: openAppSettings,
            child: const Text('Open Settings', style: TextStyle(color: Color(0xFF4F8AFF))),
          ),
        ]),
    ],
  );
}
