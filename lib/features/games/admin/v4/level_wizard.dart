// lib/features/games/admin/v4/level_wizard.dart — SUPER ADMIN: the level wizard (Games v4 T67, CONTRACT §2, §4, §10).
// Five plain steps for a non-technical admin: 1 game + name · 2 subject and questions (picked from the bank, or a
// rule that draws from the pool) · 3 difficulty, age and unlock · 4 settings (timer, lives, speed, penalty, theme,
// music; a sacred subject locks what its texts forbid) · 5 try it, then publish. "Try it" saves the level as a draft and
// plays it in the app with the real template through `POST /games/{id}/draw {mode: "preview"}`: unranked, no play is
// saved, and a question that is not approved yet is badged. Nothing is public until Publish.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/hub_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/levels_api.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart' show GamePlayView;
import 'package:flutter_education_app/features/games/games_models.dart' show GameSummary;
import 'package:flutter_education_app/features/games/templates/register_all.dart';

/// What the wizard collects. Plain values + the text controllers; [toBody] is the `POST / PUT /admin/games` body.
class LevelDraft {
  LevelDraft({
    this.id,
    this.template,
    this.subjectId,
    this.mode = 'pool',
    List<int>? itemIds,
    Set<String>? types,
    this.diffLo = 1,
    this.diffHi = 5,
    this.count = 8,
    this.ageMin = 6,
    this.ageMax = 99,
    this.unlockPrev = true,
    this.minStars = 1,
    this.coins = 5,
    this.levelNo,
    Map<String, dynamic>? settings,
    this.status = 'draft',
    String titleAr = '',
    String titleEn = '',
    String topic = '',
    this.key,
  })  : itemIds = itemIds ?? [],
        types = types ?? {},
        settings = settings ?? {},
        titleArC = TextEditingController(text: titleAr),
        titleEnC = TextEditingController(text: titleEn),
        topicC = TextEditingController(text: topic);

  factory LevelDraft.fromRow(LevelRow r) {
    final src = r.itemSource;
    final diff = src['difficulty'];
    int? num0(Object? v) => v is num ? v.toInt() : null;
    return LevelDraft(
      id: r.id,
      key: '${r.raw['key'] ?? ''}',
      template: r.template,
      subjectId: r.subjectId,
      mode: src['mode'] == 'fixed' ? 'fixed' : 'pool',
      itemIds: [if (src['item_ids'] is List) for (final x in src['item_ids'] as List) if (x is num) x.toInt()],
      types: {if (src['types'] is List) for (final x in src['types'] as List) '$x'},
      diffLo: diff is List && diff.isNotEmpty ? num0(diff.first) ?? 1 : 1,
      diffHi: diff is List && diff.length > 1 ? num0(diff[1]) ?? 5 : 5,
      count: num0(src['count']) ?? num0(r.settings['count']) ?? 8,
      ageMin: r.ageMin,
      ageMax: r.ageMax,
      unlockPrev: r.unlock['mode'] == 'prev',
      minStars: num0(r.unlock['min_stars']) ?? 1,
      coins: r.coins,
      levelNo: r.levelNo == 0 ? null : r.levelNo,
      settings: Map<String, dynamic>.from(r.settings),
      status: r.status,
      titleAr: r.titleAr,
      titleEn: r.titleEn,
      topic: r.topic,
    );
  }

  int? id;
  String? key;
  String? template;
  int? subjectId;

  /// `fixed` (picked questions) or `pool` (a rule).
  String mode;
  final List<int> itemIds;
  final Set<String> types;
  int diffLo, diffHi, count, ageMin, ageMax, minStars, coins;
  bool unlockPrev;
  int? levelNo;
  final Map<String, dynamic> settings;
  String status;
  final TextEditingController titleArC, titleEnC, topicC;

  void dispose() {
    titleArC.dispose();
    titleEnC.dispose();
    topicC.dispose();
  }

  Map<String, dynamic> itemSource() => mode == 'fixed'
      ? {'mode': 'fixed', 'item_ids': List<int>.of(itemIds)}
      : {
          'mode': 'pool',
          'subject_id': subjectId,
          if (topicC.text.trim().isNotEmpty) 'topic': topicC.text.trim(),
          if (types.isNotEmpty) 'types': types.toList()..sort(),
          'difficulty': [diffLo, diffHi],
          'count': count,
        };

  Map<String, dynamic> toBody({String? status}) => {
        if (id == null) 'key': key ?? 'lv_${template}_${DateTime.now().millisecondsSinceEpoch}',
        'engine': template,
        'title_ar': titleArC.text.trim(),
        'title_en': titleEnC.text.trim(),
        'config': <String, dynamic>{},
        'status': status ?? this.status,
        'game_subject_id': subjectId,
        'topic': topicC.text.trim(),
        'level_no': ?levelNo,
        'age_min': ageMin,
        'age_max': ageMax,
        'template_settings': {...settings, 'count': count},
        'item_source': itemSource(),
        'unlock': unlockPrev ? {'mode': 'prev', 'min_stars': minStars} : {'mode': 'open'},
        'coins_reward': coins,
      };

  /// Why the step cannot be left yet (null = fine).
  String? stepProblem(int step, {bool sacredClash = false}) {
    switch (step) {
      case 0:
        if (template == null) return t('اختر اللعبة', 'Choose the game');
        if (titleArC.text.trim().isEmpty || titleEnC.text.trim().isEmpty) {
          return t('اكتب اسم المستوى بالعربية والإنجليزية', 'Write the level\'s name in Arabic and English');
        }
      case 1:
        if (subjectId == null) return t('اختر المادة', 'Choose the subject');
        if (sacredClash) {
          return t('هذه اللعبة لا تقبل نصوص القرآن والحديث: اختر مادة أخرى', 'This game never takes Quran or Hadith texts: choose another subject');
        }
        if (mode == 'fixed' && itemIds.isEmpty) return t('اختر سؤالاً واحداً على الأقل', 'Pick at least one question');
      case 2:
        if (diffLo > diffHi) return t('أصعب مستوى أقل من أسهل مستوى', 'The hardest level is below the easiest');
        if (ageMin > ageMax) return t('العمر الأعلى أقل من الأدنى', 'The oldest age is below the youngest');
    }
    return null;
  }
}

class LevelWizardPage extends StatefulWidget {
  const LevelWizardPage({super.key, this.level, this.api, this.adminApi, this.itemsApi, this.initialTemplate, this.initialSubjectId});

  /// Null = a new level.
  final LevelRow? level;
  final String? initialTemplate;
  final int? initialSubjectId;
  final LevelsAdminApi? api;
  final GamesV4AdminApi? adminApi;
  final ItemsV4Api? itemsApi;

  @override
  State<LevelWizardPage> createState() => _LevelWizardPageState();
}

class _LevelWizardPageState extends State<LevelWizardPage> {
  late final LevelsAdminApi _api = widget.api ?? LevelsAdminApi();
  late final GamesV4AdminApi _admin = widget.adminApi ?? GamesV4AdminApi();
  late final ItemsV4Api _items = widget.itemsApi ?? ItemsV4Api();
  late final LevelDraft _d = widget.level != null
      ? LevelDraft.fromRow(widget.level!)
      : LevelDraft(template: widget.initialTemplate, subjectId: widget.initialSubjectId);
  List<GameTemplateRow>? _templates;
  List<GameSubjectRow> _subjects = const [];
  String? _loadError, _stepError;
  int _step = 0;
  bool _busy = false;

  GameSession? _session;
  int _unapproved = 0, _previewRound = 0;
  ({int score, int max})? _previewDone;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    registerGameTemplates();
    _load();
  }

  @override
  void dispose() {
    _session?.dispose();
    _d.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final tp = await _admin.templates();
      final sb = await _admin.subjects();
      if (!mounted) return;
      setState(() {
        _templates = tp;
        _subjects = sb;
        _applyDefaults();
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = levelsErrorText(e));
    }
  }

  GameTemplateRow? get _tpl => _templates?.where((x) => x.key == _d.template).firstOrNull;
  GameSubjectRow? get _subject => _subjects.where((x) => x.id == _d.subjectId).firstOrNull;
  bool get _sacredClash => (_subject?.sacred ?? false) && !(_tpl?.sacredAllowed ?? true);

  /// A new level starts from the template's own defaults (and its age band).
  void _applyDefaults() {
    final tp = _tpl;
    if (tp == null || widget.level != null || _d.settings.isNotEmpty) return;
    for (final k in const ['timer_s', 'lives', 'speed', 'penalty', 'theme', 'music']) {
      final v = tp.setting(k);
      if (v != null) _d.settings[k] = v;
    }
    final c = tp.setting('count');
    if (c is num) _d.count = c.toInt();
    if (tp.ageMin != null) _d.ageMin = tp.ageMin!;
    if (tp.ageMax != null) _d.ageMax = tp.ageMax!;
  }

  void _chooseTemplate(String key) {
    setState(() {
      _d.template = key;
      _d.settings.clear();
      _applyDefaults();
      _stepError = null;
    });
  }

  void _next() {
    final p = _d.stepProblem(_step, sacredClash: _sacredClash);
    if (p != null) {
      setState(() => _stepError = p);
      return;
    }
    setState(() {
      _stepError = null;
      _step++;
    });
  }

  /// Saves the level (a draft until Publish) and returns whether it worked.
  Future<bool> _save({String? status}) async {
    try {
      final body = _d.toBody(status: status);
      final r = _d.id == null ? await _api.create(body) : await _api.update(_d.id!, body);
      _d.id = r.id;
      if (status != null) _d.status = status;
      return true;
    } catch (e) {
      if (mounted) setState(() => _previewError = levelsErrorText(e));
      return false;
    }
  }

  Future<void> _startPreview() async {
    setState(() {
      _busy = true;
      _previewError = null;
      _previewDone = null;
    });
    _session?.dispose();
    _session = null;
    if (await _save()) {
      try {
        final draw = await _api.preview(_d.id!);
        final items = draw['items'];
        final session = GameSession.fromDraw(draw, onFinished: (s) {
          if (mounted) setState(() => _previewDone = (score: s.score, max: s.maxScore));
        });
        if (session == null) {
          _previewError = t('لا توجد أسئلة تكفي للتجربة', 'There are not enough questions to try');
        } else {
          _unapproved = items is List ? items.where((x) => x is Map && x['status'] != null && x['status'] != 'approved').length : 0;
          _session = session;
          _previewRound++;
          session.start();
        }
      } catch (e) {
        _previewError = levelsErrorText(e);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finish({required bool publish}) async {
    setState(() {
      _busy = true;
      _previewError = null;
    });
    final ok = await _save(status: publish ? 'published' : null);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      showAppNotice(publish ? t('نُشر المستوى', 'Level published') : t('حُفظت المسودة', 'Draft saved'));
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _pickItems() async {
    final r = await showAppSheet<List<int>>(
      context,
      (ctx) => BankPickerSheet(api: _items, subjectId: _d.subjectId, selected: _d.itemIds),
    );
    if (r != null) {
      setState(() => _d.itemIds
        ..clear()
        ..addAll(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tp = _templates;
    return AdminPage(
      width: AppWidth.reading,
      title: widget.level == null ? t('مستوى جديد', 'New level') : t('تعديل المستوى', 'Edit level'),
      icon: Icons.stairs_rounded,
      dirty: _d.id == null && _step > 0,
      body: _loadError != null
          ? AppErrorState(message: _loadError, onRetry: _load)
          : tp == null
              ? const AppListSkeleton(items: 4)
              : SingleChildScrollView(
                  padding: AdminPage.bodyPadding(context),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    LevelStepper(step: _step),
                    AppSpace.gapMd,
                    LevelStepBody(
                      step: _step,
                      draft: _d,
                      templates: tp,
                      subjects: _subjects,
                      onChanged: () => setState(() => _stepError = null),
                      onTemplate: _chooseTemplate,
                      onPickItems: _pickItems,
                      preview: PreviewPanel(
                        session: _session,
                        round: _previewRound,
                        engine: _d.template ?? '',
                        unapproved: _unapproved,
                        done: _previewDone,
                        error: _previewError,
                        busy: _busy,
                        onStart: _startPreview,
                      ),
                    ),
                    if (_stepError != null) ...[
                      AppSpace.gapSm,
                      AppBanner(icon: Icons.error_outline_rounded, text: _stepError!, color: appToneColor(context, AppTone.danger)),
                    ],
                    AppSpace.gapMd,
                    _bar(),
                  ]),
                ),
    );
  }

  Widget _bar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, alignment: WrapAlignment.end, children: [
        if (_step > 0)
          AppButton.ghost(key: const ValueKey('games.wiz.back'), label: t('السابق', 'Back'), onPressed: _busy ? null : () => setState(() => _step--)),
        if (_step == 4) ...[
          AppButton.secondary(key: const ValueKey('games.wiz.draft'), label: t('حفظ كمسودة', 'Save as draft'), onPressed: _busy ? null : () => _finish(publish: false)),
          AppButton.primary(
            key: const ValueKey('games.wiz.publish'),
            label: t('نشر المستوى', 'Publish level'),
            icon: Icons.publish_rounded,
            onPressed: _busy ? null : () => _finish(publish: true),
          ),
        ] else
          AppButton.primary(key: const ValueKey('games.wiz.next'), label: t('التالي', 'Next'), onPressed: _next),
      ]),
    );
  }
}

String levelStepName(int i) => switch (i) {
      0 => t('اللعبة', 'Game'),
      1 => t('الأسئلة', 'Questions'),
      2 => t('الصعوبة والعمر', 'Difficulty and age'),
      3 => t('الإعدادات', 'Settings'),
      _ => t('التجربة والنشر', 'Try and publish'),
    };

class LevelStepper extends StatelessWidget {
  const LevelStepper({super.key, required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) AppSpace.gapXs,
          Expanded(
            child: Container(
              height: AppSpace.xs,
              decoration: BoxDecoration(color: i <= step ? c.primary : c.divider, borderRadius: BorderRadius.circular(AppRadius.pill)),
            ),
          ),
        ],
      ]),
      AppSpace.gapSm,
      Text('${t('الخطوة ${step + 1} من 5', 'Step ${step + 1} of 5')} · ${levelStepName(step)}',
          key: const ValueKey('games.wiz.step'), style: AppType.meta(context).copyWith(color: c.textMedium)),
    ]);
  }
}

/// The body of one step over plain values (the draft is mutated, [onChanged] redraws).
class LevelStepBody extends StatelessWidget {
  const LevelStepBody({
    super.key,
    required this.step,
    required this.draft,
    required this.templates,
    required this.subjects,
    required this.onChanged,
    this.onTemplate,
    this.onPickItems,
    this.preview,
  });

  final int step;
  final LevelDraft draft;
  final List<GameTemplateRow> templates;
  final List<GameSubjectRow> subjects;
  final VoidCallback onChanged;
  final ValueChanged<String>? onTemplate;
  final VoidCallback? onPickItems;
  final Widget? preview;

  GameTemplateRow? get _tpl => templates.where((x) => x.key == draft.template).firstOrNull;
  GameSubjectRow? get _subject => subjects.where((x) => x.id == draft.subjectId).firstOrNull;

  @override
  Widget build(BuildContext context) => switch (step) {
        0 => _game(context),
        1 => _questions(context),
        2 => _difficulty(context),
        3 => _settings(context),
        _ => preview ?? const SizedBox.shrink(),
      };

  Widget _game(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(t('اختر اللعبة', 'Choose the game')),
      for (final tp in templates)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppCard(
            key: ValueKey('games.wiz.tpl.${tp.key}'),
            onTap: tp.enabled && onTemplate != null ? () => onTemplate!(tp.key) : null,
            child: Row(children: [
              Icon(draft.template == tp.key ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: draft.template == tp.key ? c.primary : c.textMedium),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tp.name, style: AppType.row(context).copyWith(color: c.textDark)),
                  if (!tp.sacredAllowed || !tp.enabled) ...[
                    AppSpace.gapXs,
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                      if (!tp.sacredAllowed)
                        AppStatusBadge(label: t('لا تُستخدم مع القرآن والحديث', 'Not for Quran and Hadith'), icon: Icons.lock_rounded, tone: AppTone.gold, dense: true),
                      if (!tp.enabled) AppStatusBadge(label: t('متوقفة', 'Off'), dense: true),
                    ]),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      AppSpace.gapSm,
      AppField(
          key: const ValueKey('games.wiz.title_ar'),
          controller: draft.titleArC,
          label: t('اسم المستوى بالعربية', 'Level name in Arabic'),
          onChanged: (_) => onChanged()),
      AppSpace.gapSm,
      AppField(
          key: const ValueKey('games.wiz.title_en'),
          controller: draft.titleEnC,
          label: t('اسم المستوى بالإنجليزية', 'Level name in English'),
          ltr: true,
          onChanged: (_) => onChanged()),
    ]);
  }

  Widget _num(String key, int? value, String label, int min, int max, void Function(int?) set) => AppNumberField(
        key: ValueKey(key),
        initialValue: value,
        label: label,
        min: min,
        max: max,
        onChanged: (v) {
          set(v?.toInt());
          onChanged();
        },
      );

  Widget _questions(BuildContext context) {
    final c = context.colors;
    final clash = (_subject?.sacred ?? false) && !(_tpl?.sacredAllowed ?? true);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(t('المادة', 'Subject')),
      AppDropdown<int>(
        key: const ValueKey('games.wiz.subject'),
        value: subjects.any((s) => s.id == draft.subjectId) ? draft.subjectId : null,
        hint: Text(t('اختر المادة', 'Choose the subject')),
        items: [for (final s in subjects.where((s) => s.enabled)) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          draft.subjectId = v;
          onChanged();
        },
      ),
      if (clash) ...[
        AppSpace.gapSm,
        AppBanner(
          icon: Icons.lock_rounded,
          text: t('هذه اللعبة لا تقبل نصوص القرآن والحديث: اختر مادة أخرى.', 'This game never takes Quran or Hadith texts: choose another subject.'),
          color: appToneColor(context, AppTone.gold),
        ),
      ],
      AppSpace.gapMd,
      AppSectionTitle(t('من أين تأتي الأسئلة؟', 'Where do the questions come from?')),
      AppDropdown<String>(
        key: const ValueKey('games.wiz.mode'),
        value: draft.mode,
        items: [
          DropdownMenuItem(value: 'pool', child: Text(t('تلقائياً بشروط أحددها', 'Automatically, by a rule'))),
          DropdownMenuItem(value: 'fixed', child: Text(t('أسئلة أختارها بنفسي', 'Questions I pick myself'))),
        ],
        onChanged: (v) {
          draft.mode = v ?? draft.mode;
          onChanged();
        },
      ),
      AppSpace.gapSm,
      if (draft.mode == 'fixed') ...[
        Text(t('${draft.itemIds.length} سؤال مختار', '${draft.itemIds.length} questions picked'), style: AppType.meta(context).copyWith(color: c.textMedium)),
        AppSpace.gapSm,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.secondary(
            key: const ValueKey('games.wiz.pick'),
            label: t('اختيار من بنك الأسئلة', 'Pick from the question bank'),
            icon: Icons.library_add_check_rounded,
            onPressed: draft.subjectId == null ? null : onPickItems,
          ),
        ),
      ] else ...[
        AppField(
          key: const ValueKey('games.wiz.topic'),
          controller: draft.topicC,
          label: t('الموضوع (اختياري)', 'Topic (optional)'),
          helper: t('مثال: juz_30/112 — يشمل ما يبدأ به', 'For example juz_30/112 — also matches what starts with it'),
          ltr: true,
          onChanged: (_) => onChanged(),
        ),
        AppSpace.gapSm,
        Text(t('أنواع الأسئلة (بلا اختيار = كل ما تقبله اللعبة)', 'Question types (none = whatever the game accepts)'),
            style: AppType.meta(context).copyWith(color: c.textMedium)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final k in kItemTypes)
            FilterChip(
              key: ValueKey('games.wiz.type.$k'),
              label: Text(itemTypeName(k)),
              selected: draft.types.contains(k),
              onSelected: (v) {
                v ? draft.types.add(k) : draft.types.remove(k);
                onChanged();
              },
            ),
        ]),
        AppSpace.gapSm,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _num('games.wiz.diff_lo', draft.diffLo, t('أسهل مستوى (1-5)', 'Easiest (1-5)'), 1, 5, (v) => draft.diffLo = v ?? 1)),
          AppSpace.gapSm,
          Expanded(child: _num('games.wiz.diff_hi', draft.diffHi, t('أصعب مستوى (1-5)', 'Hardest (1-5)'), 1, 5, (v) => draft.diffHi = v ?? 5)),
        ]),
      ],
      AppSpace.gapSm,
      _num('games.wiz.count', draft.count, t('عدد الأسئلة في الجولة', 'Questions in a round'), 1, 30, (v) => draft.count = v ?? 8),
    ]);
  }

  Widget _difficulty(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(t('العمر', 'Age range')),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _num('games.wiz.age_min', draft.ageMin, t('من عمر', 'Age from'), 4, 99, (v) => draft.ageMin = v ?? 6)),
        AppSpace.gapSm,
        Expanded(child: _num('games.wiz.age_max', draft.ageMax, t('إلى عمر', 'Age to'), 4, 99, (v) => draft.ageMax = v ?? 99)),
      ]),
      AppSpace.gapMd,
      AppSectionTitle(t('متى يُفتح المستوى؟', 'When does the level open?')),
      AppDropdown<bool>(
        key: const ValueKey('games.wiz.unlock'),
        value: draft.unlockPrev,
        items: [
          DropdownMenuItem(value: true, child: Text(t('بعد إنهاء المستوى السابق', 'After the previous level'))),
          DropdownMenuItem(value: false, child: Text(t('مفتوح للجميع', 'Open to everyone'))),
        ],
        onChanged: (v) {
          draft.unlockPrev = v ?? draft.unlockPrev;
          onChanged();
        },
      ),
      if (draft.unlockPrev) ...[
        AppSpace.gapSm,
        _num('games.wiz.min_stars', draft.minStars, t('نجوم المستوى السابق المطلوبة', 'Stars needed on the previous level'), 1, 3, (v) => draft.minStars = v ?? 1),
      ],
      AppSpace.gapSm,
      _num('games.wiz.coins', draft.coins, t('عملات المكافأة (0-300)', 'Coins as a reward (0-300)'), 0, 300, (v) => draft.coins = v ?? 0),
      AppSpace.gapSm,
      _num('games.wiz.level_no', draft.levelNo, t('رقم المستوى (فارغ = في النهاية)', 'Level number (empty = at the end)'), 1, 100000, (v) => draft.levelNo = v),
    ]);
  }

  Widget _settings(BuildContext context) {
    final fixed = _tpl?.fixedSettings ?? false;
    final sacred = _subject?.sacred ?? false;
    final s = draft.settings;
    final penalty = '${s['penalty'] ?? 'soft'}';
    int? n(String k) => s[k] is num ? (s[k] as num).toInt() : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (fixed) ...[
        AppBanner(
          icon: Icons.info_outline_rounded,
          text: t('الوقت والأرواح والعقوبة ثابتة في هذه اللعبة: لا مؤقت ولا خسارة.', 'Timer, lives and penalty are fixed in this game: no timer and nothing to lose.'),
        ),
        AppSpace.gapSm,
      ],
      if (sacred) ...[
        AppBanner(
          icon: Icons.lock_rounded,
          text: t('نص مقدّس: لا تُخصم أرواح، ولا مكافأة وقت، والأجواء هادئة.', 'Sacred text: no lives are lost, no time bonus, and the mood is calm.'),
          color: appToneColor(context, AppTone.gold),
        ),
        AppSpace.gapSm,
      ],
      if (!fixed) ...[
        AppNumberField(
          key: const ValueKey('games.wiz.timer'),
          initialValue: n('timer_s'),
          label: t('المؤقت بالثواني (0 = بلا مؤقت)', 'Timer in seconds (0 = no timer)'),
          min: 0,
          max: 900,
          step: 10,
          onChanged: (v) {
            s['timer_s'] = v?.toInt() ?? 0;
            onChanged();
          },
        ),
        AppSpace.gapSm,
        AppNumberField(
          key: const ValueKey('games.wiz.lives'),
          initialValue: n('lives'),
          label: t('الأرواح (0 = بلا حدّ)', 'Lives (0 = unlimited)'),
          min: 0,
          max: 9,
          onChanged: (v) {
            s['lives'] = v?.toInt() ?? 0;
            onChanged();
          },
        ),
        AppSpace.gapSm,
        AppDropdown<String>(
          key: const ValueKey('games.wiz.penalty'),
          value: sacred && penalty == 'lives' ? 'soft' : penalty,
          decoration: InputDecoration(labelText: t('عند الخطأ', 'On a wrong answer')),
          items: [
            DropdownMenuItem(value: 'none', child: Text(t('بلا عقوبة', 'No penalty'))),
            DropdownMenuItem(value: 'soft', child: Text(t('خصم خفيف', 'Soft penalty'))),
            if (!sacred) DropdownMenuItem(value: 'lives', child: Text(t('تُخصم روح', 'Lose a life'))),
          ],
          onChanged: (v) {
            s['penalty'] = v ?? 'soft';
            onChanged();
          },
        ),
        AppSpace.gapSm,
      ],
      AppNumberField(
        key: const ValueKey('games.wiz.speed'),
        initialValue: n('speed') ?? 3,
        label: t('السرعة (1 بطيء، 5 سريع)', 'Speed (1 slow, 5 fast)'),
        min: 1,
        max: 5,
        onChanged: (v) {
          s['speed'] = v?.toInt() ?? 3;
          onChanged();
        },
      ),
      AppSpace.gapSm,
      AppDropdown<String>(
        key: const ValueKey('games.wiz.theme'),
        value: '${s['theme'] ?? 'auto'}',
        decoration: InputDecoration(labelText: t('الشكل', 'Theme')),
        items: [
          DropdownMenuItem(value: 'auto', child: Text(t('حسب عمر اللاعب', 'By the player\'s age'))),
          DropdownMenuItem(value: 'kids', child: Text(t('أطفال', 'Kids'))),
          DropdownMenuItem(value: 'teen', child: Text(t('مراهقون', 'Teens'))),
          DropdownMenuItem(value: 'adult', child: Text(t('كبار', 'Adults'))),
        ],
        onChanged: (v) {
          s['theme'] = v ?? 'auto';
          onChanged();
        },
      ),
      AppSwitchTile(
        key: const ValueKey('games.wiz.music'),
        title: t('الموسيقى', 'Music'),
        icon: Icons.music_note_rounded,
        value: s['music'] != false && !sacred,
        onChanged: sacred
            ? null
            : (v) {
                s['music'] = v;
                onChanged();
              },
      ),
    ]);
  }
}

/// Step 5: try the level in the app, then publish. Plain values (the session is the wizard's).
class PreviewPanel extends StatelessWidget {
  const PreviewPanel({
    super.key,
    required this.engine,
    this.session,
    this.round = 0,
    this.unapproved = 0,
    this.done,
    this.error,
    this.busy = false,
    this.onStart,
  });

  final GameSession? session;
  final int round;
  final String engine;
  final int unapproved;
  final ({int score, int max})? done;
  final String? error;
  final bool busy;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(t('جرّب المستوى قبل النشر', 'Try the level before you publish')),
      Text(
        t('تُلعب الجولة بالقالب الحقيقي دون تسجيل أي نتيجة. المستوى يبقى مسودة حتى تنشره.',
            'The round is played with the real game and nothing is recorded. The level stays a draft until you publish it.'),
        style: AppType.meta(context).copyWith(color: c.textMedium),
      ),
      AppSpace.gapSm,
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.secondary(
          key: const ValueKey('games.wiz.preview'),
          label: session == null ? t('احفظ وجرّب', 'Save and try') : t('جرّب من جديد', 'Try again'),
          icon: Icons.play_arrow_rounded,
          onPressed: busy ? null : onStart,
        ),
      ),
      if (error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: appToneColor(context, AppTone.danger)),
      ],
      if (unapproved > 0) ...[
        AppSpace.gapSm,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppStatusBadge(
            key: const ValueKey('games.wiz.unapproved'),
            label: t('$unapproved سؤال غير معتمد بعد', '$unapproved questions not approved yet'),
            icon: Icons.rule_rounded,
            tone: AppTone.warning,
          ),
        ),
        AppSpace.gapXs,
        Text(t('لن تظهر للاعبين حتى تُعتمد.', 'Players will not get them until they are approved.'), style: AppType.meta(context).copyWith(color: c.textMedium)),
      ],
      if (done != null) ...[
        AppSpace.gapSm,
        AppBanner(
          key: const ValueKey('games.wiz.done'),
          icon: Icons.check_circle_rounded,
          text: t('انتهت التجربة: ${done!.score} من ${done!.max}', 'Try-out finished: ${done!.score} of ${done!.max}'),
          color: appToneColor(context, AppTone.success),
        ),
      ],
      if (session != null && done == null) ...[
        AppSpace.gapSm,
        SizedBox(
          height: 520,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.block),
            child: GamePlayView(
              key: ValueKey('games.wiz.play.$round'),
              game: GameSummary(id: 0, key: 'preview', engine: engine, titleAr: '', titleEn: ''),
              round: round,
              v4Session: session,
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Pick questions from the bank: search, tick, done. Pops the ticked ids in the order they were ticked.
class BankPickerSheet extends StatefulWidget {
  const BankPickerSheet({super.key, required this.api, required this.subjectId, this.selected = const []});

  final ItemsV4Api api;
  final int? subjectId;
  final List<int> selected;

  @override
  State<BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<BankPickerSheet> {
  final _q = TextEditingController();
  late final List<int> _picked = [...widget.selected];
  List<Json>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _error = null);
    try {
      final p = await widget.api.items(subjectId: widget.subjectId, status: 'approved', q: _q.text, limit: 50);
      if (mounted) setState(() => _items = p.items);
    } catch (e) {
      if (mounted) setState(() => _error = itemErrorText(e));
    }
  }

  String _label(Json it) {
    final p = it['prompt'];
    final m = p is Map ? p : const {};
    final s = '${m['ar'] ?? ''}'.isNotEmpty ? '${m['ar']}' : '${m['en'] ?? ''}';
    return s.isEmpty ? '#${it['id']}' : s;
  }

  @override
  Widget build(BuildContext context) {
    final l = _items;
    return AppSheetContent(
      title: t('اختر الأسئلة', 'Pick the questions'),
      subtitle: t('${_picked.length} مختار · الأسئلة المعتمدة فقط', '${_picked.length} picked · approved questions only'),
      icon: Icons.library_add_check_rounded,
      children: [
        AppField(
          key: const ValueKey('games.wiz.bank.q'),
          controller: _q,
          label: t('بحث', 'Search'),
          icon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
        ),
        AppSpace.gapSm,
        if (_error != null)
          AppErrorState(message: _error, onRetry: _search)
        else if (l == null)
          const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
        else if (l.isEmpty)
          AppEmpty(
              icon: Icons.search_off_rounded,
              title: t('لا أسئلة معتمدة', 'No approved questions'),
              message: t('غيّر البحث أو اعتمد أسئلة في المراجعة.', 'Change the search or approve questions in the review.'))
        else
          for (final it in l)
            AppSwitchTile(
              key: ValueKey('games.wiz.bank.${it['id']}'),
              title: _label(it),
              subtitle: itemTypeName('${it['type']}'),
              dense: true,
              value: _picked.contains(it['id']),
              onChanged: (v) => setState(() {
                final id = (it['id'] as num).toInt();
                v ? _picked.add(id) : _picked.remove(id);
              }),
            ),
        AppSpace.gapMd,
        AppButton.primary(
          key: const ValueKey('games.wiz.bank.done'),
          label: t('تم', 'Done'),
          icon: Icons.check_rounded,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_picked),
        ),
      ],
    );
  }
}
