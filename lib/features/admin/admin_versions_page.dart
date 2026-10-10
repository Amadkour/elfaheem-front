// lib/features/admin/admin_versions_page.dart — publish / force-update app versions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/app_loading_indicator.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_labels.dart';
import 'admin_providers.dart';

final _semver = RegExp(r'^\d+(\.\d+){0,2}([+-][0-9A-Za-z.\-]+)?$');

/// Compares the numeric part of two versions ("1.2.3+4" → [1,2,3]); <0 if a<b, 0 equal, >0 if a>b.
int _cmpVersion(String a, String b) {
  List<int> parts(String v) =>
      v.split(RegExp(r'[+-]')).first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

class AdminVersionsPage extends StatelessWidget {
  const AdminVersionsPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminVersionsProvider()..load(),
    child: const _View(),
  );
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminVersionsProvider>();
    final c = context.colors;

    Widget body;
    if (p.items.isEmpty && p.isLoading) {
      body = const Center(child: AppLoadingIndicator());
    } else if (p.error != null && p.items.isEmpty) {
      body = ErrorRetry(message: p.error!, onRetry: p.load);
    } else if (p.items.isEmpty) {
      body = EmptyState(
        'admin_no_versions_published_yet'.tr,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: p.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
          children: [for (final v in p.items) _VersionCard(v)],
        ),
      );
    }

    return BasePage(
      key: const ValueKey('admin_versions'),
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'app_version'.tr),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "admin_float",
        key: const ValueKey('admin_versions.publish'),
        backgroundColor: c.primary,
        onPressed: () => _form(context, p),
        icon: const Icon(Icons.rocket_launch_rounded, color: Colors.white),
        label: Text(
          'admin_publish_version'.tr,
          style: const TextStyle(fontFamily: 'tajawal', color: Colors.white),
        ),
      ),
      child: body,
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard(this.v);

  final Map<String, dynamic> v;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminVersionsProvider>();
    final active = asBool(v['is_active']);
    final id = asInt(v['id']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? c.success : c.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v${asStr(v['version'])}',
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: c.textDark,
                ),
              ),
              const SizedBox(width: 10),
              StatusChip(asStr(v['platform']), c.primary),
              const Spacer(),
              Switch(
                value: active,
                activeTrackColor: c.success,
                onChanged: (_) async {
                  if (!active && asBool(v['force_update'])) {
                    final ok = await confirm(
                      context,
                      message: 'admin_activate_forced_version'.tr,
                      danger: true,
                    );
                    if (!ok) return;
                  }
                  await p.toggle(id);
                },
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            children: [
              if (asBool(v['force_update']))
                StatusChip('admin_forced'.tr, c.danger),
              if (asBool(v['recommend_update']))
                StatusChip('admin_recommended'.tr, c.warning),
              if (asStrOrNull(v['min_supported']) != null)
                StatusChip(trp('admin_min_version', {'version': asStr(v['min_supported'])}), c.charcoal),
            ],
          ),
          if (asStrOrNull(v['release_notes_ar']) != null ||
              asStrOrNull(v['release_notes_en']) != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                asStr(v['release_notes_ar'], asStr(v['release_notes_en'])),
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 12.5,
                  color: c.textMedium,
                ),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text('btn_edit'.tr),
                  onPressed: () => _form(context, p, existing: v),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('delete'.tr),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      message: 'admin_delete_this_version'.tr,
                      danger: true,
                    );
                    if (ok) await p.remove(id);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _form(
    BuildContext context,
    AdminVersionsProvider p, {
      Map<String, dynamic>? existing,
    }) {
  final editing = existing != null;
  final version = TextEditingController(text: asStr(existing?['version']));
  final minSup = TextEditingController(text: asStr(existing?['min_supported']));
  final notesAr = TextEditingController(
    text: asStr(existing?['release_notes_ar']),
  );
  final notesEn = TextEditingController(
    text: asStr(existing?['release_notes_en']),
  );
  String platform = asStr(existing?['platform'], 'android');
  bool force = asBool(existing?['force_update']);
  bool recommend = asBool(existing?['recommend_update']);
  bool active = asBool(existing?['is_active'], true);
  bool busy = false;

  return showAdminSheet(context, (ctx) {
    return StatefulBuilder(
      builder: (ctx, setS) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              editing
                  ? 'admin_edit_version'.tr
                  : 'admin_publish_new_version'.tr,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!editing) ...[
                      Field(
                        controller: version,
                        label: 'admin_version_e_g_1_2_3'.tr,
                        ltr: true,
                      ),
                      ChoiceRow<String>(
                        label: 'admin_platform'.tr,
                        options: const {
                          'android': 'Android',
                          'ios': 'iOS',
                          'web': 'Web',
                        },
                        value: platform,
                        onChanged: (v) => setS(() => platform = v),
                      ),
                    ],
                    Field(
                      controller: minSup,
                      label: 'admin_minimum_supported_optional'.tr,
                      ltr: true,
                    ),
                    Field(
                      controller: notesAr,
                      label: 'admin_release_notes_arabic'.tr,
                      maxLines: 3,
                    ),
                    Field(
                      controller: notesEn,
                      label: 'admin_release_notes_english'.tr,
                      maxLines: 3,
                      ltr: true,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'admin_force_update'.tr,
                        style: const TextStyle(fontFamily: 'tajawal'),
                      ),
                      subtitle: Text(
                        'admin_blocks_the_app_until_updated'.tr,
                        style: const TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 11.5,
                        ),
                      ),
                      value: force,
                      onChanged: (v) => setS(() => force = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'admin_recommend_update'.tr,
                        style: const TextStyle(fontFamily: 'tajawal'),
                      ),
                      value: recommend,
                      onChanged: (v) => setS(() => recommend = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'admin_active_2'.tr,
                        style: const TextStyle(fontFamily: 'tajawal'),
                      ),
                      value: active,
                      onChanged: (v) => setS(() => active = v),
                    ),
                    const SizedBox(height: 8),
                    PrimaryButton(
                      label: 'save'.tr,
                      isLoading: busy,
                      onPressed: () async {
                        if (!editing &&
                            !_semver.hasMatch(version.text.trim())) {
                          toast(
                            'admin_invalid_version_number'.tr,
                            error: true,
                          );
                          return;
                        }
                        if (minSup.text.trim().isNotEmpty &&
                            !_semver.hasMatch(minSup.text.trim())) {
                          toast(
                            'admin_invalid_minimum_version'.tr,
                            error: true,
                          );
                          return;
                        }
                        final effectiveVersion =
                        editing ? asStr(existing['version']) : version.text.trim();
                        if (minSup.text.trim().isNotEmpty &&
                            _cmpVersion(minSup.text.trim(), effectiveVersion) > 0) {
                          toast('admin_min_version_gt'.tr, error: true);
                          return;
                        }
                        if (force && active) {
                          final ok = await confirm(
                            ctx,
                            message: 'admin_activate_forced_version'.tr,
                            danger: true,
                          );
                          if (!ok || !ctx.mounted) return;
                        }
                        setS(() => busy = true);
                        final common = <String, dynamic>{
                          'force_update': force,
                          'recommend_update': recommend,
                          'is_active': active,
                          'min_supported': minSup.text.trim().isEmpty
                              ? null
                              : minSup.text.trim(),
                          'release_notes_ar': notesAr.text.trim().isEmpty
                              ? null
                              : notesAr.text.trim(),
                          'release_notes_en': notesEn.text.trim().isEmpty
                              ? null
                              : notesEn.text.trim(),
                        };
                        final ok = editing
                            ? await p.update(asInt(existing['id']), common)
                            : await p.create({
                          'version': version.text.trim(),
                          'platform': platform,
                          ...common,
                        });
                        if (ctx.mounted) {
                          setS(() => busy = false);
                          if (ok) Navigator.pop(ctx);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }).whenComplete(() => disposeAfterRoute([version, minSup, notesAr, notesEn]));
}