import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The course catalog + the student's enrolments.
///
/// Catalog:    `courses/{CODE}`  — CODE (e.g. CSC3600) is the unique key, so the
///             same course can never appear twice with different spellings.
/// Enrolments: `users/{uid}/enrolments/{CODE}` — the courses a student takes.
///
/// Hierarchy for browsing: University → School → Program → Course.
class CoursesService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static String get _uid => _auth.currentUser!.uid;

  static final _catalog = _db.collection('courses');
  static CollectionReference<Map<String, dynamic>> get _enrolments =>
      _db.collection('users').doc(_uid).collection('enrolments');

  /// Canonical course code: uppercased, internal whitespace removed.
  /// "csc 3600" / "Csc3600" → "CSC3600".
  static String normalizeCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'\s+'), '').trim();

  // ── Catalog ────────────────────────────────────────────────────────────────

  /// Streams catalog courses for a university, ordered by code. School/program
  /// filtering is applied client-side (the catalog is small; avoids composite
  /// indexes). Pass [university] null to read the whole catalog.
  static Stream<List<Map<String, dynamic>>> catalogStream({
    String? university,
    String? school,
    String? program,
  }) {
    Query<Map<String, dynamic>> q = _catalog;
    if (university != null && university.isNotEmpty) {
      q = q.where('university', isEqualTo: university);
    }
    return q.snapshots().map((snap) {
      var list = snap.docs.map((d) => {...d.data(), 'code': d.id}).toList();
      if (school != null && school.isNotEmpty) {
        list = list.where((c) => (c['school'] as String? ?? '') == school).toList();
      }
      if (program != null && program.isNotEmpty) {
        list = list.where((c) {
          final progs = (c['programs'] as List?)?.cast<String>() ?? const [];
          return progs.contains(program);
        }).toList();
      }
      list.sort((a, b) => (a['code'] as String).compareTo(b['code'] as String));
      return list;
    });
  }

  /// Distinct schools present in the catalog for a university (for filter chips).
  static Future<List<String>> schoolsFor(String university) async {
    final snap = await _catalog.where('university', isEqualTo: university).get();
    final set = <String>{};
    for (final d in snap.docs) {
      final s = d.data()['school'] as String?;
      if (s != null && s.isNotEmpty) set.add(s);
    }
    final out = set.toList()..sort();
    return out;
  }

  /// Create/update a catalog course (lecturer/admin, or the seed importer).
  /// The doc id is the normalized code, guaranteeing no duplicates.
  static Future<void> upsertCourse(Map<String, dynamic> course) async {
    final code = normalizeCode(course['code'] as String? ?? '');
    if (code.isEmpty) throw Exception('A course code is required.');
    await _catalog.doc(code).set({
      ...course,
      'code': code,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Enrolments ───────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> enrolledStream() {
    return _enrolments.orderBy('code').snapshots().map(
        (s) => s.docs.map((d) => {...d.data(), 'code': d.id}).toList());
  }

  static Stream<Set<String>> enrolledCodesStream() {
    return _enrolments.snapshots().map((s) => s.docs.map((d) => d.id).toSet());
  }

  /// Enrol in a catalog course. Denormalises key fields for quick display.
  static Future<void> enrol(Map<String, dynamic> course) async {
    final code = normalizeCode(course['code'] as String? ?? '');
    if (code.isEmpty) return;
    await _enrolments.doc(code).set({
      'code':       code,
      'title':      course['title'] ?? '',
      'school':     course['school'] ?? '',
      'university': course['university'] ?? '',
      'programs':   course['programs'] ?? const [],
      'year':       course['year'],
      'semester':   course['semester'],
      'enrolledAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> unenrol(String code) async {
    await _enrolments.doc(normalizeCode(code)).delete();
  }

  /// A descriptive label for a course code — "CSC3600 Artificial Intelligence"
  /// — for AI prompts (a bare code is weak context). Checks the student's
  /// enrolment first, then the catalog; falls back to the code alone.
  static Future<String> descriptiveLabel(String code) async {
    final c = normalizeCode(code);
    if (c.isEmpty) return code;
    try {
      var doc = await _enrolments.doc(c).get();
      var title = doc.data()?['title'] as String?;
      if (title == null || title.isEmpty) {
        final cat = await _catalog.doc(c).get();
        title = cat.data()?['title'] as String?;
      }
      return (title != null && title.trim().isNotEmpty) ? '$c $title' : c;
    } catch (_) {
      return c;
    }
  }
}
