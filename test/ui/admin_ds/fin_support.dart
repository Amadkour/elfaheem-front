// Shared set-up of the fin_* tests (Finance hub: Payouts, Payments & payouts, Payment methods, Points, Fees):
// a super-admin signed in and a FakeApi that answers the finance routes with the shapes the server sends.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api.dart';

/// A withdrawal as GET /api/v1/admin/withdrawals sends it (WithdrawalResponse + the teacher / payout block).
Map<String, dynamic> finWithdrawal(int i, {String status = 'pending', String currency = 'EGP', bool automatic = false}) => {
      'id': 500 + i,
      'teacher_id': 40 + i,
      'teacher_name': ['سارة أحمد', 'Omar Khaled', 'ليلى محمود', 'Youssef Ali'][i % 4],
      'teacher_gmail': 'teacher$i@example.test',
      'amount': 1250.5 * (i + 1),
      'status': status,
      'note': i % 2 == 0 ? 'Please send before Friday' : null,
      'requested_at': '2026-10-2${i % 9}T10:00:00Z',
      'processed_at': null,
      'bank_snapshot': {'method': automatic ? 'moyasar' : 'bank_account', 'account_name': 'Account $i', 'bank_name': 'NBE', 'iban': 'EG380019000500000000263180002'},
      'payout_method': automatic ? 'moyasar' : 'bank_account',
      'payout_provider': automatic ? 'moyasar' : null,
      'payout_automatic': automatic,
      'payout_state': 'none',
      'payout_currency': currency,
    };

Object? withdrawalsRoute(RequestOptions o, {int total = 5, String currency = 'EGP'}) {
  final q = o.uri.queryParameters;
  final skip = int.tryParse(q['skip'] ?? '') ?? 0;
  final limit = int.tryParse(q['limit'] ?? '') ?? 20;
  final status = q['status'] ?? 'pending';
  final all = [for (var i = 0; i < total; i++) finWithdrawal(i, status: status, currency: currency, automatic: i % 3 == 0)];
  return {'items': all.skip(skip).take(limit).toList(), 'total': all.length};
}

Map<String, dynamic> finPayment(int i, {String status = 'completed'}) => {
      'id': 900 + i,
      'status': status,
      'amount': 350.0 + i * 75,
      'currency': 'EGP',
      'method': ['visa', 'instapay', 'bank_transfer', 'mada'][i % 4],
      'kind': i % 4 == 0 || i % 4 == 3 ? 'online' : 'transfer',
      'plan': i % 3 == 0 ? 'monthly' : null,
      'created_at': '2026-10-1${i % 9}T09:30:00Z',
      'paid_at': '2026-10-1${i % 9}T09:31:00Z',
      'transaction_id': 'TX-${1000 + i}',
      'provider': 'moyasar',
      'pending_review': false,
      'student': {'id': 10 + i, 'name': ['منى إبراهيم', 'Karim Nabil', 'هدى سمير', 'Adam Fathy'][i % 4], 'gmail': 's$i@example.test', 'phone': '+2010000$i'},
      'course': {'id': 3, 'name_ar': 'الفيزياء للثانوية', 'name_en': 'High-school physics', 'teacher': {'name': 'Omar Khaled'}},
    };

Object? paymentsRoute(RequestOptions o, {int total = 7}) {
  final q = o.uri.queryParameters;
  final page = int.tryParse(q['page'] ?? '') ?? 1;
  final size = int.tryParse(q['size'] ?? '') ?? 20;
  var status = q['status'];
  final all = [for (var i = 0; i < total; i++) finPayment(i, status: status == 'pending' ? 'pending' : (i % 5 == 4 ? 'refunded' : 'completed'))];
  final from = (page - 1) * size;
  return {
    'items': from >= all.length ? [] : all.skip(from).take(size).toList(),
    'total': all.length,
    'page': page,
    'size': size,
    'pages': (all.length / size).ceil().clamp(1, 999),
    'totals': {'by_currency': {'EGP': 4200.0}},
  };
}

Map<String, dynamic> financeSummary() => {
      'payments': {
        'completed': {'count': 38, 'by_currency': {'EGP': 48210.0, 'SAR': 1200.0}},
        'pending_transfers': {'count': 3, 'by_currency': {'EGP': 1450.0}},
        'refunded': {'count': 1, 'by_currency': {'EGP': 350.0}},
      },
      'payouts': {
        'pending': {'count': 4, 'by_currency': {'EGP': 9800.0}},
        'paid': {'count': 12, 'by_currency': {'EGP': 40100.5}},
      },
      'methods': ['visa', 'mada', 'instapay', 'bank_transfer'],
      'payout_methods': ['bank_account', 'instapay'],
    };

Map<String, FakeHandler> finRoutes({int withdrawals = 5, int payments = 7}) => {
      'GET /api/v1/admin/withdrawals': (o) => withdrawalsRoute(o, total: withdrawals),
      'GET /api/v1/admin/payouts/teachers': (_) => {
            'items': [
              for (var i = 0; i < 3; i++)
                {'id': 40 + i, 'name': 'Teacher $i', 'gmail': 't$i@example.test', 'effective_allowed': i != 2, 'override_enabled': i == 2 ? false : null, 'effective_methods': ['bank_account'], 'accounts_count': i}
            ],
            'total': 3,
            'page': 1,
            'pages': 1
          },
      'GET /api/v1/admin/payouts/settings': (_) => {
            'payouts_enabled_for_all': true,
            'payout_auto_enabled': false,
            'payout_min_amount': 250.5,
            'default_min_amount': 100,
            'payout_allowed_methods': ['bank_account', 'instapay'],
            'methods': [
              {'id': 'bank_account', 'label_ar': 'حساب بنكي', 'label_en': 'Bank account', 'automatic': false},
              {'id': 'instapay', 'label_ar': 'إنستاباي', 'label_en': 'InstaPay', 'automatic': false},
              {'id': 'moyasar', 'label_ar': 'ميسر', 'label_en': 'Moyasar', 'automatic': true, 'configured': false, 'currency': 'SAR'},
            ],
          },
      'PUT /api/v1/admin/payouts/settings': (o) => {
            'payouts_enabled_for_all': true,
            'payout_auto_enabled': false,
            'payout_min_amount': 250.5,
            'default_min_amount': 100,
            'payout_allowed_methods': ['bank_account', 'instapay'],
            'methods': [],
          },
      'GET /api/v1/admin/finance/summary': (_) => financeSummary(),
      'GET /api/v1/admin/finance/payments': (o) => paymentsRoute(o, total: payments),
      'GET /api/v1/admin/finance/payouts': (o) => {
            'items': [
              for (var i = 0; i < 4; i++)
                {
                  'id': 700 + i,
                  'status': ['pending', 'paid', 'approved', 'rejected'][i],
                  'amount': 1800.0 + i * 120,
                  'currency': 'EGP',
                  'payout_method': 'bank_account',
                  'requested_at': '2026-10-2${i}T10:00:00Z',
                  'teacher': {'id': 40 + i, 'name': ['سارة أحمد', 'Omar Khaled', 'ليلى محمود', 'Youssef Ali'][i]},
                  'destination': {'account_name': 'Account $i', 'bank_name': 'NBE'},
                  'has_receipt': i == 1,
                }
            ],
            'total': 4,
            'page': 1,
            'size': 20,
            'pages': 1,
            'totals': {'by_currency': {'EGP': 7500.0}},
          },
      'GET /api/v1/admin/settings': (_) => {'default_payment_provider': 'moyasar', 'platform_fee_percent': 10, 'max_devices': 2},
      'GET /api/v1/admin/payment-methods': (_) => {
            'items': [
              {'method': 'card', 'label': 'Credit card', 'enabled': true},
              {'method': 'bank_transfer', 'label': 'Bank transfer', 'enabled': true, 'iban': 'EG380019000500000000263180002', 'bank_name': 'NBE'},
              {'method': 'instapay', 'label': 'InstaPay', 'enabled': false, 'instapay_id': ''},
            ]
          },
      'GET /api/v1/admin/fees': (_) => {
            'items': [
              {'method': 'visa', 'label_ar': 'فيزا', 'label_en': 'Visa', 'percent': 2.5, 'fixed': 1.0, 'is_default': false, 'default_percent': 2.2, 'default_fixed': 1.0}
            ],
            'platform': {'percent': 10, 'fixed': 0, 'is_default': true, 'default_percent': 10, 'default_fixed': 0},
            'vat': {'percent': 14, 'is_default': true, 'default_percent': 14},
            'teacher_vat': {'percent': 14, 'is_default': true, 'default_percent': 14},
            'policy': {'fee_bearer': 'both', 'student_share': 0.5, 'vat_on': 'fee', 'is_default': true},
          },
      'GET /api/v1/admin/finance/ledger-report': (_) => {
            'group_by': 'teacher',
            'balanced': true,
            'groups': 12,
            'unbalanced': 0,
            'totals': {'EGP': {'gross': 1000.0, 'fee': 100.0, 'vat': 14.0, 'net': 886.0}},
            'rows': [
              for (var i = 0; i < 4; i++) {'label': 'Teacher $i', 'currency': 'EGP', 'gross': 250.0 * (i + 1), 'fee': 25.0, 'vat': 3.5, 'net': 221.5}
            ],
          },
    };

/// Signs a super-admin in and plugs [api] into the app's Dio.
Future<MyAuthProvider> finSetUp(FakeApi api) async {
  translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  final storage = await StorageService.getInstance();
  await storage.saveUser({'id': 7, 'name': 'Boss', 'gmail': 'boss@example.test', 'role': 'super-admin'});
  api.install();
  addTearDown(api.uninstall);
  return MyAuthProvider(storage: storage)..loadCachedUser();
}

Widget finProviders(MyAuthProvider auth, Widget child) => MultiProvider(
      providers: [ChangeNotifierProvider<MyAuthProvider>.value(value: auth)],
      child: child,
    );

Future<void> finFrames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
