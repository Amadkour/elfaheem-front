// The organization dashboard's section pages over a fake server (D-103 page anatomy, org_page_kit.dart): the route
// table both test/ui/org_pages_layout_test.dart and test/visual/org_pages_golden_test.dart answer from. Every
// payload is shaped like the REAL server's (../back routers/organization/*: org_admin_router.py members / courses,
// org_dept_router.py departments, org_academic_router.py, org_join_router.py, org_registrar_router.py,
// org_services_router.py): the page envelope {total, page, size, pages, items}, naive-UTC datetimes, user_brief.
import 'package:dio/dio.dart';

import '../support/fake_api.dart' show FakeHandler;

Map<String, dynamic> _page(List<Map<String, dynamic>> items, [Map<String, dynamic> extra = const {}]) =>
    {'total': items.length, 'page': 1, 'size': 20, 'pages': 1, ...extra, 'items': items};

Map<String, dynamic> _user(int id, String name, String email, {String? username, String role = 'student', bool active = true}) =>
    {'id': id, 'name': name, 'email': email, 'phone': null, 'username': username, 'role': role, 'image_url': null, 'is_active': active};

Map<String, dynamic> _member(int id, String role, Map<String, dynamic> user,
        {String status = 'active', String? code, String? level, String? cohort, List<Map<String, dynamic>> depts = const [],
        String? expires}) =>
    {
      'id': id, 'org_id': 4, 'user_id': user['id'], 'role': role, 'status': status, 'effective_status': status,
      'is_live': status == 'active', 'student_code': code, 'permissions': null, 'joined_via': 'code_req',
      'code_verified': true, 'created_at': '2026-09-02T10:15:00', 'starts_at': null, 'expires_at': expires,
      'ended_at': null, 'end_reason': null, 'program_id': null, 'academic_level': level, 'cohort': cohort,
      'experience_level': null, 'academic_rank': null, 'max_weekly_hours': null, 'profile_verified_at': null,
      'departments': depts, 'user': user,
    };

List<Map<String, dynamic>> students() => [
      _member(112, 'student', _user(5031, 'أحمد محمود السيد', 'ahmed.mahmoud@student.edu.eg', username: 'ahmed_m'),
          code: '2026-CS-0142', level: '1', cohort: 'current'),
      _member(109, 'student', _user(5020, 'Sara Ibrahim', 'sara.ibrahim@student.edu.eg'),
          code: '2026-CS-0139', level: '2', cohort: 'current', expires: '2027-06-30T00:00:00'),
      _member(101, 'student', _user(4988, 'مريم خالد عبد العزيز', 'mariam.k@gmail.com', username: 'mariam_k', active: false),
          cohort: 'incoming'),
      _member(98, 'student', _user(4950, 'Youssef Hassan', 'youssef.hassan@student.edu.eg'), code: '2025-IS-0077', level: '3'),
    ];

List<Map<String, dynamic>> staff() => [
      _member(140, 'teacher', _user(3005, 'د. عمر فاروق', 'omar.farouk@fci.edu.eg', role: 'teacher'),
          depts: [{'dept_id': 12, 'title': 'رئيس القسم', 'is_head': true}]),
      _member(141, 'admin_assistant', _user(3010, 'Mostafa Samir', 'm.samir@fci.edu.eg', role: 'org-staff')),
    ];

Map<String, dynamic> _dept(int id, String ar, String en, String color, List<String> features,
        {Map<String, dynamic>? head, int? parent, String kind = 'service', Map<String, int> counts = const {}}) =>
    {
      'id': id, 'org_id': 4, 'unit_type': 'service', 'preset': null, 'code': null, 'name_ar': ar, 'name_en': en,
      'description': null, 'icon': 'apartment', 'logo_url': null, 'color': color, 'features': features,
      'email': null, 'phone': null, 'location': null, 'office_hours': null, 'accepts_complaints': true,
      'is_active': true, 'order': id, 'head': head, 'parent_id': parent, 'kind': kind, 'program_id': null,
      'council_id': null, 'my_permissions': null,
      'counts': {'team': 0, 'courses': 0, 'open_complaints': 0, 'pending_forms': 0, 'materials': 0, 'announcements': 0, ...counts},
    };

Map<String, dynamic> departments() => {
      'items': [
        _dept(7, 'شؤون الطلاب', 'Student Affairs', '#2563EB', ['materials', 'announcements', 'forms', 'complaints', 'members'],
            head: _user(3001, 'د. هالة عبد الرحمن', 'hala.ar@fci.edu.eg', role: 'teacher'),
            counts: {'team': 5, 'open_complaints': 3, 'pending_forms': 2}),
        _dept(9, 'الدعم الفني', 'IT Support', '#16A34A', ['announcements', 'complaints'], parent: 7, kind: 'office', counts: {'team': 2}),
        _dept(14, 'الموارد البشرية', 'Human Resources', '#D97706', ['forms', 'materials'], counts: {'team': 3}),
      ],
      'can_create': true,
    };

Map<String, dynamic> programs() => {
      'items': [
        {
          'id': 2, 'unit_type': 'academic', 'code': 'CS', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer Science',
          'description': null, 'manager': _user(3005, 'د. عمر فاروق', 'omar.farouk@fci.edu.eg', role: 'teacher'),
          'capacity': 120, 'min_electives': 2, 'is_active': true, 'entry_course_ids': [201],
          'required_course_ids': [201, 202, 205], 'elective_course_ids': [210], 'prerequisites': [], 'students': 87,
        },
        {
          'id': 3, 'unit_type': 'academic', 'code': 'IS', 'name_ar': 'نظم المعلومات', 'name_en': 'Information Systems',
          'description': null, 'manager': null, 'capacity': null, 'min_electives': 0, 'is_active': true,
          'entry_course_ids': [], 'required_course_ids': [203], 'elective_course_ids': [], 'prerequisites': [],
          'students': 41,
        },
      ],
    };

List<Map<String, dynamic>> courses() => [
      {
        'id': 205, 'org_id': 4, 'dept_id': 12, 'code': 'CS201', 'program_id': 2, 'term_id': 14, 'scope': 'department',
        'name_en': 'Data Structures', 'name_ar': 'هياكل البيانات', 'image_url': null, 'teacher': {'id': 3005, 'name': 'د. عمر فاروق'},
        'fees': 0.0, 'total_hours': 48, 'max_students': 120, 'is_published': true, 'members_only': true,
        'prerequisite_ids': [201], 'students': 96,
      },
      {
        'id': 201, 'org_id': 4, 'dept_id': null, 'code': 'CS101', 'program_id': null, 'term_id': 13, 'scope': 'general',
        'name_en': 'Introduction to Programming', 'name_ar': 'مقدمة في البرمجة', 'image_url': null,
        'teacher': {'id': 3002, 'name': 'Dr. Karim Adel'}, 'fees': 0.0, 'total_hours': 42, 'max_students': null,
        'is_published': true, 'members_only': true, 'prerequisite_ids': [], 'students': 210,
      },
      {
        'id': 199, 'org_id': 4, 'dept_id': null, 'code': null, 'program_id': null, 'term_id': null, 'scope': 'general',
        'name_en': null, 'name_ar': 'مهارات التواصل', 'image_url': null, 'teacher': null, 'fees': 150.0, 'total_hours': 12,
        'max_students': 40, 'is_published': false, 'members_only': false, 'prerequisite_ids': [], 'students': 0,
      },
    ];

Map<String, dynamic> joinSettings() => {
      'join_mode': 'code_req', 'unit_default': 'approval', 'requests_enabled': true, 'auto_accept': false,
      'code_required': true, 'approval_required': true, 'legacy_code': 'FCI-7Q2K',
      'counts': {'org_requests': 2, 'unit_requests': 2, 'active_codes': 1},
    };

Map<String, dynamic> orgJoinRequests() => {
      'total': 2, 'page': 1, 'pages': 1,
      'items': [
        {
          'id': 120, 'kind': 'org', 'status': 'pending', 'role': 'student', 'joined_via': 'code_req', 'code_verified': true,
          'created_at': '2026-10-29T14:02:00',
          'user': {'id': 5102, 'name': 'يوسف أشرف', 'email': 'youssef.ashraf@gmail.com', 'image_url': null},
        },
        {
          'id': 121, 'kind': 'org', 'status': 'pending', 'role': 'teacher', 'joined_via': 'approval', 'code_verified': false,
          'created_at': '2026-10-30T09:40:00',
          'user': {'id': 5110, 'name': 'Dr. Nour Hassan', 'email': 'nour.hassan@fci.edu.eg', 'image_url': null},
        },
      ],
    };

Map<String, dynamic> unitJoinInbox() => {
      'items': [
        {
          'id': 55, 'org_id': 4, 'unit_type': 'dept', 'unit_id': 7, 'user_id': 5031, 'status': 'pending', 'via': 'request',
          'answers': {'phone': '01001234567', 'reason': 'أرغب في المشاركة في الأنشطة'}, 'needs_verification': false,
          'checks': {}, 'code_verified': false, 'decided_by': null, 'decided_at': null, 'note': null,
          'created_at': '2026-10-28T11:20:00',
          'user': {'id': 5031, 'name': 'أحمد محمود السيد', 'email': 'ahmed.mahmoud@student.edu.eg', 'image_url': null},
          'unit': {'unit_type': 'dept', 'unit_id': 7, 'kind': 'service', 'code': 'STUDENT_AFFAIRS', 'name_ar': 'شؤون الطلاب', 'name_en': 'Student Affairs', 'is_active': true},
        },
        {
          'id': 58, 'org_id': 4, 'unit_type': 'program', 'unit_id': 2, 'user_id': 5020, 'status': 'pending', 'via': 'code',
          'answers': {}, 'needs_verification': true,
          'checks': {'academic_level': {'required': ['2', '3'], 'recorded': false}, 'entry_courses': {'required': [201], 'missing': [201]}},
          'code_verified': true, 'decided_by': null, 'decided_at': null, 'note': null, 'created_at': '2026-10-30T16:05:00',
          'user': {'id': 5020, 'name': 'Sara Ibrahim', 'email': 'sara.ibrahim@student.edu.eg', 'image_url': null},
          'unit': {'unit_type': 'program', 'unit_id': 2, 'kind': 'academic', 'code': 'CS', 'name_ar': 'علوم الحاسب', 'name_en': 'Computer Science', 'is_active': true},
        },
      ],
    };

Map<String, dynamic> academicSettings() => {
      'has_departments': true, 'graduation_course_ids': [201, 202],
      'levels': [
        {'key': '1', 'label_ar': 'الفرقة الأولى', 'label_en': 'First year'},
        {'key': '2', 'label_ar': 'الفرقة الثانية', 'label_en': 'Second year'},
      ],
      'allow_general_teachers': false, 'teacher_may_teach_lab': true,
      'selection': {'open': true, 'message': 'اختر قسمك قبل نهاية الشهر', 'deadline': '2026-11-30T23:59:00', 'auto_approve': false},
    };

Map<String, dynamic> terms() => {
      'items': [
        {'id': 15, 'year_label': '2026/2027', 'kind': 'term2', 'label_ar': 'الفصل الثاني', 'label_en': 'Term 2', 'start_date': '2027-02-14', 'end_date': '2027-06-10', 'status': 'upcoming'},
        {'id': 14, 'year_label': '2026/2027', 'kind': 'term1', 'label_ar': 'الفصل الأول', 'label_en': 'Term 1', 'start_date': '2026-09-19', 'end_date': '2027-01-21', 'status': 'current'},
      ],
    };

Map<String, dynamic> decisions() => {
      'items': [
        {
          'id': 338, 'kind': 'missing_term', 'status': 'open', 'title': 'الفصل الصيفي 2026/2027 غير موجود — مسودة جاهزة للاعتماد',
          'description': null, 'affected': {},
          'recommendation': {'action': 'create_term', 'params': {'year_label': '2026/2027', 'kind': 'summer', 'start_date': '2027-07-01', 'end_date': '2027-08-25'}, 'why': 'template'},
          'alternatives': [], 'risk': 'false_positive', 'auto_applied': false, 'entity': 'term', 'entity_id': null, 'term_id': null,
          'requested_by': null, 'decided_by': null, 'decided_at': null, 'decision': null, 'note': null, 'created_at': '2026-10-29T07:00:00',
        },
      ],
      'users': {},
      'courses': {},
      'counts': {'open': 1, 'accepted': 14, 'rejected': 3},
    };

List<Map<String, dynamic>> announcements() => [
      {
        'id': 41, 'org_id': 4, 'dept_id': null, 'title': 'بدء التسجيل للفصل الثاني', 'body': 'يبدأ التسجيل يوم الأحد 15 نوفمبر عبر التطبيق.',
        'image_url': null, 'link_url': null, 'link': {'kind': 'form', 'target': '18', 'label': 'نموذج التسجيل'}, 'category': 'academic',
        'audience': {'roles': ['student'], 'sub_orgs': true, 'dept_ids': []}, 'is_pinned': true, 'status': 'published',
        'publish_at': '2026-10-25T08:00:00', 'expire_at': '2026-11-20T00:00:00', 'notify': true, 'views': 512,
        'created_at': '2026-10-24T15:30:00', 'author': null, 'targeted': 640, 'snapshot_at': '2026-10-25T08:00:05',
        'delivered_at': '2026-10-25T08:01:10', 'stats': {'viewed': 480, 'clicked': 131, 'likes': 57, 'dislikes': 2, 'reached': 630},
      },
      {
        'id': 43, 'org_id': 4, 'dept_id': null, 'title': 'Field trip — details soon', 'body': 'Details to follow.', 'image_url': null,
        'link_url': null, 'link': null, 'category': 'general', 'audience': {'roles': ['student'], 'sub_orgs': false, 'dept_ids': [12]},
        'is_pinned': false, 'status': 'draft', 'publish_at': null, 'expire_at': null, 'notify': true, 'views': 0,
        'created_at': '2026-10-31T09:00:00', 'author': null, 'targeted': null, 'snapshot_at': null, 'delivered_at': null,
        'stats': {'viewed': 0, 'clicked': 0, 'likes': 0, 'dislikes': 0, 'reached': 0},
      },
    ];

List<Map<String, dynamic>> forms() => [
      {
        'id': 18, 'org_id': 4, 'dept_id': 7, 'title': 'طلب إثبات قيد', 'description': 'لاستخراج شهادة قيد', 'kind': 'request',
        'fields': [], 'audience': {'roles': ['student'], 'sub_orgs': true}, 'status': 'open', 'opens_at': null,
        'closes_at': '2026-12-31T00:00:00', 'allow_multiple': true, 'requires_review': true, 'mandatory': false,
        'max_responses': null, 'created_at': '2026-09-10T09:00:00', 'counts': {'total': 9, 'submitted': 2, 'in_review': 1, 'approved': 6},
      },
      {
        'id': 16, 'org_id': 4, 'dept_id': null, 'title': 'Course feedback survey', 'description': null, 'kind': 'survey',
        'fields': [], 'audience': {'roles': [], 'sub_orgs': true}, 'status': 'draft', 'opens_at': null, 'closes_at': null,
        'allow_multiple': false, 'requires_review': false, 'mandatory': false, 'max_responses': 500,
        'created_at': '2026-10-01T12:00:00', 'counts': {'total': 0},
      },
    ];

List<Map<String, dynamic>> complaints() => [
      {
        'id': 77, 'ref': 'CMP-2026-0077', 'org_id': 4, 'dept_id': 7, 'subject': 'تأخر نتيجة مادة البرمجة', 'body': 'لم تظهر نتيجتي حتى الآن',
        'category': 'academic', 'priority': 'high', 'status': 'open', 'is_anonymous': false, 'attachments': [], 'course_id': 201,
        'assigned_to': null, 'due_at': '2026-10-30T12:00:00', 'overdue': true, 'first_response_at': null, 'resolved_at': null,
        'rating': null, 'rating_note': null, 'unread': true, 'created_at': '2026-10-28T08:15:00', 'updated_at': '2026-10-28T08:15:00',
        'user': _user(5031, 'أحمد محمود السيد', 'ahmed.mahmoud@student.edu.eg', username: 'ahmed_m'),
      },
      {
        'id': 75, 'ref': 'CMP-2026-0075', 'org_id': 4, 'dept_id': 9, 'subject': 'Wi-Fi not working in Hall B', 'body': 'No connection since Monday.',
        'category': 'facilities', 'priority': 'medium', 'status': 'in_progress', 'is_anonymous': true, 'attachments': [],
        'course_id': null, 'assigned_to': _user(3010, 'Mostafa Samir', 'm.samir@fci.edu.eg', role: 'org-staff'),
        'due_at': '2026-11-03T12:00:00', 'overdue': false, 'first_response_at': '2026-10-27T10:00:00', 'resolved_at': null,
        'rating': null, 'rating_note': null, 'unread': false, 'created_at': '2026-10-26T19:40:00', 'updated_at': '2026-10-27T10:00:00',
        'user': {'id': null, 'name': 'صاحب الشكوى (هوية محجوبة)', 'email': null, 'phone': null, 'role': null, 'image_url': null, 'is_active': true},
      },
    ];

List<Map<String, dynamic>> materials() => [
      {
        'id': 64, 'org_id': 4, 'dept_id': 7, 'title': 'اللائحة الداخلية 2026', 'description': 'النسخة المعتمدة', 'folder': 'لوائح',
        'file_url': 'https://cdn.example.com/m/64.pdf', 'link_url': null, 'file_name': 'bylaws-2026.pdf', 'file_type': 'pdf',
        'file_size': 834512, 'visibility': 'members', 'audience': {'roles': ['student'], 'sub_orgs': true}, 'downloads': 143,
        'created_at': '2026-09-01T10:00:00',
      },
      {
        'id': 60, 'org_id': 4, 'dept_id': null, 'title': 'Request letter template', 'description': null, 'folder': 'Templates',
        'file_url': null, 'link_url': 'https://docs.google.com/document/d/abc', 'file_name': null, 'file_type': null,
        'file_size': null, 'visibility': 'team', 'audience': {'roles': [], 'sub_orgs': true}, 'downloads': 4,
        'created_at': '2026-08-15T09:00:00',
      },
    ];

/// The route table of every section page (org 4). [empty]: every list answers nothing (the empty states).
Map<String, FakeHandler> orgPageRoutes({bool empty = false}) {
  List<Map<String, dynamic>> l(List<Map<String, dynamic>> x) => empty ? const [] : x;
  const b = 'GET /api/v1/org/orgs/4';
  return {
    '$b/members': (RequestOptions o) {
      final role = '${o.queryParameters['role'] ?? ''}';
      final status = '${o.queryParameters['status'] ?? 'active'}';
      if (status != 'active') return _page(const []);
      return _page(l(role == 'student' ? students() : staff()));
    },
    '$b/departments': (_) => empty ? {'items': const [], 'can_create': true} : departments(),
    '$b/academic/programs': (_) => empty ? {'items': const []} : programs(),
    '$b/academic/settings': (_) => academicSettings(),
    '$b/academic/terms': (_) => empty ? {'items': const []} : terms(),
    '$b/suggestions': (_) => {'items': const [], 'courses': const {}},
    '$b/courses': (_) => _page(l(courses())),
    '$b/join/settings': (_) => joinSettings(),
    '$b/join/requests': (_) => empty ? {'total': 0, 'page': 1, 'pages': 1, 'items': const []} : orgJoinRequests(),
    '$b/join-requests/inbox': (_) => empty ? {'items': const []} : unitJoinInbox(),
    '$b/registrar/decisions': (_) => empty ? {'items': const [], 'users': const {}, 'courses': const {}, 'counts': const {}} : decisions(),
    '$b/announcements': (_) => _page(l(announcements())),
    '$b/forms': (_) => _page(l(forms())),
    '$b/complaints': (_) => _page(l(complaints()), {'stats': empty ? const {} : {'open': 1, 'in_progress': 1}}),
    '$b/materials': (_) => _page(l(materials()), {'folders': empty ? const [] : ['لوائح', 'Templates']}),
  };
}
