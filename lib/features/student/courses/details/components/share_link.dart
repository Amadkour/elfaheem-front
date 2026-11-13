// features/student/courses/details/components/share_link.dart
//
// Share entry point for the course screen.
//  • mobile → unchanged: DeepLinkService.shareCourse (native sheet / copy)
//  • web    → a dialog that SHOWS the link, pre-selected, with a copy button.
//             (The browser has no native share sheet, so before this the link
//             was copied silently or not at all, and the user never saw it.)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_share_sheet.dart' show showAppShareSheet, appLinkKindLabel, AppLinkKind;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/deep_link_service.dart';
import 'package:provider/provider.dart';

import '../../../../../config/app_config.dart';
import '../../../models.dart';
import '../growth_tr.dart';

/// The public URL of a course: the same `/c/<id>?ref=<sharer>` link `DeepLinkService.shareCourse` builds
/// (the only form the router and `DeepLinkService.parse` understand), on the site being browsed.
String courseShareUrl(CourseModel course, {int? sharerId}) {
  final id = int.tryParse(course.id) ?? 0;
  final link = DeepLinkService.buildLink(id, sharerId);
  return kIsWeb ? link.replaceFirst(DeepLinkService.siteBase, Uri.base.origin) : link;
}

/// The app's one share sheet (D-307, design/app_share_sheet.dart): the link, Copy, the system share sheet (apps) and a
/// QR code. The link keeps the sharer's id (`?ref=`) for the share counter.
Future<void> shareCourseLink(BuildContext context, CourseModel course) async {
  final title = (AppConfig.lang == 'ar' ? course.titleAr : course.titleEn) ?? '';
  final (kind, icon) = appLinkKindLabel(AppLinkKind.course);
  await showAppShareSheet(
    context,
    url: courseShareUrl(course, sharerId: context.read<MyAuthProvider>().currentUser?.id),
    title: title,
    kind: kind,
    icon: icon,
  );
}

/// [heading] replaces "Share this course" (e.g. a profile link, D-074).
Future<void> showShareLinkDialog(
  BuildContext context, {
  required String url,
  required String title,
  String? heading,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ShareLinkDialog(url: url, title: title, heading: heading),
    );

class _ShareLinkDialog extends StatefulWidget {
  const _ShareLinkDialog({required this.url, required this.title, this.heading});
  final String url, title;
  final String? heading;

  @override
  State<_ShareLinkDialog> createState() => _ShareLinkDialogState();
}

class _ShareLinkDialogState extends State<_ShareLinkDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.url)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.url.length);
  bool _copied = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: c.cardBg,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.ios_share_rounded, size: 19, color: c.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.heading ?? gt('مشاركة الكورس', 'Share this course'),
                    style: c.h3.copyWith(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: gt('إغلاق', 'Close'),
                  icon: Icon(Icons.close_rounded, color: c.textLight),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const SizedBox(height: 6),
              Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: c.caption),
              const SizedBox(height: 16),
              // URLs are always left-to-right, even inside an Arabic UI.
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _ctrl,
                  readOnly: true,
                  autofocus: true,
                  onTap: () => _ctrl.selection =
                      TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length),
                  style: c.body.copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: c.primaryWash,
                    prefixIcon: Icon(Icons.link_rounded, size: 18, color: c.primary),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: _copy,
                  style: FilledButton.styleFrom(
                    backgroundColor: _copied ? c.success : c.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _copied
                        ? gt('تم النسخ', 'Copied')
                        : gt('نسخ الرابط', 'Copy link'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
