// Utility helpers

/// Normalizes a raw device-contact phone number to E.164.
///
/// Numbers that already include a country code (with `+` or a leading
/// `00`) are preserved as-is. Local-format numbers (9 digits, or 10
/// digits starting with `0`) are assumed to be Zambian and get a `+260`
/// prefix. Any other number with a plausible international length is
/// kept with a `+` rather than dropped, so contacts with foreign numbers
/// don't silently disappear from the list.
String toE164(String raw) {
  final trimmed = raw.trim();
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';

  if (trimmed.startsWith('+')) return '+$digits';
  if (digits.startsWith('00') && digits.length > 10) return '+${digits.substring(2)}';

  if (digits.startsWith('260') && digits.length == 12) return '+$digits';
  if (digits.startsWith('0') && digits.length == 10) return '+260${digits.substring(1)}';
  if (digits.length == 9) return '+260$digits';

  if (digits.length >= 10) return '+$digits';

  return '';
}
