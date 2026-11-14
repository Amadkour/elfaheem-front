// The app assistant as it really sits in the app: the floating host above the Navigator (AppKeyboardSupport around
// it, as in main.dart), over the fake backend.
//
// N2: the pop-up stays mounted while closed (an answer being prepared is kept), beside the Navigator in the view's
// own focus scope. Its hidden nodes must leave the focus order, and no traversal (Tab, the browser handing focus back
// to the page) may measure a node that is not laid out — FocusNode.rect threw "Null check operator used on a null
// value" in RenderObject.getTransformTo on the web.
//
// N6: opening the assistant never shows a failure first — an old latest chat, or one whose last answer failed or was
// abandoned, opens on a new chat with the starter questions (the history stays reachable). Only a chat the assistant
// opened BY ITSELF is swapped, and the person is told where it went; a chat they started, asked in or picked keeps its
// failure with Retry. A poll that fails in passing (500 / 503) never gives up on an answer.
//
// The pop-up follows the open organization (its page reads the host's current scope, not the one it was built with),
// and Full screen from a new chat stays on a new chat with the unsent question, which comes back with the pop-up.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/design/app_keyboard.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat_screen.dart';
import 'package:flutter_education_app/main.dart' as app show navigatorKey;
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();

Map<String, dynamic> _query(int id, String state, DateTime asked) => {
      'id': id,
      'state': state,
      'stage': null,
      'question': 'Explain the privacy policy: what data do you keep about me?',
      'found': state == 'done' ? true : null,
      'answer': state == 'done' ? 'We keep your account and your course progress. [1]' : null,
      'citations': state == 'done'
          ? [
              {'n': 1, 'document_id': 0, 'title': 'Privacy', 'kind': 'page', 'quote': 'We keep your account.'},
            ]
          : [],
      'generator': state == 'done' ? 'extractive' : null,
      'app': true,
      'error': state == 'failed' ? 'worker' : null,
      'follow_ups': [],
      'created_at': _iso(asked),
      'conversation_id': 2,
      'answer_partial': null,
    };

Map<String, dynamic> _conversations(DateTime lastAt) => {
      'items': [
        {
          'id': 2,
          'title': 'Explain the privacy policy…',
          'scope': {'app': true, 'org_id': null, 'course_id': null},
          'created_at': _iso(lastAt),
          'last_at': _iso(lastAt),
          'turns': 1,
        },
      ],
      'retention_days': 90,
    };

const _starters = {
  'questions': ['How do I download a lecture?', 'How do I pay for a course?'],
};

Widget _page(String name) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: ListView(children: [
      const TextField(),
      for (var i = 0; i < 4; i++) TextButton(onPressed: () {}, child: Text('$name $i')),
    ]));

/// Hands the view its focus back WHILE a frame is painted: after the build removed what a tap replaced, before the
/// removed elements are unmounted. That is where the web engine reports it (the tapped node's DOM element leaves the
/// page in the frame's semantics update, the browser moves its focus, the view looks for its initial focus).
class _FocusBackDuringPaint extends CustomPainter {
  _FocusBackDuringPaint(this.armed, this.viewId) : super(repaint: AppAssistant.open);
  final ValueNotifier<bool> armed;
  final int viewId;

  @override
  void paint(Canvas canvas, Size size) {
    if (!armed.value) return;
    armed.value = false;
    WidgetsBinding.instance.handleViewFocusChanged(
        ViewFocusEvent(viewId: viewId, state: ViewFocusState.focused, direction: ViewFocusDirection.forward));
  }

  @override
  bool shouldRepaint(_FocusBackDuringPaint oldDelegate) => true;
}

/// Answers the calls in turn (the last one again once the list is spent).
FakeHandler _inTurn(List<Object?> answers) {
  var n = 0;
  return (_) => answers[n < answers.length ? n++ : answers.length - 1];
}

const _swappedNotice = 'Your previous chat is saved under Chats';

Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Every focus node a traversal may sort (focusable, traversable, under focusable ancestors) can be measured.
void _expectMeasurable(String when) {
  final broken = <String>[];
  for (final n in FocusManager.instance.rootScope.descendants) {
    if (!n.canRequestFocus || n.skipTraversal) continue;
    if (n.ancestors.any((a) => !a.descendantsAreFocusable || !a.descendantsAreTraversable)) continue;
    try {
      n.rect;
    } catch (e) {
      broken.add('${n.context?.widget.runtimeType}: ${e.toString().split('\n').first}');
    }
  }
  expect(broken, isEmpty, reason: when);
}

void main() {
  late StorageService storage;
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    storage = await StorageService.getInstance();
    await storage.saveUser({'id': 7, 'name': 'Test User', 'gmail': 'user@example.com', 'role': 'student'});
  });
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    AppAssistant.open.value = false;
    AppAssistant.draft.value = null;
  });

  FakeApi backend(Map<String, FakeHandler> routes) {
    final api = FakeApi({'GET /api/v1/rag/starters': (_) => _starters, ...routes}, fallback: (_) => const <String, dynamic>{})
      ..install();
    addTearDown(api.uninstall);
    return api;
  }

  testWidgets('N2: the hidden pop-up leaves the focus order; traversal never measures a node that is not laid out', (tester) async {
    final now = DateTime.now().toUtc();
    backend({
      'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(minutes: 5))),
      'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'done', now.subtract(const Duration(minutes: 5)))], 'has_more': false},
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final nav = GlobalKey<NavigatorState>();
    final theme = ThemeConfigProvider(api: ApiClient());
    await ApiClient().primeSession();
    // a web deep link: the home is built under the page and never laid out
    await tester.pumpWidget(MultiProvider(
      providers: appProviders(storage: storage, api: ApiClient()),
      child: ThemeConfigScope(
        provider: theme,
        child: MaterialApp(
          navigatorKey: nav,
          theme: theme.materialTheme(dark: false),
          navigatorObservers: [topRouteObserver],
          initialRoute: '/privacy',
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => _page('other')),
          onGenerateInitialRoutes: (_) => [
            MaterialPageRoute<void>(builder: (_) => _page('home'), settings: const RouteSettings(name: '/dashboard')),
            MaterialPageRoute<void>(builder: (_) => _page('privacy'), settings: const RouteSettings(name: '/privacy')),
          ],
          builder: (context, child) => AppKeyboardSupport(child: AppAssistantHost(navigatorKey: nav, child: child!)),
        ),
      ),
    ));
    await _settle(tester);

    Future<void> traverse(String when) async {
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      // the browser hands the focus back to the page (web: findFirstFocus over the view's scope)
      WidgetsBinding.instance.handleViewFocusChanged(
          ViewFocusEvent(viewId: tester.view.viewId, state: ViewFocusState.focused, direction: ViewFocusDirection.forward));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: when);
      _expectMeasurable(when);
    }

    _expectMeasurable('start');
    await traverse('page, assistant never opened');

    // open from the edge tab, type, Tab around inside the card
    await tester.tap(find.byType(AppAssistantEdgeTab));
    await _settle(tester);
    expect(find.byType(RagChatView), findsOneWidget);
    _expectMeasurable('pop-up open');
    await tester.tap(find.descendant(of: find.byType(RagChatView), matching: find.byType(TextField)));
    await tester.pump();
    await traverse('pop-up open, its field focused');

    // closed: still mounted (the answer is kept) but out of the focus order
    AppAssistant.open.value = false;
    await tester.pump();
    final field = find.descendant(of: find.byType(RagChatView, skipOffstage: false), matching: find.byType(EditableText, skipOffstage: false));
    final node = tester.widget<EditableText>(field).focusNode;
    expect(node.hasFocus, isFalse, reason: 'a closed pop-up keeps no focus');
    expect(node.ancestors.any((a) => !a.descendantsAreFocusable), isTrue, reason: 'a closed pop-up is out of the focus order');
    await traverse('pop-up closed');

    // "Ask about this page": opens on a new chat with the question typed in
    AppAssistant.ask('What data do you keep about me?');
    await _settle(tester);
    expect(node.ancestors.every((a) => a.descendantsAreFocusable), isTrue, reason: 'open again: focusable');
    await traverse('pop-up opened by Ask');

    // expanded to the full page and back
    await tester.tap(find.byTooltip('Full screen').hitTestable().first, warnIfMissed: false);
    await _settle(tester);
    await traverse('full page');
    nav.currentState!.pop();
    await _settle(tester);
    await traverse('back from the full page');

    await tester.pumpWidget(const SizedBox());
    await _settle(tester, 70);
  });

  testWidgets('N2 (real app): a tap on the edge tab removes it in the frame that opens the pop-up; the focus handed back '
      'to the view in that frame never measures its parked node', (tester) async {
    final now = DateTime.now().toUtc();
    backend({
      'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(days: 2))),
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final armed = ValueNotifier<bool>(false);
    final nav = GlobalKey<NavigatorState>();
    final theme = ThemeConfigProvider(api: ApiClient());
    await ApiClient().primeSession();
    await tester.pumpWidget(MultiProvider(
      providers: appProviders(storage: storage, api: ApiClient()),
      child: ThemeConfigScope(
        provider: theme,
        child: MaterialApp(
          navigatorKey: nav,
          theme: theme.materialTheme(dark: false),
          navigatorObservers: [topRouteObserver],
          home: CustomPaint(painter: _FocusBackDuringPaint(armed, tester.view.viewId), child: _page('profile')),
          builder: (context, child) => AppKeyboardSupport(child: AppAssistantHost(navigatorKey: nav, child: child!)),
        ),
      ),
    ));
    await _settle(tester);
    expect(find.byType(AppAssistantEdgeTab), findsOneWidget);

    armed.value = true;
    await tester.tap(find.byType(AppAssistantEdgeTab));
    await tester.pump();
    expect(armed.value, isFalse, reason: 'the focus was handed back during that frame');
    expect(tester.takeException(), isNull);
    expect(find.byType(AppAssistantEdgeTab), findsNothing, reason: 'the tab gave way to the pop-up');
    await _settle(tester);
    expect(find.byType(RagChatView), findsOneWidget);

    // closed from its header: the tab comes back; the same hand-back in that frame is safe too
    armed.value = true;
    await tester.tap(find.byTooltip('Close').hitTestable().first);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _settle(tester);
    expect(find.byType(AppAssistantEdgeTab), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester, 70);
  });

  testWidgets('the pop-up has a Navigator of its own: Chats opens its sheet inside the card', (tester) async {
    final now = DateTime.now().toUtc();
    backend({
      'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(minutes: 5))),
      'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'done', now.subtract(const Duration(minutes: 5)))], 'has_more': false},
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final nav = GlobalKey<NavigatorState>();
    final theme = ThemeConfigProvider(api: ApiClient());
    await ApiClient().primeSession();
    await tester.pumpWidget(MultiProvider(
      providers: appProviders(storage: storage, api: ApiClient()),
      child: ThemeConfigScope(
        provider: theme,
        child: MaterialApp(
          navigatorKey: nav,
          theme: theme.materialTheme(dark: false),
          navigatorObservers: [topRouteObserver],
          home: _page('home'),
          builder: (context, child) => AppKeyboardSupport(child: AppAssistantHost(navigatorKey: nav, child: child!)),
        ),
      ),
    ));
    await _settle(tester);
    AppAssistant.openPanel();
    await _settle(tester, 12);
    await tester.tap(find.byTooltip('rag_chats'.tr).hitTestable().first);
    await _settle(tester, 8);
    expect(tester.takeException(), isNull, reason: 'showModalBottomSheet found no Navigator above the pop-up');
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, 70);
  });

  /// The host as in main.dart over [home], with the app's providers; the app Navigator's key is returned.
  Future<GlobalKey<NavigatorState>> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final nav = GlobalKey<NavigatorState>();
    final theme = ThemeConfigProvider(api: ApiClient());
    await ApiClient().primeSession();
    await tester.pumpWidget(MultiProvider(
      providers: appProviders(storage: storage, api: ApiClient()),
      child: ThemeConfigScope(
        provider: theme,
        child: MaterialApp(
          navigatorKey: nav,
          theme: theme.materialTheme(dark: false),
          navigatorObservers: [topRouteObserver],
          home: _page('home'),
          builder: (context, child) => AppKeyboardSupport(child: AppAssistantHost(navigatorKey: nav, child: child!)),
        ),
      ),
    ));
    await _settle(tester);
    return nav;
  }

  testWidgets('Full screen from a new chat: the page stays on a new chat (not the latest) with the unsent question; '
      'back, the pop-up gets the page\'s chat and text', (tester) async {
    final now = DateTime.now().toUtc();
    final api = backend({
      'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(minutes: 5))),
      'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'done', now.subtract(const Duration(minutes: 5)))], 'has_more': false},
    });
    final nav = await pumpHost(tester);
    AppAssistant.openPanel();
    await _settle(tester, 12);
    final popup = tester.state<RagChatViewState>(find.byType(RagChatView));
    expect(popup.conversationId, 2, reason: 'the recent chat is resumed');
    await tester.tap(find.byTooltip('rag_new_chat'.tr).hitTestable().first);
    await _settle(tester, 4);
    expect(popup.conversationId, isNull);
    await tester.enterText(find.descendant(of: find.byType(RagChatView), matching: find.byType(TextField)), 'How do I pay?');
    await tester.pump();
    final opened = api.calls.where((c) => c.path.endsWith('/messages')).length;

    await tester.tap(find.byTooltip('Full screen').hitTestable().first);
    await _settle(tester, 12);
    final pageView = find.descendant(of: find.byType(RagChatScreen), matching: find.byType(RagChatView));
    final page = tester.state<RagChatViewState>(pageView);
    expect(page.conversationId, isNull, reason: 'a new chat stays new: the latest conversation is not reopened');
    expect(page.draftText, 'How do I pay?', reason: 'the unsent question moved along');
    expect(api.calls.where((c) => c.path.endsWith('/messages')).length, opened, reason: 'no conversation was opened');
    expect(find.descendant(of: find.byType(RagChatScreen), matching: find.byType(RagStarterPrompts)), findsOneWidget);
    expect(popup.draftText, isEmpty, reason: 'taken out of the pop-up while the page has it');

    await tester.enterText(find.descendant(of: pageView, matching: find.byType(TextField)), 'How do I pay by card?');
    await tester.pump();
    nav.currentState!.pop();
    await _settle(tester, 12);
    expect(find.byType(RagChatScreen), findsNothing);
    expect(popup.mounted, isTrue, reason: 'the pop-up stayed mounted while closed');
    expect(popup.draftText, 'How do I pay by card?', reason: 'the page\'s unsent text comes back');
    expect(popup.conversationId, isNull);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester, 70);
  });

  group('the pop-up follows the open organization', () {
    final overview = {
      'items': [
        {'organization': {'id': 7, 'name': 'Nile', 'status': 'approved'}, 'role': 'member'},
      ],
    };
    final apply = AppModeController.applyContext;
    setUp(() {
      AppConfig.setOrgsEnabled(true);
      AppModeController.applyContext = (_) {};
      AppModeController.instance.debugSet(overview, mode: AppMode.individual, orgId: 7);
    });
    tearDown(() {
      AppModeController.instance.debugSet(const {}, mode: AppMode.individual);
      AppModeController.applyContext = apply;
    });

    testWidgets('switched to Organization mode and back while the pop-up is mounted: each scope\'s chat at once', (tester) async {
      final now = DateTime.now().toUtc();
      final orgAsked = now.subtract(const Duration(minutes: 2));
      backend({
        'GET /api/v1/rag/conversations': (o) => o.uri.queryParameters['org_id'] == '7'
            ? {
                'items': [
                  {
                    'id': 9,
                    'title': 'The organization rules',
                    'scope': {'app': true, 'org_id': 7, 'course_id': null},
                    'created_at': _iso(orgAsked),
                    'last_at': _iso(orgAsked),
                    'turns': 1,
                  },
                ],
                'retention_days': 90,
              }
            : _conversations(now.subtract(const Duration(minutes: 5))),
        'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'done', now.subtract(const Duration(minutes: 5)))], 'has_more': false},
        'GET /api/v1/rag/conversations/9/messages': (_) => {'items': [{..._query(9, 'done', orgAsked), 'conversation_id': 9, 'org_id': 7}], 'has_more': false},
      });
      await pumpHost(tester);
      AppAssistant.openPanel();
      await _settle(tester, 12);
      RagChatView view() => tester.widget<RagChatView>(find.byType(RagChatView));
      RagChatViewState chat() => tester.state<RagChatViewState>(find.byType(RagChatView));
      expect(view().orgId, isNull);
      expect(chat().conversationId, 2);

      AppModeController.instance.debugSet(overview, mode: AppMode.organization, orgId: 7);
      await _settle(tester, 12);
      expect(view().orgId, 7, reason: 'the pop-up follows the organization now, not when it is next rebuilt');
      expect(find.text('About the app and Nile'), findsOneWidget);
      expect(chat().conversationId, 9);

      AppModeController.instance.debugSet(overview, mode: AppMode.individual, orgId: 7);
      await _settle(tester, 12);
      expect(view().orgId, isNull);
      expect(chat().conversationId, 2, reason: 'the personal chat the person was in comes back');

      await tester.pumpWidget(const SizedBox());
      await _settle(tester, 70);
    });
  });

  group('the edge tab (R3)', () {
    test('no tab while a role shell top bar (sidebar / rail) carries the assistant button', () {
      expect(appAssistantEdgeTabShown(sideChrome: 0), isTrue, reason: 'phone bottom bar, or no shell');
      expect(appAssistantEdgeTabShown(sideChrome: 67), isFalse, reason: 'tablet rail');
      expect(appAssistantEdgeTabShown(sideChrome: 240), isFalse, reason: 'desktop sidebar');
    });

    test('a wide window without a shell docks it in the bottom end corner', () {
      expect(AppAssistantSpot.fallback(rtl: true, wide: true).fraction, 1.0);
      expect(AppAssistantSpot.fallback(rtl: true, wide: true).left, isTrue);
      expect(AppAssistantSpot.fallback(rtl: false).fraction, lessThan(1.0), reason: 'phones keep it above the FAB strip');
    });
  });

  group('ragPollGivesUp / ragGivesUp', () {
    RagAnswer a(String state, DateTime asked) => RagAnswer.fromJson(_query(1, state, asked));
    final now = DateTime.now().toUtc();
    test('only a 404 / 403 / 401 ends the wait; a 500, a 503 or no network is passing', () {
      expect(ragPollGivesUp(EngineResult.fail(404, 'query_not_found', 'gone')), isTrue);
      expect(ragPollGivesUp(EngineResult.fail(403, 'not_owner', 'no')), isTrue);
      expect(ragPollGivesUp(EngineResult.fail(401, null, 'signed out')), isTrue);
      expect(ragPollGivesUp(EngineResult.fail(500, null, 'boom')), isFalse);
      expect(ragPollGivesUp(EngineResult.fail(503, 'server_busy', 'busy')), isFalse);
      expect(ragPollGivesUp(EngineResult.fail(0, null, 'offline')), isFalse);
      expect(ragPollGivesUp(EngineResult.ok(const {})), isFalse);
    });
    test('an unfinished answer is given up on only past its patience, at the deadline, or when it is gone', () {
      final fresh = a('queued', now.subtract(const Duration(seconds: 30)));
      final busy = EngineResult.fail(503, 'server_busy', 'busy');
      expect(ragGivesUp(fresh, busy, now, timedOut: false), isFalse, reason: 'a passing failure');
      expect(ragGivesUp(fresh, EngineResult.ok(_query(1, 'running', now)), now, timedOut: false), isFalse);
      expect(ragGivesUp(fresh, busy, now, timedOut: true), isTrue, reason: 'the wait spent its patience');
      expect(ragGivesUp(fresh, EngineResult.fail(404, null, 'gone'), now, timedOut: false), isTrue);
      expect(ragGivesUp(a('queued', now.subtract(const Duration(minutes: 4))), busy, now, timedOut: false), isTrue,
          reason: 'past its patience by the server clock');
      expect(ragGivesUp(fresh, EngineResult.ok(_query(1, 'done', now)), now, timedOut: true), isFalse, reason: 'finished');
      expect(ragGivesUp(a('done', now), busy, now, timedOut: true), isFalse);
    });
  });

  group('ragShowsFailure', () {
    RagAnswer a(int id, String state) => RagAnswer.fromJson(_query(id, state, DateTime.now()));
    test('the last question failed, or was given up on', () {
      expect(ragShowsFailure([], {}), isFalse);
      expect(ragShowsFailure([a(1, 'done'), a(2, 'failed')], {}), isTrue);
      expect(ragShowsFailure([a(1, 'queued')], {1}), isTrue);
      expect(ragShowsFailure([a(1, 'queued')], {}), isFalse, reason: 'still being followed');
      expect(ragShowsFailure([a(1, 'failed'), a(2, 'done')], {}), isFalse, reason: 'only the last one counts');
    });
  });

  group('N6: never opens on a failure', () {
    Future<void> pumpChat(WidgetTester tester) async {
      await tester.pumpWidget(layoutHost(const SizedBox(height: 700, child: RagChatView(app: true, compact: true)), scale: 1));
      await _settle(tester, 12);
    }

    testWidgets('the latest chat ends on an abandoned question: a new chat with the starters, the chat under Chats', (tester) async {
      final now = DateTime.now().toUtc();
      final api = backend({
        'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(hours: 1))),
        'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'queued', now.subtract(const Duration(hours: 1)))], 'has_more': false},
      });
      await pumpChat(tester);
      expect(find.byType(RagStarterPrompts), findsOneWidget);
      expect(find.byType(RagStalledNote), findsNothing);
      expect(find.byType(RagAnswerCard), findsNothing);
      expect(find.text('rag_chats'.tr), findsOneWidget, reason: 'the old chat stays reachable');
      expect(api.calls.where((c) => c.path.startsWith('/api/v1/rag/queries/')), isEmpty, reason: 'nothing is followed');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the latest chat is old: not reopened at all', (tester) async {
      final now = DateTime.now().toUtc();
      final api = backend({
        'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(days: 1))),
        'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'done', now.subtract(const Duration(days: 1)))], 'has_more': false},
      });
      await pumpChat(tester);
      expect(find.byType(RagStarterPrompts), findsOneWidget);
      expect(api.calls.where((c) => c.path.endsWith('/messages')), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a recent answered chat is reopened as before', (tester) async {
      final now = DateTime.now().toUtc();
      backend({
        'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(minutes: 10))),
        'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'done', now.subtract(const Duration(minutes: 10)))], 'has_more': false},
      });
      await pumpChat(tester);
      expect(find.byType(RagAnswerCard), findsOneWidget);
      expect(find.byType(RagStarterPrompts), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an older server (flat history) ending on a failure: the starters, "Earlier questions" unfolds it', (tester) async {
      final now = DateTime.now().toUtc();
      backend({
        'GET /api/v1/rag/conversations': (_) => const FakeResponse(404, {'detail': 'Not Found'}),
        'GET /api/v1/rag/queries': (_) => {
              'items': [_query(4, 'failed', now.subtract(const Duration(minutes: 2))), _query(3, 'done', now.subtract(const Duration(hours: 2)))],
            },
      });
      await pumpChat(tester);
      expect(find.byType(RagStarterPrompts), findsOneWidget);
      expect(find.byType(RagAnswerCard), findsNothing);
      await tester.tap(find.byKey(const ValueKey('rag.earlier')));
      await _settle(tester, 4);
      expect(find.byType(RagAnswerCard), findsNWidgets(2));
      expect(find.byType(RagStarterPrompts), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    /// Under the app's own Navigator key, where [showAppNotice] draws.
    Future<GlobalKey<RagChatViewState>> pumpRooted(WidgetTester tester, {int? conversationId}) async {
      final key = GlobalKey<RagChatViewState>();
      await tester.pumpWidget(ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MaterialApp(
          navigatorKey: app.navigatorKey,
          home: Scaffold(
              body: SizedBox(height: 700, child: RagChatView(key: key, app: true, compact: true, initialConversationId: conversationId))),
        ),
      ));
      await _settle(tester, 12);
      return key;
    }

    testWidgets('a reopened recent question the server no longer has (404): a new chat, and a notice says where the chat went', (tester) async {
      final now = DateTime.now().toUtc();
      backend({
        'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(seconds: 20))),
        'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'queued', now.subtract(const Duration(seconds: 20)))], 'has_more': false},
        'GET /api/v1/rag/queries/2': (_) => const FakeResponse(404, {'detail': {'code': 'query_not_found', 'message': 'gone'}}),
      });
      final key = await pumpRooted(tester);
      expect(find.byType(RagStalledNote), findsNothing);
      expect(find.byType(RagStarterPrompts), findsOneWidget);
      expect(key.currentState!.conversationId, isNull);
      expect(find.text('rag_chats'.tr), findsWidgets, reason: 'the chat stays under Chats');
      expect(find.text(_swappedNotice), findsOneWidget, reason: 'the person is told where the chat went');
      await _settle(tester, 70); // the notice times out
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a reopened recent question whose polls fail in passing (503, 500): followed on, the answer arrives, the chat stays', (tester) async {
      final now = DateTime.now().toUtc();
      final api = backend({
        'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(seconds: 20))),
        'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'queued', now.subtract(const Duration(seconds: 20)))], 'has_more': false},
        'GET /api/v1/rag/queries/2': _inTurn([
          const FakeResponse(503, {'detail': {'code': 'server_busy', 'message': 'busy'}}),
          const FakeResponse(500, {'detail': 'worker hiccup'}),
          _query(2, 'done', now.subtract(const Duration(seconds: 20))),
        ]),
      });
      final key = await pumpRooted(tester);
      await _settle(tester, 60);
      expect(api.calls.where((c) => c.path == '/api/v1/rag/queries/2').length, greaterThanOrEqualTo(3));
      expect(key.currentState!.conversationId, 2);
      expect(find.byType(RagAnswerCard), findsOneWidget);
      expect(find.byType(RagStalledNote), findsNothing, reason: 'a passing poll failure is not a failure');
      expect(find.byType(RagStarterPrompts), findsNothing);
      expect(find.text(_swappedNotice), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a question asked in a new chat survives a failed poll mid-answer; opening the pop-up again keeps the chat', (tester) async {
      final now = DateTime.now().toUtc();
      final api = backend({
        'GET /api/v1/rag/conversations': (_) => {'items': [], 'retention_days': 90},
        'POST /api/v1/rag/conversations': (_) => {
              'id': 11,
              'title': 'Explain the privacy policy',
              'scope': {'app': true, 'org_id': null, 'course_id': null},
              'created_at': _iso(now),
              'last_at': _iso(now),
              'turns': 0,
            },
        'POST /api/v1/rag/ask': (_) => {..._query(5, 'queued', now), 'conversation_id': 11},
        'GET /api/v1/rag/queries/5': _inTurn([
          {..._query(5, 'running', now), 'conversation_id': 11},
          const FakeResponse(503, {'detail': {'code': 'server_busy', 'message': 'busy'}}),
          {..._query(5, 'done', now), 'conversation_id': 11},
        ]),
      });
      final key = await pumpRooted(tester);
      expect(key.currentState!.conversationId, isNull, reason: 'no chat yet: a new one');
      key.currentState!.send('Explain the privacy policy: what data do you keep about me?');
      await _settle(tester, 60);
      expect(api.calls.where((c) => c.path == '/api/v1/rag/queries/5').length, greaterThanOrEqualTo(3));
      expect(key.currentState!.conversationId, 11);
      expect(find.byType(RagAnswerCard), findsOneWidget);
      expect(find.byType(RagStalledNote), findsNothing, reason: 'one 503 mid-answer does not mark it failed');
      key.currentState!.reopened();
      await _settle(tester, 4);
      expect(key.currentState!.conversationId, 11, reason: 'the new chat is not swapped away');
      expect(find.byType(RagAnswerCard), findsOneWidget);
      expect(find.text(_swappedNotice), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the pop-up opened again on a chat the person picked that ends on a failure: it stays, with Retry', (tester) async {
      final now = DateTime.now().toUtc();
      backend({
        'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(minutes: 1))),
        'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'failed', now.subtract(const Duration(minutes: 1)))], 'has_more': false},
      });
      // picked by the person (not reopened by itself)
      final key = await pumpRooted(tester, conversationId: 2);
      expect(find.byType(RagStarterPrompts), findsNothing);
      key.currentState!.reopened();
      await _settle(tester, 4);
      expect(find.byType(RagStarterPrompts), findsNothing, reason: 'a chat the person chose is never swapped by itself');
      expect(key.currentState!.conversationId, 2);
      expect(find.text(_swappedNotice), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
