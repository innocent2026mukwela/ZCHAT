import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../config.dart';

/// Handles all communication with the ZCHAT backend AI endpoints.
/// Change [_serverBase] to your production server URL when deploying.
/// 10.0.2.2 = Android emulator loopback to host machine.
/// For a physical device on the same Wi-Fi, use your machine's LAN IP.
class AiService {
  static const _serverBase = AppConfig.backendBase;
  static const _baseUrl    = '$_serverBase/api/ai';

  /// Fetches the current Firebase ID token and returns auth + content headers.
  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    return {
      'Content-Type':  'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Sends the full conversation history to Claude and returns the reply
  /// along with the conversation's ID (so follow-up turns can resume it).
  ///
  /// [messages] — the full chat so far, e.g.:
  ///   [{'role': 'user', 'content': 'Explain recursion'}, ...]
  ///
  /// [courseId] — optional active course; Claude uses it to call data tools
  ///   like grade lookups and deadline checks.
  ///
  /// [conversationId] — pass the ID returned from a previous call to append
  ///   to that conversation; omit to start a new one.
  ///
  /// Returns `{'reply': String, 'conversationId': String}`.
  static Future<Map<String, dynamic>> chat({
    required List<Map<String, dynamic>> messages,
    String? courseId,
    String? conversationId,
  }) async {
    final headers = await _authHeaders();
    final body = jsonEncode({
      'messages': messages,
      'courseId': courseId,
      'conversationId': conversationId,
    });

    final response = await http
        .post(Uri.parse('$_baseUrl/chat'), headers: headers, body: body)
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'reply': data['reply'] as String? ?? 'No response received.',
        'conversationId': data['conversationId'] as String?,
      };
    }
    try {
      final err = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(err['error'] ?? 'Request failed (${response.statusCode})');
    } catch (_) {
      throw Exception('Request failed (${response.statusCode})');
    }
  }

  /// Streaming version of [chat]. Yields events as Server-Sent-Events arrive:
  ///   {'delta': String}                         — a chunk of the reply
  ///   {'done': true, 'conversationId': String}  — final event
  ///   {'error': String}                          — failure mid-stream
  ///
  /// On mobile this streams token-by-token; on Flutter web the http client may
  /// buffer the response, so the reply can arrive in fewer, larger chunks.
  static Stream<Map<String, dynamic>> chatStream({
    required List<Map<String, dynamic>> messages,
    String? courseId,
    String? conversationId,
  }) async* {
    final headers = await _authHeaders();
    final req = http.Request('POST', Uri.parse('$_baseUrl/chat/stream'))
      ..headers.addAll(headers)
      ..body = jsonEncode({
        'messages': messages,
        'courseId': courseId,
        'conversationId': conversationId,
      });

    final client = http.Client();
    try {
      final resp = await client.send(req).timeout(const Duration(seconds: 90));
      if (resp.statusCode != 200) {
        yield {'error': 'Request failed (${resp.statusCode})'};
        return;
      }
      // Parse the SSE stream: lines of `data: {json}` separated by blank lines.
      final lines = resp.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        try {
          yield jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {/* ignore malformed keep-alive lines */}
      }
    } finally {
      client.close();
    }
  }

  /// Lists the user's recent AI conversations (most recently active first).
  /// Each entry has: id, title, last_question, last_answer, updated_at.
  static Future<List<Map<String, dynamic>>> fetchConversations() async {
    final headers = await _authHeaders();
    final response = await http
        .get(Uri.parse('$_baseUrl/conversations'), headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['conversations'] as List? ?? []);
    }
    throw Exception('Could not fetch conversations');
  }

  /// Fetches the full message history for a conversation, ready to drop
  /// straight into the chat screen's history array.
  /// Returns `{'conversationId': String, 'title': String?, 'messages': [...]}`.
  static Future<Map<String, dynamic>> fetchConversation(String id) async {
    final headers = await _authHeaders();
    final response = await http
        .get(Uri.parse('$_baseUrl/conversations/$id'), headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Could not fetch conversation');
  }

  /// Generates a multiple-choice quiz from a past paper stored in the backend.
  /// Returns a list of question maps: [{question, options, answer}].
  static Future<List<Map<String, dynamic>>> generateQuiz({
    required String paperId,
    required String courseCode,
    int numQuestions = 5,
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$_baseUrl/quiz'),
      headers: headers,
      body: jsonEncode({
        'paperId':      paperId,
        'courseCode':   courseCode,
        'numQuestions': numQuestions,
      }),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['questions'] as List? ?? []);
    }
    throw Exception('Quiz generation failed');
  }

  /// Fetches the user's past Q&A history from the database.
  /// Optionally filtered by [courseId].
  static Future<List<Map<String, dynamic>>> fetchHistory({
    String? courseId,
    int limit = 20,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl/history').replace(queryParameters: {
      'limit': limit.toString(),
      'courseId': courseId,
    });
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['history'] as List? ?? []);
    }
    throw Exception('Could not fetch history');
  }

  /// Generates AI course summary cards for [courseId].
  static Future<List<Map<String, dynamic>>> generateCourseSummary({
    required String courseId,
    int numTopics = 4,
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$_baseUrl/summary'),
      headers: headers,
      body: jsonEncode({'courseId': courseId, 'numTopics': numTopics}),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['summaries'] as List? ?? []);
    }
    throw Exception('Summary generation failed');
  }

  /// Generates exam-style MCQ questions for [courseCode].
  static Future<List<Map<String, dynamic>>> generateExamQuestions({
    required String courseCode,
    int numQuestions = 5,
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$_baseUrl/exam-questions'),
      headers: headers,
      body: jsonEncode({'courseCode': courseCode, 'numQuestions': numQuestions}),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['questions'] as List? ?? []);
    }
    throw Exception('Exam question generation failed');
  }

  /// Generates a personalised adaptive study plan.
  static Future<List<Map<String, dynamic>>> generateAdaptivePlan({
    required String courseId,
    List<String> weakTopics = const [],
    Map<String, dynamic> scores = const {},
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$_baseUrl/adaptive-plan'),
      headers: headers,
      body: jsonEncode({'courseId': courseId, 'weakTopics': weakTopics, 'scores': scores}),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['plan'] as List? ?? []);
    }
    throw Exception('Adaptive plan generation failed');
  }

  /// Sends a push notification to [recipientUid] via the backend.
  static Future<void> sendNotification({
    required String recipientUid,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    final headers = await _authHeaders();
    await http
        .post(
          Uri.parse('$_serverBase/api/notifications/send'),
          headers: headers,
          body: jsonEncode({'uid': recipientUid, 'title': title, 'body': body, 'data': data}),
        )
        .timeout(const Duration(seconds: 10));
  }

  /// Summarises a list of chat messages (plain strings) using Claude.
  /// Returns a summary string with bullet points.
  static Future<String> summarizeChat({
    required List<String> messages,
    String chatName = 'this conversation',
  }) async {
    final headers = await _authHeaders();
    final transcript = messages.join('\n');
    final response = await http.post(
      Uri.parse('$_baseUrl/chat'),
      headers: headers,
      body: jsonEncode({
        'messages': [
          {
            'role': 'user',
            'content':
                'You are a helpful assistant. Summarise the following group chat named "$chatName" '
                'into 3–5 concise bullet points highlighting key decisions, action items, and important '
                'information. Format each bullet starting with "• ". Keep each bullet under 20 words.\n\n'
                'Chat transcript:\n$transcript',
          }
        ],
      }),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['reply'] as String? ?? 'Could not generate summary.';
    }
    throw Exception('Summary request failed (${response.statusCode})');
  }

  /// Gets AI feedback on a submitted assignment text.
  static Future<Map<String, dynamic>> getAssignmentFeedback({
    required String submissionText,
    String assignmentTitle = 'Assignment',
    int totalMarks = 100,
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$_baseUrl/feedback'),
      headers: headers,
      body: jsonEncode({
        'submissionText': submissionText,
        'assignmentTitle': assignmentTitle,
        'totalMarks': totalMarks,
      }),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['feedback'] as Map<String, dynamic>? ?? {};
    }
    throw Exception('Feedback generation failed');
  }
}
