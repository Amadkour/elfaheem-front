// lib/features/auth/username_field.dart
//
// The @username input used at sign-up and in the profile (D-071):
//
//   UsernameField(controller:, currentUsername:, error:, onStatusChanged:)
//
// "@" prefix, left-to-right even in Arabic, no autocorrect / suggestions. Every edit is checked against the mirrored
// rules at once; a valid name is sent to GET /auth/username/check after [UsernameField.debounce] (stale answers are
// dropped, an empty value is never sent). [currentUsername] (profile edit) counts as available. [error] is a
// USERNAME_* answer of the submit: it shows (with its suggestions) while the field still holds that name.
// [lockedUntil] (D-071 v2) is the end of the change cooldown: the field is read-only, says when the name can be
// changed again, and only offers to remove it (or to undo that).
//
// UsernameStatusView is the plain-values status line + suggestion chips (pumped by the layout harness,
// test/auth/username_field_layout_test.dart).
library;

import '../../design/app_tokens.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/app_time.dart';
import 'auth_widgets.dart' show SectionLabel, authInputDecoration, authFieldText, authDuration;
import 'username.dart';

/// Where a username field stands.
enum UsernameStatus {
  /// Nothing typed (and nothing to remove).
  empty,

  /// The field was emptied while the account has a username: saving removes it.
  cleared,

  /// Waiting for the debounce or the server.
  checking,
  available,

  /// The account's own username.
  current,

  /// The account's own username while the change cooldown runs: it can be kept or removed, not changed.
  locked,
  taken,
  reserved,
  invalid,

  /// The server could not be asked (older server, throttle, offline): the submit decides.
  unchecked;

  /// A non-empty value the form must not submit yet.
  bool get blocksSubmit =>
      this == checking || this == taken || this == reserved || this == invalid;

  bool get isError => this == taken || this == reserved || this == invalid;
}

class UsernameField extends StatefulWidget {
  const UsernameField({
    super.key,
    required this.controller,
    this.currentUsername,
    this.error,
    this.onStatusChanged,
    this.checker,
    this.label,
    this.enabled = true,
    this.debounce = const Duration(milliseconds: 450),
    this.lockedUntil,
  });

  final TextEditingController controller;

  /// The account's username (profile edit): typing it again is "current", not "taken".
  final String? currentUsername;

  /// A USERNAME_* error returned by the submit, shown while the field still holds [UsernameError.username].
  final UsernameError? error;

  final ValueChanged<UsernameStatus>? onStatusChanged;

  /// Replaces [UsernameApi.check] (tests).
  final Future<UsernameCheck> Function(String username)? checker;

  /// Label above the field (default: the translated "Username (optional)").
  final String? label;
  final bool enabled;
  final Duration debounce;

  /// The end of the change cooldown (UTC), or null. While set (and the account has a name) the field only keeps or
  /// removes [currentUsername].
  final DateTime? lockedUntil;

  @override
  State<UsernameField> createState() => _UsernameFieldState();
}

class _UsernameFieldState extends State<UsernameField> {
  Timer? _timer;
  int _seq = 0;
  String? _lastNorm;
  UsernameStatus _status = UsernameStatus.empty;
  UsernameProblem? _problem;
  String? _serverMessage;
  List<String> _suggestions = const [];

  String get _current => UsernameRules.normalize(widget.currentUsername ?? '');

  bool get _locked => widget.lockedUntil != null && _current.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _evaluate(notify: false);
  }

  @override
  void didUpdateWidget(covariant UsernameField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
    if (old.error != widget.error ||
        old.currentUsername != widget.currentUsername ||
        old.lockedUntil != widget.lockedUntil) {
      _lastNorm = null;
      _evaluate(notify: false);
      // the parent is building: tell it after the frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onStatusChanged?.call(_status);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() => _evaluate(notify: true);

  void _set(
    UsernameStatus s, {
    UsernameProblem? problem,
    String? message,
    List<String> suggestions = const [],
    bool notify = true,
  }) {
    final changed = s != _status;
    _status = s;
    _problem = problem;
    _serverMessage = message;
    _suggestions = suggestions;
    if (mounted && notify) setState(() {});
    if (changed && notify) widget.onStatusChanged?.call(s);
  }

  /// Decides what the current text means; a valid, new name schedules the server check.
  void _evaluate({required bool notify}) {
    final norm = UsernameRules.normalize(widget.controller.text);
    if (norm == _lastNorm) return; // a cursor move, not an edit
    _lastNorm = norm;
    _timer?.cancel();
    final seq = ++_seq;

    if (norm.isEmpty) {
      _set(_current.isEmpty ? UsernameStatus.empty : UsernameStatus.cleared, notify: notify);
      return;
    }
    if (norm == _current) {
      _set(_locked ? UsernameStatus.locked : UsernameStatus.current, notify: notify);
      return;
    }
    final err = widget.error;
    if (err != null && err.username == norm && !err.tooSoon) {
      _set(
        err.taken
            ? UsernameStatus.taken
            : err.reserved
                ? UsernameStatus.reserved
                : UsernameStatus.invalid,
        problem: UsernameRules.problemOf(norm),
        message: err.message,
        suggestions: err.suggestions,
        notify: notify,
      );
      return;
    }
    final problem = UsernameRules.problemOf(norm);
    if (problem != null && problem != UsernameProblem.reserved) {
      _set(UsernameStatus.invalid, problem: problem, notify: notify);
      return;
    }
    // reserved: said at once, the server is still asked for its suggestions
    _set(
      problem == UsernameProblem.reserved ? UsernameStatus.reserved : UsernameStatus.checking,
      problem: problem,
      notify: notify,
    );
    _timer = Timer(widget.debounce, () => _check(norm, seq));
  }

  Future<void> _check(String norm, int seq) async {
    final check = widget.checker ?? UsernameApi.check;
    UsernameCheck r;
    try {
      r = await check(norm);
    } catch (_) {
      r = UsernameCheck.unchecked(norm);
    }
    if (!mounted || seq != _seq) return; // the text changed meanwhile
    final localReserved = _problem == UsernameProblem.reserved;
    if (!r.checked) {
      _set(localReserved ? UsernameStatus.reserved : UsernameStatus.unchecked, problem: _problem);
    } else if (r.available) {
      _set(UsernameStatus.available);
    } else if (r.reserved || localReserved) {
      _set(UsernameStatus.reserved, problem: UsernameProblem.reserved, suggestions: r.suggestions);
    } else if (r.invalid) {
      _set(UsernameStatus.invalid, problem: UsernameRules.problemOf(norm), message: r.message);
    } else {
      _set(UsernameStatus.taken, suggestions: r.suggestions);
    }
  }

  void _pick(String suggestion) {
    final s = UsernameRules.normalize(suggestion);
    widget.controller.value = TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final norm = UsernameRules.normalize(widget.controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionLabel(label: widget.label ?? 'username_optional'.tr),
        const SizedBox(height: AppSpace.xs),
        // the whole box is LTR: "@" then the name, also in Arabic
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            readOnly: _locked,
            keyboardType: TextInputType.text,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            inputFormatters: [
              const UsernameInputFormatter(),
              LengthLimitingTextInputFormatter(UsernameRules.maxLength),
            ],
            autofillHints: const [AutofillHints.newUsername],
            textInputAction: TextInputAction.next,
            style: authFieldText(context),
            cursorColor: c.primary,
            decoration: authInputDecoration(
              context,
              hint: 'username_hint'.tr,
              icon: Icons.alternate_email_rounded,
              suffix: _suffix(c),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        UsernameStatusView(
          status: _status,
          username: norm,
          problem: _problem,
          serverMessage: _serverMessage,
          suggestions: _suggestions,
          onSuggestion: widget.enabled ? _pick : null,
          lockedUntil: widget.lockedUntil,
        ),
        if (_locked && widget.enabled) ...[
          const SizedBox(height: AppSpace.xxs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _pick(norm.isEmpty ? _current : ''),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 44),
                foregroundColor: norm.isEmpty ? c.primary : c.danger,
              ),
              icon: Icon(norm.isEmpty ? Icons.undo_rounded : Icons.person_remove_outlined, size: 18),
              label: Text(
                norm.isEmpty ? 'username_keep_current'.tr : 'username_remove'.tr,
                style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: norm.isEmpty ? c.primary : c.danger),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget? _suffix(ThemeConfigProvider c) {
    final icon = _suffixIcon(c);
    if (icon == null) return null;
    return AnimatedSwitcher(
      duration: authDuration(context, 200),
      transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
      child: KeyedSubtree(key: ValueKey(_status), child: icon),
    );
  }

  Widget? _suffixIcon(ThemeConfigProvider c) => switch (_status) {
        UsernameStatus.checking => Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
            ),
          ),
        UsernameStatus.available || UsernameStatus.current =>
          Icon(Icons.check_circle_rounded, size: 20, color: c.success),
        UsernameStatus.locked => Icon(Icons.lock_clock_outlined, size: 20, color: c.textLight),
        UsernameStatus.taken || UsernameStatus.reserved || UsernameStatus.invalid =>
          Icon(Icons.error_outline_rounded, size: 20, color: c.danger),
        _ => null,
      };
}

/// The status line under a username field and, for a taken / reserved name, the suggestions to tap. Plain values.
class UsernameStatusView extends StatelessWidget {
  const UsernameStatusView({
    super.key,
    required this.status,
    this.username = '',
    this.problem,
    this.serverMessage,
    this.suggestions = const [],
    this.onSuggestion,
    this.lockedUntil,
  });

  final UsernameStatus status;

  /// The normalized name the line talks about.
  final String username;

  /// The rule that failed (invalid), when the app knows it.
  final UsernameProblem? problem;

  /// The server's sentence, used for an invalid name the app's rules let through.
  final String? serverMessage;
  final List<String> suggestions;
  final ValueChanged<String>? onSuggestion;

  /// [UsernameStatus.locked]: when the name can be changed again (UTC).
  final DateTime? lockedUntil;

  String _text() {
    switch (status) {
      case UsernameStatus.empty:
        return 'username_rules'.tr;
      case UsernameStatus.cleared:
        return 'username_will_remove'.tr;
      case UsernameStatus.checking:
        return 'username_checking'.tr;
      case UsernameStatus.available:
        return 'username_available'.tr;
      case UsernameStatus.current:
        return 'username_current'.tr;
      case UsernameStatus.locked:
        final at = lockedUntil;
        return at == null
            ? 'username_change_locked'.tr
            : 'username_change_again_on'.tr.replaceAll('{date}', AppTime.date(at));
      case UsernameStatus.taken:
        return 'username_taken'.tr;
      case UsernameStatus.reserved:
        return 'username_reserved'.tr;
      case UsernameStatus.invalid:
        final p = problem;
        if (p != null) return UsernameRules.problemKey(p).tr;
        return serverMessage ?? 'username_invalid'.tr;
      case UsernameStatus.unchecked:
        return 'username_unchecked'.tr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (IconData icon, Color color) = switch (status) {
      UsernameStatus.available || UsernameStatus.current => (Icons.check_circle_rounded, c.success),
      UsernameStatus.taken || UsernameStatus.reserved || UsernameStatus.invalid => (Icons.error_outline_rounded, c.danger),
      UsernameStatus.cleared => (Icons.remove_circle_outline_rounded, c.warning),
      UsernameStatus.checking => (Icons.hourglass_top_rounded, c.textLight),
      UsernameStatus.locked => (Icons.lock_clock_outlined, c.textMedium),
      _ => (Icons.info_outline_rounded, c.textLight),
    };
    final showName = username.isNotEmpty &&
        (status == UsernameStatus.available || status == UsernameStatus.taken);
    final chips = status == UsernameStatus.taken || status == UsernameStatus.reserved
        ? suggestions
        : const <String>[];

    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    if (showName) ...[
                      // a left-to-right mark first keeps the "@" before the name inside an Arabic sentence
                      TextSpan(
                        text: '${String.fromCharCode(0x200E)}@$username ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                    TextSpan(text: _text()),
                  ]),
                  style: AppType.meta(context).copyWith(fontWeight: FontWeight.w500, color: color, height: 1.45),
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('username_try'.tr, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
                for (final s in chips)
                  _SuggestionChip(
                    label: s,
                    onTap: onSuggestion == null ? null : () => onSuggestion!(s),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = c.isDark ? c.primaryLight : c.primary;
    return Material(
      color: c.primary.withValues(alpha: c.isDark ? 0.16 : 0.06),
      shape: StadiumBorder(side: BorderSide(color: c.primary.withValues(alpha: c.isDark ? 0.40 : 0.22))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: TextDirection.ltr,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: ink),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(
                    '@$label',
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: ink, height: 1.2),
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
