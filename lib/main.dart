import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'services/planner_service.dart';
import 'services/zego_service.dart';
import 'utils/theme.dart';
import 'router.dart';

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

class UnZAzChatApp extends StatelessWidget {
  const UnZAzChatApp({super.key});

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
