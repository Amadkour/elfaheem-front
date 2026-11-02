// The scanner's presentational widgets (plain values, no camera, no network): the layout harness and the visual
// renders pump them directly (CLAUDE.md pattern, like PreJoinLayout / LiveControlBar).
//   ScannerOverlay      the guide rectangle with corner guides, the live message, the good-run pulse
//   ScannerControls     shutter · finish · switch camera (bottom) — ScannerTopBar: close · count · torch
//   CaptureResultCard   accepted ("Paper 12 of 40 captured") or rejected (the exact reason + Retake)
//   CameraProblemView   permission denied / blocked / no camera / not supported, with the fix and a way out
//   ScanProgressView    "X of N papers processed", the counts, rejected pages with "Replace this page"
//   OmrToolsPanel       the bubble-sheet entries of the exam's scans screen
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import 'omr_camera.dart' show OmrCameraIssue;
import 'omr_scan.dart' show OmrHintTone;

/// A4 portrait: width / height of the guide.
const kSheetAspect = 210 / 297;

/// Room kept above the guide (the top bar + the message) and below it (auto-capture + the shutter row).
const kGuideTop = 150.0;
const kGuideBottom = 180.0;

/// The guide's rectangle inside a box of [size]; [safe] = the device's own insets (notch, home bar).
Rect scannerGuideRect(Size size, {EdgeInsets safe = EdgeInsets.zero}) {
  final padding = EdgeInsets.fromLTRB(20, kGuideTop + safe.top, 20, kGuideBottom + safe.bottom);
  final avail = padding.deflateRect(Offset.zero & size);
  if (avail.width <= 0 || avail.height <= 0) return Rect.zero;
  var w = avail.width, h = w / kSheetAspect;
  if (h > avail.height) {
    h = avail.height;
    w = h * kSheetAspect;
  }
  return Rect.fromCenter(center: avail.center, width: w, height: h);
}

// ── the guide ───────────────────────────────────────────────────────────────────────────────────────────────────

class ScannerOverlay extends StatefulWidget {
  const ScannerOverlay({
    super.key,
    required this.message,
    this.tone = OmrHintTone.neutral,
    this.quarters = const [false, false, false, false],
    this.progress = 0,
    this.scanning = true,
    this.icon,
  });

  /// The server's sentence ("Move closer.", "Too dark, move to better light.") or the screen's own state line;
  /// empty = no message (a result card speaks instead).
  final String message;
  final OmrHintTone tone;

  /// Corner marks seen: [top-left, top-right, bottom-right, bottom-left] of the picture.
  final List<bool> quarters;

  /// 0 … 1, how far the steady run is towards an automatic capture.
  final double progress;

  /// False while a photo is being checked or a result is shown: the pulse stops.
  final bool scanning;
  final IconData? icon;

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ScannerOverlay old) {
    super.didUpdateWidget(old);
    if (old.scanning != widget.scanning) _sync();
  }

  void _sync() {
    if (widget.scanning) {
      syncMotionLoop(context, _pulse, reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, icon) = switch (widget.tone) {
      OmrHintTone.good => (c.success, c.onHero, Icons.check_circle_rounded),
      OmrHintTone.warn => (c.warning, c.charcoalDark, Icons.wb_sunny_outlined),
      OmrHintTone.neutral => (c.heroShade.withValues(alpha: .82), c.onHero, Icons.crop_free_rounded),
    };
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      final safe = MediaQuery.paddingOf(context);
      final guide = scannerGuideRect(size, safe: safe);
      return Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) => CustomPaint(
                painter: _GuidePainter(
                  guide: guide,
                  scrim: c.heroShade.withValues(alpha: .5),
                  idle: c.onHero,
                  found: c.success,
                  quarters: widget.quarters,
                  progress: widget.progress,
                  pulse: widget.scanning ? .55 + .45 * _pulse.value : 1,
                ),
              ),
            ),
          ),
        ),
        if (guide != Rect.zero && widget.message.isNotEmpty)
          Positioned(
            left: AppSpace.md,
            right: AppSpace.md,
            top: safe.top + 76,
            child: Center(
              child: Semantics(
                liveRegion: true,
                label: widget.message,
                child: ExcludeSemantics(
                  child: AnimatedContainer(
                    duration: AppMotion.of(context).base,
                    constraints: const BoxConstraints(maxWidth: 520, minHeight: AppTouch.min),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.hero)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(widget.icon ?? icon, color: fg, size: 22),
                      const SizedBox(width: AppSpace.xs),
                      Flexible(
                        child: Text(widget.message,
                            textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w700, c: fg, h: 1.3)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter({
    required this.guide,
    required this.scrim,
    required this.idle,
    required this.found,
    required this.quarters,
    required this.progress,
    required this.pulse,
  });

  final Rect guide;
  final Color scrim, idle, found;
  final List<bool> quarters;
  final double progress, pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (guide == Rect.zero) return;
    final r = RRect.fromRectAndRadius(guide, const Radius.circular(AppRadius.card));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(r)),
      Paint()..color = scrim,
    );
    if (progress > 0) {
      canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = found.withValues(alpha: (.25 + .75 * progress).clamp(0.0, 1.0).toDouble()));
    }
    final arm = (guide.shortestSide * .14).clamp(18.0, 44.0).toDouble();
    const k = AppRadius.card;
    void corner(int i, Offset o, double dx, double dy) {
      final on = i < quarters.length && quarters[i];
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 5 : 4
        ..strokeCap = StrokeCap.round
        ..color = on ? found : idle.withValues(alpha: .9 * pulse);
      final path = Path()
        ..moveTo(o.dx, o.dy + dy * arm)
        ..lineTo(o.dx, o.dy + dy * k)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + dx * k, o.dy)
        ..lineTo(o.dx + dx * arm, o.dy);
      canvas.drawPath(path, p);
    }

    corner(0, guide.topLeft, 1, 1);
    corner(1, guide.topRight, -1, 1);
    corner(2, guide.bottomRight, -1, -1);
    corner(3, guide.bottomLeft, 1, -1);
  }

  @override
  bool shouldRepaint(covariant _GuidePainter o) =>
      o.guide != guide || o.progress != progress || o.pulse != pulse || o.scrim != scrim || o.idle != idle || o.found != found ||
      !_sameList(o.quarters, quarters);

  static bool _sameList(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ── controls ────────────────────────────────────────────────────────────────────────────────────────────────────

/// A round control on the camera picture (≥ 48 × 48, labelled).
class _CamButton extends StatelessWidget {
  const _CamButton({required this.icon, required this.label, required this.onPressed, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        enabled: onPressed != null,
        child: Material(
          color: active ? c.warning : c.heroShade.withValues(alpha: .7),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: AppTouch.primary,
              height: AppTouch.primary,
              child: Icon(icon, color: active ? c.charcoalDark : c.onHero.withValues(alpha: onPressed == null ? .4 : 1), size: 26),
            ),
          ),
        ),
      ),
    );
  }
}

class ScannerTopBar extends StatelessWidget {
  const ScannerTopBar({
    super.key,
    required this.title,
    required this.onClose,
    this.countLabel,
    this.onCount,
    this.torchOn = false,
    this.onTorch,
  });

  final String title;
  final VoidCallback onClose;

  /// "2 of 40" / "Set the number of papers" — tapping sets the expected count.
  final String? countLabel;
  final VoidCallback? onCount;
  final bool torchOn;

  /// Null: no torch on this camera (the button is not shown).
  final VoidCallback? onTorch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Row(children: [
        _CamButton(icon: Icons.close_rounded, label: t('إغلاق', 'Close'), onPressed: onClose),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w700, c: c.onHero)),
        ),
        if (countLabel != null) ...[
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Material(
              color: c.heroShade.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(AppRadius.hero),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.hero),
                onTap: onCount,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.layers_outlined, color: c.onHero, size: 18),
                      const SizedBox(width: AppSpace.xxs),
                      Flexible(child: Text(countLabel!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.onHero))),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (onTorch != null) ...[
          const SizedBox(width: AppSpace.xs),
          _CamButton(icon: torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, label: t('الفلاش', 'Torch'), onPressed: onTorch, active: torchOn),
        ],
      ]),
    );
  }
}

class ScannerControls extends StatelessWidget {
  const ScannerControls({
    super.key,
    required this.onShutter,
    this.busy = false,
    this.onFinish,
    this.finishLabel,
    this.onSwitch,
    this.autoOn = true,
    this.onAuto,
  });

  /// The manual shutter (always there: auto-capture is a help, not the only way).
  final VoidCallback? onShutter;
  final bool busy;
  final VoidCallback? onFinish;
  final String? finishLabel;
  final VoidCallback? onSwitch;
  final bool autoOn;
  final ValueChanged<bool>? onAuto;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shutter = Semantics(
      button: true,
      label: t('التقاط الورقة', 'Capture the paper'),
      enabled: onShutter != null && !busy,
      child: GestureDetector(
        onTap: busy ? null : onShutter,
        child: Container(
          width: 80,
          height: 80,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.onHero, width: 4)),
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, color: busy ? c.onHero.withValues(alpha: .4) : c.onHero),
            child: busy ? Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: c.primary))) : null,
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (onAuto != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Material(
              color: c.heroShade.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(AppRadius.hero),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(t('التقاط تلقائي', 'Auto-capture'), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.onHero))),
                  const SizedBox(width: AppSpace.xs),
                  AppSwitch(value: autoOn, onChanged: onAuto),
                ]),
              ),
            ),
          ),
        Row(children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: onFinish == null
                  ? const SizedBox.shrink()
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(AppTouch.min, AppTouch.min),
                        backgroundColor: c.heroShade.withValues(alpha: .8),
                        foregroundColor: c.onHero,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                      ),
                      onPressed: onFinish,
                      icon: const Icon(Icons.done_all_rounded, size: 20),
                      label: Text(finishLabel ?? t('إنهاء', 'Finish'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          shutter,
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: onSwitch == null ? const SizedBox.shrink() : _CamButton(icon: Icons.cameraswitch_rounded, label: t('تبديل الكاميرا', 'Switch camera'), onPressed: onSwitch),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── capture result ──────────────────────────────────────────────────────────────────────────────────────────────

class CaptureResultCard extends StatelessWidget {
  const CaptureResultCard({
    super.key,
    required this.accepted,
    required this.title,
    this.more = const [],
    this.duplicate = false,
    this.onRetake,
    this.onDismiss,
  });

  final bool accepted;

  /// The server's sentence: "Paper 12 of 40 captured" or the exact reason ("Too blurry, hold steady.").
  final String title;

  /// A rejected photo's other problems.
  final List<String> more;
  final bool duplicate;
  final VoidCallback? onRetake;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = accepted ? c.success : c.danger;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: c.cardBg,
        elevation: 0,
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sheet),
            border: Border.all(color: tone.withValues(alpha: .45), width: 1.5),
            boxShadow: AppShadow.card(context),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: tone.withValues(alpha: .14), shape: BoxShape.circle),
                child: Icon(accepted ? Icons.check_rounded : Icons.error_outline_rounded, color: tone, size: 28),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: appText(17, w: FontWeight.w800, c: c.textDark, h: 1.3)),
                  const SizedBox(height: AppSpace.xxs),
                  Text(
                    accepted
                        ? (duplicate
                            ? t('هذه الصورة مرفوعة من قبل — لم يُضف شيء جديد', 'This photo was already sent — nothing new was added')
                            : t('ضع الورقة التالية داخل الإطار', 'Place the next paper inside the frame'))
                        : t('لم يُحفظ شيء ولم يُصحَّح شيء. أعد التصوير.', 'Nothing was saved or graded. Take it again.'),
                    style: appText(13.5, c: c.textMedium, h: 1.35),
                  ),
                ]),
              ),
              if (accepted && onDismiss != null)
                IconButton(
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  tooltip: t('إخفاء', 'Hide'),
                  onPressed: onDismiss,
                  icon: Icon(Icons.close_rounded, color: c.textMedium),
                ),
            ]),
            for (final m in more)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: AppSpace.xs, start: 56),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: c.danger)),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text(m, style: appText(13.5, c: c.textDark, h: 1.35))),
                ]),
              ),
            if (!accepted && onRetake != null) ...[
              const SizedBox(height: AppSpace.md),
              SizedBox(
                height: AppTouch.primary,
                child: FilledButton.icon(
                  key: const ValueKey('omr.retake'),
                  onPressed: onRetake,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: Text(t('إعادة التصوير', 'Retake'), style: appText(16, w: FontWeight.w800, c: c.onHero)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── camera problems ─────────────────────────────────────────────────────────────────────────────────────────────

class CameraProblemView extends StatelessWidget {
  const CameraProblemView({super.key, required this.issue, required this.web, this.onRetry, this.onSettings, this.onUpload, this.onClose});

  final OmrCameraIssue issue;

  /// The fix is said differently in a browser and on a phone.
  final bool web;
  final VoidCallback? onRetry;

  /// Phones: the app's settings page (a refusal for good can only be changed there).
  final VoidCallback? onSettings;

  /// The way out: upload photos or PDFs instead.
  final VoidCallback? onUpload;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, title, fix) = switch (issue) {
      OmrCameraIssue.denied => (
          Icons.no_photography_outlined,
          t('الكاميرا غير مسموح بها', 'Camera access is off'),
          t('اسمح للتطبيق باستخدام الكاميرا عند السؤال، ثم أعد المحاولة.', 'Allow the camera when you are asked, then try again.'),
        ),
      OmrCameraIssue.blocked => (
          Icons.no_photography_outlined,
          t('الكاميرا محظورة', 'The camera is blocked'),
          web
              ? t('اضغط رمز القفل بجوار عنوان الصفحة، واسمح بالكاميرا لهذا الموقع، ثم أعد المحاولة.',
                  'Tap the lock next to the page address, allow the camera for this site, then try again.')
              : t('افتح الإعدادات ← التطبيقات ← هذا التطبيق ← الأذونات، وفعّل الكاميرا، ثم ارجع وأعد المحاولة.',
                  'Open Settings → Apps → this app → Permissions, turn the camera on, then come back and try again.'),
        ),
      OmrCameraIssue.noCamera => (
          Icons.videocam_off_outlined,
          t('لا توجد كاميرا', 'No camera found'),
          t('هذا الجهاز بلا كاميرا متاحة. صوّر الأوراق بهاتف آخر أو ارفع الصور وملفات PDF.',
              'This device has no camera we can use. Use another phone, or upload images and PDFs.'),
        ),
      OmrCameraIssue.unsupported => (
          Icons.videocam_off_outlined,
          t('المتصفح لا يتيح الكاميرا هنا', 'The browser does not offer the camera here'),
          t('افتح الصفحة عبر https في متصفح حديث (Chrome أو Safari أو Edge)، أو ارفع الصور وملفات PDF.',
              'Open the page over https in a current browser (Chrome, Safari or Edge), or upload images and PDFs.'),
        ),
      OmrCameraIssue.failed => (
          Icons.videocam_off_outlined,
          t('تعذّر تشغيل الكاميرا', 'The camera could not start'),
          t('قد يكون تطبيق آخر يستخدمها. أغلقه ثم أعد المحاولة.', 'Another app may be using it. Close that app, then try again.'),
        ),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
                child: Icon(icon, color: c.primary, size: 40),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(title, textAlign: TextAlign.center, style: appText(19, w: FontWeight.w800, c: c.textDark)),
            const SizedBox(height: AppSpace.xs),
            Text(fix, textAlign: TextAlign.center, style: appText(14.5, c: c.textMedium, h: 1.45)),
            const SizedBox(height: AppSpace.lg),
            if (onSettings != null && issue == OmrCameraIssue.blocked) ...[
              AppPrimaryButton(label: t('فتح الإعدادات', 'Open settings'), icon: Icons.settings_outlined, onPressed: onSettings),
              const SizedBox(height: AppSpace.sm),
            ],
            if (onRetry != null && issue != OmrCameraIssue.noCamera && issue != OmrCameraIssue.unsupported) ...[
              (onSettings != null && issue == OmrCameraIssue.blocked)
                  ? OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(t('إعادة المحاولة', 'Try again')))
                  : AppPrimaryButton(label: t('إعادة المحاولة', 'Try again'), icon: Icons.refresh_rounded, onPressed: onRetry),
              const SizedBox(height: AppSpace.sm),
            ],
            if (onUpload != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(t('رفع صور أو PDF بدلًا من ذلك', 'Upload images or PDFs instead')),
              ),
            if (onClose != null) ...[
              const SizedBox(height: AppSpace.xs),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
                onPressed: onClose,
                child: Text(t('رجوع', 'Back')),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── progress ────────────────────────────────────────────────────────────────────────────────────────────────────

/// A rejected page and what happened to its replacement (plain values).
class RejectedPageRow {
  const RejectedPageRow({
    required this.pageId,
    required this.text,
    this.instruction = '',
    this.fileName,
    this.replacement,
    this.replacementText,
  });

  final int pageId;

  /// "Page 7 is too blurry. Please upload a clearer image of it."
  final String text;
  final String instruction;
  final String? fileName;

  /// null · uploading · refused (the gate said no: nothing stored) · processing · processed · review · rejected ·
  /// failed.
  final String? replacement;

  /// What the server said about the replacement: "Page 7 replaced. It is being read now.", or the gate's exact
  /// reason ("Page 7 is too blurry. … Too blurry, hold steady.").
  final String? replacementText;
}

class ScanProgressView extends StatelessWidget {
  const ScanProgressView({
    super.key,
    required this.headline,
    required this.done,
    required this.total,
    required this.finished,
    this.graded = 0,
    this.review = 0,
    this.rejected = 0,
    this.failed = 0,
    this.duplicates = 0,
    this.camera = false,
    this.rejectedPages = const [],
    this.onReplace,
    this.onReview,
    this.onResults,
    this.onMore,
  });

  /// The server's "12 of 40 papers processed".
  final String headline;
  final int done;
  final int total;
  final bool finished;
  final int graded, review, rejected, failed, duplicates;
  final bool camera;
  final List<RejectedPageRow> rejectedPages;
  final ValueChanged<int>? onReplace;
  final VoidCallback? onReview;
  final VoidCallback? onResults;

  /// "Upload more" / "Scan more".
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final frac = total <= 0 ? (finished ? 1.0 : 0.0) : (done / total).clamp(0.0, 1.0).toDouble();
    Widget count(IconData icon, int n, String label, Color color) => AppStatChip(icon: icon, value: '$n', label: label, color: color);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: (finished ? c.success : c.primary).withValues(alpha: .12), shape: BoxShape.circle),
              child: Icon(finished ? Icons.task_alt_rounded : (camera ? Icons.photo_camera_outlined : Icons.document_scanner_outlined),
                  color: finished ? c.success : c.primary),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(liveRegion: true, child: Text(headline, style: appText(18, w: FontWeight.w800, c: c.textDark, h: 1.25))),
                const SizedBox(height: 2),
                Text(
                  finished
                      ? t('اكتملت المعالجة', 'Processing finished')
                      : t('تُقرأ الأوراق في الخلفية — يمكنك مغادرة هذه الصفحة', 'Papers are read in the background — you can leave this page'),
                  style: appText(13, c: c.textMedium),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.md),
          AppProgressBar(value: frac * 100, height: 8, color: finished ? c.success : c.primary),
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            count(Icons.check_circle_outline_rounded, graded, t('صُححت', 'Graded'), c.success),
            count(Icons.rate_review_outlined, review, t('للمراجعة', 'To review'), c.warning),
            count(Icons.block_rounded, rejected, t('مرفوضة', 'Rejected'), c.danger),
            if (failed > 0) count(Icons.error_outline_rounded, failed, t('تعذّرت', 'Failed'), c.danger),
          ]),
          if (duplicates > 0) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              t('$duplicates صفحة مرفوعة من قبل وتم تخطيها', '$duplicates page${duplicates == 1 ? ' was' : 's were'} already uploaded and skipped'),
              style: appText(13, c: c.textMedium),
            ),
          ],
        ]),
      ),
      if (rejectedPages.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        AppSectionTitle(t('صفحات تحتاج صورة أوضح', 'Pages that need a clearer image'),
            subtitle: t('لم تُصحَّح هذه الصفحات. ارفع صورة أوضح لكل منها.', 'These pages were not graded. Upload a clearer image of each.')),
        for (final r in rejectedPages) _RejectedTile(row: r, onReplace: onReplace == null ? null : () => onReplace!(r.pageId)),
      ],
      const SizedBox(height: AppSpace.md),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        if (onReview != null && review > 0)
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            onPressed: onReview,
            icon: const Icon(Icons.rate_review_outlined),
            label: Text(t('مراجعة $review', 'Review $review')),
          ),
        if (onResults != null)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            onPressed: onResults,
            icon: const Icon(Icons.leaderboard_outlined),
            label: Text(t('النتائج', 'Results')),
          ),
        if (onMore != null)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            onPressed: onMore,
            icon: Icon(camera ? Icons.photo_camera_outlined : Icons.upload_file_rounded),
            label: Text(camera ? t('تصوير المزيد', 'Scan more') : t('رفع المزيد', 'Upload more')),
          ),
      ]),
    ]);
  }
}

class _RejectedTile extends StatelessWidget {
  const _RejectedTile({required this.row, this.onReplace});
  final RejectedPageRow row;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rep = row.replacement;
    final (Color? pillColor, String? pill) = switch (rep) {
      'uploading' => (c.primary, t('يُفحص البديل…', 'Checking the new image…')),
      'refused' => (c.danger, t('رُفضت الصورة البديلة', 'The new image was refused')),
      'processing' => (c.primary, t('قُبلت — يُقرأ البديل…', 'Accepted — reading the new image…')),
      'processed' => (c.success, t('استُبدلت وصُححت', 'Replaced and graded')),
      'review' => (c.warning, t('استُبدلت — تحتاج مراجعة', 'Replaced — needs review')),
      'rejected' => (c.danger, t('رُفض البديل أيضًا', 'The new image was refused too')),
      'failed' => (c.danger, t('تعذّرت قراءة البديل', 'The new image could not be read')),
      _ => (null, null),
    };
    final settled = rep == 'processed' || rep == 'review';
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(settled ? Icons.check_circle_rounded : Icons.image_not_supported_outlined, color: settled ? c.success : c.danger),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.text, style: appText(14.5, w: FontWeight.w700, c: c.textDark, h: 1.35)),
              if (row.instruction.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(row.instruction, style: appText(13, c: c.textMedium, h: 1.35)),
              ],
              if (row.fileName != null && row.fileName!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(row.fileName!, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: appText(12, c: c.textLight)),
              ],
              if (pill != null) ...[
                const SizedBox(height: AppSpace.xs),
                AppBadgePill(pill, color: pillColor),
              ],
              if (row.replacementText != null && row.replacementText!.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Semantics(
                  liveRegion: true,
                  child: Text(row.replacementText!,
                      key: ValueKey('omr.replace.result.${row.pageId}'),
                      style: appText(13, c: const {'refused', 'rejected', 'failed'}.contains(rep) ? c.danger : c.textMedium, h: 1.35)),
                ),
              ],
            ]),
          ),
        ]),
        if (onReplace != null && !settled && rep != 'uploading' && rep != 'processing') ...[
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              key: ValueKey('omr.replace.${row.pageId}'),
              style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              onPressed: onReplace,
              icon: const Icon(Icons.find_replace_rounded),
              label: Text(t('استبدال هذه الصفحة', 'Replace this page')),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── the exam's bubble-sheet tools ───────────────────────────────────────────────────────────────────────────────

/// One entry of [OmrToolsPanel]. A null [onTap] with a [note] says why it is not available yet.
class OmrToolEntry {
  const OmrToolEntry({required this.id, required this.icon, required this.title, required this.subtitle, this.onTap, this.note});
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? note;
}

class OmrToolsPanel extends StatelessWidget {
  const OmrToolsPanel({super.key, required this.entries, this.busy, this.title, this.subtitle});
  final List<OmrToolEntry> entries;

  /// The heading (default: "Bubble sheet" and its one-line how-to).
  final String? title, subtitle;

  /// The entry whose action is running.
  final String? busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(title ?? t('ورقة التظليل', 'Bubble sheet'),
          subtitle: subtitle ?? t('اطبع الأوراق، ثم صوّرها أو ارفعها — تُصحَّح تلقائيًا', 'Print the sheets, then scan or upload them — they are graded for you')),
      for (final e in entries)
        Opacity(
          opacity: e.onTap == null && busy != e.id ? .6 : 1,
          child: AppCard(
            key: ValueKey('omr.tool.${e.id}'),
            margin: const EdgeInsets.only(bottom: AppSpace.xs),
            onTap: busy == null ? e.onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.chip)),
                  child: Icon(e.icon, color: appInk(context, c.primary)),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.title, style: appText(14.5, w: FontWeight.w700, c: c.textDark)),
                    const SizedBox(height: 2),
                    Text(e.note ?? e.subtitle, style: appText(12.5, c: c.textMedium, h: 1.3)),
                  ]),
                ),
                const SizedBox(width: AppSpace.xs),
                if (busy == e.id)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else if (e.onTap != null)
                  Icon(Icons.chevron_right_rounded, color: c.textMedium),
              ]),
            ),
          ),
        ),
    ]);
  }
}
