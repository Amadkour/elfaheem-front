// lib/design/export/export_job.dart
//
// Exports that never freeze the app (7.2):
//
//   ExportJob                 progress (0 – 1, or null = indeterminate), the current step's label, cancel
//   exportCompute(work, job)  runs the pure, CPU-heavy part of an export (a writer: rows → bytes) away from the UI:
//                             on phones and desktop in a separate isolate that Cancel kills at once; on the web
//                             (no isolates for app code) on the page's thread, after yielding a frame so the
//                             progress dialog paints, with a cancel check before and after. The isolate gets the
//                             app language, the translations and the timezone the writers read (statics are per
//                             isolate); everything else the writer needs (font bytes, images) is loaded before.
//   runExportWithProgress     the progress dialog with Cancel around a whole export (every file of it)
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' as cfg;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';

import '../app_tokens.dart';
import 'table_export_model.dart' show tx;

/// Thrown (and caught by [runExportWithProgress]) when the person cancels.
class ExportCancelled implements Exception {
  const ExportCancelled();
  @override
  String toString() => 'the export was cancelled';
}

/// One running export.
class ExportJob {
  /// 0 – 1, or null while the size of the work is unknown.
  final progress = ValueNotifier<double?>(null);

  /// What is being done now ("Fetching rows 400 / 1200", "Writing the PDF (Arabic)").
  final stage = ValueNotifier<String>('');

  final _cancel = Completer<void>();
  bool get cancelled => _cancel.isCompleted;

  /// Completes when the person cancels.
  Future<void> get onCancel => _cancel.future;

  void cancel() {
    if (!_cancel.isCompleted) _cancel.complete();
  }

  void step(String label, [double? fraction]) {
    stage.value = label;
    progress.value = fraction?.clamp(0, 1).toDouble();
  }

  void throwIfCancelled() {
    if (cancelled) throw const ExportCancelled();
  }

  void dispose() {
    progress.dispose();
    stage.dispose();
  }
}

/// The static state the writers read, carried into the export isolate.
class ExportGlobals {
  const ExportGlobals(this.lang, this.strings, this.zone, this.h24);
  final String lang;

  /// The translations (assets/translation.json) the writers' labels come from.
  final Map<String, dynamic> strings;
  final String zone;
  final bool h24;

  factory ExportGlobals.capture() => ExportGlobals(cfg.AppConfig.lang, cfg.translation, AppTime.zoneId, AppTime.use24h);

  void apply() {
    cfg.AppConfig.lang = lang;
    cfg.translation = strings;
    AppTime.configureOrg(zone, h24 ? '24h' : '12h');
  }
}

/// Runs [work] off the UI (see the file header). [work] must be pure: no plugin, no rootBundle, no widget.
/// Throws [ExportCancelled] when [job] is cancelled meanwhile.
Future<T> exportCompute<T>(FutureOr<T> Function() work, {ExportJob? job}) async {
  job?.throwIfCancelled();
  if (kIsWeb || !exportUseIsolates) {
    // let the progress dialog paint before the page's thread is busy, and after
    await Future<void>.delayed(const Duration(milliseconds: 16));
    job?.throwIfCancelled();
    final r = await work();
    await Future<void>.delayed(Duration.zero);
    job?.throwIfCancelled();
    return r;
  }
  final result = ReceivePort(), errors = ReceivePort(), exits = ReceivePort();
  final done = Completer<T>();
  Isolate? iso;
  try {
    result.listen((m) {
      if (!done.isCompleted) done.complete(m as T);
    });
    errors.listen((e) {
      final l = e is List ? e : [e, ''];
      if (!done.isCompleted) done.completeError(RemoteError('${l[0]}', '${l.length > 1 ? l[1] : ''}'));
    });
    exits.listen((_) {
      // the result message may still be on its way: give it a moment before calling the exit a failure
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (!done.isCompleted) done.completeError(StateError('the export stopped unexpectedly'));
      });
    });
    unawaited(job?.onCancel.then((_) {
      iso?.kill(priority: Isolate.immediate);
      if (!done.isCompleted) done.completeError(const ExportCancelled());
    }));
    iso = await Isolate.spawn<List<Object?>>(_exportEntry, [result.sendPort, ExportGlobals.capture(), work],
        onError: errors.sendPort, onExit: exits.sendPort, errorsAreFatal: true, debugName: 'export');
    if (job?.cancelled ?? false) iso.kill(priority: Isolate.immediate);
    return await done.future;
  } finally {
    result.close();
    errors.close();
    exits.close();
  }
}

/// Tests that need the writers on their own isolate (globals set by the test) turn this off.
bool exportUseIsolates = true;

Future<void> _exportEntry(List<Object?> m) async {
  final port = m[0] as SendPort;
  (m[1] as ExportGlobals).apply();
  final r = await (m[2] as FutureOr<Object?> Function())();
  Isolate.exit(port, r);
}

/// Runs [run] behind a progress dialog with a Cancel button. Returns its result, or null when cancelled (a notice
/// says so). Errors other than a cancel are rethrown.
Future<T?> runExportWithProgress<T>(BuildContext context, Future<T> Function(ExportJob job) run, {String? title}) async {
  final job = ExportJob();
  final nav = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ExportProgressDialog(job: job, title: title),
  );
  unawaited(nav.push(route));
  try {
    return await run(job);
  } on ExportCancelled {
    return null;
  } finally {
    if (route.isActive) nav.removeRoute(route);
    job.dispose();
  }
}

/// The dialog of [runExportWithProgress] (public for the layout tests).
class ExportProgressDialog extends StatelessWidget {
  const ExportProgressDialog({super.key, required this.job, this.title});
  final ExportJob job;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title ?? tx('exs_progress_title', 'Preparing the file…', 'جارٍ تجهيز الملف…'), style: AppType.section(context)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ValueListenableBuilder<double?>(
              valueListenable: job.progress,
              builder: (_, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                child: LinearProgressIndicator(value: v, minHeight: 6, color: c.primary, backgroundColor: c.primary.withValues(alpha: .12)),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            ValueListenableBuilder<String>(
              valueListenable: job.stage,
              builder: (_, s, _) => Text(s, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              job.cancel();
              job.step(tx('exs_cancelling', 'Cancelling…', 'جارٍ الإلغاء…'));
            },
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            child: Text(tx('exs_cancel', 'Cancel', 'إلغاء')),
          ),
        ],
      ),
    );
  }
}
