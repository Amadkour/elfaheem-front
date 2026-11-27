// The booking flow's demo data (CAST.md): Faisal books maths, الصف الثاني الثانوي, boys' groups with male teachers,
// group أ Sunday and Tuesday 7:30 – 8:20 pm Riyadh (16:30 UTC), no class between 5 and 7 pm. The payloads follow
// docs/redesign/api/booking.md and payments.md; [bookingRoutes] serves them over FakeApi.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppAccent, AppArea;
import 'package:flutter_education_app/design/app_kit.dart' show AppAreaScope;
import 'package:flutter_education_app/features/courses/course_space/course_space.dart' show CourseSpaceAction;
import 'package:flutter_education_app/features/courses/course_space/subject_panel.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_space.dart';
import 'package:flutter_education_app/features/courses/student/details/subject_guest_space.dart';
import 'package:flutter_education_app/features/courses/student/details/subject_panels.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/booking/booking_api.dart';
import 'package:flutter_education_app/features/booking/booking_flow_controller.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart';

import '../fake_api.dart';
import 'sb_subject_fakes.dart';

/// The cast's zone, so the goldens read the reference's times.
void bkUseRiyadh() => AppTime.configurePlatform(zone: 'Asia/Riyadh');

const int bkSubjectId = 12, bkGradeId = 34;

Map<String, dynamic> bkOptionsJson({String? gender = 'boys', bool inPerson = true}) => {
      'subject': {'id': bkSubjectId, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics'},
      'grade': {'id': bkGradeId, 'name_ar': 'الصف الثاني الثانوي', 'name_en': 'Grade 11'},
      'class_minutes': 50,
      'group_size': {'min': 5, 'max': 10},
      'gender': gender,
      'currency': 'SAR',
      'price_period': 'month',
      'modes': [
        {'key': 'remote', 'available': true},
        {'key': 'in_person', 'available': inPerson, if (!inPerson) 'reason': 'no_centre_here'},
      ],
      'kinds': [
        {'key': 'group', 'available': true, 'prices': {'remote': 199, 'in_person': 299}},
        {'key': 'individual', 'available': true, 'prices': {'remote': 449, 'in_person': 599}},
      ],
      'proposals': true,
      'proposal_hours': 24,
    };

Map<String, dynamic> bkCentresJson() => {
      'country': 'SA',
      'here_city_id': 101,
      'cities': [
        {
          'id': 101,
          'name_ar': 'الرياض',
          'name_en': 'Riyadh',
          'districts': [
            for (final (i, d) in const [
              ('النرجس', 'Al Narjis'),
              ('الملقا', 'Al Malqa'),
              ('الياسمين', 'Al Yasmin'),
              ('العليا', 'Al Olaya'),
              ('الروضة', 'Al Rawdah'),
              ('قرطبة', 'Qurtubah'),
            ].indexed)
              {
                'id': 1011 + i,
                'name_ar': d.$1,
                'name_en': d.$2,
                'centres': [
                  {'id': 3 + i, 'name_ar': 'فرع ${d.$1}', 'name_en': '${d.$2} branch', 'address_ar': 'طريق الأمير سعود', 'address_en': 'Prince Saud Rd'},
                ],
              },
          ],
        },
        for (final (i, c) in const [('جدة', 'Jeddah'), ('مكة المكرمة', 'Makkah'), ('المدينة المنورة', 'Madinah'), ('الشرقية', 'Eastern Province')].indexed)
          {
            'id': 102 + i,
            'name_ar': c.$1,
            'name_en': c.$2,
            'districts': [
              {
                'id': 2000 + i,
                'name_ar': 'الروضة',
                'name_en': 'Al Rawdah',
                'centres': [
                  {'id': 30 + i, 'name_ar': 'فرع ${c.$1}', 'name_en': '${c.$2} branch'},
                ],
              },
            ],
          },
      ],
    };

Map<String, dynamic> _teacher(int id, String ar) => {'user_id': id, 'name': ar, 'gender': 'male', 'avatar_url': null};

Map<String, dynamic> bkGroupsJson({bool single = false}) {
  // Python weekdays: Monday 0 … Sunday 6; 25 Nov 2026 is a Wednesday
  final all = [
    {
      'id': 41, 'label': 'أ', 'gender': 'boys', 'mode': 'remote', 'centre': null,
      'teacher': _teacher(7, 'أ. ماجد الشهري'),
      'weekdays': [6, 1],
      'times': ['2026-12-06T16:30:00Z', '2026-12-01T16:30:00Z'],
      'starts_at': '2026-12-01T16:30:00Z', 'ends_on': null,
      'availability': single ? 'few' : 'open', 'price': 199, 'currency': 'SAR', 'price_period': 'month', 'mine': null,
    },
    {
      'id': 42, 'label': 'ب', 'gender': 'boys', 'mode': 'remote', 'centre': null,
      'teacher': _teacher(8, 'أ. سلطان العمري'),
      'weekdays': [0, 2],
      'times': ['2026-11-30T13:00:00Z', '2026-12-02T13:00:00Z'],
      'starts_at': '2026-12-02T13:00:00Z', 'ends_on': null,
      'availability': 'few', 'price': 199, 'currency': 'SAR', 'price_period': 'month', 'mine': null,
    },
    {
      'id': 43, 'label': 'ج', 'gender': 'boys', 'mode': 'remote', 'centre': null,
      'teacher': _teacher(9, 'أ. تركي الشمري'),
      'weekdays': [0, 3],
      'times': ['2026-11-30T17:30:00Z', '2026-12-03T17:30:00Z'],
      'starts_at': '2026-12-03T17:30:00Z', 'ends_on': null,
      'availability': 'open', 'price': 199, 'currency': 'SAR', 'price_period': 'month', 'mine': null,
    },
    {
      'id': 44, 'label': 'د', 'gender': 'boys', 'mode': 'remote', 'centre': null,
      'teacher': _teacher(10, 'أ. نايف الحارثي'),
      'weekdays': [6, 2],
      'times': ['2026-12-06T18:00:00Z', '2026-12-02T18:00:00Z'],
      'starts_at': '2026-12-06T18:00:00Z', 'ends_on': null,
      'availability': 'full', 'price': 199, 'currency': 'SAR', 'price_period': 'month', 'mine': null,
    },
  ];
  return {'class_minutes': 50, 'single': single, 'items': single ? all.take(1).toList() : all};
}

Map<String, dynamic> bkSlotsJson() => {
      'class_minutes': 50,
      'items': [
        {
          'teacher': _teacher(7, 'أ. ماجد الشهري'),
          'price': 449,
          'currency': 'SAR',
          'price_period': 'month',
          'slots': [
            // Sunday 4 and 8 pm, Monday 7:30, Tuesday 4 and 7:30, Wednesday 8, Thursday 4 and 9 (Riyadh)
            {'id': 90, 'starts_at': '2026-11-29T13:00:00Z', 'weekly': true},
            {'id': 91, 'starts_at': '2026-11-29T17:00:00Z', 'weekly': true},
            {'id': 92, 'starts_at': '2026-11-30T16:30:00Z', 'weekly': true},
            {'id': 93, 'starts_at': '2026-12-01T13:00:00Z', 'weekly': true},
            {'id': 94, 'starts_at': '2026-12-01T16:30:00Z', 'weekly': true},
            {'id': 95, 'starts_at': '2026-12-02T17:00:00Z', 'weekly': true},
            {'id': 96, 'starts_at': '2026-11-26T13:00:00Z', 'weekly': true},
            {'id': 97, 'starts_at': '2026-11-26T18:00:00Z', 'weekly': true},
          ],
        },
      ],
    };

Map<String, dynamic> bkMethodsJson() => {
      'provider': 'moyasar',
      'charge_currency': 'SAR',
      'payer_country': 'SA',
      'seller_country': 'SA',
      'methods': [
        {'key': 'mada', 'kind': 'card', 'flow': 'card', 'label': 'مدى', 'brands': ['mada']},
        {'key': 'apple_pay', 'kind': 'wallet', 'flow': 'wallet', 'label': 'Apple Pay', 'brands': []},
        {'key': 'card', 'kind': 'card', 'flow': 'card', 'label': 'بطاقة ائتمان', 'brands': ['visa', 'mastercard']},
        {'key': 'bank_transfer', 'kind': 'manual', 'flow': 'manual', 'label': 'تحويل بنكي', 'brands': []},
      ],
      'bnpl': [],
      'vat': {'applies': false, 'percent': null, 'included': false, 'label': null},
      'display': null,
      'charge_note': 'يُخصم المبلغ بالريال السعودي (SAR).',
    };

Map<String, dynamic> bkBookingJson({String status = 'active'}) => {
      'id': 501,
      'kind': 'group',
      'mode': 'remote',
      'status': status,
      'subject': {'id': bkSubjectId, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics'},
      'grade': {'id': bkGradeId, 'name_ar': 'الصف الثاني الثانوي', 'name_en': 'Grade 11'},
      'centre': null,
      'details': null,
      'teacher': _teacher(7, 'أ. ماجد الشهري'),
      'group': {'id': 41, 'label': 'أ', 'weekdays': [6, 1], 'times': ['2026-12-06T16:30:00Z', '2026-12-01T16:30:00Z'], 'starts_at': '2026-12-01T16:30:00Z'},
      'slots': [],
      'proposal': null,
      'next_class_at': status == 'active' ? '2026-12-01T16:30:00Z' : null,
      'class_minutes': 50,
      'price': 199,
      'currency': 'SAR',
      'price_period': 'month',
      'hold_until': status == 'pending_payment' ? '2026-11-26T09:30:00Z' : null,
      'checkout': null,
      'created_at': '2026-11-26T09:00:00Z',
    };

/// Every booking route over FakeApi. [confirmStatus]: what confirm answers.
Map<String, FakeHandler> bookingRoutes({String confirmStatus = 'active', bool single = false}) => {
      'GET /api/v1/booking/options': (_) => bkOptionsJson(),
      'GET /api/v1/booking/centres': (_) => bkCentresJson(),
      'GET /api/v1/booking/groups': (_) => bkGroupsJson(single: single),
      'GET /api/v1/booking/slots': (_) => bkSlotsJson(),
      'GET /api/v1/payments/methods': (_) => bkMethodsJson(),
      'POST /api/v1/booking/quote': (RequestOptions o) => {
            'kind': 'group',
            'mode': 'remote',
            'teacher': _teacher(7, 'أ. ماجد الشهري'),
            'group': {'id': 41, 'label': 'أ', 'weekdays': [6, 1], 'times': ['2026-12-06T16:30:00Z', '2026-12-01T16:30:00Z'], 'starts_at': '2026-12-01T16:30:00Z'},
            'class_minutes': 50,
            'price': 199,
            'currency': 'SAR',
            'price_period': 'month',
            'pay_now': true,
            'providers': ['moyasar'],
            'availability': 'open',
          },
      'POST /api/v1/booking/confirm': (_) => {'booking': bkBookingJson(status: confirmStatus), 'checkout': null},
      'GET /api/v1/booking/me': (_) => {'items': [bkBookingJson()]},
      'POST /api/v1/booking/groups/44/notify': (_) => {'booking': bkBookingJson(status: 'waitlisted')},
      'POST /api/v1/booking/notify-other-time': (_) => {'booking': bkBookingJson(status: 'notify')},
    };

/// A controller filled by hand (no call) and standing on [step]: the goldens' states.
BkFlowController demoBkController({
  int step = 1,
  String mode = 'remote',
  String kind = 'group',
  bool single = false,
  bool proposing = false,
  bool inPerson = false,
  bool gender = true,
}) {
  final c = BkFlowController(subjectId: bkSubjectId, gradeId: bkGradeId, subjectKey: 'math', courseId: '9', api: BookingApi());
  c.options = BkOptions.fromJson(bkOptionsJson(gender: gender ? 'boys' : null));
  c.step = step;
  if (step >= 2 || inPerson) c.mode = inPerson ? 'in_person' : mode;
  if (inPerson) {
    c.centres = BkCentres.fromJson(bkCentresJson());
    c.cityId = 101;
    c.districtIndex = 0;
    c.centreId = 3;
  }
  if (step >= 3) c.kind = kind;
  if (step >= 3 && kind == 'group') {
    c.groups = BkGroups.fromJson(bkGroupsJson(single: single));
    c.groupId = 41;
  }
  if (step >= 3 && kind == 'individual') {
    c.slotTeachers = [for (final m in bkMaps(bkSlotsJson()['items'])) BkSlotTeacher.fromJson(m)];
    c.proposing = proposing;
    if (proposing) {
      c.proposalDays.addAll([6, 1]);
      c.proposalPeriods.add('afternoon');
    } else {
      c.pickedSlots[DateTime.sunday] = 90;
      c.pickedSlots[DateTime.tuesday] = 94;
    }
  }
  if (step >= 4) {
    c.payInfo = BkPayInfo.fromJson(bkMethodsJson());
    c.method = 'mada';
  }
  if (step >= 5) c.booked = BkBooking.fromJson(bkBookingJson());
  return c;
}

// ─────────────────────────────────────────────────────────────────────────────
// The subject page before subscribing, and its panels
// ─────────────────────────────────────────────────────────────────────────────

/// SubjMGuest: Faisal browses maths before booking (no count of students anywhere).
Widget demoGuestSpace({bool booking = true}) => SubjectGuestSpace(
      title: sbT('الرياضيات', 'Mathematics'),
      subject: 'math',
      grade: sbT('الصف الثاني الثانوي', 'Grade 11'),
      kindLabel: sbT('حصص مباشرة ودروس مسجّلة', 'Live classes and recorded lessons'),
      teacher: sbT('أ. ماجد الشهري', 'Mr Majed Alshehri'),
      teacherYears: 9,
      teacherBio: sbT(
        'يدرّس الرياضيات بأسلوب بسيط، ويحب يربط الدرس بأمثلة من حياة الطالب. يرد على أسئلتك بعد كل حصة.',
        'Teaches maths simply and links each lesson to examples from your life. Answers your questions after every class.',
      ),
      lessonsCount: 24,
      rating: '4.8',
      facts: [
        SubjectFact(icon: Icons.menu_book_outlined, value: '24', label: sbT('درس', 'lessons'), accent: AppAccent.pink),
        SubjectFact(icon: Icons.schedule_rounded, value: '50', label: sbT('دقيقة لكل حصة', 'minutes a class'), accent: AppAccent.grape),
      ],
      bookNote: sbT('مع كل درس دفتر وتمارين', 'Every lesson comes with a notebook and exercises'),
      steps: [
        for (final (i, s) in demoSubjectSteps(live: false).indexed)
          SubjectStep(
            id: s.id,
            number: s.number,
            title: s.title,
            meta: s.meta,
            kind: s.kind,
            state: i == 0 ? SubjectStepState.todo : SubjectStepState.locked,
          ),
      ],
      price: booking ? sbT('199 ريال', 'SAR 199') : null,
      priceNote: booking ? sbT('في الشهر', 'a month') : null,
      primaryLabel: sbT('احجز المادة', 'Book the subject'),
      onPrimary: () {},
      onPreview: () {},
      includes: [
        sbT('مسار كامل يمشي مع المنهج', 'A full path that follows the curriculum'),
        sbT('كل حصة مباشرة تتسجل وترجع لها أي وقت', 'Every live class is recorded so you can go back to it any time'),
        sbT('دفتر وتمارين لكل درس', 'A notebook and exercises for every lesson'),
        sbT('المساعد الذكي يرد على أسئلتك', 'The smart assistant answers your questions'),
      ],
      more: [
        CourseSpaceAction(icon: Icons.info_outline_rounded, label: sbT('عن الدورة', 'About the course'), onTap: () {}),
        CourseSpaceAction(icon: Icons.assignment_rounded, label: sbT('الاختبارات', 'Exams'), onTap: () {}),
      ],
      onBack: () {},
    );

/// The assistant panel: on with Faisal's question answered, or locked.
Widget demoBotPanel({bool on = true}) => AppAreaScope(
      area: AppArea.learn,
      child: SubjectPanelFrame(
        title: sbT('المساعد الذكي', 'Smart assistant'),
        child: SubjectBotPanel(
          courseId: 9,
          subjectTitle: sbT('الرياضيات', 'Mathematics'),
          gate: on
              ? const BkAssistantGate(on: true, courseId: 9)
              : const BkAssistantGate(on: false, reason: 'feature_off'),
          initialTurns: on
              ? [
                  BkBotTurn(
                    question: sbT('ليش ٢⁰ = ١؟ ما دخلت مخي', 'Why is 2⁰ = 1? I don\'t get it'),
                    answer: sbT(
                      'سؤال حلو! شف النمط: كل ما ننقص الأس واحد، نقسم على ٢. ٢³ = ٨، ٢² = ٤، ٢¹ = ٢، ٢⁰ = ١. يعني أي عدد غير الصفر، أُسّه صفر، يساوي ١.',
                      'Good question! Look at the pattern: each time the power drops by one, we divide by 2. 2³ = 8, 2² = 4, 2¹ = 2, 2⁰ = 1. So any number but zero to the power zero is 1.',
                    ),
                  ),
                ]
              : const [],
        ),
      ),
    );

/// The schedule panel in December 2026: maths on Sundays and Tuesdays, physics and English on other days.
Widget demoSchedulePanel() {
  final items = <BkCalItem>[];
  for (var d = 1; d <= 31; d++) {
    final day = DateTime.utc(2026, 12, d);
    final wd = day.weekday; // Dart: Monday 1 … Sunday 7
    if (wd == DateTime.sunday || wd == DateTime.tuesday) {
      items.add(BkCalItem(courseId: 9, title: 'الرياضيات', start: day.add(const Duration(hours: 16, minutes: 30)), end: day.add(const Duration(hours: 17, minutes: 20))));
    }
    if (wd == DateTime.monday || wd == DateTime.wednesday) {
      items.add(BkCalItem(courseId: 10, title: sbT('الفيزياء', 'Physics'), start: day.add(const Duration(hours: 13)), end: day.add(const Duration(hours: 13, minutes: 50))));
    }
    if (wd == DateTime.thursday) {
      items.add(BkCalItem(courseId: 11, title: sbT('الإنجليزي', 'English'), start: day.add(const Duration(hours: 13)), end: day.add(const Duration(hours: 13, minutes: 50))));
    }
  }
  return AppAreaScope(
    area: AppArea.sched,
    child: SubjectPanelFrame(
      title: sbT('جدول حصصي', 'My classes'),
      child: SubjectSchedulePanel(
        courseId: 9,
        subjectTitle: sbT('الرياضيات', 'Mathematics'),
        subjectKey: 'math',
        items: items,
        month: DateTime(2026, 12),
      ),
    ),
  );
}
