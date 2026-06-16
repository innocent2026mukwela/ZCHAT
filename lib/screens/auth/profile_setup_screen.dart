import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../utils/glass.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  static const _universities = [
    'University of Zambia',
    'Copperbelt University',
    'Mulungushi University',
    'Cavendish University Zambia',
    'Zambia Open University',
    'University of Lusaka',
    'Northrise University',
    'Other',
  ];
  String _university = 'University of Zambia';
  final _studentCtrl = TextEditingController();
  final _schoolCtrl = TextEditingController();
  final _programCtrl = TextEditingController();
  final _staffCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _role       = 'student';
  bool _loading      = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _studentCtrl.dispose();
    _schoolCtrl.dispose();
    _programCtrl.dispose();
    _staffCtrl.dispose();
    _departmentCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == 'lecturer') {
      final email = _emailCtrl.text.trim().toLowerCase();
      if (!email.endsWith('@unza.zm') && !email.endsWith('@unza.ac.zm')) {
        setState(() => _error = 'Lecturer email must be a UNZA institutional address (@unza.zm)');
        return;
      }
    }
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.completeProfile(
        fullName: _nameCtrl.text.trim(),
        role: _role,
        university: _university,
        studentNumber: _role == 'student' ? _studentCtrl.text.trim() : null,
        school: _role == 'student' ? _schoolCtrl.text.trim() : null,
        program: _role == 'student' ? _programCtrl.text.trim() : null,
        staffId: _role == 'lecturer' ? _staffCtrl.text.trim() : null,
        department: _role == 'lecturer' ? _departmentCtrl.text.trim() : null,
        lecturerEmail: _role == 'lecturer' ? _emailCtrl.text.trim() : null,
      );
      if (mounted) context.go(_role == 'lecturer' ? '/lecturer/home' : '/home');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(
          children: [
            const GlowOrbs(),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const SizedBox(height: 56),

                      // Logo
                      GlassCard(
                        borderRadius: BorderRadius.circular(22),
                        padding: const EdgeInsets.all(18),
                        child: const Icon(Icons.person_rounded, size: 32, color: Colors.white),
                      ).animate().scale(begin: const Offset(0.7, 0.7), duration: 500.ms, curve: Curves.elasticOut),

                      const SizedBox(height: 20),

                      const Text('Set up profile',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5))
                          .animate(delay: 80.ms).fadeIn().slideY(begin: 0.1, end: 0),

                      const SizedBox(height: 6),

                      Text('Shown to classmates and lecturers',
                        style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(140)))
                          .animate(delay: 140.ms).fadeIn(),

                      const SizedBox(height: 36),

                      // Role selector
                      GlassCard(
                        borderRadius: BorderRadius.circular(16),
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: ['student', 'lecturer'].map((role) {
                            final sel = _role == role;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _role = role),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: sel ? const Color(0xFF2563EB) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: sel ? [BoxShadow(color: const Color(0xFF2563EB).withAlpha(80), blurRadius: 12)] : [],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(role == 'student' ? Icons.school_outlined : Icons.cast_for_education_outlined,
                                        size: 18, color: sel ? Colors.white : Colors.white.withAlpha(140)),
                                      const SizedBox(width: 7),
                                      Text(role == 'student' ? 'Student' : 'Lecturer',
                                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                                          color: sel ? Colors.white : Colors.white.withAlpha(140))),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ).animate(delay: 180.ms).fadeIn(),

                      const SizedBox(height: 16),

                      // Full name
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(18),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withAlpha(40)),
                            ),
                            child: TextFormField(
                              controller: _nameCtrl,
                              textCapitalization: TextCapitalization.words,
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                hintText: 'Full name',
                                hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                                prefixIcon: Icon(Icons.person_outline_rounded, color: Colors.white.withAlpha(160)),
                                border: InputBorder.none, enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none, filled: false,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                            ),
                          ),
                        ),
                      ).animate(delay: 220.ms).fadeIn().slideY(begin: 0.1, end: 0),

                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showModalBottomSheet<String>(
                            context: context,
                            backgroundColor: const Color(0xFF0E1829),
                            shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                            builder: (_) => SafeArea(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                const SizedBox(height: 12),
                                Container(width: 40, height: 4,
                                  decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2))),
                                const SizedBox(height: 12),
                                const Text('Select University',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                ..._universities.map((u) => ListTile(
                                  title: Text(u, style: TextStyle(
                                    color: u == _university ? const Color(0xFF4F8AFF) : Colors.white)),
                                  trailing: u == _university
                                      ? const Icon(Icons.check_rounded, color: Color(0xFF4F8AFF))
                                      : null,
                                  onTap: () => Navigator.pop(context, u),
                                )),
                                const SizedBox(height: 8),
                              ]),
                            ),
                          );
                          if (picked != null) setState(() => _university = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withAlpha(35)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.account_balance_rounded, color: Color(0xFF4F8AFF), size: 20),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_university,
                                style: const TextStyle(color: Colors.white, fontSize: 15))),
                            Icon(Icons.arrow_drop_down_rounded, color: Colors.white.withAlpha(140)),
                          ]),
                        ),
                      ).animate(delay: 240.ms).fadeIn().slideY(begin: 0.1, end: 0),

                      if (_role == 'student') ...[
                        const SizedBox(height: 12),
                        _GlassInput(
                          controller: _studentCtrl,
                          hintText: 'Student number',
                          icon: Icons.badge_outlined,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Student number is required' : null,
                        ).animate(delay: 260.ms).fadeIn().slideY(begin: 0.1, end: 0),
                        const SizedBox(height: 12),
                        _GlassInput(
                          controller: _schoolCtrl,
                          hintText: 'School',
                          icon: Icons.school_outlined,
                          textCapitalization: TextCapitalization.words,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'School is required' : null,
                        ).animate(delay: 280.ms).fadeIn().slideY(begin: 0.1, end: 0),
                        const SizedBox(height: 12),
                        _GlassInput(
                          controller: _programCtrl,
                          hintText: 'Program of study',
                          icon: Icons.menu_book_outlined,
                          textCapitalization: TextCapitalization.words,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Program of study is required' : null,
                        ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1, end: 0),
                      ],

                      if (_role == 'lecturer') ...[
                        const SizedBox(height: 12),
                        _GlassInput(
                          controller: _staffCtrl,
                          hintText: 'Staff ID',
                          icon: Icons.badge_outlined,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Staff ID is required' : null,
                        ).animate(delay: 260.ms).fadeIn().slideY(begin: 0.1, end: 0),
                        const SizedBox(height: 12),
                        _GlassInput(
                          controller: _departmentCtrl,
                          hintText: 'Department or school',
                          icon: Icons.account_balance_outlined,
                          textCapitalization: TextCapitalization.words,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Department is required' : null,
                        ).animate(delay: 280.ms).fadeIn().slideY(begin: 0.1, end: 0),
                        const SizedBox(height: 12),
                        _GlassInput(
                          controller: _emailCtrl,
                          hintText: 'UNZA email',
                          icon: Icons.alternate_email_rounded,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            final email = v?.trim().toLowerCase() ?? '';
                            if (email.isEmpty) return 'UNZA email is required';
                            if (!email.endsWith('@unza.zm')) return 'Use your @unza.zm email';
                            return null;
                          },
                        ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1, end: 0),
                        const SizedBox(height: 12),
                      ],

                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.red.withAlpha(30), borderRadius: BorderRadius.circular(12),
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
                      ],

                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity, height: 54,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            disabledBackgroundColor: const Color(0xFF2563EB).withAlpha(100),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _loading
                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                              : const Text('Get Started', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.15, end: 0),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const _GlassInput({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withAlpha(40)),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
              prefixIcon: Icon(icon, color: Colors.white.withAlpha(160)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            validator: validator,
          ),
        ),
      ),
    );
  }
}
