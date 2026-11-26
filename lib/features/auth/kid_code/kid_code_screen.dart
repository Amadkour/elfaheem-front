// features/auth/kid_code/kid_code_screen.dart
//
// The child signs in with the code the parent made (Stu1Auth?screen=kidcode, state=found, state=pass; WP7):
//   1. enter   six boxes (3 + 3), the code is looked up; a wrong code shakes the boxes (M15)
//   2. found   "is this your account?": the child's initial, name, grade and the parent's name; yes / not me
//   3. pass    choose a password (strength bar), then the code is claimed and the session starts
// Kill switch `auth.child_code` (the login entry tile and this page's BasePage key).
//
//   KidCodeScreen()                         the page (state, calls, navigation)
//   KidCodeEnterView / KidCodeFoundView / KidCodePassView   plain values, for the layout harness and goldens
//   KidCodeEntryTile(onTap:)                the "got a code from your parent?" tile of the login card
//   KidCodeBoxes(controller:)               the six-box code input
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appInk;
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../auth_shell.dart';
import '../auth_widgets.dart';
import 'kid_code_api.dart';

enum KidCodeStep { enter, found, pass }

/// The child-code sign-in page.
class KidCodeScreen extends StatefulWidget {
  const KidCodeScreen({super.key, this.api});

  final KidCodeApi? api;

  @override
  State<KidCodeScreen> createState() => _KidCodeScreenState();
}

class _KidCodeScreenState extends State<KidCodeScreen> {
  late final KidCodeApi _api = widget.api ?? KidCodeApi();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _shake = AppFeedbackController();
  KidCodeStep _step = KidCodeStep.enter;
  KidCodeAccount? _account;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _shake.dispose();
    super.dispose();
  }

  String _errorText(Object e) {
    final x = ApiException.from(e);
    if (x.code == 'child_code_invalid') return 'sa_kid_code_wrong'.tr;
    return x.message;
  }

  Future<void> _lookup() async {
    if (kidCodeDigits(_code.text).length != 6 || _busy) {
      _shake.shake();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final a = await _api.lookup(_code.text);
      if (!mounted) return;
      setState(() {
        _account = a;
        _step = KidCodeStep.found;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
      _shake.shake();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notMe() => setState(() {
        _account = null;
        _code.clear();
        _error = null;
        _step = KidCodeStep.enter;
      });

  Future<void> _claim() async {
    if (_password.text.length < 8 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<MyAuthProvider>();
    final nav = Navigator.of(context);
    try {
      final session = await _api.claim(_code.text, _password.text);
      await auth.completeSession(session);
      TextInput.finishAutofillContext();
      auth.loadCachedUser();
      final user = session['user'];
      final username = user is Map ? user['username']?.toString() : null;
      if (username != null && username.isNotEmpty) {
        showAppNotice('sa_kid_username_notice'.tr.replaceAll('{username}', '@$username'));
      }
      nav.pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
    } catch (e) {
      if (!mounted) return;
      final x = ApiException.from(e);
      setState(() {
        _error = _errorText(e);
        // a code that died meanwhile sends the child back to the first step
        if (x.code == 'child_code_invalid') {
          _step = KidCodeStep.enter;
          _code.clear();
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, sub, glyph, tone) = switch (_step) {
      KidCodeStep.enter => ('sa_kid_enter_title'.tr, 'sa_kid_enter_sub'.tr, Icons.key_rounded, null),
      KidCodeStep.found => ('sa_kid_found_title'.tr, 'sa_kid_found_sub'.tr, null, null),
      KidCodeStep.pass => (
          'sa_kid_pass_title'.tr,
          'sa_kid_pass_sub'.tr,
          Icons.lock_outline_rounded,
          context.colors.kit.accent(AppAccent.mint),
        ),
    };
    return PopScope(
      canPop: _step == KidCodeStep.enter,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _notMe();
      },
      child: AuthScaffold(
        pageKey: const ValueKey(kKidCodeFeature),
        kicker: 'sa_kid_kicker'.tr,
        heroTitle: 'sa_kid_hero'.tr,
        squiggle: 'sa_kid_squiggle'.tr,
        title: title,
        subtitle: sub,
        glyph: glyph,
        glyphTone: tone,
        legalLinks: _step == KidCodeStep.pass,
        builder: (context, wide) => AppWipeSwitcher(
          switchKey: _step,
          child: switch (_step) {
            KidCodeStep.enter => KidCodeEnterView(
                controller: _code,
                feedback: _shake,
                error: _error,
                busy: _busy,
                onSubmit: _lookup,
                onBack: () => Navigator.of(context).maybePop(),
              ),
            KidCodeStep.found => KidCodeFoundView(account: _account!, onYes: () => setState(() => _step = KidCodeStep.pass), onNo: _notMe),
            KidCodeStep.pass => KidCodePassView(controller: _password, error: _error, busy: _busy, onSubmit: _claim),
          },
        ),
      ),
    );
  }
}

// ── 1. enter ─────────────────────────────────────────────────────────────────

class KidCodeEnterView extends StatelessWidget {
  const KidCodeEnterView({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.feedback,
    this.error,
    this.busy = false,
    this.onBack,
  });

  final TextEditingController controller;
  final AppFeedbackController? feedback;
  final String? error;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget boxes = KidCodeBoxes(controller: controller, error: error != null, onCompleted: onSubmit);
    if (feedback != null) boxes = AppFeedback(controller: feedback!, borderRadius: AppRadius.controlAll, child: boxes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        boxes,
        const SizedBox(height: AppSpace.md),
        AnimatedSwitcher(
          duration: AppMotion.of(context).fast,
          child: Text(
            error ?? 'sa_kid_enter_hint'.tr,
            key: ValueKey(error),
            textAlign: TextAlign.center,
            style: AppType.label(context).copyWith(
              color: error != null ? c.kit.error.ink : c.textMedium,
              fontWeight: error != null ? FontWeight.w600 : null,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => AuthButton(
            label: 'sa_kid_enter_go'.tr,
            loading: busy,
            onPressed: onSubmit,
          ),
        ),
        if (onBack != null) ...[
          const SizedBox(height: AppSpace.xs),
          _CardLink(label: 'sa_kid_back_login'.tr, onTap: onBack!),
        ],
      ],
    );
  }
}

/// A centred link in the area's ink (48 dp).
class _CardLink extends StatelessWidget {
  const _CardLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = appInk(context, AppAreaScope.of(context).ink);
    return Center(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(AppTouch.min, AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          foregroundColor: ink,
        ),
        child: Text(label, textAlign: TextAlign.center, style: AppType.bodyStrong(context).copyWith(color: ink)),
      ),
    );
  }
}

/// Six digit boxes in two groups of three. One invisible field under them takes the typing (paste, autofill, the
/// number pad); Arabic-Indic digits are accepted.
class KidCodeBoxes extends StatefulWidget {
  const KidCodeBoxes({super.key, required this.controller, this.error = false, this.onCompleted, this.autofocus = true});

  final TextEditingController controller;
  final bool error;
  final VoidCallback? onCompleted;
  final bool autofocus;

  @override
  State<KidCodeBoxes> createState() => _KidCodeBoxesState();
}

class _KidCodeBoxesState extends State<KidCodeBoxes> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const gap = AppSpace.xs;
      const groupGap = AppSpace.md;
      final w = ((box.maxWidth - 4 * gap - groupGap) / 6).clamp(0.0, AppTouch.primary);
      final h = AppTouch.primary + AppSpace.xs;
      return ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final digits = kidCodeDigits(widget.controller.text);
          final row = Directionality(
            // a code reads left to right in both languages
            textDirection: TextDirection.ltr,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < 6; i++) ...[
                if (i == 3) const SizedBox(width: groupGap) else if (i > 0) const SizedBox(width: gap),
                SizedBox(
                  width: w,
                  child: AuthOtpBox(
                    height: h,
                    error: widget.error,
                    filled: i < digits.length,
                    focused: _focus.hasFocus && i == digits.length.clamp(0, 5),
                    child: Center(
                      child: Text(
                        i < digits.length ? appDigits(digits[i]) : '',
                        style: AuthOtpBox.digitStyle(context),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          );
          return Stack(children: [
            ExcludeSemantics(child: row),
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                alwaysIncludeSemantics: true,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  showCursor: false,
                  enableInteractiveSelection: false,
                  inputFormatters: [_SixDigits()],
                  onChanged: (v) {
                    if (kidCodeDigits(v).length == 6) widget.onCompleted?.call();
                  },
                  onSubmitted: (_) => widget.onCompleted?.call(),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    labelText: 'sa_kid_code_label'.tr,
                  ),
                ),
              ),
            ),
          ]);
        },
      );
    });
  }
}

/// Keeps at most six Latin digits.
class _SixDigits extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = kidCodeDigits(newValue.text);
    if (d.length > 6) d = d.substring(0, 6);
    return TextEditingValue(text: d, selection: TextSelection.collapsed(offset: d.length));
  }
}

// ── 2. found ─────────────────────────────────────────────────────────────────

class KidCodeFoundView extends StatelessWidget {
  const KidCodeFoundView({super.key, required this.account, required this.onYes, required this.onNo});

  final KidCodeAccount account;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppPop(
          child: Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.cardWide),
              border: Border.all(color: set.a, width: AppBorder.focus),
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [c.cardBg, set.tint],
              ),
            ),
            child: Row(children: [
              ExcludeSemantics(
                child: Container(
                  width: AppTouch.primary + AppSpace.xs,
                  height: AppTouch.primary + AppSpace.xs,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: set.button),
                  child: Text(account.initial, style: AppType.headline(context).copyWith(color: set.btnFg)),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(account.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                  if (account.grade.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xxs),
                    Text(account.grade, style: AppType.label(context).copyWith(color: c.textMedium)),
                  ],
                  if (account.parentName.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Row(children: [
                      Icon(Icons.people_outline_rounded, size: AppIconSize.sm, color: set.ink),
                      const SizedBox(width: AppSpace.xxs),
                      Flexible(
                        child: Text(
                          'sa_kid_parent'.tr.replaceAll('{name}', account.parentName),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label(context).copyWith(color: set.ink, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(width: AppSpace.sm),
              ExcludeSemantics(
                child: Container(
                  width: AppIconSize.xl,
                  height: AppIconSize.xl,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: set.ink),
                  child: Icon(Icons.check_rounded, size: AppIconSize.md, color: c.cardBg),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        AuthButton(label: 'sa_kid_yes'.tr, onPressed: onYes),
        const SizedBox(height: AppSpace.xs),
        _CardLink(label: 'sa_kid_not_me'.tr, onTap: onNo),
      ],
    );
  }
}

// ── 3. pass ──────────────────────────────────────────────────────────────────

/// 0..4 like the sign-up page: 8+ characters, a capital, a digit, 10+ characters.
int kidPasswordStrength(String p) {
  if (p.isEmpty) return 0;
  var s = 0;
  if (p.length >= 8) s++;
  if (RegExp(r'[A-Z]').hasMatch(p)) s++;
  if (RegExp(r'\d').hasMatch(p)) s++;
  if (p.length >= 10) s++;
  return s;
}

class KidCodePassView extends StatelessWidget {
  const KidCodePassView({super.key, required this.controller, required this.onSubmit, this.error, this.busy = false});

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final String? error;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconPasswordField(
            controller: controller,
            label: 'password'.tr,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: AppSpace.sm),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final s = kidPasswordStrength(controller.text);
              return AuthPasswordStrength(
                strength: s,
                color: switch (s) { 1 => c.danger, 2 => c.warning, 3 || 4 => c.kit.ok.color, _ => c.divider },
                label: switch (s) {
                  1 => 'pw_strength_weak'.tr,
                  2 => 'pw_strength_fair'.tr,
                  3 => 'pw_strength_strong'.tr,
                  4 => 'pw_strength_very_strong'.tr,
                  _ => '',
                },
              );
            },
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(error!, style: AppType.label(context).copyWith(color: c.kit.error.ink, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: AppSpace.lg),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => AuthButton(
              label: 'sa_kid_pass_go'.tr,
              loading: busy,
              onPressed: controller.text.length >= 8 ? onSubmit : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── the login card's entry ───────────────────────────────────────────────────

/// "Got a code from your parent?": a tinted tile with the key in a paper box and a chevron to the reading end.
class KidCodeEntryTile extends StatelessWidget {
  const KidCodeEntryTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final radius = BorderRadius.circular(AppRadius.tile);
    return AppJelly(
      wide: true,
      child: Material(
        color: set.tint,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: Color.lerp(set.tint, set.a, .35)!, width: AppBorder.strong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Row(children: [
              Container(
                width: AppTouch.min + AppSpace.xs,
                height: AppTouch.min + AppSpace.xxs,
                decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.nav)),
                child: Icon(Icons.key_rounded, size: AppIconSize.lg, color: set.ink),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('sa_kid_entry_title'.tr, style: AppType.tileTitle(context)),
                  const SizedBox(height: AppSpace.xxs),
                  Text('sa_kid_entry_sub'.tr, style: AppType.meta(context).copyWith(color: c.textMedium)),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: set.ink),
            ]),
          ),
        ),
      ),
    );
  }
}
