// lib/features/student/record/student_record_pages.dart — a student's own record (D-290, phase 7): configurations of the
// shared list (entity_list_page.dart), nothing of their own.
//
//   Grades and certificates    StudentGradesPage: every assessment (GET /entities/students/{me}/grades) · certificates
//   Payments and subscriptions StudentMoneyPage:  payments · subscription events
//   Courses I left             studentLeftCoursesList: My courses' "Left" filter, with the date and reason
//
// A grade or payment opens its course's panel: progress, lessons, deadlines, the assessments of that course and the
// student's history in it. The server scopes every list to the student themselves.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/design/master_detail/entity_list_page.dart';
import 'package:flutter_education_app/design/master_detail/entity_specs.dart';
import 'package:flutter_education_app/design/master_detail/entity_exports.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/features/student/certificates/my_certificates_screen.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

Future<EntityPage<T>> _rows<T extends EntityItem>(int studentId, String section, EntityListQuery q) async {
  final p = await EntitiesApi.instance.page(EntityRef(EntityKind.student, studentId), section, query: q);
  return EntityPage<T>(items: p.items.whereType<T>().toList(), total: p.total, page: p.page, size: p.size, pages: p.pages);
}

Widget _courseCell(EntityCourse? course) => course == null ? const SizedBox.shrink() : EntityChip(course.ref);

// ── Grades ───────────────────────────────────────────────────────────────────

EntityListConfig<GradeRow> studentGradesList(int studentId) => EntityListConfig<GradeRow>(
      id: 'student_grades',
      title: 'md_p7_sec_grades'.tr,
      rowKind: EntityKind.course,
      load: (q) => _rows<GradeRow>(studentId, 'grades', q),
      idOf: (r) => '${r.source}:${r.id}',
      refOf: (r) => r.course?.ref,
      searchHint: 'md_p7_search_grades'.tr,
      sorts: const ['newest', 'oldest', 'score_desc', 'score_asc'],
      empty: EntityListEmpty(Icons.grading_rounded, 'md_p7_empty_grades'.tr),
      columns: [
        AppTableColumn(
          key: 'title',
          label: 'md_p7_assessment'.tr,
          primary: true,
          flex: 3,
          cell: (context, r) => Text(r.title.isEmpty ? 'md_p7_grade_untitled'.tr : r.title,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
        ),
        AppTableColumn(key: 'course', label: 'md_kind_course'.tr, flex: 2, cell: (context, r) => _courseCell(r.course)),
        AppTableColumn(key: 'score', label: 'md_p7_score'.tr, cell: (context, r) => gradeBadge(r)),
        AppTableColumn.text(key: 'at', label: 'md_p7_date'.tr, text: (r) => mdDate(r.at)),
      ],
      card: (context, r) => gradeRowFor(context, r, ownerKind: EntityKind.student, link: false),
      export: entityGradeExport(),
    );

// ── Payments and subscriptions ───────────────────────────────────────────────

EntityListConfig<PaymentRow> studentPaymentsList(int studentId) => EntityListConfig<PaymentRow>(
      id: 'student_payments',
      title: 'md_sec_payments'.tr,
      rowKind: EntityKind.course,
      load: (q) => _rows<PaymentRow>(studentId, 'payments', q),
      idOf: (r) => r.id,
      refOf: (r) => r.course?.ref,
      searchHint: 'md_p7_search_payments'.tr,
      sorts: const ['newest', 'oldest', 'amount_desc'],
      empty: EntityListEmpty(Icons.payments_outlined, 'md_empty_section'.tr),
      columns: [
        AppTableColumn(key: 'course', label: 'md_kind_course'.tr, primary: true, flex: 3, cell: (context, r) => _courseCell(r.course)),
        AppTableColumn.text(
            key: 'amount',
            label: 'md_p7_amount'.tr,
            numeric: true,
            text: (r) => r.amount == null ? '—' : mdMoney(EntityMoney(r.amount!, r.currency))),
        AppTableColumn(
          key: 'status',
          label: 'md_p7_status'.tr,
          cell: (context, r) => AppStatusBadge(label: mdPaymentStatus(r.status), tone: mdPaymentTone(r.status), dense: true),
        ),
        AppTableColumn.text(key: 'at', label: 'md_p7_date'.tr, text: (r) => mdDate(r.paidAt ?? r.createdAt)),
      ],
      card: (context, r) => IgnorePointer(child: entityRowFor(context, r)),
      export: entityPaymentExport(),
    );

EntityListConfig<SubscriptionRow> studentSubscriptionsList(int studentId) => EntityListConfig<SubscriptionRow>(
      id: 'student_subscriptions',
      title: 'md_sec_subscriptions'.tr,
      rowKind: EntityKind.course,
      load: (q) => _rows<SubscriptionRow>(studentId, 'subscriptions', q),
      idOf: (r) => r.json['id'] as Object? ?? r.hashCode,
      refOf: (r) => r.course?.ref,
      sorts: const ['newest', 'oldest'],
      empty: EntityListEmpty(Icons.receipt_long_outlined, 'md_empty_section'.tr),
      columns: [
        AppTableColumn.text(key: 'type', label: 'md_p7_status'.tr, primary: true, flex: 2, text: (r) => mdSubscriptionText(r.type)),
        AppTableColumn(key: 'course', label: 'md_kind_course'.tr, flex: 3, cell: (context, r) => _courseCell(r.course)),
        AppTableColumn.text(key: 'at', label: 'md_p7_date'.tr, text: (r) => mdDateTime(r.occurredAt)),
      ],
      card: (context, r) => IgnorePointer(child: entityRowFor(context, r)),
    );

// ── Courses I left ───────────────────────────────────────────────────────────

/// The courses the student left (My courses shows the active ones): the date and the reason on each.
EntityListConfig<EnrollmentRow> studentLeftCoursesList(int studentId) => EntityListConfig<EnrollmentRow>(
      id: 'student_left_courses',
      title: 'courses'.tr,
      rowKind: EntityKind.course,
      load: (q) => _rows<EnrollmentRow>(studentId, 'courses', q),
      idOf: (r) => r.subject.id,
      refOf: (r) => r.subject,
      fixedFilter: const {'state': 'withdrawn'},
      searchable: false,
      empty: EntityListEmpty(Icons.sentiment_satisfied_alt_rounded, 'md_p7_empty_left'.tr),
      columns: [
        AppTableColumn(key: 'course', label: 'md_kind_course'.tr, primary: true, flex: 3, cell: (context, r) => EntityChip(r.subject)),
        AppTableColumn(
          key: 'progress',
          label: 'md_progress'.tr,
          flex: 2,
          cell: (context, r) => EntityProgress(r.enrollment.progress),
        ),
        AppTableColumn.text(key: 'at', label: 'md_p7_date'.tr, text: (r) => mdDate(r.enrollment.withdrawnAt)),
        AppTableColumn.text(
            key: 'reason',
            label: 'md_p7_reason'.tr,
            flex: 2,
            text: (r) => mdReasonLabel(r.enrollment.withdrawalReasonCode)),
      ],
      card: (context, r) => IgnorePointer(child: entityRowFor(context, r)),
    );

// ── Pages ────────────────────────────────────────────────────────────────────

/// A page of two lists under one strip.
class _TwoListsPage extends StatefulWidget {
  const _TwoListsPage({required this.pageKey, required this.title, required this.tabs, required this.builder});

  final String pageKey;
  final String title;
  final List<AppTabItem> tabs;
  final Widget Function(BuildContext context, int tab, int studentId) builder;

  @override
  State<_TwoListsPage> createState() => _TwoListsPageState();
}

class _TwoListsPageState extends State<_TwoListsPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final me = context.select<MyAuthProvider, int?>((a) => a.currentUser?.id);
    return BasePage(
      key: ValueKey(widget.pageKey),
      useWebCard: true,
      appBar: ScreenAppBar(title: widget.title),
      child: SafeArea(
        bottom: false,
        child: me == null
            ? const SizedBox.shrink()
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                  child: AppTabs(items: widget.tabs, index: _tab, onChanged: (i) => setState(() => _tab = i), expand: true),
                ),
                Expanded(child: KeyedSubtree(key: ValueKey('${widget.pageKey}.$_tab'), child: widget.builder(context, _tab, me))),
              ]),
      ),
    );
  }
}

/// Grades and certificates.
class StudentGradesPage extends StatelessWidget {
  const StudentGradesPage({super.key});

  @override
  Widget build(BuildContext context) => _TwoListsPage(
        pageKey: 'student_grades',
        title: 'md_p7_grades_certificates'.tr,
        tabs: [AppTabItem('md_p7_sec_grades'.tr), AppTabItem('my_certificates'.tr)],
        builder: (context, tab, me) => tab == 0
            ? EntityListPage<GradeRow>(config: studentGradesList(me))
            : const MyCertificatesScreen(embedded: true),
      );
}

/// Payments and subscriptions.
class StudentMoneyPage extends StatelessWidget {
  const StudentMoneyPage({super.key});

  @override
  Widget build(BuildContext context) => _TwoListsPage(
        pageKey: 'student_payments',
        title: 'md_p7_payments_subscriptions'.tr,
        tabs: [AppTabItem('md_sec_payments'.tr), AppTabItem('md_sec_subscriptions'.tr)],
        builder: (context, tab, me) => tab == 0
            ? EntityListPage<PaymentRow>(config: studentPaymentsList(me))
            : EntityListPage<SubscriptionRow>(config: studentSubscriptionsList(me)),
      );
}
