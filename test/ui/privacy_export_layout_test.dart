// "Download my data" (data-subject export): status parsing, code texts, and the page body on every screen size.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/shared/profile/privacy_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

class _FakeApi implements DataExportApi {
  _FakeApi(this.current);
  DataExportStatus current;
  int requests = 0;

  @override
  Future<DataExportStatus> status() async => current;

  @override
  Future<DataExportStatus> request() async {
    requests++;
    return current = DataExportStatus.fromJson(const {
      'state': 'ready', 'export_id': 'abc', 'size_bytes': 2048, 'expires_at': '2026-10-29T10:00:00',
      'can_request': false, 'next_request_at': '2026-10-27T10:00:00'
    });
  }

  @override
  Future<Uint8List> download(String exportId) async => Uint8List(0);
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('DataExportStatus', () {
    test('reads the server status; naive times are UTC', () {
      final s = DataExportStatus.fromJson(const {
        'state': 'ready', 'export_id': 'e1', 'requested_at': '2026-10-26T08:00:00', 'finished_at': '2026-10-26T08:00:05',
        'expires_at': '2026-10-29T08:00:05', 'size_bytes': 51234, 'can_request': false,
        'next_request_at': '2026-10-27T08:00:00', 'keep_days': 3, 'cooldown_hours': 24,
      });
      expect(s.ready, isTrue);
      expect(s.busy, isFalse);
      expect(s.requestedAt, DateTime.utc(2026, 10, 26, 8));
      expect(s.expiresAt!.isUtc, isTrue);
      expect(s.sizeBytes, 51234);
      expect(s.canRequest, isFalse);
      expect(s.nextRequestAt, DateTime.utc(2026, 10, 27, 8));
    });

    test('missing or odd fields never throw', () {
      final s = DataExportStatus.fromJson(null);
      expect(s.state, 'none');
      expect(s.ready, isFalse);
      final q = DataExportStatus.fromJson(const {'state': 'processing', 'requested_at': 'garbage', 'size_bytes': '12'});
      expect(q.busy, isTrue);
      expect(q.requestedAt, isNull);
      expect(q.sizeBytes, 12);
      expect(exportUtc('2026-10-26T08:00:00+02:00'), DateTime.utc(2026, 10, 26, 6));
      expect(DataExportStatus.fromJson(const {'state': 'ready'}).ready, isFalse, reason: 'ready needs an export id');
    });

    test('codes and states have both languages', () {
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        for (final code in ['export_rate_limited', 'export_in_progress', 'export_not_ready', 'export_expired',
            'export_replaced', 'export_failed', 'export_interrupted', 'view_as_not_allowed']) {
          expect(dataExportCodeText(code, 'FALLBACK'), isNot('FALLBACK'), reason: '$code / $lang');
        }
        expect(dataExportCodeText('something_else', 'FALLBACK'), 'FALLBACK');
        for (final st in ['none', 'queued', 'processing', 'ready', 'failed', 'expired']) {
          expect(dataExportStateText(st), isNotEmpty);
        }
      }
      AppConfig.lang = 'ar';
      expect(dataExportEntryLabel(), 'تنزيل بياناتي');
      AppConfig.lang = 'en';
      expect(dataExportEntryLabel(), 'Download my data');
    });
  });

  group('layout', () {
    final states = <String, DataExportStatus>{
      'none': DataExportStatus.empty,
      'processing': DataExportStatus.fromJson(const {'state': 'processing', 'requested_at': '2026-10-26T08:00:00'}),
      'ready': DataExportStatus.fromJson(const {
        'state': 'ready', 'export_id': 'e1', 'requested_at': '2026-10-26T08:00:00', 'expires_at': '2026-10-29T08:00:05',
        'size_bytes': 7340032, 'can_request': false, 'next_request_at': '2026-10-27T08:00:00'
      }),
      'ready+again': DataExportStatus.fromJson(const {
        'state': 'ready', 'export_id': 'e1', 'expires_at': '2026-10-29T08:00:05', 'size_bytes': 900, 'can_request': true
      }),
      'failed': DataExportStatus.fromJson(const {'state': 'failed', 'error_code': 'export_interrupted', 'can_request': true}),
      'expired': DataExportStatus.fromJson(const {'state': 'expired', 'can_request': false, 'next_request_at': '2026-10-27T08:00:00'}),
    };
    for (final e in states.entries) {
      testWidgets('DataExportView ${e.key}', (t) async {
        await expectNoLayoutErrors(t, () => DataExportView(status: e.value, onRequest: () {}, onDownload: () {}));
      });
    }

    testWidgets('loading, busy buttons and an error banner', (t) async {
      await expectNoLayoutErrors(t, () => const DataExportView(status: DataExportStatus.empty, loading: true));
      await expectNoLayoutErrors(
          t,
          () => DataExportView(
              status: states['ready']!,
              downloading: true,
              error: 'You can ask for a copy of your data once every 24 hours — a long message that has to wrap',
              onRetry: () {}));
    });

    testWidgets('buttons follow the state', (t) async {
      AppConfig.lang = 'en';
      var asked = 0, saved = 0;
      Future<void> pump(DataExportStatus s) =>
          t.pumpWidget(layoutHost(DataExportView(status: s, onRequest: () => asked++, onDownload: () => saved++)));
      await pump(DataExportStatus.empty);
      expect(find.text('Download my data'), findsNothing);
      await t.tap(find.text('Request a copy of my data'));
      expect(asked, 1);
      await pump(states['ready']!);
      await t.tap(find.text('Download my data'));
      expect(saved, 1);
      expect(find.text('Request a new copy'), findsNothing, reason: 'no request button while the 24 h wait runs');
      await pump(states['ready+again']!);
      expect(find.text('Request a new copy'), findsOneWidget);
      await pump(states['processing']!);
      await t.tap(find.byType(AppPrimaryButton), warnIfMissed: false);
      expect(asked, 1, reason: 'no second request while one is being built');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('DataExportPage loads, requests and shows the result', (t) async {
      final api = _FakeApi(DataExportStatus.empty);
      await expectNoLayoutErrors(t, () => DataExportPage(api: api), scaffold: false);
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(DataExportPage(api: _FakeApi(DataExportStatus.empty)), scaffold: false));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Request a copy of my data'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Ready to download'), findsOneWidget);
      expect(find.text('Download my data'), findsWidgets);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });
  });
}
