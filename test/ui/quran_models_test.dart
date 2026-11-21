// Quran memorization (D-1347): the wire models against the server's shapes (FLUTTER_API_CHANGES, Learning Hub
// phase 6), the juz map from the real meta (test/fixtures/quran_meta.json = back data/learn_seed/quran_meta.json,
// names and counts only), the filters' query and the outbox's same-client_id retry.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/quran/quran_api.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

QuranMeta quranTestMeta() => QuranMeta.fromJson(jsonDecode(File('test/fixtures/quran_meta.json').readAsStringSync()));

class _FakeApi extends QuranApi {
  _FakeApi(this.answer);

  final Object? Function(Map<String, dynamic> body) answer;
  final sent = <Map<String, dynamic>>[];

  @override
  Future<({QuranEntry entry, bool duplicate})> record(Map<String, dynamic> body) async {
    sent.add(body);
    final a = answer(body);
    if (a is Exception) throw a;
    return (entry: QuranEntry.fromJson({'id': 1, ...body}), duplicate: a == true);
  }
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('meta: 114 surahs, 30 juz, 6236 ayahs, juz lookup', () {
    final m = quranTestMeta();
    expect(m.surahs.length, 114);
    expect(m.juz.length, 30);
    expect(m.totalAyahs, 6236);
    expect(m.surah(2)!.ayahs, 286);
    expect(m.juzOf(1, 1), 1);
    expect(m.juzOf(2, 141), 1);
    expect(m.juzOf(2, 142), 2);
    expect(m.juzOf(114, 6), 30);
    // juz 1 = Al-Fatiha + the start of Al-Baqarah; juz 30 = surahs 78 to 114
    expect([for (final s in m.surahsInJuz(1)) s.number], [1, 2]);
    final last = [for (final s in m.surahsInJuz(30)) s.number];
    expect(last.first, 78);
    expect(last.last, 114);
    expect(m.surahsInJuz(31), isEmpty);
  });

  test('teacher list + card', () {
    final l = QuranTeacherList.fromJson({
      'items': [
        {
          'user_id': 7,
          'name': 'Fatima',
          'avatar_url': null,
          'gender': 'f',
          'bio': 'x',
          'ijazah': 'Hafs',
          'goals': ['memorization', 'tajweed'],
          'session_types': ['group'],
          'country_code': 'EG',
          'verified': true,
          'courses': [
            {'id': 3, 'name_ar': 'حلقة', 'name_en': 'Circle', 'fees': 150, 'currency': 'EGP', 'image_url': null, 'delivery_mode': 'online', 'country_code': 'EG'},
          ],
          'gender_ok': false,
        },
      ],
      'total': 1,
      'gender_matching': 'same',
    });
    expect(l.genderMatching, 'same');
    final t = l.items.single;
    expect((t.userId, t.gender, t.verified, t.genderOk), (7, 'f', true, false));
    expect(t.goals, ['memorization', 'tajweed']);
    expect(t.courses.single.name, 'Circle');
    expect(t.courses.single.fees, 150);
    final mine = QuranTeacher.fromJson({'user_id': 9, 'status': null, 'goals': [], 'session_types': [], 'courses': [], 'verified': false});
    expect((mine.status, mine.genderOk, mine.gender), (null, null, null));
  });

  test('filters → query', () {
    expect(QuranFilters.empty.toQuery(), isEmpty);
    const f = QuranFilters(gender: 'm', goal: 'revision', sessionType: 'individual');
    expect(f.toQuery(), {'gender': 'm', 'goal': 'revision', 'session_type': 'individual'});
    expect(f.activeCount, 3);
    expect(f.withGoal(null).toQuery(), {'gender': 'm', 'session_type': 'individual'});
    expect(f.withGoal(null) == const QuranFilters(gender: 'm', sessionType: 'individual'), isTrue);
  });

  test('progress summary', () {
    final p = QuranProgress.fromJson({
      'surahs': [
        {'surah': 1, 'memorized_ayahs': 7, 'total_ayahs': 7},
        {'surah': 2, 'memorized_ayahs': 20, 'total_ayahs': 286},
      ],
      'juz': [for (var j = 1; j <= 30; j++) {'juz': j, 'percent': j == 30 ? 100.0 : (j == 1 ? 18.4 : 0.0)}],
      'recent': [
        {'id': 5, 'student_id': 2, 'teacher_id': 3, 'course_id': null, 'surah': 2, 'from_ayah': 1, 'to_ayah': 20, 'kind': 'memorization',
          'grade': 5, 'note': null, 'client_id': 'abcdefgh', 'recorded_by': 3, 'recorded_at': '2026-11-20T10:00:00'},
      ],
      'memorized_total': 27,
      'total_ayahs': 6236,
    });
    expect(p.surahs[2]!.memorized, 20);
    expect(p.surahsDone, 1);
    expect(p.juzDone, 1);
    expect(p.juz[1], 18.4);
    expect(p.recent.single.ayahCount, 20);
    expect(p.percent, closeTo(0.43, 0.01));
    expect(QuranSettings.fromJson({'module': 'quran', 'values': {'self_log': false, 'gender_matching': 'prefer'}}).selfLog, isFalse);
    expect(QuranSettings.fromJson(const {}).selfLog, isTrue);
  });

  test('booking refusals are bilingual (apiErrorText, shown by the course checkout)', () {
    ApiException e(String code, [Map<String, dynamic> extra = const {}]) =>
        ApiException(statusCode: 403, type: ApiErrorType.forbidden, message: 'x', code: code, body: {
          'detail': {'code': code, ...extra}
        });
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      final differs = apiErrorText(e('quran_gender_rule', {'reason': 'gender_differs'}));
      final unknown = apiErrorText(e('quran_gender_rule', {'reason': 'gender_unknown'}));
      final unverified = apiErrorText(e('quran_teacher_unverified'));
      expect({differs, unknown, unverified}.length, 3);
      expect(differs, isNot('x'));
      expect(unverified, isNot('x'));
    }
    AppConfig.lang = 'en';
    expect(quranCodeText('quran_bad_range', {'ayahs': 7}), contains('7'));
  });

  test('outbox: a network failure keeps the entry, the retry sends the same client_id once', () async {
    SharedPreferences.setMockInitialValues({});
    QuranOutbox.prefs = SharedPreferences.getInstance;
    QuranOutbox.userId = () async => '42';
    final body = {'client_id': newQuranClientId(), 'surah': 1, 'from_ayah': 1, 'to_ayah': 7, 'kind': 'memorization'};
    await QuranOutbox.add(body);
    await QuranOutbox.add(body); // the same entry twice is kept once
    expect((await QuranOutbox.pending()).length, 1);

    final offline = _FakeApi((_) => ApiException(statusCode: 0, type: ApiErrorType.network, message: 'offline'));
    expect((await QuranOutbox.flush(offline)).sent, 0);
    expect((await QuranOutbox.pending()).length, 1);

    final online = _FakeApi((_) => true);
    final r = await QuranOutbox.flush(online);
    expect(r.sent, 1);
    expect(online.sent.single['client_id'], body['client_id']);
    expect(await QuranOutbox.pending(), isEmpty);

    // a refusal (the server answered) leaves the box too, with its text
    await QuranOutbox.add({...body, 'client_id': newQuranClientId()});
    final refuse = _FakeApi((_) => ApiException(statusCode: 403, type: ApiErrorType.forbidden, message: 'x', code: 'quran_self_log_off'));
    final x = await QuranOutbox.flush(refuse);
    expect(x.refused.single, contains('Logging your own progress is off'));
    expect(await QuranOutbox.pending(), isEmpty);
    expect(newQuranClientId().length, inInclusiveRange(8, 36));
  });
}
