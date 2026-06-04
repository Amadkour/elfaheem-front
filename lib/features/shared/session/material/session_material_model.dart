// lib/features/sessions/model/session_material_model.dart
// ─────────────────────────────────────────────────────────────────────────────
// Mirrors the Python SessionMaterial ORM / SessionMaterialResponse schema.
// NEW: audioUrl / audioKey / audioSize fields for the paired audio stream
//      stored on the same SessionMaterial row (added by the multi-quality
//      recording migration).
//      `availableQualities` computed getter returns all playable variants.

import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/rating_widget.dart';

enum SessionMaterialType { image, video, pdf, document, link,recorded,recording }

// ── Quality tier ─────────────────────────────────────────────────────────────

enum QualityTier { low, medium, high }

extension QualityTierX on QualityTier {
  String get label {
    switch (this) {
      case QualityTier.low:    return '360p';
      case QualityTier.medium: return '720p';
      case QualityTier.high:   return '1080p';
    }
  }

  String get fullLabel {
    switch (this) {
      case QualityTier.low:    return 'Low (360p)';
      case QualityTier.medium: return 'Medium (720p)';
      case QualityTier.high:   return 'High (1080p)';
    }
  }
}

// ── Playable variant ──────────────────────────────────────────────────────────
// One entry per selectable stream: each has a url, a tier label, and a
// flag that says whether it is an audio-only stream.

class MaterialVariant {
  const MaterialVariant({
    required this.url,
    required this.tier,
    required this.isAudio,
    this.fileSizeBytes,
  });

  final String?     url;
  final QualityTier tier;
  final bool       isAudio;
  final int?       fileSizeBytes;

  /// Human-readable label shown in the picker, e.g. "720p" or "Audio 192k"
  String get label => isAudio ? 'Audio ${_audioBitrateLabel(tier)}' : tier.label;

  String get fullLabel =>
      isAudio ? 'Audio Only — ${_audioBitrateLabel(tier)}' : tier.fullLabel;

  static String _audioBitrateLabel(QualityTier t) {
    switch (t) {
      case QualityTier.high:   return '192 kbps';
      case QualityTier.medium: return '96 kbps';
      case QualityTier.low:    return '64 kbps';
    }
  }

  String get sizeLabel {
    if (fileSizeBytes == null) return '';
    final kb = fileSizeBytes! / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

// ── Main model ────────────────────────────────────────────────────────────────

class SessionMaterialModel {
  final int    id;
  final int    sessionId;
  final String name;
  final String? description;
  final SessionMaterialType type;
  final int?    fileSize;
  final String? key;
  final int     order;
  final DateTime createdAt;
  final bool    completed;
  final RatingSummary? rateSummary;

  // ── Multi-quality video URLs ───────────────────────────────────────────────
  final String? urlHigh;    // 1080p MP4 (same as url for high-quality tier)
  final String? urlMedium;  // 720p  MP4
  final String? urlLow;     // 360p  MP4

  final int? fileSizeHigh;
  final int? fileSizeMedium;
  final int? fileSizeLow;

  // ── Paired audio URLs (stored on the same material row) ───────────────────
  // audio_high  → 192 kbps OGG, paired with the high video tier
  // audio_medium → 96 kbps OGG, paired with the medium/low video tiers
  final String? audioUrl;        // primary audio (audio_high, 192 kbps)
  final String? audioKey;
  final int?    audioSize;

  final String? audioMediumUrl;  // audio_medium, 96 kbps
  final String? audioMediumKey;
  final int?    audioMediumSize;

  const SessionMaterialModel({
    required this.id,
    required this.sessionId,
    required this.name,
    this.description,
    required this.type,
    this.fileSize,
    this.key,
    required this.order,
    required this.createdAt,
    required this.completed,
    this.rateSummary,
    // multi-quality video
    this.urlHigh,
    this.urlMedium,
    this.urlLow,
    this.fileSizeHigh,
    this.fileSizeMedium,
    this.fileSizeLow,
    // audio
    this.audioUrl,
    this.audioKey,
    this.audioSize,
    this.audioMediumUrl,
    this.audioMediumKey,
    this.audioMediumSize,
  });

  // ── JSON deserialisation ──────────────────────────────────────────────────

  factory SessionMaterialModel.fromJson(Map<String, dynamic> json) {
    return SessionMaterialModel(
      id:          json['id']          as int,
      sessionId:   json['session_id']  as int,
      name:        json['name']        as String,
      description: json['description'] as String?,
      type:        _parseType(json['type'] as String),
      fileSize:    json['file_size']   as int?,
      key:         json['key']         as String?,
      order:       json['order']       as int? ?? 0,
      createdAt:   (json['created_at'] as String).toLocalSaTime,
      completed:   json['completed']   as bool? ?? false,
      rateSummary: json.containsKey('rate') && json['rate'] != null
          ? RatingSummary.fromJson(json['rate'] as Map<String, dynamic>)
          : null,
      // multi-quality video
      urlHigh:        json['url_high']         as String?,
      urlMedium:      json['url_medium']        as String?,
      urlLow:         json['url_low']           as String?,
      fileSizeHigh:   json['file_size_high']    as int?,
      fileSizeMedium: json['file_size_medium']  as int?,
      fileSizeLow:    json['file_size_low']     as int?,
      // audio
      audioUrl:        json['audio_url']          as String?,
      audioKey:        json['audio_key']          as String?,
      audioSize:       json['audio_size']         as int?,
      audioMediumUrl:  json['audio_medium_url']   as String?,
      audioMediumKey:  json['audio_medium_key']   as String?,
      audioMediumSize: json['audio_medium_size']  as int?,
    );
  }

  // ── Computed: all playable variants ──────────────────────────────────────
  // Returns a flat list of every stream available for this material.
  // The caller (VideoPlayerScreen / quality picker) uses this to populate
  // the Video and Audio sections of the stream-selection sheet.
  //
  // Order: high → medium → low for each media type, with video listed first.

  List<MaterialVariant> get availableVariants {
    final variants = <MaterialVariant>[];

    // ── Video streams ─────────────────────────────────────────────────────
    final highUrl   = urlHigh;
    final mediumUrl = urlMedium;
    final lowUrl    = urlLow;

    // Always add high (at minimum the primary url is always present)
    variants.add(MaterialVariant(
      url: lowUrl, tier: QualityTier.low,
      isAudio: false, fileSizeBytes: fileSizeLow ?? fileSize,
    ));

    if (mediumUrl != null && mediumUrl.isNotEmpty) {
      variants.add(MaterialVariant(
        url: mediumUrl, tier: QualityTier.medium,
        isAudio: false, fileSizeBytes: fileSizeMedium,
      ));
    }

    if (highUrl != null && highUrl.isNotEmpty) {
      variants.add(MaterialVariant(
        url: highUrl, tier: QualityTier.high,
        isAudio: false, fileSizeBytes: fileSizeHigh,
      ));
    }

    // ── Audio streams ─────────────────────────────────────────────────────
    if (audioUrl != null && audioUrl!.isNotEmpty) {
      variants.add(MaterialVariant(
        url: audioUrl!, tier: QualityTier.high,
        isAudio: true, fileSizeBytes: audioSize,
      ));
    }

    if (audioMediumUrl != null && audioMediumUrl!.isNotEmpty) {
      variants.add(MaterialVariant(
        url: audioMediumUrl!, tier: QualityTier.medium,
        isAudio: true, fileSizeBytes: audioMediumSize,
      ));
    }

    return variants;
  }

  /// Convenience: video-only variants (for the quality chip/sheet).
  List<MaterialVariant> get videoVariants =>
      availableVariants.where((v) => !v.isAudio).toList();

  /// Convenience: audio-only variants.
  List<MaterialVariant> get audioVariants =>
      availableVariants.where((v) => v.isAudio).toList();

  /// True if at least one audio-only stream is available.
  bool get hasAudio => audioVariants.isNotEmpty;

  /// True if more than one video resolution is available.
  bool get hasMultipleVideoQualities => videoVariants.length > 1;

  // ── Type helpers ──────────────────────────────────────────────────────────

  static SessionMaterialType _parseType(String t) {
    switch (t) {
      case 'image':    return SessionMaterialType.image;
      case 'video':    return SessionMaterialType.video;
      case 'pdf':      return SessionMaterialType.pdf;
      case 'document': return SessionMaterialType.document;
      case 'recorded': return SessionMaterialType.recorded;
      case 'recording': return SessionMaterialType.recording;
      default:         return SessionMaterialType.link;
    }
  }

  String get typeLabel {
    switch (type) {
      case SessionMaterialType.image:    return 'صورة';
      case SessionMaterialType.video:    return 'فيديو';
      case SessionMaterialType.pdf:      return 'PDF';
      case SessionMaterialType.document: return 'مستند';
      case SessionMaterialType.link:     return 'رابط';
      case SessionMaterialType.recorded: return 'تسجبل';
      case SessionMaterialType.recording: return 'progress';
    }
  }

  /// Human-readable file size (primary stream)
  String get sizeLabel {
    if (fileSize == null) return '';
    final kb = fileSize! / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}