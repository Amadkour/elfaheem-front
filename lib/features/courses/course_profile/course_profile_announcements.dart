// lib/features/courses/course_profile/course_profile_announcements.dart
//
// Course announcements (Tea1Class.dc.html?screen=announce): the teaching team posts to all students, lecture students
// or sections/labs (a TA posts to sections/labs unless granted lecture editing). One-way: students read them and
// reply privately to the teacher in the chat (privacy WP3); posting notifies them. Teacher pages use the restrained
// motion only (M9 presses): a wide page shows the list beside an inline composer, a phone opens the same composer
// as a sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/org/org_v3.dart' show orgParseUtc;
import 'package:flutter_education_app/features/courses/course_profile/course_profile_models.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_screen.dart' show cpCall, cpErrorMessage;
import 'package:flutter_education_app/features/courses/course_profile/t1_class_parts.dart';

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class CpAnnouncementsTab extends StatefulWidget {
  const CpAnnouncementsTab({super.key, required this.profile, required this.onChanged, this.load = true});
  final CourseProfile profile;
  final Future<void> Function() onChanged;

  /// False in tests: show the profile's preview only.
  final bool load;

  @override
  State<CpAnnouncementsTab> createState() => _CpAnnouncementsTabState();
}

class _CpAnnouncementsTabState extends State<CpAnnouncementsTab> {
  late List<Map<String, dynamic>> _items = widget.profile.announcements;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.load) _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final r = await ApiClient().get('/api/v1/course-profile/${widget.profile.id}/announcements');
      if (!mounted) return;
      setState(() => _items = [for (final e in (_map(r)['items'] as List? ?? const [])) _map(e)]);
    } catch (e) {
      if (mounted) setState(() => _error = cpErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _compose() async {
    final posted = await showAppSheet<bool>(context, (_) => _Composer(profile: widget.profile));
    if (posted == true) await _posted();
  }

  Future<void> _posted() async {
    await _fetch();
    await widget.onChanged();
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    if (!await appConfirm(context, message: t('حذف هذا الإعلان؟', 'Delete this announcement?'), danger: true)) return;
    final r = await cpCall(() => ApiClient().delete('/api/v1/course-profile/${widget.profile.id}/announcements/${a['id']}'),
        ok: t('تم الحذف', 'Deleted'));
    if (r != null) await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final canPost = p.caps.announce && !p.readOnly;
    final Widget body;
    if (_loading) {
      body = const AppListSkeleton(items: 3);
    } else if (_error != null && _items.isEmpty) {
      body = AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _fetch);
    } else if (_items.isEmpty) {
      body = AppEmpty(
        icon: Icons.campaign_outlined,
        title: t('لا إعلانات بعد', 'No announcements yet'),
        message: canPost ? t('انشر أول إعلان لطلابك', 'Post the first announcement to your students') : null,
        actionLabel: canPost ? t('إعلان جديد', 'New announcement') : null,
        onAction: canPost ? _compose : null,
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final a in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: CpAnnouncementCard(item: a, onDelete: a['can_delete'] == true && !p.readOnly ? () => _delete(a) : null),
          ),
      ]);
    }
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900 && canPost;
      final list = AppCard(
        title: t('الإعلانات', 'Announcements'),
        action: wide || !canPost
            ? (_items.isEmpty ? null : ClCountChip('${_items.length}'))
            : AppPill(icon: Icons.campaign_rounded, label: t('إعلان جديد', 'New'), onTap: _compose),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              canPost
                  ? t('يصل الإعلان لطلاب الدورة كإشعار', 'Students get each announcement as a notification')
                  : t('آخر ما نشره فريق التدريس', 'Latest from the teaching team'),
              style: AppType.meta(context)),
          AppSpace.gapSm,
          body,
        ]),
      );
      if (!wide) return list;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: list),
        AppSpace.gapMd,
        Expanded(
          flex: 2,
          child: AppCard(
            title: t('إعلان جديد', 'New announcement'),
            action: Icon(Icons.campaign_outlined, size: AppIconSize.md, color: context.colors.textLight),
            child: _Composer(profile: p, onPosted: _posted),
          ),
        ),
      ]);
    });
  }
}

/// One announcement. `compact` = title + one body line (overview / side rail).
class CpAnnouncementCard extends StatelessWidget {
  const CpAnnouncementCard({super.key, required this.item, this.onDelete, this.compact = false});
  final Map<String, dynamic> item;
  final VoidCallback? onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final track = '${item['track'] ?? 'all'}';
    final tone = switch (track) { 'section' => c.purple, 'lecture' => c.primary, _ => c.accent };
    final when = orgParseUtc(item['created_at']);
    final author = _map(item['author'])['name'];
    final body = '${item['body'] ?? ''}'.trim();
    final aud = cpAudienceLabel(track);
    final pinned = item['pinned'] == true;
    final seen = item['seen_count'] is num ? (item['seen_count'] as num).toInt() : null;
    final total = item['audience_count'] is num ? (item['audience_count'] as num).toInt() : null;
    return Container(
      padding: EdgeInsets.all(compact ? AppSpace.sm : AppSpace.md),
      decoration: BoxDecoration(
        color: pinned ? Color.alphaBlend(c.primaryTint, c.cardBg) : c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: pinned ? c.primary : c.divider, width: pinned ? AppBorder.strong : AppBorder.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (pinned) AppTag(t('مثبّت', 'Pinned'), c.primary, icon: Icons.push_pin_rounded),
              AppTag(t(aud.$1, aud.$2), tone),
              if (when != null) Text(AppTime.dateTime(when), style: AppType.meta(context)),
            ]),
          ),
          if (onDelete != null) AppIconButton(icon: Icons.delete_outline_rounded, tooltip: t('حذف', 'Delete'), onPressed: onDelete),
        ]),
        AppSpace.gapXs,
        Text('${item['title'] ?? ''}', maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
        if (body.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(body, maxLines: compact ? 2 : 8, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textMedium)),
        ],
        if (!compact && (author != null || seen != null)) ...[
          AppSpace.gapXs,
          Row(children: [
            if (seen != null && total != null) ...[
              Icon(Icons.visibility_outlined, size: AppIconSize.sm, color: c.textLight),
              const SizedBox(width: AppSpace.xxs),
              Text(t('شافه $seen من $total', 'Seen by $seen of $total'), style: AppType.meta(context)),
              AppSpace.gapXs,
            ],
            if (author != null) Expanded(child: Text('$author', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
          ]),
        ],
      ]),
    );
  }
}

/// The composer: a sheet on a phone (no [onPosted]: it pops with true), inline on a wide page ([onPosted] runs and
/// the form clears).
class _Composer extends StatefulWidget {
  const _Composer({required this.profile, this.onPosted});
  final CourseProfile profile;
  final Future<void> Function()? onPosted;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late final bool _taOnly = widget.profile.role == 'ta' && !widget.profile.caps.manageLecture;
  late String _track = _taOnly ? 'section' : 'all';
  bool _pinned = false, _notify = true, _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty) {
      showAppNotice(t('اكتب عنوانًا للإعلان', 'Write a title'), error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await cpCall(
        () => ApiClient().post('/api/v1/course-profile/${widget.profile.id}/announcements', body: {
              'track': _track,
              'title': _title.text.trim(),
              'body': _body.text.trim(),
              'pinned': _pinned,
              'notify': _notify,
            }),
        ok: t('تم نشر الإعلان', 'Announcement posted'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) return;
    final after = widget.onPosted;
    if (after == null) {
      Navigator.of(context).pop(true);
      return;
    }
    _title.clear();
    _body.clear();
    await after();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _taOnly ? const ['section'] : const ['all', 'lecture', 'section'];
    final c = context.colors;
    final form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(controller: _title, label: t('العنوان', 'Title')),
      AppSpace.gapSm,
      AppField(controller: _body, label: t('النص', 'Message'), maxLines: 5),
      AppSpace.gapMd,
      Text(t('الجمهور', 'Audience'), style: AppType.label(context)),
      AppSpace.gapXs,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final k in tracks)
          AppChoiceChip(
            label: t(cpAudienceLabel(k).$1, cpAudienceLabel(k).$2),
            selected: _track == k,
            onTap: () => setState(() => _track = k),
          ),
      ]),
      if (_taOnly) ...[
        AppSpace.gapXs,
        Text(t('صلاحيتك تشمل طلاب السكاشن والمعامل', 'Your rights cover section & lab students'), style: AppType.meta(context).copyWith(color: c.textLight)),
      ],
      AppSpace.gapXs,
      AppSwitchTile(
        title: t('أرسل إشعار للطلاب', 'Notify the students'),
        value: _notify,
        onChanged: (v) => setState(() => _notify = v),
      ),
      if (widget.profile.role != 'ta')
        AppSwitchTile(
          title: t('ثبّته فوق', 'Pin it on top'),
          value: _pinned,
          onChanged: (v) => setState(() => _pinned = v),
        ),
      AppSpace.gapMd,
      AppButton.primary(expand: true, icon: Icons.send_rounded, label: t('نشر', 'Post'), busy: _busy, onPressed: _busy ? null : _send),
    ]);
    if (widget.onPosted != null) return form;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader(t('إعلان جديد', 'New announcement')),
      Flexible(
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md), child: form),
      ),
    ]);
  }
}
