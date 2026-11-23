// lib/features/games/admin/v4/timing_tool.dart — the ayah timing tool for a per-surah reciter (Games v4 T85, CONTRACT §9, §10, §13).
//
//   TimingSurahsPage   GET …/reciters/{key}/timings: the 114 surahs with marked / total
//   TimingSurahPage    GET | PUT …/reciters/{key}/timings/{surah}: the surah plays; tap "end of this ayah" as each one
//                      ends; nudge ±100 ms; replay a mark; save the surah
//   TimingDraft        the marks as plain values (pure Dart, tested): an ayah starts where the one before it ends, so
//                      only the first start and every end are stored
//   TimingEditorBody   the editor over plain values (no player, no api), what the layout harness tests
//
// Ayah 1 starts after the basmala of the surah file (CONTRACT §9, except 1 and 9 where it is the ayah itself): the first
// start defaults to 0 and "Start of ayah 1 here" sets it at the playhead. A save sends the marked prefix only; the
// server refuses non-ascending or overlapping rows (422 `bad_timings`) and stamps `source: admin`.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart';

/// 83250 -> "1:23.250".
String timingClock(int ms) {
  final m = ms ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  final r = ms % 1000;
  return '$m:${s.toString().padLeft(2, '0')}.${r.toString().padLeft(3, '0')}';
}

/// The marks of one surah. `ends[i]` is the end of ayah i + 1 (null = not marked yet); ayah i starts where ayah i - 1
/// ends, ayah 1 at `start0`. Marks fill from the top, so the marked ayat are always a prefix.
class TimingDraft {
  TimingDraft(this.count, {this.start0 = 0, List<int?>? ends}) : ends = ends ?? List<int?>.filled(count, null);

  factory TimingDraft.fromServer(List<Json> ayat) {
    final ends = <int?>[for (final a in ayat) a['end_ms'] is num ? (a['end_ms'] as num).toInt() : null];
    // a hole in the server rows is not a prefix: keep the leading run
    final cut = ends.indexOf(null);
    if (cut >= 0) {
      for (var i = cut; i < ends.length; i++) {
        ends[i] = null;
      }
    }
    final first = ayat.isEmpty ? null : ayat.first['start_ms'];
    return TimingDraft(ayat.length, start0: first is num ? first.toInt() : 0, ends: ends);
  }

  final int count;
  int start0;
  final List<int?> ends;

  int get marked => ends.where((e) => e != null).length;
  bool get complete => marked == count;
  int? get nextToMark => marked < count ? marked : null;
  int? startOf(int i) => i == 0 ? start0 : ends[i - 1];
  int? endOf(int i) => ends[i];

  /// The playhead ends the next unmarked ayah.
  bool mark(int posMs) {
    final i = nextToMark;
    if (i == null || posMs <= (startOf(i) ?? 0)) return false;
    ends[i] = posMs;
    return true;
  }

  /// Moves the end of ayah i (and so the start of the next one) by [deltaMs]; refused when it would cross a neighbour.
  bool nudgeEnd(int i, int deltaMs) {
    final e = ends[i];
    if (e == null) return false;
    final v = e + deltaMs;
    final next = i + 1 < count ? ends[i + 1] : null;
    if (v <= startOf(i)! || (next != null && v >= next)) return false;
    ends[i] = v;
    return true;
  }

  bool nudgeStart0(int deltaMs) => setStart0(start0 + deltaMs);

  bool setStart0(int ms) {
    final e = ends[0];
    if (ms < 0 || (e != null && ms >= e)) return false;
    start0 = ms;
    return true;
  }

  /// Forgets the mark of ayah i and of every ayah after it.
  void clearFrom(int i) {
    for (var j = i; j < count; j++) {
      ends[j] = null;
    }
  }

  List<Json> toBody() => [
        for (var i = 0; i < count; i++)
          if (ends[i] != null) {'ayah': i + 1, 'start_ms': startOf(i), 'end_ms': ends[i]}
      ];
}

/// The player the tool needs, so a test can fake it.
abstract class TimingPlayer {
  Future<void> load(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int ms);
  Stream<int> get positionMs;
  Stream<int> get durationMs;
  Future<void> dispose();
}

class AudioplayersTimingPlayer implements TimingPlayer {
  final AudioPlayer _p = AudioPlayer();

  @override
  Future<void> load(String url) => _p.setSource(UrlSource(url));

  @override
  Future<void> play() => _p.resume();

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> seek(int ms) => _p.seek(Duration(milliseconds: ms));

  @override
  Stream<int> get positionMs => _p.onPositionChanged.map((d) => d.inMilliseconds);

  @override
  Stream<int> get durationMs => _p.onDurationChanged.map((d) => d.inMilliseconds);

  @override
  Future<void> dispose() => _p.dispose();
}

// ── the surah list ───────────────────────────────────────────────────────────

class TimingSurahsPage extends StatefulWidget {
  const TimingSurahsPage({super.key, required this.reciterKey, required this.reciterName, this.api, this.playerFactory});
  final String reciterKey;
  final String reciterName;
  final ItemsV4Api? api;
  final TimingPlayer Function()? playerFactory;

  @override
  State<TimingSurahsPage> createState() => _TimingSurahsPageState();
}

class _TimingSurahsPageState extends State<TimingSurahsPage> {
  late final ItemsV4Api _api = widget.api ?? ItemsV4Api();
  List<Json>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.timingSurahs(widget.reciterKey);
      if (mounted) setState(() { _items = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = itemErrorText(e));
    }
  }

  Future<void> _open(Json s) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TimingSurahPage(
        reciterKey: widget.reciterKey,
        surah: jint(s['surah']),
        surahName: '${s['name_ar'] ?? ''}',
        api: _api,
        playerFactory: widget.playerFactory,
      ),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        helpPageId: 'admin.games.timings',
        width: AppWidth.reading,
        title: t('أزمنة الآيات', 'Ayah timings'),
        subtitle: widget.reciterName,
        icon: Icons.timer_outlined,
        onRefresh: _load,
        body: _error != null && _items == null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _items == null
                ? const AppListSkeleton(items: 6)
                : TimingSurahsBody(items: _items!, onOpen: _open),
      );
}

class TimingSurahsBody extends StatelessWidget {
  const TimingSurahsBody({super.key, required this.items, required this.onOpen});
  final List<Json> items;
  final ValueChanged<Json> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return AppEmpty(icon: Icons.timer_outlined, title: t('لا سور بعد', 'No surahs yet'));
    final done = items.where((s) => jint(s['marked']) >= jint(s['ayat']) && jint(s['ayat']) > 0).length;
    return ListView(
      padding: AdminPage.bodyPadding(context),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Text(t('$done من ${items.length} سورة مكتملة', '$done of ${items.length} surahs complete'), style: AppType.meta(context)),
        ),
        for (final s in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: _SurahRow(surah: s, onTap: () => onOpen(s)),
          ),
      ],
    );
  }
}

class _SurahRow extends StatelessWidget {
  const _SurahRow({required this.surah, required this.onTap});
  final Json surah;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final marked = jint(surah['marked']);
    final total = jint(surah['ayat']);
    final full = total > 0 && marked >= total;
    return AppCard(
      onTap: onTap,
      child: Row(children: [
        SizedBox(width: AppSpace.xl, child: Text('${surah['surah']}', style: AppType.meta(context))),
        Expanded(child: Text('${surah['name_ar'] ?? ''}', style: AppType.bodyStrong(context), maxLines: 2, overflow: TextOverflow.ellipsis)),
        AppSpace.gapXs,
        AppStatusBadge(
          label: '$marked / $total',
          tone: full ? AppTone.success : (marked > 0 ? AppTone.warning : AppTone.neutral),
          dense: true,
          icon: full ? Icons.check_circle_rounded : null,
        ),
      ]),
    );
  }
}

// ── one surah ────────────────────────────────────────────────────────────────

class TimingSurahPage extends StatefulWidget {
  const TimingSurahPage({super.key, required this.reciterKey, required this.surah, required this.surahName, this.api, this.playerFactory});
  final String reciterKey;
  final int surah;
  final String surahName;
  final ItemsV4Api? api;
  final TimingPlayer Function()? playerFactory;

  @override
  State<TimingSurahPage> createState() => _TimingSurahPageState();
}

class _TimingSurahPageState extends State<TimingSurahPage> {
  late final ItemsV4Api _api = widget.api ?? ItemsV4Api();
  late final TimingPlayer _player = (widget.playerFactory ?? AudioplayersTimingPlayer.new)();
  final List<StreamSubscription<int>> _subs = [];
  List<Json> _ayat = [];
  TimingDraft? _draft;
  String? _error;
  bool _dirty = false;
  bool _saving = false;
  bool _playing = false;
  int _pos = 0;
  int _dur = 0;
  int? _stopAt; // a replay stops here

  @override
  void initState() {
    super.initState();
    _subs.add(_player.positionMs.listen(_onPos));
    _subs.add(_player.durationMs.listen((d) { if (mounted) setState(() => _dur = d); }));
    _load();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _onPos(int p) {
    if (!mounted) return;
    final stop = _stopAt;
    if (stop != null && p >= stop) {
      _stopAt = null;
      _player.pause();
      setState(() { _pos = stop; _playing = false; });
      return;
    }
    setState(() => _pos = p);
  }

  Future<void> _load() async {
    try {
      final r = await _api.timingSurah(widget.reciterKey, widget.surah);
      final ayat = jlist(r['ayat']);
      await _player.load('${r['url']}');
      if (!mounted) return;
      setState(() { _ayat = ayat; _draft = TimingDraft.fromServer(ayat); _error = null; _dirty = false; });
    } catch (e) {
      if (mounted) setState(() => _error = itemErrorText(e));
    }
  }

  Future<void> _toggle() async {
    _stopAt = null;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  void _change(bool Function(TimingDraft d) f) {
    final d = _draft;
    if (d == null) return;
    if (f(d)) setState(() => _dirty = true);
  }

  Future<void> _replay(int i) async {
    final d = _draft!;
    final s = d.startOf(i);
    final e = d.endOf(i);
    if (s == null || e == null) return;
    await _player.seek(s);
    _stopAt = e;
    await _player.play();
    if (mounted) setState(() { _playing = true; _pos = s; });
  }

  Future<void> _seek(int ms) async {
    _stopAt = null;
    await _player.seek(ms.clamp(0, _dur > 0 ? _dur : ms));
  }

  Future<void> _save() async {
    final d = _draft!;
    setState(() => _saving = true);
    try {
      final r = await _api.putTimingSurah(widget.reciterKey, widget.surah, d.toBody());
      final ayat = jlist(r['ayat']);
      if (!mounted) return;
      setState(() { _ayat = ayat; _draft = TimingDraft.fromServer(ayat); _dirty = false; });
      showAppNotice(t('تم حفظ الأزمنة', 'Timings saved'));
    } catch (e) {
      showAppNotice(itemErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (await appConfirmDiscard(context)) nav.pop();
        },
        child: AdminPage(
          width: AppWidth.reading,
          title: widget.surahName,
          subtitle: t('سجّل نهاية كل آية أثناء التلاوة', 'Mark the end of each ayah while it plays'),
          icon: Icons.timer_outlined,
          body: _error != null && _draft == null
              ? AppErrorState(message: _error!, onRetry: _load)
              : _draft == null
                  ? const AppListSkeleton(items: 4)
                  : TimingEditorBody(
                      ayat: _ayat,
                      draft: _draft!,
                      positionMs: _pos,
                      durationMs: _dur,
                      playing: _playing,
                      dirty: _dirty,
                      saving: _saving,
                      onToggle: _toggle,
                      onSeek: _seek,
                      onMark: () => _change((d) => d.mark(_pos)),
                      onSetStart: () => _change((d) => d.setStart0(_pos)),
                      onNudgeEnd: (i, ms) => _change((d) => d.nudgeEnd(i, ms)),
                      onNudgeStart: (ms) => _change((d) => d.nudgeStart0(ms)),
                      onClearFrom: (i) => _change((d) { d.clearFrom(i); return true; }),
                      onReplay: _replay,
                      onSave: _save,
                    ),
        ),
      );
}

/// The editor over plain values.
class TimingEditorBody extends StatelessWidget {
  const TimingEditorBody({
    super.key,
    required this.ayat,
    required this.draft,
    required this.positionMs,
    required this.durationMs,
    required this.playing,
    this.dirty = false,
    this.saving = false,
    this.onToggle,
    this.onSeek,
    this.onMark,
    this.onSetStart,
    this.onNudgeEnd,
    this.onNudgeStart,
    this.onClearFrom,
    this.onReplay,
    this.onSave,
  });

  final List<Json> ayat;
  final TimingDraft draft;
  final int positionMs;
  final int durationMs;
  final bool playing;
  final bool dirty;
  final bool saving;
  final VoidCallback? onToggle;
  final ValueChanged<int>? onSeek;
  final VoidCallback? onMark;
  final VoidCallback? onSetStart;
  final void Function(int index, int deltaMs)? onNudgeEnd;
  final ValueChanged<int>? onNudgeStart;
  final ValueChanged<int>? onClearFrom;
  final ValueChanged<int>? onReplay;
  final VoidCallback? onSave;

  static const int step = 100;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final next = draft.nextToMark;
    final maxMs = durationMs > 0 ? durationMs : (positionMs > 0 ? positionMs : 1);
    return ListView(
      padding: AdminPage.bodyPadding(context),
      children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              AppIconButton(
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: playing ? t('إيقاف مؤقت', 'Pause') : t('تشغيل', 'Play'),
                onPressed: onToggle,
              ),
              AppSpace.gapXs,
              Expanded(
                child: Text('${timingClock(positionMs)} / ${durationMs > 0 ? timingClock(durationMs) : '--'}',
                    textDirection: TextDirection.ltr, style: AppType.bodyStrong(context)),
              ),
              AppStatusBadge(label: '${draft.marked} / ${draft.count}', tone: draft.complete ? AppTone.success : AppTone.neutral, dense: true),
            ]),
            Slider(
              value: positionMs.clamp(0, maxMs).toDouble(),
              max: maxMs.toDouble(),
              onChanged: onSeek == null ? null : (v) => onSeek!(v.round()),
            ),
            AppButton.primary(
              label: next == null ? t('كل الآيات مسجّلة', 'Every ayah is marked') : t('نهاية الآية ${next + 1} هنا', 'End of ayah ${next + 1} here'),
              icon: Icons.flag_rounded,
              expand: true,
              onPressed: next == null ? null : onMark,
            ),
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              if (next == 0 || draft.start0 > 0 || draft.marked == 0)
                AppButton.secondary(label: t('بداية الآية 1 هنا', 'Start of ayah 1 here'), size: AppButtonSize.sm, onPressed: onSetStart),
              AppButton.tonal(
                label: dirty ? t('حفظ السورة', 'Save surah') : t('محفوظ', 'Saved'),
                icon: Icons.save_outlined,
                size: AppButtonSize.sm,
                onPressed: dirty && !saving ? onSave : null,
              ),
            ]),
          ]),
        ),
        AppSpace.gapSm,
        for (var i = 0; i < ayat.length && i < draft.count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: _AyahRow(
              number: i + 1,
              text: '${ayat[i]['text'] ?? ''}',
              start: draft.startOf(i),
              end: draft.endOf(i),
              current: i == next,
              accent: c.primary,
              onNudgeEnd: onNudgeEnd == null ? null : (d) => onNudgeEnd!(i, d),
              onNudgeStart: i == 0 ? onNudgeStart : null,
              onClear: onClearFrom == null ? null : () => onClearFrom!(i),
              onReplay: onReplay == null ? null : () => onReplay!(i),
            ),
          ),
      ],
    );
  }
}

class _AyahRow extends StatelessWidget {
  const _AyahRow({
    required this.number,
    required this.text,
    required this.start,
    required this.end,
    required this.current,
    required this.accent,
    this.onNudgeEnd,
    this.onNudgeStart,
    this.onClear,
    this.onReplay,
  });
  final int number;
  final String text;
  final int? start;
  final int? end;
  final bool current;
  final Color accent;
  final ValueChanged<int>? onNudgeEnd;
  final ValueChanged<int>? onNudgeStart;
  final VoidCallback? onClear;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    final marked = end != null;
    final step = TimingEditorBody.step;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$number', style: AppType.bodyStrong(context).copyWith(color: current ? accent : null)),
          AppSpace.gapSm,
          Expanded(child: Text(text, style: AppType.body(context), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
        AppSpace.gapXs,
        Row(children: [
          Expanded(
            child: Text(
              marked ? '${timingClock(start ?? 0)}  →  ${timingClock(end!)}' : t('غير مسجّلة', 'Not marked'),
              textDirection: TextDirection.ltr,
              style: AppType.meta(context),
            ),
          ),
          if (current) AppStatusBadge(label: t('التالية', 'Next'), tone: AppTone.brand, dense: true),
        ]),
        if (marked)
          Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
            AppIconButton(icon: Icons.replay_rounded, tooltip: t('إعادة سماع الآية', 'Replay this ayah'), onPressed: onReplay),
            if (onNudgeStart != null) ...[
              AppButton.ghost(label: t('البداية −100', 'Start −100'), size: AppButtonSize.sm, onPressed: () => onNudgeStart!(-step)),
              AppButton.ghost(label: t('البداية +100', 'Start +100'), size: AppButtonSize.sm, onPressed: () => onNudgeStart!(step)),
            ],
            AppButton.ghost(label: t('النهاية −100', 'End −100'), size: AppButtonSize.sm, onPressed: onNudgeEnd == null ? null : () => onNudgeEnd!(-step)),
            AppButton.ghost(label: t('النهاية +100', 'End +100'), size: AppButtonSize.sm, onPressed: onNudgeEnd == null ? null : () => onNudgeEnd!(step)),
            AppButton.ghost(label: t('امسح من هنا', 'Clear from here'), size: AppButtonSize.sm, onPressed: onClear),
          ]),
      ]),
    );
  }
}
