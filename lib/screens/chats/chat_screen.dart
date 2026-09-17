import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../screens/calls/outgoing_call_screen.dart';
import '../../screens/classroom/live_session_screen.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config.dart';
import '../../services/ai_service.dart';
import '../../services/auto_download_service.dart';
import '../../services/chat_service.dart';
import '../../services/presence_service.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  bool _hasText = false;
  bool _summaryDismissed = false;
  int  _unreadCount = 0;
  bool _showEmojiKeyboard = false;
  int  _pageLimit = 50; // messages loaded; grows when the user loads older

  // @mentions (group chats)
  final List<Map<String, String>> _groupMembers = []; // {uid, name}
  String? _mentionQuery;                                // active @query, null = off
  final Set<String> _pendingMentions = {};             // uids selected via @
  bool _sendBlocked = false;                            // group is admins-only & I'm not admin

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

  // Delete-for-me set (local + loaded from Firestore)
  final _deletedForMe = <String>{};

  // Chat wallpaper (color int from SharedPreferences)
  int? _wallpaperColor;

  // Search in chat
  bool _searchMode = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  // Pinned message
  Map<String, dynamic>? _pinnedMessage;

  // Presence (gap 3)
  bool   _isOnline     = false;
  String _lastSeenText = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _presenceSub;

  // Disappearing messages enforcement (gap 8)
  String _disappearing = 'off';

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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to send document: ${e.toString().replaceFirst("Exception: ", "")}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  Future<void> _pickImage({ImageSource source = ImageSource.gallery}) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 75);
    if (picked == null || !mounted) return;
    final result = await _showCaptionSheet(File(picked.path));
    if (result == null) return;
    await ChatService.sendImage(widget.chatId, File(picked.path),
        caption: result['caption'] as String? ?? '',
        viewOnce: result['viewOnce'] as bool? ?? false);
    Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
  }

  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 10));
    if (picked == null || !mounted) return;
    try {
      final file = File(picked.path);
      final fileName = picked.name;
      final ref = FirebaseStorage.instance
          .ref('chat_videos/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_$fileName');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await ChatService.sendMessage(
        widget.chatId,
        '🎥 Video',
        type: 'video',
        imageUrl: url,
      );
      Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to send video: ${e.toString().replaceFirst("Exception: ", "")}'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _shareLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Location permission is needed to share your location.'),
            behavior: SnackBarBehavior.floating));
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      await ChatService.sendLocation(widget.chatId, pos.latitude, pos.longitude);
      Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not get your location: ${e.toString().replaceFirst('Exception: ', '')}'),
          behavior: SnackBarBehavior.floating));
      }
    }
  }

  void _showPollComposer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _PollComposerSheet(
          onSubmit: (q, opts, multi) {
            ChatService.sendPoll(widget.chatId, q, opts, multi: multi);
            Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
          },
        ),
      ),
    );
  }

  void _showEventComposer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _EventComposerSheet(
          onSubmit: (title, dt, loc, desc, addCall) {
            ChatService.sendEvent(
              widget.chatId,
              title: title,
              dateTime: dt,
              location: loc,
              description: desc,
              callRoomId: addCall ? 'event_${widget.chatId}_${DateTime.now().millisecondsSinceEpoch}' : null,
            );
            Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
          },
        ),
      ),
    );
  }

  Future<void> _pickContact() async {
    try {
      final status = await Permission.contacts.request();
      if (!status.isGranted || !mounted) return;
      final all = await FlutterContacts.getAll(
          properties: ContactProperties.allProperties);
      if (!mounted) return;
      final selected = await showModalBottomSheet<Contact>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF0E1829),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _ContactPickerSheet(contacts: all),
      );
      if (selected == null || !mounted) return;
      final name  = selected.displayName;
      final phone = selected.phones.isNotEmpty
          ? selected.phones.first.number
          : '';
      await ChatService.sendMessage(
        widget.chatId,
        '$name\n$phone',
        type: 'contact',
      );
      Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
    } catch (_) {}
  }

  static const _kStickers = [
    '😂','😍','🥰','😎','🤩','😭','🥺','😡',
    '👍','❤️','🔥','🎉','💯','✨','🙏','👏',
    '😴','🤔','😅','😇','🤣','💪','🎓','📚',
    '🏆','⭐','🌟','💡','📝','🎵','🍕','😂',
  ];

  // Tenor v2 (Google). Key comes from AppConfig.tenorKey (--dart-define=TENOR_KEY).
  // v1 was shut down by Google; v2 returns media in `media_formats`.
  Future<List<String>> _searchGifs(String query) async {
    if (AppConfig.tenorKey.isEmpty) return [];
    final q = Uri.encodeComponent(query.isEmpty ? 'trending' : query);
    final url = 'https://tenor.googleapis.com/v2/search'
        '?q=$q&key=${AppConfig.tenorKey}&limit=20&media_filter=tinygif,gif&client_key=zchat';
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map;
      final results = body['results'] as List? ?? [];
      return results
          .map((r) {
            final formats = r['media_formats'] as Map? ?? {};
            final tiny = formats['tinygif'] as Map?;
            final full = formats['gif'] as Map?;
            return ((tiny?['url'] ?? full?['url']) as String?) ?? '';
          })
          .where((u) => u.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _showGifPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _GifPickerSheet(
        onSelected: (url) {
          ChatService.sendMessage(widget.chatId, '🎞️ GIF', type: 'image', imageUrl: url);
          Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
        },
        searchGifs: _searchGifs,
      ),
    );
  }

  void _showStickerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1829),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8, mainAxisSpacing: 8, crossAxisSpacing: 8),
              itemCount: _kStickers.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  ChatService.sendMessage(widget.chatId, _kStickers[i], type: 'sticker');
                  Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
                },
                child: Text(_kStickers[i], style: const TextStyle(fontSize: 28),
                    textAlign: TextAlign.center),
              ),
            ),
          ),
        ]),
      ),
    );
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
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 18, children: [
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
              _AttachOption(
                icon: Icons.videocam_rounded,
                label: 'Video',
                color: const Color(0xFFF87171),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
                },
              ),
              if (AppConfig.gifEnabled)
                _AttachOption(
                  icon: Icons.gif_box_outlined,
                  label: 'GIF',
                  color: const Color(0xFFA78BFA),
                  onTap: () {
                    Navigator.pop(context);
                    _showGifPicker();
                  },
                ),
              _AttachOption(
                icon: Icons.person_rounded,
                label: 'Contact',
                color: const Color(0xFF34D399),
                onTap: () {
                  Navigator.pop(context);
                  _pickContact();
                },
              ),
              _AttachOption(
                icon: Icons.sticky_note_2_outlined,
                label: 'Sticker',
                color: const Color(0xFFF472B6),
                onTap: () {
                  Navigator.pop(context);
                  _showStickerPicker();
                },
              ),
              _AttachOption(
                icon: Icons.location_on_outlined,
                label: 'Location',
                color: const Color(0xFFEF4444),
                onTap: () {
                  Navigator.pop(context);
                  _shareLocation();
                },
              ),
              _AttachOption(
                icon: Icons.poll_outlined,
                label: 'Poll',
                color: const Color(0xFF60A5FA),
                onTap: () {
                  Navigator.pop(context);
                  _showPollComposer();
                },
              ),
              _AttachOption(
                icon: Icons.event_rounded,
                label: 'Event',
                color: const Color(0xFFFB923C),
                onTap: () {
                  Navigator.pop(context);
                  _showEventComposer();
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
    _loadDisappearing();
    if (!_isDirect) _loadGroupMembers();
    _loadSummaryDismissed();
    ChatService.getDeletedForMeIds(widget.chatId).then((ids) {
      if (mounted) setState(() => _deletedForMe.addAll(ids));
    });
    SharedPreferences.getInstance().then((p) {
      final c = p.getInt('wallpaper_${widget.chatId}');
      if (mounted && c != null) setState(() => _wallpaperColor = c);
    });
    WidgetsBinding.instance.addObserver(this);
    PresenceService.setOnline();

    // Typing indicator: listen to other user's typing state
    if (_isDirect && _otherUid.isNotEmpty) {
      _typingSub = ChatService.typingStream(widget.chatId, _otherUid)
          .listen((typing) {
        if (mounted) setState(() => _isTyping = typing);
      });

      // Presence: stream other user's online status, respecting their
      // "Last seen" privacy setting. 'Nobody' hides both online + last-seen
      // (WhatsApp-style); in a direct chat 'My contacts' counts as visible.
      _presenceSub = PresenceService.stream(_otherUid).listen((snap) {
        if (!mounted) return;
        final data    = snap.data();
        final privacy = data?['privacyLastSeen'] as String? ?? 'My contacts';
        final hidden  = privacy == 'Nobody';
        final online  = !hidden && (data?['isOnline'] as bool?) == true;
        final ts      = data?['lastSeen'] as Timestamp?;
        setState(() {
          _isOnline     = online;
          _lastSeenText = hidden ? '' : (online ? '' : PresenceService.formatLastSeen(ts));
        });
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PresenceService.setOnline();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      PresenceService.setOffline();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PresenceService.setOffline();
    _presenceSub?.cancel();
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

  // ── Helpers (gaps 1, 7, 8) ───────────────────────────────────────────────

  Future<void> _loadDisappearing() async {
    final doc = await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId).get();
    if (mounted && doc.exists) {
      setState(() =>
          _disappearing = doc.data()?['disappearingMessages'] as String? ?? 'off');
      // Actually delete anything already past its TTL when the chat is opened.
      _purgeExpired();
    }
  }

  Duration? _disappearingTtl() {
    switch (_disappearing) {
      case '24h': return const Duration(hours: 24);
      case '7d':  return const Duration(days: 7);
      case '30d': return const Duration(days: 30);
      default:    return null; // 'off'
    }
  }

  void _purgeExpired() {
    final ttl = _disappearingTtl();
    if (ttl == null) return;
    // Fire-and-forget; the client-side _isExpired filter hides anything not yet
    // deleted, so the UI is correct even before the purge completes.
    ChatService.purgeExpiredMessages(widget.chatId, ttl);
  }

  bool _isExpired(_Msg msg) {
    final ttl = _disappearingTtl();
    if (ttl == null) return false;
    return DateTime.now().isAfter(msg.createdAt.add(ttl));
  }

  static const _monthNames = [
    'JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'
  ];

  String _dateLabel(DateTime dt) {
    final now    = DateTime.now();
    final today  = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff   = today.difference(msgDay).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return '${_monthNames[dt.month - 1]} ${dt.day}';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // Caption sheet shown before sending an image — returns {caption, viewOnce}
  Future<Map<String, dynamic>?> _showCaptionSheet(File imageFile) {
    final ctrl = TextEditingController();
    bool viewOnce = false;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0E1829),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(22)),
                  child: Image.file(imageFile,
                      height: 280,
                      width: double.infinity,
                      fit: BoxFit.cover),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
                  child: Row(children: [
                    IconButton(
                      tooltip: 'View once',
                      icon: Icon(
                        viewOnce ? Icons.timer_rounded : Icons.timer_outlined,
                        color: viewOnce
                            ? const Color(0xFF4F8AFF)
                            : Colors.white54,
                      ),
                      onPressed: () => setSt(() => viewOnce = !viewOnce),
                    ),
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        autofocus: false,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: viewOnce
                              ? 'View once — no caption'
                              : 'Add a caption…',
                          hintStyle:
                              TextStyle(color: Colors.white.withAlpha(100)),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send_rounded,
                          color: Color(0xFF4F8AFF)),
                      onPressed: () => Navigator.pop(ctx,
                          {'caption': ctrl.text.trim(), 'viewOnce': viewOnce}),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
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

  void _scrollToPinnedMessage() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
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
    final mentions = _isDirect ? const <String>[] : _resolveMentions(text);
    setState(() {
      _ctrl.clear();
      _hasText = false;
      _replyTarget = null;
      _mentionQuery = null;
      _pendingMentions.clear();
    });
    ChatService.sendMessage(
      widget.chatId,
      text,
      mentions: mentions.isEmpty ? null : mentions,
      replyToId:         replyTarget?.id,
      replyToText:       replyTarget == null ? null : _msgPreview(replyTarget),
      replyToSenderName: replyTarget == null
          ? null
          : (replyTarget.sent
              ? 'You'
              : (replyTarget.senderName ?? 'Unknown')),
    );
    Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
  }

  // ── @mentions (group chats) ─────────────────────────────────────────────────

  Future<void> _loadGroupMembers() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
      final data = doc.data() ?? {};
      final names = Map<String, dynamic>.from(data['memberNames'] as Map? ?? {});
      if (!mounted) return;
      setState(() {
        _groupMembers
          ..clear()
          ..addAll(names.entries
              .where((e) => e.key != _myUid)
              .map((e) => {'uid': e.key, 'name': (e.value as String?) ?? 'Member'}));
        _sendBlocked = ChatService.isSendBlocked({...data, 'id': widget.chatId});
      });
    } catch (_) {}
  }

  void _onComposerChanged(String v) {
    setState(() => _hasText = v.trim().isNotEmpty);
    _onTypingChanged(v.isNotEmpty);
    if (_isDirect || _groupMembers.isEmpty) {
      if (_mentionQuery != null) setState(() => _mentionQuery = null);
      return;
    }
    final sel  = _ctrl.selection.baseOffset;
    final upto = (sel >= 0 && sel <= v.length) ? v.substring(0, sel) : v;
    final match = RegExp(r'(?:^|\s)@([A-Za-z0-9_]*)$').firstMatch(upto);
    setState(() => _mentionQuery = match?.group(1)?.toLowerCase());
  }

  void _insertMention(Map<String, String> member) {
    final v   = _ctrl.text;
    final sel = _ctrl.selection.baseOffset.clamp(0, v.length);
    final before = v.substring(0, sel);
    final after  = v.substring(sel);
    final at = before.lastIndexOf('@');
    if (at < 0) return;
    final newBefore = '${before.substring(0, at)}@${member['name']} ';
    _ctrl.text = '$newBefore$after';
    _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: newBefore.length));
    _pendingMentions.add(member['uid'] ?? '');
    setState(() { _mentionQuery = null; _hasText = _ctrl.text.trim().isNotEmpty; });
  }

  List<String> _resolveMentions(String text) {
    final out = <String>[];
    for (final m in _groupMembers) {
      final uid = m['uid'] ?? '';
      if (_pendingMentions.contains(uid) && text.contains('@${m['name']}')) out.add(uid);
    }
    return out;
  }

  List<Map<String, String>> get _mentionMatches {
    final q = _mentionQuery;
    if (q == null) return const [];
    return _groupMembers
        .where((m) => (m['name'] ?? '').toLowerCase().contains(q))
        .take(6)
        .toList();
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to send voice message. Check your connection.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 3),
        ));
      }
    }
    Future.delayed(const Duration(milliseconds: 80), _scrollToBottom);
  }

  // ── Smart summary ─────────────────────────────────────────────────────────

  Future<void> _loadSummaryDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _summaryDismissed =
          prefs.getBool('summary_dismissed_${widget.chatId}') ?? false);
    }
  }

  Future<void> _dismissSummaryBanner() async {
    setState(() => _summaryDismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('summary_dismissed_${widget.chatId}', true);
  }

  bool get _showSummaryBanner => !_isDirect && _unreadCount > 0 && !_summaryDismissed;

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
                        _dismissSummaryBanner();
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
      final sender   = data['senderName'] as String? ?? 'User';
      final text     = (data['text']     as String? ?? '').trim();
      final imageUrl = (data['imageUrl'] as String? ?? '').trim();
      final audioUrl = (data['audioUrl'] as String? ?? '').trim();
      final content = text.isNotEmpty
          ? text
          : imageUrl.isNotEmpty
              ? '[shared an image]'
              : audioUrl.isNotEmpty
                  ? '[sent a voice message]'
                  : '';
      return '$sender: $content';
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
        onSearchTap: () => setState(() => _searchMode = true),
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
        decoration: _wallpaperColor != null
            ? BoxDecoration(color: Color(_wallpaperColor!))
            : const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Column(children: [
            const SizedBox(height: kToolbarHeight + 44),
            if (_showSummaryBanner)
              _SummaryBanner(
                count: _unreadCount,
                onTap: _showSmartSummary,
                onDismiss: _dismissSummaryBanner,
              ),
            if (_showSummaryBanner && _pinnedMessage != null)
              Divider(height: 1, thickness: 1, color: Colors.white.withAlpha(12)),
            if (_pinnedMessage != null)
              _PinnedBanner(
                text: _pinnedMessage!['text'] as String? ?? 'Pinned message',
                onTap: _scrollToPinnedMessage,
                onDismiss: _unpinMessage,
              ),
            Expanded(child: _buildMessages()),
            if (_replyTarget != null) _ReplyBar(
              msg: _replyTarget!,
              onClear: _clearReply,
            ),
            if (_sendBlocked)
              _AdminsOnlyNotice()
            else
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
                          : _isDirect
                              ? Row(children: [
                                  if (_isOnline)
                                    Container(
                                      width: 7, height: 7,
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: const BoxDecoration(
                                          color: Color(0xFF34C759),
                                          shape: BoxShape.circle),
                                    ),
                                  Text(
                                    _isOnline ? 'online' : _lastSeenText,
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 12),
                                  ),
                                ])
                              : const SizedBox.shrink(),
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

  bool get _isNearBottom {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return pos.maxScrollExtent - pos.pixels < 200;
  }

  Widget _buildMessages() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ChatService.messagesStream(widget.chatId, limit: _pageLimit),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(child: Text('Could not load messages',
              style: TextStyle(color: Colors.white.withAlpha(120))));
        }
        final docs = snap.data ?? [];
        // If we received a full page, older messages likely exist.
        final hasMore = docs.length >= _pageLimit;
        var messages = docs
            .where((d) => d['deleted'] != true)
            .where((d) => !_deletedForMe.contains(d['id'] as String? ?? ''))
            .map((d) => _Msg.fromFirestore(d, _myUid))
            .where((m) => !_isExpired(m))
            .toList();

        // Filter by search query if active
        if (_searchQuery.isNotEmpty) {
          messages = messages
              .where((m) => m.text.toLowerCase().contains(_searchQuery))
              .toList();
        }

        // Scroll to bottom only when user is already near the bottom
        if (snap.hasData && _isNearBottom) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        final firstUnreadIdx = messages.indexWhere((m) => !m.read && !m.sent);
        final unreadCount = firstUnreadIdx == -1
            ? 0
            : messages.skip(firstUnreadIdx).where((m) => !m.read && !m.sent).length;
        if (unreadCount != _unreadCount) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) { if (mounted) setState(() => _unreadCount = unreadCount); });
        }

        // A "load earlier" header occupies index 0 when more history exists.
        final showLoadMore = hasMore && _searchQuery.isEmpty;
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          itemCount: messages.length + (showLoadMore ? 1 : 0),
          itemBuilder: (ctx, rawIndex) {
            if (showLoadMore && rawIndex == 0) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextButton.icon(
                    onPressed: () => setState(() => _pageLimit += 50),
                    icon: const Icon(Icons.history_rounded, size: 16, color: Color(0xFF4F8AFF)),
                    label: const Text('Load earlier messages',
                        style: TextStyle(color: Color(0xFF4F8AFF), fontSize: 13)),
                  ),
                ),
              );
            }
            final i = showLoadMore ? rawIndex - 1 : rawIndex;
            final msg  = messages[i];
            final prev = i > 0 ? messages[i - 1] : null;
            final showDate = prev == null ||
                !_isSameDay(msg.createdAt, prev.createdAt);
            return Column(children: [
              if (showDate) _DateChip(_dateLabel(msg.createdAt)),
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
        onQuickReact: (emoji) {
          Navigator.pop(context);
          ChatService.toggleReaction(widget.chatId, msg.id, emoji);
        },
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
            ChatService.starMessage(widget.chatId, msg.id, msg.text, chatName: widget.chatName);
          }
        },
        onForward: () {
          Navigator.pop(context);
          _showForwardSheet(msg);
        },
        // Edit is only offered on your own text messages, within a 15-minute
        // window (WhatsApp-style).
        onEdit: msg.sent && !msg.isImage && !msg.isVoice &&
                DateTime.now().difference(msg.createdAt) < const Duration(minutes: 15)
            ? () {
                Navigator.pop(context);
                _showEditDialog(msg);
              }
            : null,
        onPin: () {
          Navigator.pop(context);
          _pinMessage(msg);
        },
        onInfo: msg.sent ? () {
          Navigator.pop(context);
          _showMessageInfo(msg);
        } : null,
        onDelete: () async {
          Navigator.pop(context);
          if (msg.sent) {
            // Sender gets two options: delete for me OR delete for everyone
            final choice = await showDialog<String>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF0E1829),
                title: const Text('Delete message?', style: TextStyle(color: Colors.white)),
                content: Text('Choose how to delete this message.',
                    style: TextStyle(color: Colors.white.withAlpha(180))),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                  TextButton(onPressed: () => Navigator.pop(context, 'me'),
                      child: const Text('Delete for me', style: TextStyle(color: Colors.orangeAccent))),
                  TextButton(onPressed: () => Navigator.pop(context, 'everyone'),
                      child: const Text('Delete for everyone', style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            );
            if (choice == 'everyone') {
              await ChatService.deleteMessage(widget.chatId, msg.id);
            } else if (choice == 'me') {
              await ChatService.deleteForMe(widget.chatId, msg.id);
              if (mounted) setState(() => _deletedForMe.add(msg.id));
            }
          } else {
            // Received message: only "delete for me"
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF0E1829),
                title: const Text('Delete message?', style: TextStyle(color: Colors.white)),
                content: Text('This will delete the message for you only.',
                    style: TextStyle(color: Colors.white.withAlpha(180))),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                  TextButton(onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete for me', style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            );
            if (ok == true) {
              await ChatService.deleteForMe(widget.chatId, msg.id);
              if (mounted) setState(() => _deletedForMe.add(msg.id));
            }
          }
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
                ...seenBy.map((uid) => FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
                  builder: (ctx, userSnap) {
                    final name = userSnap.data?.get('fullName') as String?
                              ?? userSnap.data?.get('displayName') as String?
                              ?? uid.substring(0, 6);
                    final photo = userSnap.data?.get('photoUrl') as String? ?? '';
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF1565C0),
                        backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                        child: photo.isEmpty
                            ? Text(name[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontSize: 12))
                            : null,
                      ),
                      title: Text(name,
                          style: const TextStyle(color: Colors.white, fontSize: 14)),
                      trailing: const Icon(Icons.done_all_rounded,
                          color: Color(0xFF53BDEB), size: 16),
                    );
                  },
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
        msgText: _msgPreview(msg),
        onForwardTo: (chatId) {
          ChatService.sendMessage(
            chatId,
            _msgPreview(msg),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_mentionMatches.isNotEmpty) _mentionSuggestions(),
                Row(
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
                                onChanged: _onComposerChanged,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Horizontal strip of @-mention candidates shown above the composer.
  Widget _mentionSuggestions() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 46),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _mentionMatches.map((m) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => _insertMention(m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withAlpha(35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 11, backgroundColor: const Color(0xFF2563EB),
                  child: Text((m['name'] ?? '?').isNotEmpty ? m['name']![0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 7),
                Text('@${m['name']}', style: const TextStyle(color: Colors.white, fontSize: 13)),
              ]),
            ),
          ),
        )).toList(),
      ),
    );
  }
}

// Shown instead of the composer when a group is admins-only and you're not an admin.
class _AdminsOnlyNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      color: Colors.white.withAlpha(10),
      border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
    ),
    child: SafeArea(top: false, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.lock_outline_rounded, size: 16, color: Colors.white.withAlpha(140)),
      const SizedBox(width: 8),
      Text('Only admins can send messages', style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13)),
    ])),
  );
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
    if (msg.isImage)   return _ImageBubble(msg: msg);
    if (msg.isVoice)   return _VoiceBubble(msg: msg);
    if (msg.isVideo)   return _VideoBubble(msg: msg);
    if (msg.isSticker) return _StickerBubble(msg: msg);
    if (msg.isContact) return _ContactBubble(msg: msg);
    if (msg.isPoll)    return _PollBubble(msg: msg);
    if (msg.isEvent)   return _EventBubble(msg: msg);
    if (msg.isLocation) return _LocationBubble(msg: msg);

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
          _LinkedText.hasLink(msg.text)
              ? _LinkedText(
                  msg.text,
                  style: const TextStyle(fontSize: 14.5, color: Colors.white, height: 1.4),
                )
              : Text(
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

class _ImageBubble extends StatefulWidget {
  final _Msg msg;
  const _ImageBubble({required this.msg});
  @override
  State<_ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<_ImageBubble> {
  bool _autoLoad = true;
  bool _userTapped = false;

  @override
  void initState() {
    super.initState();
    AutoDownloadService.getImages().then((pref) {
      if (mounted) setState(() => _autoLoad = pref != 'never');
    });
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
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF4F8AFF))),
              errorWidget: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48),
            ),
          ),
        ),
      ),
    )).then((_) {
      // Mark view-once as seen after the full-screen viewer closes
      if (widget.msg.viewOnce && !widget.msg.viewOnceViewed && !widget.msg.sent) {
        final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
        FirebaseFirestore.instance
            .collection('chats').doc(widget.msg.chatId)
            .collection('messages').doc(widget.msg.id)
            .update({'viewOnceViewedBy': FieldValue.arrayUnion([myUid])});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;

    // View-once: sender sees a clock badge; recipient sees "opened" after viewing
    if (msg.viewOnce) {
      if (msg.sent) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.timer_rounded, color: Colors.white70, size: 18),
            const SizedBox(width: 6),
            const Text('View once', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 8),
            _TimeRow(msg: msg, onDark: false),
          ]),
        );
      }
      if (msg.viewOnceViewed) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.timer_off_rounded, color: Colors.white38, size: 18),
            const SizedBox(width: 6),
            Text('Photo opened', style: TextStyle(color: Colors.white.withAlpha(100), fontSize: 13)),
            const SizedBox(width: 8),
            _TimeRow(msg: msg, onDark: false),
          ]),
        );
      }
      // Not yet viewed — show tap-to-view badge
      return GestureDetector(
        onTap: () {
          if (msg.imageUrl != null && msg.imageUrl!.isNotEmpty) {
            _showFullImage(context, msg.imageUrl!);
          }
        },
        child: Stack(alignment: Alignment.bottomRight, children: [
          Container(
            width: 220, height: 180,
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_rounded, color: Color(0xFF4F8AFF), size: 40),
                SizedBox(height: 8),
                Text('Tap to view once',
                    style: TextStyle(color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(6), child: _TimeRow(msg: msg, onDark: true)),
        ]),
      );
    }

    final show = _autoLoad || _userTapped;
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
              ? show
                ? GestureDetector(
                    onTap: () => _showFullImage(context, msg.imageUrl!),
                    child: CachedNetworkImage(
                      imageUrl: msg.imageUrl!,
                      width: 220, height: 180,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 220, height: 180,
                        color: Colors.black26,
                        child: const Center(child: CircularProgressIndicator(
                          color: Colors.white54, strokeWidth: 2,
                        )),
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 220, height: 100,
                        color: Colors.black26,
                        child: const Icon(Icons.broken_image_outlined,
                            color: Colors.white54, size: 36),
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: () => setState(() => _userTapped = true),
                    child: Container(
                      width: 220, height: 180,
                      color: Colors.black26,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_rounded, color: Colors.white54, size: 36),
                          SizedBox(height: 6),
                          Text('Tap to load',
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                  )
              : Container(
                  width: 220, height: 120,
                  color: Colors.black26,
                  child: const Center(
                    child: Icon(Icons.image_rounded, color: Colors.white54, size: 40),
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
  double _speed    = 1.0;

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
      await _player.setSpeed(_speed);
      await _player.play();
      setState(() => _playing = true);
    }
  }

  Future<void> _cycleSpeed() async {
    final next = _speed == 1.0 ? 1.5 : _speed == 1.5 ? 2.0 : 1.0;
    await _player.setSpeed(next);
    setState(() => _speed = next);
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
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _cycleSpeed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _speed == 1.0 ? '1×' : _speed == 1.5 ? '1.5×' : '2×',
                style: const TextStyle(color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _TimeRow(msg: widget.msg),
        ],
      ),
    );
  }
}

// ── Video bubble ─────────────────────────────────────────────────────────────

class _VideoBubble extends StatefulWidget {
  final _Msg msg;
  const _VideoBubble({required this.msg});

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  bool _showPlayer  = false;
  bool _autoLoad    = true;
  bool _userTapped  = false;

  @override
  void initState() {
    super.initState();
    AutoDownloadService.getVideos().then((pref) {
      if (mounted) setState(() => _autoLoad = pref != 'never');
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.msg.imageUrl ?? '';
    final loadAllowed = _autoLoad || _userTapped;
    return GestureDetector(
      onTap: () {
        if (!loadAllowed) {
          setState(() => _userTapped = true);
        } else if (url.isNotEmpty) {
          setState(() => _showPlayer = true);
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 220, height: 140,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _showPlayer && url.isNotEmpty
                ? _VideoPlayerWidget(url: url)
                : Center(child: Icon(
                    loadAllowed ? Icons.videocam_rounded : Icons.download_rounded,
                    color: Colors.white54, size: 48)),
          ),
          if (!_showPlayer)
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(140),
                shape: BoxShape.circle,
              ),
              child: Icon(
                loadAllowed ? Icons.play_arrow_rounded : Icons.download_rounded,
                color: Colors.white, size: 34),
            ),
          if (!loadAllowed && !_showPlayer)
            const Positioned(
              bottom: 28,
              child: Text('Tap to load',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          Positioned(
            bottom: 6, right: 8,
            child: _TimeRow(msg: widget.msg),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerWidget extends StatefulWidget {
  final String url;
  const _VideoPlayerWidget({required this.url});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late final VideoPlayerController _ctrl;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) { setState(() => _initialised = true); _ctrl.play(); }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialised) {
      return const Center(child: SizedBox(
        width: 24, height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      ));
    }
    return AspectRatio(
      aspectRatio: _ctrl.value.aspectRatio,
      child: VideoPlayer(_ctrl),
    );
  }
}

// ── Sticker bubble ───────────────────────────────────────────────────────────

class _StickerBubble extends StatelessWidget {
  final _Msg msg;
  const _StickerBubble({required this.msg});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(msg.text, style: const TextStyle(fontSize: 52)),
        const SizedBox(height: 2),
        _TimeRow(msg: msg),
      ],
    ),
  );
}

// ── Linkified message text (taps open URLs) ───────────────────────────────────

class _LinkedText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _LinkedText(this.text, {required this.style});

  static final _urlRegex =
      RegExp(r'((https?:\/\/)|(www\.))[^\s]+', caseSensitive: false);
  // WhatsApp-style formatting: *bold* _italic_ ~strike~ `mono`.
  static final _fmtRegex = RegExp(r'\*[^*\n]+\*|_[^_\n]+_|~[^~\n]+~|`[^`\n]+`');
  static final _mentionRegex = RegExp(r'@[A-Za-z0-9_]+');
  // URLs, @mentions, or formatting — matched together and rendered in order.
  static final _richRegex = RegExp(
      r'((https?:\/\/)|(www\.))[^\s]+|@[A-Za-z0-9_]+|\*[^*\n]+\*|_[^_\n]+_|~[^~\n]+~|`[^`\n]+`',
      caseSensitive: false);

  /// Cheap pre-check so plain messages skip the stateful path entirely.
  static bool hasLink(String s) =>
      _urlRegex.hasMatch(s) || _mentionRegex.hasMatch(s) || _fmtRegex.hasMatch(s);

  @override
  State<_LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<_LinkedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _spans() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final spans = <InlineSpan>[];
    final text = widget.text;
    var start = 0;
    for (final m in _LinkedText._richRegex.allMatches(text)) {
      if (m.start > start) spans.add(TextSpan(text: text.substring(start, m.start)));
      final raw = m.group(0)!;
      final first = raw[0];
      if (raw.startsWith('@')) {
        // @mention — highlighted, non-tappable.
        spans.add(TextSpan(
          text: raw,
          style: const TextStyle(color: Color(0xFF9EC5FF), fontWeight: FontWeight.w600),
        ));
      } else if (first == '*' || first == '_' || first == '~' || first == '`') {
        // Formatting — strip the markers and apply the style.
        final inner = raw.substring(1, raw.length - 1);
        final style = switch (first) {
          '*' => const TextStyle(fontWeight: FontWeight.w700),
          '_' => const TextStyle(fontStyle: FontStyle.italic),
          '~' => const TextStyle(decoration: TextDecoration.lineThrough),
          _   => const TextStyle(fontFamily: 'monospace', letterSpacing: 0.2),
        };
        spans.add(TextSpan(text: inner, style: style));
      } else {
        // URL — tappable. Don't swallow trailing sentence punctuation.
        final link = raw.replaceAll(RegExp(r'[.,!?;:)\]]+$'), '');
        final url  = link.startsWith('http') ? link : 'https://$link';
        final rec  = TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        _recognizers.add(rec);
        spans.add(TextSpan(
          text: link,
          style: const TextStyle(
            color: Color(0xFF9EC5FF),
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF9EC5FF),
          ),
          recognizer: rec,
        ));
        final tail = raw.substring(link.length);
        if (tail.isNotEmpty) spans.add(TextSpan(text: tail));
      }
      start = m.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return spans;
  }

  @override
  Widget build(BuildContext context) =>
      Text.rich(TextSpan(style: widget.style, children: _spans()));
}

// ── Contact card bubble ───────────────────────────────────────────────────────

class _ContactBubble extends StatelessWidget {
  final _Msg msg;
  const _ContactBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    // text is stored as "Name\nphone"
    final parts = msg.text.split('\n');
    final name  = parts.isNotEmpty ? parts[0] : 'Contact';
    final phone = parts.length > 1 ? parts[1] : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF4F8AFF).withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded,
                color: Color(0xFF4F8AFF), size: 22),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if (phone.isNotEmpty)
                  Text(phone,
                      style: TextStyle(
                          color: Colors.white.withAlpha(160), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TimeRow(msg: msg),
        ],
      ),
    );
  }
}

// ── Location bubble ───────────────────────────────────────────────────────────

class _LocationBubble extends StatelessWidget {
  final _Msg msg;
  const _LocationBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final loc = msg.location ?? {};
    final lat = (loc['lat'] as num?)?.toDouble() ?? 0;
    final lng = (loc['lng'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (!msg.sent && msg.senderName != null && msg.senderName!.isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 2),
            child: Text(msg.senderName!, style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 12, fontWeight: FontWeight.w600))),
        GestureDetector(
          onTap: () => launchUrl(Uri.parse('https://maps.google.com/?q=$lat,$lng'), mode: LaunchMode.externalApplication),
          child: Container(
            width: 230,
            decoration: BoxDecoration(color: Colors.white.withAlpha(14), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Center(child: Icon(Icons.location_on_rounded, color: Colors.redAccent.withAlpha(230), size: 40)),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  const Icon(Icons.map_outlined, size: 15, color: Color(0xFF9EC5FF)),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Location · open in Maps',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerRight, child: _TimeRow(msg: msg)),
      ]),
    );
  }
}

// ── Poll bubble ───────────────────────────────────────────────────────────────

class _PollBubble extends StatelessWidget {
  final _Msg msg;
  const _PollBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final myUid    = FirebaseAuth.instance.currentUser?.uid ?? '';
    final poll     = msg.poll ?? {};
    final question = poll['question'] as String? ?? 'Poll';
    final multi    = poll['multi'] == true;
    final options  = (poll['options'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final totalVotes = options.fold<int>(0, (s, o) => s + ((o['voters'] as List?)?.length ?? 0));

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (!msg.sent && msg.senderName != null && msg.senderName!.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 2),
              child: Text(msg.senderName!, style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 12, fontWeight: FontWeight.w600))),
          Row(children: [
            const Icon(Icons.poll_outlined, size: 15, color: Color(0xFF9EC5FF)),
            const SizedBox(width: 6),
            Text(multi ? 'Poll · select many' : 'Poll · select one',
                style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(140), fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Text(question, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ...options.asMap().entries.map((e) {
            final i       = e.key;
            final o       = e.value;
            final voters  = (o['voters'] as List?)?.cast<String>() ?? [];
            final voted   = voters.contains(myUid);
            final pct     = totalVotes == 0 ? 0.0 : voters.length / totalVotes;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => ChatService.votePoll(msg.chatId, msg.id, i),
                child: Stack(children: [
                  Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: voted ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(30)),
                    ),
                  ),
                  // Fill bar
                  FractionallySizedBox(
                    widthFactor: pct.clamp(0.0, 1.0),
                    child: Container(height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withAlpha(voted ? 90 : 55),
                        borderRadius: BorderRadius.circular(10))),
                  ),
                  Positioned.fill(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      if (voted) const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF4F8AFF)),
                      if (voted) const SizedBox(width: 6),
                      Expanded(child: Text(o['text'] as String? ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13))),
                      Text('${voters.length}', style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  )),
                ]),
              ),
            );
          }),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('$totalVotes vote${totalVotes == 1 ? '' : 's'}',
                style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 11)),
            _TimeRow(msg: msg),
          ]),
        ]),
      ),
    );
  }
}

// ── Event bubble ──────────────────────────────────────────────────────────────

class _EventBubble extends StatelessWidget {
  final _Msg msg;
  const _EventBubble({required this.msg});

  static const _months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ev    = msg.event ?? {};
    final title = ev['title'] as String? ?? 'Event';
    final ts    = ev['dateTime'] as Timestamp?;
    final dt    = ts?.toDate();
    final loc   = ev['location'] as String? ?? '';
    final desc  = ev['description'] as String? ?? '';
    final roomId = ev['callRoomId'] as String?;
    final rsvp  = Map<String, dynamic>.from(ev['rsvp'] as Map? ?? {});
    final myRsvp = rsvp[myUid] as String?;
    final going = rsvp.values.where((v) => v == 'going').length;

    String timeLabel = '';
    if (dt != null) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      timeLabel = '${dt.day} ${_months[dt.month - 1]} · $h:$m';
    }

    Widget rsvpBtn(String value, String label, IconData icon) {
      final on = myRsvp == value;
      return Expanded(child: GestureDetector(
        onTap: () => ChatService.rsvpEvent(msg.chatId, msg.id, value),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF2563EB).withAlpha(70) : Colors.white.withAlpha(14),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: on ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(30)),
          ),
          child: Column(children: [
            Icon(icon, size: 15, color: on ? Colors.white : Colors.white.withAlpha(170)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: on ? Colors.white : Colors.white.withAlpha(170), fontWeight: FontWeight.w600)),
          ]),
        ),
      ));
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (!msg.sent && msg.senderName != null && msg.senderName!.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 2),
              child: Text(msg.senderName!, style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 12, fontWeight: FontWeight.w600))),
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(50), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.event_rounded, color: Color(0xFF9EC5FF), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (timeLabel.isNotEmpty) Text(timeLabel, style: const TextStyle(color: Color(0xFF9EC5FF), fontSize: 12, fontWeight: FontWeight.w600)),
            ])),
          ]),
          if (loc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.location_on_outlined, size: 13, color: Colors.white.withAlpha(150)),
              const SizedBox(width: 4),
              Expanded(child: Text(loc, style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ],
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(desc, style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 10),
          Row(children: [
            rsvpBtn('going', 'Going', Icons.check_rounded),
            rsvpBtn('maybe', 'Maybe', Icons.help_outline_rounded),
            rsvpBtn('no',    'No',    Icons.close_rounded),
          ]),
          if (roomId != null && roomId.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () {
                final me = FirebaseAuth.instance.currentUser;
                if (me == null) return;
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LiveSessionScreen(courseId: title, roomId: roomId),
                ));
              },
              icon: const Icon(Icons.videocam_rounded, size: 16),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF4F8AFF), side: const BorderSide(color: Color(0xFF4F8AFF))),
              label: const Text('Join call'),
            )),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('$going going', style: TextStyle(color: Colors.white.withAlpha(130), fontSize: 11)),
            _TimeRow(msg: msg),
          ]),
        ]),
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
            original.senderName ?? (original.sent ? 'You' : 'Someone'),
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
                  msg.senderName ?? (msg.sent ? 'You' : 'Someone'),
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

// One-line preview label for a message (used in reply quotes, forwards, previews).
String _msgPreview(_Msg m) =>
    m.isVoice   ? '🎤 Voice message'
    : m.isImage   ? '📷 Photo'
    : m.isVideo   ? '🎬 Video'
    : m.isContact ? '👤 Contact'
    : m.isPoll    ? '📊 ${m.poll?['question'] ?? 'Poll'}'
    : m.isEvent   ? '📅 ${m.event?['title'] ?? 'Event'}'
    : m.isLocation ? '📍 Location'
    : m.text;

class _Msg {
  final String id;
  final String text;
  final String time;
  final bool sent;
  final bool read;
  final bool isImage;
  final bool isVoice;
  final bool isVideo;
  final bool isSticker;
  final bool isContact;
  final bool edited;
  final bool viewOnce;
  final bool viewOnceViewed;
  final String chatId;
  final String? imageUrl;
  final String? audioUrl;
  final String? imageLabel;
  final String? voiceDuration;
  final String? senderName;
  final _Msg? replyTo;
  final Map<String, int>? reactions;
  final Map<String, dynamic>? poll;
  final Map<String, dynamic>? event;
  final Map<String, dynamic>? location;
  final DateTime createdAt;

  bool get isPoll     => poll  != null;
  bool get isEvent    => event != null;
  bool get isLocation => location != null;

  _Msg({
    required this.id,
    required this.text,
    required this.sent,
    required this.time,
    required this.read,
    this.isImage = false,
    this.isVoice = false,
    this.isVideo = false,
    this.isSticker = false,
    this.isContact = false,
    this.edited = false,
    this.viewOnce = false,
    this.viewOnceViewed = false,
    this.chatId = '',
    this.imageUrl,
    this.audioUrl,
    this.imageLabel,
    this.voiceDuration,
    this.senderName,
    this.replyTo,
    this.reactions,
    this.poll,
    this.event,
    this.location,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  _Msg copyWith({Map<String, int>? reactions}) => _Msg(
    id: id, text: text, sent: sent, time: time, read: read,
    isImage: isImage, isVoice: isVoice, isVideo: isVideo,
    isSticker: isSticker, isContact: isContact,
    edited: edited, viewOnce: viewOnce, viewOnceViewed: viewOnceViewed,
    chatId: chatId,
    imageUrl: imageUrl, audioUrl: audioUrl, imageLabel: imageLabel,
    senderName: senderName, voiceDuration: voiceDuration, replyTo: replyTo,
    reactions: reactions ?? this.reactions,
    createdAt: createdAt,
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
        id:         d['replyToId'] as String? ?? '',
        text:       d['replyToText'] as String,
        sent:       false, time: '', read: true,
        senderName: d['replyToSenderName'] as String?,
      );
    }

    return _Msg(
      id:            d['id'] as String,
      text:          d['text'] as String? ?? '',
      sent:          d['senderUid'] == myUid,
      time:          '$h:$m',
      read:          readBy.any((uid) => uid != myUid),
      isImage:         type == 'image',
      isVoice:         type == 'voice',
      isVideo:         type == 'video',
      isSticker:       type == 'sticker',
      isContact:       type == 'contact',
      poll:            d['poll']     is Map ? Map<String, dynamic>.from(d['poll']     as Map) : null,
      event:           d['event']    is Map ? Map<String, dynamic>.from(d['event']    as Map) : null,
      location:        d['location'] is Map ? Map<String, dynamic>.from(d['location'] as Map) : null,
      edited:          (d['edited'] as bool?) == true,
      viewOnce:        (d['viewOnce'] as bool?) == true,
      viewOnceViewed:  List<String>.from(
          d['viewOnceViewedBy'] as List? ?? []).contains(myUid),
      chatId:          d['chatId'] as String? ?? '',
      imageUrl:        d['imageUrl'] as String?,
      audioUrl:        d['audioUrl'] as String?,
      voiceDuration:   d['voiceDuration'] as String? ?? (type == 'voice' ? '0:00' : null),
      senderName:      d['senderName'] as String?,
      replyTo:         replyTo,
      reactions:       reactions.isEmpty ? null : reactions,
      createdAt:       ts?.toDate(),
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
  Widget build(BuildContext context) => SizedBox(
    width: 74, // fixed cell so the Wrap forms a tidy 4-per-row grid
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            shape: BoxShape.circle,
            border: Border.all(color: color.withAlpha(60)),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ),
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
  final void Function(String emoji) onQuickReact;
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
    required this.onQuickReact,
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
                  onTap: () { Navigator.pop(context); onQuickReact(e); },
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
  final VoidCallback? onSearchTap;

  const _ContactInfoSheet({
    required this.name,
    required this.chatId,
    required this.otherUid,
    required this.isGroup,
    this.onVoiceCall,
    this.onVideoCall,
    this.onSearchTap,
  });

  @override
  State<_ContactInfoSheet> createState() => _ContactInfoSheetState();
}

class _ContactInfoSheetState extends State<_ContactInfoSheet> {
  Map<String, dynamic>? _profile;
  bool   _isBlocked     = false;
  bool   _isMuted       = false;
  bool   _isChatLocked  = false;
  bool   _mediaVisible  = true;
  String _disappearing  = 'off';
  List<Map<String, dynamic>> _mediaItems = [];
  List<Map<String, dynamic>> _groupMembers = [];
  List<String> _adminUids = [];
  bool _adminsOnly = false; // only admins can send in this group
  bool _requireApproval = false; // new members need admin approval
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    if (!widget.isGroup && widget.otherUid.isNotEmpty) _loadProfile();
    _loadChatMeta();
    _loadMedia();
    if (widget.isGroup) _loadGroupInfo();
  }

  Future<void> _loadProfile() async {
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(widget.otherUid).get();
    if (mounted) setState(() => _profile = doc.data());
  }

  Future<void> _loadChatMeta() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!widget.isGroup && widget.otherUid.isNotEmpty) {
      final blockedDoc = await FirebaseFirestore.instance
          .collection('users').doc(myUid).collection('blocked').doc(widget.otherUid).get();
      if (mounted) setState(() => _isBlocked = blockedDoc.exists);
    }
    final chatDoc = await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId).get();
    if (mounted && chatDoc.exists) {
      final data  = chatDoc.data()!;
      final muted = Map<String, dynamic>.from(data['muted'] as Map? ?? {});
      setState(() {
        _isMuted       = (muted[myUid] as bool?) == true;
        _disappearing  = data['disappearingMessages'] as String? ?? 'off';
        _mediaVisible  = (data['mediaVisible'] as bool?) ?? true;
      });
    }
    // Load chat lock from SharedPreferences
    final prefs  = await SharedPreferences.getInstance();
    final locked = (prefs.getStringList('locked_chats') ?? []).toSet();
    if (mounted) setState(() => _isChatLocked = locked.contains(widget.chatId));
  }

  Future<void> _toggleChatLock() async {
    if (!_isChatLocked) {
      // Require auth before locking
      bool canCheck = false;
      try {
        canCheck = await _localAuth.canCheckBiometrics ||
                   await _localAuth.isDeviceSupported();
      } catch (_) {}
      if (canCheck) {
        bool authed = false;
        try {
          authed = await _localAuth.authenticate(
            localizedReason: 'Confirm to lock this chat',
            options: const AuthenticationOptions(stickyAuth: true),
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Biometric error: ${e.toString().replaceFirst("Exception: ", "")}'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ));
          }
          return;
        }
        if (!authed) return;
      }
    }
    final prefs  = await SharedPreferences.getInstance();
    final locked = (prefs.getStringList('locked_chats') ?? []).toSet();
    if (_isChatLocked) {
      locked.remove(widget.chatId);
    } else {
      locked.add(widget.chatId);
    }
    await prefs.setStringList('locked_chats', locked.toList());
    if (mounted) setState(() => _isChatLocked = !_isChatLocked);
  }

  Future<void> _setDisappearing(String val) async {
    await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId)
        .update({'disappearingMessages': val});
    if (mounted) setState(() => _disappearing = val);
  }

  Future<void> _toggleMediaVisible() async {
    final next = !_mediaVisible;
    await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId)
        .update({'mediaVisible': next});
    if (mounted) setState(() => _mediaVisible = next);
  }

  Future<void> _loadMedia() async {
    final snap = await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId).collection('messages')
        .where('type', isEqualTo: 'image')
        .limit(12)
        .get();
    if (mounted) {
      setState(() => _mediaItems = snap.docs
          .map((d) => {'imageUrl': d.data()['imageUrl'] as String? ?? ''})
          .where((m) => (m['imageUrl'] as String).isNotEmpty)
          .toList());
    }
  }

  Future<void> _loadGroupInfo() async {
    final chatDoc = await FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId).get();
    if (!mounted || !chatDoc.exists) return;
    final data = chatDoc.data()!;
    final memberUids = List<String>.from(data['memberUids'] as List? ?? []);
    final adminUids  = List<String>.from(data['adminUids']  as List? ?? []);
    if (memberUids.isEmpty) return;
    final snaps = await Future.wait(
      memberUids.map((uid) => FirebaseFirestore.instance.collection('users').doc(uid).get()),
    );
    if (!mounted) return;
    setState(() {
      _adminUids = adminUids;
      _adminsOnly = (data['sendPolicy'] as String?) == 'admins';
      _requireApproval = (data['requireApproval'] as bool?) == true;
      _groupMembers = snaps
          .where((s) => s.exists)
          .map((s) => {'uid': s.id, ...s.data()!})
          .toList();
    });
  }

  Future<void> _removeMember(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E1829),
        title: const Text('Remove member', style: TextStyle(color: Colors.white)),
        content: const Text('Remove this member from the group?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    await ChatService.removeGroupMember(widget.chatId, uid);
    if (mounted) {
      setState(() {
        _groupMembers.removeWhere((m) => m['uid'] == uid);
        _adminUids.remove(uid);
      });
    }
  }

  Future<void> _addMember() async {
    // Search ZCHAT users by name/phone
    final ctrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    final existingUids = _groupMembers.map((m) => m['uid'] as String).toSet();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF0E1829),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add member', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone',
                  hintStyle: TextStyle(color: Colors.white.withAlpha(60)),
                  filled: true,
                  fillColor: Colors.white.withAlpha(10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                ),
                onChanged: (q) async {
                  if (q.trim().length < 2) { setS(() => results = []); return; }
                  final snap = await FirebaseFirestore.instance
                      .collection('users')
                      .orderBy('fullName')
                      .startAt([q.trim()]).endAt(['${q.trim()}'])
                      .limit(10).get();
                  final filtered = snap.docs
                      .map((d) => {'uid': d.id, ...d.data()})
                      .where((u) => !existingUids.contains(u['uid']))
                      .toList();
                  setS(() => results = filtered);
                },
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final u    = results[i];
                    final name = u['fullName'] as String? ?? u['phoneNumber'] as String? ?? 'Unknown';
                    final photo = u['photoUrl'] as String? ?? '';
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFF1565C0),
                        backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                        child: photo.isEmpty
                            ? Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white))
                            : null,
                      ),
                      title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await ChatService.addGroupMember(widget.chatId, u['uid'] as String, name);
                        await _loadGroupInfo();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('$name added to group'),
                            backgroundColor: const Color(0xFF0A1A4A),
                          ));
                        }
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAdmin(String uid, bool isCurrentlyAdmin) async {
    if (isCurrentlyAdmin) {
      await ChatService.demoteAdmin(widget.chatId, uid);
      if (mounted) setState(() => _adminUids.remove(uid));
    } else {
      await ChatService.promoteAdmin(widget.chatId, uid);
      if (mounted) setState(() => _adminUids.add(uid));
    }
  }

  Future<void> _editGroupDescription() async {
    final doc = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
    final current = doc.data()?['description'] as String? ?? '';
    final ctrl = TextEditingController(text: current);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1829),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Group description', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          maxLength: 200,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter a description…',
            hintStyle: TextStyle(color: Colors.white.withAlpha(60)),
            filled: true,
            fillColor: Colors.white.withAlpha(10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            counterStyle: TextStyle(color: Colors.white.withAlpha(80)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () async {
              await ChatService.setGroupDescription(widget.chatId, ctrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFF4F8AFF))),
          ),
        ],
      ),
    );
  }

  Future<void> _pickWallpaper() async {
    const colors = [
      0xFF0A1628, 0xFF1A0A28, 0xFF0A2818, 0xFF280A0A,
      0xFF0A1E3D, 0xFF1A1000, 0xFF001A1A, 0xFF1A001A,
    ];
    const labels = [
      'Dark Blue', 'Dark Purple', 'Dark Green', 'Dark Red',
      'Navy',      'Dark Brown',  'Dark Teal',  'Dark Magenta',
    ];
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('wallpaper_${widget.chatId}');
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E1829),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Chat wallpaper', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(
            spacing: 12, runSpacing: 12,
            children: List.generate(colors.length, (i) {
              final selected = current == colors[i];
              return GestureDetector(
                onTap: () async {
                  await prefs.setInt('wallpaper_${widget.chatId}', colors[i]);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Tooltip(
                  message: labels[i],
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Color(colors[i]),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(30),
                        width: selected ? 3 : 1,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                        : null,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () async {
              await prefs.remove('wallpaper_${widget.chatId}');
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.restore_rounded, size: 16, color: Colors.white54),
            label: const Text('Reset to default', style: TextStyle(color: Colors.white54)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }

  Future<void> _shareInviteLink() async {
    final doc = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
    String token = doc.data()?['inviteToken'] as String? ?? '';
    if (token.isEmpty) {
      token = '${widget.chatId}_${DateTime.now().millisecondsSinceEpoch}';
      await ChatService.setGroupInviteToken(widget.chatId, token);
    }
    final link = 'zchat://join?chatId=${widget.chatId}&token=$token';
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E1829),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Invite link', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(link, style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12)),
          ),
          const SizedBox(height: 12),
          const Text('Share this link so others can join the group.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Link copied to clipboard'),
                backgroundColor: Color(0xFF0A1A4A),
              ));
            },
            child: const Text('Copy link', style: TextStyle(color: Color(0xFF4F8AFF))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final smsUri = Uri.parse('sms:?body=${Uri.encodeComponent('Join my group on ZCHAT: $link')}');
              if (await canLaunchUrl(smsUri)) await launchUrl(smsUri);
            },
            child: const Text('Share via SMS', style: TextStyle(color: Color(0xFF86EFAC))),
          ),
        ],
      ),
    );
  }

  Future<void> _reportContact() async {
    final reasons = ['Spam', 'Harassment', 'Fake account', 'Inappropriate content', 'Other'];
    String? selected;
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF0E1829),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Report', style: TextStyle(color: Colors.white)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ...reasons.map((r) => RadioListTile<String>(
              value: r, groupValue: selected,
              activeColor: const Color(0xFF4F8AFF),
              title: Text(r, style: const TextStyle(color: Colors.white, fontSize: 14)),
              onChanged: (v) => setS(() => selected = v),
            )),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Additional details (optional)',
                hintStyle: TextStyle(color: Colors.white.withAlpha(60)),
                filled: true,
                fillColor: Colors.white.withAlpha(10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: selected == null ? null : () async {
                await FirebaseFirestore.instance.collection('reports').add({
                  'reportedUid':  widget.isGroup ? widget.chatId : widget.otherUid,
                  'reportedName': widget.name,
                  'reporterUid':  FirebaseAuth.instance.currentUser?.uid,
                  'reason':       selected,
                  'details':      ctrl.text.trim(),
                  'chatId':       widget.chatId,
                  'isGroup':      widget.isGroup,
                  'createdAt':    FieldValue.serverTimestamp(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Report submitted. Thank you.'),
                  backgroundColor: Color(0xFF0A1A4A),
                ));
              },
              child: const Text('Submit', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
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
    final about    = _profile?['about'] as String? ?? 'Available on ZCHAT.';
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
                _InfoAction(icon: Icons.search_rounded, label: 'Search', onTap: () {
                  Navigator.pop(context);
                  widget.onSearchTap?.call();
                }),
                _InfoAction(
                  icon: _isMuted ? Icons.notifications_off_outlined : Icons.notifications_outlined,
                  label: _isMuted ? 'Unmute' : 'Mute',
                  onTap: () { _toggleMute(); Navigator.pop(context); },
                ),
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
            // Media strip — tap header to open full gallery
            GestureDetector(
              onTap: () => _MediaGallerySheet.show(context, widget.chatId),
              child: Padding(
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
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => _MediaGallerySheet.show(context, widget.chatId),
                        child: Container(
                          width: 80, height: 80,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: _mediaItems[i]['imageUrl'] as String,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Icon(
                                  Icons.image_outlined,
                                  color: Colors.white.withAlpha(60), size: 30),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            Divider(color: Colors.white.withAlpha(12), height: 28),

            // ── Group description ──────────────────────────────────────────
            if (widget.isGroup) ...[
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get(),
                builder: (_, snap) {
                  final desc = snap.data?.data() != null
                      ? (snap.data!.data() as Map<String, dynamic>)['description'] as String? ?? ''
                      : '';
                  final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  final iAmAdmin = _adminUids.contains(myUid);
                  if (desc.isEmpty && !iAmAdmin) return const SizedBox.shrink();
                  return ListTile(
                    leading: const Icon(Icons.info_outline_rounded, color: Colors.white70),
                    title: Text(
                      desc.isEmpty ? 'Add group description' : desc,
                      style: TextStyle(
                        color: desc.isEmpty ? Colors.white.withAlpha(80) : Colors.white,
                        fontSize: 14,
                        fontStyle: desc.isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                    trailing: iAmAdmin
                        ? IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Color(0xFF4F8AFF), size: 18),
                            onPressed: _editGroupDescription,
                          )
                        : null,
                  );
                },
              ),
              Divider(color: Colors.white.withAlpha(12), height: 8),
            ],

            // ── Group members ──────────────────────────────────────────────
            if (widget.isGroup) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Text('${_groupMembers.length} members',
                    style: TextStyle(color: Colors.white.withAlpha(180),
                        fontWeight: FontWeight.w600, fontSize: 14)),
                  const Spacer(),
                  if (_adminUids.contains(FirebaseAuth.instance.currentUser?.uid))
                    GestureDetector(
                      onTap: _addMember,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F8AFF).withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF4F8AFF).withAlpha(80)),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.person_add_outlined, color: Color(0xFF4F8AFF), size: 15),
                          SizedBox(width: 4),
                          Text('Add', style: TextStyle(color: Color(0xFF4F8AFF), fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                ]),
              ),
              ..._groupMembers.map((m) {
                final uid   = m['uid'] as String? ?? '';
                final name  = m['fullName'] as String? ?? m['displayName'] as String? ?? m['phoneNumber'] as String? ?? 'Unknown';
                final photo = m['photoUrl'] as String? ?? '';
                final isMe  = uid == FirebaseAuth.instance.currentUser?.uid;
                final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                final iAmAdmin = _adminUids.contains(myUid);
                final isAdmin  = _adminUids.contains(uid);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF1565C0),
                    backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                    child: photo.isEmpty
                        ? Text(name.substring(0, name.length.clamp(0, 1)).toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
                        : null,
                  ),
                  title: Text(isMe ? 'You' : name,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: isAdmin
                      ? Text('Admin', style: TextStyle(color: const Color(0xFF4F8AFF).withAlpha(200), fontSize: 12))
                      : null,
                  trailing: (iAmAdmin && !isMe)
                      ? PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
                          color: const Color(0xFF0E1829),
                          onSelected: (v) {
                            if (v == 'remove') _removeMember(uid);
                            if (v == 'promote' || v == 'demote') _toggleAdmin(uid, isAdmin);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: isAdmin ? 'demote' : 'promote',
                              child: Text(isAdmin ? 'Remove admin' : 'Make admin',
                                  style: const TextStyle(color: Colors.white))),
                            const PopupMenuItem(value: 'remove',
                              child: Text('Remove from group',
                                  style: TextStyle(color: Colors.redAccent))),
                          ],
                        )
                      : null,
                );
              }),
              Divider(color: Colors.white.withAlpha(12), height: 28),
            ],

            // ── Encryption info ────────────────────────────────────────────
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded, color: Colors.white70),
              title: const Text('Encryption',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                'Messages are end-to-end encrypted.',
                style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12),
              ),
              onTap: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF0E1829),
                  title: const Text('End-to-End Encryption',
                      style: TextStyle(color: Colors.white)),
                  content: Text(
                    'Messages in this chat are secured with end-to-end encryption. '
                    'Only you and ${widget.isGroup ? 'group members' : widget.name.split(' ').first} '
                    'can read them.',
                    style: TextStyle(color: Colors.white.withAlpha(180), height: 1.5),
                  ),
                  actions: [TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK', style: TextStyle(color: Color(0xFF4F8AFF))),
                  )],
                ),
              ),
            ),

            // ── Disappearing messages ──────────────────────────────────────
            ListTile(
              leading: const Icon(Icons.timer_outlined, color: Colors.white70),
              title: const Text('Disappearing messages',
                  style: TextStyle(color: Colors.white)),
              trailing: Text(
                _disappearing == 'off' ? 'Off'
                    : _disappearing == '24h' ? '24 hours'
                    : _disappearing == '7d'  ? '7 days'
                    : '30 days',
                style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13),
              ),
              onTap: () => showModalBottomSheet(
                context: context,
                backgroundColor: const Color(0xFF0E1829),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                builder: (_) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.white.withAlpha(40),
                            borderRadius: BorderRadius.circular(2))),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text('Disappearing Messages',
                          style: TextStyle(color: Colors.white, fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                    for (final opt in [
                      ('off', 'Off',      Icons.timer_off_outlined),
                      ('24h', '24 hours', Icons.timer_outlined),
                      ('7d',  '7 days',   Icons.timer_outlined),
                      ('30d', '30 days',  Icons.timer_outlined),
                    ])
                      ListTile(
                        leading: Icon(opt.$3,
                            color: opt.$1 == _disappearing
                                ? const Color(0xFF4F8AFF) : Colors.white54),
                        title: Text(opt.$2,
                            style: TextStyle(
                                color: opt.$1 == _disappearing
                                    ? const Color(0xFF4F8AFF) : Colors.white)),
                        trailing: opt.$1 == _disappearing
                            ? const Icon(Icons.check_rounded, color: Color(0xFF4F8AFF))
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          _setDisappearing(opt.$1);
                        },
                      ),
                    const SizedBox(height: 8),
                  ]),
                ),
              ),
            ),

            // ── Media visibility ───────────────────────────────────────────
            SwitchListTile(
              secondary: const Icon(Icons.photo_library_outlined, color: Colors.white70),
              title: const Text('Media visibility',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _mediaVisible
                    ? 'Photos saved to gallery'
                    : 'Photos hidden from gallery',
                style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12),
              ),
              value: _mediaVisible,
              activeThumbColor: const Color(0xFF4F8AFF),
              onChanged: (_) => _toggleMediaVisible(),
            ),

            // ── Chat lock ──────────────────────────────────────────────────
            SwitchListTile(
              secondary: Icon(
                _isChatLocked ? Icons.lock_rounded : Icons.lock_open_outlined,
                color: _isChatLocked ? const Color(0xFF7C3AED) : Colors.white70,
              ),
              title: const Text('Chat lock',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                'Lock and hide this chat on this device.',
                style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12),
              ),
              value: _isChatLocked,
              activeThumbColor: const Color(0xFF7C3AED),
              onChanged: (_) => _toggleChatLock(),
            ),

            // ── Group send permission (admins only) ─────────────────────────
            if (widget.isGroup && _adminUids.contains(FirebaseAuth.instance.currentUser?.uid))
              SwitchListTile(
                secondary: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white70),
                title: const Text('Only admins can send', style: TextStyle(color: Colors.white)),
                subtitle: Text('Turn the group into an announcement channel.',
                    style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12)),
                value: _adminsOnly,
                activeThumbColor: const Color(0xFF4F8AFF),
                onChanged: (v) async {
                  setState(() => _adminsOnly = v);
                  await ChatService.setGroupSendPolicy(widget.chatId, v);
                },
              ),

            // ── Approve new members (invite-link joins) ─────────────────────
            if (widget.isGroup && _adminUids.contains(FirebaseAuth.instance.currentUser?.uid))
              SwitchListTile(
                secondary: const Icon(Icons.how_to_reg_outlined, color: Colors.white70),
                title: const Text('Approve new members', style: TextStyle(color: Colors.white)),
                subtitle: Text('People who use the invite link need your approval.',
                    style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12)),
                value: _requireApproval,
                activeThumbColor: const Color(0xFF4F8AFF),
                onChanged: (v) async {
                  setState(() => _requireApproval = v);
                  await ChatService.setRequireApproval(widget.chatId, v);
                },
              ),

            // ── Pending join requests (admins) ──────────────────────────────
            if (widget.isGroup && _adminUids.contains(FirebaseAuth.instance.currentUser?.uid))
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: ChatService.joinRequestsStream(widget.chatId),
                builder: (ctx, snap) {
                  final reqs = snap.data ?? [];
                  if (reqs.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text('JOIN REQUESTS (${reqs.length})',
                          style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                    ),
                    ...reqs.map((r) => ListTile(
                      leading: CircleAvatar(radius: 18, backgroundColor: const Color(0xFF2563EB),
                        child: Text((r['name'] as String? ?? '?').isNotEmpty ? (r['name'] as String)[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                      title: Text(r['name'] as String? ?? 'Someone', style: const TextStyle(color: Colors.white)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399)),
                          onPressed: () => ChatService.approveJoinRequest(widget.chatId, r['uid'] as String, r['name'] as String? ?? 'Member')),
                        IconButton(icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent),
                          onPressed: () => ChatService.rejectJoinRequest(widget.chatId, r['uid'] as String)),
                      ]),
                    )),
                  ]);
                },
              ),

            Divider(color: Colors.white.withAlpha(12), height: 28),

            // ── Group invite link ──────────────────────────────────────────
            if (widget.isGroup)
              ListTile(
                leading: const Icon(Icons.link_rounded, color: Colors.white70),
                title: const Text('Invite via link', style: TextStyle(color: Colors.white)),
                onTap: _shareInviteLink,
              ),

            // ── Chat wallpaper ─────────────────────────────────────────────
            ListTile(
              leading: const Icon(Icons.wallpaper_rounded, color: Colors.white70),
              title: const Text('Chat wallpaper', style: TextStyle(color: Colors.white)),
              onTap: _pickWallpaper,
            ),

            // ── Mute / Create group / Block / Delete ───────────────────────
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
                leading: const Icon(Icons.group_add_rounded, color: Colors.white70),
                title: Text('Create group with ${widget.name.split(' ').first}',
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/new-group',
                      extra: {'preselectedUid': widget.otherUid});
                },
              ),

            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orangeAccent),
              title: Text(widget.isGroup ? 'Report group' : 'Report ${widget.name.split(' ').first}',
                  style: const TextStyle(color: Colors.orangeAccent)),
              onTap: _reportContact,
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

// ── Full media gallery ────────────────────────────────────────────────────────

class _MediaGallerySheet extends StatefulWidget {
  final String chatId;
  const _MediaGallerySheet({required this.chatId});

  static void show(BuildContext context, String chatId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MediaGallerySheet(chatId: chatId),
    );
  }

  @override
  State<_MediaGallerySheet> createState() => _MediaGallerySheetState();
}

class _MediaGallerySheetState extends State<_MediaGallerySheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _images = [];
  List<Map<String, dynamic>> _docs   = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    final col = FirebaseFirestore.instance
        .collection('chats').doc(widget.chatId).collection('messages');
    final imgSnap = await col.where('type', isEqualTo: 'image').orderBy('createdAt', descending: true).get();
    final docSnap = await col.where('type', isEqualTo: 'document').orderBy('createdAt', descending: true).get();
    if (!mounted) return;
    setState(() {
      _images  = imgSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _docs    = docSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E1829),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white.withAlpha(40),
                    borderRadius: BorderRadius.circular(2))),
          )),
          const Text('Media & Docs',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            indicatorColor: const Color(0xFF4F8AFF),
            labelColor: const Color(0xFF4F8AFF),
            unselectedLabelColor: Colors.white54,
            tabs: const [Tab(text: 'Images'), Tab(text: 'Documents')],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)))
                : TabBarView(controller: _tabs, children: [
                    // Images tab
                    _images.isEmpty
                        ? Center(child: Text('No images yet', style: TextStyle(color: Colors.white.withAlpha(80))))
                        : GridView.builder(
                            controller: ctrl,
                            padding: const EdgeInsets.all(8),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
                            itemCount: _images.length,
                            itemBuilder: (_, i) {
                              final url = _images[i]['imageUrl'] as String? ?? '';
                              return GestureDetector(
                                onTap: () => _openImage(context, url),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                                      errorWidget: (_, _, _) => Container(
                                          color: Colors.white.withAlpha(10),
                                          child: const Icon(Icons.broken_image_outlined,
                                              color: Colors.white38))),
                                ),
                              );
                            },
                          ),
                    // Documents tab
                    _docs.isEmpty
                        ? Center(child: Text('No documents yet', style: TextStyle(color: Colors.white.withAlpha(80))))
                        : ListView.builder(
                            controller: ctrl,
                            itemCount: _docs.length,
                            itemBuilder: (_, i) {
                              final d    = _docs[i];
                              final name = (d['text'] as String? ?? 'Document').replaceFirst('📄 ', '');
                              final url  = d['imageUrl'] as String? ?? '';
                              return ListTile(
                                leading: Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFBBF24).withAlpha(30),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.insert_drive_file_rounded,
                                      color: Color(0xFFFBBF24), size: 22),
                                ),
                                title: Text(name,
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: IconButton(
                                  icon: const Icon(Icons.open_in_new_rounded,
                                      color: Color(0xFF4F8AFF), size: 18),
                                  onPressed: url.isNotEmpty
                                      ? () => launchUrl(Uri.parse(url),
                                          mode: LaunchMode.externalApplication)
                                      : null,
                                ),
                              );
                            },
                          ),
                  ]),
          ),
        ]),
      ),
    );
  }

  void _openImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain,
                errorWidget: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 60)),
          ),
        ),
      ),
    );
  }
}

// ── GIF picker sheet ──────────────────────────────────────────────────────────

class _GifPickerSheet extends StatefulWidget {
  final void Function(String url) onSelected;
  final Future<List<String>> Function(String query) searchGifs;
  const _GifPickerSheet({required this.onSelected, required this.searchGifs});

  @override
  State<_GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<_GifPickerSheet> {
  final _ctrl  = TextEditingController();
  List<String> _urls    = [];
  bool         _loading = false;

  @override
  void initState() {
    super.initState();
    _fetch('');
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _fetch(String q) async {
    setState(() => _loading = true);
    final results = await widget.searchGifs(q);
    if (mounted) setState(() { _urls = results; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(children: [
        Container(margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white.withAlpha(40),
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search GIFs…',
              hintStyle: TextStyle(color: Colors.white.withAlpha(60)),
              filled: true,
              fillColor: Colors.white.withAlpha(10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, color: Colors.white54),
                      onPressed: () { _ctrl.clear(); _fetch(''); })
                  : null,
            ),
            onSubmitted: _fetch,
            textInputAction: TextInputAction.search,
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF)))
              : _urls.isEmpty
                  ? Center(child: Text('No GIFs found',
                      style: TextStyle(color: Colors.white.withAlpha(80))))
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 4,
                          childAspectRatio: 1.6),
                      itemCount: _urls.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelected(_urls[i]);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(imageUrl: _urls[i], fit: BoxFit.cover,
                              placeholder: (_, _) => Container(color: Colors.white.withAlpha(8),
                                  child: const Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Color(0xFF4F8AFF))))),
                        ),
                      ),
                    ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

// ── Contact picker sheet ──────────────────────────────────────────────────────

class _ContactPickerSheet extends StatefulWidget {
  final List<Contact> contacts;
  const _ContactPickerSheet({required this.contacts});
  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.contacts.where((c) {
      final q = _query.toLowerCase();
      if (q.isEmpty) return true;
      return (c.displayName ?? '').toLowerCase().contains(q) ||
          c.phones.any((p) => p.number.contains(q));
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white.withAlpha(40),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search contacts…',
              hintStyle: TextStyle(color: Colors.white.withAlpha(80)),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withAlpha(12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final c = filtered[i];
              final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF1565C0),
                  child: Text(
                    (c.displayName?.isNotEmpty == true)
                        ? c.displayName![0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(c.displayName ?? '',
                    style: const TextStyle(color: Colors.white)),
                subtitle: phone.isNotEmpty
                    ? Text(phone,
                        style: TextStyle(
                            color: Colors.white.withAlpha(140), fontSize: 12))
                    : null,
                onTap: () => Navigator.pop(context, c),
              );
            },
          ),
        ),
      ]),
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

// ── Poll composer ─────────────────────────────────────────────────────────────

class _PollComposerSheet extends StatefulWidget {
  final void Function(String question, List<String> options, bool multi) onSubmit;
  const _PollComposerSheet({required this.onSubmit});
  @override
  State<_PollComposerSheet> createState() => _PollComposerSheetState();
}

class _PollComposerSheetState extends State<_PollComposerSheet> {
  final _q = TextEditingController();
  final _opts = <TextEditingController>[TextEditingController(), TextEditingController()];
  bool _multi = false;

  @override
  void dispose() { _q.dispose(); for (final c in _opts) { c.dispose(); } super.dispose(); }

  bool get _valid =>
      _q.text.trim().isNotEmpty && _opts.where((c) => c.text.trim().isNotEmpty).length >= 2;

  Widget _field(TextEditingController c, String hint) => Container(
    decoration: BoxDecoration(color: Colors.white.withAlpha(16), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withAlpha(30))),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: TextField(controller: c, style: const TextStyle(color: Colors.white, fontSize: 14), onChanged: (_) => setState(() {}),
      decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.white.withAlpha(90)), border: InputBorder.none)),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        const Text('Create poll', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _field(_q, 'Ask a question'),
        const SizedBox(height: 10),
        ..._opts.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _field(e.value, 'Option ${e.key + 1}'))),
        if (_opts.length < 8)
          TextButton.icon(onPressed: () => setState(() => _opts.add(TextEditingController())),
              icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF4F8AFF)),
              label: const Text('Add option', style: TextStyle(color: Color(0xFF4F8AFF)))),
        SwitchListTile(contentPadding: EdgeInsets.zero,
          title: const Text('Allow multiple answers', style: TextStyle(color: Colors.white, fontSize: 14)),
          value: _multi, activeThumbColor: const Color(0xFF4F8AFF), onChanged: (v) => setState(() => _multi = v)),
        const SizedBox(height: 6),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _valid ? () {
            Navigator.pop(context);
            widget.onSubmit(_q.text.trim(), _opts.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList(), _multi);
          } : null,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), disabledBackgroundColor: const Color(0xFF2563EB).withAlpha(80), padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('Send poll', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        )),
      ])),
    ));
  }
}

// ── Event composer ────────────────────────────────────────────────────────────

class _EventComposerSheet extends StatefulWidget {
  final void Function(String title, DateTime dateTime, String location, String description, bool addCall) onSubmit;
  const _EventComposerSheet({required this.onSubmit});
  @override
  State<_EventComposerSheet> createState() => _EventComposerSheetState();
}

class _EventComposerSheetState extends State<_EventComposerSheet> {
  final _title = TextEditingController();
  final _loc   = TextEditingController();
  final _desc  = TextEditingController();
  DateTime  _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  bool _addCall = false;

  @override
  void dispose() { _title.dispose(); _loc.dispose(); _desc.dispose(); super.dispose(); }

  DateTime get _dateTime => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date,
        firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Widget _field(TextEditingController c, String hint) => Container(
    decoration: BoxDecoration(color: Colors.white.withAlpha(16), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withAlpha(30))),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: TextField(controller: c, style: const TextStyle(color: Colors.white, fontSize: 14), onChanged: (_) => setState(() {}),
      decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.white.withAlpha(90)), border: InputBorder.none)),
  );

  Widget _pickTile(IconData icon, String label, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(color: Colors.white.withAlpha(16), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withAlpha(30))),
    child: Row(children: [Icon(icon, size: 16, color: Colors.white.withAlpha(160)), const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis))]),
  ));

  @override
  Widget build(BuildContext context) {
    final dl = '${_date.day}/${_date.month}/${_date.year}';
    final tl = '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    return SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        const Text('Create event', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _field(_title, 'Event title'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _pickTile(Icons.calendar_today_rounded, dl, _pickDate)),
          const SizedBox(width: 8),
          Expanded(child: _pickTile(Icons.access_time_rounded, tl, _pickTime)),
        ]),
        const SizedBox(height: 10),
        _field(_loc, 'Location (optional)'),
        const SizedBox(height: 10),
        _field(_desc, 'Description (optional)'),
        SwitchListTile(contentPadding: EdgeInsets.zero,
          title: const Text('Add video call link', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text('Members can join a live session', style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 12)),
          value: _addCall, activeThumbColor: const Color(0xFF4F8AFF), onChanged: (v) => setState(() => _addCall = v)),
        const SizedBox(height: 6),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _title.text.trim().isEmpty ? null : () {
            Navigator.pop(context);
            widget.onSubmit(_title.text.trim(), _dateTime, _loc.text.trim(), _desc.text.trim(), _addCall);
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), disabledBackgroundColor: const Color(0xFF2563EB).withAlpha(80), padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('Send event', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        )),
      ])),
    ));
  }
}
