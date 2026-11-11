// lib/features/admin/admin_table_export.dart — paged admin / organization lists exported through the generic
// exporter (lib/design/app_table_export.dart). A list only holds the pages scrolled so far, so the export first
// fetches every page with the list's own search · filters · sort, then opens the format / column picker.
//
//   PagedList<AdminUsersProvider>(…, export: (rows) => adminUsersExport('student', rows))
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../core/api_client.dart';
import '../../config/app_config.dart' show AppConfig;
import '../../core/app_time.dart';
import '../../design/app_table_export.dart';
import '../../design/export/export_job.dart' show ExportJob, runExportWithProgress;
import 'admin_common.dart';
import 'admin_filter_models.dart' show encodeFilters;
import 'admin_models.dart' show PageData;
import 'admin_providers.dart' show AdminPagedProvider;

/// Every row of [p]'s list (current search / filters / sort), [pageSize] per request, at most [maxRows].
/// [progress] shows "rows n / total" and stops between pages when the person cancels (ExportCancelled).
Future<List<Map<String, dynamic>>> fetchAllRows(AdminPagedProvider p, {int pageSize = 200, int maxRows = 20000, ExportJob? progress}) async {
  if (p.allLoaded) return List.of(p.rows);
  final out = <Map<String, dynamic>>[];
  for (var page = 1;; page++) {
    progress?.throwIfCancelled();
    final r = await ApiClient().get(p.path, queryParams: {
      for (final e in p.filters.entries)
        if (e.value != null && '${e.value}'.isNotEmpty) e.key: e.value,
      ...encodeFilters(p.adv),
      if (p.search.isNotEmpty) 'search': p.search,
      if (p.sort != null) 'sort': p.sort,
      'page': page,
      'size': pageSize,
    });
    if (r is! Map) break;
    final d = PageData(Map<String, dynamic>.from(r));
    out.addAll(d.items);
    final total = d.pages <= 0 ? out.length : (d.pages * pageSize).clamp(out.length, maxRows);
    progress?.step('${t('جلب الصفوف', 'Fetching rows')} ${out.length} / $total', d.pages <= 0 ? null : page / d.pages);
    if (d.items.isEmpty || page >= d.pages || out.length >= maxRows) break;
  }
  progress?.throwIfCancelled();
  return out;
}

/// The list's search and filters, printed under the export title.
Map<String, String> activeFiltersOf(AdminPagedProvider p) => {
      if (p.search.isNotEmpty) t('بحث', 'Search'): p.search,
      for (final e in p.adv.entries)
        if (e.value != null) e.key.replaceAll('_', ' '): e.value is DateTime ? AppTime.date((e.value as DateTime).toUtc()) : '${e.value}',
    };

bool _busy = false;

/// Fetches every row of [p], builds the table with [build] and opens the export sheet.
Future<void> exportPagedList(BuildContext context, AdminPagedProvider p, AppTableExport Function(List<Map<String, dynamic>> rows) build) async {
  if (_busy) return;
  _busy = true;
  try {
    // every page behind a progress dialog with Cancel; the export sheet then writes the file (with its own progress)
    final rows = !p.allLoaded
        ? await runExportWithProgress(context, (job) => fetchAllRows(p, progress: job), title: t('جارٍ تجهيز كل الصفوف…', 'Preparing every row…'))
        : List.of(p.rows);
    if (rows == null) {
      toast(t('أُلغي التصدير', 'Export cancelled'));
      return;
    }
    if (!context.mounted) return;
    final e = bilingualExport(() => build(rows));
    await showAppExportSheet(context, e.copyWith(filters: {...activeFiltersOf(p), ...e.filters}));
  } catch (err) {
    toast(ApiException.from(err).message, error: true);
  } finally {
    _busy = false;
  }
}

/// Exports rows that are NOT an [AdminPagedProvider] list (the payments hub, the payout requests): [fetch] gets every
/// row behind a progress dialog with Cancel, [build] turns them into the table, the export sheet writes the file.
Future<void> exportFetched(
  BuildContext context, {
  required Future<List<Map<String, dynamic>>> Function(ExportJob job) fetch,
  required AppTableExport Function(List<Map<String, dynamic>> rows) build,
  Map<String, String> filters = const {},
}) async {
  if (_busy) return;
  _busy = true;
  try {
    final rows = await runExportWithProgress(context, fetch, title: t('جارٍ تجهيز كل الصفوف…', 'Preparing every row…'));
    if (rows == null) {
      toast(t('أُلغي التصدير', 'Export cancelled'));
      return;
    }
    if (!context.mounted) return;
    final e = bilingualExport(() => build(rows));
    await showAppExportSheet(context, e.copyWith(filters: {...filters, ...e.filters}));
  } catch (err) {
    toast(ApiException.from(err).message, error: true);
  } finally {
    _busy = false;
  }
}

/// Payment history (the payments hub): date · payer · course · amount · currency · method · status.
AppTableExport adminPaymentsExport(List<Map<String, dynamic>> rows) {
  String courseName(Map<String, dynamic> c) {
    final ar = asStr(c['name_ar']);
    final en = asStr(c['name_en']);
    final first = t(ar, en);
    return first.isNotEmpty ? first : (ar.isNotEmpty ? ar : en);
  }

  return AppTableExport(
    id: 'admin.payments',
    title: t('سجل المدفوعات', 'Payment history'),
    columns: [
      AppExportColumn('created_at', t('التاريخ', 'Date'), type: AppColType.dateTime),
      AppExportColumn('payer', t('الدافع', 'Payer'), locked: true, total: AppTotal.count),
      AppExportColumn('course', t('الكورس', 'Course')),
      AppExportColumn('amount', t('المبلغ', 'Amount'), type: AppColType.money, total: AppTotal.sum),
      AppExportColumn('currency', t('العملة', 'Currency'), width: 9),
      AppExportColumn('method', t('الطريقة', 'Method')),
      _status('status', t('الحالة', 'Status'), {
        'pending': t('قيد الانتظار', 'Pending'),
        'completed': t('مكتمل', 'Completed'),
        'failed': t('فشل', 'Failed'),
        'refunded': t('مُسترد', 'Refunded'),
        'cancelled': t('ملغي', 'Cancelled'),
      }),
    ],
    rows: [
      for (final r in rows)
        {
          'created_at': r['created_at'],
          'payer': asStr(asMap(r['student'])['name']),
          'course': courseName(asMap(r['course'])),
          'amount': r['amount'],
          'currency': asStr(r['currency']) == '—' ? '' : asStr(r['currency']),
          'method': asStr(r['method']),
          'status': asStr(r['status']),
        },
    ],
  );
}

/// A compact "Export" pill for list headers.
class AppExportPill extends StatelessWidget {
  const AppExportPill({super.key, required this.onTap, this.label});
  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.primary.withValues(alpha: .08),
      shape: StadiumBorder(side: BorderSide(color: c.primary.withValues(alpha: .25))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.ios_share_rounded, size: 16, color: c.primary),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: Text(label ?? t('تصدير · Excel · Word · PDF', 'Export · Excel · Word · PDF'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.primary, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Tables
// ═════════════════════════════════════════════════════════════════════════════

AppExportColumn _status(String id, String label, Map<String, String> labels) => AppExportColumn(id, label, type: AppColType.status, statusLabels: labels);

/// Platform users (students / teachers / admins).
AppTableExport adminUsersExport(String role, List<Map<String, dynamic>> rows) => AppTableExport(
      id: 'admin.users.$role',
      title: switch (role) { 'teacher' => t('المعلمون', 'Teachers'), 'admin' => t('المشرفون', 'Admins'), _ => t('الطلاب', 'Students') },
      columns: [
        AppExportColumn('id', '#', type: AppColType.integer, width: 8, visible: false),
        AppExportColumn('name', t('الاسم', 'Name'), locked: true, total: AppTotal.count),
        AppExportColumn('gmail', t('البريد', 'Email')),
        AppExportColumn('phone', t('الهاتف', 'Phone')),
        AppExportColumn('country', t('الدولة', 'Country')),
        _status('state', t('الحالة', 'Status'), {'active': t('نشط', 'Active'), 'inactive': t('موقوف', 'Inactive'), 'pending_deletion': t('بانتظار الحذف', 'Pending deletion')}),
        _status('verified', t('موثّق', 'Verified'), {'yes': t('نعم', 'Yes'), 'no': t('لا', 'No')}),
        AppExportColumn('courses_count', t('الكورسات', 'Courses'), type: AppColType.integer, total: AppTotal.sum),
        if (role == 'teacher') AppExportColumn('net_earnings', t('صافي الأرباح', 'Net earnings'), type: AppColType.money, total: AppTotal.sum),
        AppExportColumn('login_times', t('مرات الدخول', 'Logins'), type: AppColType.integer, visible: false),
        AppExportColumn('created_at', t('تاريخ التسجيل', 'Joined'), type: AppColType.date),
        AppExportColumn('last_login', t('آخر دخول', 'Last login'), type: AppColType.dateTime, visible: false),
      ],
      rows: [
        for (final r in rows)
          {
            ...r,
            'state': asBool(r['pending_deletion']) ? 'pending_deletion' : (asBool(r['is_active']) ? 'active' : 'inactive'),
            'verified': asBool(r['is_verified']) ? 'yes' : 'no',
          },
      ],
    );

/// Categories.
AppTableExport adminCategoriesExport(List<Map<String, dynamic>> rows) => AppTableExport(
      id: 'admin.categories',
      title: t('التصنيفات', 'Categories'),
      columns: [
        AppExportColumn('id', '#', type: AppColType.integer, width: 8, visible: false),
        AppExportColumn('name_ar', t('الاسم بالعربية', 'Arabic name'), locked: true, total: AppTotal.count),
        AppExportColumn('name_en', t('الاسم بالإنجليزية', 'English name')),
        AppExportColumn('description', t('الوصف', 'Description'), visible: false),
        AppExportColumn('courses_count', t('الكورسات', 'Courses'), type: AppColType.integer, total: AppTotal.sum),
        AppExportColumn('teachers_count', t('المعلمون', 'Teachers'), type: AppColType.integer),
        AppExportColumn('students_count', t('الطلاب', 'Students'), type: AppColType.integer),
      ],
      rows: rows,
    );

/// Subscription requests.
AppTableExport adminSubscriptionsExport(List<Map<String, dynamic>> rows) => AppTableExport(
      id: 'admin.subscriptions',
      title: t('الاشتراكات', 'Subscriptions'),
      columns: [
        AppExportColumn('student_name', t('الطالب', 'Student'), locked: true, total: AppTotal.count),
        AppExportColumn('student_gmail', t('البريد', 'Email')),
        AppExportColumn('plan_code', t('الخطة', 'Plan')),
        AppExportColumn('amount', t('المبلغ', 'Amount'), type: AppColType.money, total: AppTotal.sum),
        AppExportColumn('currency', t('العملة', 'Currency'), width: 9),
        _status('status', t('الحالة', 'Status'), {
          'pending': t('معلق', 'Pending'),
          'active': t('نشط', 'Active'),
          'rejected': t('مرفوض', 'Rejected'),
          'expired': t('منتهي', 'Expired'),
          'cancelled': t('ملغي', 'Cancelled'),
        }),
        AppExportColumn('payment_method', t('طريقة الدفع', 'Payment method')),
        AppExportColumn('transfer_reference', t('مرجع التحويل', 'Transfer reference'), visible: false),
        AppExportColumn('starts_at', t('البداية', 'Starts'), type: AppColType.date),
        AppExportColumn('ends_at', t('النهاية', 'Ends'), type: AppColType.date),
        AppExportColumn('created_at', t('تاريخ الطلب', 'Requested'), type: AppColType.dateTime, visible: false),
      ],
      rows: rows,
    );

/// Platform courses.
AppTableExport adminCoursesExport(List<Map<String, dynamic>> rows) => AppTableExport(
      id: 'admin.courses',
      title: t('الكورسات', 'Courses'),
      columns: [
        AppExportColumn('name', t('الكورس', 'Course'), locked: true, total: AppTotal.count),
        AppExportColumn('teacher_name', t('المعلم', 'Teacher')),
        AppExportColumn('category_name', t('التصنيف', 'Category')),
        AppExportColumn('type', t('النوع', 'Type'), visible: false),
        _status('published', t('النشر', 'Published'), {'yes': t('منشور', 'Published'), 'no': t('مسودة', 'Draft')}),
        AppExportColumn('final_price', t('السعر', 'Price'), type: AppColType.money),
        AppExportColumn('currency', t('العملة', 'Currency'), width: 9),
        AppExportColumn('students_count', t('الطلاب', 'Students'), type: AppColType.integer, total: AppTotal.sum),
        AppExportColumn('completion_rate', t('نسبة الإتمام %', 'Completion %'), type: AppColType.number),
        AppExportColumn('avg_progress', t('متوسط التقدم %', 'Average progress %'), type: AppColType.number, visible: false),
        AppExportColumn('withdrawn_count', t('المنسحبون', 'Withdrawn'), type: AppColType.integer, total: AppTotal.sum, visible: false),
        AppExportColumn('rating_avg', t('التقييم', 'Rating'), type: AppColType.number),
        AppExportColumn('rating_count', t('عدد التقييمات', 'Ratings'), type: AppColType.integer, visible: false),
        AppExportColumn('paid_count', t('المدفوع', 'Paid'), type: AppColType.integer, total: AppTotal.sum),
        AppExportColumn('income', t('الدخل', 'Income'), type: AppColType.money, total: AppTotal.sum),
        AppExportColumn('pending_payments', t('مدفوعات معلقة', 'Pending payments'), type: AppColType.integer, total: AppTotal.sum, visible: false),
        AppExportColumn('created_at', t('تاريخ الإنشاء', 'Created'), type: AppColType.date, visible: false),
      ],
      rows: [
        for (final r in rows)
          {
            ...r,
            'name': _localName(r, fallback: asStr(r['name'])),
            'published': asBool(r['is_published']) ? 'yes' : 'no',
            'category_name': _localName(asMap(r['category'])),
          },
      ],
    );

/// A `name_ar` / `name_en` pair in the export's language, falling back to the other one.
String _localName(Map<String, dynamic> j, {String fallback = ''}) {
  final ar = asStrOrNull(j['name_ar']) ?? '', en = asStrOrNull(j['name_en']) ?? '';
  final name = t(ar.isEmpty ? en : ar, en.isEmpty ? ar : en);
  return name.isEmpty ? fallback : name;
}

/// Organizations (the platform admin's review list). [typeLabels]: the organization type -> its label.
AppTableExport adminOrganizationsExport(List<Map<String, dynamic>> rows, {Map<String, String> typeLabels = const {}}) => AppTableExport(
      id: 'admin.organizations',
      title: t('المؤسسات', 'Organizations'),
      columns: [
        AppExportColumn('id', '#', type: AppColType.integer, width: 8, visible: false),
        AppExportColumn('name', t('المؤسسة', 'Organization'), locked: true, total: AppTotal.count),
        AppExportColumn('type_label', t('النوع', 'Type')),
        _status('status', t('الحالة', 'Status'), {
          'pending': t('بانتظار المراجعة', 'Waiting'),
          'approved': t('معتمدة', 'Approved'),
          'rejected': t('تحتاج تعديل', 'Needs changes'),
          'suspended': t('موقوفة', 'Suspended'),
          'deleted': t('محذوفة', 'Deleted'),
        }),
        AppExportColumn('parent_name', t('تابعة لـ', 'Under')),
        AppExportColumn('license_no', t('رقم الترخيص', 'Licence number'), visible: false),
        AppExportColumn('creator_name', t('مقدم الطلب', 'Applicant')),
        AppExportColumn('creator_email', t('البريد', 'Email'), visible: false),
        AppExportColumn('submitted_at', t('أُرسل', 'Sent'), type: AppColType.dateTime),
      ],
      rows: [
        for (final r in rows)
          {
            ...r,
            'name': _localName(r),
            'type_label': typeLabels[asStr(r['type'])] ?? asStr(r['type']),
            'parent_name': r['parent'] is Map ? _localName(asMap(r['parent'])) : '',
            'creator_name': asStr(asMap(r['creator'])['name']),
            'creator_email': asStr(asMap(r['creator'])['email']),
          },
      ],
    );

/// Teacher withdrawal (payout) requests.
AppTableExport adminWithdrawalsExport(List<Map<String, dynamic>> rows) => AppTableExport(
      id: 'admin.withdrawals',
      title: t('طلبات السحب', 'Payout requests'),
      columns: [
        AppExportColumn('id', '#', type: AppColType.integer, width: 8),
        AppExportColumn('teacher_name', t('المعلم', 'Teacher'), locked: true),
        AppExportColumn('teacher_gmail', t('البريد', 'Email')),
        AppExportColumn('amount', t('المبلغ', 'Amount'), type: AppColType.money, total: AppTotal.sum),
        AppExportColumn('payout_currency', t('العملة', 'Currency'), width: 9),
        _status('status', t('الحالة', 'Status'), {'pending': t('معلق', 'Pending'), 'approved': t('مقبول', 'Approved'), 'paid': t('مدفوع', 'Paid'), 'rejected': t('مرفوض', 'Rejected')}),
        AppExportColumn('payout_method', t('الطريقة', 'Method')),
        AppExportColumn('bank_reference', t('مرجع البنك', 'Bank reference'), visible: false),
        AppExportColumn('note', t('ملاحظة', 'Note'), visible: false),
        AppExportColumn('requested_at', t('تاريخ الطلب', 'Requested'), type: AppColType.dateTime),
        AppExportColumn('processed_at', t('تاريخ التنفيذ', 'Processed'), type: AppColType.dateTime),
      ],
      rows: rows,
    );

/// Organization members (students / teachers / staff).
/// [orgId] / [roles] / [status] (the people page's tab and filter) make it an organization export: templates can be
/// shared with the organization, and "Share link" / "Schedule" use the server dataset `org.people` (Export Studio).
AppTableExport orgMembersExport(String kind, List<Map<String, dynamic>> rows, {String? orgName, int? orgId, String? roles, String? status}) => AppTableExport(
      id: 'org.members.$kind',
      orgId: orgId,
      serverDataset: orgId == null ? null : 'org.people',
      serverParams: orgId == null ? null : {'org_id': orgId, 'roles': ?roles, 'status': ?status},
      title: switch (kind) { 'teachers' => t('المعلمون', 'Teachers'), 'staff' => t('فريق العمل', 'Staff'), _ => t('الطلاب', 'Students') },
      brand: orgName,
      columns: [
        AppExportColumn('name', t('الاسم', 'Name'), locked: true, total: AppTotal.count),
        AppExportColumn('email', t('البريد', 'Email')),
        if (kind == 'students') AppExportColumn('student_code', t('الكود', 'Code')),
        if (kind != 'students') AppExportColumn('role', t('الدور', 'Role')),
        AppExportColumn('departments', t('الأقسام', 'Departments')),
        if (kind == 'students') AppExportColumn('academic_level', t('المستوى', 'Level')),
        if (kind == 'students') AppExportColumn('cohort', t('الدفعة', 'Cohort'), visible: false),
        _status('status', t('الحالة', 'Status'), {
          'active': t('نشط', 'Active'),
          'pending': t('طلب انضمام', 'Join request'),
          'scheduled': t('مجدول', 'Scheduled'),
          'expired': t('منتهي', 'Expired'),
          'suspended': t('موقوف', 'Suspended'),
          'rejected': t('مرفوض', 'Rejected'),
        }),
      ],
      rows: [
        for (final r in rows)
          {
            ...r,
            'name': asMap(r['user'])['name'],
            'email': asMap(r['user'])['email'],
            'status': r['effective_status'] ?? r['status'],
            'departments': r['departments'] is List ? (r['departments'] as List).map((d) => d is Map ? (d['name'] ?? d['name_ar'] ?? d['id']) : d).join('، ') : r['departments'],
            'academic_level': r['academic_level'] is Map ? (r['academic_level'] as Map)['name'] : r['academic_level'],
            'cohort': r['cohort'] is Map ? (r['cohort'] as Map)['name'] : r['cohort'],
          },
      ],
    );

/// Organization courses.
AppTableExport orgCoursesExport(List<Map<String, dynamic>> rows, {String? orgName}) => AppTableExport(
      id: 'org.courses',
      title: t('الكورسات', 'Courses'),
      brand: orgName,
      columns: [
        AppExportColumn('code', t('الكود', 'Code'), width: 12),
        AppExportColumn('name', t('الكورس', 'Course'), locked: true, total: AppTotal.count),
        AppExportColumn('teacher', t('المدرس', 'Teacher')),
        AppExportColumn('scope', t('النطاق', 'Scope')),
        AppExportColumn('students', t('الطلاب', 'Students'), type: AppColType.integer, total: AppTotal.sum),
        AppExportColumn('fees', t('الرسوم', 'Fees'), type: AppColType.money, total: AppTotal.sum),
        _status('published', t('النشر', 'Published'), {'yes': t('منشور', 'Published'), 'no': t('مسودة', 'Draft')}),
        _status('members_only', t('للأعضاء فقط', 'Members only'), {'yes': t('نعم', 'Yes'), 'no': t('لا', 'No')}),
      ],
      rows: [
        for (final r in rows)
          {
            ...r,
            'name': (AppConfig.lang == 'ar' ? r['name_ar'] : r['name_en']) ?? r['name_ar'] ?? r['name_en'],
            'teacher': asMap(r['teacher'])['name'],
            'scope': r['scope'] == 'department' ? t('مقرر قسم', 'Department course') : t('مقرر عام', 'General course'),
            'published': asBool(r['is_published']) ? 'yes' : 'no',
            'members_only': asBool(r['members_only']) ? 'yes' : 'no',
          },
      ],
    );
