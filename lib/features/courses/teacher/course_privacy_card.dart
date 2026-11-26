// features/courses/teacher/course_privacy_card.dart
//
// "Public / Private" choice of the course form (Tea1Wizard privacy): two radio cards. A private course needs a
// 6-digit code: students must enter it (server-verified) before the course opens. The teacher can type one (the
// boxes are a view of one hidden number field), generate one, or leave it empty (the server generates it). On edit
// the current code is loaded from GET /courses/{id}/access-code (only the owner / admins can read it).
import 'dart:math';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/wizard_kit.dart';

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
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    if (widget.courseId != null && widget.isPrivate && widget.codeCtrl.text.isEmpty) _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
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

  Future<void> _copy() async {
    if (widget.codeCtrl.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.codeCtrl.text));
    if (mounted) showAppNotice('pc_copy'.tr);
  }

  Widget _code(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: set.a.withValues(alpha: 0.4), width: AppBorder.strong),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('t1_wz_code'.tr, style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.xxs),
        Text('t1_wz_code_sub'.tr, style: AppType.meta(context)),
        const SizedBox(height: AppSpace.sm),
        FormField<String>(
          validator: (_) => CoursePrivacyCard.validateCode(widget.isPrivate, widget.codeCtrl.text),
          builder: (state) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Semantics(
              textField: true,
              label: 't1_wz_code'.tr,
              child: ListenableBuilder(
                listenable: widget.codeCtrl,
                builder: (_, _) => Stack(children: [
                  WzCodeBoxes(code: widget.codeCtrl.text, focused: _focus.hasFocus),
                  // the boxes are what is seen; this invisible field is what is typed in
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0,
                      child: TextField(
                        key: const ValueKey('wizard.privacy.code'),
                        controller: widget.codeCtrl,
                        focusNode: _focus,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(WzCodeBoxes.length)],
                        showCursor: false,
                        enableInteractiveSelection: false,
                        decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
                        onChanged: (_) => state.didChange(widget.codeCtrl.text),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            if (state.hasError) ...[
              const SizedBox(height: AppSpace.xs),
              Text(state.errorText!, style: AppType.meta(context).copyWith(color: c.danger)),
            ],
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
          AppButton.secondary(key: const ValueKey('wizard.privacy.generate'), label: 'pc_generate'.tr, icon: Icons.autorenew_rounded, onPressed: _generate),
          AppButton.primary(key: const ValueKey('wizard.privacy.copy'), label: 'pc_copy'.tr, icon: Icons.copy_rounded, onPressed: _copy),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final priv = widget.isPrivate;
    return ParentComponent(
      featureKey: 'course_form.privacy',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        WzOption(
          key: const ValueKey('wizard.privacy.public'),
          selected: !priv,
          title: 'pc_public_course'.tr,
          subtitle: 't1_wz_public_sub'.tr,
          onTap: () => widget.onChanged(false),
        ),
        const SizedBox(height: AppSpace.sm),
        WzOption(
          key: const ValueKey('wizard.privacy.private'),
          selected: priv,
          icon: Icons.lock_outline_rounded,
          title: 'cas_private_course'.tr,
          subtitle: 't1_wz_private_sub'.tr,
          onTap: () => widget.onChanged(true),
        ),
        if (priv) ...[const SizedBox(height: AppSpace.sm), _code(context)],
      ]),
    );
  }
}
