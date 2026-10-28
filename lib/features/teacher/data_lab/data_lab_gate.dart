// lib/features/teacher/data_lab/data_lab_gate.dart
// Student side of the Data Lab — screens that stay on top of the app until they are done:
//   1. account setup  an account a teacher created by importing a sheet: choose a password, add what is missing
//                     (e-mail — verified by a 4-digit code — phone, name) → "Your account is verified"
//   2. forms          the teacher's questions, ALL questions of a form on ONE screen; answers go into the sheet
//
// Wrap the student's home once (e.g. in the student dashboard):
//     DataLabGate(child: StudentDashboardScreen())
// It checks when the app opens and every time it comes back to the foreground. Teachers / admins pass straight
// through. Nothing here ever blocks the app when a check fails.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:provider/provider.dart';

import 'data_lab_api.dart';
import 'data_lab_models.dart';
import 'data_lab_widgets.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/design/app_icons.dart';

String _tr(String key, String fallback) => dlTr(key, fallback);

class DataLabGate extends StatefulWidget {
  const DataLabGate({super.key, required this.child});

  final Widget child;

  @override
  State<DataLabGate> createState() => _DataLabGateState();
}

class _DataLabGateState extends State<DataLabGate> with WidgetsBindingObserver {
  final _api = DataLabApi();
  Map<String, dynamic>? _setup; // account setup still to do
  List<DlPendingForm> _forms = [];
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    final auth = context.read<MyAuthProvider>();
    if (auth.currentUser?.role != 'student') return;
    // Straight from the login answer: shown at once, even before (or without) the request below.
    if (auth.accountSetup != null && _setup == null) setState(() => _setup = auth.accountSetup);
    _checking = true;
    try {
      Map<String, dynamic>? setup = _setup;
      try {
        final s = await _api.accountSetup();
        setup = s['required'] == true ? s : null;
        if (setup == null) auth.accountSetup = null;
      } catch (e) {
        // Keep what the login said; never block the app only because a check failed — but say why.
        debugPrint('[DataLabGate] account-setup check failed: ${e is ApiException ? '${e.statusCode} ${e.message}' : e}');
      }
      List<DlPendingForm> forms = _forms;
      if (setup == null) {
        try {
          forms = DlPendingForm.group(await _api.myPendingRequests());
        } catch (e) {
          debugPrint('[DataLabGate] pending questions check failed: ${e is ApiException ? '${e.statusCode} ${e.message}' : e}');
        }
      }
      if (mounted) {
        setState(() {
          _setup = setup;
          _forms = forms;
        });
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget? overlay;
    if (_setup != null) {
      overlay = AccountSetupScreen(
        key: const ValueKey('dl-setup'),
        state: _setup!,
        onDone: () {
          context.read<MyAuthProvider>().accountSetup = null;
          setState(() => _setup = null);
          _check(); // then the teacher's questions, if any
        },
      );
    } else if (_forms.isNotEmpty) {
      overlay = DataLabFormScreen(
        key: ValueKey('dl-form-${_forms.first.key}'),
        form: _forms.first,
        remaining: _forms.length,
        onAnswered: () => setState(() => _forms = _forms.sublist(1)),
        onChanged: _check, // a question was closed meanwhile → refresh
      );
    }
    return Stack(children: [
      widget.child,
      if (overlay != null) Positioned.fill(child: PopScope(canPop: false, child: overlay)),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared look of the blocking screens
// ═════════════════════════════════════════════════════════════════════════════

class _GatePage extends StatelessWidget {
  const _GatePage({required this.icon, required this.title, required this.subtitle, required this.children, this.footer});

  final IconData icon;
  final String title, subtitle;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection: pageDirection,
      child: Material(
        color: c.background,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [c.primary, c.primaryDark]),
                      boxShadow: c.primaryShadow,
                    ),
                    child: Icon(icon, color: c.onHero, size: 42),
                  ),
                  const SizedBox(height: 20),
                  Text(title, textAlign: TextAlign.center, style: dlText(21, w: FontWeight.w800, c: c.textDark)),
                  const SizedBox(height: 8),
                  Text(subtitle, textAlign: TextAlign.center, style: dlText(13, c: c.textMedium, h: 1.55)),
                  const SizedBox(height: 22),
                  ...children,
                  ?footer,
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _errText(Object e) => apiErrorText(ApiException.from(e));

// ═════════════════════════════════════════════════════════════════════════════
// 1. Account setup
// ═════════════════════════════════════════════════════════════════════════════

class AccountSetupScreen extends StatefulWidget {
  const AccountSetupScreen({super.key, required this.state, required this.onDone});

  /// GET /data-lab/me/account-setup
  final Map<String, dynamic> state;
  final VoidCallback onDone;

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  final _api = DataLabApi();
  late final _name = TextEditingController(text: '${widget.state['name'] ?? ''}');
  late final _email = TextEditingController(text: '${widget.state['email'] ?? ''}');
  late final _phone = TextEditingController(text: '${widget.state['phone'] ?? ''}');
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _code = TextEditingController();
  late String _step = (widget.state['verify_email'] as String?) != null ? 'code' : 'details'; // details | code | done
  late String _codeEmail = '${widget.state['verify_email'] ?? ''}';
  bool _busy = false, _hide = true;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  Map<String, dynamic> get s => widget.state;
  bool get _needName => s['need_name'] == true || '${s['name'] ?? ''}'.trim().isEmpty;
  bool get _needEmail => s['need_email'] == true;
  bool get _needPhone => s['need_phone'] == true;
  bool get _needPass => s['need_password'] != false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _pass, _pass2, _code]) {
      c.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _cooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _cooldown = 0);
        return;
      }
      setState(() => _cooldown--);
    });
  }

  Future<void> _save() async {
    if (_needName && _name.text.trim().length < 2) return setState(() => _error = _tr('dl_setup_err_name', 'Please enter your full name'));
    if (_needEmail && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
      return setState(() => _error = _tr('dl_setup_err_email', 'Please enter a valid e-mail'));
    }
    if (_needPhone && _phone.text.replaceAll(RegExp(r'\D'), '').length < 8) {
      return setState(() => _error = _tr('dl_setup_err_phone', 'Please enter a valid phone number'));
    }
    if (_needPass && _pass.text.length < 8) return setState(() => _error = _tr('dl_setup_err_pass', 'Choose a password of at least 8 characters'));
    if (_needPass && _pass.text != _pass2.text) return setState(() => _error = _tr('dl_setup_err_match', 'The two passwords are not the same'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.saveAccountSetup(
        name: _needName ? _name.text.trim() : null,
        email: _needEmail ? _email.text.trim() : null,
        phone: _needPhone ? _phone.text.trim() : null,
        password: _needPass ? _pass.text : null,
      );
      if (!mounted) return;
      if (r['step'] == 'verify_email') {
        setState(() {
          _step = 'code';
          _codeEmail = '${r['email'] ?? _email.text.trim()}';
        });
        _startCooldown();
      } else {
        setState(() => _step = 'done');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 4) return setState(() => _error = _tr('dl_setup_err_code', 'Enter the 4-digit code'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.verifyAccountSetup(_code.text.trim());
      if (mounted) setState(() => _step = 'done');
    } catch (e) {
      if (mounted) setState(() => _error = _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await _api.resendAccountSetupCode();
      _startCooldown();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = _errText(e));
    }
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? kb, bool obscure = false, bool ltr = false, Widget? suffix}) {
    final c = context.colors;
    OutlineInputBorder b(Color x, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: x, width: w));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: kb,
        obscureText: obscure,
        textDirection: ltr ? TextDirection.ltr : null,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        style: dlText(14.5, c: c.textDark),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: dlText(13, c: c.textMedium),
          prefixIcon: Icon(icon, color: c.textMedium),
          suffixIcon: suffix,
          filled: true,
          fillColor: c.cardBg,
          border: b(c.divider),
          enabledBorder: b(c.divider),
          focusedBorder: b(c.primary, 1.6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final course = '${s['course_title'] ?? ''}';
    if (_step == 'done') {
      return _GatePage(
        icon: Icons.verified_rounded,
        title: _tr('dl_setup_done', 'Your account is verified'),
        subtitle: _tr('dl_setup_done_sub', 'Everything is set. From now on, sign in with your own password.'),
        children: [
          DlPrimaryButton(label: _tr('dl_setup_continue', 'Continue'), icon: Icons.arrow_forward_rounded, onPressed: widget.onDone),
        ],
      );
    }
    final steps = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (final (i, on) in [_step == 'details' || _step == 'code', _step == 'code'].indexed) ...[
        if (i > 0) Container(width: 30, height: 2, color: on ? c.primary : c.divider),
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? c.primary : c.divider),
          child: Text('${i + 1}', style: dlText(12, w: FontWeight.w800, c: c.onHero)),
        ),
      ],
    ]);
    final error = _error == null
        ? const SizedBox.shrink()
        : Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, size: 18, color: c.danger),
        const SizedBox(width: 8),
        Expanded(child: Text(_error!, style: dlText(12.5, w: FontWeight.w600, c: c.danger))),
      ]),
    );
    final signOut = Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TextButton.icon(
        onPressed: () async {
          try {
            await context.read<ProfileProvider>().logout(context);
          } catch (_) {}
        },
        icon: Icon(DirIcons.logout, size: 18, color: c.textMedium),
        label: Text(_tr('dl_setup_sign_out', 'Sign out'), style: dlText(12.5, c: c.textMedium)),
      ),
    );

    if (_step == 'code') {
      return _GatePage(
        icon: Icons.mark_email_unread_rounded,
        title: _tr('dl_setup_code_title', 'Check your e-mail'),
        subtitle: '${_tr('dl_setup_code_sub', 'We sent a 4-digit code to')} $_codeEmail',
        footer: signOut,
        children: [
          steps,
          const SizedBox(height: 18),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) {
              if (_error != null) setState(() => _error = null);
              if (v.length == 4) _verify();
            },
            style: dlText(30, w: FontWeight.w800, c: c.textDark).copyWith(letterSpacing: 14),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••',
              hintStyle: dlText(30, w: FontWeight.w800, c: c.textLight).copyWith(letterSpacing: 14),
              filled: true,
              fillColor: c.cardBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c.divider)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c.divider)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c.primary, width: 1.6)),
            ),
          ),
          const SizedBox(height: 12),
          error,
          DlPrimaryButton(label: _tr('dl_setup_verify', 'Verify'), icon: Icons.verified_rounded, busy: _busy, onPressed: _verify),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
              onPressed: _cooldown > 0 ? null : _resend,
              child: Text(_cooldown > 0 ? '${_tr('dl_setup_resend_in', 'Send again in')} $_cooldown s' : _tr('dl_setup_resend', 'Send the code again')),
            ),
            TextButton(
              onPressed: () => setState(() {
                _step = 'details';
                _code.clear();
              }),
              child: Text(_tr('dl_setup_change_email', 'Change e-mail')),
            ),
          ]),
        ],
      );
    }

    return _GatePage(
      icon: Icons.waving_hand_rounded,
      title: course.isEmpty ? _tr('dl_setup_title', 'Welcome!') : '${_tr('dl_setup_welcome', 'Welcome to')} $course',
      subtitle: _tr('dl_setup_sub', 'Your teacher created your account. Complete your details and choose your own password to finish.'),
      footer: signOut,
      children: [
        if (_needEmail) ...[steps, const SizedBox(height: 18)],
        DlCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!_needName && '${s['name'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Icon(Icons.person_rounded, color: c.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${s['name']}', style: dlText(15, w: FontWeight.w800, c: c.textDark))),
                ]),
              ),
            if (_needName) _field(_name, _tr('dl_setup_name', 'Full name'), Icons.person_rounded),
            if (_needEmail) _field(_email, 'dl_t_email'.tr, Icons.alternate_email_rounded, kb: TextInputType.emailAddress, ltr: true),
            if (!_needEmail && '${s['email'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Icon(Icons.mark_email_read_rounded, size: 18, color: c.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${s['email']}', textDirection: TextDirection.ltr, style: dlText(13, c: c.textMedium))),
                ]),
              ),
            if (_needPhone) _field(_phone, 'dl_t_phone'.tr, Icons.phone_rounded, kb: TextInputType.phone, ltr: true),
            if (_needPass) ...[
              _field(_pass, _tr('dl_setup_pass', 'New password'), Icons.lock_rounded,
                  obscure: _hide,
                  suffix: IconButton(
                    icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: c.textMedium),
                    tooltip: _hide ? (AppConfig.lang == 'ar' ? 'إظهار كلمة المرور' : 'Show password') : (AppConfig.lang == 'ar' ? 'إخفاء كلمة المرور' : 'Hide password'),
                    onPressed: () => setState(() => _hide = !_hide),
                  )),
              _field(_pass2, _tr('dl_setup_pass2', 'Confirm the password'), Icons.lock_reset_rounded, obscure: _hide),
            ],
            error,
            if (_needEmail)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: c.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_tr('dl_setup_email_note', 'We will send a code to this e-mail to verify it.'), style: dlText(11.5, c: c.textMedium, h: 1.4))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        DlPrimaryButton(
          label: _needEmail ? _tr('dl_setup_next', 'Next') : _tr('dl_setup_finish', 'Finish'),
          icon: _needEmail ? Icons.arrow_forward_rounded : Icons.verified_rounded,
          busy: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. Teacher's form — every question on one screen
// ═════════════════════════════════════════════════════════════════════════════

class DataLabFormScreen extends StatefulWidget {
  const DataLabFormScreen({super.key, required this.form, required this.onAnswered, this.remaining = 1, this.onChanged});

  final DlPendingForm form;
  final VoidCallback onAnswered;

  /// A question was closed by the teacher meanwhile → reload the forms.
  final VoidCallback? onChanged;
  final int remaining;

  @override
  State<DataLabFormScreen> createState() => _DataLabFormScreenState();
}

class _DataLabFormScreenState extends State<DataLabFormScreen> {
  final _api = DataLabApi();
  late final Map<int, TextEditingController> _ctrls = {
    for (final q in widget.form.questions) if (!q.isDropdown) q.requestId: TextEditingController(),
  };
  final Map<int, String> _choices = {};
  final Map<int, String> _errors = {};
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _value(DlPendingRequest q) => q.isDropdown ? (_choices[q.requestId] ?? '') : _ctrls[q.requestId]!.text.trim();

  Future<void> _submit() async {
    _errors.clear();
    for (final q in widget.form.questions) {
      final v = _value(q);
      if (v.isEmpty) {
        _errors[q.requestId] = 'dl_gate_required'.tr;
      } else if (q.isNumber) {
        final n = double.tryParse(v.replaceAll(',', '.'));
        if (n == null) {
          _errors[q.requestId] = _tr('dl_err_number', 'Please type a number, e.g. 17.5');
        } else if (q.maxValue != null && (n < 0 || n > q.maxValue!)) {
          _errors[q.requestId] = '0 – ${dlFmt(q.maxValue)}';
        }
      }
    }
    if (_errors.isNotEmpty) return setState(() => _error = null);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.answerForm({for (final q in widget.form.questions) q.requestId: _value(q)});
      if (mounted) widget.onAnswered();
    } catch (e) {
      if (!mounted) return;
      // the server names the question that was refused
      final rid = e is ApiException ? int.tryParse(RegExp(r'"?request_id"?\s*:\s*(\d+)').firstMatch('$e')?.group(1) ?? '') : null;
      setState(() {
        if (rid != null && widget.form.questions.any((q) => q.requestId == rid)) {
          _errors[rid] = _errText(e);
        } else {
          _error = _errText(e);
        }
      });
      if (e is ApiException && e.code == 'REQUEST_CLOSED') widget.onChanged?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = widget.form;
    final many = f.questions.length > 1;
    return _GatePage(
      icon: Icons.waving_hand_rounded,
      title: f.title.isNotEmpty ? f.title : 'dl_gate_title'.tr,
      subtitle: '${'dl_gate_sub'.tr} ${f.courseTitle}',
      children: [
        DlCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < f.questions.length; i++) ...[
              if (i > 0) Divider(height: 28, color: c.divider),
              _question(c, f.questions[i], many ? i + 1 : null),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: dlText(12, w: FontWeight.w600, c: c.danger)),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        DlPrimaryButton(label: 'dl_gate_continue'.tr, icon: Icons.arrow_forward_rounded, busy: _busy, onPressed: _submit),
        const SizedBox(height: 10),
        Text(widget.remaining > 1 ? '${widget.remaining - 1} ${'dl_gate_more'.tr}' : 'dl_gate_why'.tr,
            textAlign: TextAlign.center, style: dlText(11.5, c: c.textLight, h: 1.5)),
      ],
    );
  }

  Widget _question(ThemeConfigProvider c, DlPendingRequest q, int? n) {
    final err = _errors[q.requestId];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (n != null) ...[
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: (err != null ? c.danger : c.primary).withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Text('$n', style: dlText(11.5, w: FontWeight.w800, c: err != null ? c.danger : c.primary)),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: Text(q.title, style: dlText(15, w: FontWeight.w800, c: c.textDark))),
      ]),
      const SizedBox(height: 10),
      if (q.isDropdown)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in q.options)
            DlChoiceChip(
              label: o,
              selected: _choices[q.requestId] == o,
              onTap: () => setState(() {
                _choices[q.requestId] = o;
                _errors.remove(q.requestId);
              }),
            ),
        ])
      else
        DlField(
          controller: _ctrls[q.requestId]!,
          label: q.isNumber && q.maxValue != null ? '${'dl_gate_your_answer'.tr} (0 – ${dlFmt(q.maxValue)})' : 'dl_gate_your_answer'.tr,
          keyboard: q.isNumber ? const TextInputType.numberWithOptions(decimal: true) : null,
          onChanged: (_) {
            if (_errors.containsKey(q.requestId)) setState(() => _errors.remove(q.requestId));
          },
        ),
      if (err != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(err, style: dlText(12, w: FontWeight.w600, c: c.danger)),
        ),
    ]);
  }
}

/// One question on its own (kept for code that pushes it directly).
class DataLabRequestScreen extends StatelessWidget {
  const DataLabRequestScreen({super.key, required this.request, required this.onAnswered, this.remaining = 1});

  final DlPendingRequest request;
  final VoidCallback onAnswered;
  final int remaining;

  @override
  Widget build(BuildContext context) =>
      DataLabFormScreen(form: DlPendingForm([request]), onAnswered: onAnswered, remaining: remaining);
}
