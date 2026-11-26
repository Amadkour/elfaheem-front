// Review renders of the kit gallery's sections (KIT_SPEC §7.3: colours, buttons, cards and tiles, states, controls),
// each under the home area. Not a CI suite.
//
//   flutter test test/visual/redesign/kit_sections_golden_test.dart --update-goldens [--plain-name buttons]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/gallery/kit_gallery_sections.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_golden_harness.dart';

Widget _sections(List<int> which, {AppArea area = AppArea.home}) => AppAreaScope(
      area: area,
      child: Builder(builder: (context) {
        final all = kitGallerySections();
        return ListView(
          padding: EdgeInsets.all(AppSpace.gutter(MediaQuery.sizeOf(context).width)),
          children: [for (final i in which) all[i].build(context)],
        );
      }),
    );

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  // the gallery's section order: 0 colours, 1 type, 2 buttons, 3 cards, 4 hero, 5 chips, 6 states, 7 progress,
  // 8 live, 9 sheets, 10 motion
  testWidgets('colours', (t) => kitRender(t, 'kit_colours', () => _sections([0]), storage: storage));
  testWidgets('type', (t) => kitRender(t, 'kit_type', () => _sections([1]), storage: storage));
  testWidgets('cards and tiles', (t) => kitRender(t, 'kit_cards_tiles', () => _sections([3]), storage: storage));
  testWidgets('states', (t) => kitRender(t, 'kit_states', () => _sections([6]), storage: storage));
  testWidgets('controls', (t) => kitRender(t, 'kit_controls', () => _sections([5, 7, 8]), storage: storage));
  testWidgets('buttons', (t) async {
    for (final a in [AppArea.home, AppArea.learn, AppArea.games, AppArea.store]) {
      await kitRender(t, 'kit_buttons_${a.name}', () => _sections([2], area: a), storage: storage, modes: const [false]);
    }
    await kitRender(
        t,
        'kit_buttons_teacher',
        () => AppAreaScope.role(
            role: AppRoleAccent.teacher,
            child: Builder(
                builder: (c) => ListView(
                    padding: const EdgeInsets.all(AppSpace.md), children: [kitGallerySections()[2].build(c)]))),
        storage: storage,
        modes: const [false]);
  });
}
