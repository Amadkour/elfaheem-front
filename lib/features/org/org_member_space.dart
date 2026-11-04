// lib/features/org/org_member_space.dart
//
// The STUDENT / TEACHER side of an organization they belong to — one warm place:
//   News         announcements for me (pinned first)
//   Departments  who does what, where and when + "contact / complain" from the card
//   Requests     forms open for me (dynamic form filling) + my requests with their tracking numbers & status
//   Complaints   my complaints, the conversation, closing & rating
//   Courses      the organization's courses (existing screen) · Timetable (existing screen)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin/admin_common.dart';
import 'org_member_pages.dart' show OrgCoursesScreen, OrgTimetableScreen;
import 'org_my_exams.dart' show openMyExams;
import 'org_providers.dart';
import 'org_services_pages.dart' show ComplaintBubble;
import 'org_ui.dart';
import 'org_terms_pages.dart';
import 'org_departments_page.dart' show DeptLogo;
import 'org_member_parts.dart';
import 'org_academic_pages.dart' show MyAcademicPathPage;
import 'org_announcements.dart' show OrgAnnouncementFeed;
import 'org_dynamic_form.dart';
import 'org_join_pages.dart' show OrgJoinUnitsTab;
import 'org_platform_context.dart';

const _pub = '$orgBase/public';

class OrgMemberSpace extends StatelessWidget {
  const OrgMemberSpace({super.key, required this.org, this.initialTab = 0});
  final int initialTab;   // 0 news · 1 departments · 2 requests · 3 complaints · 4 regulations · 5 my path · 6 join
  final Map<String, dynamic> org;

  @override
  Widget build(BuildContext context) {
    final id = asInt(org['id']);
    return _OrgContextScope(
      orgId: id,
      child: DefaultTabController(
      length: 7,
      initialIndex: initialTab.clamp(0, 6),
      child: BasePage(
        useWebCard: true,
        maxWith: 900,
        child: Column(children: [
          // the organization's name always leads the page, with the way out to the personal space; one tab strip under it
          AppPageHeader(
            title: orgNameOf(org),
            subtitle: t('مساحتك: أخبارك وطلباتك وشكاواك', 'Your space: news, requests and complaints'),
            icon: Icons.apartment_rounded,
            onBack: () => Navigator.of(context).maybePop(),
            actions: [
              AppIconButton(
                  tooltip: t('المقررات', 'Courses'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgCoursesScreen(org: org))),
                  icon: Icons.menu_book_rounded),
              AppIconButton(
                  tooltip: t('جدولي', 'My timetable'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgTimetableScreen(orgId: id))),
                  icon: Icons.calendar_month_rounded),
              AppIconButton(
                  tooltip: t('امتحاناتي', 'My exams'),
                  onPressed: () => openMyExams(context, orgId: id),
                  icon: Icons.event_note_rounded),
              const ContextExitButton(),
            ],
          ),
          const _SpaceTabs(),
          Expanded(
            child: TabBarView(children: [
              OrgAnnouncementFeed(orgId: id),   // point 17: views · reactions · deep links
              _Directory(org: org),
              _Requests(orgId: id),
              _MyComplaints(org: org),
              OrgTermsView(orgId: id),
              MyAcademicPathPage(orgId: id),
              OrgJoinUnitsTab(orgId: id),
            ]),
          ),
        ]),
      ),
      ),
    );
  }
}

/// The seven tabs of the space as one underline strip (scrolls on a phone), driven by the DefaultTabController.
class _SpaceTabs extends StatelessWidget {
  const _SpaceTabs();

  @override
  Widget build(BuildContext context) {
    final ctl = DefaultTabController.of(context);
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider))),
      child: ListenableBuilder(
        listenable: ctl,
        builder: (context, _) => AppUnderlineTabs(
          index: ctl.index,
          onChanged: ctl.animateTo,
          items: [
            AppTabItem(t('الأخبار', 'News')),
            AppTabItem(t('الإدارات', 'Departments')),
            AppTabItem(t('طلباتي', 'Requests')),
            AppTabItem(t('شكاواي', 'Complaints')),
            AppTabItem(t('اللوائح', 'Regulations')),
            AppTabItem(t('مساري', 'My path')),
            AppTabItem(t('انضمام', 'Join')),
          ],
        ),
      ),
    );
  }
}

/// While the space is open its organization's timezone / 12h-24h and feature offs apply; leaving it restores
/// whatever organization (or the platform defaults) was applied before.
class _OrgContextScope extends StatefulWidget {
  const _OrgContextScope({required this.orgId, required this.child});
  final int orgId;
  final Widget child;

  @override
  State<_OrgContextScope> createState() => _OrgContextScopeState();
}

class _OrgContextScopeState extends State<_OrgContextScope> {
  int? _prev;

  @override
  void initState() {
    super.initState();
    _prev = OrgPlatformContext.openId;
    if (widget.orgId > 0) OrgPlatformContext.open(widget.orgId);
  }

  @override
  void dispose() {
    if (widget.orgId > 0 && _prev != widget.orgId) OrgPlatformContext.open(_prev);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Small loader used by every tab (GET → list).
mixin _Loader<T extends StatefulWidget> on State<T> {
  List<Map<String, dynamic>>? items;
  bool failed = false;
  String get url;
  Map<String, dynamic>? get query => null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final r = await OrgApi.i.getMap(url, query);
    if (!mounted) return;
    setState(() {
      items = r == null ? items : asMapList(r['items']);
      failed = r == null && items == null;
    });
  }

  Widget body(Widget Function(List<Map<String, dynamic>>) builder) => OrgAsync(
        loading: items == null && !failed,
        failed: failed,
        onRetry: load,
        child: items == null ? const SizedBox.shrink() : AppRefresh(onRefresh: load, child: builder(items!)),
      );
}

// ═════════════════════════ Departments directory ═════════════════════════

class _Directory extends StatefulWidget {
  const _Directory({required this.org});
  final Map<String, dynamic> org;

  @override
  State<_Directory> createState() => _DirectoryState();
}

class _DirectoryState extends State<_Directory> with _Loader<_Directory> {
  @override
  String get url => '$_pub/${widget.org['id']}/departments';

  @override
  Widget build(BuildContext context) {
    return body((list) => list.isEmpty
        ? ListView(children: [
            OrgEmpty(
              icon: Icons.apartment_rounded,
              title: t('لا إدارات منشورة بعد', 'No departments listed yet'),
              message: t('عند نشر المؤسسة لإداراتها ستجدها هنا. يمكنك طلب الانضمام لقسم من تبويب الانضمام.', 'Departments appear here once the organization publishes them. You can ask to join a unit from the Join tab.'),
              actionLabel: t('انضمام لقسم', 'Join a department'),
              onAction: () => DefaultTabController.maybeOf(context)?.animateTo(6),
            )
          ])
        : ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl), children: [
            for (final d in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      DeptLogo(d: d, size: 44),
                      AppSpace.gapSm,
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(orgNameOf(d), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                          if ('${d['description'] ?? ''}'.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpace.xxs),
                              child: Text('${d['description']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                            ),
                        ]),
                      ),
                    ]),
                    AppSpace.gapXs,
                    OrgInfoRow(Icons.place_rounded, '${d['location'] ?? ''}'),
                    OrgInfoRow(Icons.schedule_rounded, '${d['office_hours'] ?? ''}'),
                    OrgInfoRow(Icons.alternate_email_rounded, '${d['email'] ?? ''}', ltr: true),
                    OrgInfoRow(Icons.phone_rounded, '${d['phone'] ?? ''}', ltr: true),
                    if (d['accepts_complaints'] == true) ...[
                      AppSpace.gapXs,
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: AppPill(
                          label: t('تواصل / شكوى', 'Contact / complain'),
                          icon: Icons.chat_bubble_outline_rounded,
                          onTap: () => showComplaintComposer(context, widget.org, dept: d),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
          ]));
  }
}

// ═════════════════════════ Requests (forms) ═════════════════════════

class _Requests extends StatefulWidget {
  const _Requests({required this.orgId});
  final int orgId;

  @override
  State<_Requests> createState() => _RequestsState();
}

class _RequestsState extends State<_Requests> with _Loader<_Requests> {
  List<Map<String, dynamic>> _mine = [];

  @override
  String get url => '$_pub/me/forms';

  @override
  Map<String, dynamic> get query => {'org_id': widget.orgId};

  @override
  Future<void> load() async {
    final r = await OrgApi.i.getMap('$_pub/me/form-responses');
    _mine = asMapList(r?['items']).where((x) => asInt(x['org_id']) == widget.orgId).toList();
    await super.load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return body((forms) => ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl), children: [
          AppSection(
            title: t('نماذج متاحة لك', 'Forms open for you'),
            child: forms.isEmpty
                ? MemberNote(t('لا نماذج مفتوحة الآن', 'No open forms right now'), icon: Icons.edit_document)
                : Column(children: [
                    for (final f in forms)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.xs),
                        child: MemberRow(
                          icon: Icons.edit_document,
                          tone: f['can_answer'] == true ? c.primary : c.textLight,
                          title: '${f['title']}',
                          subtitle: [
                            if (asMap(f['department']).isNotEmpty) orgNameOf(asMap(f['department'])),
                            if (f['closes_at'] != null) '${t('حتى', 'until')} ${shortDate('${f['closes_at']}')}',
                          ].join(' · '),
                          trailing: f['can_answer'] == true ? null : AppStatusBadge(label: t('أُرسل', 'Sent'), tone: AppTone.success, icon: Icons.check_rounded, dense: true),
                          onTap: f['can_answer'] == true
                              ? () async {
                                  final sent = await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(builder: (_) => OrgFormFillScreen(formId: asInt(f['id']))));
                                  if (sent == true) load();
                                }
                              : null,
                        ),
                      ),
                  ]),
          ),
          AppSpace.gapLg,
          AppSection(
            title: t('طلباتي ومتابعتها', 'My requests'),
            child: _mine.isEmpty
                ? MemberNote(t('لم ترسل طلبات بعد. اختر نموذجاً من الأعلى لتبدأ.', 'No requests yet. Pick a form above to start one.'), icon: Icons.receipt_long_rounded)
                : Column(children: [
                    for (final r in _mine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.xs),
                        child: MemberRow(
                          icon: Icons.receipt_long_rounded,
                          tone: statusColor(context, '${r['status']}'),
                          title: '${r['form_title']}',
                          subtitle: [
                            '${r['ref']} · ${relTime(r['created_at'])}',
                            if ('${r['reviewer_note'] ?? ''}'.isNotEmpty) '${r['reviewer_note']}',
                          ].join('\n'),
                          trailing: MemberStatusBadge('${r['status']}',
                              label: r['status'] == 'approved'
                                  ? t('تمت الموافقة', 'Approved')
                                  : r['status'] == 'rejected'
                                      ? t('يحتاج منك', 'Needs you')
                                      : null),
                        ),
                      ),
                  ]),
          ),
        ]));
  }
}

class OrgFormFillScreen extends StatefulWidget {
  const OrgFormFillScreen({super.key, required this.formId});
  final int formId;

  @override
  State<OrgFormFillScreen> createState() => _OrgFormFillScreenState();
}

class _OrgFormFillScreenState extends State<OrgFormFillScreen> {
  Map<String, dynamic>? _f;
  bool _failed = false, _busy = false;
  final _answers = OrgFormAnswers();
  Set<String> _missing = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _answers.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap('$_pub/forms/${widget.formId}');
    if (!mounted) return;
    setState(() {
      _f = r;
      _failed = r == null;
    });
  }

  Future<void> _submit() async {
    final fields = asMapList(_f?['fields']);
    final answers = _answers.collect(fields);
    setState(() => _missing = _answers.missing(fields));
    if (_missing.isNotEmpty) {
      final f = fields.firstWhere((x) => _missing.contains('${x['key']}'));
      showAppNotice(t('«${f['label']}» مطلوب', '"${f['label']}" is required'), error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await OrgApi.i.post('$_pub/forms/${widget.formId}/responses', {'answers': answers});
    if (!mounted) return;
    setState(() => _busy = false);
    if (r is Map) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
          icon: Icon(Icons.check_circle_rounded, color: ctx.colors.success, size: AppIconSize.hero),
          title: Text(t('تم الإرسال', 'Sent'), textAlign: TextAlign.center, style: AppType.section(ctx)),
          content: Text('${r['message'] ?? ''}', textAlign: TextAlign.center, style: AppType.body(ctx)),
          actions: [AppButton.primary(label: t('حسناً', 'OK'), onPressed: () => Navigator.pop(ctx))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    }
  }

  Widget _field(Map<String, dynamic> f) => OrgDynamicField(
        field: f,
        answers: _answers,
        onChanged: () => setState(() {}),
        error: _missing.contains('${f['key']}') ? t('مطلوب', 'Required') : null,
        onUpload: () => orgPickAndUpload('$_pub/uploads'),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = _f;
    return BasePage(
      useWebCard: true,
      maxWith: 720,
      child: Column(children: [
        AppPageHeader(title: f == null ? t('نموذج', 'Form') : '${f['title']}', icon: Icons.edit_document, onBack: () => Navigator.of(context).maybePop()),
        Expanded(
          child: OrgAsync(
            loading: f == null && !_failed,
            failed: _failed,
            onRetry: _load,
            child: f == null
                ? const SizedBox.shrink()
                : ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl), children: [
                    if ('${f['description'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.md),
                        child: AppBanner(icon: Icons.info_outline_rounded, color: c.primary, text: '${f['description']}'),
                      ),
                    for (final x in asMapList(f['fields'])) _field(x),
                    AppSpace.gapSm,
                    AppButton.primary(label: t('إرسال', 'Send'), icon: Icons.send_rounded, busy: _busy, expand: true, onPressed: _submit),
                  ]),
          ),
        ),
      ]),
    );
  }
}

// ═════════════════════════ Complaints ═════════════════════════

Future<bool> showComplaintComposer(BuildContext context, Map<String, dynamic> org, {Map<String, dynamic>? dept}) async {
  final subject = TextEditingController();
  final body = TextEditingController();
  String category = 'general', priority = 'medium';
  bool anonymous = false, busy = false, sent = false;
  final files = <Map<String, dynamic>>[];
  final cats = {
    'academic': t('أكاديمية', 'Academic'),
    'administrative': t('إدارية', 'Administrative'),
    'financial': t('مالية', 'Financial'),
    'technical': t('تقنية', 'Technical'),
    'facilities': t('مرافق', 'Facilities'),
    'conduct': t('سلوك', 'Conduct'),
    'general': t('أخرى', 'Other'),
  };
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(dept == null ? t('شكوى أو اقتراح', 'Complaint or suggestion') : '${t('إلى', 'To')} ${orgNameOf(dept)}'),
            Text(t('نحن نسمعك. اكتب ما حدث بهدوء ووضوح — ستصلك متابعة برقم مرجعي.',
                    "We're listening. Describe what happened clearly — you'll get a reference number to follow up."),
                style: AppType.body(ctx).copyWith(color: c.textMedium)),
            AppSpace.gapSm,
            ChoiceRow<String>(label: t('النوع', 'Type'), options: cats, value: category, onChanged: (v) => set(() => category = v)),
            Field(controller: subject, label: t('العنوان', 'Subject')),
            Field(controller: body, label: t('التفاصيل', 'Details'), maxLines: 6),
            ChoiceRow<String>(
                label: t('مدى الإلحاح', 'How urgent?'),
                options: {'low': priorityLabel('low'), 'medium': priorityLabel('medium'), 'high': priorityLabel('high')},
                value: priority,
                onChanged: (v) => set(() => priority = v)),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final f in files) InputChip(label: Text('${f['name']}'), onDeleted: () => set(() => files.remove(f))),
              AppButton.secondary(
                label: t('إرفاق ملف', 'Attach a file'),
                icon: Icons.attach_file_rounded,
                size: AppButtonSize.sm,
                onPressed: () async {
                  final up = await orgPickAndUpload('$_pub/uploads');
                  if (up != null) set(() => files.add({'name': up['name'], 'url': up['url']}));
                },
              ),
            ]),
            OrgSwitchRow(
              title: t('إخفاء هويتي عن موظفي الإدارة', 'Hide my identity from department staff'),
              subtitle: t('لن يرى اسمك إلا مدير المؤسسة', 'Only the organization admin can see your name'),
              value: anonymous,
              onChanged: (v) => set(() => anonymous = v),
            ),
            AppSpace.gapXs,
            AppButton.primary(
              busy: busy,
              expand: true,
              label: t('إرسال', 'Send'),
              icon: Icons.send_rounded,
              onPressed: () async {
                if (subject.text.trim().length < 3 || body.text.trim().length < 5) {
                  showAppNotice(t('اكتب عنواناً وتفاصيل كافية', 'Add a subject and enough details'), error: true);
                  return;
                }
                set(() => busy = true);
                final r = await OrgApi.i.post('$_pub/${org['id']}/complaints', {
                  'dept_id': dept?['id'],
                  'subject': subject.text.trim(),
                  'body': body.text.trim(),
                  'category': category,
                  'priority': priority,
                  'is_anonymous': anonymous,
                  'attachments': files,
                });
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (r is Map) {
                  sent = true;
                  Navigator.pop(ctx);
                  showAppNotice('${r['message'] ?? t('وصلت شكواك', 'Received')}');
                }
              },
            ),
          ]),
        );
      }));
  return sent;
}

class _MyComplaints extends StatefulWidget {
  const _MyComplaints({required this.org});
  final Map<String, dynamic> org;

  @override
  State<_MyComplaints> createState() => _MyComplaintsState();
}

class _MyComplaintsState extends State<_MyComplaints> with _Loader<_MyComplaints> {
  @override
  String get url => '$_pub/me/complaints';

  Future<void> _compose() async {
    if (await showComplaintComposer(context, widget.org)) load();
  }

  @override
  Widget build(BuildContext context) {
    return body((all) {
      final list = all.where((x) => asInt(x['org_id']) == asInt(widget.org['id'])).toList();
      if (list.isEmpty) {
        return ListView(children: [
          OrgEmpty(
              icon: Icons.support_agent_rounded,
              title: t('لا شكاوى', 'No complaints'),
              message: t('إن واجهتك مشكلة فنحن هنا — رأيك يحسّن الخدمة للجميع', "If something goes wrong, we're here — your voice improves things for everyone"),
              actionLabel: t('شكوى جديدة', 'New complaint'),
              onAction: _compose),
        ]);
      }
      return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl), children: [
        // the one primary action of the tab, in reach (not a floating button over the list)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton.primary(label: t('شكوى جديدة', 'New complaint'), icon: Icons.edit_rounded, onPressed: _compose),
        ),
        AppSpace.gapSm,
        for (final x in list)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: MemberRow(
              icon: Icons.support_agent_rounded,
              tone: statusColor(context, '${x['status']}'),
              title: '${x['subject']}',
              subtitle: '${x['ref']} · ${relTime(x['updated_at'] ?? x['created_at'])}',
              trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                MemberStatusBadge('${x['status']}'),
                if (x['unread'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xxs),
                    child: AppStatusBadge(label: t('رد جديد', 'New reply'), tone: AppTone.brand, dot: true, dense: true),
                  ),
              ]),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgMyComplaintThread(id: asInt(x['id']))));
                load();
              },
            ),
          ),
      ]);
    });
  }
}

class OrgMyComplaintThread extends StatefulWidget {
  /// A complaint I filed in an organization (the member side: thread, reply, rate, reopen). Public for the profile's
  /// Complaints page (D-086).
  const OrgMyComplaintThread({super.key, required this.id});
  final int id;

  @override
  State<OrgMyComplaintThread> createState() => _OrgMyComplaintThreadState();
}

class _OrgMyComplaintThreadState extends State<OrgMyComplaintThread> {
  Map<String, dynamic>? _d;
  bool _failed = false, _sending = false;
  final _msg = TextEditingController();

  String get _url => '$_pub/complaints/${widget.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap(_url);
    if (!mounted) return;
    setState(() {
      _d = r ?? _d;
      _failed = r == null && _d == null;
    });
  }

  Future<void> _rate() async {
    int stars = 5;
    final note = TextEditingController();
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('كيف كانت تجربتك؟', 'How was your experience?')),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: AppIconSize.xl,
                  tooltip: t('$i من 5', '$i of 5'),
                  onPressed: () => set(() => stars = i),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_border_rounded, color: ctx.colors.warning),
                ),
            ]),
            Field(controller: note, label: t('كلمة لفريق الإدارة (اختياري)', 'A word for the team (optional)')),
            AppButton.primary(
              expand: true,
              label: t('إرسال التقييم', 'Send rating'),
              onPressed: () async {
                final r = await OrgApi.i.post('$_url/rate', {'rating': stars, 'note': note.text.trim()});
                if (r is Map) showAppNotice('${r['message'] ?? ''}');
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ]),
        )));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = _d;
    final st = '${d?['status'] ?? ''}';
    return BasePage(
      useWebCard: true,
      maxWith: 760,
      child: Column(children: [
        AppPageHeader(
            title: d == null ? t('شكواي', 'My complaint') : '${d['ref']}',
            icon: Icons.support_agent_rounded,
            onBack: () => Navigator.of(context).maybePop()),
        Expanded(
          child: OrgAsync(
        loading: d == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: d == null
            ? const SizedBox.shrink()
            : Column(children: [
                Expanded(
                  child: AppRefresh(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md), children: [
                      Section(
                        title: '${d['subject']}',
                        icon: Icons.support_agent_rounded,
                        trailing: MemberStatusBadge(st),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (asMap(d['department']).isNotEmpty)
                            Text('${t('إلى', 'To')} ${orgNameOf(asMap(d['department']))}', style: AppType.meta(context).copyWith(color: c.primary)),
                          AppSpace.gapXs,
                          Text('${d['body']}', style: AppType.body(context)),
                          if (d['due_at'] != null && (st == 'open' || st == 'in_progress'))
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: OrgPill('${t('نلتزم بالرد قبل', 'We reply by')} ${shortDateTime('${d['due_at']}')}', icon: Icons.timer_rounded),
                            ),
                        ]),
                      ),
                      for (final m in asMapList(d['messages'])) ComplaintBubble(m: m, staffView: false),
                      if (st == 'resolved' && d['rating'] == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: MemberRow(
                            icon: Icons.star_rounded,
                            tone: c.warning,
                            title: t('هل حُلّت مشكلتك؟', 'Was it solved?'),
                            subtitle: t('قيّم الخدمة وأغلق الشكوى', 'Rate the service and close it'),
                            onTap: _rate,
                          ),
                        ),
                      if (st == 'resolved' || st == 'closed')
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: AppPill(
                            label: t('ما زالت المشكلة قائمة؟ أعد فتحها', 'Still a problem? Reopen it'),
                            icon: Icons.replay_rounded,
                            onTap: () async {
                              if (await OrgApi.i.post('$_url/reopen', null, t('أُعيد فتح الشكوى', 'Reopened')) != null) _load();
                            },
                          ),
                        ),
                    ]),
                  ),
                ),
                if (st != 'closed')
                  Container(
                    padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.sm),
                    decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _msg,
                          minLines: 1,
                          maxLines: 4,
                          style: AppType.body(context),
                          decoration: InputDecoration(
                            hintText: t('اكتب ردك…', 'Write your reply…'),
                            filled: true,
                            fillColor: c.inputBg,
                            border: OutlineInputBorder(borderRadius: AppRadius.cardAll, borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      AppSpace.gapXs,
                      AppIconButton(
                        variant: AppIconButtonVariant.filled,
                        busy: _sending,
                        tooltip: t('إرسال', 'Send'), 
                        onPressed: _sending
                            ? null
                            : () async {
                                if (_msg.text.trim().isEmpty) return;
                                setState(() => _sending = true);
                                final r = await OrgApi.i.post('$_url/messages', {'body': _msg.text.trim()});
                                if (!mounted) return;
                                setState(() => _sending = false);
                                if (r != null) {
                                  _msg.clear();
                                  _load();
                                }
                              },
                        icon: Icons.send_rounded,
                      ),
                    ]),
                  ),
              ]),
          ),
        ),
      ]),
    );
  }
}
