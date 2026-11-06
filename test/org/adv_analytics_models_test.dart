// Academic Advising, Phase 8 (docs/advising/PHASE8.md): the analytics, compliance, health check and outreach answers
// parse (an older server that leaves blocks out still parses), hidden counts stay null ("fewer than 5", never 0),
// the filter and the audience build the server's query / body, and every new server code has text. The sample
// payloads are shared with test/ui/adv_analytics_layout_test.dart and test/visual/adv_analytics_golden_test.dart.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/advising/adv_analytics_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart' show AdvRef;
import 'package:flutter_education_app/features/org/advising/adv_texts.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _term(int id, String kind, String year, {bool current = false}) =>
    {'id': id, 'label': year, 'kind': kind, 'start': '2026-09-20', 'end': '2027-01-20', if (current) 'current': true};

Map<String, dynamic> sampleAdvOptionsJson({bool aggregate = false}) => {
      'terms': [_term(9, 'term1', '2026/2027', current: true), _term(8, 'term2', '2025/2026'), _term(7, 'term1', '2025/2026')],
      'programs': [
        {'id': 11, 'name': 'هندسة البرمجيات', 'name_en': 'Software Engineering'},
        {'id': 12, 'name': 'علوم الحاسب', 'name_en': 'Computer Science'},
      ],
      'levels': ['Level 1', 'Level 2', 'Level 3', 'Level 4'],
      'cohorts': ['2023', '2024', '2025'],
      'advisors': aggregate ? [] : [
        {'user_id': 31, 'name': 'د. هدى سالم'},
        {'user_id': 32, 'name': 'د. كريم نبيل'},
      ],
      'categories': [],
      'risk_bands': [],
      'gpa_bands': [],
      'probation_below': 2.0,
      'scale_max': 4.0,
      'metrics': [
        {'key': 'risk_band', 'label_ar': 'مستوى الخطر', 'label_en': 'Risk level', 'needs_key': true, 'needs_term': false},
      ],
      'tier': aggregate ? 'aggregate' : 'manage',
    };

List<Map<String, dynamic>> _points(List<String> keys, List<List<num>> rows) => [
      for (var i = 0; i < rows.length; i++) {'date': '2026-10-${(5 + i * 7).toString().padLeft(2, '0')}', for (var k = 0; k < keys.length; k++) keys[k]: rows[i][k]},
    ];

Map<String, dynamic> sampleAdvOverviewJson({bool aggregate = false}) {
  int? s(int v) => aggregate && v > 0 && v < 5 ? null : v;
  return {
    'generated_at': '2026-11-05T08:00:00',
    'range': {'from': '2026-09-20', 'to': '2026-11-05', 'days': 47, 'term': _term(9, 'term1', '2026/2027'), 'interval': 'week'},
    'filters': {'program_id': null, 'level': null, 'cohort': null, 'advisor_user_id': null},
    'viewer': {'tier': aggregate ? 'aggregate' : 'manage', 'drill': !aggregate, 'min_group': 5},
    'state_series': true,
    'kpis': {
      'students': {'value': 1240, 'previous': 1198},
      'unassigned': {'value': 18, 'previous': 42},
      'at_risk': {'value': 137, 'previous': 151},
      'meetings_completed': {'value': 412, 'previous': 350},
      'no_show_rate': {'value': 8.4, 'previous': 11.2},
      'avg_response_hours': {'value': 6.5, 'previous': 9.1},
      'alerts': {'value': 96, 'previous': 80},
      'complaints_open': {'value': 4, 'previous': null},
    },
    'students': {'total': 1240, 'assigned': 1222, 'unassigned': 18, 'advisor_away': 23, 'no_contact_term': 310, 'graduated': 0},
    'load': {
      'advisors': 34,
      'active_advisors': 29,
      'avg': 35.9,
      'max': 52,
      'over': 2,
      'warn': 5,
      'capacity_left': 138,
      'distribution': [
        {'key': 'empty', 'advisors': 1},
        {'key': 'under_50', 'advisors': 4},
        {'key': '50_79', 'advisors': 17},
        {'key': '80_99', 'advisors': 8},
        {'key': 'full', 'advisors': 2},
        {'key': 'over', 'advisors': 2},
      ],
      'top': [
        {'user_id': 31, 'name': 'د. هدى سالم', 'load': 52, 'max_load': 40, 'load_pct': 130, 'warn': true, 'over': true},
        {'user_id': 32, 'name': 'د. كريم نبيل', 'load': 41, 'max_load': 40, 'load_pct': 102.5, 'warn': true, 'over': true},
        {'user_id': 33, 'name': 'Dr. Sarah Ibrahim', 'load': 38, 'max_load': 40, 'load_pct': 95, 'warn': true, 'over': false},
      ],
    },
    'struggling': {
      'risk_bands': {'high': 42, 'medium': 95, 'low': 388, 'none': 715},
      'by_priority': {'low': s(21), 'normal': 38, 'high': 17, 'urgent': s(3)},
      'by_category': [
        {'category': {'id': 1, 'key': 'academic', 'name_ar': 'أكاديمي', 'name_en': 'Academic', 'sensitive': false}, 'students': 58, 'flags': 71, 'by_priority': {}},
        {'category': {'id': 2, 'key': 'attendance', 'name_ar': 'الحضور', 'name_en': 'Attendance', 'sensitive': false}, 'students': 33, 'flags': 35, 'by_priority': {}},
        if (aggregate)
          {'category': {'id': null, 'key': 'sensitive', 'name_ar': 'تصنيفات حساسة', 'name_en': 'Sensitive categories', 'sensitive': true}, 'students': null, 'flags': null, 'by_priority': {}}
        else
          {'category': {'id': 5, 'key': 'wellbeing', 'name_ar': 'الرفاه', 'name_en': 'Wellbeing', 'sensitive': true}, 'students': 4, 'flags': 4, 'by_priority': {}},
      ],
    },
    'risk_trend': {
      'points': [
        for (final (i, p) in _points(['alerts', 'opened', 'resolved'], [[12, 12, 8], [18, 18, 11], [9, 9, 14], [22, 22, 15], [15, 15, 19], [11, 11, 13], [9, 9, 10]]).indexed)
          {...p, 'at_risk': 151 - i * 2, 'high': 48 - i, 'avg_score': 21.5},
      ],
    },
    'gpa': {
      'scale_max': 4.0,
      'probation_below': 2.0,
      'avg_cgpa': 2.84,
      'no_gpa': 96,
      'distribution': [
        {'key': 'b0', 'from': 0.0, 'to': 1.0, 'students': s(3)},
        {'key': 'b1', 'from': 1.0, 'to': 2.0, 'students': 61},
        {'key': 'b2', 'from': 2.0, 'to': 2.5, 'students': 170},
        {'key': 'b3', 'from': 2.5, 'to': 3.0, 'students': 312},
        {'key': 'b4', 'from': 3.0, 'to': 3.5, 'students': 355},
        {'key': 'b5', 'from': 3.5, 'to': 4.0, 'students': 243},
        {'key': 'none', 'from': null, 'to': null, 'students': 96},
      ],
      'trend': [
        for (final (i, g) in [2.61, 2.66, 2.70, 2.74].indexed) {'term': _term(5 + i, i.isEven ? 'term1' : 'term2', '202${4 + i ~/ 2}/202${5 + i ~/ 2}'), 'students': 1100, 'avg_term_gpa': g, 'below_line': 70},
      ],
    },
    'meetings': {
      'booked': 498,
      'completed': 412,
      'no_show': 38,
      'cancelled': 48,
      'late_cancelled': 9,
      'upcoming': 64,
      'students_met': 377,
      'completion_rate': 91.6,
      'no_show_rate': 8.4,
      'by_mode': {'in_person': 280, 'video': 96, 'phone': 30, 'chat': 6},
      'points': _points(['completed', 'no_show', 'cancelled'], [[52, 6, 5], [61, 4, 8], [70, 7, 6], [66, 5, 9], [58, 6, 7], [55, 5, 6], [50, 5, 7]]),
    },
    'response': {
      'replies': 640,
      'avg_hours': 6.5,
      'sla_met_pct': 87.3,
      'awaiting_reply': 14,
      'buckets': {'lt_1h': 210, 'h1_4': 180, 'h4_24': 170, 'd1_3': 62, 'gt_3d': 18},
      'points': [for (final p in _points(['replies'], [[80], [92], [101], [95], [88], [97], [87]])) {...p, 'avg_hours': 7.1}],
    },
    'complaints': {'opened': 11, 'closed': 9, 'open_now': 4, 'escalated': 2, 'about_advisor': 1, 'avg_resolution_hours': 30.5, 'points': _points(['opened', 'closed'], [[2, 1], [1, 2], [3, 1], [2, 2], [1, 1], [1, 1], [1, 1]])},
    'requests': {
      'open': {'submitted': 9, 'needs_info': 3, 'in_review': 6, 'at_department_council': 4, 'at_faculty_council': 2},
      'referrals_open': 5,
      'overdue': 3,
      'decided': {'approved': 31, 'rejected': 6, 'withdrawn': 2, 'closed': 1},
      'referrals_decided': {'handled': 12, 'declined': 1},
      'approval_rate': 83.8,
      'avg_decision_days': 4.2,
      'by_type': [
        {'support_type': 'tutoring', 'label_ar': 'دروس تقوية', 'label_en': 'Tutoring', 'count': 14},
        {'support_type': 'accommodation', 'label_ar': 'تسهيلات', 'label_en': 'Accommodation', 'count': 9},
      ],
    },
    'activity': {'window_days': 14, 'advisors': 34, 'active': 29, 'inactive': 5, 'actions': {'meetings': 188, 'replies': 301, 'notes': 244, 'alerts_resolved': 57}},
    'outcomes': {
      'term': _term(8, 'term2', '2025/2026'),
      'as_of': '2026-11-05T02:10:00',
      'enrolled': 1180,
      'supported': 402,
      'at_risk': 160,
      'at_risk_supported': 118,
      'meetings_held': 690,
      'alerts_resolved': 140,
      'plans_completed': 21,
      'plans_met': 16,
      'gpa_change': {
        'supported': {'n': 402, 'avg': 0.18},
        'not_supported': {'n': 778, 'avg': 0.02},
        'at_risk_supported': {'n': 118, 'avg': 0.31},
        'at_risk_not_supported': {'n': 42, 'avg': -0.12},
      },
      'retention': {
        'all': {'n': 1180, 'retained': 1131, 'rate': 95.8},
        'supported': {'n': 402, 'retained': 391, 'rate': 97.3},
        'at_risk_supported': {'n': 118, 'retained': 109, 'rate': 92.4},
        'at_risk_not_supported': {'n': aggregate ? 4 : 42, 'retained': aggregate ? null : 33, 'rate': aggregate ? null : 78.6},
      },
    },
    'satisfaction': {'count': 214, 'average': 4.4, 'hidden': false},
    if (!aggregate) 'health': {'checked_at': '2026-11-05T02:20:00', 'issues': 4, 'critical': 1},
  };
}

Map<String, dynamic> sampleAdvHealthJson() => {
      'checked_at': '2026-11-05T02:20:00',
      'trigger': 'tick',
      'issues': 4,
      'critical': 1,
      'items': [
        {'key': 'unassigned_students', 'severity': 'warning', 'count': 18, 'label_ar': 'طلاب بلا مرشد', 'label_en': 'Students without an advisor', 'hint_ar': 'وزّعهم على المرشدين', 'hint_en': 'Distribute them to advisors', 'drill': {'metric': 'unassigned', 'key': null}, 'action': 'distribute', 'sample': []},
        {'key': 'stuck_requests', 'severity': 'critical', 'count': 3, 'label_ar': 'طلبات متوقفة', 'label_en': 'Stuck requests', 'hint_ar': 'تأخرت خطوتها الحالية أكثر من 7 أيام', 'hint_en': 'Their current step is over 7 days late', 'drill': {'metric': 'stuck_request', 'key': null}, 'action': 'open_requests', 'sample': []},
        {'key': 'advisors_over_capacity', 'severity': 'warning', 'count': 2, 'label_ar': 'مرشدون فوق الحد الأقصى', 'label_en': 'Advisors over their maximum', 'hint_ar': '', 'hint_en': '', 'drill': null, 'action': 'rebalance', 'sample': [
          {'user_id': 31, 'name': 'د. هدى سالم', 'value': 52},
          {'user_id': 32, 'name': 'د. كريم نبيل', 'value': 41},
        ]},
        {'key': 'advisors_without_hours', 'severity': 'info', 'count': 3, 'label_ar': 'مرشدون بلا ساعات مكتبية', 'label_en': 'Advisors without office hours', 'hint_ar': '', 'hint_en': '', 'drill': null, 'action': 'open_advisors', 'sample': []},
        {'key': 'orphaned_flags', 'severity': 'ok', 'count': 0, 'label_ar': 'تنبيهات لطلاب غادروا', 'label_en': 'Alerts of students who left', 'drill': null, 'action': null, 'sample': []},
      ],
      'previous': {'checked_at': '2026-11-04T02:20:00', 'issues': 6, 'critical': 1},
    };

Map<String, dynamic> _crow(int? id, String name, {int? advisees = 36, int? contacted = 31, double? cov = 86.1, bool? meets = true}) => {
      'user_id': id,
      'name': name,
      'advisees': advisees,
      'contacted': contacted,
      'coverage_pct': cov,
      'contacts': 58,
      'contacts_per_student': 1.6,
      'meetings_completed': 40,
      'no_shows': 3,
      'no_show_rate': 7.0,
      'alerts': 9,
      'alerts_resolved': 7,
      'avg_resolution_days': 3.4,
      'avg_first_contact_days': 12.5,
      'replies': 44,
      'avg_response_hours': 5.2,
      'at_risk': 6,
      'at_risk_contacted': 6,
      'supported_gpa_change': 0.21,
      'retained_pct': 97.2,
      'meets_target': meets,
    };

Map<String, dynamic> sampleAdvComplianceJson({bool pending = false}) => {
      'term': _term(8, 'term2', '2025/2026'),
      'as_of': pending ? null : '2026-11-05T02:10:00',
      'pending': pending,
      'targets': {'coverage_pct': 80, 'min_contacts': 1},
      'total': _crow(null, '', advisees: 1180, contacted: 960, cov: 81.4, meets: null),
      'advisors': [
        _crow(31, 'د. هدى سالم'),
        _crow(32, 'د. كريم نبيل', contacted: 22, cov: 61.1, meets: false),
        _crow(33, 'Dr. Sarah Ibrahim', advisees: null, contacted: null, cov: 75.0, meets: null),
      ],
    };

Map<String, dynamic> sampleAdvAdvisorsJson() => {
      'items': [
        for (final (i, n) in ['د. هدى سالم', 'د. كريم نبيل', 'Dr. Sarah Ibrahim'].indexed)
          {
            'user_id': 31 + i,
            'name': n,
            'status': i == 2 ? 'leave' : 'available',
            'away': i == 2,
            'load': 52 - i * 7,
            'max_load': 40,
            'load_pct': (52 - i * 7) / 40 * 100,
            'warn': true,
            'over': i < 2,
            'students': {'at_risk': i == 2 ? null : 9 - i, 'high_risk': 3, 'no_contact_term': 12 - i * 3},
            'meetings': {'completed': 40 - i * 9, 'no_show': 3, 'cancelled': 2, 'no_show_rate': 7.0},
            'replies': 44,
            'avg_response_hours': 5.2 + i,
            'sla_met_pct': 88.0 - i * 9,
            'notes': 30,
            'alerts_resolved': 7,
            'last_active_at': '2026-11-0${4 - i}T10:00:00',
            'active': i != 2,
            'satisfaction': {'count': 12, 'average': 4.5, 'hidden': false},
          },
      ],
      'total': 3,
      'page': 1,
      'size': 25,
      'pages': 1,
      'facets': {'active': 2, 'inactive': 1, 'over': 2, 'warn': 3},
    };

Map<String, dynamic> sampleAdvOutreachJson({String status = 'sent', bool detail = true}) => {
      'id': 77,
      'subject': 'تذكير: مراجعة الخطة الدراسية قبل التسجيل',
      'sender': {'user_id': 31, 'name': 'د. هدى سالم'},
      'label': {'ar': 'خطر مرتفع · الفصل الحالي', 'en': 'High risk · current term'},
      'status': status,
      'email': true,
      'created_at': '2026-11-04T09:30:00',
      'finished_at': '2026-11-04T09:31:00',
      'counts': {'recipients': 42, 'delivered': 41, 'pushed': 37, 'read': 29, 'failed': 1, 'capped': 2, 'out_of_scope': 0},
      'read_rate': 69.0,
      if (detail) 'body': 'مرحباً {student_name}،\nنرجو حجز لقاء مع مرشدك قبل فتح التسجيل لمراجعة خطتك الدراسية.',
      if (detail) 'audience': {'metric': 'risk_band', 'key': 'high'},
      if (detail) 'template_id': null,
    };

Map<String, dynamic> sampleAdvRecipientsJson() => {
      'items': [
        {'member_id': 601, 'name': 'سارة أحمد', 'code': '2023001', 'status': 'delivered', 'pushed': true, 'delivered_at': '2026-11-04T09:30:10', 'read_at': '2026-11-04T11:02:00'},
        {'member_id': 602, 'name': 'Omar Khaled', 'code': '2023002', 'status': 'delivered', 'pushed': true, 'delivered_at': '2026-11-04T09:30:10', 'read_at': null},
        {'member_id': 603, 'name': 'ليلى حسن', 'code': '2023003', 'status': 'failed', 'pushed': false, 'delivered_at': null, 'read_at': null},
      ],
      'total': 42,
      'page': 1,
      'size': 25,
      'pages': 2,
      'facets': {'unread': 12, 'read': 29, 'failed': 1},
    };

Map<String, dynamic> sampleAdvPreviewJson({int count = 42}) => {
      'count': count,
      'audience_hash': '3f2a9c0d11e4b7a8',
      'excluded': {'out_of_scope': 0, 'capped': 2},
      'sample': [
        {'member_id': 601, 'name': 'سارة أحمد', 'code': '2023001'},
        {'member_id': 602, 'name': 'Omar Khaled', 'code': '2023002'},
      ],
      'label': {'ar': 'خطر مرتفع · الفصل الحالي', 'en': 'High risk · current term'},
    };

Map<String, dynamic> sampleAdvStudentMessageJson({bool read = false}) => {
      'id': 77,
      'subject': 'تذكير: مراجعة الخطة الدراسية قبل التسجيل',
      'body': 'مرحباً سارة،\nنرجو حجز لقاء مع مرشدك قبل فتح التسجيل لمراجعة خطتك الدراسية.',
      'sender_name': 'د. هدى سالم',
      'sent_at': '2026-11-04T09:30:00',
      'read_at': read ? '2026-11-04T11:02:00' : null,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('overview', () {
    test('parses every section', () {
      final o = AdvOverview.fromJson(sampleAdvOverviewJson());
      expect(o.viewer.aggregate, isFalse);
      expect(o.range.term?.title, 'First term 2026/2027');
      expect(o.range.days, 47);
      expect(o.kpi('students').value, 1240);
      expect(o.kpi('unassigned').delta!.round(), -57);
      expect(o.load.distribution['50_79'], 17);
      expect(o.load.top.first.over, isTrue);
      expect(o.struggling.atRisk, 137);
      expect(o.riskTrend, hasLength(7));
      expect(o.gpa.distribution.first.label, '0.00 – 1.00');
      expect(o.gpa.distribution.last.label, 'No CGPA yet');
      expect(o.meetings.points.first.of('completed'), 52);
      expect(o.response.buckets['lt_1h'], 210);
      expect(o.requests.openTotal, 24);
      expect(o.outcomes.gpaChange['at_risk_not_supported']!.avg, -0.12);
      expect(o.outcomes.pending, isFalse);
      expect(o.health!.critical, 1);
      expect(o.empty, isFalse);
    });

    test('aggregate tier: hidden counts stay null, the sensitive row is folded', () {
      final o = AdvOverview.fromJson(sampleAdvOverviewJson(aggregate: true));
      expect(o.viewer.aggregate, isTrue);
      expect(o.viewer.drill, isFalse);
      expect(o.struggling.byPriority['urgent'], isNull);
      expect(o.struggling.byPriority['normal'], 38);
      expect(o.gpa.distribution.first.students, isNull);
      final folded = o.struggling.byCategory.last.category;
      expect(folded.folded, isTrue);
      expect(folded.name, 'Sensitive categories');
      expect(o.outcomes.retention['at_risk_not_supported']!.retained, isNull);
      expect(o.health, isNull);
    });

    test('an older server (empty body) parses to zeros', () {
      final o = AdvOverview.fromJson(const {});
      expect(o.empty, isTrue);
      expect(o.kpi('students').value, isNull);
      expect(o.outcomes.pending, isTrue);
      expect(o.stateSeries, isTrue);
      expect(o.satisfaction, isNull);
      expect(advCount(const {}, 'x'), 0);
      expect(advCount(const {'x': null}, 'x'), isNull);
    });
  });

  group('filter', () {
    test('query and range rules', () {
      final f = AdvAnalyticsFilter(programId: 11, cohort: '2024', advisor: const AdvRef(userId: 31, name: 'x')).withDates(DateTime(2026, 9, 1), DateTime(2026, 10, 1));
      expect(f.toQuery(), {'from': '2026-09-01', 'to': '2026-10-01', 'program_id': 11, 'cohort': '2024', 'advisor_user_id': 31});
      expect(f.hasStudentFilter, isTrue);
      expect(f.activeFilters, 4);
      expect(f.rangeError, isNull);
      expect(f.withTerm(8).toQuery()['term_id'], 8);
      expect(f.withTerm(8).toQuery().containsKey('from'), isFalse);
      expect(const AdvAnalyticsFilter().withDates(DateTime(2026, 2, 1), DateTime(2026, 1, 1)).rangeError, isNotNull);
      expect(const AdvAnalyticsFilter().withDates(DateTime(2025, 1, 1), DateTime(2026, 6, 1)).rangeError, isNotNull);
      expect(const AdvAnalyticsFilter().toQuery(), isEmpty);
    });
  });

  group('drill, compliance, health, runs', () {
    test('drill query', () {
      expect(const AdvDrill(metric: 'outreach', key: '77', state: 'unread').toQuery(), {'metric': 'outreach', 'key': '77', 'state': 'unread'});
      expect(advMetricLabel('gpa_band'), 'CGPA band');
    });

    test('compliance', () {
      final c = AdvCompliance.fromJson(sampleAdvComplianceJson());
      expect(c.total!.total, isTrue);
      expect(c.total!.shown, 'Whole organization');
      expect(c.meeting, 1);
      expect(c.missing, 1);
      expect(c.advisors[2].advisees, isNull);
      expect(AdvCompliance.fromJson(sampleAdvComplianceJson(pending: true)).pending, isTrue);
    });

    test('health: problems worst first', () {
      final h = AdvHealth.fromJson(sampleAdvHealthJson());
      expect(h.problems.map((i) => i.key).toList(), ['stuck_requests', 'unassigned_students', 'advisors_over_capacity', 'advisors_without_hours']);
      expect(h.problems[1].drill?.metric, 'unassigned');
      expect(h.change, -2);
      expect(AdvHealth.fromJson(const {}).neverChecked, isTrue);
    });

    test('advisors', () {
      final a = AdvAdvisorStat.fromJson((sampleAdvAdvisorsJson()['items'] as List).last as Map<String, dynamic>);
      expect(a.atRisk, isNull);
      expect(a.active, isFalse);
      expect(a.satisfaction!.average, 4.5);
    });

    test('run', () {
      final r = AdvAnalyticsRun.fromJson({'id': 3, 'kind': 'daily', 'status': 'failed', 'error': 'stale', 'counts': {'students': 10}});
      expect(r.failed, isTrue);
      expect(r.counts['students'], 10);
    });
  });

  group('outreach', () {
    test('audience body', () {
      final a = AdvAudience.of(const AdvDrill(metric: 'risk_band', key: 'high'), const AdvAnalyticsFilter(programId: 11, termId: 8), q: ' sa ');
      expect(a.toJson(), {'metric': 'risk_band', 'key': 'high', 'program_id': 11, 'term_id': 8, 'q': 'sa'});
      expect(AdvAudience.members([5, 5, 6]).toJson(), {'metric': 'all', 'member_ids': [5, 6]});
      expect(AdvAudience.fromJson({'metric': 'outreach', 'key': '77', 'state': 'unread'}).toJson(), {'metric': 'outreach', 'key': '77', 'state': 'unread'});
    });

    test('draft rules and body', () {
      const d = AdvOutreachDraft(clientId: 'c1');
      expect(d.error, isNotNull);
      final ok = d.copyWith(subject: ' Hi ', body: 'Hello {student_name}', email: true);
      expect(ok.error, isNull);
      final j = ok.toJson(const AdvAudience(metric: 'all'), 'h');
      expect(j['subject'], 'Hi');
      expect(j['client_id'], 'c1');
      expect(j['email'], isTrue);
      expect(d.copyWith(subject: 'x', body: 'y' * 5001).error, isNotNull);
    });

    test('placeholders are plain text', () {
      final (text, at) = advInsertToken('Dear', '{student_name}', 4);
      expect(text, 'Dear {student_name}');
      expect(at, text.length);
      expect(advFillPlaceholders('Hi {student_name} {x.__class__}', {'{student_name}': 'Sara'}), 'Hi Sara {x.__class__}');
    });

    test('preview, outreach, recipients, student message', () {
      final p = AdvOutreachPreview.fromJson(sampleAdvPreviewJson());
      expect(p.capped, 2);
      expect(p.label, 'High risk · current term');
      final o = AdvOutreach.fromJson(sampleAdvOutreachJson());
      expect(o.unread, 12);
      expect(o.audience!.metric, 'risk_band');
      expect(o.inFlight, isFalse);
      expect(AdvOutreach.fromJson(sampleAdvOutreachJson(detail: false)).body, isNull);
      final r = AdvOutreachRecipient.fromJson((sampleAdvRecipientsJson()['items'] as List).first as Map<String, dynamic>);
      expect(r.read, isTrue);
      final m = AdvStudentMessage.fromJson(sampleAdvStudentMessageJson());
      expect(m.unread, isTrue);
      expect(m.markedRead(DateTime.utc(2026)).unread, isFalse);
      expect(AdvHubOutreach.fromJson({'unread': 2, 'latest': [sampleAdvStudentMessageJson()]}).latest, hasLength(1));
    });

    test('status keys', () {
      final me = AdvAnalyticsMe.fromStatus({'me': {'analytics': 'aggregate', 'outreach': false, 'health_issues': 0}});
      expect(me.any, isTrue);
      expect(me.manage, isFalse);
      expect(AdvAnalyticsMe.fromStatus(const {}).any, isFalse);
    });
  });

  test('every new code has text in both languages', () {
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      final m = advCodeTexts();
      for (final code in ['advising_bad_range', 'advising_bad_metric', 'advising_run_busy', 'advising_bad_template', 'advising_audience_empty', 'advising_audience_too_large', 'advising_audience_changed']) {
        expect(m[code], isNotEmpty, reason: '$code $lang');
      }
    }
  });
}
