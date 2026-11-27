// The international pass's four users (RULES §2 – §3, payments.md, international.md): a student in Saudi Arabia, a
// student in Egypt, a teacher in the UAE and a parent in the UK. Each market carries what the server would answer
// for that person: the gateway and its currency, GET /payments/methods (methods, VAT, the "≈" amount), the time zone.
// Names are Latin where the English pass checks for Arabic left on screen (data, not UI copy, is the only Arabic).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppArea;
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppAreaScope;
import 'package:flutter_education_app/features/booking/booking_api.dart';
import 'package:flutter_education_app/features/booking/booking_flow_controller.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_panel.dart';
import 'package:flutter_education_app/features/courses/student/details/subject_panels.dart';

import '../fake_api.dart';
import 'sb_subject_fakes.dart' show sbT;

class IntlMarket {
  const IntlMarket({
    required this.name,
    required this.country,
    required this.role,
    required this.zone,
    required this.provider,
    required this.currency,
    required this.methods,
    this.vatPercent,
    this.approxCurrency,
  });

  final String name, country, role, zone, provider, currency;

  /// The method keys GET /payments/methods lists for this payer, in display order.
  final List<String> methods;

  /// Null = no VAT for this payer (the server's `vat.applies: false`).
  final double? vatPercent;

  /// The payer's own currency when it differs from the charge currency (the "≈" amount).
  final String? approxCurrency;

  bool get saudi => country == 'SA';
  bool get vat => vatPercent != null;

  /// Points the course / booking / wallet price is in.
  double get price => currency == 'EGP' ? 450 : 199;

  @override
  String toString() => name;
}

/// SA: the downstream product (Moyasar, SAR, VAT 15 % domestic, مدى and STC Pay).
const intlSaStudent = IntlMarket(
  name: 'student in Saudi Arabia',
  country: 'SA',
  role: 'student',
  zone: 'Asia/Riyadh',
  provider: 'moyasar',
  currency: 'SAR',
  methods: ['mada', 'card', 'apple_pay', 'stc_pay', 'bank_transfer'],
  vatPercent: 15,
);

/// EG: Alfaheem's own market (Paymob, EGP, InstaPay, the admin's 14 % VAT).
const intlEgStudent = IntlMarket(
  name: 'student in Egypt',
  country: 'EG',
  role: 'student',
  zone: 'Africa/Cairo',
  provider: 'paymob',
  currency: 'EGP',
  methods: ['card', 'apple_pay', 'google_pay', 'bank_transfer', 'instapay'],
  vatPercent: 14,
);

/// AE: a teacher on the SA seller; no VAT outside the seller's country, a converted AED amount.
const intlAeTeacher = IntlMarket(
  name: 'teacher in the UAE',
  country: 'AE',
  role: 'teacher',
  zone: 'Asia/Dubai',
  provider: 'moyasar',
  currency: 'SAR',
  methods: ['card', 'apple_pay', 'google_pay', 'bank_transfer'],
  approxCurrency: 'AED',
);

/// GB: a parent paying an Egyptian-priced course (Paymob, EGP): no InstaPay, no VAT, a converted GBP amount.
const intlUkParent = IntlMarket(
  name: 'parent in the UK',
  country: 'GB',
  role: 'parent',
  zone: 'Europe/London',
  provider: 'paymob',
  currency: 'EGP',
  methods: ['card', 'apple_pay', 'google_pay', 'bank_transfer'],
  approxCurrency: 'GBP',
);

const intlMarkets = [intlSaStudent, intlEgStudent, intlAeTeacher, intlUkParent];

/// Words that belong to Saudi Arabia only (RULES §2): never on screen for anyone else.
const intlSaudiOnly = ['مدى', 'mada', 'Mada', 'STC', 'stc pay', 'قدرات', 'تحصيلي', 'Qudurat', 'Tahsili', '١٥٪', '15%', '15 %'];

/// Shows times in the market's zone (AppTime, the viewer's zone).
void intlUseZone(IntlMarket m) => AppTime.configurePlatform(zone: m.zone);

const _labels = {
  'mada': ('مدى', 'mada'),
  'card': ('بطاقة ائتمان', 'Credit card'),
  'apple_pay': ('Apple Pay', 'Apple Pay'),
  'google_pay': ('Google Pay', 'Google Pay'),
  'stc_pay': ('STC Pay', 'STC Pay'),
  'bank_transfer': ('تحويل بنكي', 'Bank transfer'),
  'instapay': ('إنستاباي', 'InstaPay'),
};

/// GET /api/v1/payments/methods for [m] (payments.md §1).
Map<String, dynamic> intlMethodsJson(IntlMarket m) {
  final vat = m.vatPercent;
  final v = vat?.toStringAsFixed(0);
  return {
    'provider': m.provider,
    'charge_currency': m.currency,
    'payer_country': m.country,
    'seller_country': m.provider == 'moyasar' ? 'SA' : 'EG',
    'methods': [
      for (final k in m.methods)
        {
          'key': k,
          'kind': k.endsWith('_pay') ? 'wallet' : (k == 'bank_transfer' || k == 'instapay' ? 'manual' : 'card'),
          'flow': k.endsWith('_pay') ? 'wallet' : (k == 'bank_transfer' || k == 'instapay' ? 'manual' : 'card'),
          'label': sbT(_labels[k]!.$1, _labels[k]!.$2),
          'brands': k == 'mada' ? ['mada'] : (k == 'card' ? ['visa', 'mastercard'] : []),
        },
    ],
    'bnpl': [],
    'vat': vat == null
        ? {'applies': false, 'percent': null, 'included': false, 'label': null}
        : {'applies': true, 'percent': vat, 'included': false, 'label': sbT('ضريبة القيمة المضافة $v٪', 'VAT $v%')},
    'display': m.approxCurrency == null
        ? null
        : {'currency': m.approxCurrency, 'rate': 0.2, 'amount': m.price, 'approx_amount': m.price * 0.2, 'as_of': '2026-11-20T09:00:00'},
    'charge_note': sbT('يُخصم المبلغ بعملة البوابة (${m.currency}).', 'You are charged in ${m.currency}.'),
  };
}

/// GET /api/v1/config as an older server answers it: every method the admin opened for the gateway, InstaPay
/// whenever the course is in EGP, whoever pays (the country filter is /payments/methods' job).
Map<String, dynamic> intlConfigJson(IntlMarket m) => {
      'provider': m.provider,
      'currency': m.currency,
      'payment_methods': [
        {'type': 'card', 'label': '', 'enabled': true},
        {'type': 'bank_transfer', 'label': '', 'enabled': true},
        {'type': 'instapay', 'label': '', 'enabled': m.currency == 'EGP'},
      ],
      'wallet_methods': [
        {'type': 'apple_pay', 'label': 'Apple Pay', 'enabled': true},
      ],
    };

/// The checkout routes over FakeApi: config, plans, the fee quote (with `vat_applies`) and the payer's methods.
Map<String, FakeHandler> intlCheckoutRoutes(IntlMarket m) {
  final vat = m.vat ? (m.price * 0.1 * m.vatPercent! / 100) : 0.0;
  return {
    'GET /api/v1/payments/transfer-status': (_) => <String, dynamic>{},
    'GET /api/v1/config': (_) => intlConfigJson(m),
    'GET /api/v1/payments/methods': (_) => intlMethodsJson(m),
    'GET /api/v1/payment-methods': (_) => <Object>[],
    'GET /api/v1/payments/price-options': (_) => {
          'currency': m.currency,
          'default_plan': 'yearly',
          'options': [
            {'plan': 'yearly', 'duration_days': 365, 'price': m.price, 'final_price': m.price},
          ],
        },
    'GET /api/v1/payments/fees/preview': (_) => {
          'course_price': m.price,
          'platform_fee': m.price * 0.1,
          'vat_on_platform': vat,
          'gateway_fee': 3.0,
          'total': m.price * 1.1 + vat + 3,
          'vat_applies': m.vat,
        },
  };
}

/// GET /me/points as the server answers it (every top-up method, whoever asks) plus the payer's methods.
Map<String, FakeHandler> intlWalletRoutes(IntlMarket m) => {
      'GET /api/v1/me/points': (_) => {
            'balance': 120,
            'price_per_point': 0.5,
            'currency': m.currency,
            'topup_min': 10,
            'methods': ['bank_transfer', 'instapay', 'card'],
            'history': [],
            'topups': [],
          },
      'GET /api/v1/payments/methods': (_) => intlMethodsJson(m),
      'GET /api/v1/me/live-plan': (_) => <String, dynamic>{},
      'GET /api/v1/games/v4/me/profile': (_) => {'coins': 0},
    };

/// GET /my-payments for the parent: what this account paid, in the payment's own currency.
Map<String, dynamic> intlMyPaymentsJson(IntlMarket m) => {
      'items': [
        {'id': 1191, 'course_id': 1, 'amount': m.price, 'status': 'completed', 'payment_method': 'card', 'meta_data': {'currency': m.currency}, 'paid_at': '2026-11-20T10:00:00Z', 'created_at': '2026-11-20T10:00:00Z'},
        {'id': 1172, 'course_id': 2, 'amount': m.price, 'status': 'pending', 'payment_method': 'bank_transfer', 'meta_data': {'currency': m.currency}, 'created_at': '2026-11-24T10:00:00Z'},
      ],
      'total': 2,
    };

/// The booking flow standing on "review and pay" for [m]: the subject's price in the market's currency and the
/// payer's methods. Latin names (data) so the English pass can look for Arabic UI copy.
BkFlowController intlBookingAtPay(IntlMarket m) {
  final c = BkFlowController(subjectId: 12, gradeId: 34, subjectKey: 'math', courseId: '9', api: BookingApi());
  c.options = BkOptions.fromJson({
    'subject': {'id': 12, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics'},
    'grade': {'id': 34, 'name_ar': 'الصف الثاني', 'name_en': 'Grade 11'},
    'class_minutes': 50,
    'group_size': {'min': 5, 'max': 10},
    'gender': 'boys',
    'currency': m.currency,
    'price_period': 'month',
    'modes': [
      {'key': 'remote', 'available': true},
      {'key': 'in_person', 'available': m.saudi, if (!m.saudi) 'reason': 'no_centre_here'},
    ],
    'kinds': [
      {'key': 'group', 'available': true, 'prices': {'remote': m.price}},
      {'key': 'individual', 'available': true, 'prices': {'remote': m.price * 2}},
    ],
    'proposals': true,
    'proposal_hours': 24,
  });
  c.step = 3;
  c.mode = 'remote';
  c.kind = 'group';
  c.groups = BkGroups.fromJson({
    'class_minutes': 50,
    'single': true,
    'items': [
      {
        'id': 41, 'label': 'A', 'gender': 'boys', 'mode': 'remote', 'centre': null,
        'teacher': {'user_id': 7, 'name': 'Majed', 'gender': 'male', 'avatar_url': null},
        'weekdays': [6, 1],
        'times': ['2026-12-06T16:30:00Z', '2026-12-01T16:30:00Z'],
        'starts_at': '2026-12-01T16:30:00Z', 'ends_on': null,
        'availability': 'open', 'price': m.price, 'currency': m.currency, 'price_period': 'month', 'mine': null,
      },
    ],
  });
  c.groupId = 41;
  c.step = 4;
  c.payInfo = BkPayInfo.fromJson(intlMethodsJson(m));
  c.method = c.payInfo!.bookable.first.key;
  return c;
}

/// The subject's schedule panel in December 2026, maths on Sundays and Tuesdays at 16:30 UTC (each viewer reads it
/// in their own zone).
Widget intlSchedulePanel() {
  final items = <BkCalItem>[];
  for (var d = 1; d <= 31; d++) {
    final day = DateTime.utc(2026, 12, d);
    if (day.weekday == DateTime.sunday || day.weekday == DateTime.tuesday) {
      items.add(BkCalItem(courseId: 9, title: sbT('الرياضيات', 'Mathematics'), start: day.add(const Duration(hours: 16, minutes: 30)), end: day.add(const Duration(hours: 17, minutes: 20))));
    }
  }
  return AppAreaScope(
    area: AppArea.sched,
    child: SubjectPanelFrame(
      title: sbT('جدول حصصي', 'My classes'),
      child: SubjectSchedulePanel(courseId: 9, subjectTitle: sbT('الرياضيات', 'Mathematics'), subjectKey: 'math', items: items, month: DateTime(2026, 12)),
    ),
  );
}
