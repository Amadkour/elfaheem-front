// lib/features/org/governance/gov_settings_page.dart — the organization's governance settings (org admin):
// routing rules (open · rules between entity kinds), the SLA hours per priority and the e-mail channel of every
// notice (`GET/PUT …/governance/settings`, spec §2 / §4). `GovSettingsForm` takes plain values so the layout
// harness can pump it; `GovSettingsPage` loads and saves.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_v3.dart' show orgCall;
import 'gov_api.dart';
import 'gov_models.dart' show entityKindLabel, entityKinds, priorities, priorityLabelOf, slaHours;

/// One routing rule: items may go from entities of [fromKind] to entities of [toKind] (`*` = any).
class RoutingRule {
  RoutingRule({this.fromKind = '*', this.toKind = '*', this.allow = true});
  String fromKind, toKind;
  bool allow;

  factory RoutingRule.fromJson(Map<String, dynamic> j) =>
      RoutingRule(fromKind: '${j['from_kind'] ?? '*'}', toKind: '${j['to_kind'] ?? '*'}', allow: j['allow'] != false);

  Map<String, dynamic> toJson() => {'from_kind': fromKind, 'to_kind': toKind, 'allow': allow};
}

/// The editable settings document (`GET …/settings`).
class GovSettings {
  GovSettings({this.mode = 'open', List<RoutingRule>? rules, Map<String, int>? sla, this.email = 'fallback'})
      : rules = rules ?? [],
        sla = sla ?? Map.of(slaHours);
  String mode; // open | rules
  final List<RoutingRule> rules;
  final Map<String, int> sla;
  String email; // fallback | always

  factory GovSettings.fromJson(Map<String, dynamic> j) {
    final routing = asMap(j['routing']);
    final hours = asMap(j['sla_hours']);
    return GovSettings(
      mode: routing['mode'] == 'rules' ? 'rules' : 'open',
      rules: [for (final r in asMapList(routing['rules'])) RoutingRule.fromJson(r)],
      sla: {for (final p in priorities) p: asInt(hours[p], slaHours[p]!)},
      email: j['email'] == 'always' ? 'always' : 'fallback',
    );
  }

  Map<String, dynamic> toJson() => {
        'routing': {'mode': mode, 'rules': [for (final r in rules) r.toJson()]},
        'sla_hours': sla,
        'email': email,
      };
}

/// Presentational form: every control takes and returns plain values through [onChanged]; [onSave] saves.
class GovSettingsForm extends StatefulWidget {
  const GovSettingsForm({super.key, required this.settings, required this.onChanged, required this.onSave, this.busy = false});
  final GovSettings settings;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final bool busy;

  @override
  State<GovSettingsForm> createState() => _GovSettingsFormState();
}

class _GovSettingsFormState extends State<GovSettingsForm> {
  late final Map<String, TextEditingController> _sla = {
    for (final p in priorities) p: TextEditingController(text: '${widget.settings.sla[p] ?? slaHours[p]}'),
  };

  @override
  void dispose() {
    for (final c in _sla.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.settings;
    final onChanged = widget.onChanged;
    final kinds = ['*', ...entityKinds];
    String kindLabel(String k) => k == '*' ? t('أي جهة', 'Any entity') : entityKindLabel(k);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      AppSectionTitle(t('مسارات الإحالة', 'Routing rules')),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSwitchTile(
            title: t('إحالة مفتوحة بين كل الجهات', 'Open routing between every entity'),
            subtitle: t('عند الإيقاف تُسمح فقط المسارات المذكورة أدناه', 'When off, only the routes listed below are allowed'),
            value: s.mode == 'open',
            onChanged: (v) {
              s.mode = v ? 'open' : 'rules';
              onChanged();
            },
          ),
          if (s.mode == 'rules') ...[
            const SizedBox(height: 8),
            for (var i = 0; i < s.rules.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                    width: 180,
                    child: AppDropdown<String>(
                      decoration: InputDecoration(labelText: t('من', 'From')),
                      value: s.rules[i].fromKind,
                      items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text(kindLabel(k)))],
                      onChanged: (v) {
                        s.rules[i].fromKind = v ?? '*';
                        onChanged();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: AppDropdown<String>(
                      decoration: InputDecoration(labelText: t('إلى', 'To')),
                      value: s.rules[i].toKind,
                      items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text(kindLabel(k)))],
                      onChanged: (v) {
                        s.rules[i].toKind = v ?? '*';
                        onChanged();
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: t('حذف', 'Remove'),
                    onPressed: () {
                      s.rules.removeAt(i);
                      onChanged();
                    },
                    icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                  ),
                ]),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppPill(
                icon: Icons.add_rounded,
                label: t('إضافة مسار', 'Add a route'),
                onTap: () {
                  s.rules.add(RoutingRule());
                  onChanged();
                },
              ),
            ),
            if (s.rules.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppBanner(icon: Icons.info_outline_rounded, text: t('بلا مسارات مسموحة لن تُقبل أي إحالة بين الجهات', 'With no allowed route, no item can be routed between entities')),
              ),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      AppSectionTitle(t('مهلة الرد (ساعات) لكل أولوية', 'SLA hours per priority')),
      AppCard(
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          for (final p in priorities)
            SizedBox(
              width: 150,
              child: AppField(
                controller: _sla[p]!,
                label: priorityLabelOf(p),
                keyboard: TextInputType.number,
                onChanged: (v) {
                  final n = int.tryParse(v.trim());
                  if (n != null && n > 0) s.sla[p] = n;
                },
              ),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      AppSectionTitle(t('البريد الإلكتروني', 'E-mail')),
      AppCard(
        child: AppSwitchTile(
          title: t('أرسل كل إشعار بالبريد أيضاً', 'Also e-mail every notice'),
          subtitle: t('افتراضياً يُرسل البريد فقط عندما لا يصل الإشعار إلى أي جهاز', 'By default e-mail is sent only when no device received the push'),
          value: s.email == 'always',
          onChanged: (v) {
            s.email = v ? 'always' : 'fallback';
            onChanged();
          },
        ),
      ),
      const SizedBox(height: 20),
      AppPrimaryButton(label: t('حفظ الإعدادات', 'Save settings'), busy: widget.busy, onPressed: widget.busy ? null : widget.onSave),
    ]);
  }
}

class GovSettingsPage extends StatefulWidget {
  const GovSettingsPage({super.key, required this.orgId, this.embedded = false});
  final int orgId;
  final bool embedded;

  @override
  State<GovSettingsPage> createState() => _GovSettingsPageState();
}

class _GovSettingsPageState extends State<GovSettingsPage> {
  GovSettings? _s;
  bool _busy = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => GovApi(widget.orgId).settings(), quiet: true);
    if (!mounted) return;
    setState(() {
      _failed = !r.ok;
      _s = r.ok ? GovSettings.fromJson(r.map) : null;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await orgCall(() => GovApi(widget.orgId).saveSettings(_s!.toJson()), ok: t('حُفظت الإعدادات', 'Settings saved'));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _s = GovSettings.fromJson(r.map);
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _s == null
        ? (_failed
            ? AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر تحميل الإعدادات', 'Could not load the settings'), onAction: _load, actionLabel: t('إعادة المحاولة', 'Retry'))
            : const AppListSkeleton(items: 3))
        : GovSettingsForm(settings: _s!, busy: _busy, onChanged: () => setState(() {}), onSave: _save);
    if (widget.embedded) return body;
    // org admin only: the dashboard's header, Back first (Save stays at the end of the form)
    return OrgPushedPage(title: t('إعدادات الطلبات والإحالات', 'Requests & routing settings'), maxWidth: 900, child: body);
  }
}
