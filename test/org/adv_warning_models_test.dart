// Academic Advising, Phase 6 (docs/advising/PHASE6.md): the early warning's answers parse (an older server that
// leaves keys out still parses), the rule draft builds the WHOLE-object bodies checked against the kind catalog
// (number, whole number, on / off and empty parameters), the explanations fall back to a sentence per kind, the
// graduation projection reads, the settings group inherits like the other settings, and every new server code has
// text in both languages. The sample payloads (shaped like services/organization/advising/warning_rules.py,
// alerts.py, warning_engine.py) are shared with test/ui/adv_warning_layout_test.dart and
// test/visual/adv_warning_golden_test.dart.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_texts.dart';
import 'package:flutter_education_app/features/org/advising/adv_warning_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_warning_parts.dart' show advRunCountsText, advWarningErrorText;
import 'package:flutter_test/flutter_test.dart';

/// The clock the samples are written against.
final advWarnNow = DateTime.utc(2026, 11, 5, 10);

Map<String, dynamic> _param(String key, String type, Object? def, num? min, num? max, num? step, String? unit, String ar, String en, {bool nullable = false}) => {
      'key': key,
      'type': type,
      'min': min,
      'max': max,
      'step': step,
      'default': def,
      'nullable': nullable,
      'unit': unit,
      'label_ar': ar,
      'label_en': en,
    };

Map<String, dynamic> _kind(String kind, String ar, String en, String helpAr, String helpEn, String priority, int cooldown, List<Map<String, dynamic>> params) => {
      'kind': kind,
      'label_ar': ar,
      'label_en': en,
      'help_ar': helpAr,
      'help_en': helpEn,
      'default_priority': priority,
      'default_cooldown_days': cooldown,
      'params': params,
    };

/// The server's kind catalog (risk_rules.KINDS).
List<Map<String, dynamic>> sampleAdvKindsJson() => [
      _kind('gpa_below', 'معدل تراكمي منخفض', 'Low CGPA', 'ينبّه عندما يقل المعدل التراكمي عن الحد، ومن جديد كلما انخفض ربع نقطة أخرى.',
          'Alerts when the CGPA is under the limit, and again for every further quarter point down.', 'high', 30, [_param('threshold', 'number', 2.0, 0.5, 5.0, 0.01, 'gpa', 'الحد', 'Limit')]),
      _kind('gpa_drop', 'هبوط معدل الفصل', 'Term GPA drop', 'ينبّه عندما يقل معدل آخر فصل مُعتمد عن المعدل التراكمي بمقدار الفرق أو أكثر.',
          'Alerts when the last graded term\'s GPA is at least this far under the CGPA.', 'normal', 30, [_param('drop', 'number', 0.5, 0.1, 2.0, 0.01, 'gpa', 'الفرق', 'Drop')]),
      _kind('failed_courses', 'مقررات راسبة', 'Failed courses', 'عدد المقررات التي رسب فيها الطالب ولم ينجح فيها بعد.', 'How many courses the student failed and has not passed since.', 'high', 30,
          [_param('count', 'int', 2, 1, 20, 1, 'count', 'العدد', 'Count')]),
      _kind('absence_pct', 'نسبة غياب مرتفعة', 'High absence', 'أعلى نسبة غياب في مقرر من مقررات الفصل الحالي.', 'The highest absence percentage in a course of the current term.', 'normal', 14,
          [_param('percent', 'number', 15.0, 1.0, 100.0, 0.5, 'percent', 'النسبة', 'Percent')]),
      _kind('no_contact', 'لا تواصل مع المرشد', 'No contact with the advisor', 'الأيام منذ آخر تواصل مسجّل (أو منذ تعيين المرشد إن لم يحدث تواصل).',
          'Days since the last logged contact (or since the advisor was assigned, when there was none).', 'low', 30, [_param('days', 'int', 45, 7, 365, 1, 'days', 'الأيام', 'Days')]),
      _kind('graduation_delay', 'خطر تأخر التخرج', 'Graduation delay risk', 'يقارن الساعات المنجزة والمتبقية بالخطة.', 'Compares the credit hours earned and remaining with the plan.', 'normal', 90, [
        _param('terms', 'int', 1, 1, 6, 1, 'terms', 'فصول التأخر', 'Terms late'),
        _param('planned_terms', 'int', null, 2, 20, 1, 'terms', 'الفصول المخططة', 'Planned terms', nullable: true),
        _param('min_terms', 'int', 2, 1, 10, 1, 'terms', 'بعد فصول دراسية', 'After terms'),
        _param('at_risk', 'bool', true, null, null, null, null, 'ينبّه عند الخطر أيضاً', 'Also alert when at risk'),
      ]),
      _kind('midterm_fail', 'درجة منتصف الفصل منخفضة', 'Low midterm mark', 'درجة منتصف الفصل في مقرر من مقررات الفصل الحالي أقل من النسبة.', 'A midterm mark of a current course under the percentage.', 'high', 30,
          [_param('percent', 'number', 50.0, 1.0, 100.0, 0.5, 'percent', 'النسبة', 'Percent')]),
    ];

Map<String, dynamic> _cat(int id, String key, String ar, String en, {bool sensitive = false}) =>
    {'id': id, 'key': key, 'name_ar': ar, 'name_en': en, 'sensitive': sensitive};

Map<String, dynamic> _rule(int id, String kind, String ar, String en, Map<String, dynamic> params, String sumAr, String sumEn,
        {String priority = 'normal', int cooldown = 30, bool enabled = true, bool system = true, Map<String, dynamic>? category, Map<String, dynamic>? scope, bool custom = false}) =>
    {
      'id': id,
      'key': '${kind}_1',
      'kind': kind,
      'name_ar': ar,
      'name_en': en,
      'custom_name': custom,
      'params': params,
      'priority': priority,
      'cooldown_days': cooldown,
      'enabled': enabled,
      'system': system,
      'category': category,
      'scope': scope,
      'summary': {'ar': sumAr, 'en': sumEn},
      'updated_at': '2026-11-01T08:00:00',
      'updated_by': system ? null : {'user_id': 7, 'name': 'د. سلمى الحربي'},
    };

Map<String, dynamic> sampleAdvRunJson({int id = 41, String status = 'done', String trigger = 'tick', String kind = 'evaluate', String? error}) => {
      'id': id,
      'kind': kind,
      'trigger': trigger,
      'status': status,
      'actor': trigger == 'manual' ? {'user_id': 7, 'name': 'د. سلمى الحربي'} : null,
      'counts': {
        'students': status == 'running' ? 120 : 342,
        'matched': 57,
        'alerts': 12,
        'suppressed': 45,
        'flags_opened': 4,
        'flags_updated': 3,
        'notified': 6,
        'digest_waiting': 5,
        'digests': kind == 'digest' ? 9 : 0,
        'nudges_advisors': kind == 'digest' ? 4 : 0,
        'nudges_students': kind == 'digest' ? 21 : 0,
      },
      'error': error,
      'started_at': '2026-11-05T09:00:00',
      'finished_at': status == 'running' ? null : '2026-11-05T09:00:04',
      'duration_ms': status == 'running' ? null : 4200,
    };

/// `GET …/rules`: the seeded rules, one custom rule limited to a program, one switched off.
Map<String, dynamic> sampleAdvRulesJson({bool canEdit = true, bool running = false, bool failed = false, bool empty = false}) => {
      'items': empty
          ? []
          : [
              _rule(1, 'gpa_below', 'معدل تراكمي منخفض', 'Low CGPA', {'threshold': 2.0}, 'المعدل التراكمي أقل من 2.00', 'CGPA below 2.00', priority: 'high'),
              _rule(2, 'gpa_below', 'إنذار أكاديمي نهائي', 'Final academic warning', {'threshold': 1.5}, 'المعدل التراكمي أقل من 1.50', 'CGPA below 1.50',
                  priority: 'urgent', system: false, custom: true, cooldown: 14),
              _rule(3, 'absence_pct', 'نسبة غياب مرتفعة', 'High absence', {'percent': 15.0}, 'غياب 15% أو أكثر في مقرر', '15 % absence or more in a course', cooldown: 14),
              _rule(4, 'no_contact', 'لا تواصل مع المرشد', 'No contact with the advisor', {'days': 45}, 'لا تواصل منذ 45 يوماً', 'No contact for 45 days', priority: 'low'),
              _rule(5, 'graduation_delay', 'خطر تأخر التخرج', 'Graduation delay risk', {'terms': 1, 'planned_terms': null, 'min_terms': 2, 'at_risk': true},
                  'تأخر متوقع في التخرج 1 فصل أو أكثر', 'Graduation projected 1 term(s) late or more', cooldown: 90,
                  scope: {'program_id': 4, 'level': null, 'cohort': null}),
              _rule(6, 'midterm_fail', 'درجة منتصف الفصل منخفضة', 'Low midterm mark', {'percent': 50.0}, 'درجة منتصف الفصل أقل من 50%', 'Midterm mark under 50 %',
                  priority: 'high', enabled: false, category: _cat(12, 'academic', 'أكاديمي', 'Academic')),
            ],
      'kinds': sampleAdvKindsJson(),
      'engine': {
        'enabled': true,
        'running': running ? sampleAdvRunJson(id: 42, status: 'running', trigger: 'manual') : null,
        'last_run': sampleAdvRunJson(status: failed ? 'failed' : 'done', error: failed ? 'stale' : null),
        'next_run_at': '2026-11-05T10:00:00',
      },
      'can_edit': canEdit,
    };

Map<String, dynamic> sampleAdvPreviewJson({bool needsRun = false}) => {
      'matches': needsRun ? 0 : 12,
      'students': needsRun ? 0 : 342,
      'evaluated_at': needsRun ? null : '2026-11-05T09:00:04',
      'needs_run': needsRun,
      'sample': needsRun
          ? []
          : [
              {'member_id': 31, 'name': 'ريم عبدالله القحطاني', 'code': '441203', 'explanation': {'ar': 'المعدل التراكمي 1.62 أقل من 2.00', 'en': 'CGPA 1.62 is below 2.00'}},
              {'member_id': 32, 'name': 'Omar Haddad', 'code': '441377', 'explanation': {'ar': 'المعدل التراكمي 1.88 أقل من 2.00', 'en': 'CGPA 1.88 is below 2.00'}},
            ],
    };

Map<String, dynamic> _alert(int id, int member, String name, String code, Map<String, dynamic> rule, String priority, Map<String, dynamic> explanation, String fired,
        {String delivery = 'single', Map<String, dynamic>? flag, Map<String, dynamic>? category, Map<String, dynamic> evidence = const {}}) =>
    {
      'id': id,
      'member_id': member,
      'student': {'name': name, 'code': code},
      'rule': rule,
      'priority': priority,
      'level': 1,
      'category': category ?? _cat(12, 'academic', 'أكاديمي', 'Academic'),
      'evidence': evidence,
      'explanation': explanation,
      'term': {'id': 9, 'label': '2026/2027', 'kind': 'term1'},
      'fired_at': fired,
      'flag': flag,
      'delivery': delivery,
    };

Map<String, dynamic> _ruleRef(int? id, String kind, String ar, String en) => {'id': id, 'key': '${kind}_1', 'kind': kind, 'name_ar': ar, 'name_en': en};

List<Map<String, dynamic>> _alerts() => [
      _alert(501, 31, 'ريم عبدالله القحطاني', '441203', _ruleRef(2, 'gpa_below', 'إنذار أكاديمي نهائي', 'Final academic warning'), 'urgent',
          {'ar': 'المعدل التراكمي 1.42 أقل من 1.50', 'en': 'CGPA 1.42 is below 1.50'}, '2026-11-05T09:00:03',
          delivery: 'urgent', flag: {'id': 801, 'status': 'open'}, evidence: {'cgpa': 1.42, 'threshold': 1.5}),
      _alert(502, 32, 'Omar Haddad', '441377', _ruleRef(3, 'absence_pct', 'نسبة غياب مرتفعة', 'High absence'), 'normal',
          {'ar': 'غياب 22.5% في CS101 (الحد 15%)', 'en': '22.5 % absence in CS101 (limit 15 %)'}, '2026-11-05T09:00:03',
          delivery: 'digest', flag: {'id': 802, 'status': 'acknowledged'}),
      _alert(503, 33, 'سارة محمد الدوسري', '441512', _ruleRef(5, 'graduation_delay', 'خطر تأخر التخرج', 'Graduation delay risk'), 'normal',
          {'ar': 'أنجز 45 من 132 ساعة بعد 6 فصول: التخرج يحتاج 11 فصلاً على الأقل، أي 3 بعد الخطة (8)', 'en': '45 of 132 credits after 6 terms: graduation needs at least 11 terms, 3 more than the 8 planned'},
          '2026-11-04T09:00:02', flag: {'id': 803, 'status': 'contacted'}),
      _alert(504, 34, 'خالد ناصر العتيبي', '441090', _ruleRef(null, 'midterm_fail', 'درجة منتصف الفصل منخفضة', 'Low midterm mark'), 'high',
          {'ar': 'درجة منتصف الفصل أقل من 50% في 2 مقرر: CS101 38%, MA102 45%', 'en': 'Midterm below 50 % in 2 course(s): CS101 38 %, MA102 45 %'}, '2026-11-02T09:00:02',
          delivery: 'none'),
    ];

/// `GET …/alerts` for a director: four alerts, one hidden (sensitive).
Map<String, dynamic> sampleAdvAlertsJson({bool empty = false}) => {
      'items': empty ? [] : _alerts(),
      'total': empty ? 0 : 4,
      'page': 1,
      'size': 25,
      'pages': 1,
      'restricted': empty ? 0 : 1,
      'facets': empty ? {'urgent': 0, 'high': 0, 'last_7d': 0} : {'urgent': 1, 'high': 1, 'last_7d': 4},
    };

Map<String, dynamic> sampleAdvGraduationBlock(String status) => switch (status) {
      'delayed' => {
          'status': 'delayed', 'basis': 'credits', 'reason': null, 'earned': 45.0, 'in_progress': 12.0, 'total': 132.0, 'remaining': 87.0, 'terms_done': 6, 'planned_terms': 8,
          'projected_terms': 11, 'delay_terms': 3, 'needed_per_term': null, 'max_load': 18.0, 'level': 'Level 3', 'expected_level': null,
          'failed_count': 2, 'delayed_count': 1,
          'failed_courses': [
            {'course_id': 101, 'code': 'CS101', 'name_ar': 'مقدمة في البرمجة', 'name_en': 'Introduction to Programming', 'credits': 3, 'attempts': 2},
            {'course_id': 205, 'code': 'MA102', 'name_ar': 'التفاضل والتكامل 2', 'name_en': 'Calculus II', 'credits': 4, 'attempts': 1},
          ],
          'delayed_courses': [
            {'course_id': 150, 'code': 'PHY101', 'name_ar': 'فيزياء عامة', 'name_en': 'General Physics', 'credits': 3, 'level': 'Level 1'},
          ],
        },
      'at_risk' => {
          'status': 'at_risk', 'basis': 'credits', 'reason': null, 'earned': 64.0, 'in_progress': 15.0, 'total': 132.0, 'terms_done': 4, 'planned_terms': 8,
          'projected_terms': 8, 'delay_terms': 0, 'needed_per_term': 17.0, 'max_load': 18.0, 'level': 'Level 3',
        },
      'levels' => {
          'status': 'delayed', 'basis': 'levels', 'reason': null, 'earned': null, 'in_progress': null, 'total': null, 'terms_done': 6, 'planned_terms': 8,
          'projected_terms': null, 'delay_terms': 2, 'needed_per_term': null, 'max_load': null, 'level': 'الفرقة الثانية', 'expected_level': 'الفرقة الثالثة',
        },
      'unknown' => {'status': 'unknown', 'basis': null, 'reason': 'no_total', 'terms_done': 2},
      'graduated' => {'status': 'graduated', 'basis': 'credits', 'earned': 134.0, 'total': 132.0, 'terms_done': 8, 'planned_terms': 8},
      _ => {
          'status': 'on_track', 'basis': 'credits', 'reason': null, 'earned': 96.0, 'in_progress': 16.0, 'total': 132.0, 'terms_done': 6, 'planned_terms': 8,
          'projected_terms': 8, 'delay_terms': 0, 'needed_per_term': 10.0, 'max_load': 18.0, 'level': 'Level 4',
        },
    };

/// `GET …/students/{member_id}/warning`.
Map<String, dynamic> sampleAdvWarningJson({bool evaluated = true, bool hits = true, String graduation = 'delayed'}) => {
      'evaluated_at': evaluated ? '2026-11-05T09:00:03' : null,
      'term': {'id': 9, 'label': '2026/2027', 'kind': 'term1'},
      'hits': !evaluated || !hits
          ? []
          : [
              {
                'rule': _ruleRef(3, 'absence_pct', 'نسبة غياب مرتفعة', 'High absence'),
                'priority': 'normal',
                'level': 2,
                'explanation': {'ar': 'غياب 22.5% في CS101 (الحد 15%)', 'en': '22.5 % absence in CS101 (limit 15 %)'},
                'evidence': {'percent': 22.5, 'course': 'CS101', 'limit': 15},
                'alert_id': 502,
              },
              {
                'rule': _ruleRef(2, 'gpa_below', 'إنذار أكاديمي نهائي', 'Final academic warning'),
                'priority': 'urgent',
                'level': 1,
                'explanation': {'ar': 'المعدل التراكمي 1.42 أقل من 1.50', 'en': 'CGPA 1.42 is below 1.50'},
                'evidence': {'cgpa': 1.42, 'threshold': 1.5},
                'alert_id': null,
              },
            ],
      'graduation': sampleAdvGraduationBlock(graduation),
      'recent': evaluated ? _alerts().take(2).toList() : [],
      'restricted': evaluated ? 1 : 0,
      'can': {'run': true},
    };

Map<String, dynamic> _grad(int member, String name, String code, String program, String level, String status, {Map<String, dynamic>? primary}) => {
      'member_id': member,
      'name': name,
      'code': code,
      'program': program,
      'level': level,
      'primary': primary,
      'graduation': sampleAdvGraduationBlock(status),
    };

/// `GET …/graduation` (status all, delay first).
Map<String, dynamic> sampleAdvGraduationJson({bool empty = false}) => {
      'items': empty
          ? []
          : [
              _grad(33, 'سارة محمد الدوسري', '441512', 'هندسة البرمجيات', 'المستوى الثالث', 'delayed', primary: {'user_id': 7, 'name': 'د. سلمى الحربي'}),
              _grad(35, 'Yousef Al-Amin', '441802', 'Computer Science', 'Level 3', 'at_risk', primary: {'user_id': 8, 'name': 'Dr. Hani Saleh'}),
              _grad(36, 'نورة فهد الشمري', '441611', 'هندسة البرمجيات', 'المستوى الرابع', 'on_track', primary: {'user_id': 7, 'name': 'د. سلمى الحربي'}),
              _grad(37, 'Lina Kareem', '441955', 'Information Systems', 'Level 1', 'unknown'),
            ],
      'total': empty ? 0 : 4,
      'page': 1,
      'size': 25,
      'pages': 1,
      'facets': {'delayed': empty ? 0 : 1, 'at_risk': empty ? 0 : 1, 'on_track': empty ? 0 : 1, 'unknown': empty ? 0 : 1},
    };

Map<String, dynamic> sampleAdvPrefsJson({String digest = 'inherit'}) => {
      'digest': digest,
      'effective': digest == 'inherit' ? 'daily' : digest,
      'org_default': 'daily',
      'digest_hour': 7,
      'digest_weekday': 6,
      'timezone': 'Asia/Riyadh',
      'last_digest_at': '2026-11-05T04:00:00',
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('rules and the kind catalog', () {
    test('the rules answer parses: rules, kinds, engine, can_edit', () {
      final b = AdvRulesBundle.fromJson(sampleAdvRulesJson());
      expect(b.rules.length, 6);
      expect(b.kinds.length, 7);
      expect(b.canEdit, isTrue);
      expect(b.enabledCount, 5);
      final custom = b.rules[1];
      expect(custom.customName, isTrue);
      expect(custom.priority, 'urgent');
      expect(custom.params['threshold'], 1.5);
      expect(custom.summary.shown, 'CGPA below 1.50');
      expect(b.rules[4].scope?.programId, 4);
      expect(b.rules[4].params['at_risk'], isTrue);
      expect(b.rules[4].params['planned_terms'], isNull);
      expect(b.rules[0].updatedBy, isNull);
      expect(b.engine.enabled, isTrue);
      expect(b.engine.lastRun?.counts.alerts, 12);
      expect(b.engine.lastRun?.durationMs, 4200);
      expect(b.engine.nextRunAt, isNotNull);
      AppConfig.lang = 'ar';
      expect(custom.name, 'إنذار أكاديمي نهائي');
    });

    test('grouped by kind in the catalog order, worst priority first', () {
      final b = AdvRulesBundle.fromJson(sampleAdvRulesJson());
      final g = b.grouped;
      expect([for (final (k, _) in g) k], ['gpa_below', 'absence_pct', 'no_contact', 'graduation_delay', 'midterm_fail']);
      expect([for (final r in g.first.$2) r.id], [2, 1]);
    });

    test('an older server: no kinds, no engine, no summary — still parses', () {
      final b = AdvRulesBundle.fromJson({
        'items': [
          {'id': 3, 'kind': 'absence_pct', 'params': {'percent': 20}},
        ],
      });
      expect(b.kinds, isEmpty);
      expect(b.canEdit, isFalse);
      expect(b.engine.enabled, isFalse);
      expect(b.engine.lastRun, isNull);
      final r = b.rules.single;
      expect(r.enabled, isTrue);
      expect(r.priority, 'normal');
      expect(r.summary.isEmpty, isTrue);
      expect(r.name, 'absence_pct');
      expect(b.grouped.single.$1, 'absence_pct');
    });

    test('a parameter formats, steps and checks by its unit and limits', () {
      final kinds = [for (final k in sampleAdvKindsJson()) AdvRuleKind.fromJson(k)];
      final gpa = kinds.first.params.single;
      expect(gpa.number(2), '2.00');
      expect(gpa.stepped(2.0, up: false), 1.99);
      expect(gpa.check(0.4), isNotNull);
      expect(gpa.check(2.0), isNull);
      final pct = kinds.firstWhere((k) => k.kind == 'absence_pct').params.single;
      expect(pct.format(22.5), '22.5%');
      expect(pct.stepped(100, up: true), 100);
      final grad = kinds.firstWhere((k) => k.kind == 'graduation_delay');
      expect(grad.param('planned_terms')!.nullable, isTrue);
      expect(grad.param('planned_terms')!.check(null), isNull);
      expect(grad.param('terms')!.check(null), isNotNull);
      expect(grad.param('at_risk')!.isBool, isTrue);
      expect(grad.defaults, {'terms': 1, 'planned_terms': null, 'min_terms': 2, 'at_risk': true});
      expect(grad.param('min_terms')!.format(3), '3 terms');
      final days = kinds.firstWhere((k) => k.kind == 'no_contact').params.single;
      expect(days.format(45), '45 days');
      expect(days.normalize(45.4), 45);
    });

    test('a new rule starts from its kind; the POST and PUT bodies are whole', () {
      final kind = AdvRuleKind.fromJson(sampleAdvKindsJson().firstWhere((k) => k['kind'] == 'graduation_delay'));
      final d = AdvRuleDraft.fresh(kind);
      expect(d.priority, 'normal');
      expect(d.cooldownDays, 90);
      expect(d.error(kind), isNull);
      final body = d.withParam('planned_terms', 10).copyWith(scope: const AdvRuleScope(level: 'Level 3'), nameEn: '  Late for graduation ').toJson(kind, create: true);
      expect(body, {
        'kind': 'graduation_delay',
        'params': {'terms': 1, 'planned_terms': 10, 'min_terms': 2, 'at_risk': true},
        'priority': 'normal',
        'cooldown_days': 90,
        'enabled': true,
        'category_id': null,
        'scope': {'program_id': null, 'level': 'Level 3', 'cohort': null},
        'name_ar': null,
        'name_en': 'Late for graduation',
      });
      expect(d.toJson(kind).containsKey('kind'), isFalse);
      expect(d.toJson(kind)['scope'], isNull);
      expect(d.previewBody(kind), {'kind': 'graduation_delay', 'params': {'terms': 1, 'planned_terms': null, 'min_terms': 2, 'at_risk': true}, 'scope': null});
    });

    test('a draft refuses what the server would: out of range, empty, cool-down, long names', () {
      final kind = AdvRuleKind.fromJson(sampleAdvKindsJson().first);
      final d = AdvRuleDraft.fresh(kind);
      expect(d.withParam('threshold', 6).error(kind), contains('between'));
      expect(d.withParam('threshold', null).error(kind), contains('Give a value'));
      expect(d.copyWith(cooldownDays: 400).error(kind), contains('cool-down'));
      expect(d.copyWith(nameAr: 'x' * 121).error(kind), contains('120'));
    });

    test('editing keeps the custom name only when it is one; changedFrom compares the whole rule', () {
      final b = AdvRulesBundle.fromJson(sampleAdvRulesJson());
      final kind = b.kindOf('gpa_below');
      final seeded = AdvRuleDraft.of(b.rules[0]);
      expect(seeded.nameAr, '');
      final custom = AdvRuleDraft.of(b.rules[1]);
      expect(custom.nameEn, 'Final academic warning');
      expect(custom.changedFrom(b.rules[1], kind), isFalse);
      expect(custom.copyWith(priority: 'high').changedFrom(b.rules[1], kind), isTrue);
      expect(AdvRuleDraft.of(b.rules[5]).categoryId, 12);
    });

    test('the preview reads, with its headline', () {
      final p = AdvRulePreview.fromJson(sampleAdvPreviewJson());
      expect(p.matches, 12);
      expect(p.sample.length, 2);
      expect(p.headline, '12 students of 342 match now');
      expect(AdvRulePreview.fromJson(sampleAdvPreviewJson(needsRun: true)).needsRun, isTrue);
      expect(const AdvRulePreview().headline, 'No student matches now');
      AppConfig.lang = 'ar';
      expect(p.headline, 'يطابقها 12 طالباً من 342 الآن');
    });
  });

  group('engine runs', () {
    test('a run parses; counts that do not apply are 0; a failed run says why', () {
      final r = AdvWarningRun.fromJson(sampleAdvRunJson(status: 'failed', error: 'stale', trigger: 'manual'));
      expect(r.failed, isTrue);
      expect(r.actor?.name, 'د. سلمى الحربي');
      expect(advWarnRunErrorText(r.error), contains('30 minutes'));
      final older = AdvWarningRun.fromJson({'id': 3, 'status': 'weird', 'trigger': 'student'});
      expect(older.running, isTrue);
      expect(older.trigger, 'student');
      expect(older.counts.students, 0);
      expect(AdvWarningRun.maybe(null), isNull);
      expect(AdvWarningRun.maybe({'id': 0}), isNull);
    });

    test('the counts in a sentence: an evaluation, a digest pass', () {
      expect(advRunCountsText(AdvWarningRun.fromJson(sampleAdvRunJson())), '342 students · 12 new alerts · 4 flags opened');
      expect(advRunCountsText(AdvWarningRun.fromJson(sampleAdvRunJson(kind: 'digest'))), '9 digests · 25 reminders');
      expect(advDurationText(4200), '4.2 s');
      expect(advDurationText(125000), '2 min');
    });
  });

  group('alerts', () {
    test('the alerts answer parses: student, rule, explanation, term, flag, delivery, facets', () {
      final p = AdvPage.fromJson(sampleAdvAlertsJson(), AdvAlert.fromJson);
      expect(p.items.length, 4);
      expect(p.restricted, 1);
      expect(p.facet('urgent'), 1);
      final a = p.items.first;
      expect(a.studentShown, 'ريم عبدالله القحطاني');
      expect(a.rule.id, 2);
      expect(a.delivery, 'urgent');
      expect(a.flagId, 801);
      expect(a.flagStatus, 'open');
      expect(a.explanationText, 'CGPA 1.42 is below 1.50');
      expect(a.term?.shown, contains('2026/2027'));
      expect(a.evidence['cgpa'], 1.42);
      final gone = p.items.last;
      expect(gone.rule.id, isNull);
      expect(gone.flagId, isNull);
      expect(gone.delivery, 'none');
      AppConfig.lang = 'ar';
      expect(a.explanationText, 'المعدل التراكمي 1.42 أقل من 1.50');
    });

    test('an alert without its explanation (an older server) says what its kind checks, in both languages', () {
      final a = AdvAlert.fromJson({'id': 1, 'member_id': 2, 'rule': {'kind': 'no_contact'}, 'delivery': 'unknown'});
      expect(a.explanationText, advWarningKindFallback('no_contact'));
      expect(a.delivery, 'pending');
      expect(a.studentShown, '#2');
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        for (final k in ['gpa_below', 'gpa_drop', 'failed_courses', 'repeated_fail', 'absence_pct', 'absence_count', 'no_contact', 'graduation_delay', 'midterm_fail', 'new_kind']) {
          expect(advWarningKindFallback(k), isNotEmpty);
          expect(advWarningKindFallback(k), isNot(k));
        }
      }
    });

    test('the alerts query: filters, since as UTC, counts', () {
      final since = DateTime.utc(2026, 11, 4, 7);
      final q = AdvAlertQuery(memberId: 31, priority: 'urgent', since: since, flag: 'open');
      expect(q.toQuery(), {'member_id': 31, 'priority': 'urgent', 'since': '2026-11-04T07:00:00.000Z', 'flag': 'open', 'page': 1, 'size': 25});
      expect(q.activeFilters, 4);
      expect(const AdvAlertQuery().activeFilters, 0);
      expect(q.copyWith(priority: () => null).priority, isNull);
    });
  });

  group('the 360 and graduation', () {
    test('the warning block parses; hits worst first; a held-back hit has no alert', () {
      final w = AdvWarning.fromJson(sampleAdvWarningJson());
      expect(w.evaluated, isTrue);
      expect(w.hits.first.priority, 'urgent');
      expect(w.hits.first.alertId, isNull);
      expect(w.hits.last.alertId, 502);
      expect(w.recent.length, 2);
      expect(w.restricted, 1);
      expect(w.canRun, isTrue);
      expect(w.graduation?.status, 'delayed');
      final fresh = AdvWarning.fromJson(sampleAdvWarningJson(evaluated: false));
      expect(fresh.evaluated, isFalse);
      expect(fresh.hits, isEmpty);
      final old = AdvWarning.fromJson(const {});
      expect(old.graduation, isNull);
      expect(old.canRun, isFalse);
    });

    test('graduation: credits, levels, unknown, graduated', () {
      final d = AdvGraduation.fromJson(sampleAdvGraduationBlock('delayed'));
      expect(d.credits, isTrue);
      expect(d.progress, closeTo(45 / 132, 1e-9));
      expect(d.progressWithCurrent, closeTo(57 / 132, 1e-9));
      expect(d.delayText, '3 terms late');
      expect(d.remaining, 87.0);
      expect(d.failedCount, 2);
      expect(d.failedCourses.first.name, 'Introduction to Programming');
      expect(d.failedCourses.first.attempts, 2);
      expect(d.delayedCourses.single.level, 'Level 1');
      expect(AdvGraduation.fromJson(sampleAdvGraduationBlock('at_risk')).failedCourses, isEmpty);
      expect(advGraduationReasonText('no_level'), contains('level'));
      expect(d.neededText, isNull);
      final r = AdvGraduation.fromJson(sampleAdvGraduationBlock('at_risk'));
      expect(r.neededText, 'Needs 17 credits each remaining term');
      expect(r.delayText, isNull);
      final l = AdvGraduation.fromJson(sampleAdvGraduationBlock('levels'));
      expect(l.basis, 'levels');
      expect(l.expectedLevel, 'الفرقة الثالثة');
      expect(l.progress, isNull);
      final u = AdvGraduation.fromJson(sampleAdvGraduationBlock('unknown'));
      expect(u.known, isFalse);
      expect(advGraduationReasonText(u.reason), contains('credit total'));
      expect(AdvGraduation.fromJson(const {'status': 'odd'}).status, 'unknown');
      expect(AdvGraduation.fromJson(sampleAdvGraduationBlock('graduated')).progress, 1.0);
      AppConfig.lang = 'ar';
      expect(d.delayText, 'متأخر 3 فصول');
      expect(d.failedCourses.first.name, 'مقدمة في البرمجة');
    });

    test('the graduation list parses with its facets; the query carries the filters', () {
      final p = AdvPage.fromJson(sampleAdvGraduationJson(), AdvGraduationItem.fromJson);
      expect(p.items.length, 4);
      expect(p.facet('delayed'), 1);
      expect(p.items.first.primary?.name, 'د. سلمى الحربي');
      expect(p.items.last.primary, isNull);
      expect(const AdvGraduationQuery(q: ' sara ').toQuery(), {'status': 'all', 'q': 'sara', 'page': 1, 'size': 25});
    });
  });

  group('alert delivery and settings', () {
    test('prefs parse; unknown values fall back', () {
      final p = AdvAlertPrefs.fromJson(sampleAdvPrefsJson());
      expect(p.digest, 'inherit');
      expect(p.effective, 'daily');
      expect(p.digestWeekday, 6);
      expect(p.timezone, 'Asia/Riyadh');
      final odd = AdvAlertPrefs.fromJson({'digest': 'hourly', 'effective': 'inherit', 'digest_hour': 40});
      expect(odd.digest, 'inherit');
      expect(odd.effective, 'off');
      expect(odd.digestHour, 23);
      expect(advWeekdayLabel(0), 'Monday');
      expect(advWeekdayLabel(6), 'Sunday');
    });

    test('the settings group inherits like the other settings', () {
      final b = AdvPolicyBundle.fromJson({
        'effective': {'digest': 'daily', 'digest_hour': 8, 'nudge_students': false},
        'defaults': {'digest': 'off', 'digest_hour': 7, 'digest_weekday': 6, 'nudge_after_days': 21, 'nudge_advisors': true, 'nudge_students': true},
        'org': {'id': 1, 'settings': {'digest': 'daily'}},
      });
      final org = advAlertInherited(b, 'org');
      expect(org.digest, 'off', reason: 'the organization sets digest: what it falls back to is the default');
      expect(org.digestHour, 8, reason: 'not set by the organization: the effective value (a parent)');
      final scope = advAlertInherited(b, 'program');
      expect(scope.digest, 'daily');
      expect(scope.nudgeStudents, isFalse);
      final shown = advAlertShown(scope, {'nudge_students': true, 'nudge_after_days': 30});
      expect(shown.nudgeStudents, isTrue);
      expect(shown.nudgeAfterDays, 30);
      expect(advAlertSettingsError({'digest_hour': 24}), isNotNull);
      expect(advAlertSettingsError({'nudge_after_days': 0}), isNotNull);
      expect(advAlertSettingsError({'digest_hour': 6}), isNull);
      expect(AdvAlertSettings.fromMap(const {}).nudgeAfterDays, 21);
    });
  });

  group('texts', () {
    test('every new server code has text in both languages', () {
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        final texts = advCodeTexts();
        for (final c in ['advising_bad_rule', 'advising_rule_system', 'advising_rule_limit', 'advising_run_busy']) {
          expect(texts[c], isNotNull, reason: c);
          expect(texts[c], isNotEmpty);
        }
      }
    });

    test('advising_bad_rule names the field and its limits', () {
      final kind = AdvRuleKind.fromJson(sampleAdvKindsJson().first);
      final e = ApiException(message: 'bad', statusCode: 422, code: 'advising_bad_rule', body: {
        'detail': {'code': 'advising_bad_rule', 'field': 'params.threshold', 'reason': 'out_of_range'},
      });
      expect(advWarningErrorText(e, kind: kind), '"Limit" is not accepted — it is between 0.50 and 5.00');
      final cd = ApiException(message: 'bad', statusCode: 422, code: 'advising_bad_rule', body: {
        'detail': {'code': 'advising_bad_rule', 'field': 'cooldown_days', 'reason': 'out_of_range'},
      });
      expect(advWarningErrorText(cd), contains('365'));
    });
  });
}
