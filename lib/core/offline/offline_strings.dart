/// lib/features/shared/downloads/offline_strings.dart
library;

import 'package:flutter_education_app/config/app_config.dart';

/// Translates [key] through the app's translation.json (`'key'.tr`).
///
/// If the key hasn't been added to translation.json yet, falls back to the
/// built-in Arabic / English text below, so the UI is never shown as a raw key.
/// Once the keys are merged into translation.json, that file wins.
String offlineT(String key) {
  final v = key.tr;
  if (v.isNotEmpty && v != key) return v;
  final pair = _fallback[key];
  if (pair == null) return key;
  return AppConfig.lang == 'ar' ? pair.$1 : pair.$2;
}

/// key -> (Arabic, English)
const Map<String, (String, String)> _fallback = {
  'dl_title': ('التحميلات', 'Downloads'),
  'dl_offline_info': (
    'أنت غير متصل بالإنترنت — يمكنك مشاهدة الفيديوهات المحمّلة',
    'You are offline — you can watch your downloaded videos'
  ),
  'dl_back_online': ('عاد الاتصال بالإنترنت', 'You are back online'),
  'dl_retry_connection': ('إعادة محاولة الاتصال', 'Retry connection'),
  'dl_go_home': ('العودة للرئيسية', 'Back to home'),
  'dl_empty_title': ('لا توجد فيديوهات محمّلة', 'No downloaded videos'),
  'dl_empty_body': (
    'حمّل الفيديوهات من داخل المشغّل لمشاهدتها بدون إنترنت',
    'Download videos from the player to watch them without internet'
  ),
  'dl_videos_count': ('فيديو', 'videos'),
  'dl_storage_used': ('المساحة المستخدمة', 'Storage used'),
  'dl_delete_title': ('حذف التحميل', 'Delete download'),
  'dl_delete_body': (
    'سيتم حذف الفيديو من جهازك، ويمكنك تحميله مرة أخرى لاحقاً.',
    'The video will be removed from your device. You can download it again later.'
  ),
  'dl_delete_all': ('حذف الكل', 'Delete all'),
  'dl_delete_all_title': (
    'حذف جميع التحميلات؟',
    'Delete all downloads?'
  ),
  'dl_expires_in_days': ('ينتهي خلال {n} يوم', 'Expires in {n} days'),
  'dl_expires_today': ('ينتهي اليوم', 'Expires today'),
  'dl_started': ('بدأ التحميل…', 'Download started…'),
  'dl_done': (
    'تم التحميل — متاح بدون إنترنت',
    'Downloaded — available offline'
  ),
  'dl_failed': (
    'فشل التحميل، حاول مرة أخرى',
    'Download failed, please try again'
  ),
  'dl_tooltip_download': (
    'تحميل للمشاهدة بدون إنترنت',
    'Download to watch offline'
  ),
  'dl_on_device': ('محمّل على الجهاز', 'Downloaded on device'),
  'dl_minimize': ('تصغير', 'Minimize'),
  'dl_pip_unsupported': (
    'النافذة المصغرة غير مدعومة على هذا الجهاز',
    'Picture-in-picture is not supported on this device'
  ),
  'dl_pip_failed': (
    'تعذّر تشغيل النافذة المصغرة',
    'Could not start picture-in-picture'
  ),
  'dl_rotation_auto': ('التدوير التلقائي: مفعّل', 'Auto-rotate: on'),
  'dl_rotation_locked': ('تم قفل التدوير', 'Rotation locked'),
  'dl_views_left': (
    'المشاهدات المتبقية هذا الشهر: {n}',
    'Views left this month: {n}'
  ),
  'dl_views_ended': ('انتهت المشاهدات', 'No views left'),
  'dl_ok': ('حسناً', 'OK'),
};
