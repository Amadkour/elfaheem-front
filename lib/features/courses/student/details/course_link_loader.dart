// features/courses/student/details/course_link_loader.dart
//
// Opens a course knowing only its id — used by shared links, notification taps and dialog buttons.
//   1. GET /courses/{id}/access  → private & locked? → code sheet (server-verified)
//   2. record the share click (who shared / who opened)
//   3. GET /courses/{id} → CourseModel → replace this screen with the course profile
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/deep_link_service.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/courses/student/details/course_access_sheet.dart';
import 'package:flutter_education_app/features/courses/student/details/course_detail_screen.dart';
import 'package:flutter_education_app/features/courses/student/details/growth_tr.dart';

class CourseLinkLoader extends StatefulWidget {
  const CourseLinkLoader({super.key, required this.courseId, this.ref});

  final int courseId;
  final int? ref;

  @override
  State<CourseLinkLoader> createState() => _CourseLinkLoaderState();
}

class _CourseLinkLoaderState extends State<CourseLinkLoader> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (mounted) setState(() => _error = null);
    final api = ApiClient();
    try {
      final access = await api.get('/api/v1/courses/${widget.courseId}/access');
      if (access is Map && access['is_private'] == true && access['has_access'] != true) {
        if (!mounted) return;
        final ok = await CourseAccessSheet.show(context,
            courseId: widget.courseId, courseName: (access['name'] ?? '').toString());
        if (!ok) {
          if (mounted) Navigator.of(context).maybePop();
          return;
        }
      }

      // Only links carry a `ref`; opens from notifications aren't "shares".
      if (widget.ref != null) DeepLinkService.instance.recordClick(widget.courseId, widget.ref);

      final json = await api.get('/api/v1/courses/${widget.courseId}');
      if (json is! Map<String, dynamic> || !mounted) return;

      final role = context.read<MyAuthProvider>().currentUser?.role;
      final teacherView = (role == 'teacher' || role == 'admin' || role == 'super-admin') &&
          AppNavigator.teacherCourseBuilder != null;
      final model = CourseModel.fromJson(json);

      // `arguments: model` keeps topRouteObserver.activeCourseId working (live-session refresh).
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        settings: RouteSettings(name: '/course-detail', arguments: teacherView ? null : model),
        builder: (_) => teacherView ? AppNavigator.teacherCourseBuilder!(json) : CourseDetailScreen(course: model),
      ));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.statusCode == 404 ? gt('الدورة غير موجودة', 'Course not found') : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = gt('تعذر فتح الدورة', 'Could not open the course'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppHeader(title: gt('الدورة', 'Course')),
      body: Center(
        child: _error == null
            ? const AppLoadingIndicator(size: 96)
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline_rounded, size: 48, color: c.danger),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: c.body),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _run, child: Text(gt('إعادة المحاولة', 'Retry'))),
                ]),
              ),
      ),
    );
  }
}
