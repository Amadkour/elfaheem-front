import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_taking.dart' show Paper;
import 'package:flutter_education_app/features/shared/exam_engine/exam_taking_screen.dart' show ExamQuestionCard;
import 'package:flutter_education_app/features/shared/exam_engine/offline/offline_exam_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

// A real 1x1 PNG.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
const _id1 = '1111111111111111111111111111111111111111111111111111111111111111.png';
const _id2 = '2222222222222222222222222222222222222222222222222222222222222222.png';

Map<String, dynamic> _content({Map<String, String>? media, List<String>? omitted}) => {
      'package_id': '7.1', 'exam_id': 7, 'title': 'T',
      if (media != null) 'media': media,
      if (omitted != null) 'media_omitted': omitted,
      'paper': {
        'sections': [
          {
            'section_id': 1, 'title': 'A', 'mode': 'online', 'navigation': 'free',
            'questions': [
              {'question_id': 1, 'type': 'true_false', 'points': 1, 'answer': null, 'save_seq': 0,
               'body': {'prompt': 'p1', 'media': [{'id': _id1, 'alt': 'a figure'}]}},
              {'question_id': 2, 'type': 'true_false', 'points': 1, 'answer': null, 'save_seq': 0,
               'body': {'prompt': 'p2', 'media': [{'id': _id2, 'alt': 'a left-out figure'}]}},
            ],
          }
        ],
      },
    };

/// What the server does: AES-256-GCM(K_exam, content), AAD "pkg|<exam>|<n>"; the header carries the SHA-256 of the ciphertext.
Future<OfflinePackage> _seal(Map<String, dynamic> content, List<int> key) async {
  final nonce = List<int>.generate(12, (i) => i);
  final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode(content)), secretKey: SecretKey(key), nonce: nonce, aad: utf8.encode('pkg|7|1'));
  final ct = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  return OfflinePackage.fromJson({
    'package_id': '7.1', 'exam_id': 7, 'n': 1, 'title': 'T', 'questions': 2,
    'hash': dc.sha256.convert(ct).toString(), 'nonce': base64Encode(nonce), 'data': base64Encode(ct),
  });
}

void main() {
  setUp(() => AppConfig.lang = 'en');
  final key = List<int>.generate(32, (i) => 255 - i);

  test('package parse: the images come out of the decrypted package, the omitted ones are listed', () async {
    final p = await _seal(_content(media: {_id1: base64Encode(_png)}, omitted: [_id2]), key);
    expect(p.intact, isTrue);
    final m = PackageMedia.fromContent(await openPackage(p, key));
    expect(m.of(_id1), _png);
    expect(m.isOmitted(_id1), isFalse);
    expect(m.isOmitted(_id2), isTrue);
    expect(m.omitted, {_id2});
  });

  test('an older package (no media keys) and a damaged entry both parse without throwing', () async {
    final old = PackageMedia.fromContent(await openPackage(await _seal(_content(), key), key));
    expect(old.bytes, isEmpty);
    expect(old.isOmitted(_id1), isTrue);
    final bad = PackageMedia.fromContent({'media': {_id1: '%%%not base64%%%'}});
    expect(bad.of(_id1), isNull);
    expect(bad.omitted, {_id1});
  });

  test('at rest the phone holds only ciphertext: the stored file shows no image bytes, and re-reading it still opens', () async {
    final p = await _seal(_content(media: {_id1: base64Encode(_png)}), key);
    final stored = jsonEncode(p.json);             // exactly what OfflineExamStore.savePackage writes
    expect(stored.contains(base64Encode(_png)), isFalse);
    expect(stored.contains('a figure'), isFalse);
    final back = OfflinePackage.fromJson(Map<String, dynamic>.from(jsonDecode(stored) as Map));
    expect(back.intact, isTrue);
    expect(PackageMedia.fromContent(await openPackage(back, key)).of(_id1), _png);
  });

  test('the relay carries the images: a package with ~2 MB of images splits into parts and joins back intact', () async {
    final big = Uint8List.fromList(List<int>.generate(2 * 1024 * 1024, (i) => (i * 31) & 255));
    final p = await _seal(_content(media: {_id1: base64Encode(big)}), key);
    final wire = jsonEncode(p.json);
    final parts = splitParts(wire);
    expect(parts.every((x) => x.length <= kExamPartChars), isTrue);
    expect(parts.length, greaterThan(200));
    final received = OfflinePackage.fromJson(Map<String, dynamic>.from(jsonDecode(parts.join()) as Map));
    expect(received.intact, isTrue);
    expect(received.hash, p.hash);
    expect(PackageMedia.fromContent(await openPackage(received, key)).of(_id1), big);
  });

  testWidgets('the exam card shows an image from bytes, and the alt text when the image was left out (no overflow)', (tester) async {
    final paper = Paper.fromJson(Map<String, dynamic>.from(_content()['paper'] as Map));
    final q1 = paper.all[0], q2 = paper.all[1];
    await expectNoLayoutErrors(tester, () => ExamQuestionCard(question: q1, section: paper.sections[0], enabled: true, onAnswer: (_) {}, imageBytes: _png));
    await expectNoLayoutErrors(tester, () => ExamQuestionCard(question: q2, section: paper.sections[0], enabled: true, onAnswer: (_) {}, imageOmitted: true));

    await tester.pumpWidget(layoutHost(ExamQuestionCard(question: q1, section: paper.sections[0], enabled: true, onAnswer: (_) {}, imageBytes: _png)));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(layoutHost(ExamQuestionCard(question: q2, section: paper.sections[0], enabled: true, onAnswer: (_) {}, imageOmitted: true)));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('a left-out figure'), findsOneWidget);
    // no image data and not omitted (an online card without an attempt): nothing extra is drawn
    await tester.pumpWidget(layoutHost(ExamQuestionCard(question: q1, section: paper.sections[0], enabled: true, onAnswer: (_) {})));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
  });
}
