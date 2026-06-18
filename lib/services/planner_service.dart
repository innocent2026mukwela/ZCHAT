import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ── Local notification setup ──────────────────────────────────────────────────

final _notif = FlutterLocalNotificationsPlugin();
bool _notifInitialised = false;

Future<void> initLocalNotifications() async {
  if (_notifInitialised) return;
  tz.initializeTimeZones();
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios    = DarwinInitializationSettings();
  await _notif.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );
  _notifInitialised = true;
}

// ── Planner service ───────────────────────────────────────────────────────────

class PlannerService {
  static final _db  = FirebaseFirestore.instance;
  static String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // ── Collections ──────────────────────────────────────────────────────────

  static CollectionReference get _timetable =>
      _db.collection('users').doc(_uid).collection('timetable');

  static CollectionReference get _studyPlans =>
      _db.collection('users').doc(_uid).collection('studyPlans');

  static CollectionReference get _studyGuides =>
      _db.collection('users').doc(_uid).collection('studyGuides');

  // ── Timetable ─────────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> timetableStream() =>
      _timetable.snapshots().map((s) {
        final docs = s.docs.map((d) => <String, dynamic>{'id': d.id, ...(d.data() as Map<String, dynamic>)}).toList();
        docs.sort((a, b) {
          final dCmp = (a['dayIndex'] as int? ?? 0).compareTo(b['dayIndex'] as int? ?? 0);
          if (dCmp != 0) return dCmp;
          return (a['startTime'] as String? ?? '').compareTo(b['startTime'] as String? ?? '');
        });
        return docs;
      });

  static Future<void> addTimetableSlot(Map<String, dynamic> data) async {
    final doc = await _timetable.add({...data, 'createdAt': FieldValue.serverTimestamp()});
    if (data['reminder'] == true) {
      await _scheduleWeeklyReminder(doc.id, data);
    }
  }

  static Future<void> updateTimetableSlot(String id, Map<String, dynamic> data) async {
    await _timetable.doc(id).update({...data, 'updatedAt': FieldValue.serverTimestamp()});
    if (_notifInitialised) await _notif.cancel(_notifId('t', id));
    if (data['reminder'] == true) await _scheduleWeeklyReminder(id, data);
  }

  static Future<void> deleteTimetableSlot(String id) async {
    await _timetable.doc(id).delete();
    if (_notifInitialised) await _notif.cancel(_notifId('t', id));
  }

  // ── Study Plans ───────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> studyPlansStream() =>
      _studyPlans.snapshots().map((s) {
        final docs = s.docs.map((d) => <String, dynamic>{'id': d.id, ...(d.data() as Map<String, dynamic>)}).toList();
        docs.sort((a, b) {
          final at = (a['dateTime'] as dynamic)?.millisecondsSinceEpoch as int? ?? 0;
          final bt = (b['dateTime'] as dynamic)?.millisecondsSinceEpoch as int? ?? 0;
          return at.compareTo(bt);
        });
        return docs;
      });

  static Future<void> addStudyPlan(Map<String, dynamic> data) async {
    final doc = await _studyPlans.add({...data, 'done': false, 'createdAt': FieldValue.serverTimestamp()});
    if (data['reminder'] == true && data['dateTime'] != null) {
      await _scheduleOneTimeReminder(doc.id, data);
    }
  }

  static Future<void> updateStudyPlan(String id, Map<String, dynamic> data) async {
    await _studyPlans.doc(id).update({...data, 'updatedAt': FieldValue.serverTimestamp()});
    if (_notifInitialised) await _notif.cancel(_notifId('s', id));
    if (data['reminder'] == true && data['dateTime'] != null) {
      await _scheduleOneTimeReminder(id, data);
    }
  }

  static Future<void> toggleStudyPlanDone(String id, bool done) async {
    await _studyPlans.doc(id).update({'done': done});
  }

  static Future<void> deleteStudyPlan(String id) async {
    await _studyPlans.doc(id).delete();
    if (_notifInitialised) await _notif.cancel(_notifId('s', id));
  }

  // ── Study Guides ──────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> studyGuidesStream() =>
      _studyGuides.snapshots().map((s) {
        final docs = s.docs.map((d) => <String, dynamic>{'id': d.id, ...(d.data() as Map<String, dynamic>)}).toList();
        docs.sort((a, b) {
          final at = (a['createdAt'] as dynamic)?.millisecondsSinceEpoch as int? ?? 0;
          final bt = (b['createdAt'] as dynamic)?.millisecondsSinceEpoch as int? ?? 0;
          return bt.compareTo(at);
        });
        return docs;
      });

  static Future<void> addStudyGuide(Map<String, dynamic> data) async {
    await _studyGuides.add({...data, 'createdAt': FieldValue.serverTimestamp()});
  }

  static Future<void> updateStudyGuide(String id, Map<String, dynamic> data) async {
    await _studyGuides.doc(id).update({...data, 'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> deleteStudyGuide(String id) async {
    await _studyGuides.doc(id).delete();
  }

  // ── Notification helpers ──────────────────────────────────────────────────

  static int _notifId(String prefix, String docId) =>
      (prefix + docId).hashCode.abs() % 100000;

  // Note: matchDateTimeComponents.dayOfWeekAndTime fires at the wall-clock time
  // stored at scheduling time. If the device observes DST, reminders may fire
  // 1 hour early or late on the changeover weekend — this is a known limitation
  // of the flutter_local_notifications zonedSchedule API.
  static Future<void> _scheduleWeeklyReminder(String id, Map<String, dynamic> data) async {
    try {
      final dayIndex  = data['dayIndex'] as int? ?? 1;  // 1=Mon … 7=Sun
      final startTime = data['startTime'] as String? ?? '08:00';
      final parts     = startTime.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m)
          .subtract(const Duration(minutes: 10));
      // Advance to the correct weekday
      while (scheduled.weekday != dayIndex || scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      await _notif.zonedSchedule(
        _notifId('t', id),
        data['subject'] as String? ?? 'Class Reminder',
        '${data['subject']} starts in 10 minutes · ${data['venue'] ?? ''}',
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails('zchat_planner', 'ZCHAT Planner',
              importance: Importance.high, priority: Priority.high),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  static Future<void> _scheduleOneTimeReminder(String id, Map<String, dynamic> data) async {
    try {
      final ts = data['dateTime'] as Timestamp?;
      if (ts == null) return;
      final dt = ts.toDate().subtract(const Duration(minutes: 10));
      if (dt.isBefore(DateTime.now())) return;
      final scheduled = tz.TZDateTime.from(dt, tz.local);
      await _notif.zonedSchedule(
        _notifId('s', id),
        data['topic'] as String? ?? 'Study Reminder',
        '${data['topic']} in 10 minutes',
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails('zchat_planner', 'ZCHAT Planner',
              importance: Importance.high, priority: Priority.high),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const dayIndexes = [1, 2, 3, 4, 5, 6, 7];
}
