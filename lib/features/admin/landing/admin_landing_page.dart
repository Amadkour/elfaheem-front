// lib/features/admin/landing/admin_landing_page.dart
//
// Super admin → "Landing page": the rate limit of the public numbers + the real reviews featured as testimonials.
// Owns the loading / saving state; every widget it draws takes plain values (landing_admin_widgets.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin_common.dart' show t;
import 'landing_admin_api.dart';
import 'landing_admin_widgets.dart';

String landingTitle() => t('الصفحة الرئيسية للموقع', 'Landing page');

class AdminLandingPage extends StatefulWidget {
  const AdminLandingPage({super.key});

  @override
  State<AdminLandingPage> createState() => _AdminLandingPageState();
}

class _AdminLandingPageState extends State<AdminLandingPage> {
  LandingOverview? _saved;
  String? _error;
  bool _savingRate = false;
  bool _savingList = false;

  LandingRateLimit _rate = const LandingRateLimit();
  List<LandingReview> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _rateDirty => _saved != null && _rate != _saved!.rateLimit;

  bool get _listDirty {
    final s = _saved;
    if (s == null) return false;
    final a = [for (final r in s.testimonials) r.id];
    final b = [for (final r in _list) r.id];
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final o = await LandingAdminApi.load();
      if (!mounted) return;
      setState(() {
        _saved = o;
        _rate = o.rateLimit;
        _list = List.of(o.testimonials);
      });
    } catch (e) {
      if (mounted) setState(() => _error = landingErrorText(e));
    }
  }

  Future<void> _saveRate() async {
    setState(() => _savingRate = true);
    try {
      final o = await LandingAdminApi.saveRateLimit(_rate);
      if (!mounted) return;
      setState(() {
        _saved = LandingOverview(
            rateLimit: o.rateLimit,
            minPerMinute: o.minPerMinute,
            maxPerMinute: o.maxPerMinute,
            testimonials: _saved?.testimonials ?? o.testimonials);
        _rate = o.rateLimit;
      });
      showAppNotice(t('تم حفظ حد الطلبات', 'Request limit saved'));
    } catch (e) {
      showAppNotice(landingErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _savingRate = false);
    }
  }

  Future<void> _saveList() async {
    setState(() => _savingList = true);
    try {
      final o = await LandingAdminApi.saveTestimonials([for (final r in _list) r.id]);
      if (!mounted) return;
      setState(() {
        final s = _saved;
        _saved = LandingOverview(
            rateLimit: s?.rateLimit ?? o.rateLimit,
            minPerMinute: o.minPerMinute,
            maxPerMinute: o.maxPerMinute,
            testimonials: o.testimonials);
        _list = List.of(o.testimonials);
      });
      showAppNotice(t('تم حفظ الآراء المعروضة', 'Testimonials saved'));
    } catch (e) {
      showAppNotice(landingErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _savingList = false);
    }
  }

  void _reorder(int from, int to) {
    setState(() {
      // onReorderItem already hands over the adjusted index
      _list.insert(to, _list.removeAt(from));
    });
  }

  Future<void> _add() async {
    final picked = await showAppSheet<List<LandingReview>>(context, (_) => LandingCandidatesSheet(initial: _list));
    if (picked != null && mounted) setState(() => _list = picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = _saved;
    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: landingTitle()),
      child: s == null
          ? (_error != null
              ? Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    AppBanner(icon: Icons.cloud_off_rounded, color: context.colors.danger, text: _error!),
                    const SizedBox(height: AppSpace.sm),
                    Align(child: AppButton.tonal(label: t('إعادة المحاولة', 'Try again'), onPressed: _load)),
                  ]),
                )
              : const AppListSkeleton(items: 4))
          : AppRefresh(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl),
                children: [
                  LandingAdminBody(
                    rate: _rate,
                    minPerMinute: s.minPerMinute,
                    maxPerMinute: s.maxPerMinute,
                    rateDirty: _rateDirty,
                    savingRate: _savingRate,
                    onRate: (v) => setState(() => _rate = v),
                    onSaveRate: _saveRate,
                    reviews: _list,
                    listDirty: _listDirty,
                    savingList: _savingList,
                    onReorder: _reorder,
                    onRemove: (id) => setState(() => _list.removeWhere((r) => r.id == id)),
                    onAdd: _add,
                    onSaveList: _saveList,
                  ),
                ],
              ),
            ),
    );
  }
}

/// The "Add reviews" sheet: loads the candidates (search, stars, kind, paging) and pops the new ordered selection.
class LandingCandidatesSheet extends StatefulWidget {
  const LandingCandidatesSheet({super.key, required this.initial});

  /// The reviews already featured, in order.
  final List<LandingReview> initial;

  @override
  State<LandingCandidatesSheet> createState() => _LandingCandidatesSheetState();
}

class _LandingCandidatesSheetState extends State<LandingCandidatesSheet> {
  // insertion-ordered: the featured ones first, then the newly ticked
  late final Map<int, LandingReview> _selected = {for (final r in widget.initial) r.id: r};
  final List<LandingReview> _items = [];
  String _q = '';
  int _minStars = 4;
  String? _kind;
  int _page = 1;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _gen = 0; // drops the answer of a superseded request

  @override
  void initState() {
    super.initState();
    _fetch(reset: true);
  }

  Future<void> _fetch({required bool reset}) async {
    final gen = ++_gen;
    setState(() {
      _error = null;
      if (reset) {
        _loading = true;
        _page = 1;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final p = await LandingAdminApi.candidates(q: _q, minStars: _minStars, kind: _kind, page: reset ? 1 : _page + 1);
      if (!mounted || gen != _gen) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(p.items);
        _page = p.page;
        _total = p.total;
        _hasMore = p.hasMore;
      });
    } catch (e) {
      if (mounted && gen == _gen) setState(() => _error = landingErrorText(e));
    } finally {
      if (mounted && gen == _gen) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _toggle(LandingReview r) {
    if (_selected.containsKey(r.id)) {
      setState(() => _selected.remove(r.id));
    } else if (_selected.length >= kLandingMaxTestimonials) {
      showAppNotice(t('الحد الأقصى $kLandingMaxTestimonials تقييماً — أزل واحداً أولاً.',
          'At most $kLandingMaxTestimonials reviews — remove one first.'), error: true);
    } else {
      setState(() => _selected[r.id] = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetContent(
      title: t('إضافة تقييمات', 'Add reviews'),
      children: [
        LandingCandidatesBody(
          items: _items,
          selectedIds: _selected.keys.toSet(),
          total: _total,
          loading: _loading,
          loadingMore: _loadingMore,
          hasMore: _hasMore,
          error: _error,
          minStars: _minStars,
          kind: _kind,
          onQuery: (q) {
            _q = q;
            _fetch(reset: true);
          },
          onMinStars: (s) {
            _minStars = s;
            _fetch(reset: true);
          },
          onKind: (k) {
            _kind = k;
            _fetch(reset: true);
          },
          onToggle: _toggle,
          onMore: () => _fetch(reset: false),
          onRetry: () => _fetch(reset: _items.isEmpty),
          onDone: () => Navigator.of(context).pop(_selected.values.toList()),
        ),
      ],
    );
  }
}
