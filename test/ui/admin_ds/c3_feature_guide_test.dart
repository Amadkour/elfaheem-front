// C-round: the Feature guide shows the App switch state READ-ONLY (a badge) with a "Change in Features" button; the
// Assistant chip is still the guide's own toggle.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_feature_guide.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

GuideFeature _f(String key, {String state = 'shown'}) => GuideFeature({
      'key': key,
      'group': 'g',
      'roles': ['student'],
      'title_ar': 'ميزة $key',
      'title_en': 'Feature $key',
      'summary_ar': 'وصف',
      'summary_en': 'Summary',
      'app_state': state,
      'rag_enabled': true,
      'in_assistant': state != 'hidden',
      'hidden_on': state == 'partial' ? ['ios'] : [],
    });

void main() {
  setUp(() => AppConfig.lang = 'en');

  Widget tiles({VoidCallback? onOpen}) => ListView(children: [
        GuideFeatureTile(feature: _f('a'), roleNames: const {'student': 'Student'}, onOpenFeatures: onOpen, onRag: (_) {}),
        GuideFeatureTile(feature: _f('b', state: 'hidden'), roleNames: const {'student': 'Student'}, onOpenFeatures: onOpen),
        GuideFeatureTile(feature: _f('c', state: 'none'), roleNames: const {'student': 'Student'}, onOpenFeatures: onOpen),
      ]);

  testWidgets('no App toggle: a read-only badge and the Change in Features button', (tester) async {
    var opened = 0;
    await tester.pumpWidget(layoutHost(tiles(onOpen: () => opened++), scale: 1));
    expect(find.text('App: On'), findsOneWidget);
    expect(find.text('App: Hidden'), findsOneWidget);
    // a feature with no app switch has neither badge nor button
    expect(find.byKey(const ValueKey('guide.change_in_features')), findsNWidgets(2));
    expect(find.widgetWithText(AppChoiceChip, 'App'), findsNothing);
    expect(find.widgetWithText(AppChoiceChip, 'Assistant'), findsNWidgets(3), reason: 'the guide keeps its own Assistant toggle');
    await tester.tap(find.byKey(const ValueKey('guide.change_in_features')).first);
    expect(opened, 1);
  });

  testWidgets('layout', (tester) async {
    await expectNoLayoutErrors(tester, () => tiles(onOpen: () {}));
  });
}
