// lib/features/org/org_join_scan.dart — scan an organization join code with the camera.
//
//   parseJoinQr(raw)        pure: the join code inside a scanned QR payload (unit-tested in test/org/)
//   openJoinScanner(ctx)    full-screen scanner → the code, or null (closed / "enter it by hand")
//   joinScannerAvailable    false on web (mobile_scanner's web build loads ZXing from a CDN at runtime) — the
//                           Join page hides its "Scan QR" button there and keeps the manual field
//
// Payloads understood: the bare code the Codes panel encodes (QrImageView(data: code), maybe grouped
// "ABCD-2345-XY"), the shared invitation text ("… الكود: CODE" / "… the code: CODE") and a link carrying
// ?code= / ?join_code= (also inside a #/ fragment), or the share link https://nextbrain.site/j/<CODE>. Codes are normalised like the server does (upper-case,
// letters and digits only).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../admin/admin_common.dart' show t;

bool get joinScannerAvailable => !kIsWeb;

/// The share link of a join code: opens the Join page with the code filled in (also signed out). `?code=` repeats
/// the code for installed apps that predate `/j/` links: their scanner reads a link's `?code=` (D-283), so one
/// printed QR works in old and new apps.
String joinLinkFor(String code) {
  final c = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return 'https://nextbrain.site/j/$c?code=$c';
}

final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');
final _sharedText = RegExp(r'[:：]\s*([A-Za-z0-9][A-Za-z0-9 \-]{2,48}?)\s*[.!]?\s*$');
final _bare = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 \-]*$');

String? _norm(String v) {
  final n = v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return n.length >= 4 && n.length <= 40 ? n : null;
}

/// The join code inside a scanned QR payload, or null when it isn't one.
String? parseJoinQr(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty || s.length > 600) return null;
  if (_scheme.hasMatch(s)) {
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    // a join link: https://nextbrain.site/j/<CODE>
    final seg = uri.pathSegments;
    if (seg.length == 2 && seg[0] == 'j') return _norm(seg[1]);
    String? pick(Map<String, String> q) => q['code'] ?? q['join_code'];
    var v = pick(uri.queryParameters);
    final frag = uri.fragment;
    if (v == null && frag.contains('?')) {
      v = pick(Uri.splitQueryString(frag.substring(frag.indexOf('?') + 1)));
    }
    return v == null ? null : _norm(v);
  }
  final shared = _sharedText.firstMatch(s);
  if (shared != null) return _norm(shared.group(1)!);
  if (_bare.hasMatch(s) && s.length <= 48) return _norm(s);
  return null;
}

/// Opens the full-screen scanner; returns the parsed code (null when closed).
Future<String?> openJoinScanner(BuildContext context) => Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const JoinScannerPage()),
    );

class JoinScannerPage extends StatefulWidget {
  const JoinScannerPage({super.key});

  @override
  State<JoinScannerPage> createState() => _JoinScannerPageState();
}

class _JoinScannerPageState extends State<JoinScannerPage> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _ctrl = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
  late final _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  bool _done = false;
  String? _hint;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // back from the system settings (camera allowed there) → try again
    if (state == AppLifecycleState.resumed && !_done && _ctrl.value.error != null) {
      unawaited(_ctrl.start().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hintTimer?.cancel();
    _sweep.dispose();
    unawaited(_ctrl.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final code = parseJoinQr(b.rawValue);
      if (code != null) {
        _done = true;
        HapticFeedback.mediumImpact();
        unawaited(_ctrl.stop().catchError((_) {}));
        Navigator.of(context).pop(code);
        return;
      }
    }
    if (cap.barcodes.isNotEmpty) {
      _hintTimer?.cancel();
      setState(() => _hint = t('هذا الرمز ليس كود انضمام — امسح رمز QR الذي أرسلته مؤسستك', 'This isn\'t a join code — scan the QR your institution sent'));
      _hintTimer = Timer(const Duration(seconds: 3), () => mounted ? setState(() => _hint = null) : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, box) {
        final side = (box.maxWidth < box.maxHeight ? box.maxWidth : box.maxHeight) * 0.68;
        final window = Rect.fromCenter(center: Offset(box.maxWidth / 2, box.maxHeight * 0.44), width: side, height: side);
        return Stack(fit: StackFit.expand, children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
            scanWindow: window,
            errorBuilder: (context, error) => _ErrorView(error: error, onManual: () => Navigator.of(context).pop()),
            placeholderBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _ctrl,
            builder: (_, st, _) => st.error != null
                ? const SizedBox.shrink()
                : IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _sweep,
                      builder: (_, _) => CustomPaint(painter: _ViewfinderPainter(window, c.primary, _sweep.value)),
                    ),
                  ),
          ),
          // top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                _RoundButton(icon: Icons.close_rounded, tooltip: t('إغلاق', 'Close'), onTap: () => Navigator.of(context).pop()),
                Expanded(
                  child: Text(t('امسح كود الانضمام', 'Scan join code'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _ctrl,
                  builder: (_, st, _) {
                    final on = st.torchState == TorchState.on;
                    final usable = st.isRunning && st.torchState != TorchState.unavailable;
                    return _RoundButton(
                      icon: on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      tooltip: t('الكشاف', 'Torch'),
                      active: on,
                      color: c.primary,
                      onTap: usable ? () => unawaited(_ctrl.toggleTorch().catchError((_) {})) : null,
                    );
                  },
                ),
              ]),
            ),
          ),
          // hint under the viewfinder
          Positioned(
            left: 24,
            right: 24,
            top: window.bottom + 28,
            child: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _ctrl,
              builder: (_, st, _) => st.error != null
                  ? const SizedBox.shrink()
                  : Column(children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _hint ?? t('وجّه الكاميرا إلى رمز QR الخاص بمؤسستك', 'Point the camera at your institution\'s QR code'),
                          key: ValueKey(_hint),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _hint == null ? Colors.white : c.warning, fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: const StadiumBorder(),
                        ),
                        icon: const Icon(Icons.keyboard_rounded, size: 20),
                        label: Text(t('أدخل الكود يدوياً', 'Enter the code instead')),
                      ),
                    ]),
            ),
          ),
        ]);
      }),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.active = false, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: active ? (color ?? Colors.white) : Colors.black.withValues(alpha: 0.42),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(icon, color: onTap == null ? Colors.white38 : Colors.white, size: 24),
            ),
          ),
        ),
      );
}

/// Dimmed scrim with a rounded cut-out, corner brackets and a soft scanning line.
class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter(this.window, this.accent, this.t);
  final Rect window;
  final Color accent;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(window, const Radius.circular(26));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(r)),
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.22));
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = accent;
    const len = 48.0, rad = 26.0;
    final w = window;
    for (final (o, dx, dy) in [(w.topLeft, 1.0, 1.0), (w.topRight, -1.0, 1.0), (w.bottomLeft, 1.0, -1.0), (w.bottomRight, -1.0, -1.0)]) {
      canvas.drawPath(
        Path()
          ..moveTo(o.dx, o.dy + dy * len)
          ..lineTo(o.dx, o.dy + dy * rad)
          ..arcToPoint(Offset(o.dx + dx * rad, o.dy), radius: const Radius.circular(rad), clockwise: dx * dy > 0)
          ..lineTo(o.dx + dx * len, o.dy),
        p,
      );
    }
    final y = w.top + 18 + (w.height - 36) * t;
    final line = Rect.fromLTWH(w.left + 22, y - 1.5, w.width - 44, 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(line, const Radius.circular(2)),
      Paint()
        ..shader = LinearGradient(colors: [accent.withValues(alpha: 0), accent, accent.withValues(alpha: 0)]).createShader(line)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.t != t || old.window != window || old.accent != accent;
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onManual});
  final MobileScannerException error;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(denied ? Icons.no_photography_rounded : Icons.videocam_off_rounded, color: c.primary, size: 40),
              ),
              const SizedBox(height: 18),
              Text(
                denied ? t('الكاميرا غير مسموح بها', 'Camera access is off') : t('تعذّر تشغيل الكاميرا', 'The camera couldn\'t start'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? t('اسمح للتطبيق باستخدام الكاميرا من الإعدادات لمسح رمز QR، أو أدخل الكود يدوياً.',
                        'Allow camera access in Settings to scan the QR code, or type the code instead.')
                    : t('جرّب مرة أخرى بعد قليل، أو أدخل الكود يدوياً.', 'Try again in a moment, or type the code instead.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 22),
              if (denied)
                FilledButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings_rounded),
                  label: Text(t('فتح الإعدادات', 'Open Settings')),
                ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onManual,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.keyboard_rounded),
                label: Text(t('أدخل الكود يدوياً', 'Enter the code instead')),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
