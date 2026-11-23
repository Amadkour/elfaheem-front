// lib/features/games/admin/v4/breaks_page.dart — SUPER ADMIN: "Breaks & parents" (Games v4 T71, CONTRACT §8, §10).
// The platform's `games` module settings, through the existing module-settings API (GET / PUT
// /api/v1/admin/module-settings/games): Play now, break reminders, study minutes before a reminder, the longest
// break, and the parent summary. The PUT replaces the platform row's values, so the page sends the row it loaded with
// these five keys changed.
//
//   GamesBreaksPage   loads and saves
//   GamesBreaksBody   plain values: the form
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/admin/modules/module_settings_api.dart';

const List<String> kBreaksKeys = ['play_now', 'break_reminders', 'study_minutes', 'break_max_minutes', 'parent_summary'];

class GamesBreaksPage extends StatefulWidget {
  const GamesBreaksPage({super.key, this.api});
  final ModuleSettingsApi? api;

  @override
  State<GamesBreaksPage> createState() => _GamesBreaksPageState();
}

class _GamesBreaksPageState extends State<GamesBreaksPage> {
  late final ModuleSettingsApi _api = widget.api ?? const ModuleSettingsApi();
  ModuleView? _view;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.load('games', 'platform', null);
    if (!mounted) return;
    setState(() {
      _view = r.value ?? _view;
      _error = r.ok ? null : r.error;
    });
  }

  Future<void> _save(Map<String, dynamic> five) async {
    final v = _view;
    if (v == null) return;
    setState(() => _saving = true);
    final r = await _api.save('games', 'platform', null, {...v.values, ...five});
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r.value != null) _view = r.value;
    });
    if (r.ok) {
      showAppNotice(t('تم الحفظ', 'Saved'));
    } else {
      showAppNotice(r.error ?? '', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _view;
    return AdminPage(
      title: t('الاستراحات وأولياء الأمور', 'Breaks & parents'),
      subtitle: t('اللعب الآن وتذكير الاستراحة وملخص ولي الأمر', 'Play now, break reminders and the parent summary'),
      icon: Icons.self_improvement_rounded,
      onRefresh: _load,
      width: AppWidth.reading,
      body: _error != null && v == null
          ? AppErrorState(message: _error!, onRetry: _load)
          : v == null
              ? const AppListSkeleton(items: 4)
              : GamesBreaksBody(key: ValueKey(v.updatedAt), values: v.effective, saving: _saving, onSave: _save),
    );
  }
}

class GamesBreaksBody extends StatefulWidget {
  const GamesBreaksBody({super.key, required this.values, this.saving = false, this.onSave});
  final Map<String, dynamic> values;
  final bool saving;
  final ValueChanged<Map<String, dynamic>>? onSave;

  @override
  State<GamesBreaksBody> createState() => _GamesBreaksBodyState();
}

class _GamesBreaksBodyState extends State<GamesBreaksBody> {
  late bool _playNow = widget.values['play_now'] != false;
  late bool _reminders = widget.values['break_reminders'] != false;
  late bool _parent = widget.values['parent_summary'] != false;
  late final _study = TextEditingController(text: '${widget.values['study_minutes'] ?? 45}');
  late final _breakMax = TextEditingController(text: '${widget.values['break_max_minutes'] ?? 10}');

  @override
  void dispose() {
    _study.dispose();
    _breakMax.dispose();
    super.dispose();
  }

  int _clamp(TextEditingController c, int lo, int hi, int d) => (int.tryParse(c.text.trim()) ?? d).clamp(lo, hi);

  @override
  Widget build(BuildContext context) => ListView(padding: AdminPage.bodyPadding(context), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSwitchTile(
              title: t('زر «العب الآن»', 'The "Play now" button'),
              subtitle: t('يقترح على الطالب لعبة قصيرة تناسب سنّه ودورته.', 'Suggests a short game that fits the learner\'s age and course.'),
              icon: Icons.play_circle_rounded,
              value: _playNow,
              onChanged: (v) => setState(() => _playNow = v),
            ),
            AppSwitchTile(
              title: t('تذكير بالاستراحة', 'Break reminders'),
              subtitle: t('بعد وقت مذاكرة معيّن يذكّر الطالب باستراحة بلعبة.', 'After a set study time, reminds the learner to take a game break.'),
              icon: Icons.notifications_active_rounded,
              value: _reminders,
              onChanged: (v) => setState(() => _reminders = v),
            ),
            if (_reminders) ...[
              AppSpace.gapSm,
              AppNumberField(
                key: const ValueKey('games.breaks.study'),
                controller: _study,
                label: t('دقائق المذاكرة قبل التذكير (10 إلى 180)', 'Study minutes before a reminder (10 to 180)'),
                min: 10,
                max: 180,
              ),
              AppSpace.gapSm,
              AppNumberField(
                key: const ValueKey('games.breaks.max'),
                controller: _breakMax,
                label: t('أطول استراحة بالدقائق (3 إلى 30)', 'Longest break in minutes (3 to 30)'),
                min: 3,
                max: 30,
              ),
            ],
            AppSwitchTile(
              title: t('ملخص اللعب لولي الأمر', 'Parent summary'),
              subtitle: t('يرى ولي الأمر دقائق لعب ابنه وما أنهاه، ولا يرى تفاصيل الألعاب.', 'Parents see their child\'s minutes and finished games, not the game details.'),
              icon: Icons.family_restroom_rounded,
              value: _parent,
              onChanged: (v) => setState(() => _parent = v),
            ),
          ]),
        ),
        AppSpace.gapLg,
        AppButton.primary(
          key: const ValueKey('games.breaks.save'),
          label: t('حفظ', 'Save'),
          icon: Icons.check_rounded,
          expand: true,
          busy: widget.saving,
          onPressed: widget.saving
              ? null
              : () => widget.onSave?.call({
                    'play_now': _playNow,
                    'break_reminders': _reminders,
                    'parent_summary': _parent,
                    'study_minutes': _clamp(_study, 10, 180, 45),
                    'break_max_minutes': _clamp(_breakMax, 3, 30, 10),
                  }),
        ),
      ]);
}
