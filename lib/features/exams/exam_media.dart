// Question images (Exam Studio): the API calls, the pure checks, an in-memory byte cache, `QuestionImage` (viewer) and
// `QuestionImageField` (pick -> crop -> upload -> preview -> remove). Web-safe: bytes only, no dart:io.
//
// Contract: wt-back docs/exam_creation/PLAN.md "Question images". A question body carries
// `"media": [{"id": "<sha256>.<png|jpg>", "alt": "<=200 chars"}]` (at most one item). The bytes are read through
// ApiClient (auth headers) from `GET /questions/{qid}/media/{id}` (bank / editor) or `GET /attempts/{aid}/media/{id}`
// (the student's paper), never from a public URL.
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';

/// Server limits (`services/files.py` rules for question images).
const questionMediaMaxBytes = 5 * 1024 * 1024;
const questionMediaMaxAlt = 200;
const questionMediaExtensions = {'png', 'jpg', 'jpeg'};

/// One image of a question body.
class QuestionMedia {
  const QuestionMedia(this.id, [this.alt = '']);
  final String id;
  final String alt;

  QuestionMedia withAlt(String a) => QuestionMedia(id, a);
  Map<String, dynamic> toJson() => {'id': id, if (alt.trim().isNotEmpty) 'alt': alt.trim()};

  static final _idPattern = RegExp(r'^[0-9a-f]{64}\.(png|jpg)$');
  static bool validId(String id) => _idPattern.hasMatch(id);

  @override
  bool operator ==(Object other) => other is QuestionMedia && other.id == id && other.alt == alt;
  @override
  int get hashCode => Object.hash(id, alt);
}

/// The first image of a body (`media` list), or null. Items without an id are ignored.
QuestionMedia? mediaOfBody(Map<String, dynamic> body) {
  for (final m in asMapList(body['media'])) {
    final id = '${m['id'] ?? ''}';
    if (id.isNotEmpty) return QuestionMedia(id, '${m['alt'] ?? ''}');
  }
  return null;
}

/// Code for [authoringCodeText] (or null when fine) for a picked file: extension and size, checked before the upload.
String? validateMediaFile(String fileName, int size) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  if (!questionMediaExtensions.contains(ext)) return 'question_media_type';
  if (size <= 0) return 'question_media_empty';
  if (size > questionMediaMaxBytes) return 'question_media_too_big';
  return null;
}

/// Validates the body's `media` list the way the server does (client side): at most one item, an id, a short alt.
List<String> validateMediaList(Object? media) {
  if (media == null) return const [];
  if (media is! List) return const ['question_media_invalid'];
  final out = <String>[];
  if (media.length > 1) out.add('question_media_too_many');
  for (final m in media) {
    final map = m is Map ? asMap(m) : const <String, dynamic>{};
    if (!QuestionMedia.validId('${map['id'] ?? ''}')) out.add('question_media_invalid');
    if ('${map['alt'] ?? ''}'.length > questionMediaMaxAlt) out.add('question_media_alt_long');
  }
  return out.toSet().toList();
}

// ── bytes cache ─────────────────────────────────────────────────────────────────────────────────────────────────

/// A small LRU of image bytes by key (a question / attempt scope plus the media id), so a list rebuild or a page flip
/// never downloads the same image twice. In flight loads are shared.
class MediaBytesCache {
  MediaBytesCache({this.maxEntries = 40, this.maxBytes = 32 * 1024 * 1024});
  final int maxEntries;

  /// The total size of the cached bytes; the oldest go first (one image alone may exceed it and is kept alone).
  final int maxBytes;
  int _bytes = 0;
  final LinkedHashMap<String, Uint8List> _done = LinkedHashMap();
  final Map<String, Future<Uint8List>> _pending = {};

  static final MediaBytesCache instance = MediaBytesCache();

  Uint8List? peek(String key) {
    final v = _done.remove(key);
    if (v != null) _done[key] = v;       // most recent last
    return v;
  }

  void put(String key, Uint8List bytes) {
    final old = _done.remove(key);
    if (old != null) _bytes -= old.length;
    _done[key] = bytes;
    _bytes += bytes.length;
    while (_done.length > maxEntries || (_bytes > maxBytes && _done.length > 1)) {
      final oldest = _done.keys.first;
      _bytes -= _done.remove(oldest)!.length;
    }
  }

  void remove(String key) {
    final old = _done.remove(key);
    if (old != null) _bytes -= old.length;
  }

  void clear() {
    _done.clear();
    _pending.clear();
    _bytes = 0;
  }

  int get length => _done.length;
  int get totalBytes => _bytes;

  Future<Uint8List> load(String key, Future<Uint8List> Function() fetch) {
    final hit = peek(key);
    if (hit != null) return Future.value(hit);
    return _pending[key] ??= fetch().then((b) {
      put(key, b);
      return b;
    }).whenComplete(() {
      _pending.remove(key);
    });
  }
}

// ── API ─────────────────────────────────────────────────────────────────────────────────────────────────────────

class QuestionMediaApi {
  QuestionMediaApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = ExamEngineApi.base;

  /// `POST /questions/media` (multipart `file`) in the bank space of [orgId] (null = the personal bank).
  /// On success the result map holds `id`, `name`, `content_type`, `size`, `sha256`.
  Future<EngineResult> upload({required Uint8List bytes, required String fileName, int? orgId, int? courseId}) => engineCall(() => _api.postMultipart(
      '$base/questions/media${mediaScopeQuery(orgId, courseId)}',
      fields: const {}, fileField: 'file', fileName: fileName, fileBytes: bytes));

  Future<Uint8List> questionBytes(int questionId, String mediaId) => _api.getBytes('$base/questions/$questionId/media/$mediaId');
  Future<Uint8List> attemptBytes(int attemptId, String mediaId) => _api.getBytes('$base/attempts/$attemptId/media/$mediaId');
}

/// A bank question's image bytes through the real API and the shared cache (printed papers fetch before laying out).
Future<Uint8List> bankQuestionBytes(int questionId, String mediaId) =>
    MediaBytesCache.instance.load(questionMediaKey(questionId, mediaId), () => QuestionMediaApi().questionBytes(questionId, mediaId));

/// Cache key + loader of a bank question's image.
String questionMediaKey(int questionId, String mediaId) => 'q$questionId/$mediaId';
String attemptMediaKey(int attemptId, String mediaId) => 'a$attemptId/$mediaId';

// ── viewer ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// Shows one question image: loads the bytes through [load] (cached by [cacheKey]), a skeleton while loading, a calm
/// "image unavailable" tile on failure. [maxHeight] bounds it; [compact] draws a small thumbnail for lists.
class QuestionImage extends StatefulWidget {
  const QuestionImage({super.key, required this.cacheKey, required this.load, this.alt = '', this.maxHeight = 220, this.compact = false, this.cache});
  final String cacheKey;
  final Future<Uint8List> Function() load;
  final String alt;
  final double maxHeight;
  final bool compact;
  final MediaBytesCache? cache;

  /// A bank question's image through the real API.
  factory QuestionImage.bank({Key? key, required int questionId, required QuestionMedia media, double maxHeight = 220, bool compact = false, QuestionMediaApi? api}) {
    final a = api ?? QuestionMediaApi();
    return QuestionImage(key: key, cacheKey: questionMediaKey(questionId, media.id), load: () => a.questionBytes(questionId, media.id), alt: media.alt, maxHeight: maxHeight, compact: compact);
  }

  /// An image of the student's paper (attempt route).
  factory QuestionImage.attempt({Key? key, required int attemptId, required QuestionMedia media, double maxHeight = 260, QuestionMediaApi? api}) {
    final a = api ?? QuestionMediaApi();
    return QuestionImage(key: key, cacheKey: attemptMediaKey(attemptId, media.id), load: () => a.attemptBytes(attemptId, media.id), alt: media.alt, maxHeight: maxHeight);
  }

  @override
  State<QuestionImage> createState() => _QuestionImageState();
}

class _QuestionImageState extends State<QuestionImage> {
  late Future<Uint8List> _future = _start();
  MediaBytesCache get _cache => widget.cache ?? MediaBytesCache.instance;

  Future<Uint8List> _start() => _cache.load(widget.cacheKey, widget.load);

  @override
  void didUpdateWidget(QuestionImage old) {
    super.didUpdateWidget(old);
    if (old.cacheKey != widget.cacheKey) _future = _start();
  }

  void _retry() => setState(() {
        _cache.remove(widget.cacheKey);
        _future = _start();
      });

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 56.0 : null;
    Widget frame(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(widget.compact ? 8 : 12),
          child: child,
        );
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) {
          final img = Image.memory(snap.data!, fit: widget.compact ? BoxFit.cover : BoxFit.contain, gaplessPlayback: true,
              width: size, height: size ?? widget.maxHeight, semanticLabel: widget.alt.isEmpty ? t('صورة السؤال', 'Question image') : widget.alt,
              errorBuilder: (_, _, _) => _tile(context, Icons.broken_image_outlined, size));
          return widget.compact ? frame(img) : frame(ConstrainedBox(constraints: BoxConstraints(maxHeight: widget.maxHeight), child: img));
        }
        if (snap.hasError) {
          return InkWell(
            onTap: _retry,
            borderRadius: BorderRadius.circular(12),
            child: _tile(context, Icons.image_not_supported_outlined, size, label: widget.compact ? null : t('تعذّر تحميل الصورة — اضغط للمحاولة', 'Image unavailable — tap to retry')),
          );
        }
        return _tile(context, Icons.image_outlined, size, loading: true);
      },
    );
  }

  Widget _tile(BuildContext context, IconData icon, double? size, {String? label, bool loading = false}) {
    final c = context.colors;
    return Container(
        width: size,
        height: size ?? 96,
        constraints: size == null ? const BoxConstraints(minWidth: 96) : null,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(widget.compact ? 8 : 12), border: Border.all(color: c.divider)),
        child: loading
            ? Icon(icon, color: c.textLight)
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: c.textLight),
                if (label != null) ...[const SizedBox(width: 8), Flexible(child: Text(label, style: appText(12, c: c.textMedium), maxLines: 2, overflow: TextOverflow.ellipsis))],
              ]),
    );
  }
}

// ── editor field ────────────────────────────────────────────────────────────────────────────────────────────────

/// What the editor field reports back: the new media (null = removed). The id was uploaded already.
typedef MediaChanged = void Function(QuestionMedia? media);

/// Pick -> crop -> upload -> preview -> remove, one image. Plain callbacks, so it is layout-testable:
/// [pick] returns the file the person chose (null = cancelled), [upload] returns the new media or an error text.
class QuestionImageField extends StatefulWidget {
  const QuestionImageField({super.key, required this.media, required this.onChanged, required this.preview, required this.upload, this.pick, this.enabled = true});
  final QuestionMedia? media;
  final MediaChanged onChanged;

  /// Builds the preview of the current image (a `QuestionImage` or a memory image of the just uploaded bytes).
  final Widget Function(QuestionMedia media) preview;

  /// Uploads the bytes; returns (media, null) or (null, error text).
  final Future<(QuestionMedia?, String?)> Function(Uint8List bytes, String fileName) upload;

  /// Test hook / custom picker. Default: the gallery via image_picker, then the app cropper.
  final Future<({Uint8List bytes, String name})?> Function(BuildContext context)? pick;
  final bool enabled;

  @override
  State<QuestionImageField> createState() => _QuestionImageFieldState();
}

Future<({Uint8List bytes, String name})?> pickQuestionImage(BuildContext context) async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1800, imageQuality: 90);
  if (x == null || !context.mounted) return null;
  final bytes = await x.readAsBytes();
  if (!context.mounted) return null;
  // a question's figure is content: its lines and labels must stay exactly as they are
  final out = await showAppImageCropper(context, bytes, shape: CropShape.wide, allowBackground: false);
  if (out == null) return null;
  if (identical(out, bytes)) return (bytes: bytes, name: x.name);
  final base = x.name.contains('.') ? x.name.substring(0, x.name.lastIndexOf('.')) : x.name;
  return (bytes: out, name: '$base.png');
}

class _QuestionImageFieldState extends State<QuestionImageField> {
  bool _busy = false;
  String? _error;
  late final TextEditingController _alt = TextEditingController(text: widget.media?.alt ?? '');

  @override
  void didUpdateWidget(QuestionImageField old) {
    super.didUpdateWidget(old);
    if (old.media?.id != widget.media?.id) _alt.text = widget.media?.alt ?? '';
  }

  @override
  void dispose() {
    _alt.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final picked = await (widget.pick ?? pickQuestionImage)(context);
    if (picked == null || !mounted) return;
    final bad = validateMediaFile(picked.name, picked.bytes.length);
    if (bad != null) {
      setState(() => _error = _mediaCodeText(bad));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final (m, err) = await widget.upload(picked.bytes, picked.name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    // a replaced image starts with an empty description (the old one described the old picture)
    if (m != null) widget.onChanged(m);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = widget.media;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('صورة السؤال (اختيارية)', 'Question image (optional)'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
      const SizedBox(height: 8),
      if (m != null) ...[
        Align(alignment: AlignmentDirectional.centerStart, child: widget.preview(m)),
        const SizedBox(height: 8),
        AppField(
            key: const ValueKey('media.alt'), controller: _alt, label: t('وصف الصورة (لقارئ الشاشة)', 'Image description (for screen readers)'),
            onChanged: (v) => widget.onChanged(m.withAlt(v.length > questionMediaMaxAlt ? v.substring(0, questionMediaMaxAlt) : v))),
      ],
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: widget.enabled && !_busy ? _choose : null,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_photo_alternate_outlined),
          label: Text(m == null ? t('إضافة صورة', 'Add an image') : t('استبدال الصورة', 'Replace the image')),
        ),
        if (m != null)
          TextButton.icon(
            onPressed: widget.enabled && !_busy ? () => widget.onChanged(null) : null,
            icon: Icon(Icons.delete_outline_rounded, color: c.danger),
            label: Text(t('إزالة الصورة', 'Remove the image'), style: TextStyle(color: c.danger)),
          ),
      ]),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: appText(12.5, c: c.danger))),
      const SizedBox(height: 12),
    ]);
  }
}

String _mediaCodeText(String code) => switch (code) {
      'question_media_type' => t('الصورة يجب أن تكون PNG أو JPG', 'The image must be PNG or JPG'),
      'question_media_empty' => t('الملف فارغ', 'The file is empty'),
      'question_media_too_big' => t('حجم الصورة أكبر من 5 ميغابايت', 'The image is larger than 5 MB'),
      _ => t('تعذّر رفع الصورة', 'The image could not be uploaded'),
    };

/// Texts for the media codes (merged into `authoringCodeText`'s fallback).
String? mediaCodeText(String code) => switch (code) {
      'question_media_type' || 'question_media_empty' || 'question_media_too_big' => _mediaCodeText(code),
      'question_media_invalid' => t('الصورة غير صالحة أو لا تتبع هذا البنك', 'The image is invalid or belongs to another bank'),
      'question_media_too_many' => t('صورة واحدة فقط لكل سؤال', 'One image per question'),
      'question_media_alt_long' => t('وصف الصورة أطول من 200 حرف', 'The image description is over 200 characters'),
      'media_missing' => t('الصورة غير موجودة', 'The image is missing'),
      _ => null,
    };


/// The scope query of the upload: the same `org_id` / `course_id` the question is created with.
String mediaScopeQuery(int? orgId, int? courseId) {
  final parts = [if (orgId != null) 'org_id=$orgId', if (courseId != null) 'course_id=$courseId'];
  return parts.isEmpty ? '' : '?${parts.join('&')}';
}
