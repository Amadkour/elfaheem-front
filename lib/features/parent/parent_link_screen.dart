// lib/features/parent/parent_link_screen.dart
// Parent: enter the student's code, fill the fields / attach the documents the super-admin asked for
// (shown according to the ACTIVE mode), and follow the status of every request.
//   easy      -> code only
//   advanced  -> code + dynamic fields + documents (stays "pending" until an admin decides)
//   external  -> code + dynamic fields (linked only if the external service really verifies)
// Needs: file_picker (image / PDF documents). Redesign: Pa2More `screen=link|linkadv` (phase 4) — the hero, the code
// box, the fields as kit inputs (a short select as chips, a phone through WorldPhoneField), "where does the code come
// from" and the requests.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/helpers.dart';
import 'parent_consent.dart';
import 'parent_link_providers.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/world_phone_field.dart';
import 'pa_kit.dart';

class ParentLinkPage extends StatefulWidget {
  const ParentLinkPage({super.key});

  @override
  State<ParentLinkPage> createState() => _ParentLinkPageState();
}

class _ParentLinkPageState extends State<ParentLinkPage> {
  final _code = TextEditingController();
  final _ctrls = <String, TextEditingController>{};
  final _selects = <String, String?>{};
  final _docs = <String, PlatformFile>{};
  String _modeSeen = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ParentLinkProvider>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _code.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String key) => _ctrls.putIfAbsent(key, () => TextEditingController());

  void _resetFormIfConfigChanged(ParentLinkProvider p) {
    final sig = '${p.mode}|${p.fields.map((f) => f['key']).join(',')}|${p.documents.map((d) => d['key']).join(',')}';
    if (sig != _modeSeen) {
      _modeSeen = sig;
      _selects.clear();
      _docs.clear();
      for (final c in _ctrls.values) {
        c.clear();
      }
    }
  }

  Future<void> _pick(String key) async {
    // file_picker v12+: pickFile() returns PlatformFile? (null if cancelled).
    // The bytes are read later, when the request is submitted.
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (f == null) return;
    // PlatformFile.size was removed in v12 — length is now a method.
    final size = f.lengthSync() ?? await f.length() ?? 0;
    if (size > 8 * 1024 * 1024) {
      plToast('pl_file_too_big'.tr);
      return;
    }
    setState(() => _docs[key] = f);
  }

  Future<void> _submit(ParentLinkProvider p) async {
    final code = _code.text.trim();
    if (code.length < 4) {
      plToast('pl_enter_code'.tr);
      return;
    }
    final values = <String, String>{};
    for (final f in p.fields) {
      final key = '${f['key']}';
      final v = (f['type'] == 'select' ? _selects[key] : _ctrl(key).text.trim()) ?? '';
      if (f['required'] == true && v.isEmpty) {
        plToast('${'pl_field_required'.tr}: ${plLabel(f)}');
        return;
      }
      if (v.isNotEmpty) values[key] = v;
    }
    for (final d in p.documents) {
      if (d['required'] == true && !_docs.containsKey('${d['key']}')) {
        plToast('${'pl_doc_required'.tr}: ${plLabel(d)}');
        return;
      }
    }
    var r = await p.redeem(code, values, Map.of(_docs));
    if (!mounted) return;
    // an under-age child: ask for the parent's consent (version v1), then send the same request with it
    if (r == null && p.lastErrorCode == 'consent_required') {
      final agreed = await showParentConsentDialog(context);
      if (!mounted) return;
      if (agreed) {
        r = await p.redeem(code, values, Map.of(_docs), consent: true);
        if (!mounted) return;
      }
    }
    if (r == null) {
      plToast(p.errorMessage);
      return;
    }
    _code.clear();
    setState(() {
      _docs.clear();
      _selects.clear();
    });
    for (final c in _ctrls.values) {
      c.clear();
    }
    plToast(r['status'] == 'approved' ? 'pl_linked_ok'.tr : 'pl_submitted_pending'.tr, error: false);
  }

  Widget _fieldWidget(Map<String, dynamic> f) {
    final key = '${f['key']}';
    final label = '${plLabel(f)}${f['required'] == true ? ' *' : ''}';
    switch (f['type']) {
      case 'select':
        final options = [for (final o in (f['options'] as List? ?? [])) '$o'];
        // a short list reads as chips (the design's "صلتك بالطالب"), a long one as the kit's dropdown
        if (options.length <= 4) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppType.tileTitle(context)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final o in options)
                  AppChip(
                    key: ValueKey('pa.link.$key.$o'),
                    label: _optionLabel(o),
                    selected: _selects[key] == o,
                    onTap: () => setState(() => _selects[key] = _selects[key] == o ? null : o),
                  ),
              ]),
            ]),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppDropdown<String>(
            key: ValueKey('sel-$key-$_modeSeen-${_selects[key]}'),
            initialValue: _selects[key],
            decoration: InputDecoration(labelText: label),
            items: [for (final o in options) DropdownMenuItem(value: o, child: Text(_optionLabel(o)))],
            onChanged: (v) => setState(() => _selects[key] = v),
          ),
        );
      case 'date':
        final c = _ctrl(key);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: GestureDetector(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime(DateTime.now().year - 10),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (d != null) c.text = plDate(d);
            },
            child: AbsorbPointer(child: AppField(controller: c, label: label, icon: Icons.calendar_month_rounded, readOnly: true)),
          ),
        );
      case 'phone':
        // any country (RULES §3): the picker builds the E.164 number
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: WorldPhoneField(controller: _ctrl(key), label: label, required: f['required'] == true, fieldKey: ValueKey('pa.link.$key')),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppField(
            controller: _ctrl(key),
            label: label,
            icon: f['type'] == 'number' ? Icons.badge_outlined : Icons.person_outline_rounded,
            keyboard: f['type'] == 'number' ? TextInputType.number : TextInputType.text,
          ),
        );
    }
  }

  // known option values get a translation, anything else is shown as typed
  String _optionLabel(String o) {
    final k = 'pl_opt_$o';
    final t = k.tr;
    return t == k ? o : t;
  }

  Widget _docWidget(Map<String, dynamic> d) {
    final key = '${d['key']}';
    final f = _docs[key];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppTile(
        icon: f == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
        tone: f == null ? null : context.colors.kit.ok,
        title: '${plLabel(d)}${d['required'] == true ? ' *' : ''}',
        subtitle: f?.name ?? 'pl_doc_hint'.tr,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          AppButton.secondary(label: f == null ? 'pl_choose'.tr : 'pl_change'.tr, size: AppButtonSize.sm, onPressed: () => _pick(key)),
          if (f != null)
            AppIconButton(icon: Icons.close_rounded, tooltip: 'pa_remove'.tr, onPressed: () => setState(() => _docs.remove(key))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ParentLinkProvider>();
    final c = context.colors;
    _resetFormIfConfigChanged(p);
    final advanced = p.mode == 'advanced';
    final hero = AppHero(
      kicker: 'pa_link_child'.tr,
      title: 'pa_link_title'.tr,
      subtitle: 'pl_mode_hint_${p.mode}'.tr,
    );
    final form = AppCard(
      title: 'pa_link_child'.tr,
      action: AppStatusBadge(
        label: advanced ? 'pa_link_needs_review'.tr : (p.mode == 'external' ? 'pa_link_verified'.tr : 'pa_link_direct'.tr),
        tone: advanced ? AppTone.warning : AppTone.success,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${'pl_student_code'.tr} *', style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.xs),
        TextField(
          key: const ValueKey('pa.link.code'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLength: 9,
          style: appText(AppIconSize.lg, w: FontWeight.w800, c: c.textDark).copyWith(letterSpacing: AppSpace.xs),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'pa_code_hint'.tr,
            filled: true,
            fillColor: c.kit.well,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.tile)),
          ),
        ),
        const SizedBox(height: AppSpace.xxs),
        Text('pa_code_rules'.tr, style: AppType.meta(context)),
        const SizedBox(height: AppSpace.md),
        for (final f in p.fields) _fieldWidget(f),
        if (advanced && p.documents.isNotEmpty) ...[
          Text('pl_documents'.tr, style: AppType.tileTitle(context)),
          const SizedBox(height: AppSpace.xs),
          for (final d in p.documents) _docWidget(d),
        ],
        const SizedBox(height: AppSpace.xs),
        AppButton.primary(
          key: const ValueKey('pa.link.submit'),
          label: advanced ? 'pl_submit_request'.tr : 'pa_link_now'.tr,
          icon: Icons.link_rounded,
          busy: p.isLoading,
          expand: true,
          onPressed: p.isLoading ? null : () => _submit(p),
        ),
      ]),
    );
    final where = AppCard(
      title: 'pa_link_where'.tr,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppTile.narrow),
          child: AppHeroSurface(
            borderRadius: BorderRadius.circular(AppRadius.cardWide),
            shapes: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(children: [
                Text('pa_link_where_path'.tr, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
                const SizedBox(height: AppSpace.xs),
                Text('pa_link_where_title'.tr, style: AppType.section(context).copyWith(color: c.onHero)),
                const SizedBox(height: AppSpace.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                  decoration: BoxDecoration(color: c.heroGlass, borderRadius: BorderRadius.circular(AppRadius.tile)),
                  child: Text('• • • • • • •', textDirection: TextDirection.ltr, style: AppType.section(context).copyWith(color: c.onHero)),
                ),
                const SizedBox(height: AppSpace.xs),
                Text('pa_link_where_hint'.tr, textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
              ]),
            ),
          ),
        ),
      ),
    );
    final requests = AppCard(
      title: 'pl_my_requests'.tr,
      child: p.requests.isEmpty
          ? Text('pl_no_requests'.tr, style: AppType.body(context).copyWith(color: c.textMedium))
          : PaStack(gap: AppSpace.sm, children: [
              for (final r in p.requests)
                Container(
                  padding: const EdgeInsets.all(AppSpace.sm),
                  decoration: BoxDecoration(
                    color: c.kit.well,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                    border: Border.all(color: c.kit.line, width: AppBorder.strong),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${r['student_name'] ?? ''}', style: AppType.tileTitle(context))),
                      PlStatusChip('${r['status']}'),
                    ]),
                    Text('${'pl_mode_${r['mode']}'.tr} · ${plDateTime(r['created_at'])}', style: AppType.meta(context)),
                    if ('${r['decision_note'] ?? ''}'.isNotEmpty)
                      Text('${'pl_admin_note'.tr}: ${r['decision_note']}', style: AppType.meta(context).copyWith(color: c.kit.error.ink)),
                    if (r['status'] == 'pending')
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: AppButton.ghost(
                          label: 'pl_cancel_request'.tr,
                          size: AppButtonSize.sm,
                          onPressed: () async {
                            final ok = await Helpers.confirmDialog(context);
                            if (ok == true && context.mounted) {
                              final done = await p.cancel(r['id'] as int);
                              if (!done) plToast(p.errorMessage);
                            }
                          },
                        ),
                      ),
                  ]),
                ),
            ]),
    );
    return PaHeroPage(
      onRefresh: p.loadAll,
      width: AppWidth.reading,
      hero: hero,
      body: PaColumns(start: [form], end: [requests, where], startFlex: 6, endFlex: 5),
    );
  }
}
