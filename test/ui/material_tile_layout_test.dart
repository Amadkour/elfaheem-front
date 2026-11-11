// The material card's parts (D-316): no overflow at any size, the sheet pops with the option tapped.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/session/material/components/material_tile_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _groups = [
  [
    MaterialOption(id: 'studio', icon: Icons.movie_edit, label: 'Open in Studio', hint: "Trim, cut, split, speed, merge — as a draft students don't see until you publish it"),
  ],
  [
    MaterialOption(id: 'edit', icon: Icons.tune_rounded, label: 'Edit details', hint: 'Name, description and order'),
    MaterialOption(id: 'share', icon: Icons.ios_share_rounded, label: 'Share lesson link'),
  ],
];
const _delete = MaterialOption(id: 'delete', icon: Icons.delete_outline_rounded, label: 'Delete material', danger: true);

Widget _sheet() => const MaterialOptionsSheet(
      title: 'A very long lecture title that wraps over more than one line on a small phone in both languages',
      icon: SizedBox(width: 44, height: 44, child: Icon(Icons.smart_display_rounded)),
      color: Colors.blue,
      facts: ['Video', '152.4 MB', '1:02:33'],
      groups: _groups,
      danger: _delete,
    );

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  testWidgets('the options sheet fits every size', (t) async {
    await expectNoLayoutErrors(t, _sheet);
  });

  testWidgets('the more button and the index badge fit every size', (t) async {
    await expectNoLayoutErrors(t, () => Row(mainAxisSize: MainAxisSize.min, children: [MaterialMoreButton(onTap: () {}), const MaterialIndexBadge(index: 12)]));
  });

  testWidgets('a tapped option is what the sheet pops with; the button is 48 wide and labelled', (t) async {
    String? got;
    await t.pumpWidget(layoutHost(
      scale: 1,
      Builder(
        builder: (ctx) => MaterialMoreButton(
          onTap: () async => got = await showModalBottomSheet<String>(context: ctx, isScrollControlled: true, builder: (_) => _sheet()),
        ),
      ),
    ));
    expect(t.getSize(find.byType(MaterialMoreButton)).width, 48);
    expect(find.bySemanticsLabel(MaterialMoreButton.label), findsOneWidget);
    await t.tap(find.byType(MaterialMoreButton));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('material.option.delete')));
    await t.pumpAndSettle();
    expect(got, 'delete');
  });
}
