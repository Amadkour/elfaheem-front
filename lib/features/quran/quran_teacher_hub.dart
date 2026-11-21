// lib/features/quran/quran_teacher_hub.dart — the teacher's Quran page (Learning Hub Phase 6, D-1347), opened from
// Profile › "My Quran teaching":
//
//   QuranTeacherHubPage   GET /api/v1/me/quran/teacher-profile (+ /quran/meta, /edu/countries): the card editor
//                         (PUT, kill switch `quran.teacher_apply`), the record sheet over the teacher's quran
//                         programs, and each program's students → that student's progress
//   QuranCardForm         the editor with plain values (test/ui/quran_layout_test.dart): gender, introduction,
//                         ijazah, goals, session types, country; "Publish" / "Save as draft"
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredCourseForm;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/quran/quran_api.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:flutter_education_app/features/quran/quran_progress.dart';
import 'package:flutter_education_app/features/quran/quran_record_sheet.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// The values the editor sends.
typedef QuranCardDraft = ({
  String gender,
  String bio,
  String ijazah,
  List<String> goals,
  List<String> sessionTypes,
  String? countryCode,
  bool publish,
});

String quranStatusLabel(String? s) => switch (s) {
      'published' => t('منشورة', 'Published'),
      'pending' => t('بانتظار المراجعة', 'Waiting for review'),
      'draft' => t('مسودة', 'Draft'),
      _ => t('لم تُنشأ بعد', 'Not created yet'),
    };

AppTone _statusTone(String? s) => switch (s) {
      'published' => AppTone.success,
      'pending' => AppTone.warning,
      _ => AppTone.neutral,
    };

class QuranTeacherHubPage extends StatefulWidget {
  const QuranTeacherHubPage({super.key, this.api});

  final QuranApi? api;

  @override
  State<QuranTeacherHubPage> createState() => _QuranTeacherHubPageState();
}

class _QuranTeacherHubPageState extends State<QuranTeacherHubPage> {
  late final QuranApi _api = widget.api ?? QuranApi();
  QuranTeacher? _card;
  QuranMeta? _meta;
  List<(String, String)> _countries = const [];
  bool _loading = true, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      QuranOutbox.flush(_api).then((r) {
        if (r.sent > 0) showAppNotice(t('أُرسلت التسجيلات المحفوظة على الجهاز', 'The entries kept on this device were sent'));
        for (final x in r.refused) {
          showAppNotice(x, error: true);
        }
      });
      final card = _api.myCard(), meta = _api.meta(), countries = _api.countries();
      final c = await card, m = await meta, l = await countries;
      if (!mounted) return;
      setState(() {
        _card = c;
        _meta = m;
        _countries = l;
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

  Future<String?> _save(QuranCardDraft d) async {
    setState(() => _saving = true);
    try {
      final r = await _api.saveCard(
        gender: d.gender,
        bio: d.bio,
        ijazah: d.ijazah,
        goals: d.goals,
        sessionTypes: d.sessionTypes,
        countryCode: d.countryCode,
        publish: d.publish,
      );
      if (!mounted) return null;
      setState(() {
        _card = r;
        _saving = false;
      });
      showAppNotice(switch (r.status) {
        'published' => t('نُشرت بطاقتك: يراها الطلاب الآن', 'Your card is published: students can see it now'),
        'pending' => t('أُرسلت بطاقتك للمراجعة', 'Your card was sent for review'),
        _ => t('حُفظت المسودة', 'Draft saved'),
      });
      return null;
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      return quranErrorText(e);
    }
  }

  Future<void> _record() async {
    final m = _meta, c = _card;
    if (m == null || c == null) return;
    await showQuranRecordSheet(context, meta: m, api: _api, courses: c.courses);
  }

  Future<void> _students(QuranCourse p) async {
    final m = _meta;
    if (m == null) return;
    final picked = await showAppSheet<QuranStudentRef>(
      context,
      (_) => AppSheetContent(
        title: p.name,
        icon: Icons.groups_rounded,
        children: [_StudentList(load: () => _api.courseStudents(p.id))],
      ),
    );
    if (picked == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: RouteSettings(name: '/quran/students/${picked.id}'),
      builder: (_) => QuranProgressPage.student(studentId: picked.id, name: picked.name, api: _api),
    ));
  }

  /// Opens the course form with the program type preset to a Quran program (D-1343).
  Widget _addProgramButton() => AppButton(
        key: const ValueKey('quran.hub.add_program'),
        label: t('أضف برنامج قرآن', 'Add a Quran program'),
        icon: Icons.add_rounded,
        onPressed: _addProgram,
      );

  Future<void> _addProgram() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredCourseForm(programKind: 'quran')));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _card;
    return BasePage(
      width: AppWidth.form,
      appBar: ScreenAppBar(title: t('تعليم القرآن', 'My Quran teaching')),
      child: SafeArea(
        child: c == null
            ? (_loading ? const AppListSkeleton(items: 4) : AppErrorState(message: _error, onRetry: _load))
            : AppRefresh(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
                  QuranCardForm(
                    initial: c,
                    countries: _countries,
                    saving: _saving,
                    locked: quranTeacherApplyOff(),
                    onSave: _save,
                  ),
                  AppSection(
                    title: t('برامجي', 'My programs'),
                    subtitle: t('برامج القرآن دورات: الحجز والدفع والجلسات من صفحة الدورة.',
                        'Quran programs are courses: booking, payment and sessions live on the course page.'),
                    trailing: c.courses.isEmpty || _meta == null
                        ? null
                        : AppButton(
                            key: const ValueKey('quran.hub.record'),
                            label: t('سجل التسميع', 'Record sheet'),
                            icon: Icons.edit_note_rounded,
                            size: AppButtonSize.sm,
                            onPressed: _record,
                          ),
                    child: c.courses.isEmpty
                        ? AppEmpty(
                            icon: Icons.event_note_rounded,
                            title: t('لا برامج قرآن منشورة بعد', 'No published Quran programs yet'),
                            message: t('أضف برنامج قرآن: هو كورس نوعه "برنامج تحفيظ قرآن"، وبعد نشره يظهر هنا مع طلابه.',
                                'Add a Quran program: a course of the type "Quran program". Once published it shows here with its students.'),
                            actionLabel: t('أضف برنامج قرآن', 'Add a Quran program'),
                            onAction: _addProgram,
                          )
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _addProgramButton(),
                            const SizedBox(height: AppSpace.sm),
                            for (final p in c.courses) ...[
                              AppActionCard(
                                key: ValueKey('quran.hub.program.${p.id}'),
                                icon: Icons.menu_book_rounded,
                                title: p.name,
                                subtitle: t('الطلاب وتقدّمهم', 'Students and their progress'),
                                onTap: () => _students(p),
                              ),
                              const SizedBox(height: AppSpace.sm),
                            ],
                          ]),
                  ),
                  const SizedBox(height: AppSpace.lg),
                ]),
              ),
      ),
    );
  }
}

class _StudentList extends StatefulWidget {
  const _StudentList({required this.load});

  final Future<List<QuranStudentRef>> Function() load;

  @override
  State<_StudentList> createState() => _StudentListState();
}

class _StudentListState extends State<_StudentList> {
  late final Future<List<QuranStudentRef>> _f = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<QuranStudentRef>>(
        future: _f,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) return const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
          if (s.hasError) return AppErrorState(message: quranErrorText(s.error!));
          final l = s.data ?? const [];
          if (l.isEmpty) {
            return AppEmpty(icon: Icons.groups_rounded, title: t('لا طلاب في هذا البرنامج بعد', 'No students in this program yet'));
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            for (final st in l)
              ListTile(
                key: ValueKey('quran.hub.student.${st.id}'),
                minTileHeight: AppTouch.min,
                leading: AppAvatar(name: st.name, url: st.imageUrl, size: AppTouch.min - AppSpace.xs),
                title: Text(st.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).pop(st),
              ),
          ]);
        },
      );
}

class QuranCardForm extends StatefulWidget {
  const QuranCardForm({
    super.key,
    required this.initial,
    required this.onSave,
    this.countries = const [],
    this.saving = false,
    this.locked = false,
  });

  final QuranTeacher initial;

  /// null = saved; else the refusal's text.
  final Future<String?> Function(QuranCardDraft draft) onSave;
  final List<(String, String)> countries;
  final bool saving;

  /// `quran.teacher_apply` is off: the card shows, the editor is read only.
  final bool locked;

  @override
  State<QuranCardForm> createState() => _QuranCardFormState();
}

class _QuranCardFormState extends State<QuranCardForm> {
  late String? _gender = widget.initial.gender;
  late final _bio = TextEditingController(text: widget.initial.bio);
  late final _ijazah = TextEditingController(text: widget.initial.ijazah ?? '');
  late Set<String> _goals = {...widget.initial.goals};
  late Set<String> _sessions = {...widget.initial.sessionTypes};
  late String? _country = widget.initial.countryCode;
  String? _error;

  @override
  void dispose() {
    _bio.dispose();
    _ijazah.dispose();
    super.dispose();
  }

  Future<void> _save(bool publish) async {
    if (_gender == null) {
      setState(() => _error = t('اختر: معلم أم معلمة', 'Choose: male or female teacher'));
      return;
    }
    if (publish && (_goals.isEmpty || _sessions.isEmpty)) {
      setState(() => _error = t('اختر هدفاً واحداً ونوع جلسة واحداً على الأقل قبل النشر',
          'Choose at least one goal and one session type before publishing'));
      return;
    }
    setState(() => _error = null);
    final r = await widget.onSave((
      gender: _gender!,
      bio: _bio.text.trim(),
      ijazah: _ijazah.text.trim(),
      goals: [for (final g in quranGoals) if (_goals.contains(g)) g],
      sessionTypes: [for (final s in quranSessionTypes) if (_sessions.contains(s)) s],
      countryCode: _country,
      publish: publish,
    ));
    if (mounted && r != null) setState(() => _error = r);
  }

  Widget _chips(String title, List<String> values, bool Function(String) on, String Function(String) label, void Function(String) toggle) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppFieldLabel(title),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final v in values)
            AppChoiceChip(
              key: ValueKey('quran.card.$v'),
              label: label(v),
              selected: on(v),
              onTap: widget.locked ? () {} : () => setState(() => toggle(v)),
            ),
        ]),
        const SizedBox(height: AppSpace.md),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = widget.initial;
    final countries = [
      ...widget.countries,
      if (_country != null && !widget.countries.any((e) => e.$1 == _country)) (_country!, _country!),
    ];
    return AppCard(
      highlight: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Text(t('بطاقتي كمعلم قرآن', 'My Quran teacher card'),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark)),
          ),
          const SizedBox(width: AppSpace.xs),
          AppStatusBadge(label: quranStatusLabel(card.status), tone: _statusTone(card.status), dense: true),
        ]),
        if (card.verified) ...[
          const SizedBox(height: AppSpace.xs),
          AppStatusBadge(label: t('موثّق من المنصة', 'Verified by the platform'), tone: AppTone.success, icon: Icons.verified_rounded, dense: true),
        ],
        const SizedBox(height: AppSpace.sm),
        Text(t('يراها الطلاب في تبويب القرآن بعد النشر. لا تُكتب آيات هنا: الأسماء والأعداد فقط.',
                'Students see it in the Quran tab once published. No Quran text here: names and numbers only.'),
            style: AppType.meta(context).copyWith(color: c.textMedium)),
        if (widget.locked) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.lock_outline_rounded, color: c.warning, text: t('تعديل البطاقة متوقف حالياً من إدارة المنصة', 'Editing the card is switched off by the platform right now')),
        ],
        const SizedBox(height: AppSpace.md),
        _chips(t('أنا', 'I am'), quranGenders, (v) => _gender == v, quranGenderLabel, (v) => _gender = v),
        if (card.verified) ...[
          Text(
            key: const ValueKey('quran.card.reverify'),
            t('تغيير الجنس أو الإجازة يحتاج توثيقاً جديداً من المنصة', 'Changing the gender or the ijazah needs a new verification by the platform'),
            style: AppType.meta(context).copyWith(color: c.textMedium),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        _chips(t('الأهداف', 'Goals'), quranGoals, _goals.contains, quranGoalLabel,
            (v) => _goals = _goals.contains(v) ? ({..._goals}..remove(v)) : {..._goals, v}),
        _chips(t('أنواع الجلسات', 'Session types'), quranSessionTypes, _sessions.contains, quranSessionLabel,
            (v) => _sessions = _sessions.contains(v) ? ({..._sessions}..remove(v)) : {..._sessions, v}),
        AppDropdown<String>(
          key: const ValueKey('quran.card.country'),
          decoration: InputDecoration(labelText: t('الدولة', 'Country')),
          enabled: !widget.locked,
          value: _country ?? '',
          items: [
            DropdownMenuItem(value: '', child: Text(t('غير محددة', 'Not set'), overflow: TextOverflow.ellipsis)),
            for (final e in countries) DropdownMenuItem(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _country = (v ?? '').isEmpty ? null : v),
        ),
        const SizedBox(height: AppSpace.sm),
        AppField(
          controller: _ijazah,
          label: t('الإجازة (اختياري)', 'Ijazah (optional)'),
          hint: t('مثال: إجازة برواية حفص عن عاصم', 'e.g. an ijazah in the Hafs narration'),
          maxLength: 300,
          enabled: !widget.locked,
        ),
        const SizedBox(height: AppSpace.sm),
        AppField(
          controller: _bio,
          label: t('نبذة عنك', 'About you'),
          hint: t('خبرتك وطريقتك في التحفيظ', 'Your experience and how you teach'),
          maxLines: 5,
          maxLength: 4000,
          enabled: !widget.locked,
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
        ],
        const SizedBox(height: AppSpace.md),
        AppButtonRow(
          primary: AppButton.primary(
            key: const ValueKey('quran.card.publish'),
            label: t('نشر البطاقة', 'Publish the card'),
            icon: Icons.public_rounded,
            busy: widget.saving,
            onPressed: widget.locked || widget.saving ? null : () => _save(true),
          ),
          secondary: [
            AppButton.secondary(
              key: const ValueKey('quran.card.draft'),
              label: t('حفظ كمسودة', 'Save as draft'),
              onPressed: widget.locked || widget.saving ? null : () => _save(false),
            ),
          ],
        ),
      ]),
    );
  }
}
