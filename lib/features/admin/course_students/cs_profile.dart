// lib/features/admin/course_students/cs_profile.dart
//
// The student profile: the presentational view (access diagnostic first, then platform subscriptions and the
// timeline), the admin action sheet, and the drawer (side panel on wide windows, full-height sheet on phones).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../admin_common.dart' show t;
import 'cs_api.dart';
import 'cs_models.dart';
import 'cs_widgets.dart';

typedef CsActionCallback = void Function(CsCourseAccess course, String action);

String csActionLabel(String action) => switch (action) {
      'extend' => t('تمديد', 'Extend'),
      'reactivate' => t('إعادة تفعيل', 'Reactivate'),
      'grant' => t('منح وصول', 'Grant access'),
      _ => t('إلغاء', 'Cancel'),
    };

IconData csActionIcon(String action) => switch (action) {
      'extend' => Icons.update_rounded,
      'reactivate' => Icons.restart_alt_rounded,
      'grant' => Icons.card_giftcard_rounded,
      _ => Icons.block_rounded,
    };

const List<String> kCsActions = ['extend', 'reactivate', 'grant', 'cancel'];

// ── the profile ─────────────────────────────────────────────────────────────

class CsProfileView extends StatelessWidget {
  const CsProfileView({super.key, required this.profile, this.onAction, this.busy = false});
  final CsProfile profile;
  final CsActionCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final timeline = csTimeline(profile);
    return ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [
        _Header(profile),
        const SizedBox(height: AppSpace.md),
        _SectionCard(
          title: t('تشخيص الوصول', 'Access diagnostic'),
          icon: Icons.fact_check_outlined,
          emphasised: true,
          child: profile.courses.isEmpty
              ? Text(t('لا دورات مسجّلة لهذا الطالب', 'This student has no courses'), style: AppType.meta(context))
              : Column(children: [
                  for (var i = 0; i < profile.courses.length; i++) ...[
                    if (i > 0) Divider(height: AppSpace.lg, color: context.colors.divider),
                    _CourseDiagnostic(profile.courses[i], onAction: onAction),
                  ],
                ]),
        ),
        const SizedBox(height: AppSpace.md),
        _SectionCard(
          title: t('اشتراكات المنصة', 'Platform subscriptions'),
          icon: Icons.workspace_premium_outlined,
          child: profile.platformSubs.isEmpty
              ? Text(t('لا اشتراكات على المنصة', 'No platform subscriptions'), style: AppType.meta(context))
              : Column(children: [for (final s in profile.platformSubs) _PlatformSubLine(s)]),
        ),
        const SizedBox(height: AppSpace.md),
        _SectionCard(
          title: t('السجل الزمني', 'Timeline'),
          icon: Icons.timeline_rounded,
          child: timeline.isEmpty
              ? Text(t('لا أحداث مسجّلة', 'No events recorded'), style: AppType.meta(context))
              : Column(children: [
                  for (var i = 0; i < timeline.length; i++) _TimelineTile(timeline[i], profile, last: i == timeline.length - 1),
                ]),
        ),
        const SizedBox(height: AppSpace.lg),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.child, this.emphasised = false});
  final String title;
  final IconData icon;
  final Widget child;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: emphasised ? c.primary : c.divider, width: emphasised ? 1.5 : 1),
        boxShadow: emphasised ? AppShadow.card(context) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 20, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(title, style: AppType.section(context))),
        ]),
        const SizedBox(height: AppSpace.sm),
        child,
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.p);
  final CsProfile p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = p.student;
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Row(children: [
            Icon(icon, size: 15, color: c.textMedium),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppAvatar(name: s.name, url: s.imageUrl, size: 56),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
            if (s.email != null) line(Icons.mail_outline_rounded, s.email!),
            if (s.phone != null) line(Icons.phone_outlined, s.phone!),
            if (s.username != null) line(Icons.alternate_email_rounded, s.username!),
          ]),
        ),
      ]),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        if (p.academicId != null) _IdChip(t('الرقم الأكاديمي', 'Academic ID'), p.academicId!),
        if (p.nationalId != null) _IdChip(t('الرقم القومي', 'National ID'), p.nationalId!),
        for (final code in p.studentCodes) _IdChip(t('كود الطالب', 'Student code'), code),
        _IdChip('ID', '${s.id}'),
        if (!p.isActive) AppBadgePill(t('الحساب موقوف', 'Account disabled'), color: c.danger, icon: Icons.lock_outline_rounded),
      ]),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.lg, runSpacing: AppSpace.xs, children: [
        if (p.joinedAt != null) Text(t('انضم في ${csDate(p.joinedAt)}', 'Joined ${csDate(p.joinedAt)}'), style: AppType.meta(context)),
        Text(
          p.totalSpent.isEmpty
              ? t('إجمالي المدفوع: 0', 'Total spent: 0')
              : t('إجمالي المدفوع: ', 'Total spent: ') + p.totalSpent.map((m) => csMoneyText(m.amount, m.currency)).join(' + '),
          style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark),
        ),
      ]),
    ]);
  }
}

class _IdChip extends StatelessWidget {
  const _IdChip(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs + AppSpace.xxs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text('$label ', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textMedium))),
        Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: appText(11.5, w: FontWeight.w600, c: c.textDark))),
      ]),
    );
  }
}

class _CourseDiagnostic extends StatelessWidget {
  const _CourseDiagnostic(this.course, {this.onAction});
  final CsCourseAccess course;
  final CsActionCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = course.access;
    final tone = a.hasAccess ? c.success : c.danger;
    final actions = [for (final x in kCsActions) if (csActionValid(x, a)) x];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(course.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
        const SizedBox(width: AppSpace.xs),
        CsStatusBadge(a.kind),
      ]),
      if (course.teacherName.isNotEmpty) Text(course.teacherName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(a.hasAccess ? Icons.lock_open_rounded : Icons.lock_outline_rounded, size: 18, color: appInk(context, tone)),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: a.hasAccess ? t('لديه وصول - ', 'Has access - ') : t('لا وصول - ', 'No access - '), style: appText(13, w: FontWeight.w600, c: appInk(context, tone))),
            TextSpan(text: csReasonText(a), style: appText(13, c: c.textDark)),
          ]), style: const TextStyle(height: 1.45)),
        ),
      ]),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xxs, children: [
        _Kv(t('المصدر', 'Source'), csSourceLabel(a.source)),
        _Kv(t('الباقة', 'Plan'), csPlanLabel(a.plan)),
        _Kv(t('الانتهاء', 'Expiry'), csDate(a.expiresAt)),
        _Kv(t('المتبقي', 'Left'), csDaysText(a)),
      ]),
      for (final f in a.flags)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: AppBanner(icon: Icons.flag_outlined, text: csFlagText(f), color: f == 'paid_no_access' ? c.danger : c.warning),
        ),
      if (actions.isNotEmpty && onAction != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final x in actions)
              OutlinedButton.icon(
                onPressed: () => onAction!(course, x),
                icon: Icon(csActionIcon(x), size: 18),
                label: Text(csActionLabel(x)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              ),
          ]),
        ),
    ]);
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(TextSpan(children: [
      TextSpan(text: '$k: ', style: appText(12, c: c.textMedium)),
      TextSpan(text: v, style: appText(12, w: FontWeight.w600, c: c.textDark)),
    ]));
  }
}

class _PlatformSubLine extends StatelessWidget {
  const _PlatformSubLine(this.s);
  final CsPlatformSub s;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Row(children: [
          Expanded(child: Text('${csPlanLabel(s.plan)} · ${s.status}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text('${csDate(s.startsAt)} - ${csDate(s.endsAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
        ]),
      );
}

// ── timeline ────────────────────────────────────────────────────────────────

(IconData, Color) _eventStyle(BuildContext context, String type) {
  final c = context.colors;
  return switch (type) {
    'payment_succeeded' || 'activated' || 'renewed' || 'admin_granted' || 'admin_reactivated' => (Icons.check_circle_outline_rounded, c.success),
    'admin_extended' => (Icons.update_rounded, c.primary),
    'expired' => (Icons.event_busy_rounded, c.secondText),
    'cancelled' => (Icons.block_rounded, c.warning),
    'refunded' => (Icons.undo_rounded, c.warning),
    'payment_failed' || 'access_denied' => (Icons.error_outline_rounded, c.danger),
    'created' => (Icons.add_circle_outline_rounded, c.primary),
    _ => (Icons.history_rounded, c.secondText),
  };
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile(this.item, this.profile, {required this.last});
  final CsTimelineItem item;
  final CsProfile profile;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = item.event, pay = item.payment;
    final (icon, tone) = e != null ? _eventStyle(context, e.type) : (Icons.payments_outlined, pay?.status == 'completed' ? c.success : c.secondText);
    final title = e != null ? csEventLabel(e.type) : t('دفعة ${csMoneyText(pay!.amount, pay.currency)}', 'Payment ${csMoneyText(pay.amount, pay.currency)}');
    final courseId = e?.courseId ?? pay?.courseId;
    final change = e == null ? null : csChangeText(e);
    final meta = <String>[
      if (e != null) csActorLabel(e),
      if (pay != null) ...[pay.status, if (pay.provider != null) pay.provider!, if (pay.plan != null) csPlanLabel(pay.plan)],
      if (courseId != null) profile.courseName(courseId),
    ].where((x) => x.isNotEmpty).join(' · ');
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 32,
          child: Column(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone.withValues(alpha: c.isDark ? 0.22 : 0.14)),
              child: Icon(icon, size: 16, color: appInk(context, tone)),
            ),
            if (!last) Expanded(child: Container(width: 2, color: c.divider)),
          ]),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(title, style: AppType.row(context)),
                if (e?.backfilled == true) AppBadgePill(t('مُستنتَج لاحقاً', 'Backfilled'), color: c.secondText, icon: Icons.history_toggle_off_rounded),
              ]),
              if (item.at != null) Text(AppTime.dateTime(item.at!), style: AppType.meta(context)),
              if (meta.isNotEmpty) Text(meta, style: AppType.meta(context)),
              if (e?.reason != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text('"${e!.reason}"', style: appText(12.5, c: c.textDark, h: 1.4))),
              if (change != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(change, style: appText(12, c: c.textMedium, h: 1.4))),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── action sheet ────────────────────────────────────────────────────────────

/// Collects the reason (5-500 characters) and, where the action needs them, days and a plan. [onSubmit] does the call
/// and throws on failure; the sheet shows the error and stays open.
class CsActionSheet extends StatefulWidget {
  const CsActionSheet({super.key, required this.action, required this.studentName, required this.course, required this.onSubmit});
  final String action;
  final String studentName;
  final CsCourseAccess course;
  final Future<void> Function(String reason, int? days, String? plan) onSubmit;

  @override
  State<CsActionSheet> createState() => _CsActionSheetState();
}

class _CsActionSheetState extends State<CsActionSheet> {
  final _reason = TextEditingController();
  final _days = TextEditingController();
  String? _plan;
  bool _busy = false;
  String? _error;

  static const int minReason = 5;
  static const int maxReason = 500;

  CsAccess get _a => widget.course.access;
  bool get _showDays => widget.action != 'cancel';
  bool get _showPlan => widget.action == 'grant';

  /// extend always needs days; reactivate when the plan already ended (or has no end); grant may leave it empty.
  bool get _daysRequired =>
      widget.action == 'extend' || (widget.action == 'reactivate' && (_a.expiresAt == null || !_a.expiresAt!.isAfter(DateTime.now().toUtc())));

  int? get _daysValue => int.tryParse(_days.text.trim());
  bool get _daysOk {
    if (!_showDays) return true;
    final d = _daysValue;
    if (_days.text.trim().isEmpty) return !_daysRequired;
    return d != null && d >= 1 && d <= 3650;
  }

  bool get _reasonOk => _reason.text.trim().length >= minReason && _reason.text.trim().length <= maxReason;

  @override
  void dispose() {
    _reason.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await appConfirm(context,
        message: t('تأكيد «${csActionLabel(widget.action)}» للطالب ${widget.studentName} في ${widget.course.name}؟',
            'Confirm "${csActionLabel(widget.action)}" for ${widget.studentName} in ${widget.course.name}?'),
        danger: widget.action == 'cancel');
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_reason.text.trim(), _showDays ? _daysValue : null, _showPlan ? _plan : null);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final ex = ApiException.from(e);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = csErrorText(ex.code, ex.message);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = _reason.text.trim().length;
    return AppSheetContent(
      title: '${csActionLabel(widget.action)} · ${widget.course.name}',
      children: [
        Text(csReasonText(_a), style: AppType.meta(context)),
        const SizedBox(height: AppSpace.md),
        AppField(controller: _reason, label: t('السبب (يظهر في السجل)', 'Reason (kept in the history)'), maxLines: 3, onChanged: (_) => setState(() {})),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text('$n / $maxReason', style: appText(11.5, c: n > maxReason ? c.danger : c.textMedium)),
        ),
        if (_showDays) ...[
          const SizedBox(height: AppSpace.sm),
          AppField(
            controller: _days,
            label: _daysRequired ? t('عدد الأيام (1 - 3650)', 'Days (1 - 3650)') : t('عدد الأيام (اختياري)', 'Days (optional)'),
            hint: widget.action == 'grant' ? t('فارغ = مدة الباقة أو بلا نهاية', "Empty = the plan's length, or no end") : null,
            keyboard: TextInputType.number,
            ltr: true,
            onChanged: (_) => setState(() {}),
          ),
        ],
        if (_showPlan) ...[
          const SizedBox(height: AppSpace.sm),
          AppDropdown<String?>(
            value: _plan,
            decoration: InputDecoration(labelText: t('الباقة', 'Plan')),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(t('بدون باقة', 'No plan'))),
              for (final p in const ['monthly', 'six_months', 'yearly']) DropdownMenuItem<String?>(value: p, child: Text(csPlanLabel(p))),
            ],
            onChanged: (v) => setState(() => _plan = v),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
        ],
        const SizedBox(height: AppSpace.md),
        AppPrimaryButton(label: csActionLabel(widget.action), icon: csActionIcon(widget.action), busy: _busy, onPressed: (_reasonOk && _daysOk && !_busy) ? _submit : null),
      ],
    );
  }
}

// ── drawer ──────────────────────────────────────────────────────────────────

/// The panel chrome: a title bar with a close button over the body.
class CsDrawerFrame extends StatelessWidget {
  const CsDrawerFrame({super.key, required this.title, required this.onClose, required this.child});
  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: AppSpace.md, end: AppSpace.xs, top: AppSpace.xs, bottom: AppSpace.xs),
        child: Row(children: [
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
          IconButton(tooltip: t('إغلاق', 'Close'), onPressed: onClose, icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Divider(height: 1, color: c.divider),
      Expanded(child: child),
    ]);
  }
}

/// Loads one student and shows [CsProfileView]; runs the admin actions and refreshes after each.
class CsProfileLoader extends StatefulWidget {
  const CsProfileLoader({super.key, required this.studentId, this.api, this.onChanged});
  final int studentId;
  final CourseStudentsApi? api;
  final VoidCallback? onChanged;

  @override
  State<CsProfileLoader> createState() => _CsProfileLoaderState();
}

class _CsProfileLoaderState extends State<CsProfileLoader> {
  late final CourseStudentsApi _api = widget.api ?? CourseStudentsApi();
  CsProfile? _profile;
  String? _error;
  bool _loading = true;

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
      final p = await _api.profile(widget.studentId);
      if (mounted) setState(() => _profile = p);
    } catch (e) {
      final ex = ApiException.from(e);
      if (mounted) setState(() => _error = csErrorText(ex.code, ex.message));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(CsCourseAccess course, String action) async {
    final p = _profile;
    if (p == null) return;
    final done = await showAppSheet<bool>(
      context,
      (_) => CsActionSheet(
        action: action,
        studentName: p.student.name,
        course: course,
        onSubmit: (reason, days, plan) => _api.act(p.student.id, course.courseId, action: action, reason: reason, days: days, plan: plan),
      ),
    );
    if (done != true) return;
    showAppNotice(t('تم تنفيذ «${csActionLabel(action)}»', '"${csActionLabel(action)}" done'));
    HapticFeedback.selectionClick();
    widget.onChanged?.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null) {
      if (_error != null) {
        return AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
      }
      return const AppListSkeleton(items: 4);
    }
    return AnimatedOpacity(
      opacity: _loading ? 0.5 : 1,
      duration: AppMotion.of(context).fast,
      child: CsProfileView(profile: _profile!, onAction: _act, busy: _loading),
    );
  }
}

/// Opens a student's profile: a side drawer from the reading-direction end on wide windows, a full-height sheet on
/// phones. [onChanged] runs after an admin action succeeded (the caller refreshes its roster row).
Future<void> showCsProfileDrawer(BuildContext context, int studentId, {String? title, CourseStudentsApi? api, VoidCallback? onChanged}) {
  final wide = MediaQuery.sizeOf(context).width >= kCsTableBreakpoint;
  final heading = title ?? t('ملف الطالب', 'Student profile');
  if (!wide) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: Directionality.of(context),
        child: Container(
          height: MediaQuery.sizeOf(ctx).height,
          decoration: BoxDecoration(color: ctx.colors.background, borderRadius: AppRadius.sheetTop),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: CsDrawerFrame(title: heading, onClose: () => Navigator.of(ctx).pop(), child: CsProfileLoader(studentId: studentId, api: api, onChanged: onChanged)),
          ),
        ),
      ),
    );
  }
  final rtl = Directionality.of(context) == TextDirection.rtl;
  final motion = AppMotion.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: t('إغلاق', 'Close'),
    barrierColor: context.colors.charcoalDark.withValues(alpha: 0.5),
    transitionDuration: motion.base,
    pageBuilder: (ctx, _, _) => Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SizedBox(
          width: 520,
          height: double.infinity,
          child: Material(
            color: ctx.colors.background,
            elevation: 8,
            child: CsDrawerFrame(title: heading, onClose: () => Navigator.of(ctx).pop(), child: CsProfileLoader(studentId: studentId, api: api, onChanged: onChanged)),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween<Offset>(begin: Offset(rtl ? -1 : 1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: AppMotion.curve)),
      child: child,
    ),
  );
}
