// lib/features/profile/switch_account_tile.dart
//
// "Switch account" (D-1158): the personal Profile's way to every account the person holds — the personal one and
// each organization account. It opens the one shared context switcher (lib/design/context_switcher.dart); choosing
// an organization opens its dashboard there. Nothing for a person without an organization.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_settings.dart' show AppSettingsTile;
import 'package:flutter_education_app/design/context_switcher.dart' show showContextSwitcherSheet;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

class SwitchAccountTile extends StatelessWidget {
  const SwitchAccountTile({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppModeController.instance,
        builder: (context, _) {
          final ctl = AppModeController.instance;
          if (!ctl.available) return const SizedBox.shrink();
          final n = ctl.liveEntries.length;
          return AppSettingsTile(
            key: const ValueKey('profile.switch_account'),
            icon: Icons.swap_horiz_rounded,
            label: t('تبديل الحساب', 'Switch account'),
            subtitle: n == 1
                ? t('حسابك الشخصي وحساب مؤسستك', 'Your personal account and your organization account')
                : t('حسابك الشخصي وحسابات مؤسساتك ($n)', 'Your personal account and your $n organization accounts'),
            keywords: 'switch account organization تبديل حساب مؤسسة',
            onTap: () => showContextSwitcherSheet(context),
          );
        },
      );
}
