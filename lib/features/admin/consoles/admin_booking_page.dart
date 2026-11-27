// lib/features/admin/consoles/admin_booking_page.dart
//
// The platform admins' "Booking" console (docs/redesign/api/booking.md, "Super admin side"): four tabs.
//   Settings   GET|PUT /api/v1/admin/booking/settings   prices per mode and kind (a month), currency, few_seats_at,
//                                                       proposal_hours; class_minutes and group_size are read-only
//   Centres    GET|POST /api/v1/admin/booking/centres · PUT|DELETE /{id} (DELETE deactivates)
//   Groups     GET|POST /api/v1/admin/booking/groups · pause / resume / close through POST /packages/{id}/status
//   Requests   GET /api/v1/admin/booking/requests?status · POST /{id}/schedule · POST /{id}/decline
// Every PUT sends every field. Staff routes: counts and rosters are shown here (privacy applies to students only).
// No kill switch of its own (the `booking` key turns the student flow off, not this page): the page sits behind
// the admin permission (the server's `admin_only`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/world_phone_field.dart' show WorldCountries;

import '../admin_common.dart' show trp;
import '../cfg_common.dart';
import '../sup/sup_kit.dart';
import 'console_parts.dart';

/// The console's kill switch (backend `features/platform/feature_catalog.py`).
const kAdminBookingKey = 'admin.booking';

String _named(dynamic m) {
  final j = cMap(m);
  return eduName(cStr(j['name_ar']), cStr(j['name_en']));
}

String _modeText(String m) => m == 'in_person' ? 'a2_bk_in_person'.tr : 'a2_bk_remote'.tr;

String _kindText(String k) => k == 'group' ? 'a2_bk_group'.tr : 'a2_bk_individual'.tr;

String _genderText(String g) => g == 'girls' ? 'a2_bk_girls'.tr : 'a2_bk_boys'.tr;

String _statusText(String s) {
  final k = 'a2_bk_st_$s';
  final v = k.tr;
  return v == k ? s : v;
}

AppTone _statusTone(String s) => switch (s) {
      'published' || 'active' || 'scheduled' => AppTone.success,
      'proposed' || 'notify' || 'pending_payment' || 'draft' => AppTone.warning,
      'paused' => AppTone.info,
      'closed' || 'declined' || 'cancelled' || 'expired' => AppTone.neutral,
      _ => AppTone.neutral,
    };

/// An instant of the server ("…Z") in the viewer's zone.
String _when(dynamic iso) {
  final d = DateTime.tryParse(cStr(iso));
  return d == null ? '' : AppTime.dateTime(d.toUtc());
}

class AdminBookingPage extends StatefulWidget {
  const AdminBookingPage({super.key, this.initialTab = 0});

  /// The tab the page opens on.
  final int initialTab;

  @override
  State<AdminBookingPage> createState() => _AdminBookingPageState();
}

class _AdminBookingPageState extends State<AdminBookingPage> {
  final _api = ApiClient();
  late int _tab = widget.initialTab;
  Object? _error;
  bool _loaded = false;
  bool _saving = false;

  // settings
  Map<String, dynamic> _settings = {};
  final _price = {
    for (final m in const ['remote', 'in_person'])
      for (final k in const ['group', 'individual']) '$m.$k': TextEditingController(),
  };
  final _currency = TextEditingController();
  final _fewSeats = TextEditingController();
  final _proposalHours = TextEditingController();

  List<Map<String, dynamic>> _centres = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _requests = [];
  String _groupStatus = '';
  String _requestStatus = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _price.values) {
      c.dispose();
    }
    _currency.dispose();
    _fewSeats.dispose();
    _proposalHours.dispose();
    super.dispose();
  }

  // ── settings ────────────────────────────────────────────────────────────────────────────────────────────────

  void _takeSettings(Map<String, dynamic> s) {
    _settings = s;
    final prices = cMap(s['prices']);
    _price.forEach((k, c) {
      final p = k.split('.');
      c.text = cNumText(cMap(prices[p[0]])[p[1]]);
    });
    _currency.text = cStr(s['currency']);
    _fewSeats.text = cNumText(s['few_seats_at']);
    _proposalHours.text = cNumText(s['proposal_hours']);
  }

  Map<String, dynamic> _settingsBody() => {
        'prices': {
          for (final m in const ['remote', 'in_person'])
            m: {for (final k in const ['group', 'individual']) k: cNum(_price['$m.$k']!.text)},
        },
        'currency': _currency.text.trim().toUpperCase(),
        'few_seats_at': cInt(_fewSeats.text),
        'proposal_hours': cInt(_proposalHours.text),
      };

  bool get _settingsDirty {
    if (!_loaded) return false;
    final prices = cMap(_settings['prices']);
    for (final e in _price.entries) {
      final p = e.key.split('.');
      if (e.value.text.trim() != cNumText(cMap(prices[p[0]])[p[1]])) return true;
    }
    return _currency.text.trim().toUpperCase() != cStr(_settings['currency']).toUpperCase() ||
        _fewSeats.text.trim() != cNumText(_settings['few_seats_at']) ||
        _proposalHours.text.trim() != cNumText(_settings['proposal_hours']);
  }

  Future<void> _saveSettings() async {
    final b = _settingsBody();
    final prices = cMap(b['prices']);
    final bad = prices.values.any((m) => cMap(m).values.any((v) => v == null || (v as num) < 0)) ||
        b['few_seats_at'] == null ||
        b['proposal_hours'] == null ||
        cStr(b['currency']).length != 3;
    if (bad) {
      showAppNotice('a2_bk_settings_invalid'.tr, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final r = cMap(await _api.put('/api/v1/admin/booking/settings', body: b));
      if (mounted) setState(() => _takeSettings(r));
      showAppNotice('a2_saved'.tr);
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── loads ───────────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (_settingsDirty) {
      final ok = await appConfirm(context, message: 'a2_discard_q'.tr);
      if (!ok || !mounted) return;
    }
    try {
      final r = await Future.wait([
        _api.get('/api/v1/admin/booking/settings'),
        _api.get('/api/v1/admin/booking/centres'),
        _fetchGroups(),
        _fetchRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _takeSettings(cMap(r[0]));
        _centres = cList(cMap(r[1])['items']);
        _groups = cList(cMap(r[2])['items']);
        _requests = cList(cMap(r[3])['items']);
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!_loaded) {
        setState(() => _error = e);
      } else {
        showAppNotice(cfgErrorMessage(e), error: true);
      }
    }
  }

  Future<dynamic> _fetchGroups() =>
      _api.get('/api/v1/admin/booking/groups', queryParams: {if (_groupStatus.isNotEmpty) 'status': _groupStatus});

  Future<dynamic> _fetchRequests() =>
      _api.get('/api/v1/admin/booking/requests', queryParams: {if (_requestStatus.isNotEmpty) 'status': _requestStatus});

  Future<void> _reload(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    }
  }

  Future<void> _reloadCentres() => _reload(() async {
        final r = cMap(await _api.get('/api/v1/admin/booking/centres'));
        if (mounted) setState(() => _centres = cList(r['items']));
      });

  Future<void> _reloadGroups() => _reload(() async {
        final r = cMap(await _fetchGroups());
        if (mounted) setState(() => _groups = cList(r['items']));
      });

  Future<void> _reloadRequests() => _reload(() async {
        final r = cMap(await _fetchRequests());
        if (mounted) setState(() => _requests = cList(r['items']));
      });

  // ── actions ─────────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _editCentre([Map<String, dynamic>? centre]) async {
    final ok = await showAppSheet<bool>(context, (_) => _CentreSheet(centre: centre));
    if (ok == true) await _reloadCentres();
  }

  Future<void> _dropCentre(Map<String, dynamic> centre) async {
    final ok = await appConfirm(context, message: 'a2_bk_centre_drop_q'.tr, danger: true);
    if (!ok) return;
    try {
      await _api.delete('/api/v1/admin/booking/centres/${cInt(centre['id'])}');
      showAppNotice('a2_bk_centre_dropped'.tr);
      await _reloadCentres();
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    }
  }

  Future<void> _newGroup() async {
    final ok = await showAppSheet<bool>(context, (_) => _GroupSheet(centres: _centres, settings: _settings));
    if (ok == true) await _reloadGroups();
  }

  Future<void> _groupStatusTo(Map<String, dynamic> g, String status) async {
    if (status == 'closed') {
      final ok = await appConfirm(context, message: 'a2_bk_group_close_q'.tr, danger: true);
      if (!ok) return;
    }
    try {
      await _api.post('/api/v1/packages/${cInt(g['id'])}/status', body: {'status': status});
      await _reloadGroups();
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    }
  }

  Future<void> _schedule(Map<String, dynamic> r) async {
    final ok = await showAppSheet<bool>(context, (_) => _ScheduleSheet(request: r, hours: cInt(_settings['proposal_hours'])));
    if (ok == true) await _reloadRequests();
  }

  Future<void> _decline(Map<String, dynamic> r) async {
    final ok = await showAppSheet<bool>(context, (_) => _DeclineSheet(requestId: cInt(r['id']) ?? 0));
    if (ok == true) await _reloadRequests();
  }

  // ── tabs ────────────────────────────────────────────────────────────────────────────────────────────────────

  Widget _settingsTab(BuildContext context) {
    final size = cMap(_settings['group_size']);
    void changed(String _) => setState(() {});
    Widget price(String mode, String kind) => Expanded(
          child: AppField(
            controller: _price['$mode.$kind']!,
            label: _kindText(kind),
            ltr: true,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            onChanged: changed,
          ),
        );
    return ListView(padding: SupPage.bodyPadding(context), children: [
      SupCard(
        title: 'a2_bk_prices'.tr,
        subtitle: 'a2_bk_prices_d'.tr,
        icon: Icons.sell_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final mode in const ['remote', 'in_person']) ...[
            Text(_modeText(mode), style: AppType.label(context)),
            const SizedBox(height: AppSpace.xs),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              price(mode, 'group'),
              const SizedBox(width: AppSpace.sm),
              price(mode, 'individual'),
            ]),
            const SizedBox(height: AppSpace.md),
          ],
          AppField(controller: _currency, label: 'a2_bk_currency'.tr, helper: 'a2_bk_currency_d'.tr, ltr: true, maxLength: 3, onChanged: changed),
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      SupCard(
        title: 'a2_bk_rules'.tr,
        icon: Icons.rule_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ConsoleNumberField(controller: _fewSeats, label: 'a2_bk_few_seats'.tr, helper: 'a2_bk_few_seats_d'.tr, onChanged: changed),
          ConsoleNumberField(
              controller: _proposalHours, label: 'a2_bk_proposal_hours'.tr, helper: 'a2_bk_proposal_hours_d'.tr, onChanged: changed),
          Text(
            trp('a2_bk_fixed', {
              'minutes': '${cInt(_settings['class_minutes']) ?? 50}',
              'min': '${cInt(size['min']) ?? 5}',
              'max': '${cInt(size['max']) ?? 10}',
            }),
            style: AppType.meta(context),
          ),
        ]),
      ),
    ]);
  }

  Widget _centresTab(BuildContext context) {
    if (_centres.isEmpty) {
      return ListView(padding: SupPage.bodyPadding(context), children: [
        AppEmpty(
          icon: Icons.location_city_rounded,
          title: 'a2_bk_centres_empty'.tr,
          message: 'a2_bk_centres_empty_d'.tr,
          actionLabel: 'a2_bk_centre_new'.tr,
          onAction: _editCentre,
        ),
      ]);
    }
    return ListView(padding: SupPage.bodyPadding(context), children: [
      for (final c in _centres) ...[
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(eduName(cStr(c['name_ar']), cStr(c['name_en'])),
                    style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: AppSpace.xs),
              AppStatusBadge(
                label: c['active'] == true ? 'a2_bk_active'.tr : 'a2_bk_inactive'.tr,
                tone: c['active'] == true ? AppTone.success : AppTone.neutral,
                dense: true,
              ),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Text(
              [cStr(c['country_code']), eduName(cStr(c['address_ar']), cStr(c['address_en']))].where((s) => s.isNotEmpty).join(' · '),
              style: AppType.meta(context),
            ),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppButton.secondary(label: 'a2_edit'.tr, icon: Icons.edit_rounded, onPressed: () => _editCentre(c)),
              if (c['active'] == true)
                AppButton.ghost(label: 'a2_bk_deactivate'.tr, icon: Icons.block_rounded, onPressed: () => _dropCentre(c)),
            ]),
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
    ]);
  }

  Widget _filter(String value, List<String> statuses, ValueChanged<String> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: AppDropdown<String>(
          decoration: InputDecoration(labelText: 'a2_bk_status'.tr),
          value: value,
          items: [
            DropdownMenuItem(value: '', child: Text('a2_bk_all'.tr)),
            for (final s in statuses) DropdownMenuItem(value: s, child: Text(_statusText(s))),
          ],
          onChanged: (v) => onChanged(v ?? ''),
        ),
      );

  Widget _groupsTab(BuildContext context) => ListView(padding: SupPage.bodyPadding(context), children: [
        _filter(_groupStatus, const ['published', 'paused', 'draft', 'closed'], (v) {
          setState(() => _groupStatus = v);
          _reloadGroups();
        }),
        if (_groups.isEmpty)
          AppEmpty(
            icon: Icons.groups_rounded,
            title: 'a2_bk_groups_empty'.tr,
            actionLabel: 'a2_bk_group_new'.tr,
            onAction: _newGroup,
          ),
        for (final g in _groups) ...[_groupCard(context, g), const SizedBox(height: AppSpace.sm)],
      ]);

  Widget _groupCard(BuildContext context, Map<String, dynamic> g) {
    final status = cStr(g['status']);
    final sched = cMap(g['schedule']);
    final days = [for (final d in (g['weekdays'] as List? ?? const [])) consoleWeekday(cInt(d) ?? 0)].join('، ');
    final teacher = cStr(cMap(g['teacher'])['name']);
    final centre = g['centre'] == null ? '' : _named(g['centre']);
    final lines = [
      [_genderText(cStr(g['gender'])), _modeText(cStr(g['mode'])), if (centre.isNotEmpty) centre].join(' · '),
      if (teacher.isNotEmpty) teacher,
      [if (days.isNotEmpty) days, if (cStr(sched['start_time']).isNotEmpty) AppTime.clock(cStr(sched['start_time']))].join(' · '),
      trp('a2_bk_seats', {
        'taken': '${cInt(g['seats_taken']) ?? 0}',
        'max': '${cInt(g['max_students']) ?? 0}',
        'waiting': '${cInt(g['waiting']) ?? 0}',
      }),
      if (g['price'] != null) trp('a2_bk_price_month', {'price': cNumText(g['price']), 'currency': cStr(g['currency'])}),
    ];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(cStr(g['title'], cStr(g['label'])), style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpace.xs),
          AppStatusBadge(label: _statusText(status), tone: _statusTone(status), dense: true),
        ]),
        if (g['below_minimum'] == true) ...[
          const SizedBox(height: AppSpace.xxs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppStatusBadge(label: 'a2_bk_below_min'.tr, tone: AppTone.warning, dense: true),
          ),
        ],
        const SizedBox(height: AppSpace.xxs),
        for (final l in lines)
          if (l.isNotEmpty) Text(l, style: AppType.meta(context)),
        if (status != 'closed') ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (status == 'published')
              AppButton.secondary(label: 'a2_bk_pause'.tr, icon: Icons.pause_rounded, onPressed: () => _groupStatusTo(g, 'paused')),
            if (status == 'paused' || status == 'draft')
              AppButton.secondary(label: 'a2_bk_publish'.tr, icon: Icons.play_arrow_rounded, onPressed: () => _groupStatusTo(g, 'published')),
            AppButton.ghost(label: 'a2_bk_close'.tr, icon: Icons.lock_outline_rounded, onPressed: () => _groupStatusTo(g, 'closed')),
          ]),
        ],
      ]),
    );
  }

  Widget _requestsTab(BuildContext context) => ListView(padding: SupPage.bodyPadding(context), children: [
        _filter(_requestStatus, const ['proposed', 'notify', 'scheduled'], (v) {
          setState(() => _requestStatus = v);
          _reloadRequests();
        }),
        if (_requests.isEmpty) AppEmpty(icon: Icons.event_available_rounded, title: 'a2_bk_requests_empty'.tr),
        for (final r in _requests) ...[_requestCard(context, r), const SizedBox(height: AppSpace.sm)],
      ]);

  Widget _requestCard(BuildContext context, Map<String, dynamic> r) {
    final status = cStr(r['status']);
    final p = cMap(r['proposal']);
    final days = [for (final d in (p['weekdays'] as List? ?? const [])) consoleWeekday(cInt(d) ?? 0)].join('، ');
    final periods = [for (final x in (p['periods'] as List? ?? const [])) _period(cStr(x))].join('، ');
    final lines = [
      [if (r['subject'] != null) _named(r['subject']), if (r['grade'] != null) _named(r['grade'])].join(' · '),
      [_kindText(cStr(r['kind'])), _modeText(cStr(r['mode'])), if (cStr(r['gender']).isNotEmpty) _genderText(cStr(r['gender']))].join(' · '),
      if (days.isNotEmpty || periods.isNotEmpty) trp('a2_bk_wants', {'days': days, 'periods': periods}),
      if (cStr(r['details']).isNotEmpty) cStr(r['details']),
      if (r['created_at'] != null) trp('a2_bk_sent', {'at': _when(r['created_at'])}),
    ];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(cStr(cMap(r['student'])['name'], '—'), style: AppType.section(context), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpace.xs),
          AppStatusBadge(label: _statusText(status), tone: _statusTone(status), dense: true),
        ]),
        const SizedBox(height: AppSpace.xxs),
        for (final l in lines)
          if (l.isNotEmpty) Text(l, style: AppType.meta(context)),
        if (status == 'proposed' || status == 'notify') ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (status == 'proposed')
              AppButton.secondary(label: 'a2_bk_schedule'.tr, icon: Icons.event_rounded, onPressed: () => _schedule(r)),
            AppButton.ghost(label: 'a2_bk_decline'.tr, icon: Icons.close_rounded, onPressed: () => _decline(r)),
          ]),
        ],
      ]),
    );
  }

  static String _period(String k) {
    final key = 'a2_bk_period_$k';
    final v = key.tr;
    return v == key ? k : v;
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _requests.where((r) => r['status'] == 'proposed' || r['status'] == 'notify').length;
    final actions = <Widget>[
      if (_loaded && _tab == 0) cfgSaveButton(dirty: _settingsDirty, busy: _saving, onSave: _saveSettings),
      if (_loaded && _tab == 1) SupHeroButton(label: 'a2_bk_centre_new'.tr, icon: Icons.add_rounded, onTap: _editCentre),
      if (_loaded && _tab == 2) SupHeroButton(label: 'a2_bk_group_new'.tr, icon: Icons.add_rounded, onTap: _newGroup),
    ];
    return SupPage(
      pageKey: const ValueKey(kAdminBookingKey),
      title: 'a2_bk_title'.tr,
      kicker: 'a2_bk_kicker'.tr,
      headline: waiting > 0 ? trp('a2_bk_head_waiting', {'n': '$waiting'}) : 'a2_bk_head'.tr,
      line: 'a2_bk_line'.tr,
      onRefresh: _load,
      dirty: _settingsDirty,
      width: AppWidth.reading,
      stats: _loaded
          ? [
              AppHeroStat(value: '${_centres.where((c) => c['active'] == true).length}', label: 'a2_bk_stat_centres'.tr),
              AppHeroStat(value: '${_groups.length}', label: 'a2_bk_stat_groups'.tr),
              AppHeroStat(value: '$waiting', label: 'a2_bk_stat_requests'.tr),
            ]
          : const [],
      tabs: [
        supTab('a2_bk_tab_settings'.tr),
        supTab('a2_bk_tab_centres'.tr),
        supTab('a2_bk_tab_groups'.tr),
        supTab('a2_bk_tab_requests'.tr, count: waiting),
      ],
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      actions: actions,
      body: _error != null && !_loaded
          ? cfgErrorState(_error, onRetry: _load)
          : !_loaded
              ? const AppListSkeleton(items: 4, withAvatar: false)
              : SupTabStack(index: _tab, children: [
                  _settingsTab(context),
                  _centresTab(context),
                  _groupsTab(context),
                  _requestsTab(context),
                ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Centre sheet (create / edit): every field sent on both
// ═════════════════════════════════════════════════════════════════════════════

class _CentreSheet extends StatefulWidget {
  const _CentreSheet({this.centre});

  final Map<String, dynamic>? centre;

  @override
  State<_CentreSheet> createState() => _CentreSheetState();
}

class _CentreSheetState extends State<_CentreSheet> {
  late final Map<String, dynamic> _c = widget.centre ?? const {};
  late String? _country = cStr(_c['country_code']).isEmpty ? WorldCountries.instance.initial.code : cStr(_c['country_code']);
  late int? _city = cInt(_c['city_id']);
  late int? _district = cInt(_c['district_id']);
  late bool _active = _c['active'] != false;
  late final _ctrl = {
    for (final k in const ['name_ar', 'name_en', 'address_ar', 'address_en']) k: TextEditingController(text: cStr(_c[k])),
    for (final k in const ['lat', 'lng', 'sort']) k: TextEditingController(text: cNumText(_c[k])),
  };
  List<EduArea> _cities = [];
  List<EduArea> _districts = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCities() async {
    final cc = _country;
    if (cc == null) return;
    final list = await EduCatalog.instance.areas(cc);
    if (!mounted || cc != _country) return;
    setState(() => _cities = list);
    await _loadDistricts();
  }

  Future<void> _loadDistricts() async {
    final cc = _country, city = _city;
    if (cc == null || city == null) {
      setState(() => _districts = []);
      return;
    }
    final list = await EduCatalog.instance.areas(cc, parentId: city);
    if (mounted && city == _city) setState(() => _districts = list);
  }

  Future<void> _save() async {
    if (_country == null || _city == null || _ctrl['name_ar']!.text.trim().isEmpty || _ctrl['name_en']!.text.trim().isEmpty) {
      showAppNotice('a2_fill_required'.tr, error: true);
      return;
    }
    final body = {
      'country_code': _country,
      'city_id': _city,
      'district_id': _district,
      for (final k in const ['name_ar', 'name_en', 'address_ar', 'address_en']) k: _ctrl[k]!.text.trim(),
      'lat': cNum(_ctrl['lat']!.text),
      'lng': cNum(_ctrl['lng']!.text),
      'sort': cInt(_ctrl['sort']!.text) ?? 0,
      'active': _active,
    };
    setState(() => _busy = true);
    try {
      final id = cInt(_c['id']);
      if (id == null) {
        await ApiClient().post('/api/v1/admin/booking/centres', body: body);
      } else {
        await ApiClient().put('/api/v1/admin/booking/centres/$id', body: body);
      }
      if (!mounted) return;
      showAppNotice('a2_saved'.tr);
      Navigator.pop(context, true);
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _f(String k, String label, {bool ltr = false, TextInputType? keyboard, bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: AppField(controller: _ctrl[k]!, label: label, ltr: ltr, keyboard: keyboard, required: required),
      );

  @override
  Widget build(BuildContext context) {
    const num = TextInputType.numberWithOptions(decimal: true, signed: true);
    return AppSheetContent(
      title: widget.centre == null ? 'a2_bk_centre_new'.tr : 'a2_bk_centre_edit'.tr,
      icon: Icons.location_city_rounded,
      tone: AppTone.gold,
      children: [
        ConsoleCountryField(
          value: _country,
          label: 'a2_mk_country'.tr,
          onChanged: (v) {
            setState(() {
              _country = v;
              _city = null;
              _district = null;
              _cities = [];
              _districts = [];
            });
            _loadCities();
          },
        ),
        const SizedBox(height: AppSpace.sm),
        AppDropdown<int>(
          decoration: InputDecoration(labelText: 'a2_bk_city'.tr),
          value: _cities.any((a) => a.id == _city) ? _city : null,
          items: [for (final a in _cities) DropdownMenuItem(value: a.id, child: Text(a.name))],
          onChanged: (v) {
            setState(() {
              _city = v;
              _district = null;
            });
            _loadDistricts();
          },
        ),
        const SizedBox(height: AppSpace.sm),
        if (_districts.isNotEmpty) ...[
          AppDropdown<int?>(
            decoration: InputDecoration(labelText: 'a2_bk_district'.tr),
            value: _districts.any((a) => a.id == _district) ? _district : null,
            items: [
              DropdownMenuItem<int?>(value: null, child: Text('a2_bk_no_district'.tr)),
              for (final a in _districts) DropdownMenuItem<int?>(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _district = v),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        _f('name_ar', 'a2_bk_name_ar'.tr, required: true),
        _f('name_en', 'a2_bk_name_en'.tr, ltr: true, required: true),
        _f('address_ar', 'a2_bk_address_ar'.tr),
        _f('address_en', 'a2_bk_address_en'.tr, ltr: true),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _f('lat', 'a2_bk_lat'.tr, ltr: true, keyboard: num)),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: _f('lng', 'a2_bk_lng'.tr, ltr: true, keyboard: num)),
        ]),
        _f('sort', 'a2_bk_sort'.tr, ltr: true, keyboard: TextInputType.number),
        AppSwitchTile(title: 'a2_bk_active'.tr, value: _active, onChanged: (v) => setState(() => _active = v)),
        const SizedBox(height: AppSpace.sm),
        AppButtonRow(
          primary: AppButton.primary(label: 'a2_save'.tr, busy: _busy, onPressed: _save),
          secondary: [AppButton.secondary(label: 'cancel'.tr, onPressed: () => Navigator.pop(context))],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Teachers (for a group or a proposal): GET /admin/users?role=teacher
// ═════════════════════════════════════════════════════════════════════════════

Future<List<Map<String, dynamic>>> _teachers() async {
  final r = await ApiClient().get('/api/v1/admin/users', queryParams: {'role': 'teacher', 'page': 1, 'size': 100});
  return cList(r is Map ? r['items'] : r);
}

class _TeacherField extends StatelessWidget {
  const _TeacherField({required this.teachers, required this.value, required this.onChanged});

  final List<Map<String, dynamic>> teachers;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => AppDropdown<int>(
        decoration: InputDecoration(labelText: 'a2_bk_teacher'.tr),
        value: teachers.any((t) => cInt(t['id']) == value) ? value : null,
        items: [
          for (final t in teachers)
            DropdownMenuItem(value: cInt(t['id']), child: Text(cStr(t['name'], '#${t['id']}'), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      );
}

/// A date then a time on the viewer's wall clock, as a UTC instant.
Future<DateTime?> _pickInstant(BuildContext context) async {
  final now = AppTime.toZone(DateTime.now().toUtc());
  final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: now);
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 19, minute: 30));
  if (t == null) return null;
  return AppTime.fromZone(DateTime(d.year, d.month, d.day, t.hour, t.minute)).toUtc();
}

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ═════════════════════════════════════════════════════════════════════════════
//  New group
// ═════════════════════════════════════════════════════════════════════════════

class _GroupSheet extends StatefulWidget {
  const _GroupSheet({required this.centres, required this.settings});

  final List<Map<String, dynamic>> centres;
  final Map<String, dynamic> settings;

  @override
  State<_GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends State<_GroupSheet> {
  List<Map<String, dynamic>> _teacherList = [];
  EduCountryCatalog? _catalog;
  String _country = WorldCountries.instance.initial.code;
  int? _teacher, _grade, _subject, _centre;
  String _gender = 'boys', _mode = 'remote';
  int _size = 10;
  final _days = <int>{};
  TimeOfDay? _time;
  DateTime? _start, _end;
  final _label = TextEditingController();
  final _price = TextEditingController();
  final _title = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _teachers().then((v) {
      if (mounted) setState(() => _teacherList = v);
    }).catchError((Object e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    });
    _loadCatalog();
  }

  @override
  void dispose() {
    _label.dispose();
    _price.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final c = await EduCatalog.instance.load(_country);
    if (mounted) setState(() => _catalog = c);
  }

  Future<void> _pickDate(bool end) async {
    final now = AppTime.toZone(DateTime.now().toUtc());
    final d = await showDatePicker(
        context: context, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 730)), initialDate: now);
    if (d != null && mounted) setState(() => end ? _end = d : _start = d);
  }

  Future<void> _save() async {
    if (_teacher == null || _grade == null || _subject == null || _days.isEmpty || _time == null || _start == null ||
        _label.text.trim().isEmpty || (_mode == 'in_person' && _centre == null)) {
      showAppNotice('a2_fill_required'.tr, error: true);
      return;
    }
    final body = {
      'teacher_id': _teacher,
      'edu_subject_id': _subject,
      'grade_id': _grade,
      'gender': _gender,
      'mode': _mode,
      'centre_id': _mode == 'in_person' ? _centre : null,
      'label': _label.text.trim(),
      'max_students': _size,
      'weekdays': (_days.toList()..sort()),
      'start_time': _hhmm(_time!),
      'tz': AppTime.zoneId,
      'start_date': _ymd(_start!),
      'end_date': _end == null ? null : _ymd(_end!),
      'price': cNum(_price.text),
      'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
    };
    setState(() => _busy = true);
    try {
      await ApiClient().post('/api/v1/admin/booking/groups', body: body);
      if (!mounted) return;
      showAppNotice('a2_bk_group_made'.tr);
      Navigator.pop(context, true);
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = _catalog;
    final grades = [
      for (final s in cat?.stages ?? const <EduStage>[])
        for (final g in s.grades) (g.id, '${s.name} · ${g.name}'),
    ];
    final subjects = cat?.subjectsOf(_grade) ?? const <EduSubject>[];
    final centres = [for (final c in widget.centres) if (c['active'] == true && cStr(c['country_code']) == _country) c];
    final gap = const SizedBox(height: AppSpace.sm);
    final defPrice = cNumText(cMap(cMap(widget.settings['prices'])[_mode])['group']);
    return AppSheetContent(
      title: 'a2_bk_group_new'.tr,
      icon: Icons.groups_rounded,
      tone: AppTone.gold,
      children: [
        _TeacherField(teachers: _teacherList, value: _teacher, onChanged: (v) => setState(() => _teacher = v)),
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.sm),
          child: Text('a2_bk_teacher_gender'.tr, style: AppType.meta(context)),
        ),
        ConsoleCountryField(
          value: _country,
          label: 'a2_bk_curriculum'.tr,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _country = v;
              _grade = null;
              _subject = null;
              _centre = null;
              _catalog = null;
            });
            _loadCatalog();
          },
        ),
        gap,
        AppDropdown<int>(
          decoration: InputDecoration(labelText: 'a2_bk_grade'.tr),
          value: grades.any((g) => g.$1 == _grade) ? _grade : null,
          items: [for (final g in grades) DropdownMenuItem(value: g.$1, child: Text(g.$2, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() {
            _grade = v;
            _subject = null;
          }),
        ),
        gap,
        AppDropdown<int>(
          decoration: InputDecoration(labelText: 'a2_bk_subject'.tr),
          value: subjects.any((s) => s.id == _subject) ? _subject : null,
          items: [for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name))],
          onChanged: (v) => setState(() => _subject = v),
        ),
        gap,
        AppTabs(
          expand: true,
          items: [AppTabItem('a2_bk_boys'.tr), AppTabItem('a2_bk_girls'.tr)],
          index: _gender == 'girls' ? 1 : 0,
          onChanged: (i) => setState(() => _gender = i == 1 ? 'girls' : 'boys'),
        ),
        gap,
        AppTabs(
          expand: true,
          items: [AppTabItem('a2_bk_remote'.tr), AppTabItem('a2_bk_in_person'.tr)],
          index: _mode == 'in_person' ? 1 : 0,
          onChanged: (i) => setState(() => _mode = i == 1 ? 'in_person' : 'remote'),
        ),
        gap,
        if (_mode == 'in_person') ...[
          AppDropdown<int>(
            decoration: InputDecoration(labelText: 'a2_bk_centre'.tr),
            value: centres.any((c) => cInt(c['id']) == _centre) ? _centre : null,
            items: [
              for (final c in centres)
                DropdownMenuItem(value: cInt(c['id']), child: Text(eduName(cStr(c['name_ar']), cStr(c['name_en'])))),
            ],
            onChanged: (v) => setState(() => _centre = v),
          ),
          gap,
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: AppField(controller: _label, label: 'a2_bk_label'.tr, helper: 'a2_bk_label_d'.tr, maxLength: 10)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: AppDropdown<int>(
              decoration: InputDecoration(labelText: 'a2_bk_size'.tr),
              value: _size,
              items: [for (var n = 5; n <= 10; n++) DropdownMenuItem(value: n, child: Text('$n'))],
              onChanged: (v) => setState(() => _size = v ?? _size),
            ),
          ),
        ]),
        gap,
        AppFieldLabel('a2_bk_days'.tr),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final d in const [5, 6, 0, 1, 2, 3, 4])
            AppChip(
              label: consoleWeekday(d),
              selected: _days.contains(d),
              onTap: () => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
            ),
        ]),
        gap,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton.secondary(
            label: _time == null ? 'a2_bk_time'.tr : AppTime.clock(_hhmm(_time!)),
            icon: Icons.schedule_rounded,
            onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 19, minute: 30));
              if (t != null && mounted) setState(() => _time = t);
            },
          ),
          AppButton.secondary(
            label: _start == null ? 'a2_bk_start_date'.tr : AppTime.wall(_start!),
            icon: Icons.event_rounded,
            onPressed: () => _pickDate(false),
          ),
          AppButton.secondary(
            label: _end == null ? 'a2_bk_end_date'.tr : AppTime.wall(_end!),
            icon: Icons.event_busy_rounded,
            onPressed: () => _pickDate(true),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.sm),
          child: Text(trp('a2_bk_zone', {'zone': AppTime.zoneId}), style: AppType.meta(context)),
        ),
        AppField(
          controller: _price,
          label: 'a2_bk_price'.tr,
          helper: trp('a2_bk_price_d', {'price': defPrice, 'currency': cStr(widget.settings['currency'])}),
          ltr: true,
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        gap,
        AppField(controller: _title, label: 'a2_bk_group_title'.tr, helper: 'a2_bk_group_title_d'.tr),
        gap,
        AppButtonRow(
          primary: AppButton.primary(label: 'a2_bk_group_publish'.tr, busy: _busy, onPressed: _save),
          secondary: [AppButton.secondary(label: 'cancel'.tr, onPressed: () => Navigator.pop(context))],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Fix a proposal / decline a request
// ═════════════════════════════════════════════════════════════════════════════

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.request, this.hours});

  final Map<String, dynamic> request;
  final int? hours;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  static const _max = 5;
  List<Map<String, dynamic>> _teacherList = [];
  int? _teacher;
  final _times = <DateTime>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _teachers().then((v) {
      if (mounted) setState(() => _teacherList = v);
    }).catchError((Object e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    });
  }

  Future<void> _save() async {
    if (_teacher == null || _times.isEmpty) {
      showAppNotice('a2_fill_required'.tr, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient().post('/api/v1/admin/booking/requests/${cInt(widget.request['id'])}/schedule',
          body: {'teacher_id': _teacher, 'starts_at': [for (final t in _times) t.toUtc().toIso8601String()]});
      if (!mounted) return;
      showAppNotice('a2_bk_scheduled'.tr);
      Navigator.pop(context, true);
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hours = widget.hours;
    return AppSheetContent(
      title: 'a2_bk_schedule'.tr,
      subtitle: cStr(cMap(widget.request['student'])['name']),
      icon: Icons.event_rounded,
      tone: AppTone.gold,
      children: [
        _TeacherField(teachers: _teacherList, value: _teacher, onChanged: (v) => setState(() => _teacher = v)),
        const SizedBox(height: AppSpace.sm),
        AppFieldLabel('a2_bk_times'.tr),
        for (final t in _times)
          AppTile(
            dense: true,
            icon: Icons.repeat_rounded,
            title: '${consoleWeekday((AppTime.toZone(t).weekday + 6) % 7)} · ${AppTime.time(t)}',
            subtitle: trp('a2_bk_weekly_from', {'date': AppTime.date(t)}),
            trailing: IconButton(
              tooltip: 'a2_remove'.tr,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _times.remove(t)),
            ),
          ),
        if (_times.length < _max)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.secondary(
              label: 'a2_bk_add_time'.tr,
              icon: Icons.add_rounded,
              onPressed: () async {
                final t = await _pickInstant(context);
                if (t != null && mounted) setState(() => _times.add(t));
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Text(hours == null ? 'a2_bk_schedule_d'.tr : trp('a2_bk_schedule_h', {'h': '$hours'}), style: AppType.meta(context)),
        ),
        AppButtonRow(
          primary: AppButton.primary(label: 'a2_bk_schedule_save'.tr, busy: _busy, onPressed: _save),
          secondary: [AppButton.secondary(label: 'cancel'.tr, onPressed: () => Navigator.pop(context))],
        ),
      ],
    );
  }
}

class _DeclineSheet extends StatefulWidget {
  const _DeclineSheet({required this.requestId});

  final int requestId;

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      showAppNotice('a2_bk_reason_needed'.tr, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient().post('/api/v1/admin/booking/requests/${widget.requestId}/decline', body: {'reason': reason});
      if (!mounted) return;
      showAppNotice('a2_bk_declined'.tr);
      Navigator.pop(context, true);
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: 'a2_bk_decline'.tr,
        icon: Icons.close_rounded,
        tone: AppTone.danger,
        children: [
          AppField(controller: _reason, label: 'a2_bk_reason'.tr, helper: 'a2_bk_reason_d'.tr, maxLines: 3, maxLength: 300, required: true),
          const SizedBox(height: AppSpace.sm),
          AppButtonRow(
            primary: AppButton.danger(label: 'a2_bk_decline'.tr, busy: _busy, onPressed: _save),
            secondary: [AppButton.secondary(label: 'cancel'.tr, onPressed: () => Navigator.pop(context))],
          ),
        ],
      );
}
