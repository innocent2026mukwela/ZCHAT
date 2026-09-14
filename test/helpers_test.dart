import 'package:flutter_test/flutter_test.dart';
import 'package:unza_z_chat/utils/helpers.dart';

void main() {
  group('toE164', () {
    test('keeps numbers that already have a + country code', () {
      expect(toE164('+260977991006'), '+260977991006');
      expect(toE164('+1 (555) 123-4567'), '+15551234567');
    });

    test('adds +260 to a 9-digit local Zambian number', () {
      expect(toE164('977991006'), '+260977991006');
    });

    test('adds +260 to a 10-digit number with a leading 0', () {
      expect(toE164('0977991006'), '+260977991006');
    });

    test('handles a 260-prefixed 12-digit number', () {
      expect(toE164('260977991006'), '+260977991006');
    });

    test('converts a 00 international prefix to +', () {
      expect(toE164('00260977991006'), '+260977991006');
    });

    test('strips spaces, dashes and parentheses', () {
      expect(toE164('097 799 1006'), '+260977991006');
    });

    test('returns empty for empty or too-short input', () {
      expect(toE164(''), '');
      expect(toE164('   '), '');
      expect(toE164('123'), '');
    });

    test('keeps a plausible foreign number with a +', () {
      expect(toE164('447911123456'), '+447911123456');
    });
  });
}
