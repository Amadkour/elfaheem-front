// lib/features/games/admin/v4/reciters_page.dart — the reciters (Games v4 T65, CONTRACT §9, §10, §13).
//
//   RecitersPage    GET /api/v1/admin/games/v4/reciters; every change is PUT …/reciters/{key}
//   RecitersBody    the cards over plain values: licence, permission status (verified / pending / denied) and its
//                   note, coverage, audience, the on switch and the default mark
//
// A reciter can be switched on only when its permission is `verified` (409 `reciter_not_verified`), and the default
// cannot be switched off (409 `default_required`): the card says so before the server has to. Nothing here edits
// recited text; the permission and the licence are the admin's record of why a voice may be used.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/ed_kit.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/quran_picker.dart' show AdminAudioCheck;
import 'package:flutter_education_app/features/games/admin/v4/timing_tool.dart';

String permissionName(String k) => switch (k) {
      'verified' => t('الإذن موثّق', 'Permission verified'),
      'pending' => t('الإذن قيد التحقق', 'Permission pending'),
      'denied' => t('الإذن مرفوض', 'Permission denied'),
      _ => k,
    };

/// A riwayah key in words (unknown keys stay as they are).
String riwayahName(String k) => switch (k) {
      'hafs' => t('حفص عن عاصم', 'Hafs from Asim'),
      'warsh' => t('ورش عن نافع', 'Warsh from Nafi'),
      'qalun' => t('قالون عن نافع', 'Qalun from Nafi'),
      'duri' => t('الدوري عن أبي عمرو', 'Ad-Duri from Abu Amr'),
      'susi' => t('السوسي عن أبي عمرو', 'As-Susi from Abu Amr'),
      'shubah' => t('شعبة عن عاصم', 'Shubah from Asim'),
      _ => k,
    };

AppTone permissionTone(String k) => switch (k) {
      'verified' => AppTone.success,
      'denied' => AppTone.danger,
      _ => AppTone.warning,
    };

class RecitersPage extends StatefulWidget {
  const RecitersPage({super.key, this.api});
  final ItemsV4Api? api;

  @override
  State<RecitersPage> createState() => _RecitersPageState();
}

class _RecitersPageState extends State<RecitersPage> {
  late final ItemsV4Api _api = widget.api ?? ItemsV4Api();
  List<Json>? _items;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    AdminAudioCheck.instance.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _api.reciters();
      if (mounted) setState(() { _items = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = itemErrorText(e));
    }
  }

  Future<void> _put(String key, Json body) async {
    setState(() => _busy = key);
    try {
      final saved = await _api.putReciter(key, body);
      if (!mounted) return;
      // a new default clears the others on the server: reload to show the truth
      if (body['is_default'] == true) {
        await _load();
      } else {
        setState(() => _items = [for (final r in _items!) r['key'] == key ? saved : r]);
      }
    } catch (e) {
      showAppNotice(itemErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
        width: AppWidth.reading,
        title: t('القرّاء', 'Reciters'),
        subtitle: t('الرخصة وحالة الإذن لكل قارئ', 'The licence and permission of every voice'),
        icon: Icons.record_voice_over_rounded,
        onRefresh: _load,
        body: _error != null && _items == null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _items == null
                ? const AppListSkeleton(items: 3)
                : RecitersBody(items: _items!, busyKey: _busy, onChange: _put),
      );
}

class RecitersBody extends StatelessWidget {
  const RecitersBody({super.key, required this.items, required this.onChange, this.busyKey});
  final List<Json> items;
  final String? busyKey;
  final void Function(String key, Json body) onChange;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return AppEmpty(icon: Icons.record_voice_over_rounded, title: t('لا قرّاء بعد', 'No reciters yet'));
    }
    return ListView(
      padding: AdminPage.bodyPadding(context),
      children: [for (final r in items) Padding(padding: const EdgeInsets.only(bottom: AppSpace.md), child: ReciterCard(reciter: r, busy: busyKey == r['key'], onChange: (b) => onChange('${r['key']}', b)))],
    );
  }
}

class ReciterCard extends StatelessWidget {
  const ReciterCard({super.key, required this.reciter, required this.onChange, this.busy = false});
  final Json reciter;
  final bool busy;
  final ValueChanged<Json> onChange;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = reciter;
    final ar = AppConfig.lang == 'ar';
    final status = '${r['permission_status'] ?? 'pending'}';
    final enabled = r['enabled'] == true;
    final isDefault = r['is_default'] == true;
    final verified = status == 'verified';
    final cov = jmap(r['coverage']);
    final sample = jmap(r['sample']);
    final note = '${r['permission_note'] ?? ''}';
    final licence = '${r['licence'] ?? ''}';
    final source = '${r['source_url'] ?? ''}';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${ar ? r['name_ar'] : r['name_en']}', style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(
                [
                  if ('${r['riwayah'] ?? ''}'.isNotEmpty) riwayahName('${r['riwayah']}'),
                  r['audience'] == 'kids' ? t('للأطفال', 'For kids') : t('للجميع', 'For everyone'),
                  if (cov['of'] != null) t('${cov['surahs']} من ${cov['of']} سورة', '${cov['surahs']} of ${cov['of']} surahs'),
                ].join(' · '),
                style: AppType.meta(context),
              ),
            ]),
          ),
          AppSwitch(
            value: enabled,
            // switching on needs a verified permission; the default stays on
            onChanged: (verified || enabled) && !isDefault && !busy ? (v) => onChange({'enabled': v}) : null,
          ),
        ]),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppStatusBadge(label: permissionName(status), tone: permissionTone(status), dense: true, icon: verified ? Icons.verified_rounded : Icons.hourglass_top_rounded),
          if (isDefault) AppStatusBadge(label: t('الافتراضي', 'Default'), tone: AppTone.brand, dense: true),
          if (!enabled) AppStatusBadge(label: t('متوقف', 'Off'), tone: AppTone.neutral, dense: true),
        ]),
        if (licence.isNotEmpty) ...[
          AppSpace.gapSm,
          Text('${t('الرخصة', 'Licence')}: $licence', style: AppType.body(context), maxLines: 4, overflow: TextOverflow.ellipsis),
        ],
        if (source.isNotEmpty) Text(source, textDirection: TextDirection.ltr, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
        if (note.isNotEmpty) Text(note, style: AppType.meta(context), maxLines: 4, overflow: TextOverflow.ellipsis),
        if (!verified && !enabled)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(t('لا يُفعَّل القارئ قبل توثيق إذنه.', 'A reciter is switched on only after the permission is verified.'),
                style: AppType.meta(context).copyWith(color: c.warning)),
          ),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (sample['url'] != null)
            AppButton.secondary(
              label: t('سماع عيّنة', 'Hear a sample'),
              icon: Icons.play_arrow_rounded,
              size: AppButtonSize.sm,
              onPressed: () => AdminAudioCheck.instance.play('${sample['url']}', startMs: jint(sample['start_ms']), endMs: sample['end_ms'] == null ? null : jint(sample['end_ms']), cap: const Duration(seconds: 3)),
            ),
          if (!isDefault && enabled)
            AppButton.tonal(label: t('اجعله الافتراضي', 'Make default'), size: AppButtonSize.sm, onPressed: busy ? null : () => onChange({'is_default': true})),
          if (r['source_kind'] == 'surah_files')
            AppButton.tonal(
              label: t('أزمنة الآيات', 'Ayah timings'),
              icon: Icons.timer_outlined,
              size: AppButtonSize.sm,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TimingSurahsPage(reciterKey: '${r['key']}', reciterName: '${ar ? r['name_ar'] : r['name_en']}'))),
            ),
          AppButton.ghost(label: t('الإذن', 'Permission'), icon: Icons.edit_outlined, size: AppButtonSize.sm, onPressed: busy ? null : () => _editPermission(context)),
        ]),
      ]),
    );
  }

  Future<void> _editPermission(BuildContext context) async {
    final res = await showAppSheet<Json>(context, (_) => PermissionSheet(status: '${reciter['permission_status'] ?? 'pending'}', note: '${reciter['permission_note'] ?? ''}'));
    if (res != null) onChange(res);
  }
}

/// The admin's record of why a voice may be used: status and a note (who allowed it, when, where).
class PermissionSheet extends StatefulWidget {
  const PermissionSheet({super.key, required this.status, required this.note});
  final String status;
  final String note;

  @override
  State<PermissionSheet> createState() => _PermissionSheetState();
}

class _PermissionSheetState extends State<PermissionSheet> {
  late String _status = widget.status;
  late String _note = widget.note;

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: t('إذن القارئ', 'Reciter permission'),
        children: [
          EdSelect<String>(
            label: t('الحالة', 'Status'),
            value: _status,
            options: [for (final s in ['verified', 'pending', 'denied']) (s, permissionName(s))],
            onChanged: (v) => setState(() => _status = v),
          ),
          AppSpace.gapSm,
          EdText(label: t('ملاحظة (من أذن؟ وأين؟)', 'Note (who allowed it, and where)'), value: _note, maxLines: 3, onChanged: (v) => _note = v),
          AppSpace.gapMd,
          AppButton.primary(label: t('حفظ', 'Save'), expand: true, onPressed: () => Navigator.of(context).pop({'permission_status': _status, 'permission_note': _note})),
        ],
      );
}
