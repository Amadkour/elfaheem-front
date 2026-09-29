/// features/shared/device/device_blocked_dialog.dart
///
/// Show it when login / any request says the device is not the registered one:
///
///   final p = DeviceSecurityProvider();
///   if (!await p.check()) await showDeviceBlockedDialog(context, p);
library;

import 'package:flutter/material.dart';
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
  String? _msg;

  Future<void> _send() async {
    setState(() => _busy = true);
    final ok = await widget.p.sendSwitchRequest( widget.courseId??-1);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = ok ? 'تم إرسال الطلب إلى المدرس. سيتم إشعارك بعد الموافقة.' :(widget.p.switchError?? 'تعذر إرسال الطلب، حاول مرة أخرى.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.p;
    final String body;
    if (p.hasPending || _msg != null && _msg!.startsWith('تم')) {
      body = 'لديك طلب تغيير جهاز قيد المراجعة عند المدرس.';
    } else if (p.switchUsedThisMonth) {
      body = 'هذا الحساب مسجّل على جهاز آخر، وقد استخدمت طلب تغيير الجهاز لهذا الشهر. '
          'يمكنك إرسال طلب جديد في الشهر القادم.';
    } else {
      body = 'هذا الحساب مسجّل على جهاز آخر، ولا يمكن المشاهدة إلا من الجهاز الذي سجّلت ودفعت منه.\n\n'
          'إذا كان هذا جهازك الجديد يمكنك إرسال طلب للمدرس لنقل الحساب (مرة واحدة كل شهر).';
    }
    final canSend = p.canRequest && !p.hasPending && !(_msg?.startsWith('تم') ?? false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          Icon(Icons.phonelink_lock_rounded, color: c.danger),
          const SizedBox(width: 8),
          Expanded(child: Text('جهاز غير مسموح به', style: c.h3)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Align( alignment:Alignment.centerRight ,child: Text(body, style: c.body)),
          if (_msg != null) ...[const SizedBox(height: 10), Text(_msg!, style: c.caption.copyWith(color: Colors.red,fontSize: 14,fontWeight: FontWeight.w600))],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق')),
          if (canSend)
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('إرسال طلب للمدرس'),
            ),
        ],
      ),
    );
  }
}
