// lib/features/games/admin/v4/review_page.dart — Games v4 T66: the review queue (CONTRACT §10). Religious and other
// "requires review" questions wait here as pending; a reviewer (an admin, or a user with `game_profiles.can_review`)
// approves or rejects each with an optional note. The admin also sees who the reviewers are and can add or remove
// them. The page is `GamesReviewPage`; `ReviewQueueBody` / `ReviewersCard` are plain-values bodies the layout test
// pumps without a server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_review_api.dart';

class GamesReviewPage extends StatefulWidget {
  const GamesReviewPage({super.key, this.api});
  final ItemsReviewApi? api;

  @override
  State<GamesReviewPage> createState() => _GamesReviewPageState();
}

class _GamesReviewPageState extends State<GamesReviewPage> {
  late final ItemsReviewApi _api = widget.api ?? ItemsReviewApi();
  List<ReviewItem>? _items;
  int _total = 0;
  String? _error;
  int? _busyId;
  List<Reviewer>? _reviewers; // null: not an admin (or not loaded): the card is hidden
  bool _reviewersBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final q = await _api.queue();
      if (!mounted) return;
      setState(() {
        _items = q.items;
        _total = q.total;
      });
    } catch (e) {
      if (mounted) setState(() => _error = reviewErrorText(e));
    }
    try {
      final r = await _api.reviewers();
      if (mounted) setState(() => _reviewers = r);
    } catch (_) {
      // a reviewer who is not an admin cannot list reviewers: the card stays hidden
    }
  }

  Future<void> _decide(ReviewItem item, bool approve) async {
    String? note;
    if (!approve) {
      final n = await showAppSheet<String>(context, (_) => const _RejectSheet());
      if (n == null) return;
      note = n;
    }
    setState(() => _busyId = item.id);
    try {
      await _api.decide(item.id, approve: approve, note: note);
      if (!mounted) return;
      setState(() {
        _items = [for (final i in _items ?? const <ReviewItem>[]) if (i.id != item.id) i];
        _total = _total > 0 ? _total - 1 : 0;
      });
      showAppNotice(approve ? t('تم اعتماد السؤال', 'Question approved') : t('تم رفض السؤال', 'Question rejected'));
    } catch (e) {
      final gone = ApiException.from(e).code == 'not_pending';
      if (gone && mounted) {
        setState(() => _items = [for (final i in _items ?? const <ReviewItem>[]) if (i.id != item.id) i]);
      }
      showAppNotice(reviewErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _saveReviewers(List<Reviewer> next) async {
    setState(() => _reviewersBusy = true);
    try {
      final r = await _api.setReviewers([for (final r in next) r.id]);
      if (mounted) setState(() => _reviewers = r);
    } catch (e) {
      showAppNotice(reviewErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _reviewersBusy = false);
    }
  }

  Future<void> _addReviewer() async {
    final picked = await showAppSheet<Reviewer>(context, (_) => _FindUserSheet(api: _api));
    if (picked == null) return;
    final cur = _reviewers ?? const <Reviewer>[];
    if (cur.any((r) => r.id == picked.id)) return;
    await _saveReviewers([...cur, picked]);
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      width: AppWidth.reading,
      title: t('مراجعة الأسئلة', 'Review questions'),
      subtitle: t('أسئلة بانتظار اعتمادك قبل أن تظهر للطلاب.', 'Questions waiting for your approval before students see them.'),
      icon: Icons.fact_check_rounded,
      onRefresh: _load,
      body: ListView(
        padding: AdminPage.bodyPadding(context),
        children: [
          ReviewQueueBody(
            items: _items,
            total: _total,
            error: _error,
            busyId: _busyId,
            onApprove: (i) => _decide(i, true),
            onReject: (i) => _decide(i, false),
            onRetry: _load,
          ),
          if (_reviewers != null) ...[
            const SizedBox(height: AppSpace.lg),
            ReviewersCard(
              reviewers: _reviewers!,
              busy: _reviewersBusy,
              onAdd: _addReviewer,
              onRemove: (r) => _saveReviewers([for (final x in _reviewers!) if (x.id != r.id) x]),
            ),
          ],
        ],
      ),
    );
  }
}

/// The queue: one card per pending question. [items] null = loading.
class ReviewQueueBody extends StatelessWidget {
  const ReviewQueueBody({
    super.key,
    required this.items,
    required this.total,
    required this.onApprove,
    required this.onReject,
    this.error,
    this.busyId,
    this.onRetry,
  });

  final List<ReviewItem>? items;
  final int total;
  final String? error;
  final int? busyId;
  final ValueChanged<ReviewItem> onApprove;
  final ValueChanged<ReviewItem> onReject;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (error != null && list == null) {
      return AppEmpty(
          icon: Icons.cloud_off_rounded,
          title: error!,
          actionLabel: t('إعادة المحاولة', 'Try again'),
          onAction: onRetry);
    }
    if (list == null) return const AppListSkeleton();
    if (list.isEmpty) {
      return AppEmpty(
        icon: Icons.task_alt_rounded,
        title: t('لا شيء للمراجعة', 'Nothing to review'),
        message: t('كل الأسئلة معتمدة. ستظهر هنا الأسئلة الجديدة التي تحتاج مراجعة.',
            'Every question is approved. New questions that need a review will show up here.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Text(
            countText(total, ar1: 'سؤال واحد بانتظار المراجعة', ar2: 'سؤالان بانتظار المراجعة', arFew: '$total أسئلة بانتظار المراجعة',
                arMany: '$total سؤالًا بانتظار المراجعة', en1: '1 question waiting', en: '$total questions waiting'),
            style: AppType.label(context),
          ),
        ),
        for (final i in list)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: ReviewItemCard(item: i, busy: busyId == i.id, onApprove: () => onApprove(i), onReject: () => onReject(i)),
          ),
      ],
    );
  }
}

class ReviewItemCard extends StatelessWidget {
  const ReviewItemCard({super.key, required this.item, required this.onApprove, required this.onReject, this.busy = false});

  final ReviewItem item;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppStatusBadge(label: gameItemTypeName(item.type), tone: AppTone.brand, dense: true),
            if (item.subject.isNotEmpty) AppStatusBadge(label: item.subject, dense: true),
            if (item.topic.isNotEmpty) AppStatusBadge(label: item.topic, dense: true),
          ]),
          const SizedBox(height: AppSpace.sm),
          Text(item.prompt, style: AppType.bodyStrong(context)),
          if (item.preview.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(item.preview, style: AppType.body(context), maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          if (item.sourceRef.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text('${t('المصدر', 'Source')}: ${item.sourceRef}', style: AppType.meta(context)),
          ],
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
            AppButton(
                label: t('اعتماد', 'Approve'), icon: Icons.check_rounded, busy: busy, onPressed: busy ? null : onApprove),
            AppButton(
                label: t('رفض', 'Reject'),
                icon: Icons.close_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: busy ? null : onReject),
          ]),
        ],
      ),
    );
  }
}

/// The reviewers: who may approve religious questions (the super admin manages the list).
class ReviewersCard extends StatelessWidget {
  const ReviewersCard({super.key, required this.reviewers, required this.onAdd, required this.onRemove, this.busy = false});

  final List<Reviewer> reviewers;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<Reviewer> onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('المراجعون', 'Reviewers'), style: AppType.section(context)),
          const SizedBox(height: AppSpace.xxs),
          Text(
              t('يمكنهم اعتماد أو رفض الأسئلة الدينية. المشرفون يراجعون دائمًا.',
                  'They can approve or reject religious questions. Admins can always review.'),
              style: AppType.meta(context)),
          const SizedBox(height: AppSpace.sm),
          if (reviewers.isEmpty)
            Text(t('لا يوجد مراجعون بعد.', 'No reviewers yet.'), style: AppType.body(context))
          else
            for (final r in reviewers)
              Row(children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.name.isEmpty ? '#${r.id}' : r.name, style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (r.username.isNotEmpty) Text('@${r.username}', style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
                IconButton(
                  tooltip: t('إزالة', 'Remove'),
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  onPressed: busy ? null : () => onRemove(r),
                  icon: const Icon(Icons.person_remove_rounded),
                ),
              ]),
          const SizedBox(height: AppSpace.xs),
          AppButton(
              label: t('إضافة مراجع', 'Add a reviewer'),
              icon: Icons.person_add_alt_1_rounded,
              variant: AppButtonVariant.tonal,
              busy: busy,
              onPressed: busy ? null : onAdd),
        ],
      ),
    );
  }
}

/// The reject dialog: an optional note the author reads.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet();

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('رفض السؤال', 'Reject this question'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.sm),
        AppField(
          controller: _note,
          label: t('سبب الرفض (اختياري)', 'Why (optional)'),
          hint: t('مثال: الآية غير مطابقة للمصحف', 'e.g. the ayah does not match the Mushaf'),
          maxLines: 3,
          maxLength: 300,
        ),
        const SizedBox(height: AppSpace.sm),
        AppButtonRow(
          primary: AppButton(
              label: t('رفض', 'Reject'), variant: AppButtonVariant.danger, onPressed: () => Navigator.of(context).pop(_note.text.trim())),
          secondary: [
            AppButton(label: t('إلغاء', 'Cancel'), variant: AppButtonVariant.ghost, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ]),
    );
  }
}

/// Search a person by name or username to make them a reviewer.
class _FindUserSheet extends StatefulWidget {
  const _FindUserSheet({required this.api});
  final ItemsReviewApi api;

  @override
  State<_FindUserSheet> createState() => _FindUserSheetState();
}

class _FindUserSheetState extends State<_FindUserSheet> {
  List<Reviewer> _found = const [];
  bool _busy = false;
  bool _searched = false;

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _found = const [];
        _searched = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await widget.api.findUsers(q.trim());
      if (mounted) {
        setState(() {
          _found = r;
          _searched = true;
        });
      }
    } catch (e) {
      showAppNotice(reviewErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('إضافة مراجع', 'Add a reviewer'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.sm),
        AppSearchField(hint: t('ابحث بالاسم أو اسم المستخدم', 'Search by name or username'), autofocus: true, onChanged: _search),
        const SizedBox(height: AppSpace.sm),
        if (_busy)
          const AppListSkeleton(items: 2)
        else if (_searched && _found.isEmpty)
          Text(t('لا نتائج', 'No results'), style: AppType.body(context))
        else
          for (final u in _found)
            InkWell(
              onTap: () => Navigator.of(context).pop(u),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(u.username.isEmpty ? u.name : '${u.name}  @${u.username}',
                      style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
      ]),
    );
  }
}
