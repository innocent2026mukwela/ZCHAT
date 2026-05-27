import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../utils/glass.dart';

class PdfViewerScreen extends StatefulWidget {
  final String url;
  final String title;
  const PdfViewerScreen({super.key, required this.url, required this.title});
  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final _pdfKey = GlobalKey<SfPdfViewerState>();
  final _ctrl   = PdfViewerController();
  int  _currentPage = 1;
  int  _totalPages  = 0;
  bool _loading     = true;
  bool _error       = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
            // App bar
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
                        icon: const Icon(Icons.share_rounded, color: Colors.white),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: widget.url));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Link copied to clipboard'),
                            backgroundColor: Color(0xFF2563EB),
                            behavior: SnackBarBehavior.floating,
                          ));
                        },
                      ),
                    ])),
                    // Toolbar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: Row(children: [
                        _Tool(icon: Icons.zoom_in_rounded, onTap: () => _ctrl.zoomLevel = (_ctrl.zoomLevel + 0.25).clamp(0.5, 4.0)),
                        _Tool(icon: Icons.zoom_out_rounded, onTap: () => _ctrl.zoomLevel = (_ctrl.zoomLevel - 0.25).clamp(0.5, 4.0)),
                        _Tool(icon: Icons.fit_screen_rounded, onTap: () { _ctrl.zoomLevel = 1.0; }),
                        const Spacer(),
                        if (_totalPages > 0)
                          Text('Page $_currentPage / $_totalPages', style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12)),
                        const Spacer(),
                        _Tool(icon: Icons.search_rounded, onTap: () => _pdfKey.currentState?.openBookmarkView()),
                        _Tool(icon: Icons.keyboard_arrow_up_rounded, onTap: () => _ctrl.previousPage()),
                        _Tool(icon: Icons.keyboard_arrow_down_rounded, onTap: () => _ctrl.nextPage()),
                      ]),
                    ),
                  ])),
                ),
              ),
            ),

            // PDF content
            Expanded(
              child: widget.url.isEmpty
                  ? _EmptyState(title: widget.title, onQuiz: () => _navigateToQuiz(context))
                  : Stack(children: [
                      SfPdfViewer.network(
                        widget.url,
                        key: _pdfKey,
                        controller: _ctrl,
                        onDocumentLoaded: (details) {
                          setState(() {
                            _totalPages = details.document.pages.count;
                            _loading = false;
                          });
                        },
                        onDocumentLoadFailed: (details) {
                          setState(() { _loading = false; _error = true; });
                        },
                        onPageChanged: (details) {
                          setState(() => _currentPage = details.newPageNumber);
                        },
                      ),
                      if (_loading)
                        const Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF))),
                      if (_error)
                        _EmptyState(title: widget.title, onQuiz: () => _navigateToQuiz(context)),
                    ]),
            ),

            // Bottom action bar
            if (!_loading && !_error && widget.url.isNotEmpty)
              Container(
                color: Colors.black.withAlpha(80),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: SafeArea(
                  top: false,
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _navigateToQuiz(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB794F4),
                          side: const BorderSide(color: Color(0xFF7C3AED)),
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.quiz_outlined),
                        label: const Text('Generate Quiz', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ).animate().slideY(begin: 0.3, end: 0),
          ]),
        ]),
      ),
    );
  }

  void _navigateToQuiz(BuildContext context) {
    // Extract courseCode from title (e.g. "CS3201 2023 Paper" → "CS3201")
    final parts  = widget.title.split(' ');
    final course = parts.isNotEmpty ? parts.first : 'course';
    context.push('/ai/quiz/$course');
  }
}

// ── Empty / error state ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String title;
  final VoidCallback onQuiz;
  const _EmptyState({required this.title, required this.onQuiz});

  @override
  Widget build(BuildContext context) {
    return Center(
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
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('PDF not available', style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 13)),
          ]),
        ).animate().scale(duration: 400.ms, curve: Curves.easeOut),
        const SizedBox(height: 28),
        SizedBox(
          width: 220,
          child: OutlinedButton.icon(
            onPressed: onQuiz,
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB794F4), side: const BorderSide(color: Color(0xFF7C3AED)), minimumSize: const Size(220, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            icon: const Icon(Icons.quiz_outlined),
            label: const Text('Generate Quiz', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ).animate(delay: 200.ms).fadeIn(),
      ]),
    );
  }
}

// ── Toolbar button ────────────────────────────────────────────────────────────

class _Tool extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Tool({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, color: Colors.white.withAlpha(160), size: 18),
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
  );
}
