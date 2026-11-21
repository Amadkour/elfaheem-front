// lib/core/offline/sync/offline_reads.dart — the readers' and the buttons' side of the offline layer (F13, D-1351).
//
//   final body = await readThrough('games.list', () => api.get('/api/v1/games'));
//       online: the server's answer, kept in ReadCache for later; offline (or the connection lost on the way): the
//       last kept answer. A refusal (4xx) is never covered up by an old copy: it throws as before.
//
//   if (offlineBlocked()) return;      // a button that needs the server (money, enrolment, a download)
//       offline: tells the person "this needs a connection" once and answers true.
//
// No request of its own: a home's request budget never moves (test/perf/). Which readers use it: PROGRESS.md,
// Phase 7, F13.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../config/app_config.dart';
import '../../../design/app_notice.dart';
import '../../api_client.dart';
import '../app_connectivity.dart';
import 'read_cache.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The app's online answer (tests replace it).
ValueListenable<bool> Function() offlineReadsOnline = () => AppConnectivity.instance.online;

/// The failure is the connection's, not the server's answer: no response at all, a timeout or a 5xx.
bool isTransportFailure(Object e) {
  if (e is TimeoutException) return true;
  if (e is ApiException) return e.statusCode == 0 || e.statusCode >= 500;
  return false;
}

/// [fetch] when online, keeping its answer under [key]; the last kept answer when offline or when [fetch] fails on
/// the connection. Rethrows when nothing was ever kept.
Future<Object?> readThrough(String key, Future<Object?> Function() fetch, {ReadCache? cache}) async {
  final c = cache ?? ReadCache.instance;
  if (!offlineReadsOnline().value) {
    final hit = await c.get(key);
    if (hit != null) return hit.body;
    // nothing kept: try the server anyway (the online answer may be behind)
  }
  try {
    final r = await fetch();
    unawaited(c.put(key, r));
    return r;
  } catch (e) {
    if (!isTransportFailure(e)) rethrow;
    final hit = await c.get(key);
    if (hit != null) return hit.body;
    rethrow;
  }
}

/// The sentence of a button that needs the server.
String needsConnectionText() => _t('يحتاج هذا إلى اتصال بالإنترنت. اتصل ثم حاول مرة أخرى.',
    'This needs an internet connection. Connect, then try again.');

/// True (and the person is told) when the app is offline; [notify] replaces the notice in tests.
bool offlineBlocked({void Function(String message)? notify}) {
  if (offlineReadsOnline().value) return false;
  (notify ?? (m) => showAppNotice(m, error: true))(needsConnectionText());
  return true;
}

/// The line under a result kept on the device until the server answers it.
String keptOnDeviceText() => _t('حُفظت النتيجة على هذا الجهاز، وتصل إلى حسابك عند الاتصال.',
    'Saved on this device. It reaches your account once you are online.');
