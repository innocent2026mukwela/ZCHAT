import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../utils/glass.dart';

class PdfViewerScreen extends StatefulWidget {
  final String url;
  final String title;
  const PdfViewerScreen({super.key, required this.url, required this.title});
  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  bool _downloaded = false;

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
                    Padding(padding: const EdgeInsets.fromLTRB(4, 8, 8, 0), child: Row(children: [
                      IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const Text('Past Paper', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ])),
                      IconButton(
                        icon: Icon(_downloaded ? Icons.download_done_rounded : Icons.download_rounded,
                          color: _downloaded ? const Color(0xFF86EFAC) : Colors.white),
                        onPressed: () {
                          setState(() => _downloaded = true);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text('Downloaded'), backgroundColor: const Color(0xFF2563EB),
                            behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ));
                        },
                      ),
                      IconButton(icon: const Icon(Icons.share_rounded, color: Colors.white), onPressed: () {}),
                    ])),
                    // Toolbar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: Row(children: [
                        _Tool(icon: Icons.zoom_in_rounded),
                        _Tool(icon: Icons.zoom_out_rounded),
                        _Tool(icon: Icons.fit_screen_rounded),
                        const Spacer(),
                        Text('Page 1 / 8', style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12)),
                        const Spacer(),
                        _Tool(icon: Icons.search_rounded),
                        _Tool(icon: Icons.bookmark_border_rounded),
                      ]),
                    ),
                  ])),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GlassCard(
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 80, height: 96,
                        decoration: BoxDecoration(color: Colors.red.withAlpha(40), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withAlpha(60))),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 40),
                          Text('PDF', style: TextStyle(color: Colors.redAccent.withAlpha(200), fontSize: 10, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      Text('PDF viewer', style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13)),
                    ]),
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOut),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 220,
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _downloaded = true),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), minimumSize: const Size(220, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: Icon(_downloaded ? Icons.check_rounded : Icons.download_rounded),
                      label: Text(_downloaded ? 'Downloaded ✓' : 'Download PDF', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ).animate(delay: 150.ms).fadeIn(),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 220,
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB794F4), side: const BorderSide(color: Color(0xFF7C3AED)), minimumSize: const Size(220, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.quiz_outlined),
                      label: const Text('Generate Quiz', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ).animate(delay: 200.ms).fadeIn(),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  final IconData icon;
  const _Tool({required this.icon});
  @override
  Widget build(BuildContext context) => IconButton(icon: Icon(icon, color: Colors.white.withAlpha(160), size: 18), onPressed: () {}, visualDensity: VisualDensity.compact);
}
