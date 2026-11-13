// The kit's controls (Warm Editorial, system.md §4): the field language (AppField, AppEmailField, AppPasswordField,
// AppUrlField, AppNumberField, AppSearchField, AppDropdown, AppPicker), the switch, and the older widgets that wear
// the same look (PrimaryButton, MyTextField, MyPasswordTextField, MySearchBar, OutlineButton, CustomButton) at
// 320 / 1400 wide, ar + en, textScaler 1.3 — plus the behaviour the brief fixes: the label sits ABOVE the well, a
// busy button keeps its width, the switch is a 48 px target and toggles from the keyboard, a dropdown opens its
// sheet and answers the pick.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/custom_button.dart';
import 'package:flutter_education_app/utils/widget/outline_button.dart';
import 'package:flutter_education_app/utils/widget/password_text_field.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_education_app/utils/widget/search_text_field.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

const _long = 'عنوان طويل جداً لحقل يمتد على أكثر من سطر عند التكبير / A very long label that wraps at text scale 1.3';

Widget _fields() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpace.md),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(controller: TextEditingController(), label: _long, hint: 'Hint', icon: Icons.person_rounded, required: true),
      AppField(controller: TextEditingController(text: 'Some typed value'), label: 'Note', maxLines: 3, helper: _long),
      AppField(controller: TextEditingController(text: 'bad'), label: 'With error', errorText: _long),
      AppField(controller: TextEditingController(), label: 'Disabled', enabled: false, hint: 'Nothing here'),
      AppEmailField(controller: TextEditingController(text: 'sara@example.test')),
      AppEmailField(controller: TextEditingController(text: 'not-an-email')),
      AppPasswordField(controller: TextEditingController(text: 'abc'), showStrength: true),
      AppUrlField(controller: TextEditingController(), required: true),
      AppNumberField(controller: TextEditingController(text: '12'), label: _long, min: 0, max: 10, helper: 'Up to ten'),
      const AppNumberField(label: 'Off', enabled: false),
      AppSearchField(onChanged: (_) {}),
      AppSearchField(onChanged: (_) {}, dense: true, controller: TextEditingController(text: 'query')),
      AppDropdown<int>(
        decoration: InputDecoration(labelText: _long, hintText: 'Pick one'),
        items: [for (var i = 0; i < 12; i++) DropdownMenuItem(value: i, child: Text('Option $i'))],
        value: 3,
        onChanged: (_) {},
      ),
      AppDropdown<int>(
        items: const [DropdownMenuItem(value: 1, child: Text('10')), DropdownMenuItem(value: 2, child: Text('25'))],
        value: 1,
        onChanged: (_) {},
      ),
      AppDropdown<int>(items: const [], value: null, onChanged: null, hint: const Text('Nothing to choose')),
      AppPicker<String>(
        label: 'Group',
        value: 'b',
        options: const {'a': 'Alpha', 'b': 'Beta'},
        onChanged: (_) {},
        icon: Icons.folder_rounded,
        allowNone: true,
      ),
      AppPicker<String>(label: _long, value: null, options: const {}, onChanged: (_) {}, enabled: false),
      AppSwitchTile(title: _long, subtitle: _long, icon: Icons.lock_open_rounded, value: true, onChanged: (_) {}),
      AppSwitchTile(title: 'Dense, off', dense: true, value: false, onChanged: (_) {}),
      const AppSwitchTile(title: 'Disabled', value: true, onChanged: null),
      Row(children: [
        AppSwitch(value: true, onChanged: (_) {}),
        AppSwitch(value: false, onChanged: (_) {}),
        const AppSwitch(value: false, onChanged: null),
      ]),
    ]),
  );
}

Widget _legacy() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpace.md),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PrimaryButton(isLoading: false, label: _long, icon: Icons.send, onPressed: () {}),
      const SizedBox(height: AppSpace.xs),
      PrimaryButton(isLoading: true, label: 'Saving', onPressed: () {}),
      const SizedBox(height: AppSpace.xs),
      const PrimaryButton(isLoading: false, label: 'Disabled', onPressed: null),
      const SizedBox(height: AppSpace.xs),
      Row(children: [PrimaryButton(isLoading: false, label: 'In a row', onPressed: () {}, iconBefore: true, icon: Icons.check)]),
      const SizedBox(height: AppSpace.xs),
      MyTextField(controller: TextEditingController(), label: _long),
      const SizedBox(height: AppSpace.xs),
      MyTextField(controller: TextEditingController(text: 'typed'), label: 'Name', maxLine: 3, enable: false),
      const SizedBox(height: AppSpace.xs),
      MyPasswordTextField(controller: TextEditingController(), label: 'Password', obscurePassword: true, onPressed: () {}),
      MySearchBar(controller: TextEditingController(), hint: 'search'),
      Row(children: [
        OutlineButton(label: _long, color: Colors.red, icon: Icons.delete, onPressed: () {}),
        const SizedBox(width: AppSpace.xs),
        OutlineButton(label: 'Short', color: Colors.green, icon: Icons.check, onPressed: () {}),
      ]),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, children: [
        CustomButton(text: _long, onPressed: () {}, icon: Icons.add),
        const CustomButton(text: 'Loading', isLoading: true),
      ]),
    ]),
  );
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('every field, picker and switch lays out', (tester) async {
    await expectNoLayoutErrors(tester, _fields);
  });

  testWidgets('the older button and fields lay out', (tester) async {
    await expectNoLayoutErrors(tester, _legacy);
  });

  testWidgets('a field draws its label above the well, the error under it', (tester) async {
    await tester.pumpWidget(layoutHost(Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: AppField(controller: TextEditingController(), label: 'E-mail', errorText: 'Required'),
    )));
    final label = tester.getTopLeft(find.text('E-mail'));
    final well = tester.getTopLeft(find.byType(TextField));
    final error = tester.getTopLeft(find.text('Required'));
    expect(label.dy, lessThan(well.dy));
    expect(error.dy, greaterThan(tester.getBottomLeft(find.byType(EditableText)).dy));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a busy button keeps its width', (tester) async {
    await tester.pumpWidget(layoutHost(Center(child: AppButton.primary(label: 'Save changes', onPressed: () {}))));
    final idle = tester.getSize(find.byType(AppButton)).width;
    await tester.pumpWidget(layoutHost(Center(child: AppButton.primary(label: 'Save changes', busy: true, onPressed: () {}))));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.getSize(find.byType(AppButton)).width, idle);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  // D-649 replaced D-612's solid fill: the primary button is the brand gradient on a soft tinted shadow; the accent
  // (gold) variant too, with a dark ink; a disabled primary is still the flat neutral well
  testWidgets('the primary button is the brand gradient on a soft shadow; disabled it is a flat well', (tester) async {
    await tester.pumpWidget(layoutHost(Center(child: AppButton.primary(label: 'Save', onPressed: () {}))));
    final boxes = tester.widgetList<AnimatedContainer>(find.descendant(of: find.byType(AppButton), matching: find.byType(AnimatedContainer)));
    // D-650 r3: the brand fill is an AppBrandFill (primary held past the label, then the cream end)
    final deco = boxes.first.decoration as AppBrandFill;
    expect(deco.colors, isNotEmpty);
    expect(deco.boxShadow, isNotEmpty);
    await tester.pumpWidget(layoutHost(const Center(child: AppButton.primary(label: 'Save', onPressed: null))));
    final off = tester.widgetList<AnimatedContainer>(find.descendant(of: find.byType(AppButton), matching: find.byType(AnimatedContainer))).first.decoration as BoxDecoration;
    expect(off.gradient, isNull);
    expect(off.boxShadow, isNull);
    await tester.pumpWidget(layoutHost(Center(child: AppButton.accent(label: 'Go live', onPressed: () {}))));
    final gold = tester.widgetList<AnimatedContainer>(find.descendant(of: find.byType(AppButton), matching: find.byType(AnimatedContainer))).first.decoration as BoxDecoration;
    expect(gold.gradient, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AppSwitch is a 48 px target, toggles on tap and on Space with keyboard focus', (tester) async {
    var value = false;
    await tester.pumpWidget(layoutHost(StatefulBuilder(builder: (context, set) {
      return Center(child: AppSwitch(value: value, onChanged: (v) => set(() => value = v), semanticLabel: 'Dark mode'));
    })));
    final size = tester.getSize(find.byType(AppSwitch));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    await tester.tap(find.byType(AppSwitch));
    await tester.pump(const Duration(milliseconds: 300));
    expect(value, isTrue);
    // Tab lands on the switch (the only traversable thing), Space toggles it
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 300));
    expect(value, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AppSwitchTile is one Tab stop: the switch inside does not take focus', (tester) async {
    await tester.pumpWidget(layoutHost(AppSwitchTile(title: 'Allow', value: true, onChanged: (_) {})));
    expect(find.byType(FocusableActionDetector), findsNothing);
    expect(tester.getSize(find.byType(AppSwitchTile)).height, greaterThanOrEqualTo(48));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AppDropdown opens its sheet and answers the pick; AppPicker too', (tester) async {
    int? picked;
    await tester.pumpWidget(layoutHost(Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: AppDropdown<int>(
        decoration: const InputDecoration(labelText: 'Size'),
        items: const [DropdownMenuItem(value: 1, child: Text('Small')), DropdownMenuItem(value: 2, child: Text('Large'))],
        value: 1,
        onChanged: (v) => picked = v,
      ),
    )));
    expect(find.text('Size'), findsOneWidget); // the label above the well
    await tester.tap(find.byType(AppDropdown<int>));
    await tester.pumpAndSettle();
    expect(find.text('Large'), findsOneWidget);
    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();
    expect(picked, 2);
    expect(find.text('Large'), findsOneWidget); // now the well shows it

    String? group;
    await tester.pumpWidget(layoutHost(Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: AppPicker<String>(
        label: 'Group',
        value: null,
        options: const {'a': 'Alpha', 'b': 'Beta'},
        allowNone: true,
        onChanged: (v) => group = v,
      ),
    )));
    await tester.tap(find.byType(AppPicker<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(group, 'b');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AppSearchField debounces, clears at once and on Esc', (tester) async {
    final seen = <String>[];
    await tester.pumpWidget(layoutHost(AppSearchField(onChanged: seen.add, debounce: const Duration(milliseconds: 50))));
    await tester.enterText(find.byType(TextField), 'ab');
    expect(seen, isEmpty);
    await tester.pump(const Duration(milliseconds: 80));
    expect(seen, ['ab']);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(seen, ['ab', '']);
    await tester.enterText(find.byType(TextField), 'c');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 250));
    expect(seen.last, '');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a disabled filled button is a neutral well, a disabled ghost fades', (tester) async {
    await tester.pumpWidget(layoutHost(const Row(children: [
      AppButton.primary(label: 'Off', onPressed: null),
      AppButton.ghost(label: 'Off', onPressed: null),
    ])));
    final opacities = tester.widgetList<Opacity>(find.descendant(of: find.byType(AppButton), matching: find.byType(Opacity))).toList();
    expect(opacities.first.opacity, 1);
    expect(opacities.last.opacity, 0.45);
    await tester.pumpWidget(const SizedBox());
  });
}
