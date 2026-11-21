// lib/features/teachers/teacher_review_admin.dart — ADMIN / SUPER ADMIN: the teacher review queue (CONTRACT.md §1;
// D-1623, D-1624).
//
//   GET  /api/v1/admin/teachers?status&subject&page            the queue (status tabs, subject filter, "Load more")
//   GET  /api/v1/admin/teachers/{uid}/documents/{id}/url       a 60 s signed link (audited), opened at once
//   POST /api/v1/admin/teachers/{uid}/approve                  asks first
//   POST /api/v1/admin/teachers/{uid}/reject {reason}          a required reason (≤ 500), shown to the teacher
//
//   TeacherReviewPage    the queue
//   TeacherReviewCard    one profile in the queue (plain values)
//   TeacherReviewDetail  the opened profile with its documents and the two decisions (plain values)
//
// Entry: the admin services hub, beside the older Quran teachers page (kill switch `teacher_onboarding`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/share/external_link.dart' show openExternalLink;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/teachers/teacher_onboarding.dart' show TeacherDocRow;
import 'package:flutter_education_app/features/teachers/teachers_api.dart';
import 'package:flutter_education_app/features/teachers/teachers_models.dart';
import 'package:flutter_education_app/features/teachers/teachers_parts.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool next = false}) async {
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
      if (!mounted || status != kTeacherReviewStatuses[_tab] || subject != _subject) return;
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
        items: [for (final s in kTeacherReviewStatuses) AppTabItem(teacherStatusLabel(s))],
        index: _tab,
        onChanged: (i) {
          setState(() => _tab = i);
          unawaited(_load());
        },
      ),
      const SizedBox(height: AppSpace.sm),
      AppDropdown<String>(
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
    if (_loading && _items.isEmpty) {
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
    return BasePage(
      width: AppWidth.content,
      appBar: ScreenAppBar(title: t('مراجعة المعلمين', 'Teacher review')),
      child: SafeArea(
        child: AppRefresh(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [filters, list, const SizedBox(height: AppSpace.lg)]),
        ),
      ),
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
        AppAvatar(name: p.name.isEmpty ? '?' : p.name, url: p.avatarUrl, size: AppTouch.min),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(p.name.isEmpty ? '—' : p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark)),
            const SizedBox(height: AppSpace.xxs),
            Text(
              [
                teacherGenderLabel(p.gender),
                if (p.documents.isNotEmpty) countText(p.documents.length),
                if (p.submittedAt != null) AppTime.date(p.submittedAt!),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(color: c.textMedium),
            ),
            const SizedBox(height: AppSpace.xs),
            TeacherSubjectBadges(subjects: p.subjects),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        Flexible(child: AppStatusBadge(label: teacherStatusLabel(p.status), tone: teacherStatusTone(p.status), dense: true)),
      ]),
    );
  }

  static String countText(int n) => t(n == 1 ? 'مستند واحد' : '$n مستندات', n == 1 ? '1 document' : '$n documents');
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
        message: t('اعتماد ${_p.name}؟ يظهر للطلاب ويفتح باقاته، ويصله إشعار.', 'Approve ${_p.name}? They appear to students, can open packages and get a notification.'),
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
  Widget build(BuildContext context) => BasePage(
        width: AppWidth.reading,
        appBar: ScreenAppBar(title: _p.name.isEmpty ? t('ملف معلم', 'Teacher profile') : _p.name),
        child: SafeArea(
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
            AppAvatar(name: p.name.isEmpty ? '?' : p.name, url: p.avatarUrl, size: AppTouch.primary),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark)),
                Text(teacherGenderLabel(p.gender), style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ),
            Flexible(child: AppStatusBadge(label: teacherStatusLabel(p.status), tone: teacherStatusTone(p.status), dense: true)),
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
        title: t('عن المعلم', 'About'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppInfoRow(Icons.workspace_premium_rounded, yearsText(p.yearsExperience)),
          if (p.languages.isNotEmpty) AppInfoRow(Icons.translate_rounded, p.languages.map(teacherLanguageLabel).join('، ')),
          if (p.sessionTypes.isNotEmpty || p.delivery.isNotEmpty)
            AppInfoRow(Icons.groups_rounded, [...p.sessionTypes.map(teacherSessionTypeLabel), ...p.delivery.map(packageDeliveryLabel)].join(' · ')),
          const SizedBox(height: AppSpace.xs),
          Text(p.bio.isEmpty ? '—' : p.bio, style: AppType.body(context).copyWith(color: c.textDark)),
        ]),
      ),
      AppSection(
        title: t('المؤهلات', 'Qualifications'),
        child: Text(p.qualifications.isEmpty ? '—' : p.qualifications, style: AppType.body(context).copyWith(color: c.textDark)),
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
