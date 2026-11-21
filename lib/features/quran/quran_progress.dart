// lib/features/quran/quran_progress.dart — memorization progress by surah and juz (Learning Hub Phase 6, D-1347).
// GET /api/v1/quran/meta names the surahs and draws the juz map; the summary comes from one of three readers:
//
//   QuranProgressPage.mine      GET /api/v1/me/quran/progress (student; "Log my progress" while `self_log` is on)
//   QuranProgressPage.student   GET /api/v1/quran/students/{id}/progress (that student's teacher; "Record")
//   QuranProgressPage.child     GET /api/v1/parent/children/{id}/quran/progress (a linked child; read only)
//
//   QuranProgressView  plain values (test/ui/quran_layout_test.dart): the hero (one ring + three figures), the 30-juz
//                      map (tap a juz → its surahs), the surah list (in progress / all) and the recent entries.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/quran/quran_api.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:flutter_education_app/features/quran/quran_record_sheet.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

enum _Source { mine, student, child }

class QuranProgressPage extends StatefulWidget {
  const QuranProgressPage.mine({super.key, this.api})
      : _source = _Source.mine,
        personId = null,
        personName = null;

  const QuranProgressPage.student({super.key, required int studentId, required String name, this.api})
      : _source = _Source.student,
        personId = studentId,
        personName = name;

  const QuranProgressPage.child({super.key, required int childId, required String name, this.api})
      : _source = _Source.child,
        personId = childId,
        personName = name;

  final _Source _source;
  final int? personId;
  final String? personName;
  final QuranApi? api;

  @override
  State<QuranProgressPage> createState() => _QuranProgressPageState();
}

class _QuranProgressPageState extends State<QuranProgressPage> {
  late final QuranApi _api = widget.api ?? QuranApi();
  QuranMeta? _meta;
  QuranProgress? _progress;
  bool _selfLog = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<QuranProgress> _read() => switch (widget._source) {
        _Source.mine => _api.myProgress(),
        _Source.student => _api.studentProgress(widget.personId!),
        _Source.child => _api.childProgress(widget.personId!),
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget._source == _Source.mine) {
        // a log that waited for the network goes first, so the summary counts it
        await QuranOutbox.flush(_api);
      }
      final meta = _api.meta();
      final progress = _read();
      final settings = widget._source == _Source.mine ? _api.settings().then<bool>((s) => s.selfLog).catchError((_) => false) : Future.value(false);
      final m = await meta, p = await progress, self = await settings;
      if (!mounted) return;
      setState(() {
        _meta = m;
        _progress = p;
        _selfLog = self;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = quranErrorText(e);
      });
    }
  }

  Future<void> _record() async {
    final m = _meta;
    if (m == null) return;
    final saved = await showQuranRecordSheet(
      context,
      meta: m,
      api: _api,
      student: widget._source == _Source.student ? (id: widget.personId!, name: widget.personName ?? '', imageUrl: null) : null,
      selfLog: widget._source == _Source.mine,
    );
    if (saved && mounted) _load();
  }

  String get _title => switch (widget._source) {
        _Source.mine => t('تقدّمي في الحفظ', 'My memorization'),
        _ => widget.personName?.isNotEmpty == true ? widget.personName! : t('تقدّم الحفظ', 'Memorization'),
      };

  @override
  Widget build(BuildContext context) {
    final canRecord = !GuestState.active &&
        ((widget._source == _Source.mine && _selfLog) || widget._source == _Source.student);
    final m = _meta, p = _progress;
    return BasePage(
      width: AppWidth.content,
      appBar: ScreenAppBar(title: _title),
      child: SafeArea(
        child: m == null || p == null
            ? (_loading ? const AppListSkeleton(items: 5) : AppErrorState(message: _error, onRetry: _load))
            : QuranProgressView(
                meta: m,
                progress: p,
                mine: widget._source == _Source.mine,
                onRecord: canRecord ? _record : null,
                onRefresh: _load,
              ),
      ),
    );
  }
}

/// An ISO instant (no offset = UTC) as the platform's date.
String quranDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(iso);
  final d = DateTime.tryParse(zoned ? iso : '${iso}Z');
  return d == null ? '' : AppTime.date(d.toUtc());
}

class QuranProgressView extends StatefulWidget {
  const QuranProgressView({super.key, required this.meta, required this.progress, this.mine = true, this.onRecord, this.onRefresh});

  final QuranMeta meta;
  final QuranProgress progress;

  /// The student's own page (the texts say "you").
  final bool mine;
  final VoidCallback? onRecord;
  final Future<void> Function()? onRefresh;

  @override
  State<QuranProgressView> createState() => _QuranProgressViewState();
}

class _QuranProgressViewState extends State<QuranProgressView> {
  int? _juz;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = widget.meta, p = widget.progress;
    final surahs = _juz != null
        ? m.surahsInJuz(_juz!)
        : _all
            ? m.surahs
            : [for (final s in m.surahs) if ((p.surahs[s.number]?.memorized ?? 0) > 0) s];
    final children = <Widget>[
      _Hero(progress: p, mine: widget.mine, onRecord: widget.onRecord),
      AppSection(
        title: t('الأجزاء', 'Juz'),
        subtitle: t('اضغط جزءاً لترى سوره.', 'Tap a juz to see its surahs.'),
        child: AppGrid(
          minTile: 96,
          spacing: AppSpace.xs,
          padding: EdgeInsets.zero,
          children: [
            for (var j = 1; j <= 30; j++)
              _JuzTile(
                juz: j,
                percent: p.juz[j] ?? 0,
                selected: _juz == j,
                onTap: () => setState(() => _juz = _juz == j ? null : j),
              ),
          ],
        ),
      ),
      AppSection(
        title: _juz != null ? '${t('سور الجزء', 'Surahs of juz')} $_juz' : t('السور', 'Surahs'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppChoiceChip(
              key: const ValueKey('quran.surahs.progress'),
              label: t('قيد الحفظ', 'In progress'),
              selected: _juz == null && !_all,
              onTap: () => setState(() {
                _juz = null;
                _all = false;
              }),
            ),
            AppChoiceChip(
              key: const ValueKey('quran.surahs.all'),
              label: t('كل السور', 'All surahs'),
              selected: _juz == null && _all,
              onTap: () => setState(() {
                _juz = null;
                _all = true;
              }),
            ),
            if (_juz != null)
              AppChoiceChip(
                label: '${t('الجزء', 'Juz')} $_juz',
                selected: true,
                icon: Icons.close_rounded,
                onTap: () => setState(() => _juz = null),
              ),
          ]),
          const SizedBox(height: AppSpace.sm),
          if (surahs.isEmpty)
            AppEmpty(
              icon: Icons.menu_book_rounded,
              title: widget.mine ? t('لم تبدأ الحفظ بعد', 'You have not started yet') : t('لا حفظ مسجّل بعد', 'Nothing memorized yet'),
              message: t('ما يُسجَّل من حفظ يظهر هنا سورةً سورة.', 'Recorded memorization shows here, surah by surah.'),
              actionLabel: _all ? null : t('اعرض كل السور', 'Show every surah'),
              onAction: _all ? null : () => setState(() => _all = true),
            )
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Column(children: [
                for (var i = 0; i < surahs.length; i++) ...[
                  if (i > 0) Divider(height: AppBorder.hairline, color: c.divider),
                  _SurahRow(surah: surahs[i], progress: p.surahs[surahs[i].number]),
                ],
              ]),
            ),
        ]),
      ),
      AppSection(
        title: t('آخر ما سُجّل', 'Recent entries'),
        child: p.recent.isEmpty
            ? Text(t('لا تسجيلات بعد.', 'No entries yet.'), style: AppType.body(context).copyWith(color: c.textMedium))
            : AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Column(children: [
                  for (var i = 0; i < p.recent.length; i++) ...[
                    if (i > 0) Divider(height: AppBorder.hairline, color: c.divider),
                    QuranEntryRow(entry: p.recent[i], meta: m),
                  ],
                ]),
              ),
      ),
      const SizedBox(height: AppSpace.lg),
    ];
    final list = ListView(padding: const EdgeInsets.all(AppSpace.md), children: children);
    return widget.onRefresh == null ? list : AppRefresh(onRefresh: widget.onRefresh!, child: list);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.progress, required this.mine, this.onRecord});

  final QuranProgress progress;
  final bool mine;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return AppBlock(
      tone: AppBlockTone.emerald,
      hero: true,
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        Widget figure(String value, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.figure(context).copyWith(color: b.ink)),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
            ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Wrap(
            spacing: AppSpace.lg,
            runSpacing: AppSpace.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                label: '${p.percent.toStringAsFixed(1)}% ${t('من القرآن', 'of the Quran')}',
                child: ExcludeSemantics(
                  child: AppRing(value: p.percent, label: t('من القرآن', 'of the Quran'), color: b.accentInk(context.colors.primary)),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppTouch.min * 6),
                child: Wrap(spacing: AppSpace.lg, runSpacing: AppSpace.sm, children: [
                  figure('${p.memorizedTotal} / ${p.totalAyahs}', t('آية محفوظة', 'ayahs memorized')),
                  figure('${p.juzDone} / 30', t('جزءاً كاملاً', 'full juz')),
                  figure('${p.surahsDone} / 114', t('سورة كاملة', 'full surahs')),
                ]),
              ),
            ],
          ),
          if (onRecord != null) ...[
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.primary(
                key: const ValueKey('quran.record'),
                label: mine ? t('سجّل ما حفظت', 'Log what I memorized') : t('سجّل تسميعاً', 'Record a recitation'),
                icon: Icons.edit_note_rounded,
                onPressed: onRecord,
              ),
            ),
          ],
        ]);
      }),
    );
  }
}

class _JuzTile extends StatelessWidget {
  const _JuzTile({required this.juz, required this.percent, required this.selected, required this.onTap});

  final int juz;
  final double percent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = percent >= 100;
    final f = (percent / 100).clamp(0.0, 1.0);
    // the tile's wash deepens with the memorized share (the primary at most 30 % over the card: ink stays dark)
    final bg = Color.lerp(c.cardBg, c.primary, 0.04 + 0.26 * f)!;
    final r = BorderRadius.circular(AppRadius.card);
    return Semantics(
      button: true,
      selected: selected,
      label: '${t('الجزء', 'Juz')} $juz، ${percent.toStringAsFixed(0)}%',
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.focus : AppBorder.hairline),
        ),
        child: InkWell(
          key: ValueKey('quran.juz.$juz'),
          borderRadius: r,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xs),
              child: ExcludeSemantics(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Expanded(
                      child: Text('${t('الجزء', 'Juz')} $juz',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark)),
                    ),
                    if (done) Icon(Icons.check_circle_rounded, size: AppIconSize.sm, color: c.primary),
                  ]),
                  const SizedBox(height: AppSpace.xxs),
                  Text('${percent.toStringAsFixed(percent == percent.roundToDouble() ? 0 : 1)}%',
                      maxLines: 1, style: AppType.meta(context).copyWith(color: c.textMedium)),
                  const SizedBox(height: AppSpace.xxs),
                  AppProgressBar(value: percent, height: AppSpace.xxs, color: c.primary),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SurahRow extends StatelessWidget {
  const _SurahRow({required this.surah, this.progress});

  final QuranSurah surah;
  final QuranSurahProgress? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mem = progress?.memorized ?? 0;
    final total = progress?.total ?? surah.ayahs;
    final done = total > 0 && mem >= total;
    return Semantics(
      label: '${surah.name}: $mem / $total',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
          child: Row(children: [
            Container(
              width: AppTouch.min * 0.75,
              height: AppTouch.min * 0.75,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: done ? c.primary : c.inputBg, shape: BoxShape.circle),
              child: Text('${surah.number}', style: AppType.label(context).copyWith(color: done ? c.onHero : c.textDark)),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    child: Text(surah.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark)),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Text('$mem / $total', style: AppType.meta(context).copyWith(color: c.textMedium)),
                ]),
                const SizedBox(height: AppSpace.xxs),
                AppProgressBar(value: mem.toDouble(), max: total <= 0 ? 1 : total.toDouble(), height: AppSpace.xxs, color: c.primary),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One entry: the surah, the ayah range, the kind, the grade and the day.
class QuranEntryRow extends StatelessWidget {
  const QuranEntryRow({super.key, required this.entry, required this.meta, this.pending = false});

  final QuranEntry entry;
  final QuranMeta meta;

  /// Waiting for the network (the outbox).
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final range = '${t('الآيات', 'Ayahs')} ${e.fromAyah}–${e.toAyah}';
    final day = quranDate(e.recordedAt);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Text(meta.surahName(e.surah), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark)),
          ),
          if (day.isNotEmpty) Text(day, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(range, style: AppType.meta(context).copyWith(color: c.textMedium)),
          AppStatusBadge(label: quranGoalLabel(e.kind), tone: AppTone.brand, dense: true),
          if (e.grade != null) AppStatusBadge(label: quranGradeLabel(e.grade!), tone: e.grade! >= 4 ? AppTone.success : AppTone.neutral, dense: true),
          if (pending) AppStatusBadge(label: t('بانتظار الاتصال', 'Waiting to send'), tone: AppTone.warning, icon: Icons.cloud_upload_rounded, dense: true),
        ]),
        if ((e.note ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(e.note!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ],
      ]),
    );
  }
}
