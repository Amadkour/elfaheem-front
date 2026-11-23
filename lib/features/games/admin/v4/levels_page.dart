// lib/features/games/admin/v4/levels_page.dart — SUPER ADMIN: the Games v4 levels (T67, CONTRACT §10). One list per game
// and subject (the filters), drag the handle to reorder (`POST /admin/games/reorder` also rewrites `level_no`), a switch
// publishes / hides a level, a tap edits it in the wizard, "Add level" opens the wizard and "Split automatically" cuts
// the subject's approved questions into numbered levels (a draft each, nothing public until published). Kill switch
// `admin.games_content`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/hub_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/level_wizard.dart';
import 'package:flutter_education_app/features/games/admin/v4/levels_api.dart';

class GamesLevelsPage extends StatefulWidget {
  const GamesLevelsPage({super.key, this.api, this.adminApi});

  final LevelsAdminApi? api;
  final GamesV4AdminApi? adminApi;

  @override
  State<GamesLevelsPage> createState() => _GamesLevelsPageState();
}

class _GamesLevelsPageState extends State<GamesLevelsPage> {
  late final LevelsAdminApi _api = widget.api ?? LevelsAdminApi();
  late final GamesV4AdminApi _admin = widget.adminApi ?? GamesV4AdminApi();
  List<LevelRow>? _levels;
  List<GameTemplateRow> _templates = const [];
  List<GameSubjectRow> _subjects = const [];
  String? _template, _error;
  int? _subject;
  DateTime? _loadedAt;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    _admin.templates().then((l) => mounted ? setState(() => _templates = l) : null).catchError((_) {});
    _admin.subjects().then((l) => mounted ? setState(() => _subjects = l) : null).catchError((_) {});
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.levels(template: _template, subjectId: _subject);
      r.sort((a, b) => a.levelNo.compareTo(b.levelNo));
      if (!mounted) return;
      setState(() {
        _levels = r;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = levelsErrorText(e));
    }
  }

  Future<void> _toggle(LevelRow l, bool on) async {
    setState(() => _busy.add(l.id));
    try {
      await _api.update(l.id, {'status': on ? 'published' : 'draft'});
      showAppNotice(on ? t('نُشر المستوى', 'Level published') : t('أُعيد المستوى مسودة', 'Level back to draft'));
      await _load();
    } catch (e) {
      showAppNotice(levelsErrorText(e), error: true);
    }
    if (mounted) setState(() => _busy.remove(l.id));
  }

  Future<void> _reorder(int from, int to) async {
    final list = [...?_levels];
    final moved = list.removeAt(from);
    list.insert(to, moved);
    setState(() => _levels = list);
    try {
      await _api.reorder([for (final l in list) l.id]);
      await _load();
    } catch (e) {
      showAppNotice(levelsErrorText(e), error: true);
      await _load();
    }
  }

  Future<void> _edit([LevelRow? l]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => LevelWizardPage(level: l, initialTemplate: _template, initialSubjectId: _subject, api: _api, adminApi: _admin),
    ));
    if (saved == true) await _load();
  }

  Future<void> _delete(LevelRow l) async {
    if (!await appConfirm(context, message: t('حذف المستوى «${l.title}»؟', 'Delete the level "${l.title}"?'), danger: true)) return;
    try {
      await _api.delete(l.id);
      showAppNotice(t('حُذف المستوى', 'Level deleted'));
      await _load();
    } catch (e) {
      showAppNotice(levelsErrorText(e), error: true);
    }
  }

  Future<void> _autoSplit() async {
    final body = await showAppSheet<Map<String, dynamic>>(
      context,
      (ctx) => AutoSplitSheet(templates: _templates, subjects: _subjects, template: _template, subjectId: _subject),
    );
    if (body == null) return;
    try {
      final r = await _api.autoSplit(body);
      showAppNotice(t('أُنشئ ${r.created.length} مستوى (مسودات)', '${r.created.length} levels created (drafts)'));
      await _load();
    } catch (e) {
      showAppNotice(levelsErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      helpPageId: 'admin.games.levels',
      width: AppWidth.content,
      title: t('المستويات', 'Levels'),
      subtitle: t('رتّب مستويات كل لعبة وكل مادة، وانشر ما اكتمل.', 'Order each game\'s levels by subject, and publish what is ready.'),
      icon: Icons.stairs_rounded,
      onRefresh: _load,
      updatedAt: _loadedAt,
      actions: [
        AppButton.secondary(
          key: const ValueKey('games.levels.split'),
          label: t('تقسيم تلقائي', 'Split automatically'),
          icon: Icons.auto_awesome_rounded,
          onPressed: _templates.isEmpty || _subjects.isEmpty ? null : _autoSplit,
        ),
      ],
      primaryAction: AppButton.primary(
        key: const ValueKey('games.levels.add'),
        label: t('إضافة مستوى', 'Add level'),
        icon: Icons.add_rounded,
        onPressed: () => _edit(),
      ),
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: GamesLevelsBody(
          levels: _levels,
          error: _error,
          templates: _templates,
          subjects: _subjects,
          template: _template,
          subjectId: _subject,
          busy: _busy,
          onTemplate: (v) {
            setState(() => _template = v);
            _load();
          },
          onSubject: (v) {
            setState(() => _subject = v);
            _load();
          },
          onRetry: _load,
          onToggle: _toggle,
          onEdit: _edit,
          onDelete: _delete,
          onReorder: _reorder,
        ),
      ),
    );
  }
}

/// The filters and the list over plain values.
class GamesLevelsBody extends StatelessWidget {
  const GamesLevelsBody({
    super.key,
    required this.levels,
    this.error,
    this.templates = const [],
    this.subjects = const [],
    this.template,
    this.subjectId,
    this.busy = const {},
    this.onTemplate,
    this.onSubject,
    this.onRetry,
    this.onToggle,
    this.onEdit,
    this.onDelete,
    this.onReorder,
  });

  /// Null: loading.
  final List<LevelRow>? levels;
  final String? error;
  final List<GameTemplateRow> templates;
  final List<GameSubjectRow> subjects;
  final String? template;
  final int? subjectId;
  final Set<int> busy;
  final ValueChanged<String?>? onTemplate;
  final ValueChanged<int?>? onSubject;
  final VoidCallback? onRetry;
  final void Function(LevelRow l, bool on)? onToggle;
  final ValueChanged<LevelRow>? onEdit, onDelete;
  final void Function(int from, int to)? onReorder;

  @override
  Widget build(BuildContext context) {
    final l = levels;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.form.max),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: AppDropdown<String?>(
            key: const ValueKey('games.levels.f_template'),
            value: template,
            decoration: InputDecoration(labelText: t('اللعبة', 'Game')),
            items: [
              DropdownMenuItem(value: null, child: Text(t('كل الألعاب', 'All games'))),
              for (final x in templates) DropdownMenuItem(value: x.key, child: Text(x.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onTemplate ?? (_) {},
          ),
        ),
        AppSpace.gapSm,
        Expanded(
          child: AppDropdown<int?>(
            key: const ValueKey('games.levels.f_subject'),
            value: subjectId,
            decoration: InputDecoration(labelText: t('المادة', 'Subject')),
            items: [
              DropdownMenuItem(value: null, child: Text(t('كل المواد', 'All subjects'))),
              for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onSubject ?? (_) {},
          ),
        ),
          ]),
        ),
      ),
      AppSpace.gapSm,
      Expanded(child: _list(context, l)),
    ]);
  }

  Widget _list(BuildContext context, List<LevelRow>? l) {
    if (error != null && l == null) return AppErrorState(message: error, onRetry: onRetry);
    if (l == null) return const AppListSkeleton(items: 5, padding: EdgeInsets.zero);
    if (l.isEmpty) {
      return AppEmpty(
        icon: Icons.stairs_rounded,
        title: t('لا مستويات بعد', 'No levels yet'),
        message: t('أضف مستوى، أو قسّم أسئلة المادة تلقائياً.', 'Add a level, or split the subject\'s questions automatically.'),
      );
    }
    final reorderable = onReorder != null;
    return ReorderableListView.builder(
      key: const ValueKey('games.levels.list'),
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      itemCount: l.length,
      onReorderItem: onReorder ?? (_, _) {},
      itemBuilder: (context, i) => Padding(
        key: ValueKey('games.level.${l[i].id}'),
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: LevelCard(
          level: l[i],
          gameName: templates.where((x) => x.key == l[i].template).firstOrNull?.name,
          subjectName: subjects.where((x) => x.id == l[i].subjectId).firstOrNull?.name,
          index: i,
          reorderable: reorderable,
          busy: busy.contains(l[i].id),
          onToggle: onToggle == null ? null : (v) => onToggle!(l[i], v),
          onTap: onEdit == null ? null : () => onEdit!(l[i]),
          onDelete: onDelete == null ? null : () => onDelete!(l[i]),
        ),
      ),
    );
  }
}

class LevelCard extends StatelessWidget {
  const LevelCard({
    super.key,
    required this.level,
    this.gameName,
    this.subjectName,
    this.index = 0,
    this.reorderable = true,
    this.busy = false,
    this.onToggle,
    this.onTap,
    this.onDelete,
  });

  final LevelRow level;

  /// The game and the subject by name (null while their lists load).
  final String? gameName, subjectName;
  final int index;
  final bool reorderable;
  final bool busy;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap, onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = level;
    return AppCard(
      onTap: onTap,
      child: Row(children: [
        if (reorderable)
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
              child: Icon(Icons.drag_indicator_rounded, color: c.textMedium, semanticLabel: t('اسحب لإعادة الترتيب', 'Drag to reorder')),
            ),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${l.levelNo > 0 ? '${l.levelNo}. ' : ''}${l.title}', style: AppType.row(context).copyWith(color: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
            AppSpace.gapXs,
            Text(
              [
                ?gameName,
                ?subjectName,
                t('عمر ${l.ageMin}-${l.ageMax}', 'Ages ${l.ageMin}-${l.ageMax}'),
                t('${l.starts} لعبة', '${l.starts} plays'),
              ].join(' · '),
              style: AppType.meta(context).copyWith(color: c.textMedium),
            ),
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppStatusBadge(
                  label: l.published ? t('منشور', 'Published') : t('مسودة', 'Draft'), tone: l.published ? AppTone.success : AppTone.neutral, dense: true),
              if (l.sacred) AppStatusBadge(label: t('نص مقدّس', 'Sacred text'), icon: Icons.lock_rounded, tone: AppTone.gold, dense: true),
            ]),
          ]),
        ),
        AppSpace.gapSm,
        AppSwitch(value: l.published, semanticLabel: l.title, onChanged: busy ? null : onToggle),
        if (onDelete != null)
          AppIconButton(icon: Icons.delete_outline_rounded, tooltip: t('حذف', 'Delete'), onPressed: onDelete),
      ]),
    );
  }
}

/// "Split automatically": the body of `POST /levels/auto-split`, or null when dismissed.
class AutoSplitSheet extends StatefulWidget {
  const AutoSplitSheet({super.key, required this.templates, required this.subjects, this.template, this.subjectId});

  final List<GameTemplateRow> templates;
  final List<GameSubjectRow> subjects;
  final String? template;
  final int? subjectId;

  @override
  State<AutoSplitSheet> createState() => _AutoSplitSheetState();
}

class _AutoSplitSheetState extends State<AutoSplitSheet> {
  late String? _template = widget.template ?? widget.templates.firstOrNull?.key;
  late int? _subject = widget.subjectId ?? widget.subjects.firstOrNull?.id;
  final _topic = TextEditingController();
  final _titleAr = TextEditingController(text: 'المستوى {n}');
  final _titleEn = TextEditingController(text: 'Level {n}');
  int _per = 8;
  bool _steps = true, _publish = false;
  String? _error;

  @override
  void dispose() {
    _topic.dispose();
    _titleAr.dispose();
    _titleEn.dispose();
    super.dispose();
  }

  void _go() {
    if (_template == null || _subject == null) {
      setState(() => _error = t('اختر اللعبة والمادة', 'Choose the game and the subject'));
      return;
    }
    if (_titleAr.text.trim().isEmpty || _titleEn.text.trim().isEmpty) {
      setState(() => _error = t('اكتب اسم المستوى بالعربية والإنجليزية', 'Write the level name in Arabic and English'));
      return;
    }
    Navigator.of(context).pop({
      'template': _template,
      'game_subject_id': _subject,
      if (_topic.text.trim().isNotEmpty) 'topic': _topic.text.trim(),
      'per_level': _per,
      'difficulty_steps': _steps,
      'title_ar': _titleAr.text.trim(),
      'title_en': _titleEn.text.trim(),
      'publish': _publish,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetContent(
      title: t('تقسيم تلقائي إلى مستويات', 'Split into levels automatically'),
      subtitle: t('تُقطع الأسئلة المعتمدة إلى مستويات مرقّمة بعد آخر مستوى.', 'The approved questions are cut into numbered levels after the last one.'),
      icon: Icons.auto_awesome_rounded,
      children: [
        AppDropdown<String>(
          key: const ValueKey('games.split.template'),
          value: widget.templates.any((x) => x.key == _template) ? _template : null,
          decoration: InputDecoration(labelText: t('اللعبة', 'Game')),
          items: [for (final x in widget.templates) DropdownMenuItem(value: x.key, child: Text(x.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _template = v),
        ),
        AppSpace.gapSm,
        AppDropdown<int>(
          key: const ValueKey('games.split.subject'),
          value: widget.subjects.any((x) => x.id == _subject) ? _subject : null,
          decoration: InputDecoration(labelText: t('المادة', 'Subject')),
          items: [for (final s in widget.subjects) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _subject = v),
        ),
        AppSpace.gapSm,
        AppField(key: const ValueKey('games.split.topic'), controller: _topic, label: t('الموضوع (اختياري)', 'Topic (optional)')),
        AppSpace.gapSm,
        AppNumberField(
          key: const ValueKey('games.split.per'),
          initialValue: _per,
          label: t('عدد الأسئلة في كل مستوى (3-30)', 'Questions per level (3-30)'),
          min: 3,
          max: 30,
          onChanged: (v) => _per = v?.toInt() ?? 8,
        ),
        AppSwitchTile(
          key: const ValueKey('games.split.steps'),
          title: t('الأسهل أولاً', 'Easiest first'),
          subtitle: t('يتدرّج المستوى في الصعوبة', 'Levels grow harder as they go'),
          value: _steps,
          onChanged: (v) => setState(() => _steps = v),
        ),
        AppField(key: const ValueKey('games.split.title_ar'), controller: _titleAr, label: t('اسم المستوى بالعربية', 'Level name in Arabic'), helper: t('{n} = رقم المستوى', '{n} = the level number')),
        AppSpace.gapSm,
        AppField(key: const ValueKey('games.split.title_en'), controller: _titleEn, label: t('اسم المستوى بالإنجليزية', 'Level name in English'), ltr: true),
        AppSwitchTile(
          key: const ValueKey('games.split.publish'),
          title: t('نشرها فوراً', 'Publish at once'),
          subtitle: t('الأفضل تركها مسودات وتجربتها أولاً', 'Better to keep drafts and try them first'),
          value: _publish,
          onChanged: (v) => setState(() => _publish = v),
        ),
        if (_error != null) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: appToneColor(context, AppTone.danger)),
        ],
        AppSpace.gapMd,
        AppButton.primary(key: const ValueKey('games.split.go'), label: t('إنشاء المستويات', 'Create the levels'), icon: Icons.check_rounded, expand: true, onPressed: _go),
      ],
    );
  }
}
