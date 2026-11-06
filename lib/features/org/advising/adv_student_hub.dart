// lib/features/org/advising/adv_student_hub.dart — the student's ONE advising screen (docs/advising/PHASE5.md "Student
// hub", #18): the advisor card(s) with office hours and the next free time, one-tap Book and Message, upcoming and
// past meetings, the notes advisors shared with the student, a pending survey, and the way into the conversations.
// Reached from the member home ("My advisor") and the advising deep links.
//
//   AdvHubView         plain values (test/ui/adv_appt_layout_test.dart, test/visual/adv_appt_golden_test.dart)
//   AdvStudentHubPage  loads `GET /org/public/{id}/advising/me` and runs every action
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh;
import '../org_v3.dart' show orgCall;
import 'adv_appointments.dart';
import 'adv_appt_models.dart';
import 'adv_case_parts.dart' show AdvTypedText;
import 'adv_comm_api.dart';
import 'adv_comm_parts.dart';
import 'adv_parts.dart';
import 'adv_survey_sheet.dart';
import 'adv_support_hub.dart' show AdvStudentSupportPage;
import 'adv_threads.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  The view (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class AdvAdvisorHubCard extends StatelessWidget {
  const AdvAdvisorHubCard({super.key, required this.advisor, this.canBook = true, this.onBook, this.onMessage});
  final AdvHubAdvisor advisor;
  final bool canBook;
  final VoidCallback? onBook, onMessage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = advisor;
    final lines = a.hours.lines;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AppAvatar(name: a.shown, size: AppTouch.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(header: true, child: Text(a.shown, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
                Text(a.typeLabel, style: AppType.meta(context)),
              ]),
            ),
          ]),
          if (a.office != null) AdvInfoLine(icon: Icons.place_outlined, text: a.office!, typed: true),
          if (a.contactNote != null) AdvInfoLine(icon: Icons.contact_phone_outlined, text: a.contactNote!, typed: true, maxLines: 3),
          if (a.bio != null) ...[
            const SizedBox(height: AppSpace.xs),
            AdvTypedText(a.bio!, maxLines: 3, style: AppType.body(context)),
          ],
          const SizedBox(height: AppSpace.sm),
          Text(t('الساعات المكتبية', 'Office hours'), style: AppType.bodyStrong(context)),
          if (lines.isEmpty)
            AdvInfoLine(icon: Icons.schedule_rounded, text: t('لم تُحدد بعد — راسل مرشدك لتتفقا على موعد', 'Not set yet — message your advisor to agree on a time'))
          else ...[
            for (final (wd, text) in lines)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 92 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4), child: Text(advWeekdayLabel(wd), style: AppType.meta(context).copyWith(color: c.textDark))),
                  Expanded(child: Text(text, style: AppType.meta(context))),
                ]),
              ),
            if (a.hours.modes.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                for (final m in a.hours.modes) AppBadgePill(advMeetingModeLabelShort(m), color: c.primary, icon: advModeIcon(m)),
              ]),
            ],
          ],
          if (a.nextFree != null)
            AdvInfoLine(icon: Icons.event_available_rounded, color: c.success, text: t('أقرب موعد متاح: ${AppTime.date(a.nextFree!, pattern: 'EEE d MMM')} · ${AppTime.time(a.nextFree!)}', 'Next free: ${AppTime.date(a.nextFree!, pattern: 'EEE d MMM')} · ${AppTime.time(a.nextFree!)}')),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (onBook != null && a.bookable) AppButton.primary(label: t('احجز موعداً', 'Book a meeting'), icon: Icons.event_available_rounded, onPressed: canBook ? onBook : null),
            if (onMessage != null) AppButton.secondary(label: t('راسله', 'Message'), icon: Icons.chat_bubble_outline_rounded, onPressed: onMessage),
          ]),
        ]),
      ),
    );
  }
}

class AdvHubView extends StatelessWidget {
  const AdvHubView({
    super.key,
    required this.load,
    this.hub,
    this.errorText,
    this.now,
    this.onRetry,
    this.onBook,
    this.onMessage,
    this.onThreads,
    this.onSurvey,
    this.onAllAppointments,
    this.onSupport,
    this.apptActions = const AdvApptActions(),
  });

  final AdvLoad load;
  final AdvHub? hub;
  final String? errorText;
  final DateTime? now;
  final VoidCallback? onRetry, onThreads, onAllAppointments;

  /// Phase 7: the requests filed for me, my support plans and accommodations (AdvStudentSupportPage).
  final VoidCallback? onSupport;
  final ValueChanged<AdvHubAdvisor>? onBook, onMessage;
  final ValueChanged<AdvSurveyInfo>? onSurvey;
  final AdvApptActions apptActions;

  static const double wideFrom = 980;

  @override
  Widget build(BuildContext context) {
    final h = hub;
    if (load != AdvLoad.ready || h == null) return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry);
    final c = context.colors;
    if (h.advisors.isEmpty) {
      return AppEmpty(
        icon: Icons.person_search_rounded,
        title: t('لم يُسند إليك مرشد أكاديمي بعد', 'No academic advisor is assigned to you yet'),
        message: t('يسند مدير الإرشاد مرشداً لكل طالب، وتصلك رسالة حين يحدث ذلك.', 'The advising director assigns an advisor to every student; you are told when it happens.'),
      );
    }
    final blocked = h.bookBlocked;
    final surveys = [
      for (final s in h.surveys)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppBanner(
            icon: Icons.star_outline_rounded,
            color: c.warning,
            text: t('كيف كان لقاؤك مع ${s.advisorName}${s.dateText.isEmpty ? '' : ' (${s.dateText})'}؟ قيّمه دون اسمك.', 'How was your meeting with ${s.advisorName}${s.dateText.isEmpty ? '' : ' (${s.dateText})'}? Rate it anonymously.'),
            action: onSurvey == null ? null : TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)), onPressed: () => onSurvey!(s), child: Text(t('تقييم', 'Rate'))),
          ),
        ),
    ];
    final advisors = [
      AdvSectionTitle(h.advisors.length > 1 ? t('مرشدوك', 'Your advisors') : t('مرشدك', 'Your advisor'), first: true),
      for (final a in h.advisors)
        AdvAdvisorHubCard(advisor: a, canBook: blocked == null, onBook: onBook == null ? null : () => onBook!(a), onMessage: a.type == 'primary' || h.advisors.length == 1 ? (onMessage == null ? null : () => onMessage!(a)) : null),
      if (blocked != null && h.bookable.isNotEmpty) AppBanner(icon: Icons.info_outline_rounded, text: blocked),
    ];
    final t0 = h.threads;
    final messages = AppActionCard(
      icon: Icons.forum_outlined,
      title: t('رسائلي مع المرشد', 'Messages with my advisor'),
      subtitle: t0.unread > 0
          ? countText(t0.unread, ar1: 'رسالة جديدة', ar2: 'رسالتان جديدتان', arFew: '${t0.unread} رسائل جديدة', arMany: '${t0.unread} رسالة جديدة', en1: '1 new message', en: '${t0.unread} new messages')
          : (t0.open > 0
              ? countText(t0.open, ar1: 'محادثة مفتوحة', ar2: 'محادثتان مفتوحتان', arFew: '${t0.open} محادثات مفتوحة', arMany: '${t0.open} محادثة مفتوحة', en1: '1 open conversation', en: '${t0.open} open conversations')
              : t('أسئلة، طلبات، شكاوى', 'Questions, requests, complaints')),
      badge: t0.unread,
      onTap: onThreads,
    );
    final meetings = [
      AdvAppointmentList(
        upcoming: h.upcoming,
        past: h.past,
        actions: apptActions,
        now: now,
        pastTitle: t('آخر اللقاءات', 'Recent meetings'),
        emptyUpcoming: blocked == null ? t('لا مواعيد قادمة — احجز من بطاقة مرشدك', 'No upcoming meetings — book one from your advisor\'s card') : t('لا مواعيد قادمة', 'No upcoming meetings'),
      ),
      if (onAllAppointments != null && (h.past.length >= 5 || h.upcoming.isNotEmpty))
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: onAllAppointments,
            icon: const Icon(Icons.history_rounded),
            label: Text(t('كل مواعيدي', 'All my appointments')),
          ),
        ),
      Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(h.rules.cancelSummary, style: AppType.meta(context))),
    ];
    final notes = [
      AdvSectionTitle(t('من مرشدك', 'From your advisor'), subtitle: t('ملاحظات شاركها معك', 'Notes shared with you')),
      if (h.notes.isEmpty)
        Text(t('لا ملاحظات بعد', 'No notes yet'), style: AppType.body(context))
      else
        for (final n in h.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text([if (n.authorName.isNotEmpty) n.authorName, if (n.createdAt != null) AppTime.date(n.createdAt!)].join(' · '), style: AppType.meta(context)),
                const SizedBox(height: AppSpace.xxs),
                SelectionArea(child: AdvTypedText(n.body)),
              ]),
            ),
          ),
    ];
    final support = onSupport == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: AppActionCard(
              icon: Icons.support_outlined,
              title: t('الطلبات وخطة الدعم', 'Requests and support plan'),
              subtitle: t('طلباتك ومراحلها، خطتك وتسهيلاتك', 'Your requests and their stages, your plan and accommodations'),
              onTap: onSupport!,
            ),
          );
    return LayoutBuilder(builder: (context, box) {
      final pad = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl);
      if (box.maxWidth >= wideFrom) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(padding: pad, children: [
              ...surveys,
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...advisors, const SizedBox(height: AppSpace.sm), messages, support])),
                const SizedBox(width: AppSpace.lg),
                Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...meetings, ...notes])),
              ]),
            ]),
          ),
        );
      }
      return AdvPageFrame(maxWidth: 720, children: [...surveys, ...advisors, const SizedBox(height: AppSpace.xs), messages, support, const SizedBox(height: AppSpace.md), ...meetings, ...notes]);
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class AdvStudentHubPage extends StatelessWidget {
  const AdvStudentHubPage({super.key, required this.orgId, this.surveyToken});
  final int orgId;

  /// A survey deep link: opened once the hub shows.
  final String? surveyToken;

  @override
  Widget build(BuildContext context) => AdvCommScaffold(
        orgId: orgId,
        title: t('مرشدي الأكاديمي', 'My academic advisor'),
        maxWidth: 1200,
        child: _AdvHubBody(orgId: orgId, surveyToken: surveyToken),
      );
}

class _AdvHubBody extends StatefulWidget {
  const _AdvHubBody({required this.orgId, this.surveyToken});
  final int orgId;
  final String? surveyToken;

  @override
  State<_AdvHubBody> createState() => _AdvHubBodyState();
}

class _AdvHubBodyState extends State<_AdvHubBody> {
  late final AdvCommApi _api = AdvCommApi(widget.orgId, student: true);
  OrgPageRefresh? _refresh;
  StreamSubscription<LiveEvent>? _live;
  AdvHub? _hub;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  bool _surveyOpened = false;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _live = LiveEvents.instance.listen({LiveEvents.connectivity}, (_) {
      if (mounted && AppConnectivity.instance.isOnline && _load != AdvLoad.ready) _reload();
    });
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    _live?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final r = await orgCall(() => _api.hub(), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _hub = r.data as AdvHub;
        _load = AdvLoad.ready;
      } else if (_hub == null) {
        _load = advFailLoad(r);
        _error = advCommErrorText(r.error!);
      }
    });
    if (r.ok && mounted) {
      OrgPageRefresh.reportUpdated(context);
      final token = widget.surveyToken;
      if (token != null && !_surveyOpened) {
        _surveyOpened = true;
        _survey(AdvSurveyInfo(token: token));
      }
    }
  }

  List<(int, String)> get _advisors => [for (final a in _hub?.advisors ?? const <AdvHubAdvisor>[]) (a.userId, a.shown)];

  Future<void> _book(AdvHubAdvisor a) async {
    final h = _hub;
    if (h == null) return;
    final made = await showAdvBookingSheet(context, _api, advisors: [for (final x in h.bookable) (x.userId, x.shown)], rules: h.rules);
    if (made != null && mounted) _reload();
  }

  Future<void> _message(AdvHubAdvisor a) async {
    final made = await showAdvNewThreadSheet(context, _api, advisors: _advisors);
    if (made == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvThreadPage(orgId: widget.orgId, threadId: made.id, student: true, subject: made.subjectShown)));
    if (mounted) _reload();
  }

  Future<void> _threads() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvThreadsPage(orgId: widget.orgId, student: true, advisors: _advisors)));
    if (mounted) _reload();
  }

  Future<void> _survey(AdvSurveyInfo s) async {
    final done = await showAdvSurveySheet(context, _api, s.token, info: s.advisorName.isEmpty ? null : s);
    if (done && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final flow = AdvApptFlow(_api, rules: _hub?.rules ?? const AdvBookingRules(), onChanged: _reload, onChat: (_) => _threads());
    return AdvHubView(
      load: _load,
      hub: _hub,
      errorText: _error,
      onRetry: () {
        setState(() => _load = AdvLoad.loading);
        _reload();
      },
      onBook: _book,
      onMessage: _message,
      onThreads: _threads,
      onSurvey: _survey,
      onAllAppointments: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvAppointmentsPage(orgId: widget.orgId, student: true, onChat: (_) => _threads())));
        if (mounted) _reload();
      },
      onSupport: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentSupportPage(orgId: widget.orgId))),
      apptActions: flow.actions(context),
    );
  }
}
