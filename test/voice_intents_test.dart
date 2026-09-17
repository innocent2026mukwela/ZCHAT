import 'package:flutter_test/flutter_test.dart';
import 'package:unza_z_chat/services/voice_intents.dart';

void main() {
  group('VoiceIntents.parse', () {
    test('navigation commands map to routes', () {
      expect(VoiceIntents.parse('open planner').type, VoiceIntentType.navigate);
      expect(VoiceIntents.parse('open planner').route, '/planner');
      expect(VoiceIntents.parse('take me to zfeed').route, '/threads');
      expect(VoiceIntents.parse('open my chats').route, '/home');
      expect(VoiceIntents.parse('show my profile').route, '/profile');
    });

    test('read-messages, with and without a name', () {
      final all = VoiceIntents.parse('read my messages');
      expect(all.type, VoiceIntentType.readMessages);
      expect(all.nameFilter, isNull);

      final any = VoiceIntents.parse('any new messages?');
      expect(any.type, VoiceIntentType.readMessages);

      final named = VoiceIntents.parse('read my unread from chanda');
      expect(named.type, VoiceIntentType.readMessages);
      expect(named.nameFilter, 'chanda');
    });

    test('"read my messages" is not swallowed by the chats nav keyword', () {
      // Has the "messages" keyword but no nav verb → must be a read, not navigate.
      expect(VoiceIntents.parse('read my messages').type, VoiceIntentType.readMessages);
    });

    test('everything else falls through to assist', () {
      expect(VoiceIntents.parse('explain recursion').type, VoiceIntentType.assist);
      expect(VoiceIntents.parse('when is my next class').type, VoiceIntentType.assist);
      expect(VoiceIntents.parse('what is big o notation').type, VoiceIntentType.assist);
    });
  });
}
