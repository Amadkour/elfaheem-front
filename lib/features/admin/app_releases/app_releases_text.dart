// lib/features/admin/app_releases/app_releases_text.dart
//
// The words and colours of App versions (D-143): platform names and icons, status chips, policies, download sources,
// the server's error codes and the form's field errors — bilingual, `t(ar, en)`.
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../admin_common.dart' show t;

String releasePlatformName(String p) => switch (p) {
      'android' => t('أندرويد', 'Android'),
      'ios' => t('آيفون — تطبيق الويب (PWA)', 'iPhone — web app (PWA)'),
      'web' => t('الموقع (الويب)', 'Web'),
      'linux' => t('لينكس', 'Linux'),
      'windows' => t('ويندوز', 'Windows'),
      'macos' => t('ماك', 'macOS'),
      _ => p,
    };

/// The short name for chips and titles ("iPhone" rather than the full PWA line).
String releasePlatformShort(String p) => switch (p) {
      'ios' => t('آيفون', 'iPhone'),
      _ => releasePlatformName(p),
    };

IconData releasePlatformIcon(String p) => switch (p) {
      'android' => Icons.android_rounded,
      'ios' => Icons.phone_iphone_rounded,
      'web' => Icons.language_rounded,
      'linux' => Icons.terminal_rounded,
      'windows' => Icons.desktop_windows_rounded,
      'macos' => Icons.laptop_mac_rounded,
      _ => Icons.devices_other_rounded,
    };

/// One line under the platform card of the New version form.
String releasePlatformHint(String p) => switch (p) {
      'android' => t('ملفات APK موقّعة لموقعنا، وملف AAB عند اختيار Google Play', 'Signed APKs for our website, and an AAB for Google Play'),
      'ios' => t('أبل لا تسمح بالتثبيت إلا من App Store، لذلك يثبّت مستخدمو الآيفون تطبيق الويب. يُسجَّل هنا ما الجديد وسياسة التحديث فقط.',
          'Apple only allows installs from the App Store, so iPhone users get the web app. This records the notes and the update policy only.'),
      'web' => t('يُبنى الموقع ويحل محل النسخة الحالية دفعة واحدة، وتبقى السابقة للرجوع', 'The site is built and replaces the served one at once; the previous one is kept for rollback'),
      'linux' => t('حزم ‎.deb و ‎.tar.gz', '.deb and .tar.gz packages'),
      'windows' || 'macos' => t('لا يُبنى على خادم البناء؛ أضف رابط الملف أو المتجر', 'Not built on the build server; give the file or store link'),
      _ => '',
    };

String releaseStatusName(String s) => switch (s) {
      'queued' => t('في الانتظار', 'Queued'),
      'building' => t('يُبنى', 'Building'),
      'testing' => t('يُختبر', 'Testing'),
      'uploading' => t('يُرفع', 'Uploading'),
      'ready' => t('جاهز للنشر', 'Ready'),
      'live' => t('منشور الآن', 'Live'),
      'failed' => t('فشل', 'Failed'),
      'canceled' => t('أُلغي', 'Canceled'),
      'rolled_back' => t('تم الرجوع عنه', 'Rolled back'),
      'replaced' => t('استُبدل بأحدث', 'Replaced'),
      _ => s,
    };

Color releaseStatusColor(BuildContext context, String s) {
  final c = context.colors;
  return switch (s) {
    'live' => c.success,
    'ready' => c.primary,
    'queued' || 'building' || 'testing' || 'uploading' => c.warning,
    'failed' => c.danger,
    _ => c.textLight,
  };
}

IconData releaseStatusIcon(String s) => switch (s) {
      'live' => Icons.check_circle_rounded,
      'ready' => Icons.inventory_2_outlined,
      'queued' => Icons.schedule_rounded,
      'building' => Icons.construction_rounded,
      'testing' => Icons.fact_check_outlined,
      'uploading' => Icons.cloud_upload_outlined,
      'failed' => Icons.error_outline_rounded,
      'canceled' => Icons.block_rounded,
      'rolled_back' => Icons.history_rounded,
      'replaced' => Icons.published_with_changes_rounded,
      _ => Icons.circle_outlined,
    };

String releasePolicyName(String p) => switch (p) {
      'must' => t('تحديث إجباري', 'Must update'),
      'recommended' => t('تحديث مُستحسن', 'Recommended'),
      _ => t('اختياري', 'Optional'),
    };

String releasePolicyHint(String p) => switch (p) {
      'must' => t('لا يعمل التطبيق حتى يُحدَّث؛ صفحات الويب المفتوحة يُطلب منها إعادة التحميل', 'The app stops until it is updated; open web pages are asked to reload'),
      'recommended' => t('نافذة لطيفة يمكن تأجيلها', 'A gentle prompt that can be put off'),
      _ => t('لا تنبيه؛ يظهر الإصدار في صفحة التنزيلات', 'No prompt; the version shows on the downloads page'),
    };

String releaseSourceName(String s) => switch (s) {
      'google_play' => 'Google Play',
      'app_store' => 'App Store',
      'custom' => t('رابط مخصص', 'Custom link'),
      _ => t('موقعي', 'My website'),
    };

IconData releaseSourceIcon(String s) => switch (s) {
      'google_play' => Icons.shop_rounded,
      'app_store' => Icons.storefront_rounded,
      'custom' => Icons.link_rounded,
      _ => Icons.public_rounded,
    };

/// The sources each platform offers (web is always our own site).
List<String> releaseSourcesFor(String platform) => switch (platform) {
      'android' => const ['website', 'google_play', 'custom'],
      'ios' => const ['website', 'app_store'],
      'macos' => const ['website', 'app_store', 'custom'],
      'linux' || 'windows' => const ['website', 'custom'],
      _ => const ['website'],
    };

String releaseGateName(String g) => g == 'direct' ? t('ارفع مباشرة', 'Upload directly') : t('اختبر أولاً', 'Test first');

/// The server's codes as sentences (../back docs/app_releases.md "As built"); [fallback] (its own words) otherwise.
String releaseErrorText(String? code, String fallback, {Map<String, dynamic> extra = const {}}) => switch (code) {
      'version_exists' => t('هذا الإصدار موجود بالفعل لهذه المنصة — اختر رقماً أعلى', 'This version already exists for this platform — pick a higher one'),
      'version_not_greater' => extra['live'] == null
          ? t('يجب أن يكون الإصدار أعلى من المنشور الآن', 'The version must be higher than the live one')
          : t('يجب أن يكون الإصدار أعلى من المنشور الآن (${extra['live']})', 'The version must be higher than the live one (${extra['live']})'),
      'build_number_not_greater' => extra['next_build_number'] == null
          ? t('رقم البناء يجب أن يكون أعلى من آخر رقم', 'The build number must be higher than the last one')
          : t('رقم البناء يجب أن يكون ${extra['next_build_number']} أو أكثر', 'The build number must be ${extra['next_build_number']} or higher'),
      'version_invalid' => t('اكتب الإصدار بالشكل x.y.z مثل 1.4.0', 'Write the version as x.y.z, e.g. 1.4.0'),
      'build_number_invalid' => t('رقم البناء رقم صحيح أكبر من صفر', 'The build number is a whole number above zero'),
      'min_supported_invalid' => t('أقل إصدار مدعوم بالشكل x.y.z', 'The minimum supported version is x.y.z'),
      'platform_invalid' => t('منصة غير معروفة', 'Unknown platform'),
      'policy_invalid' => t('سياسة تحديث غير معروفة', 'Unknown update policy'),
      'gate_invalid' => t('طريقة فحص غير معروفة', 'Unknown gate'),
      'source_invalid' => t('هذا المصدر لا يناسب المنصة (Google Play لأندرويد فقط، App Store للآيفون والماك فقط)',
          'This source does not fit the platform (Google Play is Android only, App Store iPhone and macOS only)'),
      'store_url_invalid' => t('الرابط يجب أن يبدأ بـ https://', 'The link must start with https://'),
      'store_url_required' => t('أضف رابط المتجر أو الملف', 'Add the store or file link'),
      'branch_invalid' => t('اسم الفرع غير صالح (حروف وأرقام و . _ / - فقط)', 'The branch name is not valid (letters, digits and . _ / - only)'),
      'branch_not_found' => t('لم يجد خادم البناء هذا الفرع في المستودع', 'The build server could not find this branch on the repository'),
      'reauth_failed' || 'REAUTH_REQUIRED' || 'reauth_required' => t('كلمة المرور غير صحيحة', 'The password is not correct'),
      'too_many_attempts' => t('محاولات كثيرة — انتظر قليلاً ثم حاول مجدداً', 'Too many attempts — wait a little, then try again'),
      'build_running' => t('هناك بناء يعمل لهذه المنصة — انتظر حتى ينتهي أو ألغِه', 'A build is already running for this platform — wait for it or cancel it'),
      'releases_not_configured' => t('خادم الإصدارات غير مُعدّ بعد على هذا الخادم (لا يوجد مجلد الإصدارات) — راجع docs/app_releases_server.md',
          'Releases are not set up on this server yet (no releases folder) — see docs/app_releases_server.md'),
      'not_cancelable' => t('لا يمكن الإلغاء الآن: بدأ الرفع أو انتهى البناء', 'It can no longer be canceled: the upload started or the build ended'),
      'not_retryable' => t('لا يمكن إعادة المحاولة لهذا الإصدار', 'This version cannot be retried'),
      'not_publishable' => t('الإصدار ليس جاهزاً للنشر', 'This version is not ready to go live'),
      'not_live' => t('هذا الإصدار ليس المنشور الآن', 'This version is not the live one'),
      'rollback_unavailable' => t('لا يوجد إصدار سابق منشور (أو حُذفت ملفاته) للرجوع إليه', 'There is no earlier live version (or its files are gone) to go back to'),
      'artifacts_missing' => t('انتهى البناء دون كل الملفات المطلوبة', 'The build ended without every required file'),
      'super_admin_required' => t('هذه الصفحة للمشرف العام فقط', 'This page is for the super admin only'),
      _ => (code != null && code.startsWith('artifacts_missing')) ? t('انتهى البناء دون كل الملفات المطلوبة: ${code.split(':').skip(1).join(':').trim()}', 'The build ended without every required file: ${code.split(':').skip(1).join(':').trim()}') : fallback,
    };

/// The form's own checks (validateReleaseDraft) as sentences.
String releaseFieldError(String key) => switch (key) {
      'version_format' => t('اكتب الإصدار بالشكل x.y.z مثل 1.4.0', 'Write the version as x.y.z, e.g. 1.4.0'),
      'build_number' => t('رقم البناء رقم صحيح أكبر من صفر', 'The build number is a whole number above zero'),
      'min_above_version' => t('أقل إصدار مدعوم لا يتجاوز هذا الإصدار', 'The minimum supported version cannot be above this version'),
      'branch_invalid' => releaseErrorText('branch_invalid', ''),
      'url_https' => t('رابط يبدأ بـ https://', 'A link starting with https://'),
      _ => releaseErrorText(key, key),
    };

/// Which field a server code belongs to (it is shown under that field).
String? releaseErrorField(String? code) => switch (code) {
      'version_exists' || 'version_not_greater' || 'version_invalid' => 'version',
      'build_number_not_greater' || 'build_number_invalid' => 'build_number',
      'min_supported_invalid' => 'min_supported',
      'branch_invalid' || 'branch_not_found' => 'branch',
      'store_url_required' || 'store_url_invalid' || 'source_invalid' => 'store_url',
      _ => null,
    };

/// "12 MB"
String releaseBytes(int? b) {
  if (b == null || b <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v < 10 && i > 0 ? v.toStringAsFixed(1) : v.round()} ${units[i]}';
}
