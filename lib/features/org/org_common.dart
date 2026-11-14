// lib/features/org/org_common.dart — small shared pieces of the organization UI.
library;

import 'package:flutter_education_app/design/app_mesh.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/core/share/external_link.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_providers.dart';
import 'org_ui.dart' show orgFileUrl;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

/// Warm, human gradient from the organization's own colour (falls back to the app primary).
Color orgColor(BuildContext context, Map<String, dynamic>? org) {
  final hex = (org?['color'] ?? '').toString();
  if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }
  return context.colors.primary;
}

const orgTypeIcons = <String, IconData>{
  'university': Icons.account_balance_rounded,
  'faculty': Icons.school_rounded,
  'department': Icons.apartment_rounded,
  'institute': Icons.corporate_fare_rounded,
  'school': Icons.cast_for_education_rounded,
  'center': Icons.hub_rounded,
  'other': Icons.domain_rounded,
};

Map<String, String> orgTypeLabels() => {
      'university': t('جامعة', 'University'),
      'faculty': t('كلية', 'Faculty'),
      'department': t('قسم', 'Department'),
      'institute': t('معهد', 'Institute'),
      'school': t('مدرسة', 'School'),
      'center': t('مركز', 'Center'),
      'other': t('أخرى', 'Other'),
    };

Map<String, String> joinModeLabels() => {
      'open': t('مفتوح للجميع', 'Open to everyone'),
      'approval': t('بموافقة المدير', 'Needs approval'),
      'code': t('بكود فقط', 'Code only'),
      'code_req': t('كود + طلب وموافقة', 'Code + request'),
      'closed': t('مغلق', 'Closed'),
    };

Map<String, String> dayLabels() => {
      'saturday': t('السبت', 'Saturday'),
      'sunday': t('الأحد', 'Sunday'),
      'monday': t('الاثنين', 'Monday'),
      'tuesday': t('الثلاثاء', 'Tuesday'),
      'wednesday': t('الأربعاء', 'Wednesday'),
      'thursday': t('الخميس', 'Thursday'),
      'friday': t('الجمعة', 'Friday'),
    };

Future<void> openFileUrl(String? url) async {
  if (url == null || url.isEmpty) return;
  await openExternalLink(orgFileUrl(url), failText: t('تعذّر فتح الملف', 'Could not open the file'));
}

/// Downloads an Excel template / export through the backend (it returns a file URL) and opens it.
Future<void> downloadExcel(BuildContext context, String path, [Map<String, dynamic>? query]) async {
  final r = await context.read<OrgSession>().file(path, query);
  await openFileUrl(r?['url']?.toString());
}

/// Pick an .xlsx, upload it, show the result (created / linked / row errors / generated passwords).
Future<bool> importExcelFlow(BuildContext context, String kind) async {
  final session = context.read<OrgSession>();
  final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx']);
  if (f == null) return false;
  final bytes = kIsWeb ? await f.readAsBytes() : null;
  if (kIsWeb ? bytes == null : f.path == null) {
    toast(t('تعذّرت قراءة الملف', 'Could not read the file'), error: true);
    return false;
  }
  final res = await session.importExcel(kind, f.name, filePath: kIsWeb ? null : f.path, bytes: bytes);
  if (res == null || !context.mounted) return false;
  await showAdminSheet<void>(context, (_) => _ImportResultSheet(res));
  return true;
}

class _ImportResultSheet extends StatelessWidget {
  const _ImportResultSheet(this.r);
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final errors = asMapList(r['errors']);
    final creds = asMapList(r['credentials']);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(tone: AppTone.info, icon: Icons.file_download_outlined, t('نتيجة الاستيراد', 'Import result')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          InfoChip(Icons.add_circle_rounded, '${t('جديد', 'New')} ${r['created']}', c.success),
          InfoChip(Icons.link_rounded, '${t('مرتبط', 'Linked')} ${r['linked']}', c.primary),
          if (asInt(r['invited']) > 0) InfoChip(Icons.mark_email_unread_rounded, '${t('دعوات مرسلة', 'Invited')} ${r['invited']}', c.warning),
          if (asInt(r['skipped']) > 0) InfoChip(Icons.skip_next_rounded, '${t('تخطي', 'Skipped')} ${r['skipped']}', c.textMedium),
          if (errors.isNotEmpty) InfoChip(Icons.error_rounded, '${t('أخطاء', 'Errors')} ${errors.length}', c.danger),
        ]),
        if (asInt(r['invited']) > 0) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('الحسابات الموجودة أصلاً تلقّت دعوة — تنضم إلى المؤسسة بعد قبولها.', 'Accounts that already exist received an invitation — they join once they accept.'),
              style: AppType.label(context).copyWith(color: c.textMedium)),
        ],
        if (errors.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Text(t('صفوف بها أخطاء', 'Rows with problems'), style: c.h2.copyWith(fontSize: 14)),
          const SizedBox(height: AppSpace.xs),
          for (final e in errors.take(40))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs / 2),
              child: Text('${t('صف', 'Row')} ${e['row']}: ${e['error']}',
                  style: AppType.label(context).copyWith(color: c.danger)),
            ),
        ],
        if (creds.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Text(t('بيانات الدخول للحسابات الجديدة (تظهر مرة واحدة)', 'Login details of new accounts (shown once)'),
              style: c.h2.copyWith(fontSize: 14)),
          const SizedBox(height: AppSpace.xs),
          for (final u in creds.take(60))
            SelectableText('${u['email']}   ·   ${u['password']}',
                textDirection: TextDirection.ltr, style: AppType.label(context).copyWith(color: c.textDark)),
        ],
      ]),
    );
  }
}

/// Hides [child] when the admin assistant has no right for [module]/[action].
class OrgGate extends StatelessWidget {
  const OrgGate(this.module, {super.key, this.action = 'view', required this.child, this.fallback});
  final String module, action;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final ok = context.watch<OrgSession>().can(module, action);
    return ok ? child : (fallback ?? const SizedBox.shrink());
  }
}

/// Friendly hero used on top of every org tab: logo / icon, name, breadcrumb-ish subtitle, trailing action.
class OrgHero extends StatelessWidget {
  const OrgHero({super.key, required this.org, this.subtitle, this.trailing});
  final Map<String, dynamic> org;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final base = orgColor(context, org);
    final logo = (org['logo_url'] ?? '').toString();
    return Container(margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.sm), decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.block), boxShadow: [BoxShadow(color: base.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 8))]), child: AppMeshSurface(color: base, radius: BorderRadius.circular(AppRadius.block), child: Padding(padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.sm, AppSpace.md), child: Row(children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(color: context.colors.onHero.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppRadius.card)),
          clipBehavior: Clip.antiAlias,
          child: logo.isNotEmpty
              ? Image.network(logo, fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallbackIcon(context))
              : _fallbackIcon(context),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(OrgSession.nameOf(org),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.section(context).copyWith(color: context.colors.onHero)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Text(subtitle!,
                    style: AppType.label(context).copyWith(color: context.colors.onHero.withValues(alpha: 0.86))),
              ),
          ]),
        ),
        if (trailing != null) trailing!,
      ]))));
  }

  Widget _fallbackIcon(BuildContext context) => Icon(orgTypeIcons[org['type']] ?? Icons.domain_rounded, color: context.colors.onHero, size: AppIconSize.xl);
}


/// Excel · PDF · Word — one sheet for every organization export.
Future<void> exportData(BuildContext context, String path, [Map<String, dynamic>? query]) async {
  final fmt = await showAdminSheet<String>(context, (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(tone: AppTone.info, icon: Icons.ios_share_rounded, t('تصدير بصيغة', 'Export as')),
          for (final (f, label, icon) in [
            ('xlsx', 'Excel', Icons.table_chart_rounded),
            ('pdf', 'PDF', Icons.picture_as_pdf_rounded),
            ('docx', 'Word', Icons.description_rounded),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, f),
            ),
        ]),
      ));
  if (fmt == null || !context.mounted) return;
  await downloadExcel(context, path, {...?query, 'format': fmt});
}
