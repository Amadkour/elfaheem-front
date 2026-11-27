// lib/features/games/learner/nickname_sheet.dart — "Your name in games" (redesign WP4, owner decision O-3,
// docs/redesign/api/games.md): the ONE name and picture other players see on boards, champions and challenges.
//
//   GamesNicknameApi    GET /me/games/nickname (the first call makes one) · GET …/suggestions (5 free names) ·
//                       PUT {nickname?, avatar?: {icon?, color?}}
//   showNicknameSheet   loads, then NicknameEditor; returns the saved nickname (null = closed without saving)
//   NicknameEditor      plain values (test/ui/wire_layout_test.dart): the avatar preview, the name field (read-only
//                       until `can_change_at`), the suggestions, the picture and colour pickers, Save. A 422
//                       `nickname_invalid` shows its reason under the field, 409 `nickname_taken` its suggestions,
//                       429 `nickname_change_too_soon` locks the field until its date. The avatar may change any time.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

/// The learner's board identity.
@immutable
class GamesNickname {
  const GamesNickname({
    required this.nickname,
    this.icon = 'star',
    this.color = 'b',
    this.source = 'generated',
    this.canChangeAt,
    this.icons = kNicknameIcons,
    this.colors = kNicknameColors,
  });

  final String nickname, icon, color, source;

  /// Null = the name may change now.
  final DateTime? canChangeAt;
  final List<String> icons, colors;

  bool locked(DateTime now) => canChangeAt != null && canChangeAt!.isAfter(now);

  static List<String> _strs(Object? v, List<String> fallback) {
    final l = [for (final x in (v is List ? v : const [])) if (x is String && x.isNotEmpty) x];
    return l.isEmpty ? fallback : l;
  }

  factory GamesNickname.fromJson(Map<String, dynamic> j) {
    final av = j['avatar'] is Map ? j['avatar'] as Map : const {};
    final at = DateTime.tryParse('${j['can_change_at'] ?? ''}');
    return GamesNickname(
      nickname: '${j['nickname'] ?? ''}',
      icon: '${av['icon'] ?? 'star'}',
      color: '${av['color'] ?? 'b'}',
      source: '${j['source'] ?? 'generated'}',
      canChangeAt: at == null ? null : (at.isUtc ? at : DateTime.utc(at.year, at.month, at.day, at.hour, at.minute, at.second)),
      icons: _strs(j['icons'], kNicknameIcons),
      colors: _strs(j['colors'], kNicknameColors),
    );
  }
}

const kNicknameIcons = ['bolt', 'star', 'rocket', 'moon', 'target', 'crown', 'fire', 'sparkle', 'heart', 'leaf'];
const kNicknameColors = ['b', 'y', 'o', 'n', 'p', 't', 'k', 'g'];

IconData nicknameIcon(String key) => switch (key) {
      'bolt' => Icons.bolt_rounded,
      'rocket' => Icons.rocket_launch_rounded,
      'moon' => Icons.nightlight_round,
      'target' => Icons.track_changes_rounded,
      'crown' => Icons.emoji_events_rounded,
      'fire' => Icons.local_fire_department_rounded,
      'sparkle' => Icons.auto_awesome_rounded,
      'heart' => Icons.favorite_rounded,
      'leaf' => Icons.eco_rounded,
      _ => Icons.star_rounded,
    };

/// A colour key (the design's gradient keys) as a kit tone.
KitTone nicknameTone(BuildContext context, String key) {
  final kit = context.colors.kit;
  return switch (key) {
    'y' => kit.accent(AppAccent.sun),
    'o' => kit.warmTone,
    'n' => kit.primaryTone,
    'p' => kit.accent(AppAccent.pink),
    't' => kit.accent(AppAccent.mint),
    'k' => kit.accent(AppAccent.grape),
    'g' => kit.accent(AppAccent.lime),
    _ => kit.accent(AppAccent.sky),
  };
}

class GamesNicknameApi {
  GamesNicknameApi({ApiClient? client}) : _c = client ?? ApiClient();

  final ApiClient _c;

  Future<GamesNickname> mine() async => GamesNickname.fromJson(_map(await _c.get('/api/v1/me/games/nickname')));

  Future<List<String>> suggestions() async {
    final r = _map(await _c.get('/api/v1/me/games/nickname/suggestions'));
    return [for (final x in (r['items'] as List? ?? const [])) if (x is String) x];
  }

  Future<GamesNickname> save({String? nickname, String? icon, String? color}) async => GamesNickname.fromJson(_map(await _c.put(
        '/api/v1/me/games/nickname',
        body: {
          'nickname': ?nickname,
          if (icon != null || color != null) 'avatar': {'icon': ?icon, 'color': ?color},
        },
      )));

  static Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
}

/// The bilingual text of a 422 `nickname_invalid` reason.
String nicknameReasonText(String? reason, String fallback) => switch (reason) {
      'too_short' => 'sd_nick_too_short'.tr,
      'too_long' => 'sd_nick_too_long'.tr,
      'bad_chars' => 'sd_nick_bad_chars'.tr,
      'contact' => 'sd_nick_contact'.tr,
      'blocked' => 'sd_nick_blocked'.tr,
      'own_name' => 'sd_nick_own_name'.tr,
      'reserved' => 'sd_nick_reserved'.tr,
      _ => fallback,
    };

/// Opens the editor; the saved nickname, or null.
Future<GamesNickname?> showNicknameSheet(BuildContext context, {GamesNicknameApi? api}) =>
    showAppSheet<GamesNickname>(context, (_) => _NicknameHost(api: api ?? GamesNicknameApi()));

class _NicknameHost extends StatefulWidget {
  const _NicknameHost({required this.api});

  final GamesNicknameApi api;

  @override
  State<_NicknameHost> createState() => _NicknameHostState();
}

class _NicknameHostState extends State<_NicknameHost> {
  final _field = TextEditingController();
  GamesNickname? _me;
  List<String> _suggestions = const [];
  String? _icon, _color, _fieldError, _loadError;
  bool _saving = false, _suggesting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final me = await widget.api.mine();
      if (!mounted) return;
      setState(() {
        _me = me;
        _field.text = me.nickname;
        _icon = me.icon;
        _color = me.color;
      });
      if (!me.locked(DateTime.now().toUtc())) await _suggest();
    } catch (e) {
      if (mounted) setState(() => _loadError = ApiException.from(e).message);
    }
  }

  Future<void> _suggest() async {
    setState(() => _suggesting = true);
    try {
      final s = await widget.api.suggestions();
      if (mounted) setState(() => _suggestions = s);
    } catch (e) {
      if (mounted) showAppNotice(ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  Future<void> _save() async {
    final me = _me;
    if (me == null || _saving) return;
    final name = _field.text.trim();
    final nameChanged = name != me.nickname && !me.locked(DateTime.now().toUtc());
    final iconChanged = _icon != me.icon, colorChanged = _color != me.color;
    if (!nameChanged && !iconChanged && !colorChanged) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _fieldError = null;
    });
    try {
      final saved = await widget.api.save(
        nickname: nameChanged ? name : null,
        icon: iconChanged ? _icon : null,
        color: colorChanged ? _color : null,
      );
      if (!mounted) return;
      showAppNotice('sd_nick_saved'.tr);
      Navigator.of(context).pop(saved);
    } catch (e) {
      final x = ApiException.from(e);
      final detail = x.body is Map && (x.body as Map)['detail'] is Map ? (x.body as Map)['detail'] as Map : const {};
      if (!mounted) return;
      setState(() {
        _saving = false;
        switch (x.code) {
          case 'nickname_invalid':
            _fieldError = nicknameReasonText('${detail['reason'] ?? ''}', x.message);
          case 'nickname_taken':
            _fieldError = 'sd_nick_taken'.tr;
            final s = [for (final v in (detail['suggestions'] as List? ?? const [])) if (v is String) v];
            if (s.isNotEmpty) _suggestions = s;
          case 'nickname_change_too_soon':
            final at = DateTime.tryParse('${detail['can_change_at'] ?? ''}');
            _me = GamesNickname(
              nickname: me.nickname,
              icon: me.icon,
              color: me.color,
              source: me.source,
              canChangeAt: at == null ? null : (at.isUtc ? at : DateTime.utc(at.year, at.month, at.day, at.hour, at.minute)),
              icons: me.icons,
              colors: me.colors,
            );
            _field.text = me.nickname;
          default:
            showAppNotice(x.message, error: true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    if (me == null) {
      return AppSheetContent(
        title: 'sd_nick_title'.tr,
        icon: Icons.badge_outlined,
        children: [
          _loadError == null ? const AppListSkeleton(items: 3, padding: EdgeInsets.zero) : AppErrorState(message: _loadError, onRetry: _load),
        ],
      );
    }
    return NicknameEditor(
      me: me,
      controller: _field,
      icon: _icon ?? me.icon,
      color: _color ?? me.color,
      suggestions: _suggestions,
      fieldError: _fieldError,
      saving: _saving,
      suggesting: _suggesting,
      onIcon: (v) => setState(() => _icon = v),
      onColor: (v) => setState(() => _color = v),
      onSuggestion: (v) => setState(() {
        _field.text = v;
        _fieldError = null;
      }),
      onMoreSuggestions: _suggest,
      onChanged: (_) {
        if (_fieldError != null) setState(() => _fieldError = null);
      },
      onSave: _save,
    );
  }
}

/// The avatar: the picked icon on the picked colour.
class NicknameAvatar extends StatelessWidget {
  const NicknameAvatar({super.key, required this.icon, required this.color, this.size = AppTouch.min});

  final String icon, color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = nicknameTone(context, color);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [tone.color, Color.lerp(tone.color, tone.ink, .45)!],
          ),
        ),
        child: Icon(nicknameIcon(icon), size: size * .5, color: context.colors.onHero),
      ),
    );
  }
}

class NicknameEditor extends StatelessWidget {
  const NicknameEditor({
    super.key,
    required this.me,
    required this.controller,
    required this.icon,
    required this.color,
    this.suggestions = const [],
    this.fieldError,
    this.saving = false,
    this.suggesting = false,
    this.now,
    this.onIcon,
    this.onColor,
    this.onSuggestion,
    this.onMoreSuggestions,
    this.onChanged,
    this.onSave,
  });

  final GamesNickname me;
  final TextEditingController controller;
  final String icon, color;
  final List<String> suggestions;
  final String? fieldError;
  final bool saving, suggesting;

  /// "Now" for the change lock (tests); default the clock.
  final DateTime? now;
  final ValueChanged<String>? onIcon, onColor, onSuggestion, onChanged;
  final VoidCallback? onMoreSuggestions, onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final locked = me.locked(now ?? DateTime.now().toUtc());
    return AppSheetContent(
      title: 'sd_nick_title'.tr,
      icon: Icons.badge_outlined,
      children: [
        Row(children: [
          NicknameAvatar(icon: icon, color: color, size: AppTouch.min + AppSpace.md),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(controller.text.isEmpty ? me.nickname : controller.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              Text('sd_nick_sub'.tr, style: AppType.meta(context)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        AppField(
          key: const ValueKey('games.nick.field'),
          controller: controller,
          label: 'sd_nick_field'.tr,
          maxLength: 20,
          readOnly: locked,
          enabled: !saving,
          errorText: fieldError,
          helper: locked
              ? 'sd_nick_locked'.tr.replaceAll('{date}', AppTime.date(me.canChangeAt!))
              : 'sd_nick_rule'.tr,
          onChanged: onChanged,
        ),
        if (!locked) ...[
          const SizedBox(height: AppSpace.sm),
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('sd_nick_suggest'.tr, style: AppType.tileTitle(context)),
            AppButton.ghost(
              key: const ValueKey('games.nick.more'),
              label: 'sd_nick_more'.tr,
              icon: Icons.refresh_rounded,
              busy: suggesting,
              onPressed: onMoreSuggestions,
            ),
          ]),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final s in suggestions)
              AppChip(
                key: ValueKey('games.nick.s.$s'),
                label: s,
                selected: controller.text.trim() == s,
                onTap: onSuggestion == null ? null : () => onSuggestion!(s),
              ),
          ]),
        ],
        const SizedBox(height: AppSpace.md),
        Text('sd_nick_icon'.tr, style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final (i, k) in me.icons.indexed)
            _Pick(
              key: ValueKey('games.nick.icon.$k'),
              label: '${'sd_nick_icon'.tr} ${i + 1}',
              selected: k == icon,
              ring: set.ink,
              onTap: onIcon == null ? null : () => onIcon!(k),
              child: Icon(nicknameIcon(k), size: AppIconSize.md, color: k == icon ? set.ink : c.textMedium),
            ),
        ]),
        const SizedBox(height: AppSpace.md),
        Text('sd_nick_color'.tr, style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final (i, k) in me.colors.indexed)
            _Pick(
              key: ValueKey('games.nick.color.$k'),
              label: '${'sd_nick_color'.tr} ${i + 1}',
              selected: k == color,
              ring: set.ink,
              onTap: onColor == null ? null : () => onColor!(k),
              child: NicknameAvatar(icon: icon, color: k, size: AppTouch.min - AppSpace.sm),
            ),
        ]),
        const SizedBox(height: AppSpace.lg),
        AppButton.primary(
          key: const ValueKey('games.nick.save'),
          label: 'sd_nick_save'.tr,
          expand: true,
          busy: saving,
          onPressed: onSave,
        ),
      ],
    );
  }
}

/// One choice of the picture / colour pickers: a 44 px target with a ring when picked.
class _Pick extends StatelessWidget {
  const _Pick({super.key, required this.label, required this.selected, required this.ring, required this.child, this.onTap});

  final String label;
  final bool selected;
  final Color ring;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: AppTouch.min,
          height: AppTouch.min,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.kit.well,
            border: Border.all(color: selected ? ring : c.kit.line, width: selected ? AppBorder.focus : AppBorder.hairline),
          ),
          child: child,
        ),
      ),
    );
  }
}
