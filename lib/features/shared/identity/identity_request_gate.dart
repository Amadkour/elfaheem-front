// The student's identifier dialog (D-150): a teacher asked for a value the exam identifies students by (national ID,
// academic ID, phone, a custom field) and this student has none yet → a friendly dialog on app open and on every
// resume, one request at a time: "Your teacher needs your National ID for the upcoming exam. Please enter it."
//
// It sits next to DataLabGate in the student shell (inside it, so a blocking Data Lab screen stays on top) and, like
// it, never blocks the app when the check fails. "Later" hides it until the app comes back to the front. A push tap
// (module `identity_requests`) goes through AppNavigator → [openIdentityRequestsFromLink]. Kill switch
// `exam.identifiers` hides all of it. Pure part: identity_requests.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import 'identity_requests.dart';

class IdentityRequestGate extends StatefulWidget {
  const IdentityRequestGate({super.key, required this.child, this.api, this.enabled});

  final Widget child;
  final IdentityApi? api;

  /// Who is asked (default: a signed-in student). The kill switch is checked on top of it.
  final bool Function(BuildContext context)? enabled;

  static final ValueNotifier<int> _wake = ValueNotifier(0);

  /// Check again now and show what is pending (a push tap, a link).
  static void wake() => _wake.value++;

  @override
  State<IdentityRequestGate> createState() => _IdentityRequestGateState();
}

/// The `identity_requests` module of a push / notification tap: back to the shell's home and the dialog on top.
Future<void> openIdentityRequestsFromLink(NavigatorState root) async {
  root.popUntil((r) => r.isFirst);
  AppShellNav.popVisibleToRoot();
  IdentityRequestGate.wake();
}

class _IdentityRequestGateState extends State<IdentityRequestGate> with WidgetsBindingObserver {
  late final IdentityApi _api = widget.api ?? IdentityApi();
  List<IdentityRequestItem> _items = const [];
  bool _checking = false;
  bool _later = false;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    IdentityRequestGate._wake.addListener(_onWake);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    IdentityRequestGate._wake.removeListener(_onWake);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _later = false;
      _check();
    }
  }

  void _onWake() {
    _later = false;
    _check();
  }

  bool get _off => AppConfig.disableList.contains(kExamIdentifiersFeatureKey);

  bool _isAsked() {
    final f = widget.enabled;
    if (f != null) return f(context);
    try {
      final auth = context.read<MyAuthProvider>();
      return auth.isAuthenticated && auth.currentUser?.role == 'student';
    } catch (_) {
      return false;
    }
  }

  Future<void> _check() async {
    if (_checking || !mounted || _off || !_isAsked()) return;
    _checking = true;
    try {
      final r = await _api.pending();
      if (!mounted) return;
      if (!r.ok) {
        // never block the app because a check failed — but say why in the log
        debugPrint('[IdentityRequestGate] pending check failed: ${r.status} ${r.code ?? r.message}');
        return;
      }
      setState(() {
        _items = IdentityRequestItem.listFrom(r.map);
        _shown = 0;
      });
    } finally {
      _checking = false;
    }
  }

  void _done(Set<int> closed) {
    setState(() {
      _items = [for (final x in _items) if (!closed.contains(x.id)) x];
      _shown++;
    });
    if (_items.isEmpty) showAppNotice(t('شكرًا، تم الحفظ', 'Thank you — saved'));
  }

  @override
  Widget build(BuildContext context) {
    final show = !_later && !_off && _items.isNotEmpty;
    return Stack(children: [
      widget.child,
      if (show)
        Positioned.fill(
          child: IdentityRequestOverlay(
            key: ValueKey('identity-request-${_items.first.id}'),
            item: _items.first,
            index: _shown + 1,
            total: _shown + _items.length,
            api: _api,
            onDone: _done,
            onGone: () {
              setState(() => _items = _items.sublist(1));
              _check();
            },
            onLater: () => setState(() => _later = true),
          ),
        ),
    ]);
  }
}

/// The modal layer: a scrim and the card, the typed value and the round trip.
class IdentityRequestOverlay extends StatefulWidget {
  const IdentityRequestOverlay({
    super.key,
    required this.item,
    required this.api,
    required this.onDone,
    required this.onGone,
    required this.onLater,
    this.index = 1,
    this.total = 1,
  });

  final IdentityRequestItem item;
  final IdentityApi api;

  /// The request ids the answer closed.
  final ValueChanged<Set<int>> onDone;
  final VoidCallback onGone;
  final VoidCallback onLater;
  final int index;
  final int total;

  @override
  State<IdentityRequestOverlay> createState() => _IdentityRequestOverlayState();
}

class _IdentityRequestOverlayState extends State<IdentityRequestOverlay> {
  final _ctl = TextEditingController();
  String? _error;

  /// The text the error is about: editing it clears the error.
  String _errorText = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() {
      if (_error != null && _ctl.text != _errorText) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final f = widget.item.field;
    final rule = identityRuleBroken(f, _ctl.text);
    if (rule != null) {
      setState(() {
        _error = identityRuleText(rule, f);
        _errorText = _ctl.text;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.api.submit(widget.item.id, _ctl.text);
    if (!mounted) return;
    if (r.ok) {
      widget.onDone(closedIds(r, widget.item.id));
      return;
    }
    if (identityRequestGone(r)) {
      widget.onGone();
      return;
    }
    setState(() {
      _busy = false;
      _error = identitySubmitError(r, f);
      _errorText = _ctl.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: pageDirection,
      child: PopScope(
        canPop: false,
        child: Stack(children: [
          // the kit's warm scrim (the dialogs' and sheets')
          Positioned.fill(child: ModalBarrier(dismissible: false, color: appScrimColor(context))),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: IdentityRequestCard(
                    item: widget.item,
                    controller: _ctl,
                    error: _error,
                    busy: _busy,
                    index: widget.index,
                    total: widget.total,
                    onSubmit: _submit,
                    onLater: widget.onLater,
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The dialog's card (plain values; under the layout harness).
class IdentityRequestCard extends StatelessWidget {
  const IdentityRequestCard({
    super.key,
    required this.item,
    required this.controller,
    required this.onSubmit,
    required this.onLater,
    this.onChanged,
    this.error,
    this.busy = false,
    this.index = 1,
    this.total = 1,
  });

  final IdentityRequestItem item;
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onLater;
  final VoidCallback? onChanged;
  final String? error;
  final bool busy;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = item.field;
    final hint = identityHint(f);
    final ltr = f.kind != 'text';
    final due = item.dueUtc;
    final meta = [
      if (item.examTitle != null) item.examTitle!,
      if (due != null) item.paper ? t('قبل ${AppTime.date(due)}', 'Before ${AppTime.date(due)}') : t('حتى ${AppTime.date(due)}', 'By ${AppTime.date(due)}'),
    ];
    final tone = AppBlockColors.of(context, AppBlockTone.emerald);
    // paper at the dialog radius, the modal lift (it floats over the scrim), the editorial title beside a tinted mark
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          boxShadow: AppElevation.of(context, 4),
        ),
        child: Material(
        color: c.cardBg,
        elevation: 0,
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: AppTouch.min,
                height: AppTouch.min,
                decoration: BoxDecoration(color: tone.surface, shape: BoxShape.circle),
                child: Icon(f.kind == 'phone' ? Icons.phone_iphone_rounded : (f.kind == 'email' ? Icons.alternate_email_rounded : Icons.badge_outlined),
                    color: tone.accentInk(c.primary), size: AppIconSize.lg),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(t('مطلوب: ${f.labelAr}', '${f.labelEn} needed'),
                      style: AppType.pageTitle(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (total > 1) AppBadgePill(t('$index من $total', '$index of $total')),
            ]),
            const SizedBox(height: AppSpace.md),
            Text(item.message, style: AppType.body(context).copyWith(color: c.textDark, height: 1.55)),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text(meta.join(' · '), style: AppType.meta(context)),
            ],
            const SizedBox(height: AppSpace.md),
            TextField(
              key: const ValueKey('identity.value'),
              controller: controller,
              autofocus: true,
              readOnly: busy, // not disabled: the field keeps its focus (and the phone its keyboard) during the round trip
              keyboardType: identityKeyboard(f.kind),
              textDirection: ltr ? TextDirection.ltr : null,
              textInputAction: TextInputAction.done,
              onChanged: (_) => onChanged?.call(),
              onSubmitted: (_) => onSubmit(),
              style: appFieldTextStyle(context).copyWith(fontWeight: FontWeight.w600),
              // the kit's well; its label is floated inside so the dialog stays one block of reading
              decoration: appFieldDecoration(
                context,
                helper: hint.isEmpty ? null : hint,
                errorText: error,
              ).copyWith(labelText: f.label, errorMaxLines: 3),
            ),
            const SizedBox(height: AppSpace.md),
            AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: busy, onPressed: onSubmit),
            const SizedBox(height: AppSpace.xxs),
            TextButton(
              key: const ValueKey('identity.later'),
              onPressed: busy ? null : onLater,
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
              child: Text(t('لاحقًا', 'Later')),
            ),
          ]),
        ),
      ),
      ),
    );
  }
}
