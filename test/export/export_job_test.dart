// Background exports (7.2): the writer runs on another isolate with the app's language / translations / timezone,
// Cancel kills it at once, the progress dialog shows the step and fits every screen.
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/export/export_job.dart';
import 'package:flutter_education_app/design/export/table_export_model.dart';
import 'package:flutter_education_app/design/export/table_export_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  test('the writer runs on its own isolate with the app language, translations and timezone', () async {
    AppConfig.lang = 'en';
    translation['exs_test_key'] = {'en': 'From the app', 'ar': 'من التطبيق'};
    AppTime.configureOrg('Asia/Riyadh', '24h');
    addTearDown(() {
      translation.remove('exs_test_key');
      AppTime.configureOrg(null, null);
    });
    final main = Isolate.current.hashCode;
    final r = await exportCompute(() => (Isolate.current.hashCode, AppConfig.lang, translate('exs_test_key'), AppTime.zoneId, AppTime.use24h));
    expect(r.$1, isNot(main));
    expect(r.$2, 'en');
    expect(r.$3, 'From the app');
    expect(r.$4, 'Asia/Riyadh');
    expect(r.$5, isTrue);
  });

  test('a real writer comes back as bytes', () async {
    final e = AppTableExport(id: 'j', title: 'Jobs', columns: const [AppExportColumn('a', 'A')], rows: [for (var i = 0; i < 500; i++) {'a': 'row $i'}]);
    final bytes = await exportCompute(() => appTableXlsx(e));
    expect(bytes.sublist(0, 2), [0x50, 0x4B]); // a zip
  });

  test('Cancel stops a long writer at once', () async {
    final job = ExportJob();
    final watch = Stopwatch()..start();
    final run = exportCompute(() {
      // ~forever: only a kill ends it
      var x = 0;
      final end = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(end)) {
        x++;
      }
      return x;
    }, job: job);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    job.cancel();
    await expectLater(run, throwsA(isA<ExportCancelled>()));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('an error in the writer reaches the caller', () async {
    await expectLater(exportCompute<int>(() => throw StateError('broken')), throwsA(isA<RemoteError>()));
  });

  testWidgets('the progress dialog: step text, Cancel returns null', (tester) async {
    await tester.pumpWidget(layoutHost(Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final r = await runExportWithProgress<int>(context, (job) async {
            job.step('Writing PDF · English', .4);
            await job.onCancel;
            job.throwIfCancelled();
            return 1;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('result $r')));
        },
        child: const Text('go'),
      ),
    ), scale: 1));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Writing PDF · English'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, closeTo(.4, 1e-9));
    await tester.tap(find.byType(TextButton).last);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ExportProgressDialog), findsNothing);
    expect(find.text('result null'), findsOneWidget);
  });

  testWidgets('the progress dialog has no overflow on any screen', (tester) async {
    final job = ExportJob()..step('جلب الصفوف 12000 / 20000 · كتابة ملف PDF طويل جدًا باسم طويل', .6);
    await expectNoLayoutErrors(tester, () => ExportProgressDialog(job: job));
  });
}
