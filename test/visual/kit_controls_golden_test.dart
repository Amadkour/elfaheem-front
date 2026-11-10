// VISUAL review renders of the kit's controls (Warm Editorial, system.md §4, lib/design/app_buttons.dart,
// app_inputs.dart, app_switch.dart, app_search_field.dart, app_number_field.dart, the pickers in app_kit.dart, and
// the older PrimaryButton / MyTextField): every button variant, size and state (rest, hover, keyboard focus, busy,
// disabled), every field state (rest, focused, filled, error, disabled), the pickers, switches and the raw
// Material buttons the theme styles — at 390x844 and 1440x900, ar / en, light / dark, into
// test/visual/goldens/kit_controls_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/kit_controls_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery();

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  bool _on = true;
  final _focusField = FocusNode();

  @override
  void dispose() {
    _focusField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: AppSpace.sectionHead, child: Text(title, style: AppType.section(context))),
            child,
          ]),
        );
    final buttons = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final size in AppButtonSize.values) ...[
        Text(size.name, style: AppType.meta(context)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppButton.primary(label: _tr('حفظ', 'Save'), icon: Icons.check_rounded, size: size, onPressed: () {}),
          AppButton.secondary(label: _tr('معاينة', 'Preview'), size: size, onPressed: () {}),
          AppButton.tonal(label: _tr('تصدير', 'Export'), icon: Icons.ios_share_rounded, size: size, onPressed: () {}),
          AppButton.ghost(label: _tr('إلغاء', 'Cancel'), size: size, onPressed: () {}),
          AppButton.danger(label: _tr('حذف', 'Delete'), icon: Icons.delete_outline_rounded, size: size, onPressed: () {}),
          AppButton.danger(label: _tr('إيقاف', 'Suspend'), dangerOutline: true, size: size, onPressed: () {}),
        ]),
        const SizedBox(height: AppSpace.md),
      ],
      Text(_tr('الحالات', 'States'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AppButton.primary(label: _tr('جارٍ الحفظ', 'Saving'), busy: true, onPressed: () {}),
        AppButton.secondary(label: _tr('جارٍ', 'Busy'), busy: true, onPressed: () {}),
        AppButton.primary(label: _tr('معطّل', 'Disabled'), onPressed: null),
        AppButton.secondary(label: _tr('معطّل', 'Disabled'), onPressed: null),
        AppButton.tonal(label: _tr('معطّل', 'Disabled'), onPressed: null),
        AppButton.danger(label: _tr('معطّل', 'Disabled'), onPressed: null),
        AppButton.primary(key: const Key('focused-button'), label: _tr('مُركَّز', 'Focused'), onPressed: () {}),
        AppIconButton(icon: Icons.notifications_rounded, tooltip: 'bell', badge: 12, onPressed: () {}),
        AppIconButton(icon: Icons.edit_rounded, tooltip: 'edit', variant: AppIconButtonVariant.tonal, onPressed: () {}),
        AppIconButton(icon: Icons.add_rounded, tooltip: 'add', variant: AppIconButtonVariant.filled, onPressed: () {}),
        const AppIconButton(icon: Icons.edit_rounded, tooltip: 'off', onPressed: null),
      ]),
      const SizedBox(height: AppSpace.md),
      AppButtonRow(
        primary: AppButton.primary(label: _tr('إرسال', 'Send'), onPressed: () {}),
        secondary: [AppButton.secondary(label: _tr('حفظ كمسودة', 'Save draft'), onPressed: () {}), AppButton.ghost(label: _tr('إلغاء', 'Cancel'), onPressed: () {})],
      ),
      const SizedBox(height: AppSpace.md),
      Text(_tr('أزرار Material من الثيم', 'Material buttons from the theme'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
        FilledButton(onPressed: () {}, child: Text(_tr('حفظ', 'Save'))),
        FilledButton.tonal(onPressed: () {}, child: Text(_tr('تصدير', 'Export'))),
        FilledButton.tonalIcon(onPressed: () {}, icon: const Icon(Icons.ios_share_rounded), label: Text(_tr('مشاركة', 'Share'))),
        OutlinedButton(onPressed: () {}, child: Text(_tr('معاينة', 'Preview'))),
        TextButton(onPressed: () {}, child: Text(_tr('إلغاء', 'Cancel'))),
      ]),
      const SizedBox(height: AppSpace.md),
      Text(_tr('الزر القديم', 'The older PrimaryButton'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      PrimaryButton(isLoading: false, label: _tr('تسجيل الدخول', 'Sign in'), onPressed: () {}),
      const SizedBox(height: AppSpace.xs),
      PrimaryButton(isLoading: true, label: _tr('تسجيل الدخول', 'Sign in'), onPressed: () {}),
      const SizedBox(height: AppSpace.xs),
      PrimaryButton(isLoading: false, label: _tr('معطّل', 'Disabled'), onPressed: null),
    ]);
    final fields = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(controller: TextEditingController(), label: _tr('الاسم الكامل', 'Full name'), hint: _tr('كما في البطاقة', 'As on your ID'), icon: Icons.person_rounded, required: true),
      AppField(controller: TextEditingController(text: _tr('سارة أحمد', 'Sara Ahmed')), label: _tr('مُركَّز', 'Focused'), focusNode: _focusField, icon: Icons.person_rounded),
      AppField(controller: TextEditingController(text: 'sara@exa'), label: _tr('بخطأ', 'With an error'), errorText: _tr('اكتب بريداً صحيحاً مثل name@example.com', 'Enter a valid e-mail like name@example.com'), icon: Icons.alternate_email_rounded),
      AppField(controller: TextEditingController(text: _tr('ملاحظة من سطرين تشرح شيئاً للمعلم.', 'A two-line note that explains something to the teacher.')), label: _tr('ملاحظة', 'Note'), maxLines: 3, helper: _tr('تظهر للمعلم فقط', 'Only the teacher sees this')),
      AppField(controller: TextEditingController(), label: _tr('معطّل', 'Disabled'), enabled: false, hint: _tr('غير متاح', 'Not available')),
      AppEmailField(controller: TextEditingController(text: 'sara@example.test')),
      AppPasswordField(controller: TextEditingController(text: 'Abc1'), showStrength: true),
      AppNumberField(controller: TextEditingController(text: '12'), label: _tr('المقاعد', 'Seats'), min: 1, max: 12, helper: _tr('حتى 12', 'Up to 12')),
      AppSearchField(onChanged: (_) {}),
      const SizedBox(height: AppSpace.sm),
      AppSearchField(onChanged: (_) {}, controller: TextEditingController(text: _tr('رياضيات', 'Maths'))),
      const SizedBox(height: AppSpace.sm),
      AppDropdown<int>(
        decoration: InputDecoration(labelText: _tr('الصف', 'Grade')),
        items: [for (var i = 1; i <= 6; i++) DropdownMenuItem(value: i, child: Text(_tr('الصف $i', 'Grade $i')))],
        value: 3,
        onChanged: (_) {},
      ),
      const SizedBox(height: AppSpace.sm),
      AppPicker<String>(
        label: _tr('المجموعة', 'Group'),
        value: null,
        options: {'a': _tr('ألف', 'Alpha'), 'b': _tr('باء', 'Beta')},
        onChanged: (_) {},
        icon: Icons.folder_rounded,
        hint: _tr('اختر مجموعة', 'Choose a group'),
      ),
      MyTextField(controller: TextEditingController(), label: _tr('حقل قديم (العنوان كعنصر نائب)', 'An older field (its label is the placeholder)')),
      const SizedBox(height: AppSpace.md),
      AppSwitchTile(title: _tr('إشعارات الدروس', 'Lesson reminders'), subtitle: _tr('قبل البث بعشر دقائق', 'Ten minutes before a live session'), icon: Icons.notifications_active_rounded, value: _on, onChanged: (v) => setState(() => _on = v)),
      AppSwitchTile(title: _tr('الوضع الهادئ', 'Quiet mode'), value: !_on, onChanged: (v) => setState(() => _on = !v)),
      const AppSwitchTile(title: 'Disabled', subtitle: 'Managed by the organization', value: true, onChanged: null),
      Row(children: [
        AppSwitch(value: true, onChanged: (_) {}),
        AppSwitch(value: false, onChanged: (_) {}),
        AppSwitch(value: false, onChanged: (_) {}, inactiveColor: c.danger),
      ]),
    ]);
    final wide = MediaQuery.sizeOf(context).width > 900;
    return ListView(padding: EdgeInsets.fromLTRB(g, AppSpace.md, g, AppSpace.xl), children: [
      Text(_tr('عناصر التحكم', 'Controls'), style: AppType.pageTitle(context)),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: section(_tr('الأزرار', 'Buttons'), buttons)),
          AppSpace.gapXl,
          Expanded(child: section(_tr('الحقول', 'Fields'), fields)),
        ])
      else ...[
        section(_tr('الأزرار', 'Buttons'), buttons),
        section(_tr('الحقول', 'Fields'), fields),
      ],
    ]);
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('kit controls gallery', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    try {
      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        for (final lang in const ['ar', 'en']) {
          for (final dark in const [false, true]) {
            AppConfig.lang = lang;
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(_host(const _Gallery(), dark: dark));
            await _frames(tester);
            // keyboard focus on the "Focused" field (light) or the "Focused" button (dark) so the ring shows
            if (dark) {
              final inner = find.descendant(of: find.byKey(const Key('focused-button')), matching: find.byType(AnimatedContainer));
              Focus.of(tester.element(inner.first)).requestFocus();
            } else {
              tester.state<_GalleryState>(find.byType(_Gallery))._focusField.requestFocus();
            }
            await _frames(tester, 4);
            for (var i = 0; i < 4; i++) {
              var extra = 0.0;
              for (final e in find.byType(Scrollable).evaluate()) {
                final s = (e as StatefulElement).state as ScrollableState;
                if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                  extra = math.max(extra, s.position.maxScrollExtent);
                }
              }
              if (extra < 1) break;
              tester.view.physicalSize = Size(size.width, math.min(6000, tester.view.physicalSize.height + extra));
              await _frames(tester, 6);
            }
            final e = tester.takeException();
            expect(e, isNull, reason: '${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
            await expectLater(
              find.byKey(_shot),
              matchesGoldenFile('goldens/kit_controls_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
            );
            // the pick sheet (phones only): the Grade dropdown opened, the whole screen captured
            if (size.width < 600) {
              tester.view.physicalSize = size;
              await _frames(tester, 4);
              await tester.scrollUntilVisible(find.byType(AppDropdown<int>), 300, scrollable: find.byType(Scrollable).first);
              await _frames(tester, 2);
              await tester.tap(find.byType(AppDropdown<int>));
              await _frames(tester, 8);
              await expectLater(
                find.byType(MaterialApp),
                matchesGoldenFile('goldens/kit_controls_sheet_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
              );
              Navigator.of(tester.element(find.byType(_Gallery))).pop();
              await _frames(tester, 4);
            }
          }
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
