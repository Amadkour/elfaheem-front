// lib/features/shared/data_lab/data_lab_gate.dart
// Student side of a Data Lab request: a screen that stays on top of the app until the student answers.
//
// Wrap the student's home once (e.g. in the student dashboard):
//     DataLabGate(child: StudentDashboardScreen())
// It checks when the app opens and every time it comes back to the foreground. Teachers / admins pass straight through.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';

import 'data_lab_api.dart';
import 'data_lab_models.dart';
import 'data_lab_widgets.dart';

class DataLabGate extends StatefulWidget {
  const DataLabGate({super.key, required this.child});

  final Widget child;

  @override
  State<DataLabGate> createState() => _DataLabGateState();
}

class _DataLabGateState extends State<DataLabGate> with WidgetsBindingObserver {
  final _api = DataLabApi();
  List<DlPendingRequest> _pending = [];
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
    final user = context.read<MyAuthProvider>().currentUser;
    if (user?.role != 'student') return;
    _checking = true;
    try {
      final items = await _api.myPendingRequests();
      if (mounted) setState(() => _pending = items);
    } catch (_) {
      // never block the app because the check failed
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
    widget.child,
    if (_pending.isNotEmpty)
      Positioned.fill(
        child: PopScope(
          canPop: false,
          child: DataLabRequestScreen(
            key: ValueKey(_pending.first.requestId),
            request: _pending.first,
            remaining: _pending.length,
            onAnswered: () => setState(() => _pending = _pending.sublist(1)),
          ),
        ),
      ),
  ]);
}

/// The blocking form. Can also be pushed on its own.
class DataLabRequestScreen extends StatefulWidget {
  const DataLabRequestScreen({super.key, required this.request, required this.onAnswered, this.remaining = 1});

  final DlPendingRequest request;
  final VoidCallback onAnswered;
  final int remaining;

  @override
  State<DataLabRequestScreen> createState() => _DataLabRequestScreenState();
}

class _DataLabRequestScreenState extends State<DataLabRequestScreen> {
  final _api = DataLabApi();
  final _ctrl = TextEditingController();
  String? _choice, _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final r = widget.request;
    final value = r.isDropdown ? (_choice ?? '') : _ctrl.text.trim();
    if (value.isEmpty) return setState(() => _error = 'dl_gate_required'.tr);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.answerRequest(r.requestId, value);
      if (mounted) widget.onAnswered();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.request;
    return Directionality(
      textDirection: pageDirection,
      child: Material(
        color: c.background,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [c.primary, c.primaryDark]),
                      boxShadow: c.primaryShadow,
                    ),
                    child: const Icon(Icons.waving_hand_rounded, color: Colors.white, size: 42),
                  ),
                  const SizedBox(height: 20),
                  Text('dl_gate_title'.tr, textAlign: TextAlign.center, style: dlText(21, w: FontWeight.w800, c: c.textDark)),
                  const SizedBox(height: 8),
                  Text('${'dl_gate_sub'.tr} ${r.courseTitle}',
                      textAlign: TextAlign.center, style: dlText(13, c: c.textMedium, h: 1.55)),
                  const SizedBox(height: 22),
                  DlCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.title, style: dlText(15, w: FontWeight.w800, c: c.textDark)),
                      const SizedBox(height: 12),
                      if (r.isDropdown)
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final o in r.options)
                            DlChoiceChip(label: o, selected: _choice == o, onTap: () => setState(() => _choice = o)),
                        ])
                      else
                        DlField(controller: _ctrl, label: 'dl_gate_your_answer'.tr),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_error!, style: dlText(12, w: FontWeight.w600, c: c.danger)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  DlPrimaryButton(label: 'dl_gate_continue'.tr, icon: Icons.arrow_forward_rounded, busy: _busy, onPressed: _submit),
                  const SizedBox(height: 10),
                  Text(widget.remaining > 1 ? '${widget.remaining - 1} ${'dl_gate_more'.tr}' : 'dl_gate_why'.tr,
                      textAlign: TextAlign.center, style: dlText(11.5, c: c.textLight, h: 1.5)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
