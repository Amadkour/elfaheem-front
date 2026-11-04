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
import 'package:flutter_education_app/design/app_page_header.dart' show AppPageHeader;
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_member_pages.dart' show OrgCoursesScreen, OrgTimetableScreen;
import 'org_my_exams.dart' show openMyExams;
import 'org_providers.dart';
import 'org_services_pages.dart' show ComplaintBubble;
import 'org_ui.dart';
import 'org_terms_pages.dart';
import 'org_departments_page.dart' show DeptLogo;
import 'org_academic_pages.dart' show MyAcademicPathPage;
import 'org_announcements.dart' show OrgAnnouncementFeed;
import 'org_dynamic_form.dart';
import 'org_join_pages.dart' show OrgJoinUnitsTab;
import 'org_platform_context.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

const _pub = '$orgBase/public';

class OrgMemberSpace extends StatelessWidget {
  const OrgMemberSpace({super.key, required this.org, this.initialTab = 0});
  final int initialTab;   // 0 news · 1 departments · 2 requests · 3 complaints · 4 regulations · 5 my path · 6 join
  final Map<String, dynamic> org;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = orgColor(context, org);
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
          // the organization's name always leads the page, with the way out to the personal space
          AppPageHeader(
            title: orgNameOf(org),
            icon: Icons.apartment_rounded,
            onBack: () => Navigator.of(context).maybePop(),
            actions: [
          IconButton(
              tooltip: t('المقررات', 'Courses'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgCoursesScreen(org: org))),
              icon: const Icon(Icons.menu_book_rounded)),
          IconButton(
              tooltip: t('جدولي', 'My timetable'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrgTimetableScreen())),
              icon: const Icon(Icons.calendar_month_rounded)),
          IconButton(
              tooltip: t('امتحاناتي', 'My exams'),
              onPressed: () => openMyExams(context, orgId: id),
              icon: const Icon(Icons.event_note_rounded)),
          const ContextExitButton(),
            ],
          ),
          OrgHero(org: org, subtitle: t('مرحباً بك في مجتمعك 👋', 'Welcome to your community 👋')),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: col,
            indicatorColor: col,
            unselectedLabelColor: c.textMedium,
            labelStyle: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800),
            tabs: [
              Tab(icon: const Icon(Icons.campaign_rounded, size: 20), text: t('الأخبار', 'News')),
              Tab(icon: const Icon(Icons.apartment_rounded, size: 20), text: t('الإدارات', 'Departments')),
              Tab(icon: const Icon(Icons.assignment_rounded, size: 20), text: t('طلباتي', 'Requests')),
              Tab(icon: const Icon(Icons.support_agent_rounded, size: 20), text: t('شكاواي', 'Complaints')),
              Tab(icon: const Icon(Icons.gavel_rounded, size: 20), text: t('اللوائح', 'Regulations')),
              Tab(icon: const Icon(Icons.route_rounded, size: 20), text: t('مساري', 'My path')),
              Tab(icon: const Icon(Icons.group_add_rounded, size: 20), text: t('انضمام', 'Join')),
            ],
          ),
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
    final c = context.colors;
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
        : ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 40), children: [
            for (final d in list)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: hexColor(d['color'], c.primary).withValues(alpha: 0.25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    DeptLogo(d: d, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(orgNameOf(d), style: orgText(context, w: FontWeight.w800)),
                        if ('${d['description'] ?? ''}'.isNotEmpty)
                          Text('${d['description']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: orgText(context, size: 12, color: c.textMedium)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  OrgInfoRow(Icons.place_rounded, '${d['location'] ?? ''}'),
                  OrgInfoRow(Icons.schedule_rounded, '${d['office_hours'] ?? ''}'),
                  OrgInfoRow(Icons.alternate_email_rounded, '${d['email'] ?? ''}', ltr: true),
                  OrgInfoRow(Icons.phone_rounded, '${d['phone'] ?? ''}', ltr: true),
                  if (d['accepts_complaints'] == true)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () => showComplaintComposer(context, widget.org, dept: d),
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                        label: Text(t('تواصل / شكوى', 'Contact / complain'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ]),
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
    return body((forms) => ListView(padding: const EdgeInsets.fromLTRB(0, 6, 0, 40), children: [
          OrgSectionTitle(t('نماذج متاحة لك', 'Forms open for you')),
          if (forms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(t('لا نماذج مفتوحة الآن', 'No open forms right now'), style: orgText(context, color: c.textMedium)),
            ),
          for (final f in forms)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: OrgActionCard(
                icon: Icons.edit_document,
                color: f['can_answer'] == true ? c.primary : c.textLight,
                title: '${f['title']}',
                subtitle: [
                  if (asMap(f['department']).isNotEmpty) orgNameOf(asMap(f['department'])),
                  if (f['closes_at'] != null) '${t('حتى', 'until')} ${shortDate('${f['closes_at']}')}',
                  if (f['can_answer'] != true) t('أرسلته ✓', 'Sent ✓'),
                ].join(' · '),
                onTap: f['can_answer'] == true
                    ? () async {
                        final sent = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(builder: (_) => OrgFormFillScreen(formId: asInt(f['id']))));
                        if (sent == true) load();
                      }
                    : null,
              ),
            ),
          OrgSectionTitle(t('طلباتي ومتابعتها', 'My requests')),
          if (_mine.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(t('لم ترسل طلبات بعد', 'No requests yet'), style: orgText(context, color: c.textMedium)),
            ),
          for (final r in _mine)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: RowCard(
                child: Row(children: [
                  IconBadge(Icons.receipt_long_rounded, statusColor(context, '${r['status']}'), size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r['form_title']}', style: orgText(context, w: FontWeight.w800)),
                      Text('${r['ref']} · ${relTime(r['created_at'])}', textDirection: TextDirection.ltr,
                          style: orgText(context, size: 12, color: c.textMedium)),
                      if ('${r['reviewer_note'] ?? ''}'.isNotEmpty)
                        Text('💬 ${r['reviewer_note']}', style: orgText(context, size: 12.5, color: c.textDark)),
                    ]),
                  ),
                  StatusChip(r['status'] == 'approved' ? t('تمت الموافقة', 'Approved') : r['status'] == 'rejected' ? t('يحتاج منك', 'Needs you') : statusLabel('${r['status']}'),
                      statusColor(context, '${r['status']}')),
                ]),
              ),
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
      toast(t('«${f['label']}» مطلوب', '"${f['label']}" is required'), error: true);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          icon: Icon(Icons.check_circle_rounded, color: ctx.colors.success, size: 56),
          title: Text(t('تم الإرسال', 'Sent'), textAlign: TextAlign.center),
          content: Text('${r['message'] ?? ''}', textAlign: TextAlign.center, style: TextStyle(fontFamily: AppFonts.family, height: 1.5)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('حسناً', 'OK')))],
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
      appBar: ScreenAppBar(title: f == null ? t('نموذج', 'Form') : '${f['title']}'),
      child: OrgAsync(
        loading: f == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: f == null
            ? const SizedBox.shrink()
            : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
                if ('${f['description'] ?? ''}'.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(18)),
                    child: Text('${f['description']}', style: orgText(context)),
                  ),
                for (final x in asMapList(f['fields'])) _field(x),
                const SizedBox(height: 8),
                PrimaryButton(isLoading: _busy, label: t('إرسال', 'Send'), icon: Icons.send_rounded, iconBefore: true, onPressed: _submit),
              ]),
      ),
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(dept == null ? t('شكوى أو اقتراح', 'Complaint or suggestion') : '${t('إلى', 'To')} ${orgNameOf(dept)}'),
            Text(t('نحن نسمعك. اكتب ما حدث بهدوء ووضوح — ستصلك متابعة برقم مرجعي.',
                    "We're listening. Describe what happened clearly — you'll get a reference number to follow up."),
                style: orgText(ctx, size: 12.5, color: c.textMedium)),
            const SizedBox(height: 12),
            ChoiceRow<String>(label: t('النوع', 'Type'), options: cats, value: category, onChanged: (v) => set(() => category = v)),
            Field(controller: subject, label: t('العنوان', 'Subject')),
            Field(controller: body, label: t('التفاصيل', 'Details'), maxLines: 6),
            ChoiceRow<String>(
                label: t('مدى الإلحاح', 'How urgent?'),
                options: {'low': priorityLabel('low'), 'medium': priorityLabel('medium'), 'high': priorityLabel('high')},
                value: priority,
                onChanged: (v) => set(() => priority = v)),
            Wrap(spacing: 6, children: [
              for (final f in files) InputChip(label: Text('${f['name']}'), onDeleted: () => set(() => files.remove(f))),
              ActionChip(
                avatar: const Icon(Icons.attach_file_rounded, size: 16),
                label: Text(t('إرفاق', 'Attach')),
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
            const SizedBox(height: 8),
            PrimaryButton(
              isLoading: busy,
              label: t('إرسال', 'Send'),
              icon: Icons.send_rounded,
              iconBefore: true,
              onPressed: () async {
                if (subject.text.trim().length < 3 || body.text.trim().length < 5) {
                  toast(t('اكتب عنواناً وتفاصيل كافية', 'Add a subject and enough details'), error: true);
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
                  toast('${r['message'] ?? t('وصلت شكواك', 'Received')}');
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'my_complaint',
        backgroundColor: c.primary,
        onPressed: () async {
          if (await showComplaintComposer(context, widget.org)) load();
        },
        icon: Icon(Icons.edit_rounded, color: c.onHero),
        label: Text(t('شكوى جديدة', 'New complaint'), style: TextStyle(fontFamily: AppFonts.family, color: c.onHero)),
      ),
      body: body((all) {
        final list = all.where((x) => asInt(x['org_id']) == asInt(widget.org['id'])).toList();
        return list.isEmpty
            ? ListView(children: [
                OrgEmpty(icon: Icons.support_agent_rounded, title: t('لا شكاوى', 'No complaints'),
                    message: t('إن واجهتك مشكلة فنحن هنا — رأيك يحسّن الخدمة للجميع', "If something goes wrong, we're here — your voice improves things for everyone"),
                    actionLabel: t('شكوى جديدة', 'New complaint'),
                    onAction: () async {
                      if (await showComplaintComposer(context, widget.org)) load();
                    }),
              ])
            : ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 100), children: [
                for (final x in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RowCard(
                      accent: x['unread'] == true ? c.primary : null,
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgMyComplaintThread(id: asInt(x['id']))));
                        load();
                      },
                      child: Row(children: [
                        IconBadge(Icons.support_agent_rounded, statusColor(context, '${x['status']}'), size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${x['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
                            Text('${x['ref']} · ${relTime(x['updated_at'] ?? x['created_at'])}',
                                style: orgText(context, size: 12, color: c.textMedium)),
                          ]),
                        ),
                        if (x['unread'] == true) OrgPill(t('رد جديد', 'New reply'), color: c.primary),
                        const SizedBox(width: 4),
                        StatusChip(statusLabel('${x['status']}'), statusColor(context, '${x['status']}')),
                      ]),
                    ),
                  ),
              ]);
      }),
    );
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('كيف كانت تجربتك؟', 'How was your experience?')),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 36,
                  tooltip: t('$i من 5', '$i of 5'),
                  onPressed: () => set(() => stars = i),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_border_rounded, color: ctx.colors.warning),
                ),
            ]),
            Field(controller: note, label: t('كلمة لفريق الإدارة (اختياري)', 'A word for the team (optional)')),
            PrimaryButton(
              isLoading: false,
              label: t('إرسال التقييم', 'Send rating'),
              onPressed: () async {
                final r = await OrgApi.i.post('$_url/rate', {'rating': stars, 'note': note.text.trim()});
                if (r is Map) toast('${r['message'] ?? ''}');
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
      appBar: ScreenAppBar(title: d == null ? t('شكواي', 'My complaint') : '${d['ref']}'),
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
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
                      Section(
                        title: '${d['subject']}',
                        icon: Icons.support_agent_rounded,
                        trailing: StatusChip(statusLabel(st), statusColor(context, st)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (asMap(d['department']).isNotEmpty)
                            Text('${t('إلى', 'To')} ${orgNameOf(asMap(d['department']))}', style: orgText(context, size: 12, color: c.primary)),
                          const SizedBox(height: 6),
                          Text('${d['body']}', style: orgText(context)),
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
                          child: OrgActionCard(
                            icon: Icons.star_rounded,
                            color: c.warning,
                            title: t('هل حُلّت مشكلتك؟', 'Was it solved?'),
                            subtitle: t('قيّم الخدمة وأغلق الشكوى', 'Rate the service and close it'),
                            onTap: _rate,
                          ),
                        ),
                      if (st == 'resolved' || st == 'closed')
                        TextButton.icon(
                          onPressed: () async {
                            if (await OrgApi.i.post('$_url/reopen', null, t('أُعيد فتح الشكوى', 'Reopened')) != null) _load();
                          },
                          icon: const Icon(Icons.replay_rounded),
                          label: Text(t('ما زالت المشكلة قائمة؟ أعد فتحها', 'Still a problem? Reopen it'), style: TextStyle(fontFamily: AppFonts.family)),
                        ),
                    ]),
                  ),
                ),
                if (st != 'closed')
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _msg,
                          minLines: 1,
                          maxLines: 4,
                          style: TextStyle(fontFamily: AppFonts.family),
                          decoration: InputDecoration(
                            hintText: t('اكتب ردك…', 'Write your reply…'),
                            filled: true,
                            fillColor: c.inputBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(tooltip: t('إرسال', 'Send'), 
                        style: IconButton.styleFrom(backgroundColor: c.primary),
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
                        icon: Icon(Icons.send_rounded, color: c.onHero),
                      ),
                    ]),
                  ),
              ]),
      ),
    );
  }
}
