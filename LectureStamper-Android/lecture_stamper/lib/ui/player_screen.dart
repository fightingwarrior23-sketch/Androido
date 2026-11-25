import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import '../core/models.dart';
import '../core/project.dart';
import '../core/time_utils.dart';
import '../l10n/l10n.dart';
import '../services/native.dart';
import '../services/project_store.dart';
import '../services/settings.dart';
import 'audio_bar.dart';
import 'export_flow.dart';
import 'file_browser.dart';
import 'pdf_pane.dart';
import 'settings_screen.dart';
import 'stamp_list.dart';

class PlayerScreen extends StatefulWidget {
  final String id;
  final Project project;
  const PlayerScreen({super.key, required this.id, required this.project});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  late final Project pr = widget.project;
  final AudioPlayer player = AudioPlayer();
  final s = AppSettings.i;

  Duration total = Duration.zero;
  bool audioError = false;
  int leftIdx = 0, rightIdx = 1;
  late List<int> pages; // page in view for each PDF (0-based)
  final Map<String, GlobalKey<PdfPaneState>> _keys = {};
  double? armed; // pause-then-stamp: the second that was captured
  Timer? _saveTimer;

  GlobalKey<PdfPaneState> _key(String side, int idx) =>
      _keys.putIfAbsent('$side$idx', () => GlobalKey<PdfPaneState>());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pages = List.generate(pr.pdfs.length, (i) => i < pr.lastPages.length ? pr.lastPages[i] : 0);
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      final d = await player.setFilePath(pr.audio.path);
      await player.setSpeed(pr.speed);
      if (pr.position > 0) await player.seek(Duration(milliseconds: (pr.position * 1000).round()));
      if (mounted) setState(() {
        total = d ?? player.duration ?? Duration.zero;
        audioError = false;
      });
    } catch (_) {
      if (mounted) setState(() => audioError = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) _saveNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _saveNow();
    player.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- saving
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveNow);
  }

  Future<void> _saveNow() async {
    pr.position = player.position.inMilliseconds / 1000;
    pr.lastPages = List.of(pages);
    try {
      await ProjectStore.save(widget.id, pr);
    } catch (_) {}
  }

  void _say(String m, {SnackBarAction? action}) {
    final sm = ScaffoldMessenger.of(context);
    sm.clearSnackBars();
    sm.showSnackBar(SnackBar(content: Text(m), action: action, duration: const Duration(seconds: 3)));
  }

  // ------------------------------------------------------------------ audio
  double get _posSec => player.position.inMilliseconds / 1000;

  Future<void> _toggle() async {
    armed = null;
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) await player.seek(Duration.zero);
      player.play(); // completes only when paused; do not await
    }
    if (mounted) setState(() {});
  }

  Future<void> _seekTo(Duration d) async {
    final t = d < Duration.zero ? Duration.zero : (total > Duration.zero && d > total ? total : d);
    await player.seek(t);
  }

  // --------------------------------------------------------------- stamping
  (int, int) get _leftPage => (leftIdx, pages[leftIdx]);
  (int, int)? get _rightPage => pr.split && rightIdx < pr.pdfs.length ? (rightIdx, pages[rightIdx]) : null;

  Future<StampTarget?> _askTarget() {
    return showModalBottomSheet<StampTarget>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Flag which page?'), style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(ctx, StampTarget.left),
                  child: Text(tr('Left page ({n})', {'n': _leftPage.$2 + 1}))),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(ctx, StampTarget.right),
                  child: Text(tr('Right page ({n})', {'n': (_rightPage?.$2 ?? 0) + 1}))),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, StampTarget.both),
                  child: Text(tr('Both pages'))),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _onStampTap() async {
    if (pr.pdfs.isEmpty) return;
    double t;
    if (armed != null) {
      t = armed!;
    } else if (player.playing && !pr.stampWhilePlaying) {
      // pause-then-stamp: first tap pauses and remembers the moment
      await player.pause();
      HapticFeedback.selectionClick();
      if (mounted) setState(() => armed = _posSec);
      return;
    } else {
      t = _posSec;
    }

    var target = StampTarget.left;
    if (_rightPage != null) {
      final ans = await _askTarget();
      if (ans == null) return; // cancelled: stay armed
      target = ans;
    }
    final added = pr.book.stamp(
      seconds: t,
      split: pr.split,
      left: _leftPage,
      right: _rightPage,
      target: target,
    );
    final wasArmed = armed != null;
    armed = null;
    HapticFeedback.mediumImpact();
    if (added.isEmpty) {
      _say(tr('Already stamped here.'));
    } else {
      _say(
        added.length == 1
            ? tr('Stamped page {n} at {t}', {'n': added.first.page + 1, 't': fmtTime(t)})
            : tr('Stamped {k} pages at {t}', {'k': added.length, 't': fmtTime(t)}),
        action: SnackBarAction(
          label: tr('Undo'),
          onPressed: () {
            pr.book.undo();
            setState(() {});
            _scheduleSave();
          },
        ),
      );
    }
    if (wasArmed) player.play();
    setState(() {});
    _scheduleSave();
  }

  // ------------------------------------------------------------- navigation
  Future<void> _jumpTo(Stamp st) async {
    armed = null;
    await _seekTo(Duration(milliseconds: (st.seconds * 1000).round()));
    pages[st.pdf] = st.page;
    final inLeft = st.pdf == leftIdx;
    final inRight = pr.split && st.pdf == rightIdx;
    if (inLeft) {
      _key('L', leftIdx).currentState?.goTo(st.page);
    } else if (inRight) {
      _key('R', rightIdx).currentState?.goTo(st.page);
    } else {
      setState(() => leftIdx = st.pdf); // new pane opens on pages[st.pdf]
    }
    _scheduleSave();
  }

  Future<void> _addPdf() async {
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => FileBrowserScreen(audio: false, title: tr('Choose a PDF'))),
    );
    if (path == null || !mounted) return;
    if (pr.pdfs.any((r) => r.path == path)) {
      _say(tr('This PDF is already loaded.'));
      return;
    }
    setState(() {
      pr.pdfs.add(FileRef(path));
      pages.add(0);
      leftIdx = pr.pdfs.length - 1;
      if (s.splitDefault && pr.pdfs.length == 2) pr.split = true;
      if (pr.split) rightIdx = (leftIdx + 1) % pr.pdfs.length;
    });
    _scheduleSave();
  }

  Future<void> _removeCurrentPdf() async {
    if (pr.pdfs.length <= 1) return _say(tr('A project needs at least one PDF.'));
    final idx = leftIdx;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Remove this PDF?')),
        content: Text(tr('Its stamps are removed too.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Remove'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      pr.book.removePdf(idx);
      pr.pdfs.removeAt(idx);
      pages.removeAt(idx);
      _keys.clear();
      leftIdx = 0;
      rightIdx = pr.pdfs.length > 1 ? 1 : 0;
      if (pr.pdfs.length < 2) pr.split = false;
    });
    _scheduleSave();
  }

  void _toggleSplit() {
    if (pr.pdfs.length < 2) {
      _say(tr('Add a second PDF to use split screen.'),
          action: SnackBarAction(label: tr('Add PDF'), onPressed: _addPdf));
      return;
    }
    setState(() {
      pr.split = !pr.split;
      if (pr.split && (rightIdx == leftIdx || rightIdx >= pr.pdfs.length)) {
        rightIdx = (leftIdx + 1) % pr.pdfs.length;
      }
    });
    _scheduleSave();
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: pr.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Project name')),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('OK'))),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      setState(() => pr.name = v);
      _scheduleSave();
    }
  }

  Future<void> _openSettings() async {
    final oldCorner = s.corner, oldStyle = s.stampWhilePlaying;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (!mounted) return;
    setState(() {
      if (s.corner != oldCorner) {
        pr.corner = s.corner;
        pr.dragX = pr.dragY = null;
      }
      if (s.stampWhilePlaying != oldStyle) {
        pr.stampWhilePlaying = s.stampWhilePlaying;
        armed = null;
      }
    });
    _scheduleSave();
  }

  Future<void> _exportLvm() async {
    try {
      final base = ProjectStore.withRel(pr);
      final name = '${pr.name.isEmpty ? 'lecture' : pr.name}.lvm';
      final where = await Native.saveText(name, const JsonEncoder.withIndent(' ').convert(base.toLvm()));
      _say(tr('Saved to {path}', {'path': where}));
    } catch (e) {
      _say('$e');
    }
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final marks = pr.book.stamps.map((e) => e.seconds).toList();
    return Scaffold(
      appBar: AppBar(
        leading: PopupMenuButton<String>(
          icon: const Icon(Icons.menu),
          tooltip: tr('Options'),
          onSelected: (v) async {
            switch (v) {
              case 'save':
                await _saveNow();
                _say(tr('Project saved.'));
              case 'list':
                _openList();
              case 'add':
                _addPdf();
              case 'remove':
                _removeCurrentPdf();
              case 'rename':
                _rename();
              case 'export':
                await _saveNow();
                if (mounted) runExport(context, pr);
              case 'lvm':
                _exportLvm();
              case 'settings':
                _openSettings();
              case 'home':
                Navigator.pop(context);
            }
          },
          itemBuilder: (_) => [
            _item('save', Icons.save, tr('Save project')),
            _item('list', Icons.list_alt, tr('Stamp list')),
            _item('add', Icons.picture_as_pdf, tr('Add PDF')),
            _item('remove', Icons.delete_outline, tr('Remove this PDF')),
            _item('rename', Icons.edit, tr('Rename project')),
            const PopupMenuDivider(),
            _item('export', Icons.movie, tr('Export video')),
            _item('lvm', Icons.computer, tr('Save for the desktop program (.lvm)')),
            const PopupMenuDivider(),
            _item('settings', Icons.settings, tr('Settings')),
            _item('home', Icons.home, tr('Projects')),
          ],
        ),
        title: GestureDetector(
          onTap: _rename,
          child: Text(pr.name.isEmpty ? tr('Untitled') : pr.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          IconButton(
            tooltip: tr('Split screen'),
            isSelected: pr.split,
            icon: const Icon(Icons.vertical_split_outlined),
            selectedIcon: const Icon(Icons.vertical_split),
            onPressed: _toggleSplit,
          ),
          IconButton(
            tooltip: tr('Stamp list'),
            icon: Badge(
              isLabelVisible: pr.book.stamps.isNotEmpty,
              label: Text('${pr.book.stamps.length}'),
              child: const Icon(Icons.flag_outlined),
            ),
            onPressed: _openList,
          ),
        ],
      ),
      body: Column(children: [
        if (!pr.split) _tabs(),
        Expanded(
          child: LayoutBuilder(builder: (ctx, c) => Stack(children: [
            Positioned.fill(child: _panes()),
            _stampButton(c),
          ])),
        ),
        if (audioError)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(tr('The audio file cannot be opened.')),
              trailing: TextButton(
                onPressed: () async {
                  final path = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(builder: (_) => FileBrowserScreen(audio: true, title: tr('Choose the audio'))),
                  );
                  if (path != null) {
                    pr.audio = FileRef(path);
                    await _initAudio();
                    _scheduleSave();
                  }
                },
                child: Text(tr('Choose another')),
              ),
            ),
          )
        else
          StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (_, snap) => StreamBuilder<bool>(
              stream: player.playingStream,
              builder: (_, pl) => AudioBar(
                position: snap.data ?? player.position,
                total: total,
                playing: pl.data ?? false,
                speed: pr.speed,
                marks: marks,
                onSeek: (d) {
                  armed = null;
                  _seekTo(d);
                },
                onToggle: _toggle,
                onBack: () => _seekTo(player.position - const Duration(seconds: 5)),
                onForward: () => _seekTo(player.position + const Duration(seconds: 5)),
                onSpeed: (v) {
                  player.setSpeed(v);
                  setState(() => pr.speed = v);
                  s.speed = v;
                  _scheduleSave();
                },
              ),
            ),
          ),
      ]),
    );
  }

  PopupMenuItem<String> _item(String v, IconData i, String t) => PopupMenuItem(
        value: v,
        child: Row(children: [Icon(i, size: 20), const SizedBox(width: 12), Flexible(child: Text(t))]),
      );

  void _openList() => showStampList(
        context,
        project: pr,
        onJump: _jumpTo,
        onChanged: () {
          setState(() {});
          _scheduleSave();
        },
      );

  Widget _tabs() {
    return SizedBox(
      height: 48,
      child: Row(children: [
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: pr.pdfs.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(p.basenameWithoutExtension(pr.pdfs[i].path), overflow: TextOverflow.ellipsis),
                ),
                selected: i == leftIdx,
                onSelected: (_) => setState(() => leftIdx = i),
              ),
            ),
          ),
        ),
        IconButton(tooltip: tr('Add PDF'), icon: const Icon(Icons.add_circle_outline), onPressed: _addPdf),
      ]),
    );
  }

  Widget _paneFor(String side, int idx) {
    return PdfPane(
      key: _key(side, idx),
      path: pr.pdfs[idx].path,
      initialPage: pages[idx],
      onPage: (pg) {
        pages[idx] = pg;
        _scheduleSave();
      },
    );
  }

  Widget _header(int value, ValueChanged<int> onChanged) {
    return SizedBox(
      height: 44,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: value,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          items: [
            for (var i = 0; i < pr.pdfs.length; i++)
              DropdownMenuItem(value: i, child: Text(p.basenameWithoutExtension(pr.pdfs[i].path), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }

  Widget _panes() {
    if (pr.pdfs.isEmpty) return Center(child: Text(tr('No PDF loaded.')));
    if (!pr.split || rightIdx >= pr.pdfs.length) return _paneFor('L', leftIdx);
    return Row(children: [
      Expanded(
        child: Column(children: [
          _header(leftIdx, (v) => setState(() => leftIdx = v)),
          Expanded(child: _paneFor('L', leftIdx)),
        ]),
      ),
      const VerticalDivider(width: 2),
      Expanded(
        child: Column(children: [
          _header(rightIdx, (v) => setState(() => rightIdx = v)),
          Expanded(child: _paneFor('R', rightIdx)),
        ]),
      ),
    ]);
  }

  Widget _stampButton(BoxConstraints c) {
    const sz = 80.0;
    final maxX = (c.maxWidth - sz).clamp(1.0, double.infinity);
    final maxY = (c.maxHeight - sz).clamp(1.0, double.infinity);
    double x, y;
    if (pr.dragX != null && pr.dragY != null) {
      x = pr.dragX! * maxX;
      y = pr.dragY! * maxY;
    } else {
      final right = pr.corner.endsWith('Right');
      final bottom = pr.corner.startsWith('bottom');
      x = right ? maxX - 12 : 12;
      y = bottom ? maxY - 64 : 12; // keep clear of the page buttons at the bottom
    }
    x = x.clamp(0.0, maxX);
    y = y.clamp(0.0, maxY);
    final cs = Theme.of(context).colorScheme;
    final isArmed = armed != null;
    return Positioned(
      left: x,
      top: y,
      child: GestureDetector(
        onTap: _onStampTap,
        onPanUpdate: (d) {
          setState(() {
            pr.dragX = ((x + d.delta.dx).clamp(0.0, maxX)) / maxX;
            pr.dragY = ((y + d.delta.dy).clamp(0.0, maxY)) / maxY;
          });
        },
        onPanEnd: (_) => _scheduleSave(),
        child: Semantics(
          button: true,
          label: tr('Stamp'),
          child: Container(
            width: sz,
            height: sz,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isArmed ? Colors.orange : cs.primary,
              boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38, offset: Offset(0, 3))],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(isArmed ? Icons.check : Icons.flag, color: Colors.white, size: 32),
              Text(
                isArmed ? fmtTime(armed!) : tr('Stamp'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
