// lib/features/org/students/add_student_sheet.dart — "Add student", the Students page's primary action (plan §3.3,
// 4.1a / 4.1e; contract §7.2).
//
//   showAddStudentSheet(context, orgId)   step 1: the institution's active student types as clear cards, grouped
//                                         by admission route, each with one plain sentence (a clerk picks "Transfer
//                                         from another faculty", never a key); one type skips this step.
//                                         step 2: how to enter them, each shown only when the caller may:
//                                           • Enter the full file          → the onboarding wizard
//                                           • Enter the basics and invite  → the same wizard, identity + contact,
//                                                                            then "Save and invite"
//                                           • Share a link or code         → the type's intake link (link · QR)
//                                           • Import a spreadsheet         → the onboarding import page
//                                         The type's entry policy marks one method "Recommended".
//   AddStudentView(...)                   both steps over plain values (the layout harness pumps it)
//
// Nothing is rebuilt: every method opens the existing onboarding screen. Answers true when a screen ran (the caller
// reloads), null when nothing was opened.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t, asMapList;
import '../onboarding/onboarding_api.dart';
import '../onboarding/onboarding_import.dart';
import '../onboarding/onboarding_intake.dart';
import '../onboarding/onboarding_models.dart';
import '../onboarding/onboarding_types_page.dart' show OnbChoiceCard;
import '../onboarding/onboarding_wizard.dart';
import '../org_page_header.dart' show OrgPushedPage;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show orgErrorText;

/// The four ways to enter a student.
enum AddStudentMethod { full, basics, link, excel }

/// The admission routes the type cards are grouped by.
enum AddStudentRoute { first, moving, other, custom }

/// The route of a preset type key (custom types land in [AddStudentRoute.custom]).
AddStudentRoute addStudentRouteOf(OnbType ty) => switch (ty.presetKey ?? ty.key) {
      'student_new' || 'student_equivalent' || 'student_technical' || 'student_international' => AddStudentRoute.first,
      'student_transfer' || 'student_second_degree' => AddStudentRoute.moving,
      'student_postgrad' || 'student_affiliated' || 'student_special_program' || 'student_visiting' => AddStudentRoute.other,
      _ => AddStudentRoute.custom,
    };

String addStudentRouteTitle(AddStudentRoute r) => switch (r) {
      AddStudentRoute.first => t('قبول جديد', 'First admission'),
      AddStudentRoute.moving => t('قادمون من جهة أخرى', 'Coming from elsewhere'),
      AddStudentRoute.other => t('برامج ومسارات أخرى', 'Other programmes and routes'),
      AddStudentRoute.custom => t('أنواع المؤسسة', 'Your institution\'s types'),
    };

/// One plain sentence per preset type; '' for a custom type.
String addStudentTypeHint(OnbType ty) => switch (ty.presetKey ?? ty.key) {
      'student_new' => t('ناجح في الثانوية العامة أو ما يعادلها ويلتحق لأول مرة.', 'Finished secondary school and joins for the first time.'),
      'student_equivalent' => t('حاصل على شهادة معادلة مثل IGCSE أو الدبلومة الأمريكية.', 'Holds an equivalent certificate such as IGCSE or the American diploma.'),
      'student_technical' => t('حاصل على دبلوم فني ونجح في اختبار المعادلة.', 'Holds a technical diploma and passed the equivalency test.'),
      'student_international' => t('طالب غير مصري يلتحق عن طريق إدارة الوافدين.', 'A non-Egyptian student admitted through the international office.'),
      'student_transfer' => t('محوّل من كلية أو جامعة أخرى.', 'Moving in from another faculty or university.'),
      'student_second_degree' => t('يحمل مؤهلاً جامعياً ويدرس لدرجة ثانية.', 'Already holds a university degree and studies for a second one.'),
      'student_postgrad' => t('دبلوم أو ماجستير أو دكتوراه.', 'A diploma, master\'s or doctorate.'),
      'student_affiliated' => t('يدرس بالانتساب دون حضور منتظم.', 'Studies by affiliation, without regular attendance.'),
      'student_special_program' => t('برنامج خاص بمصروفات.', 'A paid special programme.'),
      'student_visiting' => t('زائر أو مستمع يدرس بعض المقررات فقط.', 'A visiting or listening student who takes some courses only.'),
      _ => '',
    };

IconData addStudentTypeIcon(OnbType ty) => switch (ty.presetKey ?? ty.key) {
      'student_new' => Icons.school_outlined,
      'student_equivalent' => Icons.workspace_premium_outlined,
      'student_technical' => Icons.engineering_outlined,
      'student_international' => Icons.public_rounded,
      'student_transfer' => Icons.swap_horiz_rounded,
      'student_second_degree' => Icons.military_tech_outlined,
      'student_postgrad' => Icons.history_edu_outlined,
      'student_affiliated' => Icons.menu_book_outlined,
      'student_special_program' => Icons.star_outline_rounded,
      'student_visiting' => Icons.hail_rounded,
      _ => Icons.person_outline_rounded,
    };

String addStudentMethodTitle(AddStudentMethod m) => switch (m) {
      AddStudentMethod.full => t('إدخال الملف كاملاً', 'Enter the full file'),
      AddStudentMethod.basics => t('إدخال الأساسيات ودعوة الطالب', 'Enter the basics and invite'),
      AddStudentMethod.link => t('مشاركة رابط أو رمز', 'Share a link or code'),
      AddStudentMethod.excel => t('استيراد ملف Excel', 'Import a spreadsheet'),
    };

String addStudentMethodHint(AddStudentMethod m) => switch (m) {
      AddStudentMethod.full => t('الهوية والبيانات والمستندات خطوة بخطوة، ثم التقديم.', 'Identity, details and documents step by step, then submit.'),
      AddStudentMethod.basics => t('الاسم والهوية ووسيلة التواصل فقط؛ يكمل الطالب الباقي بنفسه.', 'Only the name, ID and a contact; the student completes the rest.'),
      AddStudentMethod.link => t('رابط تقديم ورمز QR يتقدم منه الطلاب بأنفسهم.', 'An intake link and QR code students apply from themselves.'),
      AddStudentMethod.excel => t('نزّل القالب واملأه وارفعه؛ تراجع الصفوف قبل الحفظ.', 'Download the template, fill it in and upload it; check the rows before saving.'),
    };

IconData addStudentMethodIcon(AddStudentMethod m) => switch (m) {
      AddStudentMethod.full => Icons.assignment_ind_outlined,
      AddStudentMethod.basics => Icons.forward_to_inbox_outlined,
      AddStudentMethod.link => Icons.qr_code_2_rounded,
      AddStudentMethod.excel => Icons.table_view_outlined,
    };

/// The method the type's entry policy points at.
AddStudentMethod addStudentRecommended(String policy) => switch (policy) {
      'invitation' => AddStudentMethod.basics,
      'code' => AddStudentMethod.link,
      _ => AddStudentMethod.full,
    };

/// Opens "Add student" for organization [orgId]. [api] is for tests.
Future<bool?> showAddStudentSheet(BuildContext context, int orgId, {OnboardingApi? api}) async {
  OrgSession? session;
  try {
    session = context.read<OrgSession>();
  } catch (_) {}
  final s = session;
  bool can(String module, String action) => s == null || s.can(module, action);
  final a = api ?? OnboardingApi();
  final pick = await showAppSheet<({OnbType type, AddStudentMethod method, List<OnbType> all})>(
    context,
    (ctx) => _AddStudentSheet(orgId: orgId, api: a, can: can),
  );
  if (pick == null || !context.mounted) return null;
  final nav = Navigator.of(context);
  Widget scoped(Widget child) => s == null ? child : ChangeNotifierProvider<OrgSession>.value(value: s, child: child);
  final ty = pick.type;
  switch (pick.method) {
    case AddStudentMethod.full:
    case AddStudentMethod.basics:
      final places = await OnbPlaces.load(orgId);
      if (!context.mounted) return null;
      await nav.push<OnbCase?>(MaterialPageRoute(
        builder: (_) => scoped(OnbWizardPage(
          orgId: orgId,
          type: ty,
          api: a,
          places: places,
          canApproveNow: can(ty.module, 'approve'),
          canInvite: _inviteOn(ty, can),
          basicsOnly: pick.method == AddStudentMethod.basics,
        )),
      ));
    case AddStudentMethod.link:
      await nav.push<void>(MaterialPageRoute(builder: (_) => scoped(AddStudentLinkPage(orgId: orgId, type: ty, api: a))));
    case AddStudentMethod.excel:
      final types = [for (final x in pick.all) if (_importOn(x, can)) x];
      await nav.push<bool>(MaterialPageRoute(
        builder: (_) => scoped(OnbImportPage(orgId: orgId, types: types, initialType: ty, canInvite: _inviteOn(ty, can), api: a)),
      ));
  }
  return true;
}

bool _off(String key) => AppConfig.disableList.contains(key);
bool _inviteOn(OnbType ty, bool Function(String, String) can) => !_off(onboardingInviteKey) && can(ty.module, 'update');
bool _importOn(OnbType ty, bool Function(String, String) can) => !_off(onboardingImportKey) && (can(ty.module, 'import') || can(ty.module, 'insert'));
bool _linkOn(bool Function(String, String) can) => !_off(onboardingIntakeKey) && can('onboarding', 'update');

/// The methods the caller may use for [ty], in display order.
List<AddStudentMethod> addStudentMethodsFor(OnbType ty, bool Function(String module, String action) can) => [
      AddStudentMethod.full,
      if (_inviteOn(ty, can)) AddStudentMethod.basics,
      if (_linkOn(can)) AddStudentMethod.link,
      if (_importOn(ty, can)) AddStudentMethod.excel,
    ];

class _AddStudentSheet extends StatefulWidget {
  const _AddStudentSheet({required this.orgId, required this.api, required this.can});
  final int orgId;
  final OnboardingApi api;
  final bool Function(String module, String action) can;

  @override
  State<_AddStudentSheet> createState() => _AddStudentSheetState();
}

class _AddStudentSheetState extends State<_AddStudentSheet> {
  List<OnbType>? _types;
  String? _error;
  bool _loading = true;
  OnbType? _picked;

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
    final r = await widget.api.types(widget.orgId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!r.ok) {
        _error = orgErrorText(r.error!);
        return;
      }
      final raw = r.data is List ? r.data as List : r.map['items'];
      final l = [
        for (final m in asMapList(raw))
          if (OnbType.fromJson(m) case final ty when ty.active && ty.module == 'students' && widget.can(ty.module, 'insert')) ty,
      ];
      _types = l;
      if (l.length == 1) _picked = l.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final types = _types ?? const <OnbType>[];
    final picked = _picked;
    return AppSheetContent(
      title: t('إضافة طالب', 'Add student'),
      subtitle: picked == null ? t('اختر نوع الطالب أولاً', 'First choose the kind of student') : picked.label,
      icon: Icons.person_add_alt_1_rounded,
      children: [
        AddStudentView(
          types: types,
          loading: _loading,
          error: _error,
          onRetry: _load,
          picked: picked,
          methods: picked == null ? const [] : addStudentMethodsFor(picked, widget.can),
          onType: (ty) => setState(() => _picked = ty),
          onBack: types.length > 1 && picked != null ? () => setState(() => _picked = null) : null,
          onMethod: (m) => Navigator.of(context).pop((type: picked!, method: m, all: types)),
        ),
      ],
    );
  }
}

/// Both steps of "Add student" over plain values: the type cards ([picked] null) or the method cards.
class AddStudentView extends StatelessWidget {
  const AddStudentView({
    super.key,
    required this.types,
    this.loading = false,
    this.error,
    this.onRetry,
    this.picked,
    this.methods = const [],
    this.onType,
    this.onMethod,
    this.onBack,
  });

  final List<OnbType> types;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final OnbType? picked;
  final List<AddStudentMethod> methods;
  final ValueChanged<OnbType>? onType;
  final ValueChanged<AddStudentMethod>? onMethod;

  /// "Choose another type"; null = hidden (one type only).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    if (loading && types.isEmpty) return const AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero);
    if (error != null && types.isEmpty) return AppErrorState(message: error, onRetry: onRetry, compact: true);
    if (types.isEmpty) {
      return AppEmpty(
        icon: Icons.rule_folder_outlined,
        title: t('لا توجد أنواع طلاب متاحة لك', 'No student types are open to you'),
        message: t('يضيف المسؤول أنواع الالتحاق من صفحة الالتحاق والتعيين.', 'An administrator adds the admission types on the Admissions page.'),
      );
    }
    final p = picked;
    return p == null ? _typesStep(context) : _methodsStep(context, p);
  }

  Widget _typesStep(BuildContext context) {
    final groups = <AddStudentRoute, List<OnbType>>{};
    for (final ty in types) {
      groups.putIfAbsent(addStudentRouteOf(ty), () => []).add(ty);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in AddStudentRoute.values)
        if (groups[r] case final list?) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xs),
            child: Semantics(header: true, child: Text(addStudentRouteTitle(r), style: AppType.label(context))),
          ),
          for (final ty in list)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: OnbChoiceCard(
                key: ValueKey('students.add.type.${ty.key}'),
                icon: addStudentTypeIcon(ty),
                title: ty.label.isEmpty ? ty.key : ty.label,
                subtitle: addStudentTypeHint(ty),
                onTap: onType == null ? null : () => onType!(ty),
              ),
            ),
        ],
    ]);
  }

  Widget _methodsStep(BuildContext context, OnbType ty) {
    final rec = addStudentRecommended(ty.settings.entryPolicy);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('كيف تريد إدخاله؟', 'How do you want to enter them?'), style: AppType.bodyStrong(context)),
      Text(onbEntryPolicyHint(ty.settings.entryPolicy), style: AppType.meta(context).copyWith(color: context.colors.textMedium)),
      AppSpace.gapSm,
      for (final m in methods)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: OnbChoiceCard(
            key: ValueKey('students.add.method.${m.name}'),
            icon: addStudentMethodIcon(m),
            title: addStudentMethodTitle(m),
            subtitle: addStudentMethodHint(m),
            badge: m == rec && methods.length > 1 ? t('مقترح', 'Recommended') : null,
            onTap: onMethod == null ? null : () => onMethod!(m),
          ),
        ),
      if (onBack != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.ghost(
            key: const ValueKey('students.add.back'),
            label: t('اختيار نوع آخر', 'Choose another kind'),
            icon: Icons.arrow_back_rounded,
            size: AppButtonSize.sm,
            onPressed: onBack,
          ),
        ),
    ]);
  }
}

/// "Share a link or code": the type's intake link panel (on / off, valid until, capacity, link · QR) on its own page.
class AddStudentLinkPage extends StatelessWidget {
  const AddStudentLinkPage({super.key, required this.orgId, required this.type, this.api});
  final int orgId;
  final OnbType type;
  final OnboardingApi? api;

  @override
  Widget build(BuildContext context) {
    return OrgPushedPage(
      title: t('رابط التقديم', 'Intake link'),
      subtitle: type.label,
      helpPageId: 'org.onboarding.types',
      width: AppWidth.form,
      child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxxl), children: [
        Text(
          t('فعّل الرابط ثم انسخه أو اعرض رمز QR. من يفتحه يسجل الدخول ويقدّم ملفه، ثم يصل إليكم للمراجعة.',
              'Turn the link on, then copy it or show its QR code. Whoever opens it signs in and applies, then the file reaches you for review.'),
          style: AppType.body(context).copyWith(color: context.colors.textMedium),
        ),
        AppSpace.gapSm,
        OnbIntakePanel(orgId: orgId, type: type, api: api),
      ]),
    );
  }
}
