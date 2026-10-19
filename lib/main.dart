import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'services/call_service.dart';
import 'services/fcm_service.dart';
import 'services/media_storage_service.dart';
import 'services/planner_service.dart';
import 'services/voice_assistant_service.dart';
import 'services/zego_service.dart';
import 'config.dart';
import 'utils/theme.dart';
import 'router.dart';
import 'screens/calls/incoming_call_screen.dart';
import 'widgets/voice_assistant_overlay.dart';

Future<void> _safeInit(
  String name,
  Future<void> Function() fn, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    await fn().timeout(timeout);
  } catch (e, st) {
    // Never leave Chrome on a blank frame because an optional plugin hung/threw.
    debugPrint('[main] $name init skipped: $e\n$st');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validateAtStartup();

  await _safeInit(
    'Firebase',
    () => Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    timeout: const Duration(seconds: 15),
  );

  // Firestore web often reports "client is offline" when WebChannel/HTTP2 is
  // blocked (campus Wi‑Fi, antivirus, adblock). Configure transport + wake the
  // client before any screen touches Firestore (OTP verify, splash, etc.).
  if (Firebase.apps.isNotEmpty) {
    try {
      if (kIsWeb) {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          webExperimentalForceLongPolling: true,
        );
      }
      await FirebaseFirestore.instance.enableNetwork();
    } catch (e, st) {
      debugPrint('[main] Firestore network setup skipped: $e\n$st');
    }
  }

  await _safeInit('MediaStorage', MediaStorageService.init);

  // FCM + local notifications block (or throw) on web: Notification.requestPermission
  // can hang until the user answers a browser prompt, and getToken needs a VAPID key
  // + firebase-messaging-sw.js that this app does not ship. Skip on web so runApp
  // always reaches the first frame.
  if (!kIsWeb) {
    await _safeInit('FCM', FcmService.init);
    await _safeInit('LocalNotifications', initLocalNotifications);
  } else {
    debugPrint('[main] Skipping FCM + local notifications on web');
  }

  await _safeInit('VoiceAssistant', () => VoiceAssistantService.instance.init());

  // Zego / callkit-style plugins are mobile-first; never block web startup.
  if (!kIsWeb && FirebaseAuth.instance.currentUser != null) {
    await _safeInit('Zego', ZegoService.init);
  }

  GoogleFonts.config.allowRuntimeFetching = false;
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  runApp(const UnZAzChatApp());
}

class UnZAzChatApp extends StatefulWidget {
  const UnZAzChatApp({super.key});

  @override
  State<UnZAzChatApp> createState() => _UnZAzChatAppState();
}

class _UnZAzChatAppState extends State<UnZAzChatApp> {
  StreamSubscription<Map<String, dynamic>?>? _callSub;
  StreamSubscription<User?>? _authSub;
  bool _callScreenShowing = false;

  @override
  void initState() {
    super.initState();
    // Start/stop call listener as auth state changes
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _callSub?.cancel();
        _callSub = CallService.incomingCallStream().listen(_onIncomingCall);
      } else {
        _callSub?.cancel();
        _callSub = null;
        _callScreenShowing = false;
      }
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _onIncomingCall(Map<String, dynamic>? data) async {
    if (data == null) {
      _callScreenShowing = false;
      return;
    }
    if (_callScreenShowing) return;

    // Honour profile → Notifications → Calls before presenting the ring UI.
    final me = FirebaseAuth.instance.currentUser;
    if (me != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(me.uid).get();
        if ((doc.data()?['notifCalls'] as bool?) == false) return;
      } catch (_) {}
    }

    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    _callScreenShowing = true;
    nav.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => IncomingCallScreen(
        callId:     data['id'] as String,
        callerName: data['callerName'] as String? ?? 'Unknown',
        isVideo:    data['type'] == 'video',
        roomId:     data['roomId'] as String? ?? data['id'] as String,
      ),
    )).then((_) => _callScreenShowing = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ZCHAT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
      scaffoldMessengerKey: FcmService.messengerKey,
      // Mount the "Hey Zee" overlay above every screen (renders nothing when idle).
      builder: (context, child) => Stack(
        children: [child ?? const SizedBox.shrink(), const VoiceAssistantOverlay()],
      ),
    );
  }
}
