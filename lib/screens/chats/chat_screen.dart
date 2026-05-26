import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import '../../screens/calls/outgoing_call_screen.dart';
import '../../services/ai_service.dart';
import '../../services/chat_service.dart';
import '../../utils/glass.dart';
import '../../widgets/emoji_picker_panel.dart';

// ── Public entry point ────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String chatName;
  const ChatScreen({super.key, required this.chatId, required this.chatName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// ── State ─────────────────────────────────────────────────────────────────────

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  bool _hasText = false;
  bool _summaryDismissed = false;
  bool _showEmojiKeyboard = false;

  // Swipe-to-reply
  _Msg? _replyTarget;

  // Voice note
  bool _recording = false;
  late AnimationController _micPulse;
  final _recorder   = AudioRecorder();
  DateTime? _recordStart;

  // Typing indicator
  bool _isTyping = false;
  bool _myTyping = false;
  Timer? _typingTimer;
  late AnimationController _typingAnim;
  StreamSubscription<bool>? _typingSub;

  // Starred messages
  final _starred = <String>{};
  StreamSubscription<Set<String>>? _starredSub;

  // Search in chat
  bool _searchMode = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  // Pinned message
  Map<String, dynamic>? _pinnedMessage;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // For 1-to-1 chats the chatId is "uidA_uidB" (sorted). Extract the other uid.
  String get _otherUid {
    final parts = widget.chatId.split('_');
    if (parts.length == 2) return parts.firstWhere((p) => p != _myUid, orElse: () => '');
    return '';
  }

  bool get _isDirect => _otherUid.isNotEmpty;

  // ── Calls ──────────────────────────────────────────────────────────────────

  void _startCall({required bool video}) {
    if (!_isDirect) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OutgoingCallScreen(
        calleeUid:  _otherUid,
        calleeName: widget.chatName,
        isVideo:    video,
      ),
    ));
  }

  // ── Camera / image ─────────────────────────────────────────────────────────

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    try {
      final ref = FirebaseStorage.instance
          .ref('chat_docs/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      await ref.putFile(File(file.path!));
      final url = await ref.getDownloadURL();
      await ChatService.sendMessage(
        widget.chatId,
        '📄 ${file.name}',
        type: 'document',
        imageUrl: url,
      );
      Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
    } catch (_) {}
  }

  Future<void> _pickImage({ImageSource source = ImageSource.gallery}) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 75);
    if (picked == null) return;
    await ChatService.sendImage(widget.chatId, File(picked.path));
    Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _AttachOption(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                color: const Color(0xFF4F8AFF),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(source: ImageSource.gallery);
                },
              ),
              _AttachOption(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                color: const Color(0xFF86EFAC),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(source: ImageSource.camera);
                },
              ),
              _AttachOption(
                icon: Icons.insert_drive_file_rounded,
                label: 'Document',
                color: const Color(0xFFFBBF24),
                onTap: () {
                  Navigator.pop(context);
                  _pickDocument();
                },
              ),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _micPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _typingAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    ChatService.markRead(widget.chatId);
    _loadPinnedMessage();

    // Typing indicator: listen to other user's typing state
    if (_isDirect && _otherUid.isNotEmpty) {
      _typingSub = ChatService.typingStream(widget.chatId, _otherUid)
          .listen((typing) {
        if (mounted) setState(() => _isTyping = typing);
      });
    }

    // Starred messages: keep in sync with Firestore
    _starredSub = ChatService.starredStream().listen((ids) {
      if (mounted) {
        setState(() {
          _starred
            ..clear()
            ..addAll(ids);
        });
      }
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _typingSub?.cancel();
    _starredSub?.cancel();
    if (_isDirect) ChatService.setTyping(widget.chatId, false);
    _ctrl.dispose();
    _searchCtrl.dispose();
    _scroll.dispose();
    _micPulse.dispose();
    _typingAnim.dispose();
    super.dispose();
  }

  // ── Pinned message ────────────────────────────────────────────────────────

  Future<void> _loadPinnedMessage() async {
    final snap = await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId)
        .collection('messages')
        .where('pinned', isEqualTo: true)
        .limit(1)
        .get();
    if (mounted && snap.docs.isNotEmpty) {
      setState(() => _pinnedMessage = snap.docs.first.data());
    }
  }

  Future<void> _pinMessage(_Msg msg) async {
    // Unpin any current pinned message first
    if (_pinnedMessage != null) {
      final oldId = _pinnedMessage!['id'] as String?;
      if (oldId != null) {
        await FirebaseFirestore.instance
            .collection('chats').doc(widget.chatId)
            .collection('messages').doc(oldId)
            .update({'pinned': false});
      }
    }
    await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId)
        .collection('messages').doc(msg.id)
        .update({'pinned': true});
    if (mounted) setState(() => _pinnedMessage = {'id': msg.id, 'text': msg.text});
  }

  Future<void> _unpinMessage() async {
    if (_pinnedMessage == null) return;
    final id = _pinnedMessage!['id'] as String?;
    if (id != null) {
      await FirebaseFirestore.instance
          .collection('chats').doc(widget.chatId)
          .collection('messages').doc(id)
          .update({'pinned': false});
    }
    if (mounted) setState(() => _pinnedMessage = null);
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final replyTarget = _replyTarget;
    setState(() {
      _ctrl.clear();
      _hasText = false;
      _replyTarget = null;
    });
    ChatService.sendMessage(
      widget.chatId,
      text,
      replyToId: replyTarget?.id,
      replyToText: replyTarget?.text,
    );
    Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Typing ────────────────────────────────────────────────────────────────

  void _onTypingChanged(bool typing) {
    if (!_isDirect) return;
    if (typing == _myTyping) return;
    _myTyping = typing;
    ChatService.setTyping(widget.chatId, typing);
    _typingTimer?.cancel();
    if (typing) {
      // Auto-stop typing after 5s of no new keystrokes
      _typingTimer = Timer(const Duration(seconds: 5), () {
        _myTyping = false;
        ChatService.setTyping(widget.chatId, false);
      });
    }
  }

  // ── Reply ─────────────────────────────────────────────────────────────────

  void _setReply(_Msg msg) {
    HapticFeedback.mediumImpact();
    setState(() => _replyTarget = msg);
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _clearReply() => setState(() => _replyTarget = null);

  // ── Reactions ─────────────────────────────────────────────────────────────

  void _showReactionPicker(_Msg msg) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EmojiReactionSheet(
        onPick: (emoji) => ChatService.toggleReaction(widget.chatId, msg.id, emoji),
      ),
    );
  }

  // ── Voice note ────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    HapticFeedback.heavyImpact();
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;
    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() { _recording = true; _recordStart = DateTime.now(); });
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    HapticFeedback.lightImpact();
    final path = await _recorder.stop();
    final duration = _recordStart != null
        ? DateTime.now().difference(_recordStart!)
        : Duration.zero;
    setState(() { _recording = false; _recordStart = null; });
    if (cancel || path == null) return;

    // Format duration string
    final s   = duration.inSeconds;
    final dur = '${(s ~/ 60).toString().padLeft(1, '0')}:${(s % 60).toString().padLeft(2, '0')}';

    // Upload to Firebase Storage
    try {
      final ref = FirebaseStorage.instance
          .ref('voice_notes/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}.m4a');
      await ref.putFile(File(path));
      final url = await ref.getDownloadURL();
      await ChatService.sendMessage(
        widget.chatId, '🎤 Voice message ($dur)',
        type: 'voice', audioUrl: url, voiceDuration: dur,
      );
    } catch (_) {
      // upload failed silently
    }
    Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
  }

  // ── Smart summary ─────────────────────────────────────────────────────────

  bool get _showSummaryBanner {
    final name = widget.chatName.toLowerCase();
    final isGroup = name.contains('group') || name.contains('class') || name.contains('squad');
    return isGroup && !_summaryDismissed;
  }

  void _showSmartSummary() {
    String? summaryText;
    String? errorText;
    bool loading = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1A4A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSheet) {
          // Kick off the Claude call once, when sheet first builds
          if (loading && summaryText == null && errorText == null) {
            _fetchSummary().then((result) {
              setSheet(() { summaryText = result; loading = false; });
            }).catchError((e) {
              setSheet(() { errorText = 'Could not generate summary: $e'; loading = false; });
            });
          }

          return Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 42, height: 4,
                    decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                const Row(children: [
                  Icon(Icons.auto_awesome_rounded, color: Color(0xFFB794F4)),
                  SizedBox(width: 8),
                  Text('Smart Summary', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 14),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFFB794F4))),
                  )
                else if (errorText != null)
                  Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 14))
                else
                  ..._parseBullets(summaryText ?? '').map((b) => _SummaryPoint(b)),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withAlpha(40))),
                      child: const Text('Go to messages'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        setState(() => _summaryDismissed = true);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                      child: const Text('Mark as read'),
                    ),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<String> _fetchSummary() async {
    final snap = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(60)
        .get();

    final lines = snap.docs.reversed.map((d) {
      final data = d.data();
      final sender = data['senderName'] as String? ?? 'User';
      final text   = data['text'] as String? ?? '';
      return '$sender: $text';
    }).where((l) => l.split(': ').last.trim().isNotEmpty).toList();

    if (lines.isEmpty) return '• No messages yet to summarise.';

    return AiService.summarizeChat(messages: lines, chatName: widget.chatName);
  }

  List<String> _parseBullets(String text) {
    return text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => l.startsWith('•') ? l.substring(1).trim() : l)
        .toList();
  }

  // ── Contact / group info ──────────────────────────────────────────────────

  void _showContactInfo(BuildContext context) {
    final isGroup = !_isDirect;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactInfoSheet(
        name:    widget.chatName,
        chatId:  widget.chatId,
        otherUid: _otherUid,
        isGroup: isGroup,
        onVoiceCall: _isDirect ? () { Navigator.pop(context); _startCall(video: false); } : null,
        onVideoCall: _isDirect ? () { Navigator.pop(context); _startCall(video: true);  } : null,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Column(children: [
            const SizedBox(height: kToolbarHeight + 44),
            if (_showSummaryBanner)
              _SummaryBanner(
                count: 127,
                onTap: _showSmartSummary,
                onDismiss: () => setState(() => _summaryDismissed = true),
              ),
            if (_pinnedMessage != null)
              _PinnedBanner(
                text: _pinnedMessage!['text'] as String? ?? 'Pinned message',
                onTap: () {},
                onDismiss: _unpinMessage,
              ),
            Expanded(child: _buildMessages()),
            if (_replyTarget != null) _ReplyBar(
              msg: _replyTarget!,
              onClear: _clearReply,
            ),
            _recording ? _VoiceRecordBar(
              pulseAnim: _micPulse,
              onCancel: () => _stopRecording(cancel: true),
              onSend: () => _stopRecording(),
            ) : _buildInput(),
            if (_showEmojiKeyboard)
              EmojiPickerPanel(
                onEmojiSelected: (e) {
                  _ctrl.text += e;
                  _ctrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _ctrl.text.length));
                  setState(() => _hasText = _ctrl.text.trim().isNotEmpty);
                },
              ),
          ]),
        ]),
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: AppBar(
            backgroundColor: Colors.white.withAlpha(12),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            titleSpacing: 0,
            title: GestureDetector(
              onTap: () => _showContactInfo(context),
              child: Row(children: [
                _MiniAvatar(name: widget.chatName),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.chatName,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      _isTyping
                          ? _TypingIndicator(anim: _typingAnim)
                          : Row(children: [
                              Container(
                                  width: 7, height: 7,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFF34C759), shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              const Text('online',
                                  style: TextStyle(color: Colors.white60, fontSize: 12)),
                            ]),
                    ],
                  ),
                ),
              ]),
            ),
            actions: [
              if (!_searchMode) ...[
                IconButton(
                  icon: const Icon(Icons.search_rounded, color: Colors.white),
                  onPressed: () => setState(() => _searchMode = true),
                ),
                if (_isDirect) ...[
                  IconButton(
                    icon: const Icon(Icons.videocam_outlined, color: Colors.white),
                    onPressed: () => _startCall(video: true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.call_outlined, color: Colors.white),
                    onPressed: () => _startCall(video: false),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  onPressed: () => _showContactInfo(context),
                ),
              ] else ...[
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search messages…',
                      hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => setState(() {
                    _searchMode = false;
                    _searchQuery = '';
                    _searchCtrl.clear();
                  }),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Message list ──────────────────────────────────────────────────────────

  Widget _buildMessages() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ChatService.messagesStream(widget.chatId),
      builder: (ctx, snap) {
        final docs = snap.data ?? [];
        var messages = docs
            .where((d) => d['deleted'] != true)
            .map((d) => _Msg.fromFirestore(d, _myUid))
            .toList();

        // Filter by search query if active
        if (_searchQuery.isNotEmpty) {
          messages = messages
              .where((m) => m.text.toLowerCase().contains(_searchQuery))
              .toList();
        }

        // Scroll to bottom when new messages arrive
        if (snap.hasData) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        final firstUnreadIdx = messages.indexWhere((m) => !m.read && !m.sent);
        final unreadCount = firstUnreadIdx == -1
            ? 0
            : messages.skip(firstUnreadIdx).where((m) => !m.read && !m.sent).length;

        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          itemCount: messages.length,
          itemBuilder: (ctx, i) {
            final msg = messages[i];
            return Column(children: [
              if (i == 0) _DateChip('TODAY'),
              if (i == firstUnreadIdx && firstUnreadIdx != -1)
                _UnreadDivider(count: unreadCount),
              _SwipeableBubble(
                msg: msg,
                isStarred: _starred.contains(msg.id),
                onSwipe: () => _setReply(msg),
                onLongPress: () => _showContextMenu(msg),
              ),
            ]);
          },
        );
      },
    );
  }

  // ── Message context menu ──────────────────────────────────────────────────

  void _showContextMenu(_Msg msg) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MsgContextMenu(
        msg: msg,
        isStarred: _starred.contains(msg.id),
        onReply: () { Navigator.pop(context); _setReply(msg); },
        onReact: () { Navigator.pop(context); _showReactionPicker(msg); },
        onCopy: () {
          Navigator.pop(context);
          if (msg.text.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: msg.text));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Message copied'),
                backgroundColor: const Color(0xFF0A1A4A),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        onStar: () {
          Navigator.pop(context);
          if (_starred.contains(msg.id)) {
            ChatService.unstarMessage(msg.id);
          } else {
            ChatService.starMessage(widget.chatId, msg.id, msg.text);
          }
        },
        onForward: () {
          Navigator.pop(context);
          _showForwardSheet(msg);
        },
        onEdit: msg.sent && !msg.isImage && !msg.isVoice ? () {
          Navigator.pop(context);
          _showEditDialog(msg);
        } : null,
        onPin: () {
          Navigator.pop(context);
          _pinMessage(msg);
        },
        onInfo: msg.sent ? () {
          Navigator.pop(context);
          _showMessageInfo(msg);
        } : null,
        onDelete: () {
          Navigator.pop(context);
          ChatService.deleteMessage(widget.chatId, msg.id);
        },
      ),
    );
  }

  // ── Message info (seen by) ────────────────────────────────────────────────

  void _showMessageInfo(_Msg msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('chats').doc(widget.chatId)
            .collection('messages').doc(msg.id).get(),
        builder: (ctx, snap) {
          final readBy = List<String>.from(
              snap.data?.get('readBy') as List? ?? []);
          final seenBy = readBy.where((uid) => uid != _myUid).toList();
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white.withAlpha(40),
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Row(children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFF4F8AFF), size: 20),
                SizedBox(width: 8),
                Text('Message Info',
                    style: TextStyle(color: Colors.white, fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 16),
              if (!snap.hasData)
                const CircularProgressIndicator(color: Color(0xFF4F8AFF))
              else if (seenBy.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Not read yet',
                      style: TextStyle(color: Colors.white.withAlpha(140))),
                )
              else
                ...seenBy.map((uid) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF1565C0),
                    child: Text(uid.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  title: Text(uid,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  trailing: const Icon(Icons.done_all_rounded,
                      color: Color(0xFF53BDEB), size: 16),
                )),
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
  }

  // ── Edit message dialog ───────────────────────────────────────────────────

  void _showEditDialog(_Msg msg) {
    final ctrl = TextEditingController(text: msg.text);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E1829),
        title: const Text('Edit message', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          maxLines: null,
          decoration: InputDecoration(
            hintText: 'Edit your message',
            hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withAlpha(40)),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF4F8AFF)),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
            onPressed: () {
              final newText = ctrl.text.trim();
              if (newText.isNotEmpty && newText != msg.text) {
                ChatService.editMessage(widget.chatId, msg.id, newText);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Forward message sheet ─────────────────────────────────────────────────

  void _showForwardSheet(_Msg msg) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ForwardSheet(
        msgText: msg.isVoice ? '🎤 Voice message' : msg.isImage ? '📷 Photo' : msg.text,
        onForwardTo: (chatId) {
          ChatService.sendMessage(
            chatId,
            msg.isVoice ? '🎤 Voice message' : msg.isImage ? '📷 Photo' : msg.text,
            type: msg.isVoice ? 'voice' : msg.isImage ? 'image' : 'text',
            imageUrl: msg.imageUrl,
            audioUrl: msg.audioUrl,
            voiceDuration: msg.voiceDuration,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message forwarded'),
              backgroundColor: Color(0xFF0A1A4A),
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────────

  Widget _buildInput() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(12),
            border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(18),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withAlpha(35)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                                icon: Icon(
                                  _showEmojiKeyboard
                                      ? Icons.keyboard_rounded
                                      : Icons.emoji_emotions_outlined,
                                  color: _showEmojiKeyboard
                                      ? const Color(0xFF4F8AFF)
                                      : Colors.white.withAlpha(160),
                                  size: 22,
                                ),
                                onPressed: () {
                                  setState(() => _showEmojiKeyboard = !_showEmojiKeyboard);
                                  if (_showEmojiKeyboard) {
                                    FocusScope.of(context).unfocus();
                                  }
                                }),
                            Expanded(
                              child: TextField(
                                controller: _ctrl,
                                maxLines: null,
                                style: const TextStyle(color: Colors.white, fontSize: 15),
                                decoration: InputDecoration(
                                  hintText: 'Message',
                                  hintStyle: TextStyle(color: Colors.white.withAlpha(100)),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  filled: false,
                                ),
                                onTap: () {
                                  if (_showEmojiKeyboard) setState(() => _showEmojiKeyboard = false);
                                },
                                onChanged: (v) {
                                  setState(() => _hasText = v.trim().isNotEmpty);
                                  _onTypingChanged(v.isNotEmpty);
                                },
                              ),
                            ),
                            IconButton(
                                icon: Icon(Icons.attach_file_rounded,
                                    color: Colors.white.withAlpha(160), size: 22),
                                onPressed: _showAttachSheet),
                            if (!_hasText)
                              IconButton(
                                icon: Icon(Icons.camera_alt_outlined,
                                    color: Colors.white.withAlpha(160), size: 22),
                                onPressed: () => _pickImage(source: ImageSource.camera),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _hasText ? _send : null,
                  onLongPressStart: _hasText ? null : (_) => _startRecording(),
                  onLongPressEnd:   _hasText ? null : (_) => _stopRecording(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color: _hasText
                          ? const Color(0xFF2563EB)
                          : Colors.white.withAlpha(25),
                      shape: BoxShape.circle,
                      boxShadow: _hasText
                          ? [BoxShadow(
                              color: const Color(0xFF2563EB).withAlpha(100),
                              blurRadius: 12)]
                          : [],
                    ),
                    child: Icon(
                      _hasText ? Icons.send_rounded : Icons.mic_rounded,
                      color: _hasText ? Colors.white : Colors.white.withAlpha(160),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Swipeable bubble wrapper ──────────────────────────────────────────────────

class _SwipeableBubble extends StatefulWidget {
  final _Msg msg;
  final bool isStarred;
  final VoidCallback onSwipe;
  final VoidCallback onLongPress;

  const _SwipeableBubble({
    required this.msg,
    required this.isStarred,
    required this.onSwipe,
    required this.onLongPress,
  });

  @override
  State<_SwipeableBubble> createState() => _SwipeableBubbleState();
}

class _SwipeableBubbleState extends State<_SwipeableBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  double _drag = 0;
  bool _triggered = false;
  static const _threshold = 60.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    final delta = d.primaryDelta ?? 0;
    // Only allow rightward swipe
    if (delta < 0 && _drag <= 0) return;
    setState(() {
      _drag = (_drag + delta).clamp(0.0, _threshold + 10);
    });
    if (_drag >= _threshold && !_triggered) {
      _triggered = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onHorizontalEnd(DragEndDetails _) {
    if (_triggered) widget.onSwipe();
    _triggered = false;
    setState(() => _drag = 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalUpdate,
      onHorizontalDragEnd: _onHorizontalEnd,
      onLongPress: widget.onLongPress,
      child: Transform.translate(
        offset: Offset(_drag * 0.5, 0),
        child: Stack(children: [
          if (_drag > 10)
            Positioned(
              left: widget.msg.sent ? null : 4,
              right: widget.msg.sent ? 4 : null,
              top: 0, bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: (_drag / _threshold).clamp(0.0, 1.0),
                  child: const Icon(Icons.reply_rounded, color: Colors.white54, size: 20),
                ),
              ),
            ),
          _Bubble(msg: widget.msg),
        ]),
      ),
    );
  }
}

// ── Bubble ─────────────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final _Msg msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: msg.sent ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            msg.sent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(
              top: 2, bottom: msg.reactions != null ? 2 : 4,
              left: msg.sent ? 56 : 0,
              right: msg.sent ? 0 : 56,
            ),
            decoration: BoxDecoration(
              color: msg.sent
                  ? const Color(0xFF2563EB).withAlpha(200)
                  : Colors.white.withAlpha(20),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(msg.sent ? 16 : 4),
                bottomRight: Radius.circular(msg.sent ? 4 : 16),
              ),
              border: Border.all(color: Colors.white.withAlpha(msg.sent ? 30 : 20)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(msg.sent ? 16 : 4),
                bottomRight: Radius.circular(msg.sent ? 4 : 16),
              ),
              child: _bubbleContent(),
            ),
          ),
          // Reactions row
          if (msg.reactions != null && msg.reactions!.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                  bottom: 6,
                  left: msg.sent ? 56 : 4,
                  right: msg.sent ? 4 : 56),
              child: _ReactionsRow(reactions: msg.reactions!),
            ),
        ],
      ),
    );
  }

  Widget _bubbleContent() {
    if (msg.isImage) return _ImageBubble(msg: msg);
    if (msg.isVoice) return _VoiceBubble(msg: msg);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sender name (group chats, received only)
          if (!msg.sent && msg.senderName != null && msg.senderName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                msg.senderName!,
                style: const TextStyle(
                  color: Color(0xFF86EFAC),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // Quote reply
          if (msg.replyTo != null)
            _QuotePreview(original: msg.replyTo!, isSentBubble: msg.sent),
          Text(
            msg.text,
            style: const TextStyle(fontSize: 14.5, color: Colors.white, height: 1.4),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (msg.edited)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text('edited',
                      style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(110))),
                ),
              _TimeRow(msg: msg),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Image bubble ──────────────────────────────────────────────────────────────

class _ImageBubble extends StatelessWidget {
  final _Msg msg;
  const _ImageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.sent ? 16 : 4),
            bottomRight: Radius.circular(msg.sent ? 4 : 16),
          ),
          child: msg.imageUrl != null && msg.imageUrl!.isNotEmpty
              ? GestureDetector(
                  onTap: () => _showFullImage(context, msg.imageUrl!),
                  child: Image.network(
                    msg.imageUrl!,
                    width: 220, height: 180,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, prog) => prog == null
                        ? child
                        : Container(
                            width: 220, height: 180,
                            color: Colors.black26,
                            child: Center(child: CircularProgressIndicator(
                              value: prog.expectedTotalBytes != null
                                  ? prog.cumulativeBytesLoaded /
                                    prog.expectedTotalBytes!
                                  : null,
                              color: Colors.white54, strokeWidth: 2,
                            )),
                          ),
                    errorBuilder: (ctx2, err, st) => Container(
                      width: 220, height: 100,
                      color: Colors.black26,
                      child: const Icon(Icons.broken_image_outlined,
                          color: Colors.white54, size: 36),
                    ),
                  ),
                )
              : Container(
                  width: 220, height: 120,
                  color: Colors.black26,
                  child: const Center(
                    child: Icon(Icons.image_rounded,
                        color: Colors.white54, size: 40),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: _TimeRow(msg: msg, onDark: true),
        ),
      ],
    );
  }

  void _showFullImage(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }
}

// ── Voice bubble ──────────────────────────────────────────────────────────────

class _VoiceBubble extends StatefulWidget {
  final _Msg msg;
  const _VoiceBubble({required this.msg});

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  late final AudioPlayer _player;
  bool   _playing  = false;
  double _progress = 0;
  String _posLabel = '0:00';

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.positionStream.listen((pos) {
      final total = _player.duration?.inMilliseconds ?? 1;
      if (total > 0 && mounted) {
        final s = pos.inSeconds;
        setState(() {
          _progress = pos.inMilliseconds / total;
          _posLabel = '${(s ~/ 60)}:${(s % 60).toString().padLeft(2, '0')}';
        });
      }
    });
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        setState(() { _playing = false; _progress = 0; _posLabel = '0:00'; });
        _player.seek(Duration.zero);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.msg.audioUrl;
    if (url == null || url.isEmpty) return;
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      if (_player.processingState == ProcessingState.idle) {
        await _player.setUrl(url);
      }
      await _player.play();
      setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = (widget.msg.audioUrl ?? '').isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: hasAudio ? _toggle : null,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: hasAudio ? Colors.white.withAlpha(30) : Colors.white.withAlpha(15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: hasAudio ? Colors.white : Colors.white.withAlpha(80),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Waveform bars with progress
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(20, (i) {
                    final active = (i / 20) <= _progress;
                    final h = (4 + (i % 3) * 5 + (i % 5) * 3).toDouble().clamp(4.0, 18.0);
                    return Container(
                      width: 3, height: h,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white.withAlpha(60),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Text(
                  _playing ? _posLabel : (widget.msg.voiceDuration ?? '0:00'),
                  style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _TimeRow(msg: widget.msg),
        ],
      ),
    );
  }
}

// ── Quote preview inside a bubble ─────────────────────────────────────────────

class _QuotePreview extends StatelessWidget {
  final _Msg original;
  final bool isSentBubble;
  const _QuotePreview({required this.original, required this.isSentBubble});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isSentBubble ? Colors.white : const Color(0xFF4F8AFF),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            original.sent ? 'You' : 'Them',
            style: TextStyle(
              color: isSentBubble ? Colors.white : const Color(0xFF4F8AFF),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            original.isVoice
                ? '🎤 Voice message'
                : original.isImage
                    ? '📷 Photo'
                    : original.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Reply bar (above input) ───────────────────────────────────────────────────

class _ReplyBar extends StatelessWidget {
  final _Msg msg;
  final VoidCallback onClear;
  const _ReplyBar({required this.msg, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(20)),
          left: const BorderSide(color: Color(0xFF4F8AFF), width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.sent ? 'You' : 'Them',
                  style: const TextStyle(
                      color: Color(0xFF4F8AFF),
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  msg.isVoice
                      ? '🎤 Voice message'
                      : msg.isImage
                          ? '📷 Photo'
                          : msg.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClear,
            icon: Icon(Icons.close_rounded, color: Colors.white.withAlpha(150), size: 20),
          ),
        ],
      ),
    );
  }
}

// ── Voice recording bar ───────────────────────────────────────────────────────

class _VoiceRecordBar extends StatelessWidget {
  final AnimationController pulseAnim;
  final VoidCallback onCancel;
  final VoidCallback onSend;
  const _VoiceRecordBar({
    required this.pulseAnim,
    required this.onCancel,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(12),
            border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SafeArea(
            top: false,
            child: Row(children: [
              GestureDetector(
                onTap: onCancel,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AnimatedBuilder(
                  animation: pulseAnim,
                  builder: (_, _) => Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: Color.lerp(Colors.redAccent, Colors.red.shade200,
                              pulseAnim.value),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recording...',
                        style: TextStyle(
                          color: Colors.white.withAlpha(200),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: onSend,
                child: Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF2563EB).withAlpha(100),
                          blurRadius: 12)
                    ],
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Reactions row ─────────────────────────────────────────────────────────────

class _ReactionsRow extends StatelessWidget {
  final Map<String, int> reactions;
  const _ReactionsRow({required this.reactions});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: reactions.entries.map((e) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(25)),
        ),
        child: Text(
          e.value > 1 ? '${e.key} ${e.value}' : e.key,
          style: const TextStyle(fontSize: 13),
        ),
      )).toList(),
    );
  }
}

// ── Time row (timestamp + read receipt) ──────────────────────────────────────

class _TimeRow extends StatelessWidget {
  final _Msg msg;
  final bool onDark;
  const _TimeRow({required this.msg, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final tint = onDark ? Colors.white : Colors.white.withAlpha(160);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(msg.time, style: TextStyle(fontSize: 11, color: tint)),
      if (msg.sent) ...[
        const SizedBox(width: 3),
        Icon(Icons.done_all_rounded, size: 14,
            color: msg.read ? const Color(0xFF53BDEB) : tint),
      ],
    ]);
  }
}

// ── Pinned message banner ─────────────────────────────────────────────────────

class _PinnedBanner extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  const _PinnedBanner({required this.text, required this.onTap, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E40AF).withAlpha(40),
          border: Border(
            bottom: BorderSide(color: Colors.white.withAlpha(15)),
            left: const BorderSide(color: Color(0xFF4F8AFF), width: 3),
          ),
        ),
        child: Row(children: [
          const Icon(Icons.push_pin_rounded, color: Color(0xFF4F8AFF), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.close_rounded, color: Colors.white.withAlpha(120), size: 18),
            onPressed: onDismiss,
          ),
        ]),
      ),
    );
  }
}

// ── Summary banner ────────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  const _SummaryBanner({required this.count, required this.onTap, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: GlassCard(
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        bgColor: const Color(0xFF7C3AED).withAlpha(20),
        borderColor: const Color(0xFFB794F4).withAlpha(65),
        child: Row(children: [
          const Icon(Icons.summarize_outlined, color: Color(0xFFB794F4), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Text('$count unread messages. Tap to summarize',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
          IconButton(
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            onPressed: onDismiss,
            icon: Icon(Icons.close_rounded, color: Colors.white.withAlpha(150), size: 18),
          ),
        ]),
      ),
    );
  }
}

class _SummaryPoint extends StatelessWidget {
  final String text;
  const _SummaryPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('•',
            style: TextStyle(color: Color(0xFF86EFAC), fontSize: 18, height: 1)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(color: Colors.white.withAlpha(180), height: 1.35))),
      ]),
    );
  }
}

// ── Date chip ─────────────────────────────────────────────────────────────────

class _DateChip extends StatelessWidget {
  final String label;
  const _DateChip(this.label);

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: Colors.white.withAlpha(180),
              fontWeight: FontWeight.w500)),
    ),
  );
}

// ── Mini avatar ───────────────────────────────────────────────────────────────

class _MiniAvatar extends StatelessWidget {
  final String name;
  const _MiniAvatar({required this.name});
  static const _colors = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
    Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
  ];

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 18,
    backgroundColor: _colors[name.codeUnitAt(0) % _colors.length],
    child: Text(name[0].toUpperCase(),
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
  );
}

// ── Data model ────────────────────────────────────────────────────────────────

class _Msg {
  final String id;
  final String text;
  final String time;
  final bool sent;
  final bool read;
  final bool isImage;
  final bool isVoice;
  final bool edited;
  final String? imageUrl;
  final String? audioUrl;
  final String? imageLabel;
  final String? voiceDuration;
  final String? senderName;
  final _Msg? replyTo;
  final Map<String, int>? reactions;

  const _Msg({
    required this.id,
    required this.text,
    required this.sent,
    required this.time,
    required this.read,
    this.isImage = false,
    this.isVoice = false,
    this.edited = false,
    this.imageUrl,
    this.audioUrl,
    this.imageLabel,
    this.voiceDuration,
    this.senderName,
    this.replyTo,
    this.reactions,
  });

  _Msg copyWith({Map<String, int>? reactions}) => _Msg(
    id: id, text: text, sent: sent, time: time, read: read,
    isImage: isImage, isVoice: isVoice, edited: edited, imageUrl: imageUrl,
    audioUrl: audioUrl, imageLabel: imageLabel, senderName: senderName,
    voiceDuration: voiceDuration, replyTo: replyTo,
    reactions: reactions ?? this.reactions,
  );

  factory _Msg.fromFirestore(Map<String, dynamic> d, String myUid) {
    final ts     = d['createdAt'] as Timestamp?;
    final dt     = ts?.toDate() ?? DateTime.now();
    final h      = dt.hour.toString().padLeft(2, '0');
    final m      = dt.minute.toString().padLeft(2, '0');
    final readBy = List<String>.from(d['readBy'] as List? ?? []);
    final type   = d['type'] as String? ?? 'text';
    final rawReactions = d['reactions'] as Map<dynamic, dynamic>? ?? {};
    final reactions = rawReactions.map<String, int>((k, v) {
      final users = v is List ? v : [];
      return MapEntry(k.toString(), users.length);
    });

    _Msg? replyTo;
    if ((d['replyToText'] as String?)?.isNotEmpty == true) {
      replyTo = _Msg(
        id: d['replyToId'] as String? ?? '',
        text: d['replyToText'] as String,
        sent: false, time: '', read: true,
      );
    }

    return _Msg(
      id:            d['id'] as String,
      text:          d['text'] as String? ?? '',
      sent:          d['senderUid'] == myUid,
      time:          '$h:$m',
      read:          readBy.any((uid) => uid != myUid),
      isImage:       type == 'image',
      isVoice:       type == 'voice',
      edited:        (d['edited'] as bool?) == true,
      imageUrl:      d['imageUrl'] as String?,
      audioUrl:      d['audioUrl'] as String?,
      voiceDuration: d['voiceDuration'] as String? ?? (type == 'voice' ? '0:00' : null),
      senderName:    d['senderName'] as String?,
      replyTo:       replyTo,
      reactions:     reactions.isEmpty ? null : reactions,
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AttachOption({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(
        width: 60, height: 60,
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          shape: BoxShape.circle,
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
      const SizedBox(height: 8),
      Text(label, style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _TypingIndicator extends StatelessWidget {
  final AnimationController anim;
  const _TypingIndicator({required this.anim});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: anim,
          builder: (_, _) {
            final phase = ((anim.value + i * 0.3) % 1.0);
            final opacity = (0.3 + phase * 0.7).clamp(0.3, 1.0);
            return Container(
              width: 5, height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: Colors.white60.withAlpha((opacity * 255).toInt()),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}

// ── Unread messages divider ───────────────────────────────────────────────────

class _UnreadDivider extends StatelessWidget {
  final int count;
  const _UnreadDivider({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(child: Divider(color: const Color(0xFF4F8AFF).withAlpha(80), thickness: 1)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withAlpha(40),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(80)),
          ),
          child: Text(
            '$count unread message${count == 1 ? '' : 's'}',
            style: const TextStyle(
              color: Color(0xFF93C5FD),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: const Color(0xFF4F8AFF).withAlpha(80), thickness: 1)),
      ]),
    );
  }
}

// ── Message context menu ──────────────────────────────────────────────────────

class _MsgContextMenu extends StatelessWidget {
  final _Msg msg;
  final bool isStarred;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback onCopy;
  final VoidCallback onStar;
  final VoidCallback onForward;
  final VoidCallback? onEdit;
  final VoidCallback? onPin;
  final VoidCallback? onInfo;
  final VoidCallback onDelete;

  const _MsgContextMenu({
    required this.msg,
    required this.isStarred,
    required this.onReply,
    required this.onReact,
    required this.onCopy,
    required this.onStar,
    required this.onForward,
    this.onEdit,
    this.onPin,
    this.onInfo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E1829),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Quick emoji reactions row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['👍','❤️','😂','😮','😢','🙏','🔥','👏'].map((e) =>
                GestureDetector(
                  onTap: () { onReact(); },
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                  ),
                ),
              ).toList(),
            ),
          ),
          Divider(color: Colors.white.withAlpha(14), height: 1),
          _MenuItem(icon: Icons.reply_rounded,         label: 'Reply',              onTap: onReply),
          _MenuItem(icon: Icons.add_reaction_outlined,  label: 'React',              onTap: onReact),
          if (msg.text.isNotEmpty)
            _MenuItem(icon: Icons.copy_rounded,         label: 'Copy',               onTap: onCopy),
          _MenuItem(
            icon: isStarred ? Icons.star_rounded : Icons.star_border_rounded,
            label: isStarred ? 'Unstar' : 'Star',
            iconColor: isStarred ? const Color(0xFFFFD700) : null,
            onTap: onStar,
          ),
          _MenuItem(icon: Icons.forward_rounded,        label: 'Forward',            onTap: onForward),
          if (onEdit != null)
            _MenuItem(icon: Icons.edit_outlined,        label: 'Edit',               onTap: onEdit!),
          if (onPin != null)
            _MenuItem(icon: Icons.push_pin_outlined,    label: 'Pin message',        onTap: onPin!),
          if (onInfo != null)
            _MenuItem(icon: Icons.info_outline_rounded, label: 'Message info',       onTap: onInfo!),
          _MenuItem(icon: Icons.delete_outline_rounded, label: 'Delete',
            labelColor: Colors.redAccent, iconColor: Colors.redAccent, onTap: onDelete),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? labelColor;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? Colors.white70;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 22),
      title: Text(label,
        style: TextStyle(color: labelColor ?? Colors.white, fontSize: 15)),
      onTap: onTap,
    );
  }
}

// ── Contact / Group info sheet ────────────────────────────────────────────────

class _ContactInfoSheet extends StatefulWidget {
  final String   name, chatId, otherUid;
  final bool     isGroup;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;

  const _ContactInfoSheet({
    required this.name,
    required this.chatId,
    required this.otherUid,
    required this.isGroup,
    this.onVoiceCall,
    this.onVideoCall,
  });

  @override
  State<_ContactInfoSheet> createState() => _ContactInfoSheetState();
}

class _ContactInfoSheetState extends State<_ContactInfoSheet> {
  Map<String, dynamic>? _profile;
  bool _isBlocked = false;
  bool _isMuted   = false;
  List<Map<String, dynamic>> _mediaItems = [];

  @override
  void initState() {
    super.initState();
    if (!widget.isGroup && widget.otherUid.isNotEmpty) _loadProfile();
    _loadChatMeta();
    _loadMedia();
  }

  Future<void> _loadProfile() async {
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(widget.otherUid).get();
    if (mounted) setState(() => _profile = doc.data());
  }

  Future<void> _loadChatMeta() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // Check blocked status
    if (!widget.isGroup && widget.otherUid.isNotEmpty) {
      final blockedDoc = await FirebaseFirestore.instance
          .collection('users').doc(myUid).collection('blocked').doc(widget.otherUid).get();
      if (mounted) setState(() => _isBlocked = blockedDoc.exists);
    }
    // Check mute status
    final chatDoc = await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId).get();
    if (mounted && chatDoc.exists) {
      final muted = Map<String, dynamic>.from(chatDoc.data()?['muted'] as Map? ?? {});
      setState(() => _isMuted = (muted[myUid] as bool?) == true);
    }
  }

  Future<void> _loadMedia() async {
    final snap = await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId).collection('messages')
        .where('type', isEqualTo: 'image')
        .orderBy('createdAt', descending: true)
        .limit(12)
        .get();
    if (mounted) {
      setState(() => _mediaItems = snap.docs
          .map((d) => {'imageUrl': d.data()['imageUrl'] as String? ?? ''})
          .where((m) => (m['imageUrl'] as String).isNotEmpty)
          .toList());
    }
  }

  Future<void> _toggleBlock() async {
    if (_isBlocked) {
      await ChatService.unblockUser(widget.otherUid);
    } else {
      await ChatService.blockUser(widget.otherUid);
    }
    setState(() => _isBlocked = !_isBlocked);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isBlocked
            ? '${widget.name.split(' ').first} has been blocked'
            : '${widget.name.split(' ').first} has been unblocked'),
        backgroundColor: const Color(0xFF0A1A4A),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _toggleMute() async {
    await ChatService.muteChat(widget.chatId, !_isMuted);
    setState(() => _isMuted = !_isMuted);
  }

  static const _kColors = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
    Color(0xFFAD1457), Color(0xFFE65100), Color(0xFF00695C),
  ];

  Color get _avatarColor => _kColors[widget.name.codeUnitAt(0) % _kColors.length];

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _profile?['photoUrl'] as String? ?? '';
    final phone    = _profile?['phoneNumber'] as String? ?? '';
    final about    = _profile?['about'] as String? ?? 'Hey there! I am using ZCHAT.';
    final role     = _profile?['role'] as String? ?? 'student';

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E1829),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(
          controller: ctrl,
          padding: EdgeInsets.zero,
          children: [
            // Handle
            Center(child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2))),
            )),
            // Avatar + name
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: _avatarColor,
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty
                      ? (widget.isGroup
                          ? const Icon(Icons.group_rounded, color: Colors.white, size: 38)
                          : Text(_initials(widget.name),
                              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)))
                      : null,
                ),
                const SizedBox(height: 12),
                Text(widget.name,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  widget.isGroup ? 'Group' : role == 'lecturer' ? 'Lecturer' : 'Student',
                  style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13),
                ),
              ]),
            ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                if (!widget.isGroup) ...[
                  _InfoAction(icon: Icons.call_outlined,     label: 'Call',  onTap: widget.onVoiceCall),
                  _InfoAction(icon: Icons.videocam_outlined, label: 'Video', onTap: widget.onVideoCall),
                ],
                _InfoAction(icon: Icons.search_rounded,             label: 'Search', onTap: () {}),
                _InfoAction(icon: Icons.notifications_outlined,     label: 'Mute',   onTap: () {}),
              ]),
            ),
            Divider(color: Colors.white.withAlpha(12), height: 28),
            // Phone / about (1:1 only)
            if (!widget.isGroup) ...[
              if (phone.isNotEmpty)
                _InfoTile(icon: Icons.phone_outlined, title: phone, subtitle: 'Mobile'),
              _InfoTile(icon: Icons.info_outline_rounded, title: about, subtitle: 'About'),
              Divider(color: Colors.white.withAlpha(12), height: 28),
            ],
            // Media strip
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Text('Media, links & docs',
                  style: TextStyle(color: Colors.white.withAlpha(180), fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                Text('${_mediaItems.length}',
                    style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 13)),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF4F8AFF), size: 18),
              ]),
            ),
            SizedBox(
              height: 80,
              child: _mediaItems.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(child: Text('No media shared yet',
                          style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 13))),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _mediaItems.length,
                      itemBuilder: (_, i) => Container(
                        width: 80, height: 80,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            _mediaItems[i]['imageUrl'] as String,
                            fit: BoxFit.cover,
                            errorBuilder: (_, e, s) => Icon(
                                Icons.image_outlined,
                                color: Colors.white.withAlpha(60), size: 30),
                          ),
                        ),
                      ),
                    ),
            ),
            Divider(color: Colors.white.withAlpha(12), height: 28),
            // Mute / Block / Delete
            ListTile(
              leading: Icon(
                _isMuted ? Icons.notifications_rounded : Icons.volume_off_outlined,
                color: _isMuted ? const Color(0xFF4F8AFF) : Colors.white70,
              ),
              title: Text(_isMuted ? 'Unmute notifications' : 'Mute notifications',
                  style: const TextStyle(color: Colors.white)),
              onTap: _toggleMute,
            ),
            if (!widget.isGroup)
              ListTile(
                leading: Icon(Icons.block_rounded,
                    color: _isBlocked ? Colors.redAccent : Colors.orangeAccent),
                title: Text(
                  _isBlocked
                      ? 'Unblock ${widget.name.split(' ').first}'
                      : 'Block ${widget.name.split(' ').first}',
                  style: TextStyle(
                      color: _isBlocked ? Colors.redAccent : Colors.orangeAccent),
                ),
                onTap: _toggleBlock,
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: Text(widget.isGroup ? 'Leave group' : 'Delete chat',
                style: const TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                if (widget.isGroup) {
                  ChatService.leaveGroup(widget.chatId);
                } else {
                  ChatService.deleteChat(widget.chatId);
                }
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _InfoAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _InfoAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: onTap != null
                ? const Color(0xFF4F8AFF).withAlpha(25)
                : Colors.white.withAlpha(12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: onTap != null
                ? const Color(0xFF4F8AFF).withAlpha(60)
                : Colors.white.withAlpha(20)),
          ),
          child: Icon(icon,
            color: onTap != null ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(80),
            size: 22),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12)),
      ]),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoTile({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF4F8AFF)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12)),
    );
  }
}

// ── Forward sheet ─────────────────────────────────────────────────────────────

class _ForwardSheet extends StatefulWidget {
  final String msgText;
  final void Function(String chatId) onForwardTo;
  const _ForwardSheet({required this.msgText, required this.onForwardTo});

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E1829),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          // Handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(2)),
            )),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              Icon(Icons.forward_rounded, color: Color(0xFF4F8AFF), size: 22),
              SizedBox(width: 10),
              Text('Forward to',
                  style: TextStyle(color: Colors.white, fontSize: 17,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          Divider(color: Colors.white.withAlpha(14), height: 1),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: ChatService.chatsStream(),
              builder: (ctx, snap) {
                final chats = snap.data ?? [];
                if (chats.isEmpty) {
                  return Center(child: Text('No conversations yet',
                      style: TextStyle(color: Colors.white.withAlpha(100))));
                }
                return ListView.builder(
                  controller: ctrl,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: chats.length,
                  itemBuilder: (_, i) {
                    final chat = chats[i];
                    final name = ChatService.getChatDisplayName(chat);
                    final isGroup = chat['type'] == 'group';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF1565C0),
                        child: isGroup
                            ? const Icon(Icons.group_rounded, color: Colors.white, size: 20)
                            : Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                      ),
                      title: Text(name,
                          style: const TextStyle(color: Colors.white, fontSize: 15)),
                      subtitle: Text(isGroup ? 'Group' : 'Direct message',
                          style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onForwardTo(chat['id'] as String);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
