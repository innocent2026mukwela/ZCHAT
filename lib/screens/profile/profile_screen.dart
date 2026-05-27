import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/fcm_service.dart';
import '../../utils/glass.dart';
import '../../widgets/bottom_nav_bar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth    = FirebaseAuth.instance;
  final _db      = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  User? get _user => _auth.currentUser;

  Map<String, dynamic> _profile = {};
  bool _loading        = true;
  bool _uploadingPhoto = false;

  // Live stats
  int _coursesCount     = 0;
  int _studyPlansCount  = 0;
  int _studyGuidesCount = 0;
  int _followersCount   = 0;

  // Privacy toggles (local state — saved to Firestore)
  String _privacyLastSeen = 'My contacts';
  String _privacyPhoto    = 'My contacts';
  String _privacyGroups   = 'My contacts';
  String _statusPrivacy   = 'My contacts';
  bool   _readReceipts    = true;

  // Notification toggles
  bool _notifMessages  = true;
  bool _notifCalls     = true;
  bool _notifReminders = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (_user == null) return;
    final uid = _user!.uid;

    // Load profile doc
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};

    // Load stats concurrently
    final results = await Future.wait([
      _db.collection('users').doc(uid).collection('timetable').get(),
      _db.collection('users').doc(uid).collection('studyPlans').get(),
      _db.collection('users').doc(uid).collection('studyGuides').get(),
      _db.collection('users').doc(uid).collection('followers').count().get(),
    ]);

    // Unique subjects from timetable
    final subjects = (results[0] as QuerySnapshot)
        .docs
        .map((d) => (d.data() as Map<String, dynamic>)['subject'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();

    if (mounted) {
      setState(() {
        _profile          = data;
        _coursesCount     = subjects.length;
        _studyPlansCount  = (results[1] as QuerySnapshot).docs.length;
        _studyGuidesCount = (results[2] as QuerySnapshot).docs.length;
        _followersCount   = (results[3] as AggregateQuerySnapshot).count ?? 0;

        _privacyLastSeen  = data['privacyLastSeen'] as String? ?? 'My contacts';
        _privacyPhoto     = data['privacyPhoto']    as String? ?? 'My contacts';
        _privacyGroups    = data['privacyGroups']   as String? ?? 'My contacts';
        _statusPrivacy    = data['statusPrivacy']   as String? ?? 'My contacts';
        _readReceipts     = data['readReceipts']    as bool?   ?? true;
        _notifMessages    = data['notifMessages']   as bool?   ?? true;
        _notifCalls       = data['notifCalls']      as bool?   ?? true;
        _notifReminders   = data['notifReminders']  as bool?   ?? true;

        _loading = false;
      });
    }
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  String get _displayName => _profile['fullName']    as String?
      ?? _user?.displayName
      ?? 'Student';
  String get _phone    => _profile['phoneNumber'] as String? ?? _user?.phoneNumber ?? '';
  String get _photoUrl => _profile['photoUrl']    as String? ?? _user?.photoURL   ?? '';
  String get _role     => _profile['role']        as String? ?? 'student';
  String get _studentId => _profile['studentId'] as String? ?? '';
  String get _program  => _profile['program']     as String? ?? '';
  String get _school   => _profile['school']      as String? ?? '';
  String get _about    => _profile['about']       as String? ?? '';

  // ── Firestore save helper ─────────────────────────────────────────────────

  Future<void> _save(Map<String, dynamic> fields) async {
    if (_user == null) return;
    await _db.collection('users').doc(_user!.uid).update(fields);
    await _loadAll();
  }

  // ── Photo ─────────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      final ref = _storage.ref().child('avatars/${_user!.uid}/profile.jpg');
      await ref.putFile(File(picked.path), SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await _user?.updatePhotoURL(url);
      await _save({'photoUrl': url});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Edit sheets ───────────────────────────────────────────────────────────

  void _editName() => _showTextSheet(
    title: 'Edit Name',
    initial: _displayName,
    label: 'Full name',
    icon: Icons.person_outline_rounded,
    onSave: (v) async {
      await _user?.updateDisplayName(v);
      await _save({'fullName': v});
    },
  );

  void _editAbout() => _showTextSheet(
    title: 'About',
    initial: _about,
    label: 'About',
    icon: Icons.info_outline_rounded,
    hint: 'Hey there! I am using ZCHAT.',
    onSave: (v) => _save({'about': v}),
  );

  void _editStudentId() => _showTextSheet(
    title: 'Student ID',
    initial: _studentId,
    label: 'Student ID',
    icon: Icons.badge_outlined,
    onSave: (v) => _save({'studentId': v}),
  );

  void _editProgram() => _showTextSheet(
    title: 'Program',
    initial: _program,
    label: 'Programme (e.g. BSc Computer Science)',
    icon: Icons.school_outlined,
    onSave: (v) => _save({'program': v}),
  );

  void _editSchool() => _showTextSheet(
    title: 'School',
    initial: _school,
    label: 'School / Faculty',
    icon: Icons.account_balance_outlined,
    onSave: (v) => _save({'school': v}),
  );

  void _showTextSheet({
    required String title,
    required String initial,
    required String label,
    required IconData icon,
    String? hint,
    required Future<void> Function(String) onSave,
  }) {
    final ctrl = TextEditingController(text: initial);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: _Sheet(
              title: title,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _GlassField(controller: ctrl, label: label, icon: icon, hint: hint),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity,
                  child: _PrimaryBtn(label: 'Save', onTap: () async {
                    final v = ctrl.text.trim();
                    Navigator.pop(ctx);
                    if (v.isNotEmpty) await onSave(v);
                  }),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Privacy picker ────────────────────────────────────────────────────────

  void _pickPrivacy(String field, String current, String label) {
    const options = ['Everyone', 'My contacts', 'Nobody'];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...options.map((opt) => ListTile(
            title: Text(opt, style: TextStyle(
              color: opt == current ? const Color(0xFF4F8AFF) : Colors.white,
              fontWeight: opt == current ? FontWeight.w700 : FontWeight.w400,
            )),
            trailing: opt == current
                ? const Icon(Icons.check_rounded, color: Color(0xFF4F8AFF))
                : null,
            onTap: () async {
              Navigator.pop(context);
              await _save({field: opt});
            },
          )),
        ]),
      ),
    );
  }

  // ── QR sheet ──────────────────────────────────────────────────────────────

  void _showQr() {
    final qrData = _phone.isNotEmpty ? _phone : _user?.uid ?? 'zchat';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1A4A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Text(_displayName,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_phone, style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text('Scan with ZCHAT to connect',
            style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13)),
        ]),
      ),
    );
  }

  // ── Sign out ──────────────────────────────────────────────────────────────

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0A1A4A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign out?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to sign out?',
          style: TextStyle(color: Colors.white.withAlpha(180))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FcmService.clearToken();
              await _auth.signOut();
              if (mounted) context.go('/login');
            },
            child: const Text('Sign out',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      bottomNavigationBar: const AppBottomNavBar(),
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Column(children: [
            _buildAppBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      children: [
                        _buildAvatarCard().animate().fadeIn(),
                        const SizedBox(height: 14),
                        _buildStatsRow().animate(delay: 60.ms).fadeIn(),
                        const SizedBox(height: 16),
                        _Section(title: 'PERSONAL INFO', color: const Color(0xFF4F8AFF), children: [
                          _Row(icon: Icons.person_outline_rounded, label: 'Name',       value: _displayName,               onTap: _editName),
                          _Div(),
                          _Row(icon: Icons.info_outline_rounded,   label: 'About',      value: _about.isNotEmpty ? _about : 'Tap to add',
                            onTap: _editAbout, valueMuted: _about.isEmpty),
                          _Div(),
                          _Row(icon: Icons.phone_outlined, label: 'Phone', value: _phone.isNotEmpty ? _phone : '—', onTap: () {
                            if (_phone.isNotEmpty) {
                              Clipboard.setData(ClipboardData(text: _phone));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number copied'), behavior: SnackBarBehavior.floating));
                            }
                          }),
                          _Div(),
                          _Row(icon: Icons.badge_outlined,         label: 'Student ID', value: _studentId.isNotEmpty ? _studentId : 'Tap to add',
                            onTap: _editStudentId, valueMuted: _studentId.isEmpty),
                          _Div(),
                          _Row(icon: Icons.school_outlined,        label: 'Programme',  value: _program.isNotEmpty ? _program : 'Tap to add',
                            onTap: _editProgram, valueMuted: _program.isEmpty),
                          _Div(),
                          _Row(icon: Icons.account_balance_outlined, label: 'School',  value: _school.isNotEmpty ? _school : 'Tap to add',
                            onTap: _editSchool, valueMuted: _school.isEmpty),
                        ]).animate(delay: 80.ms).fadeIn(),
                        const SizedBox(height: 12),
                        _Section(title: 'PRIVACY', color: const Color(0xFFB794F4), children: [
                          _Row(
                            icon: Icons.access_time_rounded, label: 'Last seen',
                            value: _privacyLastSeen,
                            onTap: () => _pickPrivacy('privacyLastSeen', _privacyLastSeen, 'Who can see your last seen'),
                          ),
                          _Div(),
                          _Row(
                            icon: Icons.image_outlined, label: 'Profile photo',
                            value: _privacyPhoto,
                            onTap: () => _pickPrivacy('privacyPhoto', _privacyPhoto, 'Who can see your photo'),
                          ),
                          _Div(),
                          _Row(
                            icon: Icons.group_outlined, label: 'Groups',
                            value: _privacyGroups,
                            onTap: () => _pickPrivacy('privacyGroups', _privacyGroups, 'Who can add you to groups'),
                          ),
                          _Div(),
                          _Row(
                            icon: Icons.circle_outlined, label: 'Status',
                            value: _statusPrivacy,
                            onTap: () => _pickPrivacy('statusPrivacy', _statusPrivacy, 'Who can see my status'),
                          ),
                          _Div(),
                          _ToggleRow(
                            icon: Icons.done_all_rounded,
                            label: 'Read receipts',
                            value: _readReceipts,
                            onChanged: (v) async {
                              setState(() => _readReceipts = v);
                              await _save({'readReceipts': v});
                            },
                          ),
                        ]).animate(delay: 100.ms).fadeIn(),
                        const SizedBox(height: 12),
                        _Section(title: 'NOTIFICATIONS', color: const Color(0xFFFBBF24), children: [
                          _ToggleRow(
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'Messages',
                            value: _notifMessages,
                            onChanged: (v) async {
                              setState(() => _notifMessages = v);
                              await _save({'notifMessages': v});
                            },
                          ),
                          _Div(),
                          _ToggleRow(
                            icon: Icons.call_outlined,
                            label: 'Calls',
                            value: _notifCalls,
                            onChanged: (v) async {
                              setState(() => _notifCalls = v);
                              await _save({'notifCalls': v});
                            },
                          ),
                          _Div(),
                          _ToggleRow(
                            icon: Icons.alarm_outlined,
                            label: 'Planner reminders',
                            value: _notifReminders,
                            onChanged: (v) async {
                              setState(() => _notifReminders = v);
                              await _save({'notifReminders': v});
                            },
                          ),
                        ]).animate(delay: 120.ms).fadeIn(),
                        const SizedBox(height: 12),
                        _Section(title: 'ACCOUNT', color: const Color(0xFF86EFAC), children: [
                          _Row(icon: Icons.qr_code_rounded,       label: 'My QR Code',  value: '', onTap: _showQr),
                          _Div(),
                          _Row(icon: Icons.security_rounded, label: 'Two-step verification', value: 'Off', onTap: () {
                            showDialog(context: context, builder: (_) => AlertDialog(
                              backgroundColor: const Color(0xFF0E1829),
                              title: const Text('Two-step verification', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              content: const Text('Two-step verification adds an extra layer of security to your account. This feature will be available in a future update.', style: TextStyle(color: Colors.white70)),
                              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK', style: TextStyle(color: Color(0xFF4F8AFF))))],
                            ));
                          }),
                          _Div(),
                          _Row(icon: Icons.info_outline_rounded, label: 'App version', value: 'v1.0.0', onTap: () {
                            showAboutDialog(
                              context: context,
                              applicationName: 'ZCHAT',
                              applicationVersion: 'v1.0.0',
                              applicationLegalese: '© 2025 University of Zambia\nBuilt by Innocent Tembo',
                            );
                          }),
                        ]).animate(delay: 140.ms).fadeIn(),
                        const SizedBox(height: 12),
                        GlassCard(
                          borderRadius: BorderRadius.circular(16),
                          bgColor: Colors.redAccent.withAlpha(15),
                          borderColor: Colors.redAccent.withAlpha(50),
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                            title: const Text('Sign out',
                              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 15)),
                            onTap: _confirmSignOut,
                          ),
                        ).animate(delay: 160.ms).fadeIn(),
                      ],
                    ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildAppBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(12),
            border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          child: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => context.go('/home'),
              ),
              const Expanded(child: Text('Profile',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                onPressed: _editName,
              ),
            ]),
          )),
        ),
      ),
    );
  }

  Widget _buildAvatarCard() => GlassCard(
    borderRadius: BorderRadius.circular(24),
    bgColor: const Color(0xFF2563EB).withAlpha(15),
    borderColor: const Color(0xFF2563EB).withAlpha(50),
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      // Avatar
      Stack(children: [
        GestureDetector(
          onTap: _pickPhoto,
          child: Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF4F8AFF)]),
              boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withAlpha(100), blurRadius: 20)],
            ),
            child: _uploadingPhoto
                ? const Center(child: SizedBox(width: 24, height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                : ClipOval(
                    child: _photoUrl.isNotEmpty
                        ? CachedNetworkImage(imageUrl: _photoUrl, fit: BoxFit.cover,
                            width: 90, height: 90,
                            placeholder: (c, u) => const Icon(Icons.person_rounded, size: 46, color: Colors.white),
                            errorWidget:  (c, u, e) => const Icon(Icons.person_rounded, size: 46, color: Colors.white))
                        : const Icon(Icons.person_rounded, size: 48, color: Colors.white),
                  ),
          ),
        ),
        Positioned(
          bottom: 0, right: 0,
          child: GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB), shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF070F1E), width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      Text(_displayName,
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(_phone.isNotEmpty ? _phone : 'No phone number',
        style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 13)),
      if (_about.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(_about, textAlign: TextAlign.center,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 12)),
      ],
      const SizedBox(height: 10),
      // Role + ID chip
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB).withAlpha(50),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(80)),
        ),
        child: Text(
          [
            '${_role[0].toUpperCase()}${_role.substring(1)}',
            if (_studentId.isNotEmpty) _studentId,
            if (_program.isNotEmpty) _program,
          ].join(' · '),
          style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 14),
      // QR button
      GestureDetector(
        onTap: _showQr,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withAlpha(35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.qr_code_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text('My QR Code', style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 13)),
          ]),
        ),
      ),
    ]),
  );

  Widget _buildStatsRow() => Row(children: [
    _Stat('$_coursesCount',     'Courses',      const Color(0xFF4F8AFF)),
    const SizedBox(width: 8),
    _Stat('$_studyPlansCount',  'Study Plans',  const Color(0xFFB794F4)),
    const SizedBox(width: 8),
    _Stat('$_studyGuidesCount', 'Guides',       const Color(0xFF86EFAC)),
    const SizedBox(width: 8),
    _Stat('$_followersCount',   'Followers',    const Color(0xFFFBBF24)),
  ]);
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

class _Sheet extends StatelessWidget {
  final String title;
  final Widget child;
  const _Sheet({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF0E1829),
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Container(width: 40, height: 4,
        decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 20),
      Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      child,
    ]),
  );
}

class _GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  const _GlassField({required this.controller, required this.label, required this.icon, this.hint});
  @override
  Widget build(BuildContext context) => GlassCard(
    borderRadius: BorderRadius.circular(12),
    bgColor: Colors.white.withAlpha(8),
    borderColor: Colors.white.withAlpha(30),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    child: TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        border: InputBorder.none,
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withAlpha(160)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withAlpha(80)),
        prefixIcon: Icon(icon, color: Colors.white.withAlpha(160), size: 20),
      ),
    ),
  );
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withAlpha(80), blurRadius: 16)],
      ),
      alignment: Alignment.center,
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
    ),
  );
}

class _Stat extends StatelessWidget {
  final String value, label;
  final Color color;
  const _Stat(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: GlassCard(
      borderRadius: BorderRadius.circular(12),
      bgColor: color.withAlpha(15),
      borderColor: color.withAlpha(40),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 10),
          textAlign: TextAlign.center),
      ]),
    ),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final Color color;
  final List<Widget> children;
  const _Section({required this.title, required this.color, required this.children});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      ),
      GlassCard(
        borderRadius: BorderRadius.circular(16),
        bgColor: color.withAlpha(8),
        borderColor: color.withAlpha(35),
        padding: EdgeInsets.zero,
        child: Column(children: children),
      ),
    ],
  );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final bool valueMuted;
  final VoidCallback onTap;
  const _Row({
    required this.icon, required this.label, required this.value,
    required this.onTap, this.valueMuted = false,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: Icon(icon, color: Colors.white.withAlpha(160), size: 20),
    title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
    trailing: value.isNotEmpty
        ? Text(value, style: TextStyle(
            color: valueMuted ? Colors.white.withAlpha(80) : Colors.white.withAlpha(140),
            fontSize: 13,
            fontStyle: valueMuted ? FontStyle.italic : FontStyle.normal,
          ))
        : Icon(Icons.chevron_right_rounded, color: Colors.white.withAlpha(100), size: 18),
    onTap: onTap,
  );
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.icon, required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: Icon(icon, color: Colors.white.withAlpha(160), size: 20),
    title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
    trailing: Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: const Color(0xFF4F8AFF),
    ),
  );
}

class _Div extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 52, color: Colors.white.withAlpha(15));
}
