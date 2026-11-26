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
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/features/parent/parent_consent.dart' show ParentConsentRequired, isConsentRequired;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/self_learning/self_learning_page.dart' show SelfLearningSection;

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
        // today's grammar lesson and reviews (Learning Hub v2 §5, D-1603)
        top: const SelfLearningSection(subjects: {'nahw'}),
        hero: true,
        mine: _stageId == null ? null : _mine,
        onMine: (v) {
          setState(() => _mine = v);
          _load();
        },
      );
    }
    return SdArea(
      area: AppArea.nahw,
      child: BasePage(
        width: AppWidth.reading,
        appBar: ScreenAppBar(title: t('النحو', 'Arabic grammar'), showBack: false),
        child: SafeArea(child: body),
      ),
    );
  }
}

/// The levels (Stu2Nahw `screen=nahw`): with [hero] (the student's tab) the calm hero "النحو" and the daily lesson
/// riding up over it, then "دروس النحو" with the For my grade / Every level pill, and each level as a card: its
/// number, its progress bar (drawn in once, M2) and its lessons with a done tick, the next one's number or a ring.
/// Without [hero] (a parent's read-only view) the same cards in a plain list.
class NahwLevelsView extends StatelessWidget {
  const NahwLevelsView({
    super.key,
    required this.levels,
    this.error,
    this.onRetry,
    this.onOpen,
    this.mine,
    this.onMine,
    this.top,
    this.hero = false,
  });

  /// Drawn first (the tab's daily learning section).
  final Widget? top;

  /// null = loading.
  final List<NahwLevel>? levels;
  final String? error;
  final VoidCallback? onRetry;

  /// null = read-only (a parent's view).
  final ValueChanged<NahwLessonRef>? onOpen;

  /// "My grade only": null hides the choice (no stage known).
  final bool? mine;
  final ValueChanged<bool>? onMine;

  /// The student's tab: the hero band on top.
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final list = levels;
    // a narrow phone puts the pill under the heading
    final head = Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
      Semantics(header: true, child: Text('sd_nahw_lessons'.tr, style: AppType.section(context))),
      if (mine != null)
        AppTabs(
          key: const ValueKey('nahw.mine'),
          hug: true,
          items: [AppTabItem(t('لصفّي', 'For my grade')), AppTabItem(t('كل المستويات', 'Every level'))],
          index: mine! ? 0 : 1,
          onChanged: (i) => onMine?.call(i == 0),
        ),
    ]);
    final List<Widget> body;
    if (list == null) {
      body = [if (error != null) AppErrorState(message: error, onRetry: onRetry) else const AppListSkeleton(items: 4)];
    } else if (list.isEmpty) {
      body = [
        AppCard(
          child: AppEmpty(
            icon: Icons.translate_rounded,
            title: t('لا توجد دروس بعد', 'No lessons yet'),
            message: t('ستظهر دروس النحو هنا عند إضافتها', 'Grammar lessons show here once they are added'),
          ),
        ),
      ];
    } else {
      body = [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) AppSpace.gapMd,
          _LevelCard(level: list[i], step: i + 1, onOpen: onOpen),
        ],
      ];
    }
    final children = <Widget>[
      if (top != null) ...[top!, AppSpace.gapLg],
      head,
      AppSpace.gapSm,
      ...body,
    ];
    if (hero) {
      return SdHeroList(
        hero: AppHero(title: t('النحو', 'Arabic grammar'), subtitle: 'sd_nahw_sub'.tr, icon: Icons.translate_rounded),
        children: children,
      );
    }
    return ListView(padding: AppSpace.card, children: children);
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level, required this.step, this.onOpen});

  final NahwLevel level;
  final int step;
  final ValueChanged<NahwLessonRef>? onOpen;

  @override
  Widget build(BuildContext context) {
    final set = AppAreaScope.of(context);
    final c = context.colors;
    // the first lesson not done is the one to do next
    final next = level.lessons.indexWhere((l) => l.progress?.completed != true);
    return AppCard(
      key: ValueKey('nahw.level.${level.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: AppDashSize.glyph,
            height: AppDashSize.glyph,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: set.button, borderRadius: BorderRadius.circular(AppRadius.glyph)),
            child: Text(appDigits('$step'), style: AppType.section(context).copyWith(color: set.btnFg)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(level.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
              const SizedBox(height: AppSpace.xs),
              Semantics(
                label: t('أتممت ${level.completed} من ${level.total}', '${level.completed} of ${level.total} done'),
                child: AppProgressBar(value: level.fraction, max: 1),
              ),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          AppStatusBadge(
            label: appDigits('${level.completed} / ${level.total}'),
            tone: level.total > 0 && level.completed >= level.total ? AppTone.success : AppTone.neutral,
            dense: true,
          ),
        ]),
        AppSpace.gapSm,
        for (final (i, l) in level.lessons.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpace.xs),
          _LessonRow(lesson: l, number: i + 1, next: i == next, onOpen: onOpen),
        ],
        if (level.lessons.isEmpty) Text(t('لا توجد دروس بعد', 'No lessons yet'), style: AppType.meta(context).copyWith(color: c.textMedium)),
      ]),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson, required this.number, required this.next, this.onOpen});

  final NahwLessonRef lesson;
  final int number;
  final bool next;
  final ValueChanged<NahwLessonRef>? onOpen;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    final set = AppAreaScope.of(context);
    final p = lesson.progress;
    final done = p?.completed == true;
    final status = done || (p != null && p.percent > 0)
        ? 'sd_nahw_best'.tr.replaceAll('{n}', appDigits('${p!.percent}'))
        : next
            ? 'sd_nahw_continue'.tr
            : t('جديد', 'New');
    final Widget mark = done
        ? Container(
            width: AppIconSize.xl + AppSpace.xs,
            height: AppIconSize.xl + AppSpace.xs,
            decoration: BoxDecoration(color: kit.ok.color, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, color: context.colors.onHero, size: AppIconSize.md),
          )
        : Container(
            width: AppIconSize.xl + AppSpace.xs,
            height: AppIconSize.xl + AppSpace.xs,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: next ? set.a : kit.track,
              shape: BoxShape.circle,
              border: next ? Border.all(color: set.tint, width: AppBorder.focus * 2) : null,
            ),
            child: Text(appDigits('$number'),
                style: AppType.label(context).copyWith(color: next ? set.btnFg : context.colors.textMedium, fontWeight: FontWeight.w600)),
          );
    return AppTile(
      key: ValueKey('nahw.lesson.${lesson.id}'),
      dense: true,
      leading: ExcludeSemantics(child: mark),
      title: lesson.title,
      subtitle: status,
      selected: next,
      onTap: onOpen == null ? null : () => onOpen!(lesson),
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

  /// 403 `consent_required`: a minor whose parent has not consented yet (D-1371).
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _consent = false;
    });
    try {
      final l = await _api.child(widget.studentId);
      if (mounted) setState(() => _levels = l);
    } catch (e) {
      if (mounted) {
        setState(() {
          _consent = isConsentRequired(e);
          _error = nahwErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.studentName.trim();
    return BasePage(
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: t('النحو', 'Arabic grammar'), subtitle: name.isEmpty ? null : name),
      child: SafeArea(
        child: _consent
            ? ParentConsentRequired(studentId: widget.studentId, childName: name, onGranted: _load)
            : NahwLevelsView(levels: _levels, error: _error, onRetry: _load),
      ),
    );
  }
}
