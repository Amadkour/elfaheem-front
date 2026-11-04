// lib/features/admin/admin_users_page.dart — students & teachers (list, detail, control).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/phone_field.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_filter_models.dart';
import 'admin_filters.dart';
import 'admin_labels.dart';
import 'admin_list.dart';
import 'admin_page.dart';
import 'admin_table_export.dart' show adminUsersExport, exportPagedList;
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_view_as_page.dart' show startViewAs;
import 'admin_mfa_page.dart' show confirmResetUserMfa, mfaResetLabel;
import '../auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_badges.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppDropdown, AppEmpty, AppListSkeleton;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_username.dart' show usernameFrom;
import '../auth/username.dart' show UsernameError;
import '../auth/username_field.dart' show UsernameStatus;
import 'admin_username_field.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key, required this.role, this.embedded = false});

  /// 'student' | 'teacher'
  final String role;

  /// true when shown as a tab inside the dashboard shell (no Back).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminUsersProvider(role)..refresh(),
      child: _UsersView(role: role, embedded: embedded),
    );
  }
}

class _UsersView extends StatefulWidget {
  const _UsersView({required this.role, required this.embedded});

  final String role;
  final bool embedded;

  @override
  State<_UsersView> createState() => _UsersViewState();
}

class _UsersViewState extends State<_UsersView> {
  bool get isStudent => widget.role == 'student';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // the shell's Refresh reloads the list in place: filters, search text and scroll stay
    AdminRefreshScope.register(context, context.read<AdminUsersProvider>().refresh);
  }

  /// The server's sort value -> the table column it belongs to.
  String? _sortKey(String? s) {
    if (s == null) return null;
    if (s.startsWith('name')) return 'name';
    if (s == 'newest' || s == 'oldest') return 'joined';
    if (s == 'last_login') return 'last_login';
    return null;
  }

  void _onSort(AdminUsersProvider p, String key, bool asc) {
    p.setSort(switch (key) {
      'name' => asc ? 'name_asc' : 'name_desc',
      'joined' => asc ? 'oldest' : 'newest',
      _ => 'last_login',
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminUsersProvider>();
    final specs = _userSpecs(isStudent);
    final canViewAs = isSuperNow(context);
    final users = [for (final r in p.rows) AdminUser(r)];
    final wide = MediaQuery.sizeOf(context).width >= 600;

    final state = p.error != null && p.rows.isEmpty
        ? AppTableState.error
        : (!p.loaded && p.isLoading ? AppTableState.loading : AppTableState.ready);

    final table = AppDataTable<AdminUser>(
      state: state,
      errorText: p.error,
      onRetry: p.refresh,
      rows: users,
      rowId: (u) => u.id,
      searchHint: 'admin_search_name_email_or_phone'.tr,
      onSearch: p.setSearch,
      toolbarTrailing: _controls(context, p, specs),
      columns: [
        AppTableColumn<AdminUser>(
          key: 'name',
          label: 'name_label'.tr,
          primary: true,
          sortable: true,
          flex: 3,
          cell: (ctx, u) => _NameCell(u),
        ),
        AppTableColumn<AdminUser>(
          key: 'contact',
          label: 'admin_email'.tr,
          flex: 3,
          cell: (ctx, u) => _ContactCell(u),
        ),
        AppTableColumn<AdminUser>(
          key: 'status',
          label: 'status'.tr,
          flex: 2,
          cell: (ctx, u) => _StatusCell(u, isStudent: isStudent),
        ),
        AppTableColumn<AdminUser>.text(
          key: 'courses',
          label: t('الدورات', 'Courses'),
          flex: 1,
          text: (u) => _coursesText(isStudent ? u.enrolledCourses.length : u.coursesCount),
        ),
        AppTableColumn<AdminUser>.text(
          key: 'joined',
          label: 'admin_joined'.tr,
          sortable: true,
          flex: 2,
          showOnPhone: false,
          text: (u) => shortDate(u.createdAt),
        ),
        AppTableColumn<AdminUser>.text(
          key: 'last_login',
          label: 'admin_last_login'.tr,
          sortable: true,
          flex: 2,
          showOnPhone: false,
          text: (u) => shortDateTime(u.lastLogin),
        ),
      ],
      sortKey: _sortKey(p.sort),
      sortAscending: p.sort == 'name_asc' || p.sort == 'oldest',
      onSort: (k, asc) => _onSort(p, k, asc),
      onRowTap: (u) => _openDetail(context, p, u.id),
      rowActions: (u) => [
        if (canViewAs && (u.role == 'student' || u.role == 'teacher'))
          AppRowAction<AdminUser>(
            icon: Icons.visibility_rounded,
            label: 'view_as_user'.tr,
            onTap: () => startViewAs(Navigator.of(context, rootNavigator: true), id: u.id, name: u.name, role: u.role),
          ),
        AppRowAction<AdminUser>(
          icon: Icons.open_in_new_rounded,
          label: t('فتح', 'Open'),
          onTap: () => _openDetail(context, p, u.id),
        ),
      ],
      empty: p.hasActiveQuery
          ? AppEmpty(
              icon: Icons.search_off_rounded,
              title: 'ds_no_results'.tr,
              message: 'ds_no_results_hint'.tr,
              actionLabel: 'ds_clear_filters'.tr,
              onAction: p.clearAll,
            )
          : AppEmpty(
              icon: Icons.inbox_outlined,
              title: isStudent ? 'admin_no_students_found'.tr : 'admin_no_teachers_found'.tr,
            ),
      onClearFilters: p.clearAll,
      onLoadMore: p.loadMore,
      hasMore: p.hasMore,
      loadingMore: p.loadingMore,
    );

    return AdminPage(
      helpPageId: 'admin.users',
      title: isStudent ? 'admin_students'.tr : 'admin_teachers'.tr,
      icon: isStudent ? Icons.school_rounded : Icons.person_pin_rounded,
      subtitle: wide && p.loaded ? _totalText(p.total) : null,
      showBack: !widget.embedded,
      maxWidth: double.infinity,
      onRefresh: p.refresh,
      primaryAction: AppButton.primary(
        key: const ValueKey('users_add'),
        label: isStudent ? 'admin_add_student'.tr : 'admin_add_teacher'.tr,
        icon: Icons.person_add_alt_1_rounded,
        onPressed: () => _openForm(context, p),
      ),
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminActiveFilterChips(host: p, specs: specs, sort: _userSort, quickKeys: const {'status'}),
          Expanded(child: table),
        ]),
      ),
    );
  }

  String _totalText(int n) => isStudent
      ? countText(n,
          ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالباً', en1: '1 student', en: '{n} students')
      : countText(n,
          ar1: 'معلم واحد', ar2: 'معلمان', arFew: '{n} معلمين', arMany: '{n} معلماً', en1: '1 teacher', en: '{n} teachers');

  /// The search lives in the table toolbar; this is the rest of the ONE row of controls: the status filter, the
  /// advanced filter sheet (everything else, subscription filter included) and Export.
  Widget _controls(BuildContext context, AdminUsersProvider p, List<FilterSpec> specs) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 168),
          child: AppDropdown<String>(
          value: p.status ?? 'all',
          decoration: InputDecoration(labelText: 'admin_filter_status'.tr),
          items: [
            DropdownMenuItem(value: 'all', child: Text('filter_all'.tr)),
            DropdownMenuItem(value: 'active', child: Text('exam_status_active'.tr)),
            DropdownMenuItem(value: 'inactive', child: Text('admin_inactive'.tr)),
            DropdownMenuItem(value: 'pending_deletion', child: Text('admin_pending_deletion'.tr)),
          ],
          onChanged: (v) => p.setStatus(v == null || v == 'all' ? null : v),
          ),
        ),
      ),
      const SizedBox(width: AppSpace.xxs),
      AdminFilterButton(host: p, specs: specs, sort: _userSort, quickKeys: const {'status'}),
      AppIconButton(
        icon: Icons.ios_share_rounded,
        tooltip: t('تصدير', 'Export'),
        onPressed: p.rows.isEmpty
            ? null
            : () => exportPagedList(context, p, (rows) => adminUsersExport(widget.role, rows)),
      ),
    ]);
  }
}

/// "3 courses" / "ثلاث دورات" (the number is part of the text).
String _coursesText(int n) => countText(
      n,
      ar0: 'لا دورات',
      ar1: 'دورة واحدة',
      ar2: 'دورتان',
      arFew: '{n} دورات',
      arMany: '{n} دورة',
      en0: 'No courses',
      en1: '1 course',
      en: '{n} courses',
    );

class _NameCell extends StatelessWidget {
  const _NameCell(this.u);

  final AdminUser u;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      AdminAvatar(name: u.name, url: u.imageUrl, size: 36),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
      ),
    ]);
  }
}

/// Email on the first line, the @username (or the phone) under it.
class _ContactCell extends StatelessWidget {
  const _ContactCell(this.u);

  final AdminUser u;

  @override
  Widget build(BuildContext context) {
    final uname = usernameFrom(u.j);
    final second = uname != null ? '@$uname' : u.phone;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(u.gmail.isEmpty ? '—' : u.gmail,
          maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.row(context)),
      if (second.isNotEmpty)
        Text(second,
            maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
    ]);
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell(this.u, {required this.isStudent});

  final AdminUser u;
  final bool isStudent;

  @override
  Widget build(BuildContext context) {
    final sub = u.subscription;
    return Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
      if (u.pendingDeletion)
        AppStatusBadge(label: 'admin_pending_deletion'.tr, tone: AppTone.danger, dense: true)
      else
        AppStatusBadge(
          label: u.isActive ? 'exam_status_active'.tr : 'admin_inactive'.tr,
          tone: u.isActive ? AppTone.success : AppTone.warning,
          dense: true,
        ),
      if (isStudent)
        AppStatusBadge(
          label: u.hasActiveSubscription
              ? 'admin_subscribed'.tr
              : (sub?.status == 'pending' ? 'admin_sub_pending'.tr : 'admin_no_sub'.tr),
          tone: u.hasActiveSubscription
              ? AppTone.success
              : (sub?.status == 'pending' ? AppTone.warning : AppTone.neutral),
          dense: true,
        ),
    ]);
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

// ═════════════════════════════════════════════════════════════════════════════
//  Detail / control sheet
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the detail / control sheet of ONE user by id (the global search uses it). [role] is the list the user
/// belongs to ('student' | 'teacher' | 'admin'); the sheet loads the user itself, like a row tap does.
Future<void> showAdminUserDetail(BuildContext context, {required int userId, required String role}) async {
  // not disposed on purpose: a request of the sheet may still be in flight when it closes, and a provider with no
  // timer and no listener left is simply garbage collected
  await _openDetail(context, AdminUsersProvider(role), userId);
}

String _experienceText(Object? years) {
  final n = years is num ? years.toInt() : int.tryParse('${years ?? ''}');
  if (n == null) return '—';
  return countText(n,
      ar0: 'أقل من سنة',
      ar1: 'سنة واحدة',
      ar2: 'سنتان',
      arFew: '{n} سنوات',
      arMany: '{n} سنة',
      en0: 'Less than a year',
      en1: '1 year',
      en: '{n} years');
}

String _teachingLabel(String v) => switch (v) {
      'live' => t('مباشر', 'Live'),
      'recorded' => t('مسجّل', 'Recorded'),
      'both' => t('مباشر ومسجّل', 'Live and recorded'),
      '' => '—',
      _ => v,
    };

String _paymentLabel(String v) => switch (v) {
      'free' => t('مجاني', 'Free'),
      'paid' => t('مدفوع', 'Paid'),
      'both' => t('مجاني ومدفوع', 'Free and paid'),
      '' => '—',
      _ => v,
    };

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
    // the sheet may have been closed while an action was running (Edit, Deactivate …): nothing to redraw
    if (!mounted) return;
    if (spinner && !loading) setState(() => loading = true);
    final provider = context.read<AdminUsersProvider>();
    final r = await provider.detail(widget.userId);
    if (!mounted) return;
    setState(() {
      d = r;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.read<AdminUsersProvider>();

    if (loading) {
      return const SizedBox(
        height: 260,
        child: AppListSkeleton(items: 3),
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
                      KeyValue('admin_experience'.tr, _experienceText(asMap(d!.j['teacher_profile'])['experience_years'])),
                      KeyValue(t('الدورات', 'Courses'), _coursesText(u.coursesCount)),
                      KeyValue(
                        'admin_teaching'.tr,
                        _teachingLabel(asStr(asMap(d!.j['teacher_profile'])['teaching_type'])),
                      ),
                      KeyValue(
                        'admin_payment'.tr,
                        _paymentLabel(asStr(asMap(d!.j['teacher_profile'])['payment_type'])),
                      ),
                    ],
                  ),
                ),
              Section(
                title: 'admin_controls'.tr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // primary row: View as, Edit
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        if (isSuperNow(context) && (u.role == 'student' || u.role == 'teacher'))
                          AppButton.tonal(
                            key: const ValueKey('admin.user_view_as'),
                            label: 'view_as_user'.tr,
                            icon: Icons.visibility_rounded,
                            onPressed: () {
                              final nav = Navigator.of(context, rootNavigator: true);
                              Navigator.pop(context); // close the sheet first
                              startViewAs(nav, id: u.id, name: u.name, role: u.role);
                            },
                          ),
                        AppButton.secondary(
                          key: const ValueKey('admin.user_edit'),
                          label: 'btn_edit'.tr,
                          icon: Icons.edit_rounded,
                          onPressed: () async {
                            await _openForm(context, p, existing: u);
                            if (mounted) await _load();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.sm),
                    // account state: verify / unverify, Activate (not a danger action), a lost authenticator
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        if (!u.isActive)
                          AppButton.tonal(
                            key: const ValueKey('admin.user_activate'),
                            label: 'admin_activate_account'.tr,
                            icon: Icons.check_circle_rounded,
                            onPressed: () async {
                              final ok = await confirm(context, message: 'admin_activate_this_account'.tr);
                              if (!ok || !mounted) return;
                              if (await p.setActive(u.id, true) && mounted) await _load();
                            },
                          ),
                        AppButton.secondary(
                          key: const ValueKey('admin.user_verify'),
                          // an ACTION label ("Remove verification" / "Verify"), not the current state
                          label: u.isVerified ? 'admin_unverify_account'.tr : 'admin_verify_account'.tr,
                          icon: u.isVerified ? Icons.gpp_bad_rounded : Icons.verified_rounded,
                          onPressed: () async {
                            final ok = await confirm(
                              context,
                              message: u.isVerified
                                  ? 'admin_unverified_this_account'.tr
                                  : 'admin_verified_this_account'.tr,
                              danger: u.isVerified,
                            );
                            if (!ok || !mounted) return;
                            if (await p.setVerified(u.id, !u.isVerified) && mounted) await _load();
                          },
                        ),
                        // super admin: a user who lost both the phone and the recovery codes (the server answers
                        // mfa_not_enabled when there is nothing to remove)
                        if (isSuperNow(context) && context.read<MyAuthProvider>().currentUser?.id != u.id)
                          AppButton.ghost(
                            key: const ValueKey('admin.user_mfa_reset'),
                            label: mfaResetLabel(),
                            icon: Icons.phonelink_erase_rounded,
                            onPressed: () => confirmResetUserMfa(context, userId: u.id, name: u.name),
                          ),
                      ],
                    ),
                    // danger zone: only Deactivate and Delete are red
                    const SizedBox(height: AppSpace.md),
                    Divider(color: context.colors.divider, height: 1),
                    const SizedBox(height: AppSpace.md),
                    Text(t('منطقة الخطر', 'Danger zone'), style: AppType.label(context).copyWith(color: context.colors.danger)),
                    const SizedBox(height: AppSpace.xs),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        if (u.isActive)
                          AppButton.danger(
                            key: const ValueKey('admin.user_deactivate'),
                            dangerOutline: true,
                            label: 'admin_deactivate_account'.tr,
                            icon: Icons.block_rounded,
                            onPressed: () async {
                              final ok = await confirm(
                                context,
                                message: '${u.name}\n${'admin_deactivate_this_account'.tr}',
                                danger: true,
                              );
                              if (!ok || !mounted) return;
                              if (await p.setActive(u.id, false) && mounted) await _load();
                            },
                          ),
                        AppButton.danger(
                          key: const ValueKey('admin.user_delete'),
                          dangerOutline: true,
                          label: 'delete'.tr,
                          icon: Icons.delete_outline_rounded,
                          onPressed: () async {
                            final ok = await confirm(
                              context,
                              message: '${u.name}\n${'admin_permanently_delete_this_user_this'.tr}',
                              danger: true,
                            );
                            if (!ok || !mounted) return;
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
                style: TextStyle(fontFamily: AppFonts.family, color: c.textLight),
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
                style: TextStyle(fontFamily: AppFonts.family, color: c.textLight),
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
                                fontFamily: AppFonts.family,
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
                style: TextStyle(fontFamily: AppFonts.family, color: c.textLight),
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
                        style: TextStyle(fontFamily: AppFonts.family),
                      ),
                      subtitle: Text(
                        '${'admin_since'.tr} ${shortDate(dev.boundAt)}',
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 11.5,
                        ),
                      ),
                      trailing: IconButton(tooltip: t('حذف', 'Delete'), 
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
                            fontFamily: AppFonts.family,
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
                          fontFamily: AppFonts.family,
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
          scrollable: true,
          title: Text(
            'admin_grant_subscription'.tr,
            style: TextStyle(fontFamily: AppFonts.family),
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
          style: TextStyle(fontFamily: AppFonts.family),
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'allow_payment'),
            child: Text(
              'admin_resubscribe_allow_payment'.tr,
              style: TextStyle(fontFamily: AppFonts.family),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'reopen'),
            child: Text(
              'admin_resubscribe_reopen'.tr,
              style: TextStyle(fontFamily: AppFonts.family),
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
          style: TextStyle(fontFamily: AppFonts.family),
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
                      style: TextStyle(fontFamily: AppFonts.family),
                    ),
                    subtitle: Text(
                      c.teacherName,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
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
  // the row's @username: an admin may set, change or remove it (D-071, admin edit)
  late final String? _currentUsername = usernameFrom(widget.existing?.j);
  late final _username = TextEditingController(text: _currentUsername ?? '');
  UsernameError? _usernameError;
  UsernameStatus _usernameStatus = UsernameStatus.current;
  bool busy = false;

  bool get editing => widget.existing != null;

  String get role => widget.provider.role;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _years, _username]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final uname = editing
        ? adminUsernameBody(current: _currentUsername, text: _username.text, enabled: adminUsernameOn)
        : const <String, Object?>{};
    final hold = adminUsernameHold(uname, _usernameStatus);
    if (hold != null) {
      toast(hold, error: _usernameStatus != UsernameStatus.checking);
      return;
    }
    setState(() => busy = true);
    bool ok;

    if (editing) {
      ok = await widget.provider.update(widget.existing!.id, {
        'name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'gmail': _email.text.trim().isEmpty ? null : _email.text.trim(),
        // no known dial code (or no phone): leave the stored country alone instead of throwing
        if (kPhoneCountries.where((e) => _phone.text.contains(e.dial)).firstOrNull case final pc?) 'country': pc.flag,
        if (_password.text.isNotEmpty) 'password': _password.text,
        ...uname,
      }, onError: (e) {
        final err = UsernameError.from(e, submitted: _username.text);
        if (err != null && mounted) setState(() => _usernameError = err);
      });
    } else {
      ok = await widget.provider.create({
        'name': _name.text.trim(),
        'gmail': _email.text.trim(),
        'password': _password.text,
        'role': role,
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        // no known dial code (or no phone): leave the stored country alone instead of throwing
        if (kPhoneCountries.where((e) => _phone.text.contains(e.dial)).firstOrNull case final pc?) 'country': pc.flag,
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
                  if (editing)
                    AdminUsernameField(
                      controller: _username,
                      currentUsername: _currentUsername,
                      error: _usernameError,
                      onStatusChanged: (s) => setState(() => _usernameStatus = s),
                    ),
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
