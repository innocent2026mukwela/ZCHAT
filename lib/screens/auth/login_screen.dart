import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  final Duration introDelay;

  const LoginScreen({
    super.key,
    this.introDelay = Duration.zero,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey    = GlobalKey<FormState>();
  String _fullPhone = '';
  bool _loading     = false;
  String? _error;
  late final AnimationController _introController;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
      value: widget.introDelay == Duration.zero ? 1 : 0,
    );
    if (widget.introDelay != Duration.zero) _revealForm();
  }

  Future<void> _revealForm() async {
    await Future.delayed(widget.introDelay);
    if (mounted) _introController.forward();
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate() || _fullPhone.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.sendOtp(_fullPhone);
      if (mounted) context.go('/otp', extra: _fullPhone);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF03050F),
              Color(0xFF06112B),
              Color(0xFF0A2060),
              Color(0xFF0D3599),
            ],
            stops: [0.0, 0.3, 0.65, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Glow orbs
            Positioned(
              top: -100, right: -100,
              child: Container(
                width: 320, height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF2563EB).withAlpha(50), Colors.transparent,
                  ]),
                ),
              ),
            ),
            Positioned(
              bottom: -80, left: -80,
              child: Container(
                width: 260, height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF4F8AFF).withAlpha(35), Colors.transparent,
                  ]),
                ),
              ),
            ),

            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final logoWidth = (constraints.maxWidth * 0.74).clamp(
                    220.0,
                    420.0,
                  );

                  return AnimatedBuilder(
                    animation: _introController,
                    child: _SignInForm(
                      formKey: _formKey,
                      loading: _loading,
                      error: _error,
                      onPhoneChanged: (phone) => _fullPhone = phone,
                      onContinue: _continue,
                    ),
                    builder: (context, child) {
                      final progress = _introController.value;
                      final logoProgress = Curves.easeInOutCubic.transform(progress);
                      final formProgress = Curves.easeOutCubic.transform(
                        ((progress - 0.20) / 0.80).clamp(0.0, 1.0),
                      );
                      final formOpacity = Curves.easeOut.transform(
                        ((progress - 0.30) / 0.70).clamp(0.0, 1.0),
                      );
                      final logoAlignmentY = Alignment.lerp(
                        Alignment.center,
                        const Alignment(0, -0.62),
                        logoProgress,
                      )!.y;

                      return Stack(
                        children: [
                          Align(
                            alignment: Alignment(0, logoAlignmentY),
                            child: _BrandLogo(width: logoWidth),
                          ),
                          Transform.translate(
                            offset: Offset(0, (1 - formProgress) * 44),
                            child: Opacity(
                              opacity: formOpacity,
                              child: IgnorePointer(
                                ignoring: progress < 0.85,
                                child: SingleChildScrollView(
                                  padding: EdgeInsets.fromLTRB(
                                    28,
                                    constraints.maxHeight * 0.34,
                                    28,
                                    40,
                                  ),
                                  child: child,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
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

class _BrandLogo extends StatelessWidget {
  final double width;
  static const _brandAsset = 'assets/icons/zchat_logo_cutout.png';

  const _BrandLogo({required this.width});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _brandAsset,
      width: width,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) {
        return const Text(
          'ZCHAT',
          style: TextStyle(
            color: Color(0xFF2EA3FF),
            fontSize: 34,
            fontWeight: FontWeight.w900,
          ),
        );
      },
    );
  }
}

class _SignInForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool loading;
  final String? error;
  final ValueChanged<String> onPhoneChanged;
  final VoidCallback onContinue;

  const _SignInForm({
    required this.formKey,
    required this.loading,
    required this.error,
    required this.onPhoneChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withAlpha(22),
                      Colors.white.withAlpha(8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withAlpha(40), width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: IntlPhoneField(
                  initialCountryCode: 'ZM',
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                  dropdownTextStyle: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  dropdownIcon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white.withAlpha(180),
                  ),
                  flagsButtonPadding: const EdgeInsets.only(left: 12),
                  decoration: InputDecoration(
                    hintText: '97 123 4567',
                    hintStyle: TextStyle(
                      color: Colors.white.withAlpha(100),
                      fontSize: 16,
                    ),
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 16,
                    ),
                  ),
                  onChanged: (phone) => onPhoneChanged(phone.completeNumber),
                  validator: (phone) {
                    if (phone == null || phone.number.length < 7) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
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
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.redAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ).animate().fadeIn().shake(),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: loading ? null : onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                disabledBackgroundColor: const Color(0xFF2563EB).withAlpha(100),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                shadowColor: const Color(0xFF2563EB).withAlpha(100),
              ),
              child: loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (dctx) => AlertDialog(
                backgroundColor: const Color(0xFF0E1829),
                title: const Text('Terms & Privacy', style: TextStyle(color: Colors.white, fontSize: 16)),
                content: const SingleChildScrollView(
                  child: Text(
                    'ZCHAT is a University of Zambia student communication and study platform.\n\n'
                    'By using ZCHAT you agree to use it respectfully and lawfully, and you consent to '
                    'the storage of your profile, messages, and study data to provide the service. Your '
                    'phone number is used only to create and secure your account. We do not sell your '
                    'data, and you can request account deletion at any time.\n\n'
                    'The full Terms of Service and Privacy Policy will be published at zchat.unza.zm.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dctx),
                    child: const Text('Close', style: TextStyle(color: Color(0xFF4F8AFF))),
                  ),
                ],
              ),
            ),
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(80), height: 1.6),
                children: const [
                  TextSpan(text: 'By continuing, you agree to our '),
                  TextSpan(text: 'Terms of Service', style: TextStyle(color: Color(0xFF4F8AFF), fontWeight: FontWeight.w600)),
                  TextSpan(text: ' and '),
                  TextSpan(text: 'Privacy Policy', style: TextStyle(color: Color(0xFF4F8AFF), fontWeight: FontWeight.w600)),
                  TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
