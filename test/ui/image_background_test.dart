// The Background tool of the app cropper (no server, D-510): the Background tab reads the picture and removes what
// the border says, every choice is local, kill switch / allowBackground hide it, "Use original" returns the identical
// bytes, the checkerboard never reaches the file, and no overflow at 320 x 640 and 1400 x 900 in both languages.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_image_background.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/fake_api.dart';
import 'layout_harness.dart';

/// A blue square on a plain red background.
Uint8List _photo() {
  final i = img.Image(width: 120, height: 120)..clear(img.ColorRgba8(200, 30, 30, 255));
  img.fillRect(i, x1: 40, y1: 40, x2: 80, y2: 80, color: img.ColorRgba8(20, 40, 220, 255));
  return Uint8List.fromList(img.encodePng(i));
}

Finder _key(String k) => find.byKey(ValueKey(k));

ImageBackdrop _shown(WidgetTester t) => t.widget<ImageBackdropFill>(find.byType(ImageBackdropFill)).backdrop;

void main() {
  late FakeApi api;
  late Uint8List photo;
  Uint8List? result;
  var returned = false;

  Widget host({bool allowBackground = true, bool allowTransparent = true}) => ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey('open'),
                  onPressed: () async {
                    result = await showAppImageCropper(ctx, photo, allowBackground: allowBackground, allowTransparent: allowTransparent);
                    returned = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester t, {bool allowBackground = true, bool allowTransparent = true, Size size = const Size(1400, 900)}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(host(allowBackground: allowBackground, allowTransparent: allowTransparent));
    await t.tap(_key('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  /// The real decode and the isolates need real time.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 600; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 40));
      final tool = find.byType(ImageBackgroundTool);
      if (i >= 2 && (tool.evaluate().isEmpty || !t.widget<ImageBackgroundTool>(tool).session.working)) break;
    }
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> openBackgroundTab(WidgetTester t) async {
    await t.tap(find.text(translate('imgbg_tab_background')));
    await t.pump();
    await settle(t);
  }

  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  tearDownAll(() => translation = {});

  setUp(() {
    mockRequestPlugins();
    photo = _photo();
    result = null;
    returned = false;
    AppConfig.lang = 'en';
    api = FakeApi({})..install();
    addTearDown(api.uninstall);
  });

  testWidgets('the Background tab removes the border colour; choices are local; no server call', (t) async {
    await open(t);
    expect(_shown(t), ImageBackdrop.original);
    await openBackgroundTab(t);
    expect(_shown(t), ImageBackdrop.transparent, reason: 'shown right away');
    expect(find.byType(ImageCheckerboard), findsWidgets);

    await t.tap(_key('imgbg_color_FFFFFF'));
    await t.pump();
    expect(_shown(t), const ImageBackdrop.color(Color(0xFFFFFFFF)));
    await t.ensureVisible(_key('imgbg_mesh_2'));
    await t.pump();
    await t.tap(_key('imgbg_mesh_2'));
    await t.pump();
    expect(_shown(t).kind, ImageBackdropKind.mesh);
    await t.ensureVisible(_key('imgbg_original'));
    await t.pump();
    await t.tap(_key('imgbg_original'));
    await t.pump();
    expect(_shown(t), ImageBackdrop.original);
    expect(api.calls, isEmpty, reason: 'nothing leaves the device');
  });

  testWidgets('the transparent corners are not baked with the checkerboard, the subject is in the file', (t) async {
    await open(t);
    await openBackgroundTab(t);
    await t.tap(_key('crop_use_photo'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
    await t.pump(const Duration(milliseconds: 500));
    expect(returned, isTrue);
    final out = img.decodePng(result!)!;
    expect(out.getPixel(3, 3).a, 0, reason: 'a corner of the file is transparent');
    final mid = out.getPixel(out.width ~/ 2, out.height ~/ 2);
    expect(mid.a, 255, reason: 'the subject is in the file');
    expect(mid.b > 150, isTrue);
  });

  testWidgets('a tap on the picture removes that colour, undo brings it back', (t) async {
    await open(t);
    await openBackgroundTab(t);
    final tool = t.widget<ImageBackgroundTool>(find.byType(ImageBackgroundTool));
    expect(tool.session.ready, isTrue);
    final centre = t.getCenter(_key('crop_frame'));
    await t.tapAt(centre);
    await settle(t);
    expect(tool.session.canUndo, isTrue);
    expect(tool.session.coverage, lessThan(0.05), reason: 'the blue square is removed');
    await t.tap(_key('imgbg_undo'));
    await settle(t);
    expect(tool.session.canUndo, isFalse);
    expect(tool.session.coverage, greaterThan(0.05));
    expect(api.calls, isEmpty);
  });

  testWidgets('a picture that cannot be read: a notice, the cropper still works', (t) async {
    photo = Uint8List.fromList(List.filled(40, 7));
    await open(t);
    await openBackgroundTab(t);
    expect(_key('imgbg_working'), findsNothing);
    expect(_shown(t), ImageBackdrop.original);
    await t.tap(_key('crop_use_original'));
    await t.pump(const Duration(milliseconds: 400));
    expect(identical(result, photo), isTrue);
    await t.pump(const Duration(seconds: 5)); // the notice's timer
  });

  testWidgets('"Use original" returns the identical bytes, also after a background was chosen', (t) async {
    await open(t);
    await openBackgroundTab(t);
    await t.tap(_key('crop_use_original'));
    await t.pump(const Duration(milliseconds: 400));
    expect(identical(result, photo), isTrue);
  });

  testWidgets('hidden: the kill switch, allowBackground false', (t) async {
    final previous = List<String>.of(AppConfig.disableList);
    addTearDown(() => AppConfig.disableList = previous);

    AppConfig.disableList = [...previous, kImageBackgroundFeature];
    await open(t);
    expect(find.byType(ImageBackgroundTool), findsNothing);
    expect(_key('crop_tabs'), findsNothing);
    AppConfig.disableList = previous;

    await t.pumpWidget(const SizedBox());
    await open(t, allowBackground: false);
    expect(find.byType(ImageBackgroundTool), findsNothing);
    expect(_key('crop_tabs'), findsNothing);
  });

  testWidgets('allowTransparent false: no Transparent tile, the first look is on white', (t) async {
    await open(t, allowTransparent: false);
    await openBackgroundTab(t);
    expect(_key('imgbg_remove'), findsNothing);
    expect(_shown(t), const ImageBackdrop.color(Color(0xFFFFFFFF)));
  });

  testWidgets('the tool lives on its tab on a phone and on a wide screen', (t) async {
    await open(t, size: const Size(390, 844));
    expect(find.byType(ImageBackgroundTool), findsNothing);
    await openBackgroundTab(t);
    expect(find.byType(ImageBackgroundTool), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await open(t);
    expect(find.byType(ImageBackgroundTool), findsNothing);
    await openBackgroundTab(t);
    expect(find.byType(ImageBackgroundTool), findsOneWidget);
  });

  testWidgets('the panel in every state: no layout errors, phone and desktop, both languages, text x 1.3', (t) async {
    Widget panel(ImageBackgroundSession s) => Material(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (ctx, box) => ImageBackgroundTool(
                session: s,
                original: photo,
                selected: ImageBackdrop.transparent,
                allowTransparent: true,
                wide: box.maxWidth >= 840,
                customColor: null,
                onPick: (_) {},
                onCustom: () {},
                onToolUsed: () {},
              ),
            ),
          ),
        );
    final session = ImageBackgroundSession.preview(coverage: 0.4, suggested: const [Color(0xFF112233), Color(0xFF445566)]);
    addTearDown(session.dispose);
    await expectNoLayoutErrors(t, () => panel(session));
    session.setBrush(ImageBackgroundBrush.restore);
    await expectNoLayoutErrors(t, () => panel(session));
    final busy = ImageBackgroundSession.preview(busyBackground: true);
    addTearDown(busy.dispose);
    await expectNoLayoutErrors(t, () => panel(busy));
  });

  testWidgets('the cropper itself: no layout errors while working and with a result', (t) async {
    Widget page() => Builder(builder: (ctx) {
          return TextButton(key: const ValueKey('open'), onPressed: () => showAppImageCropper(ctx, photo), child: const Text('open'));
        });
    await expectNoLayoutErrors(t, page, act: (t) async {
      await t.tap(_key('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: 'opening');
      await openBackgroundTab(t);
      expect(find.byType(ImageBackgroundTool), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'with a result');
      await t.tap(find.byIcon(Icons.rotate_90_degrees_ccw_rounded));
      await t.pump(const Duration(milliseconds: 100));
    });
  });
}
