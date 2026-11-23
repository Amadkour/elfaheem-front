// Games v4 T65: the content bank, the editors, the pickers and the reciter cards lay out at 320 and 1400 px,
// ar + en, textScaler 1.3 (expectNoLayoutErrors); sacred text stays read-only; a body edit is a whole new map.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/bank_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/item_editor.dart';
import 'package:flutter_education_app/features/games/admin/v4/hadith_picker.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/quran_picker.dart';
import 'package:flutter_education_app/features/games/admin/v4/reciters_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

final _subjects = <Json>[
  {'id': 1, 'key': 'quran', 'name_ar': 'القرآن', 'name_en': 'Quran', 'sacred': true},
  {'id': 2, 'key': 'math', 'name_ar': 'رياضيات', 'name_en': 'Math', 'sacred': false},
];

Json _item(String type, {int subject = 2}) => {...defaultItem(type, subjectId: subject), 'id': 7, 'prompt': {'ar': 'سؤال طويل جداً لاختبار التفاف النص في الشاشات الضيقة', 'en': 'A long question to test wrapping on narrow screens'}};

void main() {
  for (final type in kItemTypes) {
    testWidgets('editor $type: no layout errors', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.md),
            child: ItemEditorForm(item: _item(type), subjects: _subjects, onChanged: (_) {}, onPickQuran: () {}, onPickHadith: () {}),
          ));
    });
  }

  testWidgets('sacred sequence: tokens are a read-only reference, never a text field', (tester) async {
    final item = {
      ..._item('sequence', subject: 1),
      'body': {'mode': 'order', 'unit': 'word', 'tokens': '@quran:112:1', 'distractors': 2},
      'source': {'kind': 'quran', 'ref': '112:1'},
    };
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
      child: ItemEditorForm(item: item, subjects: _subjects, onChanged: (_) {}, onPickQuran: () {}, onPickHadith: () {}),
    )));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('@quran:112:1'), findsWidgets);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mcq editor: adding an option emits a new body', (tester) async {
    Json? out;
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
      child: ItemEditorForm(item: _item('mcq'), subjects: _subjects, onChanged: (v) => out = v, onPickQuran: () {}, onPickHadith: () {}),
    )));
    await tester.pump(const Duration(milliseconds: 200));
    final add = find.byIcon(Icons.add_rounded).first;
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pump();
    expect((jlistOf(out!['body'], 'options')).length, 3);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('bank: rows, filters, bulk bar, empty', (tester) async {
    final items = [for (var i = 1; i <= 3; i++) {..._item(kItemTypes[i]), 'id': i, 'status': kItemStatuses[i], 'topic': 'topic $i'}];
    await expectNoLayoutErrors(tester, () => BankBody(
          items: items,
          subjects: _subjects,
          filters: const BankFilters(),
          selected: const {1, 2},
          onFilters: (_) {},
          onToggle: (_) {},
          onSelectAll: (_) {},
          onOpen: (_) {},
          onDelete: (_) {},
          onBulkEdit: () {},
          onBulkDelete: () {},
        ));
    await expectNoLayoutErrors(tester, () => BankBody(
          items: const [],
          subjects: _subjects,
          filters: const BankFilters(q: 'x'),
          selected: const {},
          onFilters: (_) {},
          onToggle: (_) {},
          onSelectAll: (_) {},
          onOpen: (_) {},
          onDelete: (_) {},
          onBulkEdit: () {},
          onBulkDelete: () {},
        ));
  });

  testWidgets('quran picker view: no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          child: QuranPickerView(
            surahs: [for (var i = 1; i <= 114; i++) {'number': i, 'name_ar': 'سورة $i', 'name_en': 'Surah $i', 'ayat': 7}],
            reciters: const [{'key': 'alafasy', 'name_ar': 'مشاري العفاسي', 'name_en': 'Mishary Alafasy'}],
            surah: 1,
            from: 1,
            to: 2,
            reciter: 'alafasy',
            ayat: const [
              {'surah': 1, 'ayah': 1, 'text': 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ', 'audio': {'url': 'x'}},
              {'surah': 1, 'ayah': 2, 'text': 'ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ', 'audio': null},
            ],
            onSurah: (_) {},
            onFrom: (_) {},
            onTo: (_) {},
            onReciter: (_) {},
            onPlay: (_) {},
            onUse: () {},
          ),
        ));
  });

  testWidgets('hadith picker view: source, grade, matn', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          child: HadithPickerView(
            items: const [
              {'id': 1, 'collection': 'bukhari', 'number': 1, 'book': 'بدء الوحي', 'chapter': 'كيف كان بدء الوحي', 'text_ar': 'إنما الأعمال بالنيات وإنما لكل امرئ ما نوى', 'word_count': 8, 'matn_from': null, 'matn_to': null, 'grade': 'صحيح', 'grade_source': 'Sahih al-Bukhari'},
            ],
            total: 1,
            collection: null,
            number: null,
            onCollection: (_) {},
            onNumber: (_) {},
            onSearch: (_) {},
            onMatn: (_, _, _) {},
            onUse: (_) {},
          ),
        ));
  });

  testWidgets('reciters: licence + permission cards', (tester) async {
    final items = <Json>[
      {'key': 'alafasy', 'name_ar': 'مشاري العفاسي', 'name_en': 'Mishary Alafasy', 'riwayah': 'hafs', 'audience': 'all', 'enabled': true, 'is_default': true, 'licence': 'Free for non-commercial use with credit', 'permission_status': 'verified', 'permission_note': 'Email 2026-11-01', 'source_url': 'https://everyayah.com', 'coverage': {'surahs': 114, 'of': 114}, 'sample': {'url': 'https://x/1.mp3'}},
      {'key': 'mukhtar', 'name_ar': 'مختار الحاج', 'name_en': 'Mukhtar Al-Haj', 'audience': 'all', 'enabled': false, 'is_default': false, 'licence': '', 'permission_status': 'pending', 'coverage': {'surahs': 0, 'of': 114}},
    ];
    await expectNoLayoutErrors(tester, () => RecitersBody(items: items, onChange: (_, _) {}));
  });
}

List<Json> jlistOf(Object? body, String k) => [for (final x in (body as Map)[k] as List) Map<String, dynamic>.from(x as Map)];
