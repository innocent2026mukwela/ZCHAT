import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../utils/glass.dart';
import '../../widgets/bottom_nav_bar.dart';

// ── Colour palette cycled per course ─────────────────────────────────────────
const _kPalette = [
  Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFF2E7D32),
  Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
  Color(0xFF4527A0), Color(0xFF283593),
];

Color _colorFor(String subject) {
  final idx = subject.codeUnits.fold(0, (a, c) => a + c) % _kPalette.length;
  return _kPalette[idx];
}

// ── Service helper — reads unique subjects from timetable ─────────────────────
Stream<List<_Course>> _timetableCoursesStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.error('Not logged in');

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('timetable')
      .snapshots()
      .map((snap) {
    final seen  = <String>{};
    final out   = <_Course>[];
    for (final doc in snap.docs) {
      final d       = doc.data();
      final subject = (d['subject'] as String? ?? '').trim();
      final code    = (d['courseCode'] as String? ?? '').trim();
      if (subject.isEmpty || seen.contains(subject)) continue;
      seen.add(subject);
      out.add(_Course(
        subject:  subject,
        code:     code.isNotEmpty ? code : subject,
        type:     d['type']    as String? ?? 'Lecture',
        venue:    d['venue']   as String? ?? '',
        color:    _colorFor(subject),
      ));
    }
    out.sort((a, b) => a.subject.compareTo(b.subject));
    return out;
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CourseListScreen extends StatefulWidget {
  const CourseListScreen({super.key});
  @override
  State<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends State<CourseListScreen> {
  String _search = '';

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
            _buildHeader(),
            Expanded(
              child: StreamBuilder<List<_Course>>(
                stream: _timetableCoursesStream(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)));
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Could not load courses',
                        style: TextStyle(color: Colors.white.withAlpha(120))));
                  }
                  final all = snap.data ?? [];
                  if (all.isEmpty) return _buildEmpty(context);

                  final filtered = _search.isEmpty
                      ? all
                      : all.where((c) =>
                          c.subject.toLowerCase().contains(_search.toLowerCase()) ||
                          c.code.toLowerCase().contains(_search.toLowerCase())).toList();

                  if (filtered.isEmpty) {
                    return Center(child: Text('No match', style: TextStyle(color: Colors.white.withAlpha(120))));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => _CourseCard(
                      course: filtered[i],
                      index:  i,
                    ),
                  );
                },
              ),
            ),
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
          child: SafeArea(bottom: false, child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => context.go('/home'),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                const Text('My Courses', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => context.push('/planner'),
                  icon: const Icon(Icons.edit_calendar_outlined, size: 16, color: Color(0xFF4F8AFF)),
                  label: const Text('Manage', style: TextStyle(color: Color(0xFF4F8AFF), fontSize: 13)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
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
                        hintText: 'Search courses…',
                        hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                        prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(160), size: 20),
                        border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                        filled: false, contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ])),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.menu_book_rounded, size: 60, color: Colors.white.withAlpha(50)),
          const SizedBox(height: 16),
          const Text('No courses yet',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Courses are pulled from your timetable.\nAdd your class schedule in the Planner first.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withAlpha(140), height: 1.5),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.push('/planner'),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Go to Planner'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Course Card ───────────────────────────────────────────────────────────────

class _CourseCard extends StatelessWidget {
  final _Course course;
  final int     index;
  const _CourseCard({required this.course, required this.index});

  @override
  Widget build(BuildContext context) {
    final c = course;
    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        // Tap the card to open the course's past papers; the quick-action
        // buttons jump to Papers / AI Quiz.
        onTap: () => context.push('/courses/${Uri.encodeComponent(c.subject)}/papers'),
        child: Row(children: [
          // Icon block
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: c.color.withAlpha(50),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.color.withAlpha(80)),
            ),
            child: Center(child: Text(
              c.code.length > 6 ? c.code.substring(0, 4) : c.code.split(' ').first,
              style: TextStyle(color: c.color.withAlpha(220), fontWeight: FontWeight.w800, fontSize: 11),
              textAlign: TextAlign.center,
            )),
          ),
          const SizedBox(width: 14),
          // Name + meta
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.subject,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
              maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(c.type, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(160))),
              if (c.venue.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(Icons.location_on_outlined, size: 12, color: Colors.white.withAlpha(130)),
                const SizedBox(width: 2),
                Flexible(child: Text(c.venue,
                  style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(140)),
                  overflow: TextOverflow.ellipsis)),
              ],
            ]),
          ])),
          const SizedBox(width: 8),
          // Quick action buttons
          Column(children: [
            _ActionBtn(
              icon: Icons.picture_as_pdf_outlined,
              color: const Color(0xFFEF4444),
              onTap: () => context.push('/courses/${Uri.encodeComponent(c.subject)}/papers'),
            ),
            const SizedBox(height: 6),
            _ActionBtn(
              icon: Icons.psychology_alt_outlined,
              color: const Color(0xFFB794F4),
              onTap: () => context.push('/ai/quiz/${Uri.encodeComponent(c.subject)}'),
            ),
          ]),
        ]),
      ),
    ).animate(delay: (index * 40).ms).fadeIn().slideY(begin: 0.05, end: 0);
  }
}

// ── Model ─────────────────────────────────────────────────────────────────────

class _Course {
  final String subject, code, type, venue;
  final Color  color;
  const _Course({
    required this.subject,
    required this.code,
    required this.type,
    required this.venue,
    required this.color,
  });
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Icon(icon, color: color, size: 16),
    ),
  );
}
