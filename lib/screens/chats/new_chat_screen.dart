import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/chat_service.dart';
import '../../utils/glass.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});
  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  static const _colors = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
    Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
  ];

  List<Map<String, dynamic>> _zchatContacts = [];
  List<Map<String, dynamic>> _filtered = [];

  bool _loading = true;
  String _error = '';
  String _search = '';

  // Add-by-phone
  final _phoneCtrl = TextEditingController();
  bool _phoneSearching = false;
  Map<String, dynamic>? _phoneResult;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Load & match contacts ─────────────────────────────────────────────────

  Future<void> _loadContacts() async {
    setState(() { _loading = true; _error = ''; });

    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (mounted) setState(() { _loading = false; _error = 'Contacts permission denied.\nGo to Settings → Apps → ZCHAT → Permissions to enable it.'; });
      return;
    }

    final contacts = await FlutterContacts.getContacts(withProperties: true);

    // Map E.164 → contact display name (same format Firebase Auth stores)
    final Map<String, String> e164ToName = {};
    for (final c in contacts) {
      for (final p in c.phones) {
        final e164 = _toE164(p.number);
        if (e164.isNotEmpty) e164ToName[e164] = c.displayName;
      }
    }

    if (e164ToName.isEmpty) {
      if (mounted) setState(() { _loading = false; _zchatContacts = []; _filtered = []; });
      return;
    }

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final phones = e164ToName.keys.toList();
    final List<Map<String, dynamic>> matched = [];

    for (int i = 0; i < phones.length; i += 30) {
      final chunk = phones.sublist(i, i + 30 > phones.length ? phones.length : i + 30);
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        if (doc.id == myUid) continue;
        final data = Map<String, dynamic>.from(doc.data());
        data['uid'] = doc.id;
        final docPhone = data['phoneNumber'] as String? ?? '';
        data['contactName'] = e164ToName[docPhone] ?? data['fullName'] ?? data['displayName'] ?? 'Unknown';
        matched.add(data);
      }
    }

    matched.sort((a, b) => (a['contactName'] as String).compareTo(b['contactName'] as String));

    if (mounted) {
      setState(() {
        _zchatContacts = matched;
        _filtered = matched;
        _loading = false;
      });
    }
  }

  void _onSearch(String q) {
    setState(() {
      _search = q;
      _filtered = q.trim().isEmpty
          ? _zchatContacts
          : _zchatContacts.where((u) {
              final name  = (u['contactName'] as String).toLowerCase();
              final phone = (u['phoneNumber'] as String? ?? '').toLowerCase();
              return name.contains(q.toLowerCase()) || phone.contains(q.toLowerCase());
            }).toList();
    });
  }

  Future<void> _openChat(Map<String, dynamic> user) async {
    final uid  = user['uid'] as String;
    final name = (user['contactName'] ?? user['displayName'] ?? 'Unknown') as String;
    final chatId = await ChatService.getOrCreateChat(uid);
    if (!mounted) return;
    context.pushReplacement('/chats/${Uri.encodeComponent(chatId)}?name=${Uri.encodeComponent(name)}');
  }

  // ── Find by phone number ──────────────────────────────────────────────────

  Future<void> _searchByPhone() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.isEmpty) return;
    final e164 = _toE164(raw);
    if (e164.isEmpty) {
      setState(() { _phoneError = 'Enter a valid phone number'; _phoneResult = null; });
      return;
    }
    setState(() { _phoneSearching = true; _phoneError = null; _phoneResult = null; });
    try {
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      // Query E.164 format — that's what Firebase Auth stores
      final candidates = [e164];
      Map<String, dynamic>? found;
      for (final candidate in candidates) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: candidate)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final doc = snap.docs.first;
          if (doc.id == myUid) { found = null; break; }
          final data = Map<String, dynamic>.from(doc.data());
          data['uid'] = doc.id;
          data['contactName'] = data['fullName'] ?? data['displayName'] ?? 'ZCHAT User';
          found = data;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _phoneResult = found;
          _phoneError = found == null ? 'No ZCHAT user found with that number' : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _phoneError = 'Search failed. Try again.');
    } finally {
      if (mounted) setState(() => _phoneSearching = false);
    }
  }

  Future<void> _saveToContacts(Map<String, dynamic> user) async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (mounted) _showSnack('Contacts permission denied');
      return;
    }
    final name  = (user['contactName'] ?? user['displayName'] ?? 'ZCHAT User') as String;
    final phone = user['phone'] as String? ?? '';
    try {
      final contact = Contact()
        ..name.first = name.contains(' ') ? name.split(' ').first : name
        ..name.last  = name.contains(' ') ? name.split(' ').skip(1).join(' ') : ''
        ..phones     = [Phone(phone)];
      await contact.insert();
      if (mounted) _showSnack('$name saved to contacts');
      // Reload so they appear in the contacts list
      _loadContacts();
    } catch (e) {
      if (mounted) _showSnack('Could not save contact');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }

  // Converts any Zambian number format to E.164: +260XXXXXXXXX
  String _toE164(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('260') && digits.length >= 12) return '+$digits';
    if (digits.startsWith('0') && digits.length >= 10)   return '+260${digits.substring(1)}';
    if (digits.length == 9)                              return '+260$digits';
    return '';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Column(children: [
            // App bar + search
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(12),
                    border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                        child: Row(children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Expanded(child: Text('New Chat', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
                          if (!_loading)
                            IconButton(
                              icon: Icon(Icons.refresh_rounded, color: Colors.white.withAlpha(180)),
                              onPressed: _loadContacts,
                              tooltip: 'Refresh',
                            ),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(18),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withAlpha(35)),
                              ),
                              child: TextField(
                                onChanged: _onSearch,
                                style: const TextStyle(color: Colors.white, fontSize: 15),
                                decoration: InputDecoration(
                                  hintText: 'Search contacts…',
                                  hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                                  prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(160)),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),

            Expanded(child: _buildBody()),
          ]),
        ]),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── Add by phone number card ────────────────────────────────────────
        _AddByPhoneCard(
          controller: _phoneCtrl,
          searching: _phoneSearching,
          result: _phoneResult,
          error: _phoneError,
          onSearch: _searchByPhone,
          onChat: _openChat,
          onSave: _saveToContacts,
          colors: _colors,
        ),

        // ── Divider ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Expanded(child: Divider(color: Colors.white.withAlpha(30))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('YOUR CONTACTS ON ZCHAT',
                style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            ),
            Expanded(child: Divider(color: Colors.white.withAlpha(30))),
          ]),
        ),

        // ── Contacts list ────────────────────────────────────────────────────
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2)),
          )
        else if (_error.isNotEmpty)
          _ErrorView(error: _error, onRetry: _loadContacts)
        else if (_zchatContacts.isEmpty)
          _EmptyView()
        else if (_filtered.isEmpty && _search.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No contacts match "$_search"',
              style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 14))),
          )
        else
          ..._filtered.asMap().entries.map((e) {
            final i = e.key;
            final u = e.value;
            final name  = u['contactName'] as String;
            final phone = u['phoneNumber'] as String? ?? '';
            final role  = u['role']        as String? ?? 'student';
            final color = _colors[name.codeUnitAt(0) % _colors.length];
            final photoUrl = u['photoUrl'] as String? ?? '';

            return InkWell(
              onTap: () => _openChat(u),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withAlpha(10)))),
                child: Row(children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: color,
                    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.isEmpty
                        ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name,  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(phone, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: role == 'lecturer'
                          ? const Color(0xFF7C3AED).withAlpha(40)
                          : const Color(0xFF2563EB).withAlpha(40),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: role == 'lecturer'
                          ? const Color(0xFF7C3AED).withAlpha(80)
                          : const Color(0xFF2563EB).withAlpha(80)),
                    ),
                    child: Text(
                      role == 'lecturer' ? 'Lecturer' : 'Student',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: role == 'lecturer' ? const Color(0xFFB794F4) : const Color(0xFF93C5FD),
                      ),
                    ),
                  ),
                ]),
              ),
            ).animate(delay: (i * 20).ms).fadeIn();
          }),
      ],
    );
  }
}

// ── Add-by-phone card ─────────────────────────────────────────────────────────

class _AddByPhoneCard extends StatelessWidget {
  final TextEditingController controller;
  final bool searching;
  final Map<String, dynamic>? result;
  final String? error;
  final VoidCallback onSearch;
  final Future<void> Function(Map<String, dynamic>) onChat;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final List<Color> colors;

  const _AddByPhoneCard({
    required this.controller, required this.searching, required this.result,
    required this.error, required this.onSearch, required this.onChat,
    required this.onSave, required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withAlpha(30)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.person_add_rounded, color: Colors.white.withAlpha(180), size: 18),
                const SizedBox(width: 8),
                const Text('Add new contact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withAlpha(30)),
                    ),
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s\-]'))],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'e.g. 0971234567',
                        hintStyle: TextStyle(color: Colors.white.withAlpha(80), fontSize: 14),
                        prefixIcon: Icon(Icons.phone_outlined, color: Colors.white.withAlpha(140), size: 18),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (_) => onSearch(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: searching ? null : onSearch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withAlpha(searching ? 40 : 80),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(80)),
                    ),
                    child: searching
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Find', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ]),

              // Result
              if (result != null) ...[
                const SizedBox(height: 12),
                _PhoneResultTile(user: result!, colors: colors, onChat: onChat, onSave: onSave),
              ],

              // Error
              if (error != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: Colors.redAccent.withAlpha(200)),
                  const SizedBox(width: 6),
                  Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _PhoneResultTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final List<Color> colors;
  final Future<void> Function(Map<String, dynamic>) onChat;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _PhoneResultTile({required this.user, required this.colors, required this.onChat, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final name     = (user['contactName'] ?? user['displayName'] ?? 'ZCHAT User') as String;
    final phone    = user['phoneNumber'] as String? ?? '';
    final role     = user['role']  as String? ?? 'student';
    final photoUrl = user['photoUrl'] as String? ?? '';
    final color    = colors[name.codeUnitAt(0) % colors.length];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(50)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: color,
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty
              ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          Text(phone, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12)),
          const SizedBox(height: 2),
          Text(role == 'lecturer' ? '🎓 Lecturer' : '📚 Student',
            style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 11)),
        ])),
        // Save to contacts
        IconButton(
          icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF4F8AFF), size: 22),
          tooltip: 'Save to contacts',
          onPressed: () => onSave(user),
        ),
        // Open chat
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF4F8AFF), size: 22),
          tooltip: 'Start chat',
          onPressed: () => onChat(user),
        ),
      ]),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }
}

// ── Error / empty views ───────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.contacts_outlined, color: Colors.white.withAlpha(60), size: 48),
      const SizedBox(height: 16),
      Text(error, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 14, height: 1.5)),
      const SizedBox(height: 20),
      GestureDetector(
        onTap: onRetry,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withAlpha(60),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(80)),
          ),
          child: const Text('Try again', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ),
    ]),
  );
}

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.person_search_rounded, color: Colors.white.withAlpha(60), size: 48),
      const SizedBox(height: 16),
      const Text('None of your contacts are on ZCHAT yet.', textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text('Use "Add new contact" above to find anyone by phone number.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13, height: 1.5)),
    ]),
  );
}
