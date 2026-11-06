// Academic Advising, Phase 7 (docs/advising/PHASE7.md): support requests and referrals, the stage tracker, the
// approval chain and its validation, support plans, accommodations, the 360's Support block, the student's own view,
// the timeline kinds, the deep links and every new server code. The answers parse (an older server that leaves keys
// out still parses), the drafts build the WHOLE-object bodies, the chain checks mirror the server's. The sample
// payloads are shared with test/ui/adv_support_layout_test.dart and test/visual/adv_support_golden_test.dart.
import 'dart:convert';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/advising/adv_draft_store.dart' show AdvDraftBackend;
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_request_composer.dart' show AdvRequestDraftStore;
import 'package:flutter_education_app/features/org/advising/adv_support_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_support_texts.dart';
import 'package:flutter_education_app/features/org/advising/adv_texts.dart';
import 'package:flutter_education_app/features/org/org_v3.dart' show orgErrorText;
import 'package:flutter_test/flutter_test.dart';

bool get _ar => AppConfig.lang == 'ar';

const _huda = {'user_id': 31, 'name': 'د. هدى سالم'};
const _omar = {'user_id': 32, 'name': 'Prof. Omar Khaled'};
const _student = {'member_id': 601, 'user_id': 1601, 'name': 'ليلى أحمد', 'code': '2023-0142'};

const _accessibility = {
  'id': 7,
  'key': 'accessibility',
  'name_ar': 'احتياجات خاصة وإتاحة',
  'name_en': 'Accessibility',
  'sensitive': true,
  'accommodations': [
    {'key': 'extra_time', 'label_ar': 'وقت إضافي في الامتحانات', 'label_en': 'Extra exam time'},
    {'key': 'accessible_room', 'label_ar': 'قاعة ميسّرة', 'label_en': 'Accessible room'},
    {'key': 'recorded_lectures', 'label_ar': 'محاضرات مسجّلة', 'label_en': 'Recorded lectures'},
    {'key': 'front_seating', 'label_ar': 'مقعد في الصفوف الأمامية', 'label_en': 'Front seating'},
  ],
};

const _academic = {'id': 3, 'key': 'academic', 'name_ar': 'أكاديمي', 'name_en': 'Academic', 'sensitive': false, 'accommodations': <Map<String, dynamic>>[]};

/// `GET …/request-options`.
Map<String, dynamic> sampleAdvRequestOptionsJson() => {
      'support_types': [
        for (final k in advSupportTypeKeys)
          {
            'key': k,
            'label_ar': '',
            'label_en': '',
            'category_key': k == 'accommodation' ? 'accessibility' : (k == 'financial_support' ? 'financial' : (k == 'other' ? null : 'academic')),
            'needs_accommodations': k == 'accommodation',
          },
      ],
      'referral_targets': [
        {'id': 44, 'name': 'مكتب الإرشاد النفسي', 'name_en': 'Counselling office', 'preset': null, 'suggested': false},
        {'id': 41, 'name': 'الرعاية الصحية', 'name_en': 'Healthcare', 'preset': 'healthcare', 'suggested': true},
        {'id': 42, 'name': 'رعاية الشباب', 'name_en': 'Student activities', 'preset': 'student_activities', 'suggested': true},
        {'id': 43, 'name': 'شؤون الطلاب', 'name_en': 'Student affairs', 'preset': 'student_affairs', 'suggested': true},
      ],
      'categories': [_academic, _accessibility, {'id': 4, 'key': 'financial', 'name_ar': 'مالي', 'name_en': 'Financial', 'sensitive': true}],
      'templates': [
        {'id': 5, 'name_ar': 'طلب دعم', 'name_en': 'Support request', 'body_ar': 'أطلب الدعم في: {topic}\nالتفاصيل: {details}', 'body_en': 'I request support with: {topic}\nDetails: {details}'},
      ],
      'priorities': ['low', 'normal', 'high', 'urgent'],
    };

List<Map<String, dynamic>> _chain({required int current, String dept = 'current', String faculty = 'waiting', String director = 'approved', bool skipDept = false}) => [
      {'kind': 'director_review', 'dept_id': 9, 'label_ar': 'مراجعة مدير الإرشاد', 'label_en': 'Advising director review', 'status': director, 'at': '2026-10-28T09:30:00', 'by': _huda, 'note': null},
      {
        'kind': 'student_department_council',
        'dept_id': 21,
        'label_ar': 'مجلس قسم هندسة البرمجيات',
        'label_en': 'Software Engineering department council',
        'status': skipDept ? 'skipped' : dept,
        'at': skipDept ? '2026-10-28T09:30:00' : (dept == 'current' ? '2026-10-28T09:31:00' : '2026-11-03T12:00:00'),
        'by': null,
        'note': dept == 'rejected' ? (_ar ? 'العبء المطلوب أقل من الحد الأدنى للتسجيل.' : 'The load asked for is under the minimum registration.') : null,
        'skip_reason': skipDept ? 'no_department_council' : null,
      },
      {'kind': 'faculty_council', 'dept_id': 20, 'label_ar': 'مجلس الكلية', 'label_en': 'Faculty council', 'status': faculty, 'at': null, 'by': null, 'note': null},
    ];

/// One staff request; [stage] picks a realistic moment of its life.
Map<String, dynamic> sampleAdvRequestJson({String stage = 'at_department_council', String kind = 'support', bool detail = true}) {
  final decided = stage == 'approved' || stage == 'rejected' || stage == 'closed';
  final referral = kind == 'referral';
  final chain = switch (stage) {
    'needs_info' => _chain(current: 0, director: 'current', dept: 'waiting'),
    'approved' || 'closed' => _chain(current: 2, dept: 'approved', faculty: 'approved'),
    'rejected' => _chain(current: 1, dept: 'rejected'),
    'draft' => <Map<String, dynamic>>[],
    _ => _chain(current: 1),
  };
  return {
    'id': referral ? 902 : 901,
    'kind': kind,
    'member_id': 601,
    'student': _student,
    'support_type': referral ? null : 'accommodation',
    'target_dept': referral ? {'id': 41, 'name': 'الرعاية الصحية', 'name_en': 'Healthcare', 'preset': 'healthcare'} : null,
    'category': referral ? null : _accessibility,
    'title': referral
        ? (_ar ? 'متابعة طبية لضعف السمع' : 'Medical follow-up for hearing loss')
        : (_ar ? 'تسهيلات امتحانات الفصل الأول بسبب ضعف السمع' : 'First-term exam accommodations for hearing loss'),
    'body': _ar
        ? 'الطالبة تعاني ضعفاً في السمع منذ سبتمبر، والسماعة في الصيانة حتى نهاية الشهر. تطلب وقتاً إضافياً في الامتحانات ومقعداً في الصفوف الأمامية وتسجيل المحاضرات. التقرير الطبي مرفق.'
        : 'The student has had hearing loss since September and her hearing aid is being repaired until the end of the month. She asks for extra exam time, front seating and recorded lectures. The medical report is attached.',
    'priority': stage == 'needs_info' ? 'urgent' : 'high',
    'accommodations': referral
        ? <Map<String, dynamic>>[]
        : [
            {'key': 'extra_time', 'label_ar': 'وقت إضافي في الامتحانات', 'label_en': 'Extra exam time'},
            {'key': 'front_seating', 'label_ar': 'مقعد في الصفوف الأمامية', 'label_en': 'Front seating'},
            {'key': 'recorded_lectures', 'label_ar': 'محاضرات مسجّلة', 'label_en': 'Recorded lectures'},
          ],
    'accommodation_until': referral ? null : '2027-01-31',
    'attachments': [
      {'id': 71, 'name': 'medical_report.pdf', 'type': 'application/pdf', 'ext': 'pdf', 'size': 248000, 'preview': true},
      {'id': 72, 'name': 'audiogram.png', 'type': 'image/png', 'ext': 'png', 'size': 91000, 'preview': true},
    ],
    'template_id': null,
    'flag_id': 77,
    'stage': stage,
    'stage_at': '2026-10-28T09:31:00',
    'postponed': false,
    'outcome': switch (stage) { 'approved' || 'closed' => 'approved', 'rejected' => 'rejected', _ => null },
    'outcome_note': switch (stage) {
      'approved' || 'closed' => _ar ? 'وافق مجلس الكلية على التسهيلات حتى نهاية الفصل.' : 'The faculty council approved the accommodations until the end of the term.',
      'rejected' => _ar ? 'العبء المطلوب أقل من الحد الأدنى للتسجيل.' : 'The load asked for is under the minimum registration.',
      _ => null,
    },
    'outcome_at': decided ? '2026-11-03T12:00:00' : null,
    'info': stage == 'needs_info'
        ? {
            'requested_at': '2026-11-02T08:00:00',
            'note': _ar ? 'أرفق التقرير الطبي الأحدث من المستشفى الجامعي.' : 'Attach the latest medical report from the university hospital.',
            'by': _huda,
            'answered_at': null,
            'answer': null,
          }
        : null,
    'step': decided || stage == 'draft'
        ? null
        : {
            'index': stage == 'needs_info' ? 0 : 1,
            'count': 3,
            'kind': stage == 'needs_info' ? 'director_review' : 'student_department_council',
            'label_ar': stage == 'needs_info' ? 'مراجعة مدير الإرشاد' : 'مجلس قسم هندسة البرمجيات',
            'label_en': stage == 'needs_info' ? 'Advising director review' : 'Software Engineering department council',
            'due_at': stage == 'needs_info' ? '2026-11-03T08:00:00' : '2026-12-02T09:31:00',
            'overdue': stage == 'needs_info',
          },
    'escalated': stage == 'needs_info',
    'work_item': stage == 'draft' ? null : {'id': 5501, 'ref': 'REQ-2026-0418', 'status': decided ? 'approved' : 'open', 'version': 4},
    'created_by': _omar,
    'created_at': '2026-10-27T14:00:00',
    'submitted_at': stage == 'draft' ? null : '2026-10-27T14:05:00',
    'updated_at': '2026-10-28T09:31:00',
    'closed_at': stage == 'closed' ? '2026-11-04T10:00:00' : null,
    'close_note': stage == 'closed' ? (_ar ? 'أُبلغ أساتذة المقررات الأربعة، وتأكدت من القاعة.' : 'The four course teachers were told; the room is confirmed.') : null,
    'version': 3,
    'can': {
      'edit': stage == 'draft',
      'submit': stage == 'draft',
      'delete': stage == 'draft',
      'review': stage == 'submitted',
      'answer_info': stage == 'needs_info',
      'resubmit': stage == 'rejected',
      'cancel': !decided && stage != 'draft',
      'close': stage == 'approved' || stage == 'rejected',
    },
    if (detail)
      'chain': chain.isEmpty
          ? null
          : {
              'round': stage == 'rejected' ? 1 : 2,
              'current': stage == 'needs_info' ? 0 : 1,
              'steps': chain,
              'rounds': stage == 'rejected'
                  ? <Map<String, dynamic>>[]
                  : [
                      {'round': 1, 'steps': _chain(current: 1, dept: 'rejected')},
                    ],
            },
    if (detail)
      'history': [
        {'stage': 'submitted', 'at': '2026-10-27T14:05:00'},
        if (stage != 'needs_info') {'stage': 'at_department_council', 'at': '2026-10-28T09:31:00'},
        if (stage == 'needs_info') {'stage': 'needs_info', 'at': '2026-11-02T08:00:00'},
        if (decided) {'stage': stage == 'rejected' ? 'rejected' : 'at_faculty_council', 'at': '2026-11-01T09:00:00'},
        if (stage == 'approved' || stage == 'closed') {'stage': 'approved', 'at': '2026-11-03T12:00:00'},
        if (stage == 'closed') {'stage': 'closed', 'at': '2026-11-04T10:00:00'},
      ],
    if (detail)
      'agenda': stage == 'at_department_council'
          ? [
              {
                'council': {'dept_id': 21, 'name': 'مجلس قسم هندسة البرمجيات', 'name_en': 'Software Engineering department council', 'level': 'department'},
                'scheduled_at': '2026-11-10T10:00:00',
                'status': 'open',
                'approve_count': 5,
                'reject_count': 1,
                'abstain_count': 1,
                'eligible_count': 11,
              },
            ]
          : <Map<String, dynamic>>[],
  };
}

/// `GET …/requests` (a director): every queue counted.
Map<String, dynamic> sampleAdvRequestsJson() => {
      'items': [
        sampleAdvRequestJson(stage: 'needs_info', detail: false),
        sampleAdvRequestJson(detail: false),
        sampleAdvRequestJson(stage: 'in_progress', kind: 'referral', detail: false)..['step'] = null,
        {
          ...sampleAdvRequestJson(stage: 'draft', detail: false),
          'id': 905,
          'support_type': 'course_withdrawal',
          'category': _academic,
          'title': _ar ? 'انسحاب من مقرر الإحصاء ٢' : 'Withdraw from Statistics 2',
          'student': {'member_id': 612, 'user_id': 1612, 'name': 'Youssef Nabil', 'code': '2022-0311'},
          'member_id': 612,
          'accommodations': <Map<String, dynamic>>[],
          'priority': 'normal',
        },
        sampleAdvRequestJson(stage: 'approved', detail: false),
      ],
      'total': 23,
      'page': 1,
      'size': 20,
      'pages': 2,
      'restricted': 2,
      'facets': {'review': 3, 'needs_info': 1, 'overdue': 2, 'open': 11},
    };

/// `GET …/request-chain`.
Map<String, dynamic> sampleAdvChainJson({bool faculty = true, int departmentCouncils = 6}) => {
      'org': {
        'steps': [
          {'kind': 'director_review', 'dept_id': null, 'label_ar': 'مراجعة مدير الإرشاد', 'label_en': 'Advising director review'},
          {'kind': 'student_department_council', 'dept_id': null, 'label_ar': 'مجلس قسم الطالب', 'label_en': 'Student\'s department council'},
          {'kind': 'entity', 'dept_id': 43, 'label_ar': 'لجنة شؤون الطلاب', 'label_en': 'Student Affairs committee'},
          {'kind': 'faculty_council', 'dept_id': null, 'label_ar': 'مجلس الكلية', 'label_en': 'Faculty council'},
        ],
        'inherited': false,
      },
      'defaults': [
        {'kind': 'director_review', 'dept_id': null, 'label_ar': 'مراجعة مدير الإرشاد', 'label_en': 'Advising director review'},
        {'kind': 'student_department_council', 'dept_id': null, 'label_ar': 'مجلس قسم الطالب', 'label_en': 'Student\'s department council'},
        {'kind': 'faculty_council', 'dept_id': null, 'label_ar': 'مجلس الكلية', 'label_en': 'Faculty council'},
      ],
      'scopes': [
        {
          'policy_id': 12,
          'scope_type': 'program',
          'scope_ref': '11',
          'label': 'هندسة البرمجيات',
          'label_en': 'Software Engineering',
          'steps': [
            {'kind': 'director_review', 'dept_id': null, 'label_ar': 'مراجعة مدير الإرشاد', 'label_en': 'Advising director review'},
            {'kind': 'faculty_council', 'dept_id': null, 'label_ar': 'مجلس الكلية', 'label_en': 'Faculty council'},
          ],
        },
      ],
      'options': {
        'kinds': [
          for (final k in advChainKinds) {'key': k, 'label_ar': '', 'label_en': '', 'needs_dept': k == 'entity'},
        ],
        'entities': [
          {'id': 43, 'name': 'لجنة شؤون الطلاب', 'name_en': 'Student Affairs committee', 'preset': 'student_affairs', 'kind': 'service'},
          {'id': 41, 'name': 'الرعاية الصحية', 'name_en': 'Healthcare', 'preset': 'healthcare', 'kind': 'service'},
        ],
        'faculty_council': faculty,
        'department_councils': departmentCouncils,
        'advising_dept': {'id': 9, 'name': 'الإرشاد الأكاديمي', 'name_en': 'Academic Advising'},
      },
    };

/// `GET …/request-chain/preview`: the department council skipped for this student.
Map<String, dynamic> sampleAdvChainPreviewJson() => {
      'steps': [
        {'kind': 'director_review', 'dept_id': 9, 'label_ar': 'مراجعة مدير الإرشاد', 'label_en': 'Advising director review', 'resolved': true, 'reason': null},
        {'kind': 'student_department_council', 'dept_id': null, 'label_ar': 'مجلس قسم الطالب', 'label_en': 'Student\'s department council', 'resolved': false, 'reason': 'no_department_council'},
        {'kind': 'faculty_council', 'dept_id': 20, 'label_ar': 'مجلس الكلية', 'label_en': 'Faculty council', 'resolved': true, 'reason': null},
      ],
      'advising_dept': {'id': 9, 'name': 'الإرشاد الأكاديمي', 'name_en': 'Academic Advising'},
    };

/// A support plan: [status] `active` (3 of 5 done, one overdue) · `completed` (target met) · `draft`.
Map<String, dynamic> sampleAdvPlanJson({String status = 'active', int id = 301}) => {
      'id': id,
      'member_id': 601,
      'title': _ar ? 'رفع المعدل فوق 2.0 هذا الفصل' : 'Bring the GPA above 2.0 this term',
      'status': status,
      'measure': {'kind': 'term_gpa', 'target': 2.3, 'text': null},
      'result': status == 'completed' ? {'value': 2.48, 'met': true, 'at': '2027-01-20T10:00:00'} : null,
      'measure_now': {'value': status == 'completed' ? 2.48 : 2.12, 'met': status == 'completed'},
      'review_due': status == 'active',
      'review_due_at': status == 'active' ? '2026-11-20T09:00:00' : null,
      'reviewed_at': status == 'completed' ? '2026-12-04T09:00:00' : null,
      'follow_up_at': '2026-11-20T09:00:00',
      'student_visible': true,
      'flag_id': 77,
      'request_id': null,
      'outcome_note': status == 'completed' ? (_ar ? 'حضرت كل جلسات الدعم ورفعت معدلها إلى 2.48.' : 'She attended every tutoring session and raised her GPA to 2.48.') : null,
      'closed_at': status == 'completed' ? '2027-01-20T10:00:00' : null,
      'created_by': _omar,
      'created_at': '2026-10-20T11:00:00',
      'updated_at': '2026-11-02T11:00:00',
      'version': 5,
      'progress': {'done': status == 'completed' ? 4 : 2, 'total': 4},
      'items': [
        {
          'id': 1,
          'goal': _ar ? 'حضور جلسات الدعم في الرياضيات أسبوعياً' : 'Attend the weekly maths tutoring sessions',
          'action': _ar ? 'التسجيل في مركز الدعم الأكاديمي — الثلاثاء 2 ظهراً' : 'Sign up at the academic support centre — Tuesdays at 2 pm',
          'owner': 'student',
          'owner_note': null,
          'due_at': '2026-11-01T12:00:00',
          'status': 'done',
          'done_at': '2026-10-30T12:00:00',
          'note': null,
          'order': 1,
          'overdue': false,
        },
        {
          'id': 2,
          'goal': _ar ? 'مراجعة جدول المذاكرة مع المرشد' : 'Review the study timetable with the advisor',
          'action': '',
          'owner': 'advisor',
          'owner_note': null,
          'due_at': '2026-11-04T12:00:00',
          'status': 'done',
          'done_at': '2026-11-04T09:00:00',
          'note': null,
          'order': 2,
          'overdue': false,
        },
        {
          'id': 3,
          'goal': _ar ? 'تسليم واجبات البرمجة المتأخرة' : 'Hand in the late programming assignments',
          'action': _ar ? 'ثلاثة واجبات، بموافقة أستاذ المقرر' : 'Three assignments, agreed with the course teacher',
          'owner': 'student',
          'owner_note': null,
          'due_at': '2026-11-03T12:00:00',
          'status': status == 'completed' ? 'done' : 'open',
          'done_at': status == 'completed' ? '2026-11-08T12:00:00' : null,
          'note': null,
          'order': 3,
          'overdue': status != 'completed',
        },
        {
          'id': 4,
          'goal': _ar ? 'جلسة مع الأخصائي الاجتماعي' : 'A session with the social worker',
          'action': '',
          'owner': 'other',
          'owner_note': _ar ? 'مكتب شؤون الطلاب' : 'Student Affairs office',
          'due_at': '2026-11-15T12:00:00',
          'status': status == 'completed' ? 'done' : 'open',
          'done_at': status == 'completed' ? '2026-11-14T12:00:00' : null,
          'note': null,
          'order': 4,
          'overdue': false,
        },
      ],
      'can': {'edit': status != 'completed', 'status': true, 'delete': status == 'draft'},
    };

/// The student's accommodations (staff view: notes).
List<Map<String, dynamic>> sampleAdvAccommodationsJson({bool staff = true}) => [
      {
        'id': 81,
        'member_id': 601,
        'student_name': 'ليلى أحمد',
        'key': 'extra_time',
        'label_ar': 'وقت إضافي في الامتحانات',
        'label_en': 'Extra exam time',
        'category': _accessibility,
        'status': 'active',
        'starts_on': '2026-11-03',
        'ends_on': '2027-01-31',
        'source': 'request',
        'request_id': 901,
        'note': staff ? (_ar ? 'ربع ساعة لكل ساعة امتحان.' : 'A quarter of an hour per exam hour.') : null,
        'granted_by': _huda,
        'granted_at': '2026-11-03T12:00:00',
        'ended_at': null,
        'end_reason': null,
      },
      {
        'id': 82,
        'member_id': 601,
        'student_name': 'ليلى أحمد',
        'key': 'front_seating',
        'label_ar': 'مقعد في الصفوف الأمامية',
        'label_en': 'Front seating',
        'category': _accessibility,
        'status': 'active',
        'starts_on': '2026-11-03',
        'ends_on': null,
        'source': 'manual',
        'request_id': null,
        'note': null,
        'granted_by': _huda,
        'granted_at': '2026-11-03T12:00:00',
        'ended_at': null,
        'end_reason': null,
      },
    ];

/// `GET …/students/{mid}/support`.
Map<String, dynamic> sampleAdvSupportJson({bool empty = false}) => empty
    ? {
        'requests': {'open': 0, 'needs_info': 0, 'total': 0, 'latest': <Map<String, dynamic>>[]},
        'referrals': {'open': 0, 'total': 0, 'latest': <Map<String, dynamic>>[]},
        'plans': {'active': <Map<String, dynamic>>[], 'completed': 0},
        'accommodations': <Map<String, dynamic>>[],
        'restricted': 0,
        'can': {'request': true, 'refer': true, 'plan': true, 'accommodate': false},
      }
    : {
        'requests': {
          'open': 2,
          'needs_info': 1,
          'total': 6,
          'latest': [sampleAdvRequestJson(stage: 'needs_info', detail: false), sampleAdvRequestJson(detail: false)],
        },
        'referrals': {'open': 1, 'total': 1, 'latest': [sampleAdvRequestJson(stage: 'in_progress', kind: 'referral', detail: false)..['step'] = null]},
        'plans': {'active': [sampleAdvPlanJson()], 'completed': 1},
        'accommodations': sampleAdvAccommodationsJson(),
        'restricted': 1,
        'can': {'request': true, 'refer': true, 'plan': true, 'accommodate': true},
      };

/// The student's own request (`StudentRequest`).
Map<String, dynamic> sampleAdvStudentRequestJson({String stage = 'at_department_council'}) => {
      'id': 901,
      'kind': 'support',
      'support_type': 'accommodation',
      'target_dept': null,
      'title': _ar ? 'تسهيلات امتحانات الفصل الأول' : 'First-term exam accommodations',
      'body': _ar
          ? 'طلب وقت إضافي في الامتحانات ومقعد في الصفوف الأمامية حتى تعود السماعة من الصيانة.'
          : 'Extra exam time and front seating until the hearing aid is back from repair.',
      'priority': 'high',
      'stage': stage,
      'stage_at': '2026-10-28T09:31:00',
      'postponed': stage == 'at_department_council',
      'outcome': stage == 'approved' ? 'approved' : null,
      'outcome_note': stage == 'approved' ? (_ar ? 'وافق مجلس الكلية حتى نهاية الفصل.' : 'The faculty council approved them until the end of the term.') : null,
      'outcome_at': stage == 'approved' ? '2026-11-03T12:00:00' : null,
      'steps': [
        {'label_ar': 'مراجعة مدير الإرشاد', 'label_en': 'Advising director review', 'status': 'approved', 'at': '2026-10-28T09:30:00'},
        {'label_ar': 'مجلس قسم هندسة البرمجيات', 'label_en': 'Software Engineering department council', 'status': stage == 'approved' ? 'approved' : 'current', 'at': '2026-10-28T09:31:00'},
        {'label_ar': 'مجلس الكلية', 'label_en': 'Faculty council', 'status': stage == 'approved' ? 'approved' : 'waiting', 'at': stage == 'approved' ? '2026-11-03T12:00:00' : null},
      ],
      'history': [
        {'stage': 'submitted', 'at': '2026-10-27T14:05:00'},
        {'stage': 'at_department_council', 'at': '2026-10-28T09:31:00'},
        if (stage == 'approved') {'stage': 'at_faculty_council', 'at': '2026-11-01T09:00:00'},
        if (stage == 'approved') {'stage': 'approved', 'at': '2026-11-03T12:00:00'},
      ],
      'accommodations': [
        {'key': 'extra_time', 'label_ar': 'وقت إضافي في الامتحانات', 'label_en': 'Extra exam time'},
        {'key': 'front_seating', 'label_ar': 'مقعد في الصفوف الأمامية', 'label_en': 'Front seating'},
      ],
      'created_at': '2026-10-27T14:00:00',
      'submitted_at': '2026-10-27T14:05:00',
      'advisor_name': 'Prof. Omar Khaled',
    };

/// The student's `GET …/public/{org}/advising/support`.
Map<String, dynamic> sampleAdvMemberSupportJson() => {
      'requests': [
        sampleAdvStudentRequestJson(),
        {
          ...sampleAdvStudentRequestJson(stage: 'handled'),
          'id': 902,
          'kind': 'referral',
          'support_type': null,
          'target_dept': {'name': 'الرعاية الصحية', 'name_en': 'Healthcare'},
          'title': _ar ? 'متابعة طبية' : 'Medical follow-up',
          'outcome': 'handled',
          'postponed': false,
          'steps': <Map<String, dynamic>>[],
          'outcome_at': '2026-10-15T10:00:00',
        },
      ],
      'plans': [
        {
          ...sampleAdvPlanJson(),
          'review_due': false,
          'can': null,
          'items': [for (final i in sampleAdvPlanJson()['items'] as List) {...i as Map<String, dynamic>, 'note': null, 'mine': i['owner'] == 'student'}],
        },
      ],
      'accommodations': sampleAdvAccommodationsJson(staff: false),
    };

class _Memory implements AdvDraftBackend {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('options and the composer', () {
    test('request options: suggested targets first, the type labels, the categories', () {
      final o = AdvRequestOptions.fromJson(sampleAdvRequestOptionsJson());
      expect(o.referralTargets.map((e) => e.id), [41, 42, 43, 44]);
      expect(o.type('exam_excuse')!.label, 'Exam excuse', reason: 'empty server labels fall back to the app\'s');
      expect(o.type('accommodation')!.needsAccommodations, isTrue);
      expect(o.category(7)!.accommodations.length, 4);
      expect(o.templates.single.body, startsWith('I request support with'));
      AppConfig.lang = 'ar';
      expect(o.type('exam_excuse')!.label, 'عذر عن امتحان');
    });

    test('an older server without options still offers the catalogue', () {
      final o = AdvRequestOptions.fromJson(const {});
      expect(o.supportTypes.map((x) => x.key), advSupportTypeKeys);
      expect(o.type('accommodation')!.categoryKey, 'accessibility');
      expect(o.type('other')!.categoryKey, isNull);
      expect(o.priorities, advPriorities);
    });

    test('picking a type brings its category; accommodations stay only for a type that needs them', () {
      final o = AdvRequestOptions.fromJson(sampleAdvRequestOptionsJson());
      var d = const AdvRequestDraft().withType(o.type('accommodation')!, o.categories).toggleAccommodation('extra_time').toggleAccommodation('front_seating');
      expect(d.categoryId, 7);
      expect(d.accommodations, ['extra_time', 'front_seating']);
      d = d.toggleAccommodation('extra_time');
      expect(d.accommodations, ['front_seating']);
      d = d.withType(o.type('course_withdrawal')!, o.categories);
      expect(d.categoryId, 3);
      expect(d.accommodations, isEmpty);
    });

    test('the draft says what is missing before sending', () {
      final o = AdvRequestOptions.fromJson(sampleAdvRequestOptionsJson());
      expect(const AdvRequestDraft().error(), 'Give the request a title');
      expect(const AdvRequestDraft(title: 'x').error(), 'Choose the type of request');
      final acc = const AdvRequestDraft(title: 'x', body: 'y').withType(o.type('accommodation')!, o.categories);
      expect(acc.error(type: o.type('accommodation')), 'Choose the accommodations requested');
      expect(acc.error(type: o.type('accommodation'), submit: false), isNull, reason: 'a draft may be saved before');
      expect(const AdvRequestDraft(kind: 'referral', title: 'x', body: 'y').error(), 'Choose the department to refer the student to');
      expect(const AdvRequestDraft(kind: 'referral', title: 'x', targetDeptId: 41).error(), 'Write the details of the request');
      expect(AdvRequestDraft(title: 'x' * 201, supportType: 'other').error(), contains('200'));
      AppConfig.lang = 'ar';
      expect(const AdvRequestDraft().error(), 'اكتب عنواناً للطلب');
    });

    test('the POST and the PUT bodies', () {
      final d = AdvRequestDraft(
        supportType: 'accommodation',
        categoryId: 7,
        title: '  Exam accommodations ',
        body: 'Details ',
        priority: 'high',
        accommodations: const ['extra_time'],
        accommodationUntil: DateTime(2027, 1, 31),
        flagId: 77,
        clientId: 'nabc',
      );
      final post = d.toJson(submit: true);
      expect(post['title'], 'Exam accommodations');
      expect(post['accommodation_until'], '2027-01-31');
      expect(post['client_id'], 'nabc');
      expect(post['submit'], isTrue);
      expect(post['target_dept_id'], isNull);
      expect(post.containsKey('version'), isFalse);
      final put = d.toJson(version: 3);
      expect(put['version'], 3);
      expect(put.containsKey('client_id'), isFalse);
      expect(put.containsKey('submit'), isFalse);
      final ref = const AdvRequestDraft(kind: 'referral', supportType: 'exam_excuse', targetDeptId: 41, accommodations: ['x']).toJson();
      expect(ref['support_type'], isNull);
      expect(ref['target_dept_id'], 41);
      expect(ref['accommodations'], isEmpty);
    });

    test('the device copy keeps the text and the uploaded files by id', () async {
      final r = AdvRequest.fromJson(sampleAdvRequestJson(stage: 'draft'));
      final d = AdvRequestDraft.of(r).copyWith(clientId: () => 'n1');
      final back = AdvRequestDraft.fromStore(jsonDecode(jsonEncode(d.toStore())) as Map<String, dynamic>);
      expect(back.title, d.title);
      expect(back.accommodations, d.accommodations);
      expect(back.accommodationUntil, DateTime(2027, 1, 31));
      expect(back.attachments.map((a) => a.id), [71, 72]);
      expect(back.clientId, 'n1');

      final mem = _Memory();
      final store = AdvRequestDraftStore(backend: mem, userId: () async => 31);
      await store.save(3, 601, back);
      expect((await store.read(3, 601))!.title, d.title);
      expect(await store.read(3, 602), isNull);
      expect(await AdvRequestDraftStore(backend: mem, userId: () async => 32).read(3, 601), isNull, reason: 'another user never sees it');
      await store.clear(3, 601);
      expect(mem.data, isEmpty);
    });

    test('templates: the known placeholders filled, the others left for the advisor', () {
      expect(advFillTemplate('I request support with: {topic}\nDetails: {details}', {'topic': 'Exam excuse'}), 'I request support with: Exam excuse\nDetails: ');
      expect(advFillTemplate('Dear {student}', {'student': 'Laila'}), 'Dear Laila');
    });

    test('the list query', () {
      expect(const AdvRequestQuery(filter: 'kind:referral', queue: 'overdue', q: ' x ').toQuery(), {'kind': 'referral', 'queue': 'overdue', 'q': 'x', 'page': 1, 'size': 20});
      expect(const AdvRequestQuery(memberId: 601, filter: 'stage:draft', mine: true).toQuery(), {'member_id': 601, 'stage': 'draft', 'mine': 1, 'page': 1, 'size': 20});
      for (final f in advRequestFilters) {
        expect(advRequestFilterLabel(f), isNotEmpty, reason: f);
      }
    });
  });

  group('requests', () {
    test('a request at the department council parses with its chain, history and agenda', () {
      final r = AdvRequest.fromJson(sampleAdvRequestJson());
      expect(r.student!.shown, 'ليلى أحمد');
      expect(r.category!.sensitive, isTrue);
      expect(r.sensitive, isTrue);
      expect(r.accommodations.map((a) => a.label), ['Extra exam time', 'Front seating', 'Recorded lectures']);
      expect(r.accommodationUntil, DateTime(2027, 1, 31));
      expect(r.attachments.first.isPdf, isTrue);
      expect(r.step!.label, 'Software Engineering department council');
      expect(r.workItem!.version, 4);
      expect(r.chain!.steps.length, 3);
      expect(r.chain!.rounds.single.$1, 1);
      expect(r.history.first.label, 'Submitted');
      expect(r.agenda.single.voted, 7);
      expect(r.agenda.single.council, 'Software Engineering department council');
      expect(r.typeLabel, 'Accommodations');
      expect(r.can.cancel, isTrue);
      expect(r.can.review, isFalse);
    });

    test('an older answer without the new blocks still parses', () {
      final r = AdvRequest.fromJson(const {'id': 5});
      expect(r.kind, 'support');
      expect(r.stage, 'draft');
      expect(r.chain, isNull);
      expect(r.track.map((p) => p.state), [AdvTrackState.current, AdvTrackState.waiting]);
      expect(r.shownTitle, 'Support request');
      expect(AdvStudentRequest.fromJson(const {'id': 1}).steps, isEmpty);
    });

    test('the track at the department council: submitted, director done, council now, faculty waiting', () {
      final t = AdvRequest.fromJson(sampleAdvRequestJson()).track;
      expect(t.map((p) => p.state), [AdvTrackState.done, AdvTrackState.done, AdvTrackState.current, AdvTrackState.waiting, AdvTrackState.waiting]);
      expect(t.last.label, 'Decision');
    });

    test('the track waiting on information, decided, rejected mid-way, closed, with a skipped step', () {
      final info = AdvRequest.fromJson(sampleAdvRequestJson(stage: 'needs_info'));
      expect(info.infoPending, isTrue);
      expect(info.track[1].state, AdvTrackState.attention);
      expect(info.track[1].hint, contains('information'));

      final ok = AdvRequest.fromJson(sampleAdvRequestJson(stage: 'approved')).track;
      expect(ok.map((p) => p.state), everyElement(AdvTrackState.done));
      expect(ok.last.label, 'Approved');

      final no = AdvRequest.fromJson(sampleAdvRequestJson(stage: 'rejected')).track;
      expect(no.map((p) => p.state), [AdvTrackState.done, AdvTrackState.done, AdvTrackState.failed, AdvTrackState.stopped, AdvTrackState.failed]);

      final closed = AdvRequest.fromJson(sampleAdvRequestJson(stage: 'closed')).track;
      expect(closed.last.label, 'Case closed');
      expect(closed.length, 6);

      final skipped = advRequestTrack(kind: 'support', stage: 'at_faculty_council', steps: [
        for (final s in _chain(current: 2, dept: 'waiting', skipDept: true, faculty: 'current')) AdvRequestStep.fromJson(s),
      ]);
      expect(skipped[2].state, AdvTrackState.skipped);
      expect(skipped[2].hint, contains('no council'));
      expect(skipped[3].state, AdvTrackState.current);
    });

    test('a referral: sent → the receiving department → its outcome', () {
      final r = AdvRequest.fromJson({...sampleAdvRequestJson(stage: 'in_progress', kind: 'referral'), 'chain': null, 'step': null});
      expect(r.typeLabel, 'Referral · Healthcare');
      expect(r.track.map((p) => p.label), ['Sent', 'Healthcare', 'Decision']);
      expect(r.track[1].state, AdvTrackState.current);
      final done = advRequestTrack(kind: 'referral', stage: 'handled', target: 'Healthcare', outcome: 'handled');
      expect(done.map((p) => p.state), [AdvTrackState.done, AdvTrackState.done, AdvTrackState.done]);
      final declined = advRequestTrack(kind: 'referral', stage: 'declined', outcome: 'declined');
      expect(declined[1].label, 'The receiving department');
      expect(declined[1].state, AdvTrackState.failed);
    });

    test('the list: facets and the hidden sensitive ones', () {
      final p = AdvPage.fromJson(sampleAdvRequestsJson(), AdvRequest.fromJson);
      expect(p.facet('review'), 3);
      expect(p.restricted, 2);
      expect(p.items[3].draft, isTrue);
      expect(p.items[3].studentName, 'Youssef Nabil');
    });

    test('the student\'s request: steps, history and no internal details', () {
      final r = AdvStudentRequest.fromJson(sampleAdvStudentRequestJson());
      expect(r.track.map((p) => p.state), [AdvTrackState.done, AdvTrackState.done, AdvTrackState.current, AdvTrackState.waiting, AdvTrackState.waiting]);
      expect(r.track[2].hint, 'Postponed to a later session');
      expect(r.advisorName, 'Prof. Omar Khaled');
      final m = AdvMemberSupport.fromJson(sampleAdvMemberSupportJson());
      expect(m.requests[1].typeLabel, 'Referral · Healthcare');
      expect(m.requests[1].track.map((p) => p.state), everyElement(AdvTrackState.done));
      expect(m.accommodations.first.note, isNull);
      expect(m.empty, isFalse);
      expect(AdvMemberSupport.fromJson(const {}).empty, isTrue);
    });

    test('every stage and outcome has a label and a tone in both languages', () {
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final s in {...advSupportStages, ...advReferralStages}) {
          expect(advStageLabel(s), isNot(advStageLabel('nope')), reason: '$lang $s');
          expect(advStageHint(s), isNotEmpty, reason: '$lang $s');
          expect(advStageTone(s), isNotEmpty);
        }
        for (final o in ['approved', 'rejected', 'withdrawn', 'closed', 'handled', 'declined']) {
          expect(advOutcomeLabel(o), isNotEmpty, reason: '$lang $o');
        }
        for (final k in advSupportTypeKeys) {
          expect(advSupportTypeKeyLabel(k), isNot(k), reason: '$lang $k');
        }
        for (final k in advChainKinds) {
          expect(advChainKindLabel(k), isNot(k));
          expect(advChainKindHint(k), isNotEmpty);
        }
        for (final r in ['no_department_council', 'no_faculty_council', 'target_missing']) {
          expect(advSkipReasonText(r), isNotEmpty);
        }
      }
    });
  });

  group('the approval chain', () {
    test('the config parses: the organization, the defaults, a program of its own, the choices', () {
      final c = AdvChainConfig.fromJson(sampleAdvChainJson());
      expect(c.orgSteps.map((s) => s.kind), ['director_review', 'student_department_council', 'entity', 'faculty_council']);
      expect(c.orgSteps[2].deptId, 43);
      expect(c.defaults.length, 3);
      expect(c.scopes.single.label, 'Software Engineering');
      expect(c.stepsOf('program', '11')!.length, 2);
      expect(c.stepsOf('program', '12'), isNull);
      expect(c.entity(43)!.name, 'Student Affairs committee');
      expect(c.advisingDept!.name, 'Academic Advising');
      expect(c.kinds.firstWhere((k) => k.key == 'entity').needsDept, isTrue);
      expect(AdvChainConfig.fromJson(const {}).kinds.map((k) => k.key), advChainKinds, reason: 'an older answer: the four kinds');
    });

    test('the checks mirror the server: empty, too many, director first, twins, no office, no faculty council', () {
      const d = AdvChainStep(kind: 'director_review');
      const dept = AdvChainStep(kind: 'student_department_council');
      const fac = AdvChainStep(kind: 'faculty_council');
      expect(advChainProblem(const [], facultyCouncil: true), (0, 'empty'));
      expect(advChainProblem(List.filled(7, dept), facultyCouncil: true), (6, 'too_many'));
      expect(advChainProblem(const [dept, d], facultyCouncil: true), (1, 'director_first'));
      expect(advChainProblem(const [d, dept, dept], facultyCouncil: true), (2, 'duplicate'));
      expect(advChainProblem(const [d, AdvChainStep(kind: 'entity'), fac], facultyCouncil: true), (1, 'entity_invalid'));
      expect(advChainProblem(const [d, AdvChainStep(kind: 'entity', deptId: 99)], facultyCouncil: true, entityIds: {43}), (1, 'entity_invalid'));
      expect(advChainProblem(const [d, fac], facultyCouncil: false), (1, 'no_faculty_council'));
      expect(advChainProblem(const [d, AdvChainStep(kind: 'entity', deptId: 43), AdvChainStep(kind: 'entity', deptId: 41)], facultyCouncil: false), isNull,
          reason: 'two different offices in a row are fine');
      expect(advChainProblem(const [d, dept, fac], facultyCouncil: true), isNull);
      expect(advChainProblem(const [AdvChainStep(kind: 'bogus')], facultyCouncil: true), (0, 'unknown_kind'));
    });

    test('the step body and the problem texts', () {
      expect(const AdvChainStep(kind: 'entity', deptId: 43).toJson(), {'kind': 'entity', 'dept_id': 43});
      expect(const AdvChainStep(kind: 'faculty_council', deptId: 20).toJson(), {'kind': 'faculty_council', 'dept_id': null});
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final r in ['empty', 'too_many', 'unknown_kind', 'director_first', 'duplicate', 'entity_invalid', 'no_faculty_council']) {
          expect(advChainProblemText(r), isNot(advChainProblemText('x')), reason: '$lang $r');
        }
      }
      AppConfig.lang = 'en';
      expect(advChainProblemText('duplicate', index: 2), 'Two identical steps in a row (step 3)');
    });

    test('the preview names the skipped step and why', () {
      final p = AdvChainPreview.fromJson(sampleAdvChainPreviewJson());
      expect(p.skipped, 1);
      expect(p.steps[1].reason, 'no_department_council');
      expect(p.advisingDept!.name, 'Academic Advising');
    });
  });

  group('plans', () {
    test('a plan parses with its progress, measure, items and rights', () {
      final p = AdvSupportPlan.fromJson(sampleAdvPlanJson());
      expect(p.active, isTrue);
      expect(p.progress, 0.5);
      expect(p.measure!.summary, 'Term GPA ≥ 2.30');
      expect(p.items.map((i) => i.owner), ['student', 'advisor', 'student', 'other']);
      expect(p.items[3].ownerText, 'Someone else: Student Affairs office');
      expect(p.items[2].overdue, isTrue);
      expect(p.can.delete, isFalse);
      final done = AdvSupportPlan.fromJson(sampleAdvPlanJson(status: 'completed'));
      expect(done.result!.met, isTrue);
      expect(done.finished, isTrue);
      expect(AdvSupportPlan.fromJson(const {'id': 1, 'items': [{'id': 1, 'status': 'done'}, {'id': 2}, {'id': 3, 'status': 'dropped'}]}).total, 2, reason: 'without progress: counted, dropped left out');
    });

    test('backend additions: the follow-up review, the measure now, item status kept on a PUT, the student items', () {
      final p = AdvSupportPlan.fromJson(sampleAdvPlanJson());
      expect(p.reviewDue, isTrue);
      expect(p.reviewDueAt!.toUtc(), DateTime.utc(2026, 11, 20, 9));
      expect(p.measureNow!.value, 2.12);
      expect(p.measureNow!.met, isFalse);
      expect(p.withItemStatus(3, 'done').reviewDue, isTrue);
      expect((AdvPlanDraft.of(p).toJson(version: 5)['items'] as List).map((i) => (i as Map)['status']), ['done', 'done', 'open', 'open']);
      expect(const AdvPlanDraft(title: 'x', items: []).error, 'Add at least one item');
      final mine = AdvMemberSupport.fromJson(sampleAdvMemberSupportJson()).plans.single.items;
      expect(mine.map((i) => i.mine), [true, false, true, false]);
      expect(mine.first.note, isNull);
      expect(p.items.first.mine, isNull, reason: 'staff routes do not say');
      expect(advChainKindLabel('referral'), 'The receiving department');
      const tr = ApiException(statusCode: 409, message: 'x', code: 'advising_plan_transition', body: {'detail': {'code': 'advising_plan_transition', 'current': 'completed'}});
      expect(advSupportErrorText(tr), 'The plan is now "Completed" — refresh the page');
      expect(advSupportErrorText(const ApiException(statusCode: 422, message: 'x', code: 'advising_bad_dates')), startsWith('Check the dates'));
    });

    test('ticking an item moves the progress at once', () {
      final p = AdvSupportPlan.fromJson(sampleAdvPlanJson()).withItemStatus(3, 'done');
      expect(p.done, 3);
      expect(p.items[2].done, isTrue);
      expect(p.withItemStatus(1, 'open').done, 2);
    });

    test('the lifecycle and the measures', () {
      expect(advPlanNext('draft'), ['active', 'cancelled']);
      expect(advPlanNext('active'), ['completed', 'cancelled']);
      expect(advPlanNext('completed'), ['active']);
      expect(advPlanNext('cancelled'), ['active']);
      expect(const AdvPlanMeasure(kind: 'absence_max', target: 15).summary, 'Highest absence ≤ 15%');
      expect(const AdvPlanMeasure(kind: 'custom', text: 'Finish the internship').summary, 'Finish the internship');
      expect(const AdvPlanMeasure(kind: 'cgpa').error, 'Enter the target value');
      expect(const AdvPlanMeasure(kind: 'cgpa', target: 6).error, isNotNull);
      expect(const AdvPlanMeasure(kind: 'absence_max', target: 120).error, isNotNull);
      expect(const AdvPlanMeasure(kind: 'custom').error, 'Describe the measure');
      expect(const AdvPlanMeasure(kind: 'term_gpa', target: 2.5).toJson(), {'kind': 'term_gpa', 'target': 2.5, 'text': null});
    });

    test('the editor\'s bodies: items with an id kept, new ones without, the status only on create', () {
      final p = AdvSupportPlan.fromJson(sampleAdvPlanJson());
      final d = AdvPlanDraft.of(p).copyWith(items: [...p.items.take(2), const AdvSupportPlanItem(goal: 'New goal', owner: 'other', ownerNote: '  Library ')]);
      final put = d.toJson(version: 5);
      expect(put['version'], 5);
      expect(put.containsKey('status'), isFalse);
      final items = put['items'] as List;
      expect(items.length, 3);
      expect((items[0] as Map)['id'], 1);
      expect((items[2] as Map).containsKey('id'), isFalse);
      expect((items[2] as Map)['owner_note'], 'Library');
      expect(const AdvPlanDraft(title: 'x', status: 'active').toJson()['status'], 'active');
      expect(const AdvPlanDraft().error, 'Give the plan a title');
      expect(const AdvPlanDraft(title: 'x', items: [AdvSupportPlanItem()]).error, 'Write the goal of item 1');
      expect(const AdvPlanDraft(title: 'x', measure: AdvPlanMeasure(kind: 'cgpa')).error, 'Enter the target value');
      expect(const AdvPlanDraft(title: 'x', items: [AdvSupportPlanItem(goal: 'g')]).error, isNull);
      for (final s in advPlanStatuses) {
        expect(advPlanStatusLabel(s), isNot(advPlanStatusLabel('nope')));
      }
    });
  });

  group('accommodations and the 360', () {
    test('a granted accommodation and the grant body', () {
      final a = AdvAccommodationGrant.fromJson(sampleAdvAccommodationsJson().first);
      expect(a.label, 'Extra exam time');
      expect(a.endsOn, DateTime(2027, 1, 31));
      expect(a.source, 'request');
      expect(AdvAccommodationGrant.fromJson({'id': 1, 'key': 'accessible_room', 'category': _accessibility}).label, 'Accessible room', reason: 'no label: the category\'s');
      expect(const AdvGrantDraft().error, 'Choose the category');
      expect(const AdvGrantDraft(categoryId: 7).error, 'Choose at least one accommodation');
      expect(AdvGrantDraft(categoryId: 7, keys: const ['x'], startsOn: DateTime(2026, 12, 1), endsOn: DateTime(2026, 11, 1)).error, isNotNull);
      final body = AdvGrantDraft(categoryId: 7, startsOn: DateTime(2026, 11, 3)).toggle('extra_time').toggle('front_seating').copyWith(note: ' ').toJson();
      expect(body, {'category_id': 7, 'keys': ['extra_time', 'front_seating'], 'starts_on': '2026-11-03', 'ends_on': null, 'note': null});
    });

    test('the Support block', () {
      final s = AdvSupportSummary.fromJson(sampleAdvSupportJson());
      expect(s.requestsNeedsInfo, 1);
      expect(s.requests.length, 2);
      expect(s.referrals.single.referral, isTrue);
      expect(s.activePlans.single.id, 301);
      expect(s.accommodations.length, 2);
      expect(s.restricted, 1);
      expect(s.can.accommodate, isTrue);
      expect(AdvSupportSummary.fromJson(sampleAdvSupportJson(empty: true)).empty, isTrue);
      expect(AdvSupportSummary.fromJson(const {}).can.request, isFalse);
    });

    test('status me: the request counts (0 from an older server)', () {
      final me = AdvMe.fromJson(const {'director': true, 'requests_review': 3, 'requests_needs_info': 1, 'requests_overdue': 2});
      expect(me.requests.attention, 6);
      expect(me.requests.text, '3 to review · 1 needs your information · 2 overdue');
      expect(AdvMe.fromJson(const {}).requests.attention, 0);
    });
  });

  group('timeline, links and codes', () {
    test('every Phase 7 timeline kind writes its line, in both languages', () {
      const data = <String, Map<String, dynamic>>{
        'request_submitted': {'request_id': 1, 'kind': 'support', 'support_type': 'exam_excuse', 'title': 'Final exam', 'priority': 'high'},
        'request_stage': {'request_id': 1, 'stage': 'at_department_council', 'label_ar': 'مجلس القسم', 'label_en': 'Department council'},
        'request_decided': {'request_id': 1, 'outcome': 'approved'},
        'request_closed': {'request_id': 1, 'outcome': 'rejected'},
        'referral_sent': {'request_id': 2, 'target': {'name': 'الرعاية الصحية', 'name_en': 'Healthcare'}},
        'referral_outcome': {'request_id': 2, 'outcome': 'handled'},
        'plan_created': {'plan_id': 3, 'title': 'GPA plan'},
        'plan_status': {'plan_id': 3, 'from': 'active', 'to': 'completed'},
        'accommodation_granted': {'accommodation_id': 4, 'key': 'extra_time', 'label_ar': 'وقت إضافي', 'label_en': 'Extra time'},
        'accommodation_ended': {'accommodation_id': 4, 'key': 'extra_time', 'label_ar': 'وقت إضافي', 'label_en': 'Extra time'},
        'plan_review_due': {'plan_id': 3, 'title': 'GPA plan'},
        'plan_reviewed': {'plan_id': 3, 'title': 'GPA plan'},
      };
      expect(data.keys, advSupportTimelineKinds);
      expect(AdvTimelineEntry(kind: 'request_submitted', data: data['request_submitted']!).text, 'Support request submitted · Exam excuse · Final exam');
      expect(AdvTimelineEntry(kind: 'referral_sent', data: data['referral_sent']!).text, 'Referred to Healthcare');
      expect(AdvTimelineEntry(kind: 'plan_status', data: data['plan_status']!).text, 'Support plan: Active → Completed');
      for (final lang in ['en', 'ar']) {
        AppConfig.lang = lang;
        for (final e in data.entries) {
          final line = AdvTimelineEntry(kind: e.key, data: e.value).text;
          expect(line, isNot(AdvTimelineEntry(kind: 'nope').text), reason: '$lang ${e.key}');
          expect(advSupportTimelineText(e.key, const {}), isNotNull, reason: 'an empty payload still writes a line: ${e.key}');
        }
      }
      expect(advSupportTimelineText('flag_opened', const {}), isNull);
    });

    test('deep links: the request by audience, a plan to the 360, the app links', () {
      final staff = AdvSupportLink.parse(const {'module': 'advising', 'kind': 'request', 'request_id': 901, 'member_id': 601, 'audience': 'staff'})!;
      expect(staff.kind, 'request');
      expect(staff.requestId, 901);
      expect(staff.student, isFalse);
      final nested = AdvSupportLink.parse(const {'data': {'kind': 'plan', 'plan_id': 301, 'member_id': 601, 'audience': 'student'}})!;
      expect(nested.planId, 301);
      expect(nested.student, isTrue);
      expect(AdvSupportLink.parse(const {'target_id': 12}, module: 'org_adv_request')!.requestId, 12);
      expect(AdvSupportLink.parse(const {'member_id': 601}, module: 'org_adv_plan')!.kind, 'plan');
      expect(AdvSupportLink.parse(const {'kind': 'request'}), isNull, reason: 'no request id');
      expect(AdvSupportLink.parse(const {'kind': 'flag', 'flag_id': 2}), isNull);
    });

    test('every Phase 7 server code has its own text in both languages, through orgErrorText', () {
      AppConfig.lang = 'en';
      final en = advSupportCodeTexts();
      AppConfig.lang = 'ar';
      final ar = advSupportCodeTexts();
      expect(en.keys, containsAll(const [
        'advising_request_not_draft',
        'advising_request_closed',
        'advising_request_stage',
        'advising_no_department',
        'advising_stale',
        'advising_bad_support_type',
        'advising_bad_target',
        'advising_accommodations_required',
        'advising_note_required',
        'advising_chain_invalid',
        'advising_plan_transition',
        'advising_bad_measure',
        'advising_accommodation_active',
        'advising_bad_plan',
      ]));
      for (final c in en.keys) {
        expect(en[c], isNot(ar[c]), reason: c);
        expect(advCodeTexts()[c], ar[c], reason: 'merged into advCodeTexts: $c');
        expect(orgErrorText(ApiException(statusCode: 409, message: 'x', code: c)), ar[c], reason: c);
      }
    });

    test('error texts carry the chain\'s reason and the stage a request moved to', () {
      const chain = ApiException(statusCode: 422, message: 'x', code: 'advising_chain_invalid', body: {'detail': {'code': 'advising_chain_invalid', 'index': 1, 'reason': 'director_first'}});
      const stage = ApiException(statusCode: 409, message: 'x', code: 'advising_request_stage', body: {'detail': {'code': 'advising_request_stage', 'stage': 'approved'}});
      const decided = ApiException(statusCode: 409, message: 'x', code: 'already_decided');
      expect(advSupportErrorText(chain), 'The advising director review can only be the first step (step 2)');
      expect(advSupportErrorText(stage), 'The request is now at "Approved" — refresh the page');
      expect(advSupportErrorText(decided), contains('already been decided'));
      expect(advSupportStaleCodes, contains('stale_version'));
      AppConfig.lang = 'ar';
      expect(advSupportErrorText(stage), contains('مقبول'));
    });
  });
}
