// Layout smoke for the assistant's draft answer (Track E.8, lib/features/rag/rag_chat_screen.dart): the
// pending card with the stage trail and a long draft (Arabic and English), the draft widget alone, the same under
// reduced motion (steady caret), and the swap to the final answer — at 320x640 and 1400x900, Arabic and English,
// textScaler 1.3.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/rag/rag_chat.dart';
import 'package:flutter_education_app/features/rag/rag_chat_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _draftAr = 'يمكنك استخدام حسابك على جهازين في الوقت نفسه، وإذا أردت إضافة جهاز ثالث فعليك أولاً إزالة أحد الجهازين '
    'من صفحة الأجهزة في الإعدادات ثم تسجيل الدخول من الجهاز الجديد';
const _draftEn = 'You can use your account on two devices at the same time; to add a third one, first remove one of the two '
    'from the Devices page in Settings, then sign in on the new device';

RagAnswer _answer({String state = 'running', String? partial, String answer = ''}) => RagAnswer.fromJson({
      'id': 3,
      'state': state,
      'stage': state == 'running' ? 'write' : null,
      'question': 'كم جهازاً يمكنني استخدامه بحساب واحد في الوقت نفسه؟',
      'found': state == 'done' ? true : null,
      'answer': answer,
      'citations': state == 'done'
          ? [
              {'n': 1, 'document_id': 4, 'title': 'Terms and conditions', 'section': 'Devices', 'quote': _draftEn}
            ]
          : const [],
      'generator': state == 'done' ? 'llm:qwen3-0.6b' : null,
      'app': true,
      'answer_partial': partial,
    });

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('the pending card with a long draft under the stage trail', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: RagAnswerCard(answer: _answer(partial: _draftAr))));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: RagAnswerCard(answer: _answer(partial: _draftEn))));
    expect(find.byType(RagPartialAnswer), findsNothing); // the harness unmounts at the end
  });

  testWidgets('the draft alone, a very long unbroken word, and under reduced motion', (tester) async {
    await expectNoLayoutErrors(tester, () => const RagPartialAnswer(text: _draftEn));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: RagPartialAnswer(text: 'x' * 400))); // in the chat list
    await expectNoLayoutErrors(
        tester,
        () => Builder(
            builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true), child: const RagPartialAnswer(text: _draftAr))));
  });

  testWidgets('a draft is shown while running and the final answer replaces it', (tester) async {
    await tester.pumpWidget(layoutHost(RagAnswerCard(answer: _answer(partial: _draftEn))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RagPartialAnswer), findsOneWidget);
    expect(find.byType(RagStageTrail), findsOneWidget);

    await tester.pumpWidget(layoutHost(RagAnswerCard(answer: _answer())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RagPartialAnswer), findsNothing); // retracted / not yet: the stage trail alone
    expect(find.byType(RagStageTrail), findsOneWidget);

    await tester.pumpWidget(layoutHost(RagAnswerCard(answer: _answer(state: 'done', partial: _draftEn, answer: '$_draftEn. [1]'))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RagPartialAnswer), findsNothing);
    expect(find.byType(RagStageTrail), findsNothing);
    expect(find.byType(RagAnswerBody), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion: the caret does not blink', (tester) async {
    await tester.pumpWidget(layoutHost(Builder(
        builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true), child: const RagPartialAnswer(text: _draftEn)))));
    await tester.pump();
    final fade = tester.widget<FadeTransition>(find.descendant(of: find.byType(RagPartialAnswer), matching: find.byType(FadeTransition)));
    expect(fade.opacity.value, 1.0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(fade.opacity.value, 1.0);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
