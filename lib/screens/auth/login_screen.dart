import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../../config.dart';
import '../../services/auth_service.dart';
import '../../utils/glass.dart';

class LoginScreen extends StatefulWidget {
  final Duration introDelay;

  const LoginScreen({
    super.key,
    this.introDelay = Duration.zero,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey    = GlobalKey<FormState>();
  String _fullPhone = '';
  bool _loading     = false;
  String? _error;

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate() || _fullPhone.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final demoOtp = await AuthService.sendOtp(_fullPhone);
      if (!mounted) return;
      if (AppConfig.demoAuth && demoOtp != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Demo OTP: $demoOtp  ·  any 6-digit code works'),
            backgroundColor: const Color(0xFF1A6BE0),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      context.go('/otp', extra: _fullPhone);
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
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: SafeArea(
          child: Column(
            children: [
              if (AppConfig.demoAuth) const _DemoModeBanner(),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ZBrandLockup(symbolSize: 58, fontSize: 40),
                          const SizedBox(height: 12),
                          Text(
                            'University of Zambia · Campus messaging',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withAlpha(140),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 44),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Enter your phone number',
                              style: TextStyle(
                                color: Colors.white.withAlpha(215),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SignInForm(
                            formKey: _formKey,
                            loading: _loading,
                            error: _error,
                            onPhoneChanged: (phone) => _fullPhone = phone,
                            onContinue: _continue,
                          ),
                        ],
                      ).animate().fadeIn(delay: widget.introDelay, duration: 400.ms).slideY(begin: 0.04, end: 0),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoModeBanner extends StatelessWidget {
  const _DemoModeBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE6A817),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.science_outlined, size: 16, color: Color(0xFF1A1200)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'DEMO MODE — OTP is local; no backend required. '
                'Disable with --dart-define=DEMO_AUTH=false',
                style: TextStyle(
                  color: const Color(0xFF1A1200).withAlpha(230),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
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
          Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF152033),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(22), width: 1),
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
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
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
            ).animate().fadeIn(),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: loading ? null : onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A6BE0),
                disabledBackgroundColor: const Color(0xFF1A6BE0).withAlpha(100),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
