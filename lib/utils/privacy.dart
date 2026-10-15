// Helpers for profile privacy settings stored on `users/{uid}`.

/// Returns [photoUrl] only when the owner's `privacyPhoto` allows the viewer
/// to see it. Options: `Everyone`, `My contacts`, `Nobody`.
///
/// [viewerIsContact] is true when the viewer shares a chat/group or appears
/// in the owner's device contacts. Callers that cannot resolve contact status
/// should pass `true` only for already-connected peers (open chat / shared group).
String? visiblePhotoUrl(
  Map<String, dynamic>? profile, {
  bool viewerIsContact = true,
}) {
  if (profile == null) return null;
  final url = (profile['photoUrl'] as String?)?.trim() ?? '';
  if (url.isEmpty) return null;
  final privacy = profile['privacyPhoto'] as String? ?? 'My contacts';
  switch (privacy) {
    case 'Nobody':
      return null;
    case 'Everyone':
      return url;
    case 'My contacts':
    default:
      return viewerIsContact ? url : null;
  }
}
