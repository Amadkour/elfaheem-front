// Export Studio pages (D-130 / D-134): every piece lays out at 320x640 and 1400x900, Arabic and English, text 1.3 —
// the log tile and filters, the schedule card (weekly by e-mail, paused monthly), the runs sheet, the schedule form
// (weekly + e-mail with recipients, monthly, a fixed data source), the link card, the share-link sheet before and
// after the link exists, the link-open states, the hub — and each full page over FakeApi with data, empty and error
// answers (plus the export log's 403 and an older server's bare 404).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/design/export/export_studio_api.dart';
import 'package:flutter_education_app/features/exports/export_link_open_page.dart';
import 'package:flutter_education_app/features/exports/export_links_page.dart';
import 'package:flutter_education_app/features/exports/export_log_page.dart';
import 'package:flutter_education_app/features/exports/export_schedules_page.dart';
import 'package:flutter_education_app/features/exports/exports_center_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

final _now = DateTime.now().toUtc();
String _iso(DateTime d) => d.toUtc().toIso8601String().replaceFirst('Z', '');

const _longAr = 'تقرير أعضاء المؤسسة الأسبوعي لكلية الهندسة والعلوم التطبيقية بجميع الأقسام والبرامج';
const _longEn = 'Weekly members report of the Faculty of Engineering and Applied Sciences, every department and programme';

Map<String, dynamic> _scheduleJson({int id = 1, String cadence = 'weekly', String status = 'active', String delivery = 'email'}) => {
      'id': id,
      'name': id.isOdd ? _longAr : _longEn,
      'org_id': 12,
      'dataset': 'org.people',
      'params': {'org_id': 12, 'roles': 'student,teacher'},
      'template_id': null,
      'format': id.isOdd ? 'xlsx' : 'pdf',
      'lang': id.isOdd ? 'ar' : 'en',
      'cadence': cadence,
      'hour': 7,
      'minute': 30,
      'weekday': cadence == 'weekly' ? 0 : null,
      'monthday': cadence == 'monthly' ? 31 : null,
      'timezone': 'Asia/Riyadh',
      'delivery': delivery,
      'recipients': delivery == 'email' ? ['dean.office.engineering@university.example.edu', 'registrar@university.example.edu'] : [],
      'status': status,
      'pause_reason': status == 'paused' ? 'permission_revoked' : null,
      'next_run_at': _iso(_now.add(const Duration(days: 2))),
      'last_run_at': _iso(_now.subtract(const Duration(days: 5))),
      'last_status': status == 'paused' ? 'failed' : 'ready',
      'fail_count': 0,
    };

Map<String, dynamic> _runJson(int id, String status) => {
      'id': id,
      'schedule_id': 1,
      'dataset': 'org.people',
      'format': 'xlsx',
      'lang': 'ar',
      'status': status,
      'file_name': '${_longAr}_2026-10-31.xlsx',
      'size': 1843200,
      'rows': 12450,
      'error': status == 'failed' ? 'permission_revoked' : null,
      'created_at': _iso(_now.subtract(Duration(hours: id))),
    };

Map<String, dynamic> _linkJson(int id, {bool revoked = false, bool expired = false, String audience = 'org', String? token}) => {
      'id': id,
      'run_id': null,
      'file_name': '${id.isOdd ? _longAr : _longEn}.pdf',
      'size': 734003,
      'dataset': null,
      'org_id': 12,
      'audience': audience,
      'note': null,
      'expires_at': _iso(expired ? _now.subtract(const Duration(days: 1)) : _now.add(const Duration(days: 6, hours: 3))),
      'revoked_at': revoked ? _iso(_now.subtract(const Duration(hours: 2))) : null,
      'download_count': 1234,
      'last_download_at': null,
      'created_at': _iso(_now.subtract(const Duration(days: 1))),
      'token': ?token,
    };

Map<String, dynamic> _logJson(int id) => {
      'id': id,
      'user': {'id': 900 + id, 'name': id.isOdd ? 'أحمد حمدي عبد الرحمن محمد مدكور السيد' : 'Alexandria Konstantinopoulou-Montgomery'},
      'org_id': 12,
      'channel': const ['interactive', 'schedule', 'link'][id % 3],
      'page_key': 'org.people.members.department.engineering.long.page.key.$id',
      'dataset': 'org.people',
      'format': const ['xlsx', 'docx', 'pdf', 'csv'][id % 4],
      'lang': 'ar',
      'rows': 125000 + id,
      'columns': ['name', 'email', 'phone', 'role', 'department', 'joined_at'],
      'template_id': null,
      'filters': {},
      'created_at': _iso(_now.subtract(Duration(hours: id))),
    };

const _datasets = {
  'items': [
    {'key': 'org.people', 'title_ar': 'أعضاء المؤسسة', 'title_en': 'Organization members', 'params': ['org_id', 'roles', 'status']},
    {'key': 'course.students', 'title_ar': 'طلاب المقرر', 'title_en': 'Course students', 'params': ['course_id', 'include_dropped']},
  ],
};

ExportScheduleInfo _schedule({int id = 1, String cadence = 'weekly', String status = 'active', String delivery = 'email'}) =>
    ExportScheduleInfo.fromJson(_scheduleJson(id: id, cadence: cadence, status: status, delivery: delivery));

List<ExportDatasetInfo> get _datasetInfos => [for (final j in _datasets['items']!) ExportDatasetInfo.fromJson(j)];

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

/// What the fake backend answers: data, empty lists, or an error.
enum _Mode { data, empty, error, missing, forbidden }

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.disableList = []);

  group('pure', () {
    test('weekday 0 is Monday (the server\'s date.weekday()); cadence words', () {
      AppConfig.lang = 'en';
      expect(exportWeekdayName(0), 'Monday');
      expect(exportWeekdayName(6), 'Sunday');
      expect(exportCadenceText(cadence: 'weekly', hour: 7, minute: 0, weekday: 0), startsWith('Every Monday at '));
      expect(exportCadenceText(cadence: 'monthly', hour: 7, minute: 0, monthday: 5), startsWith('Every month on day 5 at '));
      expect(exportCadenceText(cadence: 'daily', hour: 7, minute: 0), startsWith('Every day at '));
      AppConfig.lang = 'ar';
      expect(exportWeekdayName(0), 'الإثنين');
    });

    test('the draft writes the server body', () {
      final d = ExportScheduleDraft(dataset: 'org.people', params: {'org_id': '12', 'roles': 'student', 'status': ''}, cadence: 'weekly', weekday: 3, delivery: 'email', recipients: ['a@b.co'], timezone: 'Africa/Cairo');
      final b = d.toBody();
      expect(b['params'], {'org_id': 12, 'roles': 'student'});
      expect(b['weekday'], 3);
      expect(b['monthday'], isNull);
      expect(b['recipients'], ['a@b.co']);
      expect(b['timezone'], 'Africa/Cairo');
      d
        ..cadence = 'monthly'
        ..monthday = 31
        ..delivery = 'list';
      final m = d.toBody();
      expect(m['weekday'], isNull);
      expect(m['monthday'], 31);
      expect(m['recipients'], isEmpty);
      final back = ExportScheduleDraft.fromInfo(_schedule());
      expect(back.weekday, 0);
      expect(back.params['org_id'], '12');
    });

    test('e-mail check, link state, file sniffing', () {
      AppConfig.lang = 'en';
      expect(exportEmailValid('dean@university.example.edu'), isTrue);
      expect(exportEmailValid('not an email'), isFalse);
      expect(exportLinkStateText(ExportLinkInfo.fromJson(_linkJson(1, revoked: true)), _now), 'Revoked');
      expect(exportLinkStateText(ExportLinkInfo.fromJson(_linkJson(1, expired: true)), _now), 'Expired');
      expect(exportLinkStateText(ExportLinkInfo.fromJson(_linkJson(1)), _now), 'Expires in 7 days');
      expect(exportSniffExtension(Uint8List.fromList(utf8.encode('%PDF-1.7'))), 'pdf');
      expect(exportSniffExtension(Uint8List.fromList([0x50, 0x4B, ...utf8.encode('....word/document.xml')])), 'docx');
      expect(exportSniffExtension(Uint8List.fromList([0x50, 0x4B, ...utf8.encode('....xl/workbook.xml')])), 'xlsx');
    });
  });

  group('presentational', () {
    testWidgets('log tiles and filters', (t) async {
      final entries = [for (var i = 1; i <= 4; i++) ExportLogEntry.fromJson(_logJson(i))];
      final user = TextEditingController(text: '12345'), key = TextEditingController(text: 'org.people.members');
      addTearDown(() {
        user.dispose();
        key.dispose();
      });
      await expectNoLayoutErrors(
        t,
        () => ListView(padding: const EdgeInsets.all(16), children: [
          ExportLogFilters(user: user, pageKey: key, format: 'xlsx', channel: 'schedule', rangeLabel: '1 Oct 2026 – 31 Oct 2026'),
          for (final e in entries) ExportLogTile(entry: e),
          ExportLogTile(entry: ExportLogEntry.fromJson({'id': 9, 'format': 'pdf'})),
          const ExportLogForbidden(),
        ]),
      );
    });

    testWidgets('schedule cards: weekly by e-mail, paused monthly kept in the list', (t) async {
      await expectNoLayoutErrors(
        t,
        () => ListView(padding: const EdgeInsets.all(16), children: [
          ExportScheduleCard(info: _schedule(), datasetTitle: 'أعضاء المؤسسة', onToggle: () {}, onRunNow: () {}, onRuns: () {}, onEdit: () {}, onDelete: () {}),
          ExportScheduleCard(info: _schedule(id: 2, cadence: 'monthly', status: 'paused', delivery: 'list'), busy: true, onToggle: () {}),
          ExportScheduleCard(info: _schedule(id: 3, cadence: 'daily')),
        ]),
      );
    });

    testWidgets('runs sheet: files, loading, empty, error, older server', (t) async {
      final runs = [
        ExportRunInfo.fromJson(_runJson(1, 'ready')),
        ExportRunInfo.fromJson(_runJson(2, 'running')),
        ExportRunInfo.fromJson(_runJson(3, 'failed')),
        ExportRunInfo.fromJson(_runJson(4, 'expired')),
      ];
      await expectNoLayoutErrors(t, () => ExportRunsSheetBody(title: _longAr, runs: runs, downloadingId: 1, onDownload: (_) {}));
      await expectNoLayoutErrors(t, () => const ExportRunsSheetBody(title: 'Files'));
      await expectNoLayoutErrors(t, () => const ExportRunsSheetBody(title: 'Files', runs: []));
      await expectNoLayoutErrors(t, () => ExportRunsSheetBody(title: '', error: 'Something went wrong. Try again.', onRetry: () {}));
      await expectNoLayoutErrors(t, () => const ExportRunsSheetBody(title: 'Files', missing: true));
    });

    testWidgets('schedule form: weekly + e-mail with recipients', (t) async {
      final templates = [StudioTemplate(id: 4, name: 'قالب التقرير الرسمي لمجلس الكلية بالشعار والتوقيعات', format: 'xlsx')];
      await expectNoLayoutErrors(
        t,
        () => _scroll(ExportScheduleFormBody(
          draft: ExportScheduleDraft(
            name: _longEn,
            dataset: 'org.people',
            params: {'org_id': '12'},
            templateId: 4,
            delivery: 'email',
            recipients: ['dean.office.engineering@university.example.edu', 'registrar@university.example.edu', 'it@x.io'],
            timezone: 'Africa/Cairo',
          ),
          datasets: _datasetInfos,
          templates: templates,
          error: 'Files can only be e-mailed to people of the same organization',
          onSubmit: () {},
        )),
      );
    });

    testWidgets('schedule form: monthly, fixed data source, templates loading', (t) async {
      await expectNoLayoutErrors(
        t,
        () => _scroll(ExportScheduleFormBody(
          draft: ExportScheduleDraft(dataset: 'course.students', cadence: 'monthly', monthday: 31, hour: 23, minute: 45, format: 'pdf', lang: 'en'),
          datasets: _datasetInfos,
          datasetFixed: true,
          isEdit: true,
          busy: true,
          onSubmit: () {},
        )),
      );
      await expectNoLayoutErrors(
        t,
        () => _scroll(ExportScheduleFormBody(draft: ExportScheduleDraft(cadence: 'daily'), datasets: _datasetInfos, templates: const [], onSubmit: () {})),
      );
    });

    testWidgets('link cards: fresh with its link, older, expired, revoked', (t) async {
      final fresh = ExportLinkInfo.fromJson(_linkJson(1, token: 'aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5bC7dE9f'));
      await expectNoLayoutErrors(
        t,
        () => ListView(padding: const EdgeInsets.all(16), children: [
          ExportLinkCard(info: fresh, nowUtc: _now, onCopy: () {}, onRevoke: () {}),
          ExportLinkCard(info: ExportLinkInfo.fromJson(_linkJson(2, audience: 'me')), nowUtc: _now, busy: true, onRevoke: () {}),
          ExportLinkCard(info: ExportLinkInfo.fromJson(_linkJson(3, expired: true)), nowUtc: _now),
          ExportLinkCard(info: ExportLinkInfo.fromJson(_linkJson(4, revoked: true)), nowUtc: _now),
          ExportLinkCard(info: ExportLinkInfo.fromJson({'id': 5}), nowUtc: _now),
        ]),
      );
    });

    testWidgets('share-link sheet: before and after the link exists', (t) async {
      await expectNoLayoutErrors(
        t,
        () => _scroll(ExportShareLinkBody(fileName: '${_longAr}_2026-10-31.xlsx', size: 1843200, orgAllowed: true, audience: 'org', days: 14, onCreate: () {})),
      );
      await expectNoLayoutErrors(
        t,
        () => _scroll(ExportShareLinkBody(
          fileName: '$_longEn.pdf',
          orgAllowed: false,
          audience: 'me',
          days: 1,
          busy: true,
          error: 'Sharing with the organization needs an organization',
        )),
      );
      final link = ExportLinkInfo.fromJson(_linkJson(1, token: 'aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5bC7dE9fG1hJ3kL5mN7'));
      await expectNoLayoutErrors(
        t,
        () => _scroll(ExportShareLinkBody(
          fileName: '${_longAr}_2026-10-31.xlsx',
          size: 1843200,
          orgAllowed: true,
          audience: 'org',
          days: 7,
          link: link,
          onCopy: () {},
          onDone: () {},
        )),
      );
      await expectNoLayoutErrors(t, () => _scroll(const ExportNewLinkChooser()));
    });

    testWidgets('link-open states', (t) async {
      await expectNoLayoutErrors(t, () => _scroll(const ExportLinkOpenView(phase: ExportLinkOpenPhase.loading)));
      await expectNoLayoutErrors(
        t,
        () => _scroll(ExportLinkOpenView(phase: ExportLinkOpenPhase.saved, fileName: '${_longAr}_2026-10-31.xlsx', size: 1843200, onDownloadAgain: () {}, onBack: () {})),
      );
      for (final code in ['link_expired', 'link_revoked', 'link_forbidden', 'link_other_org', 'link_not_found', 'not_authenticated', null]) {
        await expectNoLayoutErrors(
          t,
          () => _scroll(ExportLinkOpenView(phase: ExportLinkOpenPhase.failed, code: code, error: 'Something went wrong. Try again.', onRetry: () {}, onBack: () {})),
        );
      }
      await expectNoLayoutErrors(t, () => _scroll(ExportLinkOpenView(phase: ExportLinkOpenPhase.failed, missing: true, onBack: () {})));
    });

    testWidgets('the hub, with and without the admin tile', (t) async {
      await expectNoLayoutErrors(t, () => const ExportsCenterPage(admin: true), scaffold: false);
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(const ExportsCenterPage(admin: true), scaffold: false));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Export log'), findsOneWidget);
      expect(find.text('Scheduled exports'), findsOneWidget);
      await t.pumpWidget(layoutHost(const ExportsCenterPage(), scaffold: false));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Export log'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('full pages over FakeApi', () {
    var mode = _Mode.data;
    late FakeApi api;

    Object? answer(Object? data, Object? empty) => switch (mode) {
          _Mode.data => data,
          _Mode.empty => empty,
          _Mode.error => const FakeResponse(400, {'detail': 'Database unavailable, please try again shortly'}),
          _Mode.missing => const FakeResponse(404, {'detail': 'Not Found'}),
          _Mode.forbidden => const FakeResponse(403, {'detail': {'code': 'export_log_forbidden', 'message': 'لا تملك صلاحية'}}),
        };

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      await StorageService.getInstance();
      api = FakeApi({
        'GET /api/v1/exports/schedules': (_) => answer({'items': [_scheduleJson(), _scheduleJson(id: 2, cadence: 'monthly', status: 'paused', delivery: 'list')]}, {'items': []}),
        'GET /api/v1/exports/datasets': (_) => answer(_datasets, {'items': []}),
        'GET /api/v1/exports/templates': (_) => answer({'items': [], 'default_id': null}, {'items': []}),
        'GET /api/v1/exports/runs': (_) => answer({'items': [_runJson(1, 'ready')], 'total': 1, 'page': 1, 'size': 30}, {'items': [], 'total': 0}),
        'GET /api/v1/exports/links': (_) => answer({'items': [_linkJson(1), _linkJson(2, revoked: true), _linkJson(3, expired: true, audience: 'me')]}, {'items': []}),
        'GET /api/v1/exports/log': (_) => answer({'total': 120, 'page': 1, 'size': 50, 'pages': 3, 'items': [for (var i = 1; i <= 6; i++) _logJson(i)]},
            {'total': 0, 'page': 1, 'size': 50, 'pages': 1, 'items': []}),
        'GET /api/v1/exports/links/*': (_) => const FakeResponse(410, {'detail': {'code': 'link_expired', 'message': 'انتهت صلاحية الرابط'}}),
      }, latency: const Duration(milliseconds: 10))
        ..install();
    });
    tearDownAll(() => api.uninstall());
    tearDown(() => mode = _Mode.data);

    for (final m in [_Mode.data, _Mode.empty, _Mode.error, _Mode.missing]) {
      testWidgets('schedules page: ${m.name}', (t) async {
        mode = m;
        await expectNoLayoutErrors(t, () => ExportSchedulesPage(api: ExportStudioApi()), scaffold: false, frames: 6);
      });
      testWidgets('links page: ${m.name}', (t) async {
        mode = m;
        await expectNoLayoutErrors(t, () => ExportLinksPage(api: ExportStudioApi()), scaffold: false, frames: 6);
      });
    }

    for (final m in _Mode.values) {
      testWidgets('log page: ${m.name}', (t) async {
        mode = m;
        await expectNoLayoutErrors(t, () => const ExportLogPage(orgId: 12), scaffold: false, frames: 6);
      });
    }

    testWidgets('schedules page: the cards show the data; New schedule opens the form', (t) async {
      await expectNoLayoutErrors(
        t,
        () => ExportSchedulesPage(api: ExportStudioApi()),
        scaffold: false,
        frames: 6,
        act: (t) async => t.tap(find.byType(FloatingActionButton)),
      );
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(ExportSchedulesPage(api: ExportStudioApi()), scaffold: false));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ExportScheduleCard), findsNWidgets(2));
      expect(find.textContaining('Every Monday at'), findsOneWidget);
      await t.tap(find.byType(FloatingActionButton));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ExportScheduleFormBody), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('links page: New link opens the chooser; the once-only note shows', (t) async {
      await expectNoLayoutErrors(
        t,
        () => ExportLinksPage(api: ExportStudioApi()),
        scaffold: false,
        frames: 6,
        act: (t) async => t.tap(find.byType(FloatingActionButton)),
      );
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(ExportLinksPage(api: ExportStudioApi()), scaffold: false));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ExportLinkCard), findsNWidgets(3));
      expect(find.textContaining('A link is shown once'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('link-open page: an expired link', (t) async {
      await expectNoLayoutErrors(t, () => ExportLinkOpenPage(token: 'tok-123', api: ExportStudioApi()), scaffold: false, frames: 6);
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(ExportLinkOpenPage(token: 'tok-123', api: ExportStudioApi()), scaffold: false));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('This link has expired'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('log page: the 403 shows the calm admins-only state', (t) async {
      mode = _Mode.forbidden;
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(const ExportLogPage(), scaffold: false));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ExportLogForbidden), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}
