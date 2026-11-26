// Review renders of دفتر المادة (SubjectProfile rows 17-18, 27-30): view, keyboard and pen, 390x844 and 1360x900,
// ar + en, with the CAST demo notebook. Not a CI suite; compare by eye with
// D:/platform/redesign-ref/ref/subject/0{17,18,27..30}_*Notes*.png.
//
//   flutter test test/visual/redesign/sb/notebook_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_panel.dart';
import 'package:flutter_education_app/features/notebook/notebook_panel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_api.dart';
import '../../../support/redesign/sb_notebook_fakes.dart';
import '../kit_golden_harness.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The panel as the subject page opens it: a full-height sheet on a phone, the 520 drawer at the end side on web.
Widget _shot(NotebookMode mode) => AppAreaScope(
  area: AppArea.learn,
  child: Builder(
    builder: (context) {
      final phone = MediaQuery.sizeOf(context).width < 700;
      final frame = SubjectPanelFrame(
        title: _t('دفتر الرياضيات', 'Maths notebook'),
        child: NotebookPanel(courseId: 41, subjectId: 3, subjectTitle: _t('الرياضيات', 'Maths'), initialMode: mode),
      );
      final panel = Material(color: context.colors.cardBg, child: frame);
      if (phone) return panel;
      return ColoredBox(
        color: context.colors.kit.deep,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: SizedBox(width: kSubjectPanelNarrow, child: panel),
        ),
      );
    },
  ),
);

Future<void> _draw(WidgetTester tester) async {
  final r = tester.getRect(find.byType(AspectRatio).last);
  Future<void> stroke(List<Offset> pts) async {
    final g = await tester.startGesture(r.topLeft + pts.first);
    for (final p in pts.skip(1)) {
      await g.moveTo(r.topLeft + p);
    }
    await g.up();
  }

  final w = r.width, h = r.height;
  // the axes
  await stroke([Offset(w * .12, h * .1), Offset(w * .12, h * .85), Offset(w * .9, h * .85)]);
  // y = 2^x
  await stroke([
    for (var i = 0; i <= 16; i++)
      Offset(w * (.15 + .6 * i / 16), h * (.82 - .7 * ((1 << (i ~/ 2)) - 1) / 255 - .002 * i * i)),
  ]);
}

void main() {
  late StorageService storage;
  late FakeApi fake;
  setUpAll(() async => storage = await kitGoldenSetUp());
  setUp(() {
    mockRequestPlugins();
    fake = FakeApi(NotebookFakeStore().routes, latency: const Duration(milliseconds: 10))..install();
  });
  tearDown(() => fake.uninstall());

  testWidgets('notebook view', (tester) async {
    await kitRender(tester, 'sb_notebook_view', () => _shot(NotebookMode.view), storage: storage, modes: const [false], grow: false);
  });

  testWidgets('notebook keyboard', (tester) async {
    await kitRender(
      tester,
      'sb_notebook_type',
      () => _shot(NotebookMode.type),
      storage: storage,
      modes: const [false],
      grow: false,
      act: (tester) async {
        await tester.tap(find.text('sb_nb_tool_heading'.tr));
        await tester.pump();
        await tester.enterText(find.byType(TextField), _t('الدوال الأسية', 'Exponential functions'));
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        await tester.enterText(find.byType(TextField), _t('ص = ٢^س تتضاعف بسرعة.', 'y = 2^x doubles fast.'));
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        await tester.enterText(find.byType(TextField), _t('مثال: البكتيريا تتضاعف كل ساعة', 'Example: bacteria double every hour'));
        await tester.pump();
      },
    );
  });

  testWidgets('notebook pen', (tester) async {
    await kitRender(
      tester,
      'sb_notebook_pen',
      () => _shot(NotebookMode.pen),
      storage: storage,
      modes: const [false],
      grow: false,
      act: _draw,
    );
  });
}
