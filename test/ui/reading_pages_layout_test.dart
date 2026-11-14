// The reading pages (Terms · Privacy · About, D-088) and the inline language switch: the pure body parser, and every
// part at 320x640 and 1400x900, Arabic and English, text 1.3, with no overflow.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_language_switch.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_model.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_parts.dart';
import 'package:flutter_education_app/features/rag/app_assistant.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'باستخدامك لتطبيق NextBrain فإنك توافق على هذه الشروط والأحكام، وعلى سياسة الخصوصية المرفقة بها، '
    'وإذا لم توافق على أي بند يُرجى التوقف عن استخدام التطبيق. By using the app you agree to these terms.';

void main() {
  group('readingBlocks', () {
    test('paragraphs, bullets and numbered steps', () {
      final b = readingBlocks('Intro line\nsecond line\n\n- one\n• two\n1. first\n٢) second\n\nOutro');
      expect(b, const [
        ReadingBlock(ReadingBlockKind.paragraph, 'Intro line\nsecond line'),
        ReadingBlock(ReadingBlockKind.bullet, 'one'),
        ReadingBlock(ReadingBlockKind.bullet, 'two'),
        ReadingBlock(ReadingBlockKind.numbered, 'first', number: '1'),
        ReadingBlock(ReadingBlockKind.numbered, 'second', number: '٢'),
        ReadingBlock(ReadingBlockKind.paragraph, 'Outro'),
      ]);
    });

    test('a number that starts a sentence without a separator stays text; empty input gives nothing', () {
      expect(readingBlocks('10 years or older'), const [ReadingBlock(ReadingBlockKind.paragraph, '10 years or older')]);
      expect(readingBlocks('  \n\r\n '), isEmpty);
      expect(readingBlocks('-'), const [ReadingBlock(ReadingBlockKind.paragraph, '-')]);
    });

    test('reading time is at least a minute, about 200 words a minute', () {
      expect(readingMinutes(const ['']), 1);
      expect(readingMinutes([List.filled(401, 'w').join(' ')]), 3);
    });

    test('section numbers are two-digit labels', () {
      expect(readingNumber(3), '03');
      expect(readingNumber(12), '12');
    });
  });

  test('AppAssistant.ask leaves the question for the pop-up and opens it', () {
    AppAssistant.ask('Explain the privacy policy');
    expect(AppAssistant.draft.value, 'Explain the privacy policy');
    expect(AppAssistant.open.value, isTrue);
    AppAssistant.draft.value = null;
    AppAssistant.open.value = false;
  });

  testWidgets('reading parts never overflow', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          ReadingHero(
            icon: Icons.gavel_rounded,
            title: 'الشروط والأحكام Terms & conditions',
            intro: _long,
            meta: const [
              ReadingMetaPill(icon: Icons.update_rounded, label: 'آخر تحديث 6 أكتوبر 2026 — a long date label'),
              ReadingMetaPill(icon: Icons.tag_rounded, label: 'Version 3.0.0'),
              ReadingMetaPill(icon: Icons.schedule_rounded, label: '3 min read'),
            ],
          ),
          const SizedBox(height: 16),
          ReadingTocChips(titles: const ['قبول الشروط', 'A very long section title that keeps going on', 'Payments'], active: 1, onTap: (_) {}),
          ReadingTocList(
            titles: const ['قبول الشروط', 'A very long section title that keeps going and going', 'Payments'],
            active: 0,
            onTap: (_) {},
            footer: ReadingAskCard(onAsk: () {}, compact: true),
          ),
          const SizedBox(height: 16),
          const ReadingSectionCard(number: 3, icon: Icons.lock_outline_rounded, title: 'البيانات التي نحتفظ بها — The data we keep', body: '$_long\n- bullet $_long\n1. step $_long'),
          const SizedBox(height: 16),
          const ReadingNote(icon: Icons.verified_user_outlined, text: _long, caption: 'Updated 6 October 2026 · Version 3.0.0'),
          const SizedBox(height: 16),
          ReadingAskCard(onAsk: () {}),
          const SizedBox(height: 16),
          Wrap(children: [AskAboutPageChip(onTap: () {}), AskAboutPageChip(onTap: () {}, expanded: false)]),
          AskAboutPageAction(onTap: () {}),
        ]),
      ),
    );
  });

  testWidgets('the skeleton never overflows', (tester) async {
    await expectNoLayoutErrors(tester, () => const ReadingSkeleton());
  });

  testWidgets('about parts never overflow', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const AboutHeroCard(name: 'مركز NextBrain التعليمي المتكامل', tagline: _long, version: '2.4.0 (41)', updateAvailable: true),
          const SizedBox(height: 16),
          const AboutStatsCard(stats: [
            AppStatModel(id: 1, value: '1,000,000+', label: 'طالب مسجّل في المنصة', order: 1),
            AppStatModel(id: 2, value: '50+', label: 'Courses', order: 2),
            AppStatModel(id: 3, value: '66', label: 'Expert teachers across every subject', order: 3),
          ]),
          const SizedBox(height: 16),
          const AboutMissionQuote(mission: _long),
          const SizedBox(height: 16),
          const AboutFeatureGrid(features: [
            AppFeatureModel(id: 1, iconName: 'quiz', title: 'اختبارات ذكية بتصحيح فوري', description: _long, order: 1),
            AppFeatureModel(id: 2, iconName: 'groups', title: 'Live', order: 2),
            AppFeatureModel(id: 3, iconName: 'unknown', title: 'Recorded lessons', description: 'Offline', order: 3),
          ]),
          const SizedBox(height: 16),
          const AboutTeamRow(team: [
            TeamMemberModel(id: 1, name: 'أحمد حمدان عبد الرحمن', role: 'المسؤول المالي والإداري للمنصة', order: 1),
            TeamMemberModel(id: 2, name: 'Sara', role: 'Content', emoji: '🙂', order: 2),
          ]),
          const SizedBox(height: 16),
          AboutSupportCard(
            contacts: const [
              ContactInfoModel(id: 1, type: 'email', value: 'a.very.long.support.address@nextbrain.example.com', order: 1),
              ContactInfoModel(id: 2, type: 'address', value: _long, label: 'العنوان', order: 2),
            ],
            onOpen: (_) {},
            onCopy: (_) {},
            onAsk: () {},
            version: '2.4.0 (41)',
            latest: '2.5.0',
            updateAvailable: true,
            notes: _long,
          ),
        ]),
      ),
    );
  });

  testWidgets('the language switch never overflows and reports the other language', (tester) async {
    final picked = <String>[];
    await expectNoLayoutErrors(
      tester,
      () => Center(child: AppLanguageSegmented(current: AppConfig.lang, onChanged: picked.add)),
      act: (tester) async {
        await tester.tap(find.text(AppConfig.lang == 'ar' ? 'EN' : 'عربي'));
      },
    );
    expect(picked, ['en', 'ar', 'en', 'ar']);
  });
}
