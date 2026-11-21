// lib/features/org/students/student_file_tabs.dart — the tabs of the unified student file (D-1400, phase 1, PLAN.md §3.2).
//
//   StudentOverviewTab        key facts, the admission case in one line, what is still open, what is missing
//   StudentAcademicTab        the academic summary + "Open the full record" (OrgRecordScreen, which logs `academic`)
//   StudentDocumentsTab       the admission case: type, state, due date, missing count + "Open the case" (OnbReviewPage)
//   StudentRequestsTab        open complaints / requests / asks + links into the existing pages
//   StudentAdvisingTab        one link card into the advising 360 (AdvStudentPage)
//   StudentAccessLogView      who opened the file, which part, when (plain values; StudentAccessLogTab loads it)
//   StudentFactsCard          label / value rows (used by the overview)
//
// Every tab takes plain values and callbacks; the page (student_file_page.dart) wires the calls and the pushes, so
// the layout harness pumps each one without a network. A section the caller may not see is not drawn at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgErrorText;
import 'student_file_models.dart';
import 'students_api.dart';
import 'students_models.dart';

/// The tab's title inside its body (a quiet section heading).
class _TabHeading extends StatelessWidget {
  const _TabHeading(this.text, {this.subtitle});
  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(text, style: AppType.section(context))),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(subtitle!, style: AppType.meta(context).copyWith(color: context.colors.textMedium)),
          ],
        ]),
      );
}

/// Label / value rows in one card. [rows]: (icon, label, value, value is left-to-right).
class StudentFactsCard extends StatelessWidget {
  const StudentFactsCard({super.key, required this.rows});

  final List<(IconData, String, String, bool)> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return AppCard(
      child: Column(children: [
        for (final (i, (icon, label, value, ltr)) in rows.indexed) ...[
          if (i > 0) Divider(height: AppSpace.md, color: c.divider),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: AppIconSize.md, color: c.textMedium),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppType.meta(context).copyWith(color: c.textMedium)),
                SelectableText(value, textDirection: ltr ? TextDirection.ltr : null, style: AppType.row(context)),
              ]),
            ),
          ]),
        ],
      ]),
    );
  }
}

/// One tappable line of a list card: icon, text, an optional count and a forward arrow.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.text, this.meta, this.onTap, this.tone = AppTone.neutral});
  final IconData icon;
  final String text;
  final String? meta;
  final VoidCallback? onTap;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(children: [
            Icon(icon, size: AppIconSize.md, color: appToneColor(context, tone)),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: AppType.row(context)),
                if (meta != null) Text(meta!, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textMedium),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Overview
// ═════════════════════════════════════════════════════════════════════════════

class StudentOverviewTab extends StatelessWidget {
  const StudentOverviewTab({super.key, required this.file, this.onMissing, this.onOpenTab, this.missingOn = true});

  final StudentFile file;

  /// Opens the missing-data sheet; null = no button.
  final VoidCallback? onMissing;

  /// Jumps to another tab (the open items link to theirs).
  final ValueChanged<StudentFileTab>? onOpenTab;

  /// The kill switch `org.students.missing` is on.
  final bool missingOn;

  @override
  Widget build(BuildContext context) {
    final r = file.row;
    final tabs = studentFileTabs(file.can);
    final facts = <(IconData, String, String, bool)>[
      if (r.studentCode != null) (Icons.badge_outlined, t('رقم الطالب', 'Student number'), r.studentCode!, true),
      if (r.program != null && r.program!.label.isNotEmpty) (Icons.account_tree_outlined, t('البرنامج', 'Programme'), r.program!.label, false),
      if (r.level != null) (Icons.stairs_outlined, t('الفرقة', 'Level'), studentLevelText(r.level!), false),
      if (r.enrolStatus.isNotEmpty) (Icons.how_to_reg_outlined, t('حالة القيد', 'Enrolment'), enrolLabel(r.enrolStatus), false),
      if (r.acadStanding != null) (Icons.insights_outlined, t('الوضع الأكاديمي', 'Academic standing'), standingLabel(r.acadStanding!), false),
      if (file.joinedAt != null) (Icons.event_available_outlined, t('انضم في', 'Joined'), AppTime.date(file.joinedAt!.toUtc()), false),
      if (file.email != null) (Icons.alternate_email_rounded, t('البريد', 'Email'), file.email!, true),
      if (file.phone != null) (Icons.phone_outlined, t('الهاتف', 'Phone'), file.phone!, true),
      if (file.birthDate != null) (Icons.cake_outlined, t('تاريخ الميلاد', 'Date of birth'), AppTime.wall(file.birthDate!), false),
      if (file.gender != null) (Icons.wc_rounded, t('النوع', 'Gender'), genderText(file.gender!), false),
      if (file.nationality != null) (Icons.flag_outlined, t('الجنسية', 'Nationality'), file.nationalityText!, false),
      if (r.nidLast4 != null) (Icons.fingerprint_rounded, t('آخر 4 أرقام من الهوية', 'ID, last 4 digits'), '•••• ${r.nidLast4}', true),
    ];
    final open = file.open;
    final meeting = open.nextMeeting;
    final openRows = <Widget>[
      if (open.complaints != null)
        _LinkRow(
          icon: Icons.report_outlined,
          tone: open.complaints! > 0 ? AppTone.warning : AppTone.neutral,
          text: open.complaints! == 0
              ? t('لا توجد شكاوى مفتوحة', 'No open complaints')
              : countText(open.complaints!,
                  ar1: 'شكوى مفتوحة', ar2: 'شكويان مفتوحتان', arFew: '{n} شكاوى مفتوحة', arMany: '{n} شكوى مفتوحة',
                  en1: '1 open complaint', en: '{n} open complaints'),
          onTap: tabs.contains(StudentFileTab.requests) ? () => onOpenTab?.call(StudentFileTab.requests) : null,
        ),
      if (open.requests > 0)
        _LinkRow(
          icon: Icons.assignment_outlined,
          tone: AppTone.info,
          text: countText(open.requests,
              ar1: 'طلب مفتوح', ar2: 'طلبان مفتوحان', arFew: '{n} طلبات مفتوحة', arMany: '{n} طلباً مفتوحاً',
              en1: '1 open request', en: '{n} open requests'),
          onTap: tabs.contains(StudentFileTab.requests) ? () => onOpenTab?.call(StudentFileTab.requests) : null,
        ),
      if (open.asks > 0)
        _LinkRow(
          icon: Icons.help_outline_rounded,
          tone: AppTone.info,
          text: countText(open.asks,
              ar1: 'طلب واحد بانتظار الطالب', ar2: 'طلبان بانتظار الطالب', arFew: '{n} طلبات بانتظار الطالب',
              arMany: '{n} طلباً بانتظار الطالب', en1: '1 ask waiting for the student', en: '{n} asks waiting for the student'),
        ),
      if (meeting != null)
        _LinkRow(
          icon: Icons.event_outlined,
          tone: AppTone.brand,
          text: meeting.title ?? t('اجتماع قادم', 'Upcoming meeting'),
          meta: meeting.startsAt == null ? null : AppTime.dateTime(meeting.startsAt!.toUtc()),
        ),
    ];
    final missing = r.missingCount ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (missingOn && missing > 0) ...[
        AppBanner(
          icon: Icons.assignment_late_outlined,
          color: context.colors.warning,
          text: countText(missing,
              ar1: 'ينقص ملف الطالب بند واحد', ar2: 'ينقص ملف الطالب بندان', arFew: 'ينقص ملف الطالب {n} بنود',
              arMany: 'ينقص ملف الطالب {n} بنداً', en1: '1 item is missing from the file', en: '{n} items are missing from the file'),
          action: onMissing == null
              ? null
              : AppButton(label: t('عرض الناقص', 'See what is missing'), size: AppButtonSize.sm, variant: AppButtonVariant.ghost, onPressed: onMissing),
        ),
        AppSpace.gapMd,
      ],
      _TabHeading(t('البيانات الأساسية', 'Key facts')),
      if (facts.isEmpty)
        AppCard(child: Text(t('لا توجد بيانات بعد', 'No details yet'), style: AppType.body(context)))
      else
        StudentFactsCard(rows: facts),
      if (file.intake != null && file.intake!.caseId != null) ...[
        AppSpace.gapLg,
        _TabHeading(t('الالتحاق', 'Admission')),
        AppCard(child: _IntakeLine(intake: file.intake!)),
      ],
      if (openRows.isNotEmpty) ...[
        AppSpace.gapLg,
        _TabHeading(t('ما زال مفتوحاً', 'Still open')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
          child: Column(children: [
            for (final (i, w) in openRows.indexed) ...[
              if (i > 0) Divider(height: AppSpace.xs, color: context.colors.divider),
              w,
            ],
          ]),
        ),
      ],
    ]);
  }
}

/// The admission case in one block: type, label, due date, conditional.
class _IntakeLine extends StatelessWidget {
  const _IntakeLine({required this.intake});
  final FileIntake intake;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = intake.label ?? 'accepted';
    final chip = StudentChip('intake', label);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (intake.typeLabel.isNotEmpty) Text(intake.typeLabel, style: AppType.bodyStrong(context)),
        AppStatusBadge(label: chip.label, tone: chip.tone, dense: true),
        if (intake.conditional) AppStatusBadge(label: t('قبول مشروط', 'Conditional'), tone: AppTone.warning, dense: true),
      ]),
      if (intake.dueAt != null) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(t('آخر موعد لاستكمال الملف: ${AppTime.date(intake.dueAt!.toUtc())}', 'Complete the file by ${AppTime.date(intake.dueAt!.toUtc())}'),
            style: AppType.meta(context).copyWith(color: c.textMedium)),
      ],
      if (intake.activatedAt != null) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(t('فُعّلت العضوية في ${AppTime.date(intake.activatedAt!.toUtc())}', 'Membership active since ${AppTime.date(intake.activatedAt!.toUtc())}'),
            style: AppType.meta(context).copyWith(color: c.textMedium)),
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Academic
// ═════════════════════════════════════════════════════════════════════════════

class StudentAcademicTab extends StatelessWidget {
  const StudentAcademicTab({super.key, required this.academic, this.standing, this.onOpenRecord});

  final StudentAcademic? academic;

  /// The student's `acad_standing`.
  final String? standing;

  /// Opens the full academic record (GPA, degree audit, transcript); opening it is recorded as `academic`.
  final VoidCallback? onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final a = academic;
    String n(double? v, {int digits = 0}) => v == null ? '—' : v.toStringAsFixed(digits);
    final rows = <(IconData, String, String, bool)>[
      if (a?.studySystem != null) (Icons.rule_rounded, t('نظام الدراسة', 'Study system'), studySystemText(a!.studySystem!), false),
      if (standing != null) (Icons.insights_outlined, t('الوضع الأكاديمي', 'Academic standing'), standingLabel(standing!), false),
      if (a != null && a.probations > 0)
        (Icons.warning_amber_rounded, t('مرات الإنذار', 'Warnings so far'), '${a.probations}', false),
      if (a?.advisorName != null) (Icons.support_agent_rounded, t('المرشد الأكاديمي', 'Academic advisor'), a!.advisorName!, false),
      if (a?.graduatedAt != null) (Icons.workspace_premium_outlined, t('تاريخ التخرج', 'Graduated on'), AppTime.date(a!.graduatedAt!.toUtc()), false),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _TabHeading(t('الملخص الأكاديمي', 'Academic summary')),
      if (a == null)
        AppCard(child: Text(t('لا يوجد سجل أكاديمي بعد', 'No academic record yet'), style: AppType.body(context)))
      else ...[
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          _Figure(label: t('المعدل التراكمي', 'CGPA'), value: n(a.cgpa, digits: 2)),
          _Figure(label: t('ساعات مكتسبة', 'Credits earned'), value: n(a.earnedCredits)),
          _Figure(label: t('ساعات مسجلة', 'Credits attempted'), value: n(a.attemptedCredits)),
        ]),
        if (rows.isNotEmpty) ...[AppSpace.gapMd, StudentFactsCard(rows: rows)],
      ],
      if (onOpenRecord != null) ...[
        AppSpace.gapMd,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: t('السجل الأكاديمي الكامل', 'Full academic record'),
            icon: Icons.history_edu_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: onOpenRecord,
          ),
        ),
      ],
    ]);
  }
}

/// One figure of the summary (the number large, its label under it).
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: AppSpace.xxxl * 2),
        child: AppCard(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, textDirection: TextDirection.ltr, style: AppType.figure(context)),
            Text(label, style: AppType.meta(context).copyWith(color: context.colors.textMedium)),
          ]),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  File & documents
// ═════════════════════════════════════════════════════════════════════════════

class StudentDocumentsTab extends StatelessWidget {
  const StudentDocumentsTab({super.key, this.intake, this.missingCount, this.onOpenCase, this.onMissing});

  final FileIntake? intake;
  final int? missingCount;

  /// Opens the admission case (fields, documents, verify / reject); null = the caller may not open it.
  final VoidCallback? onOpenCase;
  final VoidCallback? onMissing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = intake;
    if (i == null || i.caseId == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _TabHeading(t('الملف والمستندات', 'File & documents')),
        AppCard(
          child: Row(children: [
            Icon(Icons.folder_off_outlined, size: AppIconSize.md, color: c.textMedium),
            AppSpace.gapSm,
            Expanded(
              child: Text(t('لا يوجد ملف التحاق لهذا الطالب (أُضيف قبل نظام الالتحاق)', 'This student has no admission file (added before admissions)'),
                  style: AppType.body(context).copyWith(color: c.textMedium)),
            ),
          ]),
        ),
      ]);
    }
    final missing = missingCount ?? i.missingCount ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _TabHeading(t('الملف والمستندات', 'File & documents'),
          subtitle: t('البيانات والمستندات التي قدّمها الطالب عند الالتحاق', 'The details and documents the student gave at admission')),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _IntakeLine(intake: i),
          AppSpace.gapSm,
          Text(
            missing == 0
                ? t('كل المستندات المطلوبة مكتملة', 'Every required document is in')
                : countText(missing,
                    ar1: 'ينقص بند واحد', ar2: 'ينقص بندان', arFew: 'تنقص {n} بنود', arMany: 'ينقص {n} بنداً',
                    en1: '1 item missing', en: '{n} items missing'),
            style: AppType.row(context).copyWith(color: missing == 0 ? c.success : c.warning),
          ),
          if (onOpenCase != null || (missing > 0 && onMissing != null)) ...[
            AppSpace.gapMd,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              if (onOpenCase != null)
                AppButton(label: t('فتح ملف الالتحاق', 'Open the admission file'), icon: Icons.folder_open_rounded, onPressed: onOpenCase),
              if (missing > 0 && onMissing != null)
                AppButton(
                    label: t('ما الناقص؟', 'What is missing?'),
                    icon: Icons.assignment_late_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: onMissing),
            ]),
          ],
        ]),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Requests & complaints
// ═════════════════════════════════════════════════════════════════════════════

class StudentRequestsTab extends StatelessWidget {
  const StudentRequestsTab({super.key, required this.open, required this.can, this.onOpenComplaints, this.onOpenRequests});

  final StudentOpen open;
  final StudentCan can;
  final VoidCallback? onOpenComplaints;
  final VoidCallback? onOpenRequests;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (can.complaints && open.complaints != null)
        _LinkRow(
          icon: Icons.report_outlined,
          tone: open.complaints! > 0 ? AppTone.warning : AppTone.neutral,
          text: t('الشكاوى', 'Complaints'),
          meta: open.complaints! == 0
              ? t('لا توجد شكاوى مفتوحة', 'No open complaints')
              : countText(open.complaints!,
                  ar1: 'شكوى مفتوحة', ar2: 'شكويان مفتوحتان', arFew: '{n} شكاوى مفتوحة', arMany: '{n} شكوى مفتوحة',
                  en1: '1 open complaint', en: '{n} open complaints'),
          onTap: onOpenComplaints,
        ),
      if (can.requests)
        _LinkRow(
          icon: Icons.assignment_outlined,
          tone: open.requests > 0 ? AppTone.info : AppTone.neutral,
          text: t('الطلبات والمعاملات', 'Requests'),
          meta: open.requests == 0
              ? t('لا توجد طلبات مفتوحة', 'No open requests')
              : countText(open.requests,
                  ar1: 'طلب مفتوح', ar2: 'طلبان مفتوحان', arFew: '{n} طلبات مفتوحة', arMany: '{n} طلباً مفتوحاً',
                  en1: '1 open request', en: '{n} open requests'),
          onTap: onOpenRequests,
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _TabHeading(t('الطلبات والشكاوى', 'Requests & complaints'),
          subtitle: t('تُفتح في صفحاتها المعتادة', 'Each opens in its usual page')),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                child: Text(t('لا شيء هنا', 'Nothing here'), style: AppType.body(context)),
              )
            : Column(children: [
                for (final (i, w) in rows.indexed) ...[
                  if (i > 0) Divider(height: AppSpace.xs, color: context.colors.divider),
                  w,
                ],
              ]),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Advising
// ═════════════════════════════════════════════════════════════════════════════

class StudentAdvisingTab extends StatelessWidget {
  const StudentAdvisingTab({super.key, this.advisorName, this.onOpen});

  final String? advisorName;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _TabHeading(t('الإرشاد الأكاديمي', 'Academic advising')),
        AppActionCard(
          icon: Icons.support_agent_rounded,
          title: t('ملف الإرشاد', 'Advising record'),
          subtitle: advisorName == null
              ? t('الملاحظات والمواعيد وخطط الدعم', 'Notes, appointments and support plans')
              : t('المرشد: $advisorName', 'Advisor: $advisorName'),
          onTap: onOpen,
        ),
      ]);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Access log
// ═════════════════════════════════════════════════════════════════════════════

/// Loads the access log (opening it is itself recorded as `access_log`) and pages it.
class StudentAccessLogTab extends StatefulWidget {
  const StudentAccessLogTab({super.key, required this.api, required this.uid});

  final StudentsApi api;
  final int uid;

  @override
  State<StudentAccessLogTab> createState() => _StudentAccessLogTabState();
}

class _StudentAccessLogTabState extends State<StudentAccessLogTab> {
  final _rows = <AccessLogEntry>[];
  int _page = 0, _pages = 1, _total = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _next();
  }

  Future<void> _next() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await widget.api.accessLog(widget.uid, page: _page + 1);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!r.ok) {
        _error = orgErrorText(r.error!);
        return;
      }
      final p = StudentAccessLog.fromJson(r.map);
      _rows.addAll(p.items);
      _page = p.page;
      _pages = p.pages;
      _total = p.total;
    });
  }

  @override
  Widget build(BuildContext context) => StudentAccessLogView(
        rows: _rows,
        total: _total,
        loading: _loading,
        error: _error,
        onRetry: _next,
        hasMore: _page < _pages,
        onLoadMore: _next,
      );
}

class StudentAccessLogView extends StatelessWidget {
  const StudentAccessLogView({
    super.key,
    required this.rows,
    this.total = 0,
    this.loading = false,
    this.error,
    this.onRetry,
    this.hasMore = false,
    this.onLoadMore,
  });

  final List<AccessLogEntry> rows;
  final int total;
  final bool loading, hasMore;
  final String? error;
  final VoidCallback? onRetry, onLoadMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = _TabHeading(
      t('سجل الاطلاع', 'Access log'),
      subtitle: total == 0
          ? t('من فتح هذا الملف ومتى', 'Who opened this file, and when')
          : countText(total,
              ar1: 'مرة اطلاع واحدة', ar2: 'مرتا اطلاع', arFew: '{n} مرات اطلاع', arMany: '{n} مرة اطلاع',
              en1: '1 view recorded', en: '{n} views recorded'),
    );
    if (rows.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        if (loading)
          const AppListSkeleton(items: 3)
        else if (error != null)
          AppErrorState(message: error, onRetry: onRetry, compact: true)
        else
          AppCard(child: Text(t('لم يفتح أحد هذا الملف بعد', 'Nobody has opened this file yet'), style: AppType.body(context))),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        child: Column(children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) Divider(height: AppSpace.xs, color: c.divider),
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AppAvatar(name: r.actorName.isEmpty ? '?' : r.actorName, size: AppTouch.min - AppSpace.md),
                  AppSpace.gapSm,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.actorName.isEmpty ? t('غير معروف', 'Unknown') : r.actorName, style: AppType.row(context)),
                      Text(
                        [r.sectionLabel, if (r.at != null) AppTime.dateTime(r.at!.toUtc())].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.meta(context).copyWith(color: c.textMedium),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ],
        ]),
      ),
      if (error != null) AppErrorState(message: error, onRetry: onRetry, compact: true),
      if (hasMore && error == null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.md),
          child: Center(
            child: AppButton(
              label: t('عرض المزيد', 'Load more'),
              icon: Icons.expand_more_rounded,
              variant: AppButtonVariant.secondary,
              busy: loading,
              onPressed: onLoadMore,
            ),
          ),
        ),
    ]);
  }
}
