// Layout smoke for the chat sessions widgets (lib/features/rag/rag_chat_sessions.dart, rag_chat_screen.dart):
// the conversations panel and its rows (current, long titles, no meta), the empty panel with the retention notice,
// the empty chat with the New chat button (no retention banner there), the thumbs-down comment sheet, the rename
// dialog, and an answer card with a curated source and its deep link — at 320x640 and 1400x900, Arabic and
// English, textScaler 1.3.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/rag/rag_chat.dart';
import 'package:flutter_education_app/features/rag/rag_chat_screen.dart';
import 'package:flutter_education_app/features/rag/rag_learning.dart' show RagDownVote;
import 'package:flutter_education_app/features/rag/chat/rag_chat_parts.dart' show RagSourceChip;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'كيف أحمّل محاضرة مسجلة كاملة لمشاهدتها لاحقاً بلا اتصال بالإنترنت من داخل التطبيق على هاتفي؟';
const _longEn = 'How do I download a whole recorded lecture so that I can watch it later without an internet connection?';

final _now = DateTime.utc(2026, 10, 28, 12);

List<RagConversation> _items() => [
      RagConversation(id: 1, title: _longEn, app: true, lastAt: _now.subtract(const Duration(minutes: 3)), turns: 12),
      RagConversation(id: 2, title: _longAr, app: true, lastAt: _now.subtract(const Duration(hours: 5)), turns: 1),
      RagConversation(id: 3, title: 'Fees', app: true, lastAt: _now.subtract(const Duration(days: 3)), turns: 2),
      const RagConversation(id: 4, title: '', app: true),
    ];

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('the conversations panel: rows with a current one, menus, the retention notice', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => RagSessionsPanel(
            items: _items(),
            currentId: 2,
            retentionDays: 90,
            now: _now,
            onOpen: (_) {},
            onNew: () {},
            onRename: (_) {},
            onDelete: (_) {},
            onClose: () {}));
  });

  testWidgets('the panel inside a 300 px side column, and empty, and loading', (tester) async {
    await expectNoLayoutErrors(
        tester, () => Align(alignment: AlignmentDirectional.centerStart, child: SizedBox(width: 300, child: RagSessionsPanel(items: _items(), now: _now, onOpen: (_) {}, onNew: () {}))));
    await expectNoLayoutErrors(tester, () => RagSessionsPanel(items: const [], retentionDays: 30, onOpen: (_) {}, onNew: () {}));
    await expectNoLayoutErrors(tester, () => RagSessionsPanel(items: const [], loading: true, onOpen: (_) {}, onNew: () {}));
  });

  testWidgets('a row: long title, no meta, without a menu', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => Column(children: [
              RagSessionRow(item: _items()[1], onTap: () {}, current: true, now: _now, onRename: () {}, onDelete: () {}),
              RagSessionRow(item: _items()[3], onTap: () {}),
            ]));
  });

  testWidgets('the row menu opens on the overflow button and on a long press', (tester) async {
    var renamed = 0;
    await expectNoLayoutErrors(
        tester,
        () => RagSessionRow(item: _items()[0], onTap: () {}, now: _now, onRename: () => renamed++, onDelete: () {}),
        act: (tester) async {
          await tester.tap(find.byIcon(Icons.more_vert_rounded));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
          await tester.tap(find.byIcon(Icons.edit_outlined));
          await tester.pumpAndSettle();
          // and from a long press
          await tester.longPress(find.byType(RagSessionRow));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
          await tester.tap(find.byIcon(Icons.edit_outlined));
          await tester.pumpAndSettle();
        });
    expect(renamed, 8); // twice per size × language
  });

  // the empty chat shows no retention banner (it read as "this new chat gets deleted"); the Chats panel keeps it
  testWidgets('the empty chat: starter prompts with New chat and Chats', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(12), children: [
              RagStarterPrompts(context_: RagContext.org, onPick: (_) {}, onNewChat: () {}, onChats: () {}),
            ]));
    await expectNoLayoutErrors(tester, () => ListView(children: [RagStarterPrompts(context_: RagContext.app, onPick: (_) {}, compact: true, onNewChat: () {})]));
  });

  testWidgets('the thumbs-down comment sheet body, and the rename dialog', (tester) async {
    await expectNoLayoutErrors(tester, () => const Align(alignment: Alignment.bottomCenter, child: RagRatingCommentSheet()));
    await expectNoLayoutErrors(tester, () => const Align(alignment: Alignment.bottomCenter, child: RagRatingCommentSheet(reasons: false)));
    await expectNoLayoutErrors(tester, () => RagRenameDialog(title: _longEn), scaffold: false);
  });

  testWidgets('the comment sheet pops the typed comment, Skip pops an empty one (Track F: with the picked reason)', (tester) async {
    AppConfig.lang = 'en';
    RagDownVote? got;
    await tester.pumpWidget(layoutHost(Builder(builder: (context) => Center(
        child: FilledButton(
            onPressed: () async => got = await showAppSheet<RagDownVote>(context, (_) => const RagRatingCommentSheet()),
            child: const Text('rate'))))));
    await tester.tap(find.text('rate'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'The article number is wrong');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(got, const RagDownVote(comment: 'The article number is wrong'));
    await tester.tap(find.text('rate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outdated'));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(got, const RagDownVote(reason: 'outdated'));
  });

  testWidgets('an answer from the curated Q&A: the qa source with its Open link, and the qa stage while pending', (tester) async {
    final done = RagAnswer.fromJson({
      'id': 3, 'state': 'done', 'question': _longAr, 'found': true, 'answer': 'افتح المحاضرة ثم اضغط «تنزيل». [1]', 'generator': 'qa',
      'conversation_id': 7,
      'citations': [
        {'n': 1, 'document_id': 0, 'title': _longEn, 'kind': 'qa', 'quote': 'Open the lecture and tap Download.', 'deep_link': '/downloads'},
      ],
    });
    final pending = RagAnswer.fromJson({'id': 4, 'state': 'running', 'stage': 'qa', 'question': 'q', 'answer': ''});
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(child: Column(children: [RagAnswerCard(answer: done, onRate: (_) {}, onNavigate: () {}), RagAnswerCard(answer: pending)])),
        act: (tester) async {
          await tester.tap(find.byType(RagSourceChip).first);
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
        });
  });
}
