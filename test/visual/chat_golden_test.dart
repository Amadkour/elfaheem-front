// Visual review renders of the Messages inbox and conversation (D-375), compared by eye like the other test/visual files
// (NOT a CI suite). The images go to CHAT_RENDER_DIR when it is set, else test/visual/goldens.
//
//   CHAT_RENDER_DIR=<dir> flutter test test/visual/chat_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/features/shared/chat/chat_api.dart';
import 'package:flutter_education_app/features/shared/chat/chat_models.dart';
import 'package:flutter_education_app/features/shared/chat/chat_page.dart';
import 'package:flutter_education_app/features/shared/chat/chat_store.dart';
import 'package:flutter_education_app/features/shared/chat/chat_widgets.dart';
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

class _Api extends ChatApi {
  @override
  Future<void> read(int id, int messageId) async {}
  @override
  Future<void> delivered(List<Map<String, int>> items) async {}
  @override
  Future<String> attachmentLink(int attachmentId, {bool inline = true}) async => 'https://files.test/$attachmentId';
}

final _now = DateTime.now().toUtc();
DateTime _ago(int minutes) => _now.subtract(Duration(minutes: minutes));

const _me = 1;
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

ChatConversation _c(int id, String name, String last, {int unread = 0, int minutes = 3, bool online = false, bool pinned = false, bool muted = false, String? course, int? sender, String kind = 'direct', String lastKind = 'text', int? senderId}) {
  final c = course == null ? null : ChatCourse(id: id, name: course, nameEn: course);
  return ChatConversation(
    id: id,
    kind: kind,
    peer: kind == 'direct' ? ChatPerson(id: id + 100, name: name, role: 'teacher') : null,
    online: online,
    course: c,
    last: ChatLastMessage(id: 1000 - id, kind: lastKind, body: last, senderId: senderId ?? (sender ?? id + 100), senderName: name, createdAt: _ago(minutes)),
    lastAt: _ago(minutes),
    unread: unread,
    pinned: pinned,
    muted: muted,
    peerReadId: 1000,
    composer: ChatComposerState.open,
  );
}

List<ChatConversation> _rows(bool ar) => ar
    ? [
        _c(1, 'أ. سارة عبد الله', 'تذكير: الواجب غدًا قبل الساعة الثامنة', unread: 2, minutes: 2, online: true, course: 'الفيزياء المتقدمة'),
        _c(2, 'الرياضيات للصف الثالث', 'راجعوا الملف المرفق قبل الحصة', unread: 14, minutes: 40, kind: 'course_group', course: 'الرياضيات للصف الثالث'),
        _c(3, 'محمد علي', 'شكرًا جزيلًا يا أستاذ', minutes: 180, sender: _me, course: 'الكيمياء'),
        _c(4, 'أ. منى إبراهيم', 'سأرسل الملف بعد قليل', minutes: 1500, pinned: true, course: 'اللغة العربية'),
        _c(5, 'أ. خالد حسن', '', minutes: 4000, lastKind: 'image', course: 'التاريخ'),
        _c(6, 'ولي أمر ليلى', 'تمام، شكرًا لكم', minutes: 9000, muted: true, unread: 3),
      ]
    : [
        _c(1, 'Ms. Sara Abdullah', 'Reminder: the homework is due tomorrow before 8', unread: 2, minutes: 2, online: true, course: 'Advanced Physics'),
        _c(2, 'Grade 3 Mathematics', 'Please check the attached sheet before class', unread: 14, minutes: 40, kind: 'course_group', course: 'Grade 3 Mathematics'),
        _c(3, 'Mohamed Ali', 'Thank you so much, sir', minutes: 180, sender: _me, course: 'Chemistry'),
        _c(4, 'Ms. Mona Ibrahim', 'I will send the file shortly', minutes: 1500, pinned: true, course: 'Arabic'),
        _c(5, 'Mr. Khaled Hassan', '', minutes: 4000, lastKind: 'image', course: 'History'),
        _c(6, "Layla's father", 'Great, thank you', minutes: 9000, muted: true, unread: 3),
      ];

ChatMessage _m(int id, String body, int minutes, {int sender = 101, String? client}) =>
    ChatMessage(id: id, clientId: client ?? 'c$id', conversationId: 1, body: body, senderId: sender, senderName: 'Ms. Sara', createdAt: _ago(minutes));

ChatThreadController _thread(ChatHub hub, {required bool ar, bool states = true}) {
  final png = base64Decode(_png);
  final t = ChatThreadController(1, hub: hub)
    ..loaded = true
    ..loading = false
    ..visible = true
    ..conversation = (_c(1, ar ? 'أ. سارة عبد الله' : 'Ms. Sara Abdullah', '', online: true, course: ar ? 'الفيزياء المتقدمة' : 'Advanced Physics')..peerReadId = 11);
  t.messages = chatMergeMessages([], [
    if (states) ...[
      ChatMessage(clientId: 'q1', conversationId: 1, body: ar ? 'هذه الرسالة لم تصل، جرّب مرة أخرى' : 'This one did not get through', senderId: _me, createdAt: _now, sendState: ChatSendState.failed),
      ChatMessage(clientId: 'q2', conversationId: 1, body: ar ? 'سأرسلها عند عودة الاتصال' : 'Sending when back online', senderId: _me, createdAt: _ago(1), sendState: ChatSendState.queued),
      ChatMessage(clientId: 'q3', conversationId: 1, body: ar ? 'الصورة من الدرس' : 'The photo from the lesson', senderId: _me, createdAt: _ago(2), local: [ChatLocalFile(name: 'lesson.png', bytes: png)], sendState: ChatSendState.sending),
    ],
    _m(15, ar ? 'نعم، سأرسله الآن' : 'Yes, sending it now', 3),
    _m(14, ar ? 'تذكير: الواجب غدًا قبل الساعة الثامنة' : 'Reminder: the homework is due tomorrow before 8', 4),
    _m(13, ar ? 'هل الملف جاهز؟' : 'Is the file ready?', 5),
    _m(12, ar ? 'تم، شكرًا جزيلًا' : 'Done, thank you so much', 6, sender: _me),
    _m(11, ar ? 'راجعتُ المسألة الثالثة وأظن أن الناتج صحيح، هل يمكن أن تؤكدي لي؟' : 'I went over problem three and I think the answer is right, can you confirm?', 7, sender: _me),
    _m(10, ar ? 'صباح الخير يا أستاذة' : 'Good morning, Ms. Sara', 8, sender: _me),
    _m(9, ar ? 'لا تنسوا مراجعة الفصل الرابع' : 'Do not forget to review chapter four', 60 * 26),
    ChatMessage(id: 8, clientId: 'c8', conversationId: 1, body: ar ? 'ملخص الفصل' : 'Chapter summary', senderId: 101, createdAt: _ago(60 * 27), attachments: const [ChatAttachment(id: 1, name: 'chapter-4-summary.pdf', mime: 'application/pdf', ext: 'pdf', size: 482113)]),
  ]);
  t.firstUnreadKey = 'c13';
  return t;
}

final _shot = GlobalKey();

Widget _host(Widget child, {required bool dark, required bool rtl}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: displayTheme(theme.materialTheme(dark: false), const DisplayPrefs()),
      darkTheme: displayTheme(theme.materialTheme(dark: true), const DisplayPrefs()),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: Scaffold(body: SafeArea(child: child))),
    ),
  );
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  Future<void> shot(WidgetTester t, String name, Widget Function(bool ar) build, {required Size size, required String lang, required bool dark}) async {
    AppConfig.lang = lang;
    final ar = lang == 'ar';
    debugDisableShadows = false;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    await t.pumpWidget(_host(build(ar), dark: dark, rtl: ar));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    final dir = Platform.environment['CHAT_RENDER_DIR'];
    final file = 'chat_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png';
    await expectLater(find.byKey(_shot), matchesGoldenFile(dir == null ? 'goldens/$file' : Uri.file('$dir/$file').toString()));
    await t.pumpWidget(const SizedBox());
    debugDisableShadows = true;
  }

  ChatHub hubWith(bool ar, {int requests = 0}) {
    final hub = ChatHub.forTest()
      ..api = _Api()
      ..debugSetMyId(_me)
      ..requestCount = requests;
    hub.conversations.addAll(_rows(ar));
    return hub;
  }

  testWidgets('inbox phone', (t) async {
    await shot(t, 'inbox', (ar) {
      final hub = hubWith(ar, requests: 2);
      return ChatListView(hub: hub, onOpen: (_) {}, onNewChat: () {}, onRequests: () {});
    }, size: const Size(390, 844), lang: 'ar', dark: false);
  });

  testWidgets('conversation phone', (t) async {
    await shot(t, 'thread', (ar) {
      final hub = hubWith(ar);
      final th = _thread(hub, ar: ar);
      hub.registerThread(th);
      return ChatThreadView(conversationId: 1, controller: th, showBack: true);
    }, size: const Size(390, 844), lang: 'ar', dark: false);
  });

  testWidgets('desktop master-detail', (t) async {
    await shot(t, 'split', (ar) {
      final hub = hubWith(ar, requests: 2)..selectedId = 1;
      final th = _thread(hub, ar: ar);
      hub.registerThread(th);
      return Row(children: [
        SizedBox(width: kChatListWidth, child: ChatListView(hub: hub, onOpen: (_) {}, onNewChat: () {}, onRequests: () {})),
        const VerticalDivider(width: 1),
        Expanded(child: ChatThreadView(conversationId: 1, controller: th, showBack: false)),
      ]);
    }, size: const Size(1440, 900), lang: 'en', dark: true);
  });

  testWidgets('a received request phone', (t) async {
    await shot(t, 'request_thread', (ar) {
      final hub = hubWith(ar);
      final th = ChatThreadController(1, hub: hub)
        ..loaded = true
        ..loading = false
        ..visible = true
        ..conversation = (_c(9, ar ? 'خالد سمير' : 'Khaled Samir', '')
          ..composer = ChatComposerState.requestReceived
          ..request = const ChatRequestInfo(state: 'pending', mine: false))
        ..messages = [_m(1, ar ? 'السلام عليكم، هل يمكنني السؤال عن موعد الدرس القادم؟' : 'Hello, may I ask when the next lesson is?', 5)];
      hub.registerThread(th);
      return ChatThreadView(conversationId: 1, controller: th, showBack: true);
    }, size: const Size(390, 844), lang: 'ar', dark: false);
  });

  testWidgets('requests sheet', (t) async {
    await shot(t, 'requests', (ar) {
      final hub = hubWith(ar, requests: 2);
      hub.requests = [
        _c(21, ar ? 'خالد سمير' : 'Khaled Samir', ar ? 'السلام عليكم، هل يمكنني السؤال عن موعد الدرس القادم؟' : 'Hello, may I ask when the next lesson is?', minutes: 12),
        _c(22, ar ? 'نور أحمد' : 'Nour Ahmed', ar ? 'أرغب في الانضمام إلى مجموعتك' : 'I would like to join your group', minutes: 300),
      ];
      return ChatRequestsSheet(hub: hub, onOpen: (_) {});
    }, size: const Size(390, 844), lang: 'ar', dark: false);
  });

  testWidgets('empty inbox phone', (t) async {
    await shot(t, 'empty', (ar) {
      final hub = ChatHub.forTest()
        ..api = _Api()
        ..debugSetMyId(_me);
      return ChatListView(hub: hub, onOpen: (_) {}, onNewChat: () {});
    }, size: const Size(390, 844), lang: 'ar', dark: false);
  });
}
