// ─────────────────────────────────────────────────────────────────────────────
// features/auth/teacher_documents/teacher_document_model.dart
// ─────────────────────────────────────────────────────────────────────────────

// ── Required Document Type  (admin-defined catalogue) ─────────────────────────

class RequiredDocumentType {
  final int id;
  final String title;
  final String? description;
  final String iconName;
  final bool isRequired;

  const RequiredDocumentType({
    required this.id,
    required this.title,
    this.description,
    required this.iconName,
    required this.isRequired,
  });

  factory RequiredDocumentType.fromJson(Map<String, dynamic> j) =>
      RequiredDocumentType(
        id: j['id'] as int,
        title: j['title'] as String,
        description: j['description'] as String?,
        iconName: j['icon_name'] as String? ?? 'description',
        isRequired: j['is_required'] as bool? ?? true,
      );
}

// ── Uploaded document (one file row) ─────────────────────────────────────────

class TeacherDocumentModel {
  final int id;
  final int? requiredDocumentTypeId;
  final String title;
  final String fileUrl;
  final String? fileName;
  final String fileType; // "image" | "pdf"
  final int? fileSize;
  final String status; // "pending" | "approved" | "rejected"
  final String? rejectionReason;
  final DateTime uploadedAt;

  const TeacherDocumentModel({
    required this.id,
    this.requiredDocumentTypeId,
    required this.title,
    required this.fileUrl,
    this.fileName,
    required this.fileType,
    this.fileSize,
    required this.status,
    this.rejectionReason,
    required this.uploadedAt,
  });

  bool get isImage => fileType == 'image';
  bool get isPdf   => fileType == 'pdf';
  bool get isApproved  => status == 'approved';
  bool get isPending   => status == 'pending';
  bool get isRejected  => status == 'rejected';

  factory TeacherDocumentModel.fromJson(Map<String, dynamic> j) =>
      TeacherDocumentModel(
        id: j['id'] as int,
        requiredDocumentTypeId: j['required_document_type_id'] as int?,
        title: j['title'] as String,
        fileUrl: j['file_url'] as String,
        fileName: j['file_name'] as String?,
        fileType: j['file_type'] as String? ?? 'image',
        fileSize: j['file_size'] as int?,
        status: j['status'] as String? ?? 'pending',
        rejectionReason: j['rejection_reason'] as String?,
        uploadedAt: DateTime.parse(j['uploaded_at'] as String),
      );
}

// ── Requirement-with-status (the merged view returned by /overview) ────────────

class DocumentRequirementStatus {
  final int typeId;
  final String title;
  final String? description;
  final String iconName;
  final bool isRequired;
  final TeacherDocumentModel? document; // null = not uploaded yet

  const DocumentRequirementStatus({
    required this.typeId,
    required this.title,
    this.description,
    required this.iconName,
    required this.isRequired,
    this.document,
  });

  bool get isFulfilled => document != null;

  factory DocumentRequirementStatus.fromJson(Map<String, dynamic> j) =>
      DocumentRequirementStatus(
        typeId: j['type_id'] as int,
        title: j['title'] as String,
        description: j['description'] as String?,
        iconName: j['icon_name'] as String? ?? 'description',
        isRequired: j['is_required'] as bool? ?? true,
        document: j['document'] != null
            ? TeacherDocumentModel.fromJson(j['document'] as Map<String, dynamic>)
            : null,
      );
}

// ── Overview (top-level response from GET /teacher-documents) ─────────────────

class TeacherDocumentsOverview {
  final List<DocumentRequirementStatus> requirements;
  final List<TeacherDocumentModel> customDocuments;
  final bool allRequiredFulfilled;

  const TeacherDocumentsOverview({
    required this.requirements,
    required this.customDocuments,
    required this.allRequiredFulfilled,
  });

  factory TeacherDocumentsOverview.fromJson(Map<String, dynamic> j) =>
      TeacherDocumentsOverview(
        requirements: (j['requirements'] as List? ?? [])
            .map((e) => DocumentRequirementStatus.fromJson(e as Map<String, dynamic>))
            .toList(),
        customDocuments: (j['custom_documents'] as List? ?? [])
            .map((e) => TeacherDocumentModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        allRequiredFulfilled: j['all_required_fulfilled'] as bool? ?? false,
      );

  int get totalUploaded =>
      requirements.where((r) => r.isFulfilled).length + customDocuments.length;

  int get requiredCount => requirements.where((r) => r.isRequired).length;

  int get fulfilledRequiredCount =>
      requirements.where((r) => r.isRequired && r.isFulfilled).length;
}
