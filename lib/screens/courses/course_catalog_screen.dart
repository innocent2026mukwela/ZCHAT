import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/courses_service.dart';
import '../../utils/glass.dart';

/// Browse the course catalog (University → School → Program) and enrol.
class CourseCatalogScreen extends StatefulWidget {
  const CourseCatalogScreen({super.key});
  @override
  State<CourseCatalogScreen> createState() => _CourseCatalogScreenState();
}

class _CourseCatalogScreenState extends State<CourseCatalogScreen> {
  String _university = 'University of Zambia';
  String? _school;   // null = all schools
  String? _program;  // null = all programs
  String _search = '';

  Set<String> _enrolled = {};
  StreamSubscription? _enrolledSub;
  bool _loadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadProfileDefaults();
    _enrolledSub = CoursesService.enrolledCodesStream().listen((codes) {
      if (mounted) setState(() => _enrolled = codes);
    });
  }

  Future<void> _loadProfileDefaults() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final d = (await FirebaseFirestore.instance.collection('users').doc(uid).get()).data() ?? {};
        _university = (d['university'] as String?)?.trim().isNotEmpty == true
            ? d['university'] as String : _university;
        final school = (d['school'] as String?)?.trim();
        if (school != null && school.isNotEmpty) _school = school;
        final program = (d['program'] as String?)?.trim();
        if (program != null && program.isNotEmpty) _program = program;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingProfile = false);
  }

  @override
  void dispose() {
    _enrolledSub?.cancel();
    super.dispose();
  }

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
            _header(),
            if (_loadingProfile)
              const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF))))
            else
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: CoursesService.catalogStream(university: _university),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)));
                    }
                    final all = snap.data ?? [];
                    // Distinct schools / programs for the filter chips.
                    final schools = (all.map((c) => c['school'] as String? ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort());
                    final programs = (all
                        .where((c) => _school == null || (c['school'] as String? ?? '') == _school)
                        .expand((c) => (c['programs'] as List?)?.cast<String>() ?? const <String>[])
                        .toSet().toList()..sort());

                    var list = all.where((c) {
                      if (_school != null && (c['school'] as String? ?? '') != _school) return false;
                      if (_program != null &&
                          !(((c['programs'] as List?)?.cast<String>()) ?? const []).contains(_program)) return false;
                      if (_search.isNotEmpty) {
                        final q = _search.toLowerCase();
                        final code = (c['code'] as String? ?? '').toLowerCase();
                        final title = (c['title'] as String? ?? '').toLowerCase();
                        if (!code.contains(q) && !title.contains(q)) return false;
                      }
                      return true;
                    }).toList();

                    return Column(children: [
                      _filters(schools, programs),
                      Expanded(
                        child: list.isEmpty
                            ? _empty(all.isEmpty)
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: list.length,
                                itemBuilder: (ctx, i) => _courseCard(list[i], i),
                              ),
                      ),
                    ]);
                  },
                ),
              ),
          ]),
        ]),
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
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => context.pop(),
              ),
              const Expanded(child: Text('Course Catalog',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(children: [
              Icon(Icons.account_balance_outlined, size: 14, color: Colors.white.withAlpha(150)),
              const SizedBox(width: 6),
              Expanded(child: Text(_university,
                  style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withAlpha(35)),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by code or title…',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(160), size: 20),
                  border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                  filled: false, contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
        ])),
      ),
    ),
  );

  Widget _filters(List<String> schools, List<String> programs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (schools.isNotEmpty) _chipRow('School', schools, _school, (v) => setState(() { _school = v; _program = null; })),
      if (programs.isNotEmpty) _chipRow('Program', programs, _program, (v) => setState(() => _program = v)),
    ]);
  }

  Widget _chipRow(String label, List<String> options, String? selected, ValueChanged<String?> onPick) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip('All $label', selected == null, () => onPick(null)),
          ...options.map((o) => _chip(o, selected == o, () => onPick(o))),
        ],
      ),
    );
  }

  Widget _chip(String text, bool on, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF2563EB).withAlpha(60) : Colors.white.withAlpha(14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(30)),
        ),
        child: Text(text, style: TextStyle(
            color: on ? Colors.white : Colors.white.withAlpha(180),
            fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
      ),
    ),
  );

  Widget _courseCard(Map<String, dynamic> c, int i) {
    final code = c['code'] as String? ?? '';
    final enrolled = _enrolled.contains(code);
    final year = c['year'], sem = c['semester'];
    return GlassCard(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withAlpha(45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(70)),
          ),
          alignment: Alignment.center,
          child: Text(code, textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9EC5FF), fontWeight: FontWeight.w800, fontSize: 11)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['title'] as String? ?? code,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text([
            if (c['school'] != null) c['school'],
            if (year != null) 'Year $year',
            if (sem != null) 'Sem $sem',
          ].join(' · '),
              style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () async {
            if (enrolled) {
              await CoursesService.unenrol(code);
            } else {
              await CoursesService.enrol(c);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: enrolled ? Colors.white.withAlpha(18) : const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(20),
              border: enrolled ? Border.all(color: Colors.white.withAlpha(40)) : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(enrolled ? Icons.check_rounded : Icons.add_rounded,
                  size: 15, color: Colors.white),
              const SizedBox(width: 4),
              Text(enrolled ? 'Enrolled' : 'Enrol',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    ).animate(delay: (i * 30).ms).fadeIn().slideY(begin: 0.05, end: 0);
  }

  Widget _empty(bool catalogEmpty) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.menu_book_rounded, size: 56, color: Colors.white.withAlpha(50)),
        const SizedBox(height: 14),
        Text(
          catalogEmpty
              ? 'No courses in the catalog yet for $_university.'
              : 'No courses match your filters.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withAlpha(150), height: 1.5),
        ),
      ]),
    ),
  );
}
