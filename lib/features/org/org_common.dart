// lib/features/org/org_common.dart — small shared pieces of the organization UI.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_providers.dart';

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
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok) toast(t('تعذّر فتح الملف', 'Could not open the file'), error: true);
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
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(t('نتيجة الاستيراد', 'Import result')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          InfoChip(Icons.add_circle_rounded, '${t('جديد', 'New')} ${r['created']}', c.success),
          InfoChip(Icons.link_rounded, '${t('مرتبط', 'Linked')} ${r['linked']}', c.primary),
          if (asInt(r['skipped']) > 0) InfoChip(Icons.skip_next_rounded, '${t('تخطي', 'Skipped')} ${r['skipped']}', c.textMedium),
          if (errors.isNotEmpty) InfoChip(Icons.error_rounded, '${t('أخطاء', 'Errors')} ${errors.length}', c.danger),
        ]),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(t('صفوف بها أخطاء', 'Rows with problems'), style: c.h2.copyWith(fontSize: 14)),
          const SizedBox(height: 6),
          for (final e in errors.take(40))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${t('صف', 'Row')} ${e['row']}: ${e['error']}',
                  style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.danger)),
            ),
        ],
        if (creds.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(t('بيانات الدخول للحسابات الجديدة (تظهر مرة واحدة)', 'Login details of new accounts (shown once)'),
              style: c.h2.copyWith(fontSize: 14)),
          const SizedBox(height: 6),
          for (final u in creds.take(60))
            SelectableText('${u['email']}   ·   ${u['password']}',
                textDirection: TextDirection.ltr, style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.textDark)),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [base, Color.alphaBlend(Colors.black.withValues(alpha: 0.28), base)],
        ),
        boxShadow: [BoxShadow(color: base.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: logo.isNotEmpty
              ? Image.network(logo, fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallbackIcon())
              : _fallbackIcon(),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(OrgSession.nameOf(org),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'bahji', fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(subtitle!,
                    style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: Colors.white.withValues(alpha: 0.86))),
              ),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }

  Widget _fallbackIcon() => Icon(orgTypeIcons[org['type']] ?? Icons.domain_rounded, color: Colors.white, size: 28);
}
