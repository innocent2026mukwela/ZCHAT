import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config.dart';
import '../../services/chat_service.dart';
import '../../services/users_api.dart';
import '../../utils/glass.dart';
import '../../utils/helpers.dart';
import '../../utils/privacy.dart';

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

  // Static cache — survives widget rebuilds and screen pops/pushes.
  static List<_ContactEntry>? _cachedContacts;
  static Map<String, _ZchatUser> _cachedZchatMap = {};
  static List<_DemoPeer>? _cachedDemoPeers;

  List<_ContactEntry> _all      = [];
  List<_ContactEntry> _filtered = [];
  List<_DemoPeer> _demoPeers = [];
  List<_DemoPeer> _searchHits = [];

  // e164 → ZCHAT user data (uid, about, photoUrl, role)
  Map<String, _ZchatUser> _zchatMap = {};

  bool _loading         = true;
  bool _zchatChecking   = false;
  bool _demoLoading     = false;
  bool _searchingRemote = false;
  String _error         = '';
  String _search        = '';
  final Set<String> _checking = {};
  Timer? _searchDebounce;

  bool get _demoMode => AppConfig.demoAuth;

  @override
  void initState() {
    super.initState();
    if (_cachedDemoPeers != null) {
      _demoPeers = _cachedDemoPeers!;
    }
    if (_cachedContacts != null) {
      // Show cached data immediately — no spinner.
      _all      = _cachedContacts!;
      _filtered = _cachedContacts!;
      _zchatMap = _cachedZchatMap;
      _loading  = false;
      // Silently refresh in background.
      _loadContacts(silent: true);
    } else {
      _loadContacts();
    }
    if (_demoMode) _loadDemoPeers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadDemoPeers() async {
    if (!_demoMode) return;
    setState(() => _demoLoading = true);
    final peers = await UsersApi.listDemoPeers();
    final list = peers
        .map((u) => _DemoPeer(
              uid: u['uid'] as String? ?? '',
              name: (u['fullName'] as String?)?.trim().isNotEmpty == true
                  ? u['fullName'] as String
                  : (u['phoneNumber'] as String? ?? 'User'),
              phone: u['phoneNumber'] as String? ?? '',
              // Suggested contacts for discovery — treat as contacts except Nobody.
              photoUrl: visiblePhotoUrl(u, viewerIsContact: true) ?? '',
            ))
        .where((p) => p.uid.isNotEmpty)
        .toList();
    _cachedDemoPeers = list;
    if (mounted) setState(() { _demoPeers = list; _demoLoading = false; });
  }

  // ── Load ALL phone contacts ───────────────────────────────────────────────

  Future<void> _loadContacts({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = ''; });

    final status = silent
        ? await Permission.contacts.status
        : await Permission.contacts.request();
    if (!status.isGranted) {
      if (!silent && mounted) {
        setState(() {
          _loading = false;
          // Local-auth mode can still start chats via suggested contacts / search.
          _error = _demoMode
              ? ''
              : 'Contacts permission denied.\nEnable Contacts access for ZCHAT in Settings.';
        });
      }
      return;
    }

    final contacts = await FlutterContacts.getAll(properties: ContactProperties.allProperties);
    final List<_ContactEntry> entries = [];
    for (final c in contacts) {
      final name = c.displayName ?? '';
      final allE164s = c.phones
          .map((p) => toE164(p.number))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (allE164s.isEmpty) continue;
      final rawPhone = c.phones.firstWhere(
        (p) => toE164(p.number).isNotEmpty,
        orElse: () => c.phones.first,
      ).number;
      entries.add(_ContactEntry(
        displayName: name.isNotEmpty ? name : allE164s.first,
        e164: allE164s.first,
        raw: rawPhone,
        allE164s: allE164s,
      ));
    }
    entries.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    _cachedContacts = entries;

    if (mounted) {
      setState(() {
        _all      = entries;
        _filtered = _search.isEmpty
            ? entries
            : entries.where((e) =>
                e.displayName.toLowerCase().contains(_search.toLowerCase()) ||
                e.e164.contains(_search) || e.raw.contains(_search)).toList();
        if (!silent) _loading = false;
      });
    }

    // Batch-check which contacts are on ZCHAT (all phone numbers, in background)
    _batchCheckZchat(entries.expand((e) => e.allE164s).toList());
  }

  Future<void> _batchCheckZchat(List<String> phones) async {
    if (phones.isEmpty) return;
    setState(() => _zchatChecking = true);

    // Membership is resolved by the backend (source of truth for accounts),
    // which excludes the caller and only returns numbers we already have.
    final Map<String, _ZchatUser> result = {};
    final users = await UsersApi.checkContacts(phones);
    for (final u in users) {
      final phone = u['phoneNumber'] as String? ?? '';
      if (phone.isEmpty) continue;
      result[phone] = _ZchatUser(
        uid:      u['uid']      as String? ?? '',
        about:    '',
        photoUrl: visiblePhotoUrl(u, viewerIsContact: true) ?? '',
        role:     u['role']     as String? ?? 'student',
      );
    }

    _cachedZchatMap = result;
    if (mounted) setState(() { _zchatMap = result; _zchatChecking = false; });
  }

  void _onSearch(String q) {
    setState(() {
      _search   = q;
      _filtered = q.trim().isEmpty
          ? _all
          : _all.where((e) =>
              e.displayName.toLowerCase().contains(q.toLowerCase()) ||
              e.e164.contains(q) || e.raw.contains(q)).toList();
      if (q.trim().isEmpty) _searchHits = [];
    });

    _searchDebounce?.cancel();
    if (!_demoMode || q.trim().length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchDemoUsers(q.trim());
    });
  }

  Future<void> _searchDemoUsers(String q) async {
    if (!mounted) return;
    setState(() => _searchingRemote = true);
    final users = await UsersApi.searchUsersLocal(q);
    if (!mounted || _search != q) {
      if (mounted) setState(() => _searchingRemote = false);
      return;
    }
    final hits = users
        .map((u) => _DemoPeer(
              uid: u['uid'] as String? ?? '',
              name: (u['fullName'] as String?)?.trim().isNotEmpty == true
                  ? u['fullName'] as String
                  : (u['phoneNumber'] as String? ?? 'User'),
              phone: u['phoneNumber'] as String? ?? '',
              // Free-text search hits are not assumed contacts.
              photoUrl: visiblePhotoUrl(u, viewerIsContact: false) ?? '',
            ))
        .where((p) => p.uid.isNotEmpty)
        .toList();
    setState(() { _searchHits = hits; _searchingRemote = false; });
  }

  // ── Tap → ZCHAT check → chat or invite ───────────────────────────────────

  _ZchatUser? _zchatForEntry(_ContactEntry entry) {
    for (final n in entry.allE164s) {
      final u = _zchatMap[n];
      if (u != null) return u;
    }
    return null;
  }

  Future<void> _onContactTap(_ContactEntry entry) async {
    // If we already know from batch check, use whichever number matched
    final known = _zchatForEntry(entry);
    if (known != null) {
      await _openChat(known.uid, entry.displayName);
      return;
    }

    if (_checking.contains(entry.e164)) return;
    setState(() => _checking.add(entry.e164));
    try {
      final users = await UsersApi.checkContacts(entry.allE164s);
      if (!mounted) return;
      if (users.isNotEmpty) {
        final u    = users.first;
        final name = (u['fullName'] as String?)?.trim().isNotEmpty == true
            ? u['fullName'] as String
            : entry.displayName;
        await _openChat(u['uid'] as String, name);
      } else {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _InviteScreen(contact: entry),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not check contact. Try again.'),
              behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _checking.remove(entry.e164));
    }
  }

  Future<void> _openChat(String uid, String name) async {
    final chatId = await ChatService.getOrCreateChat(uid);
    if (!mounted) return;
    context.pushReplacement(
      '/chats/${Uri.encodeComponent(chatId)}?name=${Uri.encodeComponent(name)}',
    );
  }

  // ── New contact (native) ──────────────────────────────────────────────────

  Future<void> _newContact() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) return;
    await FlutterContacts.native.showCreator();
    _loadContacts();
  }

  Future<void> _joinViaLink() async {
    final ctrl = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1829),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Join group via link', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Paste invite link (zchat://join?…)',
            hintStyle: TextStyle(color: Colors.white.withAlpha(90)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF4F8AFF))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(dctx, ctrl.text.trim()), child: const Text('Join', style: TextStyle(color: Color(0xFF4F8AFF)))),
        ],
      ),
    );
    if (link == null || link.isEmpty || !mounted) return;

    final uri = Uri.tryParse(link);
    final chatId = uri?.queryParameters['chatId'];
    final token  = uri?.queryParameters['token'];
    if (chatId == null || token == null || !link.contains('zchat://join')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('That doesn\'t look like a valid ZCHAT invite link.'), behavior: SnackBarBehavior.floating));
      return;
    }
    try {
      final result = await ChatService.joinViaInvite(chatId, token);
      if (!mounted) return;
      if (result == 'requested') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Request sent — an admin will approve you.'), behavior: SnackBarBehavior.floating));
      } else {
        context.pushReplacement('/chats/${Uri.encodeComponent(chatId)}?name=${Uri.encodeComponent('Group')}');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), behavior: SnackBarBehavior.floating));
    }
  }

  // ── QR Scan ───────────────────────────────────────────────────────────────

  void _openQrScan() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _QrScanScreen(
        onUidFound: (uid) async {
          Navigator.of(context).pop(); // close scanner
          // Look up user by uid
          try {
            final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
            if (!mounted) return;
            if (doc.exists) {
              final name = doc.data()?['fullName'] as String?
                        ?? doc.data()?['displayName'] as String?
                        ?? 'ZCHAT User';
              await _openChat(uid, name);
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User not found'),
                      behavior: SnackBarBehavior.floating),
                );
              }
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Lookup failed: ${e.toString().replaceFirst("Exception: ", "")}'),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ));
            }
          }
        },
      ),
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // ── Build ─────────────────────────────────────────────────────────────────

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
            _buildHeader(),
            Expanded(child: _buildBody()),
          ]),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRect(
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
                padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(child: Text('New Chat',
                    style: TextStyle(color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w700))),
                  if (_zchatChecking)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withAlpha(150))),
                    ),
                  IconButton(
                    icon: Icon(Icons.qr_code_scanner_rounded,
                        color: Colors.white.withAlpha(200)),
                    onPressed: _openQrScan,
                    tooltip: 'Scan QR code',
                  ),
                  if (!_loading)
                    IconButton(
                      icon: Icon(Icons.refresh_rounded,
                          color: Colors.white.withAlpha(180)),
                      onPressed: () {
                        _loadContacts();
                        if (_demoMode) _loadDemoPeers();
                      },
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
                          hintText: 'Search name or number…',
                          hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                          prefixIcon: Icon(Icons.search_rounded,
                              color: Colors.white.withAlpha(160)),
                          border: InputBorder.none, enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none, filled: false,
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
    );
  }

  Widget _buildBody() {
    if (_loading && !_demoMode) {
      return const Center(child: CircularProgressIndicator(
          color: Color(0xFF4F8AFF), strokeWidth: 2));
    }
    if (_error.isNotEmpty && !_demoMode) {
      return _ErrorView(error: _error, onRetry: _loadContacts);
    }

    // Build items: [New group, New contact] + demo peers + contacts
    final items = <_ListItem>[];
    items.add(_ListItem.action(
      icon: Icons.group_add_rounded, label: 'New group',
      onTap: () => context.push('/new-group'),
    ));
    items.add(_ListItem.action(
      icon: Icons.person_add_rounded, label: 'New contact',
      onTap: _newContact,
    ));
    items.add(_ListItem.action(
      icon: Icons.link_rounded, label: 'Join group via link',
      onTap: _joinViaLink,
    ));

    // Demo: searchable Firestore peers (works without contacts / backend).
    if (_demoMode) {
      final q = _search.trim().toLowerCase();
      final demoShown = q.isEmpty
          ? _demoPeers
          : [
              ..._searchHits,
              ..._demoPeers.where((p) =>
                  p.name.toLowerCase().contains(q) ||
                  p.phone.toLowerCase().contains(q)),
            ];
      // Deduplicate by uid (search hits may overlap demo list).
      final seen = <String>{};
      final uniqueDemo = <_DemoPeer>[];
      for (final p in demoShown) {
        if (seen.add(p.uid)) uniqueDemo.add(p);
      }

      if (_demoLoading && uniqueDemo.isEmpty) {
        items.add(_ListItem.sectionHeader('People on ZCHAT', 0));
      } else if (uniqueDemo.isNotEmpty) {
        items.add(_ListItem.sectionHeader(
            q.isEmpty ? 'People on ZCHAT' : 'Matching contacts', uniqueDemo.length));
        for (final p in uniqueDemo) {
          items.add(_ListItem.demoPeer(p));
        }
      } else if (q.isEmpty) {
        items.add(_ListItem.hint(
          'No other accounts yet. Sign in on a second device/browser '
          'with a different phone number to chat 1:1.',
        ));
      }
    }

    final onZchat = _filtered.where((e) => _zchatForEntry(e) != null).toList();
    final invite  = _filtered.where((e) => _zchatForEntry(e) == null).toList();

    if (onZchat.isNotEmpty) {
      items.add(_ListItem.sectionHeader('On ZCHAT', onZchat.length));
      for (final e in onZchat) { items.add(_ListItem.contact(e)); }
    }
    if (invite.isNotEmpty) {
      items.add(_ListItem.sectionHeader('Invite to ZCHAT', invite.length));
      for (final e in invite) { items.add(_ListItem.contact(e)); }
    }

    final hasDemoResults = _demoMode && (_demoPeers.isNotEmpty || _searchHits.isNotEmpty);
    if (_filtered.isEmpty && _search.isNotEmpty && !hasDemoResults && !_searchingRemote) {
      return Center(child: Text(
        'No contacts match "$_search"',
        style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14)));
    }
    if (_all.isEmpty && !_demoMode) return const _EmptyView();
    if (_all.isEmpty && _demoMode && items.length <= 3 && !_demoLoading) {
      // Only action rows — still show the list so the suggested-contacts hint is visible.
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        if (item.type == _ItemType.sectionHeader) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Row(children: [
              Text(item.label!,
                style: TextStyle(color: Colors.white.withAlpha(160),
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(width: 8),
              if (item.count != null && item.count! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${item.count}',
                    style: TextStyle(color: Colors.white.withAlpha(160),
                        fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              if (_demoLoading || _searchingRemote) ...[
                const SizedBox(width: 10),
                SizedBox(width: 12, height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: Colors.white.withAlpha(140))),
              ],
            ]),
          );
        }

        if (item.type == _ItemType.hint) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(item.label!,
              style: TextStyle(color: Colors.white.withAlpha(130),
                  fontSize: 13, height: 1.45)),
          );
        }

        if (item.type == _ItemType.action) {
          return InkWell(
            onTap: item.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withAlpha(50),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(60)),
                  ),
                  child: Icon(item.icon, color: const Color(0xFF4F8AFF), size: 22),
                ),
                const SizedBox(width: 14),
                Text(item.label!,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
            ),
          ).animate(delay: (index * 30).ms).fadeIn();
        }

        if (item.type == _ItemType.demoPeer) {
          final peer = item.demoPeer!;
          final color = _colors[peer.name.codeUnitAt(0) % _colors.length];
          return InkWell(
            onTap: () => _openChat(peer.uid, peer.name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withAlpha(8)))),
              child: Row(children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: color,
                  backgroundImage: peer.photoUrl.isNotEmpty
                      ? NetworkImage(peer.photoUrl) : null,
                  child: peer.photoUrl.isEmpty
                      ? Text(peer.name[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w700, fontSize: 16))
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(peer.name,
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w600, fontSize: 15)),
                    if (peer.phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(peer.phone,
                        style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 13)),
                    ],
                  ],
                )),
              ]),
            ),
          ).animate(delay: (index * 10).ms).fadeIn();
        }

        // Contact tile
        final entry       = item.entry!;
        final zchat       = _zchatForEntry(entry);
        final isOnZchat   = zchat != null;
        final color       = _colors[entry.displayName.codeUnitAt(0) % _colors.length];
        final isChecking  = _checking.contains(entry.e164);
        final photoUrl    = zchat?.photoUrl ?? '';
        final about       = zchat?.about ?? '';
        final subtitle    = isOnZchat && about.isNotEmpty ? about : entry.raw;

        return InkWell(
          onTap: isChecking ? null : () => _onContactTap(entry),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withAlpha(8)))),
            child: Row(children: [
              // Avatar
              Stack(children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: color,
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty
                      ? Text(entry.displayName[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w700, fontSize: 16))
                      : null,
                ),
                if (isOnZchat)
                  Positioned(
                    right: 0, bottom: 0,
                    child: Container(
                      width: 14, height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF0A1A4A), width: 1.5),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.displayName,
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 13)),
                ],
              )),
              if (isChecking)
                const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF4F8AFF)))
              else if (isOnZchat)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF22C55E).withAlpha(80)),
                  ),
                  child: const Text('ZCHAT',
                    style: TextStyle(color: Color(0xFF22C55E),
                        fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
        ).animate(delay: (index * 10).ms).fadeIn();
      },
    );
  }
}

// ── QR Scan Screen ────────────────────────────────────────────────────────────

class _QrScanScreen extends StatefulWidget {
  final void Function(String uid) onUidFound;
  const _QrScanScreen({required this.onUidFound});
  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  bool _handled = false;
  final MobileScannerController _ctrl = MobileScannerController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? '';
      // Expect: zchat://user/{uid}
      if (raw.startsWith('zchat://user/')) {
        _handled = true;
        final uid = raw.replaceFirst('zchat://user/', '').trim();
        if (uid.isNotEmpty) widget.onUidFound(uid);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _ctrl.toggleTorch(),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: _ctrl, onDetect: _onDetect),
        Center(
          child: Container(
            width: 240, height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF4F8AFF), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          bottom: 40, left: 0, right: 0,
          child: Center(
            child: Text('Scan a ZCHAT QR code',
              style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ── Invite Screen ─────────────────────────────────────────────────────────────

class _InviteScreen extends StatelessWidget {
  final _ContactEntry contact;
  const _InviteScreen({required this.contact});

  static const _inviteText =
      'Hey! I\'m using ZCHAT. '
      'Join me: https://zchat.unza.zm/download';

  Future<void> _sendSms(BuildContext context) async {
    final uri = Uri(scheme: 'sms', path: contact.e164,
        queryParameters: {'body': _inviteText});
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open SMS app'),
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _sendWhatsApp(BuildContext context) async {
    final num     = contact.e164.replaceAll('+', '');
    final encoded = Uri.encodeComponent(_inviteText);
    final uri     = Uri.parse('https://wa.me/$num?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp not installed'),
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = const [
      Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
      Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
    ][contact.displayName.codeUnitAt(0) % 6];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          SafeArea(child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Expanded(child: Text('Invite to ZCHAT',
                  style: TextStyle(color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w700))),
              ]),
            ),
            const SizedBox(height: 48),
            CircleAvatar(
              radius: 52, backgroundColor: color,
              child: Text(contact.displayName[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 36,
                    fontWeight: FontWeight.w700)),
            ).animate().scale(duration: 300.ms, curve: Curves.easeOut),
            const SizedBox(height: 20),
            Text(contact.displayName,
              style: const TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(contact.raw,
              style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 14)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.withAlpha(80)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
                SizedBox(width: 8),
                Text('Not on ZCHAT yet',
                  style: TextStyle(color: Colors.orange,
                      fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Invite ${contact.displayName.split(' ').first} to join ZCHAT.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withAlpha(160),
                    fontSize: 14, height: 1.6),
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('Send SMS Invite'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 15),
                  ),
                  onPressed: () => _sendSms(context),
                ),
              ),
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Invite via WhatsApp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700,
                        fontSize: 15),
                  ),
                  onPressed: () => _sendWhatsApp(context),
                ),
              ),
            ).animate().fadeIn(delay: 280.ms).slideY(begin: 0.2, end: 0),
          ])),
        ]),
      ),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────

class _ContactEntry {
  final String displayName, e164, raw;
  final List<String> allE164s;
  const _ContactEntry({required this.displayName, required this.e164,
      required this.raw, required this.allE164s});
}

class _ZchatUser {
  final String uid, about, photoUrl, role;
  const _ZchatUser({required this.uid, required this.about,
      required this.photoUrl, required this.role});
}

class _DemoPeer {
  final String uid, name, phone, photoUrl;
  const _DemoPeer({
    required this.uid,
    required this.name,
    required this.phone,
    required this.photoUrl,
  });
}

enum _ItemType { action, sectionHeader, contact, demoPeer, hint }

class _ListItem {
  final _ItemType type;
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final _ContactEntry? entry;
  final _DemoPeer? demoPeer;
  final int? count;

  const _ListItem._({required this.type, this.label,
      this.icon, this.onTap, this.entry, this.demoPeer, this.count});

  factory _ListItem.action({required IconData icon, required String label,
      required VoidCallback onTap}) =>
      _ListItem._(type: _ItemType.action, icon: icon, label: label, onTap: onTap);

  factory _ListItem.sectionHeader(String label, int count) =>
      _ListItem._(type: _ItemType.sectionHeader, label: label, count: count);

  factory _ListItem.contact(_ContactEntry entry) =>
      _ListItem._(type: _ItemType.contact, entry: entry);

  factory _ListItem.demoPeer(_DemoPeer peer) =>
      _ListItem._(type: _ItemType.demoPeer, demoPeer: peer);

  factory _ListItem.hint(String label) =>
      _ListItem._(type: _ItemType.hint, label: label);
}

// ── Error / Empty ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.contacts_outlined, color: Colors.white.withAlpha(60), size: 48),
        const SizedBox(height: 16),
        Text(error, textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withAlpha(140),
              fontSize: 14, height: 1.5)),
        const SizedBox(height: 20),
        Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () => openAppSettings(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withAlpha(60),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(80)),
              ),
              child: const Text('Open Settings',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withAlpha(40)),
              ),
              child: const Text('Try again',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ]),
    ),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.contacts_outlined, color: Colors.white.withAlpha(60), size: 48),
        const SizedBox(height: 16),
        const Text('No contacts found',
          style: TextStyle(color: Colors.white, fontSize: 15,
              fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Save contacts on your device to find them here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withAlpha(140),
              fontSize: 13, height: 1.5)),
      ]),
    ),
  );
}
