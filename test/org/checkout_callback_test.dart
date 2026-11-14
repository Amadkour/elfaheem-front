// The hosted-checkout WebView's rules (S6, F14): the result page's callback is matched by exact scheme + host + path,
// only https pages are followed, and "paid" is shown only once GET /api/v1/payments/{id} says completed.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/payments/enrollment/checkout_callback.dart';
import 'package:flutter_education_app/features/payments/enrollment/payment_flow_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

class _Flow extends PaymentFlowProvider {}

const _prod = CheckoutOrigin(schemes: {'https'}, hosts: {'alfheemacademy.com', 'www.alfheemacademy.com'});
const _dev = CheckoutOrigin(schemes: {'https', 'http'}, hosts: {'alfheemacademy.com', ...kDevCheckoutHosts});

bool _cb(String url, [CheckoutOrigin o = _prod]) => isCheckoutCallback(Uri.parse(url), o);
bool _nav(String url, {bool main = true, CheckoutOrigin o = _prod}) =>
    checkoutNavigationAllowed(Uri.tryParse(url), o, isMainFrame: main);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() => AppConfig.lang = 'en');

  group('callback match', () {
    test('the result page\'s real URLs match (hash route, root or /app/, path strategy, www)', () {
      expect(_cb('https://alfheemacademy.com/#/payment/callback?status=paid&course_id=4'), isTrue);
      expect(_cb('https://alfheemacademy.com#/payment/callback?status=failed'), isTrue);
      expect(_cb('https://alfheemacademy.com/app/#/payment/callback?status=initiated'), isTrue);
      expect(_cb('https://alfheemacademy.com/app#/payment/callback?status=paid'), isTrue);
      expect(_cb('https://www.alfheemacademy.com/#/payment/callback?status=paid'), isTrue);
      expect(_cb('https://alfheemacademy.com/payment/callback?status=paid'), isTrue);
      expect(_cb('https://alfheemacademy.com/app/payment/callback?status=paid'), isTrue);
      expect(_cb('https://ALFHEEMACADEMY.com/#/payment/callback?status=paid'), isTrue);
    });

    test('a URL that only contains the words is not the callback', () {
      expect(_cb('https://evil.example/#/payment/callback?status=paid'), isFalse);
      expect(_cb('https://evil.example/payment/callback?status=paid'), isFalse);
      expect(_cb('https://alfheemacademy.com.evil.example/#/payment/callback?status=paid'), isFalse);
      expect(_cb('https://evil.example/?next=https://alfheemacademy.com/#/payment/callback'), isFalse);
      expect(_cb('https://api.moyasar.com/v1/payments?return=/payment/callback'), isFalse);
      expect(_cb('https://alfheemacademy.com/x/#/payment/callback?status=paid'), isFalse);
      expect(_cb('https://alfheemacademy.com/#/payment/callbackx?status=paid'), isFalse);
      expect(_cb('https://alfheemacademy.com/#/other?r=/payment/callback&status=paid'), isFalse);
      expect(_cb('https://alfheemacademy.com/api/v1/payments/callback?status=paid'), isFalse);
      expect(_cb('http://alfheemacademy.com/#/payment/callback?status=paid'), isFalse, reason: 'plain http in a release');
      expect(_cb('nextbrain://payment/callback?status=paid'), isFalse);
    });

    test('a debug build also takes the local stack\'s http callback, a release build never', () {
      expect(_cb('http://localhost:8000/#/payment/callback?status=paid', _dev), isTrue);
      expect(_cb('http://localhost:8000/#/payment/callback?status=paid'), isFalse);
      final rel = CheckoutOrigin.current(release: true);
      expect(rel.schemes, {'https'});
      expect(rel.hosts, contains(Uri.parse(AppConfig.baseUrl).host));
      expect(rel.hosts.intersection(kDevCheckoutHosts), isEmpty);
    });

    test('status: the hash route\'s query first, then the URL\'s own, failed when missing', () {
      expect(checkoutStatusFrom(Uri.parse('https://alfheemacademy.com/#/payment/callback?status=paid&message=a%20b')), 'paid');
      expect(checkoutStatusFrom(Uri.parse('https://alfheemacademy.com/app/payment/callback?status=initiated')), 'initiated');
      expect(checkoutStatusFrom(Uri.parse('https://alfheemacademy.com/#/payment/callback?course_id=3')), 'failed');
      expect(checkoutStatusFrom(Uri.parse('https://alfheemacademy.com/#/payment/callback')), 'failed');
      expect(checkoutStatusFrom(Uri.parse('https://alfheemacademy.com/#/payment/callback?status=')), 'failed');
    });
  });

  group('navigation', () {
    test('https pages are followed, anything else blocked', () {
      expect(_nav('https://api.moyasar.com/v1/transaction_auths/x/form'), isTrue);
      expect(_nav('https://accept.paymob.com/unifiedcheckout/?publicKey=x'), isTrue);
      for (final bad in [
        'http://api.moyasar.com/form',
        'http://alfheemacademy.com/#/payment/callback?status=paid',
        'javascript:alert(1)',
        'data:text/html,<b>paid</b>',
        'file:///etc/passwd',
        'intent://x#Intent;scheme=y;end',
        'nextbrain://pay',
        'about:blank',
        'https:///no-host',
      ]) {
        expect(_nav(bad), isFalse, reason: bad);
      }
      expect(checkoutNavigationAllowed(null, _prod), isFalse);
    });

    test('a 3-D Secure sub-frame may start blank; the main frame may not', () {
      expect(_nav('about:blank', main: false), isTrue);
      expect(_nav('about:srcdoc', main: false), isTrue);
      expect(_nav('about:blank'), isFalse);
      expect(_nav('about:config', main: false), isFalse);
    });

    test('debug: the local stack\'s own http pages only', () {
      expect(_nav('http://10.0.2.2:18080/checkout?token=x', o: _dev), isTrue);
      expect(_nav('http://localhost:18080/checkout', o: _dev), isTrue);
      expect(_nav('http://evil.example/checkout', o: _dev), isFalse);
      expect(_nav('http://10.0.2.2:18080/checkout'), isFalse);
    });
  });

  group('the "paid" trust path', () {
    test('statuses fold: every one completed = confirmed, a failed / refunded one = failed, else pending', () {
      expect(paymentStatusStep(['completed']), PaidCheck.confirmed);
      expect(paymentStatusStep(['COMPLETED', 'completed']), PaidCheck.confirmed);
      expect(paymentStatusStep(['completed', 'pending']), PaidCheck.pending);
      expect(paymentStatusStep(['completed', null]), PaidCheck.pending);
      expect(paymentStatusStep(['completed', 'failed']), PaidCheck.failed);
      expect(paymentStatusStep(['refunded']), PaidCheck.failed);
      expect(paymentStatusStep([]), PaidCheck.pending);
    });

    test('payment ids from a checkout session', () {
      expect(checkoutPaymentIds({'payment_id': 7, 'payment_ids': [7, 8, '9', 8]}), [7, 8, 9]);
      expect(checkoutPaymentIds({'payment_id': '5'}), [5]);
      expect(checkoutPaymentIds({'payment_ids': []}), isEmpty);
      expect(checkoutPaymentIds({'status': 'checkout'}), isEmpty);
    });

    Future<(_Flow, FakeApi)> flow(Map<int, List<Object>> answers) async {
      final reads = {for (final k in answers.keys) k: 0};
      final fake = FakeApi({
        for (final id in answers.keys)
          'GET /api/v1/payments/$id': (_) {
            final list = answers[id]!;
            final a = list[reads[id]!.clamp(0, list.length - 1)];
            reads[id] = reads[id]! + 1;
            return a is FakeResponse ? a : {'id': id, 'status': a, 'student_id': 1, 'course_id': 2, 'amount': 10};
          },
      }, latency: Duration.zero)
        ..install();
      addTearDown(fake.uninstall);
      final f = _Flow()
        ..confirmEvery = Duration.zero
        ..confirmTries = 3;
      addTearDown(f.dispose);
      return (f, fake);
    }

    test('"paid" + the server says completed → success', () async {
      final (f, fake) = await flow({41: ['completed']});
      await f.handleCheckoutResult('paid', [41]);
      expect(f.step, EnrollStep.success);
      expect(fake.calls.where((c) => c.path.endsWith('/payments/41')), hasLength(1));
    });

    test('"paid" but the server still says pending → read again, then pending (never success)', () async {
      final (f, fake) = await flow({42: ['pending']});
      await f.handleCheckoutResult('paid', [42]);
      expect(f.step, EnrollStep.pending);
      expect(fake.calls.where((c) => c.path.endsWith('/payments/42')), hasLength(3));
    });

    test('"paid", pending first, completed on the next read → success', () async {
      final (f, _) = await flow({43: ['pending', 'completed']});
      await f.handleCheckoutResult('paid', [43]);
      expect(f.step, EnrollStep.success);
    });

    test('"paid" but the server says failed → the failure page', () async {
      final (f, _) = await flow({44: ['failed']});
      await f.handleCheckoutResult('paid', [44]);
      expect(f.step, EnrollStep.failed);
      expect(f.failureReason, isNotNull);
    });

    test('"paid" and the status cannot be read → pending, not success', () async {
      final (f, _) = await flow({45: [const FakeResponse(500, {'detail': 'boom'})]});
      await f.handleCheckoutResult('paid', [45]);
      expect(f.step, EnrollStep.pending);
    });

    test('"paid" with no payment id in the session → pending, no request', () async {
      final (f, fake) = await flow({});
      await f.handleCheckoutResult('paid', const []);
      expect(f.step, EnrollStep.pending);
      expect(fake.calls, isEmpty);
    });

    test('a roadmap checkout: success only when every course\'s payment is completed', () async {
      final (f, _) = await flow({51: ['completed'], 52: ['pending']});
      await f.handleCheckoutResult('paid', [51, 52]);
      expect(f.step, EnrollStep.pending);
      final (g, _) = await flow({53: ['completed'], 54: ['completed']});
      await g.handleCheckoutResult('paid', [53, 54]);
      expect(g.step, EnrollStep.success);
    });

    test('the other statuses keep their steps and ask nothing', () async {
      final (f, fake) = await flow({});
      await f.handleCheckoutResult('initiated', [1]);
      expect(f.step, EnrollStep.pending);
      await f.handleCheckoutResult('cancelled', [1]);
      expect(f.step, EnrollStep.method);
      await f.handleCheckoutResult('failed', [1]);
      expect(f.step, EnrollStep.failed);
      await f.handleCheckoutResult('whatever', [1]);
      expect(f.step, EnrollStep.failed);
      expect(fake.calls, isEmpty);
    });
  });
}
