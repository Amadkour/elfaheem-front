// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../../services/api_service.dart';
// import '../../utils/validators.dart';
// import '../../utils/helpers.dart';
//
// class CreateLiveSessionScreen extends StatefulWidget {
//   final int courseId;
//
//   const CreateLiveSessionScreen({Key? key, required this.courseId}) : super(key: key);
//
//   @override
//   State<CreateLiveSessionScreen> createState() => _CreateLiveSessionScreenState();
// }
//
// class _CreateLiveSessionScreenState extends State<CreateLiveSessionScreen> {
//   final _formKey = GlobalKey<FormState>();
//   final _titleController = TextEditingController();
//   final _descriptionController = TextEditingController();
//   DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 1));
//   bool _isSubmitting = false;
//
//   @override
//   void dispose() {
//     _titleController.dispose();
//     _descriptionController.dispose();
//     super.dispose();
//   }
//
//   Future<void> _selectDateTime() async {
//     final date = await showDatePicker(
//       context: context,
//       initialDate: _scheduledAt,
//       firstDate: DateTime.now(),
//       lastDate: DateTime.now().add(const Duration(days: 365)),
//     );
//
//     if (date != null && mounted) {
//       final time = await showTimePicker(
//         context: context,
//         initialTime: TimeOfDay.fromDateTime(_scheduledAt),
//       );
//
//       if (time != null) {
//         setState(() {
//           _scheduledAt = DateTime(
//             date.year,
//             date.month,
//             date.day,
//             time.hour,
//             time.minute,
//           );
//         });
//       }
//     }
//   }
//
//   Future<void> _createSession() async {
//     if (!_formKey.currentState!.validate()) return;
//
//     setState(() => _isSubmitting = true);
//
//     try {
//       final apiService = context.read<ApiService>();
//       await apiService.createLiveSession(
//         courseId: widget.courseId,
//         title: _titleController.text.trim(),
//         description: _descriptionController.text.trim(),
//         scheduledAt: _scheduledAt,
//       );
//
//       if (mounted) {
//         Helpers.showMessage(context, 'Live session scheduled successfully!');
//         Navigator.pop(context);
//       }
//     } catch (e) {
//       if (mounted) {
//         Helpers.showMessage(context, 'Failed to create session: $e', isError: true);
//       }
//     } finally {
//       if (mounted) {
//         setState(() => _isSubmitting = false);
//       }
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Schedule Live Session'),
//       ),
//       body: Form(
//         key: _formKey,
//         child: ListView(
//           padding: const EdgeInsets.all(16),
//           children: [
//             TextFormField(
//               controller: _titleController,
//               decoration: InputDecoration(
//                 labelText: 'Session Title *',
//                 hintText: 'e.g., Q&A Session - Week 1',
//                 border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
//                 prefixIcon: const Icon(Icons.title),
//               ),
//               validator: (v) => Validators.validateRequired(v, 'Title'),
//             ),
//             const SizedBox(height: 16),
//
//             TextFormField(
//               controller: _descriptionController,
//               decoration: InputDecoration(
//                 labelText: 'Description',
//                 hintText: 'What will you discuss?',
//                 border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
//                 prefixIcon: const Icon(Icons.description),
//               ),
//               maxLines: 3,
//             ),
//             const SizedBox(height: 16),
//
//             // Date/Time picker
//             InkWell(
//               onTap: _selectDateTime,
//               child: InputDecorator(
//                 decoration: InputDecoration(
//                   labelText: 'Scheduled Date & Time *',
//                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
//                   prefixIcon: const Icon(Icons.calendar_today),
//                 ),
//                 child: Text(
//                   Helpers.formatDateTime(_scheduledAt),
//                   style: const TextStyle(fontSize: 16),
//                 ),
//               ),
//             ),
//             const SizedBox(height: 24),
//
//             // Info card
//             Card(
//               color: Colors.blue.shade50,
//               child: Padding(
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: const [
//                     Text(
//                       'Live Session Features:',
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     SizedBox(height: 8),
//                     Text('• Real-time video streaming'),
//                     Text('• Interactive chat'),
//                     Text('• Screen sharing'),
//                     Text('• Automatic recording'),
//                     Text('• Up to 100 participants'),
//                   ],
//                 ),
//               ),
//             ),
//             const SizedBox(height: 24),
//
//             ElevatedButton(
//               onPressed: _isSubmitting ? null : _createSession,
//               style: ElevatedButton.styleFrom(
//                 padding: const EdgeInsets.all(16),
//                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//               ),
//               child: _isSubmitting
//                   ? const SizedBox(
//                 height: 20,
//                 width: 20,
//                 child: CircularProgressIndicator(
//                   strokeWidth: 2,
//                   valueColor: AlwaysStoppedAnimation(Colors.white),
//                 ),
//               )
//                   : const Text(
//                 'Schedule Session',
//                 style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../utils/validators.dart';
import '../../utils/helpers.dart';

/// ---------- Meeting Platform Enum ----------
enum MeetingPlatform {
  googleMeet,
  zoom,
}

class CreateLiveSessionScreen extends StatefulWidget {
  final int courseId;

  const CreateLiveSessionScreen({Key? key, required this.courseId})
      : super(key: key);

  @override
  State<CreateLiveSessionScreen> createState() =>
      _CreateLiveSessionScreenState();
}

class _CreateLiveSessionScreenState extends State<CreateLiveSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime _scheduledAt = DateTime.now().add(const Duration(hours: 1));
  bool _isSubmitting = false;

  /// Default platform
  MeetingPlatform _platform = MeetingPlatform.googleMeet;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// ---------- Date & Time Picker ----------
  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_scheduledAt),
      );

      if (time != null) {
        setState(() {
          _scheduledAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  /// ---------- Create Session ----------
  Future<void> _createSession() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final apiService = context.read<ApiService>();

      await apiService.createLiveSession(
        courseId: widget.courseId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        scheduledAt: _scheduledAt,
        platform: _platform.name, // googleMeet | zoom
      );

      if (mounted) {
        Helpers.showMessage(
            context, 'Live session scheduled successfully!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Helpers.showMessage(
          context,
          'Failed to create session: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Live Session'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            /// ---------- Title ----------
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Session Title *',
                hintText: 'e.g., Q&A Session - Week 1',
                prefixIcon: const Icon(Icons.title),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) => Validators.validateRequired(v, 'Title'),
            ),
            const SizedBox(height: 16),

            /// ---------- Description ----------
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'What will you discuss?',
                prefixIcon: const Icon(Icons.description),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            /// ---------- Date & Time ----------
            InkWell(
              onTap: _selectDateTime,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Scheduled Date & Time *',
                  prefixIcon: const Icon(Icons.calendar_today),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  Helpers.formatDateTime(_scheduledAt),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),

            /// ---------- Platform Selector ----------
            const Text(
              'Meeting Platform *',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            SegmentedButton<MeetingPlatform>(
              segments: const [
                ButtonSegment(
                  value: MeetingPlatform.googleMeet,
                  label: Row(
                    children: [
                      Icon(Icons.video_call),
                      SizedBox(width: 8),
                      Text('Google Meet'),
                    ],
                  ),
                ),
                ButtonSegment(
                  value: MeetingPlatform.zoom,
                  label: Row(
                    children: [
                      Icon(Icons.videocam),
                      SizedBox(width: 8),
                      Text('Zoom'),
                    ],
                  ),
                ),
              ],
              selected: {_platform},
              onSelectionChanged: (value) {
                setState(() => _platform = value.first);
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor:
                Theme.of(context).primaryColor,
                selectedForegroundColor: Colors.white,
                foregroundColor: Colors.black87,
                padding:
                const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            /// ---------- Platform Info ----------
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Card(
                key: ValueKey(_platform),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: Colors.grey.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _platform ==
                            MeetingPlatform.googleMeet
                            ? Icons.video_call
                            : Icons.videocam,
                        color:
                        Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _platform ==
                              MeetingPlatform.googleMeet
                              ? 'Google Meet link will be generated automatically.'
                              : 'Zoom meeting details will be created for this session.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            /// ---------- Info Card ----------
            Card(
              color: Colors.blue.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Session Features:',
                      style: TextStyle(
                          fontWeight:
                          FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('• Real-time video streaming'),
                    Text('• Interactive chat'),
                    Text('• Screen sharing'),
                    Text('• Automatic recording'),
                    Text('• Up to 100 participants'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            /// ---------- Submit ----------
            ElevatedButton(
              onPressed:
              _isSubmitting ? null : _createSession,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                  AlwaysStoppedAnimation(
                      Colors.white),
                ),
              )
                  : const Text(
                'Schedule Session',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
