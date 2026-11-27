// lib/features/admin/modules/admin_modules_page.dart
//
// SUPER ADMIN: module switches (learning hub phase 6, D-1348), kill switch `admin.modules`.
//
//   AdminModulesPage     scope picker (platform · a country · an organization) → one card per module (store, games,
//                        quran, self_learning) built from the server's `fields`, each value with where it comes from (set here ·
//                        from the platform · the default) and "use inherited"; on a country, the student tab
//                        switches of that country. ONE Save writes every changed card.
//   ModuleSettingsCard   one module's fields over plain values (tested by the layout harness).
//   CountryTabsCard      the four student tab switches of a country over plain values.
//
// Resolution on the server: defaults ← platform ← country ← organization (the organization wins). The admin view
// of a country / an organization shows what it inherits from the platform row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/self_learning/admin/sl_admin_page.dart' show SlAdminPage;

import '../admin_common.dart' show ErrorRetry, t;
import '../admin_page.dart';
import 'module_settings_api.dart';
import 'package:flutter_education_app/features/quran/admin/quran_admin_page.dart' show QuranAdminPage;
import '../sup/sup_kit.dart';

// ── texts ────────────────────────────────────────────────────────────────────

(String, String) moduleTitle(String module) => switch (module) {
      'store' => (t('المتجر الرقمي', 'Digital store'),
          t('الكتب والملخصات: الدفع بالنقاط، بيع المعلمين، والتنزيلات', 'Books and summaries: points, teachers selling, downloads')),
      'games' => (t('الألعاب التعليمية', 'Learning games'), t('نقاط مكافأة اللعب وحدّها اليومي', 'Points for playing and their daily cap')),
      'quran' => (t('تحفيظ القرآن', 'Quran memorization'),
          t('قواعد المعلمين والحجز وتسجيل الحفظ', 'Rules for teachers, booking and logging memorization')),
      'self_learning' => (t('التعلّم الذاتي اليومي', 'Daily self-learning'),
          t('دروس قصيرة وأسئلة مراجعة تصل الطالب خلال اليوم', 'Short lessons and review questions delivered to students through the day')),
      _ => (module, ''),
    };

IconData moduleIcon(String module) => switch (module) {
      'store' => Icons.storefront_rounded,
      'games' => Icons.sports_esports_rounded,
      'quran' => Icons.menu_book_rounded,
      'self_learning' => Icons.auto_stories_rounded,
      _ => Icons.tune_rounded,
    };

/// (title, plain explanation) of a field.
(String, String) moduleFieldText(String module, String key) => switch ('$module.$key') {
      'store.points_enabled' => (t('الدفع بالنقاط', 'Pay with points'),
          t('يستطيع المشتري دفع ثمن عناصر المتجر من رصيد نقاطه.', 'Buyers can pay for store items from their points balance.')),
      'store.teacher_items' => (t('المعلمون يبيعون عناصرهم', 'Teachers sell their own items'),
          t('يضيف المعلم كتبه وملخصاته إلى المتجر ويبيعها.', 'Teachers add their own books and summaries to the store and sell them.')),
      'store.review_required' => (t('مراجعة عناصر المعلمين أولاً', 'Review teachers\' items first'),
          t('عند التشغيل ينتظر كل عنصر يرسله المعلم مراجعتك قبل أن يراه المشترون. عند الإيقاف يظهر بمجرد نشره.',
              'On: every item a teacher sends waits for your review before buyers see it. Off: it shows as soon as it is published.')),
      'store.download_daily_limit' => (t('التنزيلات في اليوم', 'Downloads per day'),
          t('أقصى عدد ملفات ينزّلها المشتري الواحد من مكتبته في اليوم.', 'The most files one buyer can download from their library in a day.')),
      'games.points_rewards' => (t('نقاط مقابل اللعب', 'Points for playing'),
          t('يكسب الطالب نقاطاً عن كل لعبة ينهيها بنجمة على الأقل (ويجب أن يكون مفتاح مكافآت الألعاب مفعّلاً).',
              'Students earn points for a game finished with at least one star (the games rewards switch must be on too).')),
      'games.points_daily_cap' => (t('حد النقاط اليومي', 'Daily points cap'),
          t('أقصى ما يكسبه الطالب الواحد من الألعاب في اليوم.', 'The most points one student can earn from games in a day.')),
      'quran.teacher_verification_required' => (t('المعلمون الموثَّقون فقط', 'Verified teachers only'),
          t('لا يظهر في القائمة ولا يُحجز إلا المعلم الذي وثّقته.', 'Only teachers you have verified are listed and can be booked.')),
      'quran.content_review_required' => (t('مراجعة بطاقات المعلمين', 'Review teacher cards'),
          t('تنتظر بطاقة المعلم التعريفية مراجعتك قبل نشرها.', 'A teacher\'s profile card waits for your review before it is published.')),
      'quran.gender_matching' => (t('جنس المعلم والطالب', 'Teacher and student gender'),
          t('هل يشترط أن يكون المعلم من جنس الطالب نفسه عند الحجز.', 'Whether a booking needs the teacher and the student to be of the same gender.')),
      'quran.self_log' => (t('الطالب يسجل حفظه بنفسه', 'Students log their own progress'),
          t('يسجل الطالب ما حفظه بنفسه. عند الإيقاف يسجله معلمه فقط.', 'Students record what they memorized themselves. Off: only their teacher records it.')),
      'self_learning.enabled' => (t('تشغيل التعلّم الذاتي', 'Self-learning on'),
          t('يصل الطلاب درس قصير أو سؤال مراجعة عدة مرات في اليوم.', 'Students get a short lesson or a review question a few times a day.')),
      'self_learning.subject_quran' => (t('مادة القرآن', 'Subject: Quran'), ''),
      'self_learning.subject_tajweed' => (t('مادة التجويد', 'Subject: Tajweed'), ''),
      'self_learning.subject_fiqh' => (t('مادة الفقه', 'Subject: Fiqh'), ''),
      'self_learning.subject_nahw' => (t('مادة النحو', 'Subject: Grammar'),
          t('المواد المفعّلة فقط تصل منها الدروس والأسئلة.', 'Lessons and questions come only from the subjects switched on.')),
      'self_learning.interval_minutes' => (t('الفاصل بين رسالتين', 'Time between two deliveries'),
          t('أقل وقت بين درس وآخر للطالب الواحد.', 'The shortest time between two deliveries to one student.')),
      'self_learning.daily_limit' => (t('الحد اليومي', 'Daily limit'),
          t('أقصى عدد دروس وأسئلة تصل الطالب في اليوم.', 'The most lessons and questions one student gets in a day.')),
      'self_learning.active_from_min' => (t('بداية أوقات النشاط', 'Active hours start'), t('بتوقيت مؤسسة الطالب، وإلا بتوقيت المنصة.', "In the student's organization's time zone, else the platform's.")),
      'self_learning.active_to_min' => (t('نهاية أوقات النشاط', 'Active hours end'), ''),
      'self_learning.quiet_from_min' => (t('بداية وقت الهدوء', 'Quiet hours start'),
          t('لا يصل شيء في وقت الهدوء، حتى داخل أوقات النشاط.', 'Nothing is delivered in quiet hours, even inside active hours.')),
      'self_learning.quiet_to_min' => (t('نهاية وقت الهدوء', 'Quiet hours end'), ''),
      'self_learning.student_can_toggle' => (t('الطالب يشغّلها ويوقفها', 'Students can switch it on and off'),
          t('يختار الطالب تشغيل الدروس اليومية وموادها. عند الإيقاف تديرها أنت فقط.',
              'Students choose whether they get daily lessons and from which subjects. Off: only you decide.')),
      'self_learning.notify' => (t('إشعار عند الوصول', 'Notify on delivery'),
          t('يصل الطالب إشعار مع كل درس أو سؤال.', 'Students get a notification with each lesson or question.')),
      _ => (key, ''),
    };

/// The self-learning interval choices (minutes).
const kSlIntervalChoices = [30, 60, 120, 180, 240, 360, 480, 720, 1440];

String slIntervalText(int m) => m % 60 == 0
    ? (m == 60 ? t('كل ساعة', 'Every hour') : t('كل ${m ~/ 60} ساعات', 'Every ${m ~/ 60} hours'))
    : t('كل $m دقيقة', 'Every $m minutes');

/// The self-learning fields drawn as a time of day: minutes after midnight in the student's zone (CONTRACT C7).
const _slTimeKeys = {'active_from_min', 'active_to_min', 'quiet_from_min', 'quiet_to_min'};

TimeOfDay? _timeOfMinutes(dynamic v) {
  final m = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  if (m == null || m < 0 || m >= 1440) return null;
  return TimeOfDay(hour: m ~/ 60, minute: m % 60);
}

String moduleChoiceText(String module, String key, String choice) => switch ('$module.$key.$choice') {
      'quran.gender_matching.off' => t('بلا شرط', 'No rule'),
      'quran.gender_matching.same' => t('الجنس نفسه فقط (يُرفض الحجز غير ذلك)', 'Same gender only (other bookings are refused)'),
      'quran.gender_matching.prefer' => t('تفضيل الجنس نفسه (يظهر أولاً)', 'Prefer the same gender (listed first)'),
      _ => choice,
    };

String countryTabText(String key) => switch (key) {
      'student_tab_store' => t('المتجر', 'Store'),
      'student_tab_games' => t('الألعاب', 'Games'),
      'student_tab_quran' => t('القرآن', 'Quran'),
      'student_tab_nahw' => t('النحو', 'Grammar (nahw)'),
      'student_tab_self_learning' => t('التعلّم الذاتي اليومي', 'Daily self-learning'),
      _ => key,
    };

/// Field order per module (unknown keys from the server follow). `review_required` sits right after `teacher_items`.
const _fieldOrder = {
  'store': ['points_enabled', 'teacher_items', 'review_required', 'download_daily_limit'],
  'games': ['points_rewards', 'points_daily_cap'],
  'quran': ['teacher_verification_required', 'content_review_required', 'gender_matching', 'self_log'],
  'self_learning': ['enabled', 'subject_quran', 'subject_tajweed', 'subject_fiqh', 'subject_nahw', 'interval_minutes', 'daily_limit',
    'active_from_min', 'active_to_min', 'quiet_from_min', 'quiet_to_min', 'student_can_toggle', 'notify'],
};

List<ModuleField> orderedFields(ModuleView v) {
  final order = _fieldOrder[v.module] ?? const <String>[];
  final byKey = {for (final f in v.fields) f.key: f};
  return [
    for (final k in order)
      if (byKey[k] != null) byKey[k]!,
    for (final f in v.fields)
      if (!order.contains(f.key)) f,
  ];
}

bool sameValues(Map<String, dynamic> a, Map<String, dynamic> b) =>
    a.length == b.length && a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);

String _valueText(String module, ModuleField f, dynamic v) {
  if (v is bool) return v ? t('مفعّل', 'On') : t('متوقف', 'Off');
  if (module == 'self_learning' && _slTimeKeys.contains(f.key) && v is num) return AppTime.clockMinutes(v.toInt());
  if (module == 'self_learning' && f.key == 'interval_minutes' && v is num) return slIntervalText(v.toInt());
  if (f.type == 'str') return moduleChoiceText(module, f.key, '$v');
  return '$v';
}

// ── the page ─────────────────────────────────────────────────────────────────

class AdminModulesPage extends StatefulWidget {
  const AdminModulesPage({super.key, this.api = const ModuleSettingsApi(), this.initialCountry});

  final ModuleSettingsApi api;

  /// Opens on this country's scope (a country code), else on the platform.
  final String? initialCountry;

  @override
  State<AdminModulesPage> createState() => _AdminModulesPageState();
}

class _AdminModulesPageState extends State<AdminModulesPage> {
  late int _scope = widget.initialCountry == null ? 0 : 1;
  late String? _country = widget.initialCountry;
  int? _orgId;
  List<ModuleCountry>? _countries;
  List<ModuleOrg>? _orgs;
  String? _pickerError;

  final Map<String, ModuleView> _views = {};
  final Map<String, Map<String, dynamic>> _drafts = {};
  final Map<String, String> _errors = {};
  bool _loading = false;
  bool _saving = false;
  DateTime? _loadedAt;
  int _rev = 0;
  int _gen = 0;
  List<String>? _tabsDraft;

  String get _scopeName => kModuleScopes[_scope];

  String? get _scopeKey => switch (_scopeName) {
        'country' => _country,
        'org' => _orgId?.toString(),
        _ => null,
      };

  bool get _ready => _scopeName == 'platform' || _scopeKey != null;

  ModuleCountry? get _countryRow {
    for (final c in _countries ?? const <ModuleCountry>[]) {
      if (c.code == _country) return c;
    }
    return null;
  }

  bool get _tabsDirty {
    final c = _countryRow;
    final d = _tabsDraft;
    if (c == null || d == null) return false;
    return {...c.disabled}.difference({...d}).isNotEmpty || {...d}.difference({...c.disabled}).isNotEmpty;
  }

  bool get _dirty =>
      _tabsDirty || _views.entries.any((e) => !sameValues(e.value.values, _drafts[e.key] ?? const {}));

  @override
  void initState() {
    super.initState();
    _loadPicker();
    _load();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    if (!_ready) {
      setState(() {
        _views.clear();
        _drafts.clear();
        _errors.clear();
      });
      return;
    }
    setState(() => _loading = true);
    final results = await Future.wait([for (final m in kModuleKeys) widget.api.load(m, _scopeName, _scopeKey)]);
    if (!mounted || gen != _gen) return;
    setState(() {
      _loading = false;
      _loadedAt = DateTime.now();
      _rev++;
      _views.clear();
      _drafts.clear();
      _errors.clear();
      for (var i = 0; i < kModuleKeys.length; i++) {
        final m = kModuleKeys[i];
        final r = results[i];
        if (r.ok && r.value != null) {
          _views[m] = r.value!;
          _drafts[m] = Map<String, dynamic>.from(r.value!.values);
        } else {
          _errors[m] = r.error ?? '';
        }
      }
      final c = _countryRow;
      _tabsDraft = c == null ? null : [...c.disabled];
    });
  }

  Future<void> _loadPicker() async {
    setState(() => _pickerError = null);
    if (_scopeName == 'country' && _countries == null) {
      final r = await widget.api.countries();
      if (!mounted) return;
      setState(() {
        if (!r.ok) {
          _pickerError = r.error;
          return;
        }
        _countries = r.value;
        final c = _countryRow;
        if (_tabsDraft == null && c != null) _tabsDraft = [...c.disabled];
      });
    } else if (_scopeName == 'org' && _orgs == null) {
      final r = await widget.api.orgs();
      if (!mounted) return;
      setState(() => r.ok ? _orgs = r.value : _pickerError = r.error);
    }
  }

  Future<bool> _leaveOk() async => !_dirty || await appConfirmDiscard(context);

  Future<void> _pickScope(int i) async {
    if (i == _scope || !await _leaveOk()) return;
    setState(() => _scope = i);
    _loadPicker();
    _load();
  }

  Future<void> _pickCountry(String? code) async {
    if (code == null || code == _country || !await _leaveOk()) return;
    setState(() => _country = code);
    _load();
  }

  Future<void> _pickOrg(int? id) async {
    if (id == null || id == _orgId || !await _leaveOk()) return;
    setState(() => _orgId = id);
    _load();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final errors = <String>[];
    for (final m in kModuleKeys) {
      final v = _views[m];
      final d = _drafts[m];
      if (v == null || d == null || sameValues(v.values, d)) continue;
      final r = await widget.api.save(m, _scopeName, _scopeKey, d);
      if (!mounted) return;
      if (r.ok && r.value != null) {
        setState(() {
          _views[m] = r.value!;
          _drafts[m] = Map<String, dynamic>.from(r.value!.values);
        });
      } else {
        errors.add('${moduleTitle(m).$1}: ${r.error}');
      }
    }
    final c = _countryRow;
    if (c != null && _tabsDirty) {
      final r = await widget.api.setCountryFeatures(c.code, _tabsDraft!);
      if (!mounted) return;
      if (r.ok) {
        setState(() {
          _countries = [for (final x in _countries!) x.code == c.code ? x.withDisabled(r.value!) : x];
          _tabsDraft = [...r.value!];
        });
      } else {
        errors.add('${t('تبويبات الطلاب', 'Student tabs')}: ${r.error}');
      }
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _rev++;
    });
    showAppNotice(errors.isEmpty ? t('حُفظت الإعدادات', 'Settings saved') : errors.join('\n'), error: errors.isNotEmpty);
  }

  String get _scopeLabel => switch (_scopeName) {
        'country' => _countryRow?.name ?? (_country ?? ''),
        'org' => (_orgs ?? const <ModuleOrg>[]).where((o) => o.id == _orgId).map((o) => o.name).firstOrNull ?? '',
        _ => t('كل المنصة', 'The whole platform'),
      };

  Widget _scopeCard(BuildContext context) {
    final picker = switch (_scopeName) {
      'country' => _countries == null
          ? (_pickerError != null ? ErrorRetry(message: _pickerError!, onRetry: _loadPicker) : const AppListSkeleton(items: 1))
          : AppDropdown<String>(
              key: const ValueKey('modules.country'),
              value: _country,
              decoration: InputDecoration(labelText: t('الدولة', 'Country')),
              items: [for (final c in _countries!) DropdownMenuItem(value: c.code, child: Text('${c.name} (${c.code})'))],
              onChanged: _pickCountry,
            ),
      'org' => _orgs == null
          ? (_pickerError != null ? ErrorRetry(message: _pickerError!, onRetry: _loadPicker) : const AppListSkeleton(items: 1))
          : AppDropdown<int>(
              key: const ValueKey('modules.org'),
              value: _orgId,
              decoration: InputDecoration(labelText: t('المؤسسة', 'Organization')),
              items: [for (final o in _orgs!) DropdownMenuItem(value: o.id, child: Text(o.name))],
              onChanged: _pickOrg,
            ),
      _ => null,
    };
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTabs(
          expand: true,
          index: _scope,
          onChanged: _pickScope,
          items: [
            AppTabItem(t('المنصة', 'Platform'), icon: Icons.public_rounded),
            AppTabItem(t('دولة', 'Country'), icon: Icons.flag_rounded),
            AppTabItem(t('مؤسسة', 'Organization'), icon: Icons.apartment_rounded),
          ],
        ),
        AppSpace.gapSm,
        Text(
          t('قيم المنصة تسري على الجميع. الدولة أو المؤسسة تغيّر فقط ما تضبطه، وما تتركه تأخذه من المنصة. عند الطالب: المؤسسة أقوى من الدولة.',
              'Platform values apply everywhere. A country or an organization changes only what it sets and takes the rest from the platform. For a student, the organization wins over the country.'),
          style: AppType.meta(context),
        ),
        if (picker != null) ...[AppSpace.gapSm, picker],
      ]),
    );
  }

  /// Under the two Quran flags: the page that verifies and reviews the teachers (without it the flags would hide
  /// every teacher for good).
  Widget _quranAdminLink(BuildContext context) => AppActionCard(
        key: const ValueKey('modules.quran_admin'),
        icon: Icons.verified_user_rounded,
        title: t('توثيق ومراجعة معلمي القرآن', 'Verify and review Quran teachers'),
        subtitle: t('البطاقات بانتظار المراجعة والموثّقة', 'Cards waiting for review, and verified teachers'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuranAdminPage())),
      );

  /// Under the self-learning switch: the lessons and questions it delivers.
  Widget _slAdminLink(BuildContext context) => AppActionCard(
        key: const ValueKey('modules.sl_admin'),
        icon: Icons.auto_stories_rounded,
        title: t('محتوى التعلّم الذاتي', 'Self-learning content'),
        subtitle: t('الدروس القصيرة وأسئلة المراجعة', 'The short lessons and review questions'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SlAdminPage())),
      );

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[_scopeCard(context)];
    if (!_ready) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: AppSpace.lg),
        child: AppEmpty(
          icon: _scopeName == 'country' ? Icons.flag_rounded : Icons.apartment_rounded,
          title: _scopeName == 'country' ? t('اختر دولة', 'Pick a country') : t('اختر مؤسسة', 'Pick an organization'),
          message: t('ثم غيّر ما يختلف فيها عن المنصة', 'Then change what differs there from the platform'),
        ),
      ));
    } else if (_loading && _views.isEmpty) {
      children.addAll([AppSpace.gapMd, const AppListSkeleton(items: 3)]);
    } else {
      final c = _countryRow;
      if (_scopeName == 'country' && c != null && _tabsDraft != null) {
        children.addAll([
          AppSpace.gapMd,
          CountryTabsCard(
            countryName: c.name,
            disabled: _tabsDraft!,
            onChanged: (d) => setState(() => _tabsDraft = d),
          ),
        ]);
      }
      for (final m in kModuleKeys) {
        children.add(AppSpace.gapMd);
        final v = _views[m];
        if (v == null) {
          children.add(AppCard(
            padding: AppSpace.card,
            child: ErrorRetry(message: '${moduleTitle(m).$1}: ${_errors[m] ?? ''}', onRetry: _load),
          ));
        } else {
          children.add(ModuleSettingsCard(
            key: ValueKey('modules.card.$m'),
            view: v,
            draft: _drafts[m] ?? const {},
            revision: _rev,
            onChanged: (d) => setState(() => _drafts[m] = d),
            after: switch (m) {
              'quran' => {'content_review_required': _quranAdminLink(context)},
              'self_learning' => {'enabled': _slAdminLink(context)},
              _ => const <String, Widget>{},
            },
          ));
        }
      }
    }
    return SupPage(
        kicker: '${'a2_modules_kicker'.tr} · $_scopeLabel', headline: 'a2_modules_head'.tr, line: 'a2_modules_line'.tr,
        width: AppWidth.reading,
        title: t('مفاتيح الوحدات', 'Module switches'),
        onRefresh: _saving ? null : _load,
        updatedAt: _loadedAt,
        dirty: _dirty,
        body: ListView(padding: AdminPage.bodyPadding(context), children: children),
        actions: [
          if (_ready)
            AppButton.primary(
              key: const ValueKey('modules.save'),
              label: t('حفظ', 'Save'),
              busy: _saving,
              onPressed: _dirty && !_saving ? _save : null,
            ),
        ],
      );
  }
}

// ── one module ───────────────────────────────────────────────────────────────

class ModuleSettingsCard extends StatelessWidget {
  const ModuleSettingsCard({
    super.key,
    required this.view,
    required this.draft,
    required this.onChanged,
    this.revision = 0,
    this.after = const {},
  });

  final ModuleView view;

  /// A widget drawn right under a field's row (by key), e.g. the link to the Quran teachers page under the
  /// verification / review flags.
  final Map<String, Widget> after;

  /// This scope's edited values (a key missing = inherited).
  final Map<String, dynamic> draft;
  final ValueChanged<Map<String, dynamic>> onChanged;

  /// Bumped by the page on a load / save so the number fields take the new values.
  final int revision;

  void _set(String key, dynamic v) => onChanged({...draft, key: v});

  void _inherit(String key) => onChanged({...draft}..remove(key));

  @override
  Widget build(BuildContext context) {
    final (title, desc) = moduleTitle(view.module);
    final fields = orderedFields(view);
    final rows = <Widget>[];
    for (final f in fields) {
      if (rows.isNotEmpty) rows.add(Divider(height: AppSpace.md, color: context.colors.divider));
      final indented = view.module == 'store' && f.key == 'review_required';
      final row = _field(context, f);
      rows.add(indented
          ? Padding(padding: const EdgeInsetsDirectional.only(start: AppSpace.lg), child: row)
          : row);
      final extra = after[f.key];
      if (extra != null) rows.addAll([AppSpace.gapSm, extra]);
    }
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(moduleIcon(view.module), size: AppIconSize.lg, color: context.colors.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(title, style: AppType.section(context))),
          if (view.scope == 'platform' && view.overrideCount > 0)
            Flexible(
              child: AppStatusBadge(
                label: t('${view.overrideCount} استثناء', '${view.overrideCount} overrides'),
                tone: AppTone.info,
                dense: true,
              ),
            ),
        ]),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(desc, style: AppType.meta(context)),
        ],
        AppSpace.gapSm,
        ...rows,
      ]),
    );
  }

  Widget _field(BuildContext context, ModuleField f) {
    final (title, help) = moduleFieldText(view.module, f.key);
    final shown = view.shown(f.key, draft);
    final source = view.sourceOf(f.key, draft);
    final id = '${view.module}.${f.key}';
    final Widget input;
    final sl = view.module == 'self_learning';
    if (sl && _slTimeKeys.contains(f.key)) {
      input = _timeField(context, f, title, help, shown);
    } else if (sl && f.key == 'interval_minutes') {
      input = _intervalField(context, f, title, help, shown);
    } else if (f.type == 'bool') {
      input = AppSwitchTile(
        key: ValueKey('modules.$id'),
        title: title,
        subtitle: help.isEmpty ? null : help,
        value: shown == true,
        onChanged: (v) => _set(f.key, v),
      );
    } else if (f.type == 'int') {
      input = AppNumberField(
        key: ValueKey('modules.$id.${view.scope}.${view.scopeKey}.$revision'),
        initialValue: shown is num ? shown : null,
        label: title,
        helper: help.isEmpty ? null : help,
        min: 0,
        onChanged: (v) {
          if (v != null && v >= 0) _set(f.key, v.toInt());
        },
      );
    } else {
      final choices = f.choices.isEmpty ? ['$shown'] : f.choices;
      input = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppDropdown<String>(
          key: ValueKey('modules.$id'),
          value: choices.contains('$shown') ? '$shown' : null,
          decoration: InputDecoration(labelText: title),
          items: [
            for (final c in choices) DropdownMenuItem(value: c, child: Text(moduleChoiceText(view.module, f.key, c))),
          ],
          onChanged: (v) {
            if (v != null) _set(f.key, v);
          },
        ),
        if (help.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(help, style: AppType.meta(context)),
        ],
      ]);
    }
    final note = view.module == 'store' && f.key == 'review_required' && view.shown('teacher_items', draft) != true
        ? t('يسري فقط عندما يبيع المعلمون عناصرهم.', 'Applies only while teachers sell their own items.')
        : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      input,
      if (note != null) Text(note, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xxs),
      ModuleSourceLine(
        key: ValueKey('modules.$id.source'),
        source: source,
        scope: view.scope,
        inheritedText: _valueText(view.module, f, view.inherited(f.key)),
        onInherit: source == ModuleSource.here ? () => _inherit(f.key) : null,
      ),
    ]);
  }
}

extension on ModuleSettingsCard {
  Widget _help(BuildContext context, String help) =>
      help.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(help, style: AppType.meta(context)));

  /// A time of day (minutes after midnight), shown with AppTime (12 / 24 h) and picked with the clock picker.
  Widget _timeField(BuildContext context, ModuleField f, String title, String help, dynamic shown) {
    final v = _timeOfMinutes(shown);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(title, style: AppType.bodyStrong(context))),
        const SizedBox(width: AppSpace.xs),
        AppButton.secondary(
          key: ValueKey('modules.${view.module}.${f.key}'),
          label: v == null ? t('اختر الوقت', 'Pick a time') : AppTime.clockMinutes(v.hour * 60 + v.minute),
          icon: Icons.schedule_rounded,
          size: AppButtonSize.sm,
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: v ?? const TimeOfDay(hour: 8, minute: 0),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: AppTime.use24h),
                child: child!,
              ),
            );
            if (picked != null) _set(f.key, picked.hour * 60 + picked.minute);
          },
        ),
      ]),
      _help(context, help),
    ]);
  }

  /// The interval between two deliveries: a list of sensible choices (the current value kept when it is not one).
  Widget _intervalField(BuildContext context, ModuleField f, String title, String help, dynamic shown) {
    final cur = shown is num ? shown.toInt() : null;
    final choices = [...kSlIntervalChoices, if (cur != null && !kSlIntervalChoices.contains(cur)) cur]..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<int>(
        key: ValueKey('modules.${view.module}.${f.key}'),
        value: cur,
        decoration: InputDecoration(labelText: title),
        items: [for (final m in choices) DropdownMenuItem(value: m, child: Text(slIntervalText(m)))],
        onChanged: (v) {
          if (v != null) _set(f.key, v);
        },
      ),
      _help(context, help),
    ]);
  }
}

/// "Set here · Use the platform's (On)" — where a value comes from, and the way back to the inherited one.
class ModuleSourceLine extends StatelessWidget {
  const ModuleSourceLine({super.key, required this.source, required this.scope, required this.inheritedText, this.onInherit});

  final ModuleSource source;
  final String scope;
  final String inheritedText;
  final VoidCallback? onInherit;

  @override
  Widget build(BuildContext context) {
    final here = switch (scope) {
      'country' => t('مضبوط لهذه الدولة', 'Set for this country'),
      'org' => t('مضبوط لهذه المؤسسة', 'Set for this organization'),
      _ => t('مضبوط للمنصة', 'Set for the platform'),
    };
    final (label, tone) = switch (source) {
      ModuleSource.here => (here, AppTone.brand),
      ModuleSource.platform => (t('من المنصة', 'From the platform'), AppTone.neutral),
      ModuleSource.defaults => (t('القيمة الافتراضية', 'The default'), AppTone.neutral),
    };
    final back = scope == 'platform' ? t('الافتراضي', 'the default') : t('المنصة', 'the platform');
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppStatusBadge(label: label, tone: tone, dense: true),
        if (onInherit != null)
          AppButton.ghost(
            label: t('استخدم $back ($inheritedText)', 'Use $back ($inheritedText)'),
            icon: Icons.undo_rounded,
            size: AppButtonSize.sm,
            onPressed: onInherit,
          ),
      ],
    );
  }
}

// ── the student tabs of a country ────────────────────────────────────────────

class CountryTabsCard extends StatelessWidget {
  const CountryTabsCard({super.key, required this.countryName, required this.disabled, required this.onChanged});

  final String countryName;

  /// The country's whole switched-off list (keys outside the four tabs are kept).
  final List<String> disabled;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.tab_rounded, size: AppIconSize.lg, color: context.colors.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('تبويبات الطلاب في $countryName', 'Student tabs in $countryName'), style: AppType.section(context))),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(
          t('التبويب المتوقف يختفي عن طلاب هذه الدولة فقط. إيقافه من إدارة المنصة يخفيه في كل مكان.',
              'A tab switched off here disappears for this country\'s students only. Switching it off for the platform hides it everywhere.'),
          style: AppType.meta(context),
        ),
        AppSpace.gapSm,
        for (final k in kCountryTabKeys)
          AppSwitchTile(
            key: ValueKey('modules.tab.$k'),
            title: countryTabText(k),
            value: !disabled.contains(k),
            onChanged: (on) => onChanged(on ? [for (final d in disabled) if (d != k) d] : [...disabled, k]),
          ),
      ]),
    );
  }
}
