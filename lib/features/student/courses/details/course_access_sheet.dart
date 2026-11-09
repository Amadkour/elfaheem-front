// features/student/courses/details/course_access_sheet.dart
//
// Private-course code sheet. Same look & keypad as the exam passcode sheet, but the code is checked
// BY THE SERVER (POST /courses/{id}/unlock) — it is never sent to the phone. Returns true on success.
import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';


class CourseAccessSheet extends StatefulWidget {
  const CourseAccessSheet({super.key, required this.courseId, required this.courseName});

  final int courseId;
  final String courseName;

  static Future<bool> show(BuildContext context, {required int courseId, required String courseName}) async {
    final ok = await showAppModalSheet<bool>(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.colors.heroShade.withValues(alpha: 0.6),
      builder: (_) => CourseAccessSheet(courseId: courseId, courseName: courseName),
    );
    return ok == true;
  }

  @override
  State<CourseAccessSheet> createState() => _CourseAccessSheetState();
}

class _CourseAccessSheetState extends State<CourseAccessSheet> with SingleTickerProviderStateMixin {
  static const _len = 6;
  // Theme roles (the sheet follows the live theme, light or dark).
  ThemeConfigProvider get _c => context.colors;
  Color get _surface => _c.cardBg;
  Color get _gold => _c.accent2;
  Color get _empty => _c.divider;
  Color get _red => _c.danger;
  Color get _text => _c.textDark;
  Color get _muted => _c.textLight;

  String _entered = '';
  bool _checking = false;
  String? _error;

  late final AnimationController _shake =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _key(String d) {
    if (_entered.length >= _len || _checking) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      _entered += d;
    });
    if (_entered.length == _len) _verify();
  }

  void _del() {
    if (_entered.isEmpty || _checking) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _checking = true);
    try {
      await ApiClient().post('/api/v1/courses/${widget.courseId}/unlock', body: {'code': _entered});
      HapticFeedback.heavyImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      final d = _detail(e);
      final code = (d['code'] ?? e.code)?.toString().toLowerCase();
      String msg;
      if (code == 'too_many_attempts' || e.statusCode == 429) {
        msg = 'cas_too_many'.tr.replaceAll('{minutes}', '${d['minutes'] ?? 15}');
      } else if (code == 'wrong_code') {
        msg = 'cas_wrong_code'.tr.replaceAll('{n}', '${d['attempts_left'] ?? 0}');
      } else {
        msg = e.message;
      }
      HapticFeedback.vibrate();
      _shake.forward(from: 0);
      if (mounted) setState(() { _error = msg; _entered = ''; _checking = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'cas_server_unreachable'.tr; _entered = ''; _checking = false; });
    }
  }

  Map _detail(ApiException e) {
    final b = e.body;
    if (b is Map && b['detail'] is Map) return b['detail'] as Map;
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Container(
      width: w > 500 ? 500 : w,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              margin: const EdgeInsets.only(top: 14, bottom: 14),
              width: 40, height: 4,
              decoration: BoxDecoration(color: _c.divider, borderRadius: BorderRadius.circular(2)),
            ),
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [_gold, _c.heroEnd(_gold, 0.45)]),
                boxShadow: [BoxShadow(color: _gold.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Icon(Icons.lock_outline_rounded, color: _c.onHero, size: 28),
            ),
            const SizedBox(height: 14),
            Text('cas_private_course'.tr,
                style: TextStyle(color: _text, fontSize: 21, fontWeight: FontWeight.w700, fontFamily: AppFonts.family)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                'cas_enter_code'.tr.replaceAll('{name}', widget.courseName),
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13, height: 1.5, fontFamily: AppFonts.family),
              ),
            ),
            const SizedBox(height: 22),
            AnimatedBuilder(
              animation: _shake,
              builder: (_, child) => Transform.translate(
                offset: Offset(_error != null ? (1 - _shake.value) * 10 * ((_shake.value * 12).floor().isEven ? 1 : -1) : 0, 0),
                child: child,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_len, (i) {
                  final filled = i < _entered.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    width: filled ? 16 : 14, height: filled ? 16 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _error != null ? _red : (filled ? _gold : _empty),
                      boxShadow: filled && _error == null
                          ? [BoxShadow(color: _gold.withValues(alpha: 0.5), blurRadius: 10)]
                          : null,
                    ),
                  );
                }),
              ),
            ),
            SizedBox(
              height: 34,
              child: Center(
                child: _checking
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _gold))
                    : Text(_error ?? '', textAlign: TextAlign.center,
                    style: TextStyle(color: _red, fontSize: 12.5, fontFamily: AppFonts.family)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 20),
              // A keypad keeps the phone order 1-2-3 in Arabic too.
              child: Directionality(textDirection: TextDirection.ltr, child: Column(children: [
                for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['x', '0', 'del']])
                  Row(children: [
                    for (final k in row)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: k == 'x'
                              ? _Key(onTap: () => Navigator.of(context).pop(false), bg: context.colors.danger, label: 'cancel'.tr,
                              child: Icon(Icons.clear, color: context.colors.onHero, size: 22))
                              : k == 'del'
                              ? _Key(onTap: _del, label: 'delete'.tr, child: Icon(Icons.backspace_outlined, color: _muted, size: 22))
                              : _Key(onTap: () => _key(k),
                              child: Text(k, style: TextStyle(color: _text, fontSize: 24, fontWeight: FontWeight.w300))),
                        ),
                      ),
                  ]),
              ])),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.child, required this.onTap, this.bg, this.label});
  final Widget child;
  final VoidCallback onTap;
  final Color? bg;
  final String? label;   // icon-only keys (cancel / delete) are announced by screen readers

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg ?? c.inputBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.divider),
            boxShadow: [BoxShadow(color: c.heroShade.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 4))],
          ),
          child: child,
        ),
      ),
    );
  }
}