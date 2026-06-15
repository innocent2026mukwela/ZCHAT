import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/ai_service.dart';
import '../../utils/glass.dart';
import '../../widgets/bottom_nav_bar.dart';

/// "ZChat AI" hub — entry point for all AI academic-assistant features.
/// Shows recent conversations and quick links into each tool. Tools not
/// yet built render as "Coming soon" until their phase lands.
class AiHomeScreen extends StatefulWidget {
  const AiHomeScreen({super.key});
  @override
  State<AiHomeScreen> createState() => _AiHomeScreenState();
}

class _AiHomeScreenState extends State<AiHomeScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final convos = await AiService.fetchConversations();
      if (mounted) setState(() { _conversations = convos; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon 🚀'), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      safeArea: true,
      bottomNavigationBar: const AppBottomNavBar(),
      body: RefreshIndicator(
        color: const Color(0xFFB794F4),
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildNewChatButton(context),
            const SizedBox(height: 24),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: Color(0xFFB794F4))),
              )
            else if (_conversations.isNotEmpty) ..._buildRecentSection(context),
            const SizedBox(height: 24),
            _buildSectionTitle('Tools'),
            const SizedBox(height: 12),
            _buildToolsGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(children: [
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F8AFF)]),
          boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withAlpha(90), blurRadius: 18)],
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ZChat AI', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          Text('Your academic assistant', style: TextStyle(color: Color(0xFFB794F4), fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      ),
    ]).animate().fadeIn().slideY(begin: -0.05, end: 0);
  }

  Widget _buildNewChatButton(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/ai/chat'),
      child: GlassCard(
        borderRadius: BorderRadius.circular(18),
        bgColor: const Color(0xFF7C3AED),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.white.withAlpha(30), shape: BoxShape.circle),
            child: const Icon(Icons.add_comment_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New chat', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              Text('Ask anything about your courses', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
        ]),
      ),
    ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.06, end: 0);
  }

  List<Widget> _buildRecentSection(BuildContext context) {
    return [
      _buildSectionTitle('Recent conversations'),
      const SizedBox(height: 12),
      ...List.generate(_conversations.length, (i) {
        final c = _conversations[i];
        final title = (c['title'] as String?)?.trim();
        final preview = (c['last_question'] as String?)?.trim();
        final label = (title != null && title.isNotEmpty)
            ? title
            : (preview != null && preview.isNotEmpty ? preview : 'Conversation');
        final answer = (c['last_answer'] as String?)?.trim() ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: const Color(0xFF7C3AED).withAlpha(40), shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFB794F4), size: 18),
            ),
            title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: answer.isNotEmpty
                ? Text(answer, maxLines: 1, overflow: TextOverflow.ellipsis)
                : null,
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            onTap: () => context.push('/ai/chat', extra: c['id'] as String?),
          ),
        ).animate(delay: (i * 40).ms).fadeIn();
      }),
    ];
  }

  Widget _buildSectionTitle(String text) => Text(
    text,
    style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
  );

  Widget _buildToolsGrid(BuildContext context) {
    final tools = [
      _Tool('AI Chat', 'Ask questions & get help', Icons.smart_toy_rounded, const Color(0xFF7C3AED),
          () => context.push('/ai/chat')),
      _Tool('Practice Quiz', 'Test yourself with MCQs', Icons.quiz_rounded, const Color(0xFF2563EB),
          () => context.push('/ai/quiz/General')),
      _Tool('Course Summaries', 'AI-generated study cards', Icons.menu_book_rounded, const Color(0xFF0EA5E9),
          () => context.push('/ai/summaries/General')),
      _Tool('Past Paper Analyzer', 'Spot exam patterns', Icons.description_rounded, const Color(0xFF16A34A),
          () => _comingSoon('Past Paper Analyzer')),
      _Tool('Exam Mode', 'Timed practice exams', Icons.timer_rounded, const Color(0xFFF59E0B),
          () => _comingSoon('Exam Mode')),
      _Tool('Study Planner', 'AI-personalised plans', Icons.event_note_rounded, const Color(0xFFEC4899),
          () => _comingSoon('AI Study Planner')),
      _Tool('Group Summarizer', 'Catch up on group chats', Icons.groups_rounded, const Color(0xFF14B8A6),
          () => _comingSoon('Group Summarizer')),
      _Tool('Study Insights', 'Personalised recommendations', Icons.insights_rounded, const Color(0xFF8B5CF6),
          () => _comingSoon('Study Insights')),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tools.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (ctx, i) {
        final t = tools[i];
        return GestureDetector(
          onTap: t.onTap,
          child: GlassCard(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: t.color.withAlpha(45), shape: BoxShape.circle),
                child: Icon(t.icon, color: t.color, size: 18),
              ),
              const Spacer(),
              Text(t.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(t.subtitle, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ).animate(delay: (i * 30).ms).fadeIn().slideY(begin: 0.06, end: 0);
      },
    );
  }
}

class _Tool {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _Tool(this.title, this.subtitle, this.icon, this.color, this.onTap);
}
