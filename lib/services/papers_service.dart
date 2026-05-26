import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class PapersService {
  static final _db      = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;
  static final _auth    = FirebaseAuth.instance;

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

  /// Upload a PDF to Firebase Storage and save metadata in Firestore.
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

    // Upload file to Storage
    final storageRef = _storage
        .ref()
        .child('papers/$courseId/${year}_S${semester}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    final file = File(filePath);
    final uploadTask = await storageRef.putFile(
      file,
      SettableMetadata(contentType: 'application/pdf'),
    );
    final fileUrl  = await uploadTask.ref.getDownloadURL();
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
