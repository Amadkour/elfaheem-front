// "Add papers": ONE sheet that says where the answer sheets come from, for both paper kinds — bubble sheets
// (omr_upload_screen.dart) and written-answer / QR sheets (exam_scan_review.dart) — and for one replacement page.
// Only what works on this device is offered, never a dead button:
//
//                       camera*   gallery                    files            folder
//   Android app          ✓        image_picker (Photo        file_picker      the system folder picker (Storage Access
//                                 Picker, no permission)                      Framework, ScanFolderChannel.kt)
//   iOS app              ✓        image_picker (PHPicker,    file_picker      — (no folder access: the sheet says to
//                                 HEIC → JPEG)               (Files app)        choose Files and select its pages)
//   phone browser        ✓        <input accept=image/*      file_picker      — (phones' browsers ignore
//                                 multiple>: Photos/Camera                      webkitdirectory; same hint)
//   computer browser     ✓        —                          file_picker      <input webkitdirectory>
//   desktop app          ✓        —                          file_picker      getDirectoryPath + dart:io
//   (* the live camera only on the bubble-sheet path: omr_scanner_screen.dart)
//
// A tap starts the platform picker INSIDE the tap (a browser opens a file dialog only on a user gesture), then the
// sheet closes. What was picked is not read yet: scan_files.dart plans and sends it.
library;


import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../admin/admin_common.dart' show t;
import 'scan_files.dart';
import 'scan_folder_io.dart' if (dart.library.js_interop) 'scan_folder_web.dart' as folders;
import 'scan_prepare.dart';

enum ScanSource { camera, gallery, files, folder }

/// Where the app runs, for which sources work. Tests pass their own.
@immutable
class ScanPlatform {
  const ScanPlatform({required this.web, required this.os, this.folderBuild = true});

  factory ScanPlatform.current() => ScanPlatform(web: kIsWeb, os: defaultTargetPlatform, folderBuild: folders.scanFolderSupported);

  final bool web;
  final TargetPlatform os;

  /// The build has a folder picker (false only where the platform code is missing).
  final bool folderBuild;

  bool get phone => os == TargetPlatform.android || os == TargetPlatform.iOS;

  /// The photo gallery: the phone apps (image_picker) and phones' browsers (an image input opens Photos / Camera).
  bool get gallery => phone;

  /// A whole folder: a computer's browser, the desktop apps, the Android app.
  bool get folder => folderBuild && (web ? !phone : (os == TargetPlatform.android || os == TargetPlatform.windows || os == TargetPlatform.macOS || os == TargetPlatform.linux));

  /// Why the folder is not offered, with what to do instead (null when it is).
  String? get folderHint {
    if (folder) return null;
    if (!web && os == TargetPlatform.iOS) {
      return t('لرفع مجلد كامل من الآيفون: اختر «الملفات»، افتح المجلد، اضغط «تحديد» ثم اختر صفحاته.',
          'To send a whole folder from an iPhone: choose Files, open the folder, tap Select and choose its pages.');
    }
    if (web && phone) {
      return t('متصفح الهاتف لا يرفع مجلدًا كاملًا: اختر «الملفات» وحدد صفحات المجلد، أو استخدم حاسوبًا.',
          "A phone's browser cannot send a whole folder: choose Files and select the folder's pages, or use a computer.");
    }
    return null;
  }
}

/// The sources the sheet offers, in order. [single] = one page (a replacement): no camera, no folder.
List<ScanSource> scanSourcesFor(ScanPlatform p, {required bool camera, bool single = false}) => [
      if (camera && !single) ScanSource.camera,
      if (p.gallery) ScanSource.gallery,
      ScanSource.files,
      if (p.folder && !single) ScanSource.folder,
    ];

/// What was picked: the files (not read yet) and the folder's name for a folder.
class ScanPick {
  const ScanPick(this.source, this.files, {this.folder});
  final ScanSource source;
  final List<ScanSourceFile> files;
  final String? folder;

  /// The plan of this pick (scan order: a gallery keeps the order the photos were chosen in).
  ScanPlan plan() => planScanFiles(files, folder: folder, sort: source != ScanSource.gallery);
}

typedef ScanSourcePicker = Future<ScanPick?> Function(ScanSource source, {bool single});

const _imageOnly = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'];

ScanSourceFile _platformFile(PlatformFile f, {bool photo = false}) =>
    ScanSourceFile(name: f.name, size: f.lengthSync(), read: f.readAsBytes, photo: photo);

/// The device's pickers.
Future<ScanPick?> pickScanSource(ScanSource source, {bool single = false}) async {
  switch (source) {
    case ScanSource.camera:
      return const ScanPick(ScanSource.camera, []);
    case ScanSource.gallery:
      if (kIsWeb) {
        // a phone's browser: accept=image/* opens Photos (and the camera). The photo is sent as the browser gives it
        // (a JPEG; Safari turns HEIC into JPEG for an image input): re-encoding in the page costs seconds per photo.
        final picked = single
            ? [?await FilePicker.pickFile(type: FileType.image)]
            : await FilePicker.pickFiles(type: FileType.image);
        return picked.isEmpty ? null : ScanPick(source, [for (final f in picked) _platformFile(f)]);
      }
      // the app: the system photo picker scales the photo natively (no 48 MP decode in Dart) and turns HEIC into JPEG
      final ip = ImagePicker();
      const side = kScanPhotoMaxSide * 1.0;
      final picked = single
          ? [?await ip.pickImage(source: ImageSource.gallery, maxWidth: side, maxHeight: side, imageQuality: 92, requestFullMetadata: false)]
          : await ip.pickMultiImage(maxWidth: side, maxHeight: side, imageQuality: 92, requestFullMetadata: false);
      if (picked.isEmpty) return null;
      return ScanPick(source, [
        for (final x in picked) ScanSourceFile(name: x.name, read: x.readAsBytes, photo: true),
      ]);
    case ScanSource.files:
      final ext = single ? _imageOnly : kScanPickExtensions;
      final picked = single
          ? [?await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ext)]
          : await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ext);
      return picked.isEmpty ? null : ScanPick(source, [for (final f in picked) _platformFile(f)]);
    case ScanSource.folder:
      final r = await folders.pickScanFolder(title: t('اختر مجلد الماسح الضوئي', "Choose the scanner's folder"));
      return r == null ? null : ScanPick(source, r.files, folder: r.name);
  }
}

/// Opens the sheet; null when nothing was picked. The camera choice comes back as `ScanPick(camera, [])`: the caller
/// opens the scanner.
Future<ScanPick?> showScanSourceSheet(
  BuildContext context, {
  bool camera = false,
  bool single = false,
  String? title,
  ScanPlatform? platform,
  ScanSourcePicker? picker,
}) async {
  final started = await showAppSheet<Future<ScanPick?>>(
      context,
      (_) => ScanSourceSheet(
            camera: camera,
            single: single,
            title: title,
            platform: platform ?? ScanPlatform.current(),
            picker: picker ?? pickScanSource,
          ));
  if (started == null) return null;
  try {
    return await started;
  } catch (e) {
    showAppNotice(scanPickErrorText(e), error: true);
    return null;
  }
}

/// A picker that failed, in plain words.
String scanPickErrorText(Object e) {
  if (e is folders.ScanFolderError) {
    return e.code == 'unsupported'
        ? t('هذا الإصدار من التطبيق لا يفتح المجلدات — اختر «الملفات»', 'This version of the app cannot open folders — choose Files')
        : t('تعذّر فتح المجلد — جرّب مجلدًا آخر أو اختر «الملفات»', 'The folder could not be opened — try another one, or choose Files');
  }
  final s = '$e'.toLowerCase();
  if (s.contains('denied') || s.contains('permission')) {
    return t('لا يوجد إذن للوصول إلى الصور — اسمح به من إعدادات الجهاز', 'No access to the photos — allow it in the device settings');
  }
  return t('تعذّر فتح المصدر — حاول مرة أخرى', 'That source could not be opened — try again');
}

/// One page (a replacement): Gallery (phones) and Files, images only; the photo prepared like an upload's.
/// [pageLabel]: the page it replaces, named as its card names it ("A clearer image of page 7" in the review queue,
/// whose sentences say "Page 7 is too blurry"; "… of paper 7" with [paper], from a batch's "Paper 7" card).
Future<List<(String, Uint8List)>> pickOneScanPage(BuildContext context,
    {ScanPlatform? platform, ScanSourcePicker? picker, String? pageLabel, bool paper = false}) async {
  final pick = await showScanSourceSheet(context,
      single: true,
      title: pageLabel == null || pageLabel.isEmpty
          ? t('صورة أوضح للصفحة', 'A clearer image of the page')
          : paper
              ? t('صورة أوضح للورقة $pageLabel', 'A clearer image of paper $pageLabel')
              : t('صورة أوضح للصفحة $pageLabel', 'A clearer image of page $pageLabel'),
      platform: platform,
      picker: picker);
  if (pick == null || pick.files.isEmpty) return const [];
  try {
    return (await prepareScanFile(pick.files.first)).take(1).toList();
  } on ScanPrepareError catch (e) {
    showAppNotice(scanPrepareErrorText(e.code), error: true);
    return const [];
  }
}

/// A file that could not be prepared, in plain words (scan_files.dart ScanPrepareError codes).
String scanPrepareErrorText(String code) => switch (code) {
      'heic' => t('صورة HEIC لا يفتحها هذا الجهاز — احفظها بصيغة JPEG', 'A HEIC photo this device cannot open — save it as JPEG'),
      'tiff' => t('تعذّر فتح ملف TIFF — احفظ المسح بصيغة PDF أو JPEG', 'The TIFF could not be opened — save the scan as PDF or JPEG'),
      'decode' => t('تعذّر فتح الصورة', 'The image could not be opened'),
      'unsupported' => t('ليس صورة ولا ملف PDF', 'Not an image or a PDF'),
      'too_large' => t('أكبر من 25 ميجابايت', 'Larger than 25 MB'),
      _ => t('تعذّرت قراءة الملف', 'The file could not be read'),
    };

class ScanSourceSheet extends StatelessWidget {
  const ScanSourceSheet({
    super.key,
    required this.platform,
    required this.picker,
    this.camera = false,
    this.single = false,
    this.title,
  });

  final ScanPlatform platform;
  final ScanSourcePicker picker;
  final bool camera, single;
  final String? title;

  ({IconData icon, String title, String subtitle}) _info(ScanSource s) => switch (s) {
        ScanSource.camera => (
            icon: Icons.document_scanner_outlined,
            title: t('التصوير بالكاميرا', 'Scan with the camera'),
            subtitle: t('يلتقط كل ورقة وحده عند ثباتها ووضوحها', 'Captures each sheet by itself when it is steady and sharp'),
          ),
        ScanSource.gallery => (
            icon: Icons.photo_library_outlined,
            title: t('معرض الصور', 'Photo gallery'),
            subtitle: single
                ? t('اختر صورة من صور الهاتف', "Pick a photo from the phone's photos")
                : t('اختر صورة أو عدة صور للأوراق من صور الهاتف', "Pick one or many photos of the papers from the phone's photos"),
          ),
        ScanSource.files => (
            icon: Icons.upload_file_rounded,
            title: t('الملفات', 'Files'),
            subtitle: single
                ? t('صورة JPG أو PNG أو WebP أو HEIC', 'A JPG, PNG, WebP or HEIC image')
                : t('صور وملفات PDF معًا، عدة ملفات دفعة واحدة', 'Images and PDFs together, many at once'),
          ),
        ScanSource.folder => (
            icon: Icons.folder_open_rounded,
            title: t('مجلد الماسح الضوئي', "A scanner's folder"),
            subtitle: t('كل الصور وملفات PDF داخله، مع المجلدات الفرعية، بترتيب أسماء الملفات',
                'Every image and PDF inside it, sub-folders too, in file-name order'),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sources = scanSourcesFor(platform, camera: camera, single: single);
    final hint = single ? null : platform.folderHint;
    return AppSheetContent(
      title: title ?? t('إضافة أوراق الإجابة', 'Add answer sheets'),
      children: [
        Text(single ? t('من أين تأتي الصورة؟', 'Where does the image come from?') : t('من أين تأتي الصفحات؟', 'Where do the pages come from?'),
            key: const ValueKey('scan.src.question'), style: appText(13.5, c: c.textMedium, h: 1.35)),
        const SizedBox(height: AppSpace.sm),
        for (final s in sources)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: _SourceTile(
              key: ValueKey('scan.src.${s.name}'),
              icon: _info(s).icon,
              title: _info(s).title,
              subtitle: _info(s).subtitle,
              onTap: () {
                // the platform dialog opens inside this tap (the web's user-gesture rule), then the sheet closes
                final started = s == ScanSource.camera ? Future<ScanPick?>.value(const ScanPick(ScanSource.camera, [])) : picker(s, single: single);
                Navigator.of(context).pop(started);
              },
            ),
          ),
        if (hint != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 18, color: c.textMedium),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(hint, key: const ValueKey('scan.src.hint'), style: appText(12.5, c: c.textMedium, h: 1.4))),
          ]),
        ],
        const SizedBox(height: AppSpace.sm),
        Text(
          single
              ? t('صورة واحدة حتى 25 ميجابايت', 'One image, up to 25 MB')
              : t('JPG وPNG وWebP وHEIC وTIFF وPDF · حتى 25 ميجابايت للملف · الصفحات المرفوعة من قبل تُتخطّى',
                  'JPG, PNG, WebP, HEIC, TIFF and PDF · up to 25 MB a file · pages uploaded before are skipped'),
          style: appText(12, c: c.textLight, h: 1.4),
        ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: Icon(icon, color: appInk(context, c.primary)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: appText(14.5, w: FontWeight.w700, c: c.textDark)),
              const SizedBox(height: 2),
              Text(subtitle, style: appText(12.5, c: c.textMedium, h: 1.3)),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          Icon(Icons.chevron_right_rounded, color: c.textMedium),
        ]),
      ),
    );
  }
}
