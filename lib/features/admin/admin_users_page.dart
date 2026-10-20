// lib/features/admin/admin_users_page.dart — students & teachers (list, detail, control).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/app_bar.dart';
import '../../utils/widget/app_loading_indicator.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/outline_button.dart';
import '../../utils/widget/phone_field.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_filter_models.dart';
import 'admin_filters.dart';
import 'admin_labels.dart';
import 'admin_list.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_view_as_page.dart' show startViewAs;
import 'package:flutter_education_app/design/app_inputs.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key, required this.role, this.embedded = false});

  /// 'student' | 'teacher'
  final String role;

  /// true when shown as a tab inside the dashboard shell (no AppBar).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminUsersProvider(role)..refresh(),
      child: _UsersView(role: role, embedded: embedded),
    );
  }
}

class _UsersView extends StatelessWidget {
  const _UsersView({required this.role, required this.embedded});

  final String role;
  final bool embedded;

  bool get isStudent => role == 'student';

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminUsersProvider>();
    final c = context.colors;

    final header = Column(
      children: [
        AdminFilterBar(
          host: p,
          hintKey: 'admin_search_name_email_or_phone',
          specs: _userSpecs(isStudent),
          sort: _userSort,
          quickKeys: const {'status', 'subscribed'},
        ),
        FilterChips<String>(
          value: p.status ?? 'all',
          options: {
            'all': 'filter_all'.tr,
            'active': 'exam_status_active'.tr,
            'inactive': 'admin_inactive'.tr,
            'pending_deletion': 'admin_pending_deletion'.tr,
          },
          onChanged: (v) => p.setStatus(v == 'all' ? null : v),
        ),
        if (isStudent)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FilterChips<String>(
              value: p.subscribed == null
                  ? 'any'
                  : (p.subscribed! ? 'yes' : 'no'),
              options: {
                'any': 'admin_any_subscription'.tr,
                'yes': 'admin_subscribed'.tr,
                'no': 'admin_not_subscribed'.tr,
              },
              onChanged: (v) => p.setSubscribed(v == 'any' ? null : v == 'yes'),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );

    final list = PagedList<AdminUsersProvider>(
      header: header,
      emptyText: isStudent
          ? 'admin_no_students_found'.tr
          : 'admin_no_teachers_found'.tr,
      itemBuilder: (ctx, row) =>
          _UserTile(AdminUser(row), isStudent: isStudent),
    );

    final fab = FloatingActionButton.extended(
      heroTag: "users_float",
      key: ValueKey("users_float"),
      backgroundColor: c.primary,
      onPressed: () => _openForm(context, p),
      icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
      label: Text(
        isStudent ? 'admin_add_student'.tr : 'admin_add_teacher'.tr,
        style: const TextStyle(fontFamily: 'tajawal', color: Colors.white),
      ),
    );

    return BasePage(
      useWebCard: !embedded,
      maxWith: 1100,
      // The dashboard tab already wraps this page in a BasePage that owns the footer.
      enableFooterWidget: !embedded,
      appBar: embedded
          ? null
          : ScreenAppBar(
              title: isStudent ? 'admin_students'.tr : 'admin_teachers'.tr,
            ),
      floatingActionButton: fab,
      child: list,
    );
  }
}

// ── premium filters ─────────────────────────────────────────────────────────

const _userSort = SortSpec({
  'newest': 'admin_sort_newest',
  'oldest': 'admin_sort_oldest',
  'name_asc': 'admin_sort_name_asc',
  'name_desc': 'admin_sort_name_desc',
  'last_login': 'admin_sort_last_login',
  'most_logins': 'admin_sort_most_logins',
});

List<FilterSpec> _userSpecs(bool isStudent) => [
  const FilterSpec.choice('status', 'admin_filter_status', {
    'active': 'exam_status_active',
    'inactive': 'admin_inactive',
    'pending_deletion': 'admin_pending_deletion',
  }),
  if (isStudent) ...[
    const FilterSpec.tri(
      'subscribed',
      'admin_filter_subscription',
      yesKey: 'admin_subscribed',
      noKey: 'admin_not_subscribed',
    ),
    const FilterSpec.choice(
      'subscription_status',
      'admin_filter_subscription_status',
      {
        'pending': 'admin_pending_4',
        'active': 'admin_active',
        'expired': 'admin_expired',
        'rejected': 'admin_rejected',
        'cancelled': 'admin_cancelled_2',
      },
    ),
    const FilterSpec.lookup('course_id', 'admin_filter_enrolled_in', 'courses'),
    const FilterSpec.tri('has_enrollments', 'admin_filter_has_enrollments'),
  ] else ...[
    const FilterSpec.lookup('course_id', 'admin_filter_teaches', 'courses'),
    const FilterSpec.tri('has_courses', 'admin_filter_has_courses'),
  ],
  const FilterSpec.tri('verified', 'admin_filter_verified'),
  const FilterSpec.tri('email_verified', 'admin_filter_email_verified'),
  const FilterSpec.tri('phone_verified', 'admin_filter_phone_verified'),
  const FilterSpec.tri('has_phone', 'admin_filter_has_phone'),
  const FilterSpec.lookup('country', 'admin_filter_country', 'countries'),
  const FilterSpec.remoteChoice(
    'registration_step',
    'admin_filter_registration_step',
    'registration_steps',
  ),
  const FilterSpec.dateRange(
    'created_from',
    'created_to',
    'admin_filter_joined',
  ),
  const FilterSpec.choice('last_login', 'admin_filter_last_login', {
    'today': 'admin_filter_today',
    '7d': 'admin_filter_last_7_days',
    '30d': 'admin_filter_last_30_days',
    '90d': 'admin_filter_last_90_days',
    'inactive_30d': 'admin_filter_inactive_30d',
    'never': 'admin_filter_never_logged_in',
  }),
];

class _UserTile extends StatelessWidget {
  const _UserTile(this.u, {required this.isStudent});

  final AdminUser u;
  final bool isStudent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminUsersProvider>();
    final sub = u.subscription;

    return RowCard(
      onTap: () => _openDetail(context, p, u.id),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: c.primary.withValues(alpha: 0.15),
            child: Text(
              u.name.isEmpty ? '?' : u.name.characters.first.toUpperCase(),
              style: TextStyle(color: c.primary, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    color: c.textDark,
                  ),
                ),
                Text(
                  u.gmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 12,
                    color: c.textLight,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (u.pendingDeletion)
                      StatusChip('admin_pending_deletion'.tr, c.danger)
                    else
                      StatusChip(
                        u.isActive
                            ? 'exam_status_active'.tr
                            : 'admin_inactive'.tr,
                        u.isActive ? c.success : c.warning,
                      ),
                    if (isStudent)
                      StatusChip(
                        u.hasActiveSubscription
                            ? 'admin_subscribed'.tr
                            : (sub?.status == 'pending'
                                  ? 'admin_sub_pending'.tr
                                  : 'admin_no_sub'.tr),
                        u.hasActiveSubscription
                            ? c.success
                            : (sub?.status == 'pending'
                                  ? c.warning
                                  : c.textLight),
                      ),
                    if (isStudent)
                      StatusChip(
                        '${u.enrolledCourses.length} ${'roadmap_course_unit'.tr}',
                        c.primary,
                      )
                    else
                      StatusChip(
                        '${u.coursesCount} ${'roadmap_course_unit'.tr}',
                        c.primary,
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Super-admin: jump straight into this user's app (read-only). "Back to admin" is in the banner.
          if (isSuperNow(context) &&
              (u.role == 'student' || u.role == 'teacher'))
            IconButton(
              tooltip: 'view_as_user'.tr,
              icon: Icon(Icons.visibility_rounded, color: c.warning),
              onPressed: () => startViewAs(
                Navigator.of(context, rootNavigator: true),
                id: u.id,
                name: u.name,
                role: u.role,
              ),
            ),
          Icon(Icons.chevron_right_rounded, color: c.textLight),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Detail / control sheet
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openDetail(
  BuildContext context,
  AdminUsersProvider p,
  int id,
) async {
  await showAdminSheet(
    context,
    (ctx) => ChangeNotifierProvider.value(
      value: p,
      child: _UserDetailSheet(userId: id),
    ),
  );
}

class _UserDetailSheet extends StatefulWidget {
  const _UserDetailSheet({required this.userId});

  final int userId;

  @override
  State<_UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<_UserDetailSheet> {
  UserDetail? d;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [spinner] = true for the first load / the Retry button; false for silent refreshes after an action
  /// (so the sheet does not flash a spinner and lose its scroll position).
  Future<void> _load({bool spinner = false}) async {
    if (spinner && !loading) setState(() => loading = true);
    final r = await context.read<AdminUsersProvider>().detail(widget.userId);
    if (!mounted) return;
    setState(() {
      d = r;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminUsersProvider>();

    if (loading) {
      return const SizedBox(
        height: 260,
        child: Center(child: AppLoadingIndicator()),
      );
    }
    if (d == null) {
      return SizedBox(
        height: 260,
        child: ErrorRetry(
          message: 'admin_could_not_load_data'.tr,
          onRetry: () => _load(spinner: true),
        ),
      );
    }
    final u = d!.user;
    final isStudent = u.role == 'student';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(u.name),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            shrinkWrap: true,
            children: [
              Section(
                title: 'admin_profile_2'.tr,
                child: Column(
                  children: [
                    KeyValue('admin_email_2'.tr, u.gmail),
                    KeyValue('admin_phone'.tr, u.phone),
                    KeyValue('country'.tr, u.country),
                    KeyValue('admin_birth_date'.tr, shortDate(u.dob)),
                    KeyValue(
                      'status'.tr,
                      u.pendingDeletion
                          ? 'admin_pending_deletion'.tr
                          : (u.isActive
                                ? 'exam_status_active'.tr
                                : 'admin_inactive'.tr),
                    ),
                    KeyValue('admin_joined'.tr, shortDate(u.createdAt)),
                    KeyValue('admin_last_login'.tr, shortDateTime(u.lastLogin)),
                    KeyValue('admin_logins'.tr, '${u.loginTimes}'),
                  ],
                ),
              ),
              if (isStudent) ..._studentSections(context, p, u),
              if (!isStudent && d!.j['teacher_profile'] is Map)
                Section(
                  title: 'admin_teacher_profile'.tr,
                  child: Column(
                    children: [
                      KeyValue(
                        'admin_experience'.tr,
                        '${asMap(d!.j['teacher_profile'])['experience_years']}',
                      ),
                      KeyValue(
                        'admin_teaching'.tr,
                        asStr(asMap(d!.j['teacher_profile'])['teaching_type']),
                      ),
                      KeyValue(
                        'admin_payment'.tr,
                        asStr(asMap(d!.j['teacher_profile'])['payment_type']),
                      ),
                    ],
                  ),
                ),
              Section(
                title: 'admin_controls'.tr,
                child: Column(
                  children: [
                    if (isSuperNow(context) &&
                        (u.role == 'student' || u.role == 'teacher')) ...[
                      Row(
                        children: [
                          OutlineButton(
                            label: 'view_as_user'.tr,
                            color: context.colors.success,
                            icon: Icons.visibility_rounded,
                            onPressed: () {
                              final nav = Navigator.of(
                                context,
                                rootNavigator: true,
                              );
                              Navigator.pop(context); // close the sheet first
                              startViewAs(
                                nav,
                                id: u.id,
                                name: u.name,
                                role: u.role,
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    PrimaryButton(
                      label: u.isActive
                          ? 'admin_deactivate_account'.tr
                          : 'admin_activate_account'.tr,
                      isLoading: false,
                      iconBefore: true,

                      icon: u.isActive
                          ? Icons.block_rounded
                          : Icons.check_circle_rounded,
                      background: context.colors.danger,
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          message: u.isActive
                              ? 'admin_deactivate_this_account'.tr
                              : 'admin_activate_this_account'.tr,
                          danger: u.isActive,
                        );
                        if (!ok) return;
                        if (await p.setActive(u.id, !u.isActive)) {
                          await _load();
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    PrimaryButton(
                      // an ACTION label ("Remove verification" / "Verify"), not the current state
                      label: u.isVerified
                          ? 'admin_unverify_account'.tr
                          : 'admin_verify_account'.tr,
                      isLoading: false,
                      iconBefore: true,
                      icon: u.isVerified
                          ? Icons.gpp_bad_rounded
                          : Icons.verified_rounded,
                      background: context.colors.warning,
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          message: u.isVerified
                              ? 'admin_unverified_this_account'.tr
                              : 'admin_verified_this_account'.tr,
                          danger: u.isVerified,
                        );
                        if (!ok) return;
                        if (await p.setVerified(u.id, !u.isVerified)) {
                          await _load();
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlineButton(
                          label: 'btn_edit'.tr,
                          color: context.colors.warning,
                          icon: Icons.edit_rounded,
                          onPressed: () async {
                            await _openForm(context, p, existing: u);
                            await _load();
                          },
                        ),
                        const SizedBox(width: 8),
                        OutlineButton(
                          label: 'delete'.tr,
                          color: context.colors.danger,
                          icon: Icons.delete_outline_rounded,
                          onPressed: () async {
                            final ok = await confirm(
                              context,
                              message:
                                  'admin_permanently_delete_this_user_this'.tr,
                              danger: true,
                            );
                            if (!ok) return;
                            if (await p.remove(u.id) && context.mounted) {
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

  List<Widget> _studentSections(
    BuildContext context,
    AdminUsersProvider p,
    AdminUser u,
  ) {
    final c = context.colors;
    final sub = d!.subscriptions.isEmpty ? null : d!.subscriptions.first;

    return [
      Section(
        title: 'admin_subscription'.tr,
        trailing: TextButton.icon(
          onPressed: () async {
            await _grantDialog(context, p, u.id);
            await _load();
          },
          icon: const Icon(Icons.card_giftcard_rounded, size: 18),
          label: Text('admin_grant'.tr),
        ),
        child: sub == null
            ? Text(
                'admin_no_subscription'.tr,
                style: TextStyle(fontFamily: 'tajawal', color: c.textLight),
              )
            : Column(
                children: [
                  KeyValue('status'.tr, subscriptionStatusLabel(sub.status)),
                  KeyValue('admin_plan'.tr, planLabel(sub.planCode)),
                  KeyValue('admin_from'.tr, shortDate(sub.startsAt)),
                  KeyValue('admin_until'.tr, shortDate(sub.endsAt)),
                  KeyValue('admin_amount'.tr, money(sub.amount, sub.currency)),
                ],
              ),
      ),
      Section(
        title: 'admin_subscribed_courses'.tr,
        trailing: TextButton.icon(
          onPressed: () async {
            await _enrollDialog(context, p, u.id);
            await _load();
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text('admin_enrol'.tr),
        ),
        child: d!.enrollments.isEmpty
            ? Text(
                'admin_no_courses'.tr,
                style: TextStyle(fontFamily: 'tajawal', color: c.textLight),
              )
            : Column(
                children: [
                  for (final e in d!.enrollments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              asStr(e['course_name']),
                              style: TextStyle(
                                fontFamily: 'tajawal',
                                color: c.textDark,
                              ),
                            ),
                          ),
                          StatusChip(
                            enrollmentStatusLabel(asStr(e['status'])),
                            asStr(e['status']) == 'active'
                                ? c.success
                                : (asStr(e['status']) == 'dropped'
                                      ? c.danger
                                      : c.warning),
                          ),
                          if (e['can_resubscribe'] == true)
                            IconButton(
                              tooltip: 'admin_allow_resubscribe'.tr,
                              icon: Icon(
                                Icons.autorenew_rounded,
                                color: c.success,
                                size: 20,
                              ),
                              onPressed: () async {
                                final mode = await _resubscribeDialog(context);
                                if (mode == null) return;
                                if (await p.allowResubscribe(
                                  u.id,
                                  asInt(e['course_id']),
                                  mode: mode,
                                )) {
                                  await _load();
                                }
                              },
                            ),
                          if (asStr(e['status']) != 'dropped')
                            IconButton(
                              tooltip: 'admin_remove'.tr,
                              icon: Icon(
                                Icons.remove_circle_outline_rounded,
                                color: c.danger,
                                size: 20,
                              ),
                              onPressed: () async {
                                final ok = await confirm(
                                  context,
                                  message:
                                      'admin_remove_the_student_from_this_course'
                                          .tr,
                                  danger: true,
                                );
                                if (!ok) return;
                                if (await p.unenroll(
                                  u.id,
                                  asInt(e['course_id']),
                                )) {
                                  await _load();
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      Section(
        title: 'admin_devices'.tr,
        trailing: d!.devices.isEmpty
            ? null
            : TextButton(
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    message: 'admin_remove_all_devices_and_reset_the'.tr,
                    danger: true,
                  );
                  if (!ok) return;
                  if (await p.resetDevices(u.id)) await _load();
                },
                child: Text(
                  'admin_reset_all'.tr,
                  style: TextStyle(color: c.danger),
                ),
              ),
        child: d!.devices.isEmpty
            ? Text(
                'admin_no_registered_devices'.tr,
                style: TextStyle(fontFamily: 'tajawal', color: c.textLight),
              )
            : Column(
                children: [
                  for (final dev in d!.devices)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        Icons.phone_android_rounded,
                        color: c.primary,
                      ),
                      title: Text(
                        dev.deviceName,
                        style: const TextStyle(fontFamily: 'tajawal'),
                      ),
                      subtitle: Text(
                        '${'admin_since'.tr} ${shortDate(dev.boundAt)}',
                        style: const TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 11.5,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: c.danger,
                          size: 20,
                        ),
                        onPressed: () async {
                          if (await p.removeDevice(u.id, dev.id)) await _load();
                        },
                      ),
                    ),
                  if (d!.lastDeviceSwitchAt != null)
                    KeyValue(
                      'admin_last_switch'.tr,
                      shortDate(d!.lastDeviceSwitchAt),
                    ),
                ],
              ),
      ),
      if (d!.payments.isNotEmpty)
        Section(
          title: 'payments'.tr,
          child: Column(
            children: [
              for (final pay in d!.payments.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '#${pay['id']} • ${paymentMethodLabel(asStrOrNull(pay['method']))} • ${shortDate(asStrOrNull(pay['created_at']))}',
                          style: TextStyle(
                            fontFamily: 'tajawal',
                            fontSize: 12.5,
                            color: c.textMedium,
                          ),
                        ),
                      ),
                      Text(
                        money(
                          asDouble(pay['price_paid'], asDouble(pay['amount'])),
                        ),
                        style: TextStyle(
                          fontFamily: 'tajawal',
                          fontWeight: FontWeight.w700,
                          color: c.textDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(
                        paymentStatusLabel(asStr(pay['status'])),
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
    ];
  }
}

Future<void> _grantDialog(
  BuildContext context,
  AdminUsersProvider p,
  int userId,
) async {
  final daysCtrl = TextEditingController();
  String plan = 'monthly';
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Directionality(
        textDirection: dir,
        child: AlertDialog(
          title: Text(
            'admin_grant_subscription'.tr,
            style: const TextStyle(fontFamily: 'tajawal'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChoiceRow<String>(
                options: {
                  'monthly': 'admin_monthly'.tr,
                  'yearly': 'admin_yearly'.tr,
                  'custom': 'admin_custom_days'.tr,
                },
                value: plan,
                onChanged: (v) => setS(() => plan = v),
              ),
              if (plan == 'custom')
                Field(
                  controller: daysCtrl,
                  label: 'admin_days_2'.tr,
                  keyboard: TextInputType.number,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('exam_cancel'.tr),
            ),
            TextButton(
              onPressed: () async {
                final days = int.tryParse(daysCtrl.text.trim());
                if (plan == 'custom' && (days == null || days < 1)) {
                  toast('admin_enter_a_valid_number_of_days'.tr, error: true);
                  return;
                }
                Navigator.pop(ctx);
                await p.grant(
                  userId,
                  planCode: plan == 'custom' ? null : plan,
                  days: plan == 'custom' ? days : null,
                );
              },
              child: Text('admin_grant'.tr),
            ),
          ],
        ),
      ),
    ),
  );
  disposeAfterRoute([daysCtrl]);
}

/// Returns 'allow_payment' (student pays again) | 'reopen' (re-activate, no payment) | null.
Future<String?> _resubscribeDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: dir,
      child: SimpleDialog(
        title: Text(
          'admin_allow_resubscribe'.tr,
          style: const TextStyle(fontFamily: 'tajawal'),
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'allow_payment'),
            child: Text(
              'admin_resubscribe_allow_payment'.tr,
              style: const TextStyle(fontFamily: 'tajawal'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'reopen'),
            child: Text(
              'admin_resubscribe_reopen'.tr,
              style: const TextStyle(fontFamily: 'tajawal'),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _enrollDialog(
  BuildContext context,
  AdminUsersProvider p,
  int userId,
) async {
  final courses = await p.courseChoices();
  if (!context.mounted) return;
  if (courses.isEmpty) {
    toast('admin_no_courses'.tr, error: true);
    return;
  }
  final picked = await showDialog<AdminCourse>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: dir,
      child: SimpleDialog(
        title: Text(
          'admin_choose_a_course'.tr,
          style: const TextStyle(fontFamily: 'tajawal'),
        ),
        children: [
          SizedBox(
            width: double.maxFinite,
            height: 360,
            child: ListView(
              children: [
                for (final c in courses)
                  ListTile(
                    title: Text(
                      c.name,
                      style: const TextStyle(fontFamily: 'tajawal'),
                    ),
                    subtitle: Text(
                      c.teacherName,
                      style: const TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 12,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, c),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  if (picked != null) await p.enroll(userId, picked.id);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Create / edit form
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openForm(
  BuildContext context,
  AdminUsersProvider p, {
  AdminUser? existing,
}) {
  return showAdminSheet(
    context,
    (ctx) => _UserForm(provider: p, existing: existing),
  );
}

class _UserForm extends StatefulWidget {
  const _UserForm({required this.provider, this.existing});

  final AdminUsersProvider provider;
  final AdminUser? existing;

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _email = TextEditingController(text: widget.existing?.gmail);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  final _password = TextEditingController();
  final _years = TextEditingController(text: '0');
  bool busy = false;

  bool get editing => widget.existing != null;

  String get role => widget.provider.role;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _years]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    bool ok;

    if (editing) {
      ok = await widget.provider.update(widget.existing!.id, {
        'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'gmail': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'country': kPhoneCountries
            .firstWhere((e) => _phone.text.contains(e.dial))
            .flag,
        if (_password.text.isNotEmpty) 'password': _password.text,
      });
    } else {
      ok = await widget.provider.create({
        'name': _name.text.trim(),
        'gmail': _email.text.trim(),
        'password': _password.text,
        'role': role,
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'country':  kPhoneCountries
          .firstWhere((e) => _phone.text.contains(e.dial))
          .flag,
        if (role == 'teacher')
          'experience_years': int.tryParse(_years.text.trim()) ?? 0,
      });
    }
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          editing
              ? 'admin_edit_user'.tr
              : (role == 'teacher'
                    ? 'admin_add_teacher'.tr
                    : 'admin_add_student'.tr),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Form(
              key: _form,
              child: Column(
                children: [
                  Field(
                    controller: _name,
                    label: 'name_label'.tr,
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'admin_name_is_required'.tr
                        : null,
                  ),
                  AppEmailField(controller: _email, label: 'admin_email'.tr),
                  PhoneInputField(controller: _phone, label: 'admin_phone'.tr),
                  if (!editing && role == 'teacher')
                    Field(
                      controller: _years,
                      label: 'admin_experience_years'.tr,
                      keyboard: TextInputType.number,
                    ),
                  AppPasswordField(controller: _password, label: editing
                        ? 'admin_new_password_optional'.tr
                        : 'password'.tr, required: !editing),
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
