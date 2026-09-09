import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../utils/glass.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _checkAuth();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    // Wait for animation to feel natural
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // Not logged in → go to login
      context.go('/login');
      return;
    }

    // Logged in → check if profile is complete. (Contacts permission is now
    // requested contextually, in New Chat / Status, not eagerly here.)
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      final profileComplete = doc.exists && doc.data()?['profileComplete'] == true;
      final role = doc.data()?['role'] as String?;

      if (!profileComplete) {
        context.go('/profile-setup');
      } else if (role == 'lecturer') {
        context.go('/lecturer/home');
      } else {
        context.go('/home');
      }
    } catch (_) {
      // Offline / read failed — don't hang forever on the splash; enter the app.
      if (mounted) context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06112B),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(
          children: [
            const GlowOrbs(),
            Center(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, _) {
                  final opacity = Curves.easeOut.transform(_anim.value);
                  final scale   = 0.85 + 0.15 * Curves.elasticOut.transform(_anim.value);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/icons/zchat_logo_cutout.png',
                            width: 200,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Text(
                              'ZCHAT',
                              style: TextStyle(
                                color: Color(0xFF2EA3FF),
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white.withAlpha(120),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
