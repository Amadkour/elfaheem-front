// lib/features/org/org_my_journey.dart
//
// Institutions v2, phase 5 (docs/institutions/V2_PLAN.md item 5, D-994 – D-997): the student's "My journey" at the top
// of the member home.
//   GET /api/v1/org/public/governance/{org_id}/me/journey
//     {now: [step], important: [step], later: [step], requests: [{id, ref, title, type, status, stage, stages, updated_at}],
//      register: {open, window_ends_at?, action}, contacts: [{kind, id, name, dept_id?, can_message}],
//      help: {file_request: action, file_complaint: action}, counts: {now, important, later}} (lists ≤ 5)
//     step = {key, title_ar, title_en, why_ar, why_en, action: {module, target_id?, route?}, due_at?, severity}
//
//   JourneyAction · JourneyStep · JourneyRequest · JourneyContact · MyJourney   pure, defensive parsers (tested)
//   OrgJourneyStore            one call per organization (cached; pull-to-refresh asks again); a failure draws nothing
//   OrgMyJourneyView           plain values (expectNoLayoutErrors): the hero "What should I do now?" with the top
//                              `now` step and its button · Important (an AppRoadmap) · "Can wait" folded · Register a
//                              course (while open) · File a request / complaint · Who do I contact? · My requests as
//                              AppStatusPath rows
//   JourneyContactsList        the contacts with Message (showUnitMessageSheet)
//   OrgMyJourney               the live section (store → view → the openers)
// A step's action opens through openJourneyAction: the server's modules (work_item, message, registrar, form,
// advising_appointment, new_request, unit_message …) map to the app's pages (journeyTargetOf); a notification-tap
// module goes through AppNavigator.openAction; an unknown one opens My requests (an API `route` is never pushed).
// Tests: test/org/institutions_v2_p5_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;

import '../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import 'governance/gov_item_screen.dart' show GovItemScreen;
import 'governance/gov_member_pages.dart' show GovMyAssignmentsPage, GovMyItemsPage, GovSubmitPage;
import 'org_must_ack.dart' show OrgMyMessagesPage;
import 'governance/gov_wiring.dart' show govEnabled;
import 'org_inst_notify.dart' show showUnitMessageSheet;
import 'org_registrar_member.dart' show openRegistration;
import 'org_v3.dart' show OrgCall, orgCall, orgParseUtc;

// ═════════════════════════════════════════════════════════════════════════════
//  Pure parts
// ═════════════════════════════════════════════════════════════════════════════

/// `{module, target_id?, route?}`: where a step (or a help entry) goes.
class JourneyAction {
  const JourneyAction({this.module, this.targetId, this.route});
  final String? module;
  final int? targetId;
  final String? route;

  bool get isEmpty => (module ?? '').isEmpty && (route ?? '').isEmpty;

  static JourneyAction? fromJson(dynamic raw) {
    final j = asMap(raw);
    final module = asStr(j['module']);
    final route = asStr(j['route']);
    final a = JourneyAction(
      module: module.isEmpty ? null : module,
      targetId: j['target_id'] == null ? null : asInt(j['target_id']),
      route: route.isEmpty ? null : route,
    );
    return a.isEmpty ? null : a;
  }

  Map<String, dynamic> toJson() => {'module': ?module, 'target_id': ?targetId, 'route': ?route};
}

/// 0 = urgent, 1 = important, 2 = the rest.
int journeySeverityRank(String s) => switch (s.toLowerCase()) {
      'urgent' || 'high' || 'danger' || 'block' || 'critical' => 0,
      'important' || 'warn' || 'warning' || 'medium' => 1,
      _ => 2,
    };

class JourneyStep {
  const JourneyStep({
    required this.key,
    this.titleAr = '',
    this.titleEn = '',
    this.whyAr = '',
    this.whyEn = '',
    this.action,
    this.dueAt,
    this.severity = 'normal',
  });

  final String key, titleAr, titleEn, whyAr, whyEn, severity;
  final JourneyAction? action;
  final DateTime? dueAt;

  String get title => t(titleAr.isEmpty ? titleEn : titleAr, titleEn.isEmpty ? titleAr : titleEn);
  String get why => t(whyAr.isEmpty ? whyEn : whyAr, whyEn.isEmpty ? whyAr : whyEn);
  bool get urgent => journeySeverityRank(severity) == 0;

  static JourneyStep? fromJson(dynamic raw) {
    final j = asMap(raw);
    final s = JourneyStep(
      key: asStr(j['key']),
      titleAr: asStr(j['title_ar']),
      titleEn: asStr(j['title_en']),
      whyAr: asStr(j['why_ar']),
      whyEn: asStr(j['why_en']),
      action: JourneyAction.fromJson(j['action']),
      dueAt: orgParseUtc(j['due_at']),
      severity: asStr(j['severity'], 'normal'),
    );
    return s.titleAr.isEmpty && s.titleEn.isEmpty ? null : s;
  }
}

/// Most urgent first, then the nearest date (no date last); the server's order breaks ties.
List<JourneyStep> journeyOrdered(Iterable<JourneyStep> steps) {
  final list = steps.toList();
  final pos = {for (var i = 0; i < list.length; i++) list[i]: i};
  list.sort((a, b) {
    final s = journeySeverityRank(a.severity).compareTo(journeySeverityRank(b.severity));
    if (s != 0) return s;
    final da = a.dueAt, db = b.dueAt;
    if (da != null && db != null && da != db) return da.compareTo(db);
    if (da != null && db == null) return -1;
    if (da == null && db != null) return 1;
    return pos[a]!.compareTo(pos[b]!);
  });
  return list;
}

/// The request path's stages, in order.
const journeyRequestStages = ['submitted', 'reviewed', 'decided'];

class JourneyRequest {
  const JourneyRequest({
    required this.id,
    this.ref = '',
    this.title = '',
    this.type = 'request',
    this.status = '',
    this.stage = 'submitted',
    this.stageTimes = const {},
    this.updatedAt,
  });

  final int id;
  final String ref, title, type, status, stage;
  final Map<String, DateTime?> stageTimes;
  final DateTime? updatedAt;

  /// 0 submitted · 1 reviewed · 2 decided (an unknown stage = submitted).
  int get reached {
    final i = journeyRequestStages.indexOf(stage);
    return i < 0 ? 0 : i;
  }

  static JourneyRequest? fromJson(dynamic raw) {
    final j = asMap(raw);
    final id = asInt(j['id']);
    if (id <= 0) return null;
    return JourneyRequest(
      id: id,
      ref: asStr(j['ref']),
      title: asStr(j['title']),
      type: asStr(j['type'], 'request'),
      status: asStr(j['status']),
      stage: asStr(j['stage'], 'submitted'),
      stageTimes: {for (final s in asMapList(j['stages'])) asStr(s['key']): orgParseUtc(s['at'])},
      updatedAt: orgParseUtc(j['updated_at']),
    );
  }
}

class JourneyContact {
  const JourneyContact({
    required this.kind,
    required this.id,
    required this.name,
    this.nameEn = '',
    this.deptId,
    this.canMessage = false,
    this.core = false,
    this.acting = false,
    this.action,
  });
  final String kind; // advisor · department · head
  final int id;
  final String name, nameEn;
  final int? deptId;
  final bool canMessage, core, acting;

  /// `{module: unit_message | unit | advisor, target_id}`.
  final JourneyAction? action;

  String get displayName => t(name, nameEn.isEmpty ? name : nameEn);

  /// The unit "Message" writes to: the action's (unit_message), else the contact's department, else the department.
  int? get messageDeptId {
    if (action?.module == 'unit_message' && action?.targetId != null) return action!.targetId;
    return deptId ?? (kind == 'department' ? id : null);
  }

  /// Message is offered only when the server allows it and a unit receives it.
  bool get messageable => canMessage && action?.module != 'unit' && messageDeptId != null;

  String get kindLabel => switch (kind) {
        'advisor' => t('مرشدك الأكاديمي', 'Your advisor'),
        'head' => acting ? t('رئيس القسم بالإنابة', 'Acting head of department') : t('رئيس القسم', 'Head of department'),
        _ => core ? t('إدارة أساسية', 'Core department') : t('إدارة', 'Department'),
      };

  IconData get icon => switch (kind) {
        'advisor' => Icons.support_rounded,
        'head' => Icons.person_rounded,
        _ => Icons.apartment_rounded,
      };

  static JourneyContact? fromJson(dynamic raw) {
    final j = asMap(raw);
    final name = asStr(j['name']).isEmpty ? asStr(j['name_en']) : asStr(j['name']);
    if (name.isEmpty) return null;
    return JourneyContact(
      kind: asStr(j['kind'], 'department'),
      id: asInt(j['id']),
      name: name,
      nameEn: asStr(j['name_en']),
      deptId: j['dept_id'] == null ? null : asInt(j['dept_id']),
      canMessage: j['can_message'] == true,
      core: j['core'] == true,
      acting: j['acting'] == true,
      action: JourneyAction.fromJson(j['action']),
    );
  }
}

class MyJourney {
  const MyJourney({
    this.now = const [],
    this.important = const [],
    this.later = const [],
    this.counts = const {},
    this.requests = const [],
    this.registerOpen = false,
    this.registered = false,
    this.registerEndsAt,
    this.registerAction,
    this.contacts = const [],
    this.fileRequest,
    this.fileComplaint,
  });

  /// Each list most urgent first ([journeyOrdered]); the server sends at most 5 of each.
  final List<JourneyStep> now, important, later;

  /// The full numbers `{now, important, later}` (the lists are capped).
  final Map<String, int> counts;
  final List<JourneyRequest> requests;

  /// A self-service registration window is open for me (`register.open`, no `reason`).
  final bool registerOpen;

  /// I already registered this term.
  final bool registered;
  final DateTime? registerEndsAt;
  final JourneyAction? registerAction;
  final List<JourneyContact> contacts;
  final JourneyAction? fileRequest, fileComplaint;

  int countOf(String k, int rows) => (counts[k] ?? 0) > rows ? counts[k]! : rows;
  int get laterCount => countOf('later', later.length);
  int get importantCount => countOf('now', now.length) - (now.isEmpty ? 0 : 1) + countOf('important', important.length);

  /// The hero's step: the most urgent `now` step (null = nothing needs me now).
  JourneyStep? get top => now.isEmpty ? null : now.first;

  /// Under the hero: the other `now` steps, then the important ones.
  List<JourneyStep> get importantRows => [...now.skip(1), ...important];

  bool get isEmpty => now.isEmpty && important.isEmpty && later.isEmpty && requests.isEmpty && contacts.isEmpty && !registerOpen;

  factory MyJourney.fromJson(Map<String, dynamic> j) {
    List<JourneyStep> steps(String k) => journeyOrdered([for (final x in (j[k] is List ? j[k] as List : const [])) ?JourneyStep.fromJson(x)]);
    final reg = asMap(j['register']);
    final help = asMap(j['help']);
    final c = asMap(j['counts']);
    return MyJourney(
      now: steps('now'),
      important: steps('important'),
      later: steps('later'),
      counts: {for (final e in c.entries) if (e.value is num) e.key: (e.value as num).toInt()},
      requests: [for (final x in (j['requests'] is List ? j['requests'] as List : const [])) ?JourneyRequest.fromJson(x)],
      registerOpen: reg['open'] == true && (reg['reason'] == null || '${reg['reason']}'.isEmpty),
      registered: reg['registered'] == true,
      registerEndsAt: orgParseUtc(reg['window_ends_at']),
      registerAction: JourneyAction.fromJson(reg['action']),
      contacts: [for (final x in (j['contacts'] is List ? j['contacts'] as List : const [])) ?JourneyContact.fromJson(x)],
      // the server's keys are file_request / file_complaint (module new_request / new_complaint); older drafts named
      // the keys after the module
      fileRequest: JourneyAction.fromJson(help['file_request'] ?? help['new_request']),
      fileComplaint: JourneyAction.fromJson(help['file_complaint'] ?? help['new_complaint']),
    );
  }
}

/// The journey's path for a step list: the first is the next node, urgent ones warn.
List<AppRoadmapNode> journeyNodes(List<JourneyStep> steps, {required void Function(JourneyStep s)? onOpen, bool later = false}) => [
      for (final s in steps)
        AppRoadmapNode(
          id: 'journey.${s.key}',
          title: s.title,
          subtitle: s.why.isEmpty ? null : s.why,
          caption: s.dueAt == null ? null : t('قبل ${AppTime.date(s.dueAt!, pattern: 'EEE d MMM')}', 'By ${AppTime.date(s.dueAt!, pattern: 'EEE d MMM')}'),
          state: !later && s.urgent ? AppRoadmapState.warn : AppRoadmapState.todo,
          onTap: s.action == null || onOpen == null ? null : () => onOpen(s),
        ),
    ];

// ═════════════════════════════════════════════════════════════════════════════
//  The store
// ═════════════════════════════════════════════════════════════════════════════

String orgJourneyPath(int orgId) => '/api/v1/org/public/governance/$orgId/me/journey';

/// One journey per organization: asked once when the home first shows it, again on pull-to-refresh.
class OrgJourneyStore extends ChangeNotifier {
  OrgJourneyStore._();
  static final instance = OrgJourneyStore._();

  final Map<int, MyJourney?> _data = {};
  final Set<int> _asked = {};

  /// Only for organizations, governance on.
  static bool get allowed => AppConfig.orgsEnabled && govEnabled();

  /// The answer (null = not asked, failed, or an older server).
  MyJourney? of(int orgId) => _data[orgId];

  /// The first answer (or failure) is in: until then the home holds back what the journey would fold away.
  bool settled(int orgId) => !allowed || _settled.contains(orgId);
  final Set<int> _settled = {};

  void ensure(int orgId) {
    if (!allowed || _asked.contains(orgId)) return;
    _asked.add(orgId);
    _load(orgId);
  }

  Future<void> refresh(int orgId) async {
    if (!allowed) return;
    _asked.add(orgId);
    await _load(orgId);
  }

  Future<void> _load(int orgId) async {
    final OrgCall r = await orgCall(() => ApiClient().get(orgJourneyPath(orgId)), quiet: true);
    _data[orgId] = r.ok ? MyJourney.fromJson(r.map) : _data[orgId];
    _settled.add(orgId);
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _data.clear();
    _asked.clear();
    _settled.clear();
  }

  @visibleForTesting
  void put(int orgId, MyJourney? j) {
    _data[orgId] = j;
    _asked.add(orgId);
    _settled.add(orgId);
    notifyListeners();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Plain-values view
// ═════════════════════════════════════════════════════════════════════════════

class OrgMyJourneyView extends StatelessWidget {
  const OrgMyJourneyView({
    super.key,
    required this.journey,
    this.onAction,
    this.onRegister,
    this.onFile,
    this.onContacts,
    this.onOpenRequest,
    this.onAllRequests,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.md),
  });

  final MyJourney journey;
  final void Function(JourneyStep step)? onAction;
  final VoidCallback? onRegister;

  /// `request` · `complaint`.
  final void Function(String type)? onFile;
  final VoidCallback? onContacts;
  final void Function(JourneyRequest r)? onOpenRequest;
  final VoidCallback? onAllRequests;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    final rows = j.importantRows;
    return Padding(
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        JourneyHero(step: j.top, onAction: j.top?.action == null || onAction == null ? null : () => onAction!(j.top!)),
        if (rows.isNotEmpty) ...[
          AppSpace.gapLg,
          _Heading(t('مهم', 'Important'), count: j.importantCount),
          AppRoadmap(
            key: const ValueKey('journey.important'),
            nodes: journeyNodes(rows, onOpen: onAction),
            next: -1,
            axis: Axis.vertical,
            label: t('خطوات مهمة', 'Important steps'),
          ),
        ],
        if (j.later.isNotEmpty) ...[
          AppSpace.gapSm,
          JourneyLater(steps: j.later, count: j.laterCount, onOpen: onAction),
        ],
        AppSpace.gapLg,
        _Heading(t('اختصارات', 'Shortcuts')),
        JourneyShortcuts(
          registerOpen: j.registerOpen,
          registerEndsAt: j.registerEndsAt,
          contacts: j.contacts.length,
          onRegister: onRegister,
          onFile: onFile,
          onContacts: j.contacts.isEmpty ? null : onContacts,
        ),
        if (j.requests.isNotEmpty) ...[
          AppSpace.gapLg,
          _Heading(t('طلباتي', 'My requests'), count: j.requests.length, actionLabel: onAllRequests == null ? null : t('الكل', 'All'), onAction: onAllRequests),
          for (final r in j.requests.take(3))
            Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: JourneyRequestRow(request: r, onTap: onOpenRequest == null ? null : () => onOpenRequest!(r))),
        ],
      ]),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.count, this.actionLabel, this.onAction});
  final String text;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(count == null ? text : '$text · $count',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            child: Text(actionLabel!, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, c.primary))),
          ),
      ]),
    );
  }
}

/// "What should I do now?": the most urgent step, why, by when, and its one button. Nothing → a calm emerald line.
class JourneyHero extends StatelessWidget {
  const JourneyHero({super.key, required this.step, this.onAction});
  final JourneyStep? step;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final s = step;
    return AppBlock(
      key: const ValueKey('journey.hero'),
      tone: s == null ? AppBlockTone.emerald : AppBlockTone.peach,
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(s == null ? Icons.check_circle_rounded : Icons.near_me_rounded, size: AppIconSize.md, color: b.ink),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(t('ماذا أفعل الآن؟', 'What should I do now?'),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: b.muted)),
              ),
            ),
          ]),
          const SizedBox(height: AppSpace.xs),
          Text(s == null ? t('لا شيء ينتظرك الآن', 'Nothing needs you right now') : s.title,
              maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.headline(context).copyWith(color: b.ink)),
          if (s != null && s.why.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(s.why, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: b.muted)),
          ],
          if (s == null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(t('سنخبرك عند ظهور خطوة جديدة', "We'll tell you when a new step comes up"),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: b.muted)),
          ],
          if (s?.dueAt != null) ...[
            const SizedBox(height: AppSpace.xs),
            Row(children: [
              Icon(Icons.event_rounded, size: AppIconSize.sm, color: b.muted),
              const SizedBox(width: AppSpace.xxs),
              Flexible(
                child: Text(t('قبل ${AppTime.dateTime(s!.dueAt!)}', 'By ${AppTime.dateTime(s.dueAt!)}'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
              ),
            ]),
          ],
          if (s != null && onAction != null) ...[
            AppSpace.gapMd,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.primary(
                key: const ValueKey('journey.hero.action'),
                label: t('ابدأ الآن', 'Do it now'),
                trailingIcon: Icons.arrow_forward_rounded,
                onPressed: onAction,
              ),
            ),
          ],
        ]);
      }),
    );
  }
}

/// "Can wait (n)": folded at first; opens to a quiet roadmap.
class JourneyLater extends StatefulWidget {
  const JourneyLater({super.key, required this.steps, this.count, this.onOpen, this.initiallyOpen = false});
  final List<JourneyStep> steps;

  /// The full number (the list may be capped); null = the rows.
  final int? count;
  final void Function(JourneyStep s)? onOpen;
  final bool initiallyOpen;

  @override
  State<JourneyLater> createState() => _JourneyLaterState();
}

class _JourneyLaterState extends State<JourneyLater> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = AppMotion.of(context);
    final label = t('يمكن أن ينتظر', 'Can wait');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        button: true,
        expanded: _open,
        label: '$label · ${widget.count ?? widget.steps.length}',
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('journey.later.toggle'),
          borderRadius: AppRadius.cardAll,
          onTap: () => setState(() => _open = !_open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
              child: Row(children: [
                Icon(Icons.schedule_rounded, size: AppIconSize.md, color: c.textMedium),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text('$label · ${widget.count ?? widget.steps.length}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textMedium)),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: m.base,
                  curve: AppMotion.curve,
                  child: Icon(Icons.expand_more_rounded, size: AppIconSize.lg, color: c.textMedium),
                ),
              ]),
            ),
          ),
        ),
      ),
      ClipRect(
        child: AnimatedSize(
          duration: m.slow,
          curve: AppMotion.curve,
          alignment: AlignmentDirectional.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: AppRoadmap(
                    key: const ValueKey('journey.later'),
                    nodes: journeyNodes(widget.steps, onOpen: widget.onOpen, later: true),
                    next: -1,
                    axis: Axis.vertical,
                    dense: true,
                    label: label,
                  ),
                ),
        ),
      ),
    ]);
  }
}

/// Register a course (while open) · File a request · File a complaint · Who do I contact?
class JourneyShortcuts extends StatelessWidget {
  const JourneyShortcuts({
    super.key,
    this.registerOpen = false,
    this.registerEndsAt,
    this.contacts = 0,
    this.onRegister,
    this.onFile,
    this.onContacts,
  });

  final bool registerOpen;
  final DateTime? registerEndsAt;
  final int contacts;
  final VoidCallback? onRegister, onContacts;
  final void Function(String type)? onFile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tiles = <Widget>[
      if (registerOpen)
        _Shortcut(
          key: const ValueKey('journey.register'),
          icon: Icons.how_to_reg_rounded,
          tone: c.success,
          title: t('سجّل مقرراتك', 'Register a course'),
          subtitle: registerEndsAt == null
              ? t('التسجيل مفتوح الآن', 'Registration is open now')
              : t('مفتوح حتى ${AppTime.date(registerEndsAt!)}', 'Open until ${AppTime.date(registerEndsAt!)}'),
          onTap: onRegister,
        ),
      _Shortcut(
        key: const ValueKey('journey.file.request'),
        icon: Icons.add_task_rounded,
        tone: c.primary,
        title: t('قدّم طلباً', 'File a request'),
        subtitle: t('إفادة، إعادة قيد، عذر…', 'A letter, re-enrolment, an excuse…'),
        onTap: onFile == null ? null : () => onFile!('request'),
      ),
      _Shortcut(
        key: const ValueKey('journey.file.complaint'),
        icon: Icons.support_agent_rounded,
        tone: c.warning,
        title: t('قدّم شكوى', 'File a complaint'),
        subtitle: t('تصل للإدارة المختصة وتتابعها هنا', 'It reaches the right office; follow it here'),
        onTap: onFile == null ? null : () => onFile!('complaint'),
      ),
      if (onContacts != null)
        _Shortcut(
          key: const ValueKey('journey.contacts'),
          icon: Icons.contact_support_rounded,
          tone: c.textMedium,
          title: t('بمن أتواصل؟', 'Who do I contact?'),
          subtitle: countText(contacts, ar1: 'جهة واحدة', ar2: 'جهتان', arFew: '{n} جهات', arMany: '{n} جهة', en1: '1 contact', en: '{n} contacts'),
          onTap: onContacts,
        ),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 640 ? 2 : 1;
      if (cols == 1) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final w in tiles) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: w),
        ]);
      }
      final w = (box.maxWidth - AppSpace.xs) / 2;
      return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [for (final x in tiles) SizedBox(width: w, child: x)]);
    });
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({super.key, required this.icon, required this.tone, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final Color tone;
  final String title, subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final well = appTintOn(context, tone, surface: c.cardBg);
    return Semantics(
      button: onTap != null,
      label: '$title${AppConfig.lang == 'ar' ? '، ' : ', '}$subtitle',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
        child: Row(children: [
          Container(
            width: AppIconSize.hero,
            height: AppIconSize.hero,
            decoration: BoxDecoration(color: well, borderRadius: AppRadius.chipAll),
            child: Icon(icon, size: AppIconSize.md, color: appInkOn(context, tone, well)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.xxs / 2),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: c.textLight),
        ]),
      ),
    );
  }
}

/// One request: title · ref, and its submitted → reviewed → decided path.
class JourneyRequestRow extends StatelessWidget {
  const JourneyRequestRow({super.key, required this.request, this.onTap});
  final JourneyRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = request;
    final title = r.title.isEmpty ? (r.type == 'complaint' ? t('شكوى', 'Complaint') : t('طلب', 'Request')) : r.title;
    String? at(String k) {
      final d = r.stageTimes[k];
      return d == null ? null : AppTime.date(d, pattern: 'd MMM');
    }

    return Semantics(
      button: onTap != null,
      child: AppCard(
        key: ValueKey('journey.request.${r.id}'),
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
            ),
            if (r.ref.isNotEmpty) ...[
              const SizedBox(width: AppSpace.xs),
              Text(r.ref, maxLines: 1, style: AppType.meta(context).copyWith(color: ensureContrastOn(c.textMedium, c.cardBg))),
            ],
          ]),
          const SizedBox(height: AppSpace.sm),
          AppStatusPath.request(
            reached: r.reached,
            times: [for (final k in journeyRequestStages) at(k)],
            semanticPrefix: title,
          ),
        ]),
      ),
    );
  }
}

/// The contacts list (the "Who do I contact?" sheet): each with Message when the server allows it.
class JourneyContactsList extends StatelessWidget {
  const JourneyContactsList({super.key, required this.contacts, required this.onMessage});
  final List<JourneyContact> contacts;
  final void Function(JourneyContact c) onMessage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (contacts.isEmpty) {
      return AppEmpty(
        icon: Icons.contact_support_rounded,
        title: t('لا جهات بعد', 'No contacts yet'),
        message: t('ستظهر هنا إدارتك ومرشدك عند تعيينهم', 'Your department and advisor show here once assigned'),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final x in contacts)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppCard(
            key: ValueKey('journey.contact.${x.kind}.${x.id}'),
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xs, AppSpace.xs),
            child: Row(children: [
              Container(
                width: AppIconSize.hero,
                height: AppIconSize.hero,
                decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
                child: Icon(x.icon, size: AppIconSize.md, color: c.textMedium),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(x.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                  Text(x.kindLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ]),
              ),
              if (x.messageable)
                AppButton.tonal(
                  key: ValueKey('journey.contact.message.${x.id}'),
                  label: t('راسل', 'Message'),
                  icon: Icons.mail_outline_rounded,
                  tooltip: t("راسل ${x.displayName}", "Message ${x.displayName}"),
                  onPressed: () => onMessage(x),
                ),
            ]),
          ),
        ),
    ]);
  }
}

/// [ensureContrast] for one surface.
Color ensureContrastOn(Color ink, Color surface) => ensureContrast(ink, [surface]);

// ═════════════════════════════════════════════════════════════════════════════
//  Openers + the live section
// ═════════════════════════════════════════════════════════════════════════════

/// Where an action's module goes in the app (the server's modules, FLUTTER_API_CHANGES phase 5).
enum JourneyTarget { workItem, complaint, message, registrar, meeting, form, newRequest, newComplaint, unitMessage, notification, none }

/// `work_item` · `complaint` · `message` · `registrar` · `advising_appointment` · `form` · `new_request` ·
/// `new_complaint` · `unit_message`; a module the app knows from notification taps (`org_work` …) goes through
/// AppNavigator; anything else is [JourneyTarget.none] (the safe fallback: My requests).
JourneyTarget journeyTargetOf(JourneyAction? a) {
  if (a == null || a.isEmpty) return JourneyTarget.none;
  return switch (a.module ?? '') {
    'work_item' || 'org_work' => a.targetId == null ? JourneyTarget.none : JourneyTarget.workItem,
    'complaint' => JourneyTarget.complaint,
    'message' || 'org_message' => JourneyTarget.message,
    'registrar' || 'register' => JourneyTarget.registrar,
    'advising_appointment' || 'meeting' => JourneyTarget.meeting,
    'form' => JourneyTarget.form,
    'new_request' => JourneyTarget.newRequest,
    'new_complaint' => JourneyTarget.newComplaint,
    'unit_message' => a.targetId == null ? JourneyTarget.none : JourneyTarget.unitMessage,
    'org_council' || 'org_department' || 'org_delegations' || 'calendar' || 'notifications' => JourneyTarget.notification,
    _ => JourneyTarget.none,
  };
}

/// Opens an action. The app's own pages for the server's modules; a notification-tap module through
/// AppNavigator.openAction; an unknown module (or an API `route`, never a page) → My requests.
Future<void> openJourneyAction(BuildContext context, JourneyAction? a, {required int orgId}) async {
  final nav = Navigator.of(context);
  Future<void> push(Widget page) => nav.push(MaterialPageRoute(builder: (_) => page));
  switch (journeyTargetOf(a)) {
    case JourneyTarget.workItem:
      return push(GovItemScreen(a!.targetId!, orgId: orgId, member: true));
    case JourneyTarget.complaint:
    case JourneyTarget.none:
      return push(GovMyItemsPage(orgId: orgId));
    case JourneyTarget.message:
      return push(OrgMyMessagesPage(orgId: orgId, openId: a!.targetId));
    case JourneyTarget.registrar:
      return openRegistration(context, orgId);
    case JourneyTarget.meeting:
      await nav.pushNamed('/calendar', arguments: {'org_id': orgId, 'meeting_id': ?a!.targetId});
      return;
    case JourneyTarget.form:
      return push(const GovMyAssignmentsPage());
    case JourneyTarget.newRequest:
      return push(GovSubmitPage(orgId));
    case JourneyTarget.newComplaint:
      return push(GovSubmitPage(orgId, type: 'complaint'));
    case JourneyTarget.unitMessage:
      await showUnitMessageSheet(context, orgId: orgId, dept: {'id': a!.targetId});
      return;
    case JourneyTarget.notification:
      final route = a!.route ?? '';
      await AppNavigator.openAction(module: a.module, targetId: a.targetId, route: route.startsWith('/api/') ? null : route, orgId: orgId);
  }
}

/// "Message this department" for a contact.
Future<void> messageJourneyContact(BuildContext context, int orgId, JourneyContact x) async {
  final dept = x.messageDeptId;
  if (dept == null) return;
  await showUnitMessageSheet(context, orgId: orgId, dept: {'id': dept, 'name_ar': x.name, 'name_en': x.nameEn.isEmpty ? x.name : x.nameEn});
}

Future<void> showJourneyContacts(BuildContext context, int orgId, List<JourneyContact> contacts) => showAppSheet<void>(
      context,
      (ctx) => AppSheetContent(
        title: t('بمن أتواصل؟', 'Who do I contact?'),
        icon: Icons.contact_support_rounded,
        children: [
          JourneyContactsList(
            contacts: contacts,
            onMessage: (x) {
              Navigator.pop(ctx);
              messageJourneyContact(context, orgId, x);
            },
          ),
        ],
      ),
    );

/// The live "My journey" section: draws nothing until the journey arrives, or when it is empty / failed.
class OrgMyJourney extends StatelessWidget {
  const OrgMyJourney({super.key, required this.orgId, required this.journey});
  final int orgId;
  final MyJourney journey;

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    void push(Widget page) => nav.push(MaterialPageRoute(builder: (_) => page));
    return OrgMyJourneyView(
      journey: journey,
      onAction: (s) => openJourneyAction(context, s.action, orgId: orgId),
      onRegister: () => openRegistration(context, orgId),
      onFile: (type) => push(GovSubmitPage(orgId, type: type == 'complaint' ? 'complaint' : 'request')),
      onContacts: () => showJourneyContacts(context, orgId, journey.contacts),
      onOpenRequest: (r) => push(GovItemScreen(r.id, orgId: orgId, member: true)),
      onAllRequests: () => push(GovMyItemsPage(orgId: orgId)),
    );
  }
}
