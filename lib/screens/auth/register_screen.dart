import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../utils/theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _studentCtrl = TextEditingController();
  final _passCtrl    = TextEditingController();
  String _role = 'student';
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _studentCtrl.dispose(); _passCtrl.dispose();
    super.dispose();
  }

  void _register() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) { setState(() => _loading = false); context.go('/home'); }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent, foregroundColor: AppColors.textDark, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.go('/login')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create Account',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                ).animate().fadeIn().slideX(begin: -0.2, end: 0),
                const SizedBox(height: 4),
                Text('Join the UnZA learning community',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ).animate(delay: 100.ms).fadeIn(),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: ['student', 'lecturer'].map((role) {
                      final sel = _role == role;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _role = role),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(role[0].toUpperCase() + role.substring(1),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: sel ? Colors.white : AppColors.textMuted, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ).animate(delay: 150.ms).fadeIn(),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2, end: 0),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'University Email', prefixIcon: Icon(Icons.email_outlined)),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                ).animate(delay: 230.ms).fadeIn().slideY(begin: 0.2, end: 0),
                const SizedBox(height: 14),
                if (_role == 'student') ...[
                  TextFormField(
                    controller: _studentCtrl,
                    decoration: const InputDecoration(labelText: 'Student Number', prefixIcon: Icon(Icons.badge_outlined)),
                  ).animate(delay: 260.ms).fadeIn().slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                ).animate(delay: 290.ms).fadeIn().slideY(begin: 0.2, end: 0),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _loading ? null : _register,
                  child: _loading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Create Account'),
                ).animate(delay: 320.ms).fadeIn().slideY(begin: 0.3, end: 0),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account? '),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ).animate(delay: 360.ms).fadeIn(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
