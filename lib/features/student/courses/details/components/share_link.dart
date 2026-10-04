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
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/deep_link_service.dart';

import '../../../models.dart';
import '../growth_tr.dart';

/// The public URL of a course.
///
/// ⚠️ Adjust this ONE line so it matches the link that
/// `DeepLinkService.shareCourse` builds / your web router expects.
String courseShareUrl(CourseModel course) =>
    '${Uri.base.origin}/course/${course.id}';

Future<void> shareCourseLink(BuildContext context, CourseModel course) async {
  if (kIsWeb) {
    await showShareLinkDialog(
      context,
      url: courseShareUrl(course),
      title: course.name,
    );
    return;
  }
  final copied = await DeepLinkService.shareCourse(
    courseId: int.parse(course.id),
    courseName: course.name,
  );
  if (copied) Helpers.showMessage(gt('تم نسخ الرابط', 'Link copied'));
}

Future<void> showShareLinkDialog(
  BuildContext context, {
  required String url,
  required String title,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ShareLinkDialog(url: url, title: title),
    );

class _ShareLinkDialog extends StatefulWidget {
  const _ShareLinkDialog({required this.url, required this.title});
  final String url, title;

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
                    gt('مشاركة الكورس', 'Share this course'),
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
                    fillColor: c.primary.withValues(alpha: 0.06),
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
