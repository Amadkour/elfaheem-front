// Demo data of the S-D review renders (docs/redesign/CAST.md): Faisal Alanazi, second secondary, boys' groups, his
// maths teacher Mr Majed Alshehri; 25 Nov 2026 is a Wednesday.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/payments/points/points_api.dart';

final sdNow = DateTime.utc(2026, 11, 25, 9);

String sdT(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

String sdIso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

PointsWallet sdWallet() => PointsWallet.fromJson({
      'balance': 1240,
      'price_per_point': 0.1,
      'currency': 'SAR',
      'topup_min': 500,
      'methods': ['card', 'bank_transfer'],
      'history': [
        {'id': 4, 'delta': 200, 'balance_after': 1240, 'kind': 'grant', 'note': sdT('منحة تفوّق: اختبار الفصل', 'Excellence grant: term exam'), 'created_at': sdIso(DateTime.utc(2026, 11, 20))},
        {'id': 3, 'delta': -890, 'balance_after': 1040, 'kind': 'spend', 'note': sdT('كتاب القدرات الكمي', 'Quantitative aptitude book'), 'created_at': sdIso(DateTime.utc(2026, 11, 10))},
        {'id': 2, 'delta': 1000, 'balance_after': 1930, 'kind': 'topup', 'note': sdT('مدى', 'mada'), 'created_at': sdIso(DateTime.utc(2026, 11, 8))},
        {'id': 1, 'delta': -300, 'balance_after': 930, 'kind': 'spend', 'ref_type': 'live_meeting', 'note': sdT('باقة أكتوبر', 'October plan'), 'created_at': sdIso(DateTime.utc(2026, 10, 30))},
      ],
    });
