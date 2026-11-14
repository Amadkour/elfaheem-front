// The scan issues of an exam (or one batch): `GET /api/v1/exam/exams/{id}/omr/issues?batch_id=` →
// `{items: [{code, page_id, batch_id, label, message, message_en, review_item_id?}], counts}`. One list over the
// rejected pages, duplicates and the identifier / form review items; the card groups it by code with a count and an
// action per item (open the review item, or replace the page). Plain values: the screens hand it the parsed list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMapList, t;

/// The codes the card knows, in the order they are listed. An unknown code is listed last under a generic title.
const List<String> kOmrIssueCodes = ['unreadable_page', 'unreadable_qr', 'duplicate_scan', 'unknown_student', 'student_twice', 'form_unknown'];

/// The group's title (Arabic / English).
String omrIssueTitle(String code) => switch (code) {
      'unreadable_page' => t('صفحة غير مقروءة', 'Unreadable page'),
      'unreadable_qr' => t('رمز QR غير مقروء', 'Unreadable QR code'),
      'duplicate_scan' => t('مسح مكرر', 'Duplicate scan'),
      'unknown_student' => t('طالب غير معروف', 'Unknown student'),
      'student_twice' => t('طالب ممسوح مرتين', 'Student scanned twice'),
      'form_unknown' => t('نموذج غير مؤكد', 'Form not confirmed'),
      _ => t('مشكلة أخرى', 'Other issue'),
    };

/// One plain sentence on what to do about the group.
String omrIssueHint(String code) => switch (code) {
      'unreadable_page' => t('صوّر الورقة مرة أخرى بإضاءة أفضل', 'Take the photo again in better light'),
      'unreadable_qr' => t('صوّر الورقة مرة أخرى مع إظهار رمز QR كاملًا', 'Take the photo again with the whole QR code in view'),
      'duplicate_scan' => t('هذه الورقة ممسوحة من قبل', 'This paper was scanned before'),
      'unknown_student' => t('اختر الطالب صاحب الورقة', 'Choose the student this paper belongs to'),
      'student_twice' => t('لهذا الطالب أكثر من ورقة — اختر الصحيحة', 'This student has more than one paper — keep the right one'),
      'form_unknown' => t('أكّد نموذج الورقة', 'Confirm which form this paper is'),
      _ => '',
    };

IconData omrIssueIcon(String code) => switch (code) {
      'unreadable_page' => Icons.image_not_supported_outlined,
      'unreadable_qr' => Icons.qr_code_2_rounded,
      'duplicate_scan' => Icons.content_copy_rounded,
      'unknown_student' => Icons.person_off_outlined,
      'student_twice' => Icons.people_outline_rounded,
      'form_unknown' => Icons.help_outline_rounded,
      _ => Icons.error_outline_rounded,
    };

class OmrScanIssue {
  const OmrScanIssue({required this.code, this.pageId, this.batchId, this.label = '', this.message = '', this.messageEn = '', this.reviewItemId});
  final String code;
  final int? pageId;
  final int? batchId;
  final String label;
  final String message;
  final String messageEn;
  final int? reviewItemId;

  factory OmrScanIssue.fromJson(Map<String, dynamic> j) => OmrScanIssue(
        code: '${j['code'] ?? ''}',
        pageId: j['page_id'] == null ? null : asInt(j['page_id']),
        batchId: j['batch_id'] == null ? null : asInt(j['batch_id']),
        label: '${j['label'] ?? ''}',
        message: '${j['message'] ?? ''}',
        messageEn: '${j['message_en'] ?? ''}',
        reviewItemId: j['review_item_id'] == null ? null : asInt(j['review_item_id']),
      );

  /// The server's sentence in the app language (the other one when only one came).
  String get text => AppConfig.lang == 'ar' ? (message.isEmpty ? messageEn : message) : (messageEn.isEmpty ? message : messageEn);

  /// A page that can be photographed again: the unreadable ones.
  bool get canReplace => pageId != null && (code == 'unreadable_page' || code == 'unreadable_qr');
}

class OmrScanIssues {
  const OmrScanIssues(this.items);
  final List<OmrScanIssue> items;
  static const empty = OmrScanIssues([]);

  factory OmrScanIssues.fromJson(Map<String, dynamic> j) => OmrScanIssues([for (final m in asMapList(j['items'])) OmrScanIssue.fromJson(m)]);

  bool get isEmpty => items.isEmpty;

  /// The items per code, in [kOmrIssueCodes] order, unknown codes last. Counts come from the list itself.
  List<(String, List<OmrScanIssue>)> get groups {
    final by = <String, List<OmrScanIssue>>{};
    for (final i in items) {
      (by[i.code] ??= []).add(i);
    }
    final codes = [...kOmrIssueCodes.where(by.containsKey), ...by.keys.where((c) => !kOmrIssueCodes.contains(c))];
    return [for (final c in codes) (c, by[c]!)];
  }
}

/// The "Scan issues" card. [onOpen]: the review item of an issue; [onReplace]: take the page again.
class OmrIssuesCard extends StatelessWidget {
  const OmrIssuesCard({super.key, required this.issues, this.onOpen, this.onReplace});
  final OmrScanIssues issues;
  final void Function(OmrScanIssue issue)? onOpen;
  final void Function(OmrScanIssue issue)? onReplace;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final th = Theme.of(context).textTheme;
    return AppCard(
      key: const ValueKey('omr.issues'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.report_problem_outlined, color: c.danger, size: 20),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(t('مشكلات المسح', 'Scan issues'), style: th.titleMedium)),
          Text('${issues.items.length}', style: th.titleMedium),
        ]),
        for (final (code, items) in issues.groups) ...[
          const SizedBox(height: AppSpace.md),
          Row(children: [
            Icon(omrIssueIcon(code), size: 18),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text('${omrIssueTitle(code)} (${items.length})', key: ValueKey('omr.issues.$code'), style: th.titleSmall)),
          ]),
          if (omrIssueHint(code).isNotEmpty) Padding(padding: const EdgeInsetsDirectional.only(start: 26), child: Text(omrIssueHint(code), style: th.bodySmall)),
          for (final i in items) _IssueRow(issue: i, onOpen: onOpen, onReplace: onReplace),
        ],
      ]),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, this.onOpen, this.onReplace});
  final OmrScanIssue issue;
  final void Function(OmrScanIssue)? onOpen;
  final void Function(OmrScanIssue)? onReplace;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final canOpen = issue.reviewItemId != null && onOpen != null;
    final canReplace = !canOpen && issue.canReplace && onReplace != null;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 26, top: AppSpace.xs),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.sm, children: [
        if (issue.label.isNotEmpty) Text(issue.label, style: th.labelLarge),
        if (issue.text.isNotEmpty) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(issue.text, style: th.bodySmall)),
        if (canOpen)
          TextButton(key: ValueKey('omr.issue.open.${issue.reviewItemId}'), onPressed: () => onOpen!(issue), child: Text(t('فتح المراجعة', 'Open review'))),
        if (canReplace)
          TextButton(key: ValueKey('omr.issue.replace.${issue.pageId}'), onPressed: () => onReplace!(issue), child: Text(t('استبدال الصفحة', 'Replace page'))),
      ]),
    );
  }
}
