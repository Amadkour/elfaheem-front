// lib/features/profile/compalints/complaints_hub_page.dart
//
// THE Complaints page of the profile / settings tab for every role except the super admin, who keeps the admin
// console (D-086). One page:
//   • "New complaint" — to the app team (NewComplaintScreen, form only) or, for a member of organizations, to one
//     of them (the organization's composer, a department inbox)
//   • My complaints — platform + organization complaints I filed, unread replies first, tap → its thread
//   • To resolve — non-students / non-parents (and anyone who has rows there): the complaints I handle, most urgent
//     first, with quick Start / Resolve; Reply and a tap open the staff thread
// Data: ComplaintsHubController (complaints_hub_data.dart); the look: ComplaintsHubView (complaints_hub_widgets.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/org/org_member_space.dart' show OrgMyComplaintThread, showComplaintComposer;
import 'package:flutter_education_app/features/org/org_services_pages.dart' show OrgComplaintThreadScreen;
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_data.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_model.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_widgets.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_screen.dart' show ComplaintDetailScreen;
import 'package:flutter_education_app/features/profile/compalints/new_complaint_screen.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2Scope;

/// Opens the page (profile tile, parent "More", the `support` deep link without an id).
Future<void> openComplaintsHub(NavigatorState nav) => nav.push(MaterialPageRoute(
    settings: const RouteSettings(name: '/help-center'), builder: (_) => const ComplaintsHubPage()));

class ComplaintsHubPage extends StatefulWidget {
  const ComplaintsHubPage({super.key, this.initialSegment = HubSegment.mine});
  final HubSegment initialSegment;

  @override
  State<ComplaintsHubPage> createState() => _ComplaintsHubPageState();
}

class _ComplaintsHubPageState extends State<ComplaintsHubPage> {
  late final ComplaintsHubController _ctl;
  final _search = TextEditingController();
  late HubSegment _segment = widget.initialSegment;
  late HubFilter _filter = defaultFilter(widget.initialSegment);
  final Set<String> _busy = {};

  /// The person's organizations (id · name · logo), from the mode switcher's overview.
  List<(int, HubName, String?)> get _orgs {
    if (!AppConfig.orgsEnabled) return const [];
    final out = <(int, HubName, String?)>[];
    for (final e in AppModeController.instance.liveEntries) {
      final o = e['organization'];
      if (o is! Map) continue;
      final id = int.tryParse('${o['id'] ?? ''}');
      final name = HubName.of(o);
      if (id != null && name != null) out.add((id, name, o['logo_url']?.toString()));
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    final auth = context.read<MyAuthProvider>();
    _ctl = ComplaintsHubController(
      myId: auth.currentUser?.id ?? 0,
      orgNames: {for (final (id, name, _) in _orgs) id: name},
    )..addListener(_changed);
    _search.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctl.refresh();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctl
      ..removeListener(_changed)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _showToResolve =>
      offersToResolve(role: context.read<MyAuthProvider>().currentUser?.role, hasRows: _ctl.toResolve.isNotEmpty);

  void _setSegment(HubSegment s) => setState(() {
        if (s == _segment) return;
        _segment = s;
        _filter = defaultFilter(s);
      });

  Future<void> _new() async {
    final orgs = _orgs;
    if (orgs.isEmpty) return _newPlatform();
    await showAppSheet<void>(
      context,
      (ctx) => HubDestinationSheet(
        orgs: orgs,
        onApp: () {
          Navigator.pop(ctx);
          _newPlatform();
        },
        onOrg: (id) {
          Navigator.pop(ctx);
          _newOrg(orgs.firstWhere((o) => o.$1 == id));
        },
      ),
    );
  }

  Future<void> _newPlatform() async {
    final sent = await Navigator.of(context).push<Object?>(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<ComplaintProvider>(
        create: (_) => ComplaintProvider(),
        child: const NewComplaintScreen(formOnly: true),
      ),
    ));
    if (!mounted || sent == null) return;
    _setSegment(HubSegment.mine);
    await _ctl.refresh(quiet: true, toResolveToo: false);
  }

  Future<void> _newOrg((int, HubName, String?) org) async {
    final sent = await showComplaintComposer(context, {'id': org.$1, 'name_ar': org.$2.ar, 'name_en': org.$2.en});
    if (!mounted || !sent) return;
    _setSegment(HubSegment.mine);
    await _ctl.refresh(quiet: true, toResolveToo: false);
  }

  Future<void> _open(HubRow r) async {
    _ctl.markRead(r);
    final Widget page;
    if (r.source == HubSource.platform) {
      page = ChangeNotifierProvider<ComplaintProvider>(
        create: (_) => ComplaintProvider(),
        child: ComplaintDetailScreen(complaintId: r.id),
      );
    } else if (r.mine) {
      page = OrgMyComplaintThread(id: r.id);
    } else {
      page = OrgComplaintThreadScreen(id: r.id, orgId: r.orgId, canAct: r.canAct);
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _ctl.refresh(quiet: true);
  }

  Future<void> _action(HubRow r, HubAction a) async {
    final to = statusAfter(a);
    if (to == null) return _open(r);
    setState(() => _busy.add(r.key));
    final ok = await _ctl.setStatus(r, to);
    if (!mounted) return;
    setState(() => _busy.remove(r.key));
    showAppNotice(
      ok ? (to == HubStatus.resolved ? 'chub_resolved_toast' : 'chub_started_toast').tr : 'chub_action_failed'.tr,
      error: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>(); // re-translate when the language changes
    final show = _showToResolve;
    final seg = show ? _segment : HubSegment.mine;
    // a student's help center wears the chat area and the kit's top bar (redesign S-C, Stu1Comm?screen=complaints)
    final student = context.read<MyAuthProvider>().currentUser?.role == 'student';
    // a teacher's page wears the teacher hero (redesign T2b, Tea2Account complaints)
    final teacher = context.read<MyAuthProvider>().currentUser?.role == 'teacher';
    final page = BasePage(
      key: const ValueKey('complaints'),
      useWebCard: !student && !teacher,
      width: AppWidth.content,
      appBar: student || teacher
          ? AppHeader(title: 'chub_title'.tr, actions: [AppRefreshAction(onRefresh: _ctl.refresh)])
          : ScreenAppBar(title: 'chub_title'.tr, actions: [AppRefreshAction(onRefresh: _ctl.refresh)]),
      child: SafeArea(
        child: Column(children: [
          Expanded(
            child: ComplaintsHubView(
              segment: seg,
              showToResolve: show,
              mine: _ctl.mine,
              toResolve: _ctl.toResolve,
              filter: _filter,
              query: _search.text,
              now: DateTime.now().toUtc(),
              searchController: _search,
              loading: seg == HubSegment.mine ? _ctl.loadingMine : _ctl.loadingToResolve,
              failed: seg == HubSegment.mine ? _ctl.mineFailed : _ctl.toResolveFailed,
              busy: _busy,
              onSegment: _setSegment,
              onFilter: (f) => setState(() => _filter = f),
              onNew: _new,
              onOpen: _open,
              onAction: _action,
              onRefresh: _ctl.refresh,
              teacher: teacher,
              onClearFilters: () => setState(() {
                _search.clear();
                _filter = defaultFilter(seg);
              }),
            ),
          ),
        ]),
      ),
    );
    if (teacher) return T2Scope(child: page);
    return student ? AppAreaScope(area: AppArea.chat, child: page) : page;
  }
}
