// High contrast (Display & reading, D-072): the palette's muted ink moves toward the main ink, hero ink gets more
// opaque, and the video player's dim labels brighten; switching it off restores every colour.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_player_parts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _distance(Color a, Color b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs() + (a.a - b.a).abs();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => DisplaySettings.instance.update(const DisplayPrefs()));

  test('muted ink, secondary text, dividers and hero ink get stronger, then come back', () async {
    final t = ThemeConfigProvider(api: ApiClient());
    for (final dark in [false, true]) {
      t.isDark = dark;
      final before = (t.textMedium, t.textLight, t.secondText, t.divider, t.onHeroMuted, VodInk.textSoft);

      await DisplaySettings.instance.update(const DisplayPrefs(highContrast: true));
      expect(_distance(t.textMedium, t.textDark), lessThan(_distance(before.$1, t.textDark)));
      expect(_distance(t.textLight, t.textDark), lessThan(_distance(before.$2, t.textDark)));
      expect(_distance(t.secondText, t.textDark), lessThan(_distance(before.$3, t.textDark)));
      expect(t.divider, isNot(before.$4));
      expect(t.onHeroMuted.a, greaterThan(before.$5.a));
      expect(VodInk.textSoft.a, greaterThan(before.$6.a));

      await DisplaySettings.instance.update(const DisplayPrefs());
      expect((t.textMedium, t.textLight, t.secondText, t.divider, t.onHeroMuted, VodInk.textSoft), before);
    }
  });
}
