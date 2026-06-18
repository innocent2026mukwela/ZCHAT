import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../services/threads_service.dart';
import '../../widgets/bottom_nav_bar.dart';

// ── Main Threads Screen ───────────────────────────────────────────────────────

class ThreadsScreen extends StatefulWidget {
  const ThreadsScreen({super.key});
  @override
  State<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends State<ThreadsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Cache current user data for compose
  String _myName      = '';
  String _myInitials  = '';
  String _myPhotoUrl  = '';
  int    _myColorVal  = 0xFF4F8AFF;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadMyProfile();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _loadMyProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await ThreadsService.fetchAuthorProfile(user.uid);
    if (mounted) {
      setState(() {
        _myName     = user.displayName ?? doc?['fullName'] as String? ?? 'Me';
        _myInitials = ThreadsService.initials(_myName);
        _myPhotoUrl = doc?['photoUrl'] as String? ?? '';
        _myColorVal = ThreadsService.colorForUid(user.uid);
      });
    }
  }

  void _showNewPostSheet() {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComposeSheet(
        myInitials: _myInitials, myPhotoUrl: _myPhotoUrl, myColorVal: _myColorVal,
        hintText: "What's on your mind?",
        actionLabel: 'Post',
        onSubmit: (text) async {
          await ThreadsService.createPost(text.trim());
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070F1E),
      bottomNavigationBar: const AppBottomNavBar(),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, snap) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF070F1E).withAlpha(230),
            elevation: 0,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(color: Colors.transparent),
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => context.go('/home'),
            ),
            title: const Text('Threads',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.5)),
            actions: [
              IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.white70), onPressed: _showNewPostSheet, tooltip: 'New thread'),
              const SizedBox(width: 4),
            ],
            bottom: TabBar(
              controller: _tabs,
              indicatorColor: Colors.white,
              indicatorWeight: 2,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              dividerColor: Colors.white12,
              tabs: const [Tab(text: 'For You'), Tab(text: 'Following')],
            ),
          ),
        ],
        body: TabBarView(controller: _tabs, children: [
          _FeedTab(stream: ThreadsService.forYouStream(),    myUid: _myUid, myInitials: _myInitials, myPhotoUrl: _myPhotoUrl, myColorVal: _myColorVal),
          _FeedTab(stream: ThreadsService.followingStream(), myUid: _myUid, myInitials: _myInitials, myPhotoUrl: _myPhotoUrl, myColorVal: _myColorVal, isFollowingTab: true),
        ]),
      ),
      floatingActionButton: _NewThreadFab(onTap: _showNewPostSheet),
    );
  }
}

// ── Feed Tab ──────────────────────────────────────────────────────────────────

class _FeedTab extends StatelessWidget {
  final Stream<List<Map<String, dynamic>>> stream;
  final String myUid, myInitials, myPhotoUrl;
  final int myColorVal;
  final bool isFollowingTab;

  const _FeedTab({
    required this.stream, required this.myUid,
    required this.myInitials, required this.myPhotoUrl, required this.myColorVal,
    this.isFollowingTab = false,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2));
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load posts',
              style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14)));
        }
        final posts = snap.data ?? [];
        if (posts.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.dynamic_feed_rounded, size: 52, color: Colors.white24),
              const SizedBox(height: 14),
              Text(
                isFollowingTab ? 'Follow some people to see their posts here.' : 'No posts yet. Be the first!',
                style: const TextStyle(color: Colors.white38, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 90),
          itemCount: posts.length,
          itemBuilder: (context, i) {
            final post = posts[i];
            return _ThreadCard(
              post: post,
              myUid: myUid,
              myInitials: myInitials,
              myPhotoUrl: myPhotoUrl,
              myColorVal: myColorVal,
              showDivider: true,
              index: i,
            ).animate(delay: (i * 20).ms).fadeIn();
          },
        );
      },
    );
  }
}

// ── Thread Card ───────────────────────────────────────────────────────────────

class _ThreadCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final String myUid, myInitials, myPhotoUrl;
  final int myColorVal;
  final bool showDivider;
  final int index;

  const _ThreadCard({
    required this.post, required this.myUid,
    required this.myInitials, required this.myPhotoUrl, required this.myColorVal,
    this.showDivider = true, this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final id          = post['id']          as String;
    final authorName  = post['authorName']  as String? ?? 'Unknown';
    final authorRole  = post['authorRole']  as String? ?? 'student';
    final authorUid   = post['authorUid']   as String? ?? '';
    final photoUrl    = post['authorPhotoUrl'] as String? ?? '';
    final colorVal    = post['avatarColorVal'] as int? ?? 0xFF4F8AFF;
    final initials    = post['avatarInitials'] as String? ?? '?';
    final content     = post['content']     as String? ?? '';
    final likes       = (post['likes']   as num?)?.toInt() ?? 0;
    final replies     = (post['replies'] as num?)?.toInt() ?? 0;
    final reposts     = (post['reposts'] as num?)?.toInt() ?? 0;
    final isVerified  = post['isVerified']  as bool? ?? false;
    final isLiked     = (post['likedBy']    as List?)?.contains(myUid) ?? false;
    final isReposted  = (post['repostedBy'] as List?)?.contains(myUid) ?? false;
    final timeAgo     = ThreadsService.timeAgo(post['createdAt'] as Timestamp?);
    final isOwn       = authorUid == myUid;

    return GestureDetector(
      onTap: () => context.push('/threads/$id', extra: post),
      child: Container(
        decoration: showDivider
            ? BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withAlpha(14))))
            : null,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Avatar
          _AuthorAvatar(photoUrl: photoUrl, colorVal: colorVal, initials: initials, size: 42),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header row
            Row(children: [
              Expanded(child: Row(children: [
                Flexible(child: Text(authorName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5),
                  overflow: TextOverflow.ellipsis)),
                if (isVerified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified_rounded, size: 15, color: Color(0xFF4F8AFF)),
                ],
              ])),
              Text(timeAgo, style: TextStyle(color: Colors.white.withAlpha(90), fontSize: 12)),
              const SizedBox(width: 6),
              _MoreMenu(
                postId: id, authorUid: authorUid, authorName: authorName,
                isOwn: isOwn, myUid: myUid, postContent: content,
                myInitials: myInitials, myPhotoUrl: myPhotoUrl, myColorVal: myColorVal,
              ),
            ]),
            // Role
            Text(
              authorRole == 'lecturer' ? 'Lecturer' : 'Student',
              style: TextStyle(color: Colors.white.withAlpha(90), fontSize: 12),
            ),
            const SizedBox(height: 7),
            // Content
            Text(content,
              style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 14.5, height: 1.45)),
            const SizedBox(height: 10),
            // Actions
            Row(children: [
              _ActionBtn(
                icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                count: likes, color: isLiked ? const Color(0xFFEF4444) : null,
                onTap: () { HapticFeedback.lightImpact(); ThreadsService.toggleLike(id, isLiked); },
              ),
              const SizedBox(width: 20),
              _ActionBtn(
                icon: Icons.chat_bubble_outline_rounded, count: replies,
                onTap: () => _showReplySheet(context, post, myInitials, myPhotoUrl, myColorVal),
              ),
              const SizedBox(width: 20),
              _ActionBtn(
                icon: isReposted ? Icons.repeat_rounded : Icons.repeat_outlined,
                count: reposts, color: isReposted ? const Color(0xFF22C55E) : null,
                onTap: () { HapticFeedback.lightImpact(); ThreadsService.toggleRepost(id, isReposted); },
              ),
              const SizedBox(width: 20),
              _ActionBtn(icon: Icons.send_outlined, count: null, onTap: () {
                HapticFeedback.lightImpact();
                Clipboard.setData(ClipboardData(text: 'https://zchat.unza.zm/threads/$id'));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Link copied to clipboard'),
                  backgroundColor: Color(0xFF2563EB),
                  behavior: SnackBarBehavior.floating,
                ));
              }),
            ]),
          ])),
        ]),
      ),
    );
  }

  void _showReplySheet(BuildContext context, Map<String, dynamic> post,
      String myInitials, String myPhotoUrl, int myColorVal) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComposeSheet(
        myInitials: myInitials, myPhotoUrl: myPhotoUrl, myColorVal: myColorVal,
        hintText: 'Reply to ${post['authorName']}...',
        actionLabel: 'Reply',
        previewPost: post,
        onSubmit: (text) async {
          await ThreadsService.addReply(post['id'] as String, text.trim());
        },
      ),
    );
  }
}

// ── More ⋮ Menu ───────────────────────────────────────────────────────────────

class _MoreMenu extends StatefulWidget {
  final String postId, authorUid, authorName, myUid, postContent;
  final bool isOwn;
  final String myInitials, myPhotoUrl;
  final int myColorVal;

  const _MoreMenu({
    required this.postId, required this.authorUid, required this.authorName,
    required this.isOwn, required this.myUid, required this.postContent,
    required this.myInitials, required this.myPhotoUrl, required this.myColorVal,
  });

  @override
  State<_MoreMenu> createState() => _MoreMenuState();
}

class _MoreMenuState extends State<_MoreMenu> {
  bool? _following;

  Future<void> _checkFollow() async {
    if (widget.isOwn || _following != null) return;
    final f = await ThreadsService.isFollowing(widget.authorUid);
    if (mounted) setState(() => _following = f);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final ctx = context;
        await _checkFollow();
        if (!mounted) return;
        _showMenu(ctx);
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.more_horiz, size: 18, color: Colors.white.withAlpha(80)),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          if (!widget.isOwn) ...[
            _MenuTile(
              icon: _following == true ? Icons.person_remove_outlined : Icons.person_add_outlined,
              label: _following == true ? 'Unfollow ${widget.authorName}' : 'Follow ${widget.authorName}',
              onTap: () async {
                Navigator.pop(context);
                if (_following == true) {
                  await ThreadsService.unfollowUser(widget.authorUid);
                  setState(() => _following = false);
                } else {
                  await ThreadsService.followUser(widget.authorUid, widget.authorName);
                  setState(() => _following = true);
                }
              },
            ),
          ],
          if (widget.isOwn)
            _MenuTile(
              icon: Icons.delete_outline_rounded,
              label: 'Delete post',
              color: Colors.redAccent,
              onTap: () async {
                Navigator.pop(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF0A1A4A),
                    title: const Text('Delete post?', style: TextStyle(color: Colors.white)),
                    content: const Text('This will permanently remove your post and all its replies.',
                        style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                );
                if (ok == true) ThreadsService.deletePost(widget.postId);
              },
            ),
          _MenuTile(
            icon: Icons.flag_outlined, label: 'Report', color: Colors.orange,
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Report submitted. Thank you.'),
                backgroundColor: Color(0xFF2563EB),
                behavior: SnackBarBehavior.floating,
              ));
            },
          ),
          _MenuTile(
            icon: Icons.copy_rounded, label: 'Copy text',
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: widget.postContent));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Text copied to clipboard'),
                backgroundColor: Color(0xFF2563EB),
                behavior: SnackBarBehavior.floating,
              ));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color ?? Colors.white70, size: 20),
    title: Text(label, style: TextStyle(color: color ?? Colors.white, fontSize: 15)),
    onTap: onTap,
  );
}

// ── Thread Detail Screen ──────────────────────────────────────────────────────

class ThreadDetailScreen extends StatefulWidget {
  final String postId;
  const ThreadDetailScreen({super.key, required this.postId});
  @override
  State<ThreadDetailScreen> createState() => _ThreadDetailScreenState();
}

class _ThreadDetailScreenState extends State<ThreadDetailScreen> {
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  String _myInitials  = '';
  String _myPhotoUrl  = '';
  int    _myColorVal  = 0xFF4F8AFF;

  // Loaded post snapshot passed as extra
  Map<String, dynamic>? _post;

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
    // Load post from Firestore directly
    FirebaseFirestore.instance.collection('threads').doc(widget.postId).get().then((doc) {
      if (doc.exists && mounted) setState(() => _post = {'id': doc.id, ...doc.data()!});
    });
  }

  Future<void> _loadMyProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await ThreadsService.fetchAuthorProfile(user.uid);
    if (mounted) {
      setState(() {
        final name = user.displayName ?? doc?['fullName'] as String? ?? 'Me';
        _myInitials = ThreadsService.initials(name);
        _myPhotoUrl = doc?['photoUrl'] as String? ?? '';
        _myColorVal = ThreadsService.colorForUid(user.uid);
      });
    }
  }

  void _showReplySheet() {
    if (_post == null) return;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _ComposeSheet(
        myInitials: _myInitials, myPhotoUrl: _myPhotoUrl, myColorVal: _myColorVal,
        hintText: 'Reply to ${_post!['authorName']}...',
        actionLabel: 'Reply',
        previewPost: _post,
        onSubmit: (text) async {
          await ThreadsService.addReply(widget.postId, text.trim());
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070F1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Thread', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _post == null
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: ThreadsService.repliesStream(widget.postId),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Could not load replies',
                      style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14)));
                }
                final replies = snap.data ?? [];
                return ListView(
                  padding: const EdgeInsets.only(bottom: 100),
                  children: [
                    // Original post (full)
                    _DetailPostHeader(
                      post: _post!, myUid: _myUid,
                      myInitials: _myInitials, myPhotoUrl: _myPhotoUrl, myColorVal: _myColorVal,
                      onReply: _showReplySheet,
                    ),
                    // Divider
                    Divider(color: Colors.white.withAlpha(14), height: 1),
                    // Replies
                    if (replies.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: Text('No replies yet. Be the first!',
                          style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 14))),
                      )
                    else
                      ...replies.asMap().entries.map((e) {
                        final r = e.value;
                        return _ReplyCard(reply: r, postId: widget.postId, myUid: _myUid);
                      }),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showReplySheet,
        backgroundColor: const Color(0xFF2563EB),
        label: const Text('Reply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        icon: const Icon(Icons.reply_rounded, color: Colors.white),
      ),
    );
  }
}

class _DetailPostHeader extends StatelessWidget {
  final Map<String, dynamic> post;
  final String myUid, myInitials, myPhotoUrl;
  final int myColorVal;
  final VoidCallback onReply;

  const _DetailPostHeader({
    required this.post, required this.myUid, required this.onReply,
    required this.myInitials, required this.myPhotoUrl, required this.myColorVal,
  });

  @override
  Widget build(BuildContext context) {
    final id         = post['id']          as String;
    final authorName = post['authorName']  as String? ?? '';
    final authorRole = post['authorRole']  as String? ?? 'student';
    final authorUid  = post['authorUid']   as String? ?? '';
    final photoUrl   = post['authorPhotoUrl'] as String? ?? '';
    final colorVal   = post['avatarColorVal'] as int? ?? 0xFF4F8AFF;
    final initials   = post['avatarInitials'] as String? ?? '?';
    final content    = post['content']     as String? ?? '';
    final likes      = (post['likes']   as num?)?.toInt() ?? 0;
    final replies    = (post['replies'] as num?)?.toInt() ?? 0;
    final reposts    = (post['reposts'] as num?)?.toInt() ?? 0;
    final isVerified = post['isVerified']  as bool? ?? false;
    final isLiked    = (post['likedBy']    as List?)?.contains(myUid) ?? false;
    final isReposted = (post['repostedBy'] as List?)?.contains(myUid) ?? false;
    final timeAgo    = ThreadsService.timeAgo(post['createdAt'] as Timestamp?);
    final isOwn      = authorUid == myUid;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _AuthorAvatar(photoUrl: photoUrl, colorVal: colorVal, initials: initials, size: 44),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(authorName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
              if (isVerified) ...[const SizedBox(width: 4), const Icon(Icons.verified_rounded, size: 15, color: Color(0xFF4F8AFF))],
            ]),
            Text(authorRole == 'lecturer' ? 'Lecturer' : 'Student',
              style: TextStyle(color: Colors.white.withAlpha(90), fontSize: 12)),
          ])),
          Text(timeAgo, style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 12)),
          const SizedBox(width: 6),
          _MoreMenu(
            postId: id, authorUid: authorUid, authorName: authorName,
            isOwn: isOwn, myUid: myUid, postContent: content,
            myInitials: myInitials, myPhotoUrl: myPhotoUrl, myColorVal: myColorVal,
          ),
        ]),
        const SizedBox(height: 12),
        Text(content, style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 15.5, height: 1.5)),
        const SizedBox(height: 14),
        // Stats row
        Row(children: [
          Text('$replies replies', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 13)),
          const SizedBox(width: 12),
          Text('$likes likes', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 13)),
          const SizedBox(width: 12),
          Text('$reposts reposts', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 13)),
        ]),
        const SizedBox(height: 12),
        Divider(color: Colors.white.withAlpha(14), height: 1),
        const SizedBox(height: 8),
        // Actions
        Row(children: [
          _ActionBtn(
            icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            count: likes, color: isLiked ? const Color(0xFFEF4444) : null,
            onTap: () { HapticFeedback.lightImpact(); ThreadsService.toggleLike(id, isLiked); },
          ),
          const SizedBox(width: 20),
          _ActionBtn(icon: Icons.chat_bubble_outline_rounded, count: replies, onTap: onReply),
          const SizedBox(width: 20),
          _ActionBtn(
            icon: isReposted ? Icons.repeat_rounded : Icons.repeat_outlined,
            count: reposts, color: isReposted ? const Color(0xFF22C55E) : null,
            onTap: () { HapticFeedback.lightImpact(); ThreadsService.toggleRepost(id, isReposted); },
          ),
          const SizedBox(width: 20),
          _ActionBtn(icon: Icons.send_outlined, count: null, onTap: () {
            HapticFeedback.lightImpact();
            Clipboard.setData(ClipboardData(text: 'https://zchat.unza.zm/threads/$id'));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Link copied to clipboard'),
              backgroundColor: Color(0xFF2563EB),
              behavior: SnackBarBehavior.floating,
            ));
          }),
        ]),
      ]),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  final Map<String, dynamic> reply;
  final String postId, myUid;
  const _ReplyCard({required this.reply, required this.postId, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final replyId    = reply['id']          as String;
    final authorName = reply['authorName']  as String? ?? '';
    final authorRole = reply['authorRole']  as String? ?? 'student';
    final photoUrl   = reply['authorPhotoUrl'] as String? ?? '';
    final colorVal   = reply['avatarColorVal'] as int? ?? 0xFF4F8AFF;
    final initials   = reply['avatarInitials'] as String? ?? '?';
    final text       = reply['text']        as String? ?? '';
    final likes      = (reply['likes'] as num?)?.toInt() ?? 0;
    final isLiked    = (reply['likedBy'] as List?)?.contains(myUid) ?? false;
    final timeAgo    = ThreadsService.timeAgo(reply['createdAt'] as Timestamp?);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withAlpha(12)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _AuthorAvatar(photoUrl: photoUrl, colorVal: colorVal, initials: initials, size: 38),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(authorName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
            const SizedBox(width: 6),
            Text(timeAgo, style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 12)),
          ]),
          Text(authorRole == 'lecturer' ? 'Lecturer' : 'Student',
            style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 11)),
          const SizedBox(height: 5),
          Text(text, style: TextStyle(color: Colors.white.withAlpha(210), fontSize: 14, height: 1.4)),
          const SizedBox(height: 6),
          _ActionBtn(
            icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            count: likes, color: isLiked ? const Color(0xFFEF4444) : null,
            onTap: () { HapticFeedback.lightImpact(); ThreadsService.toggleReplyLike(postId, replyId, isLiked); },
          ),
        ])),
      ]),
    );
  }
}

// ── Author Avatar ─────────────────────────────────────────────────────────────

class _AuthorAvatar extends StatelessWidget {
  final String photoUrl, initials;
  final int colorVal;
  final double size;
  const _AuthorAvatar({required this.photoUrl, required this.colorVal, required this.initials, required this.size});

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: size / 2,
    backgroundColor: Color(colorVal),
    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
    child: photoUrl.isEmpty
        ? Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.33))
        : null,
  );
}

// ── Compose Sheet (new post + reply) ──────────────────────────────────────────

class _ComposeSheet extends StatefulWidget {
  final String myInitials, myPhotoUrl, hintText, actionLabel;
  final int myColorVal;
  final Map<String, dynamic>? previewPost;
  final Future<void> Function(String text) onSubmit;

  const _ComposeSheet({
    required this.myInitials, required this.myPhotoUrl, required this.myColorVal,
    required this.hintText, required this.actionLabel, required this.onSubmit,
    this.previewPost,
  });

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _posting = true);
    try {
      await widget.onSubmit(_ctrl.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E1829),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white.withAlpha(50), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),

          // Preview of parent post (for replies)
          if (widget.previewPost != null) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _AuthorAvatar(
                photoUrl: widget.previewPost!['authorPhotoUrl'] as String? ?? '',
                colorVal: widget.previewPost!['avatarColorVal'] as int? ?? 0xFF4F8AFF,
                initials: widget.previewPost!['avatarInitials'] as String? ?? '?',
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.previewPost!['authorName'] as String? ?? '',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 3),
                Text(widget.previewPost!['content'] as String? ?? '',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13)),
              ])),
            ]),
            const SizedBox(height: 12),
            Divider(color: Colors.white.withAlpha(15)),
            const SizedBox(height: 10),
          ],

          // Compose row
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _AuthorAvatar(photoUrl: widget.myPhotoUrl, colorVal: widget.myColorVal, initials: widget.myInitials, size: 38),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: _ctrl, focusNode: _focus,
              maxLines: 6, minLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(color: Colors.white.withAlpha(70), fontSize: 15),
                border: InputBorder.none,
              ),
            )),
          ]),
          const SizedBox(height: 14),

          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Icon(Icons.image_outlined,   color: Colors.white.withAlpha(80), size: 22),
              const SizedBox(width: 16),
              Icon(Icons.gif_box_outlined, color: Colors.white.withAlpha(80), size: 22),
              const SizedBox(width: 16),
              Icon(Icons.poll_outlined,    color: Colors.white.withAlpha(80), size: 22),
            ]),
            GestureDetector(
              onTap: _posting ? null : _submit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: _posting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.actionLabel,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Action Button ─────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final int? count;
  final Color? color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.count, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap, behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Row(children: [
        Icon(icon, size: 20, color: color ?? Colors.white.withAlpha(140)),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 4),
          Text(_fmt(count!), style: TextStyle(color: color ?? Colors.white.withAlpha(140), fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ]),
    ),
  );

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}

// ── FAB ───────────────────────────────────────────────────────────────────────

class _NewThreadFab extends StatelessWidget {
  final VoidCallback onTap;
  const _NewThreadFab({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withAlpha(100), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.edit_outlined, color: Colors.white, size: 18),
        SizedBox(width: 8),
        Text('New Thread', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
    ),
  );
}
