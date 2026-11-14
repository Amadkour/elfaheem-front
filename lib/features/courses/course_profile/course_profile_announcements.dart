// lib/features/courses/course_profile/course_profile_announcements.dart
//
// Course announcements: the teaching team posts to all students, lecture students or sections/labs (a TA posts to
// sections/labs unless granted lecture editing). Students read them; posting notifies them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/org/org_v3.dart' show orgParseUtc;
import 'package:flutter_education_app/features/courses/course_profile/course_profile_models.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_screen.dart' show cpCall, cpErrorMessage;

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
    if (posted == true) {
      await _fetch();
      await widget.onChanged();
    }
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
    final header = AppSectionTitle(
      t('الإعلانات', 'Announcements'),
      subtitle: canPost
          ? t('يصل الإعلان لطلاب المقرر كإشعار', 'Students get each announcement as a notification')
          : t('آخر ما نشره فريق التدريس', 'Latest from the teaching team'),
      trailing: canPost ? AppPill(icon: Icons.campaign_rounded, label: t('إعلان جديد', 'New'), onTap: _compose) : null,
    );
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
            padding: const EdgeInsets.only(bottom: 10),
            child: CpAnnouncementCard(item: a, onDelete: a['can_delete'] == true && !p.readOnly ? () => _delete(a) : null),
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, const SizedBox(height: 10), body]);
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
    return AppCard(
      padding: EdgeInsets.all(compact ? 12 : 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 4,
          height: compact ? 36 : 44,
          decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (item['pinned'] == true) ...[
                Icon(Icons.push_pin_rounded, size: 15, color: c.warning),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text('${item['title'] ?? ''}', maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis,
                    style: appText(compact ? 13.5 : 14.5, w: FontWeight.w800, c: c.textDark)),
              ),
            ]),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(body, maxLines: compact ? 2 : 8, overflow: TextOverflow.ellipsis,
                  style: appText(compact ? 12.5 : 13.5, c: c.textMedium, h: 1.5)),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppTag(t(aud.$1, aud.$2), tone),
              Text(
                [if (author != null) '$author', if (when != null) AppTime.dateTime(when)].join(' · '),
                style: appText(11.5, c: c.textLight),
              ),
            ]),
          ]),
        ),
        if (onDelete != null)
          IconButton(
            tooltip: t('حذف', 'Delete'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.textLight),
            onPressed: onDelete,
          ),
      ]),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.profile});
  final CourseProfile profile;

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
      appToast(t('اكتب عنواناً للإعلان', 'Write a title'), error: true);
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
    if (r != null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _taOnly ? const ['section'] : const ['all', 'lecture', 'section'];
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader(t('إعلان جديد', 'New announcement')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppField(controller: _title, label: t('العنوان', 'Title')),
            const SizedBox(height: 12),
            AppField(controller: _body, label: t('النص', 'Message'), maxLines: 5),
            const SizedBox(height: 14),
            Text(t('الجمهور', 'Audience'), style: appText(13, w: FontWeight.w700, c: context.colors.textDark)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in tracks)
                AppChoiceChip(
                  label: t(cpAudienceLabel(k).$1, cpAudienceLabel(k).$2),
                  selected: _track == k,
                  onTap: () => setState(() => _track = k),
                ),
            ]),
            if (_taOnly) ...[
              const SizedBox(height: 8),
              Text(t('صلاحيتك تشمل طلاب السكاشن والمعامل', 'Your rights cover section & lab students'),
                  style: appText(12, c: context.colors.textLight)),
            ],
            const SizedBox(height: 6),
            if (widget.profile.role != 'ta')
              AppSwitchTile(
                title: t('تثبيت أعلى القائمة', 'Pin to top'),
                value: _pinned,
                onChanged: (v) => setState(() => _pinned = v),
              ),
            AppSwitchTile(
              title: t('إرسال إشعار للطلاب', 'Notify students'),
              value: _notify,
              onChanged: (v) => setState(() => _notify = v),
            ),
            const SizedBox(height: 12),
            AppButton.primary(expand: true, icon: Icons.send_rounded, label: t('نشر', 'Post'), busy: _busy, onPressed: _busy ? null : _send),
          ]),
        ),
      ),
    ]);
  }
}
