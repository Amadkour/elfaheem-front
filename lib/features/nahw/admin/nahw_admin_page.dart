// lib/features/nahw/admin/nahw_admin_page.dart — SUPER ADMIN: the Arabic grammar (nahw) content editor (6.R #8,
// D-1349), kill switch `admin.nahw`, help id `admin.nahw`. Before it, a typo in a lesson needed the seed loader.
//
//   NahwAdminPage         levels (title ar / en, key, stage / grade, order, active) with their lessons; Add level,
//                         Add lesson, Edit, Delete
//   NahwAdminLessonPage   one lesson: its titles and reading text (body_ar), then its exercises; Add exercise, Edit,
//                         Delete
//   NahwExerciseEditor    one typed form per kind (choose · fill · classify, never `order`) with the explanation and
//                         a live preview drawn by the student's own NahwExerciseView (the learn kit)
//   NahwAdminLevelsBody / NahwAdminLessonBody   the bodies over plain values (test/ui/nahw_admin_test.dart)
//
// Calls: nahw_admin_api.dart. The server checks each exercise against its kind (422 nahw_bad_exercise); the editor
// checks the same rules first (nahw_exercise_draft.dart) so Save is only offered when the exercise is complete.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';

import '../nahw_exercise_view.dart';
import '../nahw_models.dart';
import 'nahw_admin_api.dart';
import 'nahw_exercise_draft.dart';

int? _intOf(String s) => int.tryParse(s.trim());

String _inactive() => t('متوقف', 'Inactive');

String _exerciseCount(int n) => n == 1 ? t('تمرين واحد', '1 exercise') : t('$n تمارين', '$n exercises');

// ═════════════════════════════════════════════════════════════════════════════
//  Levels
// ═════════════════════════════════════════════════════════════════════════════

class NahwAdminPage extends StatefulWidget {
  const NahwAdminPage({super.key, this.api});

  final NahwAdminApi? api;

  @override
  State<NahwAdminPage> createState() => _NahwAdminPageState();
}

class _NahwAdminPageState extends State<NahwAdminPage> {
  late final NahwAdminApi _api = widget.api ?? NahwAdminApi();
  List<NahwAdminLevel>? _levels;
  String? _error;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await _api.levels();
      if (!mounted) return;
      setState(() {
        _levels = l;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = nahwAdminErrorText(e));
    }
  }

  /// Runs a write; a failure is the returned text (the sheet stays open), a success reloads.
  Future<String?> _write(Future<void> Function() call, String done) async {
    try {
      await call();
    } catch (e) {
      return nahwAdminErrorText(e);
    }
    showAppNotice(done);
    await _load();
    return null;
  }

  Future<void> _editLevel([NahwAdminLevel? level]) async {
    final edu = await NahwLevelEdu.load();
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      (ctx) => NahwLevelForm(
        initial: level,
        edu: edu,
        onSave: (body) => _write(
          () => level == null ? _api.createLevel(body) : _api.updateLevel(level.id, body),
          level == null ? t('أُضيف المستوى', 'Level added') : t('حُفظ المستوى', 'Level saved'),
        ),
      ),
    );
  }

  Future<void> _deleteLevel(NahwAdminLevel level) async {
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('حذف', 'Delete'),
        message: t('حذف المستوى «${level.title}» ودروسه وتمارينه؟ لا يمكن التراجع.',
            'Delete the level "${level.title}" with its lessons and exercises? This cannot be undone.'));
    if (!ok) return;
    final err = await _write(() => _api.deleteLevel(level.id), t('حُذف المستوى', 'Level deleted'));
    if (err != null) showAppNotice(err, error: true);
  }

  Future<void> _addLesson(NahwAdminLevel level) async {
    await showAppSheet<void>(
      context,
      (ctx) => NahwLessonForm(
        levelId: level.id,
        onSave: (body) => _write(() => _api.createLesson(body), t('أُضيف الدرس', 'Lesson added')),
      ),
    );
  }

  Future<void> _openLesson(NahwAdminLessonRef lesson) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: RouteSettings(name: '/admin/nahw/lessons/${lesson.id}'),
      builder: (_) => NahwAdminLessonPage(lessonId: lesson.id, title: lesson.title, api: _api),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      width: AppWidth.content,
      title: t('محتوى النحو', 'Grammar content'),
      subtitle: t('المستويات والدروس والتمارين التي يراها الطلاب في تبويب النحو.',
          'The levels, lessons and exercises students see in the Grammar tab.'),
      icon: Icons.spellcheck_rounded,
      helpPageId: 'admin.nahw',
      onRefresh: _load,
      updatedAt: _loadedAt,
      primaryAction: AppButton.primary(
        key: const ValueKey('nahw.admin.addLevel'),
        label: t('إضافة مستوى', 'Add level'),
        icon: Icons.add_rounded,
        onPressed: _levels == null ? null : () => _editLevel(),
      ),
      body: AppRefresh(
        onRefresh: _load,
        child: ListView(padding: AdminPage.bodyPadding(context), children: [
          NahwAdminLevelsBody(
            levels: _levels,
            error: _error,
            onRetry: _load,
            onEditLevel: _editLevel,
            onDeleteLevel: _deleteLevel,
            onAddLesson: _addLesson,
            onOpenLesson: _openLesson,
          ),
        ]),
      ),
    );
  }
}

/// The levels and their lessons over plain values.
class NahwAdminLevelsBody extends StatelessWidget {
  const NahwAdminLevelsBody({
    super.key,
    required this.levels,
    this.error,
    this.onRetry,
    this.onEditLevel,
    this.onDeleteLevel,
    this.onAddLesson,
    this.onOpenLesson,
  });

  /// Null: loading.
  final List<NahwAdminLevel>? levels;
  final String? error;
  final VoidCallback? onRetry;
  final ValueChanged<NahwAdminLevel>? onEditLevel, onDeleteLevel, onAddLesson;
  final ValueChanged<NahwAdminLessonRef>? onOpenLesson;

  @override
  Widget build(BuildContext context) {
    final l = levels;
    if (error != null && l == null) return AppErrorState(message: error, onRetry: onRetry);
    if (l == null) return const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
    if (l.isEmpty) {
      return AppEmpty(
        icon: Icons.spellcheck_rounded,
        title: t('لا مستويات بعد', 'No levels yet'),
        message: t('أضف مستوى، ثم دروسه وتمارينه.', 'Add a level, then its lessons and exercises.'),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final level in l) ...[
        _LevelCard(
          key: ValueKey('nahw.admin.level.${level.id}'),
          level: level,
          onEdit: onEditLevel == null ? null : () => onEditLevel!(level),
          onDelete: onDeleteLevel == null ? null : () => onDeleteLevel!(level),
          onAddLesson: onAddLesson == null ? null : () => onAddLesson!(level),
          onOpenLesson: onOpenLesson,
        ),
        AppSpace.gapSm,
      ],
    ]);
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({super.key, required this.level, this.onEdit, this.onDelete, this.onAddLesson, this.onOpenLesson});

  final NahwAdminLevel level;
  final VoidCallback? onEdit, onDelete, onAddLesson;
  final ValueChanged<NahwAdminLessonRef>? onOpenLesson;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = [
      level.key,
      if (level.stageId == null) t('لكل المراحل', 'Every stage') else t('مرتبط بمرحلة', 'Linked to a stage'),
      if (!level.active) _inactive(),
    ].join(' · ');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(level.title,
                  style: AppType.section(context).copyWith(color: level.active ? null : c.textLight),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              Text(meta, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          _RowMenu(onEdit: onEdit, onDelete: onDelete),
        ]),
        if (level.lessons.isNotEmpty) AppSpace.gapSm,
        for (final lesson in level.lessons)
          _LessonRow(
            key: ValueKey('nahw.admin.lesson.${lesson.id}'),
            lesson: lesson,
            onTap: onOpenLesson == null ? null : () => onOpenLesson!(lesson),
          ),
        AppSpace.gapXs,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.secondary(
            key: ValueKey('nahw.admin.addLesson.${level.id}'),
            label: t('إضافة درس', 'Add lesson'),
            icon: Icons.add_rounded,
            onPressed: onAddLesson,
          ),
        ),
      ]),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({super.key, required this.lesson, this.onTap});

  final NahwAdminLessonRef lesson;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = [_exerciseCount(lesson.exerciseCount), if (!lesson.active) _inactive()].join(' · ');
    return Semantics(
      button: true,
      label: '${lesson.title}, $sub',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.controlAll,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
            child: Row(children: [
              Icon(Icons.article_outlined, size: AppIconSize.md, color: c.primary),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(lesson.title,
                      style: AppType.row(context).copyWith(color: lesson.active ? null : c.textLight),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  Text(sub, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({this.onEdit, this.onDelete});

  final VoidCallback? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: t('المزيد', 'More'),
      onSelected: (v) => (v == 'edit' ? onEdit : onDelete)?.call(),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'edit', enabled: onEdit != null, child: Text(t('تعديل', 'Edit'))),
        PopupMenuItem(value: 'delete', enabled: onDelete != null, child: Text(t('حذف', 'Delete'))),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  One lesson
// ═════════════════════════════════════════════════════════════════════════════

class NahwAdminLessonPage extends StatefulWidget {
  const NahwAdminLessonPage({super.key, required this.lessonId, this.title = '', this.api});

  final int lessonId;

  /// Shown while the lesson loads.
  final String title;
  final NahwAdminApi? api;

  @override
  State<NahwAdminLessonPage> createState() => _NahwAdminLessonPageState();
}

class _NahwAdminLessonPageState extends State<NahwAdminLessonPage> {
  late final NahwAdminApi _api = widget.api ?? NahwAdminApi();
  NahwAdminLesson? _lesson;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await _api.lesson(widget.lessonId);
      if (!mounted) return;
      setState(() => _lesson = l);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = nahwAdminErrorText(e));
    }
  }

  Future<String?> _write(Future<void> Function() call, String done) async {
    try {
      await call();
    } catch (e) {
      return nahwAdminErrorText(e);
    }
    showAppNotice(done);
    await _load();
    return null;
  }

  Future<void> _editLesson() async {
    final l = _lesson;
    if (l == null) return;
    await showAppSheet<void>(
      context,
      (ctx) => NahwLessonForm(
        levelId: l.ref.levelId,
        initial: l,
        onSave: (body) => _write(() => _api.updateLesson(l.ref.id, body), t('حُفظ الدرس', 'Lesson saved')),
      ),
    );
  }

  Future<void> _deleteLesson() async {
    final l = _lesson;
    if (l == null) return;
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('حذف', 'Delete'),
        message: t('حذف الدرس «${l.ref.title}» وتمارينه؟', 'Delete the lesson "${l.ref.title}" and its exercises?'));
    if (!ok || !mounted) return;
    try {
      await _api.deleteLesson(l.ref.id);
      showAppNotice(t('حُذف الدرس', 'Lesson deleted'));
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      showAppNotice(nahwAdminErrorText(e), error: true);
    }
  }

  Future<void> _editExercise([Map<String, dynamic>? raw]) async {
    final l = _lesson;
    if (l == null) return;
    final draft = raw == null
        ? NahwExerciseDraft(sort: l.exercises.length)
        : NahwExerciseDraft.from(raw);
    await showAppSheet<void>(
      context,
      (ctx) => NahwExerciseEditor(
        draft: draft,
        onSave: (body) => _write(
          () => draft.id == null ? _api.createExercise(l.ref.id, body) : _api.updateExercise(draft.id!, body),
          draft.id == null ? t('أُضيف التمرين', 'Exercise added') : t('حُفظ التمرين', 'Exercise saved'),
        ),
      ),
    );
  }

  Future<void> _deleteExercise(Map<String, dynamic> raw) async {
    final ok = await appConfirm(context,
        danger: true, confirmLabel: t('حذف', 'Delete'), message: t('حذف هذا التمرين؟', 'Delete this exercise?'));
    if (!ok) return;
    final id = raw['id'] is num ? (raw['id'] as num).toInt() : 0;
    final err = await _write(() => _api.deleteExercise(id), t('حُذف التمرين', 'Exercise deleted'));
    if (err != null) showAppNotice(err, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = _lesson;
    return AdminPage(
      width: AppWidth.reading,
      title: l?.ref.title ?? (widget.title.isEmpty ? t('درس', 'Lesson') : widget.title),
      icon: Icons.article_rounded,
      helpPageId: 'admin.nahw',
      onRefresh: _load,
      primaryAction: AppButton.primary(
        key: const ValueKey('nahw.admin.addExercise'),
        label: t('إضافة تمرين', 'Add exercise'),
        icon: Icons.add_rounded,
        onPressed: l == null ? null : () => _editExercise(),
      ),
      body: ListView(padding: AdminPage.bodyPadding(context), children: [
        NahwAdminLessonBody(
          lesson: l,
          error: _error,
          onRetry: _load,
          onEditLesson: _editLesson,
          onDeleteLesson: _deleteLesson,
          onEditExercise: _editExercise,
          onDeleteExercise: _deleteExercise,
        ),
      ]),
    );
  }
}

/// A lesson's card (titles, reading text) and its exercises over plain values.
class NahwAdminLessonBody extends StatelessWidget {
  const NahwAdminLessonBody({
    super.key,
    required this.lesson,
    this.error,
    this.onRetry,
    this.onEditLesson,
    this.onDeleteLesson,
    this.onEditExercise,
    this.onDeleteExercise,
  });

  final NahwAdminLesson? lesson;
  final String? error;
  final VoidCallback? onRetry, onEditLesson, onDeleteLesson;
  final ValueChanged<Map<String, dynamic>>? onEditExercise, onDeleteExercise;

  @override
  Widget build(BuildContext context) {
    final l = lesson;
    if (error != null && l == null) return AppErrorState(message: error, onRetry: onRetry);
    if (l == null) return const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.ref.titleAr, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (l.ref.titleEn.isNotEmpty)
                  Text(l.ref.titleEn, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (!l.ref.active) Text(_inactive(), style: AppType.meta(context).copyWith(color: c.danger)),
              ]),
            ),
            _RowMenu(onEdit: onEditLesson, onDelete: onDeleteLesson),
          ]),
          AppSpace.gapSm,
          Text(
            l.bodyAr.trim().isEmpty ? t('لا نص للدرس بعد', 'No reading text yet') : l.bodyAr,
            style: AppType.body(context).copyWith(color: l.bodyAr.trim().isEmpty ? c.textLight : null),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.rtl,
          ),
        ]),
      ),
      AppSpace.gapMd,
      Text(t('التمارين', 'Exercises'), style: AppType.section(context)),
      AppSpace.gapXs,
      if (l.exercises.isEmpty)
        AppEmpty(
          icon: Icons.quiz_outlined,
          title: t('لا تمارين بعد', 'No exercises yet'),
          message: t('أضف تمرين اختيار أو إكمال أو تصنيف.', 'Add a choice, fill-the-gap or classify exercise.'),
        ),
      for (var i = 0; i < l.exercises.length; i++) ...[
        _ExerciseCard(
          key: ValueKey('nahw.admin.exercise.$i'),
          raw: l.exercises[i],
          onEdit: onEditExercise == null ? null : () => onEditExercise!(l.exercises[i]),
          onDelete: onDeleteExercise == null ? null : () => onDeleteExercise!(l.exercises[i]),
        ),
        AppSpace.gapSm,
      ],
    ]);
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({super.key, required this.raw, this.onEdit, this.onDelete});

  final Map<String, dynamic> raw;
  final VoidCallback? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final kind = '${raw['kind'] ?? ''}';
    final editable = kNahwEditableKinds.contains(kind);
    return AppCard(
      onTap: editable ? onEdit : null,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppStatusBadge(label: nahwKindName(kind), tone: editable ? AppTone.info : AppTone.neutral, dense: true),
            AppSpace.gapXs,
            Text('${raw['prompt'] ?? ''}', style: AppType.row(context), maxLines: 3, overflow: TextOverflow.ellipsis),
          ]),
        ),
        _RowMenu(onEdit: editable ? onEdit : null, onDelete: onDelete),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Forms
// ═════════════════════════════════════════════════════════════════════════════

/// The countries and their stages, for the level's optional stage / grade.
class NahwLevelEdu {
  const NahwLevelEdu({this.countries = const [], this.catalogs = const {}});

  final List<EduCountry> countries;
  final Map<String, EduCountryCatalog> catalogs;

  /// The country whose catalog holds stage [id].
  String? countryOf(int? id) {
    if (id == null) return null;
    for (final e in catalogs.entries) {
      if (e.value.stage(id) != null) return e.key;
    }
    return null;
  }

  /// Never throws: no pickers when the catalog cannot be read (the level is then for every stage, or keeps its ids).
  static Future<NahwLevelEdu> load() async {
    try {
      final countries = await EduCountries.load();
      final catalogs = <String, EduCountryCatalog>{};
      for (final c in countries) {
        final cat = await EduCatalog.instance.load(c.code);
        if (cat != null && !cat.isEmpty) catalogs[c.code] = cat;
      }
      return NahwLevelEdu(countries: [for (final c in countries) if (catalogs.containsKey(c.code)) c], catalogs: catalogs);
    } catch (_) {
      return const NahwLevelEdu();
    }
  }
}

/// The save button row of every form: Cancel, Save (busy while the call runs), and the server's error above it.
class _FormActions extends StatelessWidget {
  const _FormActions({required this.onSave, this.busy = false, this.error, this.problem});

  final VoidCallback? onSave;
  final bool busy;
  final String? error;

  /// What is still missing (Save stays off).
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (problem != null) ...[
        Text(problem!, style: AppType.meta(context)),
        AppSpace.gapXs,
      ],
      if (error != null) ...[
        Semantics(liveRegion: true, child: Text(error!, style: AppType.body(context).copyWith(color: c.danger))),
        AppSpace.gapXs,
      ],
      Row(children: [
        Expanded(child: AppButton.secondary(label: t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(context).maybePop())),
        AppSpace.gapSm,
        Expanded(
          child: AppButton.primary(
            key: const ValueKey('nahw.admin.save'),
            label: t('حفظ', 'Save'),
            busy: busy,
            onPressed: problem == null && !busy ? onSave : null,
          ),
        ),
      ]),
    ]);
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: AppType.section(context)),
          AppSpace.gapMd,
          ...children,
        ]),
      ),
    );
  }
}

/// Mixin of the three forms: a save that keeps the sheet open on a server error.
mixin _Saving<W extends StatefulWidget> on State<W> {
  bool busy = false;
  String? serverError;

  Future<void> save(Future<String?> Function() call) async {
    setState(() {
      busy = true;
      serverError = null;
    });
    final err = await call();
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        busy = false;
        serverError = err;
      });
    }
  }
}

class NahwLevelForm extends StatefulWidget {
  const NahwLevelForm({super.key, this.initial, this.edu = const NahwLevelEdu(), required this.onSave});

  /// Null: a new level.
  final NahwAdminLevel? initial;
  final NahwLevelEdu edu;

  /// The body to send; returns the error text, or null when saved.
  final Future<String?> Function(Map<String, dynamic> body) onSave;

  @override
  State<NahwLevelForm> createState() => _NahwLevelFormState();
}

class _NahwLevelFormState extends State<NahwLevelForm> with _Saving<NahwLevelForm> {
  late final _ar = TextEditingController(text: widget.initial?.titleAr ?? '');
  late final _en = TextEditingController(text: widget.initial?.titleEn ?? '');
  late final _key = TextEditingController(text: widget.initial?.key ?? '');
  late final _sort = TextEditingController(text: '${widget.initial?.sort ?? 0}');
  late bool _active = widget.initial?.active ?? true;
  late int? _stage = widget.initial?.stageId;
  late int? _grade = widget.initial?.gradeId;
  late String? _country = widget.edu.countryOf(widget.initial?.stageId) ??
      (widget.edu.countries.isEmpty ? null : widget.edu.countries.first.code);

  bool get _isNew => widget.initial == null;

  @override
  void dispose() {
    for (final c in [_ar, _en, _key, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _problem {
    if (_ar.text.trim().isEmpty || _en.text.trim().isEmpty) return t('اكتب العنوان بالعربية والإنجليزية', 'Write the title in Arabic and English');
    if (_isNew && !RegExp(r'^[a-z0-9_.-]{1,40}$').hasMatch(_key.text.trim())) {
      return t('المفتاح: حروف إنجليزية صغيرة وأرقام و _ . - فقط', 'Key: lowercase English letters, digits and _ . - only');
    }
    if (_intOf(_sort.text) == null) return t('الترتيب رقم', 'The order is a number');
    return null;
  }

  Map<String, dynamic> get _body => {
        if (_isNew) 'key': _key.text.trim(),
        'title_ar': _ar.text.trim(),
        'title_en': _en.text.trim(),
        'stage_id': _stage,
        'grade_id': _stage == null ? null : _grade,
        'sort': _intOf(_sort.text) ?? 0,
        'active': _active,
      };

  @override
  Widget build(BuildContext context) {
    final cat = _country == null ? null : widget.edu.catalogs[_country];
    final stage = cat?.stage(_stage);
    final known = _stage == null || stage != null;
    return _Sheet(
      title: _isNew ? t('مستوى جديد', 'New level') : t('تعديل المستوى', 'Edit level'),
      children: [
        AppField(controller: _ar, label: t('العنوان بالعربية', 'Title in Arabic'), maxLength: 200, onChanged: (_) => setState(() {})),
        AppField(controller: _en, label: t('العنوان بالإنجليزية', 'Title in English'), ltr: true, maxLength: 200, onChanged: (_) => setState(() {})),
        if (_isNew)
          AppField(
            controller: _key,
            label: t('المفتاح (لا يتغير بعد الحفظ)', 'Key (fixed once saved)'),
            hint: 'beginner',
            ltr: true,
            maxLength: 40,
            onChanged: (_) => setState(() {}),
          ),
        if (widget.edu.catalogs.isNotEmpty) ...[
          Text(t('المرحلة الدراسية (اختياري)', 'School stage (optional)'), style: AppType.label(context)),
          AppSpace.gapXs,
          if (widget.edu.countries.length > 1) ...[
            AppDropdown<String>(
              value: _country,
              items: [
                for (final c in widget.edu.countries)
                  DropdownMenuItem(value: c.code, child: Text(c.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() {
                _country = v;
                _stage = null;
                _grade = null;
              }),
            ),
            AppSpace.gapXs,
          ],
          AppDropdown<int?>(
            value: known ? _stage : null,
            hint: Text(known ? t('لكل المراحل', 'Every stage') : t('مرحلة رقم $_stage', 'Stage #$_stage')),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(t('لكل المراحل', 'Every stage'))),
              for (final s in cat?.stages ?? const <EduStage>[])
                DropdownMenuItem<int?>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _stage = v;
              _grade = null;
            }),
          ),
          if (stage != null && stage.grades.isNotEmpty) ...[
            AppSpace.gapXs,
            AppDropdown<int?>(
              value: stage.grades.any((g) => g.id == _grade) ? _grade : null,
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(t('كل صفوف المرحلة', 'Every grade of the stage'))),
                for (final g in stage.grades)
                  DropdownMenuItem<int?>(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _grade = v),
            ),
          ],
          AppSpace.gapSm,
        ],
        AppField(
          controller: _sort,
          label: t('الترتيب (الأصغر أولاً)', 'Order (smallest first)'),
          ltr: true,
          keyboard: TextInputType.number,
          onChanged: (_) => setState(() {}),
        ),
        AppSwitchTile(
          title: t('ظاهر للطلاب', 'Shown to students'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        AppSpace.gapSm,
        _FormActions(
          problem: _problem,
          busy: busy,
          error: serverError,
          onSave: () => save(() => widget.onSave(_body)),
        ),
      ],
    );
  }
}

class NahwLessonForm extends StatefulWidget {
  const NahwLessonForm({super.key, required this.levelId, this.initial, required this.onSave});

  final int levelId;

  /// Null: a new lesson.
  final NahwAdminLesson? initial;
  final Future<String?> Function(Map<String, dynamic> body) onSave;

  @override
  State<NahwLessonForm> createState() => _NahwLessonFormState();
}

class _NahwLessonFormState extends State<NahwLessonForm> with _Saving<NahwLessonForm> {
  late final _ar = TextEditingController(text: widget.initial?.ref.titleAr ?? '');
  late final _en = TextEditingController(text: widget.initial?.ref.titleEn ?? '');
  late final _body = TextEditingController(text: widget.initial?.bodyAr ?? '');
  late final _sort = TextEditingController(text: '${widget.initial?.ref.sort ?? 0}');
  late bool _active = widget.initial?.ref.active ?? true;

  @override
  void dispose() {
    for (final c in [_ar, _en, _body, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _problem {
    if (_ar.text.trim().isEmpty || _en.text.trim().isEmpty) return t('اكتب العنوان بالعربية والإنجليزية', 'Write the title in Arabic and English');
    if (_intOf(_sort.text) == null) return t('الترتيب رقم', 'The order is a number');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initial == null;
    return _Sheet(
      title: isNew ? t('درس جديد', 'New lesson') : t('تعديل الدرس', 'Edit lesson'),
      children: [
        AppField(controller: _ar, label: t('العنوان بالعربية', 'Title in Arabic'), maxLength: 200, onChanged: (_) => setState(() {})),
        AppField(controller: _en, label: t('العنوان بالإنجليزية', 'Title in English'), ltr: true, maxLength: 200, onChanged: (_) => setState(() {})),
        AppField(
          controller: _body,
          label: t('نص الدرس (بالعربية)', 'Reading text (Arabic)'),
          helper: t('سطر لكل فقرة.', 'One line per paragraph.'),
          maxLines: 10,
          maxLength: 20000,
          keyboard: TextInputType.multiline,
          onChanged: (_) => setState(() {}),
        ),
        AppField(
          controller: _sort,
          label: t('الترتيب (الأصغر أولاً)', 'Order (smallest first)'),
          ltr: true,
          keyboard: TextInputType.number,
          onChanged: (_) => setState(() {}),
        ),
        AppSwitchTile(
          title: t('ظاهر للطلاب', 'Shown to students'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        AppSpace.gapSm,
        _FormActions(
          problem: _problem,
          busy: busy,
          error: serverError,
          onSave: () => save(() => widget.onSave({
                if (isNew) 'level_id': widget.levelId,
                'title_ar': _ar.text.trim(),
                'title_en': _en.text.trim(),
                'body_ar': _body.text.trim(),
                'sort': _intOf(_sort.text) ?? 0,
                'active': _active,
              })),
        ),
      ],
    );
  }
}

/// One exercise: the kind, the prompt (ar / en), the kind's typed fields, the explanation, and a live preview drawn
/// by the student's own widget.
class NahwExerciseEditor extends StatefulWidget {
  const NahwExerciseEditor({super.key, required this.draft, required this.onSave});

  final NahwExerciseDraft draft;
  final Future<String?> Function(Map<String, dynamic> body) onSave;

  @override
  State<NahwExerciseEditor> createState() => _NahwExerciseEditorState();
}

class _NahwExerciseEditorState extends State<NahwExerciseEditor> with _Saving<NahwExerciseEditor> {
  NahwExerciseDraft get d => widget.draft;

  late final _prompt = TextEditingController(text: d.prompt);
  late final _promptEn = TextEditingController(text: d.promptEn);
  late final _explanation = TextEditingController(text: d.explanation);
  late final _text = TextEditingController(text: d.text);
  late final _sort = TextEditingController(text: '${d.sort}');
  late final List<TextEditingController> _options = [for (final o in d.options) TextEditingController(text: o)];
  late final List<(TextEditingController, TextEditingController)> _cats = [
    for (final c in d.categories) (TextEditingController(text: c.labelAr), TextEditingController(text: c.labelEn)),
  ];
  late final List<TextEditingController> _items = [for (final i in d.items) TextEditingController(text: i.text)];

  NahwResponse _response = const NahwResponse();
  bool _previewChecked = false;

  @override
  void dispose() {
    for (final c in [_prompt, _promptEn, _explanation, _text, _sort, ..._options, ..._items]) {
      c.dispose();
    }
    for (final c in _cats) {
      c.$1.dispose();
      c.$2.dispose();
    }
    super.dispose();
  }

  /// The controllers into the draft (called before every rebuild that reads it).
  void _sync() {
    d
      ..prompt = _prompt.text
      ..promptEn = _promptEn.text
      ..explanation = _explanation.text
      ..text = _text.text
      ..sort = _intOf(_sort.text) ?? 0
      ..options = [for (final c in _options) c.text];
    for (var i = 0; i < _cats.length && i < d.categories.length; i++) {
      d.categories[i]
        ..labelAr = _cats[i].$1.text
        ..labelEn = _cats[i].$2.text;
    }
    for (var i = 0; i < _items.length && i < d.items.length; i++) {
      d.items[i].text = _items[i].text;
    }
  }

  void _changed([void Function()? also]) => setState(() {
        also?.call();
        _sync();
        _previewChecked = false;
      });

  /// A structural change (an option / category / item added or removed, the kind): the preview starts again.
  void _reshaped(void Function() change) => _changed(() {
        change();
        _response = const NahwResponse();
      });

  void _addOption() => _reshaped(() {
        _options.add(TextEditingController());
        d.options.add('');
      });

  void _removeOption(int i) => _reshaped(() {
        _options.removeAt(i).dispose();
        d.options.removeAt(i);
        final a = d.answerIndex;
        if (a != null) d.answerIndex = a == i ? null : (a > i ? a - 1 : a);
      });

  void _addCategory() => _reshaped(() {
        _cats.add((TextEditingController(), TextEditingController()));
        d.categories.add(NahwCategoryDraft(key: d.nextCategoryKey()));
      });

  void _removeCategory(int i) => _reshaped(() {
        final c = _cats.removeAt(i);
        c.$1.dispose();
        c.$2.dispose();
        final key = d.categories.removeAt(i).key;
        for (final it in d.items) {
          if (it.category == key) it.category = null;
        }
      });

  void _addItem() => _reshaped(() {
        _items.add(TextEditingController());
        d.items.add(NahwItemDraft());
      });

  void _removeItem(int i) => _reshaped(() {
        _items.removeAt(i).dispose();
        d.items.removeAt(i);
      });

  Widget _removeButton(VoidCallback? onPressed) => IconButton(
        tooltip: t('حذف', 'Remove'),
        onPressed: onPressed,
        icon: const Icon(Icons.remove_circle_outline_rounded),
      );

  List<Widget> _optionFields() => [
        Text(t('الخيارات', 'Options'), style: AppType.label(context)),
        AppSpace.gapXs,
        for (var i = 0; i < _options.length; i++)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: AppField(
                key: ValueKey('nahw.admin.option.$i'),
                controller: _options[i],
                label: t('الخيار ${i + 1}', 'Option ${i + 1}'),
                onChanged: (_) => _changed(),
              ),
            ),
            _removeButton(_options.length > 2 ? () => _removeOption(i) : null),
          ]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.secondary(label: t('إضافة خيار', 'Add option'), icon: Icons.add_rounded, onPressed: _options.length < 8 ? _addOption : null),
        ),
        AppSpace.gapSm,
        Text(t('الإجابة الصحيحة', 'The right answer'), style: AppType.label(context)),
        AppSpace.gapXs,
        AppDropdown<int>(
          key: const ValueKey('nahw.admin.answer'),
          value: d.answerIndex != null && d.answerIndex! < _options.length ? d.answerIndex : null,
          hint: Text(t('اختر', 'Choose')),
          items: [
            for (var i = 0; i < _options.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(_options[i].text.trim().isEmpty ? t('الخيار ${i + 1}', 'Option ${i + 1}') : _options[i].text,
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => _changed(() => d.answerIndex = v),
        ),
      ];

  List<Widget> _classifyFields() => [
        Text(t('الأقسام', 'Categories'), style: AppType.label(context)),
        AppSpace.gapXs,
        for (var i = 0; i < _cats.length; i++)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: AppField(
                key: ValueKey('nahw.admin.cat.$i'),
                controller: _cats[i].$1,
                label: t('القسم ${i + 1} بالعربية', 'Category ${i + 1} (Arabic)'),
                onChanged: (_) => _changed(),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: AppField(
                controller: _cats[i].$2,
                label: t('بالإنجليزية', 'In English'),
                ltr: true,
                onChanged: (_) => _changed(),
              ),
            ),
            _removeButton(_cats.length > 2 ? () => _removeCategory(i) : null),
          ]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.secondary(label: t('إضافة قسم', 'Add category'), icon: Icons.add_rounded, onPressed: _cats.length < 6 ? _addCategory : null),
        ),
        AppSpace.gapSm,
        Text(t('الكلمات وقسم كل منها', 'The words and the category of each'), style: AppType.label(context)),
        AppSpace.gapXs,
        for (var i = 0; i < _items.length; i++)
          AppCard(
            padding: AppSpace.card,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: AppField(
                    key: ValueKey('nahw.admin.item.$i'),
                    controller: _items[i],
                    label: t('الكلمة ${i + 1}', 'Word ${i + 1}'),
                    onChanged: (_) => _changed(),
                  ),
                ),
                _removeButton(_items.length > 1 ? () => _removeItem(i) : null),
              ]),
              AppDropdown<String>(
                value: d.categories.any((c) => c.key == d.items[i].category) ? d.items[i].category : null,
                hint: Text(t('القسم الصحيح', 'The right category')),
                items: [
                  for (var k = 0; k < d.categories.length; k++)
                    DropdownMenuItem(
                      value: d.categories[k].key,
                      child: Text(_cats[k].$1.text.trim().isEmpty ? t('القسم ${k + 1}', 'Category ${k + 1}') : _cats[k].$1.text,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => _changed(() => d.items[i].category = v),
              ),
            ]),
          ),
        AppSpace.gapXs,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.secondary(label: t('إضافة كلمة', 'Add word'), icon: Icons.add_rounded, onPressed: _items.length < 20 ? _addItem : null),
        ),
      ];

  Widget _preview() {
    final e = d.toExercise();
    final ready = d.problem() == null && e.supported;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('معاينة كما يراها الطالب', 'Preview as the student sees it'), style: AppType.label(context)),
        AppSpace.gapSm,
        if (!ready)
          Text(t('أكمل الحقول لترى المعاينة.', 'Complete the fields to see the preview.'), style: AppType.meta(context))
        else ...[
          NahwExerciseView(
            key: const ValueKey('nahw.admin.preview'),
            exercise: e,
            response: _response,
            checked: _previewChecked,
            onChanged: (r) => setState(() => _response = r),
          ),
          if (_previewChecked && e.explanation.trim().isNotEmpty) ...[
            AppSpace.gapSm,
            Text(e.explanation, style: AppType.body(context)),
          ],
          AppSpace.gapSm,
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.secondary(
              key: const ValueKey('nahw.admin.previewCheck'),
              label: _previewChecked ? t('جرّب مرة أخرى', 'Try again') : t('تحقّق', 'Check'),
              icon: _previewChecked ? Icons.replay_rounded : Icons.check_rounded,
              onPressed: () => setState(() {
                if (_previewChecked) _response = const NahwResponse();
                _previewChecked = !_previewChecked;
              }),
            ),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = d.problem();
    return _Sheet(
      title: d.id == null ? t('تمرين جديد', 'New exercise') : t('تعديل التمرين', 'Edit exercise'),
      children: [
        Text(t('النوع', 'Kind'), style: AppType.label(context)),
        AppSpace.gapXs,
        AppDropdown<String>(
          key: const ValueKey('nahw.admin.kind'),
          value: d.editable ? d.kind : null,
          items: [
            for (final k in kNahwEditableKinds) DropdownMenuItem(value: k, child: Text(nahwKindName(k), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null && v != d.kind) _reshaped(() => d.kind = v);
          },
        ),
        AppSpace.gapSm,
        AppField(
          controller: _prompt,
          label: t('السؤال بالعربية', 'Question in Arabic'),
          maxLines: 3,
          maxLength: 4000,
          onChanged: (_) => _changed(),
        ),
        AppField(
          controller: _promptEn,
          label: t('السؤال بالإنجليزية (اختياري)', 'Question in English (optional)'),
          ltr: true,
          maxLines: 2,
          onChanged: (_) => _changed(),
        ),
        if (d.kind == 'fill')
          AppField(
            controller: _text,
            label: t('الجملة', 'The sentence'),
            helper: t('ضع ___ مكان الكلمة الناقصة.', 'Put ___ where the missing word goes.'),
            maxLines: 2,
            onChanged: (_) => _changed(),
          ),
        if (d.kind == 'choose' || d.kind == 'fill') ..._optionFields(),
        if (d.kind == 'classify') ..._classifyFields(),
        AppSpace.gapSm,
        AppField(
          controller: _explanation,
          label: t('الشرح (يظهر بعد الإجابة)', 'Explanation (shown after the answer)'),
          maxLines: 3,
          maxLength: 4000,
          onChanged: (_) => _changed(),
        ),
        AppField(
          controller: _sort,
          label: t('الترتيب (الأصغر أولاً)', 'Order (smallest first)'),
          ltr: true,
          keyboard: TextInputType.number,
          onChanged: (_) => _changed(),
        ),
        _preview(),
        AppSpace.gapMd,
        _FormActions(
          problem: problem,
          busy: busy,
          error: serverError,
          onSave: () => save(() => widget.onSave(d.toJson())),
        ),
      ],
    );
  }
}
