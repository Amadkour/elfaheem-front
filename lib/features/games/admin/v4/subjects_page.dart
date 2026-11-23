// lib/features/games/admin/v4/subjects_page.dart — SUPER ADMIN: the game subjects (Games v4, T64). The list with an
// on / off switch, "needs review" and the counts; a tap edits a subject (names, review, the course subjects it follows),
// "Add subject" creates one. A subject with questions or levels cannot be deleted (switch it off). Kill switch
// `admin.games_content`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/admin/edu/edu_admin_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/hub_api.dart';

/// A course subject the games can follow (`/admin/edu/catalog`).
typedef CourseSubjectOption = ({int id, String name});

/// Every course subject of every country, de-duplicated by id. Empty when the catalog cannot be read.
Future<List<CourseSubjectOption>> loadCourseSubjects() async {
  const api = EduAdminApi();
  final out = <int, String>{};
  final countries = await api.countries() ?? const [];
  for (final c in countries) {
    final tree = await api.tree(c.code);
    for (final s in tree?.subjects ?? const <EduRow>[]) {
      out.putIfAbsent(s.id, () => s.name(AppConfig.lang == 'ar'));
    }
  }
  return [for (final e in out.entries) (id: e.key, name: e.value)];
}

class GamesSubjectsPage extends StatefulWidget {
  const GamesSubjectsPage({super.key, this.api, this.courseSubjects});

  final GamesV4AdminApi? api;
  final Future<List<CourseSubjectOption>> Function()? courseSubjects;

  @override
  State<GamesSubjectsPage> createState() => _GamesSubjectsPageState();
}

class _GamesSubjectsPageState extends State<GamesSubjectsPage> {
  late final GamesV4AdminApi _api = widget.api ?? GamesV4AdminApi();
  List<GameSubjectRow>? _subjects;
  List<CourseSubjectOption> _course = const [];
  String? _error;
  DateTime? _loadedAt;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    (widget.courseSubjects ?? loadCourseSubjects)().then((l) {
      if (mounted) setState(() => _course = l);
    }).catchError((_) {});
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.subjects();
      if (!mounted) return;
      setState(() {
        _subjects = r;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = gamesV4ErrorText(e));
    }
  }

  Future<void> _toggle(GameSubjectRow s, bool on) async {
    setState(() => _busy.add(s.id));
    try {
      await _api.updateSubject(s.id, {'enabled': on});
      showAppNotice(on ? t('شُغّلت المادة', 'Subject switched on') : t('أُوقفت المادة', 'Subject switched off'));
      await _load();
    } catch (e) {
      showAppNotice(gamesV4ErrorText(e), error: true);
    }
    if (mounted) setState(() => _busy.remove(s.id));
  }

  Future<void> _edit([GameSubjectRow? s]) async {
    final r = await showAppSheet<SubjectSheetResult>(
      context,
      (ctx) => SubjectSheet(subject: s, courseSubjects: _course),
    );
    if (r == null) return;
    try {
      if (r.delete && s != null) {
        await _api.deleteSubject(s.id);
        showAppNotice(t('حُذفت المادة', 'Subject deleted'));
      } else if (s == null) {
        await _api.createSubject(r.body);
        showAppNotice(t('أُضيفت المادة', 'Subject added'));
      } else {
        await _api.updateSubject(s.id, r.body);
        showAppNotice(t('حُفظت المادة', 'Subject saved'));
      }
      await _load();
    } catch (e) {
      showAppNotice(gamesV4ErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      width: AppWidth.content,
      title: t('مواد الألعاب', 'Game subjects'),
      subtitle: t('المواد التي تُبنى عليها الأسئلة والمستويات، وأيها يحتاج مراجعة قبل النشر.',
          'The subjects questions and levels are built on, and which need a review before they go live.'),
      icon: Icons.menu_book_rounded,
      onRefresh: _load,
      updatedAt: _loadedAt,
      primaryAction: AppButton.primary(
        key: const ValueKey('games.subjects.add'),
        label: t('إضافة مادة', 'Add subject'),
        icon: Icons.add_rounded,
        onPressed: _subjects == null ? null : () => _edit(),
      ),
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: GamesSubjectsBody(subjects: _subjects, error: _error, busy: _busy, onRetry: _load, onToggle: _toggle, onEdit: _edit),
      ),
    );
  }
}

/// The subjects over plain values.
class GamesSubjectsBody extends StatelessWidget {
  const GamesSubjectsBody({super.key, required this.subjects, this.error, this.busy = const {}, this.onRetry, this.onToggle, this.onEdit});

  /// Null: loading.
  final List<GameSubjectRow>? subjects;
  final String? error;
  final Set<int> busy;
  final VoidCallback? onRetry;
  final void Function(GameSubjectRow s, bool on)? onToggle;
  final ValueChanged<GameSubjectRow>? onEdit;

  @override
  Widget build(BuildContext context) {
    final l = subjects;
    if (error != null && l == null) return AppErrorState(message: error, onRetry: onRetry);
    if (l == null) return const AppListSkeleton(items: 5, padding: EdgeInsets.zero);
    if (l.isEmpty) {
      return AppEmpty(
        icon: Icons.menu_book_rounded,
        title: t('لا مواد بعد', 'No subjects yet'),
        message: t('أضف مادة لتبني عليها الأسئلة والمستويات.', 'Add a subject to build questions and levels on.'),
      );
    }
    return ListView.builder(
      key: const ValueKey('games.subjects.list'),
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      itemCount: l.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: SubjectCard(
          key: ValueKey('games.subject.${l[i].key}'),
          subject: l[i],
          busy: busy.contains(l[i].id),
          onToggle: onToggle == null ? null : (v) => onToggle!(l[i], v),
          onTap: onEdit == null ? null : () => onEdit!(l[i]),
        ),
      ),
    );
  }
}

class SubjectCard extends StatelessWidget {
  const SubjectCard({super.key, required this.subject, this.busy = false, this.onToggle, this.onTap});

  final GameSubjectRow subject;
  final bool busy;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = subject;
    return AppCard(
      onTap: onTap,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: AppType.row(context).copyWith(color: c.textDark)),
            AppSpace.gapXs,
            Text(
              t('${s.items} سؤال · ${s.levels} مستوى', '${s.items} questions · ${s.levels} levels'),
              style: AppType.meta(context).copyWith(color: c.textMedium),
            ),
            if (s.sacred || s.requiresReview || !s.enabled) ...[
              AppSpace.gapXs,
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                if (s.sacred) AppStatusBadge(label: t('نص مقدّس', 'Sacred text'), icon: Icons.lock_rounded, tone: AppTone.gold, dense: true),
                if (s.requiresReview) AppStatusBadge(label: t('يحتاج مراجعة', 'Needs review'), icon: Icons.rule_rounded, tone: AppTone.info, dense: true),
                if (!s.enabled) AppStatusBadge(label: t('متوقفة', 'Off'), dense: true),
              ]),
            ],
          ]),
        ),
        AppSpace.gapSm,
        AppSwitch(value: s.enabled, semanticLabel: s.name, onChanged: busy ? null : onToggle),
      ]),
    );
  }
}

/// What the subject sheet hands back: a PUT / POST body, or a delete request.
class SubjectSheetResult {
  const SubjectSheetResult.save(this.body) : delete = false;
  const SubjectSheetResult.delete()
      : body = const {},
        delete = true;
  final Map<String, dynamic> body;
  final bool delete;
}

/// Add (subject null) or edit one subject.
class SubjectSheet extends StatefulWidget {
  const SubjectSheet({super.key, this.subject, this.courseSubjects = const []});

  final GameSubjectRow? subject;
  final List<CourseSubjectOption> courseSubjects;

  @override
  State<SubjectSheet> createState() => _SubjectSheetState();
}

class _SubjectSheetState extends State<SubjectSheet> {
  late final _nameAr = TextEditingController(text: widget.subject?.nameAr ?? '');
  late final _nameEn = TextEditingController(text: widget.subject?.nameEn ?? '');
  late final _key = TextEditingController(text: widget.subject?.key ?? '');
  late bool _enabled = widget.subject?.enabled ?? true;
  late bool _review = widget.subject?.requiresReview ?? false;
  late bool _sacred = widget.subject?.sacred ?? false;
  late final Set<int> _linked = {...?widget.subject?.eduSubjectIds};
  String? _error;

  bool get _creating => widget.subject == null;

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    _key.dispose();
    super.dispose();
  }

  void _save() {
    final ar = _nameAr.text.trim(), en = _nameEn.text.trim(), key = _key.text.trim().toLowerCase();
    if (ar.isEmpty || en.isEmpty) {
      setState(() => _error = t('اكتب اسم المادة بالعربية والإنجليزية', 'Write the subject\'s name in Arabic and English'));
      return;
    }
    if (_creating && !RegExp(r'^[a-z0-9_]{2,24}$').hasMatch(key)) {
      setState(() => _error = t('المفتاح حروف إنجليزية صغيرة وأرقام وشرطة سفلية (2 إلى 24)', 'The key is lower-case letters, digits and underscores (2 to 24)'));
      return;
    }
    Navigator.of(context).pop(SubjectSheetResult.save({
      if (_creating) 'key': key,
      if (_creating) 'sacred': _sacred,
      'name_ar': ar,
      'name_en': en,
      'enabled': _enabled,
      'requires_review': _review,
      'edu_subject_ids': _linked.toList()..sort(),
    }));
  }

  Future<void> _delete() async {
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('حذف', 'Delete'),
        message: t('حذف «${widget.subject!.name}»؟ لا تُحذف مادة لها أسئلة أو مستويات.', 'Delete "${widget.subject!.name}"? A subject with questions or levels cannot be deleted.'));
    if (ok && mounted) Navigator.of(context).pop(const SubjectSheetResult.delete());
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetContent(
      title: _creating ? t('مادة جديدة', 'New subject') : widget.subject!.name,
      icon: Icons.menu_book_rounded,
      children: [
        AppField(controller: _nameAr, label: t('الاسم بالعربية', 'Name in Arabic'), required: true, onChanged: (_) => setState(() => _error = null)),
        AppSpace.gapSm,
        AppField(controller: _nameEn, label: t('الاسم بالإنجليزية', 'Name in English'), required: true, ltr: true, onChanged: (_) => setState(() => _error = null)),
        if (_creating) ...[
          AppSpace.gapSm,
          AppField(
            controller: _key,
            label: t('المفتاح (لا يتغير لاحقاً)', 'Key (cannot change later)'),
            helper: t('مثل: history', 'For example: history'),
            ltr: true,
            required: true,
            onChanged: (_) => setState(() => _error = null),
          ),
          AppSwitchTile(
            title: t('نص مقدّس', 'Sacred text'),
            subtitle: t('يُعرض بنص ثابت ولا تُستخدم معه كل الألعاب', 'Shown in fixed text; not every game can use it'),
            icon: Icons.lock_rounded,
            value: _sacred,
            onChanged: (v) => setState(() => _sacred = v),
          ),
        ],
        AppSwitchTile(
          key: const ValueKey('games.subject.enabled'),
          title: t('مفعّلة', 'On'),
          icon: Icons.power_settings_new_rounded,
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        AppSwitchTile(
          key: const ValueKey('games.subject.review'),
          title: t('تحتاج مراجعة قبل النشر', 'Needs review before it goes live'),
          subtitle: t('الأسئلة الجديدة تنتظر موافقة مراجع', 'New questions wait for a reviewer\'s approval'),
          icon: Icons.rule_rounded,
          value: _review,
          onChanged: (v) => setState(() => _review = v),
        ),
        if (widget.courseSubjects.isNotEmpty) ...[
          AppSectionTitle(t('مواد الدورات المرتبطة', 'Linked course subjects')),
          Text(
            t('عند فتح طالب دورة في مادة مرتبطة، تُقترح له ألعاب هذه المادة.',
                'When a student opens a course in a linked subject, this subject\'s games are suggested.'),
            style: AppType.meta(context).copyWith(color: context.colors.textMedium),
          ),
          AppSpace.gapXs,
          for (final c in widget.courseSubjects)
            AppSwitchTile(
              key: ValueKey('games.subject.link.${c.id}'),
              title: c.name,
              dense: true,
              value: _linked.contains(c.id),
              onChanged: (v) => setState(() => v ? _linked.add(c.id) : _linked.remove(c.id)),
            ),
        ],
        if (_error != null) ...[
          AppSpace.gapSm,
          Text(_error!, style: AppType.meta(context).copyWith(color: appToneColor(context, AppTone.danger))),
        ],
        AppSpace.gapMd,
        AppButton.primary(key: const ValueKey('games.subject.save'), label: t('حفظ', 'Save'), icon: Icons.check_rounded, expand: true, onPressed: _save),
        if (!_creating) ...[
          AppSpace.gapSm,
          AppButton.danger(label: t('حذف المادة', 'Delete subject'), icon: Icons.delete_outline_rounded, expand: true, onPressed: _delete),
        ],
      ],
    );
  }
}
