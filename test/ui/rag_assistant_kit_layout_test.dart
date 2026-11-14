// Layout of the editorial assistant's parts and the page help (Warm Editorial theme): no overflow at 320x640 /
// 1400x900, ar / en, text scale 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/help/help_info_button.dart';
import 'package:flutter_education_app/features/help/help_models.dart';
import 'package:flutter_education_app/features/help/help_tour.dart';
import 'package:flutter_education_app/features/rag/chat/rag_chat_parts.dart';
import 'package:flutter_education_app/features/rag/rag_chat.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

final _long = 'A very long source title that keeps going past the width of a phone ' * 3;

HelpEntry _entry() => HelpEntry.fromJson({
      'page_id': 'home.student',
      'title': {'ar': 'الرئيسية', 'en': 'Home'},
      'summary': {'ar': 'نقطة البداية: الحصة الجارية وما ينتظرك.', 'en': 'Your starting point: the live session and what needs you.'},
      'sections': [
        {
          'title': {'ar': 'يحتاجك', 'en': 'Needs you'},
          'body': {'ar': 'صف من الأعداد.', 'en': 'A slim row of counts.'},
          'items': [
            {'label': {'ar': 'شارة', 'en': 'A pill'}, 'text': {'ar': 'تفتح المهمة.', 'en': 'Takes you straight to the task. ' * 4}},
            {'label': {'ar': 'زر', 'en': 'Button'}, 'text': {'ar': '', 'en': ''}},
          ],
        },
      ],
      'tour': [
        {'target': 'home.live', 'text': {'ar': 'هنا الحصة الجارية.', 'en': 'The live or next session is here.'}},
        {'target': 'home.attention', 'text': {'ar': 'ما ينتظرك.', 'en': 'What needs you, counted.'}},
      ],
    });

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('sources, prompts and the composer', (t) async {
    final citations = [
      RagCitation(1, 4, _long, 'Section', 3, 4, 'The quote of the passage. ' * 8, 'page'),
      RagCitation(2, 5, 'Terms', '', null, null, 'Short quote', 'qa'),
    ];
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: Column(children: [
          const RagAssistantMark(),
          RagSources(citations: citations),
          RagPromptList(prompts: [_long, 'How do I pay?'], onPick: (_) {}),
          RagPromptList(prompts: [_long], onPick: (_) {}, card: false),
          RagComposer(controller: TextEditingController(text: _long), onSend: () {}),
          RagComposer(controller: TextEditingController(), onSend: () {}, sending: true),
        ]),
      ),
    );
  });

  testWidgets('page help: entry, items, tour callout and progress', (t) async {
    final e = _entry();
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HelpEntryView(entry: e, onClose: () {})));
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: HelpItemList(items: [(label: _long, text: _long), (label: 'Short', text: '')])));
    await expectNoLayoutErrors(t, () => const HelpTourProgress(index: 3, count: 12));
    await expectNoLayoutErrors(t, () => HelpTourOverlay(steps: e.tour, onClose: () {}));
  });
}
