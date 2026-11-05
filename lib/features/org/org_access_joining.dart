// lib/features/org/org_access_joining.dart — joining an organization and its departments, in one place
// (API: org_join_router.py — /orgs/{o}/join/…, /join-requests/…, /public/join/code, /public/me/join-status).
//
// Staff (org admin)
//   OrgAccessJoiningPage   Requests (organization + departments, select many → accept / reject) ·
//                          Codes (generate with role / department / expiry / max uses, QR + share, rotate, revoke) ·
//                          Settings (how people join THIS organization + the default for departments)
// Members
//   OrgJoinPage            one "Join" experience: enter any code · browse & request · track my requests
//   openOrgJoin            push it (respects AppConfig.orgsEnabled)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiClient;
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/utils/web_entry_route.dart' show SignInReturn;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show AdminAvatar;
import 'org_access_page.dart' show OrgAccessPage;
import 'org_join_pages.dart' show JoinRequestCard, OrgUnitJoinScreen, unitKindLabel;
import 'org_join_scan.dart' show joinLinkFor, joinScannerAvailable, openJoinScanner, parseJoinQr;
import 'org_page_header.dart' show OrgPushedPage;
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_v3.dart';
import 'org_page_kit.dart' show OrgFilterButton, OrgPartPicker;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

part 'org_access_joining_requests.dart';
part 'org_access_joining_codes.dart';
part 'org_access_joining_settings.dart';
part 'org_access_joining_join.dart';

const _pub = '$orgBase/public';

Map<String, String> _roleLabels() => {
      'student': t('طالب', 'Student'),
      'teacher': t('عضو هيئة تدريس', 'Teacher'),
      'teacher_assistant': t('معيد / مساعد تدريس', 'Teaching assistant'),
    };

/// Friendly texts for the codes this workstream adds (the shared table covers the rest).
String joinErrorText(OrgCall r) => switch (r.code) {
      'role_mismatch' => r.detail['role'] == 'student'
          ? t('هذا الكود مخصص للطلاب — اطلب كود هيئة التدريس من إدارة المؤسسة', 'This code is for students — ask your institution for a staff code')
          : t('هذا الكود مخصص لهيئة التدريس — اطلب كود الطلاب من إدارة المؤسسة', 'This code is for teaching staff — ask your institution for a student code'),
      'closed' => t('هذه المؤسسة لا تستقبل أعضاء جدداً الآن', 'This organization isn\'t taking new members right now'),
      'bad_code' => t('لم نتعرف على هذا الكود — تأكد من الحروف واطلبه من مؤسستك', 'We don\'t recognise this code — check it and ask your institution'),
      _ => orgErrorText(r.error!),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Staff
// ═════════════════════════════════════════════════════════════════════════════

class OrgAccessJoiningPage extends StatefulWidget {
  const OrgAccessJoiningPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<OrgAccessJoiningPage> createState() => _OrgAccessJoiningPageState();
}

class _OrgAccessJoiningPageState extends State<OrgAccessJoiningPage> {
  Map<String, dynamic>? _settings;
  String? _error; // why the join settings could not be loaded (the settings tab shows it with a retry)
  late int _part = widget.initialTab;
  final Set<int> _seen = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    final r = await orgCall(() => s.api.get('${s.base}/join/settings'), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) _settings = r.map;
      _error = r.ok ? null : orgErrorText(r.error!);
    });
  }

  /// The page anatomy (D-103, org_page_kit.dart): the parts (Requests · Join codes · How people join) as ONE part
  /// picker — chips that fit, else one "part ▾" button — and each part kept alive once opened.
  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    final admin = s.can('organization', 'update');
    final counts = asMap(_settings?['counts']);
    final pending = asInt(counts['org_requests'] ?? 0) + asInt(counts['unit_requests'] ?? 0);
    final tabs = <(String, IconData, Widget)>[
      (pending > 0 ? t('الطلبات · $pending', 'Requests · $pending') : t('الطلبات', 'Requests'), Icons.inbox_rounded,
          _RequestsInbox(onChanged: _load)),
      if (admin) (t('أكواد الانضمام', 'Join codes'), Icons.qr_code_2_rounded, _OrgCodesTab(settings: _settings, onChanged: _load)),
      if (admin) (t('طريقة الانضمام', 'How people join'), Icons.tune_rounded, _JoinSettingsTab(settings: _settings, onSaved: _load, error: _error)),
    ];
    final i = _part.clamp(0, tabs.length - 1);
    _seen.add(i);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (tabs.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 0),
          child: OrgPartPicker(
            parts: [for (final x in tabs) (x.$1, x.$2)],
            index: i,
            onChanged: (k) => setState(() => _part = k),
          ),
        ),
      Expanded(
        child: IndexedStack(index: i, children: [
          for (var k = 0; k < tabs.length; k++) _seen.contains(k) ? tabs[k].$3 : const SizedBox.shrink(),
        ]),
      ),
    ]);
  }
}

