// lib/features/parent/pay/pa_book_page.dart — "Book for your child" (Pa2Pay `screen=book`, phase 4).
//
//   who      the linked children as cards (avatar · name · grade), one picked
//   which    the subjects of the child's grade (GET /edu/catalog for the child's curriculum country, or the platform
//            default when the child row does not say), one picked
//   offer    for the picked subject: GET /booking/options?subject_id=&grade_id= — remote / in person, group and فردي
//            prices ("from") in the server's currency; nothing is shown that the server did not send
//   next     the booking flow (openBookFlow) for the picked child: every booking call carries `student_id`, the
//            server checks the link (403 child_not_linked) and the booking is the child's; the parent pays by card
//            or bank transfer (owner 2026-11-27).
// Kill switch `booking` (the caller hides the entry).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/booking/booking_flow_page.dart' show openBookFlow;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../pa_kit.dart';
import '../parent_link_providers.dart';

bool paBookingOn() => !AppConfig.disableList.contains('booking');

class ParentBookPage extends StatefulWidget {
  const ParentBookPage({super.key, this.childId, this.api});

  /// The child picked when the page opens (a child's page "Book a subject").
  final int? childId;
  final ApiClient? api;

  @override
  State<ParentBookPage> createState() => _ParentBookPageState();
}

class _ParentBookPageState extends State<ParentBookPage> {
  late final ApiClient _api = widget.api ?? ApiClient();
  ParentLinkProvider? _own;
  int? _child;
  int? _subject;
  EduCountryCatalog? _catalog;
  String? _catalogFor;
  Map<String, dynamic>? _options;
  bool _optionsLoading = false;

  @override
  void initState() {
    super.initState();
    _child = widget.childId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.read<ParentLinkProvider>().ensureLoaded();
      } on ProviderNotFoundException {
        setState(() => _own = ParentLinkProvider()..loadAll());
      }
    });
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog(String? country) async {
    final code = country ?? pickEduCountry(await EduCountries.load(), null)?.code;
    if (code == null || code == _catalogFor) return;
    _catalogFor = code;
    final cat = await EduCatalog.instance.load(code);
    if (mounted) setState(() => _catalog = cat);
  }

  Future<void> _book({required int childId, required String childName, required int gradeId, required String grade}) async {
    final s = _catalog?.subjects.where((x) => x.id == _subject).firstOrNull;
    if (s == null) return;
    await openBookFlow(
      context,
      subjectId: s.id,
      gradeId: gradeId,
      subjectTitle: s.name,
      gradeTitle: grade.isEmpty ? null : grade,
      subjectKey: s.key,
      studentId: childId,
      childName: childName,
    );
  }

  Future<void> _loadOptions(int subjectId, int? gradeId) async {
    setState(() {
      _options = null;
      _optionsLoading = true;
    });
    try {
      final r = await _api.get('/api/v1/booking/options',
          queryParams: {'subject_id': subjectId, 'grade_id': ?gradeId, 'student_id': ?_child});
      if (mounted && _subject == subjectId) setState(() => _options = r is Map ? Map<String, dynamic>.from(r) : null);
    } catch (_) {
      // no offer for this subject: the card says so
    } finally {
      if (mounted) setState(() => _optionsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final own = _own;
    if (own != null) return ChangeNotifierProvider.value(value: own, child: Builder(builder: _build));
    return _build(context);
  }

  Widget _build(BuildContext context) {
    ParentLinkProvider? p;
    try {
      p = context.watch<ParentLinkProvider>();
    } on ProviderNotFoundException {
      p = null;
    }
    final kids = [for (final ch in p?.children ?? const <Map<String, dynamic>>[]) if (ch['id'] is num) ch];
    _child ??= kids.isEmpty ? null : (kids.first['id'] as num).toInt();
    final row = kids.where((k) => (k['id'] as num).toInt() == _child).firstOrNull;
    final gradeId = (row?['grade_id'] as num?)?.toInt();
    if (row != null) _loadCatalog(row['curriculum_country_code'] as String? ?? row['country_code'] as String?);
    final subjects = _catalog == null ? null : (gradeId == null ? _catalog!.subjects : _catalog!.subjectsOf(gradeId));
    final grade = '${row?['grade_name'] ?? ''}';
    final c = context.colors;

    final hero = AppHero(kicker: 'pa_book_for_child'.tr, title: 'pa_book_title'.tr, subtitle: 'pa_book_sub'.tr);
    final who = AppCard(
      title: 'pa_book_who'.tr,
      child: kids.isEmpty
          ? (p == null || !p.loadedOnce ? const AppListSkeleton(items: 1, padding: EdgeInsets.zero) : Text('pl_no_children'.tr))
          : Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
              for (final k in kids)
                _PickCard(
                  key: ValueKey('pa.book.kid.${k['id']}'),
                  selected: (k['id'] as num).toInt() == _child,
                  onTap: () => setState(() {
                    _child = (k['id'] as num).toInt();
                    _subject = null;
                    _options = null;
                  }),
                  child: Column(children: [
                    PaKidAvatar(id: (k['id'] as num).toInt(), name: '${k['name']}', size: AppDashSize.avatarSm),
                    const SizedBox(height: AppSpace.xs),
                    Text('${k['name']}', textAlign: TextAlign.center, maxLines: 2, style: AppType.tileTitle(context)),
                    if ('${k['grade_name'] ?? ''}'.isNotEmpty)
                      Text('${k['grade_name']}', textAlign: TextAlign.center, maxLines: 2, style: AppType.meta(context)),
                  ]),
                ),
            ]),
    );
    final which = row == null
        ? null
        : AppCard(
            title: 'pa_book_which'.tr,
            action: grade.isEmpty ? null : Text(paFmt('pa_book_grade_subjects', {'grade': grade}), style: AppType.meta(context)),
            child: subjects == null
                ? const AppListSkeleton(items: 2, padding: EdgeInsets.zero)
                : subjects.isEmpty
                    ? Text('pa_book_no_subjects'.tr, style: AppType.body(context))
                    : Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                        for (final s in subjects)
                          _PickCard(
                            key: ValueKey('pa.book.subject.${s.id}'),
                            selected: s.id == _subject,
                            onTap: () {
                              setState(() => _subject = s.id);
                              _loadOptions(s.id, gradeId);
                            },
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              AppIconBox(icon: Icons.menu_book_rounded, tone: subjectColors(context, s.key).tone),
                              const SizedBox(height: AppSpace.xs),
                              Text(s.name, maxLines: 2, style: AppType.tileTitle(context)),
                            ]),
                          ),
                      ]),
          );
    final offer = _subject == null
        ? null
        : AppCard(
            title: 'pa_book_offer'.tr,
            child: _optionsLoading
                ? const AppListSkeleton(items: 1, padding: EdgeInsets.zero)
                : _offer(context, _options),
          );
    return BasePage(
      appBar: ScreenAppBar(title: 'pa_book_for_child'.tr),
      child: Column(children: [
        PaSwitcherBand(showAll: false, selectedId: _child, onSelect: (id) => setState(() {
              _child = id;
              _subject = null;
              _options = null;
            })),
        Expanded(
          child: PaHeroPage(
            hero: hero,
            body: PaStack(children: [
              who,
              ?which,
              ?offer,
              AppButton.hot(
                key: const ValueKey('pa.book.next'),
                label: 'pa_book_next'.tr,
                expand: true,
                onPressed: row == null || gradeId == null || _subject == null || _options == null
                    ? null
                    : () => _book(childId: _child!, childName: '${row['name'] ?? ''}', gradeId: gradeId, grade: grade),
              ),
              Text('ow_pa_book_note'.tr, textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _offer(BuildContext context, Map<String, dynamic>? o) {
    if (o == null) return Text('pa_book_no_offer'.tr, style: AppType.body(context));
    final currency = '${o['currency'] ?? ''}';
    final kinds = [for (final k in (o['kinds'] as List? ?? const [])) if (k is Map && k['available'] == true) k];
    final modes = [for (final m in (o['modes'] as List? ?? const [])) if (m is Map && m['available'] == true) '${m['key']}'];
    String price(Map k) {
      final prices = (k['prices'] as Map?) ?? const {};
      final vals = [for (final m in modes) if (prices[m] is num) prices[m] as num];
      if (vals.isEmpty) return '—';
      final min = vals.reduce((a, b) => a < b ? a : b);
      return paFmt('pa_from_price', {'p': appDigits('${min.round()}'), 'c': currency});
    }

    return PaStack(gap: AppSpace.sm, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final m in modes) AppStatusBadge(label: m == 'remote' ? 'pa_remote'.tr : 'pa_in_person'.tr, tone: AppTone.info),
      ]),
      for (final k in kinds)
        AppTile(
          icon: k['key'] == 'group' ? Icons.groups_outlined : Icons.person_outline_rounded,
          title: k['key'] == 'group' ? 'pa_kind_group'.tr : 'pa_kind_individual'.tr,
          subtitle: k['key'] == 'group'
              ? paFmt('pa_group_size', {'a': appDigits('${(o['group_size'] as Map?)?['min'] ?? 5}'), 'b': appDigits('${(o['group_size'] as Map?)?['max'] ?? 10}')})
              : null,
          trailing: AppStatusBadge(label: price(k), tone: AppTone.success),
        ),
    ]);
  }
}

/// A selectable card (a child, a subject) with the check at its top corner.
class _PickCard extends StatelessWidget {
  const _PickCard({super.key, required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  static const double _width = 148;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.tile),
        onTap: onTap,
        child: Container(
          width: _width,
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            gradient: selected ? LinearGradient(colors: [c.cardBg, set.tint]) : null,
            color: selected ? null : c.cardBg,
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: selected ? set.a : c.kit.line, width: selected ? AppBorder.focus : AppBorder.strong),
          ),
          child: Stack(children: [
            Center(child: child),
            PositionedDirectional(
              top: 0,
              start: 0,
              child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: AppIconSize.md, color: selected ? set.a : c.kit.line),
            ),
          ]),
        ),
      ),
    );
  }
}
