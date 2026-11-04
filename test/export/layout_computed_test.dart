import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/design/export_layout/layout_computed.dart';
import 'package:flutter_education_app/design/export_layout/layout_computed_builder.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/design_engine/computed_parity.json').readAsStringSync()) as Map<String, dynamic>;
  final specs = [for (final s in fx['specs'] as List) LayoutComputedField.fromJson(Map<String, dynamic>.from(s as Map))];
  final rows = [for (final r in fx['rows'] as List) Map<String, Object?>.from(r as Map)];
  final answers = fx['answers'] as List;

  group('parity with the server', () {
    test('every answer equals', () {
      expect(rows.length, answers.length);
      for (var i = 0; i < rows.length; i++) {
        final out = applyComputed(rows[i], specs);
        for (final e in (answers[i] as Map).entries) {
          final got = out[e.key], want = e.value;
          if (want is num && got is num) {
            expect(got.toDouble(), closeTo(want.toDouble(), 1e-9), reason: 'row $i ${e.key}');
          } else {
            expect(got, want, reason: 'row $i ${e.key}');
          }
        }
      }
    });
    test('the source row is not mutated', () {
      final r = Map<String, Object?>.of(rows.first);
      applyComputed(r, specs);
      expect(r.containsKey('calc.result'), isFalse);
    });
  });

  group('unit cases', () {
    LayoutCond c(String f, String op, [Object? v]) => LayoutCond(field: f, op: op, value: v);
    test('nested groups', () {
      final g = LayoutCondGroup(match: 'any', items: [
        c('a', '>', 10),
        LayoutCondGroup(items: [c('b', '=', 'x'), c('d', 'not_empty')]),
      ]);
      expect(groupMatches(g, {'a': 1, 'b': 'X', 'd': 'q'}), isTrue);
      expect(groupMatches(g, {'a': 1, 'b': 'X', 'd': ''}), isFalse);
      expect(groupMatches(g, {'a': '١٢'}), isTrue);
      expect(groupMatches(LayoutCondGroup(), {}), isTrue);
    });
    test('operators', () {
      expect(condMatches(c('n', 'starts_with', 'أح'), {'n': 'أَحْمَد'}), isTrue);
      expect(condMatches(c('n', 'ends_with', 'MAD'), {'n': 'ahmad'}), isFalse);
      expect(condMatches(c('n', 'in', 'a, b'), {'n': 'B'}), isTrue);
      expect(condMatches(c('n', '>', 5), {'n': '1,200'}), isTrue);
      expect(condMatches(c('n', '<', 5), {'n': null}), isFalse);
      expect(condMatches(c('d', '<', '2026-01-01'), {'d': '2025-12-31'}), isTrue);
    });
    test('math: empty, zero, rounding', () {
      final row = <String, Object?>{'a': 1, 'z': 0, 's': 'x'};
      LayoutExpr m(String op, List<LayoutExpr> a) => LayoutExpr(math: op, args: a);
      expect(evaluateExpr(m('/', [LayoutExpr.field('a'), LayoutExpr.field('z')]), row), isNull);
      expect(evaluateExpr(m('+', [LayoutExpr.field('a'), LayoutExpr.field('s')]), row), isNull);
      expect(evaluateExpr(m('+', [LayoutExpr.field('a'), LayoutExpr.number(2)]), row), 3);
      expect(evaluateExpr(m('round', [LayoutExpr.number(2.675), LayoutExpr.number(2)]), row), 2.67);
      expect(evaluateExpr(m('percent', [LayoutExpr.number(1), LayoutExpr.number(3)]), row), closeTo(33.333333, 1e-9));
    });
    test('a later spec reads an earlier one; an earlier cannot read a later', () {
      final specs2 = [
        LayoutComputedField(key: 'calc.b', cases: [], otherwise: LayoutExpr.field('calc.a')),
        LayoutComputedField(key: 'calc.a', otherwise: LayoutExpr.number(5), type: 'number'),
        LayoutComputedField(key: 'calc.c', otherwise: LayoutExpr.field('calc.a'), type: 'number'),
      ];
      final out = applyComputed({}, specs2);
      expect(out['calc.b'], isNull);
      expect(out['calc.c'], 5);
    });
    test('caps and source fields', () {
      expect(computedWithinCaps(specs), isTrue);
      expect(computedWithinCaps([for (var i = 0; i <= kComputedMaxSpecs; i++) LayoutComputedField(key: 'calc.k$i')]), isFalse);
      expect(computedSourceFields(specs), containsAll(['score', 'status', 'first']));
      expect(computedSourceFields(specs).any((k) => k.startsWith('calc.')), isFalse);
    });
    test('JSON round trip', () {
      final back = [for (final s in specs) LayoutComputedField.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>)];
      expect(jsonEncode([for (final s in back) s.toJson()]), jsonEncode([for (final s in specs) s.toJson()]));
    });
  });

  group('presets', () {
    final fields = [
      const LayoutField(key: 'score', labelAr: 'الدرجة', labelEn: 'Score', type: 'number'),
      const LayoutField(key: 'first', labelAr: 'الاسم', labelEn: 'First'),
      const LayoutField(key: 'last', labelAr: 'اللقب', labelEn: 'Last'),
    ];
    test('every preset is a valid spec that evaluates', () {
      for (final p in computedPresets) {
        final s = p.build(fields, 'en', const []);
        expect(LayoutComputedField.keyPattern.hasMatch(s.key), isTrue, reason: p.id);
        expect(computedWithinCaps([s]), isTrue);
        final out = applyComputed({'score': 80, 'first': 'A', 'last': 'B'}, [s]);
        expect(out.containsKey(s.key), isTrue);
      }
    });
    test('pass / fail', () {
      final s = computedPresets.firstWhere((p) => p.id == 'pass_fail').build(fields, 'en', const []);
      expect(applyComputed({'score': 70}, [s])[s.key], 'Pass');
      expect(applyComputed({'score': 20}, [s])[s.key], 'Fail');
    });
    test('keys are unique and ASCII', () {
      final a = computedKeyFor('Result', '', const []);
      final b = computedKeyFor('Result', '', [a]);
      expect(a, 'calc.result');
      expect(b, isNot(a));
      expect(computedKeyFor('', 'النتيجة', const []), matches(RegExp(r'^calc\.[A-Za-z0-9_]+$')));
    });
  });
}
