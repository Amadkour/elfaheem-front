// lib/features/shared/public_profile/mention_card.dart
//
// What a tap on an "@name" in a text opens (MentionText → AppNavigator.openMention, D-075): a small sheet, not a
// page, because only a teacher with a confirmed username has a public profile (D-074) and most mentions are of
// students and staff, whose page would be a "not found".
//
//   showMentionCard(context, username)   loads GET /api/v1/public/u/{username} and shows MentionCardBody
//   MentionCardBody(username, result)    plain values: loading · a teacher's card + "Open profile" · "no public
//                                        page" for anyone else · profile links off · a failure with Retry
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../admin/admin_common.dart' show t;
import '../../auth/username.dart' show UsernameRules;
import 'public_profile.dart';

Future<void> showMentionCard(BuildContext context, String username, {VoidCallback? onOpenProfile}) =>
    showAppSheet<void>(context, (_) => _MentionCardLoader(username: username, onOpenProfile: onOpenProfile));

class _MentionCardLoader extends StatefulWidget {
  const _MentionCardLoader({required this.username, this.onOpenProfile});

  final String username;
  final VoidCallback? onOpenProfile;

  @override
  State<_MentionCardLoader> createState() => _MentionCardLoaderState();
}

class _MentionCardLoaderState extends State<_MentionCardLoader> {
  PublicProfileResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_result != null) setState(() => _result = null);
    final r = await PublicProfileApi.load(widget.username);
    if (mounted) setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.onOpenProfile;
    return MentionCardBody(
      username: widget.username,
      result: _result,
      onRetry: _load,
      onOpenProfile: open == null
          ? null
          : () {
              Navigator.of(context).pop();
              open();
            },
    );
  }
}

/// The sheet's content. [result] null = loading.
class MentionCardBody extends StatelessWidget {
  const MentionCardBody({
    super.key,
    required this.username,
    required this.result,
    this.onRetry,
    this.onOpenProfile,
  });

  final String username;
  final PublicProfileResult? result;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = result;
    final p = r?.status == PublicProfileStatus.found ? r!.profile : null;
    final handle = '@${p?.username ?? UsernameRules.normalize(username)}';
    final lri = String.fromCharCode(0x2066), pdi = String.fromCharCode(0x2069);

    final Widget body;
    if (r == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: AppListSkeleton(items: 1),
      );
    } else if (p != null) {
      final spec = p.specialization(AppConfig.lang) ?? p.headline;
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AppAvatar(name: p.name, url: p.imageUrl, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w800, c: c.textDark)),
              const SizedBox(height: 2),
              Text('$lri$handle$pdi',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: c.primary)),
              if (spec != null && spec.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(spec, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
              ],
            ]),
          ),
        ]),
        if (p.isTeacher && p.coursesCount > 0) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.menu_book_rounded, size: 18, color: c.textMedium),
            const SizedBox(width: 6),
            Flexible(
              child: Text(t('${p.coursesCount} كورسات', '${p.coursesCount} courses'),
                  style: appText(13, w: FontWeight.w600, c: c.textDark)),
            ),
          ]),
        ],
        if (onOpenProfile != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onOpenProfile,
            icon: const Icon(Icons.person_rounded),
            label: Text(t('فتح الملف الشخصي', 'Open profile')),
          ),
        ],
      ]);
    } else {
      final (icon, text) = switch (r.status) {
        PublicProfileStatus.disabled => (Icons.link_off_rounded, t('روابط الملفات الشخصية متوقفة الآن.', 'Profile links are off right now.')),
        PublicProfileStatus.failed => (Icons.cloud_off_rounded, r.message ?? t('تعذر التحميل.', 'Could not load.')),
        _ => (
            Icons.person_outline_rounded,
            t('ليس له صفحة عامة. الصفحات العامة للمعلمين فقط.', 'No public page. Only teachers have one.'),
          ),
      };
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AppAvatar(name: UsernameRules.normalize(username), size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Text('$lri$handle$pdi',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w800, c: c.primary)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: c.textMedium),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: appText(13, c: c.textMedium))),
        ]),
        if (r.status == PublicProfileStatus.failed && onRetry != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(t('إعادة المحاولة', 'Retry')),
          ),
        ],
      ]);
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          body,
        ]),
      ),
    );
  }
}
