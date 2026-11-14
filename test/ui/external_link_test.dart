// openExternalLink (lib/core/share/external_link.dart, security S5): which links go out, which open in the app,
// which are refused.
import 'package:flutter_education_app/core/share/external_link.dart';
import 'package:flutter_test/flutter_test.dart';

bool _out(String raw, {bool mail = false, bool tel = false, bool release = true}) =>
    checkExternalLink(raw, allowMail: mail, allowTel: tel, release: release) is ExternalLinkOut;

bool _refused(String? raw, {bool mail = false, bool tel = false, bool release = true}) =>
    checkExternalLink(raw, allowMail: mail, allowTel: tel, release: release) is ExternalLinkRefused;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // showAppNotice looks for the navigator
  test('https goes out', () {
    expect(_out('https://example.com/a?b=1'), isTrue);
    expect(_out('  HTTPS://Example.com  '), isTrue);
    expect(_out('https://nextbrain.site/s/material/12'), isTrue); // our own links: App Links bring them back
  });

  test('javascript:, intent:, file:, data:, custom schemes and http are refused', () {
    for (final bad in [
      'javascript:alert(1)',
      'JavaScript:alert(1)',
      'intent://scan/#Intent;scheme=zxing;package=com.x;end',
      'file:///etc/passwd',
      'data:text/html,<script>alert(1)</script>',
      'sms:+201000000000',
      'tg://resolve?domain=x',
      'market://details?id=x',
      'myapp://open',
      'http://example.com',
      'https:///nohost',
      '//evil.example.com/x',
      'example.com',
      '',
      '   ',
      null,
    ]) {
      expect(_refused(bad), isTrue, reason: '$bad');
    }
  });

  test('http only to the developer machine, never in a release build', () {
    expect(_out('http://10.0.2.2:18080/media/a.pdf', release: false), isTrue);
    expect(_out('http://localhost:18080/x', release: false), isTrue);
    expect(_refused('http://10.0.2.2:18080/media/a.pdf'), isTrue);
    expect(_refused('http://example.com', release: false), isTrue);
  });

  test('mailto and tel only with the flags', () {
    expect(_refused('mailto:a@b.co'), isTrue);
    expect(_out('mailto:a@b.co', mail: true), isTrue);
    expect(_refused('mailto:a@b.co', tel: true), isTrue);
    expect(_refused('tel:+201000000000'), isTrue);
    expect(_out('tel:+201000000000', tel: true), isTrue);
    expect(_refused('tel:+201000000000', mail: true), isTrue);
    expect(_refused('mailto:', mail: true), isTrue);
  });

  test('our own in-app routes open in the app, other paths are refused', () {
    expect(checkExternalLink('/c/12?ref=5'), isA<ExternalLinkInApp>());
    expect((checkExternalLink('/s/page/calendar') as ExternalLinkInApp).route, '/s/page/calendar');
    expect(_refused('/admin_dashboard'), isTrue);
    expect(_refused('/etc/passwd'), isTrue);
  });

  group('openExternalLink', () {
    final launched = <(String, String?)>[];
    var answer = true;
    setUp(() {
      launched.clear();
      answer = true;
      externalLinkLauncher = (uri, window) async {
        launched.add((uri.toString(), window));
        return answer;
      };
    });

    test('launches an allowed link and returns what the launcher said', () async {
      expect(await openExternalLink('https://example.com', webOnlyWindowName: '_blank'), isTrue);
      expect(launched, [('https://example.com', '_blank')]);
      answer = false;
      expect(await openExternalLink('https://example.com', quiet: true), isFalse);
    });

    test('never hands a refused link to the launcher', () async {
      expect(await openExternalLink('javascript:alert(1)'), isFalse);
      expect(await openExternalLink('mailto:a@b.co', quiet: true), isFalse);
      expect(launched, isEmpty);
      expect(await openExternalLink('mailto:a@b.co', allowMail: true), isTrue);
      expect(launched.single.$1, 'mailto:a@b.co');
    });

    test('a launcher that throws is false, not an exception', () async {
      externalLinkLauncher = (_, _) async => throw StateError('no activity');
      expect(await openExternalLink('https://example.com', quiet: true), isFalse);
    });
  });
}
