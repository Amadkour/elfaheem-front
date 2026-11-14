// Layout of the organization command palette (org_command_palette.dart): the panel empty, with recent items, with
// page + department + people hits, with nothing found; and the real entry point opening the dialog (wide) / the sheet
// (phone) — 320x640 and 1400x900, ar / en, text scale 1.3, no overflow.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_keyboard.dart' show AppCommandPaletteScope;
import 'package:flutter_education_app/features/org/org_command_palette.dart';
import 'package:flutter_education_app/features/org/org_command_palette_logic.dart';
import 'package:flutter_education_app/features/org/org_page_header.dart' show OrgPageHeader;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';
import 'org_insights_samples.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  OrgPaletteController controller({List<OrgPaletteRecent> recents = const [], OrgSearchResult hits = sampleSearch}) =>
      OrgPaletteController(pages: samplePalettePages(AppConfig.lang == 'ar'), search: (q) async => hits, recents: recents);

  testWidgets('empty, then recent items', (tester) async {
    await expectNoLayoutErrors(tester, () => OrgCommandPalettePanel(controller: controller(), onSelect: (_) {}, autofocus: false));
    await expectNoLayoutErrors(
      tester,
      () => OrgCommandPalettePanel(controller: controller(recents: samplePaletteRecents), onSelect: (_) {}, wide: true, autofocus: false),
    );
  });

  testWidgets('pages + departments + people, and nothing found', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => OrgCommandPalettePanel(controller: controller(), onSelect: (_) {}, wide: true, onClose: () {}),
      act: (tester) async {
        await tester.enterText(find.byType(TextField), AppConfig.lang == 'ar' ? 'ال' : 'com');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => OrgCommandPalettePanel(controller: controller(hits: OrgSearchResult.empty), onSelect: (_) {}),
      act: (tester) async {
        await tester.enterText(find.byType(TextField), 'zzqx');
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  });

  testWidgets('the dialog (wide) / the sheet (phone)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showOrgCommandPalette(context,
                orgId: 1, pages: samplePalettePages(AppConfig.lang == 'ar'), search: (q) async => sampleSearch),
            child: const Text('open'),
          ),
        ),
      ),
      act: (tester) async {
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(find.byType(TextField), 'co');
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  });

  testWidgets('the page header with Search: a chip on wide, a full-width bar on phones', (tester) async {
    var opened = 0;
    await expectNoLayoutErrors(
      tester,
      () => AppCommandPaletteScope(
        onOpen: () => opened++,
        child: const SingleChildScrollView(child: OrgPageHeader(title: 'Home', subtitle: 'Org admin', searchBar: true)),
      ),
      act: (tester) async {
        await tester.tap(find.byKey(const ValueKey('org.header.search')));
      },
    );
    expect(opened, 4); // every size × language
  });
}
