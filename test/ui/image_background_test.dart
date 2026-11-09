// The Background tool of the app cropper: one server call then instant local swaps, each server error leaves the
// original, kill switch / guest / allowBackground hide it, "Use original" returns the identical bytes, the
// checkerboard never reaches the file, and no overflow at 320 x 640 and 1400 x 900 in both languages.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_image_background.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/fake_api.dart';
import 'layout_harness.dart';

const _path = 'POST /api/v1/me/images/remove-background';

Uint8List _photo() => Uint8List.fromList(img.encodePng(img.Image(width: 64, height: 64)..clear(img.ColorRgba8(200, 30, 30, 255))));

/// Transparent, with an opaque blue centre.
Uint8List _cutoutPng() {
  final i = img.Image(width: 64, height: 64, numChannels: 4)..clear(img.ColorRgba8(0, 0, 0, 0));
  img.fillRect(i, x1: 20, y1: 20, x2: 44, y2: 44, color: img.ColorRgba8(20, 40, 220, 255));
  return Uint8List.fromList(img.encodePng(i));
}

Map<String, Object?> _ok({double coverage = 0.4}) => {
      'image_b64': base64Encode(_cutoutPng()),
      'width': 64,
      'height': 64,
      'coverage': coverage,
      'suggested_colors': ['#112233', '#445566'],
    };

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

  /// Past the fake latency and the bounded wait for the decoded cut-out.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
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
    api = FakeApi({_path: (_) => _ok()})..install();
    addTearDown(api.uninstall);
  });

  testWidgets('success: the choice applies, later swaps are local, exactly one server call', (t) async {
    await open(t);
    expect(_shown(t), ImageBackdrop.original);

    await t.tap(_key('imgbg_color_FFFFFF'));
    await t.pump(const Duration(milliseconds: 50));
    expect(_key('imgbg_working'), findsOneWidget, reason: 'the working state shows while the server works');
    await settle(t);
    expect(_key('imgbg_working'), findsNothing);
    expect(_shown(t), const ImageBackdrop.color(Color(0xFFFFFFFF)));
    expect(api.calls.where((c) => c.key == _path), hasLength(1));

    // suggested colours arrived; a swap, the gradient and transparent are local
    await t.tap(_key('imgbg_color_112233'));
    await t.pump();
    expect(_shown(t), const ImageBackdrop.color(Color(0xFF112233)));
    await t.ensureVisible(_key('imgbg_mesh_2'));
    await t.pump();
    await t.tap(_key('imgbg_mesh_2'));
    await t.pump();
    expect(_shown(t).kind, ImageBackdropKind.mesh);
    await t.tap(_key('imgbg_remove'));
    await t.pump();
    expect(_shown(t), ImageBackdrop.transparent);
    expect(find.byType(ImageCheckerboard), findsWidgets);
    expect(api.calls.where((c) => c.key == _path), hasLength(1), reason: 'one call per image');

    // undo goes back to the original at once, and the cut-out is still there for the next try
    await t.tap(_key('imgbg_undo'));
    await t.pump();
    expect(_shown(t), ImageBackdrop.original);
    await t.tap(_key('imgbg_remove'));
    await t.pump();
    expect(_shown(t), ImageBackdrop.transparent);
    expect(api.calls.where((c) => c.key == _path), hasLength(1));
    await settle(t);
  });

  testWidgets('the transparent corners are not baked with the checkerboard', (t) async {
    await open(t);
    await t.tap(_key('imgbg_remove'));
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400))); // the real image decode
    await settle(t);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(_key('crop_use_photo'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pump(const Duration(milliseconds: 500));
    expect(returned, isTrue);
    final out = img.decodePng(result!)!;
    expect(out.getPixel(3, 3).a, 0, reason: 'a corner of the file is transparent');
    final mid = out.getPixel(out.width ~/ 2, out.height ~/ 2);
    expect((mid.a, mid.b > 150), (255, true), reason: 'the subject is in the file');
  });

  const errors = <(int, String)>[
    (413, 'image_too_large'),
    (415, 'bad_image'),
    (422, 'no_subject'),
    (429, 'rate_limited'),
    (503, 'server_busy'),
    (503, 'bg_model_unavailable'),
  ];
  for (final (status, code) in errors) {
    testWidgets('$status $code: a notice, the original stays, the cropper still works', (t) async {
      api.routes[_path] = (_) => FakeResponse(status, {'detail': {'code': code, 'message': 'x'}});
      await open(t);
      await t.tap(_key('imgbg_remove'));
      await settle(t);
      expect(_key('imgbg_working'), findsNothing);
      expect(_shown(t), ImageBackdrop.original);
      final notice = _textIn(t);
      expect(notice.any((s) => s == 'x'), isFalse, reason: 'the bilingual text, not the raw server message: $notice');
      await t.tap(_key('crop_use_original'));
      await t.pump(const Duration(milliseconds: 400));
      expect(identical(result, photo), isTrue);
      await t.pump(const Duration(seconds: 5)); // the notice's timer
    });
  }

  testWidgets('cancel: no notice, the original stays', (t) async {
    api = FakeApi({_path: (_) => _ok()}, latency: const Duration(seconds: 3))..install();
    addTearDown(api.uninstall);
    await open(t);
    await t.tap(_key('imgbg_remove'));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(_key('imgbg_cancel'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(_key('imgbg_working'), findsNothing);
    expect(_shown(t), ImageBackdrop.original);
    await t.pump(const Duration(seconds: 4));
    expect(_shown(t), ImageBackdrop.original, reason: 'a late answer is dropped');
  });

  testWidgets('"Use original" returns the identical bytes, also after a background was chosen', (t) async {
    await open(t);
    await t.tap(_key('imgbg_color_FFFFFF'));
    await settle(t);
    await t.tap(_key('crop_use_original'));
    await t.pump(const Duration(milliseconds: 400));
    expect(identical(result, photo), isTrue);
  });

  testWidgets('hidden: the kill switch, a guest, allowBackground false', (t) async {
    final previous = List<String>.of(AppConfig.disableList);
    addTearDown(() => AppConfig.disableList = previous);

    AppConfig.disableList = [...previous, kImageBackgroundFeature];
    await open(t);
    expect(find.byType(ImageBackgroundTool), findsNothing);
    AppConfig.disableList = previous;

    await t.pumpWidget(const SizedBox());
    GuestState.instance.start();
    addTearDown(GuestState.instance.stop);
    await open(t);
    expect(find.byType(ImageBackgroundTool), findsNothing);
    GuestState.instance.stop();

    await t.pumpWidget(const SizedBox());
    await open(t, allowBackground: false);
    expect(find.byType(ImageBackgroundTool), findsNothing);
    expect(_key('crop_tabs'), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('allowTransparent false: no Remove tile, a colour still works', (t) async {
    await open(t, allowTransparent: false);
    expect(_key('imgbg_remove'), findsNothing);
    await t.tap(_key('imgbg_color_FFFFFF'));
    await settle(t);
    expect(_shown(t), const ImageBackdrop.color(Color(0xFFFFFFFF)));
  });

  testWidgets('phone: the tool lives on its tab', (t) async {
    await open(t, size: const Size(390, 844));
    expect(find.byType(ImageBackgroundTool), findsNothing);
    await t.tap(find.text('Background'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(ImageBackgroundTool), findsOneWidget);
  });

  testWidgets('no layout errors: phone and desktop, both languages, text x 1.3', (t) async {
    Widget page() => Builder(builder: (ctx) {
          return TextButton(key: const ValueKey('open'), onPressed: () => showAppImageCropper(ctx, photo), child: const Text('open'));
        });
    await expectNoLayoutErrors(t, page, act: (t) async {
      await t.tap(_key('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: 'opening');
      if (find.byType(ImageBackgroundTool).evaluate().isEmpty) await t.tap(find.text(translate('imgbg_tab_background')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(ImageBackgroundTool), findsOneWidget);
      await t.ensureVisible(_key('imgbg_color_FFFFFF'));
      await t.pump();
      await t.tap(_key('imgbg_color_FFFFFF'));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.takeException(), isNull, reason: 'while working');
      await settle(t);
      await t.ensureVisible(_key('imgbg_remove'));
      await t.pump();
      await t.tap(_key('imgbg_remove'));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull, reason: 'with suggestions');
      await t.tap(find.byIcon(Icons.rotate_90_degrees_ccw_rounded));
      await t.pump(const Duration(milliseconds: 100));
    });
  });
}

List<String> _textIn(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').toList();
