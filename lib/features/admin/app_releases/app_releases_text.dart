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
      'android' => t('Google Play، أو ملفات APK موقّعة على موقعنا', 'Google Play, or signed APKs on our website'),
      'ios' => t('أبل لا تسمح بالتثبيت إلا من App Store، لذلك يثبّت مستخدمو الآيفون تطبيق الويب. يُسجَّل هنا ما الجديد وسياسة التحديث فقط.',
          'Apple only allows installs from the App Store, so iPhone users get the web app. This records the notes and the update policy only.'),
      'web' => t('يُبنى الموقع ويحل محل النسخة الحالية دفعة واحدة، وتبقى السابقة للرجوع', 'The site is built and replaces the served one at once; the previous one is kept for rollback'),
      'linux' => t('حزم ‎.deb و ‎.tar.gz على موقعنا', '.deb and .tar.gz packages on our website'),
      'windows' => t('ملف zip لتطبيق ويندوز على موقعنا', 'A zip of the Windows app on our website'),
      'macos' => t('لا يُبنى هنا؛ أضف رابط الملف أو المتجر', 'Not built here; give the file or store link'),
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

/// "Google Play" / "App Store" / "My website" — the channel as the form and the release page name it.
String releaseChannelName(String platform, String channel) => channel == 'store'
    ? switch (platform) {
        'android' => 'Google Play',
        'ios' || 'macos' => 'App Store',
        'windows' => 'Microsoft Store',
        _ => t('المتجر', 'Store'),
      }
    : (platform == 'ios' ? t('تطبيق الويب (PWA)', 'The web app (PWA)') : t('موقعي', 'My website'));

IconData releaseChannelIcon(String platform, String channel) => channel == 'store'
    ? (platform == 'android' ? Icons.shop_rounded : Icons.storefront_rounded)
    : (platform == 'ios' ? Icons.add_to_home_screen_rounded : Icons.public_rounded);

/// One line under a channel card.
String releaseChannelHint(String platform, String channel) => switch ((platform, channel)) {
      ('android', 'store') => t('يبنيه Codemagic ويرفعه إلى Google Play على المسار الذي تختاره', 'Codemagic builds it and uploads it to Google Play on the track you pick'),
      ('android', _) => t('ملفات APK على خادمنا، تُنزَّل من شريط أعلى الموقع ومن نافذة التحديث', 'APKs on our server, downloaded from the strip at the top of the website and the update prompt'),
      ('ios', 'store') => t('يبنيه Codemagic ويرسله إلى App Store Connect (يحتاج حساب أبل للمطورين)', 'Codemagic builds it and sends it to App Store Connect (needs an Apple Developer account)'),
      ('ios', _) => t('أبل لا تسمح بالتثبيت إلا من App Store، فيثبّت مستخدمو الآيفون تطبيق الويب: يُسجَّل ما الجديد وسياسة التحديث فقط',
          'Apple allows installs from the App Store only, so iPhone users install the web app: this records the notes and the update policy'),
      ('web', _) => t('يبنيه Codemagic ويرفعه، فيحل محل الموقع الحالي دفعة واحدة وتبقى النسخة السابقة للرجوع',
          'Codemagic builds and uploads it; it replaces the served site at once and the previous one is kept for rollback'),
      ('linux', _) => t('حزم ‎.deb و ‎.tar.gz على خادمنا', '.deb and .tar.gz packages on our server'),
      ('windows', 'store') => t('يُسجَّل رابط Microsoft Store فقط (الرفع إلى المتجر ليس في هذه المرحلة)', 'Records the Microsoft Store link only (no store upload in this phase)'),
      ('windows', _) => t('ملف zip لتطبيق ويندوز على خادمنا', 'A zip of the Windows app on our server'),
      ('macos', 'store') => t('يُسجَّل رابط المتجر فقط (لا يُبنى تطبيق ماك هنا)', 'Records the store link only (no Mac app is built here)'),
      ('macos', _) => t('يُسجَّل رابط الملف فقط (لا يُبنى تطبيق ماك هنا)', 'Records the file link only (no Mac app is built here)'),
      _ => '',
    };

/// The store's own review still decides (Play production, the App Store): the build is "submitted", not out.
String releaseStoreReviewNote(String platform) => platform == 'android'
    ? t('Codemagic يرفع النسخة إلى Google Play. مسارا internal و alpha و beta يصلان المختبِرين خلال دقائق، أما production فيمر بمراجعة Google أولاً، و«منشور» هنا يعني «أُرسل للمراجعة».',
        'Codemagic uploads the build to Google Play. The internal, alpha and beta tracks reach testers within minutes; production still goes through Google\'s review first, so "Live" here means "submitted".')
    : t('Codemagic يرسل النسخة إلى App Store Connect، ثم تمر بمراجعة أبل قبل أن تصل المستخدمين؛ «منشور» هنا يعني «أُرسل للمراجعة».',
        'Codemagic sends the build to App Store Connect; Apple\'s review still comes before it reaches people, so "Live" here means "submitted".');

String releaseTrackName(String track) => switch (track) {
      'internal' => t('internal — فريق الاختبار الداخلي', 'internal — internal testers'),
      'alpha' => t('alpha — اختبار مغلق', 'alpha — closed testing'),
      'beta' => t('beta — اختبار مفتوح', 'beta — open testing'),
      'production' => t('production — للجميع (بعد مراجعة Google)', 'production — everyone (after Google\'s review)'),
      _ => track,
    };

/// What one missing item of the readiness answer means (an env name or a code), in the admin's words. The env name
/// itself is drawn next to it (the owner sets it in .env.production).
String releaseMissingText(String item) => switch (item) {
      'CODEMAGIC_API_TOKEN' => t('مفتاح Codemagic API غير مضبوط على الخادم', 'The Codemagic API token is not set on the server'),
      'CODEMAGIC_APP_ID' => t('معرّف تطبيق Codemagic غير مضبوط', 'The Codemagic application id is not set'),
      'APP_RELEASE_UPLOAD_SECRET' => t('مفتاح توقيع رفع الملفات غير مضبوط (يلزم لقناة الموقع)', 'The upload signing secret is not set (the website channel needs it)'),
      'PLAY_PACKAGE_NAME' => t('اسم حزمة أندرويد على Google Play غير مضبوط', 'The Android package name for Google Play is not set'),
      'package_name_example' => t('اسم الحزمة يبدأ بـ com.example وGoogle Play يرفضه — اختر معرّفاً حقيقياً أولاً',
          'The package name starts with com.example, which Google Play refuses — pick a real id first'),
      'PLAY_STORE_URL' => t('رابط التطبيق على Google Play غير مضبوط', 'The Google Play link is not set'),
      'APP_STORE_APP_ID' => t('معرّف التطبيق في App Store غير مضبوط', 'The App Store app id is not set'),
      'IOS_BUNDLE_ID' => t('معرّف حزمة iOS غير مضبوط', 'The iOS bundle id is not set'),
      'PLAY_TRACK' => t('مسار Google Play غير صالح (internal أو alpha أو beta أو production)', 'The Google Play track is not internal, alpha, beta or production'),
      'APP_RELEASES_DIR' => t('مجلد الإصدارات على الخادم غير مضبوط (لازم لنشر نسخة الويب)', 'The releases folder is not set on the server (the web build needs it)'),
      'channel_invalid' => t('هذه القناة غير متاحة لهذه المنصة', 'This channel is not available for the platform'),
      'APP_STORE_URL' => t('رابط التطبيق على App Store غير مضبوط', 'The App Store link is not set'),
      'APP_RELEASES_BUCKET' => t('حاوية ملفات الإصدارات في MinIO غير مضبوطة', 'The MinIO bucket for release files is not set'),
      'NB_PUBLIC_API_URL' => t('عنوان الخادم العام الذي يرفع إليه Codemagic غير مضبوط', 'The public API address Codemagic uploads to is not set'),
      'minio' || 'MINIO' || 'minio_unavailable' => t('تخزين MinIO غير متاح على الخادم', 'MinIO storage is not available on the server'),
      'ios_store_off' || 'app_store_off' => t('قناة App Store مطفأة حتى يُعدّ حساب أبل', 'The App Store channel is off until an Apple account is set up'),
      _ when item.startsWith('CODEMAGIC_WORKFLOW_') => t('اسم سير العمل في Codemagic غير مضبوط', 'The Codemagic workflow name is not set'),
      _ => t('إعداد ناقص على الخادم', 'A setting is missing on the server'),
    };

/// We have our own sentence for [item] (else the server's is shown).
bool releaseMissingKnown(String item) => releaseMissingText(item) != releaseMissingText('?');

/// True for an env name (drawn as code next to the sentence); false for a code such as `package_name_example`.
bool releaseMissingIsEnv(String item) => RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(item);

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
      'channel_not_configured' => t('هذه القناة غير مُعدّة بعد على الخادم — ما ينقصها مذكور أعلى الزر', 'This channel is not set up on the server yet — what is missing is listed above the button'),
      'channel_invalid' => t('هذه القناة لا تناسب المنصة', 'This channel does not fit the platform'),
      'codemagic_error' || 'codemagic_failed' => t('لم يستجب Codemagic كما يجب — حاول مرة أخرى بعد قليل', 'Codemagic did not answer as expected — try again in a moment'),
      'executor_invalid' => t('منفّذ بناء غير معروف', 'Unknown build executor'),
      'config_invalid' => t('قيمة في إعدادات البناء غير صالحة', 'A build setting is not valid'),
      'upload_not_active' => t('انتهت محاولة البناء هذه؛ الرفع لمحاولة أحدث', 'This build attempt is over; the upload belongs to a newer one'),
      'download_not_found' => t('الملف غير موجود', 'No such download'),
      'workflow_invalid' => t('اسم سير العمل: حروف وأرقام و . _ - فقط', 'The workflow name: letters, digits and . _ - only'),
      'package_name_invalid' => t('اسم الحزمة بالشكل site.nextbrain.app', 'The package name looks like site.nextbrain.app'),
      'package_name_example' => t('Google Play يرفض الحزم التي تبدأ بـ com.example', 'Google Play refuses packages that start with com.example'),
      'track_invalid' => t('مسار غير معروف (internal أو alpha أو beta أو production)', 'Unknown track (internal, alpha, beta or production)'),
      'upload_token_invalid' || 'upload_token_expired' => t('رمز رفع الملفات غير صالح أو انتهت مدته', 'The upload token is not valid or has expired'),
      'super_admin_required' => t('هذه الصفحة للمشرف العام فقط', 'This page is for the super admin only'),
      _ when code != null && code.startsWith('codemagic_start_failed') =>
        t('لم يبدأ Codemagic البناء: ${_after(code)}', 'Codemagic did not start the build: ${_after(code)}'),
      _ when code != null && code.startsWith('codemagic_build_not_found') =>
        t('لم يعد Codemagic يعرف هذا البناء', 'Codemagic no longer knows this build'),
      _ when code != null && code.startsWith('upload_missing') =>
        t('انتهى البناء على Codemagic لكن رفع الملفات إلى خادمنا لم يكتمل', 'The Codemagic build finished but the upload to our server did not complete'),
      _ when code != null && code.startsWith('codemagic:') => t('Codemagic: ${_after(code)}', 'Codemagic: ${_after(code)}'),
      _ => (code != null && code.startsWith('artifacts_missing')) ? t('انتهى البناء دون كل الملفات المطلوبة: ${code.split(':').skip(1).join(':').trim()}', 'The build ended without every required file: ${code.split(':').skip(1).join(':').trim()}') : fallback,
    };

String _after(String code) => code.split(':').skip(1).join(':').trim();

/// The form's own checks (validateReleaseDraft) as sentences.
String releaseFieldError(String key) => switch (key) {
      'version_format' => t('اكتب الإصدار بالشكل x.y.z مثل 1.4.0', 'Write the version as x.y.z, e.g. 1.4.0'),
      'build_number' => t('رقم البناء رقم صحيح أكبر من صفر', 'The build number is a whole number above zero'),
      'min_above_version' => t('أقل إصدار مدعوم لا يتجاوز هذا الإصدار', 'The minimum supported version cannot be above this version'),
      'branch_invalid' => releaseErrorText('branch_invalid', ''),
      'url_https' => t('رابط يبدأ بـ https://', 'A link starting with https://'),
      'workflow_invalid' || 'package_name_invalid' || 'package_name_example' || 'track_invalid' => releaseErrorText(key, key),
      _ => releaseErrorText(key, key),
    };

/// Which field a server code belongs to (it is shown under that field).
String? releaseErrorField(String? code) => switch (code) {
      'version_exists' || 'version_not_greater' || 'version_invalid' => 'version',
      'build_number_not_greater' || 'build_number_invalid' => 'build_number',
      'min_supported_invalid' => 'min_supported',
      'branch_invalid' || 'branch_not_found' => 'branch',
      'workflow_invalid' => 'workflow',
      'package_name_invalid' || 'package_name_example' => 'package_name',
      'track_invalid' => 'track',
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
