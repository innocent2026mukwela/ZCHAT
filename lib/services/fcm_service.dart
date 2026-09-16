import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../router.dart';

/// Top-level handler for background/terminated messages (must be top-level).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs.
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class FcmService {
  static final _fcm = FirebaseMessaging.instance;
  static final _db  = FirebaseFirestore.instance;

  /// Call once from main() after Firebase.initializeApp().
  static Future<void> init() async {
    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission (Android 13+, iOS)
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    // Listen for foreground messages — show a snackbar / in-app banner
    FirebaseMessaging.onMessage.listen(_handleForeground);

    // App opened from a notification while in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);

    // Save token for the signed-in user
    await _saveToken();

    // Token may rotate — keep Firestore up to date
    _fcm.onTokenRefresh.listen(_persistToken);
  }

  // ── Token storage ────────────────────────────────────────────────────────────

  static Future<void> _saveToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      // On iOS, getToken() waits for an APNs device token. Without a paid
      // Apple Developer push entitlement (sideload environment), that
      // registration never completes — so this must not block app startup.
      final token = await _fcm.getToken().timeout(const Duration(seconds: 5));
      if (token != null) await _persistToken(token);
    } catch (e) {
      debugPrint('[FCM] Could not get token: $e');
    }
  }

  static Future<void> _persistToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set(
      {'fcmToken': token, 'fcmUpdatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    debugPrint('[FCM] Token saved for $uid');
  }

  /// Call on sign-out to stop receiving notifications.
  ///
  /// This must never block sign-out. On iOS without a push entitlement (e.g. a
  /// sideloaded build), `deleteToken()` waits on an APNs token that never
  /// arrives and would hang forever — so every step is best-effort with a
  /// timeout, and failures are swallowed.
  static Future<void> clearToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid)
            .set({'fcmToken': FieldValue.delete()}, SetOptions(merge: true))
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('[FCM] Could not clear stored token: $e');
      }
    }
    try {
      await _fcm.deleteToken().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[FCM] Could not delete token: $e');
    }
  }

  // ── Message handlers ─────────────────────────────────────────────────────────

  static final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  static GlobalKey<ScaffoldMessengerState> get messengerKey => _messengerKey;

  static void _handleForeground(RemoteMessage message) {
    // Read receipts are silent — tick marks update via Firestore streams.
    if (message.data['readReceipt'] == 'true') return;

    final n = message.notification;
    if (n == null) return;
    debugPrint('[FCM] Foreground: ${n.title} — ${n.body}');

    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E3A6E),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(children: [
          const Icon(Icons.notifications_rounded, color: Color(0xFF93C5FD), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (n.title != null)
                Text(n.title!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              if (n.body != null)
                Text(n.body!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ]),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  static void _handleOpen(RemoteMessage message) {
    debugPrint('[FCM] Opened from notification: ${message.data}');
    final chatId = message.data['chatId'] as String?;
    if (chatId != null && chatId.isNotEmpty) {
      final name = Uri.encodeComponent(message.data['chatName'] as String? ?? 'Chat');
      appRouter.go('/chats/$chatId?name=$name');
    }
  }
}
