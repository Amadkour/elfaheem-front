// The files a teacher hands in for a paper exam (bubble sheets and written-answer sheets alike), from any source —
// the photo gallery, a pick of files, or a document scanner's whole folder — and how they are sent: pure logic, no
// platform, no widgets (scan_sources.dart picks, scan_prepare.dart turns a photo into what the reader needs,
// scan_upload_view.dart draws it).
//
//   • planScanFiles: what a pick holds — images, PDFs, and what is left out with the reason (a hidden / system file is
//     dropped silently, an unsupported type or an oversized file is listed). Scan order = natural file order inside
//     each folder ("page2" before "page10"), folders in natural order too.
//   • ScanUploader: sends the files in parts that fit the gateway (kScanPartBytes / kScanPartFiles), the parts after
//     the first join the first part's batch (`batch_id`, exam_engine/services/scans.py) so the teacher follows ONE
//     "X of N papers processed"; a part refused for one bad file is sent again file by file so only that file fails;
//     it keeps going past a failed part, and Retry sends only what failed.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;

/// One part of an upload: the production gateway took 10 MB per request on the engine's routes until the scans
/// location (deploy/nginx/nextbrain.conf.example) — 8 MB + the multipart overhead fits both. One file larger than this
/// still goes alone (the scans location takes 52 MB).
const kScanPartBytes = 8 * 1024 * 1024;

/// Files per part (the server takes 50; a smaller part keeps one failure small and the progress moving).
const kScanPartFiles = 20;

/// The server's limit for one file (EXAM_MAX_SCAN_BYTES).
const kScanMaxFileBytes = 25 * 1024 * 1024;

/// A pick larger than this is refused before anything is read (a wrong folder: a whole drive, a photo library).
const kScanMaxPick = 2000;

/// What a file is, by its name (its bytes are sniffed again when it is read: scan_prepare.dart).
enum ScanFileKind {
  image, // jpg / jpeg / png / webp: sent as it is (a gallery photo is scaled down first)
  pdf, // sent as it is, the server renders it page by page
  convert, // heic / heif (an iPhone photo), tif / tiff (a scanner's image): turned into JPEG on the device
  unsupported,
}

const _imageExt = {'jpg', 'jpeg', 'png', 'webp'};
const _convertExt = {'heic', 'heif', 'tif', 'tiff'};

/// The extensions the file dialogs offer.
const kScanPickExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'heic', 'heif', 'tif', 'tiff'];

String scanExtOf(String name) {
  final base = name.split(RegExp(r'[\\/]')).last;
  final i = base.lastIndexOf('.');
  return i <= 0 ? '' : base.substring(i + 1).toLowerCase();
}

ScanFileKind scanKindOf(String name) {
  final ext = scanExtOf(name);
  if (_imageExt.contains(ext)) return ScanFileKind.image;
  if (ext == 'pdf') return ScanFileKind.pdf;
  if (_convertExt.contains(ext)) return ScanFileKind.convert;
  return ScanFileKind.unsupported;
}

/// A hidden or system file a scanner / an OS leaves in a folder (never a page): `.DS_Store`, `._x.jpg` (macOS
/// resource forks), `Thumbs.db`, `desktop.ini`, `~$x` (Office lock files), anything under a hidden folder or
/// `__MACOSX`.
bool scanIsHidden(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return true;
  for (final p in parts) {
    if (p.startsWith('.') || p == '__MACOSX') return true;
  }
  final base = parts.last.toLowerCase();
  return base.startsWith(r'~$') || base == 'thumbs.db' || base == 'desktop.ini' || base == 'ehthumbs.db';
}

final _digits = RegExp(r'\d+|\D+');
final _allDigits = RegExp(r'^\d+$');

/// Natural order: "page2" < "page10", case-insensitive, then the plain order (a stable tie-break).
int naturalCompare(String a, String b) {
  final xa = _digits.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final xb = _digits.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < xa.length && i < xb.length; i++) {
    final pa = xa[i], pb = xb[i];
    int c;
    if (_allDigits.hasMatch(pa) && _allDigits.hasMatch(pb)) {
      // compare by value without overflowing: strip leading zeros, longer = larger, then by digits
      final sa = pa.replaceFirst(RegExp(r'^0+(?=\d)'), ''), sb = pb.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      c = sa.length != sb.length ? sa.length.compareTo(sb.length) : sa.compareTo(sb);
      if (c == 0) c = pa.length.compareTo(pb.length); // "01" after "1"
    } else {
      c = pa.compareTo(pb);
    }
    if (c != 0) return c;
  }
  final c = xa.length.compareTo(xb.length);
  return c != 0 ? c : a.compareTo(b);
}

int _leafCompare(String a, String b) {
  (String, String) split(String n) {
    final i = n.lastIndexOf('.');
    return i <= 0 ? (n, '') : (n.substring(0, i), n.substring(i + 1));
  }

  final (sa, ea) = split(a);
  final (sb, eb) = split(b);
  final c = naturalCompare(sa, sb);
  return c != 0 ? c : naturalCompare(ea, eb);
}

/// Natural order of two paths: folder by folder, then the file name ("a/page2" < "a/page10" < "b/page1").
int naturalPathCompare(String a, String b) {
  final pa = a.split(RegExp(r'[\\/]')), pb = b.split(RegExp(r'[\\/]'));
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    // a file before a sub-folder at the same level (the folder's own pages first)
    final aLeaf = i == pa.length - 1, bLeaf = i == pb.length - 1;
    if (aLeaf != bLeaf) return aLeaf ? -1 : 1;
    // a file: the name before its extension first ("scan.heic" before "scan3.tif"), then the extension
    final c = aLeaf ? _leafCompare(pa[i], pb[i]) : naturalCompare(pa[i], pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

/// One picked file. [read] is called only when its part is sent, so a folder of 300 pages is never all in memory.
class ScanSourceFile {
  const ScanSourceFile({required this.name, this.path = '', this.size, required this.read, this.photo = false});

  /// A file already in memory (a test, the camera's fallback).
  factory ScanSourceFile.bytes(String name, Uint8List bytes, {bool photo = false}) =>
      ScanSourceFile(name: name, size: bytes.length, read: () async => bytes, photo: photo);

  /// The file name.
  final String name;

  /// The path inside the picked folder (`Scans/Class A/page2.pdf`), empty for a plain pick.
  final String path;

  /// Bytes on disk when the source knows it (null: unknown until read).
  final int? size;
  final Future<Uint8List> Function() read;

  /// A photo from the gallery: scaled down to what the reader needs before it is sent (scan_prepare.dart).
  final bool photo;

  /// What the person sees: the path inside the folder, else the name.
  String get label => path.isEmpty ? name : path;
  ScanFileKind get kind => scanKindOf(name);
}

/// Why a file was left out before anything was sent.
enum ScanSkipReason { unsupported, tooLarge, empty }

class ScanSkipped {
  const ScanSkipped(this.label, this.reason);
  final String label;
  final ScanSkipReason reason;
}

/// What a pick holds, in scan order.
class ScanPlan {
  const ScanPlan({required this.files, required this.skipped, this.folder, this.hidden = 0, this.tooMany = false});
  static const empty = ScanPlan(files: [], skipped: []);

  /// The files that will be sent, in scan order.
  final List<ScanSourceFile> files;
  final List<ScanSkipped> skipped;

  /// The folder's name when a folder was picked.
  final String? folder;

  /// Hidden / system files dropped silently.
  final int hidden;

  /// More than [kScanMaxPick] files: nothing is sent (the wrong folder was picked).
  final bool tooMany;

  int get images => files.where((f) => f.kind != ScanFileKind.pdf).length;
  int get pdfs => files.where((f) => f.kind == ScanFileKind.pdf).length;
  bool get isEmpty => files.isEmpty;
  int? get knownBytes {
    var n = 0;
    for (final f in files) {
      if (f.size == null) return null;
      n += f.size!;
    }
    return n;
  }
}

/// Sorts and filters a pick. [folder] keeps the order of the folder's tree; a plain pick (gallery, files) is sorted
/// by name too — a gallery's own order (newest first) is not the scan order.
ScanPlan planScanFiles(List<ScanSourceFile> picked, {String? folder, bool sort = true}) {
  final files = <ScanSourceFile>[];
  final skipped = <ScanSkipped>[];
  var hidden = 0;
  for (final f in picked) {
    if (scanIsHidden(f.label)) {
      hidden++;
      continue;
    }
    if (f.kind == ScanFileKind.unsupported) {
      skipped.add(ScanSkipped(f.label, ScanSkipReason.unsupported));
    } else if (f.size == 0) {
      skipped.add(ScanSkipped(f.label, ScanSkipReason.empty));
    } else if ((f.size ?? 0) > kScanMaxFileBytes && f.kind == ScanFileKind.pdf) {
      // an image over the limit is scaled down on the device; a PDF cannot be
      skipped.add(ScanSkipped(f.label, ScanSkipReason.tooLarge));
    } else {
      files.add(f);
    }
  }
  if (sort) files.sort((a, b) => naturalPathCompare(a.label, b.label));
  skipped.sort((a, b) => naturalPathCompare(a.label, b.label));
  final tooMany = files.length > kScanMaxPick;
  return ScanPlan(files: tooMany ? const [] : files, skipped: skipped, folder: folder, hidden: hidden, tooMany: tooMany);
}

/// Groups prepared files (their sizes) into parts: at most [maxBytes] and [maxFiles] each, in order; a file larger
/// than [maxBytes] goes alone.
List<List<int>> scanParts(List<int> sizes, {int maxBytes = kScanPartBytes, int maxFiles = kScanPartFiles}) {
  final parts = <List<int>>[];
  var cur = <int>[];
  var bytes = 0;
  for (var i = 0; i < sizes.length; i++) {
    if (cur.isNotEmpty && (bytes + sizes[i] > maxBytes || cur.length >= maxFiles)) {
      parts.add(cur);
      cur = [];
      bytes = 0;
    }
    cur.add(i);
    bytes += sizes[i];
  }
  if (cur.isNotEmpty) parts.add(cur);
  return parts;
}

// ── sending ─────────────────────────────────────────────────────────────────────────────────────────────────────

/// A file turned into what is sent (a photo scaled down, an iPhone photo / a TIFF page as JPEG). One source file can
/// give several (a multi-page TIFF).
typedef ScanPrepare = Future<List<(String, Uint8List)>> Function(ScanSourceFile file);

/// Sends one part; [batchId] = the batch the earlier parts opened.
typedef ScanSend = Future<EngineResult> Function(List<(String, Uint8List)> files, int? batchId);

/// Thrown by a [ScanPrepare] for a file that cannot be sent (read failed, a HEIC this device cannot open, …).
class ScanPrepareError implements Exception {
  const ScanPrepareError(this.code);

  /// `read` · `decode` · `heic` · `tiff` · `unsupported` · `too_large`
  final String code;
  @override
  String toString() => 'ScanPrepareError($code)';
}

/// A file that was not taken, with the reason in plain words.
class ScanFailure {
  const ScanFailure(this.file, this.reason, {this.code, this.status = 0});
  final ScanSourceFile file;
  final String reason;
  final String? code;
  final int status;

  /// The photo itself must be taken again (an NB2 page that failed the quality check, D-687).
  bool get retake => kScanRetakeCodes.contains(code);
}

/// An NB2 page the server refused before storing it (contract B3): retake this page.
const kScanRetakeCodes = {'sheet_marks_missing', 'page_blurry', 'not_this_exam'};

/// The server refused ONE file of the part (the part is sent again file by file so the others go through).
bool scanFileLevelFailure(EngineResult r) =>
    r.status == 413 ||
    kScanRetakeCodes.contains(r.code) ||
    const {'unsupported_file', 'bad_pdf', 'bad_image', 'image_too_large', 'too_many_pages', 'page_too_large', 'file_too_large', 'upload_too_large', 'too_many_files'}
        .contains(r.code);

/// Nothing more can go through (the exam cannot take scans, no rights, the batch is gone): the rest is not sent.
bool scanStopFailure(EngineResult r) =>
    r.status == 401 ||
    r.status == 403 ||
    const {
      'forbidden',
      'exam_not_found',
      'batch_not_found',
      'not_a_student',
      'exam_not_bubble',
      'template_not_found',
      'template_too_small',
      'question_options_exceed_sheet',
      'marker_not_on_template',
      'forms_not_on_template',
      'no_bubble_questions',
    }.contains(r.code);

enum ScanUploadPhase { idle, sending, done }

/// Sends a plan's files part by part. Listen to [onChange] for the progress; [run] sends everything not sent yet
/// (the first time: all; after a failure: [retry] sends only what failed).
class ScanUploader {
  ScanUploader({
    required this.files,
    required this.prepare,
    required this.send,
    required this.errorText,
    required this.prepareErrorText,
    this.onChange,
    this.maxBytes = kScanPartBytes,
    this.maxFiles = kScanPartFiles,
    int? batchId,
  }) : _batchId = batchId;

  final List<ScanSourceFile> files;
  final ScanPrepare prepare;
  final ScanSend send;
  final String Function(EngineResult r) errorText;
  final String Function(String code) prepareErrorText;
  void Function()? onChange;
  final int maxBytes, maxFiles;

  int? _batchId;
  int? get batchId => _batchId;

  ScanUploadPhase phase = ScanUploadPhase.idle;

  /// Source files finished (sent, or failed) in this run, of [runTotal].
  int finished = 0;
  int runTotal = 0;

  /// The file being prepared / sent now.
  String? current;

  /// New pages the server stored (all runs), pages it already had.
  int pages = 0, duplicates = 0;

  /// Source files the server took (all runs).
  final Set<ScanSourceFile> sent = {};
  final List<ScanFailure> failures = [];

  /// The run stopped early ([scanStopFailure]): the reason (also on each failure).
  String? stopped;

  bool get anySent => sent.isNotEmpty;

  void _tick() => onChange?.call();

  /// Sends every file not sent yet.
  Future<void> run() => _run([for (final f in files) if (!sent.contains(f)) f]);

  /// Sends the failed files again.
  Future<void> retry() => _run([for (final f in failures) f.file]);

  Future<void> _run(List<ScanSourceFile> todo) async {
    if (phase == ScanUploadPhase.sending) return;
    phase = ScanUploadPhase.sending;
    failures.removeWhere((f) => todo.contains(f.file));
    stopped = null;
    finished = 0;
    runTotal = todo.length;
    _tick();

    // the part being built: prepared files and the source file each came from
    var part = <(String, Uint8List)>[];
    var owners = <ScanSourceFile>[];
    var bytes = 0;

    Future<void> flush() async {
      if (part.isEmpty) return;
      final p = part, o = owners;
      part = [];
      owners = [];
      bytes = 0;
      await _sendPart(p, o);
    }

    for (final f in todo) {
      if (stopped != null) {
        _fail(f, stopped!);
        continue;
      }
      current = f.label;
      _tick();
      List<(String, Uint8List)> ready;
      try {
        ready = await prepare(f);
      } on ScanPrepareError catch (e) {
        _fail(f, prepareErrorText(e.code));
        continue;
      } catch (_) {
        _fail(f, prepareErrorText('read'));
        continue;
      }
      if (ready.isEmpty) {
        _fail(f, prepareErrorText('read'));
        continue;
      }
      if (stopped != null) {
        _fail(f, stopped!);
        continue;
      }
      if (ready.any((x) => x.$2.length > kScanMaxFileBytes)) {
        _fail(f, prepareErrorText('too_large'));
        continue;
      }
      for (final x in ready) {
        if (part.isNotEmpty && (bytes + x.$2.length > maxBytes || part.length >= maxFiles)) await flush();
        if (stopped != null) break; // the part just sent ended the run
        part.add(x);
        owners.add(f);
        bytes += x.$2.length;
      }
      // the run ended while this file waited: it is listed, not sent
      if (stopped != null && !owners.any((o) => identical(o, f))) _fail(f, stopped!);
    }
    await flush();
    current = null;
    phase = ScanUploadPhase.done;
    _tick();
  }

  void _fail(ScanSourceFile f, String reason, {String? code, int status = 0}) {
    if (failures.any((x) => identical(x.file, f))) return;
    failures.add(ScanFailure(f, reason, code: code, status: status));
    if (!sent.remove(f)) finished++; // a file whose first part went is already counted
    _tick();
  }

  /// The source files of a part, once each (a TIFF's pages share one).
  static List<ScanSourceFile> _distinct(List<ScanSourceFile> o) {
    final out = <ScanSourceFile>[];
    for (final f in o) {
      if (!out.any((x) => identical(x, f))) out.add(f);
    }
    return out;
  }

  Future<void> _sendPart(List<(String, Uint8List)> part, List<ScanSourceFile> owners) async {
    final r = await send(part, _batchId);
    if (r.ok) {
      _took(r, owners);
      return;
    }
    final sources = _distinct(owners);
    if (scanStopFailure(r)) {
      stopped = errorText(r);
      for (final f in sources) {
        _fail(f, stopped!, code: r.code, status: r.status);
      }
      return;
    }
    if (scanFileLevelFailure(r) && sources.length > 1) {
      // one file spoiled the part: each source file alone, so only that one fails
      for (final f in sources) {
        if (stopped != null) {
          _fail(f, stopped!);
          continue;
        }
        final mine = [for (var i = 0; i < part.length; i++) if (identical(owners[i], f)) part[i]];
        final one = await send(mine, _batchId);
        if (one.ok) {
          _took(one, [for (final _ in mine) f]);
        } else {
          if (scanStopFailure(one)) stopped = errorText(one);
          _fail(f, errorText(one), code: one.code, status: one.status);
        }
      }
      return;
    }
    // the part as a whole did not go (network, server busy, a file the server refused): every file of it failed
    for (final f in sources) {
      _fail(f, errorText(r), code: r.code, status: r.status);
    }
  }

  void _took(EngineResult r, List<ScanSourceFile> owners) {
    final m = r.map;
    final b = m['batch_id'];
    _batchId ??= b is int ? b : int.tryParse('${b ?? ''}');
    final p = m['pages'];
    pages += p is List ? p.length : (p is num ? p.toInt() : 0);
    final d = m['duplicates'];
    duplicates += d is List ? d.length : (d is num ? d.toInt() : 0);
    for (final f in _distinct(owners)) {
      if (sent.add(f)) finished++;
    }
    _tick();
  }
}
