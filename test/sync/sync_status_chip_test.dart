// SyncStatusChip (F12, D-1351): hidden while online with nothing waiting, a labelled button otherwise, no overflow
// at any size / language / text scale, and its spinner parked under Reduce motion.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/offline/sync/sync_status.dart';
import 'package:flutter_education_app/design/sync_status_chip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  const states = [
    SyncSnapshot(phase: SyncPhase.offline, pending: 0),
    SyncSnapshot(phase: SyncPhase.offline, pending: 3),
    SyncSnapshot(phase: SyncPhase.offline, pending: 120),
    SyncSnapshot(phase: SyncPhase.syncing, pending: 4),
    SyncSnapshot(phase: SyncPhase.online, pending: 2),
  ];

  testWidgets('no layout errors in every state, in a header row', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Row(children: [
        const Expanded(child: Text('Good evening, a very long name that wraps')),
        for (final s in states) SyncStatusChipView(snapshot: s, onTap: () {}),
      ]),
    );
  });

  testWidgets('online with nothing waiting draws nothing; otherwise a labelled button', (tester) async {
    AppConfig.lang = 'en';
    final status = SyncStatus();
    await tester.pumpWidget(layoutHost(SyncStatusChip(status: status)));
    expect(find.byKey(const ValueKey('sync.status.chip')), findsNothing);

    status.setOnline(false);
    status.report(SyncStatus.outbox, 3);
    await tester.pump();
    expect(find.byKey(const ValueKey('sync.status.chip')), findsOneWidget);
    expect(find.bySemanticsLabel('You are offline, 3 changes wait to be sent'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    AppConfig.lang = 'ar';
    status.report(SyncStatus.outbox, 2);
    await tester.pump();
    expect(find.bySemanticsLabel('أنت غير متصل، تغييران ينتظران الإرسال'), findsOneWidget);
    AppConfig.lang = 'en';

    status.setOnline(true);
    status.report(SyncStatus.outbox, 0);
    await tester.pump();
    expect(find.byKey(const ValueKey('sync.status.chip')), findsNothing);
  });

  testWidgets('the syncing arrow turns, and rests under Reduce motion', (tester) async {
    AppConfig.lang = 'en';
    const snap = SyncSnapshot(phase: SyncPhase.syncing, pending: 1);
    await tester.pumpWidget(layoutHost(const SyncStatusChipView(snapshot: snap)));
    await tester.pump(const Duration(milliseconds: 300));
    final turns = tester.widget<RotationTransition>(find.descendant(of: find.byType(SyncStatusChipView), matching: find.byType(RotationTransition))).turns;
    expect(turns.value, isNot(0));
    expect(find.bySemanticsLabel('Sending what you did offline…'), findsOneWidget);

    await tester.pumpWidget(layoutHost(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: const SyncStatusChipView(snapshot: snap),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    final parked = tester.widget<RotationTransition>(find.descendant(of: find.byType(SyncStatusChipView), matching: find.byType(RotationTransition))).turns;
    expect(parked.value, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
