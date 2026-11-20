// lib/features/onboarding/join/join_flow_screen.dart — `/join?role=` (Learning Hub F5, D-1323, PLAN §3.3): the
// landing's Student / Teacher / Parent buttons land here, on web and in the apps alike.
//
//   role → country → stage + grade (a teacher: the stages and years taught) → online / in-person → area (+ address)
//   → name + phone (skippable) → confirm → the explorer with the filters applied (CONTRACT §4)
//
// Every answer is saved in [JoinDraft] as it is given, so a reload resumes the answers and the registration prefills
// from them (a student's study step, a teacher's levels sent in POST /auth/teacher-profile). A signed-in parent with
// a child code links the child here, through the consent dialog when the server answers 422 `consent_required`.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/design/app_language_switch.dart' show refreshWholeUi;
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/register_screen.dart';
import 'package:flutter_education_app/features/onboarding/explore_launcher.dart';
import 'package:flutter_education_app/features/parent/parent_consent.dart';
import 'package:flutter_education_app/features/parent/parent_link_providers.dart';

import 'join_draft.dart';
import 'join_steps.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

class JoinFlowScreen extends StatefulWidget {
  const JoinFlowScreen({super.key, this.role, this.lang});

  /// student · teacher · parent from the URL; null = the role step first.
  final String? role;
  final String? lang;

  @override
  State<JoinFlowScreen> createState() => _JoinFlowScreenState();
}

class _JoinFlowScreenState extends State<JoinFlowScreen> {
  JoinDraft _d = JoinDraft();
  JoinStep _step = JoinStep.role;
  List<EduCountry> _countries = const [];
  EduCountryCatalog? _catalog;
  bool _catalogLoading = false;
  bool _busy = false;
  final _address = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _childCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.role != null) {
      _d.role = widget.role!;
      _step = JoinStep.country;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    for (final c in [_address, _name, _phone, _childCode]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final lang = widget.lang;
    if (lang != null && lang != AppConfig.lang && mounted) {
      await context.read<LangProvider>().changeLang(lang);
      refreshWholeUi();
    }
    final saved = await JoinDraft.load();
    final countries = await EduCountries.load();
    if (!mounted) return;
    setState(() {
      if (saved != null) {
        if (widget.role != null && saved.role != widget.role) {
          // another role's answers do not fit (a teacher's levels are not a grade): keep only the shared ones
          _d = JoinDraft(
              role: widget.role!, country: saved.country, delivery: saved.delivery, area1: saved.area1, area2: saved.area2,
              address: saved.address, name: saved.name, phone: saved.phone);
        } else {
          _d = saved;
        }
      }
      _countries = countries;
      _d.country ??= pickEduCountry(countries, null)?.code;
      _address.text = _d.address;
      _name.text = _d.name;
      _phone.text = _d.phone;
      _childCode.text = _d.childCode;
    });
    await _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final country = _d.country;
    if (country == null) return;
    setState(() => _catalogLoading = _catalog?.country != country);
    final cat = await EduCatalog.instance.load(country);
    if (!mounted || _d.country != country) return;
    setState(() {
      _catalog = cat;
      _catalogLoading = false;
    });
  }

  void _edit(void Function() change) {
    final before = _d.country;
    setState(change);
    _persist();
    if (_d.country != before) _loadCatalog();
  }

  void _persist() {
    _d
      ..address = _address.text.trim()
      ..name = _name.text.trim()
      ..phone = _phone.text.trim()
      ..childCode = _childCode.text.trim();
    _d.save();
  }

  List<JoinStep> get _steps => joinStepsFor(_d);

  void _go(int delta) {
    _persist();
    final steps = _steps;
    final i = steps.indexOf(_step) + delta;
    if (i < 0) return _leave();
    if (i >= steps.length) return;
    setState(() => _step = steps[i]);
  }

  /// Back from the first step: the page under it, else the old guest search.
  void _leave() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      nav.pushReplacementNamed('/guest-search');
    }
  }

  void _skip() {
    if (_step == JoinStep.area) {
      _address.clear();
      _d.area1 = _d.area2 = null;
    } else if (_step == JoinStep.contact) {
      _name.clear();
      _phone.clear();
      _childCode.clear();
    }
    _go(1);
  }

  // ── The confirm step's actions ──────────────────────────────────────────────

  Future<void> _primary() async {
    _persist();
    if (_d.isTeacher) return _register();
    _explore();
  }

  void _explore() {
    final nav = Navigator.of(context);
    final auth = context.read<MyAuthProvider>();
    final filters = _d.filters;
    if (auth.isAuthenticated) {
      nav.pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
      openExplorer(nav, filters: filters);
    } else {
      openGuestExplore(nav, filters: filters);
    }
  }

  /// The registration with the role picked and the answers prefilled (RegisterScreen reads the draft). A signed-in
  /// person goes home instead.
  void _register() {
    final nav = Navigator.of(context);
    final auth = context.read<MyAuthProvider>();
    if (auth.isAuthenticated) {
      nav.pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
      return;
    }
    nav.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/register'),
      builder: (_) => RegisterScreen(initialRole: _d.role),
    ));
  }

  /// A signed-in parent links the child by its code; an under-age child asks for the consent first (422
  /// `consent_required`, the same dialog as the parent's link page).
  Future<void> _linkChild() async {
    final code = _childCode.text.trim();
    if (code.length < 4) {
      showAppNotice(_t('أدخل كود ابنك أو ابنتك أولًا', "Enter your child's code first"), error: true);
      setState(() => _step = JoinStep.contact);
      return;
    }
    setState(() => _busy = true);
    final p = ParentLinkProvider();
    var r = await p.redeem(code, const {}, const {});
    if (r == null && p.lastErrorCode == 'consent_required' && mounted) {
      final agreed = await showParentConsentDialog(context);
      if (agreed && mounted) r = await p.redeem(code, const {}, const {}, consent: true);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) {
      if (p.lastErrorCode != 'consent_required') showAppNotice(p.errorMessage ?? _t('تعذّر الربط', 'Could not link'), error: true);
      return;
    }
    _childCode.clear();
    _persist();
    showAppNotice(r['status'] == 'approved'
        ? _t('تم ربط ابنك بحسابك', 'Your child is linked to your account')
        : _t('أُرسل الطلب وينتظر المراجعة', 'Request sent, waiting for review'));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<MyAuthProvider>();
    final country = _d.country;
    return JoinFlowView(
      step: _step,
      draft: _d,
      countries: _countries,
      catalog: _catalog,
      catalogLoading: _catalogLoading,
      busy: _busy,
      address: _address,
      name: _name,
      phone: _phone,
      childCode: _childCode,
      loadAreas: (parent) => country == null
          ? Future.value(const <EduArea>[])
          : EduCatalog.instance.areas(country, parentId: parent),
      onEdit: _edit,
      onBack: () => _go(-1),
      onNext: _step == JoinStep.confirm ? _primary : () => _go(1),
      onSkip: _skip,
      onGoTo: (s) => setState(() => _step = s),
      onSecondary: _d.isTeacher ? _explore : (auth.isAuthenticated ? null : _register),
      onLinkChild: _d.isParent && auth.isAuthenticated && auth.isParent && _childCode.text.trim().isNotEmpty
          ? _linkChild
          : null,
    );
  }
}
