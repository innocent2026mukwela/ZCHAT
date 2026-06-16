import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/ai_service.dart';
import '../../utils/glass.dart';

class GroupSummarizerScreen extends StatefulWidget {
  const GroupSummarizerScreen({super.key});
  @override
  State<GroupSummarizerScreen> createState() => _GroupSummarizerScreenState();
}

class _GroupSummarizerScreenState extends State<GroupSummarizerScreen> {
  final _db = FirebaseFirestore.instance;
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;

  final Map<String, String?> _summaries  = {};
  final Map<String, bool>    _loading    = {};
  final Map<String, String?> _errors     = {};

  Future<void> _summarize(String chatId, String chatName) async {
    setState(() { _loading[chatId] = true; _errors[chatId] = null; });
    try {
      final msgSnap = await _db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(60)
          .get();

      if (msgSnap.docs.isEmpty) {
        if (mounted) {
          setState(() {
            _summaries[chatId] = 'No messages to summarize yet.';
            _loading[chatId] = false;
          });
        }
        return;
      }

      final lines = msgSnap.docs.reversed.map((d) {
        final data = d.data();
        final sender = (data['senderName'] as String?)?.split(' ').first ?? 'Someone';
        final text   = data['text'] as String? ?? '';
        return text.isNotEmpty ? '$sender: $text' : null;
      }).whereType<String>().toList();

      final summary = await AiService.summarizeChat(messages: lines, chatName: chatName);
      if (mounted) setState(() { _summaries[chatId] = summary; _loading[chatId] = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errors[chatId] = e.toString().replaceFirst('Exception: ', '');
          _loading[chatId] = false;
        });
      }
    }
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
            _buildAppBar(context),
            Expanded(child: _buildBody()),
          ]),
        ]),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(12),
            border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          child: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Group Summarizer', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('Catch up instantly with AI', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
              ),
              const Icon(Icons.groups_rounded, color: Color(0xFF14B8A6)),
            ]),
          )),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_myUid == null) {
      return const Center(child: Text('Not signed in', style: TextStyle(color: Colors.white54)));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('chats')
          .where('type', isEqualTo: 'group')
          .where('memberUids', arrayContains: _myUid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF14B8A6)));
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load groups', style: TextStyle(color: Colors.white.withAlpha(120))));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmpty();
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final chatId   = docs[i].id;
            final name     = data['name'] as String? ?? 'Group';
            final members  = (data['memberUids'] as List?)?.length ?? 0;
            final summary  = _summaries[chatId];
            final isLoading = _loading[chatId] ?? false;
            final error    = _errors[chatId];
            return _GroupCard(
              chatId:    chatId,
              name:      name,
              members:   members,
              summary:   summary,
              isLoading: isLoading,
              error:     error,
              onSummarize: () => _summarize(chatId, name),
              index: i,
            );
          },
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.groups_rounded, size: 64, color: Colors.white.withAlpha(40)),
          const SizedBox(height: 16),
          const Text('No group chats', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Join or create a group chat to use the AI summarizer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withAlpha(140), height: 1.5)),
        ]),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final String  chatId;
  final String  name;
  final int     members;
  final String? summary;
  final bool    isLoading;
  final String? error;
  final VoidCallback onSummarize;
  final int     index;

  const _GroupCard({
    required this.chatId,
    required this.name,
    required this.members,
    required this.summary,
    required this.isLoading,
    required this.error,
    required this.onSummarize,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: BorderRadius.circular(18),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF14B8A6).withAlpha(35),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.groups_rounded, color: Color(0xFF14B8A6), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              Text('$members members',
                  style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12)),
            ])),
            if (!isLoading)
              ElevatedButton.icon(
                onPressed: onSummarize,
                icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                label: Text(summary == null ? 'Summarize' : 'Refresh', style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14B8A6),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(90, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              )
            else
              const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(color: Color(0xFF14B8A6), strokeWidth: 2),
              ),
          ]),
          if (error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withAlpha(60)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
              ]),
            ),
          ],
          if (summary != null && error == null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF14B8A6).withAlpha(16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF14B8A6).withAlpha(50)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFF14B8A6), size: 13),
                  const SizedBox(width: 6),
                  Text('AI Summary', style: TextStyle(color: const Color(0xFF14B8A6).withAlpha(220), fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                Text(summary!, style: TextStyle(color: Colors.white.withAlpha(185), fontSize: 13, height: 1.4)),
              ]),
            ),
          ],
        ]),
      ),
    ).animate(delay: (index * 50).ms).fadeIn().slideY(begin: 0.05, end: 0);
  }
}

