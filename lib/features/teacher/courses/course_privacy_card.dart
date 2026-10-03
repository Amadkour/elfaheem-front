// features/teacher/courses/course_privacy_card.dart  (put it next to course_form_screen.dart)
//
// "Public / Private" switch for the course form. A private course needs a 6-digit code:
// students must enter it (server-verified) before the course opens. The teacher can type one,
// generate one, or leave it empty (the server generates it). On edit the current code is loaded
// from GET /courses/{id}/access-code (only the owner / admins can read it).
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../student/courses/details/growth_tr.dart';

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
    return RegExp(r'^\d{6}$').hasMatch(t) ? null : gt('الكود 6 أرقام', 'Code must be 6 digits');
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: priv ? const Color(0xFFC9A84C).withValues(alpha: 0.08) : c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: priv ? const Color(0xFFC9A84C).withValues(alpha: 0.5) : Colors.black12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(priv ? Icons.lock_rounded : Icons.public_rounded, color: priv ? const Color(0xFFC9A84C) : c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(priv ? gt('كورس خاص', 'Private course') : gt('كورس عام', 'Public course'),
                  style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
              Text(
                priv
                    ? gt('لا يفتح إلا بالكود، ولا يظهر في الكتالوج العام', 'Opens only with the code; hidden from the public catalogue')
                    : gt('يظهر للجميع في الكتالوج', 'Visible to everyone in the catalogue'),
                style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: c.textLight),
              ),
            ]),
          ),
          Switch(value: priv, onChanged: widget.onChanged),
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
              helperText: gt('اتركه فارغاً ليُنشأ تلقائياً', 'Leave empty to auto-generate'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: IconButton(
                tooltip: gt('نسخ', 'Copy'),
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
              label: Text(gt('إنشاء كود', 'Generate code')),
            ),
          ),
        ],
      ]),
    );
  }
}
