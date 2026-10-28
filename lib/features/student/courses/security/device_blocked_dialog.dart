/// features/shared/device/device_blocked_dialog.dart
///
/// Show it when login / any request says the device is not the registered one:
///
///   final p = DeviceSecurityProvider();
///   if (!await p.check()) await showDeviceBlockedDialog(context, p);
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import 'device_security_provider.dart';

Future<void> showDeviceBlockedDialog(BuildContext context, DeviceSecurityProvider p,
    { int? courseId}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DeviceBlockedDialog(p: p, courseId: courseId),
  );
}

class _DeviceBlockedDialog extends StatefulWidget {
  final DeviceSecurityProvider p;
  final int? courseId;
  const _DeviceBlockedDialog({required this.p, this.courseId});

  @override
  State<_DeviceBlockedDialog> createState() => _DeviceBlockedDialogState();
}

class _DeviceBlockedDialogState extends State<_DeviceBlockedDialog> {
  bool _busy = false;
  bool _sent = false;
  String? _msg;

  Future<void> _send() async {
    setState(() => _busy = true);
    final ok = await widget.p.sendSwitchRequest( widget.courseId??-1);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = ok;
      _msg = ok ? 'dev_request_sent'.tr : (widget.p.switchError ?? 'dev_send_failed'.tr);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.p;
    final String body;
    if (p.hasPending || _sent) {
      body = 'dev_pending_body'.tr;
    } else if (p.switchUsedThisMonth) {
      body = 'dev_used_this_month_body'.tr;
    } else {
      body = 'dev_blocked_body'.tr;
    }
    final canSend = p.canRequest && !p.hasPending && !_sent;

    return Directionality(
      textDirection: pageDirection,   // was always RTL, also in English
      child: AlertDialog(
        scrollable: true,
        backgroundColor: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          Icon(Icons.phonelink_lock_rounded, color: c.danger),
          const SizedBox(width: 8),
          Expanded(child: Text('dev_blocked_title'.tr, style: c.h3)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Align(alignment: AlignmentDirectional.centerStart, child: Text(body, style: c.body)),
          if (_msg != null) ...[const SizedBox(height: 10), Text(_msg!, style: c.caption.copyWith(color: context.colors.danger,fontSize: 14,fontWeight: FontWeight.w600))],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('dev_close'.tr)),
          if (canSend)
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('dev_send_request'.tr),
            ),
        ],
      ),
    );
  }
}