// lib/features/home/home_application_card.dart — "Your application" on the personal homes (D-1210).
//
// My open admission cases (`/me/home`'s `onboarding[]`, no request of its own, max 3): one line per case — the
// organization and the type, a status chip, "n documents missing", the due date — and a tap opens the applicant page
// of that case. Nothing is drawn for an empty list, so an older server (no field) or a person with no case sees no
// card. Plain values in, callbacks out; the page itself is a deferred screen opened by the caller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/home/me_home.dart' show MeOnboardingItem;
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredOnbApplicantPage;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/utils/widget/parent_component.dart';

/// The kill switch of member onboarding (`org.onboarding`).
const kHomeApplicationKey = 'org.onboarding';

/// True when a case on the list asks something of the person: the card then sits near the top of the home.
bool homeApplicationNeedsAction(List<MeOnboardingItem> items) => items.any((x) => x.needsAction);

String _statusLabel(MeOnboardingItem x) => switch (x.status) {
      'draft' => t('مسودة', 'Draft'),
      'submitted' => t('بانتظار المراجعة', 'Waiting for review'),
      'under_review' => t('قيد المراجعة', 'Under review'),
      'needs_correction' => t('يحتاج تعديلاً', 'Needs correction'),
      'approved' => x.conditional ? t('مقبول بشرط', 'Accepted on condition') : t('مقبول', 'Approved'),
      'active' => t('مُفعَّل', 'Active'),
      'rejected' => t('مرفوض', 'Rejected'),
      _ => x.status,
    };

AppTone _statusTone(MeOnboardingItem x) => switch (x.status) {
      'needs_correction' => AppTone.warning,
      'approved' || 'active' => AppTone.success,
      'rejected' => AppTone.danger,
      'submitted' || 'under_review' => AppTone.info,
      _ => AppTone.brand,
    };

class HomeApplicationCard extends StatelessWidget {
  const HomeApplicationCard({super.key, required this.items, this.onOpen, this.padding = EdgeInsets.zero});
  final List<MeOnboardingItem> items;
  final ValueChanged<MeOnboardingItem>? onOpen;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return ParentComponent(
      featureKey: kHomeApplicationKey,
      child: Padding(
        padding: padding,
        child: AppCard(
          key: const ValueKey('home.application'),
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.how_to_reg_rounded, size: AppIconSize.md, color: c.primary),
              AppSpace.gapSm,
              Expanded(child: Text(t('طلبي', 'Your application'), style: AppType.section(context))),
            ]),
            for (final x in items)
              InkWell(
                key: ValueKey('home.application.${x.caseId}'),
                borderRadius: BorderRadius.circular(AppRadius.chip),
                onTap: onOpen == null ? null : () => onOpen!(x),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpace.sm),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      [if (x.orgName.isNotEmpty) x.orgName, if (x.typeLabel.isNotEmpty) x.typeLabel].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodyStrong(context),
                    ),
                    const SizedBox(height: AppSpace.xxs),
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      AppStatusBadge(label: _statusLabel(x), tone: _statusTone(x), dense: true),
                      if (x.missingCount > 0)
                        Text(
                          countText(x.missingCount, ar1: 'مستند ناقص', ar2: 'مستندان ناقصان', arFew: '{n} مستندات ناقصة', arMany: '{n} مستنداً ناقصاً', en1: '1 document missing', en: '{n} documents missing'),
                          style: AppType.meta(context),
                        ),
                      if (x.dueAt != null) Text(t('الموعد ${AppTime.date(x.dueAt!)}', 'Due ${AppTime.date(x.dueAt!)}'), style: AppType.meta(context)),
                    ]),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Opens the applicant page of [x] (a deferred screen); the home reloads when it closes (a submit changes the list).
Future<void> openHomeApplication(BuildContext context, MeOnboardingItem x, {VoidCallback? onClosed}) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredOnbApplicantPage(caseId: x.caseId, orgId: x.orgId)));
  if (onClosed != null) onClosed();
}
