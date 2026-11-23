// lib/features/games/admin/v4/seed_page.dart — SUPER ADMIN: the seed console (Games v4 T71, CONTRACT §10).
// `GET /admin/games/v4/seed` lists every seeded subject (seeded / approved / waiting review / levels) and
// `POST /seed/run {subjects?, more?, levels?}` runs the seed: idempotent, never overwrites an item an admin edited and
// never brings back one an admin deleted. "Run seed" fills what is missing; "Add more" adds the next batch. Both ask first.
//
//   GamesSeedPage   loads, confirms, runs
//   GamesSeedBody   plain values: the datasets line and one card per subject
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/admin_more_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart' show Json;

int _n(Object? v) => v is num ? v.toInt() : 0;
List<Json> _maps(Object? v) => v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : <Json>[];

class GamesSeedPage extends StatefulWidget {
  const GamesSeedPage({super.key, this.api});
  final GamesAdminMoreApi? api;

  @override
  State<GamesSeedPage> createState() => _GamesSeedPageState();
}

class _GamesSeedPageState extends State<GamesSeedPage> {
  late final GamesAdminMoreApi _api = widget.api ?? GamesAdminMoreApi();
  Json? _status;
  String? _error, _busyKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _api.seedStatus();
      if (mounted) setState(() { _status = s; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = adminMoreErrorText(e));
    }
  }

  /// [key] null = every subject.
  Future<void> _run({String? key, required bool more}) async {
    final what = key ?? t('كل المواد', 'every subject');
    final ok = await appConfirm(
      context,
      message: more
          ? t('إضافة دفعة جديدة من الأسئلة لـ $what؟ لن تُمسّ أسئلتك المعدّلة.', 'Add a new batch of questions for $what? Questions you edited are never touched.')
          : t('تشغيل البذر لـ $what؟ يملأ الناقص فقط، ولا يستبدل أسئلتك المعدّلة ولا يعيد ما حذفته.',
              'Run the seed for $what? It only fills what is missing, never replaces questions you edited or brings back ones you deleted.'),
      confirmLabel: more ? t('أضف المزيد', 'Add more') : t('شغّل البذر', 'Run seed'),
    );
    if (!ok || !mounted) return;
    setState(() => _busyKey = key ?? '*');
    try {
      final r = await _api.seedRun(subjects: key == null ? null : [key], more: more);
      final errors = r['errors'] is List ? (r['errors'] as List).length : 0;
      showAppNotice(
        t('أُنشئ ${_n(r['created'])} وحُدّث ${_n(r['updated'])} وتُخطّي ${_n(r['skipped'])}${errors > 0 ? ' · أخطاء: $errors' : ''}',
            'Created ${_n(r['created'])}, updated ${_n(r['updated'])}, skipped ${_n(r['skipped'])}${errors > 0 ? ' · errors: $errors' : ''}'),
        error: errors > 0,
      );
      await _load();
    } catch (e) {
      showAppNotice(adminMoreErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        title: t('الأسئلة الجاهزة', 'Seed console'),
        subtitle: t('املأ البنك بأسئلة جاهزة لكل مادة', 'Fill the bank with ready questions for each subject'),
        icon: Icons.auto_awesome_rounded,
        onRefresh: _load,
        body: _error != null && _status == null
            ? AppErrorState(message: _error!, onRetry: _load)
            : GamesSeedBody(status: _status, busyKey: _busyKey, onRun: (k, more) => _run(key: k, more: more)),
      );
}

class GamesSeedBody extends StatelessWidget {
  const GamesSeedBody({super.key, required this.status, this.busyKey, this.onRun});
  final Json? status;
  final String? busyKey;
  final void Function(String? key, bool more)? onRun;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const AppListSkeleton(items: 4);
    final items = _maps(s['items']);
    final datasets = _maps(s['datasets']);
    final bad = datasets.where((d) => d['ok'] == false).length;
    final busy = busyKey != null;
    return ListView(padding: AdminPage.bodyPadding(context), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('تشغيل لكل المواد', 'For every subject'), style: AppType.section(context)),
          AppSpace.gapXs,
          Text(
            t('«شغّل البذر» يملأ الناقص. «أضف المزيد» يضيف دفعة جديدة. كلاهما آمن: لا يستبدل ما عدّلته ولا يعيد ما حذفته.',
                '"Run seed" fills what is missing. "Add more" adds a new batch. Both are safe: they never replace what you edited or bring back what you deleted.'),
            style: AppType.meta(context),
          ),
          AppSpace.gapSm,
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            AppButton.primary(
                key: const ValueKey('games.seed.run'),
                label: t('شغّل البذر', 'Run seed'),
                icon: Icons.play_arrow_rounded,
                busy: busyKey == '*',
                onPressed: busy ? null : () => onRun?.call(null, false)),
            AppButton.secondary(
                key: const ValueKey('games.seed.more'),
                label: t('أضف المزيد', 'Add more'),
                icon: Icons.add_rounded,
                onPressed: busy ? null : () => onRun?.call(null, true)),
          ]),
          if (bad > 0) ...[
            AppSpace.gapSm,
            AppBanner(
                icon: Icons.warning_amber_rounded,
                text: t('$bad من ملفات البيانات لا تطابق بصمتها. راجع المطوّر قبل التشغيل.', '$bad data file(s) do not match their checksum. Ask the developer before running.'),
                color: context.colors.warning),
          ],
        ]),
      ),
      AppSpace.gapMd,
      if (items.isEmpty)
        AppEmpty(icon: Icons.auto_awesome_rounded, title: t('لا مواد جاهزة للبذر', 'No seedable subjects'))
      else
        for (final i in items) _SubjectCard(item: i, busy: busyKey == '${i['key']}', disabled: busy, onRun: onRun),
    ]);
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.item, required this.busy, required this.disabled, this.onRun});
  final Json item;
  final bool busy, disabled;
  final void Function(String? key, bool more)? onRun;

  @override
  Widget build(BuildContext context) {
    final i = item;
    final ar = AppConfig.lang == 'ar';
    final subject = i['subject'];
    final name = subject is Map ? '${ar ? subject['name_ar'] : subject['name_en']}' : '$subject';
    final key = '${i['key'] ?? ''}';
    final last = DateTime.tryParse('${i['last_run_at'] ?? ''}');
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(name, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppStatusBadge(label: t('جاهز ${_n(i['seeded'])}', 'Seeded ${_n(i['seeded'])}'), tone: AppTone.neutral, dense: true),
          AppStatusBadge(label: t('معتمد ${_n(i['approved'])}', 'Approved ${_n(i['approved'])}'), tone: AppTone.success, dense: true),
          AppStatusBadge(
              label: t('بانتظار المراجعة ${_n(i['pending'])}', 'Waiting ${_n(i['pending'])}'), tone: _n(i['pending']) > 0 ? AppTone.warning : AppTone.neutral, dense: true),
          AppStatusBadge(label: t('مستويات ${_n(i['levels'])}', 'Levels ${_n(i['levels'])}'), tone: AppTone.neutral, dense: true),
        ]),
        if (last != null) ...[
          AppSpace.gapXs,
          Text(t('آخر تشغيل ${AppTime.dateTime(last)}', 'Last run ${AppTime.dateTime(last)}'), style: AppType.meta(context)),
        ],
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton.tonal(
              label: t('شغّل البذر', 'Run seed'),
              icon: Icons.play_arrow_rounded,
              size: AppButtonSize.sm,
              busy: busy,
              onPressed: disabled ? null : () => onRun?.call(key, false)),
          AppButton.ghost(
              label: t('أضف المزيد', 'Add more'),
              icon: Icons.add_rounded,
              size: AppButtonSize.sm,
              onPressed: disabled ? null : () => onRun?.call(key, true)),
        ]),
      ]),
    );
  }
}
