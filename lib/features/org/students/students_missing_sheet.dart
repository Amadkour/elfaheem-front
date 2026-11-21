// lib/features/org/students/students_missing_sheet.dart — "What is missing?" for one student (contract §4.4, §5).
//
//   showMissingDataSheet(context, orgId, uid, name:)   loads GET …/missing and shows the sheet
//   MissingDataView(data:, loading:, error:, …)        plain values: photos · documents · fields, each item with
//                                                      WHY it is required, its due date and (documents) its state
//
// Read only in phase 1: the one action is "Open the admission file" (the existing review page, OnbReviewPage). In-place
// upload / edit / waive arrive in phase 3 (F2 owns this file then).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../onboarding/onboarding_review.dart' show OnbReviewPage;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show orgErrorText;
import 'students_api.dart';
import 'students_models.dart';

/// Opens the sheet for student [uid]; [name] is the subtitle. [api] is for tests.
Future<void> showMissingDataSheet(BuildContext context, int orgId, int uid, {String? name, StudentsApi? api}) {
  OrgSession? session;
  try {
    session = context.read<OrgSession>();
  } catch (_) {}
  return showAppSheet<void>(
    context,
    (ctx) => _MissingSheet(orgId: orgId, uid: uid, name: name, api: api ?? StudentsApi(orgId), session: session),
  );
}

class _MissingSheet extends StatefulWidget {
  const _MissingSheet({required this.orgId, required this.uid, required this.api, this.name, this.session});
  final int orgId, uid;
  final String? name;
  final StudentsApi api;
  final OrgSession? session;

  @override
  State<_MissingSheet> createState() => _MissingSheetState();
}

class _MissingSheetState extends State<_MissingSheet> {
  StudentMissing? _data;
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
    final r = await widget.api.missing(widget.uid);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _data = StudentMissing.fromJson(r.map);
      } else {
        _error = orgErrorText(r.error!);
      }
    });
  }

  void _openFile(int caseId) {
    final nav = Navigator.of(context);
    final s = widget.session;
    final page = OnbReviewPage(orgId: widget.orgId, caseId: caseId, title: widget.name ?? '');
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => s == null ? page : ChangeNotifierProvider<OrgSession>.value(value: s, child: page)));
  }

  @override
  Widget build(BuildContext context) {
    final caseId = _data?.caseId;
    return AppSheetContent(
      title: t('البيانات الناقصة', 'Missing data'),
      subtitle: widget.name,
      icon: Icons.assignment_late_outlined,
      tone: AppTone.warning,
      children: [
        MissingDataView(
          data: _data,
          loading: _loading,
          error: _error,
          onRetry: _load,
          onOpenFile: caseId == null ? null : () => _openFile(caseId),
        ),
      ],
    );
  }
}

/// The sheet's body over plain values (the layout harness pumps it).
class MissingDataView extends StatelessWidget {
  const MissingDataView({super.key, this.data, this.loading = false, this.error, this.onRetry, this.onOpenFile});
  final StudentMissing? data;
  final bool loading;

  /// The text to show (already `orgErrorText`); null = no error.
  final String? error;
  final VoidCallback? onRetry;

  /// "Open the admission file"; null = no button.
  final VoidCallback? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (loading && d == null) return const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero);
    if (error != null && d == null) return AppErrorState(message: error, onRetry: onRetry, compact: true);
    if (d == null || d.caseId == null) {
      return AppEmpty(
        icon: Icons.folder_off_outlined,
        title: t('لا يوجد ملف التحاق لهذا الطالب', 'This student has no admission file'),
        message: t('لا يُطلب منه شيء حالياً.', 'Nothing is asked of them right now.'),
      );
    }
    if (d.isEmpty) {
      return AppEmpty(
        icon: Icons.task_alt_rounded,
        title: t('لا ينقص شيء', 'Nothing is missing'),
        message: t('الملف مكتمل.', 'The file is complete.'),
        actionLabel: onOpenFile == null ? null : t('فتح ملف الالتحاق', 'Open the admission file'),
        onAction: onOpenFile,
      );
    }
    final due = d.dueAt;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Intro(total: d.total, due: due),
      if (d.photos.isNotEmpty) _Group(title: t('الصور', 'Photos'), icon: Icons.photo_camera_outlined, items: d.photos),
      if (d.documents.isNotEmpty) _Group(title: t('المستندات', 'Documents'), icon: Icons.description_outlined, items: d.documents, showStatus: true),
      if (d.fields.isNotEmpty) _Group(title: t('البيانات', 'Details'), icon: Icons.edit_note_rounded, items: d.fields),
      if (onOpenFile != null) ...[
        AppSpace.gapMd,
        AppButton.primary(
          key: const ValueKey('students.missing.open'),
          label: t('فتح ملف الالتحاق', 'Open the admission file'),
          icon: Icons.folder_open_rounded,
          onPressed: onOpenFile,
        ),
      ],
    ]);
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.total, this.due});
  final int total;
  final DateTime? due;

  @override
  Widget build(BuildContext context) {
    final n = countText(total, ar1: 'ينقص بند واحد', ar2: 'ينقص بندان', arFew: 'تنقص {n} بنود', arMany: 'ينقص {n} بندًا',
        en1: '1 item is missing', en: '{n} items are missing');
    final d = due;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Text(
        d == null ? n : '$n · ${t('آخر موعد', 'due by')} ${AppTime.date(d)}',
        style: AppType.body(context),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.icon, required this.items, this.showStatus = false});
  final String title;
  final IconData icon;
  final List<MissingItem> items;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: AppIconSize.sm, color: c.textMedium),
          AppSpace.gapXs,
          Expanded(child: Semantics(header: true, child: Text('$title (${items.length})', style: AppType.label(context)))),
        ]),
        AppSpace.gapXs,
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: _ItemCard(item: it, showStatus: showStatus),
          ),
      ]),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, this.showStatus = false});
  final MissingItem item;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final why = item.why;
    final due = item.dueAt;
    return AppCard(
      key: ValueKey('students.missing.${item.key}'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.label, style: AppType.bodyStrong(context)),
        if (why.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs / 2),
          Text(why, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ],
        if (showStatus || due != null) ...[
          AppSpace.gapXs,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
            if (showStatus)
              AppStatusBadge(
                label: missingStatusText(item.status),
                tone: item.status == 'rejected' ? AppTone.danger : (item.status == 'deferred' ? AppTone.info : AppTone.warning),
                dense: true,
              ),
            if (due != null) AppStatusBadge(label: '${t('حتى', 'Due')} ${AppTime.date(due)}', icon: Icons.event_outlined, dense: true),
          ]),
        ],
      ]),
    );
  }
}
