// The layout v3 server for widget tests (FakeApi routes): fonts, rows upload, preview, runs, templates. Shared by
// test/export/layout_flow_test.dart and test/ui/layout_flow_layout_test.dart.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';

import '../support/fake_api.dart';

/// A 1 × 1 PNG.
const kPng1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// A stream handle that is never connected (JobWatch polls at its normal pace) and binds nothing.
final kNoStream = LiveStreamHandle(connected: ValueNotifier(false), bind: () {}, release: () {});

const longAr = 'اسم طويل جدًا لطالب في قائمة المقرر يمتد إلى أكثر من سطر واحد في البطاقة';

AppTableExport layoutTestExport({int rows = 120, String? dataset, int? orgId}) => AppTableExport(
      id: 'test.students',
      title: 'Students',
      titles: const {'ar': 'الطلاب', 'en': 'Students'},
      brand: 'NextBrain Academy',
      filters: const {'Course': 'Algebra'},
      orgId: orgId,
      serverDataset: dataset,
      serverParams: dataset == null ? null : const {'course_id': 7},
      columns: const [
        AppExportColumn('name', 'Name', labels: {'ar': 'الاسم', 'en': 'Name'}, locked: true),
        AppExportColumn('score', 'Score', type: AppColType.number, labels: {'ar': 'الدرجة', 'en': 'Score'}),
        AppExportColumn('status', 'Status', type: AppColType.status, labels: {'ar': 'الحالة', 'en': 'Status'}),
        AppExportColumn('joined', 'Joined', type: AppColType.date, labels: {'ar': 'الانضمام', 'en': 'Joined'}),
        AppExportColumn('email', 'Email', visible: false, labels: {'ar': 'البريد', 'en': 'Email'}),
      ],
      rows: [
        for (var i = 0; i < rows; i++)
          {
            'name': i == 0 ? longAr : 'Student ${i + 1}',
            'score': (i * 37) % 100,
            'status': i.isEven ? 'active' : 'dropped',
            'joined': DateTime.utc(2026, 9, 1 + i % 28),
            'email': 's$i@example.com',
          },
      ],
    );

/// The fake server's state and its route table.
class LayoutFakeServer {
  int runPolls = 0;

  /// How many status reads a run takes before it is done.
  int runSteps = 2;
  bool runFails = false;

  /// The run's error when it fails (a code or a sentence).
  String runError = 'Disk full';

  /// The next preview answers 429 preview_busy.
  bool previewBusy = false;
  final posted = <String, List<Object?>>{};
  final savedTemplates = <Map<String, dynamic>>[];

  Map<String, dynamic> _body(Object? data) {
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String && data.isNotEmpty) return (jsonDecode(data) as Map).cast<String, dynamic>();
    return const {};
  }

  Map<String, FakeHandler> routes() => {
        'GET /api/v1/exports/layout/fonts': (_) => {
              'items': [
                {'id': 'tajawal', 'family': 'Tajawal', 'scripts': ['arabic', 'latin'], 'bold': true, 'italic': false},
                {'id': 'cairo', 'family': 'Cairo', 'scripts': ['arabic', 'latin'], 'bold': true, 'italic': false},
              ],
              'default': 'tajawal',
            },
        'GET /api/v1/exports/templates': (_) => {
              'items': [
                {'id': 5, 'name': 'Roster cards', 'scope': 'user', 'lang': 'en', 'format': 'pdf', 'schema_version': 3},
                {'id': 6, 'name': 'Old v2', 'scope': 'user', 'lang': 'ar', 'format': 'xlsx', 'schema_version': 2},
                ...savedTemplates,
              ],
              'last_used_id': null,
            },
        'GET /api/v1/exports/templates/5': (_) => {
              'id': 5,
              'name': 'Roster cards',
              'schema_version': 3,
              'design': {
                'schema_version': 3,
                'format': 'pdf',
                'languages': ['en'],
                'designs': {
                  'en': {
                    'mode': 'list',
                    'page': {'rtl': false},
                    'list': {'fields': ['name', 'score'], 'numbered': false},
                  },
                },
              },
            },
        'POST /api/v1/exports/templates': (o) {
          final b = _body(o.data);
          (posted['templates'] ??= []).add(b);
          final t = {'id': 9, 'name': b['name'], 'scope': b['scope'], 'lang': b['lang'], 'format': b['format'], 'schema_version': b['schema_version'], 'design': b['design']};
          savedTemplates.add(t);
          return t;
        },
        'POST /api/v1/exports/templates/*': (_) => const {'ok': true},
        'POST /api/v1/exports/layout/rows': (o) {
          (posted['rows'] ??= []).add(_body(o.data));
          return const {'upload_id': 'up1'};
        },
        'GET /api/v1/exports/datasets/course.students/columns': (o) {
          (posted['columns'] ??= []).add(o.uri.queryParameters);
          return {
            'key': 'course.students',
            'title_ar': 'طلاب المقرر',
            'title_en': 'Course students',
            'columns': [
              {'key': 'name', 'label_ar': 'الاسم', 'label_en': 'Name', 'type': 'text'},
              {'key': 'username', 'label_ar': 'اسم المستخدم', 'label_en': 'Username', 'type': 'text'},
              {'key': 'status', 'label_ar': 'الحالة', 'label_en': 'Status', 'type': 'text'},
              {'key': 'progress', 'label_ar': 'التقدم', 'label_en': 'Progress', 'type': 'percent'},
            ],
          };
        },
        'POST /api/v1/exports/layout/assets': (_) => const {'asset_id': 'a1'},
        'POST /api/v1/exports/layout/validate': (_) => const {'ok': true, 'issues': []},
        'POST /api/v1/exports/layout/preview': (o) {
          (posted['preview'] ??= []).add(_body(o.data));
          if (previewBusy) {
            return const FakeResponse(429, {'detail': {'code': 'preview_busy', 'message': 'معاينة أخرى قيد التجهيز', 'message_en': 'Another preview is running'}});
          }
          return {
            'pages': [
              {'index': 1, 'total': 5, 'png_b64': kPng1},
              {'index': 3, 'total': 5, 'png_b64': kPng1},
              {'index': 5, 'total': 5, 'png_b64': kPng1},
            ],
            'issues': [
              {'code': 'xlsx_per_line', 'format': 'xlsx', 'level': 'info', 'lang': 'en', 'message_ar': 'بطاقة واحدة في كل سطر في Excel', 'message_en': 'Excel shows one card per line'},
            ],
          };
        },
        'POST /api/v1/exports/layout/runs': (o) {
          (posted['runs'] ??= []).add(_body(o.data));
          runPolls = 0;
          return const FakeResponse(202, {'run_id': 'r1'});
        },
        'GET /api/v1/exports/layout/runs/r1': (_) {
          runPolls++;
          if (runFails) return {'status': 'failed', 'progress': 40, 'error': runError};
          return runPolls >= runSteps
              ? const {'status': 'done', 'progress': 100, 'rows': 120, 'file_name': 'Students.pdf'}
              : {'status': 'running', 'progress': 30 * runPolls, 'rows': 120};
        },
        'GET /api/v1/exports/layout/runs/r1/download': (_) => '%PDF-1.7 fake',
        'POST /api/v1/exports/layout/runs/r1/cancel': (o) {
          (posted['cancel'] ??= []).add(true);
          return const {'status': 'cancelled'};
        },
      };
}
