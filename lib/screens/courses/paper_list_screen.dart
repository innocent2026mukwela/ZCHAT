import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/papers_service.dart';
import '../../utils/glass.dart';

class PaperListScreen extends StatefulWidget {
  final String courseId;
  const PaperListScreen({super.key, required this.courseId});

  @override
  State<PaperListScreen> createState() => _PaperListScreenState();
}

class _PaperListScreenState extends State<PaperListScreen> {
  String _filter    = 'All';
  String _query     = '';
  String _bandwidth = 'Standard';
  bool   _isLecturer = false;

  @override
  void initState() {
    super.initState();
    PapersService.isLecturer().then((v) { if (mounted) setState(() => _isLecturer = v); });
    SharedPreferences.getInstance().then((p) {
      final saved = p.getString('bandwidth_mode');
      if (saved != null && mounted) setState(() => _bandwidth = saved);
    });
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> all) {
    var list = _filter == 'Verified' ? all.where((p) => p['verified'] == true).toList() : List.of(all);
    if (_query.isNotEmpty) {
      list = list.where((p) {
        final text = '${p['year']} semester ${p['semester']}';
        return text.contains(_query);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kBgGradient),
        child: Stack(children: [
          const GlowOrbs(),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: PapersService.papersStream(widget.courseId),
            builder: (context, snap) {
              final allPapers = snap.data ?? [];
              final papers    = _applyFilter(allPapers);
              final verified  = allPapers.where((p) => p['verified'] == true).length;

              return Column(children: [
                _Header(
                  courseId:  widget.courseId,
                  filter:    _filter,
                  bandwidth: _bandwidth,
                  onFilter:  (v) => setState(() => _filter = v),
                  onSearch:  (v) => setState(() => _query = v.toLowerCase()),
                  onBandwidth: _showBandwidthSheet,
                  onUpload:  () => _showUpload(context),
                ),
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      color: Colors.white.withAlpha(8),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(children: [
                        _Stat('${allPapers.length}', 'Total',    const Color(0xFF4F8AFF)),
                        const SizedBox(width: 10),
                        _Stat('$verified',            'Verified', const Color(0xFF86EFAC)),
                        const SizedBox(width: 10),
                        _Stat(_bandwidth,              'Mode',     const Color(0xFFFBBF24)),
                      ]),
                    ),
                  ),
                ),
                if (snap.connectionState == ConnectionState.waiting)
                  const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF4F8AFF))))
                else if (snap.hasError)
                  Expanded(child: Center(child: Text('Could not load papers',
                      style: TextStyle(color: Colors.white.withAlpha(120)))))
                else if (papers.isEmpty)
                  Expanded(child: Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.picture_as_pdf_rounded, size: 52, color: Colors.white.withAlpha(60)),
                      const SizedBox(height: 12),
                      Text('No past papers yet.\nUse the upload button to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withAlpha(120), height: 1.5)),
                    ]),
                  ))
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: papers.length,
                      itemBuilder: (ctx, i) => _PaperCard(
                        paper:      papers[i],
                        courseId:   widget.courseId,
                        isLecturer: _isLecturer,
                        onVerify:   () => _toggleVerify(papers[i]),
                        onDownload: () => _openPdf(papers[i]),
                        onExamMode: () => context.push(
                          '/exam-simulator/${Uri.encodeComponent(widget.courseId)}?paper=${papers[i]['year']}_S${papers[i]['semester']}',
                        ),
                      ).animate(delay: (i * 45).ms).fadeIn().slideY(begin: 0.05, end: 0),
                    ),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _toggleVerify(Map<String, dynamic> paper) async {
    final id       = paper['id'] as String;
    final verified = paper['verified'] as bool? ?? false;
    if (verified) {
      await PapersService.unverifyPaper(id);
    } else {
      await PapersService.verifyPaper(id);
    }
  }

  Future<void> _openPdf(Map<String, dynamic> paper) async {
    final url = paper['fileUrl'] as String?;
    if (url == null) return;

    // Data Saver mode: confirm before pulling the file over a metered connection.
    if (_bandwidth == 'Data Saver') {
      final size = paper['fileSize'] as String? ?? '';
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: const Color(0xFF0A1A4A),
          title: const Text('Data Saver is on', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(
            'Downloading this paper${size.isNotEmpty ? ' ($size)' : ''} will use mobile data. Continue?',
            style: TextStyle(color: Colors.white.withAlpha(180)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Download', style: TextStyle(color: Color(0xFF4F8AFF))),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await PapersService.recordDownload(paper['id'] as String);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showBandwidthSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A1A4A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Bandwidth Mode', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Data Saver disables previews and keeps PDFs on demand only.',
              style: TextStyle(color: Colors.white.withAlpha(150), height: 1.4)),
          const SizedBox(height: 16),
          for (final mode in ['High', 'Standard', 'Data Saver'])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                mode == 'Data Saver' ? Icons.signal_cellular_alt_1_bar : Icons.signal_cellular_alt_rounded,
                color: mode == _bandwidth ? const Color(0xFF4F8AFF) : Colors.white70,
              ),
              title: Text(mode, style: const TextStyle(color: Colors.white)),
              trailing: mode == _bandwidth ? const Icon(Icons.check_rounded, color: Color(0xFF86EFAC)) : null,
              onTap: () async {
                setState(() => _bandwidth = mode);
                Navigator.pop(context);
                final p = await SharedPreferences.getInstance();
                await p.setString('bandwidth_mode', mode);
              },
            ),
        ]),
      ),
    );
  }

  void _showUpload(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UploadSheet(
        courseId: widget.courseId,
        onDone: () => Navigator.pop(context),
      ),
    );
  }
}

// ── Paper Card ─────────────────────────────────────────────────────────────────

class _PaperCard extends StatelessWidget {
  final Map<String, dynamic> paper;
  final String courseId;
  final bool isLecturer;
  final VoidCallback onVerify;
  final VoidCallback onDownload;
  final VoidCallback onExamMode;

  const _PaperCard({
    required this.paper,
    required this.courseId,
    required this.isLecturer,
    required this.onVerify,
    required this.onDownload,
    required this.onExamMode,
  });

  @override
  Widget build(BuildContext context) {
    final year      = paper['year']      as int?    ?? 0;
    final sem       = paper['semester']  as int?    ?? 1;
    final verified  = paper['verified']  as bool?   ?? false;
    final downloads = (paper['downloads'] as num?)?.toInt() ?? 0;
    final fileSize  = paper['fileSize']  as String? ?? '–';
    final uploader  = paper['uploaderName'] as String? ?? 'Unknown';

    return GlassCard(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 46, height: 56,
          decoration: BoxDecoration(
            color: Colors.red.withAlpha(40),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.withAlpha(60)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 24),
            Text('PDF', style: TextStyle(fontSize: 9, color: Colors.redAccent.withAlpha(200), fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('$year – Semester $sem',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
            if (isLecturer)
              GestureDetector(
                onTap: onVerify,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: verified ? const Color(0xFF86EFAC).withAlpha(30) : Colors.orange.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: verified ? const Color(0xFF86EFAC).withAlpha(80) : Colors.orange.withAlpha(80)),
                  ),
                  child: Text(
                    verified ? '✓ Verified' : 'Verify',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: verified ? const Color(0xFF86EFAC) : Colors.orange,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          Text('Uploaded by $uploader', style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 11)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (verified)
              const _MetaChip(icon: Icons.verified_rounded,   label: 'Verified',   color: Color(0xFF86EFAC))
            else
              const _MetaChip(icon: Icons.pending_outlined,   label: 'Unverified', color: Colors.orange),
            _MetaChip(icon: Icons.download_outlined,          label: '$downloads',  color: Colors.white70),
            _MetaChip(icon: Icons.sd_storage_outlined,        label: fileSize,      color: Colors.white60),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _MiniAction(label: 'Open',      icon: Icons.visibility_outlined,      color: const Color(0xFF4F8AFF),  onTap: onDownload),
            const SizedBox(width: 8),
            _MiniAction(label: 'AI Practice', icon: Icons.psychology_alt_outlined,  color: const Color(0xFFB794F4),  onTap: onExamMode),
          ]),
        ])),
      ]),
    );
  }
}

// ── Upload Sheet ───────────────────────────────────────────────────────────────

class _UploadSheet extends StatefulWidget {
  final String courseId;
  final VoidCallback onDone;
  const _UploadSheet({required this.courseId, required this.onDone});
  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  String? _filePath;
  String? _fileName;
  int     _year     = DateTime.now().year;
  int     _semester = 1;
  bool    _uploading = false;
  String? _error;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _filePath = result.files.single.path;
        _fileName = result.files.single.name;
      });
    }
  }

  Future<void> _upload() async {
    if (_filePath == null) { setState(() => _error = 'Please select a PDF file'); return; }
    setState(() { _uploading = true; _error = null; });
    try {
      final exists = await PapersService.duplicateExists(
        courseId: widget.courseId, year: _year, semester: _semester);
      if (exists) {
        if (mounted) setState(() { _uploading = false; _error = 'A paper for $_year Semester $_semester already exists.'; });
        return;
      }
      await PapersService.uploadPaper(
        courseId:  widget.courseId,
        filePath:  _filePath!,
        fileName:  _fileName!,
        year:      _year,
        semester:  _semester,
      );
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) setState(() { _uploading = false; _error = 'Upload failed. Try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A1A4A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Upload Past Paper', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 20),

          // File picker
          GestureDetector(
            onTap: _uploading ? null : _pickFile,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _filePath != null ? const Color(0xFF2563EB).withAlpha(20) : Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _filePath != null ? const Color(0xFF4F8AFF).withAlpha(150) : Colors.white.withAlpha(30),
                  width: _filePath != null ? 1.5 : 1,
                ),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_filePath != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                  size: 28, color: _filePath != null ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(140)),
                const SizedBox(width: 10),
                Flexible(child: Text(
                  _fileName ?? 'Tap to select PDF',
                  style: TextStyle(color: _filePath != null ? const Color(0xFF4F8AFF) : Colors.white.withAlpha(140), fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                )),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Year + Semester row
          Row(children: [
            Expanded(child: _DropdownField<int>(
              label: 'Year',
              value: _year,
              items: List.generate(10, (i) => DateTime.now().year - i),
              itemLabel: (v) => '$v',
              onChanged: (v) { if (v != null) setState(() => _year = v); },
            )),
            const SizedBox(width: 12),
            Expanded(child: _DropdownField<int>(
              label: 'Semester',
              value: _semester,
              items: [1, 2],
              itemLabel: (v) => 'Semester $v',
              onChanged: (v) { if (v != null) setState(() => _semester = v); },
            )),
          ]),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 20),

          SizedBox(width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _uploading ? null : _upload,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                disabledBackgroundColor: const Color(0xFF2563EB).withAlpha(100),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _uploading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('Upload Paper', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  const _DropdownField({required this.label, required this.value, required this.items, required this.itemLabel, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.white.withAlpha(15), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white.withAlpha(35))),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: const Color(0xFF0A1A4A),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            items: items.map((i) => DropdownMenuItem(value: i, child: Text(itemLabel(i)))).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    ]);
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String courseId, filter, bandwidth;
  final ValueChanged<String> onFilter, onSearch;
  final VoidCallback onBandwidth, onUpload;

  const _Header({
    required this.courseId,
    required this.filter,
    required this.bandwidth,
    required this.onFilter,
    required this.onSearch,
    required this.onBandwidth,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(color: Colors.white.withAlpha(12), border: Border(bottom: BorderSide(color: Colors.white.withAlpha(20)))),
          child: SafeArea(bottom: false, child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(4, 8, 12, 0), child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
              Expanded(child: Text(courseId, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
              _BandwidthChip(mode: bandwidth, onTap: onBandwidth),
              IconButton(icon: const Icon(Icons.upload_file_outlined, color: Colors.white), onPressed: onUpload),
            ])),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withAlpha(35))),
                    child: TextField(
                      onChanged: onSearch,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search by year…',
                        hintStyle: TextStyle(color: Colors.white.withAlpha(105)),
                        prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(150), size: 20),
                        border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: ['All', 'Verified'].map((f) {
                final sel = filter == f;
                return GestureDetector(
                  onTap: () => onFilter(f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF2563EB) : Colors.white.withAlpha(18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? const Color(0xFF2563EB) : Colors.white.withAlpha(35)),
                    ),
                    child: Text(f, style: TextStyle(color: Colors.white, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
                  ),
                );
              }).toList()),
            ),
          ])),
        ),
      ),
    );
  }
}

// ── Shared small widgets ───────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _MetaChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 12, color: color), const SizedBox(width: 3),
    Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  ]);
}

class _MiniAction extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _MiniAction({required this.label, required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(9), border: Border.all(color: color.withAlpha(60))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 15), const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      ]),
    ),
  );
}

class _BandwidthChip extends StatelessWidget {
  final String mode; final VoidCallback onTap;
  const _BandwidthChip({required this.mode, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withAlpha(18), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withAlpha(35))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.speed_rounded, color: Color(0xFF86EFAC), size: 14), const SizedBox(width: 4),
        Text(mode, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _Stat extends StatelessWidget {
  final String value, label; final Color color;
  const _Stat(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withAlpha(40))),
      child: Column(children: [
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 11)),
      ]),
    ),
  );
}
