import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/chat_service.dart';
import '../../services/media_storage_service.dart';
import '../../utils/glass.dart';
import '../../utils/storage_errors.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});
  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  static const _colors = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
    Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
  ];

  // Step 0 = pick members, Step 1 = name + create
  int _step = 0;

  List<Map<String, dynamic>> _zchatContacts = [];
  List<Map<String, dynamic>> _filtered = [];
  final Set<String> _selectedUids = {};
  bool _loading = true;

  final _nameCtrl = TextEditingController();
  File? _groupAvatar;
  bool _creating = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    try {
      final status = await Permission.contacts.request();
      if (!status.isGranted) {
        setState(() => _loading = false);
        return;
      }
      final deviceContacts = await FlutterContacts.getAll(properties: ContactProperties.allProperties);
      final phones = deviceContacts
          .expand((c) => c.phones.map((p) =>
              p.number.replaceAll(RegExp(r'\s|-|\(|\)'), '')))
          .where((p) => p.isNotEmpty)
          .toSet();

      final snap = await FirebaseFirestore.instance.collection('users').get();
      final zchat = snap.docs
          .where((d) => d.id != _myUid)
          .map((d) {
            final data = d.data();
            final phone = (data['phoneNumber'] as String? ?? '')
                .replaceAll(RegExp(r'\s|-|\(|\)'), '');
            final onDevice = phones.any((p) =>
                p.endsWith(phone.replaceAll('+', '')) ||
                phone.endsWith(p.replaceAll('+', '')));
            // Find display name from device contacts
            String contactName = data['fullName'] as String?
                ?? data['displayName'] as String? ?? '';
            if (onDevice && contactName.isEmpty) {
              final match = deviceContacts.firstWhere(
                (c) => c.phones.any((p) =>
                    p.number.replaceAll(RegExp(r'\s|-|\(|\)'), '').endsWith(
                        phone.replaceAll('+', ''))),
                orElse: () => Contact(),
              );
              contactName = match.displayName ?? '';
            }
            return {
              ...data,
              'uid': d.id,
              'displayName': contactName.isNotEmpty ? contactName : phone,
              'onDevice': onDevice,
            };
          })
          .toList();

      zchat.sort((a, b) {
        final aOn = a['onDevice'] as bool? ?? false;
        final bOn = b['onDevice'] as bool? ?? false;
        if (aOn != bOn) return aOn ? -1 : 1;
        return (a['displayName'] as String)
            .compareTo(b['displayName'] as String);
      });

      if (mounted) {
        setState(() {
          _zchatContacts = zchat;
          _filtered = zchat;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? _zchatContacts
          : _zchatContacts.where((c) {
              final name = (c['displayName'] as String).toLowerCase();
              final phone = (c['phoneNumber'] as String? ?? '').toLowerCase();
              return name.contains(q.toLowerCase()) || phone.contains(q.toLowerCase());
            }).toList();
    });
  }

  void _toggleSelect(String uid) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedUids.contains(uid)) {
        _selectedUids.remove(uid);
      } else {
        _selectedUids.add(uid);
      }
    });
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 75, maxWidth: 512);
    if (picked != null && mounted) {
      setState(() => _groupAvatar = File(picked.path));
    }
  }

  Future<void> _createGroup() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selectedUids.isEmpty) return;
    setState(() => _creating = true);
    try {
      String photoUrl = '';
      if (_groupAvatar != null) {
        photoUrl = await MediaStorageService.uploadBytes(
          bytes: await _groupAvatar!.readAsBytes(),
          path: 'group_avatars/${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: 'image/jpeg',
        );
      }
      final chatId = await ChatService.createGroupChat(
          name, _selectedUids.toList(), photoUrl: photoUrl);
      if (mounted) {
        context.pushReplacement(
            '/chats/$chatId?name=${Uri.encodeComponent(name)}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyStorageError(e)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          _step == 0 ? _buildPickMembers() : _buildNameStep(),
        ]),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: AppBar(
            backgroundColor: Colors.white.withAlpha(12),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () {
                if (_step == 1) {
                  setState(() => _step = 0);
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Group',
                    style: TextStyle(color: Colors.white, fontSize: 17,
                        fontWeight: FontWeight.w700)),
                Text(
                  _step == 0
                      ? '${_selectedUids.length} selected'
                      : 'Add a group name',
                  style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12),
                ),
              ],
            ),
            actions: [
              if (_step == 0 && _selectedUids.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _step = 1),
                  child: const Text('Next',
                      style: TextStyle(color: Color(0xFF4F8AFF),
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickMembers() {
    return Column(children: [
      const SizedBox(height: kToolbarHeight + 44),

      // Selected chips
      if (_selectedUids.isNotEmpty) ...[
        SizedBox(
          height: 68,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: _selectedUids.map((uid) {
              final contact = _zchatContacts.firstWhere(
                  (c) => c['uid'] == uid,
                  orElse: () => {'displayName': uid});
              final name = contact['displayName'] as String? ?? uid;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  backgroundColor: const Color(0xFF2563EB).withAlpha(40),
                  side: const BorderSide(color: Color(0xFF4F8AFF), width: 1),
                  label: Text(name.split(' ').first,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                  onDeleted: () => _toggleSelect(uid),
                ),
              );
            }).toList(),
          ),
        ),
        Divider(color: Colors.white.withAlpha(14), height: 1),
      ],

      // Search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withAlpha(30)),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search contacts',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Colors.white.withAlpha(120), size: 20),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: _filter,
              ),
            ),
          ),
        ),
      ),

      // Contact list
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)))
            : _filtered.isEmpty
                ? Center(child: Text('No ZCHAT users found',
                    style: TextStyle(color: Colors.white.withAlpha(100))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final contact = _filtered[i];
                      final uid = contact['uid'] as String;
                      final name = contact['displayName'] as String? ?? '';
                      final phone = contact['phoneNumber'] as String? ?? '';
                      final selected = _selectedUids.contains(uid);
                      final color = _colors[name.isNotEmpty
                          ? name.codeUnitAt(0) % _colors.length : 0];

                      return ListTile(
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: color,
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ),
                            if (selected)
                              Positioned(
                                right: -2, bottom: -2,
                                child: Container(
                                  width: 18, height: 18,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2563EB),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 12),
                                ),
                              ),
                          ],
                        ),
                        title: Text(name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        subtitle: Text(phone,
                            style: TextStyle(
                                color: Colors.white.withAlpha(100), fontSize: 12)),
                        trailing: selected
                            ? const Icon(Icons.check_circle_rounded,
                                color: Color(0xFF2563EB), size: 22)
                            : Icon(Icons.circle_outlined,
                                color: Colors.white.withAlpha(60), size: 22),
                        onTap: () => _toggleSelect(uid),
                      );
                    },
                  ),
      ),
    ]);
  }

  Widget _buildNameStep() {
    return Column(children: [
      const SizedBox(height: kToolbarHeight + 60),
      // Group avatar
      Center(
        child: GestureDetector(
          onTap: _pickAvatar,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withAlpha(40),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(80), width: 2),
                  image: _groupAvatar != null
                      ? DecorationImage(image: FileImage(_groupAvatar!), fit: BoxFit.cover)
                      : null,
                ),
                child: _groupAvatar == null
                    ? const Icon(Icons.group_rounded, color: Color(0xFF4F8AFF), size: 44)
                    : null,
              ),
              Container(
                width: 26, height: 26,
                decoration: const BoxDecoration(
                  color: Color(0xFF2563EB), shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 32),
      // Group name input
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(35)),
              ),
              child: TextField(
                controller: _nameCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Group name',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                  prefixIcon: const Icon(Icons.group_rounded,
                      color: Color(0xFF4F8AFF), size: 22),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      // Members preview
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          '${_selectedUids.length} participant${_selectedUids.length == 1 ? '' : 's'}',
          style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13),
        ),
      ),
      const Spacer(),
      // Create button
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
        child: AnimatedOpacity(
          opacity: _nameCtrl.text.trim().isNotEmpty ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _nameCtrl.text.trim().isNotEmpty && !_creating
                  ? _createGroup : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _creating
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create Group',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    ]);
  }
}
