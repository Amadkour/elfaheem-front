// Web: Page Visibility, focus / blur, full-screen and copy / paste events → integrity signals.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../admin/admin_common.dart' show t;

final List<(String, JSFunction)> _docListeners = [];
final List<(String, JSFunction)> _winListeners = [];

void attach(void Function(String kind, Map<String, dynamic> meta) onEvent) {
  detach();
  void doc(String name, void Function(web.Event) fn) {
    final js = fn.toJS;
    web.document.addEventListener(name, js);
    _docListeners.add((name, js));
  }
  void win(String name, void Function(web.Event) fn) {
    final js = fn.toJS;
    web.window.addEventListener(name, js);
    _winListeners.add((name, js));
  }
  doc('visibilitychange', (_) {
    if (web.document.hidden) onEvent('tab_switch', {'via': 'visibility'});
  });
  win('blur', (_) => onEvent('tab_switch', {'via': 'blur'}));
  doc('fullscreenchange', (_) {
    if (web.document.fullscreenElement == null) onEvent('fullscreen_exit', {});
  });
  doc('copy', (_) => onEvent('copy_paste', {'op': 'copy'}));
  doc('paste', (_) => onEvent('copy_paste', {'op': 'paste'}));
  doc('cut', (_) => onEvent('copy_paste', {'op': 'cut'}));
}

void detach() {
  for (final (name, js) in _docListeners) {
    web.document.removeEventListener(name, js);
  }
  for (final (name, js) in _winListeners) {
    web.window.removeEventListener(name, js);
  }
  _docListeners.clear();
  _winListeners.clear();
}

List<String> capabilities() => [
      t('يُسجَّل تبديل النوافذ أو التبويبات والخروج من ملء الشاشة', 'Switching tabs or windows and leaving full screen are recorded'),
      t('تُسجَّل محاولات النسخ واللصق', 'Copy and paste attempts are recorded'),
      t('لا يمكن منع لقطات الشاشة في المتصفح — تُسجَّل الإشارات فقط', 'Screenshots cannot be prevented in a browser — only the signals are recorded'),
    ];
