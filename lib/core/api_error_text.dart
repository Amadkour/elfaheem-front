/// Bilingual text for the server's coded errors outside the organization screens (those have `orgErrorText`).
///
/// The backend answers `{detail: {code, message, ...}}`; `message` is Arabic. Every code the auth / account
/// endpoints can send gets an Arabic and an English sentence here, with the extra numbers the server attaches
/// (`retry_after_minutes`, `retry_after_seconds`, `attempts_left`). Unknown codes fall back to the server message.
library;

import '../config/app_config.dart';
import 'api_client.dart';
import 'app_time.dart';
import 'course_access.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// `detail` of a coded error body, or an empty map.
Map<String, dynamic> apiErrorDetail(ApiException e) {
  final d = ApiException.asMap(e.body)?['detail'];
  return d is Map ? d.map((k, v) => MapEntry('$k', v)) : const <String, dynamic>{};
}

/// How long the client should wait after a 429, when the server said so.
Duration? apiRetryAfter(ApiException e) {
  final d = apiErrorDetail(e);
  final s = int.tryParse('${d['retry_after_seconds'] ?? ''}');
  if (s != null && s > 0) return Duration(seconds: s);
  final m = int.tryParse('${d['retry_after_minutes'] ?? ''}');
  if (m != null && m > 0) return Duration(minutes: m);
  return null;
}

/// An ISO instant as UTC (no offset = UTC), or null.
DateTime? _utc(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  final s = v.trim();
  final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

String _wait(Duration? d) {
  if (d == null) return '';
  if (d.inMinutes >= 1) return ' (${_t('${d.inMinutes} دقيقة', '${d.inMinutes} min')})';
  return ' (${_t('${d.inSeconds} ثانية', '${d.inSeconds} s')})';
}

/// The sentence for a 403 `feature_disabled` {feature} refusal (D-781): the Super Admin's AI controls by name, any
/// other kill-switch key in general words. Used by [apiErrorText], `orgErrorText` and the assistant's `ragCodeText`.
String featureDisabledText(String? feature) => switch (feature) {
      'exam.auto_create' => _t('إنشاء الأسئلة بالذكاء الاصطناعي متوقف حالياً من إدارة المنصة — اكتب الأسئلة بنفسك',
          'AI question generation is switched off by the platform right now — write the questions yourself'),
      'exam.auto_grade' => _t('التصحيح بالذكاء الاصطناعي متوقف حالياً — الإجابات المكتوبة محفوظة لتصححها يدوياً',
          'AI grading is switched off right now — the written answers are kept for you to mark by hand'),
      'exam.auto_correct' => _t('التصحيح التلقائي لأوراق التظليل متوقف حالياً من إدارة المنصة — لم يُحذف شيء',
          'Automatic bubble-sheet correction is switched off by the platform right now — nothing was deleted'),
      'rag.app_assistant' => _t('مساعد التطبيق متوقف حالياً من إدارة المنصة', 'The app assistant is switched off by the platform right now'),
      'rag.assistant' => _t('المساعد الذكي متوقف حالياً من إدارة المنصة', 'The AI assistant is switched off by the platform right now'),
      'rag.learning' => _t('التعلم من الملاحظات متوقف حالياً من إدارة المنصة', 'Learning from feedback is switched off by the platform right now'),
      _ => _t('هذه الميزة متوقفة حالياً من إدارة المنصة', 'This feature is switched off by the platform right now'),
    };

/// A coupon refusal (Games v3, CONTRACT §7: POST /coupons/quote and the three checkouts), null = not a coupon code.
/// [d] is the error's `detail` (`min_order`, `expected`).
String? couponErrorText(String? code, [Map<String, dynamic> d = const {}]) {
  String money(Object? v) {
    final n = v is num ? v : num.tryParse('${v ?? ''}');
    if (n == null) return '';
    return n == n.truncate() ? '${n.toInt()}' : n.toStringAsFixed(2);
  }

  switch (code) {
    case 'coupon_not_found':
      return _t('لا توجد قسيمة بهذا الرمز — تأكد من الأحرف', 'No coupon has this code — check the letters');
    case 'coupon_not_yours':
      return _t('هذه القسيمة لحساب آخر — القسائم شخصية', 'This coupon belongs to another account — coupons are personal');
    case 'coupon_used':
      return _t('استُخدمت هذه القسيمة من قبل — كل قسيمة تُستخدم مرة واحدة', 'This coupon was already used — each coupon works once');
    case 'coupon_expired':
      return _t('انتهت صلاحية هذه القسيمة', 'This coupon has expired');
    case 'coupon_revoked':
      return _t('أُلغيت هذه القسيمة من إدارة المنصة', 'The platform cancelled this coupon');
    case 'coupon_not_applicable':
      return _t('لا تنطبق هذه القسيمة على هذا الشراء', 'This coupon does not apply to this purchase');
    case 'coupon_locked': // a friends reward (Games v4): it opens when the invited friends join
      return _t('تُفتح هذه المكافأة بعد انضمام أصدقائك', 'This reward opens after your friends join');
    case 'coupon_wrong_course':
      return _t('هذه المكافأة لدورة أخرى', 'This reward is for a different course');
    case 'coupon_min_order':
      final m = money(d['min_order']);
      return m.isEmpty
          ? _t('المبلغ أقل من الحد الأدنى لهذه القسيمة', 'The amount is below this coupon\'s minimum')
          : _t('تعمل هذه القسيمة على مشتريات من $m فأكثر', 'This coupon works on purchases of $m or more');
    case 'coupon_currency':
      final cur = '${d['expected'] ?? ''}'.trim();
      return cur.isEmpty
          ? _t('عملة هذه القسيمة تختلف عن عملة السعر', 'This coupon is in another currency than the price')
          : _t('هذه القسيمة تعمل بعملة $cur فقط', 'This coupon only works in $cur');
  }
  return null;
}

/// A short sentence in the user's language for any [ApiException]; the server's own text when the code is unknown.
String apiErrorText(ApiException e) {
  final d = apiErrorDetail(e);
  switch (e.code) {
    case 'feature_disabled':                               // the Super Admin's kill switch, enforced by the server
      return featureDisabledText(d['feature']?.toString());
    case 'server_busy':                                    // 503 from the Exam Engine / RAG in-flight cap (D-038)
      return _t(ApiMessages.serverBusyAr, ApiMessages.serverBusyEn);
    case 'image_too_large':
      return _t('الصورة كبيرة جداً — اختر نسخة أصغر', 'This image is too large — choose a smaller copy');
    case 'bad_image':
      return _t('تعذّرت قراءة هذه الصورة — جرّب صورة أخرى', 'This image could not be read — try another one');
    case 'too_many_attempts':
      return _t('محاولات كثيرة — حاول مرة أخرى لاحقاً', 'Too many attempts — try again later') + _wait(apiRetryAfter(e));
    case 'otp_cooldown':
      return _t('تم إرسال رمز للتو — انتظر قليلاً قبل طلب رمز جديد', 'A code was just sent — wait a little before asking for another') +
          _wait(apiRetryAfter(e));
    case 'otp_invalid':
      final left = int.tryParse('${d['attempts_left'] ?? ''}');
      final base = _t('رمز التحقق غير صحيح', 'The verification code is wrong');
      return left == null ? base : '$base ${_t('(متبقٍ $left)', '($left left)')}';
    case 'otp_expired':
      return _t('انتهت صلاحية الرمز — اطلب رمزاً جديداً', 'The code expired — ask for a new one');
    case 'otp_locked':
      return _t('تجاوزت عدد المحاولات — اطلب رمزاً جديداً', 'Too many wrong codes — ask for a new one');
    case 'refresh_invalid':
    case 'refresh_expired':
    case 'refresh_reuse':
      return _t('انتهت الجلسة — سجّل الدخول مرة أخرى', 'Your session ended — please sign in again');
    case 'self_action':
      return _t('لا يمكنك تنفيذ هذا الإجراء على نفسك', 'You can\'t do this to your own record');
    case 'escalation':
      return _t('لا يمكنك منح أو سحب صلاحيات لا تملكها', 'You can\'t grant or remove rights you don\'t hold yourself');
    case 'org_forbidden':
      return _t('لا تملك صلاحية الوصول لهذه المؤسسة', 'You don\'t have access to this organization');
    case 'orgs_disabled':
      return _t('المؤسسات متوقفة حالياً على المنصة', 'Organizations are switched off on the platform right now');
    // booking a Quran program (D-1347): every enrol path and checkout can answer these two
    case 'quran_gender_rule':
      return d['reason'] == 'gender_unknown'
          ? _t('هذا البرنامج يشترط أن يكون المعلم من نفس جنس الطالب. أضف الجنس في ملفك الدراسي ثم احجز.',
              'This program needs a teacher of the student\'s gender. Add your gender in your study profile, then book.')
          : _t('هذا البرنامج يشترط أن يكون المعلم من نفس جنس الطالب. اختر معلماً آخر.',
              'This program needs a teacher of the student\'s gender. Choose another teacher.');
    case 'quran_teacher_unverified':
      return _t('لم تتحقق المنصة من هذا المعلم بعد، فلا يمكن الحجز معه الآن.',
          'The platform has not verified this teacher yet, so booking is not open now.');
    // Learning Hub v2 teachers and packages (D-1620 .., CONTRACT.md §1 / §2)
    case 'no_profile':
      return _t('لم تنشئ ملفك كمعلم بعد', 'You have not created your teacher profile yet');
    case 'profile_incomplete':
      return _t('أكمل ملفك قبل الإرسال: الاسم والجنس ومادة واحدة ونبذة ومستند واحد على الأقل.',
          'Complete your profile before sending it: name, gender, one subject, an introduction and at least one document.');
    case 'profile_locked':
      return _t('ملفك قيد المراجعة الآن، فلا يمكن تعديله حتى يُراجع.', 'Your profile is being reviewed, so it cannot be changed until the review ends.');
    case 'bad_document':
      return _t('الملف ليس صورة ولا PDF صالحاً. اختر ملفاً آخر.', 'The file is not a valid image or PDF. Choose another file.');
    case 'file_too_large':
      return _t('الملف أكبر من 10 ميجابايت', 'The file is larger than 10 MB');
    case 'not_approved':
      return _t('تُفتح الباقات بعد اعتماد ملفك كمعلم من المنصة.', 'Packages open once the platform approves your teacher profile.');
    case 'package_full':
      return _t('اكتملت مقاعد هذه الباقة', 'This package is full');
    case 'package_locked':
      return _t('انضم طلاب لهذه الباقة، فلا يتغير عدد الجلسات ولا الجدول ولا تاريخ البدء.',
          'Students have joined this package, so the sessions, the schedule and the start date can no longer change.');
    case 'package_closed':
      return _t('أُغلقت هذه الباقة', 'This package is closed');
    case 'already_enrolled':
      return _t('أنت مشترك في هذه الباقة بالفعل', 'You are already in this package');
    // Learning Hub v2 final review (D-1646): the rest of the teachers / packages / games / self-learning / series codes
    case 'teacher_only':
      return _t('هذه الصفحة للمعلمين فقط', 'This page is for teachers only');
    case 'students_only':
      return _t('هذا متاح للطلاب فقط', 'This is for students only');
    case 'not_owner':
      return _t('يستطيع صاحبها فقط فعل ذلك', 'Only its owner can do this');
    case 'not_pending':
      return _t('رُوجع هذا الطلب بالفعل — حدّث الصفحة', 'This was already reviewed — refresh the page');
    case 'reason_required':
      return _t('اكتب السبب أولاً', 'Write the reason first');
    case 'not_enrolled':
      return _t('لست مسجلاً هنا', 'You are not enrolled here');
    case 'card_unavailable':
      return _t('بطاقة الدفع غير متاحة الآن — حاول بعد قليل', 'Card payment is not available right now — try again shortly');
    case 'gateway_error':
      return _t('تعذّر الاتصال ببوابة الدفع — لم يُخصم شيء، حاول مرة أخرى', 'The payment gateway could not be reached — nothing was charged, try again');
    case 'not_due':
      return _t('هذه الدفعة ليست بانتظار استرداد', 'This payment is not waiting for a refund');
    case 'bad_rule':
      return _t('قاعدة التكرار غير صالحة — راجع الأيام والوقت وتاريخ البدء', 'The repeat rule is not valid — check the days, the time and the start date');
    case 'no_occurrences':
      return _t('لا تنتج قاعدة التكرار أي موعد — غيّر الأيام أو تاريخ الانتهاء', 'The repeat rule gives no dates — change the days or the end date');
    case 'series_ended':
      return _t('انتهى هذا الاجتماع المتكرر، فلا يمكن تعديله', 'This repeating meeting has ended, so it cannot change');
    case 'series_not_found':
      return _t('هذا الاجتماع المتكرر غير موجود', 'This repeating meeting no longer exists');
    case 'occurrence_cancelled':
      return _t('أُلغي هذا الموعد بالفعل', 'This date was already cancelled');
    case 'occurrence_not_found':
      return _t('هذا الموعد ليس من مواعيد الاجتماع المتكرر', 'This date is not one of the repeating meeting\'s dates');
    case 'bad_from_date':
      return _t('لا يمكن تعديل مواعيد مضت — اختر اليوم أو بعده', 'Past dates cannot change — pick today or later');
    case 'badge_key_taken':
      return _t('هذا المعرّف مستخدم لشارة أخرى', 'Another badge already uses this key');
    case 'badge_not_found':
      return _t('هذه الشارة غير موجودة', 'This badge no longer exists');
    case 'badge_bad_key' || 'badge_bad_name' || 'badge_bad_icon' || 'badge_bad_rule':
      return _t('بيانات الشارة غير صالحة — راجع المعرّف والاسمين والأيقونة والقاعدة',
          'The badge is not valid — check the key, both names, the icon and the rule');
    case 'game_bad_engine':
      return _t('نوع اللعبة غير معروف', 'Unknown game type');
    case 'game_bad_status':
      return _t('حالة اللعبة غير صالحة', 'Not a valid game status');
    case 'game_bad_cover':
      return _t('رابط الغلاف يجب أن يبدأ بـ https://', 'The cover link must start with https://');
    case 'game_bad_order' || 'sl_bad_order':
      return _t('تعذّر حفظ الترتيب — حدّث الصفحة وحاول مرة أخرى', 'The order could not be saved — refresh and try again');
    case 'game_bad_period':
      return _t('الفترة غير صالحة', 'Not a valid period');
    case 'sl_bad_subject':
      return _t('هذه المادة غير متاحة في الدروس اليومية', 'This subject is not offered in daily lessons');
    case 'sl_bad_choice':
      return _t('اختر إجابة من الخيارات', 'Pick one of the options');
    case 'sl_bad_client_id':
      return _t('تعذّر حفظ هذه الإجابة — أجب مرة أخرى', 'This answer could not be saved — answer again');
    case 'sl_bad_item':
      final f = '${d['field'] ?? ''}';
      return _t('بيانات العنصر غير صالحة${f.isEmpty ? '' : ' ($f)'}', 'The item is not valid${f.isEmpty ? '' : ' ($f)'}');
    // the offline outbox (D-1351, D-1352): a write the server refused when it was synced
    case 'sync_stale':
      return _t('تغيّر ملفك الدراسي من جهاز آخر، فلم يُحفظ تعديلك. عرضنا أحدث نسخة — عدّل مرة أخرى.',
          'Your study profile changed on another device, so your edit was not saved. The latest copy is shown — edit it again.');
    case 'sync_too_many':
      return _t('تغييرات كثيرة في دفعة واحدة — ستُرسل على دفعات', 'Too many changes at once — they will be sent in batches');
    case 'sync_bad_since':
      return _t('تعذّرت مزامنة آخر التغييرات — حاول مرة أخرى', 'The latest changes could not be synced — try again');
    case 'sync_bad_op' || 'sync_unknown_kind' || 'sync_error':
      return _t('تعذّر حفظ أمر سجّلته دون اتصال، فحُذف من الانتظار.',
          'Something you did offline could not be saved, so it was dropped from the queue.');
    // a parent's view of a minor's games / Quran / grammar, or a link redeem (D-1311, D-1371)
    case 'consent_required':
      return _t('هذا الطالب دون السن القانونية: يلزم موافقتك كولي أمر أولاً. افتح "أبنائي" واضغط "إعطاء الموافقة".',
          'This student is under the legal age: your consent as their parent is needed first. Open My children and tap Give consent.');
    case 'program_kind_locked':
      return _t('لا يمكن تغيير نوع البرنامج بعد تسجيل طلاب فيه', 'The program type cannot change once the course has students');
    case 'WEAK_PASSWORD':
      return _t('كلمة المرور ضعيفة — 8 أحرف على الأقل', 'The password is too weak — at least 8 characters');
    case 'PHONE_TAKEN':
      return _t('رقم الهاتف مستخدم بحساب آخر', 'This phone number is already used by another account');
    case 'REAUTH_REQUIRED':
      return _t('أدخل كلمة المرور الحالية للمتابعة', 'Enter your current password to continue');
    case 'INVALID_CREDENTIALS':                            // 401 from POST /auth/login (QA M1): no such account OR wrong password
      return _t('بيانات الدخول أو كلمة المرور غير صحيحة', 'Incorrect login or password');
    case 'TEMP_PASSWORD_EXPIRED':
      return _t('انتهت صلاحية كلمة المرور المؤقتة — اطلب بيانات دخول جديدة من مؤسستك',
          'Your temporary password has expired — ask your organization for new login details');
    case 'SELF_SERVICE_RESET':
      return _t('هذا الحساب يدير كلمة مروره بنفسه — يستطيع صاحبه استخدام "نسيت كلمة المرور"',
          'This account manages its own password — its owner can use "Forgot password"');
    case 'LOGIN_EMAIL_ONLY':
      return _t('سجّل الدخول بالبريد الإلكتروني', 'Please sign in with your e-mail');
    case 'LOGIN_PHONE_ONLY':
      return _t('سجّل الدخول برقم الهاتف', 'Please sign in with your phone number');
    case 'LOGIN_USERNAME_DISABLED':
      return _t('الدخول باسم المستخدم غير متاح حالياً — استخدم بريدك أو رقم هاتفك',
          'Signing in with a username is off right now — use your e-mail or phone');
    case 'USERNAME_TAKEN':
      return _t('اسم المستخدم محجوز لشخص آخر — جرّب أحد الاقتراحات', 'That username is taken — try one of the suggestions');
    case 'USERNAME_RESERVED':
      return _t('اسم المستخدم هذا محجوز للمنصة — اختر اسماً آخر', 'That username is reserved — pick another one');
    case 'USERNAME_CHANGE_TOO_SOON':                       // 429 from PUT /auth/me (D-071 v2): `retry_at` ISO-UTC
      final at = _utc(d['retry_at']);
      return at == null
          ? _t('غيّرت اسم المستخدم مؤخراً — يمكنك تغييره مرة أخرى لاحقاً، ويمكنك حذفه الآن',
              'You changed your username recently — you can change it again later, or remove it now')
          : _t('غيّرت اسم المستخدم مؤخراً — يمكنك تغييره مرة أخرى في ${AppTime.date(at)}',
              'You changed your username recently — you can change it again on ${AppTime.date(at)}');
    case 'course_access_denied':                           // 403 on a course's content (D-210): reason, expires_at
    case 'SUBSCRIPTION_REQUIRED':                          // 402 org_subscription_required
      return accessDeniedText(e) ?? e.message;
    case 'USERNAME_INVALID':
      return d['message'] is String && AppConfig.lang == 'ar'
          ? d['message'] as String
          : _t('اسم المستخدم غير صالح', 'That username isn\'t valid');
  }
  final coupon = couponErrorText(e.code, d);
  if (coupon != null) return coupon;
  if (e.type == ApiErrorType.rateLimited) {
    return _t('طلبات كثيرة — انتظر قليلاً ثم حاول مجدداً', 'Too many requests — wait a moment and try again') + _wait(apiRetryAfter(e));
  }
  return e.message;
}
