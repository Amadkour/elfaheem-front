// Phase 9 (fx-admin): the super admin's consoles for booking, teacher demand and payment markets over FakeApi, with
// the CAST demo data (أ. ماجد الشهري's maths group B, فيصل العنزي's proposal) for the layout tests.
import '../fake_api.dart';

Map<String, dynamic> acBookingSettings() => {
      'prices': {
        'remote': {'group': 199, 'individual': 449},
        'in_person': {'group': 299, 'individual': 599},
      },
      'currency': 'SAR',
      'few_seats_at': 3,
      'proposal_hours': 24,
      'class_minutes': 50,
      'group_size': {'min': 5, 'max': 10},
      'price_period': 'month',
    };

Map<String, dynamic> acCentre(int id, {bool active = true}) => {
      'id': id,
      'country_code': 'SA',
      'city_id': 11,
      'district_id': null,
      'name_ar': id == 1 ? 'فرع العليا — الرياض، مبنى التعليم المستمر الطابق الثاني' : 'فرع الملقا',
      'name_en': id == 1 ? 'Olaya centre, Riyadh' : 'Malqa centre',
      'address_ar': 'طريق العليا العام',
      'address_en': 'Olaya Main Road',
      'lat': 24.69,
      'lng': 46.68,
      'active': active,
      'sort': id,
    };

Map<String, dynamic> acGroup(int id, {String status = 'published', bool below = false}) => {
      'id': id,
      'label': 'ب',
      'weekdays': [6, 1, 3],
      'times': ['2026-12-01T16:30:00Z'],
      'starts_at': '2026-12-01T16:30:00Z',
      'ends_on': null,
      'gender': 'boys',
      'mode': id.isEven ? 'in_person' : 'remote',
      'status': status,
      'title': 'الرياضيات · الثالث الثانوي · مجموعة ب',
      'edu_subject_id': 3,
      'grade_id': 12,
      'centre': id.isEven ? acCentre(1) : null,
      'teacher': {'user_id': 7, 'name': 'أ. ماجد الشهري', 'gender': 'male', 'avatar_url': null},
      'max_students': 10,
      'min_students': 5,
      'seats_taken': below ? 3 : 8,
      'waiting': 2,
      'below_minimum': below,
      'price': 199.0,
      'currency': 'SAR',
      'schedule': {'freq': 'weekly', 'weekdays': [6, 1, 3], 'start_time': '19:30', 'end_time': '20:20', 'tz': 'Asia/Riyadh'},
    };

Map<String, dynamic> acRequest(int id, String status) => {
      'id': id,
      'kind': 'individual',
      'mode': 'remote',
      'status': status,
      'subject': {'id': 3, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics'},
      'grade': {'id': 12, 'name_ar': 'الثالث الثانوي', 'name_en': 'Grade 12'},
      'centre': null,
      'details': id == 1 ? 'أحتاج مراجعة قبل اختبار نهاية الفصل في التفاضل والتكامل' : null,
      'teacher': null,
      'group': null,
      'slots': <dynamic>[],
      'proposal': {'weekdays': [6, 1], 'periods': ['evening', 'night'], 'tz': 'Asia/Riyadh'},
      'class_minutes': 50,
      'price': 449.0,
      'currency': 'SAR',
      'price_period': 'month',
      'created_at': '2026-11-26T18:20:00Z',
      'student': {'user_id': 101, 'name': 'فيصل العنزي'},
      'gender': 'boys',
    };

Map<String, dynamic> acRates() => {
      'rates': [
        {'base': 'SAR', 'quote': 'EGP', 'rate': 13.2, 'updated_at': '2026-11-20T09:00:00'},
        {'base': 'SAR', 'quote': 'KWD', 'rate': 0.082, 'updated_at': '2026-11-20T09:00:00'},
      ],
      'max_age_days': 30,
    };

Map<String, dynamic> acCatalog() => {
      'methods': [
        {'key': 'card', 'kind': 'card', 'flow': 'redirect', 'label_ar': 'بطاقة', 'label_en': 'Card', 'countries': <String>[], 'providers': ['moyasar', 'paymob'], 'enabled': true, 'brands': ['visa', 'mastercard']},
        {'key': 'mada', 'kind': 'card', 'flow': 'redirect', 'label_ar': 'مدى', 'label_en': 'mada', 'countries': ['SA'], 'providers': ['moyasar'], 'enabled': true, 'brands': ['mada']},
        {'key': 'stc_pay', 'kind': 'wallet', 'flow': 'redirect', 'label_ar': 'STC Pay', 'label_en': 'STC Pay', 'countries': ['SA'], 'providers': ['moyasar'], 'enabled': false, 'brands': <String>[]},
      ],
      'bnpl': [
        {'key': 'tabby', 'label_ar': 'تابي', 'label_en': 'Tabby', 'countries': ['SA', 'AE', 'KW'], 'enabled': false},
        {'key': 'tamara', 'label_ar': 'تمارا', 'label_en': 'Tamara', 'countries': ['SA'], 'enabled': false},
      ],
    };

Map<String, dynamic> acVat() => {
      'seller_country': 'SA',
      'rules': {
        'SA': {'percent': 15.0, 'scope': 'domestic'},
        'EG': {'percent': null, 'scope': 'all'},
      },
      'tax_number': '300123456700003',
    };

Map<String, FakeHandler> adminConsoleRoutes({bool empty = false}) => {
      'GET /api/v1/admin/booking/settings': (_) => acBookingSettings(),
      'PUT /api/v1/admin/booking/settings': (_) => acBookingSettings(),
      'GET /api/v1/admin/booking/centres': (_) => {'items': empty ? <dynamic>[] : [acCentre(1), acCentre(2, active: false)]},
      'GET /api/v1/admin/booking/groups': (_) => {
            'items': empty ? <dynamic>[] : [acGroup(41), acGroup(42, status: 'paused', below: true), acGroup(43, status: 'closed')],
          },
      'GET /api/v1/admin/booking/requests': (_) => {'items': empty ? <dynamic>[] : [acRequest(1, 'proposed'), acRequest(2, 'notify')]},
      'GET /api/v1/admin/teacher-demand/settings': (_) => {'threshold': 5, 'group_min': 5, 'stale_days': 2, 'last_day': empty ? null : '2026-11-26'},
      'PUT /api/v1/admin/teacher-demand/settings': (_) => {'threshold': 6, 'group_min': 5, 'stale_days': 2, 'last_day': '2026-11-26'},
      'POST /api/v1/admin/teacher-demand/recompute': (_) => {'day': '2026-11-27', 'rows': 42},
      'GET /api/v1/admin/payments/currency-rates': (_) => empty ? {'rates': <dynamic>[], 'max_age_days': 30} : acRates(),
      'GET /api/v1/admin/payments/catalog': (_) => acCatalog(),
      'GET /api/v1/admin/payments/vat-rules': (_) => empty ? {'seller_country': 'EG', 'rules': <String, dynamic>{}, 'tax_number': null} : acVat(),
      'GET /api/v1/admin/users': (_) => {
            'items': [
              {'id': 7, 'name': 'أ. ماجد الشهري', 'role': 'teacher'},
              {'id': 8, 'name': 'أ. نورة القحطاني', 'role': 'teacher'},
            ],
            'total': 2,
          },
      'GET /api/v1/countries': (_) => {
            'default_country': 'SA',
            'featured': ['SA', 'EG'],
            'countries': [
              {'code': 'SA', 'name_ar': 'المملكة العربية السعودية', 'name_en': 'Saudi Arabia', 'dial_code': '+966', 'phone_lengths': [9, 9], 'featured': true},
              {'code': 'EG', 'name_ar': 'مصر', 'name_en': 'Egypt', 'dial_code': '+20', 'phone_lengths': [10, 10], 'featured': true},
            ],
          },
      'GET /api/v1/edu/areas': (_) => [
            {'id': 11, 'key': 'riyadh', 'name_ar': 'الرياض', 'name_en': 'Riyadh', 'level': 1, 'has_children': false},
          ],
    };
