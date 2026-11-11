// lib/features/org/orgs_unavailable_gate.dart
//
// Wraps every organization dashboard route. While the super admin has switched Organizations OFF
// (AppConfig.orgsEnabled, from the theme response) org admins / org staff see a calm "currently unavailable" page
// with refresh + sign-out instead of a dashboard whose every call would answer 403 orgs_disabled.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show t;
import 'org_platform_context.dart';
import 'package:flutter_education_app/design/app_icons.dart';

class OrgsGate extends StatelessWidget {
  const OrgsGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AppConfig.orgsEnabledNotifier,
        builder: (context, on, _) {
          if (on) return child;
          OrgPlatformContext.close();
          return const OrgsUnavailablePage();
        },
      );
}

class OrgsUnavailablePage extends StatefulWidget {
  const OrgsUnavailablePage({super.key});

  @override
  State<OrgsUnavailablePage> createState() => _OrgsUnavailablePageState();
}

class _OrgsUnavailablePageState extends State<OrgsUnavailablePage> {
  bool _busy = false;

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await context.read<ThemeConfigProvider>().refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!AppConfig.orgsEnabled) {
      appToast(t('ما زالت الخدمة متوقفة — سنفتحها لك تلقائياً فور عودتها',
          'Still paused — it opens automatically as soon as it is back'));
    }
  }

  Future<void> _logout() async {
    final auth = context.read<MyAuthProvider>();
    final nav = Navigator.of(context);
    await auth.logout();
    nav.pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.primaryTint,
                    ),
                    child: Icon(Icons.domain_disabled_rounded, size: AppIconSize.hero, color: c.primary),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(t('المؤسسات غير متاحة حالياً', 'Organizations are currently unavailable'),
                      textAlign: TextAlign.center, style: appText(19, w: FontWeight.w800, c: c.textDark)),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    t('أوقفت إدارة المنصة خدمة المؤسسات مؤقتاً. بياناتك محفوظة بالكامل، وستعود لوحة مؤسستك كما هي فور إعادة تفعيل الخدمة.',
                        'The platform team has paused organizations for now. All your data is safe, and your dashboard comes back exactly as it was once the service is switched on again.'),
                    textAlign: TextAlign.center,
                    style: appText(13.5, c: c.textMedium, h: 1.6),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  AppPrimaryButton(
                      label: t('تحقّق مرة أخرى', 'Check again'),
                      icon: Icons.refresh_rounded,
                      busy: _busy,
                      onPressed: _busy ? null : _refresh),
                  const SizedBox(height: AppSpace.xs),
                  TextButton.icon(
                    onPressed: _logout,
                    icon: Icon(DirIcons.logout, color: c.textMedium, size: AppIconSize.md),
                    label: Text(t('تسجيل الخروج', 'Sign out'), style: appText(13.5, w: FontWeight.w700, c: c.textMedium)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
