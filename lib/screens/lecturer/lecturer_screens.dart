import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../utils/glass.dart';
import '../../widgets/lecturer_bottom_nav_bar.dart';

class LecturerHomeScreen extends StatelessWidget {
  const LecturerHomeScreen({super.key});

  static const _chats = [
    _LecturerChat('CS 3201 Group', '12 new questions about tomorrow\'s test', '10:42', 12, true),
    _LecturerChat('Lecture Announcements', 'Draft announcement ready to send', '09:18', 3, true),
    _LecturerChat('Chanda Phiri', 'Sir, may I submit by 17:00?', 'Yesterday', 1, false),
    _LecturerChat('Study Squad', 'Students shared a past paper request', 'Tue', 0, true),
    _LecturerChat('Math 201 Class', 'Deadline reminder scheduled', 'Mon', 0, true),
  ];

  @override
  Widget build(BuildContext context) {
    return _LecturerScaffold(
      title: 'Lecturer Home',
      actions: [
        IconButton(icon: const Icon(Icons.search_rounded, color: Colors.white), onPressed: () {}),
        IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white), onPressed: () => context.push('/profile')),
      ],
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
        itemCount: _chats.length,
        itemBuilder: (context, index) {
          final chat = _chats[index];
          return _ChatRow(chat: chat, index: index);
        },
      ),
    );
  }
}

class LecturerCoursesScreen extends StatelessWidget {
  const LecturerCoursesScreen({super.key});

  static const _courses = [
    _Course('CS 3201', 'Data Structures', '124 students', '3 pending uploads', Color(0xFF2563EB)),
    _Course('CS 3305', 'Operating Systems', '98 students', 'Assignment closes Friday', Color(0xFF00695C)),
    _Course('CS 4101', 'Artificial Intelligence', '76 students', 'Quiz draft ready', Color(0xFF6A1B9A)),
  ];

  @override
  Widget build(BuildContext context) {
    return _LecturerScaffold(
      title: 'Courses',
      actions: [IconButton(icon: const Icon(Icons.add_rounded, color: Colors.white), onPressed: () {})],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
        children: [
          _SearchBox(hint: 'Search your courses'),
          const SizedBox(height: 14),
          for (var i = 0; i < _courses.length; i++)
            _CourseCard(course: _courses[i], index: i),
        ],
      ),
    );
  }
}

class LecturerClassroomScreen extends StatelessWidget {
  const LecturerClassroomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LecturerScaffold(
      title: 'Classroom',
      actions: [IconButton(icon: const Icon(Icons.history_rounded, color: Colors.white), onPressed: () {})],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
        children: [
          _LiveClassCard(),
          const SizedBox(height: 14),
          _ActionGrid(actions: const [
            _LecturerAction(Icons.present_to_all_rounded, 'Share screen', 'Mirror slides or demos'),
            _LecturerAction(Icons.fiber_manual_record_rounded, 'Record', 'Save session replay'),
            _LecturerAction(Icons.qr_code_2_rounded, 'Attendance', 'Generate class code'),
            _LecturerAction(Icons.upload_file_rounded, 'Resources', 'Send files to class'),
          ]),
        ],
      ),
    );
  }
}

class LecturerAiScreen extends StatelessWidget {
  const LecturerAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LecturerScaffold(
      title: 'AI Tools',
      actions: [IconButton(icon: const Icon(Icons.tune_rounded, color: Colors.white), onPressed: () {})],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
        children: [
          _AiPromptCard(),
          const SizedBox(height: 14),
          _ActionGrid(actions: const [
            _LecturerAction(Icons.quiz_outlined, 'Generate quiz', 'From topic or notes'),
            _LecturerAction(Icons.grading_rounded, 'Grade help', 'Rubric-based feedback'),
            _LecturerAction(Icons.summarize_outlined, 'Summarize', 'Class chat or PDFs'),
            _LecturerAction(Icons.campaign_outlined, 'Announcement', 'Clean up message tone'),
          ]),
        ],
      ),
    );
  }
}

class LecturerPlannerScreen extends StatelessWidget {
  const LecturerPlannerScreen({super.key});

  static const _items = [
    _PlanItem('Today, 14:00', 'Host CS 3201 live class', 'Classroom'),
    _PlanItem('Tomorrow', 'Assignment 2 deadline', 'CS 3305'),
    _PlanItem('Friday', 'Publish quiz feedback', 'AI'),
  ];

  @override
  Widget build(BuildContext context) {
    return _LecturerScaffold(
      title: 'Planner',
      actions: [IconButton(icon: const Icon(Icons.add_rounded, color: Colors.white), onPressed: () {})],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
        children: [
          _PlannerSummary(),
          const SizedBox(height: 14),
          for (var i = 0; i < _items.length; i++)
            _PlanRow(item: _items[i], index: i),
        ],
      ),
    );
  }
}

class _LecturerScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;

  const _LecturerScaffold({
    required this.title,
    required this.child,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: const LecturerBottomNavBar(),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(
          children: [
            const GlowOrbs(),
            Column(
              children: [
                _LecturerAppBar(title: title, actions: actions),
                Expanded(child: child),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LecturerAppBar extends StatelessWidget {
  static const _brandAsset = 'assets/icons/zchat_logo_cutout.png';
  final String title;
  final List<Widget>? actions;

  const _LecturerAppBar({required this.title, this.actions});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(12),
            border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Image.asset(
                    _brandAsset,
                    width: 92,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text(
                      'ZCHAT',
                      style: TextStyle(color: Color(0xFF2EA3FF), fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (actions != null) ...actions!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final _LecturerChat chat;
  final int index;

  const _ChatRow({required this.chat, required this.index});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/chats/${Uri.encodeComponent(chat.name)}?name=${Uri.encodeComponent(chat.name)}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withAlpha(12)))),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: chat.group ? const Color(0xFF00695C) : const Color(0xFF6A1B9A),
              child: Icon(chat.group ? Icons.groups_rounded : Icons.person_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                      Text(chat.time, style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(chat.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12)),
                ],
              ),
            ),
            if (chat.unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                child: Text('${chat.unread}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    ).animate(delay: (index * 35).ms).fadeIn().slideY(begin: 0.05, end: 0);
  }
}

class _CourseCard extends StatelessWidget {
  final _Course course;
  final int index;

  const _CourseCard({required this.course, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: BorderRadius.circular(18),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: course.color.withAlpha(45), borderRadius: BorderRadius.circular(14), border: Border.all(color: course.color.withAlpha(85))),
              child: Center(child: Text(course.code.split(' ').first, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text('${course.code} - ${course.students}', style: TextStyle(color: Colors.white.withAlpha(155), fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(course.status, style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70), onPressed: () {}),
          ],
        ),
      ).animate(delay: (index * 50).ms).fadeIn().slideY(begin: 0.05, end: 0),
    );
  }
}

class _LiveClassCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(45), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.videocam_rounded, color: Color(0xFF93C5FD)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next live class', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    SizedBox(height: 3),
                    Text('CS 3201 - Today 14:00', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
              label: const Text('Start Class', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.04, end: 0);
  }
}

class _ActionGrid extends StatelessWidget {
  final List<_LecturerAction> actions;

  const _ActionGrid({required this.actions});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.22,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        return GlassCard(
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(action.icon, color: const Color(0xFF93C5FD), size: 26),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(action.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withAlpha(145), fontSize: 11)),
                ],
              ),
            ],
          ),
        ).animate(delay: (index * 45).ms).fadeIn().scale(begin: const Offset(0.97, 0.97));
      },
    );
  }
}

class _AiPromptCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF93C5FD)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ask AI to prepare lecturer material',
                hintStyle: TextStyle(color: Colors.white.withAlpha(105)),
                border: InputBorder.none,
                filled: false,
                isDense: true,
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.send_rounded, color: Color(0xFF4F8AFF)), onPressed: () {}),
        ],
      ),
    ).animate().fadeIn();
  }
}

class _PlannerSummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(16),
      child: const Row(
        children: [
          Icon(Icons.event_available_rounded, color: Color(0xFF93C5FD), size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text('3 upcoming lecturer tasks this week', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.04, end: 0);
  }
}

class _PlanRow extends StatelessWidget {
  final _PlanItem item;
  final int index;

  const _PlanRow({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassTile(
        leading: const Icon(Icons.schedule_rounded, color: Color(0xFF93C5FD)),
        title: Text(item.title),
        subtitle: Text('${item.time} - ${item.source}'),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
      ).animate(delay: (index * 45).ms).fadeIn().slideX(begin: 0.04, end: 0),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final String hint;

  const _SearchBox({required this.hint});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withAlpha(105)),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(155)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }
}

class _LecturerChat {
  final String name;
  final String message;
  final String time;
  final int unread;
  final bool group;

  const _LecturerChat(this.name, this.message, this.time, this.unread, this.group);
}

class _Course {
  final String code;
  final String name;
  final String students;
  final String status;
  final Color color;

  const _Course(this.code, this.name, this.students, this.status, this.color);
}

class _LecturerAction {
  final IconData icon;
  final String title;
  final String subtitle;

  const _LecturerAction(this.icon, this.title, this.subtitle);
}

class _PlanItem {
  final String time;
  final String title;
  final String source;

  const _PlanItem(this.time, this.title, this.source);
}
