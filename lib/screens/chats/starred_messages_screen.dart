import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../services/chat_service.dart';

class StarredMessagesScreen extends StatelessWidget {
  const StarredMessagesScreen({super.key});

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt   = ts.toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)  return ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][dt.weekday - 1];
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFF06112B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1A4A),
        foregroundColor: Colors.white,
        title: const Text('Starred Messages',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users').doc(myUid).collection('starred')
            .orderBy('starredAt', descending: true)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF4F8AFF)));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.star_border_rounded, size: 64,
                    color: Colors.white.withAlpha(40)),
                const SizedBox(height: 16),
                Text('No starred messages',
                    style: TextStyle(color: Colors.white.withAlpha(100),
                        fontSize: 16)),
                const SizedBox(height: 8),
                Text('Star messages to find them here quickly.',
                    style: TextStyle(color: Colors.white.withAlpha(60),
                        fontSize: 13)),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, _) =>
                Divider(color: Colors.white.withAlpha(12), height: 1),
            itemBuilder: (ctx, i) {
              final data    = docs[i].data();
              final chatId  = data['chatId']   as String? ?? '';
              final text    = data['text']     as String? ?? '';
              final ts      = data['starredAt'] as Timestamp?;
              final msgId   = data['msgId']    as String? ?? '';

              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star_rounded,
                      color: Color(0xFFFFD700), size: 22),
                ),
                title: Text(
                  text.isEmpty ? '📷 Photo' : text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: Text(_formatTime(ts),
                    style: TextStyle(
                        color: Colors.white.withAlpha(100), fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.star_rounded,
                      color: Color(0xFFFFD700), size: 20),
                  tooltip: 'Unstar',
                  onPressed: () => ChatService.unstarMessage(msgId),
                ),
                onTap: () {
                  if (chatId.isNotEmpty) {
                    context.push(
                        '/chats/${Uri.encodeComponent(chatId)}');
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
