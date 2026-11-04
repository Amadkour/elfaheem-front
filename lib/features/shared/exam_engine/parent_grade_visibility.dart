// Whether parents see their child's grades (D-244): the platform default (super admin: always / when published / never)
// and an organization's own choice (org admin: inherit / when published / never / always). Server contract:
// ../back/docs/grading/CONTRACT.md §2 — `GET/PUT /api/v1/admin/grades/visibility {parents_see}` and
// `GET/PUT /api/v1/org/orgs/{org_id}/grades/visibility {parents_see, effective, platform_default}`. Kill switch
// `grades.parent_visibility`. The sheet's body ([ParentVisibilityBody]) takes plain values for the layout harness.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'exam_engine_api.dart';

const kParentVisibilityKey = 'grades.parent_visibility';

/// The paths in one place (the org route is under the `/api/v1/org` prefix like every org route).
String parentVisibilityPath({int? orgId}) => orgId == null ? '/api/v1/admin/grades/visibility' : '/api/v1/org/orgs/$orgId/grades/visibility';

const platformVisibilityChoices = ['always', 'when_published', 'never'];
const orgVisibilityChoices = ['inherit', 'when_published', 'never', 'always'];

String parentVisibilityLabel(String v) => switch (v) {
      'always' => t('دائماً', 'Always'),
      'never' => t('أبداً', 'Never'),
      'inherit' => t('اتباع إعداد المنصة', 'Follow the platform setting'),
      _ => t('عند النشر', 'When published'),
    };

String parentVisibilityHint(String v) => switch (v) {
      'always' => t('يرى ولي الأمر درجات ابنه فور تسجيلها، حتى قبل نشر النتائج للطلاب.',
          'Parents see their child\'s grades as soon as they are recorded, even before the results are published to students.'),
      'never' => t('لا يرى أولياء الأمور الدرجات في التطبيق.', 'Parents do not see grades in the app.'),
      'inherit' => t('تُطبَّق قاعدة المنصة العامة.', 'The platform-wide rule applies.'),
      _ => t('يرى ولي الأمر الدرجة عندما تُنشر للطالب، لا قبل ذلك.', 'Parents see a grade once it is published to the student, not before.'),
    };

class ParentVisibility {
  ParentVisibility({required this.parentsSee, this.effective, this.platformDefault});
  final String parentsSee;
  final String? effective;
  final String? platformDefault;

  factory ParentVisibility.fromJson(Map<String, dynamic> j) => ParentVisibility(
        parentsSee: '${j['parents_see'] ?? 'when_published'}',
        effective: j['effective']?.toString(),
        platformDefault: j['platform_default']?.toString(),
      );
}

class ParentVisibilityApi {
  ParentVisibilityApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  Future<EngineResult> load({int? orgId}) => engineCall(() => _api.get(parentVisibilityPath(orgId: orgId)));
  Future<EngineResult> save(String value, {int? orgId}) =>
      engineCall(() => _api.put(parentVisibilityPath(orgId: orgId), body: {'parents_see': value}));
}

/// The choices as selectable rows. [platformDefault] is named in the "follow the platform" row of an organization.
class ParentVisibilityBody extends StatelessWidget {
  const ParentVisibilityBody({super.key, required this.choices, required this.value, required this.onPick, this.platformDefault, this.effective});
  final List<String> choices;
  final String value;
  final ValueChanged<String> onPick;
  final String? platformDefault;
  final String? effective;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final v in choices)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            key: ValueKey('pv.$v'),
            onTap: () => onPick(v),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(value == v ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 22, color: value == v ? c.primary : c.textLight),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(parentVisibilityLabel(v), style: appText(14, w: FontWeight.w700, c: c.textDark)),
                  const SizedBox(height: 2),
                  Text(
                      v == 'inherit' && platformDefault != null
                          ? t('تُطبَّق قاعدة المنصة العامة، وهي الآن: ${parentVisibilityLabel(platformDefault!)}',
                              'The platform-wide rule applies, currently: ${parentVisibilityLabel(platformDefault!)}')
                          : parentVisibilityHint(v),
                      style: appText(12.5, c: c.textMedium)),
                ]),
              ),
            ]),
          ),
        ),
      if (effective != null && value == 'inherit')
        Text(t('المطبَّق الآن: ${parentVisibilityLabel(effective!)}', 'In effect now: ${parentVisibilityLabel(effective!)}'), style: appText(12, c: c.textLight)),
    ]);
  }
}

/// Loads the current value, shows the choices, saves the pick.
class ParentVisibilitySheet extends StatefulWidget {
  const ParentVisibilitySheet({super.key, this.orgId, ParentVisibilityApi? api}) : _api = api;
  final int? orgId;
  final ParentVisibilityApi? _api;

  @override
  State<ParentVisibilitySheet> createState() => _ParentVisibilitySheetState();
}

class _ParentVisibilitySheetState extends State<ParentVisibilitySheet> {
  late final ParentVisibilityApi _api = widget._api ?? ParentVisibilityApi();
  ParentVisibility? _v;
  String? _error;
  bool _saving = false;

  bool get _org => widget.orgId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.load(orgId: widget.orgId);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _v = ParentVisibility.fromJson(r.map);
        _error = null;
      } else {
        _error = r.unavailable ? t('الخدمة غير متاحة على الخادم بعد', 'Not available on the server yet') : (r.message.isEmpty ? '${r.code}' : r.message);
      }
    });
  }

  Future<void> _pick(String v) async {
    final old = _v;
    if (old == null || old.parentsSee == v || _saving) return;
    setState(() { _saving = true; _error = null; });
    final r = await _api.save(v, orgId: widget.orgId);
    if (!mounted) return;
    if (!r.ok) {
      setState(() { _saving = false; _error = r.message.isEmpty ? '${r.code}' : r.message; });
      return;
    }
    // the answer repeats the saved row (with the effective value for an organization); else keep what was picked
    final saved = r.map.containsKey('parents_see') ? ParentVisibility.fromJson(r.map) : ParentVisibility(parentsSee: v, platformDefault: old.platformDefault);
    setState(() {
      _saving = false;
      _v = ParentVisibility(parentsSee: saved.parentsSee, effective: saved.effective, platformDefault: saved.platformDefault ?? old.platformDefault);
    });
    appToast(t('حُفظ الإعداد', 'Setting saved'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = _v;
    return AppSheetContent(title: t('رؤية أولياء الأمور للدرجات', 'What parents see of grades'), children: [
      Text(
          _org ? t('تخص هذه المؤسسة. يمكنك اتباع إعداد المنصة أو تحديد قاعدتك.', 'This applies to your organization. Follow the platform setting or choose your own rule.')
              : t('القاعدة الافتراضية لكل المنصة؛ يمكن للمؤسسات تغييرها لنفسها.', 'The default for the whole platform; organizations can change it for themselves.'),
          style: appText(13, c: c.textMedium)),
      const SizedBox(height: 12),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!)),
      if (v == null && _error == null) const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero),
      if (v != null)
        ParentVisibilityBody(
            choices: _org ? orgVisibilityChoices : platformVisibilityChoices,
            value: v.parentsSee,
            platformDefault: v.platformDefault,
            effective: v.effective,
            onPick: _pick),
    ]);
  }
}

Future<void> openParentGradeVisibility(BuildContext context, {int? orgId}) =>
    showAppSheet<void>(context, (_) => ParentVisibilitySheet(orgId: orgId));
