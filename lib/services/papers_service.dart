import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/storage_errors.dart';
import 'media_storage_service.dart';

class PapersService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static User get _me => _auth.currentUser!;

  /// Real-time stream of papers for a course, newest first.
  static Stream<List<Map<String, dynamic>>> papersStream(String courseId) {
    return _db
        .collection('papers')
        .where('courseId', isEqualTo: courseId)
        .orderBy('year', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {...d.data(), 'id': d.id}).toList());
  }

  /// Local cache path for a paper PDF (null on web).
  static Future<File?> localPaperFile(String paperId) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/papers/$paperId.pdf');
      if (await file.exists()) return file;
    } catch (_) {}
    return null;
  }

  /// Whether [paperId] is already cached on disk.
  static Future<bool> isCached(String paperId) async {
    final f = await localPaperFile(paperId);
    return f != null;
  }

  /// Opens a paper: local cache if present, otherwise download then open.
  /// On web, always opens the remote [fileUrl] in a new tab.
  /// Returns true if something was opened.
  static Future<bool> openPaper({
    required String paperId,
    required String fileUrl,
  }) async {
    if (kIsWeb || fileUrl.isEmpty) {
      final uri = Uri.tryParse(fileUrl);
      if (uri == null) return false;
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    }

    File? local = await localPaperFile(paperId);
    if (local == null) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final papersDir = Directory('${dir.path}/papers');
        if (!await papersDir.exists()) {
          await papersDir.create(recursive: true);
        }
        final dest = File('${papersDir.path}/$paperId.pdf');
        final res = await http
            .get(Uri.parse(fileUrl))
            .timeout(const Duration(seconds: 90));
        if (res.statusCode != 200) {
          // Fall back to opening the remote URL.
          final uri = Uri.parse(fileUrl);
          if (await canLaunchUrl(uri)) {
            return await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return false;
        }
        await dest.writeAsBytes(res.bodyBytes, flush: true);
        local = dest;
      } catch (_) {
        final uri = Uri.parse(fileUrl);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return false;
      }
    }

    // Prefer opening the local file; fall back to remote if the OS cannot
    // handle file:// (common on some Android configs without a FileProvider).
    final localUri = Uri.file(local.path);
    try {
      if (await canLaunchUrl(localUri)) {
        final ok = await launchUrl(localUri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      }
    } catch (_) {}

    final remote = Uri.parse(fileUrl);
    if (await canLaunchUrl(remote)) {
      return await launchUrl(remote, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Upload a PDF to Supabase Storage and save metadata in Firestore.
  /// Returns the Firestore document ID.
  static Future<String> uploadPaper({
    required String courseId,
    required String filePath,
    required String fileName,
    required int year,
    required int semester,
  }) async {
    final uid  = _me.uid;
    final name = _me.displayName ?? 'Student';

    final file = File(filePath);
    late final String fileUrl;
    try {
      fileUrl = await MediaStorageService.uploadFile(
        file: file,
        path: 'papers/$courseId/${year}_S${semester}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        contentType: 'application/pdf',
      );
    } catch (e) {
      throw Exception(friendlyStorageError(e));
    }
    final fileSizeBytes = await file.length();
    final fileSizeStr   = _formatSize(fileSizeBytes);

    // Save metadata to Firestore
    final doc = await _db.collection('papers').add({
      'courseId':     courseId,
      'year':         year,
      'semester':     semester,
      'uploadedBy':   uid,
      'uploaderName': name,
      'fileUrl':      fileUrl,
      'fileName':     fileName,
      'fileSize':     fileSizeStr,
      'verified':     false,
      'verifiedBy':   null,
      'downloads':    0,
      'createdAt':    FieldValue.serverTimestamp(),
    });

    return doc.id;
  }

  /// Verify a paper — only callable by lecturers (enforced via Firestore rules).
  static Future<void> verifyPaper(String paperId) async {
    await _db.collection('papers').doc(paperId).update({
      'verified':   true,
      'verifiedBy': _me.uid,
    });
  }

  /// Unverify a paper — lecturer can remove verification.
  static Future<void> unverifyPaper(String paperId) async {
    await _db.collection('papers').doc(paperId).update({
      'verified':   false,
      'verifiedBy': null,
    });
  }

  /// Increment download count.
  static Future<void> recordDownload(String paperId) async {
    await _db.collection('papers').doc(paperId).update({
      'downloads': FieldValue.increment(1),
    });
  }

  /// Returns true if a paper for the same course/year/semester already exists.
  static Future<bool> duplicateExists({
    required String courseId,
    required int year,
    required int semester,
  }) async {
    final snap = await _db
        .collection('papers')
        .where('courseId', isEqualTo: courseId)
        .where('year', isEqualTo: year)
        .where('semester', isEqualTo: semester)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Check if the current user is a lecturer.
  static Future<bool> isLecturer() async {
    final doc = await _db.collection('users').doc(_me.uid).get();
    return doc.data()?['role'] == 'lecturer';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
