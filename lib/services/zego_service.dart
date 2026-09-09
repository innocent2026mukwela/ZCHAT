import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../config.dart';

// Sourced from AppConfig so real production creds can be supplied via
// --dart-define=ZEGO_APP_ID / ZEGO_APP_SIGN without editing source.
const int kZegoAppId      = AppConfig.zegoAppId;
const String kZegoAppSign = AppConfig.zegoAppSign;

class ZegoService {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Direct call UI only — no push-based invitation service
  }

  static Future<void> uninit() async {}
}
