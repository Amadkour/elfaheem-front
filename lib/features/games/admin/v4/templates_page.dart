// lib/features/games/admin/v4/templates_page.dart — SUPER ADMIN: the game templates (Games v4, T64). One card per
// template with an on / off switch; a tap opens its defaults sheet: timer, lives, speed, penalty, theme, music, age
// range and the subjects it hides. A template that cannot hold sacred texts says so; the growing tree's timer, lives and
// penalty are fixed by the game (CONTRACT §2) and shown as such. Kill switch `admin.games_content`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/hub_api.dart';

class GamesTemplatesPage extends StatefulWidget {
  const GamesTemplatesPage({super.key, this.api});

  final GamesV4AdminApi? api;

  @override
  State<GamesTemplatesPage> createState() => _GamesTemplatesPageState();
}

class _GamesTemplatesPageState extends State<GamesTemplatesPage> {
  late final GamesV4AdminApi _api = widget.api ?? GamesV4AdminApi();
  List<GameTemplateRow>? _templates;
  List<GameSubjectRow> _subjects = const [];
  String? _error;
  DateTime? _loadedAt;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    _api.subjects().then((s) {
      if (mounted) setState(() => _subjects = s);
    }).catchError((_) {});
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.templates();
      if (!mounted) return;
      setState(() {
        _templates = r;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = gamesV4ErrorText(e));
    }
  }

  void _replace(GameTemplateRow r) {
    final list = [...?_templates];
    final i = list.indexWhere((x) => x.key == r.key);
    if (i >= 0) list[i] = r;
    setState(() => _templates = list);
  }

  Future<void> _toggle(GameTemplateRow tpl, bool on) async {
    setState(() => _busy.add(tpl.key));
    try {
      _replace(await _api.updateTemplate(tpl.key, {'enabled': on}));
      showAppNotice(on ? t('شُغّلت اللعبة', 'Game switched on') : t('أُوقفت اللعبة', 'Game switched off'));
    } catch (e) {
      showAppNotice(gamesV4ErrorText(e), error: true);
    }
    if (mounted) setState(() => _busy.remove(tpl.key));
  }

  Future<void> _edit(GameTemplateRow tpl) async {
    final body = await showAppSheet<Map<String, dynamic>>(
      context,
      (ctx) => TemplateDefaultsSheet(template: tpl, subjects: _subjects),
    );
    if (body == null) return;
    try {
      _replace(await _api.updateTemplate(tpl.key, body));
      showAppNotice(t('حُفظت الإعدادات', 'Settings saved'));
    } catch (e) {
      showAppNotice(gamesV4ErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      width: AppWidth.content,
      title: t('قوالب الألعاب', 'Game templates'),
      subtitle: t('شغّل أو أوقف كل لعبة، واضغط عليها لضبط إعداداتها الافتراضية.',
          'Switch each game on or off, and tap it to set its defaults.'),
      icon: Icons.dashboard_customize_rounded,
      onRefresh: _load,
      updatedAt: _loadedAt,
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: GamesTemplatesBody(templates: _templates, error: _error, busy: _busy, onRetry: _load, onToggle: _toggle, onEdit: _edit),
      ),
    );
  }
}

/// The templates over plain values.
class GamesTemplatesBody extends StatelessWidget {
  const GamesTemplatesBody({super.key, required this.templates, this.error, this.busy = const {}, this.onRetry, this.onToggle, this.onEdit});

  /// Null: loading.
  final List<GameTemplateRow>? templates;
  final String? error;
  final Set<String> busy;
  final VoidCallback? onRetry;
  final void Function(GameTemplateRow tpl, bool on)? onToggle;
  final ValueChanged<GameTemplateRow>? onEdit;

  @override
  Widget build(BuildContext context) {
    final l = templates;
    if (error != null && l == null) return AppErrorState(message: error, onRetry: onRetry);
    if (l == null) return const AppListSkeleton(items: 5, padding: EdgeInsets.zero);
    if (l.isEmpty) {
      return AppEmpty(icon: Icons.dashboard_customize_rounded, title: t('لا قوالب', 'No templates'));
    }
    return ListView.builder(
      key: const ValueKey('games.templates.list'),
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      itemCount: l.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: TemplateCard(
          key: ValueKey('games.template.${l[i].key}'),
          template: l[i],
          busy: busy.contains(l[i].key),
          onToggle: onToggle == null ? null : (v) => onToggle!(l[i], v),
          onTap: onEdit == null ? null : () => onEdit!(l[i]),
        ),
      ),
    );
  }
}

class TemplateCard extends StatelessWidget {
  const TemplateCard({super.key, required this.template, this.busy = false, this.onToggle, this.onTap});

  final GameTemplateRow template;
  final bool busy;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tpl = template;
    return AppCard(
      onTap: onTap,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tpl.name, style: AppType.row(context).copyWith(color: c.textDark)),
            AppSpace.gapXs,
            Text(
              t('${tpl.levels} مستوى', '${tpl.levels} levels'),
              style: AppType.meta(context).copyWith(color: c.textMedium),
            ),
            if (!tpl.sacredAllowed || !tpl.enabled) ...[
              AppSpace.gapXs,
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                if (!tpl.sacredAllowed)
                  AppStatusBadge(
                    label: t('لا تُستخدم مع القرآن والحديث', 'Not for Quran and Hadith'),
                    icon: Icons.lock_rounded,
                    tone: AppTone.gold,
                    dense: true,
                  ),
                if (!tpl.enabled) AppStatusBadge(label: t('متوقفة', 'Off'), dense: true),
              ]),
            ],
          ]),
        ),
        AppSpace.gapSm,
        AppSwitch(
          value: tpl.enabled,
          semanticLabel: tpl.name,
          onChanged: busy ? null : onToggle,
        ),
      ]),
    );
  }
}

/// The defaults of one template. Pops the PUT body (every value as typed; an empty age is null).
class TemplateDefaultsSheet extends StatefulWidget {
  const TemplateDefaultsSheet({super.key, required this.template, this.subjects = const []});

  final GameTemplateRow template;
  final List<GameSubjectRow> subjects;

  @override
  State<TemplateDefaultsSheet> createState() => _TemplateDefaultsSheetState();
}

class _TemplateDefaultsSheetState extends State<TemplateDefaultsSheet> {
  late int? _timer = _int('timer_s');
  late int? _lives = _int('lives');
  late int? _speed = _int('speed');
  late String _penalty = '${widget.template.setting('penalty') ?? 'soft'}';
  late String _theme = '${widget.template.setting('theme') ?? 'auto'}';
  late bool _music = widget.template.setting('music') != false;
  late int? _ageMin = widget.template.ageMin;
  late int? _ageMax = widget.template.ageMax;
  late final Set<int> _hidden = {...widget.template.hiddenSubjectIds};

  int? _int(String k) {
    final v = widget.template.setting(k);
    return v is num ? v.toInt() : null;
  }

  Map<String, dynamic> _body() => {
        'defaults': {
          if (!widget.template.fixedSettings) ...{
            if (_timer != null) 'timer_s': _timer,
            if (_lives != null) 'lives': _lives,
            'penalty': _penalty,
          },
          if (_speed != null) 'speed': _speed,
          'theme': _theme,
          'music': _music,
        },
        'age_min': _ageMin,
        'age_max': _ageMax,
        'hidden_subject_ids': _hidden.toList()..sort(),
      };

  @override
  Widget build(BuildContext context) {
    final tpl = widget.template;
    final fixed = tpl.fixedSettings;
    return AppSheetContent(
      title: tpl.name,
      subtitle: t('الإعدادات الافتراضية لكل مستوى جديد', 'Defaults for every new level'),
      icon: Icons.tune_rounded,
      children: [
        if (!tpl.sacredAllowed) ...[
          AppBanner(
            icon: Icons.lock_rounded,
            text: t('هذه اللعبة لا تُستخدم مع نصوص القرآن والحديث.', 'This game is never used with Quran or Hadith texts.'),
            color: appToneColor(context, AppTone.gold),
          ),
          AppSpace.gapSm,
        ],
        if (fixed) ...[
          AppBanner(
            icon: Icons.info_outline_rounded,
            text: t('الوقت والأرواح والعقوبة ثابتة في هذه اللعبة: لا مؤقت ولا خسارة.',
                'Timer, lives and penalty are fixed in this game: no timer and nothing to lose.'),
          ),
          AppSpace.gapSm,
        ] else ...[
          AppNumberField(
            key: const ValueKey('games.tpl.timer'),
            initialValue: _timer,
            label: t('المؤقت بالثواني (0 = بلا مؤقت)', 'Timer in seconds (0 = no timer)'),
            min: 0,
            max: 900,
            step: 10,
            onChanged: (v) => _timer = v?.toInt(),
          ),
          AppSpace.gapSm,
          AppNumberField(
            key: const ValueKey('games.tpl.lives'),
            initialValue: _lives,
            label: t('الأرواح (0 = بلا حدّ)', 'Lives (0 = unlimited)'),
            min: 0,
            max: 9,
            onChanged: (v) => _lives = v?.toInt(),
          ),
          AppSpace.gapSm,
          AppDropdown<String>(
            key: const ValueKey('games.tpl.penalty'),
            value: _penalty,
            decoration: InputDecoration(labelText: t('عند الخطأ', 'On a wrong answer')),
            items: [
              DropdownMenuItem(value: 'none', child: Text(t('بلا عقوبة', 'No penalty'))),
              DropdownMenuItem(value: 'soft', child: Text(t('خصم خفيف', 'Soft penalty'))),
              DropdownMenuItem(value: 'lives', child: Text(t('تُخصم روح', 'Lose a life'))),
            ],
            onChanged: (v) => setState(() => _penalty = v ?? _penalty),
          ),
          AppSpace.gapSm,
        ],
        AppNumberField(
          key: const ValueKey('games.tpl.speed'),
          initialValue: _speed,
          label: t('السرعة (1 بطيء، 5 سريع)', 'Speed (1 slow, 5 fast)'),
          min: 1,
          max: 5,
          onChanged: (v) => _speed = v?.toInt(),
        ),
        AppSpace.gapSm,
        AppDropdown<String>(
          key: const ValueKey('games.tpl.theme'),
          value: _theme,
          decoration: InputDecoration(labelText: t('الشكل', 'Theme')),
          items: [
            DropdownMenuItem(value: 'auto', child: Text(t('حسب عمر اللاعب', 'By the player\'s age'))),
            DropdownMenuItem(value: 'kids', child: Text(t('أطفال', 'Kids'))),
            DropdownMenuItem(value: 'teen', child: Text(t('مراهقون', 'Teens'))),
            DropdownMenuItem(value: 'adult', child: Text(t('كبار', 'Adults'))),
          ],
          onChanged: (v) => setState(() => _theme = v ?? _theme),
        ),
        AppSwitchTile(
          key: const ValueKey('games.tpl.music'),
          title: t('الموسيقى', 'Music'),
          icon: Icons.music_note_rounded,
          value: _music,
          onChanged: (v) => setState(() => _music = v),
        ),
        AppSpace.gapSm,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AppNumberField(
              key: const ValueKey('games.tpl.age_min'),
              initialValue: _ageMin,
              label: t('من عمر', 'Age from'),
              min: 4,
              max: 99,
              onChanged: (v) => _ageMin = v?.toInt(),
            ),
          ),
          AppSpace.gapSm,
          Expanded(
            child: AppNumberField(
              key: const ValueKey('games.tpl.age_max'),
              initialValue: _ageMax,
              label: t('إلى عمر', 'Age to'),
              min: 4,
              max: 99,
              onChanged: (v) => _ageMax = v?.toInt(),
            ),
          ),
        ]),
        if (widget.subjects.isNotEmpty) ...[
          AppSectionTitle(t('مواد تُخفى عن هذه اللعبة', 'Subjects hidden from this game')),
          for (final s in widget.subjects)
            AppSwitchTile(
              key: ValueKey('games.tpl.hide.${s.id}'),
              title: s.name,
              value: _hidden.contains(s.id),
              dense: true,
              onChanged: (v) => setState(() => v ? _hidden.add(s.id) : _hidden.remove(s.id)),
            ),
        ],
        AppSpace.gapMd,
        AppButton.primary(
          key: const ValueKey('games.tpl.save'),
          label: t('حفظ', 'Save'),
          icon: Icons.check_rounded,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_body()),
        ),
      ],
    );
  }
}
