// The session's history: who decided what, old to new, when. Every decision the server logged, newest first, a page at a
// time, including ignoring and retaking. Also the corrected sheet's download, used by every screen of the run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../../../admin/admin_money_p8.dart' show p8SaveBytes;
import 'revision_api.dart';
import 'revision_models.dart';
import 'revision_wizard_steps.dart' show revisionAccent;

/// `sheet.xlsx`: the teacher's own file with the applied changes written in.
Future<bool> downloadCorrectedSheet(RevisionApi api, RevisionSession s) async {
  try {
    final bytes = await api.sheetFile(s.id);
    await p8SaveBytes(bytes, 'corrected-sheet-${s.id}.xlsx', mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    showAppNotice(t('نُزّل الملف المصحّح', 'The corrected sheet was downloaded'));
    return true;
  } catch (e) {
    showAppNotice(ApiException.from(e).message, error: true);
    return false;
  }
}

class RevisionHistoryScreen extends StatefulWidget {
  const RevisionHistoryScreen({super.key, required this.sessionId, this.api});
  final int sessionId;
  final RevisionApi? api;

  @override
  State<RevisionHistoryScreen> createState() => _RevisionHistoryScreenState();
}

class _RevisionHistoryScreenState extends State<RevisionHistoryScreen> {
  late final RevisionApi _api = widget.api ?? RevisionApi();
  final _items = <RevisionHistoryItem>[];
  int? _next;
  bool _loading = true, _more = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = _items.isEmpty;
        _failed = false;
      }
    });
    final p = await _api.history(widget.sessionId, before: more ? _next : null);
    if (!mounted) return;
    setState(() {
      _loading = _more = false;
      if (p == null) {
        if (!more) _failed = true;
        return;
      }
      if (!more) _items.clear();
      _items.addAll(p.items);
      _next = p.nextBefore;
    });
    if (p == null && more) showAppNotice(t('تعذّر تحميل المزيد', 'Could not load more'), error: true);
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      appBar: ScreenAppBar(title: t('سجل القرارات', 'Decision history'), actions: [AppRefreshAction(onRefresh: _load)]),
      child: Builder(builder: (context) {
        if (_loading) return const AppListSkeleton(items: 6);
        if (_failed) return AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر تحميل السجل', 'The history could not be loaded'), actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load);
        if (_items.isEmpty) {
          return AppEmpty(icon: Icons.history_rounded, title: t('لا قرارات بعد', 'No decisions yet'), message: t('كل تحديث أو تجاهل أو إعادة تصوير يظهر هنا مع صاحبه ووقته.', 'Every update, ignore or retake appears here with who did it and when.'));
        }
        return AppRefresh(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpace.md),
            itemCount: _items.length + (_next != null ? 1 : 0),
            separatorBuilder: (_, _) => AppSpace.gapXs,
            itemBuilder: (_, i) {
              if (i >= _items.length) {
                return Center(child: TextButton.icon(key: const ValueKey('rv.history.more'), onPressed: _more ? null : () => _load(more: true), icon: const Icon(Icons.expand_more_rounded), label: Text(t('تحميل المزيد', 'Load more'))));
              }
              return RevisionHistoryTile(key: ValueKey('rv.history.${_items[i].id}'), item: _items[i]);
            },
          ),
        );
      }),
    );
  }
}

class RevisionHistoryTile extends StatelessWidget {
  const RevisionHistoryTile({super.key, required this.item});
  final RevisionHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final change = revisionChangeText(item);
    final (icon, tone) = switch (item.action) {
      'apply' => (Icons.check_circle_outline_rounded, c.success),
      'keep' => (Icons.lock_outline_rounded, c.textMedium),
      'retake' => (Icons.replay_rounded, c.warning),
      'dismiss' => (Icons.close_rounded, c.textMedium),
      _ => (Icons.edit_outlined, revisionAccent(context)),
    };
    final who = [
      if ((item.byName ?? '').isNotEmpty) item.byName!,
      if (item.at != null) AppTime.dateTime(item.at!),
    ].join(' · ');
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: tone),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((item.studentName ?? '').isNotEmpty ? item.studentName! : t('ورقة بلا طالب', 'Paper with no student'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            Text(revisionActionLabel(item.action), style: AppType.row(context)),
            if (change.isNotEmpty) Text(change, textDirection: TextDirection.ltr, style: AppType.figure(context).copyWith(color: revisionAccent(context))),
            if (item.reason != null) Text(item.reason!, style: AppType.meta(context)),
            if (who.isNotEmpty) Text(who, style: AppType.meta(context)),
          ]),
        ),
      ]),
    );
  }
}
