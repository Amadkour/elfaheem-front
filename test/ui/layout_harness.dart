// Layout smoke harness: pumps a widget on a phone (320x640) and a wide web/tablet window (1400x900), in Arabic (RTL)
// and English, with textScaler 1.3, and fails on any exception (RenderFlex overflow included).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

const layoutSizes = <Size>[Size(320, 640), Size(1400, 900)];
const layoutLangs = <String>['ar', 'en'];

Widget layoutHost(Widget child, {double scale = 1.3, bool scaffold = true}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: scaffold ? Scaffold(body: child) : child,
    ),
  );
}

/// Pumps [build] at every size × language and expects no exception. [settle] pumps a few frames (no
/// pumpAndSettle: skeleton shimmers repeat forever).
Future<void> expectNoLayoutErrors(WidgetTester tester, Widget Function() build, {bool scaffold = true, int frames = 3}) async {
  final prevLang = AppConfig.lang;
  addTearDown(() {
    AppConfig.lang = prevLang;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  for (final size in layoutSizes) {
    for (final lang in layoutLangs) {
      AppConfig.lang = lang;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(layoutHost(build(), scaffold: scaffold));
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final e = tester.takeException();
      expect(e, isNull, reason: 'layout error at ${size.width.toInt()}x${size.height.toInt()} / $lang: $e');
    }
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}
