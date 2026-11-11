// lib/features/shared/certificates_issue/cert_issue_photos.dart
//
// The "Student photos" step of issuing (D-386): the design holds a student photo and some recipients have none (a
// non-user, or a registered person without a profile picture). Each one gets a photo through the shared cropper, or
// many at once matched by file name; the issue button stays blocked until everyone required has one. [CertPhotoCollector]
// holds the state, [IssuePhotosHeader] and [IssuePhotoRow] are the plain-values screens.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_image_cropper.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_tokens.dart';
import 'cert_issue_api.dart';
import 'cert_issue_logic.dart';
import 'cert_issue_parts.dart' show IssueErrorBox;
import 'cert_issue_photo_logic.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

const int kMaxPhotoBytes = 8 * 1024 * 1024;

/// What a bulk upload did, stated plainly.
class PhotoBulkReport {
  const PhotoBulkReport({this.uploaded = 0, this.failed = 0, this.unmatched = const [], this.ambiguous = const []});
  final int uploaded, failed;
  final List<String> unmatched, ambiguous;

  String get summary {
    final parts = [
      _t('تم رفع $uploaded', '$uploaded uploaded'),
      if (failed > 0) _t('تعذّر رفع $failed', '$failed failed'),
      if (unmatched.isNotEmpty) _t('${unmatched.length} بلا تطابق', '${unmatched.length} matched nobody'),
      if (ambiguous.isNotEmpty) _t('${ambiguous.length} تشبه أكثر من شخص', '${ambiguous.length} fit several people'),
    ];
    return parts.join(' · ');
  }

  bool get allGood => failed == 0 && unmatched.isEmpty && ambiguous.isEmpty;
}

class CertPhotoCollector extends ChangeNotifier {
  CertPhotoCollector({required this.api, this.onPhoto});

  final CertIssueApi api;

  /// A person got a photo (the flow writes it into the row).
  final void Function(String key, String url)? onPhoto;

  String photoMode = 'required';
  List<IssuePhotoPerson> people = const [];
  Set<String> missing = {};
  final Map<String, String> urls = {};
  final Map<String, Uint8List> previews = {};
  final Set<String> uploading = {};
  bool bulkBusy = false;
  PhotoBulkReport? report;

  bool get required => photoMode == 'required';
  List<IssuePhotoPerson> get outstanding => [for (final p in people) if (missing.contains(p.key) && urls[p.key] == null) p];
  bool get blocked => required && outstanding.isNotEmpty;

  void setPeople(List<IssuePhotoPerson> list, {required Set<String> missing, String photoMode = 'required'}) {
    people = list;
    this.missing = missing;
    this.photoMode = photoMode;
    notifyListeners();
  }

  Future<void> _store(IssuePhotoPerson p, Uint8List bytes, String name) async {
    final url = await api.uploadPhoto(bytes, name);
    urls[p.key] = url;
    previews[p.key] = bytes;
    onPhoto?.call(p.key, url);
  }

  /// One person: pick, crop with the shared cropper, upload.
  Future<void> pickOne(BuildContext context, IssuePhotoPerson p) async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null || !context.mounted) return;
    try {
      final bytes = await picked.readAsBytes();
      if (!context.mounted) return;
      final cropped = await showAppImageCropper(context, bytes, shape: CropShape.square, allowShapeChange: false, allowTransparent: false); // the server stores a JPEG
      if (cropped == null) return;
      uploading.add(p.key);
      notifyListeners();
      await _store(p, cropped, picked.name);
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
    uploading.remove(p.key);
    notifyListeners();
  }

  /// Many at once: the file names say who is who ([certMatchPhotoFiles]). Files are not cropped here: the
  /// certificate fits them to the photo frame, centred.
  Future<void> pickBulk() async {
    if (bulkBusy) return;
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return;
    bulkBusy = true;
    report = null;
    notifyListeners();
    final match = certMatchPhotoFiles([for (final f in picked) f.name], outstanding);
    var uploaded = 0, failed = 0;
    final queue = match.byPerson.entries.toList();
    final people = {for (final p in this.people) p.key: p};
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final e = queue.removeLast();
        final f = picked[e.value];
        final person = people[e.key];
        if (person == null) continue;
        uploading.add(e.key);
        notifyListeners();
        try {
          final bytes = await f.readAsBytes();
          if (bytes.length > kMaxPhotoBytes) throw StateError('too big');
          await _store(person, bytes, f.name);
          uploaded++;
        } catch (_) {
          failed++;
        }
        uploading.remove(e.key);
        notifyListeners();
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
    bulkBusy = false;
    report = PhotoBulkReport(uploaded: uploaded, failed: failed, unmatched: match.unmatched, ambiguous: match.ambiguous);
    notifyListeners();
  }
}

/// The step's header: what is needed, how far along, one primary action.
class IssuePhotosHeader extends StatelessWidget {
  const IssuePhotosHeader({super.key, required this.required, required this.total, required this.done, required this.busy, required this.onBulk, this.report});

  final bool required;
  final int total, done;
  final bool busy;
  final VoidCallback onBulk;
  final PhotoBulkReport? report;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final left = total - done;
    final finished = left <= 0;
    final progress = total == 0 ? 1.0 : done / total;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(_t('صور الطلاب', 'Student photos'), style: AppType.pageTitle(context)),
      const SizedBox(height: AppSpace.xxs),
      Text(
        required
            ? _t('هذا التصميم يحتوي على صورة الطالب. لن تُصدر شهادة بصورة رمادية: أضف صورة لكل شخص بلا صورة حساب.',
                'This design holds a student photo. No certificate is printed with a grey picture: add one for each person without a profile photo.')
            : _t('صورة الطالب اختيارية في هذا التصميم: من تضيف صورته تظهر، وتبقى مساحة الصورة فارغة لمن لا صورة له.',
                'The student photo is optional in this design: people with a photo show it, the others keep the space empty.'),
        style: AppType.meta(context),
      ),
      const SizedBox(height: AppSpace.md),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: Text(
                finished ? _t('كل الصور جاهزة', 'Every photo is ready') : _t('تبقى $left من $total', '$left of $total to go'),
                style: AppType.section(context),
              ),
            ),
            Text('$done / $total', style: AppType.row(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: AppSpace.xs),
          ClipRRect(
            borderRadius: AppRadius.chipAll,
            child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: c.divider, color: finished ? c.success : c.primary),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            key: const ValueKey('cert-photos-bulk'),
            onPressed: busy ? null : onBulk,
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.photo_library_outlined, size: AppIconSize.md),
            label: Text(busy ? _t('جارٍ الرفع…', 'Uploading…') : _t('رفع عدة صور معًا', 'Upload several photos')),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            _t('سمِّ كل ملف باسم الشخص أو رقمه (مثل 1024.jpg). تُوضع الصور وسط إطار الصورة تلقائيًا.',
                "Name each file after the person's name or number (like 1024.jpg). Photos are centred in the frame automatically."),
            style: AppType.meta(context),
          ),
          if (report != null) ...[
            const SizedBox(height: AppSpace.sm),
            AppBanner(
              icon: report!.allGood ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
              text: report!.summary +
                  (report!.unmatched.isEmpty ? '' : '\n${_t('بلا تطابق', 'No match')}: ${report!.unmatched.take(8).join('، ')}') +
                  (report!.ambiguous.isEmpty ? '' : '\n${_t('تشبه أكثر من شخص', 'Fit several people')}: ${report!.ambiguous.take(8).join('، ')}'),
            ),
          ],
        ]),
      ),
    ]);
  }
}

/// One person: who, whether their photo is in, the upload action.
class IssuePhotoRow extends StatelessWidget {
  const IssuePhotoRow({super.key, required this.person, required this.onUpload, this.preview, this.url, this.uploading = false});

  final IssuePhotoPerson person;
  final Uint8List? preview;
  final String? url;
  final bool uploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = preview != null || url != null;
    final Widget avatar = preview != null
        ? ClipOval(child: Image.memory(preview!, width: 44, height: 44, fit: BoxFit.cover, cacheWidth: 132))
        : AppAvatar(name: person.name.isEmpty ? '?' : person.name, url: person.studentImage ?? url, size: 44);
    final ids = person.identifiers.where((v) => v.trim().isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        child: Row(children: [
          avatar,
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              const SizedBox(height: 2),
              Text(
                done ? _t('الصورة جاهزة', 'Photo added') : (ids.isNotEmpty ? ids.first : _t('بحاجة إلى صورة', 'Needs a photo')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: done ? c.success : c.textMedium),
              ),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          SizedBox(
            height: AppTouch.min,
            child: uploading
                ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2)))
                : OutlinedButton(
                    onPressed: onUpload,
                    child: Text(done ? _t('تغيير', 'Replace') : _t('رفع', 'Upload')),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// One person's photo outside the flow (re-issue, a person added to a saved list with "issue now"): pick, crop, upload.
Future<String?> certAskOnePhoto(BuildContext context, CertIssueApi api, String name) async {
  final ok = await appConfirm(
    context,
    message: _t('يحتاج التصميم إلى صورة $name قبل الإصدار. اختر صورة الآن؟', 'The design needs a photo of $name before issuing. Choose one now?'),
    confirmLabel: _t('اختيار صورة', 'Choose a photo'),
  );
  if (!ok || !context.mounted) return null;
  final picked = await FilePicker.pickFile(type: FileType.image);
  if (picked == null || !context.mounted) return null;
  try {
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return null;
    final cropped = await showAppImageCropper(context, bytes, shape: CropShape.square, allowShapeChange: false, allowTransparent: false); // the server stores a JPEG
    if (cropped == null) return null;
    return await api.uploadPhoto(cropped, picked.name);
  } catch (e) {
    showAppNotice(certIssueErrorText(e), error: true);
    return null;
  }
}

/// A full page collecting the photos a server `photos_required` error named (a saved list's Issue). Returns index →
/// photo url, null when left without finishing.
Future<Map<int, String>?> certCollectPhotos(BuildContext context, CertIssueApi api, List<Map<String, dynamic>> missing) =>
    Navigator.of(context).push<Map<int, String>>(MaterialPageRoute(builder: (_) => _CollectPage(api: api, missing: missing)));

class _CollectPage extends StatefulWidget {
  const _CollectPage({required this.api, required this.missing});
  final CertIssueApi api;
  final List<Map<String, dynamic>> missing;

  @override
  State<_CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends State<_CollectPage> {
  late final CertPhotoCollector _photos = CertPhotoCollector(api: widget.api);

  @override
  void initState() {
    super.initState();
    final people = [
      for (final m in widget.missing)
        IssuePhotoPerson(key: '${m['index']}', name: '${m['name'] ?? ''}', studentId: (m['student_id'] as num?)?.toInt()),
    ];
    _photos.setPeople(people, missing: {for (final p in people) p.key});
  }

  @override
  void dispose() {
    _photos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: _t('صور الطلاب', 'Student photos')),
      body: AnimatedBuilder(
        animation: _photos,
        builder: (context, _) => Column(children: [
          Expanded(child: IssuePhotosBody(photos: _photos)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _photos.blocked
                      ? null
                      : () => Navigator.pop(context, {for (final e in _photos.urls.entries) int.parse(e.key): e.value}),
                  child: Text(_t('متابعة الإصدار', 'Continue issuing')),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Header + the people, centred on wide windows. The flow's step body and the saved list's page.
class IssuePhotosBody extends StatelessWidget {
  const IssuePhotosBody({super.key, required this.photos, this.loading = false, this.error, this.onRetry});

  final CertPhotoCollector photos;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(padding: AppSpace.card, child: Align(alignment: Alignment.topCenter, child: IssueErrorBox(message: error!, onRetry: onRetry ?? () {})));
    }
    if (loading) return const AppListSkeleton(items: 4);
    final total = photos.people.where((p) => photos.missing.contains(p.key)).length;
    final done = total - photos.outstanding.length;
    final list = [...photos.outstanding, ...photos.people.where((p) => !photos.outstanding.contains(p))];
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
        child: ListView.builder(
          key: const ValueKey('cert-photos-list'),
          padding: const EdgeInsets.all(AppSpace.md),
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: IssuePhotosHeader(
                  required: photos.required,
                  total: total,
                  done: done,
                  busy: photos.bulkBusy,
                  report: photos.report,
                  onBulk: () => unawaited(photos.pickBulk()),
                ),
              );
            }
            final p = list[i - 1];
            return IssuePhotoRow(
              key: ValueKey(p.key),
              person: p,
              preview: photos.previews[p.key],
              url: photos.urls[p.key],
              uploading: photos.uploading.contains(p.key),
              onUpload: () => unawaited(photos.pickOne(context, p)),
            );
          },
        ),
      ),
    );
  }
}
