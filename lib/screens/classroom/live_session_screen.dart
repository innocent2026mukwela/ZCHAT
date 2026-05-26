import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../utils/glass.dart';

class LiveSessionScreen extends StatefulWidget {
  final String courseId;
  final String roomId;
  const LiveSessionScreen({super.key, required this.courseId, required this.roomId});
  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  bool _micOn    = true;
  bool _camOn    = true;
  bool _screenOn = false;
  bool _chatOpen = false;

  final _chatMessages = [
    {'sender': 'Chanda',  'msg': 'Can you explain that again?'},
    {'sender': 'Mulenga', 'msg': 'What is the time complexity?'},
    {'sender': 'Lecturer','msg': 'O(n log n) for merge sort.'},
    {'sender': 'Bupe',    'msg': 'Thank you! Very clear.'},
  ];

  final _chatCtrl = TextEditingController();

  @override
  void dispose() { _chatCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          Column(children: [
            // App bar
            ClipRect(
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
                      padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
                      child: Row(children: [
                        IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.courseId, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          const Text('Live Session', style: TextStyle(color: Colors.white60, fontSize: 11)),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withAlpha(80)),
                          ),
                          child: const Row(children: [
                            Icon(Icons.fiber_manual_record_rounded, size: 9, color: Colors.redAccent),
                            SizedBox(width: 5),
                            Text('LIVE', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        GlassCard(
                          borderRadius: BorderRadius.circular(8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.people_rounded, size: 14, color: Colors.white.withAlpha(200)),
                            const SizedBox(width: 5),
                            Text('5', style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),

            // Main content
            Expanded(
              child: Row(children: [
                Expanded(
                  child: Column(children: [
                    // Video area
                    Expanded(
                      child: GlassCard(
                        borderRadius: BorderRadius.circular(0),
                        bgColor: Colors.black.withAlpha(60),
                        borderColor: Colors.transparent,
                        child: Center(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(
                              _screenOn ? Icons.screen_share_rounded : _camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                              size: 56, color: Colors.white.withAlpha(60),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _screenOn ? 'Screen sharing active' : _camOn ? 'Camera preview' : 'Camera off',
                              style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 14),
                            ),
                          ]),
                        ),
                      ),
                    ),

                    // Participants row
                    ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          height: 88,
                          color: Colors.white.withAlpha(8),
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            itemCount: 5,
                            itemBuilder: (ctx, i) {
                              final names = ['Lecturer', 'Chanda', 'Mulenga', 'Bupe', 'Tendo'];
                              final isActive = i == 0;
                              return Container(
                                width: 68,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(isActive ? 25 : 12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isActive ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(25), width: isActive ? 1.5 : 1),
                                ),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFF2563EB).withAlpha(80),
                                    child: Text(names[i][0], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(names[i], style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 9), overflow: TextOverflow.ellipsis),
                                ]),
                              ).animate(delay: (i * 80).ms).fadeIn();
                            },
                          ),
                        ),
                      ),
                    ),

                    // Controls
                    ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          color: Colors.white.withAlpha(10),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _Ctrl(icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,    label: _micOn ? 'Mute' : 'Unmute',     active: _micOn,    color: const Color(0xFF4F8AFF), onTap: () => setState(() => _micOn = !_micOn)),
                              _Ctrl(icon: _camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded, label: _camOn ? 'Stop Cam' : 'Start Cam', active: _camOn, color: const Color(0xFF4F8AFF), onTap: () => setState(() => _camOn = !_camOn)),
                              _Ctrl(icon: Icons.screen_share_rounded,  label: _screenOn ? 'Stop' : 'Share',   active: _screenOn, color: const Color(0xFFB794F4), onTap: () => setState(() => _screenOn = !_screenOn)),
                              _Ctrl(icon: Icons.chat_bubble_outline_rounded, label: 'Chat',      active: _chatOpen, color: const Color(0xFF86EFAC), onTap: () => setState(() => _chatOpen = !_chatOpen)),
                              _Ctrl(icon: Icons.call_end_rounded,       label: 'End',           active: true,      color: Colors.redAccent,           onTap: () => Navigator.of(context).pop()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),

                // Chat panel
                if (_chatOpen)
                  ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        width: 260,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(10),
                          border: Border(left: BorderSide(color: Colors.white.withAlpha(20))),
                        ),
                        child: Column(children: [
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              const Text('Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => setState(() => _chatOpen = false),
                                child: Icon(Icons.close_rounded, color: Colors.white.withAlpha(160), size: 18),
                              ),
                            ]),
                          ),
                          Divider(color: Colors.white.withAlpha(15), height: 1),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.all(12),
                              children: _chatMessages.map((m) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(m['sender']!, style: const TextStyle(color: Color(0xFF4F8AFF), fontSize: 11, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  GlassCard(
                                    borderRadius: BorderRadius.circular(10),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    child: Text(m['msg']!, style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 13)),
                                  ),
                                ]),
                              )).toList(),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                    child: Container(
                                      decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withAlpha(30))),
                                      child: TextField(
                                        controller: _chatCtrl,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'Type a message…', hintStyle: TextStyle(color: Colors.white.withAlpha(80)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                                child: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
                              ),
                            ]),
                          ),
                          SafeArea(top: false, child: const SizedBox(height: 4)),
                        ]),
                      ),
                    ),
                  ).animate().slideX(begin: 1, end: 0, duration: 250.ms),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Ctrl extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _Ctrl({required this.icon, required this.label, required this.active, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: active ? color.withAlpha(40) : Colors.white.withAlpha(15),
          shape: BoxShape.circle,
          border: Border.all(color: active ? color.withAlpha(80) : Colors.white.withAlpha(25)),
          boxShadow: active ? [BoxShadow(color: color.withAlpha(60), blurRadius: 12)] : [],
        ),
        child: Icon(icon, color: active ? color : Colors.white.withAlpha(120), size: 22),
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 10)),
    ]),
  );
}
