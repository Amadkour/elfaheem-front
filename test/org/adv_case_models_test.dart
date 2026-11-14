// Academic Advising, Phase 4 (docs/advising/PHASE4.md): the workspace, the student 360, categories, flags and their
// lifecycle, notes, the timeline and the `advising` key of /org/mine. The answers parse (an older server that leaves
// keys out still parses), the drafts build the WHOLE-object bodies, the flag transitions mirror flags_flow.py, every
// risk reason and every new server code has text in both languages. The sample payloads are shared with
// test/ui/adv_case_layout_test.dart and test/visual/adv_case_golden_test.dart.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart' show advErrorText;
import 'package:flutter_education_app/features/org/advising/adv_texts.dart';
import 'package:flutter_test/flutter_test.dart';

/// The clock the samples are written against.
final advCaseNow = DateTime.utc(2026, 11, 5, 10);

Map<String, dynamic> _item(
  int member,
  String name, {
  String? code,
  String program = 'Software Engineering',
  String level = 'Level 3',
  String cohort = '2023',
  String? standing = 'good',
  double? cgpa,
  double? lastTerm,
  double? absence,
  int failed = 0,
  Map<String, int> flags = const {},
  List<String> categories = const [],
  int score = 0,
  List<Map<String, dynamic>> reasons = const [],
  String? contact,
  Map<String, dynamic>? primary,
}) =>
    {
      'member_id': member,
      'user_id': member + 1000,
      'name': name,
      'code': code,
      'program': program,
      'level': level,
      'cohort': cohort,
      'standing': standing,
      'cgpa': cgpa,
      'last_term_gpa': lastTerm,
      'absence_max': absence,
      'failed_count': failed,
      'open_flags': {'low': 0, 'normal': 0, 'high': 0, 'urgent': 0, ...flags},
      'categories': categories,
      'risk_score': score,
      'risk_reasons': reasons,
      'last_contact_at': contact,
      'primary': primary,
    };

const _huda = {'user_id': 31, 'name': 'د. هدى سالم'};
const _omar = {'user_id': 32, 'name': 'Prof. Omar Khaled'};

/// `GET …/workspace`: risk-sorted, many flags, long names, a student never contacted.
Map<String, dynamic> sampleAdvWorkspaceJson() => {
      'items': [
        _item(601, 'عبد الرحمن محمد عبد العزيز الشناوي', code: '2023041', standing: 'probation', cgpa: 1.62, lastTerm: 1.1, absence: 27.5, failed: 3,
            flags: {'urgent': 1, 'high': 2}, categories: ['academic', 'psychological', 'financial', 'health'], score: 88, reasons: [
          {'code': 'cgpa_low', 'value': 1.62, 'points': 25},
          {'code': 'absence_high', 'value': 27.5, 'points': 20},
          {'code': 'failed_courses', 'value': 3, 'points': 15},
          {'code': 'open_flags', 'value': 15, 'points': 15},
          {'code': 'no_contact', 'value': null, 'points': 10},
        ], primary: _huda),
        _item(602, 'Mona Ibrahim', code: '2023077', cgpa: 2.31, lastTerm: 1.84, absence: 16, failed: 1, flags: {'normal': 1}, categories: ['academic'], score: 46, reasons: [
          {'code': 'gpa_drop', 'value': 0.47},
          {'code': 'absence_high', 'value': 16},
          {'code': 'failed_courses', 'value': 1},
        ], contact: '2026-10-12T09:30:00', primary: _omar),
        _item(603, 'Sara Nabil Abdelaziz Mohamed El-Sayed', code: '2023118', program: 'Artificial Intelligence and Data Science', cgpa: 2.9, lastTerm: 3.1, absence: 4,
            score: 10, reasons: [
          {'code': 'no_contact', 'value': 41},
        ], contact: '2026-09-25T11:00:00', primary: _huda),
        _item(604, 'يوسف خالد', code: '2023003', standing: 'honours', cgpa: 3.82, lastTerm: 3.9, absence: 0, score: 0, contact: '2026-11-03T08:00:00', primary: _omar),
      ],
      'total': 38,
      'page': 1,
      'size': 25,
      'pages': 2,
      'facets': {'open': 9, 'urgent': 2, 'no_contact_30d': 11, 'total': 38},
    };

/// `GET …/categories`: the seeded ones (accessibility with its accommodations) and one the director added.
Map<String, dynamic> sampleAdvCategoriesJson() => {
      'items': [
        {'id': 1, 'key': 'academic', 'name_ar': 'أكاديمي', 'name_en': 'Academic', 'sensitive': false, 'system': true, 'active': true, 'accommodations': []},
        {'id': 2, 'key': 'financial', 'name_ar': 'مالي', 'name_en': 'Financial', 'sensitive': true, 'system': true, 'active': true, 'accommodations': []},
        {'id': 3, 'key': 'career', 'name_ar': 'مهني', 'name_en': 'Career', 'sensitive': false, 'system': true, 'active': true, 'accommodations': []},
        {'id': 4, 'key': 'health', 'name_ar': 'صحي', 'name_en': 'Health', 'sensitive': true, 'system': true, 'active': true, 'accommodations': []},
        {'id': 5, 'key': 'psychological', 'name_ar': 'نفسي واجتماعي', 'name_en': 'Psychological and social', 'sensitive': true, 'system': true, 'active': true, 'accommodations': []},
        {'id': 6, 'key': 'disciplinary', 'name_ar': 'انضباطي', 'name_en': 'Disciplinary', 'sensitive': false, 'system': true, 'active': false, 'accommodations': []},
        {
          'id': 7,
          'key': 'accessibility',
          'name_ar': 'احتياجات خاصة وإتاحة',
          'name_en': 'Accessibility',
          'sensitive': true,
          'system': true,
          'active': true,
          'accommodations': [
            {'key': 'extra_time', 'label_ar': 'وقت إضافي في الامتحانات', 'label_en': 'Extra exam time'},
            {'key': 'accessible_room', 'label_ar': 'قاعة ميسّرة الوصول', 'label_en': 'Accessible room'},
            {'key': 'note_taker', 'label_ar': 'مدوّن ملاحظات', 'label_en': 'Note-taker'},
            {'key': 'recorded_lectures', 'label_ar': 'محاضرات مسجّلة', 'label_en': 'Recorded lectures'},
            {'key': 'front_seating', 'label_ar': 'مقعد في الصفوف الأمامية', 'label_en': 'Front seating'},
            {'key': 'alt_format', 'label_ar': 'مواد بصيغة بديلة', 'label_en': 'Materials in an alternative format'},
          ],
        },
        {'id': 8, 'key': 'other', 'name_ar': 'أخرى', 'name_en': 'Other', 'sensitive': false, 'system': true, 'active': true, 'accommodations': []},
        {'id': 9, 'key': 'c_housing', 'name_ar': 'السكن الجامعي', 'name_en': 'University housing', 'sensitive': false, 'system': false, 'active': true, 'accommodations': []},
      ],
    };

Map<String, dynamic> _cat(int id) => (sampleAdvCategoriesJson()['items'] as List).cast<Map<String, dynamic>>().firstWhere((c) => c['id'] == id);

/// `GET …/students/601/flags?status=all`: open, escalated, overdue, accommodations, resolved with an outcome.
Map<String, dynamic> sampleAdvFlagsJson() => {
      'items': [
        {
          'id': 71,
          'category': _cat(1),
          'priority': 'urgent',
          'status': 'open',
          'source': 'manual',
          'note': 'غاب عن ثلاث محاضرات متتالية في مقرر هياكل البيانات ولم يسلّم المشروع الأول. يحتاج لقاء عاجلاً قبل امتحان منتصف الفصل.',
          'outcome_note': null,
          'review_due_at': '2026-11-02T12:00:00',
          'owner': _huda,
          'accommodations': [],
          'created_by': _huda,
          'created_at': '2026-10-28T09:12:00',
          'updated_at': '2026-10-28T09:12:00',
          'resolved_at': null,
          'resolved_in_hours': null,
          'escalated_at': '2026-10-28T13:12:00',
          'overdue': true,
          'allowed_next': ['acknowledged', 'contacted', 'resolved', 'dismissed'],
        },
        {
          'id': 72,
          'category': _cat(7),
          'priority': 'high',
          'status': 'contacted',
          'source': 'manual',
          'note': 'Hearing impairment confirmed by the medical centre; needs the lectures recorded and a front seat.',
          'outcome_note': null,
          'review_due_at': '2026-11-20T12:00:00',
          'owner': _omar,
          'accommodations': ['recorded_lectures', 'front_seating', 'extra_time'],
          'created_by': _huda,
          'created_at': '2026-10-15T10:00:00',
          'updated_at': '2026-10-20T10:00:00',
          'resolved_at': null,
          'resolved_in_hours': null,
          'escalated_at': null,
          'overdue': false,
        },
        {
          'id': 73,
          'category': _cat(2),
          'priority': 'normal',
          'status': 'resolved',
          'source': 'rule',
          'note': null,
          'outcome_note': 'حُوّل إلى صندوق دعم الطلاب وصُرفت منحة الفصل الدراسي.',
          'review_due_at': null,
          'owner': _huda,
          'accommodations': [],
          'created_by': null,
          'created_at': '2026-09-20T08:00:00',
          'updated_at': '2026-09-23T08:00:00',
          'resolved_at': '2026-09-23T08:00:00',
          'resolved_in_hours': 72,
          'escalated_at': null,
          'overdue': false,
          'allowed_next': <String>[],
          'reopened_at': null,
        },
      ],
      'total': 3,
      'restricted': 2,
    };

/// `GET …/flags/71/history`.
Map<String, dynamic> sampleAdvFlagHistoryJson() => {
      'items': [
        {'at': '2026-10-28T13:12:00', 'actor': null, 'action': 'advising.flag_escalated', 'before': {'escalated_at': null}, 'after': {'escalated_at': '2026-10-28T13:12:00'}},
        {'at': '2026-10-28T09:30:00', 'actor': 'د. هدى سالم', 'action': 'advising.flag_update', 'before': {'priority': 'high'}, 'after': {'priority': 'urgent'}},
        {'at': '2026-10-28T09:12:00', 'actor': {'user_id': 31, 'name': 'د. هدى سالم'}, 'action': 'advising.flag_create', 'before': null, 'after': {'status': 'open'}},
      ],
    };

/// `GET …/students/601/notes`: mine (team, a logged call), a co-advisor's private-to-the-team note, sensitive.
Map<String, dynamic> sampleAdvNotesJson() => {
      'items': [
        {
          'id': 91,
          'author': _huda,
          'visibility': 'team',
          'sensitive': false,
          'category': _cat(1),
          'body': 'اتصلت بالطالب هاتفياً: يعمل مساءً لإعالة أسرته ويصل متأخراً. اتفقنا على نقل شعبة العملي إلى الصباح ومراجعة الخطة بعد أسبوعين.',
          'contact_mode': 'phone',
          'contact_at': '2026-10-29T16:20:00',
          'created_at': '2026-10-29T16:45:00',
          'edited_at': null,
          'mine': true,
          'client_id': 'nmh2k1abc0',
        },
        {
          'id': 92,
          'author': _omar,
          'visibility': 'student',
          'sensitive': false,
          'category': null,
          'body': 'Agreed study plan for the midterms: two tutoring sessions a week with the TA, and a weekly check-in by e-mail.',
          'contact_mode': null,
          'contact_at': null,
          'created_at': '2026-10-21T11:00:00',
          'edited_at': '2026-10-21T12:10:00',
          'mine': false,
        },
        {
          'id': 93,
          'author': _huda,
          'visibility': 'private',
          'sensitive': true,
          'category': _cat(5),
          'body': 'ذكر الطالب ضغوطاً نفسية بعد وفاة والده. اقترحت عليه زيارة مركز الإرشاد النفسي وسأتابع معه.',
          'contact_mode': 'in_person',
          'contact_at': '2026-10-10T10:00:00',
          'created_at': '2026-10-10T10:40:00',
          'edited_at': null,
          'mine': true,
        },
      ],
      'total': 7,
      'page': 1,
      'size': 20,
      'pages': 1,
      'restricted': 4,
    };

/// `GET …/students/601/timeline`.
Map<String, dynamic> sampleAdvTimelineJson() => {
      'items': [
        {'at': '2026-10-29T16:45:00', 'kind': 'contact', 'ref_id': 91, 'actor': 'د. هدى سالم', 'data': {'mode': 'phone'}},
        {'at': '2026-10-29T16:45:00', 'kind': 'note', 'ref_id': 91, 'actor': 'د. هدى سالم', 'data': {'visibility': 'team', 'sensitive': false}},
        {'at': '2026-10-28T09:12:00', 'kind': 'flag_opened', 'ref_id': 71, 'actor': 'د. هدى سالم', 'data': {'category': 'academic', 'priority': 'urgent'}},
        {'at': '2026-10-20T10:00:00', 'kind': 'flag_status', 'ref_id': 72, 'actor': {'user_id': 32, 'name': 'Prof. Omar Khaled'}, 'data': {'from': 'open', 'to': 'contacted', 'category': _cat(7)}},
        {'at': '2026-03-01T09:00:00', 'kind': 'handover', 'ref_id': 12, 'actor': 'Prof. Omar Khaled', 'data': {'from': 'د. ليلى منصور', 'to': _huda}},
        {'at': '2025-09-14T08:00:00', 'kind': 'assigned', 'ref_id': 5, 'actor': null, 'data': {'advisor': {'user_id': 33, 'name': 'د. ليلى منصور'}, 'type': 'primary'}},
      ],
      'next': '2025-09-14T08:00:00',
    };

Map<String, dynamic> _course(String code, String ar, String en, double credits, String? letter, {String status = 'completed', double absence = 0, bool denied = false, int attempt = 1}) => {
      'registration_id': code.hashCode,
      'course_id': code.hashCode,
      'code': code,
      'name_ar': ar,
      'name_en': en,
      'credits': credits,
      'status': status,
      'letter': letter,
      'points': null,
      'counted': true,
      'attempt': attempt,
      'condition': null,
      'absence_pct': absence,
      'denied': denied,
    };

Map<String, dynamic> _term(int id, String kind, String year, double? gpa, List<Map<String, dynamic>> courses) => {
      'term': {'id': id, 'year_label': year, 'kind': kind, 'start_date': '2025-09-01', 'end_date': '2026-01-20', 'calendar': null, 'window': 'closed'},
      'courses': courses,
      'term_gpa': gpa,
    };

/// `GET …/students/601/profile`. [academic] false: an organization without the registrar.
Map<String, dynamic> sampleAdvProfileJson({bool academic = true, bool manage = true}) {
  final st = sampleAdvWorkspaceJson()['items'][0] as Map<String, dynamic>;
  return {
    'student': {
      'member_id': 601,
      'user_id': 1601,
      'name': st['name'],
      'code': st['code'],
      'program': {'id': 11, 'name': 'هندسة البرمجيات', 'name_en': 'Software Engineering'},
      'level': 'Level 3',
      'cohort': '2023',
      'standing': 'probation',
      'joined_at': '2023-09-10T08:00:00',
    },
    'advisors': [
      {'user_id': 32, 'name': 'Prof. Omar Khaled', 'type': 'co', 'since': '2026-01-10T08:00:00', 'locked': false},
      {'user_id': 31, 'name': 'د. هدى سالم', 'type': 'primary', 'since': '2026-03-01T09:00:00', 'locked': true},
    ],
    'stats': {...st, 'meetings_term': 2},
    'academic': academic
        ? {
            'student_id': 1601,
            'cgpa': 1.62,
            'earned': 54.0,
            'attempted': 72,
            'standing': 'probation',
            'stage': 'program',
            'advisor_id': 31,
            'level': 'Level 3',
            'program': {'id': 11, 'code': 'SE', 'name_ar': 'هندسة البرمجيات', 'name_en': 'Software Engineering', 'system_type': 'credit_hour'},
            'terms': [
              _term(41, 'term1', '2025-2026', 2.08, [
                _course('CS201', 'هياكل البيانات', 'Data Structures', 3, 'C'),
                _course('CS211', 'تنظيم الحاسب ولغة التجميع', 'Computer Organization and Assembly Language', 3, 'D+', absence: 12),
                _course('MA201', 'الرياضيات المتقطعة', 'Discrete Mathematics', 3, 'F', absence: 18),
              ]),
              _term(42, 'term2', '2025-2026', 1.1, [
                _course('CS221', 'الخوارزميات', 'Algorithms', 3, 'F', absence: 27.5, denied: true),
                _course('SE201', 'مقدمة في هندسة البرمجيات', 'Introduction to Software Engineering', 3, 'D'),
                _course('MA201', 'الرياضيات المتقطعة', 'Discrete Mathematics', 3, 'F', attempt: 2),
              ]),
              _term(43, 'term1', '2026-2027', null, [
                _course('CS301', 'قواعد البيانات', 'Databases', 3, null, status: 'registered', absence: 9),
                _course('CS305', 'شبكات الحاسب', 'Computer Networks', 3, null, status: 'registered'),
                _course('HU101', 'مهارات الاتصال', 'Communication Skills', 2, null, status: 'withdrawn'),
              ]),
            ],
            'audit': {'eligible': false},
          }
        : null,
    'gpa_trend': academic
        ? [
            {'term_id': 39, 'kind': 'term1', 'label': '2024-2025', 'term_gpa': 2.71, 'cgpa': 2.71},
            {'term_id': 40, 'kind': 'term2', 'label': '2024-2025', 'term_gpa': 2.2, 'cgpa': 2.45},
            {'term_id': 41, 'kind': 'term1', 'label': '2025-2026', 'term_gpa': 2.08, 'cgpa': 2.33},
            {'term_id': 42, 'kind': 'term2', 'label': '2025-2026', 'term_gpa': 1.1, 'cgpa': 1.62},
          ]
        : [],
    'counts': {'flags_open': 3, 'notes': 7, 'restricted': 6, 'handovers': 1},
    'can': {'flag': true, 'note': true, 'assign': manage, 'sensitive': true},
  };
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('workspace', () {
    test('items parse: numbers, flags by priority, reasons, the primary advisor; facets and paging', () {
      final p = AdvPage.fromJson(sampleAdvWorkspaceJson(), AdvCaseItem.fromJson);
      expect(p.total, 38);
      expect(p.pages, 2);
      expect(p.facet('urgent'), 2);
      expect(p.facet('no_contact_30d'), 11);
      final a = p.items.first;
      expect(a.memberId, 601);
      expect(a.cgpa, 1.62);
      expect(a.absenceMax, 27.5);
      expect(a.failedCount, 3);
      expect(a.openFlags.total, 3);
      expect(a.openFlags.highest, 'urgent');
      expect(a.openFlags.of('high'), 2);
      expect(a.riskScore, 88);
      expect(a.topReason!.code, 'cgpa_low');
      expect(a.lastContactAt, isNull);
      expect(a.primary!.userId, 31);
      expect(a.subtitle, '2023041 · Software Engineering · Level 3 · 2023');
      expect(p.items.last.openFlags.highest, isNull);
      expect(p.items.last.topReason, isNull);
    });

    test('older server: an empty item still parses, scores are clamped', () {
      final a = AdvCaseItem.fromJson(const {'member_id': 5, 'risk_score': 140, 'open_flags': 2});
      expect(a.shown, '#5');
      expect(a.riskScore, 100);
      expect(a.openFlags.total, 2, reason: 'a bare count is read as normal flags');
      expect(a.categories, isEmpty);
      expect(a.riskReasons, isEmpty);
      expect(AdvPage.fromJson(const {}, AdvCaseItem.fromJson).restricted, 0);
    });

    test('the query: filters count, the advisor filter is sent only by a director, clearing keeps search and order', () {
      const q0 = AdvWorkspaceQuery();
      expect(q0.activeFilters, 0);
      expect(q0.toQuery(manage: true), {'sort': 'risk', 'page': 1, 'size': 25});
      final q = q0.copyWith(
        q: ' mona ',
        advisor: () => const AdvRef(userId: 31, name: 'Huda'),
        level: () => 'Level 3',
        categoryId: () => 7,
        flag: 'urgent',
        sort: 'contact',
      );
      expect(q.activeFilters, 4);
      expect(q.toQuery(manage: true), {
        'q': 'mona',
        'advisor_user_id': 31,
        'level': 'Level 3',
        'category_id': 7,
        'flag': 'urgent',
        'sort': 'contact',
        'page': 1,
        'size': 25,
      });
      expect(q.toQuery(manage: false).containsKey('advisor_user_id'), isFalse);
      final c = q.cleared();
      expect(c.activeFilters, 0);
      expect(c.q, ' mona ');
      expect(c.sort, 'contact');
      expect(q.copyWith(level: () => null).level, isNull);
    });

    test('filter choices: the settings give programs and levels, the listed students add theirs', () {
      final items = AdvPage.fromJson(sampleAdvWorkspaceJson(), AdvCaseItem.fromJson).items;
      final cats = [for (final m in (sampleAdvCategoriesJson()['items'] as List).cast<Map<String, dynamic>>()) AdvCategory.fromJson(m)];
      final advisor = AdvWorkspaceChoices.from(seen: items, categories: cats);
      expect(advisor.levels, ['Level 3']);
      expect(advisor.cohorts, ['2023']);
      expect(advisor.programs, isEmpty);
      expect(advisor.standings, containsAll(['good', 'probation', 'honours']));
      expect(advisor.categories.any((c) => c.key == 'disciplinary'), isFalse, reason: 'switched-off categories are not offered');
      final director = AdvWorkspaceChoices.from(
        options: const AdvPolicyOptions(levels: ['Level 1', 'Level 2'], cohorts: ['2024'], programs: [AdvNamed(id: 11, nameAr: 'هندسة البرمجيات', nameEn: 'Software Engineering')]),
        seen: items,
      );
      expect(director.levels, ['Level 1', 'Level 2', 'Level 3']);
      expect(director.cohorts, ['2023', '2024']);
      expect(director.programs.single.id, 11);
    });

    test('risk: bands, every reason code worded in both languages, last contact', () {
      expect(advRiskBand(0), 'low');
      expect(advRiskBand(29), 'low');
      expect(advRiskBand(30), 'watch');
      expect(advRiskBand(60), 'high');
      const flags = AdvFlagCounts(high: 2, urgent: 1);
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final code in advRiskReasonCodes) {
          final withValue = advRiskReasonText(AdvRiskReason(code, 3), flags: flags);
          final bare = advRiskReasonText(AdvRiskReason(code));
          expect(withValue, isNot(code), reason: '$code ($lang)');
          expect(bare, isNot(code), reason: '$code without a value ($lang)');
        }
      }
      AppConfig.lang = 'en';
      expect(advRiskReasonText(const AdvRiskReason('cgpa_low', 1.62)), 'CGPA 1.62, under 2.00');
      expect(advRiskReasonText(const AdvRiskReason('open_flags', 15), flags: flags), '3 open flags, highest Urgent');
      expect(advRiskReasonText(const AdvRiskReason('no_contact', 41)), 'No contact for 41 days');
      expect(advRiskReasonText(const AdvRiskReason('absence_high', 27.5)), '28% absence in a course');
      expect(advRiskReasonText(const AdvRiskReason('mystery')), 'mystery', reason: 'an unknown code shows as it is');
      expect(advLastContactText(null), 'Never contacted');
      expect(advLastContactText(DateTime.utc(2026, 11, 5, 8), now: advCaseNow), 'Contacted today');
      expect(advLastContactText(DateTime.utc(2026, 10, 24), now: advCaseNow), 'Last contact 12 days ago');
      AppConfig.lang = 'ar';
      expect(advLastContactText(DateTime.utc(2026, 10, 24), now: advCaseNow), 'آخر تواصل منذ 12 يوماً');
    });
  });

  group('student 360', () {
    test('the profile parses: student, advisors primary first, stats, the registrar record, the trend, rights', () {
      final p = AdvCaseProfile.fromJson(sampleAdvProfileJson());
      expect(p.memberId, 601);
      expect(p.program!.name, 'Software Engineering');
      expect(p.advisors.first.type, 'primary');
      expect(p.primary!.locked, isTrue);
      expect(p.stats.memberId, 601);
      expect(p.stats.riskScore, 88);
      expect(p.meetingsTerm, 2);
      expect(p.academic!.terms, hasLength(3));
      expect(p.academic!.terms.first.label, 'Fall 2025-2026');
      expect(p.academic!.terms[1].courses.first.failed, isTrue);
      expect(p.academic!.terms[1].courses.first.absencePct, 27.5);
      expect(p.academic!.terms.last.courses.first.letter, isNull);
      expect(p.academic!.terms.first.credits, 9);
      expect(p.gpaTrend.last.cgpa, 1.62);
      expect(p.counts.restricted, 6);
      expect(p.can.assign, isTrue);
      final s = p.toStudent();
      expect(s.primary!.userId, 31);
      expect(s.primary!.locked, isTrue);
      expect(s.others.single.type, 'co');
    });

    test('no registrar: academic is null; an older server leaves every block out', () {
      expect(AdvCaseProfile.fromJson(sampleAdvProfileJson(academic: false)).academic, isNull);
      final p = AdvCaseProfile.fromJson(const {});
      expect(p.shown, '#0');
      expect(p.advisors, isEmpty);
      expect(p.can.flag, isFalse);
      expect(p.gpaTrend, isEmpty);
      expect(p.primary, isNull);
    });
  });

  group('categories', () {
    test('parse with their accommodations; names fall back to the built-in labels', () {
      final list = [for (final m in (sampleAdvCategoriesJson()['items'] as List).cast<Map<String, dynamic>>()) AdvCategory.fromJson(m)];
      final acc = list.firstWhere((c) => c.key == 'accessibility');
      expect(acc.sensitive, isTrue);
      expect(acc.accommodations, hasLength(6));
      expect(acc.accommodationLabel('extra_time'), 'Extra exam time');
      expect(acc.accommodationLabel('gone'), 'gone');
      expect(const AdvCategory(id: 3, key: 'career').name, 'Career');
      AppConfig.lang = 'ar';
      expect(acc.name, 'احتياجات خاصة وإتاحة');
    });

    test('the draft: POST without active, PUT with every field; a new accommodation has no key', () {
      final draft = const AdvCategoryDraft(nameAr: ' السكن ', nameEn: 'Housing', accommodations: [AdvAccommodation(labelAr: 'غرفة أرضية', labelEn: 'Ground-floor room')]);
      expect(draft.toJson(create: true), {
        'name_ar': 'السكن',
        'name_en': 'Housing',
        'sensitive': false,
        'accommodations': [
          {'key': null, 'label_ar': 'غرفة أرضية', 'label_en': 'Ground-floor room'},
        ],
      });
      expect(draft.toJson()['active'], isTrue);
      expect(draft.error(), isNull);
      expect(const AdvCategoryDraft().error(), isNotNull);
      expect(const AdvCategoryDraft(nameEn: 'X', accommodations: [AdvAccommodation()]).error(), isNotNull);
      final sys = AdvCategory.fromJson(_cat(7));
      expect(AdvCategoryDraft.of(sys).changedFrom(sys), isFalse);
      expect(AdvCategoryDraft.of(sys).copyWith(active: false).changedFrom(sys), isTrue);
    });
  });

  group('flags', () {
    test('parse: category block, accommodations, overdue, escalation, the outcome', () {
      final p = AdvPage.fromJson(sampleAdvFlagsJson(), AdvFlag.fromJson);
      expect(p.restricted, 2);
      final f = p.items.first;
      expect(f.category.key, 'academic');
      expect(f.priority, 'urgent');
      expect(f.overdue, isTrue);
      expect(f.escalatedAt, isNotNull);
      expect(f.owner!.userId, 31);
      expect(p.items[1].accommodations, ['recorded_lectures', 'front_seating', 'extra_time']);
      final done = p.items.last;
      expect(done.closed, isTrue);
      expect(done.source, 'rule');
      expect(done.resolvedInHours, 72);
      expect(done.outcomeNote, isNotNull);
      final bare = AdvFlag.fromJson(const {'id': 1, 'priority': 'weird'});
      expect(bare.priority, 'normal');
      expect(bare.category.key, 'other');
    });

    test('the lifecycle mirrors flags_flow.py; reopening is for the owner or a director', () {
      expect(advFlagNext('open'), ['acknowledged', 'contacted', 'resolved', 'dismissed']);
      expect(advFlagNext('acknowledged'), ['contacted', 'resolved', 'dismissed']);
      expect(advFlagNext('contacted'), ['resolved', 'dismissed']);
      expect(advFlagNext('resolved'), ['open']);
      expect(advFlagNext('dismissed'), ['open']);
      expect(advFlagNext('resolved', canReopen: false), isEmpty);
      expect(advFlagNext('nonsense'), isEmpty);
      for (final s in advFlagStatuses) {
        for (final next in advFlagNext(s)) {
          expect(advFlagStatuses, contains(next));
          expect(next, isNot(s), reason: 'a state never moves to itself');
        }
      }
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final s in advFlagStatuses) {
          expect(advFlagStatusLabel(s), isNot(s));
          expect(advFlagStatusHint(s), isNotEmpty);
        }
      }
    });

    test('the draft: a new category keeps only its accommodations; the whole body is sent', () {
      final acc = AdvCategory.fromJson(_cat(7)), academic = AdvCategory.fromJson(_cat(1));
      var d = const AdvFlagDraft().withCategory(acc).toggleAccommodation('extra_time').toggleAccommodation('note_taker').toggleAccommodation('note_taker');
      expect(d.accommodations, ['extra_time']);
      expect(d.error(category: acc), isNull);
      expect(d.withCategory(academic).accommodations, isEmpty);
      expect(d.copyWith(accommodations: ['flying']).error(category: acc), isNotNull);
      expect(const AdvFlagDraft().error(), isNotNull, reason: 'a category is required');
      d = d.copyWith(priority: 'high', note: '  late twice  ', reviewDueAt: () => DateTime.utc(2026, 11, 20, 12));
      expect(d.toJson(), {
        'category_id': 7,
        'priority': 'high',
        'note': 'late twice',
        'review_due_at': '2026-11-20T12:00:00.000Z',
        'accommodations': ['extra_time'],
      });
      final f = AdvFlag.fromJson((sampleAdvFlagsJson()['items'] as List).first as Map<String, dynamic>);
      final again = AdvFlagDraft.of(f);
      expect(again.categoryId, 1);
      expect(again.priority, 'urgent');
      expect(again.toJson().keys, ['category_id', 'priority', 'note', 'review_due_at', 'accommodations']);
    });

    test('history lines', () {
      final rows = [for (final m in (sampleAdvFlagHistoryJson()['items'] as List).cast<Map<String, dynamic>>()) AdvFlagEvent.fromJson(m)];
      expect(rows[0].text, 'Escalated to the advising directors');
      expect(rows[1].text, 'Priority: High → Urgent');
      expect(rows[2].text, 'Flag opened');
      expect(rows[2].actor, 'د. هدى سالم');
      expect(const AdvFlagEvent(before: {'status': 'open'}, after: {'status': 'resolved', 'outcome_note': 'Done'}).text, 'Status: Open → Resolved');
      expect(const AdvFlagEvent(before: {'status': 'open'}, after: {'status': 'resolved', 'outcome_note': 'Done'}).outcome, 'Done');
    });
  });

  group('notes', () {
    test('parse: visibility, sensitive, contact, mine; restricted rows are counted', () {
      final p = AdvPage.fromJson(sampleAdvNotesJson(), AdvNote.fromJson);
      expect(p.total, 7);
      expect(p.restricted, 4);
      expect(p.items.first.contactMode, 'phone');
      expect(p.items.first.mine, isTrue);
      expect(p.items[1].editedAt, isNotNull);
      expect(p.items[2].sensitive, isTrue);
      expect(AdvNote.fromJson(const {'id': 1, 'visibility': 'everyone'}).visibility, 'team');
    });

    test('the draft: a sensitive note is never student-visible; the POST carries the offline id, the PUT does not', () {
      var d = const AdvNoteDraft(body: 'Met the student', visibility: 'student');
      d = d.copyWith(sensitive: true);
      expect(d.visibility, 'team', reason: 'turning sensitive on moves a student-visible note to the team');
      expect(d.copyWith(visibility: 'student').visibility, 'team');
      expect(const AdvNoteDraft(body: 'x', visibility: 'student', sensitive: true).error(), isNotNull);
      expect(const AdvNoteDraft(body: '  ').error(), isNotNull);
      expect(AdvNoteDraft(body: 'a' * (advNoteMaxLength + 1)).error(), isNotNull);
      final contact = const AdvNoteDraft(body: ' Called ', clientId: 'n123').copyWith(contactMode: () => 'phone', contactAt: () => DateTime.utc(2026, 11, 4, 15));
      expect(contact.toJson(), {
        'body': 'Called',
        'visibility': 'team',
        'sensitive': false,
        'category_id': null,
        'contact_mode': 'phone',
        'contact_at': '2026-11-04T15:00:00.000Z',
        'client_id': 'n123',
      });
      expect(contact.toJson(create: false).containsKey('client_id'), isFalse);
      expect(const AdvNoteDraft(body: 'x').toJson()['contact_at'], isNull, reason: 'no contact, no time');
      final back = AdvNoteDraft.fromStore(contact.toStore());
      expect(back.body, ' Called ', reason: 'the device keeps the text as typed');
      expect(back.contactMode, 'phone');
      expect(back.clientId, 'n123');
      final n = AdvNote.fromJson((sampleAdvNotesJson()['items'] as List).first as Map<String, dynamic>);
      expect(AdvNoteDraft.of(n).toJson(create: false).keys, ['body', 'visibility', 'sensitive', 'category_id', 'contact_mode', 'contact_at']);
    });
  });

  group('timeline', () {
    test('every kind has a line in both languages; the cursor is kept', () {
      final p = AdvTimelinePage.fromJson(sampleAdvTimelineJson());
      expect(p.next, '2025-09-14T08:00:00');
      expect(p.items.map((e) => e.text), [
        'Contact: Phone',
        'Advising note · Advising team',
        'Flag opened · Academic · Urgent',
        'Flag: Open → Contacted · Accessibility',
        'Handed over from د. ليلى منصور to د. هدى سالم',
        'د. ليلى منصور became the academic advisor',
      ]);
      expect(p.items[3].actor, 'Prof. Omar Khaled');
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final k in advTimelineKinds) {
          expect(AdvTimelineEntry(kind: k).text, isNotEmpty, reason: '$k ($lang)');
        }
      }
      expect(AdvTimelinePage.fromJson(const {}).next, isNull);
    });
  });

  group('entry and codes', () {
    test('/org/mine: the advising key, only for a director or an advisor', () {
      expect(AdvMineInfo.of(const {'advising': {'role': 'advisor', 'advisees': 12}})!.advisees, 12);
      expect(AdvMineInfo.of(const {'advising': {'role': 'director', 'advisees': 0}})!.director, isTrue);
      expect(AdvMineInfo.of(const {'advising': {'role': 'student'}}), isNull);
      expect(AdvMineInfo.of(const {'id': 3}), isNull);
      expect(AdvMineInfo.of(null), isNull);
    });

    test('status me: urgent and overdue flags (0 from an older server)', () {
      final me = AdvMe.fromJson(const {'advisor': true, 'flags_urgent': 2, 'flags_overdue': 5});
      expect(me.flagsUrgent, 2);
      expect(me.flagsOverdue, 5);
      expect(AdvMe.fromJson(const {}).flagsUrgent, 0);
    });

    test('every Phase 4 server code has its own text in both languages', () {
      const codes = [
        'advising_category_in_use',
        'advising_bad_accommodation',
        'advising_bad_transition',
        'advising_outcome_required',
        'advising_bad_visibility',
        'advising_rate_limited',
        'advising_not_found',
        'advising_forbidden',
      ];
      AppConfig.lang = 'en';
      final en = advCodeTexts();
      AppConfig.lang = 'ar';
      final ar = advCodeTexts();
      for (final c in codes) {
        expect(en[c], isNotNull, reason: c);
        expect(ar[c], isNotNull, reason: c);
        expect(en[c], isNot(ar[c]), reason: c);
      }
    });
  });

  group('backend additions', () {
    test('risk reasons carry their points, in the order the server sends', () {
      final a = AdvCaseItem.fromJson((sampleAdvWorkspaceJson()['items'] as List).first as Map<String, dynamic>);
      expect(a.riskReasons.map((r) => r.points), [25, 20, 15, 15, 10]);
      expect(a.topReason!.code, 'cgpa_low');
    });

    test('allowed_next is what the server allows; an older server falls back to the lifecycle', () {
      final p = AdvPage.fromJson(sampleAdvFlagsJson(), AdvFlag.fromJson);
      expect(p.items.first.nextStates(), ['acknowledged', 'contacted', 'resolved', 'dismissed']);
      expect(p.items.last.nextStates(), isEmpty, reason: 'this caller may not reopen it');
      expect(p.items[1].allowedNext, isNull);
      expect(AdvFlag.fromJson(const {'id': 2, 'reopened_at': '2026-11-01T10:00:00'}).reopenedAt!.toUtc(), DateTime.utc(2026, 11, 1, 10));
      expect(p.items[1].nextStates(), ['resolved', 'dismissed']);
      expect(AdvFlag.fromJson(const {'id': 1, 'status': 'open', 'allowed_next': ['contacted', 'bogus']}).nextStates(), ['contacted']);
    });

    test('a note carries the client_id it was posted with; the GPA trend joins term and year', () {
      final n = AdvPage.fromJson(sampleAdvNotesJson(), AdvNote.fromJson).items;
      expect(n.first.clientId, 'nmh2k1abc0');
      expect(n[1].clientId, isNull);
      final p = AdvCaseProfile.fromJson(sampleAdvProfileJson());
      expect(p.gpaTrend.map((g) => g.label), ['Fall 2024-2025', 'Spring 2024-2025', 'Fall 2025-2026', 'Spring 2025-2026']);
      expect(AdvGpaPoint.fromJson(const {'label': 'Term 3'}).label, 'Term 3', reason: 'no kind: the label as sent');
    });

    test('error texts use the numbers the server sends', () {
      const busy = ApiException(statusCode: 429, message: 'x', code: 'advising_rate_limited', body: {'detail': {'code': 'advising_rate_limited', 'retry_after_minutes': 7}});
      const inUse = ApiException(statusCode: 409, message: 'x', code: 'advising_category_in_use', body: {'detail': {'code': 'advising_category_in_use', 'open_flags': 3}});
      expect(advErrorText(busy), 'Too many changes in a short time — try again in 7 minutes');
      expect(advErrorText(inUse), '3 open flags use this category — close them, or switch the category off instead');
      AppConfig.lang = 'ar';
      expect(advErrorText(busy), contains('7 دقائق'));
      const bare = ApiException(statusCode: 429, message: 'x', code: 'advising_rate_limited');
      expect(advErrorText(bare), advCodeTexts()['advising_rate_limited']);
      for (final c in ['advising_bad_category', 'advising_category_system', 'advising_bad_contact_at', 'advising_bad_cursor', 'advising_client_id_conflict']) {
        expect(advCodeTexts()[c], isNotNull, reason: c);
      }
    });
  });
}
