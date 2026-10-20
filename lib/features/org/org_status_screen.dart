// lib/features/org/org_status_screen.dart
//
// What an organization admin sees while the organization is NOT approved yet (pending · rejected · suspended):
// a calm, human status page instead of errors — a 3-step timeline, the reviewer's note, and the one action
// that moves things forward (edit the application · resubmit · check again).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_dashboard_screen.dart' show showOrgForm, showOrgSwitcher;
import 'org_providers.dart';
import 'org_ui.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';

class OrgStatusScreen extends StatefulWidget {
  const OrgStatusScreen({super.key});

  @override
  State<OrgStatusScreen> createState() => _OrgStatusScreenState();
}

class _OrgStatusScreenState extends State<OrgStatusScreen> {
  bool _busy = false;

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await context.read<OrgSession>().load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final org = s.current!;
    final c = context.colors;
    final status = s.status;
    final note = '${org['review_note'] ?? ''}'.trim();
    final (IconData icon, Color tone, String title, String body) = switch (status) {
      'rejected' => (
          Icons.edit_note_rounded,
          c.warning,
          t('طلبك يحتاج بعض التعديلات', 'Your application needs a few changes'),
          t('راجع ملاحظة فريق المنصة بالأسفل، عدّل البيانات ثم أعد الإرسال — عادةً ما تكون المراجعة الثانية أسرع.',
              'Read the review note below, update the details and resubmit — the second review is usually quicker.'),
        ),
      'suspended' => (
          Icons.pause_circle_rounded,
          c.danger,
          t('المؤسسة موقوفة مؤقتاً', 'This organization is paused'),
          t('بيانات مؤسستك محفوظة بالكامل ولم يُحذف شيء. تواصل مع إدارة المنصة لإعادة التفعيل.',
              'All your data is safe — nothing was deleted. Contact the platform team to reactivate it.'),
        ),
      _ => (
          Icons.hourglass_top_rounded,
          c.primary,
          t('شكراً لك! طلبك قيد المراجعة', 'Thank you! Your application is under review'),
          t('يتحقق فريق المنصة من بيانات المؤسسة لحماية الطلاب والمعلمين. سنرسل لك إشعاراً فور الاعتماد — يمكنك تحسين البيانات في هذه الأثناء.',
              "We're verifying your organization to keep students and teachers safe. You'll get a notification as soon as it's approved — you can polish the details meanwhile."),
        ),
    };

    Widget step(int i, String label, {required bool done, required bool active, bool bad = false}) {
      final col = bad ? c.warning : done ? c.success : active ? c.primary : c.divider;
      return Expanded(
        child: Column(children: [
          Row(children: [
            Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : col.withValues(alpha: 0.5))),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(shape: BoxShape.circle, color: col.withValues(alpha: done || active || bad ? 1 : 0.3)),
              child: Icon(bad ? Icons.priority_high_rounded : done ? Icons.check_rounded : Icons.circle,
                  color: Colors.white, size: done || bad ? 18 : 8),
            ),
            Expanded(child: Container(height: 2, color: i == 2 ? Colors.transparent : col.withValues(alpha: 0.5))),
          ]),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: orgText(context, size: 11.5, color: c.textMedium)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        OrgHero(
          org: org,
          subtitle: statusLabel(status),
          trailing: s.items.length > 1
              ? IconButton(
                  tooltip: t('تبديل المؤسسة', 'Switch organization'),
                  onPressed: () => showOrgSwitcher(context),
                  icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: tone.withValues(alpha: 0.25)),
              boxShadow: c.cardShadow,
            ),
            child: Column(children: [
              IconBadge(icon, tone, size: 64),
              const SizedBox(height: 14),
              Text(title, textAlign: TextAlign.center, style: orgText(context, size: 18, w: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center, style: orgText(context, size: 13, color: c.textMedium)),
              const SizedBox(height: 22),
              Row(children: [
                step(0, t('أُرسل الطلب', 'Sent'), done: true, active: false),
                step(1, t('المراجعة', 'Review'),
                    done: status == 'suspended', active: status == 'pending', bad: status == 'rejected'),
                step(2, status == 'suspended' ? t('موقوفة', 'Paused') : t('جاهزة للعمل', 'Live'),
                    done: false, active: false, bad: status == 'suspended'),
              ]),
            ]),
          ),
        ),
        if (note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: tone.withValues(alpha: 0.3)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.format_quote_rounded, color: tone),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('ملاحظة فريق المنصة', 'Note from the platform team'),
                        style: orgText(context, size: 12, w: FontWeight.w800, color: tone)),
                    const SizedBox(height: 4),
                    Text(note, style: orgText(context)),
                  ]),
                ),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Column(children: [
            if (status != 'suspended')
              PrimaryButton(
                isLoading: false,
                label: t('تعديل بيانات الطلب', 'Edit the application'),
                icon: Icons.edit_rounded,
                iconBefore: true,
                onPressed: () => showOrgForm(context, edit: org),
              ),
            if (status == 'rejected') ...[
              const SizedBox(height: 10),
              PrimaryButton(
                isLoading: _busy,
                background: c.success,
                label: t('إعادة الإرسال للمراجعة', 'Resubmit for review'),
                icon: Icons.send_rounded,
                iconBefore: true,
                onPressed: () async {
                  setState(() => _busy = true);
                  await s.resubmit();
                  if (mounted) setState(() => _busy = false);
                },
              ),
            ],
            const SizedBox(height: 6),
            // A waiting / rejected / suspended org admin can always leave (before: no way out of this screen).
            TextButton.icon(
              onPressed: () async {
                if (await confirm(context, message: 'logout_confirm'.tr) && context.mounted) {
                  await context.read<ProfileProvider>().logout(context);
                }
              },
              icon: Icon(Icons.logout_rounded, color: c.danger),
              label: Text('logout'.tr, style: TextStyle(fontFamily: 'tajawal', color: c.danger)),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t('تحقق من الحالة الآن', 'Check the status now'), style: const TextStyle(fontFamily: 'tajawal')),
            ),
          ]),
        ),
      ]),
    );
  }
}
