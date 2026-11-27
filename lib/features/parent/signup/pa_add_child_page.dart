// lib/features/parent/signup/pa_add_child_page.dart — "Create your child's account" after sign-up (the "+" of the top
// bar's child switcher, the Children tab, the empty Today). The same questions as the join flow's parent steps: the
// child's name, boy or girl (optional), the curriculum's country (any country with a catalog; the parent's residence
// is not assumed), the grade, and how they study. POST /parent/children, then the code page (pa_child_code_page.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/edu_pickers.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../config/app_config.dart';
import '../pa_kit.dart';
import 'pa_child_api.dart';
import 'pa_child_code_page.dart';

/// Opens the form; true when a child was created (the caller reloads its children).
Future<bool> paOpenAddChild(BuildContext context) async {
  final r = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => paRole(const ParentAddChildPage())));
  return r == true;
}

class ParentAddChildPage extends StatefulWidget {
  const ParentAddChildPage({super.key, this.api});

  final PaChildApi? api;

  @override
  State<ParentAddChildPage> createState() => _ParentAddChildPageState();
}

class _ParentAddChildPageState extends State<ParentAddChildPage> {
  late final PaChildApi _api = widget.api ?? PaChildApi();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _d = PaChildDraft();
  List<EduCountry> _countries = const [];
  EduCountryCatalog? _catalog;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _first.addListener(() => setState(() {}));
    EduCountries.load().then((list) {
      if (!mounted) return;
      setState(() {
        _countries = list;
        _d.country ??= pickEduCountry(list, null)?.code;
      });
      _loadCatalog();
    });
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final country = _d.country;
    if (country == null) return;
    final cat = await EduCatalog.instance.load(country);
    if (mounted && _d.country == country) setState(() => _catalog = cat);
  }

  Future<void> _submit() async {
    _d
      ..firstName = _first.text
      ..lastName = _last.text;
    if (!_d.ready) return;
    setState(() => _busy = true);
    try {
      final made = await _api.create(_d);
      final code = made?.code;
      if (!mounted || made == null || code == null) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ParentChildCodePage(child: made, code: code)));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      showAppNotice(apiErrorText(ApiException.from(e)), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _first.text.trim().isNotEmpty && _d.stageId != null && _d.gradeId != null;
    final hero = AppHero(kicker: 'pa_add_child'.tr, title: 'pa_add_child_title'.tr, subtitle: 'pa_add_child_sub'.tr);
    final form = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppField(key: const ValueKey('pa.add.first'), controller: _first, label: 'pa_child_first_name'.tr, icon: Icons.person_outline_rounded),
        const SizedBox(height: AppSpace.sm),
        AppField(key: const ValueKey('pa.add.last'), controller: _last, label: 'pa_child_last_name'.tr, icon: Icons.badge_outlined),
        const SizedBox(height: AppSpace.md),
        Text('pa_boy_or_girl'.tr, style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final g in const ['m', 'f'])
            AppChip(label: 'pa_gender_$g'.tr, selected: _d.gender == g, onTap: () => setState(() => _d.gender = _d.gender == g ? null : g)),
        ]),
        if (_countries.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Text('pa_curriculum_country'.tr, style: AppType.tileTitle(context)),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final c in _countries)
              AppChip(
                label: c.name,
                selected: _d.country == c.code,
                onTap: () {
                  setState(() {
                    _d.country = c.code;
                    _d.stageId = _d.gradeId = null;
                    _d.track = null;
                    _catalog = null;
                  });
                  _loadCatalog();
                },
              ),
          ]),
        ],
        const SizedBox(height: AppSpace.md),
        Text('pa_child_grade_q'.tr, style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.xs),
        if (_catalog == null)
          const AppListSkeleton(items: 1, padding: EdgeInsets.zero)
        else
          EduStageGradePicker(
            stages: _catalog!.stages,
            stageId: _d.stageId,
            gradeId: _d.gradeId,
            trackKey: _d.track,
            onChanged: (s, g, t) => setState(() {
              _d.stageId = s;
              _d.gradeId = g;
              _d.track = t;
            }),
          ),
        const SizedBox(height: AppSpace.md),
        Text('pa_how_study'.tr, style: AppType.tileTitle(context)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final m in const ['online', 'in_person'])
            AppChip(
              label: m == 'online' ? 'pa_remote'.tr : 'pa_in_person'.tr,
              selected: _d.delivery == m,
              onTap: () => setState(() => _d.delivery = _d.delivery == m ? null : m),
            ),
        ]),
        const SizedBox(height: AppSpace.md),
        PaNote(icon: Icons.lock_outline_rounded, text: 'pa_add_child_note'.tr),
        const SizedBox(height: AppSpace.md),
        AppButton.primary(
          key: const ValueKey('pa.add.submit'),
          label: 'pa_add_child_submit'.tr,
          busy: _busy,
          expand: true,
          onPressed: ready && !_busy ? _submit : null,
        ),
      ]),
    );
    return BasePage(
      appBar: ScreenAppBar(title: 'pa_add_child'.tr),
      child: PaHeroPage(hero: hero, width: AppWidth.form, body: form),
    );
  }
}

