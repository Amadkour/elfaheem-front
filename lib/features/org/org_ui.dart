// lib/features/org/org_ui.dart
//
// The organization UI kit — ONE place for the look of every organization screen (dashboard, departments,
// services, roles, member space, platform review). Built on top of the admin kit (admin_common / admin_list /
// admin_premium_widgets) and the live theme (context.colors), so it follows the app theme and dark mode.
//
//   colours & labels   hexColor · statusColor/statusLabel · deptIcon · relTime
//   layout             OrgSectionTitle · OrgStatTile · OrgActionCard · OrgAsync · OrgEmpty · OrgPill · OrgInfoRow
//   inputs             OrgAudiencePicker · OrgPermissionMatrix · OrgSwitchRow
//   files              orgPickAndUpload
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appInk;
import 'dart:typed_data';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;

// ═════════════════════════════════════════════════════════════════════════════
//  Colours, icons, labels
// ═════════════════════════════════════════════════════════════════════════════

Color hexColor(dynamic hex, Color fallback) {
  final h = '${hex ?? ''}';
  if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(h)) return Color(int.parse('FF${h.substring(1)}', radix: 16));
  return fallback;
}

/// Department icons arrive as material icon names from the server presets.
const _deptIcons = <String, IconData>{
  'school': Icons.school_rounded,
  'psychology': Icons.psychology_rounded,
  'fact_check': Icons.fact_check_rounded,
  'badge': Icons.badge_rounded,
  'menu_book': Icons.menu_book_rounded,
  'assignment': Icons.assignment_rounded,
  'workspace_premium': Icons.workspace_premium_rounded,
  'groups': Icons.groups_rounded,
  'work': Icons.work_rounded,
  'account_balance_wallet': Icons.account_balance_wallet_rounded,
  'verified': Icons.verified_rounded,
  'computer': Icons.computer_rounded,
  'local_library': Icons.local_library_rounded,
  'celebration': Icons.celebration_rounded,
  'history_edu': Icons.history_edu_rounded,
  'apartment': Icons.apartment_rounded,
};

IconData deptIcon(dynamic name) => _deptIcons['${name ?? ''}'] ?? Icons.apartment_rounded;

const deptIconChoices = _deptIcons;

Color statusColor(BuildContext context, String? s) {
  final c = context.colors;
  return switch (s) {
    'approved' || 'active' || 'published' || 'open' || 'resolved' => c.success,
    'pending' || 'submitted' || 'in_review' || 'waiting' || 'draft' => c.warning,
    'rejected' || 'suspended' || 'closed' || 'archived' => c.danger,
    'in_progress' => c.primary,
    _ => c.textMedium,
  };
}

String statusLabel(String? s) => switch (s) {
      'approved' => t('معتمدة', 'Approved'),
      'pending' => t('قيد المراجعة', 'Under review'),
      'rejected' => t('تحتاج تعديل', 'Needs changes'),
      'suspended' => t('موقوفة', 'Suspended'),
      'draft' => t('مسودة', 'Draft'),
      'published' => t('منشور', 'Published'),
      'archived' => t('مؤرشف', 'Archived'),
      'open' => t('مفتوح', 'Open'),
      'closed' => t('مغلق', 'Closed'),
      'submitted' => t('مُرسل', 'Submitted'),
      'in_review' => t('قيد المراجعة', 'In review'),
      'in_progress' => t('جارٍ العمل', 'In progress'),
      'waiting' => t('بانتظار ردك', 'Waiting for you'),
      'resolved' => t('تم الحل', 'Resolved'),
      'active' => t('نشط', 'Active'),
      _ => s ?? '',
    };

String priorityLabel(String? p) => switch (p) {
      'low' => t('منخفضة', 'Low'),
      'high' => t('عالية', 'High'),
      'urgent' => t('عاجلة', 'Urgent'),
      _ => t('متوسطة', 'Medium'),
    };

Color priorityColor(BuildContext context, String? p) => switch (p) {
      'urgent' => context.colors.danger,
      'high' => context.colors.warning,
      'low' => context.colors.textLight,
      _ => context.colors.primary,
    };

Map<String, String> memberRoleLabels() => {
      'student': t('الطلاب', 'Students'),
      'teacher': t('هيئة التدريس', 'Teaching staff'),
      'teacher_assistant': t('الهيئة المعاونة', 'Teaching assistants'),
      'admin_assistant': t('الإداريون', 'Admin staff'),
    };

/// "منذ 5 دقائق" / "5 min ago" — humans read relative time faster than dates.
String relTime(dynamic iso) {
  final d = DateTime.tryParse('${iso ?? ''}');
  if (d == null) return '';
  final diff = DateTime.now().toUtc().difference(d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second));
  if (diff.inMinutes < 1) return t('الآن', 'just now');
  if (diff.inMinutes < 60) return t('منذ ${diff.inMinutes} د', '${diff.inMinutes} min ago');
  if (diff.inHours < 24) return t('منذ ${diff.inHours} س', '${diff.inHours} h ago');
  if (diff.inDays < 7) return t('منذ ${diff.inDays} يوم', '${diff.inDays} d ago');
  return shortDate('$iso');
}

String orgNameOf(Map<String, dynamic>? o) {
  if (o == null) return '';
  final ar = '${o['name_ar'] ?? ''}', en = '${o['name_en'] ?? ''}';
  return t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar);
}

TextStyle orgText(BuildContext context, {double size = 13.5, FontWeight w = FontWeight.w500, Color? color}) =>
    TextStyle(fontFamily: 'tajawal', fontSize: size, fontWeight: w, color: color ?? context.colors.textDark, height: 1.45);

// ═════════════════════════════════════════════════════════════════════════════
//  Layout pieces
// ═════════════════════════════════════════════════════════════════════════════

class OrgSectionTitle extends StatelessWidget {
  const OrgSectionTitle(this.title, {super.key, this.subtitle, this.action, this.padding});
  final String title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding ?? const EdgeInsetsDirectional.fromSTEB(16, 18, 10, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: orgText(context, size: 16, w: FontWeight.w800)),
            if (subtitle != null) Text(subtitle!, style: orgText(context, size: 12, color: c.textMedium)),
          ]),
        ),
        ?action,
      ]),
    );
  }
}

/// Small counter tile (two per row on phones, a strip on wide screens).
class OrgStatTile extends StatelessWidget {
  const OrgStatTile({super.key, required this.icon, required this.label, required this.value, this.color, this.onTap});
  final IconData icon;
  final String label;
  final dynamic value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    return Material(
      color: c.cardBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: col.withValues(alpha: 0.22)),
          ),
          child: Row(children: [
            IconBadge(icon, col, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${value ?? 0}',
                    style: TextStyle(fontFamily: 'bahji', fontSize: 21, fontWeight: FontWeight.w800, color: c.textDark)),
                // two lines: one cut "Live even…" / "مهام فش…" on every 3-up strip (docs/polish/visual-review.md)
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: orgText(context, size: 11.5, color: c.textMedium).copyWith(height: 1.2)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Responsive grid: 2 columns on phones, more on wide screens.
class OrgGrid extends StatelessWidget {
  const OrgGrid({super.key, required this.children, this.minTile = 170, this.spacing = 12, this.padding});
  final List<Widget> children;
  final double minTile, spacing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(builder: (context, box) {
        final cols = (box.maxWidth / minTile).floor().clamp(1, 6);
        final w = (box.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(spacing: spacing, runSpacing: spacing, children: [
          for (final ch in children) SizedBox(width: w, child: ch),
        ]);
      }),
    );
  }
}

/// A premium tappable card: coloured icon, title, one human sentence, optional badge.
class OrgActionCard extends StatelessWidget {
  const OrgActionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    this.badge = 0,
    this.onTap,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final int badge;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    return Material(
      color: c.cardBg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.divider),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [col.withValues(alpha: 0.10), c.cardBg],
            ),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              IconBadge(icon, col, size: 44),
              if (badge > 0)
                PositionedDirectional(
                  top: -6,
                  end: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(10)),
                    child: Text(badge > 99 ? '99+' : '$badge',
                        style: TextStyle(color: c.onHero, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 14.5, w: FontWeight.w800)),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: orgText(context, size: 12, color: c.textMedium)),
              ]),
            ),
            if (trailing != null) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: trailing) // a long pill ellipsizes
            else Icon(Icons.chevron_right_rounded, color: c.textLight),
          ]),
        ),
      ),
    );
  }
}

class OrgPill extends StatelessWidget {
  const OrgPill(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final col = color ?? context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // the tint keeps the raw tone; the label is the readable ink of it (warning text on its own tint was 2:1)
        if (icon != null) ...[Icon(icon, size: 13, color: appInk(context, col)), const SizedBox(width: 4)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, fontWeight: FontWeight.w700, color: appInk(context, col)))),
      ]),
    );
  }
}

class OrgInfoRow extends StatelessWidget {
  const OrgInfoRow(this.icon, this.text, {super.key, this.ltr = false});
  final IconData icon;
  final String? text;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    if ((text ?? '').trim().isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 16, color: c.textLight),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text!, textDirection: ltr ? TextDirection.ltr : null,
              textAlign: ltr ? TextAlign.start : null, style: orgText(context, size: 12.5, color: c.textMedium)),
        ),
      ]),
    );
  }
}

/// Friendly empty state with an optional call to action.
class OrgEmpty extends StatelessWidget {
  const OrgEmpty({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary.withValues(alpha: 0.10)),
            child: Icon(icon, size: 42, color: c.primary),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: orgText(context, size: 15.5, w: FontWeight.w800)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: orgText(context, size: 12.5, color: c.textMedium)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: c.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel!, style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Loading / error / content in one place, so every screen behaves the same way.
class OrgAsync extends StatelessWidget {
  const OrgAsync({super.key, required this.loading, required this.failed, required this.onRetry, required this.child});
  final bool loading, failed;
  final VoidCallback onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppListSkeleton(items: 3);
    if (failed) {
      return SizedBox(height: 280, child: ErrorRetry(message: t('تعذّر التحميل، تحقق من الاتصال', 'Could not load — check your connection'), onRetry: onRetry));
    }
    return child;
  }
}

class OrgSwitchRow extends StatelessWidget {
  const OrgSwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSwitchTile(title: title, subtitle: subtitle, value: value, onChanged: onChanged);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Audience picker (who sees an announcement / form / file)
// ═════════════════════════════════════════════════════════════════════════════

class OrgAudiencePicker extends StatelessWidget {
  const OrgAudiencePicker({super.key, required this.value, required this.onChanged});
  final Map<String, dynamic> value; // {"roles": [...], "sub_orgs": bool}
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final roles = {...((value['roles'] as List?) ?? const []).map((e) => '$e')};
    final sub = value['sub_orgs'] != false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('مَن يرى هذا؟', 'Who sees this?'), style: orgText(context, size: 12.5, color: c.textLight)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: [
        FilterChip(
          label: Text(t('الجميع', 'Everyone'), style: const TextStyle(fontFamily: 'tajawal')),
          selected: roles.isEmpty,
          onSelected: (_) => onChanged({'roles': <String>[], 'sub_orgs': sub}),
        ),
        for (final e in memberRoleLabels().entries)
          FilterChip(
            label: Text(e.value, style: const TextStyle(fontFamily: 'tajawal')),
            selected: roles.contains(e.key),
            onSelected: (on) {
              final n = {...roles};
              on ? n.add(e.key) : n.remove(e.key);
              onChanged({'roles': n.toList(), 'sub_orgs': sub});
            },
          ),
      ]),
      OrgSwitchRow(
        title: t('يشمل المؤسسات الفرعية', 'Include sub-organizations'),
        subtitle: t('مثلاً: إعلان الجامعة يظهر لطلاب كل الكليات', "e.g. a university notice reaches every faculty's students"),
        value: sub,
        onChanged: (v) => onChanged({'roles': roles.toList(), 'sub_orgs': v}),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Permission matrix (modules × actions) — drawn from GET …/access/catalog
// ═════════════════════════════════════════════════════════════════════════════

class OrgPermissionMatrix extends StatelessWidget {
  const OrgPermissionMatrix({
    super.key,
    required this.catalog,
    required this.value,
    required this.onChanged,
    this.deptOnly = false,
    this.readOnly = false,
    this.tone,
  });

  final Map<String, dynamic> catalog;
  final Map<String, Set<String>> value;
  final ValueChanged<Map<String, Set<String>>> onChanged;
  final bool deptOnly, readOnly;

  /// danger colour for the "deny" matrix.
  final Color? tone;

  String _l(Map m) => t('${m['label_ar']}', '${m['label_en']}');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = tone ?? c.primary;
    final actions = {for (final a in asMapList(catalog['actions'])) '${a['key']}': _l(a)};
    final modules = asMapList(catalog['modules']).where((m) => !deptOnly || m['scope'] == 'dept').toList();
    final groups = asMapList(catalog['groups']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final g in groups)
        if (modules.any((m) => m['group'] == g['key'])) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
            child: Text(_l(g), style: orgText(context, size: 12.5, w: FontWeight.w800, color: c.textLight)),
          ),
          for (final m in modules.where((m) => m['group'] == g['key']))
            Builder(builder: (context) {
              final key = '${m['key']}';
              final cur = value[key] ?? <String>{};
              final all = [for (final a in (m['actions'] as List)) '$a'];
              final full = all.every(cur.contains);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 10),
                decoration: BoxDecoration(
                  color: cur.isEmpty ? c.inputBg : col.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cur.isEmpty ? c.divider : col.withValues(alpha: 0.35)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(_l(m), style: orgText(context, w: FontWeight.w800))),
                    if (m['scope'] == 'dept' && !deptOnly)
                      OrgPill(t('يمكن تقييده بإدارة', 'Can be per department'), color: c.textLight),
                    if (!readOnly)
                      TextButton(
                        onPressed: () => onChanged({...value, key: full ? <String>{} : {...all}}),
                        child: Text(full ? t('إلغاء', 'Clear') : t('الكل', 'All'), style: const TextStyle(fontFamily: 'tajawal')),
                      ),
                  ]),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final a in all)
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        selectedColor: col.withValues(alpha: 0.18),
                        side: BorderSide(color: cur.contains(a) ? col : c.divider),
                        label: Text(actions[a] ?? a,
                            style: TextStyle(
                                fontFamily: 'tajawal', fontSize: 12, color: cur.contains(a) ? col : c.textMedium,
                                fontWeight: cur.contains(a) ? FontWeight.w800 : FontWeight.w500)),
                        selected: cur.contains(a),
                        onSelected: readOnly
                            ? null
                            : (on) {
                                final n = {...cur};
                                if (on) {
                                  n.add(a);
                                  if (tone == null) n.add('view'); // any right needs view (allow matrix)
                                } else {
                                  n.remove(a);
                                  if (a == 'view' && tone == null) n.clear();
                                }
                                onChanged({...value, key: n});
                              },
                      ),
                  ]),
                ]),
              );
            }),
        ],
    ]);
  }
}

Map<String, Set<String>> permsFromJson(dynamic j) => {
      for (final e in asMap(j).entries) e.key: {...((e.value as List?) ?? const []).map((x) => '$x')},
    };

Map<String, List<String>> permsToJson(Map<String, Set<String>> p) => {
      for (final e in p.entries)
        if (e.value.isNotEmpty) e.key: e.value.toList(),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Files
// ═════════════════════════════════════════════════════════════════════════════

const orgFileExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'zip'];

/// Pick a file and upload it to [uploadPath] (…/uploads). Returns {url, name, type, size} or null.
/// Org files come back as signed API paths ("/api/v1/org/files/…") — make them absolute for the app.
String orgFileUrl(String? url) {
  final u = url ?? '';
  if (!u.startsWith('/')) return u;
  final base = AppConfig.baseUrl.endsWith('/') ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1) : AppConfig.baseUrl;
  return '$base$u';
}

const _imageExt = {'png', 'jpg', 'jpeg', 'webp', 'gif'};

/// Pick a file and upload it. Images go through the app cropper first (zoom, circle, smaller size).
Future<Map<String, dynamic>?> orgPickAndUpload(String uploadPath,
    {List<String>? extensions, BuildContext? context, CropShape cropShape = CropShape.square}) async {
  final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensions ?? orgFileExtensions);
  if (f == null) return null;
  var name = f.name;
  Uint8List? bytes = kIsWeb ? await f.readAsBytes() : null;
  final isImage = _imageExt.contains(name.split('.').last.toLowerCase());
  if (isImage && context != null && context.mounted) {
    final cropped = await showAppImageCropper(context, bytes ?? await f.readAsBytes(), shape: cropShape);
    if (cropped == null) return null;
    bytes = cropped;
    name = '${name.replaceAll(RegExp(r'\.[^.]+$'), '')}.png';
  }
  try {
    final r = await ApiClient().postMultipart(uploadPath,
        fields: const {}, fileField: 'file', fileName: name, filePath: bytes != null ? null : f.path, fileBytes: bytes);
    if (r is! Map) return null;
    final out = Map<String, dynamic>.from(r);
    out['url'] = orgFileUrl('${out['url'] ?? ''}');
    return out;
  } on ApiException catch (e) {
    toast(e.message, error: true);
    return null;
  }
}

String fileSizeLabel(dynamic bytes) {
  final b = asInt(bytes);
  if (b <= 0) return '';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Picker — replaces raw DropdownButton across the organization screens
// ═════════════════════════════════════════════════════════════════════════════

/// Looks exactly like `Field` (same fill, radius, label); a tap opens a bottom sheet with search (for long lists),
/// a "None" row when [allowNone], and a check on the current value. Works the same on phones, tablets and web.
class OrgPickField<T> extends StatelessWidget {
  const OrgPickField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.allowNone = false,
    this.noneLabel,
    this.icon,
  });

  final String label;
  final T? value;
  final Map<T, String> options; // value → shown text (insertion order is kept)
  final ValueChanged<T?> onChanged;
  final bool allowNone;
  final String? noneLabel;
  final IconData? icon;

  Future<void> _open(BuildContext context) async {
    var query = '';
    final picked = await showAdminSheet<_Picked<T>>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          final entries = options.entries
              .where((e) => query.isEmpty || e.value.toLowerCase().contains(query.toLowerCase()))
              .toList();
          Widget row(T? v, String text) => Material(type: MaterialType.transparency, child: ListTile(
                onTap: () => Navigator.pop(ctx, _Picked<T>(v)),
                title: Text(text, style: orgText(ctx, w: v == value ? FontWeight.w800 : FontWeight.w500)),
                trailing: v == value ? Icon(Icons.check_circle_rounded, color: c.primary) : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                tileColor: v == value ? c.primary.withValues(alpha: 0.07) : null,
              ));
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SheetHeader(label),
              if (options.length > 8)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SearchBox(hint: t('ابحث…', 'Search…'), onChanged: (q) => set(() => query = q)),
                ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  if (allowNone && query.isEmpty) row(null, noneLabel ?? t('بدون', 'None')),
                  for (final e in entries) row(e.key, e.value),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(t('لا نتائج', 'No results'), textAlign: TextAlign.center,
                          style: orgText(ctx, color: c.textMedium)),
                    ),
                ]),
              ),
            ]),
          );
        }));
    if (picked != null) onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = value == null ? (allowNone ? (noneLabel ?? t('بدون', 'None')) : '') : (options[value] ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(context),
        child: InputDecorator(
          isEmpty: text.isEmpty,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(fontFamily: 'tajawal', color: c.textMedium),
            prefixIcon: icon == null ? null : Icon(icon, color: c.textLight),
            suffixIcon: Icon(Icons.unfold_more_rounded, color: c.textLight),
            filled: true,
            fillColor: c.inputBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.divider)),
          ),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Wrapper so "picked None" (null) can be told apart from "closed the sheet".
class _Picked<T> {
  const _Picked(this.value);
  final T? value;
}
