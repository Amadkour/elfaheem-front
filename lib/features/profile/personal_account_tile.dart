// lib/features/profile/personal_account_tile.dart
//
// "Personal account" (UX v3 phase 3): the one switch of an organization member's optional personal profile, in the
// organization Settings and in the personal Account page. Nothing for a person without an organization.
//
//   on   PUT /api/v1/me/personal {enabled: true}, then "Open personal space" (the context switcher)
//   off  appConfirm (the data is kept, only hidden), PUT, then back to the organization
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/personal_access.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppSwitchTile, appConfirm, showAppError, showAppNotice;
import 'package:flutter_education_app/design/context_switcher.dart' show showContextSwitcherSheet;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';

/// The plain line under the switch.
String personalAccountHint() => t('فعّله لتحصل على ملف عام وتدرّس دورات خارج مؤسستك. تبقى بيانات مؤسستك منفصلة.',
    'Turn on to get a public profile and teach courses outside your institution. Your institution data stays separate.');

class PersonalAccountTile extends StatefulWidget {
  const PersonalAccountTile({super.key, this.inOrg = false});

  /// Drawn inside the organization (its Settings): turning off stays where it is. False (the personal Account page):
  /// turning off goes back to the organization's home.
  final bool inOrg;

  @override
  State<PersonalAccountTile> createState() => _PersonalAccountTileState();
}

class _PersonalAccountTileState extends State<PersonalAccountTile> {
  bool _busy = false;

  Future<void> _change(bool on) async {
    if (!on) {
      final ok = await appConfirm(context,
          message: t('سيُخفى ملفك العام ودوراتك الشخصية، ولن يُحذف شيء. يمكنك تفعيله مرة أخرى في أي وقت.',
              'Your public profile and personal courses will be hidden. Nothing is deleted, and you can turn it on again at any time.'),
          confirmLabel: t('إيقاف', 'Turn off'));
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await PersonalAccess.instance.set(on);
      if (!mounted) return;
      if (on) {
        showAppNotice(t('فُعّل حسابك الشخصي', 'Your personal account is on'),
            actionLabel: t('افتح المساحة الشخصية', 'Open personal space'),
            onAction: () {
              if (mounted) showContextSwitcherSheet(context);
            });
      } else {
        showAppNotice(t('أُوقف حسابك الشخصي', 'Your personal account is off'));
        if (!widget.inOrg) {
          final home = context.read<MyAuthProvider>().homeRoute;
          Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(home, (_) => false);
        }
      }
    } catch (e) {
      if (mounted) showAppError(context, e, onRetry: () => _change(on));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([PersonalAccess.instance, AppModeController.instance]),
        builder: (context, _) {
          final pa = PersonalAccess.instance;
          // without an organization the personal account is everything: no switch
          if (!widget.inOrg && !pa.hasOrg && pa.flag) return const SizedBox.shrink();
          return AppSwitchTile(
            key: const ValueKey('personal.switch'),
            icon: Icons.person_rounded,
            title: t('الحساب الشخصي', 'Personal account'),
            subtitle: personalAccountHint(),
            value: pa.flag,
            onChanged: _busy ? null : _change,
          );
        },
      );
}
