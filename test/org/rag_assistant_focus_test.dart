// The app assistant as it really sits in the app: the floating host above the Navigator (AppKeyboardSupport around
// it, as in main.dart), over the fake backend.
//
// N2: the pop-up stays mounted while closed (an answer being prepared is kept), beside the Navigator in the view's
// own focus scope. Its hidden nodes must leave the focus order, and no traversal (Tab, the browser handing focus back
// to the page) may measure a node that is not laid out — FocusNode.rect threw "Null check operator used on a null
// value" in RenderObject.getTransformTo on the web.
//
// N6: opening the assistant never shows a failure first — an old latest chat, or one whose last answer failed or was
// abandoned, opens on a new chat with the starter questions (the history stays reachable).
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/providers.dart';
import 'package:flutter_education_app/design/app_keyboard.dart';
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat_screen.dart';
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

    testWidgets('a reopened recent question that gives up at once: a new chat, not the failure (the panel, N6)', (tester) async {
      final now = DateTime.now().toUtc();
      backend({
        'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(seconds: 20))),
        'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'queued', now.subtract(const Duration(seconds: 20)))], 'has_more': false},
        'GET /api/v1/rag/queries/2': (_) => const FakeResponse(500, {'detail': 'worker gone'}),
      });
      await pumpChat(tester);
      expect(find.byType(RagStalledNote), findsNothing);
      expect(find.byType(RagStarterPrompts), findsOneWidget);
      expect(find.text('rag_chats'.tr), findsOneWidget, reason: 'the chat stays under Chats');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the pop-up opened again on a chat that ends on a failure: a new chat', (tester) async {
      final now = DateTime.now().toUtc();
      backend({
        'GET /api/v1/rag/conversations': (_) => _conversations(now.subtract(const Duration(minutes: 1))),
        'GET /api/v1/rag/conversations/2/messages': (_) => {'items': [_query(2, 'failed', now.subtract(const Duration(minutes: 1)))], 'has_more': false},
      });
      final key = GlobalKey<RagChatViewState>();
      // picked by the person (not reopened by itself): the failure stays while they look at it
      await tester.pumpWidget(layoutHost(SizedBox(height: 700, child: RagChatView(key: key, app: true, compact: true, initialConversationId: 2)), scale: 1));
      await _settle(tester, 12);
      expect(find.byType(RagStarterPrompts), findsNothing);
      key.currentState!.reopened();
      await _settle(tester, 4);
      expect(find.byType(RagStarterPrompts), findsOneWidget);
      expect(key.currentState!.conversationId, isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
