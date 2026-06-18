import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'services/call_service.dart';
import 'services/fcm_service.dart';
import 'services/planner_service.dart';
import 'services/zego_service.dart';
import 'utils/theme.dart';
import 'router.dart';
import 'screens/calls/incoming_call_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FcmService.init();
  await initLocalNotifications();

  // Init Zego if user is already signed in (app relaunch)
  if (FirebaseAuth.instance.currentUser != null) {
    await ZegoService.init();
  }

  GoogleFonts.config.allowRuntimeFetching = false;
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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

  void _onIncomingCall(Map<String, dynamic>? data) {
    if (data == null) {
      _callScreenShowing = false;
      return;
    }
    if (_callScreenShowing) return;

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
    );
  }
}
