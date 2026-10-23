// lib/features/org/org_registrar_member.dart — the registrar for members (API: /public/{org}/registrar/…).
//
//   OrgRegistrationScreen   the term's offerings: what I may register, why not (with the way out: other sections,
//                           waitlist, "request an exception"), a cart (co-requisites go together), drop / withdraw
//   OrgRecordScreen         GPA · earned hours · standing · level, the degree audit and the transcript
//   OrgTeachScreen          instructors: my courses per term → roster → grades (draft → submit for approval)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin/admin_common.dart';
import 'org_providers.dart';
import 'org_registrar.dart';
import 'org_v3.dart';

String _pub(int orgId) => '$orgBase/public/$orgId/registrar';

String _courseTitle(Map<String, dynamic> c) {
  final name = t('${c['name_ar'] ?? c['name_en'] ?? ''}', '${c['name_en'] ?? c['name_ar'] ?? ''}');
  return c['code'] == null ? name : '${c['code']} · $name';
}

Future<void> openRegistration(BuildContext context, int orgId) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgRegistrationScreen(orgId: orgId)));

Future<void> openRecord(BuildContext context, int orgId) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgRecordScreen(orgId: orgId)));

Future<void> openTeaching(BuildContext context, int orgId) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgTeachScreen(orgId: orgId)));

// ═════════════════════════════════════════════════════════════════════════════
//  Registration
// ═════════════════════════════════════════════════════════════════════════════

class OrgRegistrationScreen extends StatefulWidget {
  const OrgRegistrationScreen({super.key, required this.orgId});
  final int orgId;

  @override
  State<OrgRegistrationScreen> createState() => _OrgRegistrationScreenState();
}

class _OrgRegistrationScreenState extends State<OrgRegistrationScreen> {
  List<Map<String, dynamic>>? _terms;
  int? _termId;
  Map<String, dynamic>? _data;
  bool _failed = false, _busy = false;
  final _cart = RegCart();

  String get _b => _pub(widget.orgId);

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    final r = await orgCall(() => OrgApi.i.api.get('$_b/terms'), quiet: true);
    if (!mounted) return;
    final items = asMapList(r.map['items']);
    final open = items.where((x) => const {'registration', 'add_drop'}.contains(x['window'])).firstOrNull;
    setState(() {
      _terms = items;
      _failed = !r.ok;
      _termId = asInt((open ?? items.firstOrNull)?['id']);
    });
    if (_termId != null && _termId! > 0) _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => OrgApi.i.api.get('$_b/terms/$_termId/offerings'), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) _data = r.map;
      _failed = !r.ok && _data == null;
    });
  }

  List<Map<String, dynamic>> get _items => asMapList(_data?['items']);

  Map<int, Map<String, dynamic>> get _courses => {for (final o in _items) asInt(asMap(o['course'])['id']): asMap(o['course'])};

  String _name(int id) {
    final c = _courses[id];
    return c == null ? '#$id' : '${c['code'] ?? _courseTitle(c)}';
  }

  Set<int> get _registered => {
        for (final o in _items)
          if (const {'registered', 'waitlisted'}.contains(asMap(o['registration'])['status'])) asInt(asMap(o['course'])['id']),
      };

  Future<void> _add(Map<String, dynamic> o, {int? section, int? lab}) async {
    final c = asMap(o['course']);
    final id = asInt(c['id']);
    _cart.put(id, asDouble(c['credits']), section: section, lab: lab);
    final missing = RegCart.missingCoreqs(c, _cart.items.keys.toSet(), _registered);
    for (final m in missing) {
      final other = _items.where((x) => asInt(asMap(x['course'])['id']) == m).firstOrNull;
      if (other != null) _cart.put(m, asDouble(asMap(other['course'])['credits']));
    }
    if (missing.isNotEmpty) {
      toast(t('أُضيفت المقررات المتزامنة معه: ${missing.map(_name).join('، ')}', 'Its co-requisites were added: ${missing.map(_name).join(', ')}'));
    }
    setState(() {});
  }

  Future<void> _submit() async {
    if (_cart.isEmpty) return;
    setState(() => _busy = true);
    final r = await orgCall(() => OrgApi.i.api.post('$_b/terms/$_termId/register', body: {'items': _cart.toJson()}), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    final results = asMap(r.ok ? r.map['results'] : r.detail['results']);
    final lines = <String>[];
    results.forEach((cid, v) {
      final m = asMap(v);
      final st = '${m['status']}';
      final why = st == 'rejected' ? blockText(asMapList(m['blocks']).firstOrNull ?? const {}, courseName: _name) : regStatusText(st);
      lines.add('${_name(asInt(cid))}: $why');
    });
    if (r.ok) _cart.clear();
    if (lines.isEmpty && !r.ok) lines.add(orgErrorText(r.error!));
    await showAppSheet(context, (_) => _ResultSheet(ok: r.ok && r.map['ok'] == true, lines: lines));
    _load();
  }

  Future<void> _drop(Map<String, dynamic> reg) async {
    final w = asMap(_data?['term'])['window'];
    final msg = w == 'withdraw'
        ? t('الانسحاب يُسجَّل في السجل بتقدير W ولا يدخل في المعدل. متابعة؟', 'Withdrawal is recorded as W (not in the GPA). Continue?')
        : t('حذف المقرر من تسجيلك؟', 'Drop this course?');
    if (!await appConfirm(context, message: msg, danger: true)) return;
    final r = await orgCall(() => OrgApi.i.api.post('$_b/registrations/${reg['id']}/drop'),
        ok: t('تم', 'Done'));
    if (r.ok) _load();
  }

  Future<void> _exception(Map<String, dynamic> o) async {
    final ctrl = TextEditingController();
    final ok = await showAppSheet<bool>(context, (ctx) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle(t('طلب استثناء', 'Request an exception'), subtitle: _courseTitle(asMap(o['course']))),
            const SizedBox(height: 8),
            AppBanner(icon: Icons.info_outline_rounded, text: t('يراجعه المرشد / شؤون الطلاب، وستصلك النتيجة.', 'Your advisor / registrar reviews it and you will be notified.')),
            const SizedBox(height: 12),
            AppField(controller: ctrl, label: t('السبب', 'Reason'), maxLines: 3),
            const SizedBox(height: 12),
            AppPrimaryButton(label: t('إرسال', 'Send'), icon: Icons.send_rounded, onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ));
    if (ok != true || ctrl.text.trim().length < 3) return;
    await orgCall(() => OrgApi.i.api.post('$_b/terms/$_termId/exception',
        body: {'course_id': asMap(o['course'])['id'], 'reason': ctrl.text.trim()}), ok: t('أُرسل الطلب', 'Request sent'));
  }

  Future<void> _chooseSections(Map<String, dynamic> o) async {
    final secs = asMapList(o['sections']);
    final lec = secs.where((s) => s['kind'] == 'lecture').toList();
    final lab = secs.where((s) => s['kind'] == 'lab').toList();
    int? pickL = lec.isEmpty ? null : asInt(lec.first['id']), pickB = lab.isEmpty ? null : asInt(lab.first['id']);
    final ok = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          Widget group(String title, List<Map<String, dynamic>> list, int? cur, ValueChanged<int> on) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSectionTitle(title),
                  for (final s in list)
                    _SectionTile(section: s, selected: asInt(s['id']) == cur, onTap: () => set(() => on(asInt(s['id'])))),
                ],
              );
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (lec.isNotEmpty) group(t('المحاضرة', 'Lecture'), lec, pickL, (v) => pickL = v),
              if (lab.isNotEmpty) group(t('العملي', 'Lab'), lab, pickB, (v) => pickB = v),
              const SizedBox(height: 12),
              AppPrimaryButton(label: t('إضافة للسلة', 'Add to cart'), icon: Icons.add_shopping_cart_rounded,
                  onPressed: () => Navigator.pop(ctx, true)),
            ]),
          );
        }));
    if (ok == true) _add(o, section: pickL, lab: pickB);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final term = asMap(_data?['term']);
    final lim = asMap(_data?['limits']);
    final load = asDouble(_data?['load']);
    final after = loadAfter(load, _cart.credits, lim);
    return BasePage(
      useWebCard: true,
      maxWith: 1000,
      appBar: ScreenAppBar(title: t('تسجيل المقررات', 'Course registration')),
      child: AppAsync(
        loading: _terms == null || (_data == null && !_failed && (_terms ?? const []).isNotEmpty),
        failed: _failed,
        onRetry: _loadTerms,
        child: (_terms ?? const []).isEmpty
            ? AppEmpty(icon: Icons.event_busy_rounded, title: t('لا يوجد فصل دراسي مفتوح', 'No open term'))
            : Column(children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      AppHero(
                        title: termTitle(term),
                        subtitle: windowText('${term['window']}'),
                        icon: Icons.how_to_reg_rounded,
                        stats: [
                          AppHeroStat(icon: Icons.timer_outlined, value: '${load.toStringAsFixed(0)} / ${lim['max'] ?? '—'}', label: t('ساعاتي', 'My hours')),
                          AppHeroStat(icon: Icons.trending_up_rounded, value: gpaText(_data?['cgpa']), label: t('المعدل التراكمي', 'CGPA')),
                          AppHeroStat(icon: Icons.verified_rounded, value: asDouble(_data?['earned']).toStringAsFixed(0), label: t('ساعات مكتسبة', 'Earned hours')),
                        ],
                      ),
                      if ((_terms ?? const []).length > 1)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(children: [
                            for (final x in _terms!)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(end: 8),
                                child: AppChoiceChip(label: termTitle(x), selected: asInt(x['id']) == _termId, onTap: () {
                                  setState(() {
                                    _termId = asInt(x['id']);
                                    _data = null;
                                    _cart.clear();
                                  });
                                  _load();
                                }),
                              ),
                          ]),
                        ),
                      if (_data?['below_min'] == true && asInt(lim['min']) > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: AppBanner(icon: Icons.info_outline_rounded, color: c.warning,
                              text: t('الحد الأدنى للعبء ${lim['min']} ساعة هذا الفصل', 'The minimum load this term is ${lim['min']} hours')),
                        ),
                      if (lim['graduating'] == true)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: AppBanner(icon: Icons.school_rounded, color: c.success,
                              text: t('أنت طالب متوقع تخرجه: يمكنك تسجيل كل ما تبقى لك', 'You are graduating: you may register everything you have left')),
                        ),
                      const SizedBox(height: 8),
                      if (_items.isEmpty)
                        AppEmpty(icon: Icons.menu_book_rounded, title: t('لا توجد مقررات مطروحة بعد', 'No courses offered yet'))
                      else
                        for (final o in _items)
                          _OfferingCard(
                            offering: o,
                            inCart: _cart.has(asInt(asMap(o['course'])['id'])),
                            courseName: _name,
                            onAdd: () => asMapList(o['sections']).length > 1 ? _chooseSections(o) : _add(o),
                            onRemove: () => setState(() => _cart.remove(asInt(asMap(o['course'])['id']))),
                            onDrop: () => _drop(asMap(o['registration'])),
                            onException: () => _exception(o),
                          ),
                    ]),
                  ),
                ),
                if (!_cart.isEmpty)
                  SafeArea(
                    top: false,
                    child: AppCard(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(t('${_cart.items.length} مقرر في السلة', '${_cart.items.length} course(s) in the cart'),
                                style: appText(14, w: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(t('${after.load.toStringAsFixed(0)} ساعة من ${after.max}', '${after.load.toStringAsFixed(0)} of ${after.max} hours'),
                                style: appText(12, c: after.over ? c.danger : c.textMedium), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: AppPrimaryButton(label: t('سجّل', 'Register'), icon: Icons.check_rounded, busy: _busy, onPressed: _submit),
                        ),
                      ]),
                    ),
                  ),
              ]),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.selected, required this.onTap});
  final Map<String, dynamic> section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final seats = asInt(section['seats']);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      onTap: onTap,
      child: Row(children: [
        Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? c.primary : c.textLight),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sectionLabel(section), style: appText(14, w: FontWeight.w700)),
            Text([for (final m in asMapList(section['meetings'])) meetingText(m)].join(' · '),
                style: appText(12, c: c.textMedium), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        AppBadgePill(seats > 0 ? t('$seats مقعد', '$seats seats') : t('ممتلئة', 'Full'), color: seats > 0 ? c.success : c.warning),
      ]),
    );
  }
}

class _OfferingCard extends StatelessWidget {
  const _OfferingCard({
    required this.offering,
    required this.inCart,
    required this.courseName,
    required this.onAdd,
    required this.onRemove,
    required this.onDrop,
    required this.onException,
  });

  final Map<String, dynamic> offering;
  final bool inCart;
  final String Function(int) courseName;
  final VoidCallback onAdd, onRemove, onDrop, onException;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final course = asMap(offering['course']);
    final reg = asMap(offering['registration']);
    final status = '${reg['status'] ?? ''}';
    final live = const {'registered', 'waitlisted'}.contains(status);
    final blocks = asMapList(offering['blocks']);
    final warnings = asMapList(offering['warnings']);
    final canEx = blocks.isNotEmpty && blocks.every((b) => b['exception'] == true);
    final secs = asMapList(offering['sections']);
    return AppCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_courseTitle(course), style: appText(15, w: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${asDouble(course['credits']).toStringAsFixed(0)} ${t('ساعات', 'credits')} · ${courseKindText('${course['kind']}')}',
                  style: appText(12, c: c.textMedium)),
            ]),
          ),
          const SizedBox(width: 8),
          if (live)
            AppBadgePill(status == 'waitlisted' && reg['waitlist_position'] != null
                    ? t('انتظار #${reg['waitlist_position']}', 'Waitlist #${reg['waitlist_position']}')
                    : regStatusText(status),
                color: status == 'registered' ? c.success : c.warning)
          else if (offering['can_register'] == true)
            AppBadgePill(offering['full'] == true ? t('انتظار', 'Waitlist') : t('متاح', 'Open'),
                color: offering['full'] == true ? c.warning : c.primary),
        ]),
        if (secs.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text([for (final s in secs.take(3)) '${sectionLabel(s)}: ${[for (final m in asMapList(s['meetings'])) meetingText(m)].join('، ')}'].join('\n'),
              style: appText(12, c: c.textLight), maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.block_rounded, size: 16, color: c.danger),
              const SizedBox(width: 6),
              Expanded(child: Text(blockText(b, courseName: courseName), style: appText(12, c: c.danger))),
            ]),
          ),
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 16, color: c.warning),
              const SizedBox(width: 6),
              Expanded(child: Text(registrarCodeText('${w['code']}'), style: appText(12, c: c.textMedium))),
            ]),
          ),
        if (asMapList(offering['alternatives']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                '${t('بدائل متاحة', 'Available alternatives')}: ${[for (final a in asMapList(offering['alternatives'])) sectionLabel(a)].join('، ')}',
                style: appText(12, c: c.primary)),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          if (live)
            AppPill(icon: Icons.remove_circle_outline_rounded, label: t('حذف / انسحاب', 'Drop / withdraw'), color: c.danger, onTap: onDrop)
          else if (inCart)
            AppPill(icon: Icons.remove_shopping_cart_rounded, label: t('إزالة من السلة', 'Remove from cart'), onTap: onRemove)
          else if (offering['can_register'] == true || blocks.every((b) => b['code'] == 'missing_prereq' && _coreqOnly(b)))
            AppPill(icon: Icons.add_shopping_cart_rounded, label: t('أضف للسلة', 'Add to cart'), onTap: onAdd),
          if (!live && canEx) AppPill(icon: Icons.outgoing_mail, label: t('طلب استثناء', 'Request an exception'), onTap: onException),
        ]),
      ]),
    );
  }

  /// A "missing prerequisite" that is only a co-requisite to take together — the cart solves it.
  static bool _coreqOnly(Map<String, dynamic> b) {
    final m = asMapList(b['missing']);
    return m.isNotEmpty && m.every((x) => x['mode'] == 'coreq' || x['mode'] == 'concurrent');
  }
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.ok, required this.lines});
  final bool ok;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 48, color: ok ? c.success : c.warning),
        const SizedBox(height: 8),
        Text(ok ? t('تم التسجيل', 'Registered') : t('راجع النتيجة', 'Check the result'),
            textAlign: TextAlign.center, style: appText(16, w: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l, style: appText(13))),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Record: GPA · audit · transcript
// ═════════════════════════════════════════════════════════════════════════════

class OrgRecordScreen extends StatefulWidget {
  const OrgRecordScreen({super.key, required this.orgId, this.studentId});
  final int orgId;
  final int? studentId;          // staff view (…/registrar/students/{uid}/record)

  @override
  State<OrgRecordScreen> createState() => _OrgRecordScreenState();
}

class _OrgRecordScreenState extends State<OrgRecordScreen> {
  Map<String, dynamic>? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = widget.studentId == null
        ? '${_pub(widget.orgId)}/record'
        : '$orgBase/orgs/${widget.orgId}/registrar/students/${widget.studentId}/record';
    final r = await orgCall(() => OrgApi.i.api.get(path), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) _data = r.map;
      _failed = !r.ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      maxWith: 1000,
      appBar: ScreenAppBar(title: t('السجل الأكاديمي', 'Academic record')),
      child: AppAsync(
        loading: _data == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: _data == null ? const SizedBox() : RecordView(data: _data!),
      ),
    );
  }
}

class RecordView extends StatelessWidget {
  const RecordView({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final audit = asMap(data['audit']);
    final prog = asMap(data['program']);
    final standing = '${data['standing'] ?? ''}';
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      AppHero(
        title: prog.isEmpty ? t('السجل الأكاديمي', 'Academic record') : t('${prog['name_ar'] ?? prog['code']}', '${prog['name_en'] ?? prog['code']}'),
        subtitle: [standingText(standing), if (data['level'] != null) t('المستوى ${data['level']}', 'Level ${data['level']}')]
            .where((x) => x.isNotEmpty).join(' · '),
        icon: Icons.school_rounded,
        stats: [
          AppHeroStat(icon: Icons.trending_up_rounded, value: gpaText(data['cgpa']), label: t('المعدل التراكمي', 'CGPA')),
          AppHeroStat(icon: Icons.verified_rounded, value: asDouble(data['earned']).toStringAsFixed(0), label: t('ساعات مكتسبة', 'Earned')),
          AppHeroStat(icon: Icons.flag_rounded, value: asDouble(audit['remaining_credits']).toStringAsFixed(0), label: t('متبقٍ للتخرج', 'Left to graduate')),
        ],
      ),
      if (standing == 'probation')
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AppBanner(icon: Icons.warning_amber_rounded, color: c.danger,
              text: t('أنت تحت الإنذار الأكاديمي — حدّك الأقصى للساعات أقل، تواصل مع مرشدك', 'You are on probation — your maximum load is lower; talk to your advisor')),
        ),
      if (audit['eligible'] == true)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AppBanner(icon: Icons.celebration_rounded, color: c.success,
              text: t('استوفيت متطلبات التخرج — بانتظار الاعتماد النهائي', 'You meet the graduation requirements — awaiting final approval')),
        ),
      if (asMapList(audit['groups']).isNotEmpty) ...[
        AppSectionTitle(t('متطلبات التخرج', 'Degree requirements')),
        for (final g in asMapList(audit['groups']))
          AppCard(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(t('${g['label_ar'] ?? g['key']}', '${g['label_en'] ?? g['key']}'), style: appText(14, w: FontWeight.w700))),
                Text('${asDouble(g['have']).toStringAsFixed(0)} / ${asDouble(g['need']).toStringAsFixed(0)}',
                    style: appText(13, w: FontWeight.w700, c: g['done'] == true ? c.success : c.textMedium)),
              ]),
              const SizedBox(height: 6),
              AppProgressBar(value: asDouble(g['have']), max: asDouble(g['need'], 1) <= 0 ? 1 : asDouble(g['need']),
                  color: g['done'] == true ? c.success : c.primary),
              if ((g['missing_required'] as List?)?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(t('مقررات إجبارية متبقية: ${(g['missing_required'] as List).length}', 'Required courses left: ${(g['missing_required'] as List).length}'),
                      style: appText(12, c: c.textMedium)),
                ),
            ]),
          ),
      ],
      AppSectionTitle(t('كشف الدرجات', 'Transcript')),
      if (asMapList(data['terms']).isEmpty)
        AppEmpty(icon: Icons.history_edu_rounded, title: t('لا توجد مقررات بعد', 'No courses yet')),
      for (final tr in asMapList(data['terms']))
        AppCard(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(termTitle(asMap(tr['term'])), style: appText(14, w: FontWeight.w700))),
              if (tr['term_gpa'] != null) AppBadgePill('${t('معدل الفصل', 'Term GPA')} ${gpaText(tr['term_gpa'])}', color: c.primary),
            ]),
            const SizedBox(height: 6),
            for (final x in asMapList(tr['courses']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(_courseTitle(x), style: appText(13, c: x['counted'] == false && x['letter'] != null ? c.textLight : null),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Text(asDouble(x['credits']).toStringAsFixed(0), style: appText(12, c: c.textMedium)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 56,
                    child: Text(x['letter'] != null ? '${x['letter']}' : regStatusText('${x['status']}'),
                        textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: appText(13, w: FontWeight.w700, c: x['denied'] == true ? c.danger : null)),
                  ),
                ]),
              ),
          ]),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Instructors: grades
// ═════════════════════════════════════════════════════════════════════════════

class OrgTeachScreen extends StatefulWidget {
  const OrgTeachScreen({super.key, required this.orgId});
  final int orgId;

  @override
  State<OrgTeachScreen> createState() => _OrgTeachScreenState();
}

class _OrgTeachScreenState extends State<OrgTeachScreen> {
  List<Map<String, dynamic>>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => OrgApi.i.api.get('${_pub(widget.orgId)}/teach'), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) _items = asMapList(r.map['items']);
      _failed = !r.ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      useWebCard: true,
      maxWith: 1000,
      appBar: ScreenAppBar(title: t('رصد الدرجات', 'Grade entry')),
      child: AppAsync(
        loading: _items == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: (_items ?? const []).isEmpty
            ? AppEmpty(icon: Icons.class_rounded, title: t('لا توجد شعب مسندة إليك', 'No sections assigned to you'))
            : ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
                for (final x in _items!)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: AppActionCard(
                      icon: Icons.grading_rounded,
                      title: _courseTitle(asMap(x['course'])),
                      subtitle: '${termTitle(asMap(x['term']))} · ${[
                        for (final e in asMap(x['grade_states']).entries) '${gradeStateText(e.key)} ${e.value}'
                      ].join(' · ')}',
                      color: asInt(asMap(x['grade_states'])['none']) > 0 ? c.warning : c.primary,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => _GradesScreen(
                                path: '${_pub(widget.orgId)}/teach/terms/${asMap(x['term'])['id']}/courses/${asMap(x['course'])['id']}',
                                canSubmit: true,
                              )))
                          .then((_) => _load()),
                    ),
                  ),
              ]),
      ),
    );
  }
}

/// The roster with a score field per student. [path] = the roster route (instructor or staff); staff screens
/// pass [onApprove] instead of submitting.
class _GradesScreen extends StatefulWidget {
  const _GradesScreen({required this.path, this.canSubmit = false, this.onApprove});
  final String path;
  final bool canSubmit;
  final Future<void> Function()? onApprove;

  @override
  State<_GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<_GradesScreen> {
  Map<String, dynamic>? _data;
  bool _failed = false, _busy = false;
  final Map<int, TextEditingController> _ctrl = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final r = await orgCall(() => OrgApi.i.api.get(widget.path), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _data = r.map;
        for (final i in asMapList(r.map['items'])) {
          final uid = asInt(asMap(i['student'])['id']);
          _ctrl.putIfAbsent(uid, () => TextEditingController()).text = i['percent'] == null ? '' : '${i['percent']}';
        }
      }
      _failed = !r.ok;
    });
  }

  Future<void> _save() async {
    final items = <Map<String, dynamic>>[];
    for (final i in asMapList(_data?['items'])) {
      if (i['grade_state'] == 'approved' || i['status'] == 'withdrawn') continue;
      final uid = asInt(asMap(i['student'])['id']);
      final v = double.tryParse((_ctrl[uid]?.text ?? '').trim());
      if (v == null) continue;
      if (v < 0 || v > 100) {
        toast(registrarCodeText('bad_percent'), error: true);
        return;
      }
      items.add({'student_id': uid, 'percent': v});
    }
    if (items.isEmpty) return;
    setState(() => _busy = true);
    final r = await orgCall(() => OrgApi.i.api.put(widget.path, body: {'items': items}));
    if (!mounted) return;
    setState(() => _busy = false);
    final errs = asMapList(r.map['errors']);
    toast(errs.isEmpty ? t('حُفظت الدرجات', 'Grades saved') : '${registrarCodeText('${errs.first['code']}')} (${errs.length})', error: errs.isNotEmpty);
    _load();
  }

  Future<void> _submit() async {
    await _save();
    if (!mounted) return;
    if (!await appConfirm(context, message: t('إرسال الدرجات للاعتماد؟ لن تتمكن من تعديلها بعدها.', 'Submit the grades for approval? You cannot edit them afterwards.'))) return;
    final r = await orgCall(() => OrgApi.i.api.post('${widget.path}/submit'), ok: t('أُرسلت للاعتماد', 'Submitted for approval'));
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = asMapList(_data?['items']);
    final deny = '${_data?['deny_letter'] ?? 'DN'}';
    return BasePage(
      useWebCard: true,
      maxWith: 1000,
      appBar: ScreenAppBar(title: _data == null ? t('الدرجات', 'Grades') : _courseTitle(asMap(_data!['course']))),
      child: AppAsync(
        loading: _data == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: Column(children: [
          Expanded(
            child: items.isEmpty
                ? AppEmpty(icon: Icons.groups_rounded, title: t('لا يوجد طلاب مسجلون', 'No registered students'))
                : ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AppBanner(icon: Icons.info_outline_rounded,
                          text: t('اكتب الدرجة من 100 ويُحسب التقدير تلقائياً. المحروم من الامتحان يأخذ $deny.',
                              'Enter the score out of 100 — the letter is computed. A student denied the exam gets $deny.')),
                    ),
                    const SizedBox(height: 8),
                    for (final i in items)
                      AppCard(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${asMap(i['student'])['name'] ?? ''}', style: appText(14, w: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text([
                                if (i['student_code'] != null) '${i['student_code']}',
                                gradeStateText('${i['grade_state']}'),
                                if (i['absence_pct'] != null) t('غياب ${i['absence_pct']}%', 'Absent ${i['absence_pct']}%'),
                              ].join(' · '), style: appText(12, c: i['denied'] == true ? c.danger : c.textMedium), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          if (i['letter'] != null) Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: AppBadgePill('${i['letter']}', color: c.primary),
                          ),
                          SizedBox(
                            width: 76,
                            child: TextField(
                              controller: _ctrl[asInt(asMap(i['student'])['id'])],
                              enabled: i['grade_state'] != 'approved' && i['status'] != 'withdrawn' && i['denied'] != true &&
                                  (widget.onApprove != null || i['grade_state'] != 'submitted'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(isDense: true, hintText: '—'),
                            ),
                          ),
                        ]),
                      ),
                  ]),
          ),
          if (items.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.save_rounded, busy: _busy, onPressed: _save),
                  if (widget.canSubmit)
                    AppPill(icon: Icons.send_rounded, label: t('إرسال للاعتماد', 'Submit for approval'), onTap: _submit),
                  if (widget.onApprove != null)
                    AppPill(icon: Icons.lock_rounded, label: t('اعتماد وقفل', 'Approve & lock'), color: c.success, onTap: () async {
                      await _save();
                      await widget.onApprove!();
                      _load();
                    }),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Staff grade screen (same roster; approval locks the grades and recomputes GPA / level / audit).
Widget staffGradesScreen(int orgId, int termId, int courseId) {
  final base = '$orgBase/orgs/$orgId/registrar/terms/$termId/grades/$courseId';
  return _GradesScreen(
    path: base,
    onApprove: () async {
      final r = await orgCall(() => OrgApi.i.api.post('$base/approve'));
      if (r.ok) {
        toast(t('اعتُمدت ${r.map['approved']} درجة${asInt(r.map['missing']) > 0 ? ' — ${r.map['missing']} بلا درجة' : ''}',
            'Approved ${r.map['approved']}${asInt(r.map['missing']) > 0 ? ' — ${r.map['missing']} still missing' : ''}'));
      }
    },
  );
}
