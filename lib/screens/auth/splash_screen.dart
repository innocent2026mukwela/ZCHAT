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
      duration: const Duration(milliseconds: 900),
    )..forward();
    _checkAuth();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      context.go('/login');
      return;
    }

    // Contacts permission is requested contextually (New Chat / Status), not here.
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
    } catch (e, st) {
      // Offline / read failed — don't hang forever on the splash; enter the app.
      debugPrint('[Splash] profile check failed: $e\n$st');
      if (mounted) context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070D18),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Center(
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, _) {
              final t = Curves.easeOutCubic.transform(_anim.value);
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - t)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/icons/zchat_logo_cutout.png',
                        width: 180,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Text(
                          'ZCHAT',
                          style: TextStyle(
                            fontFamily: kBrandFont,
                            color: Color(0xFF5B9BFF),
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withAlpha(100),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
