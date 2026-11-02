// lib/features/admin/models/models_hub_text.dart
//
// The words of the AI Models page and the floating download bar (D-152), Arabic + English through `t(ar, en)`:
// role names, statuses, sources, providers, audit actions, and the byte / speed / time-left labels.
library;

import '../../../config/app_config.dart';
import '../../../core/models_hub/models_hub_api.dart';
import '../../../design/app_bidi.dart';
import '../admin_common.dart' show t;

/// The page's kill switch (../back services/feature_catalog.py).
const kModelsAdminFeatureKey = 'models.admin';

String hubRoleName(String role) => switch (role) {
      'embedding' => t('التضمين', 'Embedding'),
      'generation' => t('التوليد', 'Generation'),
      'reranker' => t('إعادة الترتيب', 'Re-ranker'),
      'nli' => t('الاستدلال اللغوي (NLI)', 'NLI'),
      'ocr_det' => t('OCR · كشف النص', 'OCR · text detection'),
      'ocr_rec_ar' => t('OCR · قراءة العربية', 'OCR · Arabic reading'),
      'ocr_rec_en' => t('OCR · قراءة الإنجليزية', 'OCR · English reading'),
      'handwriting_en' => t('خط اليد (إنجليزي)', 'Handwriting (English)'),
      'digits' => t('الأرقام', 'Digits'),
      'vision_language' => t('الرؤية واللغة', 'Vision-language'),
      _ => role,
    };

String hubRoleHint(String role) => switch (role) {
      'embedding' => t('يحوّل النصوص إلى متجهات لفهرس المستندات والتصحيح', 'Turns text into vectors for the document index and grading'),
      'generation' => t('يكتب إجابات المساعد والأسئلة المولّدة', 'Writes the assistant’s answers and generated questions'),
      'reranker' => t('يرتّب المقاطع الأقرب للسؤال', 'Orders the passages closest to a question'),
      'nli' => t('يتحقق من أن الإجابة تستند إلى المصدر', 'Checks that an answer follows from its source'),
      'ocr_det' => t('جزء من محرك OCR: يجد أسطر النص في الصورة', 'Part of the OCR engine: finds the text lines in an image'),
      'ocr_rec_ar' => t('جزء من محرك OCR: يقرأ الأسطر العربية', 'Part of the OCR engine: reads Arabic lines'),
      'ocr_rec_en' => t('جزء من محرك OCR: يقرأ الأسطر الإنجليزية', 'Part of the OCR engine: reads English lines'),
      'handwriting_en' => t('يقرأ الإجابات المكتوبة بخط اليد', 'Reads handwritten answers'),
      'digits' => t('يقرأ الأرقام المكتوبة في أوراق الإجابة', 'Reads handwritten digits on answer sheets'),
      'vision_language' => t('يصف الصور ويقرأ الحالات الصعبة', 'Describes images and reads the hard cases'),
      _ => '',
    };

String hubStatusLabel(String status) => switch (status) {
      'not_downloaded' => t('غير مُنزّل', 'Not downloaded'),
      'downloading' => t('جارٍ التنزيل', 'Downloading'),
      'paused' => t('متوقف مؤقتاً', 'Paused'),
      'ready' => t('جاهز', 'Ready'),
      'active' => t('مُفعّل', 'Active'),
      'failed' => t('فشل', 'Failed'),
      _ => status,
    };

String hubSourceLabel(String source) => switch (source) {
      'registry' => t('السجل', 'Registry'),
      'hf' => 'Hugging Face',
      'ollama' => 'Ollama',
      'url' => t('رابط', 'URL'),
      _ => source,
    };

String hubPriorityLabel(String p) => switch (p) {
      'interactive' => t('تفاعلي (أعلى)', 'Interactive (highest)'),
      'batch' => t('دفعات', 'Batch'),
      'grading' => t('التصحيح (أدنى)', 'Grading (lowest)'),
      _ => p,
    };

/// What a pending activation is doing now.
String hubStageLabel(String stage) => switch (stage) {
      'downloading' => t('جارٍ تنزيل النموذج الجديد', 'Downloading the new model'),
      'testing' => t('جارٍ اختبار السلامة', 'Running the health test'),
      'ready_to_confirm' => t('اجتاز الاختبار — بانتظار تأكيدك', 'Passed the health test — waiting for you to confirm'),
      'failed' => t('لم يجتز الفحص', 'Did not pass the checks'),
      'reindex_later' => t('بانتظار إعادة بناء فهرس المستندات', 'Waiting for the document index rebuild'),
      'reindexing' => t('جارٍ إعادة بناء فهرس المستندات', 'Rebuilding the document index'),
      'reindex_failed' => t('فشلت إعادة بناء الفهرس', 'The index rebuild failed'),
      _ => stage,
    };

String hubAuditAction(String action) => switch (action) {
      'seed_active' => t('ضُبط من إعدادات الخادم', 'Set from the server settings'),
      'add' => t('أُضيف إلى المكتبة', 'Added to the library'),
      'download' => t('بدأ التنزيل', 'Download started'),
      'download_pause' => t('أُوقف التنزيل مؤقتاً', 'Download paused'),
      'download_resume' => t('استُؤنف التنزيل', 'Download resumed'),
      'download_cancel' => t('أُلغي التنزيل', 'Download cancelled'),
      'download_done' => t('اكتمل التنزيل', 'Download finished'),
      'download_failed' => t('فشل التنزيل', 'Download failed'),
      'activate_request' => t('طُلب التفعيل', 'Activation requested'),
      'activate_checks_failed' => t('لم يجتز فحوص التفعيل', 'Activation checks failed'),
      'health_test_request' => t('طُلب اختبار السلامة', 'Health test requested'),
      'health_test' => t('اختبار السلامة', 'Health test'),
      'activate' => t('فُعّل', 'Activated'),
      'activate_cancel' => t('أُلغي التفعيل المعلّق', 'Pending activation cancelled'),
      'rollback' => t('رجوع إلى النموذج السابق', 'Rolled back'),
      'set_fallback' => t('تغيّر النموذج الاحتياطي', 'Fallback changed'),
      'set_limits' => t('تغيّرت حدود الموارد', 'Resource limits changed'),
      'delete' => t('حُذف', 'Deleted'),
      'fallback' => t('خدم النموذج الاحتياطي', 'The fallback served'),
      'reindex_later' => t('إعادة الفهرسة لاحقاً', 'Re-index later'),
      'reindex_start' => t('بدأت إعادة الفهرسة', 'Re-index started'),
      'drop_vectors' => t('حُذفت المتجهات القديمة', 'Old vectors dropped'),
      _ => action,
    };

/// A number with a Latin unit ("296 MB", "18%") kept in reading order inside an Arabic sentence: wrapped in a
/// left-to-right isolate (U+2066 … U+2069) in Arabic, as is in English.
String hubLtr(String s) =>
    AppConfig.lang == 'ar' && s.isNotEmpty ? '${String.fromCharCode(0x2066)}$s${String.fromCharCode(0x2069)}' : s;

/// "1.4 GB" / "523 MB" / "16 KB" (decimal units, as the server counts them).
String hubBytes(int bytes) {
  if (bytes <= 0) return '—';
  const k = 1000;
  if (bytes >= k * k * k) return hubLtr('${(bytes / (k * k * k)).toStringAsFixed(bytes >= 10 * k * k * k ? 0 : 1)} GB');
  if (bytes >= k * k) return hubLtr('${(bytes / (k * k)).toStringAsFixed(bytes >= 100 * k * k ? 0 : 1)} MB');
  return hubLtr('${(bytes / k).ceil()} KB');
}

/// "523 MB" / "2.1 GB" from megabytes.
String hubMb(int mb) => mb <= 0 ? '—' : hubLtr(mb >= 1000 ? '${(mb / 1000).toStringAsFixed(1)} GB' : '$mb MB');

/// "12 MB/s" (empty while nothing was measured).
String hubSpeed(double bps) {
  if (bps <= 0) return '';
  if (bps >= 1e6) return hubLtr('${(bps / 1e6).toStringAsFixed(bps >= 1e7 ? 0 : 1)} MB/s');
  return hubLtr('${(bps / 1e3).ceil()} KB/s');
}

/// "2 min left" / "35 s left" / "1 h 5 min left".
String hubEta(int? seconds) {
  if (seconds == null || seconds < 0) return '';
  if (seconds < 60) return t('بقي $seconds ث', '$seconds s left');
  final m = (seconds / 60).ceil();
  if (m < 60) return t('بقي $m د', '$m min left');
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? t('بقي $h س', '$h h left') : t('بقي $h س $r د', '$h h $r min left');
}

/// An estimate rounded the way a person says it: under 10 s as is, under a minute to 5 s, under 90 s to 10 s, then to
/// the nearest minute (128 s is "2 min", not the "3 min" rounding up gave), and past an hour hours + minutes.
String _roundedSpan(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  if (s < 10) return t('${s < 1 ? 1 : s} ث', '${s < 1 ? 1 : s} s');
  if (s < 60) return t('${(s / 5).round() * 5} ث', '${(s / 5).round() * 5} s');
  if (s < 90) return t('${(s / 10).round() * 10} ث', '${(s / 10).round() * 10} s');
  final m = (s / 60).round();
  if (m < 60) return t('$m د', '$m min');
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? t('$h س', '$h h') : t('$h س $r د', '$h h $r min');
}

/// "about 2 min" for an estimate in seconds (rounded as [_roundedSpan]).
String hubDuration(int? seconds) {
  if (seconds == null) return t('غير معروف', 'unknown');
  return t('نحو ${_roundedSpan(seconds)}', 'about ${_roundedSpan(seconds)}');
}

/// "45 s" / "2 min" / "1 h 5 min": a duration without "about" (the ends of a range), rounded as [_roundedSpan].
String hubSpan(int seconds) => _roundedSpan(seconds);

/// A size kept as one unbreakable left-to-right unit ("1.1 GB", never "1.1" on one line and "GB" on the next, and
/// never "GB 1.1" in Arabic): the space becomes a no-break space, the whole a left-to-right isolate.
String hubSizeUnit(String size) => size == '—' ? size : ltrIsolate(size.replaceAll(' ', '\u00A0'));

/// The variant of a model ("int8", "fp32", "v1"): its version without the trailing commit hash ("int8-2c4055b" ->
/// "int8"), else the first word of its quantisation.
String hubVariant(String version, [String? quantization]) {
  final v = version.replaceFirst(RegExp(r'-[0-9a-f]{7,}$'), '');
  if (v.isNotEmpty) return v;
  final q = (quantization ?? '').trim();
  return q.isEmpty ? '' : q.split(RegExp(r'[\s(]')).first;
}

/// A ref ("multilingual-e5-small@int8-761b726") as the page names it: "multilingual-e5-small · int8".
String hubRefLabel(String ref) {
  final at = ref.indexOf('@');
  if (at <= 0) return ref;
  final v = hubVariant(ref.substring(at + 1));
  return v.isEmpty ? ref.substring(0, at) : hubLtr('${ref.substring(0, at)} · $v');
}

/// A model's name as the page shows it: with its variant ("multilingual-e5-small · int8") when another model of
/// [role] shares the name (int8 and fp32 builds of one model), so "Active" and "Previous" can be told apart. A model
/// the library lacks is named from its [ref].
String hubModelLabel(HubModel? m, {HubRole? role, String? ref}) {
  if (m == null) return ref == null || ref.isEmpty ? '' : hubRefLabel(ref);
  final twin = role != null && role.models.any((o) => o.id != m.id && o.name == m.name);
  if (!twin) return m.name;
  final v = hubVariant(m.version, m.quantization);
  return v.isEmpty ? m.name : hubLtr('${m.name} · $v');
}

/// The download's one line: "Downloading… 43% · 12 MB/s · 2 min left" / "Paused · 43%" / "Waiting to start…".
String hubDownloadLine(HubDownload d) {
  final pct = d.fraction == null ? '' : hubLtr('${(d.fraction! * 100).floor()}%');
  if (d.paused) return [t('متوقف مؤقتاً', 'Paused'), if (pct.isNotEmpty) pct].join(' · ');
  if (d.status == 'queued') return [t('بانتظار البدء…', 'Waiting to start…'), if (pct.isNotEmpty && d.bytesDone > 0) pct].join(' · ');
  final rest = [if (pct.isNotEmpty) pct, if (hubSpeed(d.speedBps).isNotEmpty) hubSpeed(d.speedBps), if (hubEta(d.etaS).isNotEmpty) hubEta(d.etaS)];
  return [t('جارٍ التنزيل…', 'Downloading…'), if (rest.isNotEmpty) rest.join(' · ')].join(' ');
}

/// The model's short name for a download (its ref without the version when the row is not known).
String hubDownloadName(HubDownload d, [HubModel? m]) {
  if (m != null) return m.name;
  final r = d.ref ?? '';
  final at = r.indexOf('@');
  return at > 0 ? r.substring(0, at) : (r.isEmpty ? t('نموذج', 'Model') : r);
}

/// Who made an audit row: "You", "User #12", or "The model server" (actor null).
String hubActor(int? actor, int? me) {
  if (actor == null) return t('خادم النماذج', 'The model server');
  if (actor == me) return t('أنت', 'You');
  return t('المستخدم #$actor', 'User #$actor');
}

/// The one-line result of a health test: "Passed · 10.4 / s · loaded in 3.8 s · 523 MB".
String hubTestLine(HubTest test) {
  final parts = <String>[
    test.ok ? t('نجح', 'Passed') : t('فشل', 'Failed'),
    if (test.speed != null && test.speed! > 0) '${test.speed!.toStringAsFixed(test.speed! >= 100 ? 0 : 1)} ${t('/ث', '/ s')}',
    if (test.loadMs != null && test.loadMs! > 0) t('التحميل ${(test.loadMs! / 1000).toStringAsFixed(1)} ث', 'loaded in ${(test.loadMs! / 1000).toStringAsFixed(1)} s'),
    if (test.rssMb != null && test.rssMb! > 0) hubMb(test.rssMb!),
  ];
  return parts.join(' · ');
}

/// Why a check failed, from its fields (the server's `reason` when it gives one).
String hubCheckLine(HubCheck c) {
  final name = switch (c.name) {
    'ram' => t('الذاكرة', 'Memory'),
    'cpu' => t('المعالج', 'Processor'),
    'files' => t('الملفات', 'Files'),
    _ => c.name,
  };
  final why = c.reason ?? (c.raw['problems'] is List && (c.raw['problems'] as List).isNotEmpty ? (c.raw['problems'] as List).join(', ') : null);
  return why == null ? name : '$name: ${bidiIsolate(why)}';
}
