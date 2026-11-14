// features/shared/notification/admin_message_dialogs.dart
//
// Shows admin messages sent as "dialog" / "dialog with button". Call checkPending():
//   • after login / app start (see _Guard in main.dart)
//   • when the app resumes (WidgetsBindingObserver in ElFaheemApp)
//   • when a push of type admin_message arrives in the foreground (notification_service.dart)
// Never runs while a super-admin is in "view as" mode (it would show — and could not dismiss — someone else's dialogs).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/config/app_config.dart'
    show pageDirection;
import 'package:flutter_education_app/core/api_client.dart';
import '../../../main.dart' show navigatorKey;
import '../../../utils/widget/app_navigator.dart';
import '../../../utils/widget/view_as_state.dart';
import 'package:flutter_education_app/features/courses/student/details/growth_tr.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

class AdminMessageDialogs {
  AdminMessageDialogs._();

  static bool _busy = false;
  static bool _again =
      false; // a push arrived while a dialog was open → check once more afterwards

  static Future<void> checkPending() async {
    if (ViewAsState.active) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      final r = await ApiClient().get('/api/v1/messages/pending-dialogs');
      final items = (r is Map ? r['items'] : null) as List? ?? const [];
      for (final raw in items) {
        final ctx = navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) break;
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        try {
          final goTo = await _show(ctx, m);
          // mark seen BEFORE navigating so a crash in the target screen can't re-show it forever
          try {
            await ApiClient().post(
              '/api/v1/messages/dialogs/${m['recipient_id']}/seen',
            );
          } catch (_) {}
          if (goTo) {
            await AppNavigator.openModule(
              m['module']?.toString(),
              targetId: int.tryParse('${m['target_id'] ?? ''}'),
            );
          }
        } catch (_) {
          // one broken message must not block the ones after it
        }
      }
    } catch (_) {
      // dialogs are best-effort
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        checkPending();
      }
    }
  }

  /// true → the user pressed the action button.
  static Future<bool> _show(
    BuildContext context,
    Map<String, dynamic> m,
  ) async {
    final c = context.colors;
    final hasAction = m['has_action'] == true;
    final label = (m['label'] as String?)?.trim();
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: !hasAction,
      builder: (ctx) => Directionality(
        textDirection: pageDirection,
        // the app's MaterialApp is LTR; Arabic dialogs must be RTL
        // paper, radius 28, an editorial headline under a sky mark (the message is information, D-613)
        child: AlertDialog(
          backgroundColor: c.cardBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sheet),
          ),
          icon: Container(
            width: AppTouch.primary,
            height: AppTouch.primary,
            decoration: BoxDecoration(color: c.blockSky, shape: BoxShape.circle),
            child: Icon(Icons.campaign_rounded, color: c.blockAccentInk(c.primary, c.blockSky), size: AppIconSize.xl - 4),
          ),
          title: Text(
            '${m['title']}',
            textAlign: TextAlign.center,
            style: AppType.headline(ctx),
          ),
          content: SingleChildScrollView(
            child: Text(
              '${m['body']}',
              textAlign: TextAlign.center,
              style: AppType.body(ctx).copyWith(color: c.textMedium, height: 1.6),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(gt('إغلاق', 'Close')),
            ),
            if (hasAction)
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  (label != null && label.isNotEmpty)
                      ? label
                      : gt('فتح', 'Open'),
                ),
              ),
          ],
        ),
      ),
    );
    return res == true;
  }
}
