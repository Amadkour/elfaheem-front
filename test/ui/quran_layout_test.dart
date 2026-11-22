// Quran memorization's screens (D-1347) on a phone and a wide window, ar / en, text 1.3: the teacher list with its
// filters, the teacher card, progress by surah and juz, the record sheet and the teacher's card editor.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:flutter_education_app/features/quran/quran_progress.dart';
import 'package:flutter_education_app/features/quran/quran_record_sheet.dart';
import 'package:flutter_education_app/features/quran/quran_tab.dart';
import 'package:flutter_education_app/features/quran/quran_teacher_hub.dart';
import 'package:flutter_education_app/features/quran/quran_teacher_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';
import 'quran_models_test.dart' show quranTestMeta;

QuranTeacher _teacher(int id, {bool? genderOk, bool courses = true}) => QuranTeacher.fromJson({
      'user_id': id,
      'name': id.isEven ? 'الشيخة فاطمة عبد الرحمن محمد الأنصاري الحافظة' : 'Sheikh Abdullah ibn Mohammed Al-Qahtani the reciter',
      'gender': id.isEven ? 'f' : 'm',
      'bio': 'معلمة قرآن منذ خمس عشرة سنة، أحفّظ بالتكرار والربط بين الآيات وأتابع كل طالبة أسبوعياً. ' * 4,
      'ijazah': 'إجازة برواية حفص عن عاصم بالسند المتصل، وإجازة في الشاطبية والجزرية',
      'goals': ['memorization', 'tajweed', 'revision'],
      'session_types': ['individual', 'group'],
      'country_code': 'EG',
      'verified': id % 3 == 0,
      'courses': courses
          ? [
              for (var c = 1; c <= 2; c++)
                {
                  'id': id * 10 + c,
                  'name_ar': 'حلقة تحفيظ جزء عم للمبتدئين مع التجويد والمراجعة الأسبوعية',
                  'name_en': 'Juz Amma memorization circle for beginners with tajweed and a weekly revision',
                  'fees': c == 1 ? 0 : 12345.5,
                  'currency': 'EGP',
                  'delivery_mode': c == 1 ? 'online' : 'both',
                },
            ]
          : [],
      'gender_ok': genderOk,
    });

final _progress = QuranProgress.fromJson({
  'surahs': [
    {'surah': 1, 'memorized_ayahs': 7, 'total_ayahs': 7},
    {'surah': 2, 'memorized_ayahs': 141, 'total_ayahs': 286},
    for (var s = 78; s <= 114; s++) {'surah': s, 'memorized_ayahs': s.isEven ? 3 : 5, 'total_ayahs': 40},
  ],
  'juz': [for (var j = 1; j <= 30; j++) {'juz': j, 'percent': j == 1 ? 100.0 : (j == 30 ? 37.5 : (j == 2 ? 2.4 : 0.0))}],
  'recent': [
    for (var i = 0; i < 3; i++)
      {
        'id': i,
        'surah': 2,
        'from_ayah': 100 + i,
        'to_ayah': 141,
        'kind': quranKinds[i],
        'grade': i + 3,
        'note': 'أحسنت في المدود، راجع أحكام النون الساكنة والتنوين قبل الحصة القادمة ' * 2,
        'client_id': 'abcdefgh$i',
        'recorded_at': '2026-11-20T10:00:00',
      },
  ],
  'memorized_total': 300,
  'total_ayahs': 6236,
});

void main() {
  final meta = quranTestMeta();
  final teachers = [for (var i = 1; i <= 4; i++) _teacher(i, genderOk: i == 2 ? false : true)];

  testWidgets('teacher list', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => QuranBrowseView(
        filters: const QuranFilters(gender: 'f', goal: 'memorization', sessionType: 'individual'),
        onFilters: (_) {},
        items: teachers,
        total: 4,
        genderMatching: 'same',
        onProgress: () {},
      ),
    );
  });

  testWidgets('teacher list: empty, loading, error', (tester) async {
    for (final v in [
      QuranBrowseView(filters: const QuranFilters(goal: 'tajweed'), onFilters: (_) {}, items: const [], total: 0),
      QuranBrowseView(filters: QuranFilters.empty, onFilters: (_) {}, items: const [], loading: true),
      QuranBrowseView(filters: QuranFilters.empty, onFilters: (_) {}, items: const [], error: 'No connection'),
    ]) {
      await expectNoLayoutErrors(tester, () => v);
    }
  });

  testWidgets('filter sheet', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => QuranFilterBar(value: const QuranFilters(goal: 'revision'), resultCount: 12, onChanged: (_) {}),
      act: (tester) async {
        final open = find.byKey(const ValueKey('quran_filters.open'));
        if (open.evaluate().isNotEmpty) await tester.tap(open);
      },
    );
  });

  testWidgets('teacher card', (tester) async {
    await expectNoLayoutErrors(tester, () => QuranTeacherView(teacher: _teacher(3), genderOk: true, onBook: (_) {}));
    await expectNoLayoutErrors(tester, () => QuranTeacherView(teacher: _teacher(2, courses: false), genderOk: false));
  });

  testWidgets('progress by surah and juz', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => QuranProgressView(meta: meta, progress: _progress, onRecord: () {}),
      act: (tester) async {
        await _tapVisible(tester, const ValueKey('quran.juz.30'));
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => QuranProgressView(meta: meta, progress: const QuranProgress(), mine: false),
      act: (tester) async {
        await _tapVisible(tester, const ValueKey('quran.surahs.all'));
      },
    );
  });

  testWidgets('record sheet', (tester) async {
    Future<String?> submit(Map<String, dynamic> _) async => 'This student is not enrolled in one of your courses';
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: QuranRecordForm(
          meta: meta,
          courses: teachers.first.courses,
          loadStudents: (_) async => [(id: 1, name: 'Abdelrahman Mohamed Abdelaziz El-Sayed', imageUrl: null)],
          onSubmit: submit,
        ),
      ),
      act: (tester) async {
        await _tapVisible(tester, const ValueKey('quran.record.save'));
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: QuranRecordForm(meta: meta, selfLog: true, initialSurah: 2, onSubmit: submit),
      ),
    );
  });

  testWidgets('teacher card editor', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: QuranCardForm(
          initial: QuranTeacher.fromJson({'user_id': 1, 'status': null, 'goals': [], 'session_types': [], 'courses': []}),
          countries: const [('EG', 'جمهورية مصر العربية'), ('SA', 'المملكة العربية السعودية')],
          onSave: (_) async => 'A value on the card is not accepted. Check the choices.',
        ),
      ),
      act: (tester) async {
        await _tapVisible(tester, const ValueKey('quran.card.draft'));
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: QuranCardForm(
          initial: QuranTeacher.fromJson({...{'status': 'pending', 'verified': true}, 'user_id': 2, 'gender': 'm', 'country_code': 'KW',
            'goals': ['tajweed'], 'session_types': ['group'], 'courses': []}),
          locked: true,
          onSave: (_) async => null,
        ),
      ),
    );
  });
}

/// Scrolls the first scrollable until [key] is built and on screen, then taps it.
Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final f = find.byKey(key);
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await tester.tap(f);
}
