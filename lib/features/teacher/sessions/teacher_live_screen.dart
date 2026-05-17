// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_education_app/features/auth/auth_provider.dart';
// import 'package:flutter_education_app/features/student/sessions/sessions_provider.dart';
// import 'package:flutter_education_app/features/teacher/home/teacher_provider.dart';
// import 'package:flutter_education_app/features/teacher/sessions/live/prejoin.dart';
// import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';
// import 'package:provider/provider.dart';
//
// class TeacherLiveSessionScreen extends StatefulWidget {
//   final int sessionId;
//   final int courseId;
//   final String sessionName;
//   final String authToken;
//   final bool enableRecording;
//   final int? maxParticipants;
//
//   const TeacherLiveSessionScreen({
//     super.key,
//     required this.sessionId,
//     required this.courseId,
//     required this.sessionName,
//     required this.authToken,
//     this.enableRecording = true,
//     this.maxParticipants,
//   });
//
//   @override
//   State<TeacherLiveSessionScreen> createState() =>
//       _TeacherLiveSessionScreenState();
// }
// class _TeacherLiveSessionScreenState extends State<TeacherLiveSessionScreen> {
//
//
//   @override
//   Widget build(BuildContext context) {
//     UserModel? user = context.read<AuthProvider>().currentUser;
//     return PreJoinPage(
//       args: JoinArgs(
//         isTeacher: user!.isTeacher,
//         userId: user.id,
//         userName: user.name,
//         sessionId: widget.sessionId,
//         courseId: widget.courseId,
//         maxStudents: widget.maxParticipants ?? 5,
//         onEnd: () => _confirmEndSession(user),
//         onStart: () => _onStartLive(user),
//       ),
//     );
//   }
//
//   // Widget _buildAttendancePanel() {
//   //   return Container(
//   //     width: 260,
//   //     constraints: const BoxConstraints(maxHeight: 460),
//   //     decoration: BoxDecoration(
//   //       color: const Color(0xEE1A1D2E),
//   //       borderRadius: BorderRadius.circular(14),
//   //       border: Border.all(color: Colors.white12),
//   //     ),
//   //     child: Column(mainAxisSize: MainAxisSize.min, children: [
//   //       // Header
//   //       Padding(
//   //         padding: const EdgeInsets.all(12),
//   //         child: Row(children: [
//   //           const Icon(Icons.checklist, color: Colors.greenAccent, size: 18),
//   //           const SizedBox(width: 6),
//   //           Text(
//   //             'Attendance  ($_presentCount / ${_enrolledStudents.length})',
//   //             style: const TextStyle(
//   //                 color: Colors.white,
//   //                 fontSize: 13,
//   //                 fontWeight: FontWeight.w600),
//   //           ),
//   //           const Spacer(),
//   //           GestureDetector(
//   //             onTap: () => if(mounted) setState(() => _showAttendancePanel = false),
//   //             child: const Icon(Icons.close, color: Colors.white54, size: 18),
//   //           ),
//   //         ]),
//   //       ),
//   //       const Divider(color: Colors.white12, height: 1),
//   //
//   //       // Student list — ALL enrolled students of this course
//   //       Flexible(
//   //         child: _enrolledStudents.isEmpty
//   //             ? const Padding(
//   //                 padding: EdgeInsets.all(16),
//   //                 child: Text('No enrolled students found.',
//   //                     style: TextStyle(color: Colors.white54, fontSize: 13)),
//   //               )
//   //             : ListView.builder(
//   //                 shrinkWrap: true,
//   //                 itemCount: _enrolledStudents.length,
//   //                 itemBuilder: (_, i) {
//   //                   final s = _enrolledStudents[i];
//   //                   final inRoom = _isInRoom(s);
//   //                   final isPresent = _attendanceMap[s.id] ?? false;
//   //                   return _AttendanceTile(
//   //                     student: s,
//   //                     isPresent: isPresent,
//   //                     isInRoom: inRoom,
//   //                     onToggle: () => _toggleAttendance(s.id),
//   //                   );
//   //                 },
//   //               ),
//   //       ),
//   //
//   //       // Bulk actions
//   //       if (_enrolledStudents.isNotEmpty)
//   //         Padding(
//   //           padding: const EdgeInsets.all(10),
//   //           child: Row(children: [
//   //             Expanded(
//   //               child: OutlinedButton(
//   //                 style: OutlinedButton.styleFrom(
//   //                   foregroundColor: Colors.greenAccent,
//   //                   side: const BorderSide(color: Colors.greenAccent),
//   //                   padding: const EdgeInsets.symmetric(vertical: 6),
//   //                   shape: RoundedRectangleBorder(
//   //                       borderRadius: BorderRadius.circular(8)),
//   //                 ),
//   //                 onPressed: () => setState(() {
//   //                   for (final s in _enrolledStudents) {
//   //                     _attendanceMap[s.id] = true;
//   //                   }
//   //                 }),
//   //                 child:
//   //                     const Text('All Present', style: TextStyle(fontSize: 12)),
//   //               ),
//   //             ),
//   //             const SizedBox(width: 8),
//   //             Expanded(
//   //               child: OutlinedButton(
//   //                 style: OutlinedButton.styleFrom(
//   //                   foregroundColor: Colors.redAccent,
//   //                   side: const BorderSide(color: Colors.redAccent),
//   //                   padding: const EdgeInsets.symmetric(vertical: 6),
//   //                   shape: RoundedRectangleBorder(
//   //                       borderRadius: BorderRadius.circular(8)),
//   //                 ),
//   //                 onPressed: () => setState(() {
//   //                   for (final s in _enrolledStudents) {
//   //                     _attendanceMap[s.id] = false;
//   //                   }
//   //                 }),
//   //                 child:
//   //                     const Text('All Absent', style: TextStyle(fontSize: 12)),
//   //               ),
//   //             ),
//   //           ]),
//   //         ),
//   //     ]),
//   //   );
//   // }
// // ── API ───────────────────────────────────────────────────────────────────
//
// // Future<void> _fetchEnrolledStudents() async {
// //   try {
// //     // GET /api/v1/courses/{course_id}/students
// //     // → List<{ id, name, image_url, enrolled_at, status, ... }>
// //     final res = await http.get(
// //       Uri.parse(
// //           '${AppConfig.baseUrl}/api/v1/courses/${widget.courseId}/students'),
// //       headers: {'Authorization': 'Bearer ${widget.authToken}'},
// //     );
// //     if (res.statusCode == 200) {
// //       final list = json.decode(res.body) as List<dynamic>;
// //       setState(() {
// //         _enrolledStudents =
// //             list.map((j) => EnrolledStudent.fromJson(j)).toList();
// //         for (final s in _enrolledStudents) {
// //           _attendanceMap[s.id] = false; // default absent
// //         }
// //       });
// //     }
// //   } catch (_) {
// //     // non-fatal
// //   }
// // }
// }
//
// class _AttendanceTile extends StatelessWidget {
//   final EnrolledStudent student;
//   final bool isPresent;
//   final bool isInRoom;
//   final VoidCallback onToggle;
//
//   const _AttendanceTile({
//     required this.student,
//     required this.isPresent,
//     required this.isInRoom,
//     required this.onToggle,
//   });
//
//   @override
//   Widget build(BuildContext context) => Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
//         child: Row(children: [
//           CircleAvatar(
//             radius: 18,
//             backgroundColor: const Color(0xFF2C3154),
//             backgroundImage: student.imageUrl != null
//                 ? NetworkImage(student.imageUrl!)
//                 : null,
//             child: student.imageUrl == null
//                 ? Text(
//                     student.name.isNotEmpty
//                         ? student.name[0].toUpperCase()
//                         : '?',
//                     style: const TextStyle(
//                         color: Colors.white,
//                         fontSize: 13,
//                         fontWeight: FontWeight.bold),
//                   )
//                 : null,
//           ),
//           const SizedBox(width: 8),
//           Expanded(
//             child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Text(student.name,
//                       style: const TextStyle(color: Colors.white, fontSize: 13),
//                       overflow: TextOverflow.ellipsis),
//                   Text(
//                     isInRoom ? '● In room' : '○ Not joined',
//                     style: TextStyle(
//                         color: isInRoom ? Colors.greenAccent : Colors.white38,
//                         fontSize: 10),
//                   ),
//                 ]),
//           ),
//           // Present / Absent toggle
//           GestureDetector(
//             onTap: onToggle,
//             child: AnimatedContainer(
//               duration: const Duration(milliseconds: 200),
//               width: 76,
//               height: 28,
//               decoration: BoxDecoration(
//                 color: isPresent
//                     ? Colors.green.withValues(alpha:0.25)
//                     : Colors.red.withValues(alpha:0.20),
//                 borderRadius: BorderRadius.circular(8),
//                 border: Border.all(
//                   color: isPresent ? Colors.greenAccent : Colors.redAccent,
//                 ),
//               ),
//               child: Center(
//                 child: Row(mainAxisSize: MainAxisSize.min, children: [
//                   Icon(isPresent ? Icons.check : Icons.close,
//                       size: 12,
//                       color: isPresent ? Colors.greenAccent : Colors.redAccent),
//                   const SizedBox(width: 3),
//                   Text(
//                     isPresent ? 'Present' : 'Absent',
//                     style: TextStyle(
//                       color: isPresent ? Colors.greenAccent : Colors.redAccent,
//                       fontSize: 10,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                 ]),
//               ),
//             ),
//           ),
//         ]),
//       );
// }
// class EnrolledStudent {
//   final int id;
//   final String name;
//   final String? imageUrl;
//
//   EnrolledStudent({required this.id, required this.name, this.imageUrl});
//
//   factory EnrolledStudent.fromJson(Map<String, dynamic> j) => EnrolledStudent(
//     id: j['id'] as int,
//     name: j['name'] as String? ?? '',
//     imageUrl: j['image_url'] as String?,
//   );
// }