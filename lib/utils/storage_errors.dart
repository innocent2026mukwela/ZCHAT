import '../config.dart';
import '../services/media_storage_service.dart';

/// Maps media-upload failures to a short, actionable message for demos.
String friendlyStorageError(Object error) {
  if (error is MediaStorageNotConfiguredException) {
    return 'Media storage not configured. Pass SUPABASE_URL and '
        'SUPABASE_ANON_KEY via --dart-define (see README).';
  }

  final raw = error.toString().replaceFirst('Exception: ', '');
  if (raw == 'Media storage not configured' ||
      raw.contains('Media storage not configured')) {
    return 'Media storage not configured. Pass SUPABASE_URL and '
        'SUPABASE_ANON_KEY via --dart-define (see README).';
  }
  if (raw.contains('row-level security') ||
      raw.contains('violates') ||
      raw.contains('Unauthorized') ||
      raw.contains('403') ||
      raw.contains('401')) {
    return 'Upload blocked by Supabase Storage policies. '
        'Allow insert/select on bucket "${AppConfig.supabaseBucket}" (see README).';
  }
  if (raw.contains('Bucket not found')) {
    return 'Storage bucket missing. Create a public bucket named '
        '"${AppConfig.supabaseBucket}" in the Supabase dashboard.';
  }
  return raw.isNotEmpty ? raw : 'Upload failed. Check your connection.';
}
