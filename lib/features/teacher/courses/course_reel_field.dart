// features/teacher/courses/component/course_reel_field.dart
//
// "Course reel" (عرض أولي) picker for the ADD / EDIT course form — optional.
// Self-contained: owns its own ApiClient and uploads/deletes directly, the
// same way every other provider in this app does (`ApiClient? api` param),
// so the form screen only needs to call `commit(courseId)` after the course
// itself has been created/updated.
//
//   final _reelCtrl = CourseReelController(initialUrl: existingReelUrl);
//   ...
//   CourseReelField(controller: _reelCtrl, posterUrl: widget.course?.imageUrl),
//   ...
//   // after the course create/update call succeeds (you now have its id):
//   if (!await _reelCtrl.commit(course.id)) {
//     showSnack(_reelCtrl.error ?? 'course_reel_upload_failed'.tr);
//   }
//
// The video is only uploaded on commit() — picking one never touches the
// server, so cancelling the form costs nothing.
// Needs `file_picker`, `dio` and `http_parser` (all already dependencies).
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:typed_data';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:http_parser/http_parser.dart';

import '../sessions/components/course_reel_player.dart';
const Map<String, String> _kReelMimeByExt = {
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
};

class CourseReelController extends ChangeNotifier {
  CourseReelController({String? initialUrl, ApiClient? api})
      : _existingUrl = (initialUrl == null || initialUrl.isEmpty) ? null : initialUrl,
        _api = api ?? ApiClient();

  /// Keep in sync with the server limit (minio_service.REEL_MAX_BYTES).
  static const maxBytes = 100 * 1024 * 1024;

  final ApiClient _api;

  String? _existingUrl;
  Uint8List? _bytes;
  String? _fileName;
  bool _removeRequested = false;
  bool _busy = false;
  String? error;

  /// The reel currently stored on the server (null once removal is requested).
  String? get existingUrl => _removeRequested ? null : _existingUrl;
  bool get hasPending => _bytes != null;
  String? get pendingName => _fileName;
  int get pendingBytes => _bytes?.length ?? 0;
  bool get removeRequested => _removeRequested;
  bool get busy => _busy;

  /// True when commit() has something to do.
  bool get hasChanges => _bytes != null || _removeRequested;

  String _extOf(String name) {
    final i = name.lastIndexOf('.');
    return i == -1 ? '' : name.substring(i + 1).toLowerCase();
  }

  Future<void> pick() async {
    error = null;
    final res = await FilePicker.pickFiles(
      type: FileType.video,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      error = 'course_reel_upload_failed'.tr;
    } else if (bytes.length > maxBytes) {
      error = 'course_reel_too_large'.tr;
    } else if (!_kReelMimeByExt.containsKey(_extOf(f.name))) {
      error = 'course_reel_unsupported_type'.tr;
    } else {
      _bytes = bytes;
      _fileName = f.name;
      _removeRequested = false;
    }
    notifyListeners();
  }

  void clearPending() {
    _bytes = null;
    _fileName = null;
    notifyListeners();
  }

  /// Marks the stored reel for deletion (applied on commit) — undo-able.
  void requestRemove() {
    _bytes = null;
    _fileName = null;
    _removeRequested = true;
    notifyListeners();
  }

  void undoRemove() {
    _removeRequested = false;
    notifyListeners();
  }

  /// Applies the pending change for [courseId]. Returns true on success (or
  /// when there is nothing to do). On failure [error] holds the reason.
  Future<bool> commit(int courseId) async {
    if (!hasChanges) return true;
    _busy = true;
    error = null;
    notifyListeners();
    try {
      if (_bytes != null) {
        final name = _fileName ?? 'reel.mp4';
        final mime = _kReelMimeByExt[_extOf(name)] ?? 'video/mp4';
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(
            _bytes!,
            filename: name,
            contentType: MediaType.parse(mime),
          ),
        });
        final response = await _api.dio.post(
          '/api/v1/courses/$courseId/reel',
          data: formData,
        );
        if (response.statusCode != 200) {
          error = 'course_reel_upload_failed'.tr;
          return false;
        }
        final data = response.data as Map<String, dynamic>;
        _existingUrl = data['reel_url'] as String?;
        _bytes = null;
        _fileName = null;
      } else if (_removeRequested) {
        await _api.delete('/api/v1/courses/$courseId/reel');
        _existingUrl = null;
        _removeRequested = false;
      }
      return true;
    } on DioException catch (e) {
      error = (e.response?.data is Map && (e.response?.data['detail'] != null))
          ? e.response!.data['detail'].toString()
          : 'course_reel_upload_failed'.tr;
      return false;
    } catch (e) {
      error = 'course_reel_upload_failed'.tr;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

class CourseReelField extends StatelessWidget {
  final CourseReelController controller;

  /// The course image — used as the preview's poster.
  final String? posterUrl;

  const CourseReelField({super.key, required this.controller, this.posterUrl});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_form.reel',
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildCard(context),
    ),
  );

  Widget _buildCard(BuildContext context) {
    final c = context.colors;
    final existing = controller.existingUrl;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.divider, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.smart_display_rounded, size: 19, color: c.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'course_reel_title'.tr,
                      style: c.label.copyWith(
                        color: c.textDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('course_reel_hint'.tr, style: c.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (controller.busy)
            _box(
              context,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text('course_reel_uploading'.tr, style: c.label),
                ],
              ),
            )
          else if (controller.hasPending)
            _pendingTile(context)
          else if (existing != null)
              _existingPreview(context, existing)
            else if (controller.removeRequested)
                _box(
                  context,
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: c.danger, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('course_reel_will_be_removed'.tr,
                            style: c.label.copyWith(color: c.danger)),
                      ),
                      TextButton(
                        onPressed: controller.undoRemove,
                        child: Text('course_reel_undo_remove'.tr),
                      ),
                    ],
                  ),
                )
              else
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: controller.pick,
                  child: _box(
                    context,
                    dashed: true,
                    child: Column(
                      children: [
                        Icon(Icons.video_call_rounded, size: 34, color: c.primary),
                        const SizedBox(height: 6),
                        Text(
                          'course_reel_pick'.tr,
                          style: c.label.copyWith(
                            color: c.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

          if (controller.error != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 16, color: c.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(controller.error!,
                      style: c.caption.copyWith(color: c.danger)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _box(BuildContext context, {required Widget child, bool dashed = false}) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dashed ? c.primary.withValues(alpha: 0.4) : c.divider,
          width: dashed ? 1.4 : 0.8,
        ),
      ),
      child: child,
    );
  }

  /// A video picked but not uploaded yet.
  Widget _pendingTile(BuildContext context) {
    final c = context.colors;
    final mb = (controller.pendingBytes / (1024 * 1024)).toStringAsFixed(1);
    return _box(
      context,
      child: Row(
        children: [
          Icon(Icons.movie_creation_rounded, color: c.primary, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(controller.pendingName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: c.label.copyWith(
                        color: c.textDark, fontWeight: FontWeight.w700)),
                Text('$mb MB · ${'course_reel_pending_upload'.tr}',
                    style: c.caption),
              ],
            ),
          ),
          IconButton(
            tooltip: 'course_reel_replace'.tr,
            icon: Icon(Icons.swap_horiz_rounded, color: c.primary),
            onPressed: controller.pick,
          ),
          IconButton(
            tooltip: 'course_reel_remove'.tr,
            icon: Icon(Icons.close_rounded, color: c.danger),
            onPressed: controller.clearPending,
          ),
        ],
      ),
    );
  }

  /// The reel already stored on the server: live 16:9 preview + actions.
  Widget _existingPreview(BuildContext context, String url) {
    final c = context.colors;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: CourseReelPlayer(
              key: ValueKey(url),
              url: url,
              posterUrl: posterUrl,
              compact: true,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: controller.pick,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text('course_reel_replace'.tr),
            ),
            TextButton.icon(
              onPressed: controller.requestRemove,
              style: TextButton.styleFrom(foregroundColor: c.danger),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text('course_reel_remove'.tr),
            ),
          ],
        ),
      ],
    );
  }
}