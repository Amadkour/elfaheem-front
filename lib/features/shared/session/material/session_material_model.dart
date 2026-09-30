// lib/features/sessions/model/session_material_model.dart
// ─────────────────────────────────────────────────────────────────────────────
// Mirrors the Python SessionMaterial ORM / SessionMaterialResponse schema.
// NEW: audioUrl / audioKey / audioSize fields for the paired audio stream
//      stored on the same SessionMaterial row (added by the multi-quality
//      recording migration).
//      `availableQualities` computed getter returns all playable variants.

import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/rating_widget.dart';

// ── Formatting helpers ───────────────────────────────────────────────────────

/// Bytes → "812 KB" (under 1 MB) or "3.4 MB" (1 MB and above).
String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const mb = 1024 * 1024;
  if (bytes < mb) {
    final kb = (bytes / 1024).ceil().clamp(1, 1023);
    return '$kb KB';
  }
  final v = bytes / mb;
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} MB';
}

/// Seconds → "h:mm:ss" (e.g. 0:05:32, 1:02:09).
String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

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

  String get sizeLabel => formatBytes(fileSizeBytes);
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

  /// Video / recording length in seconds (null when unknown or not media).
  final int? durationSeconds;

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

  /// True for videos: the list endpoint sends NO url — the player must call
  /// POST /sessions/{sessionId}/materials/{id}/play first (counts the view).
  final bool requiresPlay;

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
    this.durationSeconds,
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
    this.requiresPlay = false,
  });

  /// Copy of this material with the URLs returned by the /play endpoint.
  SessionMaterialModel withPlayData(Map<String, dynamic> j) {
    String? u(String k) {
      final v = j[k] as String?;
      if (v == null || v.isEmpty) return null;
      // protected videos come back as a relative /api/v1/stream/<token> path
      return v.startsWith('/') ? '${ApiClient().baseUrl}$v' : v;
    }
    final primary = u('url');
    return SessionMaterialModel(
      id: id, sessionId: sessionId, name: name, description: description,
      type: type, fileSize: fileSize, key: key, order: order,
      createdAt: createdAt, completed: completed, rateSummary: rateSummary,
      durationSeconds: (j['duration_seconds'] as num?)?.toInt() ?? durationSeconds,
      urlHigh: u('url_high') ?? primary,
      urlMedium: u('url_medium') ?? primary,
      urlLow: u('url_low') ?? primary,
      fileSizeHigh: fileSizeHigh, fileSizeMedium: fileSizeMedium, fileSizeLow: fileSizeLow,
      audioUrl: u('audio_url'), audioKey: audioKey, audioSize: audioSize,
      audioMediumUrl: u('audio_medium_url'), audioMediumKey: audioMediumKey,
      audioMediumSize: audioMediumSize,
      requiresPlay: false,
    );
  }

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
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      // multi-quality video
      urlHigh:        json['url_high']         as String? ?? (json['url']??''),
      urlMedium:      json['url_medium']        as String? ?? (json['url']??''),
      urlLow:         json['url_low']           as String? ?? (json['url']??''),
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
      requiresPlay:    json['requires_play'] as bool? ?? false,
    );
  }

  /// Local copy with edited fields (used for optimistic edit / reorder).
  SessionMaterialModel copyWith({
    String? name,
    String? description,
    int? order,
    bool? completed,
    String? urlLow,
    String? urlMedium,
    String? urlHigh,
  }) {
    return SessionMaterialModel(
      id: id, sessionId: sessionId,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type, fileSize: fileSize, key: key,
      order: order ?? this.order,
      createdAt: createdAt,
      completed: completed ?? this.completed,
      rateSummary: rateSummary,
      durationSeconds: durationSeconds,
      urlHigh: urlHigh ?? this.urlHigh,
      urlMedium: urlMedium ?? this.urlMedium,
      urlLow: urlLow ?? this.urlLow,
      fileSizeHigh: fileSizeHigh, fileSizeMedium: fileSizeMedium,
      fileSizeLow: fileSizeLow,
      audioUrl: audioUrl, audioKey: audioKey, audioSize: audioSize,
      audioMediumUrl: audioMediumUrl, audioMediumKey: audioMediumKey,
      audioMediumSize: audioMediumSize,
      requiresPlay: requiresPlay,
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

  /// Lower-case file extension without the dot ('xlsx', 'py', ...) or ''.
  /// Read from the storage key, falling back to the URL path (a signed URL
  /// still ends in the file name). Drives the Word/Excel/CSV/PPT/PY icons.
  String get fileExtension {
    String? src = key;
    if (src == null || !src.contains('.')) {
      src = [urlLow, urlMedium, urlHigh]
          .firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);
      if (src != null) src = Uri.tryParse(src)?.path ?? src;
    }
    if (src == null) return '';
    final dot = src.lastIndexOf('.');
    if (dot < 0 || dot < src.lastIndexOf('/')) return '';
    return src.substring(dot + 1).toLowerCase();
  }

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

  /// Human-readable size: KB below 1 MB, MB from 1 MB up.
  /// Falls back to the quality-tier / audio sizes (recordings have no
  /// primary `file_size`).
  String get sizeLabel => formatBytes(
    fileSize ?? fileSizeHigh ?? fileSizeMedium ?? fileSizeLow ??
        audioSize ?? audioMediumSize,
  );

  /// "h:mm:ss" or '' when the length is unknown.
  String get durationLabel => formatDuration(durationSeconds);
}