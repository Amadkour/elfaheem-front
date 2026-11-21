// lib/features/nahw/nahw_tab.dart — the student's Arabic grammar (nahw) tab (Learning Hub Phase 6, D-1349; kill
// switch `student_tab_nahw`): levels beginner → advanced, each with its lessons and the student's progress.
//
//   NahwTab               GET /api/v1/nahw/levels, for the student's remembered stage / grade ("My grade") or every
//                         level; loads nothing until the tab opens (LazyTabStack). A guest is asked to sign in.
//   NahwLevelsView        the levels with progress per level and per lesson, plain values (read-only for a parent)
//   ParentChildNahwPage   GET /api/v1/parent/children/{id}/nahw: the same view of a linked child
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/course_filters.dart' show CourseFilterStore;
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'nahw_api.dart';
import 'nahw_lesson_page.dart';
import 'nahw_models.dart';

class NahwTab extends StatefulWidget {
  const NahwTab({super.key, this.api});

  final NahwApi? api;

  @override
  State<NahwTab> createState() => _NahwTabState();
}

class _NahwTabState extends State<NahwTab> {
  late final NahwApi _api = widget.api ?? NahwApi();
  List<NahwLevel>? _levels;
  String? _error;
  int? _stageId;
  int? _gradeId;
  bool _mine = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    NahwBus.revision.addListener(_load);
    if (!GuestState.active) _start();
  }

  @override
  void dispose() {
    NahwBus.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final u = await CourseFilterStore.user();
      final f = await CourseFilterStore.initial(u.id);
      _stageId = f.stageId;
      _gradeId = f.gradeId;
    } catch (_) {}
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final seq = ++_seq;
    setState(() => _error = null);
    final mine = _mine && _stageId != null;
    try {
      final l = await _api.levels(stageId: mine ? _stageId : null, gradeId: mine ? _gradeId : null);
      if (mounted && seq == _seq) setState(() => _levels = l);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = nahwErrorText(e));
    }
  }

  void _open(NahwLessonRef l) => Navigator.of(context).push(MaterialPageRoute<void>(
        settings: RouteSettings(name: '/nahw/lessons/${l.id}'),
        builder: (_) => NahwLessonPage(lessonId: l.id, title: l.title, api: _api),
      ));

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (GuestState.active) {
      body = Padding(
        padding: AppSpace.card,
        child: AppEmpty(
          icon: Icons.translate_rounded,
          title: t('تعلّم النحو خطوة بخطوة', 'Learn Arabic grammar step by step'),
          message: t('سجّل الدخول لتحفظ تقدّمك في الدروس والتمارين', 'Sign in to keep your progress in the lessons and exercises'),
          actionLabel: t('تسجيل الدخول', 'Sign in'),
          onAction: () => GuestGuard.ensure(context),
        ),
      );
    } else {
      body = NahwLevelsView(
        levels: _levels,
        error: _error,
        onRetry: _load,
        onOpen: _open,
        mine: _stageId == null ? null : _mine,
        onMine: (v) {
          setState(() => _mine = v);
          _load();
        },
      );
    }
    return BasePage(
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: t('النحو', 'Arabic grammar'), showBack: false),
      child: SafeArea(child: body),
    );
  }
}

class NahwLevelsView extends StatelessWidget {
  const NahwLevelsView({
    super.key,
    required this.levels,
    this.error,
    this.onRetry,
    this.onOpen,
    this.mine,
    this.onMine,
  });

  /// null = loading.
  final List<NahwLevel>? levels;
  final String? error;
  final VoidCallback? onRetry;

  /// null = read-only (a parent's view).
  final ValueChanged<NahwLessonRef>? onOpen;

  /// "My grade only": null hides the choice (no stage known).
  final bool? mine;
  final ValueChanged<bool>? onMine;

  @override
  Widget build(BuildContext context) {
    final list = levels;
    final head = <Widget>[
      if (mine != null) ...[
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppChoiceChip(
            key: const ValueKey('nahw.mine'),
            label: t('لصفّي', 'For my grade'),
            icon: Icons.school_rounded,
            selected: mine!,
            onTap: () => onMine?.call(true),
          ),
          AppChoiceChip(
            key: const ValueKey('nahw.all'),
            label: t('كل المستويات', 'Every level'),
            selected: !mine!,
            onTap: () => onMine?.call(false),
          ),
        ]),
        AppSpace.gapMd,
      ],
    ];
    if (list == null) {
      return ListView(padding: AppSpace.card, children: [
        ...head,
        if (error != null) AppErrorState(message: error, onRetry: onRetry) else const AppListSkeleton(items: 4),
      ]);
    }
    if (list.isEmpty) {
      return ListView(padding: AppSpace.card, children: [
        ...head,
        AppEmpty(
          icon: Icons.translate_rounded,
          title: t('لا توجد دروس بعد', 'No lessons yet'),
          message: t('ستظهر دروس النحو هنا عند إضافتها', 'Grammar lessons show here once they are added'),
        ),
      ]);
    }
    return ListView(padding: AppSpace.card, children: [
      ...head,
      for (var i = 0; i < list.length; i++) ...[
        if (i > 0) AppSpace.gapMd,
        _LevelCard(level: list[i], step: i + 1, onOpen: onOpen),
      ],
    ]);
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level, required this.step, this.onOpen});

  final NahwLevel level;
  final int step;
  final ValueChanged<NahwLessonRef>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      key: ValueKey('nahw.level.${level.id}'),
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(level.title, style: AppType.section(context))),
          const SizedBox(width: AppSpace.xs),
          AppStatusBadge(
            label: '${level.completed} / ${level.total}',
            tone: level.total > 0 && level.completed >= level.total ? AppTone.success : AppTone.neutral,
            dense: true,
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        Semantics(
          label: t('أتممت ${level.completed} من ${level.total}', '${level.completed} of ${level.total} done'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: level.fraction,
              minHeight: AppSpace.xs,
              color: c.primary,
              backgroundColor: c.divider,
            ),
          ),
        ),
        AppSpace.gapSm,
        for (final l in level.lessons) _LessonRow(lesson: l, onOpen: onOpen),
      ]),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson, this.onOpen});

  final NahwLessonRef lesson;
  final ValueChanged<NahwLessonRef>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = lesson.progress;
    final done = p?.completed == true;
    final status = p == null
        ? t('جديد', 'New')
        : done
            ? t('أتممته · ${p.percent}%', 'Done · ${p.percent}%')
            : t('أفضل نتيجة ${p.percent}%', 'Best ${p.percent}%');
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: Row(children: [
          Icon(
            done ? Icons.check_circle_rounded : (p == null ? Icons.circle_outlined : Icons.timelapse_rounded),
            size: AppIconSize.md,
            color: done ? c.success : c.textMedium,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lesson.title, style: AppType.row(context)),
              Text(status, style: AppType.meta(context)),
            ]),
          ),
          if (onOpen != null) Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
        ]),
      ),
    );
    if (onOpen == null) return row;
    return InkWell(
      key: ValueKey('nahw.lesson.${lesson.id}'),
      borderRadius: AppRadius.cardAll,
      onTap: () => onOpen!(lesson),
      child: row,
    );
  }
}

/// A parent's view of a linked child's grammar progress.
class ParentChildNahwPage extends StatefulWidget {
  const ParentChildNahwPage({super.key, required this.studentId, this.studentName = '', this.api});

  final int studentId;
  final String studentName;
  final NahwApi? api;

  @override
  State<ParentChildNahwPage> createState() => _ParentChildNahwPageState();
}

class _ParentChildNahwPageState extends State<ParentChildNahwPage> {
  late final NahwApi _api = widget.api ?? NahwApi();
  List<NahwLevel>? _levels;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await _api.child(widget.studentId);
      if (mounted) setState(() => _levels = l);
    } catch (e) {
      if (mounted) setState(() => _error = nahwErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.studentName.trim();
    return BasePage(
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: t('النحو', 'Arabic grammar'), subtitle: name.isEmpty ? null : name),
      child: SafeArea(child: NahwLevelsView(levels: _levels, error: _error, onRetry: _load)),
    );
  }
}
