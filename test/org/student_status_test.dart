// Student lifecycle phase 2 (contract §6): the vocabulary covers every value, the parsers read the §6.2 shapes,
// StatusDraft builds StatusIn and finds the first problem, the preview says what happens, and the student never sees
// a staff-only flag.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/students/student_status_models.dart';
import 'package:flutter_education_app/features/org/students/students_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _statusJson() => {
      'enrol_status': 'enrolled',
      'enrol_since': '2024-09-01',
      'enrol_until': null,
      'acad_standing': 'carrying',
      'standing_hold_until': null,
      'flags': [
        {'key': 'struggling', 'since': '2026-10-01', 'until': null, 'reason': 'Two warnings', 'event_id': 41},
      ],
      'last': {
        'enrolment': {
          'id': 40,
          'user_id': 812,
          'dimension': 'enrolment',
          'from_value': 'suspended',
          'to_value': 'enrolled',
          'via': 'manual',
          'decision_no': 'م ك 12/2026',
          'decision_date': '2026-11-18',
          'effective_from': '2026-11-21',
          'created_at': '2026-11-21T09:30:00',
          'actor': {'id': 44, 'name': 'منى السيد'},
          'title_ar': 'استئناف القيد',
          'title_en': 'Enrolment resumed',
          'can_undo': true,
          'undone': false,
        },
        'standing': null,
      },
      'options': [
        {'decision': 'flag.struggling', 'label_ar': '', 'label_en': '', 'mode': 'decide', 'needs': ['reason'], 'body': null, 'danger': false, 'blocked': null},
        {'decision': 'suspend', 'label_ar': 'إيقاف القيد', 'label_en': 'Suspend enrolment', 'mode': 'propose', 'needs': ['reason', 'decision_no', 'effective_to'], 'body': 'faculty_council', 'danger': false, 'blocked': null},
        {
          'decision': 'dismiss_academic',
          'mode': 'decide',
          'needs': ['decision_no'],
          'body': 'faculty_council',
          'danger': true,
          'blocked': {'rule': 'final_chance_first', 'text_ar': 'يجب منح فرصة أخيرة أولاً', 'text_en': 'A final chance must come first'},
        },
        {'decision': 'standing_override', 'mode': 'decide', 'needs': ['reason'], 'body': 'faculty_council'},
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('every vocabulary value has a label in both languages', () {
    for (final k in decisionKeys) {
      expect(decisionText[k], isNotNull, reason: k);
      expect(decisionTargets[k], isNotNull, reason: k);
    }
    expect(decisionTargets.keys.toSet(), decisionKeys.toSet());
    for (final r in reasonCodes) {
      expect(reasonText[r], isNotNull, reason: r);
    }
    for (final r in dismissReasons) {
      expect(dismissReasonText[r], isNotNull, reason: r);
    }
    for (final b in decisionBodies) {
      expect(bodyText[b], isNotNull, reason: b);
    }
    for (final e in [...decisionText.values, ...reasonText.values, ...dismissReasonText.values, ...bodyText.values]) {
      expect(e.$1.trim(), isNotEmpty);
      expect(e.$2.trim(), isNotEmpty);
    }
    // every enrolment target is a known status, every flag target a stored flag
    for (final tgt in decisionTargets.values) {
      if (tgt.dimension == 'enrolment') expect(enrolStatuses, contains(tgt.to));
      if (tgt.dimension == 'flag') expect(flagKeys, contains(tgt.flag));
    }
    for (final code in ['bad_transition', 'rule_blocks', 'needs_body', 'reason_required', 'decision_no_required', 'dates_required', 'bad_dates', 'not_latest', 'already_reverted', 'status_disabled']) {
      expect(statusCodeTexts()[code], isNotNull, reason: code);
    }
  });

  test('GET status parses flags, the last events and the options', () {
    final s = StudentStatus.fromJson(_statusJson());
    expect(s.enrolStatus, 'enrolled');
    expect(s.enrolSince, DateTime(2024, 9, 1));
    expect(s.acadStanding, 'carrying');
    expect(s.hasFlag('struggling'), isTrue);
    expect(s.flags.single.eventId, 41);
    final last = s.lastEnrolment!;
    expect(last.id, 40);
    expect(last.title, 'Enrolment resumed');
    expect(last.decisionDate, DateTime(2026, 11, 18));
    expect(last.createdAt, isNotNull);
    expect(last.actor!.name, 'منى السيد');
    expect(last.canUndo, isTrue);
    expect(s.lastStanding, isNull);
    expect(s.options, hasLength(4));
    expect(s.optionsOf('enrolment').map((o) => o.decision).toList(), ['suspend', 'dismiss_academic']);
    expect(s.optionsOf('flag').single.label, 'Struggling');
    final dismiss = s.option('dismiss_academic')!;
    expect(dismiss.danger, isTrue);
    expect(dismiss.blocked!.text, 'A final chance must come first');
    expect(dismiss.canOverride, isTrue); // an older server without can_override: whoever decides may try
    final suspend = s.option('suspend')!;
    expect(suspend.proposes, isTrue);
    expect(suspend.canOverride, isFalse);
    expect(suspend.needsDecisionNo, isTrue);
    expect(suspend.needsEffectiveTo, isTrue);
    AppConfig.lang = 'ar';
    expect(suspend.label, 'إيقاف القيد');
  });

  test('a fresh draft flips the flag and starts today', () {
    final s = StudentStatus.fromJson(_statusJson());
    final d = StatusDraft.forOption(s.option('flag.struggling')!, current: s, today: DateTime(2026, 11, 21, 15));
    expect(d.flagOn, isFalse); // the student is marked: the natural change is to remove it
    expect(d.effectiveFrom, DateTime(2026, 11, 21));
    final dis = StatusDraft.forOption(s.option('dismiss_academic')!, current: s);
    expect(dis.reasonCode, isNull); // four dismissal reasons: the caller picks one
    final disc = StatusDraft.forOption(const StatusOption(decision: 'dismiss_disciplinary'), current: s);
    expect(disc.reasonCode, 'disciplinary');
  });

  test('problem() names the first missing value, in the order the form shows it', () {
    final s = StudentStatus.fromJson(_statusJson());
    final o = s.option('suspend')!;
    final d = StatusDraft.forOption(o, current: s, today: DateTime(2026, 11, 21));
    expect(d.problem(o), 'reason_required');
    d.reason = 'Illness, papers attached';
    expect(d.problem(o), 'decision_no_required');
    d.decisionNo = '12/2026';
    expect(d.problem(o), 'decision_no_required'); // the date too
    d.decisionDate = DateTime(2026, 11, 18);
    expect(d.problem(o), 'dates_required');
    d.effectiveTo = DateTime(2026, 11, 1);
    expect(d.problem(o), 'bad_dates');
    d.effectiveTo = DateTime(2027, 9, 1);
    expect(d.problem(o), isNull);
    expect(d.problemText(o), isNull);

    final std = s.option('standing_override')!;
    final sd = StatusDraft.forOption(std, current: s);
    expect(sd.problem(std), 'to_required');
    sd.to = 'regular';
    expect(sd.problem(std), 'reason_required');

    final dis = s.option('dismiss_academic')!;
    final dd = StatusDraft.forOption(dis, current: s)
      ..decisionNo = '1'
      ..decisionDate = DateTime(2026, 11, 20)
      ..override = true;
    expect(dd.problem(dis), 'reason_required'); // no dismissal reason picked
    dd.reasonCode = 'gpa';
    expect(dd.problem(dis), 'reason_required'); // an override always needs the written reason
    dd.reason = 'Council exception';
    expect(dd.problem(dis), isNull);
  });

  test('toJson is StatusIn', () {
    final s = StudentStatus.fromJson(_statusJson());
    final o = s.option('suspend')!;
    final d = StatusDraft.forOption(o, current: s, today: DateTime(2026, 11, 21), source: const StatusSource('complaint', 77))
      ..reasonCode = 'illness'
      ..reason = '  Illness  '
      ..decisionNo = 'م ك 12/2026'
      ..decisionDate = DateTime(2026, 11, 18)
      ..effectiveTo = DateTime(2027, 9, 1)
      ..dropCurrent = true
      ..accessUntil = DateTime(2027, 1, 1);
    final j = d.toJson();
    expect(j['decision'], 'suspend');
    expect(j['to'], 'suspended');
    expect(j['flag_on'], isNull);
    expect(j['reason_code'], 'illness');
    expect(j['reason'], 'Illness');
    expect(j['decision_no'], 'م ك 12/2026');
    expect(j['decision_date'], '2026-11-18');
    expect(j['effective_from'], '2026-11-21');
    expect(j['effective_to'], '2027-09-01');
    expect(j['effects'], {'drop_current': true, 'access_until': null}); // a pause has no access end
    expect(j['source'], {'type': 'complaint', 'id': 77});
    expect(j['override'], isFalse);
    expect(j['attachment_ids'], isEmpty);

    final f = StatusDraft.forOption(s.option('flag.struggling')!, current: s);
    final fj = f.toJson();
    expect(fj['to'], isNull);
    expect(fj['flag_on'], isFalse);
    expect((fj['effects'] as Map)['drop_current'], isFalse);

    final w = StatusDraft(decision: 'withdraw', accessUntil: DateTime(2027, 2, 1));
    expect(w.isFinal, isTrue);
    expect((w.toJson()['effects'] as Map)['access_until'], '2027-02-01');
  });

  test('the preview says what happens in plain words', () {
    final pause = StatusDraft(decision: 'suspend', to: 'suspended', effectiveFrom: DateTime(2026, 11, 21), effectiveTo: DateTime(2027, 9, 1));
    final p = statusPreview(pause);
    expect(p, contains('cannot register new courses'));
    expect(p, contains('courses stay'));
    expect(p, contains('resumes on'));
    expect(statusPreview(pause, proposes: true, body: 'faculty_council'), startsWith('Nothing changes until the faculty council approves.'));
    final back = StatusDraft(decision: 'resume', to: 'enrolled');
    expect(statusPreview(back), contains('register courses again'));
    final mark = StatusDraft(decision: 'flag.special_case', flagOn: true);
    expect(statusPreview(mark), contains('does not see it'));
    final visible = StatusDraft(decision: 'flag.conscripted', flagOn: true);
    expect(statusPreview(visible), contains('sees it'));
    final leave = StatusDraft(decision: 'withdraw', to: 'withdrawn');
    expect(statusPreview(leave), contains('access to the organization ends'));
    AppConfig.lang = 'ar';
    expect(statusPreview(back), contains('تسجيل المقررات'));
  });

  test('results of save, propose and undo', () {
    final r = StatusResult.fromJson({'event': _statusJson()['last']['enrolment'], 'status': _statusJson()});
    expect(r.proposed, isFalse);
    expect(r.event!.id, 40);
    expect(r.status!.enrolStatus, 'enrolled');
    final p = StatusResult.proposedFrom({'decision_id': 9});
    expect(p.proposed, isTrue);
    expect(p.decisionId, 9);
  });

  test('the student never sees a staff-only flag', () {
    final m = MyStatus.fromJson({
      'enrol_status': 'suspended',
      'enrol_until': '2027-09-01',
      'acad_standing': 'warning',
      'flags': ['struggling', 'conscripted', {'key': 'special_case'}, {'key': 'excuse_open'}, 'disciplinary_record'],
      'last': {'title_ar': 'إيقاف القيد', 'title_en': 'Enrolment suspended', 'reason': 'Illness', 'decision_no': '12', 'at': '2026-11-21T09:30:00'},
    });
    expect(m.flags, ['conscripted', 'excuse_open']);
    expect(m.enrolUntil, DateTime(2027, 9, 1));
    expect(m.last!.title, 'Enrolment suspended');
    expect(m.allWell, isFalse);
    final empty = MyStatus.fromJson({});
    expect(empty.isEmpty, isTrue);
    expect(MyStatus.fromJson({'enrol_status': 'enrolled', 'acad_standing': 'regular'}).allWell, isTrue);
  });

  test('settings keep every key and replace one matrix row', () {
    final s = LifecycleSettings.fromJson({
      'decision_matrix': {
        'suspend': {'decide': 'approve', 'body': 'faculty_council', 'decision_no': true},
      },
      'side_effects': {'block_registration': true, 'access_after_leaving_days': 90},
      'future_key': 1,
    });
    expect(s.rule('suspend').body, 'faculty_council');
    expect(s.rule('resume').decide, 'approve');
    final s2 = s.withRule('suspend', s.rule('suspend').copyWith(decide: 'update', body: () => null)).withSection('side_effects', {'access_after_leaving_days': 30});
    expect(s2.rule('suspend').decide, 'update');
    expect(s2.rule('suspend').body, isNull);
    expect(s2.toJson()['future_key'], 1);
    expect(s2.toJson()['side_effects'], {'block_registration': true, 'access_after_leaving_days': 30});
    expect(s.rule('suspend').decide, 'approve'); // the original is untouched
  });

  test('dates in and out', () {
    expect(ymd(DateTime(2026, 1, 5)), '2026-01-05');
    expect(parseYmd('2026-01-05'), DateTime(2026, 1, 5));
    expect(parseYmd('2026-01-05T10:00:00'), DateTime(2026, 1, 5));
    expect(parseYmd(null), isNull);
    expect(parseYmd('soon'), isNull);
  });
}
