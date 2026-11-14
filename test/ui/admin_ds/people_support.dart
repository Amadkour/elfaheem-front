// Shared set-up of the people_* tests (Students / Teachers / Admins / View as / My account): a super-admin signed in,
// a FakeApi that answers GET /api/v1/admin/users like the real route (role, search, status, paging) and the detail,
// realistic user rows (the fields the server's _user_row sends).
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

const _firstNames = ['سارة أحمد', 'Omar Khaled', 'ليلى محمود', 'Youssef Ali', 'منى إبراهيم', 'Karim Nabil', 'هدى سمير', 'Adam Fathy'];

/// One user row as the server sends it in `items`.
Map<String, dynamic> peopleUser(int i, String role) {
  final name = '${_firstNames[i % _firstNames.length]} ${i + 1}';
  return {
    'id': 100 + i,
    'name': name,
    'gmail': 'user$i@example.test',
    'phone': '+2010000${1000 + i}',
    'role': role,
    'country': 'EG',
    'is_active': i % 5 != 3,
    'is_verified': i % 2 == 0,
    'pending_deletion': i % 9 == 8,
    'created_at': '2026-0${1 + i % 9}-1${i % 9}T10:00:00Z',
    'last_login': i % 4 == 0 ? null : '2026-10-2${i % 9}T08:30:00Z',
    'login_times': 3 + i,
    'courses_count': role == 'teacher' ? i % 6 : 0,
    'enrolled_courses': role == 'student'
        ? [
            for (var k = 0; k < i % 4; k++) {'id': k + 1, 'name': 'Course ${k + 1}', 'status': 'active'}
          ]
        : [],
    'subscription': role == 'student' && i % 3 == 0 ? {'status': 'active', 'plan_code': 'monthly', 'amount': 1250.5, 'currency': 'EGP'} : null,
    'username': i % 2 == 0 ? 'user$i' : null,
    'image_url': null,
  };
}

/// The paged list route: filters by role, search (name / email) and status, pages of `size`.
Object? usersList(RequestOptions o, {int total = 45}) {
  final q = o.uri.queryParameters;
  final role = q['role'] ?? 'student';
  final size = int.tryParse(q['size'] ?? '') ?? 20;
  final page = int.tryParse(q['page'] ?? '') ?? 1;
  var all = [for (var i = 0; i < total; i++) peopleUser(i, role == 'admin' && i == 0 ? 'super-admin' : role)];
  final s = (q['search'] ?? '').toLowerCase();
  if (s.isNotEmpty) all = all.where((u) => '${u['name']}'.toLowerCase().contains(s) || '${u['gmail']}'.contains(s)).toList();
  final st = q['status'];
  if (st == 'active') all = all.where((u) => u['is_active'] == true).toList();
  if (st == 'inactive') all = all.where((u) => u['is_active'] == false).toList();
  final from = (page - 1) * size;
  final items = from >= all.length ? <Map<String, dynamic>>[] : all.skip(from).take(size).toList();
  return {'items': items, 'total': all.length, 'page': page, 'size': size, 'pages': (all.length / size).ceil().clamp(1, 9999)};
}

Map<String, dynamic> userDetail(int id, String role, {bool active = true}) => {
      ...peopleUser(id - 100, role),
      'id': id,
      'is_active': active,
      'devices': [],
      'subscriptions': [],
      'enrollments': [],
      'payments': [],
      if (role == 'teacher') 'teacher_profile': {'experience_years': null, 'teaching_type': 'both', 'payment_type': 'paid'},
    };

Map<String, FakeHandler> peopleRoutes({int total = 45, bool detailActive = true, String detailRole = 'student'}) => {
      'GET /api/v1/admin/users': (o) => usersList(o, total: total),
      'GET /api/v1/admin/users/*': (o) {
        final id = int.parse(o.uri.pathSegments.last);
        return userDetail(id, detailRole, active: detailActive);
      },
      'GET /api/v1/admin/lookup/*': (_) => {'items': []},
      'PUT /api/v1/admin/users/*': (_) => {'ok': true},
      'DELETE /api/v1/admin/users/*': (_) => {'ok': true},
    };

late StorageService peopleStorage;

/// Signs a super-admin in (a cached user) and plugs [api] into the app's Dio. Returns the auth provider.
Future<MyAuthProvider> peopleSetUp(FakeApi api, {String role = 'super-admin'}) async {
  translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  final storage = peopleStorage = await StorageService.getInstance();
  await storage.saveUser({'id': 7, 'name': 'Boss', 'gmail': 'boss@example.test', 'role': role});
  api.install();
  addTearDown(api.uninstall);
  return MyAuthProvider(storage: storage)..loadCachedUser();
}

/// Providers above the app, as in main.dart (the pages read MyAuthProvider).
Widget peopleProviders(MyAuthProvider auth, Widget child) => MultiProvider(
      providers: [ChangeNotifierProvider<MyAuthProvider>.value(value: auth)],
      child: child,
    );

Future<void> pumpFrames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
