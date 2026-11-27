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
  // ── radios / location (v2: say exactly what to switch on) ──────────────
  'att_err_gps_off': ('الموقع (GPS) مغلق — شغّله ثم ارجع وسنكمل تلقائياً',
      'Location (GPS) is off — switch it on and come back, we\'ll continue automatically'),
  'att_err_wifi_off': ('اتصل بشبكة Wi-Fi القاعة — المعلّم يتحقق من الشبكة',
      'Connect to the classroom Wi-Fi — your teacher checks the network'),
  'att_err_bluetooth_off': ('البلوتوث مغلق — نحتاجه للوصول لهاتف زميل قريب',
      'Bluetooth is off — we need it to reach a classmate\'s phone nearby'),
  'att_err_radios_off': ('بعض الإعدادات مغلقة — شغّلها من الأزرار بالأسفل وسنكمل تلقائياً',
      'A few settings are off — switch them on below and we\'ll continue automatically'),
  'att_err_location_denied': ('اسمح للتطبيق بمعرفة موقعك أثناء الاستخدام لتسجيل الحضور',
      'Allow location while using the app to check in'),
  'att_err_location_denied_forever': ('إذن الموقع مرفوض — افتح الإعدادات واسمح به',
      'Location permission is blocked — open Settings and allow it'),
  'att_err_no_fix': ('تعذّر تحديد موقعك داخل المبنى — اقترب من نافذة أو اتصل بشبكة القاعة وحاول مجدداً',
      'We couldn\'t get your location indoors — move near a window or join the classroom Wi-Fi and retry'),
  'att_turn_on_gps': ('تشغيل الموقع', 'Turn on location'),
  'att_turn_on_wifi': ('الاتصال بالـ Wi-Fi', 'Connect to Wi-Fi'),
  'att_turn_on_bluetooth': ('تشغيل البلوتوث', 'Turn on Bluetooth'),
  'att_fix_auto_continue': ('بعد التشغيل ارجع للتطبيق — سنكمل تسجيل حضورك تلقائياً',
      'Come back after switching it on — we\'ll finish your check-in automatically'),
  'att_radio_hint_ios': ('اسحب من أعلى يمين الشاشة لمركز التحكم وشغّله من هناك',
      'Swipe down from the top-right corner to Control Center and switch it on there'),
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
    'لم نجد زميلاً متصلاً بالإنترنت قريباً منك. اطلب من زميل متصل أن يفتح شاشة تسجيل الحضور (أو يفعّل "ساعد زملاءك") وتأكد من تشغيل الموقع والبلوتوث في الجهازين.',
    'No connected classmate found nearby. Ask an online classmate to open the attendance sheet (or turn on "Help classmates"), and make sure Bluetooth and Location are on for both phones.'
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
  // ── classmate signals / launcher / offline tab ────────────────────────
  'att_stage_witness': ('إشارات الزملاء القريبين', 'Signals from nearby classmates'),
  'att_witness_progress': ('إشارات الزملاء: {x} من {n}', 'Classmate signals: {x} of {n}'),
  'att_need_mates': (
    'المعلّم يطلب إشارة من {n} زميل قريب. اطلب منهم فتح التطبيق وتفعيل "ساعد زملاءك".',
    'Your teacher requires signals from {n} nearby classmate(s). Ask them to open the app with "Help classmates" on.'
  ),
  'att_err_witnesses': (
    'لم نجد العدد المطلوب من الزملاء القريبين. اقتربوا من بعضكم وأعد المحاولة.',
    'Not enough nearby classmates answered. Move closer together and try again.'
  ),
  'att_reason_not_enough_witnesses': (
    'عدد إشارات الزملاء غير كافٍ', 'Not enough classmate signals'),
  'att_t_witnesses': ('عدد الزملاء المطلوبين لكل طالب', 'Classmates required per student'),
  'att_t_witnesses_hint': (
    'الافتراضي 0 = بدون إشارات زملاء', 'Default 0 = no classmate signals'),
  'att_visible_yes': ('هاتفك ظاهر للزملاء القريبين', 'Your phone is visible to nearby classmates'),
  'att_visible_no': ('هاتفك غير ظاهر للزملاء حالياً', 'Your phone is not visible to classmates right now'),
  'att_t_relay_on': (
    'هاتفك يستقبل حضور الطلاب غير المتصلين القريبين ويرسله للخادم',
    'Your phone is receiving check-ins from nearby offline students and sending them to the server'
  ),
  'att_t_relay_off': (
    'هاتفك غير ظاهر للطلاب غير المتصلين (فعّل البلوتوث والموقع)',
    'Your phone is not visible to offline students (turn on Bluetooth and Location)'
  ),
  'att_launch_btn': ('بدء أخذ الحضور', 'Start attendance'),
  'att_launch_title': ('اختر المحاضرة', 'Choose the lesson'),
  'att_launch_today': ('اليوم', 'Today'),
  'att_launch_next': ('التالية', 'Next'),
  'att_launch_empty': ('لا توجد محاضرات بعد', 'No lessons yet'),
  'att_tab_downloads': ('التنزيلات', 'Downloads'),
  'att_tab_attendance': ('الحضور', 'Attendance'),
  'att_courses_title': ('كورساتك للحضور', 'Your courses for attendance'),
  'att_courses_empty': (
    'لا توجد كورسات محفوظة. افتح التطبيق مرة واحدة وأنت متصل لتظهر هنا.',
    'No saved courses yet. Open the app once while online and they will appear here.'
  ),
  'att_course_tap': ('اضغط لإدخال كود الحضور', 'Tap to enter the attendance code'),
  // ── settings: method / grace / web / location ─────────────────────────
  'att_sheet_sub_mates': (
    'ابقَ بجانب زملائك — سيتم التحقق من حضورك عبر الأجهزة القريبة',
    'Stay next to your classmates — your presence is verified through nearby phones'
  ),
  'att_need_location': (
    'سيتم التحقق من موقعك (GPS / شبكة الواي فاي)',
    'Your location will be checked (GPS / Wi-Fi)'
  ),
  'att_err_web_not_allowed': (
    'المعلّم لم يسمح بتسجيل الحضور من الويب. استخدم تطبيق الموبايل.',
    'The teacher did not allow web check-in. Use the mobile app.'
  ),
  'att_err_teacher_location': (
    'تعذّر تحديد موقعك. فعّل الموقع أو اتصل بشبكة الواي فاي ثم حاول مرة أخرى.',
    'Could not get your location. Turn on location or join the Wi-Fi and try again.'
  ),
  'att_reason_wrong_location': (
    'أنت خارج نطاق القاعة أو لم يمكن التحقق من موقعك',
    'You are outside the classroom area or your location could not be verified'
  ),
  'att_t_method': ('طريقة التحقق من الطلاب', 'How to identify students'),
  'att_t_method_hint': (
    'الكود، أو عدد من الزملاء القريبين، أو الاثنان معاً',
    'The code, a number of nearby classmates, or both'
  ),
  'att_method_code': ('الكود', 'Code'),
  'att_method_witnesses': ('الزملاء', 'Classmates'),
  'att_method_both': ('الكود + الزملاء', 'Code + classmates'),
  'att_t_grace': ('مهلة الإغلاق', 'Closing grace'),
  'att_t_grace_hint': (
    'بعد الإغلاق يظل النظام يقبل الطلبات المتأخرة لهذه المدة',
    'After closing, late requests are still accepted for this long'
  ),
  'att_t_seconds': ('{n} ث', '{n} s'),
  'att_t_allow_web': ('السماح بالتسجيل من الويب', 'Allow check-in from the web'),
  'att_t_allow_web_hint': (
    'عند الإيقاف: الحضور من تطبيق الموبايل فقط',
    'When off: students can check in from the mobile app only'
  ),
  'att_t_location': ('التحقق من الموقع', 'Check location'),
  'att_t_location_hint': (
    'يجب أن يكون الطالب قرب موقعك (GPS) أو على نفس شبكة الواي فاي',
    'Students must be near you (GPS) or on the same Wi-Fi'
  ),
  'att_t_meters': ('{n} م', '{n} m'),
  'att_t_move_hint': (
    'يمكنك مغادرة هذه الشاشة — سيبقى الكود ظاهراً في الشريط العلوي',
    'You can leave this screen — the code stays visible in the top bar'
  ),
  'att_t_closing': ('يُغلق خلال {n} ثانية…', 'Closing in {n} s…'),
  'att_t_new': ('بدء حضور جديد', 'Start a new attendance'),
  'att_entry_open': ('الحضور مفتوح الآن', 'Attendance is open now'),
  'att_entry_closed': ('لا يوجد حضور مفتوح', 'No attendance open'),
  'att_t_running': ('الحضور يعمل الآن', 'Attendance is running'),
  'att_t_entry_sub': ('ابدأ جلسة حضور لإحدى المحاضرات', 'Start an attendance for a lesson'),
  'att_banner_tap': ('اضغط للفتح', 'Tap to open'),
  'att_err_unsupported_ios': (
    'هذا الجهاز لا يدعم الاتصال بالأجهزة القريبة حالياً',
    'This device cannot connect to nearby phones right now'
  ),
  // ── distance, web location, full screen ─────────────────────────────────
  'att_t_distance': ('أقصى مسافة مسموحة من المعلّم', 'Maximum distance from the teacher'),
  'att_t_distance_hint': (
    'الـ GPS داخل القاعات قد يخطئ 10–50 متراً، فلا تجعل المسافة صغيرة جداً',
    'Indoor GPS can be off by 10–50 m, so do not set the distance too small'
  ),
  'att_t_location_hint_web': (
    'على الويب الموقع تقريبي. يمكنك استخدام موقع المتصفح أو موقع مشارَك من الموبايل.',
    'On the web the location is rough. Use the browser location or one shared from your phone.'
  ),
  'att_t_web_loc_title': ('من أين نأخذ موقع القاعة؟', 'Where should the classroom location come from?'),
  'att_t_web_loc_body': (
    'المتصفح يعطي موقعاً تقريبياً (قد يخطئ بمئات الأمتار). الأدق أن تشارك موقعك من تطبيق الموبايل ثم تعود هنا.',
    'The browser gives a rough location (it can be off by hundreds of metres). It is more accurate to share your position from the mobile app and come back here.'
  ),
  'att_t_web_loc_browser': ('استخدم موقع المتصفح', 'Use browser location'),
  'att_t_web_loc_mobile': ('موقع مشارَك من الموبايل', 'Location shared from mobile'),
  'att_t_shared_found': ('تم العثور على موقع مشارَك من الموبايل', 'A location shared from your phone was found'),
  'att_t_shared_missing': (
    'لا يوجد موقع مشارَك. افتح التطبيق على الموبايل واضغط «مشاركة الموقع للويب».',
    'Nothing shared yet. Open the mobile app and tap "Share location for web".'
  ),
  'att_t_shared_check': ('تحقّق', 'Check'),
  'att_t_share_for_web': ('مشاركة الموقع للويب', 'Share location for web'),
  'att_t_shared_done': ('تمت المشاركة (صالحة 10 دقائق)', 'Shared (valid for 10 minutes)'),
  'att_err_no_shared_location': (
    'لا يوجد موقع مشارَك من الموبايل. شاركه من التطبيق أو استخدم موقع المتصفح.',
    'No location shared from mobile. Share it from the app or use the browser location.'
  ),
  'att_t_fullscreen': ('عرض الكود بملء الشاشة', 'Show code full screen'),
  'att_t_minimize': ('تصغير', 'Minimize'),
  'att_t_reg_left': ('الوقت المتبقي للتسجيل', 'Registration closes in'),
  'att_t_close_confirm': ('إغلاق التسجيل؟', 'Close registration?'),
  'att_t_close_confirm_body': (
    'سيُغلق التسجيل الآن، مع قبول الطلبات المتأخرة لمدة {n} ثانية.',
    'Registration closes now; late requests are still accepted for {n} s.'
  ),
  'att_cancel': ('إلغاء', 'Cancel'),
  // ── radios, push-driven location sharing ─────────────────────────────
  'att_radio_on': ('يعمل', 'On'),
  'att_radio_off': ('متوقف — اضغط', 'Off — tap'),
  'att_radio_hint': (
    'فعّله من الإعدادات السريعة للهاتف (لا يمكن للتطبيق تشغيله بنفسه)',
    'Turn it on from the phone\'s quick settings (an app cannot switch it on by itself)'
  ),
  'att_t_shared_auto': ('تمت مشاركة موقعك مع نسخة الويب', 'Your location was shared with the web app'),
  'att_t_web_asks_title': ('نسخة الويب تطلب موقعك', 'The web app is asking for your location'),
  'att_t_web_asks_body': (
    'نسخة الويب تحتاج موقع القاعة من هاتفك لبدء الحضور.',
    'The web app needs the classroom location from your phone to start attendance.'
  ),
  'att_t_share_now': ('شارك الآن', 'Share now'),
  'att_later': ('لاحقاً', 'Later'),
  'att_t_waiting_mobile': ('بانتظار هاتفك… سيتم إرسال الموقع تلقائياً', 'Waiting for your phone… it will send the location by itself'),
  'att_t_ask_phone': ('اطلب من الهاتف', 'Ask phone'),
  'att_err_no_mobile_device': (
    'لا يوجد هاتف مسجّل لحسابك. افتح التطبيق على الموبايل مرة واحدة.',
    'No phone is registered for your account. Open the mobile app once.'
  ),
  'att_err_mobile_no_answer': (
    'لم يرد الهاتف. افتح التطبيق على الموبايل واضغط «مشاركة الموقع للويب».',
    'The phone did not answer. Open the mobile app and tap "Share location for web".'
  ),
  // ── T1 class (sidecar docs/redesign/strings/t1_class.json) ──
  't1_cl_take_title': ('خذ الحضور', 'Take attendance'),
  't1_cl_one_of_three': ('طريقة وحدة من ثلاث', 'One of three ways'),
  't1_cl_pick_lesson': ('اختر المحاضرة', 'Pick the lesson'),
  't1_cl_how': ('كيف تبي تاخذه؟', 'How do you want to take it?'),
  't1_cl_m_code': ('كود على الشاشة', 'Code on the screen'),
  't1_cl_m_code_d': ('للقاعة والبروجكتر: كود من ٦ أرقام يتغيّر كل فترة قصيرة', 'For the hall and the projector: a 6-digit code that keeps changing'),
  't1_cl_m_qr': ('رمز QR', 'QR code'),
  't1_cl_m_qr_d': ('يمسحه الطلاب بجوالاتهم، ويشتغل لو النت ضعيف', 'Students scan it with their phones, and it works on a weak connection'),
  't1_cl_m_manual': ('تسجيل يدوي', 'Manual'),
  't1_cl_m_manual_d': ('تحدد الحاضر والغايب بنفسك من القائمة', 'You mark who is present and absent from the list yourself'),
  't1_cl_start': ('ابدأ الحضور', 'Start attendance'),
  't1_cl_left': ('باقي {t}', '{t} left'),
  't1_cl_open_live': ('الحضور مفتوح', 'Attendance is open'),
  't1_cl_code_instruction': ('افتح الدورة في جوالك واكتب الكود', 'Open the course on your phone and type the code'),
  't1_cl_qr_instruction': ('امسح الرمز بجوالك لتسجيل حضورك', 'Scan the code with your phone to check in'),
  't1_cl_code_change': ('يتغيّر الكود خلال {n} ث', 'The code changes in {n} s'),
  't1_cl_hall_only': ('اعرض هالشاشة داخل القاعة بس', 'Show this screen inside the hall only'),
  't1_cl_scan_title': ('امسح للحضور، {lesson}', 'Scan to check in, {lesson}'),
  't1_cl_scan_plain': ('امسح للحضور', 'Scan to check in'),
  't1_cl_open_tag': ('مفتوح', 'Open'),
  't1_cl_qr_renews': ('الرمز يتجدد خلال {n} ث', 'The code renews in {n} s'),
  't1_cl_offline_note': ('هاتفك يستقبل حضور الطلاب غير المتصلين ويرفعه أول ما يرجع النت.', 'Your phone receives the check-ins of offline students and uploads them as soon as it is back online.'),
  't1_cl_manual_title': ('تسجيل يدوي، {lesson}', 'Manual attendance, {lesson}'),
  't1_cl_group_students': ('طلاب المجموعة', 'Group students'),
  't1_cl_present': ('حاضر', 'Present'),
  't1_cl_absent': ('غايب', 'Absent'),
  't1_cl_all_present': ('الكل حاضر', 'All present'),
  't1_cl_all_absent': ('الكل غايب', 'All absent'),
  't1_cl_search': ('ابحث عن طالب...', 'Search for a student...'),
  't1_cl_save': ('حفظ الحضور', 'Save attendance'),
  't1_cl_no_changes': ('كل المجموعة، بدون تعديلات', 'The whole group, no edits'),
  't1_cl_duration_min': ('مدة الحضور {n} د', 'Time in class {n} min'),
  't1_cl_no_show': ('ما دخل الحصة', 'Did not join the lesson'),
};
