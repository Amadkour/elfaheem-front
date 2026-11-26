// features/courses/student/details/course_access_sheet.dart
//
// Private-course code sheet (Stu1Learn code, pin=wrong). The code is checked BY THE SERVER
// (POST /courses/{id}/unlock), never sent to the phone. Returns true on success.
//
// Look: a lock in the area's squircle (M3 pop), "دورة خاصة", one line of direction and the course's name, six code
// boxes (the focused one ringed in the area colour), a message box on a wrong code / too many tries, ONE filled
// button, and the "no code?" link when the caller gives a way to reach the teacher. A wrong code shakes the boxes
// with the coral flash (M15, AppFeedback). On a phone it is a bottom sheet, on a wide window a centred dialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

/// Why the last try did not open the course.
enum CourseCodeError { wrong, locked, other }

class CourseAccessSheet extends StatefulWidget {
  const CourseAccessSheet({
    super.key,
    required this.courseId,
    required this.courseName,
    this.onContact,
    this.unlock,
    @visibleForTesting this.initialCode = '',
    @visibleForTesting this.initialError,
    @visibleForTesting this.initialMessage,
  });

  final int courseId;
  final String courseName;

  /// "ما عندك كود؟ راسل المعلم": opens a way to reach the teacher; null hides the link.
  final VoidCallback? onContact;

  /// Tests: stands in for POST /courses/{id}/unlock (throws [ApiException] like the client).
  final Future<void> Function(String code)? unlock;

  /// Tests and goldens: a typed code, a state and its message as if the server had answered.
  final String initialCode;
  final CourseCodeError? initialError;
  final String? initialMessage;

  static const int length = 6;

  static Future<bool> show(
    BuildContext context, {
    required int courseId,
    required String courseName,
    VoidCallback? onContact,
  }) async {
    final ok = await showAppSheet<bool>(
      context,
      (_) => AppAreaScope(
        area: AppArea.learn,
        child: CourseAccessSheet(courseId: courseId, courseName: courseName, onContact: onContact),
      ),
    );
    return ok == true;
  }

  @override
  State<CourseAccessSheet> createState() => _CourseAccessSheetState();
}

class _CourseAccessSheetState extends State<CourseAccessSheet> {
  late final TextEditingController _code = TextEditingController(text: widget.initialCode);
  final _focus = FocusNode();
  final _feedback = AppFeedbackController();

  late CourseCodeError? _error = widget.initialError;
  late String? _message = widget.initialMessage;
  bool _checking = false;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    _feedback.dispose();
    super.dispose();
  }

  bool get _complete => _code.text.length == CourseAccessSheet.length;

  void _changed(String _) {
    setState(() {
      if (_error != CourseCodeError.locked) {
        _error = null;
        _message = null;
      }
    });
  }

  Future<void> _verify() async {
    if (_checking) return;
    if (_error == CourseCodeError.wrong && !_complete) {
      _focus.requestFocus();
      return;
    }
    if (!_complete || _error == CourseCodeError.locked) return;
    setState(() => _checking = true);
    try {
      final unlock = widget.unlock;
      if (unlock != null) {
        await unlock(_code.text);
      } else {
        await ApiClient().post('/api/v1/courses/${widget.courseId}/unlock', body: {'code': _code.text});
      }
      HapticFeedback.heavyImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      final d = _detail(e);
      final code = (d['code'] ?? e.code)?.toString().toLowerCase();
      CourseCodeError kind;
      String msg;
      if (code == 'too_many_attempts' || e.statusCode == 429) {
        kind = CourseCodeError.locked;
        msg = courseCodeWaitText(int.tryParse('${d['minutes'] ?? 15}') ?? 15);
      } else if (code == 'wrong_code') {
        kind = CourseCodeError.wrong;
        msg = courseCodeWrongText(int.tryParse('${d['attempts_left'] ?? 0}') ?? 0);
      } else {
        kind = CourseCodeError.other;
        msg = e.message;
      }
      HapticFeedback.vibrate();
      _feedback.shake();
      if (mounted) {
        setState(() {
          _error = kind;
          _message = msg;
          _checking = false;
          if (kind == CourseCodeError.locked) _code.clear();
        });
      }
    } catch (_) {
      _feedback.shake();
      if (mounted) {
        setState(() {
          _error = CourseCodeError.other;
          _message = 'cas_server_unreachable'.tr;
          _checking = false;
        });
      }
    }
  }

  Map _detail(ApiException e) {
    final b = e.body;
    if (b is Map && b['detail'] is Map) return b['detail'] as Map;
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final locked = _error == CourseCodeError.locked;
    final label = switch (_error) {
      CourseCodeError.locked => 'sb_learn_code_wait_cta'.tr,
      CourseCodeError.wrong => 'sb_learn_code_retry'.tr,
      _ => 'sb_learn_code_open'.tr,
    };
    final canPress = !locked && (_complete || _error == CourseCodeError.wrong);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CourseCodeLock(),
            AppSpace.gapMd,
            Semantics(
              header: true,
              child: Text('sb_learn_code_title'.tr, textAlign: TextAlign.center, style: AppType.pageTitle(context)),
            ),
            AppSpace.gapSm,
            Text(
              'sb_learn_code_hint'.tr,
              textAlign: TextAlign.center,
              style: AppType.body(context).copyWith(color: context.colors.textMedium),
            ),
            if (widget.courseName.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(widget.courseName, textAlign: TextAlign.center, style: AppType.bodyStrong(context)),
            ],
            AppSpace.gapLg,
            AppFeedback(
              controller: _feedback,
              borderRadius: BorderRadius.circular(AppRadius.tile),
              child: CourseCodeBoxes(
                controller: _code,
                focusNode: _focus,
                error: _error == CourseCodeError.wrong,
                enabled: !locked && !_checking,
                onChanged: _changed,
                onSubmitted: (_) => _verify(),
              ),
            ),
            if (_message != null && _message!.isNotEmpty) ...[
              AppSpace.gapMd,
              CourseCodeMessage(text: _message!, wait: locked),
            ],
            AppSpace.gapLg,
            SizedBox(
              width: double.infinity,
              child: AppButton.primary(
                label: label,
                busy: _checking,
                expand: true,
                size: AppButtonSize.lg,
                onPressed: canPress ? _verify : null,
              ),
            ),
            if (widget.onContact != null) ...[
              AppSpace.gapXs,
              AppButton.ghost(label: 'sb_learn_code_contact'.tr, onPressed: widget.onContact),
            ],
          ],
        ),
      ),
    );
  }
}

/// "الكود غلط، باقي لك محاولتين"
String courseCodeWrongText(int left) => 'sb_learn_code_wrong'.tr.replaceAll(
      '{left}',
      countText(left,
          ar0: 'ولا محاولة',
          ar1: 'محاولة وحدة',
          ar2: 'محاولتين',
          arFew: '{n} محاولات',
          arMany: '{n} محاولة',
          en0: 'no tries',
          en1: '1 try',
          en: '{n} tries'),
    );

/// "جرّب بعد ١٥ دقيقة"
String courseCodeWaitText(int minutes) => 'sb_learn_code_wait'.tr.replaceAll(
      '{time}',
      appDigits(countText(minutes,
          ar1: 'دقيقة', ar2: 'دقيقتين', arFew: '{n} دقايق', arMany: '{n} دقيقة', en1: '1 minute', en: '{n} minutes')),
    );

/// The lock in the area's squircle, popping in once (M3).
class CourseCodeLock extends StatelessWidget {
  const CourseCodeLock({super.key});

  @override
  Widget build(BuildContext context) {
    final set = AppAreaScope.of(context);
    return AppPop(
      child: Container(
        width: AppDashSize.ring,
        height: AppDashSize.ring,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: set.button,
          borderRadius: BorderRadius.circular(AppRadius.block),
          boxShadow: AppShadow.button(context, set.btnB),
        ),
        child: Icon(Icons.lock_outline_rounded, size: AppIconSize.xl, color: set.btnFg),
      ),
    );
  }
}

/// Six boxes over one invisible field: the phone's number pad (or a keyboard) types into it, the boxes show it.
/// Left to right in both languages, as a code is read.
class CourseCodeBoxes extends StatelessWidget {
  const CourseCodeBoxes({
    super.key,
    required this.controller,
    this.focusNode,
    this.error = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool error;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  static const double boxWidth = AppTouch.min + AppSpace.xxs;
  static const double boxHeight = AppTouch.primary + AppSpace.xs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (context, box) {
        const n = CourseAccessSheet.length;
        const gap = AppSpace.xs;
        final w = ((box.maxWidth - gap * (n - 1)) / n).clamp(AppSpace.xl, boxWidth).toDouble();
        return Semantics(
          label: 'sb_learn_code_label'.tr,
          textField: true,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, v, _) {
                  final focused = focusNode?.hasFocus ?? false;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < n; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        _box(context, c, set, w, i < v.text.length ? v.text[i] : '',
                            current: enabled && (focused || v.text.isNotEmpty) && i == v.text.length),
                      ],
                    ],
                  );
                },
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: CourseAccessSheet.length,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _box(BuildContext context, ThemeConfigProvider c, KitSet set, double w, String d, {required bool current}) {
    final filled = d.isNotEmpty;
    final kit = c.kit;
    final Color edge = error
        ? kit.live.color
        : current
            ? set.a
            : filled
                ? Color.lerp(kit.line, set.a, 0.45)!
                : kit.line;
    return AnimatedContainer(
      duration: AppMotion.of(context).fast,
      width: w,
      height: boxHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled || current ? c.cardBg : kit.well,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: edge, width: current ? AppBorder.focus : AppBorder.strong),
        boxShadow: current ? [BoxShadow(color: set.tint, spreadRadius: AppSpace.xxs)] : null,
      ),
      child: Text(appDigits(d), style: AppType.figureLarge(context).copyWith(color: c.textDark)),
    );
  }
}

/// The tinted line under the boxes: coral for a wrong code, sun while the student must wait.
class CourseCodeMessage extends StatelessWidget {
  const CourseCodeMessage({super.key, required this.text, this.wait = false});

  final String text;
  final bool wait;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    final tone = wait ? kit.warn : kit.error;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppType.bodyStrong(context).copyWith(color: tone.ink),
        ),
      ),
    );
  }
}
