// features/courses/teacher/course_privacy_card.dart  (put it next to course_form_screen.dart)
//
// "Public / Private" switch for the course form. A private course needs a 6-digit code:
// students must enter it (server-verified) before the course opens. The teacher can type one,
// generate one, or leave it empty (the server generates it). On edit the current code is loaded
// from GET /courses/{id}/access-code (only the owner / admins can read it).
import 'dart:math';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';


class CoursePrivacyCard extends StatefulWidget {
  const CoursePrivacyCard({
    super.key,
    required this.isPrivate,
    required this.onChanged,
    required this.codeCtrl,
    this.courseId,
  });

  final bool isPrivate;
  final ValueChanged<bool> onChanged;
  final TextEditingController codeCtrl;

  /// Set when editing, to prefill the existing code.
  final int? courseId;

  /// Use as the code field's validator from the parent form.
  static String? validateCode(bool isPrivate, String? v) {
    if (!isPrivate) return null;
    final t = (v ?? '').trim();
    if (t.isEmpty) return null; // empty → the server generates one
    return RegExp(r'^\d{6}$').hasMatch(t) ? null : 'pc_code_6_digits'.tr;
  }

  @override
  State<CoursePrivacyCard> createState() => _CoursePrivacyCardState();
}

class _CoursePrivacyCardState extends State<CoursePrivacyCard> {
  @override
  void initState() {
    super.initState();
    if (widget.courseId != null && widget.isPrivate && widget.codeCtrl.text.isEmpty) _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient().get('/api/v1/courses/${widget.courseId}/access-code');
      if (r is Map && r['access_code'] != null && mounted) widget.codeCtrl.text = r['access_code'].toString();
    } catch (_) {}
  }

  void _generate() {
    final rnd = Random.secure();
    widget.codeCtrl.text = List.generate(6, (_) => rnd.nextInt(10)).join();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final priv = widget.isPrivate;
    return ParentComponent(
        featureKey: 'course_form.privacy',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: priv ? c.accent2.withValues(alpha: 0.08) : c.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: priv ? c.accent2.withValues(alpha: 0.5) : c.heroShade.withValues(alpha: 0.12)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(priv ? Icons.lock_rounded : Icons.public_rounded, color: priv ? c.accent2 : c.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(priv ? 'cas_private_course'.tr : 'pc_public_course'.tr,
                      style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, color: c.textDark)),
                  Text(
                    priv
                        ? 'pc_private_hint'.tr
                        : 'pc_public_hint'.tr,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: c.textLight),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              AppSwitch(value: priv, onChanged: widget.onChanged, semanticLabel: 'cas_private_course'.tr),
            ]),
            if (priv) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: widget.codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => CoursePrivacyCard.validateCode(priv, v),
                style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  helperText: 'pc_leave_empty'.tr,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    tooltip: 'pc_copy'.tr,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () => Clipboard.setData(ClipboardData(text: widget.codeCtrl.text)),
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.autorenew_rounded, size: 18),
                  label: Text('pc_generate'.tr),
                ),
              ),
            ],
          ]),
        ));
  }
}