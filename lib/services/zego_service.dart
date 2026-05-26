import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

const int kZegoAppId     = 1781765877;
const String kZegoAppSign = 'cdc671cbee473400e34f53d71a0bcae66372a3fd4a22d47af81d8bf485320ea2';

class ZegoService {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Direct call UI only — no push-based invitation service
  }

  static Future<void> uninit() async {}
}
