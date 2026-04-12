import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:daily_flutter/daily_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class TeacherCreateLiveScreen extends StatefulWidget {
  const TeacherCreateLiveScreen({Key? key}) : super(key: key);

  @override
  State<TeacherCreateLiveScreen> createState() => _TeacherCreateLiveScreenState();
}

class _TeacherCreateLiveScreenState extends State<TeacherCreateLiveScreen> {
  final _formKey = GlobalKey<FormState>();
  final _courseTitleController = TextEditingController();
  final _courseDescriptionController = TextEditingController();
  final _teacherNameController = TextEditingController();

  bool _isLoading = false;
  String? _roomUrl;
  String? _roomName;
  int _maxParticipants = 50;
  bool _enableScreenShare = true;
  bool _enableRecording = false;
  bool _enableChat = true;

  // Replace with your Daily API key
  final String _dailyApiKey = 'cdcc6f0c2351aa1ec8f37755e9fa7c9a4f5d5c1a01050490b2e48941d8cccbbf';
  final String _dailyDomain = 'elfaheem.daily.co';

  @override
  void dispose() {
    _courseTitleController.dispose();
    _courseDescriptionController.dispose();
    _teacherNameController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Create room via Daily API
      final response = await http.post(
        Uri.parse('https://api.daily.co/v1/rooms'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_dailyApiKey',
        },
        body: jsonEncode({
          'properties': {
            'max_participants': 2,
            'enable_screenshare': _enableScreenShare,
            'enable_chat': _enableChat,
            // 'enable_recording': _enableRecording,
            'owner_only_broadcast': false,
            'enable_prejoin_ui': false,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _roomUrl = data['url'];
          _roomName = data['name'];
        });
        _showRoomCreatedDialog();
      } else {
        _showError('Failed to create room: ${response.body}');
      }
    } catch (e) {
      _showError('Error creating room: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showRoomCreatedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('Room Created!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your live course room is ready.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            const Text(
              'Room Link:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _roomUrl ?? '',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _roomUrl ?? ''));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied!')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _shareRoomLink();
            },
            child: const Text('Share Link'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startLiveSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Start Live Session'),
          ),
        ],
      ),
    );
  }

  void _shareRoomLink() {
    // Implement sharing functionality
    // You can use share_plus package
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Room Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.email),
              title: const Text('Email'),
              onTap: () {
                // Implement email sharing
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.message),
              title: const Text('SMS'),
              onTap: () {
                // Implement SMS sharing
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Other'),
              onTap: () {
                // Implement generic sharing
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startLiveSession() {
    if (_roomUrl == null) return;

    // Navigate to teacher live session screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeacherLiveSessionScreen(
          roomUrl: _roomUrl!,
          teacherName: _teacherNameController.text,
          courseTitle: _courseTitleController.text,
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Live Course'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.deepPurple, Colors.deepPurple[300]!],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.video_call,
                      size: 48,
                      color: Colors.white,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Start Your Live Course',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Set up your virtual classroom',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Course Information
              _buildSectionTitle('Course Information'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _courseTitleController,
                label: 'Course Title',
                hint: 'e.g., Introduction to Flutter',
                icon: Icons.book,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a course title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _courseDescriptionController,
                label: 'Description (Optional)',
                hint: 'Brief description of what you\'ll cover',
                icon: Icons.description,
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _teacherNameController,
                label: 'Your Name',
                hint: 'How students will see you',
                icon: Icons.person,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Session Settings
              _buildSectionTitle('Session Settings'),
              const SizedBox(height: 12),
              _buildParticipantsSlider(),
              const SizedBox(height: 16),
              _buildSwitchTile(
                title: 'Enable Screen Share',
                subtitle: 'Allow participants to share their screen',
                icon: Icons.screen_share,
                value: _enableScreenShare,
                onChanged: (value) {
                  setState(() => _enableScreenShare = value);
                },
              ),
              _buildSwitchTile(
                title: 'Enable Recording',
                subtitle: 'Record the session to cloud',
                icon: Icons.fiber_manual_record,
                value: _enableRecording,
                onChanged: (value) {
                  setState(() => _enableRecording = value);
                },
              ),
              _buildSwitchTile(
                title: 'Enable Chat',
                subtitle: 'Allow text chat during session',
                icon: Icons.chat,
                value: _enableChat,
                onChanged: (value) {
                  setState(() => _enableChat = value);
                },
              ),
              const SizedBox(height: 32),

              // Create Button
              ElevatedButton(
                onPressed: _createRoom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline),
                    SizedBox(width: 8),
                    Text(
                      'Create Room',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.deepPurple,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.deepPurple),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
        ),
      ),
      validator: validator,
      maxLines: maxLines,
    );
  }

  Widget _buildParticipantsSlider() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people, color: Colors.deepPurple),
              const SizedBox(width: 8),
              const Text(
                'Max Participants',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_maxParticipants',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _maxParticipants.toDouble(),
            min: 10,
            max: 100,
            divisions: 9,
            activeColor: Colors.deepPurple,
            onChanged: (value) {
              setState(() => _maxParticipants = value.toInt());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        secondary: Icon(icon, color: Colors.deepPurple),
        value: value,
        activeColor: Colors.deepPurple,
        onChanged: onChanged,
      ),
    );
  }
}

// Teacher Live Session Screen (placeholder - similar to student but with teacher controls)
class TeacherLiveSessionScreen extends StatelessWidget {
  final String roomUrl;
  final String teacherName;
  final String courseTitle;

  const TeacherLiveSessionScreen({
    Key? key,
    required this.roomUrl,
    required this.teacherName,
    required this.courseTitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // This would be similar to LiveCourseScreen but with additional teacher controls:
    // - Mute all participants
    // - Spotlight specific students
    // - End session for all
    // - Start/stop recording
    // - Share screen
    // - Participant management (remove, promote to co-host)

    return Scaffold(
      appBar: AppBar(
        title: Text(courseTitle),
        backgroundColor: Colors.deepPurple,
      ),
      body: Center(
        child: Text('Teacher Live Session: $roomUrl'),
      ),
    );
  }
}