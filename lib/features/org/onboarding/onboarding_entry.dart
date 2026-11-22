// lib/features/org/onboarding/onboarding_entry.dart — the one front door for adding people (D-1208, D-1210).
//
// The People pages' "Add member" action and "Import from Excel" menu item open the onboarding flow (one-person wizard /
// the import page) while the kill switch `org.onboarding` is on. Both functions answer null when the flow is not
// available (switch off, the types could not be loaded, none of the module's types the person may use): the caller
// then runs the legacy form / import exactly as before. A bool answer = the flow ran; true = something was saved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t, asMapList;
import '../org_providers.dart' show OrgSession;
import 'onboarding_api.dart';
import 'onboarding_import.dart';
import 'onboarding_models.dart';
import 'onboarding_wizard.dart';

/// Whether the people pages route through onboarding (the platform / organization kill switch is not on the list).
bool onboardingEntryOn() => !AppConfig.disableList.contains(onboardingFeatureKey);

Future<List<OnbType>?> _types(OnboardingApi api, int orgId, String module, bool Function(String) allowed) async {
  final r = await api.types(orgId);
  if (!r.ok) return null;
  final raw = r.data is List ? r.data as List : r.map['items'];
  final l = [for (final m in asMapList(raw)) OnbType.fromJson(m)].where((x) => x.active && x.module == module && allowed(x.module)).toList();
  return l.isEmpty ? null : l;
}

Widget _scope(OrgSession s, Widget child) => ChangeNotifierProvider<OrgSession>.value(value: s, child: child);

/// "Add member": one person through the wizard. The type is asked first when the module has several.
Future<bool?> openOnboardingAdd(BuildContext context, {required String module, OnboardingApi? api}) async {
  if (!onboardingEntryOn()) return null;
  final s = context.read<OrgSession>();
  final orgId = s.currentId;
  if (orgId == null) return null;
  final a = api ?? OnboardingApi();
  final types = await _types(a, orgId, module, (m) => s.can(m, 'insert'));
  if (types == null || !context.mounted) return null;
  final type = types.length == 1
      ? types.first
      : await showAppSheet<OnbType>(
          context,
          (ctx) => AppSheetContent(title: t('اختر النوع', 'Choose the type'), children: [
            for (final ty in types)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: AppCard(
                  key: ValueKey('onb.entry.type.${ty.key}'),
                  onTap: () => Navigator.of(ctx).pop(ty),
                  child: Text(ty.label, style: AppType.bodyStrong(ctx)),
                ),
              ),
          ]),
        );
  if (type == null || !context.mounted) return false;
  final places = await OnbPlaces.load(orgId);
  if (!context.mounted) return false;
  // "Approve and activate now" only for people who hold the type module's approve right (the server checks it too)
  final saved = await Navigator.of(context).push<OnbCase?>(MaterialPageRoute(
    builder: (_) => _scope(s, OnbWizardPage(orgId: orgId, type: type, api: a, places: places, canApproveNow: s.can(type.module, 'approve'))),
  ));
  return saved != null;
}

/// "Import from Excel": the onboarding import page for the module's types the person may import into.
Future<bool?> openOnboardingImport(BuildContext context, {required String module, OnboardingApi? api}) async {
  if (!onboardingEntryOn() || AppConfig.disableList.contains(onboardingImportKey)) return null;
  final s = context.read<OrgSession>();
  final orgId = s.currentId;
  if (orgId == null) return null;
  final a = api ?? OnboardingApi();
  final types = await _types(a, orgId, module, (m) => s.can(m, 'import') || s.can(m, 'insert'));
  if (types == null || !context.mounted) return null;
  final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => _scope(s, OnbImportPage(orgId: orgId, types: types, canInvite: !AppConfig.disableList.contains(onboardingInviteKey) && s.can(module, 'update'), api: a)),
  ));
  return done ?? true;
}
