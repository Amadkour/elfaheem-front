// lib/features/quran/admin/quran_admin_page.dart — SUPER ADMIN: verify and review Quran teachers (Learning Hub
// Phase 6, D-1347 / D-1350). Without it, switching `quran.teacher_verification_required` or
// `quran.content_review_required` on would hide every teacher for good.
//
//   GET  /api/v1/admin/quran/teachers?status=pending|published|draft   the cards (super admin)
//   POST /api/v1/admin/quran/teachers/{id}/verify {verified}           verify / remove the verification
//   POST /api/v1/admin/quran/teachers/{id}/review {approve}            a pending card: approve / return to draft
//
//   QuranAdminPage         status tabs → one card per teacher; every action asks first (appConfirm)
//   QuranAdminTeacherCard  one teacher over plain values (tested by the layout harness)
//
// Entry: the admin services hub (super admin, hidden with `student_tab_quran`) and the module switches page under
// the two Quran flags.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry, t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/quran/quran_api.dart' show quranErrorText;
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:flutter_education_app/features/quran/quran_teacher_hub.dart' show quranStatusLabel;

/// The three admin calls (a fake one in tests).
class QuranAdminApi {
  QuranAdminApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<List<QuranTeacher>> teachers(String status) async {
    final r = await _api.get('/api/v1/admin/quran/teachers', queryParams: {'status': status});
    final items = r is Map ? r['items'] : null;
    return [
      for (final j in (items is List ? items : const []))
        if (j is Map) QuranTeacher.fromJson(Map<String, dynamic>.from(j)),
    ];
  }

  Future<void> verify(int teacherId, bool verified) =>
      _api.post('/api/v1/admin/quran/teachers/$teacherId/verify', body: {'verified': verified});

  Future<void> review(int teacherId, bool approve) =>
      _api.post('/api/v1/admin/quran/teachers/$teacherId/review', body: {'approve': approve});
}

/// The status tabs, in order.
const List<String> kQuranAdminStatuses = ['pending', 'published', 'draft'];

class QuranAdminPage extends StatefulWidget {
  const QuranAdminPage({super.key, this.api, this.initialStatus = 'pending'});

  final QuranAdminApi? api;
  final String initialStatus;

  @override
  State<QuranAdminPage> createState() => _QuranAdminPageState();
}

class _QuranAdminPageState extends State<QuranAdminPage> {
  late final QuranAdminApi _api = widget.api ?? QuranAdminApi();
  late int _tab = kQuranAdminStatuses.contains(widget.initialStatus) ? kQuranAdminStatuses.indexOf(widget.initialStatus) : 0;
  List<QuranTeacher>? _items;
  String? _error;
  DateTime? _loadedAt;
  int? _busyId;

  String get _status => kQuranAdminStatuses[_tab];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final status = _status;
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final items = await _api.teachers(status);
      if (!mounted || status != _status) return;
      setState(() {
        _items = items;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted || status != _status) return;
      setState(() => _error = quranErrorText(e));
    }
  }

  Future<void> _act(QuranTeacher p, String action) async {
    final (message, danger) = switch (action) {
      'verify' => (t('توثيق ${p.name}؟ سيظهر للطلاب حين يُشترط التوثيق.', 'Verify ${p.name}? They show to students when verification is required.'), false),
      'unverify' => (t('إزالة توثيق ${p.name}؟ يختفي من القائمة حين يُشترط التوثيق.', 'Remove the verification of ${p.name}? They leave the list when verification is required.'), true),
      'approve' => (t('نشر بطاقة ${p.name}؟', 'Publish the card of ${p.name}?'), false),
      _ => (t('إعادة بطاقة ${p.name} إلى المسودة؟', 'Return the card of ${p.name} to draft?'), true),
    };
    if (!await appConfirm(context, message: message, danger: danger)) return;
    setState(() => _busyId = p.userId);
    try {
      switch (action) {
        case 'verify':
          await _api.verify(p.userId, true);
        case 'unverify':
          await _api.verify(p.userId, false);
        case 'approve':
          await _api.review(p.userId, true);
        default:
          await _api.review(p.userId, false);
      }
      showAppNotice(t('تم الحفظ', 'Saved'));
      if (mounted) await _load();
    } catch (e) {
      showAppNotice(quranErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final Widget list;
    if (_error != null) {
      list = ErrorRetry(message: _error!, onRetry: _load);
    } else if (items == null) {
      list = const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
    } else if (items.isEmpty) {
      list = AppEmpty(
        icon: Icons.menu_book_rounded,
        title: switch (_status) {
          'pending' => t('لا بطاقات بانتظار المراجعة', 'No cards waiting for review'),
          'published' => t('لا بطاقات منشورة', 'No published cards'),
          _ => t('لا مسودات', 'No drafts'),
        },
      );
    } else {
      list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final p in items) ...[
          QuranAdminTeacherCard(
            key: ValueKey('quran.admin.${p.userId}'),
            teacher: p,
            busy: _busyId == p.userId,
            onVerify: (v) => _act(p, v ? 'verify' : 'unverify'),
            onReview: p.status == 'pending' ? (approve) => _act(p, approve ? 'approve' : 'draft') : null,
          ),
          AppSpace.gapSm,
        ],
      ]);
    }
    return AdminPage(
      width: AppWidth.reading,
      title: t('معلمو القرآن', 'Quran teachers'),
      subtitle: t('التوثيق ومراجعة البطاقات', 'Verification and card review'),
      icon: Icons.verified_user_rounded,
      helpPageId: 'admin.quran',
      onRefresh: _load,
      updatedAt: _loadedAt,
      body: ListView(padding: AdminPage.bodyPadding(context), children: [
        AppTabs(
          expand: true,
          index: _tab,
          onChanged: (i) {
            if (i == _tab) return;
            setState(() => _tab = i);
            _load();
          },
          items: [
            AppTabItem(t('بانتظار المراجعة', 'Pending'), icon: Icons.hourglass_top_rounded),
            AppTabItem(t('منشورة', 'Published'), icon: Icons.public_rounded),
            AppTabItem(t('مسودات', 'Drafts'), icon: Icons.edit_note_rounded),
          ],
        ),
        AppSpace.gapMd,
        list,
      ]),
    );
  }
}

/// One teacher card with its actions. [onReview] is null unless the card is pending (the server reviews only those).
class QuranAdminTeacherCard extends StatelessWidget {
  const QuranAdminTeacherCard({
    super.key,
    required this.teacher,
    required this.onVerify,
    this.onReview,
    this.busy = false,
  });

  final QuranTeacher teacher;
  final ValueChanged<bool> onVerify;
  final ValueChanged<bool>? onReview;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = teacher;
    final goals = p.goals.map(quranGoalLabel).join(' · ');
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AppAvatar(name: p.name, url: p.avatarUrl, size: AppTouch.min - AppSpace.xs),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark)),
          ),
        ]),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppStatusBadge(
            label: quranStatusLabel(p.status),
            tone: switch (p.status) { 'published' => AppTone.success, 'pending' => AppTone.warning, _ => AppTone.neutral },
            dense: true,
          ),
          AppStatusBadge(
            label: p.verified ? t('موثّق', 'Verified') : t('غير موثّق', 'Not verified'),
            tone: p.verified ? AppTone.success : AppTone.neutral,
            icon: p.verified ? Icons.verified_rounded : null,
            dense: true,
          ),
          AppStatusBadge(label: quranGenderLabel(p.gender), tone: AppTone.info, dense: true),
        ]),
        if ((p.ijazah ?? '').isNotEmpty) ...[
          AppSpace.gapSm,
          Text(t('الإجازة: ${p.ijazah}', 'Ijazah: ${p.ijazah}'), style: AppType.meta(context)),
        ],
        if (goals.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(t('الأهداف: $goals', 'Goals: $goals'), style: AppType.meta(context)),
        ],
        AppSpace.gapMd,
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          if (p.verified)
            AppButton.secondary(
              key: ValueKey('quran.admin.unverify.${p.userId}'),
              label: t('إزالة التوثيق', 'Remove verification'),
              icon: Icons.remove_moderator_outlined,
              size: AppButtonSize.sm,
              onPressed: busy ? null : () => onVerify(false),
            )
          else
            AppButton.tonal(
              key: ValueKey('quran.admin.verify.${p.userId}'),
              label: t('توثيق', 'Verify'),
              icon: Icons.verified_rounded,
              size: AppButtonSize.sm,
              busy: busy,
              onPressed: busy ? null : () => onVerify(true),
            ),
          if (onReview != null) ...[
            AppButton.primary(
              key: ValueKey('quran.admin.approve.${p.userId}'),
              label: t('اعتماد ونشر', 'Approve'),
              icon: Icons.check_rounded,
              size: AppButtonSize.sm,
              onPressed: busy ? null : () => onReview!(true),
            ),
            AppButton.secondary(
              key: ValueKey('quran.admin.draft.${p.userId}'),
              label: t('إعادة للمسودة', 'Return to draft'),
              icon: Icons.undo_rounded,
              size: AppButtonSize.sm,
              onPressed: busy ? null : () => onReview!(false),
            ),
          ],
        ]),
      ]),
    );
  }
}
