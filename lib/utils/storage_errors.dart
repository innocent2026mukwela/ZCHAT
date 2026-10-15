import 'package:firebase_storage/firebase_storage.dart';

/// Maps Firebase Storage failures to a short, actionable message for demos.
String friendlyStorageError(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'unauthorized':
      case 'permission-denied':
        return 'Upload blocked by Storage rules. Deploy storage.rules '
            '(firebase deploy --only storage) so signed-in users can write '
            'chat_images, chat_videos, status, and related paths.';
      case 'object-not-found':
        return 'File not found in Storage.';
      case 'canceled':
        return 'Upload canceled.';
      case 'retry-limit-exceeded':
        return 'Upload failed after retries. Check your connection.';
      default:
        return error.message?.isNotEmpty == true
            ? error.message!
            : 'Storage error (${error.code}).';
    }
  }
  final raw = error.toString().replaceFirst('Exception: ', '');
  if (raw.contains('unauthorized') || raw.contains('permission-denied')) {
    return 'Upload blocked by Storage rules. Deploy storage.rules '
        '(firebase deploy --only storage) so signed-in users can write media.';
  }
  return raw;
}
