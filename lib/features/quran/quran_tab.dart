// lib/features/quran/quran_tab.dart — the student's Quran tab (Learning Hub Phase 6, D-1347; kill switch
// `student_tab_quran`): find a memorization teacher, open their card, book one of their programs.
//
//   QuranTab           the tab: GET /api/v1/quran/teachers with the gender / goal / session-type filters, the
//                      "My progress" button (students; a guest is asked to sign in)
//   QuranBrowseView    the tab's body with plain values (test/ui/quran_layout_test.dart)
//   QuranFilterBar     THE course filter bar's pattern (CourseFilterBar): a "Filters" button + the active chips and a
//                      sheet on a phone, one row of fields on a desktop, the result count and "Clear"
//   QuranTeacherCard   one teacher in the list
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/quran/quran_api.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:flutter_education_app/features/quran/quran_progress.dart';
import 'package:flutter_education_app/features/quran/quran_teacher_page.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// [gender] `f` = the list is filtered to women teachers: the Arabic counts them in the feminine.
String quranTeacherCountText(int n, {String? gender}) => gender == 'f'
    ? countText(n,
        ar1: 'معلمة واحدة',
        ar2: 'معلمتان',
        arFew: '$n معلمات',
        arMany: '$n معلمة',
        en1: '1 teacher',
        en: '$n teachers',
        ar0: 'لا توجد معلمات',
        en0: 'No teachers')
    : countText(n,
    ar1: 'معلم واحد',
    ar2: 'معلمان',
    arFew: '$n معلمين',
    arMany: '$n معلماً',
    en1: '1 teacher',
    en: '$n teachers',
    ar0: 'لا يوجد معلمون',
    en0: 'No teachers');

class QuranTab extends StatefulWidget {
  const QuranTab({super.key, this.api});

  final QuranApi? api;

  @override
  State<QuranTab> createState() => _QuranTabState();
}

class _QuranTabState extends State<QuranTab> {
  late final QuranApi _api = widget.api ?? QuranApi();

  QuranFilters _filters = QuranFilters.empty;
  List<QuranTeacher> _items = const [];
  int _total = 0;
  String _matching = 'off';
  bool _loading = true;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.teachers(_filters);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = r.items;
        _total = r.total;
        _matching = r.genderMatching;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = quranErrorText(e);
      });
    }
  }

  void _onFilters(QuranFilters f) {
    if (f == _filters) return;
    setState(() => _filters = f);
    _load();
  }

  void _open(QuranTeacher it) => Navigator.of(context).push(MaterialPageRoute<void>(
        settings: RouteSettings(name: '/quran/teachers/${it.userId}'),
        builder: (_) => QuranTeacherPage(teacherId: it.userId, initial: it, api: _api),
      ));

  void _openProgress() => GuestGuard.run(
      context,
      () => Navigator.of(context).push(MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/quran/progress'),
            builder: (_) => QuranProgressPage.mine(api: _api),
          )));

  @override
  Widget build(BuildContext context) {
    return BasePage(
      width: AppWidth.wide,
      appBar: ScreenAppBar(
        title: t('القرآن الكريم', 'Quran'),
        showBack: false,
        actions: [
          IconButton(
            key: const ValueKey('quran.progress'),
            tooltip: t('تقدّمي في الحفظ', 'My memorization'),
            icon: const Icon(Icons.auto_graph_rounded),
            onPressed: _openProgress,
          ),
        ],
      ),
      child: SafeArea(
        child: QuranBrowseView(
          filters: _filters,
          onFilters: _onFilters,
          items: _items,
          total: _loading ? null : _total,
          genderMatching: _matching,
          loading: _loading,
          error: _error,
          onOpen: _open,
          onRetry: _load,
          onRefresh: _load,
          onProgress: _openProgress,
        ),
      ),
    );
  }
}

/// The browse body with plain values.
class QuranBrowseView extends StatelessWidget {
  const QuranBrowseView({
    super.key,
    required this.filters,
    required this.onFilters,
    required this.items,
    this.total,
    this.genderMatching = 'off',
    this.loading = false,
    this.error,
    this.onOpen,
    this.onRetry,
    this.onRefresh,
    this.onProgress,
  });

  final QuranFilters filters;
  final ValueChanged<QuranFilters> onFilters;
  final List<QuranTeacher> items;
  final int? total;
  final String genderMatching;
  final bool loading;
  final String? error;
  final ValueChanged<QuranTeacher>? onOpen;
  final VoidCallback? onRetry, onProgress;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final head = <Widget>[
      AppBlock(
        tone: AppBlockTone.emerald,
        onTap: onProgress,
        semanticLabel: t('تقدّمي في الحفظ', 'My memorization'),
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Row(children: [
            Icon(Icons.menu_book_rounded, color: b.ink, size: AppIconSize.xl),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t('رحلتك مع الحفظ', 'Your memorization journey'),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: b.ink)),
                const SizedBox(height: AppSpace.xxs),
                Text(t('اختر معلماً أو معلمة، واحجز برنامجاً، وتابع حفظك سورةً سورة وجزءاً جزءاً.',
                        'Choose a teacher, book a program, and follow your memorization surah by surah, juz by juz.'),
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
              ]),
            ),
            if (onProgress != null) Icon(Icons.chevron_right_rounded, color: b.muted),
          ]);
        }),
      ),
      const SizedBox(height: AppSpace.md),
      QuranFilterBar(value: filters, resultCount: total, onChanged: onFilters),
      if (genderMatching == 'same') ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          icon: Icons.info_outline_rounded,
          text: t('الحجز متاح مع معلم من نفس جنس الطالب فقط.', 'Booking is open only with a teacher of the student\'s gender.'),
        ),
      ],
      const SizedBox(height: AppSpace.md),
    ];
    final Widget body;
    if (loading && items.isEmpty) {
      body = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (error != null) {
      body = AppErrorState(message: error, onRetry: onRetry);
    } else if (items.isEmpty) {
      body = AppEmpty(
        key: const ValueKey('quran.empty'),
        icon: Icons.menu_book_rounded,
        title: filters.isEmpty
            ? t('لا يوجد معلمو قرآن بعد', 'No Quran teachers yet')
            : t('لا يوجد معلمون لهذه الاختيارات', 'No teachers for these choices'),
        message: filters.isEmpty ? null : t('غيّر الاختيارات أو امسح التصفية.', 'Change the choices or clear the filters.'),
        actionLabel: filters.isEmpty ? null : t('امسح التصفية', 'Clear the filters'),
        onAction: filters.isEmpty ? null : () => onFilters(QuranFilters.empty),
      );
    } else {
      body = AppGrid(
        minTile: 320,
        padding: EdgeInsets.zero,
        children: [for (final it in items) QuranTeacherCard(teacher: it, onTap: () => onOpen?.call(it))],
      );
    }
    final list = ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [...head, body, const SizedBox(height: AppSpace.lg)],
    );
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The filter bar (CourseFilterBar's pattern)
// ═════════════════════════════════════════════════════════════════════════════

class QuranFilterBar extends StatelessWidget {
  const QuranFilterBar({super.key, required this.value, required this.onChanged, this.resultCount});

  final QuranFilters value;
  final ValueChanged<QuranFilters> onChanged;
  final int? resultCount;

  /// From this width the bar is one row of fields (CourseFilterBar.rowFrom).
  static const double rowFrom = 900;

  Future<void> _openSheet(BuildContext context) async {
    final r = await showAppSheet<QuranFilters>(context, (_) => _QuranFilterSheet(initial: value));
    if (r != null && r != value) onChanged(r);
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) => box.maxWidth >= rowFrom ? _row(context) : _compact(context));

  Widget _summary(BuildContext context) {
    final c = context.colors;
    final n = resultCount;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (n != null)
        Flexible(
          child: Semantics(
            liveRegion: true,
            child: Text(quranTeacherCountText(n, gender: value.gender),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textDark)),
          ),
        ),
      if (!value.isEmpty) ...[
        const SizedBox(width: AppSpace.xs),
        TextButton.icon(
          key: const ValueKey('quran_filters.clear'),
          onPressed: () => onChanged(QuranFilters.empty),
          style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
          icon: const Icon(Icons.close_rounded, size: AppIconSize.sm),
          label: Text(t('مسح', 'Clear')),
        ),
      ],
    ]);
  }

  Widget _compact(BuildContext context) {
    final v = value;
    final chips = <Widget>[
      if (v.gender != null)
        AppChoiceChip(label: quranGenderLabel(v.gender), selected: true, icon: Icons.close_rounded, onTap: () => onChanged(v.withGender(null))),
      if (v.goal != null)
        AppChoiceChip(label: quranGoalLabel(v.goal!), selected: true, icon: Icons.close_rounded, onTap: () => onChanged(v.withGoal(null))),
      if (v.sessionType != null)
        AppChoiceChip(
            label: quranSessionLabel(v.sessionType!), selected: true, icon: Icons.close_rounded, onTap: () => onChanged(v.withSession(null))),
    ];
    final n = v.activeCount;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        AppButton(
          key: const ValueKey('quran_filters.open'),
          label: n == 0 ? t('تصفية', 'Filters') : '${t('تصفية', 'Filters')} · $n',
          icon: Icons.tune_rounded,
          variant: n == 0 ? AppButtonVariant.secondary : AppButtonVariant.tonal,
          size: AppButtonSize.sm,
          onPressed: () => _openSheet(context),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.xs),
                  chips[i],
                ],
              ]),
            ),
          ),
        ] else
          const Spacer(),
      ]),
      if (resultCount != null || !v.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Align(alignment: AlignmentDirectional.centerStart, child: _summary(context)),
        ),
    ]);
  }

  Widget _row(BuildContext context) {
    final v = value;
    Widget field(String label, Widget child) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            AppFieldLabel(label),
            child,
          ]),
        );
    DropdownMenuItem<String> item(String v, String label) =>
        DropdownMenuItem(value: v, child: Text(label, overflow: TextOverflow.ellipsis));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        field(
          t('المعلم', 'Teacher'),
          AppDropdown<String>(
            key: const ValueKey('quran_filters.gender'),
            value: v.gender ?? '',
            items: [item('', t('الكل', 'Any')), for (final g in quranGenders) item(g, quranGenderLabel(g))],
            onChanged: (g) => onChanged(v.withGender(g == null || g.isEmpty ? null : g)),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        field(
          t('الهدف', 'Goal'),
          AppDropdown<String>(
            key: const ValueKey('quran_filters.goal'),
            value: v.goal ?? '',
            items: [item('', t('الكل', 'Any')), for (final g in quranGoals) item(g, quranGoalLabel(g))],
            onChanged: (g) => onChanged(v.withGoal(g == null || g.isEmpty ? null : g)),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        field(
          t('نوع الجلسة', 'Session'),
          AppDropdown<String>(
            key: const ValueKey('quran_filters.session'),
            value: v.sessionType ?? '',
            items: [item('', t('الكل', 'Any')), for (final s in quranSessionTypes) item(s, quranSessionLabel(s))],
            onChanged: (s) => onChanged(v.withSession(s == null || s.isEmpty ? null : s)),
          ),
        ),
      ]),
      if (resultCount != null || !v.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Align(alignment: AlignmentDirectional.centerStart, child: _summary(context)),
        ),
    ]);
  }
}

class _QuranFilterSheet extends StatefulWidget {
  const _QuranFilterSheet({required this.initial});

  final QuranFilters initial;

  @override
  State<_QuranFilterSheet> createState() => _QuranFilterSheetState();
}

class _QuranFilterSheetState extends State<_QuranFilterSheet> {
  late QuranFilters _f = widget.initial;

  Widget _group(String title, List<String> values, String? current, String Function(String) label, ValueChanged<String?> pick) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppFieldLabel(title),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppChoiceChip(label: t('الكل', 'Any'), selected: current == null, onTap: () => pick(null)),
          for (final v in values)
            AppChoiceChip(
              key: ValueKey('quran_filters.$v'),
              label: label(v),
              selected: current == v,
              onTap: () => pick(current == v ? null : v),
            ),
        ]),
        const SizedBox(height: AppSpace.md),
      ]);

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: t('تصفية المعلمين', 'Filter teachers'),
        icon: Icons.tune_rounded,
        children: [
          _group(t('المعلم', 'Teacher'), quranGenders, _f.gender, quranGenderLabel, (v) => setState(() => _f = _f.withGender(v))),
          _group(t('الهدف', 'Goal'), quranGoals, _f.goal, quranGoalLabel, (v) => setState(() => _f = _f.withGoal(v))),
          _group(t('نوع الجلسة', 'Session'), quranSessionTypes, _f.sessionType, quranSessionLabel,
              (v) => setState(() => _f = _f.withSession(v))),
          AppButtonRow(
            primary: AppButton.primary(
              key: const ValueKey('quran_filters.apply'),
              label: t('عرض المعلمين', 'Show teachers'),
              onPressed: () => Navigator.of(context).pop(_f),
            ),
            secondary: [
              AppButton.secondary(
                label: t('مسح', 'Clear'),
                onPressed: _f.isEmpty ? null : () => setState(() => _f = QuranFilters.empty),
              ),
            ],
          ),
        ],
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The card
// ═════════════════════════════════════════════════════════════════════════════

class QuranTeacherCard extends StatelessWidget {
  const QuranTeacherCard({super.key, required this.teacher, this.onTap});

  final QuranTeacher teacher;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tr = teacher;
    final meta = [quranGenderLabel(tr.gender), ...tr.sessionTypes.map(quranSessionLabel)].join(' · ');
    return AppCard(
      key: ValueKey('quran.teacher.${tr.userId}'),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          AppAvatar(name: tr.name, url: tr.avatarUrl, size: AppTouch.min),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Flexible(
                  child: Text(tr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark)),
                ),
                if (tr.verified) ...[
                  const SizedBox(width: AppSpace.xxs),
                  Tooltip(
                    message: t('موثّق من المنصة', 'Verified by the platform'),
                    child: Icon(Icons.verified_rounded, size: AppIconSize.sm, color: c.primary),
                  ),
                ],
              ]),
              const SizedBox(height: AppSpace.xxs),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textLight),
        ]),
        if ((tr.ijazah ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Row(children: [
            Icon(Icons.workspace_premium_rounded, size: AppIconSize.sm, color: c.accent2),
            const SizedBox(width: AppSpace.xxs),
            Expanded(
              child: Text(tr.ijazah!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ),
          ]),
        ],
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final g in tr.goals) AppStatusBadge(label: quranGoalLabel(g), tone: AppTone.brand, dense: true),
          AppStatusBadge(
            label: tr.courses.isEmpty
                ? t('لا برامج متاحة الآن', 'No programs open now')
                : countText(tr.courses.length,
                    ar1: 'برنامج واحد', ar2: 'برنامجان', arFew: '${tr.courses.length} برامج', arMany: '${tr.courses.length} برنامجاً',
                    en1: '1 program', en: '${tr.courses.length} programs'),
            icon: Icons.event_available_rounded,
            dense: true,
          ),
          if (tr.genderOk == false)
            AppStatusBadge(label: t('غير متاح لك', 'Not open to you'), tone: AppTone.warning, icon: Icons.block_rounded, dense: true),
        ]),
      ]),
    );
  }
}
