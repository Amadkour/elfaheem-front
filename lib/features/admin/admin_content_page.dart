// lib/features/admin/admin_content_page.dart — Terms & Conditions + About editors (AR + EN).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_list.dart';
import 'admin_providers.dart';

class AdminContentPage extends StatelessWidget {
  const AdminContentPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminContentProvider()..load(),
    child: const _View(),
  );
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminContentProvider>();
    final c = context.colors;

    Widget body;
    if (p.sections.isEmpty &&
        p.termsMeta == null &&
        p.aboutInfo == null &&
        p.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (p.error != null && p.sections.isEmpty && p.termsMeta == null) {
      body = ErrorRetry(message: p.error!, onRetry: p.load);
    } else {
      final about = p.aboutInfo;
      final meta = p.termsMeta;
      body = RefreshIndicator(
        onRefresh: p.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
          children: [
            Section(
              title: 'admin_about'.tr,
              trailing: TextButton.icon(
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text('btn_edit'.tr),
                onPressed: () => _aboutForm(context, p),
              ),
              child: about == null
                  ? Text(
                      'admin_not_set_yet'.tr,
                      style: TextStyle(
                        fontFamily: 'tajawal',
                        color: c.textLight,
                      ),
                    )
                  : Column(
                      children: [
                        KeyValue(
                          'name_label'.tr,
                          '${asStr(about['name_ar'])} / ${asStr(about['name_en'])}',
                        ),
                        KeyValue(
                          'admin_tagline'.tr,
                          '${asStr(about['tagline_ar'])} / ${asStr(about['tagline_en'])}',
                        ),
                        KeyValue(
                          'admin_mission'.tr,
                          asStr(about['mission_ar']),
                        ),
                      ],
                    ),
            ),
            Section(
              title: 'admin_terms_conditions'.tr,
              trailing: TextButton.icon(
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text('admin_version_2'.tr),
                onPressed: () => _metaForm(context, p),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (meta != null) ...[
                    KeyValue('admin_version_2'.tr, asStr(meta['version'])),
                    KeyValue(
                      'admin_last_updated'.tr,
                      '${asStr(meta['last_updated_ar'])} / ${asStr(meta['last_updated_en'])}',
                    ),
                  ] else
                    Text(
                      'admin_no_version_info'.tr,
                      style: TextStyle(
                        fontFamily: 'tajawal',
                        color: c.textLight,
                      ),
                    ),
                ],
              ),
            ),
            for (final s in p.sections)
              RowCard(
                onTap: () => _sectionForm(context, p, existing: s),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asStr(s['title_ar'], asStr(s['title_en'])),
                            style: TextStyle(
                              fontFamily: 'tajawal',
                              fontWeight: FontWeight.w800,
                              color: c.textDark,
                            ),
                          ),
                          Text(
                            asStr(s['body_ar']),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'tajawal',
                              fontSize: 12.5,
                              color: c.textMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!asBool(s['is_active'], true))
                      StatusChip('admin_hidden'.tr, c.warning),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          message: 'admin_delete_this_section'.tr,
                          danger: true,
                        );
                        if (ok) await p.deleteSection(asInt(s['id']));
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'terms_and_conditions'.tr),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.primary,
        onPressed: () => _sectionForm(context, p),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'admin_add_section'.tr,
          style: const TextStyle(fontFamily: 'tajawal', color: Colors.white),
        ),
      ),
      child: body,
    );
  }
}

String? _nz(TextEditingController c) =>
    c.text.trim().isEmpty ? null : c.text.trim();

Future<void> _aboutForm(BuildContext context, AdminContentProvider p) {
  final a = p.aboutInfo ?? {};
  final nAr = TextEditingController(text: asStr(a['name_ar']));
  final nEn = TextEditingController(text: asStr(a['name_en']));
  final tAr = TextEditingController(text: asStr(a['tagline_ar']));
  final tEn = TextEditingController(text: asStr(a['tagline_en']));
  final mAr = TextEditingController(text: asStr(a['mission_ar']));
  final mEn = TextEditingController(text: asStr(a['mission_en']));
  bool busy = false;

  return showAdminSheet(context, (ctx) {
    return StatefulBuilder(
      builder: (ctx, setS) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader('admin_about'.tr),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  children: [
                    Field(controller: nAr, label: 'admin_name_ar'.tr),
                    Field(
                      controller: nEn,
                      label: 'admin_name_en'.tr,
                      ltr: true,
                    ),
                    Field(controller: tAr, label: 'admin_tagline_ar'.tr),
                    Field(
                      controller: tEn,
                      label: 'admin_tagline_en'.tr,
                      ltr: true,
                    ),
                    Field(
                      controller: mAr,
                      label: 'admin_mission_ar'.tr,
                      maxLines: 3,
                    ),
                    Field(
                      controller: mEn,
                      label: 'admin_mission_en'.tr,
                      maxLines: 3,
                      ltr: true,
                    ),
                    PrimaryButton(
                      label: 'save'.tr,
                      isLoading: busy,
                      onPressed: () async {
                        setS(() => busy = true);
                        final ok = await p.saveAbout({
                          'name_ar': _nz(nAr),
                          'name_en': _nz(nEn),
                          'tagline_ar': _nz(tAr),
                          'tagline_en': _nz(tEn),
                          'mission_ar': _nz(mAr),
                          'mission_en': _nz(mEn),
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
  }).whenComplete(() {
    for (final x in [nAr, nEn, tAr, tEn, mAr, mEn]) {
      x.dispose();
    }
  });
}

Future<void> _metaForm(BuildContext context, AdminContentProvider p) {
  final m = p.termsMeta ?? {};
  final ver = TextEditingController(text: asStr(m['version']));
  final dAr = TextEditingController(text: asStr(m['last_updated_ar']));
  final dEn = TextEditingController(text: asStr(m['last_updated_en']));
  bool busy = false;

  return showAdminSheet(context, (ctx) {
    return StatefulBuilder(
      builder: (ctx, setS) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader('admin_terms_version'.tr),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                children: [
                  Field(controller: ver, label: 'admin_version'.tr, ltr: true),
                  Field(controller: dAr, label: 'admin_last_updated_ar'.tr),
                  Field(
                    controller: dEn,
                    label: 'admin_last_updated_en'.tr,
                    ltr: true,
                  ),
                  PrimaryButton(
                    label: 'save'.tr,
                  isLoading: busy,
                    onPressed: () async {
                      setS(() => busy = true);
                      final ok = await p.saveMeta({
                        'version': _nz(ver),
                        'last_updated_ar': _nz(dAr),
                        'last_updated_en': _nz(dEn),
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
          ],
        );
      },
    );
  }).whenComplete(() {
    for (final x in [ver, dAr, dEn]) {
      x.dispose();
    }
  });
}

Future<void> _sectionForm(
  BuildContext context,
  AdminContentProvider p, {
  Map<String, dynamic>? existing,
}) {
  final icon = TextEditingController(
    text: asStr(existing?['icon_name'], 'gavel'),
  );
  final tAr = TextEditingController(text: asStr(existing?['title_ar']));
  final tEn = TextEditingController(text: asStr(existing?['title_en']));
  final bAr = TextEditingController(text: asStr(existing?['body_ar']));
  final bEn = TextEditingController(text: asStr(existing?['body_en']));
  final order = TextEditingController(
    text: asStr(existing?['order'], '${p.sections.length + 1}'),
  );
  bool active = asBool(existing?['is_active'], true);
  bool busy = false;

  return showAdminSheet(context, (ctx) {
    return StatefulBuilder(
      builder: (ctx, setS) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              existing == null
                  ? 'admin_add_section'.tr
                  : 'admin_edit_section'.tr,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  children: [
                    Field(controller: tAr, label: 'admin_title_ar'.tr),
                    Field(
                      controller: tEn,
                      label: 'admin_title_en'.tr,
                      ltr: true,
                    ),
                    Field(
                      controller: bAr,
                      label: 'admin_body_ar'.tr,
                      maxLines: 5,
                    ),
                    Field(
                      controller: bEn,
                      label: 'admin_body_en'.tr,
                      maxLines: 5,
                      ltr: true,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Field(
                            controller: icon,
                            label: 'admin_icon_name'.tr,
                            ltr: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Field(
                            controller: order,
                            label: 'order_label'.tr,
                            keyboard: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'admin_visible_to_users'.tr,
                        style: const TextStyle(fontFamily: 'tajawal'),
                      ),
                      value: active,
                      onChanged: (v) => setS(() => active = v),
                    ),
                    PrimaryButton(
                      label: 'save'.tr,
                    isLoading: busy,
                      onPressed: () async {
                        if (tAr.text.trim().isEmpty ||
                            bAr.text.trim().isEmpty) {
                          toast(
                            'admin_arabic_title_and_body_are_required'.tr,
                            error: true,
                          );
                          return;
                        }
                        setS(() => busy = true);
                        final body = <String, dynamic>{
                          'icon_name': icon.text.trim().isEmpty
                              ? 'gavel'
                              : icon.text.trim(),
                          'title_ar': tAr.text.trim(),
                          'title_en': _nz(tEn),
                          'body_ar': bAr.text.trim(),
                          'body_en': _nz(bEn),
                          'order': int.tryParse(order.text.trim()) ?? 0,
                          'is_active': active,
                        };
                        final ok = await p.saveSection(
                          id: existing == null ? null : asInt(existing['id']),
                          body: body,
                        );
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
  }).whenComplete(() {
    for (final x in [icon, tAr, tEn, bAr, bEn, order]) {
      x.dispose();
    }
  });
}
