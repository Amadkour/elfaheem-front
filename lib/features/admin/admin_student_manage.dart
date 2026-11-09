// lib/features/admin/admin_student_manage.dart — managing a student from their detail (D-290, phase 4).
//
// Everything the old management sheet held lives here, for those whose `can.manage` is true, in whichever host shows
// the detail (the Students list's panel, a panel over another list, the full page):
//
//   the header's quick actions   Edit · Message · View as (super admins)
//   the courses section          Enrol; on a course: Remove (with the reason it is recorded under) · Allow resubscribe
//   the sections under the data  Subscription (Grant) · Account · Devices · Controls (verify, reset MFA, deactivate,
//                                delete)
//
// Loaded on demand through loadStudentManage (design/master_detail/student_detail.dart): `deferred`, so learners and
// teachers never download it. Reads and writes `/api/v1/admin/users/{id}` through AdminUsersProvider.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/master_detail/entity_detail_view.dart';
import 'package:flutter_education_app/design/master_detail/entity_specs.dart';
import 'package:flutter_education_app/design/master_detail/student_detail.dart';
import 'package:provider/provider.dart';

import '../auth/auth_provider.dart' show MyAuthProvider;
import 'admin_common.dart';
import 'admin_labels.dart';
import 'admin_mfa_page.dart' show confirmResetUserMfa, mfaResetLabel;
import 'admin_models.dart';
import 'admin_providers.dart';
import 'admin_send_message_page.dart';
import 'admin_users_page.dart' show openAdminUserForm;
import 'admin_view_as_page.dart' show startViewAs;

/// See [loadStudentManage].
StudentManage createStudentManage(EntityRef student, {required VoidCallback onChanged, required VoidCallback onDeleted}) =>
    _AdminStudentManage(student, onChanged: onChanged, onDeleted: onDeleted);

/// The provider's calls without its list: the detail has no rows of users to refresh.
class _UserCalls extends AdminUsersProvider {
  _UserCalls() : super('student');

  @override
  Future<void> refresh() async {}
}

/// A super admin on screen (a host without the auth provider above it: no).
bool _isSuper(BuildContext context) {
  try {
    return isSuperNow(context);
  } on ProviderNotFoundException {
    return false;
  }
}

/// The reasons a manager can record when taking a student out of a course (the server's WITHDRAWAL_CODES without the
/// ones only the system writes).
const _reasonCodes = ['admin', 'price', 'time', 'content_mismatch', 'quality', 'technical', 'personal', 'not_passed', 'other'];

class _AdminStudentManage extends StudentManage {
  _AdminStudentManage(this.student, {required this.onChanged, required this.onDeleted}) {
    _load();
  }

  final EntityRef student;
  final VoidCallback onChanged;
  final VoidCallback onDeleted;
  final _p = _UserCalls();

  UserDetail? _detail;
  bool _loading = true;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    final d = await _p.detail(student.id);
    if (_disposed) return;
    _detail = d ?? _detail;
    _loading = false;
    notifyListeners();
  }

  Future<void> _retry() async {
    _loading = true;
    notifyListeners();
    await _load();
  }

  /// After a change on the server: this part and the rest of the detail load again.
  Future<void> _changed() async {
    await _load();
    if (!_disposed) onChanged();
  }

  // ── quick actions ──────────────────────────────────────────────────────────

  @override
  List<EntityPanelAction> headerActions(BuildContext context) {
    final d = _detail;
    if (d == null) return const [];
    final u = d.user;
    return [
      EntityPanelAction(
        key: const ValueKey('admin.user_edit'),
        icon: Icons.edit_rounded,
        label: 'btn_edit'.tr,
        onPressed: () async {
          await openAdminUserForm(context, _p, existing: u);
          await _changed();
        },
      ),
      EntityPanelAction(
        key: const ValueKey('md.student.message'),
        icon: Icons.send_rounded,
        label: 'md_p4_message'.tr,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => AdminSendMessagePage(student: {'id': u.id, 'name': u.name}))),
      ),
      if (_isSuper(context))
        EntityPanelAction(
          key: const ValueKey('admin.user_view_as'),
          icon: Icons.visibility_rounded,
          label: 'view_as_user'.tr,
          onPressed: () =>
              startViewAs(Navigator.of(context, rootNavigator: true), id: u.id, name: u.name, role: u.role),
        ),
    ];
  }

  // ── courses ────────────────────────────────────────────────────────────────

  @override
  Widget? coursesAction(BuildContext context) => _detail == null
      ? null
      : AppButton.tonal(
          key: const ValueKey('md.student.enrol'),
          label: 'admin_enrol'.tr,
          icon: Icons.add_rounded,
          size: AppButtonSize.sm,
          onPressed: () async {
            final course = await _pickCourse(context, _p);
            if (course != null && await _p.enroll(student.id, course.id)) await _changed();
          },
        );

  /// The server's own answer when the detail has loaded, else the row's state.
  bool _canResubscribe(EnrollmentRow row) {
    for (final e in _detail?.enrollments ?? const <Map<String, dynamic>>[]) {
      if (asInt(e['course_id']) == row.subject.id) return e['can_resubscribe'] == true;
    }
    return row.enrollment.state == 'withdrawn' || row.enrollment.state == 'expired';
  }

  @override
  List<EntityPanelAction> courseActions(BuildContext context, EnrollmentRow row) {
    final courseId = row.subject.id;
    return [
      if (_canResubscribe(row))
        EntityPanelAction(
          key: ValueKey('md.student.resubscribe.$courseId'),
          icon: Icons.autorenew_rounded,
          label: 'admin_allow_resubscribe'.tr,
          onPressed: () async {
            final mode = await _resubscribeDialog(context);
            if (mode != null && await _p.allowResubscribe(student.id, courseId, mode: mode)) await _changed();
          },
        ),
      if (row.enrollment.state != 'withdrawn')
        EntityPanelAction(
          key: ValueKey('md.student.remove.$courseId'),
          icon: Icons.remove_circle_outline_rounded,
          label: 'admin_remove'.tr,
          danger: true,
          onPressed: () async {
            final why = await _removeSheet(context, student.name, row.subject.name);
            if (why == null) return;
            if (await _p.unenroll(student.id, courseId, reasonCode: why.$1, reason: why.$2)) await _changed();
          },
        ),
    ];
  }

  // ── sections ───────────────────────────────────────────────────────────────

  @override
  List<Widget> sections(BuildContext context) {
    final d = _detail;
    Widget card(String key, IconData icon, Widget child, {Widget? trailing}) => EntitySectionCard(
          spec: EntitySectionSpec(key, icon: icon, titleKey: key, shape: EntitySectionShape.block),
          trailing: trailing,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs), child: child),
        );
    if (d == null) {
      return [
        card(
          'admin_controls',
          Icons.admin_panel_settings_outlined,
          _loading
              ? const AppListSkeleton(items: 2, padding: EdgeInsets.zero)
              : AppErrorState(message: 'admin_could_not_load_data'.tr, onRetry: _retry, compact: true),
        ),
      ];
    }
    final u = d.user;
    final sub = d.subscriptions.isEmpty ? null : d.subscriptions.first;
    return [
      card(
        'admin_subscription',
        Icons.card_membership_rounded,
        sub == null
            ? Text('admin_no_subscription'.tr, style: AppType.body(context))
            : EntityFactGrid([
                EntityFact('status'.tr, subscriptionStatusLabel(sub.status)),
                EntityFact('admin_plan'.tr, planLabel(sub.planCode)),
                EntityFact('admin_from'.tr, shortDate(sub.startsAt)),
                EntityFact('admin_until'.tr, shortDate(sub.endsAt)),
                EntityFact('admin_amount'.tr, money(sub.amount, sub.currency)),
              ]),
        trailing: AppButton.tonal(
          key: const ValueKey('md.student.grant'),
          label: 'admin_grant'.tr,
          icon: Icons.card_giftcard_rounded,
          size: AppButtonSize.sm,
          onPressed: () async {
            await _grantDialog(context, _p, u.id);
            await _changed();
          },
        ),
      ),
      card(
        'admin_profile_2',
        Icons.badge_outlined,
        EntityFactGrid([
          EntityFact(
              'status'.tr,
              u.pendingDeletion
                  ? 'admin_pending_deletion'.tr
                  : (u.isActive ? 'exam_status_active'.tr : 'admin_inactive'.tr)),
          EntityFact('md_p4_verified'.tr, u.isVerified ? 'md_p4_yes'.tr : 'md_p4_no'.tr),
          EntityFact('country'.tr, u.country.isEmpty ? '—' : u.country),
          EntityFact('admin_birth_date'.tr, shortDate(u.dob)),
          EntityFact('admin_logins'.tr, '${u.loginTimes}'),
        ]),
      ),
      card(
        'admin_devices',
        Icons.devices_rounded,
        _devices(context, d, u),
        trailing: d.devices.isEmpty
            ? null
            : AppButton.ghost(
                key: const ValueKey('md.student.reset_devices'),
                label: 'admin_reset_all'.tr,
                size: AppButtonSize.sm,
                onPressed: () async {
                  final ok = await confirm(context, message: 'admin_remove_all_devices_and_reset_the'.tr, danger: true);
                  if (ok && await _p.resetDevices(u.id)) await _changed();
                },
              ),
      ),
      card('admin_controls', Icons.admin_panel_settings_outlined, _controls(context, u)),
    ];
  }

  Widget _devices(BuildContext context, UserDetail d, AdminUser u) {
    if (d.devices.isEmpty) return Text('admin_no_registered_devices'.tr, style: AppType.body(context));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final dev in d.devices)
        Row(children: [
          entityToneIcon(context, Icons.phone_android_rounded, AppTone.brand),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(dev.deviceName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              Text('${'admin_since'.tr} ${shortDate(dev.boundAt)}', style: AppType.meta(context)),
            ]),
          ),
          AppIconButton(
            key: ValueKey('md.student.device.${dev.id}'),
            icon: Icons.delete_outline_rounded,
            tooltip: 'delete'.tr,
            onPressed: () async {
              if (await _p.removeDevice(u.id, dev.id)) await _changed();
            },
          ),
        ]),
      if (d.lastDeviceSwitchAt != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text('${'admin_last_switch'.tr}: ${shortDate(d.lastDeviceSwitchAt)}', style: AppType.meta(context)),
      ],
    ]);
  }

  Widget _controls(BuildContext context, AdminUser u) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // account state: verify / unverify, Activate (not a danger action), a lost authenticator
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
        if (!u.isActive)
          AppButton.tonal(
            key: const ValueKey('admin.user_activate'),
            label: 'admin_activate_account'.tr,
            icon: Icons.check_circle_rounded,
            onPressed: () async {
              final ok = await confirm(context, message: 'admin_activate_this_account'.tr);
              if (ok && await _p.setActive(u.id, true)) await _changed();
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
              message: u.isVerified ? 'admin_unverified_this_account'.tr : 'admin_verified_this_account'.tr,
              danger: u.isVerified,
            );
            if (ok && await _p.setVerified(u.id, !u.isVerified)) await _changed();
          },
        ),
        // super admin: a user who lost both the phone and the recovery codes (the server answers mfa_not_enabled when
        // there is nothing to remove)
        if (_isSuper(context) && context.read<MyAuthProvider>().currentUser?.id != u.id)
          AppButton.ghost(
            key: const ValueKey('admin.user_mfa_reset'),
            label: mfaResetLabel(),
            icon: Icons.phonelink_erase_rounded,
            onPressed: () => confirmResetUserMfa(context, userId: u.id, name: u.name),
          ),
      ]),
      // danger zone: only Deactivate and Delete are red
      Divider(height: AppSpace.xl, thickness: AppBorder.hairline, color: context.colors.divider),
      Text(t('منطقة الخطر', 'Danger zone'), style: AppType.label(context).copyWith(color: context.colors.danger)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
        if (u.isActive)
          AppButton.danger(
            key: const ValueKey('admin.user_deactivate'),
            dangerOutline: true,
            label: 'admin_deactivate_account'.tr,
            icon: Icons.block_rounded,
            onPressed: () async {
              final ok = await confirm(context, message: '${u.name}\n${'admin_deactivate_this_account'.tr}', danger: true);
              if (ok && await _p.setActive(u.id, false)) await _changed();
            },
          ),
        AppButton.danger(
          key: const ValueKey('admin.user_delete'),
          dangerOutline: true,
          label: 'delete'.tr,
          icon: Icons.delete_outline_rounded,
          onPressed: () async {
            final ok = await confirm(context,
                message: '${u.name}\n${'admin_permanently_delete_this_user_this'.tr}', danger: true);
            if (ok && await _p.remove(u.id)) onDeleted();
          },
        ),
      ]),
    ]);
  }
}

// ── sheets ───────────────────────────────────────────────────────────────────

Future<void> _grantDialog(BuildContext context, AdminUsersProvider p, int userId) async {
  final daysCtrl = TextEditingController();
  String plan = 'monthly';
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Directionality(
        textDirection: dir,
        child: AlertDialog(
          scrollable: true,
          title: Text('admin_grant_subscription'.tr, style: AppType.section(ctx)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
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
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppNumberField(controller: daysCtrl, label: 'admin_days_2'.tr, min: 1),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('exam_cancel'.tr)),
            TextButton(
              onPressed: () async {
                final days = int.tryParse(daysCtrl.text.trim());
                if (plan == 'custom' && (days == null || days < 1)) {
                  toast('admin_enter_a_valid_number_of_days'.tr, error: true);
                  return;
                }
                Navigator.pop(ctx);
                await p.grant(userId, planCode: plan == 'custom' ? null : plan, days: plan == 'custom' ? days : null);
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
Future<String?> _resubscribeDialog(BuildContext context) => showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: dir,
        child: SimpleDialog(
          title: Text('admin_allow_resubscribe'.tr, style: AppType.section(ctx)),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'allow_payment'),
              child: Text('admin_resubscribe_allow_payment'.tr, style: AppType.body(ctx)),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'reopen'),
              child: Text('admin_resubscribe_reopen'.tr, style: AppType.body(ctx)),
            ),
          ],
        ),
      ),
    );

/// The course to enrol the student in, from the courses the admin list returns (a search once there are many).
Future<AdminCourse?> _pickCourse(BuildContext context, AdminUsersProvider p) async {
  final courses = await p.courseChoices();
  if (!context.mounted) return null;
  if (courses.isEmpty) {
    toast('admin_no_courses'.tr, error: true);
    return null;
  }
  var query = '';
  return showAppSheet<AdminCourse>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, set) {
      final q = query.trim().toLowerCase();
      final shown = q.isEmpty
          ? courses
          : courses.where((c) => '${c.name} ${c.teacherName}'.toLowerCase().contains(q)).toList();
      return AppSheetContent(title: 'admin_choose_a_course'.tr, children: [
        if (courses.length > 6) ...[
          AppSearchField(hint: 'md_search'.tr, dense: true, onChanged: (v) => set(() => query = v)),
          const SizedBox(height: AppSpace.xs),
        ],
        for (final c in shown)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(ctx)),
            subtitle: c.teacherName.isEmpty ? null : Text(c.teacherName, style: AppType.meta(ctx)),
            onTap: () => Navigator.pop(ctx, c),
          ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Text('md_no_results'.tr, textAlign: TextAlign.center, style: AppType.body(ctx)),
          ),
      ]);
    }),
  );
}

/// Why the student leaves the course: the reason it is recorded under and an optional note; null when cancelled.
Future<(String, String?)?> _removeSheet(BuildContext context, String student, String course) async {
  var code = _reasonCodes.first;
  final note = TextEditingController();
  final result = await showAppSheet<(String, String?)>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, set) => AppSheetContent(title: 'md_p4_remove_title'.tr, children: [
        Text(mdText('md_p4_remove_body', {'s': student, 'c': course}), style: AppType.body(ctx)),
        const SizedBox(height: AppSpace.md),
        Text('md_p4_remove_reason'.tr, style: AppType.label(ctx)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
          for (final r in _reasonCodes)
            AppChoiceChip(label: mdReasonLabel(r), selected: code == r, onTap: () => set(() => code = r)),
        ]),
        const SizedBox(height: AppSpace.sm),
        AppField(controller: note, label: 'md_p4_remove_note'.tr, maxLines: 3),
        const SizedBox(height: AppSpace.md),
        Row(children: [
          Expanded(child: AppButton.secondary(label: 'exam_cancel'.tr, onPressed: () => Navigator.pop(ctx))),
          AppSpace.gapSm,
          Expanded(
            child: AppButton.danger(
              key: const ValueKey('md.student.remove_confirm'),
              label: 'admin_remove'.tr,
              onPressed: () {
                final text = note.text.trim();
                Navigator.pop(ctx, (code, text.isEmpty ? null : text));
              },
            ),
          ),
        ]),
      ]),
    ),
  );
  disposeAfterRoute([note]);
  return result;
}
