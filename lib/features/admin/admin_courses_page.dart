// lib/features/admin/admin_courses_page.dart — all courses: status, income, full control,
// per-course payment provider / allowed methods / platform fee.
library;

import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/outline_button.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_filter_models.dart';
import 'admin_filters.dart';
import 'admin_labels.dart';
import 'admin_list.dart';
import 'admin_table_export.dart' show adminCoursesExport;
import 'admin_models.dart';
import 'admin_providers.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;

class AdminCoursesPage extends StatelessWidget {
  const AdminCoursesPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminCoursesProvider()..refresh(),
    child: _CoursesView(embedded: embedded),
  );
}

// ── premium filters ─────────────────────────────────────────────────────────

const _courseSort = SortSpec({
  'newest': 'admin_sort_newest',
  'oldest': 'admin_sort_oldest',
  'name_asc': 'admin_sort_name_asc',
  'name_desc': 'admin_sort_name_desc',
  'price_asc': 'admin_sort_price_asc',
  'price_desc': 'admin_sort_price_desc',
});

const _courseSpecs = <FilterSpec>[
  FilterSpec.tri('published', 'admin_filter_publish_state', yesKey: 'published', noKey: 'status_draft'),
  FilterSpec.choice('status', 'admin_filter_status', {
    'in_progress': 'admin_in_progress',
    'completed': 'completed',
  }),
  FilterSpec.lookup('teacher_id', 'admin_filter_teacher', 'teachers'),
  FilterSpec.lookup('category_id', 'admin_filter_category', 'categories'),
  FilterSpec.remoteChoice('type', 'admin_filter_course_type', 'course_types'),
  FilterSpec.remoteChoice('currency', 'admin_filter_currency', 'currencies'),
  FilterSpec.numberRange('price_min', 'price_max', 'admin_filter_price'),
  FilterSpec.tri('is_private', 'admin_filter_private'),
  FilterSpec.tri('discount_active', 'admin_filter_discount'),
  FilterSpec.tri('has_students', 'admin_filter_has_students'),
  FilterSpec.tri('has_pending_payments', 'admin_filter_pending_payments'),
  FilterSpec.dateRange('created_from', 'created_to', 'admin_filter_created'),
];

class _CoursesView extends StatelessWidget {
  const _CoursesView({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminCoursesProvider>();
    final c = context.colors;

    final header = Column(
      children: [
        AdminFilterBar(
          host: p,
          hintKey: 'admin_search_course_name',
          specs: _courseSpecs,
          sort: _courseSort,
          quickKeys: const {'published', 'status'},
        ),
        FilterChips<String>(
          value: p.published == null ? 'all' : (p.published! ? 'pub' : 'draft'),
          options: {
            'all': 'filter_all'.tr,
            'pub': 'published'.tr,
            'draft': 'status_draft'.tr,
          },
          onChanged: (v) => p.setPublished(v == 'all' ? null : v == 'pub'),
        ),
        const SizedBox(height: 6),
        FilterChips<String>(
          value: p.status ?? 'any',
          options: {
            'any': 'admin_any_status'.tr,
            'in_progress': 'admin_in_progress'.tr,
            'completed': 'completed'.tr,
          },
          onChanged: (v) => p.setStatus(v == 'any' ? null : v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.payments_rounded, color: c.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'admin_total_course_income_after_discounts'.tr,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      color: c.textMedium,
                    ),
                  ),
                ),
                Text(
                  moneyByCurrency(p.incomeByCurrency),
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w900,
                    color: c.primary,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return Directionality(
      textDirection: dir,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: embedded
            ? null
            : AppBar(
          title: Text(
            'courses'.tr,
            style: const TextStyle(fontFamily: 'tajawal'),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: "courses_float",
          key: ValueKey("courses_float"),
          backgroundColor: c.primary,
          onPressed: () => _openCourseForm(context, p),
          icon: Icon(Icons.add_rounded, color: c.onHero),
          label: Text(
            'admin_add_course'.tr,
            style: TextStyle(fontFamily: 'tajawal', color: c.onHero),
          ),
        ),
        body: PagedList<AdminCoursesProvider>(
          export: adminCoursesExport,
          header: header,
          emptyText: 'admin_no_courses_found'.tr,
          itemBuilder: (ctx, row) => _CourseTile(AdminCourse(row)),
        ),
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile(this.course);

  final AdminCourse course;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminCoursesProvider>();
    final ps = course.paymentSettings;

    return RowCard(
      onTap: () => _openCourseDetail(context, p, course.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  course.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: c.textDark,
                  ),
                ),
              ),
              StatusChip(
                course.isPublished ? 'published'.tr : 'status_draft'.tr,
                course.isPublished ? c.success : c.warning,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            course.teacherName,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 12,
              color: c.textLight,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Stat(
                Icons.group_rounded,
                '${course.studentsCount}',
                'students'.tr,
              ),
              _Stat(
                Icons.account_balance_wallet_rounded,
                money(course.income, course.currency),
                'admin_income'.tr,
              ),
              _Stat(
                Icons.sell_rounded,
                money(course.finalPrice, course.currency),
                'admin_price'.tr,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (course.discountActive)
                StatusChip(
                  '${'admin_discount'.tr} ${course.discountPercentage.toStringAsFixed(0)}%',
                  c.danger,
                ),
              // every plan the course sells (monthly / 6 months / yearly) with its price after discount
              if (course.priceOptions.length > 1)
                for (final o in course.priceOptions)
                  StatusChip(
                    '${planLabel(asStr(o['plan']))} ${money(asDouble(o['final_price']), course.currency)}',
                    c.charcoal,
                  ),
              StatusChip(
                course.status == 'completed'
                    ? 'completed'.tr
                    : 'admin_in_progress'.tr,
                c.primary,
              ),
              StatusChip(ps.provider ?? 'admin_default_gateway'.tr, c.charcoal),
              if (course.pendingPayments > 0)
                StatusChip(
                  '${course.pendingPayments} ${'admin_pending'.tr}',
                  c.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label);

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: c.textDark,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 10.5,
                    color: c.textLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Detail + payment settings
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openCourseDetail(
    BuildContext context,
    AdminCoursesProvider p,
    int id,
    ) {
  return showAdminSheet(
    context,
        (ctx) => ChangeNotifierProvider.value(
      value: p,
      child: _CourseDetail(id: id),
    ),
  );
}

class _CourseDetail extends StatefulWidget {
  const _CourseDetail({required this.id});

  final int id;

  @override
  State<_CourseDetail> createState() => _CourseDetailState();
}

class _CourseDetailState extends State<_CourseDetail> {
  AdminCourse? course;
  Map<String, dynamic> raw = {};
  bool loading = true;

  // payment-settings form
  String? provider; // null = default
  bool restrictMethods = false;
  final Set<String> methods = {'card', 'bank_transfer', 'instapay'};
  final _fee = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await context.read<AdminCoursesProvider>().detail(widget.id);
    final rawMap = await context.read<AdminCoursesProvider>().detailRaw(widget.id);
    if (!mounted) return;
    setState(() {
      course = r;
      raw = rawMap ?? {};
      loading = false;
      if (r != null) {
        provider = r.paymentSettings.provider;
        final allowed = r.paymentSettings.allowedMethods;
        restrictMethods = allowed != null;
        methods
          ..clear()
          ..addAll(allowed ?? const ['card', 'bank_transfer', 'instapay']);
        _fee.text = r.paymentSettings.feePercent?.toString() ?? '';
      }
    });
  }

  String _randomCode() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  Future<void> _changeCode(int id) async {
    final ctrl = TextEditingController(text: (raw['access_code'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Directionality(
          textDirection: dir,
          child: AlertDialog(
            scrollable: true,
            title: Text('admin_change_access_code'.tr,
                style: const TextStyle(fontFamily: 'tajawal')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Field(
                  controller: ctrl,
                  label: 'admin_access_code_hint'.tr,
                  keyboard: TextInputType.number,
                ),
                TextButton.icon(
                  onPressed: () => setS(() => ctrl.text = _randomCode()),
                  icon: const Icon(Icons.casino_rounded, size: 18),
                  label: Text('admin_generate_code'.tr),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('exam_cancel'.tr),
              ),
              TextButton(
                onPressed: () {
                  if (!RegExp(r'^\d{6}$').hasMatch(ctrl.text.trim())) {
                    toast('admin_code_6_digits'.tr, error: true);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text('save'.tr),
              ),
            ],
          ),
        ),
      ),
    );
    final code = ctrl.text.trim();
    disposeAfterRoute([ctrl]);
    if (ok == true && mounted) {
      if (await context.read<AdminCoursesProvider>().update(id, {'access_code': code})) {
        await _load();
      }
    }
  }

  Future<void> _savePayment() async {
    final feeText = _fee.text.trim();
    double? fee;
    if (feeText.isNotEmpty) {
      fee = double.tryParse(feeText);
      if (fee == null || fee < 0 || fee > 100) {
        toast('admin_fee_must_be_between_0_and_100'.tr, error: true);
        return;
      }
    }
    if (restrictMethods && methods.isEmpty) {
      toast('admin_pick_at_least_one_payment_method'.tr, error: true);
      return;
    }
    setState(() => saving = true);
    // Every key is sent on purpose: null RESETS the field to the system default.
    final ok = await context.read<AdminCoursesProvider>().savePaymentSettings(
      widget.id,
      {
        'payment_provider': provider,
        'allowed_methods': restrictMethods ? (methods.toList()..sort()) : null,
        'platform_fee_percent': fee,
      },
    );
    if (!mounted) return;
    setState(() => saving = false);
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminCoursesProvider>();
    if (loading) {
      return const SizedBox(
        height: 260,
        child: AppListSkeleton(items: 3),
      );
    }
    final co = course;
    if (co == null) {
      return SizedBox(
        height: 260,
        child: ErrorRetry(
          message: 'admin_could_not_load_data'.tr,
          onRetry: _load,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(co.name),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Section(
                title: 'admin_overview'.tr,
                child: Column(
                  children: [
                    KeyValue('admin_teacher'.tr, co.teacherName),
                    KeyValue(
                      'admin_list_price'.tr,
                      money(co.listPrice, co.currency),
                    ),
                    for (final o in co.priceOptions)
                      KeyValue(
                        planLabel(asStr(o['plan'])),
                        asBool(o['discount_active'])
                            ? '${money(asDouble(o['final_price']), co.currency)}  (${money(asDouble(o['price']))})'
                            : money(asDouble(o['final_price']), co.currency),
                      ),
                    if (co.discountActive)
                      KeyValue(
                        'admin_price_after_discount'.tr,
                        '${money(co.finalPrice, co.currency)}  (-${co.discountPercentage.toStringAsFixed(0)}%)',
                      ),
                    KeyValue('admin_students'.tr, '${co.studentsCount}'),
                    KeyValue('admin_paid'.tr, '${co.paidCount}'),
                    KeyValue(
                      'admin_income_after_discount'.tr,
                      money(co.income, co.currency),
                    ),
                    KeyValue(
                      'admin_collected_from_students_incl_fees'.tr,
                      money(co.collected, co.currency),
                    ),
                    KeyValue(
                      'admin_effective_platform_fee'.tr,
                      '${co.paymentSettings.effectiveFeePercent}%',
                    ),
                  ],
                ),
              ),
              Section(
                title: 'admin_access_and_resubscribe'.tr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSwitchTile(
                      dense: true,
                      title: 'admin_private_course'.tr,
                      value: raw['is_private'] == true,
                      activeColor: c.primary,
                      onChanged: (v) async {
                        if (await p.update(co.id, {'is_private': v})) await _load();
                      },
                    ),
                    if (raw['is_private'] == true) ...[
                      KeyValue('admin_access_code'.tr,
                          (raw['access_code'] ?? '—').toString()),
                      Row(
                        children: [
                          OutlineButton(
                            label: 'admin_change_access_code'.tr,
                            color: c.primary,
                            icon: Icons.password_rounded,
                            onPressed: () => _changeCode(co.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    AppSwitchTile(
                      dense: true,
                      title: 'admin_allow_resubscribe'.tr,
                      subtitle: 'admin_allow_resubscribe_hint'.tr,
                      value: raw['allow_resubscribe'] != false,
                      activeColor: c.primary,
                      onChanged: (v) async {
                        if (await p.update(co.id, {'allow_resubscribe': v})) await _load();
                      },
                    ),
                  ],
                ),
              ),
              Section(
                title: 'admin_payment_settings'.tr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChoiceRow<String?>(
                      label: 'admin_card_gateway'.tr,
                      options: {
                        null: 'admin_system_default'.tr,
                        'moyasar': 'Moyasar',
                        'paymob': 'Paymob',
                      },
                      value: provider,
                      onChanged: (v) => setState(() => provider = v),
                    ),
                    AppSwitchTile(
                      dense: true,
                      title: 'admin_restrict_payment_methods'.tr,
                      value: restrictMethods,
                      activeColor: c.primary,
                      onChanged: (v) => setState(() => restrictMethods = v),
                    ),
                    if (restrictMethods)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final m in {
                            'card': 'Moyasar / Paymob',
                            'bank_transfer': 'admin_bank_transfer'.tr,
                            'instapay': 'InstaPay',
                          }.entries)
                            FilterChip(
                              label: Text(
                                m.value,
                                style: const TextStyle(fontFamily: 'tajawal'),
                              ),
                              selected: methods.contains(m.key),
                              selectedColor: c.primary.withValues(alpha: 0.25),
                              onSelected: (s) => setState(
                                    () => s
                                    ? methods.add(m.key)
                                    : methods.remove(m.key),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Field(
                      controller: _fee,
                      label: 'admin_platform_fee_empty_default'.tr,
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    Text(
                      'admin_instapay_is_only_shown_for_egp_courses'.tr,
                      style: TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 11.5,
                        color: c.textLight,
                      ),
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(
                      label: 'admin_save_payment_settings'.tr,
                      isLoading: saving,
                      onPressed: _savePayment,
                    ),
                  ],
                ),
              ),
              if (co.recentPayments.isNotEmpty)
                Section(
                  title: 'admin_recent_payments'.tr,
                  child: Column(
                    children: [
                      for (final pay in co.recentPayments.take(8))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '#${pay['id']} • ${asStr(pay['method'], '—')} • ${shortDate(asStrOrNull(pay['created_at']))}',
                                  style: TextStyle(
                                    fontFamily: 'tajawal',
                                    fontSize: 12.5,
                                    color: c.textMedium,
                                  ),
                                ),
                              ),
                              Text(
                                money(
                                  asDouble(
                                    pay['price_paid'],
                                    asDouble(pay['amount']),
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'tajawal',
                                  fontWeight: FontWeight.w700,
                                  color: c.textDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusChip(
                                asStr(pay['status']),
                                asStr(pay['status']) == 'completed'
                                    ? c.success
                                    : (asStr(pay['status']) == 'pending'
                                    ? c.warning
                                    : c.danger),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              Section(
                title: 'admin_controls'.tr,
                child: Column(
                  children: [
                    Row(
                      children: [
                        OutlineButton(
                          label: co.isPublished
                              ? 'admin_unpublish'.tr
                              : 'publish_exam'.tr,
                          color: co.isPublished
                              ? context.colors.warning
                              : context.colors.success,
                          icon: co.isPublished
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          onPressed: () async {
                            final ok = await p.update(co.id, {
                              'is_published': !co.isPublished,
                            });
                            if (ok && context.mounted) {
                              Navigator.pop(
                                context,
                              ); // close the sheet and go back to the list
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        OutlineButton(
                          label: 'btn_edit'.tr,
                          color: context.colors.warning,
                          icon: Icons.edit_rounded,
                          onPressed: () async {
                            Navigator.pop(context);
                            _openCourseForm(context, p, existing: co);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlineButton(
                          label: co.status == 'completed'
                              ? 'admin_reopen'.tr
                              : 'admin_mark_completed'.tr,
                          color: context.colors.primary,
                          icon: co.status == 'completed'
                              ? Icons.replay_rounded
                              : Icons.flag_rounded,
                          onPressed: () async {
                            final next = co.status == 'completed'
                                ? 'in_progress'
                                : 'completed';
                            if (await p.update(co.id, {'status': next})) {
                              await _load();
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        OutlineButton(
                          label: 'delete'.tr,
                          color: context.colors.danger,
                          icon: Icons.edit_rounded,
                          onPressed: () async {
                            final ok = await confirm(
                              context,
                              message:
                              'admin_delete_this_course_permanently_all'.tr,
                              danger: true,
                            );
                            if (!ok) return;
                            if (await p.remove(co.id, force: true) &&
                                context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Create / edit course
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openCourseForm(
    BuildContext context,
    AdminCoursesProvider p, {
      AdminCourse? existing,
    }) {
  return showAdminSheet(
    context,
        (ctx) => _CourseForm(provider: p, existing: existing),
  );
}

class _CourseForm extends StatefulWidget {
  const _CourseForm({required this.provider, this.existing});

  final AdminCoursesProvider provider;
  final AdminCourse? existing;

  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late final _fees = TextEditingController(
    text: widget.existing == null ? '0' : widget.existing!.fees.toString(),
  );
  late final _max = TextEditingController(
    text: widget.existing?.maxStudents?.toString() ?? '',
  );

  // optional shorter plans; `fees` above is the YEARLY price
  late final _monthly = TextEditingController(
    text: widget.existing?.priceMonthly?.toString() ?? '',
  );
  late final _sixMonths = TextEditingController(
    text: widget.existing?.priceSixMonths?.toString() ?? '',
  );

  late String currency = widget.existing?.currency ?? 'EGP';
  late int defaultPlan =
      widget.existing?.defaultPricePlanIndex ??
          0; // 0 yearly · 1 six months · 2 monthly
  late String type = (widget.existing?.type ?? 'recorded').toLowerCase();
  int? teacherId;
  int? categoryId;
  bool published = false;
  bool isPrivate = false;
  bool allowResub = true;
  final _code = TextEditingController();

  List<AdminUser> teachers = [];
  List<AdminCategory> categories = [];
  bool busy = false;
  bool ready = false;

  bool get editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    teacherId = widget.existing?.teacherId;
    categoryId = widget.existing?.categoryId;
    published = widget.existing?.isPublished ?? false;
    _loadChoices();
  }

  Future<void> _loadChoices() async {
    final tch = await widget.provider.teacherChoices();
    final cat = await widget.provider.categoryChoices();
    Map<String, dynamic>? raw;
    if (widget.existing != null) {
      raw = await widget.provider.detailRaw(widget.existing!.id);
    }
    if (!mounted) return;
    setState(() {
      teachers = tch;
      categories = cat;
      if (raw != null) {
        isPrivate = raw['is_private'] == true;
        allowResub = raw['allow_resubscribe'] != false;
        _code.text = (raw['access_code'] ?? '').toString();
      }
      ready = true;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _desc, _fees, _max, _monthly, _sixMonths, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (teacherId == null) {
      toast('admin_choose_a_teacher'.tr, error: true);
      return;
    }
    setState(() => busy = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'fees': double.tryParse(_fees.text.trim()) ?? 0, // YEARLY price
      // empty = the plan is not offered (null clears it on edit)
      'price_monthly': double.tryParse(_monthly.text.trim()),
      'price_six_months': double.tryParse(_sixMonths.text.trim()),
      'default_price_plan_index': defaultPlan,
      'currency': currency,
      'type': type,
      'teacher_id': teacherId,
      'category_id': categoryId,
      'max_students': int.tryParse(_max.text.trim()),
      'is_published': published,
      'is_private': isPrivate,
      'allow_resubscribe': allowResub,
      if (isPrivate && _code.text.trim().isNotEmpty)
        'access_code': _code.text.trim(),
    };
    final ok = editing
        ? await widget.provider.update(widget.existing!.id, body)
        : await widget.provider.create(body);
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _pickTeacher() async {
    final r = await showDialog<AdminUser>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: dir,
        child: SimpleDialog(
          title: Text(
            'admin_choose_teacher'.tr,
            style: const TextStyle(fontFamily: 'tajawal'),
          ),
          children: [
            SizedBox(
              width: double.maxFinite,
              height: 340,
              child: ListView(
                children: [
                  for (final u in teachers)
                    ListTile(
                      title: Text(
                        u.name,
                        style: const TextStyle(fontFamily: 'tajawal'),
                      ),
                      subtitle: Text(
                        u.gmail,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () => Navigator.pop(ctx, u),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (r != null) setState(() => teacherId = r.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final teacherName =
        teachers
            .where((u) => u.id == teacherId)
            .map((u) => u.name)
            .firstOrNull ??
            (editing ? widget.existing!.teacherName : null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(editing ? 'admin_edit_course'.tr : 'admin_add_course'.tr),
        Flexible(
          child: !ready
              ? const SizedBox(
            height: 200,
            child: AppListSkeleton(items: 3),
          )
              : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Field(
                    controller: _name,
                    label: 'admin_course_name'.tr,
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'admin_name_is_required'.tr
                        : null,
                  ),
                  Field(
                    controller: _desc,
                    label: 'description'.tr,
                    maxLines: 3,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Field(
                          controller: _fees,
                          label: 'price_yearly_label'.tr,
                          keyboard: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            return (n == null || n < 0)
                                ? 'admin_invalid_price'.tr
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Field(
                          controller: _max,
                          label: 'admin_max_students'.tr,
                          keyboard: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Field(
                          controller: _sixMonths,
                          label: 'price_six_months_label'.tr,
                          keyboard: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (s.isEmpty) return null;
                            final n = double.tryParse(s);
                            return (n == null || n < 0)
                                ? 'admin_invalid_price'.tr
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Field(
                          controller: _monthly,
                          label: 'price_monthly_label'.tr,
                          keyboard: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final s = (v ?? '').trim();
                            if (s.isEmpty) return null;
                            final n = double.tryParse(s);
                            return (n == null || n < 0)
                                ? 'admin_invalid_price'.tr
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'price_plans_hint'.tr,
                      style: TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 11.5,
                        color: context.colors.textLight,
                      ),
                    ),
                  ),
                  ChoiceRow<int>(
                    label: 'default_plan_label'.tr,
                    options: {
                      0: 'price_yearly_label'.tr,
                      1: 'price_six_months_label'.tr,
                      2: 'price_monthly_label'.tr,
                    },
                    value: defaultPlan,
                    onChanged: (v) => setState(() => defaultPlan = v),
                  ),
                  ChoiceRow<String>(
                    label: 'currency_label'.tr,
                    options: const {
                      'EGP': 'EGP',
                      'SAR': 'SAR',
                      'USD': 'USD',
                    },
                    value: currency,
                    onChanged: (v) => setState(() => currency = v),
                  ),
                  ChoiceRow<String>(
                    label: 'admin_type'.tr,
                    options: {
                      'recorded': 'session_type_recorded'.tr,
                      'live': 'session_type_live'.tr,
                      'both': 'session_type_both'.tr,
                    },
                    value: type,
                    onChanged: (v) => setState(() => type = v),
                  ),
                  Row(
                    children: [
                      OutlineButton(
                        color: context.colors.primary,
                        onPressed: _pickTeacher,
                        icon: Icons.school_rounded,
                        label: teacherName ?? 'admin_choose_teacher'.tr,
                      ),
                      Spacer(flex:3)
                    ],
                  ),
                  if (categories.isNotEmpty)
                    ChoiceRow<int?>(
                      label: 'category_label'.tr,
                      options: {
                        null: 'admin_none'.tr,
                        for (final cat in categories) cat.id: cat.display,
                      },
                      value: categoryId,
                      onChanged: (v) => setState(() => categoryId = v),
                    ),
                  AppSwitchTile(
                    title: 'admin_private_course'.tr,
                    value: isPrivate,
                    activeColor: c.primary,
                    onChanged: (v) => setState(() => isPrivate = v),
                  ),
                  if (isPrivate)
                    Field(
                      controller: _code,
                      label: 'admin_access_code_hint'.tr,
                      keyboard: TextInputType.number,
                      validator: (v) {
                        final s = (v ?? '').trim();
                        return (s.isEmpty || RegExp(r'^\d{6}$').hasMatch(s))
                            ? null
                            : 'admin_code_6_digits'.tr;
                      },
                    ),
                  AppSwitchTile(
                    title: 'admin_allow_resubscribe'.tr,
                    subtitle: 'admin_allow_resubscribe_hint'.tr,
                    value: allowResub,
                    activeColor: c.primary,
                    onChanged: (v) => setState(() => allowResub = v),
                  ),
                  AppSwitchTile(
                    title: 'published'.tr,
                    value: published,
                    activeColor: c.primary,
                    onChanged: (v) => setState(() => published = v),
                  ),
                  const SizedBox(height: 8),
                  PrimaryButton(
                    label: 'save'.tr,
                    isLoading: busy,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}