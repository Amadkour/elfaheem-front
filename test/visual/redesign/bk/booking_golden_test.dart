// Review renders of the booking flow (BookFlow, SCREEN_MAP "Booking" rows 1-18) and the subject page's BK parts
// (SubjectProfile rows 1-2, 11-16, 19-22), with CAST.md data, to compare by eye with
// D:/platform/redesign-ref/ref/booking/ and ref/subject/. Not a CI suite.
//
//   flutter test test/visual/redesign/bk --update-goldens [--plain-name book]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/booking/booking_flow_controller.dart';
import 'package:flutter_education_app/features/booking/booking_flow_page.dart';
import 'package:flutter_education_app/features/booking/booking_sign_in_sheet.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppArea, AppAreaScope;
import 'package:flutter_test/flutter_test.dart';

import '../../../support/redesign/bk_fakes.dart';
import '../kit_golden_harness.dart';

Widget _page(BkFlowController Function() c) => BookFlowPage(controller: c(), autoload: false);

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());
  setUp(bkUseRiyadh);

  Future<void> render(WidgetTester t, String name, Widget Function() build, {bool en = false, bool grow = true}) =>
      kitRender(t, name, build, storage: storage, modes: const [false], langs: en ? const ['ar', 'en'] : const ['ar'], grow: grow);

  testWidgets('book 1 how, remote', (t) => render(t, 'bk_1_remote', () => _page(() => demoBkController()), en: true));
  testWidgets('book 1 how, in person', (t) => render(t, 'bk_1_inperson', () => _page(() => demoBkController(inPerson: true))));
  testWidgets('book 2 kind', (t) => render(t, 'bk_2_kind', () => _page(() => demoBkController(step: 2)), en: true));
  testWidgets('book 3 groups', (t) => render(t, 'bk_3_groups', () => _page(() => demoBkController(step: 3)), en: true));
  testWidgets('book 3 one group', (t) => render(t, 'bk_3_one', () => _page(() => demoBkController(step: 3, single: true))));
  testWidgets('book 3 slots', (t) => render(t, 'bk_3_slots', () => _page(() => demoBkController(step: 3, kind: 'individual'))));
  testWidgets('book 3 propose', (t) =>
      render(t, 'bk_3_propose', () => _page(() => demoBkController(step: 3, kind: 'individual', proposing: true))));
  testWidgets('book 4 review', (t) => render(t, 'bk_4_review', () => _page(() => demoBkController(step: 4)), en: true));
  testWidgets('book 4b sign in', (t) => render(
        t,
        'bk_4b_signin',
        () => AppAreaScope(area: AppArea.learn, child: Center(child: BkSignInSheet(onGoogle: () {}, onPhone: () {}))),
        grow: false,
      ));
  testWidgets('book 5 done', (t) => render(t, 'bk_5_done', () => _page(() => demoBkController(step: 5)), en: true));

  testWidgets('subject before subscribing', (t) => render(t, 'bk_subj_guest', () => demoGuestSpace(), en: true));
  testWidgets('subject assistant', (t) => render(t, 'bk_subj_bot', () => demoBotPanel(), grow: false));
  testWidgets('subject assistant locked', (t) => render(t, 'bk_subj_bot_off', () => demoBotPanel(on: false), grow: false));
  testWidgets('subject schedule', (t) => render(t, 'bk_subj_cal', () => demoSchedulePanel(), en: true, grow: false));
}
