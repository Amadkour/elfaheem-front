/// features/attendance/attendance_strings.dart
///
/// Same idea as `offlineT`: tries translation.json (`'key'.tr`) first and falls back to the
/// built-in Arabic / English text, so the UI never shows a raw key. The same keys are also
/// provided in `translation_attendance.json` — merge them into assets/translation.json.
library;

import 'package:flutter_education_app/config/app_config.dart';

String attT(String key, {Map<String, String>? args}) {
  var v = key.tr;
  if (v.isEmpty || v == key) {
    final pair = _fallback[key];
    v = pair == null ? key : (AppConfig.lang == 'ar' ? pair.$1 : pair.$2);
  }
  args?.forEach((k, val) => v = v.replaceAll('{$k}', val));
  return v;
}

/// key -> (Arabic, English)
const Map<String, (String, String)> _fallback = {
  // ── student: entry points ─────────────────────────────────────────────
  'att_btn_checkin': ('تسجيل الحضور', 'Check in'),
  'att_btn_checkin_now': ('سجّل حضورك الآن', 'Check in now'),
  'att_btn_checkin_offline': ('حضور عبر زميل', 'Check in via classmate'),
  'att_btn_live': ('مفتوح', 'OPEN'),
  'att_sheet_title': ('تسجيل حضور المحاضرة', 'Lesson attendance'),
  'att_sheet_sub': (
    'اكتب الكود الظاهر على شاشة المعلّم داخل القاعة',
    'Enter the code shown on the teacher\'s screen in the hall'
  ),
  'att_code_hint': ('الكود المكوّن من 6 أرقام', '6-digit code'),
  'att_submit': ('تأكيد الحضور', 'Confirm attendance'),
  'att_retry': ('حاول مرة أخرى', 'Try again'),
  'att_done': ('تم', 'Done'),

  // ── student: progress stages ──────────────────────────────────────────
  'att_stage_net': ('فحص الاتصال بالإنترنت', 'Checking internet'),
  'att_stage_perm': ('أذونات البلوتوث والأجهزة القريبة', 'Bluetooth & nearby permissions'),
  'att_stage_relay': ('البحث عن زميل متصل بالإنترنت', 'Looking for a connected classmate'),
  'att_stage_send': ('إرسال الطلب عبر الزميل', 'Sending the request via your classmate'),
  'att_stage_server': ('تأكيد الخادم', 'Server confirmation'),
  'att_online_direct': ('أنت متصل — يتم الإرسال مباشرة', 'You are online — sending directly'),
  'att_offline_relay': (
    'أنت غير متصل — سنستخدم زميلاً قريباً متصلاً بالإنترنت',
    'You are offline — we will use a nearby classmate who is online'
  ),

  // ── student: outcomes ─────────────────────────────────────────────────
  'att_ok_title': ('تم تسجيل حضورك', 'You are marked present'),
  'att_ok_body': ('أكّد الخادم حضورك في {time}', 'The server confirmed your attendance at {time}'),
  'att_ok_via': ('عبر زميلك', 'via your classmate'),
  'att_rej_title': ('لم يتم قبول الحضور', 'Attendance was not accepted'),
  'att_reason_wrong_code': (
    'الكود غير صحيح أو انتهت صلاحيته. اكتب الكود الحالي من شاشة المعلّم.',
    'The code is wrong or has expired. Enter the current code from the teacher\'s screen.'
  ),
  'att_reason_session_closed': ('أُغلقت جلسة الحضور', 'The attendance window is closed'),
  'att_reason_not_enrolled': ('أنت غير مسجّل في هذا الكورس', 'You are not enrolled in this course'),
  'att_pending_title': ('الطلب محفوظ بانتظار التأكيد', 'Request saved, waiting for confirmation'),
  'att_pending_body': (
    'لم يصلنا ردّ الخادم بعد. سيُعاد إرسال نفس الطلب تلقائياً عند توفر الإنترنت دون تسجيل مكرّر. لن يُعتبر حضورك مسجّلاً قبل تأكيد الخادم.',
    'We have not received the server\'s answer yet. The same request is re-sent automatically when you are online, without a duplicate record. You are NOT counted present until the server confirms.'
  ),

  // ── student: errors ───────────────────────────────────────────────────
  'att_err_code_format': ('اكتب 6 أرقام', 'Enter 6 digits'),
  'att_err_no_key': (
    'افتح التطبيق وأنت متصل بالإنترنت مرة واحدة على الأقل ثم أعد المحاولة',
    'Open the app while online at least once, then try again'
  ),
  'att_err_no_window': (
    'لا توجد جلسة حضور مفتوحة لهذه المحاضرة الآن',
    'There is no open attendance window for this lesson right now'
  ),
  'att_err_unsupported': (
    'تسجيل الحضور عبر زميل غير متاح على هذا الجهاز. اتصل بالإنترنت وسجّل مباشرة.',
    'Relay check-in is not available on this device. Connect to the internet and check in directly.'
  ),
  'att_err_perm': (
    'نحتاج إذن "الأجهزة القريبة/البلوتوث" لإيجاد زميل متصل',
    'We need the "Nearby devices / Bluetooth" permission to find a connected classmate'
  ),
  'att_err_perm_settings': ('فتح الإعدادات', 'Open settings'),
  'att_err_bluetooth': (
    'شغّل البلوتوث (والموقع في الأجهزة القديمة) ثم أعد المحاولة. لا يمكن للتطبيق تشغيله نيابةً عنك.',
    'Turn Bluetooth on (and Location on older phones), then try again. The app cannot switch it on for you.'
  ),
  'att_err_no_relay': (
    'لم نجد زميلاً متصلاً بالإنترنت قريباً منك. اطلب من زميل أن يفتح التطبيق ويفعّل "ساعد زملاءك".',
    'No connected classmate found nearby. Ask a classmate to open the app and turn on "Help classmates".'
  ),
  'att_err_forged': (
    'ردّ غير موثوق: لم يتم التحقق من توقيع الخادم، لذلك لن يُعتبر الحضور مسجّلاً.',
    'Untrusted reply: the server signature did not verify, so attendance is NOT counted.'
  ),
  'att_err_generic': ('حدث خطأ، حاول مرة أخرى', 'Something went wrong, please try again'),
  'att_err_invalid_signature': (
    'تعذّر التحقق من جهازك. سجّل الدخول وأنت متصل ثم أعد المحاولة.',
    'Your device could not be verified. Sign in while online and try again.'
  ),
  'att_err_relay_not_allowed': (
    'الزميل الوسيط غير مسجّل في هذا الكورس. جرّب زميلاً آخر.',
    'That classmate is not enrolled in this course. Try another one.'
  ),

  // ── relay (online student helping others) ─────────────────────────────
  'att_relay_title': ('ساعد زملاءك', 'Help classmates'),
  'att_relay_sub': (
    'اسمح لزملائك غير المتصلين بتسجيل حضورهم عبر هاتفك. لا نقرأ بياناتهم ولا نستطيع تغيير نتيجتهم.',
    'Let offline classmates check in through your phone. We cannot read their data or change their result.'
  ),
  'att_relay_on': ('هاتفك جاهز لمساعدة زملائك', 'Your phone is ready to help classmates'),
  'att_relay_helped': ('ساعدت {n} زميلاً', 'You helped {n} classmates'),
  'att_relay_need_online': ('يلزم اتصال بالإنترنت', 'Internet connection required'),

  // ── teacher ───────────────────────────────────────────────────────────
  'att_t_btn': ('بدء تسجيل الحضور', 'Start attendance'),
  'att_t_title': ('حضور المحاضرة', 'Lesson attendance'),
  'att_t_duration': ('مدة فتح التسجيل', 'Open for'),
  'att_t_minutes': ('{n} دقيقة', '{n} min'),
  'att_t_start': ('فتح التسجيل', 'Open attendance'),
  'att_t_show': (
    'اعرض هذه الشاشة داخل القاعة فقط — الكود يتغيّر تلقائياً ولا يصلح خارجها.',
    'Show this screen inside the hall only — the code rotates and is useless elsewhere.'
  ),
  'att_t_present': ('الحاضرون', 'Present'),
  'att_t_next_code': ('يتغيّر الكود خلال {n} ث', 'Code changes in {n}s'),
  'att_t_close': ('إغلاق التسجيل', 'Close attendance'),
  'att_t_closed': ('تم إغلاق التسجيل', 'Attendance closed'),
  'att_t_expired': ('انتهت مدة التسجيل', 'The attendance window has ended'),
};
