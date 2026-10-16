import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import '../../services/auth_service.dart';
import '../../services/two_step_service.dart';
import '../../services/zego_service.dart';
import '../../utils/glass.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  const OtpScreen({super.key, required this.phoneNumber});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _pinController = TextEditingController();
  final _focusNode     = FocusNode();
  bool _loading        = false;
  bool _resending      = false;
  String? _error;
  /// Session verification code when local OTP is used (shown neutrally).
  String? _sessionCode;
  int _secondsLeft     = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sessionCode = AuthService.lastDemoOtp;
    _startCountdown();
  }

  @override
  void dispose() { _timer?.cancel(); _pinController.dispose(); _focusNode.dispose(); super.dispose(); }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) { t.cancel(); return; }
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _verify(String otp) async {
    if (otp.length < 6) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await AuthService.verifyOtp(widget.phoneNumber, otp);
      // Zego is call infrastructure — never let its init failure (web, no
      // network, bad creds) block an otherwise-valid login.
      try {
        await ZegoService.init();
      } catch (e) {
        debugPrint('[OtpScreen] Zego init skipped: $e');
      }
      if (!mounted) return;

      // Two-step verification: if user has a PIN, require it before entry
      final pinEnabled = await TwoStepService.isEnabled();
      if (pinEnabled && mounted) {
        final passed = await _showPinChallenge();
        if (!passed) {
          setState(() { _error = 'Incorrect PIN. Try again.'; _pinController.clear(); });
          _focusNode.requestFocus();
          return;
        }
      }
      if (!mounted) return;
      if (result['needsProfile'] == true) {
        context.go('/profile-setup');
        return;
      }
      // Route lecturers to their home — do not dump them on the student shell.
      final me = await AuthService.getMe();
      if (!mounted) return;
      final role = me?['role'] as String?;
      context.go(role == 'lecturer' ? '/lecturer/home' : '/home');
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _pinController.clear(); });
      _focusNode.requestFocus();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _showPinChallenge() async {
    final ctrl = TextEditingController();
    bool? passed;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1829),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Two-step verification',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter your 6-digit PIN to continue.',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          Pinput(
            controller: ctrl,
            length: 6,
            obscureText: true,
            autofocus: true,
            onCompleted: (pin) async {
              final ok = await TwoStepService.verify(pin);
              if (ctx.mounted) Navigator.pop(ctx, ok);
            },
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    ).then((v) => passed = v as bool?);
    return passed == true;
  }

  Future<void> _resend() async {
    setState(() { _resending = true; _error = null; });
    try {
      final code = await AuthService.sendOtp(widget.phoneNumber);
      if (mounted) {
        setState(() => _sessionCode = code ?? AuthService.lastDemoOtp);
      }
      _startCountdown(); _pinController.clear(); _focusNode.requestFocus();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  String get _maskedPhone {
    final p = widget.phoneNumber;
    return p.length > 6 ? '${p.substring(0, p.length - 4)}••••' : p;
  }

  @override
  Widget build(BuildContext context) {
    final pinTheme = PinTheme(
      width: 56, height: 64,
      textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(50), width: 1.5),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(
          children: [
            const GlowOrbs(),
            SafeArea(
              child: Column(
                children: [
                  // Back button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: GlassCard(
                            borderRadius: BorderRadius.circular(12),
                            padding: const EdgeInsets.all(10),
                            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          const SizedBox(height: 48),

                          // Icon
                          GlassCard(
                            borderRadius: BorderRadius.circular(24),
                            padding: const EdgeInsets.all(20),
                            child: const Icon(Icons.lock_rounded, size: 36, color: Colors.white),
                          ).animate().scale(begin: const Offset(0.7, 0.7), duration: 500.ms, curve: Curves.elasticOut),

                          const SizedBox(height: 24),

                          const Text('Verification', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1))
                              .animate(delay: 100.ms).fadeIn().slideY(begin: 0.15, end: 0),

                          const SizedBox(height: 8),

                          RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(160), height: 1.5),
                              children: [
                                const TextSpan(text: 'Code sent to '),
                                TextSpan(text: _maskedPhone,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ).animate(delay: 160.ms).fadeIn(),

                          if (_sessionCode != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withAlpha(40)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'For this session',
                                    style: TextStyle(
                                      color: Colors.white.withAlpha(160),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _sessionCode!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 4,
                                    ),
                                  ),
                                ],
                              ),
                            ).animate(delay: 180.ms).fadeIn(),
                          ],

                          const SizedBox(height: 44),

                          // PIN input
                          Pinput(
                            length: 6,
                            controller: _pinController,
                            focusNode: _focusNode,
                            autofocus: true,
                            defaultPinTheme: pinTheme,
                            focusedPinTheme: pinTheme.copyDecorationWith(
                              border: Border.all(color: const Color(0xFF4F8AFF), width: 2),
                              color: Colors.white.withAlpha(30),
                            ),
                            submittedPinTheme: pinTheme.copyWith(
                              decoration: pinTheme.decoration?.copyWith(
                                color: const Color(0xFF2563EB).withAlpha(60),
                                border: Border.all(color: const Color(0xFF4F8AFF), width: 1.5),
                              ),
                            ),
                            errorPinTheme: pinTheme.copyDecorationWith(
                              border: Border.all(color: Colors.redAccent, width: 2),
                            ),
                            forceErrorState: _error != null,
                            hapticFeedbackType: HapticFeedbackType.lightImpact,
                            onCompleted: _loading ? null : _verify,
                            separatorBuilder: (_) => const SizedBox(width: 10),
                            keyboardType: TextInputType.number,
                          ).animate(delay: 220.ms).fadeIn().slideY(begin: 0.12, end: 0),

                          const SizedBox(height: 16),

                          if (_error != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withAlpha(30),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.red.withAlpha(80)),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                                  ]),
                                ),
                              ),
                            ).animate().fadeIn().shake(),

                          const SizedBox(height: 28),

                          if (_loading)
                            const CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2)
                          else if (_secondsLeft > 0)
                            RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(140)),
                                children: [
                                  const TextSpan(text: 'Resend in '),
                                  TextSpan(text: '${_secondsLeft}s',
                                    style: const TextStyle(color: Color(0xFF4F8AFF), fontWeight: FontWeight.w700)),
                                ],
                              ),
                            )
                          else
                            TextButton(
                              onPressed: _resending ? null : _resend,
                              child: _resending
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F8AFF)))
                                  : const Text('Resend Code', style: TextStyle(color: Color(0xFF4F8AFF), fontWeight: FontWeight.w700, fontSize: 14)),
                            ),

                          const SizedBox(height: 24),

                          GestureDetector(
                            onTap: () => context.go('/login'),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(120)),
                                children: const [
                                  TextSpan(text: 'Wrong number? '),
                                  TextSpan(text: 'Change it',
                                    style: TextStyle(color: Color(0xFF4F8AFF), fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
