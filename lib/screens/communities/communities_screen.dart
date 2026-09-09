import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/communities_service.dart';
import '../../utils/glass.dart';
import '../../widgets/bottom_nav_bar.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});
  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  String _university = '';

  @override
  void initState() {
    super.initState();
    _loadUni();
  }

  Future<void> _loadUni() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final d = (await FirebaseFirestore.instance.collection('users').doc(uid).get()).data() ?? {};
      if (mounted) setState(() => _university = (d['university'] as String?) ?? '');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        bottomNavigationBar: const AppBottomNavBar(),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF2563EB),
          onPressed: _showCreate,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('New', style: TextStyle(color: Colors.white)),
        ),
        body: Container(
          width: double.infinity, height: double.infinity,
          decoration: const BoxDecoration(gradient: kBgGradient),
          child: Stack(children: [
            const GlowOrbs(),
            Column(children: [
              _header(),
              Expanded(child: TabBarView(children: [_myTab(), _browseTab()])),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _header() => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(12),
          border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
        ),
        child: SafeArea(bottom: false, child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.go('/home')),
              const Text('Communities', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
          const TabBar(
            indicatorColor: Color(0xFF4F8AFF), indicatorWeight: 2.5,
            labelColor: Colors.white, unselectedLabelColor: Colors.white54,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [Tab(text: 'MY COMMUNITIES'), Tab(text: 'BROWSE')],
          ),
        ])),
      ),
    ),
  );

  Widget _myTab() => StreamBuilder<List<Map<String, dynamic>>>(
    stream: CommunitiesService.myCommunitiesStream(),
    builder: (ctx, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)));
      }
      final list = snap.data ?? [];
      if (list.isEmpty) return _empty('You haven\'t joined any communities yet.\nBrowse or create one.');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        itemCount: list.length,
        itemBuilder: (ctx, i) => _card(list[i], i, joined: true),
      );
    },
  );

  Widget _browseTab() => StreamBuilder<List<Map<String, dynamic>>>(
    stream: CommunitiesService.browseStream(university: _university.isEmpty ? null : _university),
    builder: (ctx, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)));
      }
      final list = snap.data ?? [];
      if (list.isEmpty) return _empty('No communities to join yet${_university.isNotEmpty ? ' for $_university' : ''}.');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        itemCount: list.length,
        itemBuilder: (ctx, i) => _card(list[i], i, joined: false),
      );
    },
  );

  Widget _card(Map<String, dynamic> c, int i, {required bool joined}) {
    final members = (c['memberUids'] as List?)?.length ?? 0;
    final subtitle = [c['school'], c['program']].where((s) => s != null && (s as String).isNotEmpty).join(' · ');
    return GlassCard(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: joined ? () => context.push('/communities/${c['id']}') : null,
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(45), borderRadius: BorderRadius.circular(14)),
            alignment: Alignment.center,
            child: Text(c['icon'] as String? ?? '🏛️', style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c['name'] as String? ?? 'Community', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('$members member${members == 1 ? '' : 's'}', style: TextStyle(color: Colors.white.withAlpha(110), fontSize: 11)),
          ])),
          const SizedBox(width: 8),
          if (joined)
            Icon(Icons.chevron_right_rounded, color: Colors.white.withAlpha(100))
          else
            GestureDetector(
              onTap: () async {
                await CommunitiesService.join(c['id'] as String);
                if (context.mounted) context.push('/communities/${c['id']}');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(20)),
                child: const Text('Join', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    ).animate(delay: (i * 30).ms).fadeIn().slideY(begin: 0.05, end: 0);
  }

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.groups_2_outlined, size: 56, color: Colors.white.withAlpha(50)),
        const SizedBox(height: 14),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(150), height: 1.5)),
      ]),
    ),
  );

  void _showCreate() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _CreateCommunitySheet(
          university: _university,
          onCreated: (id) => context.push('/communities/$id'),
        ),
      ),
    );
  }
}

// ── Create community sheet ──────────────────────────────────────────────────
class _CreateCommunitySheet extends StatefulWidget {
  final String university;
  final void Function(String id) onCreated;
  const _CreateCommunitySheet({required this.university, required this.onCreated});
  @override
  State<_CreateCommunitySheet> createState() => _CreateCommunitySheetState();
}

class _CreateCommunitySheetState extends State<_CreateCommunitySheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _school = TextEditingController();
  final _program = TextEditingController();
  String _icon = '🏛️';
  bool _saving = false;

  static const _icons = ['🏛️','💻','📐','⚗️','📚','⚖️','🩺','🎓','🔬','🏗️'];

  @override
  void dispose() { _name.dispose(); _desc.dispose(); _school.dispose(); _program.dispose(); super.dispose(); }

  Widget _field(TextEditingController c, String hint) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: Colors.white.withAlpha(16), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withAlpha(30))),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: TextField(controller: c, style: const TextStyle(color: Colors.white, fontSize: 14), onChanged: (_) => setState(() {}),
      decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.white.withAlpha(90)), border: InputBorder.none)),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        const Text('New community', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('An Announcements channel is created automatically.', style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 12)),
        const SizedBox(height: 12),
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, children: _icons.map((e) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _icon = e),
            child: Container(
              width: 44, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _icon == e ? const Color(0xFF2563EB).withAlpha(60) : Colors.white.withAlpha(14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _icon == e ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(25)),
              ),
              child: Text(e, style: const TextStyle(fontSize: 20)),
            ),
          ),
        )).toList())),
        const SizedBox(height: 12),
        _field(_name, 'Community name (e.g. BSc Computer Science)'),
        _field(_school, 'School (optional)'),
        _field(_program, 'Program (optional)'),
        _field(_desc, 'Description (optional)'),
        const SizedBox(height: 4),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: (_name.text.trim().isEmpty || _saving) ? null : () async {
            setState(() => _saving = true);
            final id = await CommunitiesService.createCommunity(
              name: _name.text.trim(),
              description: _desc.text.trim(),
              icon: _icon,
              university: widget.university,
              school: _school.text.trim(),
              program: _program.text.trim(),
            );
            if (context.mounted) { Navigator.pop(context); widget.onCreated(id); }
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), disabledBackgroundColor: const Color(0xFF2563EB).withAlpha(80), padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _saving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Create community', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        )),
      ])),
    ));
  }
}
