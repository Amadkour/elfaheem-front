// The editorial restyle of the shared overlays and list kit (D-612): sheet header / content, the confirm dialog,
// the notice, the share sheet body, the data table's phone cards and the pagination pills — no overflow at 320 x 640
// and 1400 x 900, ar + en, textScaler 1.3 — plus the behaviour the restyle touched (the notice's exit and drag,
// appConfirm's answer, the modal sheet's motion).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_share_sheet.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

const _long = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي — Office of Student Affairs, Graduate Studies and Research';

class _Row {
  const _Row(this.id, this.name);
  final int id;
  final String name;
}

final _rows = [for (var i = 0; i < 6; i++) _Row(i, 'اسم طويل جدا للطالب رقم $i Long student name number $i')];

List<AppTableColumn<_Row>> _cols() => [
      AppTableColumn.text(key: 'name', label: 'Name / الاسم', text: (r) => r.name, sortable: true, primary: true, flex: 3),
      AppTableColumn.text(key: 'id', label: 'ID', text: (r) => '${r.id}', numeric: true, sortable: true),
      AppTableColumn.text(key: 'a', label: 'Email address', text: (r) => 'student${r.id}@example.com', flex: 2),
      AppTableColumn.text(key: 'c', label: 'Status', text: (r) => 'Active'),
    ];

Widget _table(AppTableState state, {bool selectable = false, Object? current, List<_Row>? rows}) => AppDataTable<_Row>(
      shrinkWrap: true,
      columns: _cols(),
      rows: rows ?? _rows,
      state: state,
      errorText: _long,
      onRetry: () {},
      onSearch: (_) {},
      sortKey: 'name',
      onSort: (_, _) {},
      onRowTap: (_) {},
      selectable: selectable,
      selected: selectable ? {0, 2} : null,
      rowId: (r) => r.id,
      selectedRowId: current,
      bulkActions: (_) => [TextButton(onPressed: () {}, child: const Text('Archive'))],
      rowActions: (r) => [
        AppRowAction(icon: Icons.edit_outlined, label: 'Edit', onTap: () {}),
        AppRowAction(icon: Icons.delete_outline, label: 'Delete', danger: true, onTap: () {}),
      ],
      pagination: AppPagination(page: 2, pageCount: 9, onPage: (_) {}, total: 52, pageSize: 6, onPageSize: (_) {}),
    );

Widget _opener(void Function(BuildContext) open) => Center(
      child: Builder(builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open'))),
    );

/// A host with the app's [navigatorKey], so [showAppNotice] finds its overlay.
Widget _noticeHost({bool reduce = false}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: w!,
      ),
      home: const Scaffold(body: Center(child: Text('page'))),
    ),
  );
}

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');

  group('layout', () {
    testWidgets('sheet header and content', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => ListView(children: [
          AppSheetContent(
            title: _long,
            headerTrailing: TextButton(onPressed: () {}, child: const Text('Reset')),
            children: [for (var i = 0; i < 6; i++) Text('$_long $i')],
          ),
        ]),
      );
    });

    testWidgets('confirm dialog panel, long message and label', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => AppConfirmDialog(message: List.filled(10, _long).join('\n'), danger: true, confirmLabel: _long),
      );
      await expectNoLayoutErrors(tester, () => const AppConfirmDialog(message: _long));
    });

    testWidgets('share sheet body with the QR code open', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => ListView(children: [
          AppShareSheetBody(
            url: 'https://nextbrain.site/app/#/s/meeting/12?ref=1234567890abcdef',
            title: _long,
            kind: 'Meeting',
            subtitle: _long,
            hint: _long,
            icon: Icons.groups_rounded,
            showQr: true,
            copied: true,
            onCopy: () {},
            onShare: () {},
            onToggleQr: () {},
          ),
        ]),
      );
    });

    testWidgets('data table: every state, selected and open rows (cards on phones)', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => ListView(children: [
          _table(AppTableState.ready, selectable: true, current: 1),
          AppSpace.gapMd,
          _table(AppTableState.loading),
          AppSpace.gapMd,
          _table(AppTableState.error),
          AppSpace.gapMd,
          _table(AppTableState.ready, rows: const []),
        ]),
      );
    });

    testWidgets('pagination pills', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => Column(children: [
          AppPagination(page: 7, pageCount: 40, onPage: (_) {}, total: 800, pageSize: 20, onPageSize: (_) {}),
          AppPagination(page: 1, pageCount: 1, onPage: (_) {}, total: 0),
        ]),
      );
    });

    testWidgets('showAppModalSheet with a builder of its own', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _opener((c) => showAppModalSheet<void>(
              context: c,
              // a caller's own content scrolls (as with a plain showModalBottomSheet); the kit draws the sheet around it
              builder: (_) => SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < 8; i++) ListTile(title: Text('$_long $i'))]),
              ),
            )),
        act: (tester) => tester.tap(find.text('open')),
      );
    });

    testWidgets('a notice with an action, at every size', (tester) async {
      for (final size in layoutSizes) {
        for (final lang in layoutLangs) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(_noticeHost());
          showAppNotice(_long, error: true, actionLabel: 'Undo', onAction: () {});
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text(_long), findsOneWidget);
          hideAppNotice();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: '${size.width.toInt()} / $lang');
        }
      }
      AppConfig.lang = 'en';
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('behaviour', () {
    testWidgets('the notice slides in, leaves on tap with its exit, and a drag up dismisses it', (tester) async {
      await tester.pumpWidget(_noticeHost());
      expect(showAppNotice('Saved'), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Saved'), findsOneWidget);
      await tester.tap(find.text('Saved'));
      await tester.pump();
      // the exit plays (180 ms) before the entry leaves the overlay
      expect(find.text('Saved'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Saved'), findsNothing);

      showAppNotice('Dragged');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(find.text('Dragged'), const Offset(0, -80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Dragged'), findsNothing);

      // a short drag snaps back and the notice stays
      showAppNotice('Stays');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // past the touch slop (a shorter move is a tap, which closes it) but short of the dismiss distance, slowly
      await tester.timedDrag(find.text('Stays'), const Offset(0, -24), const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Stays'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // the auto-dismiss timer, then the exit
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Stays'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Reduce motion: the notice is there on the first frame and gone at once', (tester) async {
      await tester.pumpWidget(_noticeHost(reduce: true));
      showAppNotice('Now');
      await tester.pump();
      expect(find.text('Now'), findsOneWidget);
      hideAppNotice();
      await tester.pump();
      expect(find.text('Now'), findsNothing);
    });

    testWidgets('appConfirm answers true on Confirm and false on Cancel', (tester) async {
      bool? answer;
      await tester.pumpWidget(layoutHost(_opener((c) async => answer = await appConfirm(c, message: 'Sure?', danger: true))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sure?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app.confirm.ok')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(answer, isTrue);
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('app.confirm.cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(answer, isFalse);
      expect(find.text('Sure?'), findsNothing);
    });

    testWidgets('showAppModalSheet on a phone keeps the sheet motion (M14: 500 in / 200 out)', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late ModalRoute<dynamic> route;
      await tester.pumpWidget(layoutHost(_opener((c) => showAppModalSheet<void>(
            context: c,
            builder: (ctx) {
              route = ModalRoute.of(ctx)!;
              return const SizedBox(height: 200, child: Text('sheet body'));
            },
          ))));
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(route.transitionDuration, const Duration(milliseconds: 500)); // M14 peek (KIT_SPEC 5.8; was 280)
      expect(route.reverseTransitionDuration, const Duration(milliseconds: 200));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('sheet body'), findsOneWidget);
    });
  });
}
