import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum CallType { voice, video }
enum CallStatus { calling, answered, declined, missed, ended }

class CallService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String get _myUid => _auth.currentUser!.uid;

  // ── Initiate a 1-to-1 call ────────────────────────────────────────────────

  static Future<String> initiateCall({
    required String calleeUid,
    required String calleeName,
    required CallType type,
  }) async {
    final caller     = _auth.currentUser!;
    final callerName = caller.displayName ?? 'Unknown';
    final roomId     = '${_myUid}_${calleeUid}_${DateTime.now().millisecondsSinceEpoch}';

    final doc = await _db.collection('calls').add({
      'callerUid':    _myUid,
      'callerName':   callerName,
      'calleeUid':    calleeUid,
      'calleeName':   calleeName,
      'participants': [_myUid, calleeUid],
      'participantNames': {_myUid: callerName, calleeUid: calleeName},
      'isGroup':      false,
      'roomId':       roomId,
      'type':         type == CallType.video ? 'video' : 'voice',
      'status':       'calling',
      'startedAt':    FieldValue.serverTimestamp(),
      'endedAt':      null,
      'duration':     null,
    });

    return doc.id;
  }

  // ── Initiate a group call ─────────────────────────────────────────────────

  static Future<String> initiateGroupCall({
    required List<String> calleeUids,
    required Map<String, String> calleeNames, // uid → name
    required CallType type,
    String? groupName,
  }) async {
    final caller     = _auth.currentUser!;
    final callerName = caller.displayName ?? 'Unknown';
    final roomId     = 'group_${_myUid}_${DateTime.now().millisecondsSinceEpoch}';

    final allUids   = [_myUid, ...calleeUids];
    final allNames  = {_myUid: callerName, ...calleeNames};

    final doc = await _db.collection('calls').add({
      'callerUid':        _myUid,
      'callerName':       callerName,
      'calleeUid':        calleeUids.isNotEmpty ? calleeUids.first : '',
      'calleeName':       groupName ?? calleeNames.values.take(2).join(', '),
      'participants':     allUids,
      'participantNames': allNames,
      'isGroup':          true,
      'groupName':        groupName ?? '$callerName & ${calleeNames.values.take(2).join(', ')}',
      'roomId':           roomId,
      'type':             type == CallType.video ? 'video' : 'voice',
      'status':           'calling',
      'startedAt':        FieldValue.serverTimestamp(),
      'endedAt':          null,
      'duration':         null,
    });

    return doc.id;
  }

  // ── Shared room ID for a call doc ─────────────────────────────────────────

  static String buildRoomId(String callDocId) => callDocId;

  // ── Update call status ────────────────────────────────────────────────────

  static Future<void> answerCall(String callId) async {
    await _db.collection('calls').doc(callId).update({'status': 'answered'});
  }

  static Future<void> endCall(String callId, {int durationSeconds = 0}) async {
    await _db.collection('calls').doc(callId).update({
      'status':  'ended',
      'endedAt': FieldValue.serverTimestamp(),
      'duration': durationSeconds,
    });
  }

  static Future<void> declineCall(String callId) async {
    await _db.collection('calls').doc(callId).update({'status': 'declined'});
  }

  static Future<void> deleteCallRecord(String callId) async {
    await _db.collection('calls').doc(callId).delete();
  }

  // ── Call history stream for current user ─────────────────────────────────

  static Stream<List<Map<String, dynamic>>> callHistoryStream() {
    return _db
        .collection('calls')
        .where(Filter.or(
          Filter('callerUid', isEqualTo: _myUid),
          Filter('calleeUid', isEqualTo: _myUid),
        ))
        .orderBy('startedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => {...d.data(), 'id': d.id}).toList());
  }

  // ── Incoming call stream for current user ─────────────────────────────────

  static Stream<Map<String, dynamic>?> incomingCallStream() {
    return _db
        .collection('calls')
        .where('calleeUid', isEqualTo: _myUid)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .map((s) => s.docs.isEmpty ? null : {...s.docs.first.data(), 'id': s.docs.first.id});
  }

  // ── Missed calls count stream ─────────────────────────────────────────────

  static Stream<int> missedCallsCountStream() {
    return _db
        .collection('calls')
        .where('calleeUid', isEqualTo: _myUid)
        .where('status', isEqualTo: 'missed')
        .snapshots()
        .map((s) => s.docs.length);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String formatDuration(int? seconds) {
    if (seconds == null || seconds == 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String formatCallTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt  = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return 'Today, $h:$m';
    }
    if (diff.inDays == 1) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return 'Yesterday, $h:$m';
    }
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${days[dt.weekday - 1]}, $h:$m';
  }
}
