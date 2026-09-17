/// On-device intent router for the "Hey Zee" voice assistant.
///
/// Navigation and "read my messages" are a small, fixed command set, so we match
/// them locally — faster, offline, and no backend round-trip. Everything else
/// falls through to [VoiceIntentType.assist] and is answered by ZChat AI.
library;

enum VoiceIntentType { navigate, readMessages, assist }

class VoiceIntent {
  final VoiceIntentType type;
  final String? route;      // navigate: GoRouter path
  final String? routeLabel; // navigate: spoken label, e.g. "Planner"
  final String? nameFilter; // readMessages: a person/group name, or null = all
  const VoiceIntent(this.type, {this.route, this.routeLabel, this.nameFilter});
}

class VoiceIntents {
  // (keywords, route, spoken label). First keyword hit wins.
  static const List<(List<String>, String, String)> _nav = [
    (['planner', 'schedule', 'timetable', 'calendar'], '/planner', 'Planner'),
    (['zfeed', 'z feed', 'feed', 'threads'], '/threads', 'zFeed'),
    (['profile', 'my account'], '/profile', 'Profile'),
    (['call log', 'call history', 'calls'], '/calls', 'Calls'),
    (['communities', 'community'], '/communities', 'Communities'),
    (['courses', 'catalogue', 'catalog', 'my courses'], '/courses', 'Courses'),
    (['assistant', 'chat bot', 'chatbot', 'zee ai', 'ai chat'], '/ai/assistant', 'ZChat AI'),
    (['chats', 'messages', 'conversations', 'inbox', 'home'], '/home', 'Chats'),
  ];

  static final RegExp _navVerb =
      RegExp(r'\b(open|show|go to|goto|take me to|navigate to|launch|bring up)\b');
  static final RegExp _readVerb =
      RegExp(r'\b(read|catch me up on|any new)\b');
  static final RegExp _readNoun =
      RegExp(r'\b(messages?|texts?|unread|chats?|dms?)\b');
  static final RegExp _fromName = RegExp(r'from ([a-z0-9 .&_-]{2,})$');

  /// Parse a spoken command into an intent. Read is checked before navigation so
  /// "read my messages" isn't captured by the "messages" nav keyword.
  static VoiceIntent parse(String raw) {
    final t = raw.toLowerCase().trim().replaceAll(RegExp(r'[?.!]+$'), '');

    // "read my messages", "read my unread from Chanda", "any new messages"
    if (_readVerb.hasMatch(t) && _readNoun.hasMatch(t)) {
      final m = _fromName.firstMatch(t);
      final name = m?.group(1)?.trim();
      return VoiceIntent(VoiceIntentType.readMessages, nameFilter: (name != null && name.isNotEmpty) ? name : null);
    }

    // "open planner", "take me to zfeed"
    if (_navVerb.hasMatch(t)) {
      for (final entry in _nav) {
        for (final kw in entry.$1) {
          if (t.contains(kw)) {
            return VoiceIntent(VoiceIntentType.navigate, route: entry.$2, routeLabel: entry.$3);
          }
        }
      }
    }

    return const VoiceIntent(VoiceIntentType.assist);
  }
}
