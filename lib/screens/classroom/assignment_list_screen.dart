import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../utils/glass.dart';

class AssignmentListScreen extends StatefulWidget {
  final String courseId;
  const AssignmentListScreen({super.key, required this.courseId});
  @override
  State<AssignmentListScreen> createState() => _AssignmentListScreenState();
}

class _AssignmentListScreenState extends State<AssignmentListScreen> {
  String _filter = 'All';

  static Color _statusColor(String s) => switch (s) {
    'open'      => const Color(0xFFFBBF24),
    'submitted' => const Color(0xFF4F8AFF),
    'graded'    => const Color(0xFF86EFAC),
    _           => Colors.white54,
  };

  Stream<List<Map<String, dynamic>>> get _stream =>
      FirebaseFirestore.instance
          .collection('courses')
          .doc(widget.courseId)
          .collection('assignments')
          .orderBy('dueDate', descending: false)
          .snapshots()
          .map((s) => s.docs.map((d) {
                final data = d.data();
                data['id'] = d.id;
                return data;
              }).toList());

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> all) {
    if (_filter == 'All') return all;
    return all.where((a) => (a['status'] as String? ?? '') == _filter.toLowerCase()).toList();
  }

  void _showNewAssignmentSheet() {
    final titleCtrl = TextEditingController();
    final marksCtrl = TextEditingController(text: '20');
    DateTime dueDate = DateTime.now().add(const Duration(days: 7));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('New Assignment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 16),
          TextField(
            controller: titleCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Assignment title',
              labelStyle: TextStyle(color: Colors.white.withAlpha(160)),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withAlpha(40)), borderRadius: BorderRadius.circular(10)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4F8AFF)), borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: marksCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Total marks',
                  labelStyle: TextStyle(color: Colors.white.withAlpha(160)),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withAlpha(40)), borderRadius: BorderRadius.circular(10)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF4F8AFF)), borderRadius: BorderRadius.all(Radius.circular(10))),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: dueDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null) setSt(() => dueDate = d);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: Border.all(color: Colors.white.withAlpha(40)), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.schedule_rounded, color: Color(0xFF4F8AFF), size: 16),
                    const SizedBox(width: 6),
                    Text(DateFormat('MMM d').format(dueDate), style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                final marks = int.tryParse(marksCtrl.text.trim()) ?? 20;
                try {
                  await FirebaseFirestore.instance
                      .collection('courses').doc(widget.courseId)
                      .collection('assignments')
                      .add({
                        'title': title,
                        'dueDate': Timestamp.fromDate(dueDate),
                        'maxMarks': marks,
                        'status': 'open',
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Could not create assignment: ${e.toString().replaceFirst("Exception: ", "")}'),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                }
              },
              child: const Text('Create Assignment', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Column(children: [
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(color: Colors.white.withAlpha(12), border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20)))),
                  child: SafeArea(bottom: false, child: Column(children: [
                    Padding(padding: const EdgeInsets.fromLTRB(4, 8, 16, 0), child: Row(children: [
                      IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                      Expanded(child: Text('${widget.courseId} – Assignments', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
                    ])),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: ['All', 'Open', 'Submitted', 'Graded'].map((f) {
                          final sel = _filter == f;
                          return GestureDetector(
                            onTap: () => setState(() => _filter = f),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: sel ? const Color(0xFF2563EB) : Colors.white.withAlpha(18),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: sel ? const Color(0xFF2563EB) : Colors.white.withAlpha(35)),
                                boxShadow: sel ? [BoxShadow(color: const Color(0xFF2563EB).withAlpha(80), blurRadius: 10)] : [],
                              ),
                              child: Text(f, style: TextStyle(color: Colors.white, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
                            ),
                          );
                        }).toList()),
                      ),
                    ),
                  ])),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)));
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Could not load assignments',
                        style: TextStyle(color: Colors.white.withAlpha(140))));
                  }
                  final filtered = _applyFilter(snap.data ?? []);
                  if (filtered.isEmpty) {
                    return Center(child: Text(
                      _filter == 'All' ? 'No assignments yet' : 'No ${_filter.toLowerCase()} assignments',
                      style: TextStyle(color: Colors.white.withAlpha(140)),
                    ));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final a     = filtered[i];
                      final id    = a['id'] as String;
                      final title = a['title'] as String? ?? '';
                      final status = a['status'] as String? ?? 'open';
                      final marks  = a['maxMarks'] as int? ?? 0;
                      final ts     = a['dueDate'] as Timestamp?;
                      final due    = ts != null ? DateFormat('MMM d, HH:mm').format(ts.toDate()) : '—';
                      final color  = _statusColor(status);

                      return GlassCard(
                        borderRadius: BorderRadius.circular(14),
                        bgColor: status == 'open' ? const Color(0xFFFBBF24).withAlpha(10) : null,
                        borderColor: status == 'open' ? const Color(0xFFFBBF24).withAlpha(60) : null,
                        padding: const EdgeInsets.all(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            if (status == 'open')   context.push('/classroom/submit/$id');
                            else if (status == 'graded') context.push('/classroom/grades/$id');
                            else {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('Submitted — awaiting lecturer grade'),
                                behavior: SnackBarBehavior.floating,
                              ));
                            }
                          },
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withAlpha(60))),
                              child: Icon(Icons.assignment_outlined, color: color, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 5),
                              Row(children: [
                                Icon(Icons.schedule_rounded, size: 11, color: Colors.white.withAlpha(140)),
                                const SizedBox(width: 4),
                                Text('Due: $due', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(140))),
                                const SizedBox(width: 8),
                                Icon(Icons.star_outline_rounded, size: 11, color: Colors.white.withAlpha(140)),
                                const SizedBox(width: 3),
                                Text('$marks marks', style: TextStyle(fontSize: 12, color: Colors.white.withAlpha(140))),
                              ]),
                            ])),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withAlpha(60))),
                              child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
                            ),
                          ]),
                        ),
                      ).animate(delay: (i * 50).ms).fadeIn().slideY(begin: 0.05, end: 0);
                    },
                  );
                },
              ),
            ),
          ]),
          Positioned(
            bottom: 16, right: 16,
            child: FloatingActionButton.extended(
              backgroundColor: const Color(0xFF2563EB),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('New Assignment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              onPressed: _showNewAssignmentSheet,
            ),
          ),
        ]),
      ),
    );
  }
}
