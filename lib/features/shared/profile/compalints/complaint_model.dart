// ─────────────────────────────────────────────────────────────────────────────
// features/shared/complaints/complaint_model.dart
// ─────────────────────────────────────────────────────────────────────────────

enum ComplaintStatus {
  open,
  inProgress,
  resolved,
  closed;

  static ComplaintStatus fromString(String v) => switch (v) {
        'in_progress' => inProgress,
        'resolved'    => resolved,
        'closed'      => closed,
        _             => open,
      };

  String toJson() => switch (this) {
        inProgress => 'in_progress',
        resolved   => 'resolved',
        closed     => 'closed',
        open       => 'open',
      };
}

enum ComplaintCategory {
  technical,
  payment,
  courseContent,
  teacher,
  student,
  general;

  static ComplaintCategory fromString(String v) => switch (v) {
        'technical'      => technical,
        'payment'        => payment,
        'course_content' => courseContent,
        'teacher'        => teacher,
        'student'        => student,
        _                => general,
      };

  String toJson() => switch (this) {
        technical    => 'technical',
        payment      => 'payment',
        courseContent => 'course_content',
        teacher      => 'teacher',
        student      => 'student',
        general      => 'general',
      };
}

enum ComplaintPriority {
  low,
  medium,
  high,
  urgent;

  static ComplaintPriority fromString(String v) => switch (v) {
        'high'   => high,
        'urgent' => urgent,
        'low'    => low,
        _        => medium,
      };

  String toJson() => name;
}

// ── Attachment ────────────────────────────────────────────────────────────────

class ComplaintAttachment {
  final int id;
  final String fileUrl;
  final String? fileName;
  final String? fileType;
  final int? fileSize;
  final DateTime uploadedAt;

  const ComplaintAttachment({
    required this.id,
    required this.fileUrl,
    this.fileName,
    this.fileType,
    this.fileSize,
    required this.uploadedAt,
  });

  factory ComplaintAttachment.fromJson(Map<String, dynamic> j) =>
      ComplaintAttachment(
        id: j['id'],
        fileUrl: j['file_url'],
        fileName: j['file_name'],
        fileType: j['file_type'],
        fileSize: j['file_size'],
        uploadedAt: DateTime.parse(j['uploaded_at']),
      );
}

// ── Reply ─────────────────────────────────────────────────────────────────────

class ComplaintReply {
  final int id;
  final int complaintId;
  final int senderId;
  final String senderName;
  final String? senderImage;
  final String message;
  final bool isAdmin;
  final DateTime createdAt;
  final List<ComplaintAttachment> attachments;

  const ComplaintReply({
    required this.id,
    required this.complaintId,
    required this.senderId,
    required this.senderName,
    this.senderImage,
    required this.message,
    required this.isAdmin,
    required this.createdAt,
    this.attachments = const [],
  });

  factory ComplaintReply.fromJson(Map<String, dynamic> j) => ComplaintReply(
        id: j['id'],
        complaintId: j['complaint_id'],
        senderId: j['sender_id'],
        senderName: j['sender_name'] ?? '',
        senderImage: j['sender_image'],
        message: j['message'],
        isAdmin: j['is_admin'] ?? false,
        createdAt: DateTime.parse(j['created_at']),
        attachments: (j['attachments'] as List? ?? [])
            .map((a) => ComplaintAttachment.fromJson(a))
            .toList(),
      );
}

// ── Main Complaint ────────────────────────────────────────────────────────────

class ComplaintModel {
  final int id;
  final int userId;
  final String userName;
  final String? userImage;
  final int? courseId;
  final String? courseTitle;
  final String title;
  final String description;
  final ComplaintCategory category;
  final ComplaintPriority priority;
  final ComplaintStatus status;
  final bool isReadByAdmin;
  final bool isReadByUser;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;
  final int repliesCount;
  final List<ComplaintReply> replies;
  final List<ComplaintAttachment> attachments;

  const ComplaintModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userImage,
    this.courseId,
    this.courseTitle,
    required this.title,
    required this.description,
    required this.category,
    required this.priority,
    required this.status,
    required this.isReadByAdmin,
    required this.isReadByUser,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
    this.repliesCount = 0,
    this.replies = const [],
    this.attachments = const [],
  });

  factory ComplaintModel.fromJson(Map<String, dynamic> j) => ComplaintModel(
        id: j['id'],
        userId: j['user_id'],
        userName: j['user_name'] ?? '',
        userImage: j['user_image'],
        courseId: j['course_id'],
        courseTitle: j['course_title'],
        title: j['title'],
        description: j['description'],
        category: ComplaintCategory.fromString(j['category'] ?? 'general'),
        priority: ComplaintPriority.fromString(j['priority'] ?? 'medium'),
        status: ComplaintStatus.fromString(j['status'] ?? 'open'),
        isReadByAdmin: j['is_read_by_admin'] ?? false,
        isReadByUser: j['is_read_by_user'] ?? true,
        createdAt: DateTime.parse(j['created_at']),
        updatedAt: DateTime.parse(j['updated_at']),
        resolvedAt:
            j['resolved_at'] != null ? DateTime.parse(j['resolved_at']) : null,
        repliesCount: j['replies_count'] ?? 0,
        replies: (j['replies'] as List? ?? [])
            .map((r) => ComplaintReply.fromJson(r))
            .toList(),
        attachments: (j['attachments'] as List? ?? [])
            .map((a) => ComplaintAttachment.fromJson(a))
            .toList(),
      );
}

// ── Stats ─────────────────────────────────────────────────────────────────────

class ComplaintStats {
  final int total;
  final int open;
  final int inProgress;
  final int resolved;
  final int closed;
  final int unreadAdmin;

  const ComplaintStats({
    this.total = 0,
    this.open = 0,
    this.inProgress = 0,
    this.resolved = 0,
    this.closed = 0,
    this.unreadAdmin = 0,
  });

  factory ComplaintStats.fromJson(Map<String, dynamic> j) => ComplaintStats(
        total: j['total'] ?? 0,
        open: j['open'] ?? 0,
        inProgress: j['in_progress'] ?? 0,
        resolved: j['resolved'] ?? 0,
        closed: j['closed'] ?? 0,
        unreadAdmin: j['unread_admin'] ?? 0,
      );
}
