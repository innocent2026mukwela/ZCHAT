import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
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
  // Created once so bookmark/block updates don't re-subscribe the feed.
  late final Stream<List<Map<String, dynamic>>> _forYou = ThreadsService.forYouStream();
  late final Stream<List<Map<String, dynamic>>> _following = ThreadsService.followingStream();

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
        allowImage: true,
        onSubmit: (text, imageUrl) async {
          await ThreadsService.createPost(text.trim(), imageUrl: imageUrl);
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
            title: const Text('zFeed',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.5)),
            actions: [
              IconButton(icon: const Icon(Icons.search_rounded, color: Colors.white70), onPressed: () => context.push('/zfeed/search'), tooltip: 'Search'),
              IconButton(icon: const Icon(Icons.bookmark_border_rounded, color: Colors.white70), onPressed: () => context.push('/zfeed/bookmarks'), tooltip: 'Bookmarks'),
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
        body: StreamBuilder<Set<String>>(
          stream: ThreadsService.blockedIdsStream(),
          builder: (context, blockedSnap) {
            final blocked = blockedSnap.data ?? const <String>{};
            return StreamBuilder<Set<String>>(
              stream: ThreadsService.bookmarkedIdsStream(),
              builder: (context, bmSnap) {
                final bookmarks = bmSnap.data ?? const <String>{};
                return TabBarView(controller: _tabs, children: [
                  _FeedTab(stream: _forYou, myUid: _myUid, myInitials: _myInitials, myPhotoUrl: _myPhotoUrl, myColorVal: _myColorVal,
                      bookmarkedIds: bookmarks, blockedIds: blocked),
                  _FeedTab(stream: _following, myUid: _myUid, myInitials: _myInitials, myPhotoUrl: _myPhotoUrl, myColorVal: _myColorVal,
                      isFollowingTab: true, bookmarkedIds: bookmarks, blockedIds: blocked),
                ]);
              },
            );
          },
        ),
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
  final Set<String> bookmarkedIds;
  final Set<String> blockedIds;

  const _FeedTab({
    required this.stream, required this.myUid,
    required this.myInitials, required this.myPhotoUrl, required this.myColorVal,
    this.isFollowingTab = false, this.bookmarkedIds = const {}, this.blockedIds = const {},
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _FeedSkeleton();
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load posts',
              style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14)));
        }
        final posts = (snap.data ?? [])
            .where((p) => !blockedIds.contains(p['authorUid'] as String? ?? ''))
            .toList();
        return RefreshIndicator(
          color: const Color(0xFF4F8AFF),
          backgroundColor: const Color(0xFF0E1829),
          onRefresh: () async => Future.delayed(const Duration(milliseconds: 600)),
          child: posts.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 120),
                  Column(children: [
                    Icon(Icons.dynamic_feed_rounded, size: 52, color: Colors.white24),
                    const SizedBox(height: 14),
                    Text(
                      isFollowingTab ? 'Follow some people to see their posts here.' : 'No posts yet. Be the first!',
                      style: const TextStyle(color: Colors.white38, fontSize: 15),
                      textAlign: TextAlign.center),
                  ]),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: posts.length,
                  itemBuilder: (context, i) {
                    final post = posts[i];
                    return _ThreadCard(
                      post: post, myUid: myUid, myInitials: myInitials, myPhotoUrl: myPhotoUrl,
                      myColorVal: myColorVal, showDivider: true, index: i, bookmarkedIds: bookmarkedIds,
                    ).animate(delay: (i * 20).ms).fadeIn();
                  },
                ),
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
  final Set<String> bookmarkedIds;

  const _ThreadCard({
    required this.post, required this.myUid,
    required this.myInitials, required this.myPhotoUrl, required this.myColorVal,
    this.showDivider = true, this.index = 0, this.bookmarkedIds = const {},
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
    final imageUrl    = post['imageUrl']    as String? ?? '';
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
          _AuthorAvatar(photoUrl: photoUrl, colorVal: colorVal, initials: initials, size: 42,
            onTap: authorUid.isNotEmpty ? () => context.push('/zfeed/user/$authorUid') : null),
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
            if (content.isNotEmpty)
              _PostText(content, fontSize: 14.5),
            if (imageUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: imageUrl, width: double.infinity, fit: BoxFit.cover,
                  placeholder: (c, u) => Container(height: 160, color: Colors.white10),
                  errorWidget: (c, u, e) => const SizedBox.shrink(),
                ),
              ),
            ],
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
              const Spacer(),
              _ActionBtn(
                icon: bookmarkedIds.contains(id) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                count: null, color: bookmarkedIds.contains(id) ? const Color(0xFF4F8AFF) : null,
                onTap: () { HapticFeedback.lightImpact(); ThreadsService.toggleBookmark(id, bookmarkedIds.contains(id)); },
              ),
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
        onSubmit: (text, _) async {
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
        await _checkFollow();
        if (!context.mounted) return;
        _showMenu(context);
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
          if (!widget.isOwn)
            _MenuTile(
              icon: Icons.block_rounded, label: 'Block ${widget.authorName}', color: Colors.redAccent,
              onTap: () async {
                Navigator.pop(context);
                await ThreadsService.blockUser(widget.authorUid);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("Blocked ${widget.authorName}. You won't see their posts."),
                    backgroundColor: const Color(0xFF2563EB),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              },
            ),
          if (!widget.isOwn)
            _MenuTile(
              icon: Icons.flag_outlined, label: 'Report', color: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                ThreadsService.reportPost(widget.postId, widget.authorUid).catchError((_) {});
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
        onSubmit: (text, _) async {
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
        title: const Text('Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
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
    final imageUrl   = post['imageUrl']    as String? ?? '';
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
          _AuthorAvatar(photoUrl: photoUrl, colorVal: colorVal, initials: initials, size: 44,
            onTap: authorUid.isNotEmpty ? () => context.push('/zfeed/user/$authorUid') : null),
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
        if (content.isNotEmpty)
          _PostText(content, fontSize: 15.5),
        if (imageUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(
              imageUrl: imageUrl, width: double.infinity, fit: BoxFit.cover,
              placeholder: (c, u) => Container(height: 180, color: Colors.white10),
              errorWidget: (c, u, e) => const SizedBox.shrink(),
            ),
          ),
        ],
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
    final authorUid  = reply['authorUid']   as String? ?? '';
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
        _AuthorAvatar(photoUrl: photoUrl, colorVal: colorVal, initials: initials, size: 38,
          onTap: authorUid.isNotEmpty ? () => context.push('/zfeed/user/$authorUid') : null),
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

// ── Post text with tappable #hashtags / @mentions ─────────────────────────────

class _PostText extends StatefulWidget {
  final String content;
  final double fontSize;
  const _PostText(this.content, {this.fontSize = 14.5});
  @override
  State<_PostText> createState() => _PostTextState();
}

class _PostTextState extends State<_PostText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) { r.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) { r.dispose(); }
    _recognizers.clear();
    final base = TextStyle(color: Colors.white.withAlpha(220), fontSize: widget.fontSize, height: 1.45);
    const link = TextStyle(color: Color(0xFF4F8AFF), fontWeight: FontWeight.w600);
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(#\w+|@\w+)');
    int last = 0;
    for (final m in regex.allMatches(widget.content)) {
      if (m.start > last) spans.add(TextSpan(text: widget.content.substring(last, m.start)));
      final token = m.group(0)!;
      final rec = TapGestureRecognizer()
        ..onTap = () => context.push('/zfeed/search?q=${Uri.encodeComponent(token)}');
      _recognizers.add(rec);
      spans.add(TextSpan(text: token, style: link, recognizer: rec));
      last = m.end;
    }
    if (last < widget.content.length) spans.add(TextSpan(text: widget.content.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

// ── Author Avatar ─────────────────────────────────────────────────────────────

class _AuthorAvatar extends StatelessWidget {
  final String photoUrl, initials;
  final int colorVal;
  final double size;
  final VoidCallback? onTap;
  const _AuthorAvatar({required this.photoUrl, required this.colorVal, required this.initials, required this.size, this.onTap});

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: size / 2,
      backgroundColor: Color(colorVal),
      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
      child: photoUrl.isEmpty
          ? Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.33))
          : null,
    );
    return onTap == null ? avatar : GestureDetector(onTap: onTap, child: avatar);
  }
}

// ── Compose Sheet (new post + reply) ──────────────────────────────────────────

class _ComposeSheet extends StatefulWidget {
  final String myInitials, myPhotoUrl, hintText, actionLabel;
  final int myColorVal;
  final Map<String, dynamic>? previewPost;
  final Future<void> Function(String text, String? imageUrl) onSubmit;
  final bool allowImage;

  const _ComposeSheet({
    required this.myInitials, required this.myPhotoUrl, required this.myColorVal,
    required this.hintText, required this.actionLabel, required this.onSubmit,
    this.previewPost, this.allowImage = false,
  });

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  bool _posting = false;
  File? _image;

  static const _maxChars = 280;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); super.dispose(); }

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
    if (picked != null && mounted) setState(() => _image = File(picked.path));
  }

  Future<void> _submit() async {
    if (_ctrl.text.trim().isEmpty && _image == null) return;
    setState(() => _posting = true);
    try {
      String? imageUrl;
      if (_image != null) imageUrl = await ThreadsService.uploadPostImage(_image!);
      await widget.onSubmit(_ctrl.text, imageUrl);
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
              maxLength: _maxChars,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(color: Colors.white.withAlpha(70), fontSize: 15),
                border: InputBorder.none,
                counterText: '',
              ),
            )),
          ]),
          // Selected image preview
          if (_image != null) ...[
            const SizedBox(height: 12),
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(_image!, height: 180, width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                top: 8, right: 8,
                child: GestureDetector(
                  onTap: () => setState(() => _image = null),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.black.withAlpha(140), shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 14),

          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              if (widget.allowImage)
                GestureDetector(
                  onTap: _posting ? null : _pickImage,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(Icons.image_outlined,
                      color: Colors.white.withAlpha(_image == null ? 110 : 200), size: 22),
                ),
            ]),
            Row(children: [
              Text('${_maxChars - _ctrl.text.characters.length}',
                style: TextStyle(
                  color: (_maxChars - _ctrl.text.characters.length) <= 20 ? Colors.orangeAccent : Colors.white38,
                  fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
              Opacity(
                opacity: (_ctrl.text.trim().isNotEmpty || _image != null) ? 1 : 0.45,
                child: GestureDetector(
                  onTap: (_posting || (_ctrl.text.trim().isEmpty && _image == null)) ? null : _submit,
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
              ),
            ]),
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

// ── ZFeed Profile Screen ──────────────────────────────────────────────────────
// Identity comes from the main zCHAT profile (users/{uid}) — the name used at
// sign-up, photo, role and bio. Only the post/follow stats are ZFeed-specific.

class ZFeedProfileScreen extends StatefulWidget {
  final String uid;
  const ZFeedProfileScreen({super.key, required this.uid});
  @override
  State<ZFeedProfileScreen> createState() => _ZFeedProfileScreenState();
}

class _ZFeedProfileScreenState extends State<ZFeedProfileScreen> {
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  Map<String, dynamic>? _profile;
  int _followers = 0, _following = 0, _posts = 0;
  bool? _isFollowing;
  bool _loading = true;
  int _tab = 0; // 0 Posts · 1 Replies · 2 Reposts
  bool get _isMe => widget.uid == _myUid;

  Stream<List<Map<String, dynamic>>> _selectedStream() => _tab == 0
      ? ThreadsService.userPostsStream(widget.uid)
      : _tab == 1
          ? ThreadsService.userRepliesStream(widget.uid)
          : ThreadsService.userRepostsStream(widget.uid);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile   = await ThreadsService.fetchAuthorProfile(widget.uid);
    final counts    = await ThreadsService.getFollowCounts(widget.uid);
    final posts     = await ThreadsService.getPostCount(widget.uid);
    final following = _isMe ? null : await ThreadsService.isFollowing(widget.uid);
    if (!mounted) return;
    setState(() {
      _profile     = profile;
      _followers   = counts['followers'] ?? 0;
      _following   = counts['following'] ?? 0;
      _posts       = posts;
      _isFollowing = following;
      _loading     = false;
    });
  }

  Future<void> _toggleFollow() async {
    if (_isMe) return;
    final name = _profile?['fullName'] as String? ?? 'User';
    final wasFollowing = _isFollowing == true;
    setState(() { _isFollowing = !wasFollowing; _followers += wasFollowing ? -1 : 1; });
    try {
      wasFollowing
          ? await ThreadsService.unfollowUser(widget.uid)
          : await ThreadsService.followUser(widget.uid, name);
    } catch (_) {
      if (mounted) setState(() { _isFollowing = wasFollowing; _followers += wasFollowing ? 1 : -1; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawName     = (_profile?['fullName'] as String?)?.trim();
    final displayName = (rawName != null && rawName.isNotEmpty) ? rawName : 'ZCHAT User';
    final role        = _profile?['role'] as String? ?? 'student';
    final photoUrl    = _profile?['photoUrl'] as String? ?? '';
    final about       = (_profile?['about'] as String?)?.trim() ?? '';
    final program     = (_profile?['program'] as String?)?.trim() ?? '';
    final school      = (_profile?['school'] as String?)?.trim() ?? '';
    final department  = (_profile?['department'] as String?)?.trim() ?? '';
    final isVerified  = role == 'lecturer';
    final colorVal    = ThreadsService.colorForUid(widget.uid);
    final initials    = ThreadsService.initials(displayName);
    final handle      = '@${displayName.toLowerCase().replaceAll(' ', '.')}';
    final affiliation = [program, department, school].where((s) => s.isNotEmpty).join(' · ');

    return Scaffold(
      backgroundColor: const Color(0xFF070F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070F1E), elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.pop()),
        title: const Text('Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2))
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _selectedStream(),
              builder: (context, snap) {
                final posts = snap.data ?? [];
                return ListView(
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _AuthorAvatar(photoUrl: photoUrl, colorVal: colorVal, initials: initials, size: 68),
                          const SizedBox(width: 16),
                          Expanded(child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(children: [
                              _ProfileStat(count: _posts, label: 'Posts'),
                              _ProfileStat(count: _followers, label: 'Followers'),
                              _ProfileStat(count: _following, label: 'Following'),
                            ]),
                          )),
                        ]),
                        const SizedBox(height: 14),
                        Row(children: [
                          Flexible(child: Text(displayName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                            overflow: TextOverflow.ellipsis)),
                          if (isVerified) ...[const SizedBox(width: 5), const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF4F8AFF))],
                        ]),
                        const SizedBox(height: 2),
                        Text(handle, style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: (isVerified ? const Color(0xFF4F8AFF) : Colors.white).withAlpha(28),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(isVerified ? 'Lecturer' : 'Student',
                            style: TextStyle(color: isVerified ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(200),
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        if (about.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(about, style: TextStyle(color: Colors.white.withAlpha(210), fontSize: 14, height: 1.4)),
                        ],
                        if (affiliation.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            Icon(Icons.school_outlined, size: 15, color: Colors.white.withAlpha(120)),
                            const SizedBox(width: 6),
                            Flexible(child: Text(affiliation,
                              style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13),
                              overflow: TextOverflow.ellipsis)),
                          ]),
                        ],
                        const SizedBox(height: 14),
                        if (!_isMe)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _toggleFollow,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _isFollowing == true ? Colors.transparent : Colors.white,
                                side: BorderSide(color: _isFollowing == true ? Colors.white38 : Colors.white),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                              child: Text(_isFollowing == true ? 'Following' : 'Follow',
                                style: TextStyle(color: _isFollowing == true ? Colors.white : const Color(0xFF070F1E),
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            ),
                          ),
                      ]),
                    ),
                    _ProfileSegmented(tab: _tab, onChanged: (t) => setState(() => _tab = t)),
                    Divider(color: Colors.white.withAlpha(14), height: 1),
                    if (snap.connectionState == ConnectionState.waiting)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF), strokeWidth: 2)))
                    else if (posts.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Center(child: Text(
                          _tab == 1 ? (_isMe ? "You haven't replied yet." : 'No replies yet.')
                          : _tab == 2 ? (_isMe ? "You haven't reposted yet." : 'No reposts yet.')
                          : (_isMe ? "You haven't posted yet." : 'No posts yet.'),
                          style: TextStyle(color: Colors.white.withAlpha(90), fontSize: 14))))
                    else if (_tab == 1)
                      ...posts.map((r) => _ProfileReplyTile(reply: r))
                    else
                      ...posts.map((p) => _ThreadCard(
                        post: p, myUid: _myUid,
                        myInitials: initials, myPhotoUrl: _isMe ? photoUrl : '', myColorVal: colorVal,
                      )),
                  ],
                );
              },
            ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final int count;
  final String label;
  const _ProfileStat({required this.count, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12)),
    ]),
  );
}

class _ProfileSegmented extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onChanged;
  const _ProfileSegmented({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(int i, String label) {
      final sel = tab == i;
      return Expanded(child: GestureDetector(
        onTap: () => onChanged(i),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(
            color: sel ? const Color(0xFF4F8AFF) : Colors.transparent, width: 2))),
          child: Center(child: Text(label, style: TextStyle(
            color: sel ? Colors.white : Colors.white.withAlpha(120),
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 14))),
        ),
      ));
    }
    return Row(children: [seg(0, 'Posts'), seg(1, 'Replies'), seg(2, 'Reposts')]);
  }
}

class _ProfileReplyTile extends StatelessWidget {
  final Map<String, dynamic> reply;
  const _ProfileReplyTile({required this.reply});

  @override
  Widget build(BuildContext context) {
    final text    = reply['text'] as String? ?? '';
    final postId  = reply['postId'] as String?;
    final timeAgo = ThreadsService.timeAgo(reply['createdAt'] as Timestamp?);
    return InkWell(
      onTap: postId != null ? () => context.push('/threads/$postId') : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withAlpha(12)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.reply_rounded, size: 18, color: Colors.white.withAlpha(110)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withAlpha(210), fontSize: 14, height: 1.4)),
            const SizedBox(height: 4),
            Text('Replied · $timeAgo', style: TextStyle(color: Colors.white.withAlpha(90), fontSize: 12)),
          ])),
        ]),
      ),
    );
  }
}

// ── ZFeed Search Screen ───────────────────────────────────────────────────────

class ZFeedSearchScreen extends StatefulWidget {
  final String? initialQuery;
  const ZFeedSearchScreen({super.key, this.initialQuery});
  @override
  State<ZFeedSearchScreen> createState() => _ZFeedSearchScreenState();
}

class _ZFeedSearchScreenState extends State<ZFeedSearchScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _ctrl = TextEditingController();
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _posts = [];
  bool _loading = false;
  bool _searched = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _ctrl.text = widget.initialQuery!;
      _search(widget.initialQuery!);
    }
  }

  @override
  void dispose() { _tabs.dispose(); _ctrl.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() { _query = q.trim(); _loading = true; _searched = true; });
    final users = await ThreadsService.searchUsers(q);
    final posts = await ThreadsService.searchPosts(q);
    if (!mounted) return;
    setState(() { _users = users; _posts = posts; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070F1E), elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.pop()),
        titleSpacing: 0,
        title: Container(
          height: 40,
          decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search people, posts, #hashtags',
              hintStyle: TextStyle(color: Colors.white.withAlpha(90), fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(150), size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white, labelColor: Colors.white, unselectedLabelColor: Colors.white38,
          dividerColor: Colors.white12,
          tabs: const [Tab(text: 'People'), Tab(text: 'Posts')],
        ),
      ),
      body: _loading
          ? const _FeedSkeleton()
          : !_searched
              ? _hint('Search for students, posts, or #hashtags.')
              : TabBarView(controller: _tabs, children: [
                  _users.isEmpty
                      ? _hint('No people found for "$_query".')
                      : ListView(children: _users.map(_userTile).toList()),
                  _posts.isEmpty
                      ? _hint('No posts found for "$_query".')
                      : ListView(children: _posts.map((p) => _ThreadCard(
                          post: p, myUid: _myUid, myInitials: '', myPhotoUrl: '', myColorVal: 0xFF4F8AFF)).toList()),
                ]),
    );
  }

  Widget _hint(String text) => Center(
    child: Padding(padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withAlpha(90), fontSize: 15))));

  Widget _userTile(Map<String, dynamic> u) {
    final uid  = u['uid'] as String;
    final name = (u['fullName'] as String?)?.trim().isNotEmpty == true ? u['fullName'] as String : 'ZCHAT User';
    final role = u['role'] as String? ?? 'student';
    final photo = u['photoUrl'] as String? ?? '';
    return ListTile(
      onTap: () => context.push('/zfeed/user/$uid'),
      leading: _AuthorAvatar(photoUrl: photo, colorVal: ThreadsService.colorForUid(uid),
          initials: ThreadsService.initials(name), size: 44),
      title: Row(children: [
        Flexible(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
        if (role == 'lecturer') ...[const SizedBox(width: 4), const Icon(Icons.verified_rounded, size: 14, color: Color(0xFF4F8AFF))],
      ]),
      subtitle: Text(role == 'lecturer' ? 'Lecturer' : 'Student', style: TextStyle(color: Colors.white.withAlpha(110), fontSize: 12)),
    );
  }
}

// ── ZFeed Bookmarks Screen ────────────────────────────────────────────────────

class ZFeedBookmarksScreen extends StatelessWidget {
  const ZFeedBookmarksScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFF070F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070F1E), elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.pop()),
        title: const Text('Bookmarks', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: ThreadsService.bookmarksStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const _FeedSkeleton();
          final posts = snap.data ?? [];
          if (posts.isEmpty) {
            return Center(child: Padding(padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.bookmark_border_rounded, size: 52, color: Colors.white24),
                const SizedBox(height: 14),
                const Text('No bookmarks yet', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('Save posts to read later — they show up here.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(110), fontSize: 13)),
              ])));
          }
          final ids = posts.map((p) => p['id'] as String).toSet();
          return ListView(children: posts.map((p) => _ThreadCard(
            post: p, myUid: myUid, myInitials: '', myPhotoUrl: '', myColorVal: 0xFF4F8AFF,
            bookmarkedIds: ids)).toList());
        },
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  Widget _bar(double w, double h) => Container(
    height: h, width: w,
    margin: const EdgeInsets.only(bottom: 7),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
  );

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 6),
      itemCount: 7,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.white.withAlpha(13),
        highlightColor: Colors.white.withAlpha(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CircleAvatar(radius: 21, backgroundColor: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _bar(130, 12),
              _bar(double.infinity, 10),
              _bar(double.infinity, 10),
              _bar(200, 10),
            ])),
          ]),
        ),
      ),
    );
  }
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
        Text('New Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
    ),
  );
}
