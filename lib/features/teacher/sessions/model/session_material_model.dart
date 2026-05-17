// lib/features/sessions/model/session_material_model.dart
// ─────────────────────────────────────────────────────────
// Mirrors the Python SessionMaterial ORM / SessionMaterialResponse schema.

enum SessionMaterialType { image, video, pdf, document, link }

class SessionMaterialModel {
  final int id;
  final int sessionId;
  final String name;
  final String? description;
  final SessionMaterialType type;
  final String url;
  final int? fileSize;
  final String? key;
  final int order;
  final DateTime createdAt;

  const SessionMaterialModel({
    required this.id,
    required this.sessionId,
    required this.name,
    this.description,
    required this.type,
    required this.url,
    this.fileSize,
    this.key,
    required this.order,
    required this.createdAt,
  });

  factory SessionMaterialModel.fromJson(Map<String, dynamic> json) {
    return SessionMaterialModel(
      id:          json['id'] as int,
      sessionId:   json['session_id'] as int,
      name:        json['name'] as String,
      description: json['description'] as String?,
      type:        _parseType(json['type'] as String),
      url:         json['url'] as String,
      fileSize:    json['file_size'] as int?,
      key:         json['key'] as String?,
      order:       json['order'] as int? ?? 0,
      createdAt:   DateTime.parse(json['created_at'] as String),
    );
  }

  static SessionMaterialType _parseType(String t) {
    switch (t) {
      case 'image':    return SessionMaterialType.image;
      case 'video':    return SessionMaterialType.video;
      case 'pdf':      return SessionMaterialType.pdf;
      case 'document': return SessionMaterialType.document;
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
    }
  }

  /// Human-readable file size
  String get sizeLabel {
    if (fileSize == null) return '';
    final kb = fileSize! / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}
