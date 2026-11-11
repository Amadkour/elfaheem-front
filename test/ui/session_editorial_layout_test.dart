// The editorial restyle of the session area (player sheets, material panel, upload footer): no overflow at
// 320 × 640 and 1400 × 900, Arabic and English, text × 1.3.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/shared/session/material/components/add_material_sheet.dart';
import 'package:flutter_education_app/features/shared/session/material/components/session_exam_tile.dart';
import 'package:flutter_education_app/features/shared/session/material/components/session_shared_widgets.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/features/shared/session/session_track_tabs.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_player_parts.dart';
import 'package:flutter_education_app/features/shared/upload/upload_progress_footer.dart';
import 'package:flutter_education_app/features/shared/upload/upload_task.dart';
import 'package:flutter_education_app/features/student/courses/details/session_exam_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'المحاضرة الثالثة — التكامل بالتجزئة وتطبيقاته في الفيزياء والهندسة والاقتصاد';

UploadTask _task(String name, UploadStatus status, {double p = 0, bool retry = false}) => UploadTask(
      sessionId: 4,
      fileName: name,
      cancelToken: CancelToken(),
      dio: Dio(),
      path: '',
      endpoint: '',
      fields: const {},
    )
      ..status = status
      ..totalBytes = 100
      ..sentBytes = (p * 100).round()
      ..canRetry = retry;

SessionMaterialModel _m(int id, {bool done = false}) => SessionMaterialModel(
      id: id,
      sessionId: 7,
      name: '$_long $id',
      type: SessionMaterialType.video,
      order: id,
      createdAt: DateTime(2026),
      completed: done,
      durationSeconds: 3725,
    );

void main() {
  testWidgets('upload footer, folded and unfolded, never overflows', (t) async {
    final tasks = [
      _task('$_long.mp4', UploadStatus.uploading, p: 0.42),
      _task('summary-of-the-first-lecture-with-a-very-long-name.pdf', UploadStatus.success),
      _task('worksheet.docx', UploadStatus.failed, retry: true),
      _task('cancelled.png', UploadStatus.cancelled),
    ];
    Widget footer(bool expanded, double? p) => UploadProgressFooterView(
          tasks: tasks,
          expanded: expanded,
          overallProgress: p,
          activeCount: 3,
          onToggle: () {},
          onCancel: (_) {},
          onRetry: (_) {},
          onDismiss: (_) {},
        );
    await expectNoLayoutErrors(
        t, () => SingleChildScrollView(child: Column(children: [footer(false, 0.42), footer(true, 0.42), footer(false, null)])));
  });

  testWidgets('exam gate in every state and the track tabs never overflow', (t) async {
    SessionExamInfo exam(Map<String, dynamic> j) => SessionExamInfo.fromJson({'question_count': 10, 'name': _long, ...j});
    await expectNoLayoutErrors(
      t,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        SessionTrackTabs(value: 'lecture', lectures: 160, sections: 90, onChanged: (_) {}),
        const SizedBox(height: 12),
        SessionExamTile(gate: SessionExamGate([exam({'id': 1, 'passing_score': 60, 'remaining_submissions': 2})]), isTeacher: false, onOpen: () {}),
        SessionExamTile(
            gate: SessionExamGate([exam({'id': 2, 'attempted': true, 'best_percentage': 40, 'remaining_submissions': 1}), exam({'id': 5})]),
            isTeacher: false,
            onOpen: () {}),
        SessionExamTile(gate: SessionExamGate([exam({'id': 3, 'attempted': true, 'passed': true, 'best_percentage': 86})]), isTeacher: false),
        SessionExamTile(gate: SessionExamGate([exam({'id': 4, 'attempted': true, 'remaining_submissions': 0})]), isTeacher: false),
        SessionExamTile(gate: SessionExamGate([exam({'id': 6, 'passing_score': 60})]), isTeacher: true),
        Builder(
          builder: (context) => Wrap(spacing: 8, runSpacing: 8, children: [
            SessionActionBtn(icon: Icons.videocam_rounded, label: _long, color: context.colors.danger, filled: true, onTap: () {}),
            SessionActionBtn(icon: Icons.how_to_reg_rounded, label: 'Attendance', color: context.colors.primary, onTap: () {}),
            SessionActionBtn(icon: Icons.upload_rounded, label: 'Upload', color: context.colors.success, loading: true),
          ]),
        ),
        const SessionTypePill(isLive: true),
        const SessionPill('PowerPoint', Colors.deepOrange),
      ]),
    );
  });

  testWidgets('the add material sheet never overflows', (t) async {
    await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: AddMaterialSheet(sessionId: 4)));
  });

  testWidgets('the lecture list with the playing lecture and the next-up card never overflow', (t) async {
    await expectNoLayoutErrors(
      t,
      () => ColoredBox(
        color: VodInk.letterbox,
        child: ListView(children: [
          VodLectureList(items: [_m(1, done: true), _m(2), _m(3)], currentId: 2, onSelect: (_) {}),
          VodNextUpCard(next: _m(3), seconds: 2, maxWidth: 288, onPlay: () {}, onCancel: () {}),
          VodNextUpCard(next: _m(3), seconds: null, maxWidth: 288, onPlay: () {}, onCancel: () {}),
          const VodAudioOnlyTile(onTap: _noop),
        ]),
      ),
    );
  });
}

void _noop() {}
