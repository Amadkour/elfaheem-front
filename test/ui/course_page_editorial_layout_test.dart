// The Warm Editorial pieces of the course page (D-610 – D-629) at 320×640 and 1400×900, ar / en, textScaler 1.3:
// the hero over a cover (full bleed with the block overlapping it on phones, framed beside the title on desktop),
// the progress bar, a session row whose materials unfold, and the price / discount / private marks.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/course/course_price_tag.dart';
import 'package:flutter_education_app/features/shared/course/course_space/course_space.dart';
import 'package:flutter_education_app/features/shared/course/private_flag.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'مقدمة شاملة جداً في الذكاء الاصطناعي وتعلم الآلة للمبتدئين والمحترفين A complete introduction';

CourseSpaceHeroData _hero() => CourseSpaceHeroData(
  title: _long,
  subtitle: '$_long $_long',
  category: 'البرمجة وعلوم الحاسب',
  isPrivate: true,
  badges: const [CourseSpaceBadge(label: 'مسودة Draft', icon: Icons.edit_note_rounded, color: Color(0xFFB7791F))],
  teacherName: 'د. عبد الرحمن محمد عبد الله الحسيني Dr. Abdelrahman',
  onTeacher: () {},
  stats: const [
    CourseSpaceStat(icon: Icons.groups_rounded, value: '12,480', label: 'طالب Students'),
    CourseSpaceStat(icon: Icons.play_circle_outline_rounded, value: '148', label: 'درس Lessons'),
    CourseSpaceStat(icon: Icons.schedule_rounded, value: '96.5', label: 'ساعة Hours'),
    CourseSpaceStat(icon: Icons.sell_rounded, value: '1,250 EGP', label: 'السعر Price'),
  ],
  progress: 0.42,
  progressLabel: 'تقدّمك Your progress',
);

CourseSpaceTab _tab(String id) =>
    CourseSpaceTab(id: id, label: 'الجلسات Sessions $id', icon: Icons.play_lesson_rounded, count: 12, builder: (_) => const SizedBox(height: 200));

void main() {
  testWidgets('hero over a cover: phone overlap and desktop frame', (t) async {
    await expectNoLayoutErrors(
      t,
      () => CourseSpace(
        hero: _hero(),
        heroBackground: const ColoredBox(color: Color(0xFF3E6B58)),
        onBack: () {},
        topActions: [
          CourseSpaceTopAction(icon: Icons.ios_share_rounded, tooltip: 'share', onTap: () {}),
          CourseSpaceTopAction(icon: Icons.edit_rounded, tooltip: 'تعديل الكورس Edit course', primary: true, onTap: () {}),
          CourseSpaceTopAction(icon: Icons.refresh_rounded, tooltip: 'refresh', overflow: true, onTap: () {}),
        ],
        spotlight: [
          CourseSpotlightCard(icon: Icons.play_circle_fill_rounded, title: _long, subtitle: _long, progress: 0.3, actionLabel: 'تابع Resume', onAction: () {}),
        ],
        tabs: [_tab('a'), _tab('b'), _tab('c')],
        activeTab: 'a',
        onTab: (_) {},
      ),
    );
  });

  testWidgets('a session row opens and closes its materials without a layout error', (t) async {
    var open = true;
    await expectNoLayoutErrors(
      t,
      () => StatefulBuilder(
        builder: (context, set) => SingleChildScrollView(
          child: CourseSessionsSurface(
            child: CourseSessionTile(
              data: const CourseSessionView(
                number: 6,
                title: _long,
                state: CourseSessionState.next,
                durationMinutes: 95,
                materials: 5,
                materialsDone: 2,
                showProgress: true,
              ),
              rail: (top: CourseRailTone.done, bottom: CourseRailTone.plain),
              trailing: CourseSessionChevron(open: open),
              onTap: () => set(() => open = !open),
              below: CourseSessionAction(label: 'تابع المشاهدة Continue watching', icon: Icons.play_arrow_rounded, filled: true, onTap: () {}),
              panel: open ? const CourseSessionPanel(child: SizedBox(height: 80)) : null,
            ),
          ),
        ),
      ),
      act: (t) async {
        await t.tap(find.byType(InkWell).first);
        await t.pumpAndSettle();
      },
    );
  });

  testWidgets('price, discount and private marks flex instead of clipping', (t) async {
    await expectNoLayoutErrors(
      t,
      () => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          CoursePriceTag(originalPrice: 1250, finalPrice: 990, discountActive: true, format: (v) => '${v.round()} EGP'),
          CoursePriceTag(originalPrice: 0, finalPrice: 0, discountActive: false, format: (v) => 'مجاني Free'),
          const DiscountRibbon(percentage: 35),
          const SizedBox(width: 120, child: PrivateFlag(label: 'خاص — للمسجلين فقط Private, enrolled only')),
          const SizedBox(width: 280, child: CourseProgressBar(value: 0.6)),
        ],
      ),
    );
  });
}
