// NB1 written sheets from phone photos (back FLUTTER_API_CHANGES.md 2026-11-12, D-690..D-693): the new scan page
// warnings head "Retake these pages", the two written review codes ask for a new photo with no suggested mark, and a
// key-verified answer says so. Parsers on the documented shapes, read defensively.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_autograde.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('scan page warnings: the cut sides and the missing marks are retakes, in words', () {
    final p = ScanPageInfo.fromJson({
      'id': 4,
      'status': 'processed',
      'file_name': 'IMG_1.jpg',
      'quality_warnings': ['cut_left', 'blurred', 'sheet_marks_missing', null, ''],
      'quality': {
        'sheet': {'found': false, 'frame': false, 'reason': 'marks', 'missing': 2, 'sides': ['left']},
      },
    });
    expect(p.warnings, ['cut_left', 'blurred', 'sheet_marks_missing']);
    expect(p.retakeWarnings, ['cut_left', 'sheet_marks_missing']);
    expect(qualityWarningText('cut_left'), 'Retake: the left side of the sheet is outside the photo');
    for (final w in kRetakeWarnings) {
      expect(qualityWarningText(w), startsWith('Retake: '));
    }
    expect(ScanPageInfo.fromJson({'id': 1, 'quality_warnings': 'cut_top'}).warnings, isEmpty, reason: 'a wrong shape is ignored');
    AppConfig.lang = 'ar';
    expect(qualityWarningText('cut_bottom'), contains('أسفل'));
  });

  test('written review items: page_not_located / box_outside_photo are retakes with no suggested mark', () {
    for (final code in ['page_not_located', 'box_outside_photo']) {
      final it = OmrReviewItem.fromJson({
        'id': 9,
        'kind': 'short_answer',
        'code': code,
        'status': 'open',
        'actions': ['accept', 'set_score'],
        'reading': {'suggested_score': null, 'retake': true, 'text': ''},
        'en': '',
        'ar': '',
        'system_reading': {'unreadable': true, 'partial': 0.4, 'verify': 'floor'},
      });
      expect(it.retake, isTrue);
      expect(it.suggestedScore, isNull);
      expect(it.canAcceptSuggestion, isFalse);
      expect(omrCodeText(code), startsWith('Retake: '));
      expect(it.reason, omrCodeText(code), reason: 'no server sentence: the app\'s own');
    }
    // a stray suggestion beside the code is still never offered
    final odd = OmrReviewItem.fromJson({'id': 1, 'kind': 'completion', 'code': 'box_outside_photo', 'reading': {'suggested_score': 2}});
    expect((odd.retake, odd.suggestedScore), (true, null));
    final normal = OmrReviewItem.fromJson({'id': 2, 'kind': 'short_answer', 'code': 'low_confidence', 'reading': {'suggested_score': 1.5}});
    expect((normal.retake, normal.suggestedScore), (false, 1.5));
  });

  test('a key-verified answer: its tier in words', () {
    final a = AutoGrade.fromJson({'tier': 'key_verified', 'key_verify': {'accept': true, 'margin_ctc': 0.4}})!;
    expect(autoTierText(a.tier), 'Handwriting matched the key');
    expect(autoTierHint(a), isNotEmpty);
    expect(AutoGrade.fromJson({'key_verify': {}}), isNull);
  });
}
