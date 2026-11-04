// lib/features/shared/rag/admin/rag_console_settings.dart
//
// The settings D-190 added to the RAG console (FRONT_CONTRACTS "Upload settings", "Learning"), as one card of the
// Settings tab, all through PUT /api/v1/rag/admin/settings (flat keys; the server merges and bounds them):
//
//   answer_mode             generate | retrieval   (retrieval: the matching passages with their source and page, no writer)
//   ocr_scanned             bool                   (OCR scanned PDF pages and photos; off: a fully scanned PDF is refused)
//   max_doc_mb              1-500                  (the largest upload)
//   learning.embedder_auto  bool + learning.embedder_min_new 10-100000   (retrain the search model on a schedule)
//   POST /api/v1/rag/learning/embedder/train       "Train the search model now" (platform admin)
//
// Pure, unit-tested: [RagExtraSettings]. Presentational, under the layout harness: [RagExtraSettingsCard].
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../admin/admin_common.dart' show asBool, asInt, asMap, asStr, shortDateTime, t;
import '../rag_learning.dart' show EmbedderJob;

class RagExtraSettings {
  const RagExtraSettings({this.answerMode = 'generate', this.ocrScanned = false, this.maxDocMb = 30, this.embedderAuto = false, this.embedderMinNew = 200, this.present = false});

  /// The settings object of `GET /admin/settings` (`settings`); [present] = the server sent the D-190 keys at all
  /// (an older server does not, and the card is hidden).
  factory RagExtraSettings.fromJson(Object? settings) {
    final s = asMap(settings);
    return RagExtraSettings(
      answerMode: asStr(s['answer_mode']) == 'retrieval' ? 'retrieval' : 'generate',
      ocrScanned: asBool(s['ocr_scanned']),
      maxDocMb: asInt(s['max_doc_mb'], 30).clamp(1, maxDocMbLimit),
      embedderAuto: asBool(s['learning.embedder_auto']),
      embedderMinNew: asInt(s['learning.embedder_min_new'], 200).clamp(10, 100000),
      present: s.containsKey('answer_mode') || s.containsKey('max_doc_mb') || s.containsKey('ocr_scanned'),
    );
  }

  static const maxDocMbLimit = 500;

  final String answerMode;
  final bool ocrScanned, embedderAuto, present;
  final int maxDocMb, embedderMinNew;

  Map<String, dynamic> toJson() => {
        'answer_mode': answerMode,
        'ocr_scanned': ocrScanned,
        'max_doc_mb': maxDocMb,
        'learning.embedder_auto': embedderAuto,
        'learning.embedder_min_new': embedderMinNew,
      };

  RagExtraSettings copyWith({String? answerMode, bool? ocrScanned, int? maxDocMb, bool? embedderAuto, int? embedderMinNew}) => RagExtraSettings(
        answerMode: answerMode ?? this.answerMode,
        ocrScanned: ocrScanned ?? this.ocrScanned,
        maxDocMb: maxDocMb ?? this.maxDocMb,
        embedderAuto: embedderAuto ?? this.embedderAuto,
        embedderMinNew: embedderMinNew ?? this.embedderMinNew,
        present: present,
      );
}

String embedderJobText(EmbedderJob j) {
  final what = switch (j.state) {
    'queued' => t('تدريب نموذج البحث في الانتظار', 'Search-model training is queued'),
    'running' => t('يجري تدريب نموذج البحث…', 'The search model is training…'),
    'done' || 'succeeded' || 'completed' => t('انتهى آخر تدريب لنموذج البحث', 'The last search-model training finished'),
    'skipped' => t('تخطّى آخر تدريب لنموذج البحث', 'The last search-model training was skipped'),
    'failed' || 'error' => t('فشل آخر تدريب لنموذج البحث', 'The last search-model training failed'),
    _ => j.state,
  };
  return [what, if (j.detail.isNotEmpty) j.detail, if (j.at != null) shortDateTime(j.at)].join(' · ');
}

class RagExtraSettingsCard extends StatefulWidget {
  const RagExtraSettingsCard({super.key, required this.settings, required this.onSave, this.onTrain, this.job, this.training = false, this.canEdit = true});
  final RagExtraSettings settings;
  final ValueChanged<Map<String, dynamic>> onSave;

  /// "Train the search model now" (null hides it: an older server or the learning kill switch).
  final VoidCallback? onTrain;
  final EmbedderJob? job;
  final bool training, canEdit;

  @override
  State<RagExtraSettingsCard> createState() => _RagExtraSettingsCardState();
}

class _RagExtraSettingsCardState extends State<RagExtraSettingsCard> {
  late RagExtraSettings _s = widget.settings;
  late final _mb = TextEditingController(text: '${_s.maxDocMb}');
  late final _min = TextEditingController(text: '${_s.embedderMinNew}');
  String? _problem;

  @override
  void dispose() {
    _mb.dispose();
    _min.dispose();
    super.dispose();
  }

  void _save() {
    final mb = int.tryParse(_mb.text.trim());
    final mn = int.tryParse(_min.text.trim());
    if (mb == null || mb < 1 || mb > RagExtraSettings.maxDocMbLimit) {
      return setState(() => _problem = t('حجم الملف بين 1 و 500 ميغابايت', 'The file size is between 1 and 500 MB'));
    }
    if (mn == null || mn < 10 || mn > 100000) {
      return setState(() => _problem = t('الحد الأدنى للإشارات الجديدة بين 10 و 100000', 'The minimum of new signals is between 10 and 100000'));
    }
    setState(() => _problem = null);
    widget.onSave(_s.copyWith(maxDocMb: mb, embedderMinNew: mn).toJson());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final job = widget.job;
    return AppCard(
      key: const ValueKey('rag_extra_settings'),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionTitle(t('الإجابة والرفع والتعلّم', 'Answers, uploads and learning')),
        const SizedBox(height: AppSpace.xs),
        AppDropdown<String>(
          value: _s.answerMode,
          decoration: InputDecoration(labelText: t('طريقة الإجابة', 'Answer mode')),
          items: [
            DropdownMenuItem(value: 'generate', child: Text(t('توليد إجابة', 'Generate an answer'), maxLines: 1, overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'retrieval', child: Text(t('عرض المقاطع المطابقة', 'Show the matching passages'), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _s = _s.copyWith(answerMode: v)),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
          child: Text(
              _s.answerMode == 'retrieval'
                  ? t('يعرض المساعد أقرب المقاطع مع مصدرها وصفحتها دون أن يكتب إجابة.', 'The assistant shows the closest passages with their source and page, and writes no answer.')
                  : t('يكتب المساعد إجابة من المصادر ويراجعها.', 'The assistant writes an answer from the sources and checks it.'),
              style: appText(12, c: c.textLight)),
        ),
        const SizedBox(height: AppSpace.xs),
        AppSwitchTile(
            title: t('قراءة الصفحات الممسوحة ضوئياً (OCR)', 'Read scanned pages (OCR)'),
            subtitle: t('مفعّل: تُقرأ صفحات PDF الممسوحة والصور، وأبطأ في الرفع. معطّل: يُرفض ملف PDF ممسوح بالكامل وتُتخطى صفحاته الممسوحة الجزئية.',
                'On: scanned PDF pages and photos are read, and uploads are slower. Off: a fully scanned PDF is refused and partly scanned pages are skipped.'),
            value: _s.ocrScanned,
            onChanged: (v) => setState(() => _s = _s.copyWith(ocrScanned: v))),
        const SizedBox(height: AppSpace.xs),
        AppField(controller: _mb, label: t('أكبر حجم لملف مرفوع (ميغابايت)', 'Largest upload (MB)'), keyboard: TextInputType.number, ltr: true),
        const SizedBox(height: AppSpace.sm),
        AppSwitchTile(
            title: t('إعادة تدريب نموذج البحث تلقائياً', 'Retrain the search model automatically'),
            subtitle: t('يُدرَّب من التقييمات والإجابات الموثّقة حين تتجمّع إشارات جديدة كافية', 'Trained from feedback and verified answers once enough new signals have gathered'),
            value: _s.embedderAuto,
            onChanged: (v) => setState(() => _s = _s.copyWith(embedderAuto: v))),
        AppField(controller: _min, label: t('أقل عدد إشارات جديدة قبل التدريب', 'New signals needed before training'), keyboard: TextInputType.number, ltr: true),
        if (widget.onTrain != null) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              key: const ValueKey('train_embedder'),
              onPressed: widget.training || (job?.running ?? false) ? null : widget.onTrain,
              style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              icon: const Icon(Icons.model_training_rounded, size: 18),
              label: Text(widget.training || (job?.running ?? false) ? t('يجري التدريب…', 'Training…') : t('درّب نموذج البحث الآن', 'Train the search model now')),
            ),
            if (job != null) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(embedderJobText(job), key: const ValueKey('embedder_job'), style: appText(12, c: c.textMedium))),
          ]),
        ],
        if (_problem != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(_problem!, style: appText(12.5, c: c.danger))),
        if (widget.canEdit) ...[
          const SizedBox(height: AppSpace.sm),
          AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.save_rounded, onPressed: _save),
        ],
      ]),
    );
  }
}
