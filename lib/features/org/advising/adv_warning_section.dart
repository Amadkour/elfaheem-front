// lib/features/org/advising/adv_warning_section.dart — the student 360's "Early warning" section
// (docs/advising/PHASE6.md "Student 360 and graduation"): the rules the student matches now with their
// explanations, the graduation projection, the recent alerts, and "Evaluate now" (`POST …/warning/run`, synchronous).
// Also the sheet a rule flag's card opens: the alerts that opened or joined it (`GET …/flags/{id}/alerts`).
//
//   AdvWarningSection        loads `GET …/students/{member_id}/warning` and draws AdvWarningView
//   showAdvFlagAlertsSheet   a flag's alerts
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgCall;
import 'adv_models.dart' show AdvFlag;
import 'adv_parts.dart';
import 'adv_warning_api.dart';
import 'adv_warning_models.dart';
import 'adv_warning_parts.dart';

class AdvWarningSection extends StatefulWidget {
  const AdvWarningSection({super.key, required this.orgId, required this.memberId, this.onOpenFlag, this.onEvaluated});
  final int orgId, memberId;

  /// An alert's follow-up flag (the 360 opens its Flags section).
  final ValueChanged<int>? onOpenFlag;

  /// After "Evaluate now": flags may have opened, so the 360 reads its numbers and flags again.
  final VoidCallback? onEvaluated;

  @override
  State<AdvWarningSection> createState() => AdvWarningSectionState();
}

class AdvWarningSectionState extends State<AdvWarningSection> {
  late final AdvWarningApi _api = AdvWarningApi(widget.orgId);
  AdvWarning? _warning;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  bool _evaluating = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Reads the block again (the 360's Refresh).
  Future<void> reload() async {
    final r = await orgCall(() => _api.student(widget.memberId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _warning = r.data as AdvWarning;
        _load = AdvLoad.ready;
      } else if (_warning == null) {
        _load = advFailLoad(r);
        _error = advWarningErrorText(r.error!);
      }
    });
  }

  Future<void> _evaluate() async {
    setState(() => _evaluating = true);
    final r = await orgCall(() => _api.evaluateStudent(widget.memberId), quiet: true);
    if (!mounted) return;
    setState(() {
      _evaluating = false;
      if (r.ok) {
        _warning = r.data as AdvWarning;
        _load = AdvLoad.ready;
      }
    });
    if (!r.ok) {
      showAppNotice(advWarningErrorText(r.error!), error: true);
      return;
    }
    final n = _warning!.hits.length;
    showAppNotice(n == 0
        ? t('فُحص الطالب: لا يطابق أي قاعدة الآن', 'Student checked: no rule matches right now')
        : countText(n,
            ar1: 'فُحص الطالب: يطابق قاعدة واحدة', ar2: 'فُحص الطالب: يطابق قاعدتين', arFew: 'فُحص الطالب: يطابق $n قواعد', arMany: 'فُحص الطالب: يطابق $n قاعدة',
            en1: 'Student checked: 1 rule matches', en: 'Student checked: $n rules match'));
    widget.onEvaluated?.call();
  }

  @override
  Widget build(BuildContext context) => AdvWarningView(
        load: _load,
        warning: _warning,
        errorText: _error,
        evaluating: _evaluating,
        onRetry: () {
          setState(() => _load = AdvLoad.loading);
          reload();
        },
        onEvaluate: (_warning?.canRun ?? false) ? _evaluate : null,
        onOpenFlag: widget.onOpenFlag,
      );
}

/// The alerts that opened or joined [flag] (a rule flag's "Alerts" link).
Future<void> showAdvFlagAlertsSheet(BuildContext context, {required int orgId, required AdvFlag flag}) {
  final api = AdvWarningApi(orgId);
  List<AdvAlert>? rows;
  String? error;
  var started = false;
  return showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        if (!started) {
          started = true;
          orgCall(() => api.flagAlerts(flag.id), quiet: true).then((r) {
            if (!ctx.mounted) return;
            set(() {
              rows = r.ok ? r.data as List<AdvAlert> : const [];
              error = r.ok ? null : advWarningErrorText(r.error!);
            });
          });
        }
        final list = rows;
        return AppSheetContent(
          title: t('تنبيهات الإنذار المبكر', 'Early-warning alerts'),
          children: [
            Text(t('ما أرسلته القواعد في هذا التنبيه، الأحدث أولاً.', 'What the rules sent into this flag, newest first.'), style: AppType.meta(ctx)),
            const SizedBox(height: AppSpace.sm),
            if (error != null)
              AppBanner(icon: Icons.error_outline_rounded, color: ctx.colors.danger, text: error!)
            else if (list == null)
              const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)
            else if (list.isEmpty)
              Text(t('فُتح هذا التنبيه يدوياً، فلا تنبيهات قواعد فيه.', 'This flag was opened by hand, so no rule alerts are in it.'), style: AppType.body(ctx))
            else
              for (final a in list) AdvAlertCard(alert: a, showStudent: false),
          ],
        );
      }));
}
