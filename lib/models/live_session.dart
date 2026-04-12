// /// Live session model for live streaming sessions.
// class LiveSession {
//   final int id;
//   final int courseId;
//   final String title;
//   final String? description;
//   final DateTime scheduledAt;
//   final DateTime? startedAt;
//   final DateTime? endedAt;
//   final int duration;
//   final String roomName;
//   final String roomUrl;
//   final String? recordingUrl;
//   final LiveSessionStatus status;
//
//   LiveSession({
//     required this.id,
//     required this.courseId,
//     required this.title,
//     this.description,
//     required this.scheduledAt,
//     this.startedAt,
//     this.endedAt,
//     required this.duration,
//     required this.roomName,
//     required this.roomUrl,
//     this.recordingUrl,
//     required this.status,
//   });
//
//   factory LiveSession.fromJson(Map<String, dynamic> json) {
//     return LiveSession(
//       id: json['id'] as int,
//       courseId: json['course_id'] as int,
//       title: json['title'] as String,
//       description: json['description'] as String?,
//       scheduledAt: DateTime.parse(json['scheduled_at'] as String),
//       startedAt: json['started_at'] != null
//           ? DateTime.parse(json['started_at'] as String)
//           : null,
//       endedAt: json['ended_at'] != null
//           ? DateTime.parse(json['ended_at'] as String)
//           : null,
//       duration: json['duration'] as int,
//       roomName: json['room_name'] as String,
//       roomUrl: json['room_url'] as String,
//       recordingUrl: json['recording_url'] as String?,
//       status: LiveSessionStatus.fromString(json['status'] as String),
//     );
//   }
//
//   bool get isLive => status == LiveSessionStatus.live;
//   bool get isUpcoming => status == LiveSessionStatus.scheduled &&
//       scheduledAt.isAfter(DateTime.now());
//   bool get hasRecording => recordingUrl != null && recordingUrl!.isNotEmpty;
//
//   Duration get timeUntilStart => scheduledAt.difference(DateTime.now());
//
//   String get formattedTimeUntilStart {
//     if (!isUpcoming) return '';
//     final duration = timeUntilStart;
//     if (duration.inDays > 0) {
//       return '${duration.inDays}d ${duration.inHours % 24}h';
//     } else if (duration.inHours > 0) {
//       return '${duration.inHours}h ${duration.inMinutes % 60}m';
//     } else {
//       return '${duration.inMinutes}m';
//     }
//   }
// }
//
// enum LiveSessionStatus {
//   scheduled('scheduled'),
//   live('live'),
//   ended('ended'),
//   recorded('recorded');
//
//   final String value;
//   const LiveSessionStatus(this.value);
//
//   static LiveSessionStatus fromString(String value) {
//     return LiveSessionStatus.values.firstWhere(
//           (status) => status.value == value,
//       orElse: () => LiveSessionStatus.scheduled,
//     );
//   }
// }

/// Updated Live session model for Zoom integration
class LiveSession {
  final int id;
  final int courseId;
  final String title;
  final String? description;
  final DateTime scheduledAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int duration; // minutes
  final String? zoomMeetingId;
  final String? zoomJoinUrl;
  final String? zoomStartUrl;
  final String? zoomPassword;
  final String? recordingUrl;
  final LiveSessionStatus status;
  final String? platform;
  final String? googleMeetUrl;
  final String? googleMeetingCode;

  LiveSession({
    required this.id,
    required this.courseId,
    required this.title,
    this.description,
    required this.scheduledAt,
    this.startedAt,
    this.endedAt,
    required this.duration,
    required this.zoomMeetingId,
    required this.zoomJoinUrl,
    this.zoomStartUrl,
    this.zoomPassword,
    this.recordingUrl,
    required this.status,
    required this.platform,
    required this.googleMeetUrl,
    required this.googleMeetingCode,
  });

  factory LiveSession.fromJson(Map<String, dynamic> json) {
    return LiveSession(
      id: json['id'] as int,
      courseId: json['course_id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      duration: json['duration'] as int,
      zoomMeetingId: json['zoom_meeting_id'] as String?,
      zoomJoinUrl: json['zoom_join_url'] as String?,
      zoomStartUrl: json['zoom_start_url'] as String?,
      zoomPassword: json['zoom_password'] as String?,
      recordingUrl: json['recording_url'] as String?,
      status: LiveSessionStatus.fromString(json['status'] as String),
      platform: json['platform'] as String?,
      googleMeetUrl: json['google_meet_link'] as String?,
      googleMeetingCode:json['google_meeting_code'] as String?,
    );
  }

  // bool get isLive => status == LiveSessionStatus.live;
  bool get isLive => status ==LiveSessionStatus.scheduled &&
      scheduledAt.isBefore(DateTime.now());
  bool get isUpcoming => status == LiveSessionStatus.scheduled &&
      scheduledAt.isAfter(DateTime.now());
  bool get hasRecording => recordingUrl != null && recordingUrl!.isNotEmpty;

  Duration get timeUntilStart => scheduledAt.difference(DateTime.now());

  String get formattedTimeUntilStart {
    if (!isUpcoming) return '';

    final duration = timeUntilStart;
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  /// Get formatted meeting ID for display
  String get formattedMeetingId {
    // Format: 123 456 789
    if (zoomMeetingId!.length == 9) {
      return '${zoomMeetingId!.substring(0, 3)} ${zoomMeetingId!.substring(3, 6)} ${zoomMeetingId!.substring(6)}';
    }
    return zoomMeetingId??'';
  }
}

enum LiveSessionStatus {
  scheduled('scheduled'),
  live('live'),
  ended('ended'),
  recorded('recorded');

  final String value;
  const LiveSessionStatus(this.value);

  static LiveSessionStatus fromString(String value) {
    return LiveSessionStatus.values.firstWhere(
          (status) => status.value == value,
      orElse: () => LiveSessionStatus.scheduled,
    );
  }
}