// lib/features/teachers/teacher_review_admin.dart — ADMIN / SUPER ADMIN: the teacher review queue (CONTRACT.md §1;
// D-1623, D-1624).
//
//   GET  /api/v1/admin/teachers?status&subject&page            the queue (status tabs, subject filter, "Load more")
//   GET  /api/v1/admin/teachers/{uid}/documents/{id}/url       a 60 s signed link (audited), opened at once
//   POST /api/v1/admin/teachers/{uid}/approve                  asks first
//   POST /api/v1/admin/teachers/{uid}/reject {reason}          a required reason (≤ 500), shown to the teacher
//   GET  /api/v1/admin/packages/refunds-due                    the last tab: paid package money with no seat (D-1640)
//   POST /api/v1/admin/packages/refunds-due/{id}/done          asks first; 409 `not_due` drops the row too
//
//   TeacherReviewPage    the queue
//   TeacherReviewCard    one profile in the queue (plain values)
//   TeacherReviewDetail  the opened profile with its documents and the two decisions (plain values)
//   PackageRefundsList   the refunds-due tab's body; PackageRefundCard one payment (plain values)
//
// Entry: the admin services hub, beside the older Quran teachers page (kill switch `teacher_onboarding`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/share/external_link.dart' show openExternalLink;
import 'package:flutter_education_app/core/plural.dart' as plural;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/teachers/teacher_onboarding.dart' show TeacherDocRow;
import 'package:flutter_education_app/features/teachers/teachers_api.dart';
import 'package:flutter_education_app/features/teachers/teachers_models.dart';
import 'package:flutter_education_app/features/teachers/teachers_parts.dart';
import 'package:flutter_education_app/features/admin/adm_kit.dart' show admRole;
import 'package:flutter_education_app/features/admin/sup/sup_kit.dart';

const List<String> kTeacherReviewStatuses = ['pending', 'approved', 'rejected', 'draft'];

/// The reason's longest length (the server's rule).
const int kTeacherRejectMax = 500;

/// The reject sheet's check (null = fine).
String? teacherRejectReasonError(String reason) {
  final r = reason.trim();
  if (r.length < 5) return t('اكتب السبب ليعرف المعلم ما يعدّله (5 أحرف على الأقل)', 'Write the reason so the teacher knows what to change (at least 5 characters)');
  if (r.length > kTeacherRejectMax) return t('السبب أطول من 500 حرف', 'The reason is longer than 500 characters');
  return null;
}

class TeacherReviewPage extends StatefulWidget {
  const TeacherReviewPage({super.key, this.api});

  final TeachersApi? api;

  @override
  State<TeacherReviewPage> createState() => _TeacherReviewPageState();
}

class _TeacherReviewPageState extends State<TeacherReviewPage> {
  late final TeachersApi _api = widget.api ?? TeachersApi();
  int _tab = 0;
  String? _subject;
  final List<TeacherProfile> _items = [];
  int _page = 1, _total = 0;
  bool _loading = true, _more = false;
  String? _error;
  // the refunds-due tab (D-1640)
  List<PackageRefundDue>? _refunds;
  String? _refundsError;
  int? _refunding;

  bool get _onRefunds => _tab == kTeacherReviewStatuses.length;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _loadRefunds() async {
    setState(() {
      _refunds = null;
      _refundsError = null;
    });
    try {
      final r = await _api.refundsDue();
      if (mounted) setState(() => _refunds = r);
    } catch (e) {
      if (mounted) setState(() => _refundsError = teachersErrorText(e));
    }
  }

  Future<void> _markRefunded(PackageRefundDue r) async {
    final amount = packagePriceLabel(r.amount, r.currency);
    final ok = await appConfirm(context,
        message: t('هل رددت $amount إلى ${r.studentName} عند مزوّد الدفع؟ تُزال الدفعة من القائمة ويُسجَّل ذلك.',
            'Did you refund $amount to ${r.studentName} at the payment provider? The payment leaves the list and this is logged.'),
        confirmLabel: t('تمّ الردّ', 'Mark refunded'));
    if (!ok || !mounted) return;
    setState(() => _refunding = r.paymentId);
    try {
      await _api.refundDone(r.paymentId);
      if (!mounted) return;
      setState(() {
        _refunds?.removeWhere((x) => x.paymentId == r.paymentId);
        _refunding = null;
      });
      showAppNotice(t('سُجّل الردّ', 'The refund is recorded'));
    } catch (e) {
      if (!mounted) return;
      final gone = teachersErrorCode(e) == 'not_due'; // another admin did it already
      setState(() {
        if (gone) _refunds?.removeWhere((x) => x.paymentId == r.paymentId);
        _refunding = null;
      });
      showAppNotice(teachersErrorText(e), error: !gone);
    }
  }

  Future<void> _load({bool next = false}) async {
    if (_onRefunds) return _loadRefunds();
    final status = kTeacherReviewStatuses[_tab], subject = _subject;
    final page = next ? _page + 1 : 1;
    setState(() {
      if (next) {
        _more = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final r = await _api.reviewQueue(status: status, subject: subject, page: page);
      if (!mounted || _onRefunds || status != kTeacherReviewStatuses[_tab] || subject != _subject) return;
      setState(() {
        if (!next) _items.clear();
        _items.addAll(r.items);
        _page = page;
        _total = r.total;
        _loading = false;
        _more = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _more = false;
        if (next) {
          showAppNotice(teachersErrorText(e), error: true);
        } else {
          _error = teachersErrorText(e);
        }
      });
    }
  }

  Future<void> _open(TeacherProfile p) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      settings: RouteSettings(name: '/admin/teachers/${p.userId}'),
      builder: (_) => _ReviewDetailPage(profile: p, api: _api),
    ));
    if (changed == true && mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final filters = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppTabs(
        key: const ValueKey('teacher.review.tabs'),
        items: [
          for (final s in kTeacherReviewStatuses) AppTabItem(teacherStatusLabel(s)),
          AppTabItem(t('مبالغ للردّ', 'Refunds due')),
        ],
        index: _tab,
        onChanged: (i) {
          setState(() => _tab = i);
          unawaited(_load());
        },
      ),
      const SizedBox(height: AppSpace.sm),
      if (!_onRefunds) AppDropdown<String>(
        key: const ValueKey('teacher.review.subject'),
        decoration: InputDecoration(labelText: t('المادة', 'Subject')),
        value: _subject ?? '',
        items: [
          DropdownMenuItem(value: '', child: Text(t('كل المواد', 'Every subject'), overflow: TextOverflow.ellipsis)),
          for (final s in kTeacherSubjects) DropdownMenuItem(value: s, child: Text(teacherSubjectLabel(s), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          setState(() => _subject = (v ?? '').isEmpty ? null : v);
          unawaited(_load());
        },
      ),
      const SizedBox(height: AppSpace.md),
    ]);
    final Widget list;
    if (_onRefunds) {
      list = _refundsError != null
          ? AppErrorState(message: _refundsError, onRetry: _loadRefunds)
          : PackageRefundsList(items: _refunds, busyId: _refunding, onDone: _markRefunded);
    } else if (_loading && _items.isEmpty) {
      list = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (_error != null) {
      list = AppErrorState(message: _error, onRetry: _load);
    } else if (_items.isEmpty) {
      list = AppEmpty(
        icon: Icons.fact_check_outlined,
        title: t('لا ملفات هنا', 'No profiles here'),
        message: t('جرّب حالة أو مادة أخرى.', 'Try another status or subject.'),
        actionLabel: t('كل المواد', 'Every subject'),
        onAction: () {
          setState(() => _subject = null);
          unawaited(_load());
        },
      );
    } else {
      list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final p in _items) ...[
          TeacherReviewCard(profile: p, onTap: () => _open(p)),
          const SizedBox(height: AppSpace.sm),
        ],
        if (_items.length < _total)
          AppButton.secondary(
            key: const ValueKey('teacher.review.more'),
            label: t('المزيد', 'Load more'),
            busy: _more,
            onPressed: _more ? null : () => _load(next: true),
          ),
      ]);
    }
    // redesign A1 (AdmTeachers review): the role's hero with how many profiles wait, the status tabs on it
    final pending = _tab == 0 && !_loading && _error == null ? _total : null;
    return SupPage(
      role: admRole(context),
      title: t('مراجعة المعلمين', 'Teacher review'),
      kicker: t('مراجعة المعلمين', 'Teacher review'),
      headline: pending == null
          ? t('ملفات المعلمين قبل ما تظهر للطلاب', 'Teacher profiles before students see them')
          : plural.countText(pending,
              ar0: 'ما فيه ملفات تنتظر المراجعة',
              ar1: 'ملف واحد ينتظر المراجعة',
              ar2: 'ملفين تنتظر المراجعة',
              arFew: '{n} ملفات تنتظر المراجعة',
              arMany: '{n} ملف ينتظر المراجعة',
              en0: 'No profile waits for review',
              en1: 'One profile waits for review',
              en: '{n} profiles wait for review'),
      line: t('اقرأ الملف، افتح المستندات، واعتمد أو ارفض مع سبب واضح يوصل للمعلم.',
          'Read the profile, open the documents, and approve or reject with a clear reason the teacher receives.'),
      width: AppWidth.content,
      onRefresh: _load,
      helpPageId: 'admin.teacher_documents',
      stats: [
        if (pending != null) AppHeroStat(value: '$pending', label: t('بانتظار المراجعة', 'Waiting for review')),
        if (_refunds != null) AppHeroStat(value: '${_refunds!.length}', label: t('مبالغ للردّ', 'Refunds due')),
      ],
      body: ListView(padding: SupPage.bodyPadding(context), children: [filters, list]),
    );
  }
}

class TeacherReviewCard extends StatelessWidget {
  const TeacherReviewCard({super.key, required this.profile, this.onTap});

  final TeacherProfile profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    return AppCard(
      key: ValueKey('teacher.review.${p.userId}'),
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppAvatar(name: teacherInitialName(p.name), url: p.avatarUrl, size: AppTouch.min),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            // the name and, at the line's trailing edge, the status (inside the column, so the badges below keep
            // the column's whole width on a phone)
            TitleWithStatus(
              title: UserText(block: false, p.name.isEmpty ? '—' : p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark)),
              status: AppStatusBadge(label: teacherStatusLabel(p.status), tone: teacherStatusTone(p.status), dense: true),
            ),
            const SizedBox(height: AppSpace.xxs),
            Text(
              [
                teacherGenderLabel(p.gender),
                if (p.documents.isNotEmpty) countText(p.documents.length),
                // the date never breaks inside itself ("21 / نوفمبر 2026")
                if (p.submittedAt != null) AppTime.date(p.submittedAt!).replaceAll(' ', '\u00A0'),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(color: c.textMedium),
            ),
            const SizedBox(height: AppSpace.xs),
            TeacherSubjectBadges(subjects: p.subjects),
          ]),
        ),
      ]),
    );
  }

  static String countText(int n) => plural.countText(n,
      ar1: 'مستند واحد', ar2: 'مستندان', arFew: '{n} مستندات', arMany: '{n} مستنداً', en1: '1 document', en: '{n} documents');
}

/// The refunds-due tab's body: a skeleton while [items] is null, the calm empty state, or one card per payment.
class PackageRefundsList extends StatelessWidget {
  const PackageRefundsList({super.key, required this.items, this.busyId, this.onDone});

  final List<PackageRefundDue>? items;
  final int? busyId;
  final ValueChanged<PackageRefundDue>? onDone;

  @override
  Widget build(BuildContext context) {
    final l = items;
    if (l == null) return const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
    if (l.isEmpty) {
      return AppEmpty(
        icon: Icons.verified_outlined,
        title: t('لا مبالغ بانتظار الردّ', 'No refunds are waiting'),
        message: t('تظهر هنا كل دفعة باقة وصلت ولا مقعد لها.', 'A package payment that arrives with no seat to give shows here.'),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in l) ...[
        PackageRefundCard(item: r, busy: busyId == r.paymentId, onDone: onDone == null || busyId != null ? null : () => onDone!(r)),
        const SizedBox(height: AppSpace.sm),
      ],
    ]);
  }
}

class PackageRefundCard extends StatelessWidget {
  const PackageRefundCard({super.key, required this.item, this.busy = false, this.onDone});

  final PackageRefundDue item;
  final bool busy;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = item;
    return AppCard(
      key: ValueKey('package.refund.${r.paymentId}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppAvatar(name: r.studentName.isEmpty ? '?' : r.studentName, size: AppTouch.min),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(r.studentName.isEmpty ? '—' : r.studentName,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark)),
              const SizedBox(height: AppSpace.xxs),
              Text(r.packageTitle.isEmpty ? '—' : r.packageTitle,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text(packagePriceLabel(r.amount, r.currency),
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: AppType.row(context).copyWith(color: c.textDark)),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Text(packageRefundReasonText(r.reason), style: AppType.body(context).copyWith(color: c.textDark)),
        if (r.paidAt != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text('${t('دُفعت', 'Paid')} ${AppTime.dateTime(r.paidAt!)}',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ],
        const SizedBox(height: AppSpace.sm),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton.tonal(
            key: ValueKey('package.refund.done.${r.paymentId}'),
            label: t('تمّ الردّ', 'Mark refunded'),
            icon: Icons.undo_rounded,
            size: AppButtonSize.sm,
            busy: busy,
            onPressed: onDone,
          ),
        ),
      ]),
    );
  }
}

class _ReviewDetailPage extends StatefulWidget {
  const _ReviewDetailPage({required this.profile, required this.api});

  final TeacherProfile profile;
  final TeachersApi api;

  @override
  State<_ReviewDetailPage> createState() => _ReviewDetailPageState();
}

class _ReviewDetailPageState extends State<_ReviewDetailPage> {
  late TeacherProfile _p = widget.profile;
  bool _busy = false;
  int? _opening;

  @override
  void initState() {
    super.initState();
    // the queue row may not carry the documents: the profile route does (owner / admin see any status)
    unawaited(widget.api.teacher(_p.userId).then((r) {
      if (mounted && r.userId == _p.userId) setState(() => _p = r);
    }).catchError((_) {}));
  }

  Future<void> _openDoc(TeacherDoc d) async {
    setState(() => _opening = d.id);
    try {
      final url = await widget.api.documentUrl(_p.userId, d.id);
      if (url.isEmpty) throw StateError('no url');
      await openExternalLink(url);
    } catch (e) {
      showAppNotice(e is StateError ? t('تعذّر فتح المستند', 'Could not open the document') : teachersErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _approve() async {
    final ok = await appConfirm(context,
        message: teacherG(_p.gender, 'اعتماد ${_p.name}؟ يظهر للطلاب ويفتح باقاته، ويصله إشعار.', 'اعتماد ${_p.name}؟ تظهر للطلاب وتفتح باقاتها، ويصلها إشعار.',
            'Approve ${_p.name}? They appear to students, can open packages and get a notification.'),
        confirmLabel: t('اعتمد', 'Approve'));
    if (ok != true || !mounted) return;
    await _decide(() => widget.api.approve(_p.userId), t('اعتُمد المعلم', 'The teacher is approved'));
  }

  Future<void> _reject() async {
    final reason = await showTeacherRejectSheet(context, name: _p.name);
    if (reason == null || !mounted) return;
    await _decide(() => widget.api.reject(_p.userId, reason), t('أُعيد الملف للمعلم مع السبب', 'The profile went back to the teacher with the reason'));
  }

  Future<void> _decide(Future<void> Function() fn, String done) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (!mounted) return;
      showAppNotice(done);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      showAppNotice(teachersErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => SupPage(
        role: admRole(context),
        width: AppWidth.reading,
        title: _p.name.isEmpty ? t('ملف معلم', 'Teacher profile') : _p.name,
        kicker: t('مراجعة المعلمين', 'Teacher review'),
        headline: _p.name.isEmpty ? t('ملف معلم', 'Teacher profile') : _p.name,
        line: teacherStatusLabel(_p.status),
        body: SafeArea(
          child: TeacherReviewDetail(
            profile: _p,
            busy: _busy,
            openingDoc: _opening,
            onOpenDoc: _openDoc,
            onApprove: _p.approved ? null : _approve,
            onReject: _p.rejected || _p.status == 'draft' ? null : _reject,
          ),
        ),
      );
}

class TeacherReviewDetail extends StatelessWidget {
  const TeacherReviewDetail({
    super.key,
    required this.profile,
    this.onOpenDoc,
    this.onApprove,
    this.onReject,
    this.busy = false,
    this.openingDoc,
  });

  final TeacherProfile profile;
  final ValueChanged<TeacherDoc>? onOpenDoc;
  final VoidCallback? onApprove, onReject;
  final bool busy;
  final int? openingDoc;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      AppCard(
        highlight: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            AppAvatar(name: teacherInitialName(p.name), url: p.avatarUrl, size: AppTouch.primary),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                // the status at the name line's trailing edge (a Flexible beside the column split the row in half and
                // left the chip mid-card, D-1650)
                TitleWithStatus(
                  title: UserText(block: false, p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark)),
                  status: AppStatusBadge(label: teacherStatusLabel(p.status), tone: teacherStatusTone(p.status), dense: true),
                ),
                Text(teacherGenderLabel(p.gender), style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.sm),
          TeacherSubjectBadges(subjects: p.subjects),
          if (p.rejected && (p.rejectionReason ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            AppBanner(icon: Icons.feedback_outlined, color: c.danger, text: p.rejectionReason!),
          ],
        ]),
      ),
      AppSection(
        title: teacherG(p.gender, 'عن المعلم', 'عن المعلمة', 'About'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppInfoRow(Icons.workspace_premium_rounded, yearsText(p.yearsExperience)),
          if (p.languages.isNotEmpty) AppInfoRow(Icons.translate_rounded, teachersJoin(p.languages.map(teacherLanguageLabel))),
          if (p.sessionTypes.isNotEmpty || p.delivery.isNotEmpty)
            AppInfoRow(Icons.groups_rounded, [...p.sessionTypes.map(teacherSessionTypeLabel), ...p.delivery.map(packageDeliveryLabel)].join(' · ')),
          const SizedBox(height: AppSpace.xs),
          UserText(p.bio.isEmpty ? '—' : p.bio, style: AppType.body(context).copyWith(color: c.textDark)),
        ]),
      ),
      AppSection(
        title: t('المؤهلات', 'Qualifications'),
        child: UserText(p.qualifications.isEmpty ? '—' : p.qualifications, style: AppType.body(context).copyWith(color: c.textDark)),
      ),
      AppSection(
        title: t('المستندات', 'Documents'),
        subtitle: t('يُفتح كل مستند برابط مؤقت لدقيقة، ويُسجَّل فتحه.', 'Each document opens through a one-minute link, and the opening is logged.'),
        child: p.documents.isEmpty
            ? AppEmpty(icon: Icons.description_outlined, title: t('لا مستندات', 'No documents'))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final d in p.documents) ...[
                  TeacherDocRow(doc: d, busy: openingDoc == d.id, onOpen: onOpenDoc == null ? null : () => onOpenDoc!(d)),
                  const SizedBox(height: AppSpace.xs),
                ],
              ]),
      ),
      const SizedBox(height: AppSpace.md),
      if (onApprove != null || onReject != null)
        AppButtonRow(
          primary: AppButton.primary(
            key: const ValueKey('teacher.review.approve'),
            label: t('اعتمد', 'Approve'),
            icon: Icons.verified_rounded,
            busy: busy,
            onPressed: busy ? null : onApprove,
          ),
          secondary: [
            AppButton.danger(
              key: const ValueKey('teacher.review.reject'),
              label: t('ارفض مع السبب', 'Reject with a reason'),
              icon: Icons.undo_rounded,
              onPressed: busy ? null : onReject,
            ),
          ],
        ),
      const SizedBox(height: AppSpace.lg),
    ]);
  }
}

/// Asks for the reason (required, ≤ 500). The trimmed reason, or null when cancelled.
Future<String?> showTeacherRejectSheet(BuildContext context, {required String name}) {
  return showAppSheet<String>(
    context,
    (ctx) => AppSheetContent(
      title: t('رفض ملف $name', 'Reject $name\'s profile'),
      icon: Icons.undo_rounded,
      tone: AppTone.danger,
      children: const [TeacherRejectForm()],
    ),
  );
}

class TeacherRejectForm extends StatefulWidget {
  const TeacherRejectForm({super.key});

  @override
  State<TeacherRejectForm> createState() => _TeacherRejectFormState();
}

class _TeacherRejectFormState extends State<TeacherRejectForm> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _send() {
    final e = teacherRejectReasonError(_reason.text);
    if (e != null) {
      setState(() => _error = e);
      return;
    }
    Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppField(
          key: const ValueKey('teacher.reject.reason'),
          controller: _reason,
          label: t('السبب (يراه المعلم)', 'The reason (the teacher sees it)'),
          hint: t('مثال: صورة الإجازة غير واضحة، أرفق نسخة أوضح', 'e.g. The ijazah photo is not readable; attach a clearer copy'),
          maxLines: 4,
          maxLength: kTeacherRejectMax,
          required: true,
          errorText: _error,
        ),
        const SizedBox(height: AppSpace.md),
        AppButtonRow(
          primary: AppButton.danger(key: const ValueKey('teacher.reject.send'), label: t('ارفض', 'Reject'), onPressed: _send),
          secondary: [AppButton.ghost(label: t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(context).pop())],
        ),
        const SizedBox(height: AppSpace.md),
      ]);
}
