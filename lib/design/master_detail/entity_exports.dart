// lib/design/master_detail/entity_exports.dart — the exports of the shared row kinds (D-290, phase 8): one per row
// type, so every list of that type exports the same columns, with the same bilingual headers.
//
//   EntityListConfig(…, export: entityPersonExport())
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';

import '../app_table_export.dart';
import 'entity_list_tools.dart';
import 'entity_specs.dart' show mdPaymentStatus;

AppExportColumn _col(String id, String key, {AppColType type = AppColType.text, bool locked = false}) =>
    AppExportColumn(id, key.tr, type: type, locked: locked);

String? _course(EntityCourse? c) => c?.ref.name;

/// Students (or teachers) with their courses, progress and activity.
EntityListExport<PersonRow> entityPersonExport() => EntityListExport<PersonRow>(
      columns: [
        _col('name', 'md_p8_col_name', locked: true),
        _col('username', 'md_p8_col_username'),
        _col('courses', 'md_stat_courses', type: AppColType.integer),
        _col('progress', 'md_stat_avg_progress', type: AppColType.percent),
        _col('last_activity', 'md_stat_last_activity', type: AppColType.dateTime),
        _col('attention', 'md_p7_needs_attention'),
      ],
      row: (r) => {
        'name': r.person.name,
        'username': r.username == null ? null : '@${r.username}',
        'courses': r.courses,
        'progress': r.avgProgress,
        'last_activity': r.lastActivityAt,
        'attention': r.attention ? 'md_p8_yes'.tr : 'md_p8_no'.tr,
      },
    );

/// Grades and submissions.
EntityListExport<GradeRow> entityGradeExport() => EntityListExport<GradeRow>(
      columns: [
        _col('title', 'md_p8_col_title', locked: true),
        _col('student', 'md_kind_student'),
        _col('course', 'md_kind_course'),
        _col('score', 'md_p7_score', type: AppColType.number),
        _col('max', 'md_p8_col_max', type: AppColType.number),
        _col('percent', 'md_p8_col_percent', type: AppColType.percent),
        _col('at', 'md_p7_date', type: AppColType.dateTime),
      ],
      row: (r) => {
        'title': r.title,
        'student': r.student?.name,
        'course': _course(r.course),
        // a held result stays held in the file too
        'score': r.held ? null : r.score,
        'max': r.maxScore,
        'percent': r.held ? null : r.percentage,
        'at': r.at,
      },
    );

/// Course reviews.
EntityListExport<ReviewRow> entityReviewExport() => EntityListExport<ReviewRow>(
      columns: [
        _col('student', 'md_kind_student', locked: true),
        _col('course', 'md_kind_course'),
        _col('stars', 'md_p7_rating', type: AppColType.integer),
        _col('review', 'md_p7_review'),
        _col('at', 'md_p7_date', type: AppColType.dateTime),
      ],
      row: (r) => {
        'student': r.student?.name,
        'course': _course(r.course),
        'stars': r.value,
        'review': r.review,
        'at': r.at,
      },
    );

/// A student's payments (amounts with their currency: a list may hold several).
EntityListExport<PaymentRow> entityPaymentExport() => EntityListExport<PaymentRow>(
      columns: [
        _col('course', 'md_kind_course', locked: true),
        _col('amount', 'md_p8_col_amount', type: AppColType.number),
        _col('currency', 'md_p8_col_currency'),
        _col('status', 'md_p8_col_status'),
        _col('method', 'md_p8_col_method'),
        _col('paid_at', 'md_p8_col_paid_at', type: AppColType.dateTime),
      ],
      row: (r) => {
        'course': _course(r.course),
        'amount': r.amount,
        'currency': r.currency,
        'status': mdPaymentStatus(r.status),
        'method': r.method,
        'paid_at': r.paidAt ?? r.createdAt,
      },
    );
