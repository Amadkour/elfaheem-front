// lib/features/auth/username_confirm.dart
//
// "Your username is @x — keep it, choose another or remove it" (D-071 v2). Accounts that existed before usernames
// got one made from their e-mail (`username_confirmed: false`); it must not stay a public handle without the person
// agreeing, so the app asks ONCE after sign-in:
//
//   usernamePromptDue(...)        pure gate: kill switch, an unconfirmed name, the 7-day snooze after a dismissal
//   UsernameConfirmApi            POST /api/v1/auth/me/username/confirm — {} keep · {username: x} change · {username: null} remove
//   UsernameConfirmContent        the sheet's content, plain values (layout harness: test/auth/username_confirm_test.dart)
//   showUsernameConfirmSheet      the sheet itself (keep · change with UsernameField · remove)
//   UsernameConfirmPrompt         the ONE trigger: topRouteObserver hands it every pushed route; on a role home it
//                                 checks (and again when the signed-in user changes, e.g. after GET /auth/me) and
//                                 shows the sheet at most once per run per user. A dismissal is remembered per user id
//                                 and offered again after 7 days at the earliest.
library;

import 'dart:async';
import 'package:flutter_education_app/design/app_back_button.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/api_client.dart';
import '../../core/api_error_text.dart';
import '../../core/offline/app_connectivity.dart';
import '../../design/app_kit.dart' show showAppSheet;
import '../../design/app_notice.dart';
import '../../utils/widget/view_as_state.dart';
import 'auth_provider.dart';
import '../../design/app_blocks.dart';
import '../../design/app_charts.dart' show appInk;
import '../../design/app_tokens.dart';
import 'auth_widgets.dart';
import 'username.dart';
import 'username_field.dart';

/// How long a dismissed prompt stays quiet.
const usernamePromptSnooze = Duration(days: 7);

/// SharedPreferences key of the last dismissal (epoch ms) for [userId].
String usernamePromptKey(int userId) => 'username_confirm_snoozed_$userId';

/// True when the keep / change / remove sheet should be offered to [user] now.
bool usernamePromptDue({
  required UserModel? user,
  required bool featureOff,
  int? snoozedAtMs,
  required DateTime now,
}) {
  if (featureOff || user == null || user.id <= 0 || !user.needsUsernameConfirm) return false;
  if (snoozedAtMs == null) return true;
  return now.difference(DateTime.fromMillisecondsSinceEpoch(snoozedAtMs)) >= usernamePromptSnooze;
}

/// What the person chose in the sheet.
enum UsernameConfirmAction { keep, change, remove }

class UsernameConfirmApi {
  UsernameConfirmApi._();

  static const path = '/api/v1/auth/me/username/confirm';

  /// The body of [action]: keep = {} (just mark confirmed), change = the new normalized name, remove = null.
  static Map<String, dynamic> body(UsernameConfirmAction action, {String? username}) => switch (action) {
        UsernameConfirmAction.keep => <String, dynamic>{},
        UsernameConfirmAction.change => {'username': UsernameRules.normalize(username ?? '')},
        UsernameConfirmAction.remove => {'username': null},
      };

  /// Sends [action] and returns the updated user. Throws [ApiException] (USERNAME_* for a refused new name).
  static Future<UserModel> send(UsernameConfirmAction action, {String? username, ApiClient? api}) async {
    final r = await (api ?? ApiClient()).post(path, body: body(action, username: username));
    if (r is Map) return UserModel.fromJson(Map<String, dynamic>.from(r));
    throw ApiException.from('empty answer');
  }
}

// ── Content (plain values) ────────────────────────────────────────────────────

enum UsernameConfirmStep { choose, change }

class UsernameConfirmContent extends StatelessWidget {
  const UsernameConfirmContent({
    super.key,
    required this.username,
    this.step = UsernameConfirmStep.choose,
    this.busy,
    this.error,
    this.changeField,
    this.canSave = false,
    this.onKeep,
    this.onChange,
    this.onRemove,
    this.onLater,
    this.onBack,
    this.onSave,
  });

  /// The name the server filled in (without "@").
  final String username;
  final UsernameConfirmStep step;

  /// The action running now (its button spins, the others wait), or null.
  final UsernameConfirmAction? busy;

  /// A sentence to show under the actions (network / server error).
  final String? error;

  /// The username input of the change step (a UsernameField).
  final Widget? changeField;
  final bool canSave;
  final VoidCallback? onKeep, onChange, onRemove, onLater, onBack, onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AnimatedSwitcher(
            duration: authDuration(context, 220),
            child: KeyedSubtree(
              key: ValueKey(step),
              child: step == UsernameConfirmStep.choose ? _choose(context) : _change(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _choose(BuildContext context) {
    final c = context.colors;
    final idle = busy == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AuthMark(icon: Icons.alternate_email_rounded, size: AppTouch.min),
            const Spacer(),
            IconButton(
              tooltip: 'username_confirm_later'.tr,
              onPressed: idle ? onLater : null,
              style: IconButton.styleFrom(
                backgroundColor: c.cardBg,
                side: BorderSide(color: c.divider, width: AppBorder.hairline),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
              ),
              icon: Icon(Icons.close_rounded, color: c.textDark, size: AppIconSize.md),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Semantics(
          header: true,
          child: Text('username_confirm_title'.tr, style: AppType.pageTitle(context)),
        ),
        const SizedBox(height: AppSpace.sm),
        Text('username_confirm_note'.tr, style: AppType.body(context).copyWith(height: 1.55)),
        const SizedBox(height: AppSpace.md),
        _HandleCard(username: username),
        const SizedBox(height: AppSpace.md),
        AuthButton(
          label: 'username_confirm_keep'.tr,
          icon: Icons.check_rounded,
          iconBefore: true,
          loading: busy == UsernameConfirmAction.keep,
          enabled: idle,
          onPressed: onKeep,
        ),
        const SizedBox(height: AppSpace.sm),
        // the two other choices side by side, equal weight (each label may take two lines)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AuthTextAction(
                  icon: Icons.edit_rounded,
                  label: 'username_confirm_change'.tr,
                  onTap: idle ? onChange : null,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: _RemoveAction(busy: busy == UsernameConfirmAction.remove, onTap: idle ? onRemove : null)),
            ],
          ),
        ),
        if (error != null) ...[const SizedBox(height: AppSpace.sm), _ErrorLine(error!)],
        const SizedBox(height: AppSpace.xs),
        Center(
          child: TextButton(
            onPressed: idle ? onLater : null,
            style: TextButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: c.textMedium),
            child: Text('username_confirm_later'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
          ),
        ),
      ],
    );
  }

  Widget _change(BuildContext context) {
    final c = context.colors;
    final idle = busy == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IgnorePointer(ignoring: !idle, child: AppBackButton(onPressed: onBack)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                'username_confirm_change_title'.tr,
                style: AppType.pageTitle(context).copyWith(color: c.textDark),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        ?changeField,
        if (error != null) ...[const SizedBox(height: AppSpace.sm), _ErrorLine(error!)],
        const SizedBox(height: AppSpace.md),
        AuthButton(
          label: 'username_confirm_save'.tr,
          icon: Icons.check_rounded,
          iconBefore: true,
          loading: busy == UsernameConfirmAction.change,
          enabled: idle && canSave,
          onPressed: onSave,
        ),
      ],
    );
  }
}

class _HandleCard extends StatelessWidget {
  const _HandleCard({required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    // the handle is the sheet's one memorable line: ink on the peach block tint (no brand wash)
    final tone = AppBlockColors.of(context, AppBlockTone.peach);
    final ink = tone.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: AppRadius.cardAll,
        border: tone.border == null ? null : Border.all(color: tone.border!, width: AppBorder.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('username_confirm_current'.tr, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: tone.muted)),
          const SizedBox(height: AppSpace.xxs),
          // a handle always reads left to right, also inside Arabic
          Text(
            '@$username',
            textDirection: TextDirection.ltr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.section(context).copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

class _RemoveAction extends StatelessWidget {
  const _RemoveAction({required this.busy, this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // the kit's danger outline: paper, a danger hairline, the danger's readable ink (a twin of AuthTextAction)
    final ink = appInk(context, c.danger);
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.controlAll,
        side: BorderSide(color: c.danger.withValues(alpha: 0.45), width: AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(width: AppIconSize.sm, height: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: 2, color: ink))
                else
                  Icon(Icons.person_remove_outlined, size: AppIconSize.sm, color: ink),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(
                    'username_confirm_remove'.tr,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink, height: 1.25),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline_rounded, size: 16, color: c.danger),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(text, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.danger, height: 1.45))),
        ],
      ),
    );
  }
}

// ── The sheet ─────────────────────────────────────────────────────────────────

/// Shows the keep / change / remove sheet for [user]. True when the server took a choice; null / false = dismissed.
Future<bool?> showUsernameConfirmSheet(BuildContext context, {required UserModel user}) =>
    showAppSheet<bool>(context, (_) => _UsernameConfirmSheet(user: user));

class _UsernameConfirmSheet extends StatefulWidget {
  const _UsernameConfirmSheet({required this.user});

  final UserModel user;

  @override
  State<_UsernameConfirmSheet> createState() => _UsernameConfirmSheetState();
}

class _UsernameConfirmSheetState extends State<_UsernameConfirmSheet> {
  final _ctrl = TextEditingController();
  var _step = UsernameConfirmStep.choose;
  UsernameConfirmAction? _busy;
  String? _error;
  UsernameError? _fieldError;
  UsernameStatus _status = UsernameStatus.current;

  String get _current => widget.user.username ?? '';

  @override
  void initState() {
    super.initState();
    _ctrl.text = _current;
    _ctrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_rebuild);
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canSave {
    final n = UsernameRules.normalize(_ctrl.text);
    return n.isNotEmpty && n != _current && !_status.blocksSubmit;
  }

  Future<void> _run(UsernameConfirmAction action) async {
    if (_busy != null) return;
    HapticFeedback.lightImpact();
    final name = action == UsernameConfirmAction.change ? UsernameRules.normalize(_ctrl.text) : null;
    setState(() {
      _busy = action;
      _error = null;
      _fieldError = null;
    });
    final auth = context.read<MyAuthProvider>();
    try {
      final user = await UsernameConfirmApi.send(action, username: name);
      await auth.saveUserLocally(user);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showAppNotice(switch (action) {
        UsernameConfirmAction.keep => 'username_confirm_kept'.tr,
        UsernameConfirmAction.change => 'username_confirm_changed'.tr,
        UsernameConfirmAction.remove => 'username_confirm_removed'.tr,
      });
    } catch (e) {
      if (!mounted) return;
      final ex = ApiException.from(e);
      final fieldErr = name == null ? null : UsernameError.from(ex, submitted: name);
      setState(() {
        _busy = null;
        // taken / reserved / invalid: the field shows why, with the server's suggestions
        _fieldError = fieldErr;
        _error = fieldErr != null && !fieldErr.tooSoon ? null : apiErrorText(ex);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return UsernameConfirmContent(
      username: _current,
      step: _step,
      busy: _busy,
      error: _error,
      canSave: _canSave,
      changeField: _step == UsernameConfirmStep.change
          ? UsernameField(
              controller: _ctrl,
              currentUsername: _current,
              error: _fieldError,
              label: 'username_label'.tr,
              onStatusChanged: (s) => setState(() => _status = s),
            )
          : null,
      onKeep: () => _run(UsernameConfirmAction.keep),
      onRemove: () => _run(UsernameConfirmAction.remove),
      onChange: () => setState(() {
        _step = UsernameConfirmStep.change;
        _error = null;
      }),
      onBack: () => setState(() {
        _step = UsernameConfirmStep.choose;
        _error = null;
        _fieldError = null;
        _ctrl.text = _current;
      }),
      onSave: () => _run(UsernameConfirmAction.change),
      onLater: () => Navigator.of(context).pop(false),
    );
  }
}

// ── The one trigger ───────────────────────────────────────────────────────────

/// Offers the sheet once a role home is on screen (`topRouteObserver.didPush` calls [onRoute]); also re-checks when
/// the signed-in user changes while a home is on top (the start-up GET /auth/me may bring the flag after the home
/// was pushed from the cache).
class UsernameConfirmPrompt {
  UsernameConfirmPrompt._();

  static final instance = UsernameConfirmPrompt._();

  /// Route names of the role homes (main.dart `_router`).
  static const homeRoutes = {
    '/dashboard',
    '/teacher_dashboard',
    '/parent_dashboard',
    '/admin_dashboard',
    '/org_dashboard',
    '/org_member',
  };

  /// How long the home settles before the sheet comes up.
  static const settle = Duration(milliseconds: 1500);

  NavigatorState? _nav;
  MyAuthProvider? _auth;
  String? Function()? _topName;
  Timer? _timer;
  bool _open = false;
  final _asked = <int>{};

  /// [topName] reads the current top route's name (the observer's `currentRouteName`).
  void onRoute(Route<dynamic> route, String? Function() topName) {
    if (!homeRoutes.contains(route.settings.name)) return;
    final nav = route.navigator;
    if (nav == null) return;
    _nav = nav;
    _topName = topName;
    MyAuthProvider auth;
    try {
      auth = Provider.of<MyAuthProvider>(nav.context, listen: false);
    } catch (_) {
      return; // no auth provider above this navigator (tests, a nested navigator)
    }
    if (!identical(auth, _auth)) {
      _auth?.removeListener(_schedule);
      _auth = auth..addListener(_schedule);
    }
    _schedule();
  }

  void _schedule() {
    if (_open) return;
    _timer?.cancel();
    _timer = Timer(settle, _check);
  }

  Future<void> _check() async {
    final nav = _nav, auth = _auth;
    if (_open || nav == null || !nav.mounted || auth == null) return;
    if (!homeRoutes.contains(_topName?.call())) return; // something else is on top: wait for the next home
    if (!auth.isAuthenticated || ViewAsState.active || auth.accountSetup != null) return;
    if (!AppConnectivity.instance.isOnline) return;
    final user = auth.currentUser;
    if (user == null || _asked.contains(user.id)) return;
    SharedPreferences? prefs;
    int? snoozed;
    try {
      prefs = await SharedPreferences.getInstance();
      snoozed = prefs.getInt(usernamePromptKey(user.id));
    } catch (_) {}
    final due = usernamePromptDue(
      user: user,
      featureOff: AppConfig.disableList.contains(kUsernameFeatureKey),
      snoozedAtMs: snoozed,
      now: DateTime.now(),
    );
    if (!due || _open || !nav.mounted) return;
    final ctx = nav.overlay?.context;
    if (ctx == null || !ctx.mounted) return;
    _open = true;
    _asked.add(user.id);
    bool? done;
    try {
      done = await showUsernameConfirmSheet(ctx, user: user);
    } catch (_) {
    } finally {
      _open = false;
    }
    if (done != true) {
      try {
        await prefs?.setInt(usernamePromptKey(user.id), DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    }
  }
}
