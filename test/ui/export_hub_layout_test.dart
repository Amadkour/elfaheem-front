// Export Hub screens through the layout harness: the designer page (phone → bottom sheet, wide → side panel),
// the page preview and the vote result previews, and the hub sheet itself (no organization → no API calls).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/export_hub/export_hub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('designer page: council preset with a selected block, both languages, every size', (tester) async {
    for (final module in const ['council', 'items']) {
      await expectNoLayoutErrors(
        tester,
        () {
          final d = ExportDesign.standard(module, 'ar');
          return ExportDesignerPage(design: d, dataset: exportSampleDataset(module, 'ar'), module: module, lang: 'ar', name: 'x', onSave: (_, _) async => true);
        },
        scaffold: false,
        act: (tester) async {
          // a phone first says the studio works best on a larger screen: continue anyway
          for (final label in const ['المتابعة على أي حال', 'Continue anyway']) {
            final go = find.text(label);
            if (go.evaluate().isNotEmpty) await tester.tap(go.first, warnIfMissed: false);
          }
          await tester.pump(const Duration(milliseconds: 100));
          // select the title block, then open the settings sheet on a phone / use the side panel on a wide window
          final title = find.textContaining(module == 'council' ? 'جلسة' : 'تقرير');
          if (title.evaluate().isNotEmpty) await tester.tap(title.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 100));
          final page = find.text('الصفحة');
          if (page.evaluate().isNotEmpty) await tester.tap(page.first, warnIfMissed: false);
          final en = find.text('Page');
          if (en.evaluate().isNotEmpty) await tester.tap(en.first, warnIfMissed: false);
        },
      );
    }
  });

  testWidgets('page preview (read-only) at a small width and the vote result previews', (tester) async {
    final item = exportSampleItems('ar').first;
    for (final pos in exportVotePositions) {
      for (final style in exportVoteStyles) {
        await expectNoLayoutErrors(tester, () {
          final d = ExportDesign.standard('council', 'en')
            ..votes.position = pos
            ..votes.style = style
            ..votes.showVoters = true;
          return SingleChildScrollView(
            child: Column(children: [
              ExportPagePreview(design: d, dataset: exportSampleDataset('council', 'en'), maxWidth: 220),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: VoteResultPreview(votes: d.votes, result: item.votes!, lang: 'ar', fontSize: 12)),
                  const SizedBox(width: 8),
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 100), child: VoteResultPreview(votes: d.votes, result: item.votes!, lang: 'en', fontSize: 12, beside: true)),
                ]),
              ),
            ]),
          );
        });
      }
    }
  });

  testWidgets('hub sheet: council dataset with content switches and columns; a plain table; no rights', (tester) async {
    await expectNoLayoutErrors(tester, () => ExportHubSheet(dataset: exportSampleDataset('council', 'ar')));
    await expectNoLayoutErrors(tester, () => ExportHubSheet(dataset: exportSampleDataset('items', 'en'), canVotes: false, canDecisions: false));
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (context) => Center(child: TextButton(onPressed: () => exportHub(context, exportSampleDataset('council', 'en')), child: const Text('open')))),
      act: (tester) async {
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(milliseconds: 300));
        // "both" shows two template rows and the preview language chips
        final both = find.textContaining('(');
        if (both.evaluate().isNotEmpty) await tester.tap(both.first, warnIfMissed: false);
      },
    );
  });
}
