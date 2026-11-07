// Academic Advising, Phase 3 (docs/advising/PHASE3.md): settings, advisors and their profiles, conflicts, students and
// manual assignment, distribution, handovers. The answers parse (and an older server that leaves keys out still
// parses), the drafts build the WHOLE-object bodies the PUTs expect, the settings inheritance hints, the plan request,
// and every new server code has a text in both languages. The sample payloads are shared with
// test/ui/adv_assign_layout_test.dart and test/visual/adv_assign_golden_test.dart.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/advising/adv_config_page.dart' show advScopeKey, advScopeOfKey, advPolicyValueText;
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_texts.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _policy({int maxLoad = 40, String strategy = 'balanced', String mode = 'single'}) => {
      'eligible_roles': ['teacher'],
      'eligible_ranks': <String>[],
      'mode': mode,
      'max_load': maxLoad,
      'warn_pct': 80,
      'strategy': strategy,
      'auto_assign': true,
      'digest': 'off',
      'sla_hours': {'low': 120, 'normal': 72, 'high': 24, 'urgent': 4},
      'nudge_days': [3, 7],
      'retention_months': 24,
      'records_retention_months': 84,
      'survey': true,
      'workflow_steps': ['director_review'],
    };

/// `GET …/advising/policy` of a faculty that sets its own maximum and has one department override.
Map<String, dynamic> sampleAdvPolicyJson({bool multi = false}) => {
      'effective': _policy(maxLoad: 35, mode: multi ? 'multi' : 'single'),
      'defaults': _policy(),
      'org': {
        'id': 3,
        'settings': {'max_load': 35, if (multi) 'mode': 'multi', 'digest': 'weekly'},
        'updated_at': '2026-10-30T09:15:00',
      },
      'scopes': [
        {
          'id': 8,
          'scope_type': 'dept',
          'scope_ref': '21',
          'label': 'علوم الحاسب',
          'label_en': 'Computer Science',
          'settings': {'max_load': 25, 'strategy': 'department'},
          'updated_at': '2026-11-01T12:00:00',
        },
      ],
      'options': {
        'roles': [
          {'key': 'teacher', 'label_ar': 'عضو هيئة التدريس', 'label_en': 'Faculty member'},
          {'key': 'teacher_assistant', 'label_ar': 'الهيئة المعاونة', 'label_en': 'Teaching assistant'},
        ],
        'ranks': [
          for (final r in advRanks) {'key': r, 'label_ar': '', 'label_en': ''},
        ],
        'strategies': [
          for (final s in advStrategies) {'key': s, 'label_ar': '', 'label_en': ''},
        ],
        'depts': [
          {'id': 21, 'name': 'علوم الحاسب', 'name_en': 'Computer Science'},
          {'id': 22, 'name': 'نظم المعلومات', 'name_en': 'Information Systems'},
        ],
        'programs': [
          {'id': 4, 'name': 'Software Engineering (Credit hours)'},
        ],
        'levels': ['1', '2', '3', '4'],
        'cohorts': ['2023', '2024', '2025'],
      },
    };

Map<String, dynamic> _advisor(int id, String name, {String? rank, String? dept, int load = 0, int max = 35, String status = 'available', bool away = false, int co = 0, String? until}) {
  final pct = max == 0 ? 0 : (load * 100 / max).round();
  return {
    'user_id': id,
    'name': name,
    'rank': rank,
    'role': 'teacher',
    'dept': dept,
    'status': status,
    'status_from': status == 'available' ? null : '2026-10-01',
    'status_until': until,
    'away': away,
    'eligible': true,
    'max_load': max,
    'max_load_override': null,
    'load': load,
    'co_load': co,
    'load_pct': pct,
    'warn': pct >= 80 && load <= max,
    'over': load > max,
    'office_location': id == 31 ? 'Building B, room 214' : null,
    'contact_note': id == 31 ? 'Office hours: Sunday and Tuesday 10:00–12:00' : null,
  };
}

/// `GET …/advisors` page 1: a mix of loads and statuses.
Map<String, dynamic> sampleAdvAdvisorsJson() => {
      'items': [
        _advisor(31, 'د. هدى سالم', rank: 'associate_professor', dept: 'Computer Science', load: 38, max: 35, co: 2),
        _advisor(32, 'Prof. Omar Khaled', rank: 'professor', dept: 'Information Systems', load: 30),
        _advisor(33, 'د. ليلى منصور', rank: 'assistant_professor', dept: 'Computer Science', load: 22, status: 'leave', away: true, until: '2027-01-15'),
        _advisor(34, 'Dr. Samir Adel', rank: 'lecturer', dept: 'Software Engineering and Artificial Intelligence', load: 12),
        _advisor(35, 'م. ريم حسن', rank: 'assistant_lecturer', load: 0, status: 'left', away: true),
      ],
      'total': 14,
      'page': 1,
      'size': 25,
      'pages': 1,
      'facets': {'available': 9, 'away': 3, 'warn': 2, 'over': 1},
    };

Map<String, dynamic> _student(int member, String name, {String? code, Map<String, dynamic>? primary, List<Map<String, dynamic>> others = const []}) => {
      'member_id': member,
      'user_id': member + 1000,
      'name': name,
      'code': code,
      'program': 'Software Engineering',
      'level': 'Level 2',
      'cohort': '2024',
      'primary': primary,
      'others': others,
    };

/// `GET …/students`.
Map<String, dynamic> sampleAdvStudentsJson() => {
      'items': [
        _student(501, 'أحمد محمود عبد الرحمن', code: '2024001', primary: {
          'user_id': 31, 'name': 'د. هدى سالم', 'away': false, 'locked': true, 'source': 'legacy', 'since': '2025-09-14T08:00:00'
        }),
        _student(502, 'Mona Ibrahim', code: '2024002', primary: {
          'user_id': 33, 'name': 'د. ليلى منصور', 'away': true, 'locked': false, 'source': 'auto', 'since': '2025-09-14T08:00:00'
        }, others: [
          {'user_id': 32, 'name': 'Prof. Omar Khaled', 'type': 'co'},
        ]),
        _student(503, 'يوسف خالد', code: '2024003'),
        _student(504, 'Sara Nabil Abdelaziz Mohamed El-Sayed', code: '2023118', primary: {
          'user_id': 34, 'name': 'Dr. Samir Adel', 'away': false, 'locked': false, 'source': 'manual', 'since': '2026-02-01T10:00:00'
        }),
      ],
      'total': 480,
      'page': 1,
      'size': 25,
      'pages': 20,
      'facets': {'unassigned': 78, 'away': 22, 'locked': 140},
    };

/// `GET …/students/{id}/history`.
Map<String, dynamic> sampleAdvHistoryJson() => {
      'items': [
        {'user_id': 33, 'name': 'د. ليلى منصور', 'type': 'primary', 'status': 'active', 'source': 'handover', 'locked': false, 'started_at': '2026-03-01T09:00:00', 'ended_at': null, 'end_reason': null, 'actor': 'د. هدى سالم'},
        {'user_id': 31, 'name': 'د. هدى سالم', 'type': 'primary', 'status': 'ended', 'source': 'legacy', 'locked': true, 'started_at': '2025-09-14T08:00:00', 'ended_at': '2026-03-01T09:00:00', 'end_reason': 'reassigned', 'actor': null},
      ],
    };

/// `GET …/conflicts`.
Map<String, dynamic> sampleAdvConflictsJson() => {
      'items': [
        {'id': 4, 'advisor': {'user_id': 31, 'name': 'د. هدى سالم'}, 'student': {'member_id': 503, 'user_id': 1503, 'name': 'يوسف خالد'}, 'reason': 'relative', 'note': 'Nephew', 'created_at': '2026-10-02T10:00:00', 'assigned_now': false},
      ],
      'total': 1,
      'page': 1,
      'size': 100,
      'pages': 1,
    };

/// `POST …/assign/preview` (distribute).
Map<String, dynamic> sampleAdvPlanJson({bool empty = false}) => {
      'plan_hash': 'a1b2c3',
      'mode': 'distribute',
      'strategy': 'balanced',
      'counts': empty
          ? {'students': 480, 'assign': 0, 'move': 0, 'unchanged': 480, 'locked_kept': 0, 'skipped_conflict': 0, 'skipped_capacity': 0}
          : {'students': 78, 'assign': 74, 'move': 0, 'unchanged': 0, 'locked_kept': 3, 'skipped_conflict': 1, 'skipped_capacity': 3},
      'advisors': empty
          ? []
          : [
              {'user_id': 32, 'name': 'Prof. Omar Khaled', 'before': 30, 'after': 33, 'max': 35, 'warn': true, 'over': false},
              {'user_id': 34, 'name': 'Dr. Samir Adel', 'before': 12, 'after': 34, 'max': 35, 'warn': true, 'over': false},
              {'user_id': 36, 'name': 'د. كريم فؤاد', 'before': 5, 'after': 30, 'max': 35, 'warn': false, 'over': false},
              {'user_id': 31, 'name': 'د. هدى سالم', 'before': 38, 'after': 38, 'max': 35, 'warn': false, 'over': true},
              {'user_id': 37, 'name': 'Dr. Nadia Fathy', 'before': 20, 'after': 20, 'max': 35, 'warn': false, 'over': false},
            ],
      'moves': empty
          ? []
          : [
              for (var i = 0; i < 24; i++)
                {
                  'member_id': 600 + i,
                  'name': i.isEven ? 'طالب رقم ${i + 1}' : 'Student number ${i + 1}',
                  'from': null,
                  'to': {'user_id': 34, 'name': 'Dr. Samir Adel'},
                },
            ],
      'moves_total': empty ? 0 : 74,
      'warnings': empty
          ? []
          : [
              {'code': 'capacity_full', 'count': 3},
              {'code': 'conflict_skipped', 'count': 1},
              {'code': 'advisors_warn', 'count': 2},
            ],
    };

/// `GET …/assign/runs`.
Map<String, dynamic> sampleAdvRunsJson() => {
      'items': [
        {'id': 12, 'mode': 'distribute', 'strategy': 'balanced', 'status': 'applied', 'counts': {'assign': 40, 'move': 0, 'skipped_capacity': 2}, 'actor': 'د. هدى سالم', 'created_at': '2026-11-02T10:00:00', 'applied_at': '2026-11-02T10:01:00'},
        {'id': 11, 'mode': 'reassign', 'strategy': 'continuity', 'status': 'planned', 'counts': {'move': 22}, 'actor': {'name': 'Prof. Omar Khaled'}, 'created_at': '2026-11-01T08:30:00', 'applied_at': null},
      ],
      'total': 2,
      'page': 1,
      'size': 10,
      'pages': 1,
    };

/// `GET …/handovers`.
Map<String, dynamic> sampleAdvHandoversJson() => {
      'items': [
        {
          'id': 70,
          'member_id': 502,
          'student': 'Mona Ibrahim',
          'from': {'user_id': 33, 'name': 'د. ليلى منصور'},
          'to': {'user_id': 32, 'name': 'Prof. Omar Khaled'},
          'reason': 'reassign',
          'note': 'Two flags on attendance; the plan ends with the midterms.',
          'summary': {
            'flags_open': 2,
            'plans_active': 1,
            'requests_open': 0,
            'notes': 5,
            'last_meetings': [
              {'at': '2026-10-20T09:00:00', 'mode': 'in_person'},
              {'at': '2026-09-28T11:00:00', 'mode': 'video'},
            ],
          },
          'created_at': '2026-11-03T08:00:00',
          'acknowledged_at': null,
        },
        {
          'id': 69,
          'member_id': 503,
          'student': 'يوسف خالد',
          'from': null,
          'to': {'user_id': 32, 'name': 'Prof. Omar Khaled'},
          'reason': null,
          'summary': {'flags_open': 0, 'plans_active': 0, 'requests_open': 0, 'notes': 0, 'last_meetings': []},
          'created_at': '2026-10-28T08:00:00',
          'acknowledged_at': '2026-10-29T10:00:00',
        },
      ],
      'total': 2,
      'page': 1,
      'size': 25,
      'pages': 1,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('settings', () {
    test('the bundle parses: effective, defaults, the organization row, scopes and choices', () {
      final b = AdvPolicyBundle.fromJson(sampleAdvPolicyJson());
      expect(b.effective.maxLoad, 35);
      expect(b.defaults.maxLoad, 40);
      expect(b.orgId, 3);
      expect(b.orgSettings['max_load'], 35);
      expect(b.scopes.single.scopeType, 'dept');
      expect(b.scopes.single.overrides, 2);
      expect(b.options.depts.map((d) => d.id), [21, 22]);
      expect(b.options.refs('level').map((r) => r.$1), ['1', '2', '3', '4']);
      expect(b.scopeLabel('dept', '21'), 'Computer Science');
      expect(b.scopeLabel('dept', '22'), 'Information Systems', reason: 'falls back to the option name');
      AppConfig.lang = 'ar';
      expect(b.scopeLabel('dept', '21'), 'علوم الحاسب');
      expect(b.options.depts.last.name, 'نظم المعلومات');
      AppConfig.lang = 'en';
      expect(b.options.ranks.first.label(advRankLabel), 'Professor', reason: 'empty server labels fall back to the app');
    });

    test('older server: missing blocks fall back to the defaults', () {
      final b = AdvPolicyBundle.fromJson(const {});
      expect(b.effective.maxLoad, 40);
      expect(b.effective.eligibleRoles, ['teacher']);
      expect(b.orgId, isNull);
      expect(b.scopes, isEmpty);
      expect(b.options.strategies.map((s) => s.key), advStrategies);
      expect(b.options.depts, isEmpty);
    });

    test('inheritance: a scope inherits the organization; the organization its parent or the default', () {
      final b = AdvPolicyBundle.fromJson(sampleAdvPolicyJson());
      expect(b.inheritedFor('dept').maxLoad, 35);
      // the organization sets max_load itself: what it would inherit is the default (its parent's is unknown)
      expect(b.inheritedFor('org').maxLoad, 40);
      expect(b.orgInheritSource('strategy'), 'default');
      final parent = AdvPolicyBundle.fromJson({...sampleAdvPolicyJson(), 'effective': _policy(strategy: 'continuity')});
      expect(parent.orgInheritSource('strategy'), 'parent');
    });

    test('the draft keeps the stored keys, sets and resets fields, and is dirty only when changed', () {
      final b = AdvPolicyBundle.fromJson(sampleAdvPolicyJson());
      final d = AdvSettingsDraft.of(b, 'org', null);
      expect(d.dirty, isFalse);
      expect(d.shown(b.inheritedFor('org')).maxLoad, 35);
      final e = d.set('warn_pct', 70).reset('max_load');
      expect(e.dirty, isTrue);
      expect(e.toBody(), {
        'scope_type': 'org',
        'scope_ref': null,
        'settings': {'digest': 'weekly', 'warn_pct': 70},
      }, reason: 'a later phase\'s key (digest) is sent back untouched');
      expect(e.set('max_load', 35).reset('warn_pct').dirty, isFalse);
      final scope = AdvSettingsDraft.of(b, 'dept', '21');
      expect(scope.toBody()['scope_ref'], '21');
      expect(scope.shown(b.inheritedFor('dept')).strategy, 'department');
      expect(scope.shown(b.inheritedFor('dept')).warnPct, 80);
      expect(const AdvSettingsDraft(scopeType: 'level', scopeRef: '2', fresh: true).dirty, isTrue, reason: 'a new scope saves even empty');
    });

    test('draft validation', () {
      const d = AdvSettingsDraft(scopeType: 'org');
      expect(d.set('eligible_roles', <String>[]).error, isNotNull);
      expect(d.set('max_load', 0).error, isNotNull);
      expect(d.set('warn_pct', 101).error, isNotNull);
      expect(d.set('max_load', 30).error, isNull);
      // retention (the server's 422 advising_retention_order): records never shorter than sensitive notes
      expect(d.set('retention_months', 0).error, isNotNull);
      expect(d.set('records_retention_months', 11).error, isNotNull, reason: '12 months at least');
      expect(d.set('records_retention_months', 12).error, isNotNull, reason: 'below the default 24 of sensitive notes');
      expect(d.set('retention_months', 36).set('records_retention_months', 24).error, 'Advising records must be kept at least as long as sensitive notes');
      expect(d.set('retention_months', 36).set('records_retention_months', 36).error, isNull);
      expect(d.set('retention_months', 120).error, isNull, reason: 'a row that sets only the sensitive period stays valid');
      expect(d.set('retention_months', 12).set('records_retention_months', 84).toBody()['settings'], {'retention_months': 12, 'records_retention_months': 84});
    });

    test('scope keys and value texts', () {
      expect(advScopeKey('org', null), 'org');
      expect(advScopeKey('dept', '21'), 'dept:21');
      expect(advScopeOfKey('cohort:2024'), ('cohort', '2024'));
      expect(advScopeOfKey('org'), ('org', null));
      const o = AdvPolicyOptions();
      expect(advPolicyValueText('eligible_ranks', <String>[], o), 'Any rank');
      expect(advPolicyValueText('mode', 'multi', o), 'Advisor and co-advisors');
      expect(advPolicyValueText('strategy', 'continuity', o), 'Previous advisor first');
      expect(advPolicyValueText('warn_pct', 80, o), '80%');
      expect(advPolicyValueText('records_retention_months', 84, o), '84 months');
      AppConfig.lang = 'ar';
      expect(advPolicyValueText('retention_months', 24, o), '24 شهراً');
      AppConfig.lang = 'en';
      final b = AdvPolicyBundle.fromJson(sampleAdvPolicyJson());
      expect(b.effective.value('records_retention_months'), 84, reason: 'the effective settings carry the new field');
    });
  });

  group('advisors', () {
    test('an advisor parses with load, status and dates', () {
      final p = AdvPage.fromJson(sampleAdvAdvisorsJson(), AdvAdvisor.fromJson);
      expect(p.total, 14);
      expect(p.facet('away'), 3);
      final huda = p.items.first;
      expect(huda.over, isTrue);
      expect(huda.coLoad, 2);
      expect(huda.subtitle, 'Associate professor · Computer Science');
      expect(huda.officeLocation, 'Building B, room 214');
      final leila = p.items[2];
      expect(leila.away, isTrue);
      expect(leila.statusUntil, DateTime(2027, 1, 15));
      expect(leila.statusText, 'On leave until 2027-01-15');
    });

    test('older server: a bare advisor still parses', () {
      final a = AdvAdvisor.fromJson(const {'user_id': 5, 'load': 10, 'max_load': 20});
      expect(a.status, 'available');
      expect(a.eligible, isTrue);
      expect(a.loadPct, 50);
      expect(a.shown, '#5');
      expect(AdvAdvisor.fromJson(const {'user_id': 5, 'status': 'retired'}).status, 'available');
      final page = AdvPage.fromJson(const {'items': [{'user_id': 1}]}, AdvAdvisor.fromJson);
      expect(page.total, 1);
      expect(page.pages, 1);
      expect(page.facets, isEmpty);
    });

    test('the profile PUT is the whole object; an available advisor sends no dates', () {
      final a = AdvAdvisor.fromJson(sampleAdvAdvisorsJson()['items'][2] as Map<String, dynamic>);
      final d = AdvProfileDraft.of(a);
      expect(d.toJson(), {
        'status': 'leave',
        'status_from': '2026-10-01',
        'status_until': '2027-01-15',
        'max_load_override': null,
        'office_location': null,
        'contact_note': null,
        'bio': null,
      });
      final back = d.copyWith(status: 'available', officeLocation: '  B-214 ', maxLoadOverride: () => 20);
      expect(back.toJson()['status_from'], isNull);
      expect(back.toJson()['status_until'], isNull);
      expect(back.toJson()['office_location'], 'B-214');
      expect(back.toJson()['max_load_override'], 20);
      expect(d.copyWith(statusUntil: () => DateTime(2026, 9, 1)).error, isNotNull, reason: 'the end before the start');
      expect(d.copyWith(maxLoadOverride: () => 0).error, isNotNull);
    });
  });

  group('conflicts', () {
    test('a conflict parses; an unknown reason is "other"', () {
      final p = AdvPage.fromJson(sampleAdvConflictsJson(), AdvConflict.fromJson);
      final x = p.items.single;
      expect(x.advisor.userId, 31);
      expect(x.memberId, 503);
      expect(x.studentName, 'يوسف خالد');
      expect(x.reason, 'relative');
      expect(x.note, 'Nephew');
      expect(AdvConflict.fromJson(const {'id': 1, 'reason': 'grudge'}).reason, 'other');
    });
  });

  group('students and manual assignment', () {
    test('students parse with their primary and other advisors', () {
      final p = AdvPage.fromJson(sampleAdvStudentsJson(), AdvStudent.fromJson);
      expect(p.pages, 20);
      expect(p.facet('unassigned'), 78);
      final a = p.items.first;
      expect(a.primary!.locked, isTrue);
      expect(a.primary!.source, 'legacy');
      expect(a.subtitle, '2024001 · Software Engineering · Level 2');
      expect(p.items[1].others.single.type, 'co');
      expect(p.items[2].primary, isNull);
      expect(AdvStudent.fromJson(const {'member_id': 9, 'primary': {}}).primary, isNull, reason: 'an empty primary block is no advisor');
    });

    test('the PUT body is the whole object; single mode drops the others', () {
      final s = AdvStudent.fromJson(sampleAdvStudentsJson()['items'][1] as Map<String, dynamic>);
      final d = AdvAdvisorsDraft.of(s);
      expect(d.changedFrom(s), isFalse);
      final moved = d.copyWith(primary: () => const AdvRef(userId: 34, name: 'Dr. Samir Adel'), locked: true, reason: ' Advisor on leave ');
      expect(moved.changedFrom(s), isTrue);
      expect(moved.toJson(multi: true), {
        'primary': 34,
        'locked': true,
        'others': [
          {'user_id': 32, 'type': 'co'},
        ],
        'reason': 'Advisor on leave',
        'force_over_capacity': false,
      });
      expect(moved.toJson(multi: false)['others'], isEmpty);
      final cleared = d.copyWith(primary: () => null, locked: true, others: const []);
      expect(cleared.toJson(multi: true)['locked'], isFalse, reason: 'nothing to lock without a primary');
    });

    test('others: never the primary, never twice; force needs a reason', () {
      final s = AdvStudent.fromJson(sampleAdvStudentsJson()['items'][1] as Map<String, dynamic>);
      final d = AdvAdvisorsDraft.of(s);
      expect(d.addOther(const AdvRef(userId: 33, name: ''), 'co').others.length, 1, reason: '33 is the primary');
      expect(d.addOther(const AdvRef(userId: 32, name: ''), 'support').others.length, 1, reason: '32 is there already');
      expect(d.addOther(const AdvRef(userId: 40, name: 'X'), 'support').others.last.type, 'support');
      expect(d.removeOther(32).others, isEmpty);
      expect(d.copyWith(force: true).error(multi: true), isNotNull);
      expect(d.copyWith(force: true, reason: 'Only advisor in the program').error(multi: true), isNull);
      expect(d.copyWith(primary: () => null).error(multi: true), isNotNull, reason: 'others without a primary');
    });

    test('history parses newest first, an open row is active', () {
      final h = [for (final m in (sampleAdvHistoryJson()['items'] as List).cast<Map<String, dynamic>>()) AdvHistoryEntry.fromJson(m)];
      expect(h.first.active, isTrue);
      expect(h.first.actor, 'د. هدى سالم');
      expect(h.last.active, isFalse);
      expect(h.last.endReason, 'reassigned');
    });
  });

  group('distribution', () {
    test('the preview body per mode', () {
      expect(const AdvPlanRequest().toJson(), {
        'mode': 'distribute',
        'strategy': null,
        'scope': null,
        'from_advisor_user_id': null,
        'to_advisor_user_id': null,
        'member_ids': null,
      });
      final scoped = const AdvPlanRequest().copyWith(strategy: () => 'department', deptId: () => 21, level: () => '2');
      expect(scoped.toJson()['scope'], {'dept_id': 21, 'program_id': null, 'level': '2', 'cohort': null});
      const reassign = AdvPlanRequest(mode: 'reassign');
      expect(reassign.ready, isFalse, reason: 'whose students?');
      final r = reassign.copyWith(from: () => const AdvRef(userId: 33, name: ''), memberIds: () => [502]);
      expect(r.ready, isTrue);
      expect(r.toJson()['from_advisor_user_id'], 33);
      expect(r.toJson()['member_ids'], [502]);
      expect(r.copyWith(to: () => const AdvRef(userId: 33, name: '')).ready, isFalse, reason: 'never to the same advisor');
      expect(const AdvPlanRequest(mode: 'distribute', from: AdvRef(userId: 1, name: '')).toJson()['from_advisor_user_id'], isNull);
    });

    test('the plan parses; advisors with the largest change first', () {
      final p = AdvPlan.fromJson(sampleAdvPlanJson());
      expect(p.planHash, 'a1b2c3');
      expect(p.counts.assign, 74);
      expect(p.counts.skipped, 4);
      expect(p.counts.changes, 74);
      expect(p.advisors.first.userId, 36, reason: '+25 is the largest change');
      expect(p.moves.length, 24);
      expect(p.movesTotal, 74);
      expect(p.warnings.first, ('capacity_full', 3));
      expect(p.empty, isFalse);
      expect(p.scale, 38);
      expect(AdvPlan.fromJson(sampleAdvPlanJson(empty: true)).empty, isTrue);
      final bare = AdvPlan.fromJson(const {'plan_hash': 'x'});
      expect(bare.empty, isTrue);
      expect(bare.movesTotal, 0);
    });

    test('apply result and runs', () {
      final r = AdvApplyResult.fromJson(const {'run_id': 12, 'assigned': 74, 'moved': 0, 'handovers': 0, 'notified_students': 74, 'notified_advisors': 6});
      expect(r.summary, 'Applied: 74 assigned');
      expect(const AdvApplyResult().summary, 'Distribution applied');
      final runs = AdvPage.fromJson(sampleAdvRunsJson(), AdvRun.fromJson);
      expect(runs.items.first.applied, isTrue);
      expect(runs.items.first.counts.assign, 40);
      expect(runs.items.last.actor, 'Prof. Omar Khaled', reason: 'an actor object gives its name');
    });

    test('every warning code reads as a sentence in both languages', () {
      const codes = ['no_eligible_advisor', 'capacity_full', 'conflict_skipped', 'forced_over_capacity', 'primary_away', 'advisors_warn', 'advisors_over'];
      final seen = <String>{};
      for (final code in [...codes, 'something_new']) {
        final text = advWarningText(code, 3);
        expect(text, isNot(contains('_')), reason: code);
        seen.add(text);
      }
      expect(seen.length, codes.length + 1, reason: 'each code has its own sentence');
      AppConfig.lang = 'ar';
      expect(advWarningText('capacity_full', 1), contains('طالب واحد'));
      expect(advWarningText('capacity_full', 11), contains('11 طالباً'));
    });
  });

  group('handovers and status additions', () {
    test('a handover parses with its summary', () {
      final p = AdvPage.fromJson(sampleAdvHandoversJson(), AdvHandover.fromJson);
      final h = p.items.first;
      expect(h.pending, isTrue);
      expect(h.note, startsWith('Two flags'));
      expect(h.from!.userId, 33);
      expect(h.summary.flagsOpen, 2);
      expect(h.summary.lastMeetings.length, 2);
      expect(h.summary.lastMeetings.first.$2, 'in_person');
      expect(p.items.last.pending, isFalse);
      expect(p.items.last.summary.empty, isTrue);
      expect(AdvHandover.fromJson(const {'id': 1, 'student': {'name': 'X'}}).student, 'X');
    });

    test('status gains away / over and the pending handovers; member advisors their contact', () {
      final s = AdvStatus.fromJson({
        'enabled': true,
        'me': {'advisor': true, 'handovers_pending': 2},
        'counts': {'students': 10, 'assigned': 8, 'unassigned': 2, 'advisors': 2, 'away': 3, 'over': 1},
      });
      expect(s.me.handoversPending, 2);
      expect(s.counts!.away, 3);
      expect(s.counts!.over, 1);
      expect(AdvStatus.fromJson({'enabled': true, 'me': {}, 'counts': {}}).counts!.away, 0);
      final m = AdvMemberStatus.fromJson({
        'enabled': true,
        'role': 'student',
        'advisors': [
          {'user_id': 31, 'name': 'د. هدى سالم', 'type': 'primary', 'office_location': 'B-214', 'contact_note': ''},
        ],
      });
      expect(m.primaryAdvisor!.officeLocation, 'B-214');
      expect(m.primaryAdvisor!.contactNote, isNull);
    });
  });

  test('every Phase 3 server code has a text in both languages', () {
    const codes = [
      'advising_bad_scope', 'advising_single_mode', 'advising_conflict', 'advising_conflict_exists', 'advising_over_capacity', 'plan_stale',
      'advising_reason_required', 'advising_not_found', 'advising_bad_dates', 'advising_bad_request',
      'advising_retention_order',
    ];
    final en = advCodeTexts();
    AppConfig.lang = 'ar';
    final ar = advCodeTexts();
    for (final c in codes) {
      expect(en[c], isNotNull, reason: c);
      expect(ar[c], isNot(en[c]), reason: c);
    }
  });

  test('every history end reason the server writes has a label in both languages', () {
    // services/organization/advising/assignments.py: _end(...) and END_REASON.
    const reasons = ['replaced', 'cleared', 'promoted', 'legacy_sync', 'rebalanced', 'reassigned', 'removed', 'changed'];
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      for (final r in reasons) {
        expect(advEndReasonLabel(r), isNot(r), reason: '$lang $r');
      }
    }
    // handovers.REASONS: a handover's reason is a code too, never shown raw.
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      for (final r in ['reassign', 'rebalance', 'manual']) {
        expect(advHandoverReasonLabel(r), isNot(r), reason: '$lang $r');
      }
    }
  });
}
