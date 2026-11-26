// lib/features/parent/parent_consent.dart — a parent's consent to link a child under the country's minor age
// (Learning Hub F3, CONTRACT §3, D-1311).
//   ParentConsentBody          the consent text (version [kConsentVersion]) and its checkbox; plain values
//   showParentConsentDialog    the sheet (Pa2Kids `screen=consent`): the box must be ticked before "I agree" works; true when agreed
//   ConsentNeededNotice        the line + "Give consent" button on a child card whose `needs_consent` is true
//   ConsentRequiredView        a child tab's whole-page state for 403 `consent_required` (plain values)
//   ParentConsentRequired      the same with its action: the dialog, then POST; `onGranted` reloads the tab
//   revokeParentConsentFlow    "Revoke consent" on a child card: GET (is there one?), the sheet (`screen=revoke`), DELETE
// The server answers 422 `consent_required` to a redeem without consent; `needs_consent` in /parent/children marks an
// already linked child. POST /parent/children/{id}/consent {accepted: true, text_version} records it for the latter.
// Phase 10 (D-1371): consent belongs to the parent-student pair; the child's games / Quran / grammar routes answer
// 403 `consent_required` without it, DELETE /parent/children/{id}/consent revokes it, and a student who unlinks a
// parent revokes that parent's consent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/parent/pa_kit.dart';

/// The version of the consent text below; sent as `text_version`. Change it with the text.
const kConsentVersion = 'v1';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

String consentText() => _t(
      'أُقرّ بأنني ولي أمر هذا الطالب، وأن عمره أقل من السن القانونية في بلده، وأوافق على ربط حسابي بحسابه '
          'ليتمكن من متابعة حضوره ودرجاته وتقدّمه، وعلى معالجة بياناته لهذا الغرض فقط. يمكنني إلغاء الربط في أي وقت.',
      'I confirm that I am this student\'s parent or guardian, that the student is under the legal age in their '
          'country, and I agree to link my account to theirs so I can follow their attendance, grades and progress, '
          'and to the processing of their data for that purpose only. I can remove the link at any time.',
    );

class ParentConsentBody extends StatelessWidget {
  const ParentConsentBody({super.key, required this.accepted, required this.onChanged, this.childName});

  final bool accepted;
  final ValueChanged<bool> onChanged;
  final String? childName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(consentText(), style: AppType.body(context)),
        AppSpace.gapSm,
        Semantics(
          checked: accepted,
          child: InkWell(
            key: const ValueKey('consent.box'),
            borderRadius: BorderRadius.circular(AppRadius.tile),
            onTap: () => onChanged(!accepted),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
              decoration: BoxDecoration(
                color: c.kit.well,
                borderRadius: BorderRadius.circular(AppRadius.tile),
                border: Border.all(color: accepted ? set.a : c.kit.line, width: AppBorder.strong),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: accepted,
                    activeColor: set.a,
                    semanticLabel: _t('أوافق على الإقرار أعلاه', 'I agree to the statement above'),
                    onChanged: (v) => onChanged(v ?? false),
                  ),
                  Expanded(child: Text(_t('أقرّ وأوافق', 'I confirm and agree'), style: AppType.row(context))),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConsentSheetBody extends StatefulWidget {
  const _ConsentSheetBody({required this.childName, this.grade});
  final String? childName;
  final String? grade;

  @override
  State<_ConsentSheetBody> createState() => _ConsentSheetBodyState();
}

class _ConsentSheetBodyState extends State<_ConsentSheetBody> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.childName?.trim() ?? '';
    final sub = [
      if (name.isNotEmpty) _t('على متابعة $name', 'To follow $name'),
      if ((widget.grade ?? '').isNotEmpty) widget.grade!,
    ].join(_t('، ', ', '));
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaSheetHead(icon: Icons.shield_outlined, title: _t('موافقة ولي الأمر', 'Parent consent'), subtitle: sub),
          AppSpace.gapMd,
          ParentConsentBody(accepted: _on, onChanged: (v) => setState(() => _on = v)),
          AppSpace.gapMd,
          AppButtonRow(
            primary: AppButton.primary(
              key: const ValueKey('consent.agree'),
              label: _t('أوافق', 'I agree'),
              onPressed: _on ? () => Navigator.of(context).pop(true) : null,
            ),
            secondary: [AppButton.secondary(label: _t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(context).pop(false))],
          ),
        ],
      ),
    );
  }
}

/// Ask for the consent (a sheet). True only when the box is ticked and "I agree" is pressed.
Future<bool> showParentConsentDialog(BuildContext context, {String? childName, String? grade}) async {
  final r = await showAppSheet<bool>(context, (_) => paRole(_ConsentSheetBody(childName: childName, grade: grade)));
  return r == true;
}

/// A child card's "consent needed" line with its action.
class ConsentNeededNotice extends StatelessWidget {
  const ConsentNeededNotice({super.key, required this.onGive, this.busy = false});

  final VoidCallback onGive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AppTile(
      icon: Icons.lock_outline_rounded,
      tone: context.colors.kit.accent(AppAccent.grape),
      title: _t('تنتظر موافقتك', 'Waiting for your consent'),
      subtitle: _t('دون السن النظامية: نعرض الألعاب والحفظ والنحو بعد موافقتك.',
          'Under the legal age: games, Quran and grammar show after you consent.'),
      trailing: AppButton.primary(
        key: const ValueKey('consent.give'),
        label: _t('أعطِ الموافقة', 'Give consent'),
        size: AppButtonSize.sm,
        busy: busy,
        onPressed: busy ? null : onGive,
      ),
    );
  }
}

/// True for the 403 `consent_required` a child's games / Quran / grammar route answers (D-1371).
bool isConsentRequired(Object e) {
  if (e is! ApiException) return false;
  return (e.code ?? e.detail['code']?.toString()) == 'consent_required';
}

/// A child tab's state when the server needs this parent's consent first (Pa2Kids `screen=locked`): why, and the
/// action that gives it.
class ConsentRequiredView extends StatelessWidget {
  const ConsentRequiredView({super.key, required this.onGive, this.childName, this.busy = false});

  final VoidCallback onGive;
  final String? childName;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final name = childName?.trim() ?? '';
    final first = name.split(' ').first;
    final c = context.colors;
    return paRole(Center(
      key: const ValueKey('consent.required'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.form.max),
          child: AppCard(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppIconBox(icon: Icons.lock_outline_rounded, size: AppDashSize.disc, tone: c.kit.accent(AppAccent.grape)),
              AppSpace.gapSm,
              Text(_t('نحتاج موافقتك أول', 'We need your consent first'), textAlign: TextAlign.center, style: AppType.pageTitle(context)),
              AppSpace.gapXs,
              Text(
                first.isEmpty
                    ? _t('هذا الطالب دون السن النظامية، فما نعرض بياناته لولي الأمر إلا بعد موافقته. الموافقة تنسجّل مرة وحدة وتقدر تسحبها متى ما بغيت.',
                        'This student is under the legal age, so their data is shown to a parent only after the parent consents. You give it once and can withdraw it at any time.')
                    : _t('$first دون السن النظامية، فما نعرض بياناته لولي الأمر إلا بعد موافقته. الموافقة تنسجّل مرة وحدة وتقدر تسحبها متى ما بغيت.',
                        '$first is under the legal age, so their data is shown to a parent only after the parent consents. You give it once and can withdraw it at any time.'),
                textAlign: TextAlign.center,
                style: AppType.body(context).copyWith(color: c.textMedium),
              ),
              AppSpace.gapMd,
              AppButton.primary(label: _t('أعطِ الموافقة', 'Give consent'), busy: busy, onPressed: busy ? null : onGive),
            ]),
          ),
        ),
      ),
    ));
  }
}

/// POST /parent/children/{id}/consent. Throws [ApiException].
Future<void> grantParentConsent(int studentId, {ApiClient? api}) async {
  await (api ?? ApiClient()).post('/api/v1/parent/children/$studentId/consent',
      body: {'accepted': true, 'text_version': kConsentVersion});
}

/// [ConsentRequiredView] with its action: the consent dialog, then the POST; [onGranted] reloads the tab.
class ParentConsentRequired extends StatefulWidget {
  const ParentConsentRequired({super.key, required this.studentId, required this.onGranted, this.childName, this.api});

  final int studentId;
  final VoidCallback onGranted;
  final String? childName;
  final ApiClient? api;

  @override
  State<ParentConsentRequired> createState() => _ParentConsentRequiredState();
}

class _ParentConsentRequiredState extends State<ParentConsentRequired> {
  bool _busy = false;

  Future<void> _give() async {
    if (!await showParentConsentDialog(context, childName: widget.childName)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await grantParentConsent(widget.studentId, api: widget.api);
      if (!mounted) return;
      showAppNotice(_t('سُجّلت موافقتك', 'Your consent was recorded'));
      widget.onGranted();
    } catch (e) {
      showAppNotice(apiErrorText(ApiException.from(e)), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ConsentRequiredView(childName: widget.childName, busy: _busy, onGive: _give);
}

/// "Revoke consent" on a child card: reads the pair's consent first (an adult child or no consent: nothing to
/// revoke, said so), then asks in a sheet (Pa2Kids `screen=revoke`) and sends DELETE. True when a consent was revoked.
Future<bool> revokeParentConsentFlow(BuildContext context, int studentId, String childName, {ApiClient? api}) async {
  final client = api ?? ApiClient();
  try {
    final v = await client.get('/api/v1/parent/children/$studentId/consent');
    if (v is! Map || v['granted'] != true) {
      showAppNotice(_t('لا توجد موافقة مسجّلة منك لهذا الطالب', 'You have no recorded consent for this student'));
      return false;
    }
    if (!context.mounted) return false;
    final ok = await showAppSheet<bool>(context, (_) => paRole(_RevokeSheet(childName: childName))) == true;
    if (!ok) return false;
    await client.delete('/api/v1/parent/children/$studentId/consent');
    showAppNotice(_t('سُحبت موافقتك', 'Your consent was revoked'));
    return true;
  } catch (e) {
    showAppNotice(apiErrorText(ApiException.from(e)), error: true);
    return false;
  }
}

class _RevokeSheet extends StatelessWidget {
  const _RevokeSheet({required this.childName});
  final String childName;

  @override
  Widget build(BuildContext context) {
    final first = childName.split(' ').first;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppIconBox(icon: Icons.warning_amber_rounded, size: AppDashSize.disc, tone: context.colors.kit.error),
        AppSpace.gapMd,
        Text(_t('تسحب موافقتك على متابعة $first؟', 'Withdraw your consent to follow $first?'), style: AppType.pageTitle(context)),
        AppSpace.gapXs,
        Text(
          _t('ما راح تشوف ألعاب $first وحفظه ونحوه لين توافق مرة ثانية. الربط يبقى مثل ما هو، وتقدر تشوف التقارير والتنبيهات عادي.',
              "You will not see $first's games, Quran and grammar until you consent again. The link stays, and reports and alerts work as before."),
          style: AppType.body(context).copyWith(color: context.colors.textMedium),
        ),
        AppSpace.gapMd,
        AppButtonRow(
          primary: AppButton.danger(
            key: const ValueKey('consent.revoke.confirm'),
            label: _t('اسحب الموافقة', 'Withdraw consent'),
            dangerOutline: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          secondary: [AppButton.secondary(label: _t('تراجع', 'Go back'), onPressed: () => Navigator.of(context).pop(false))],
        ),
      ]),
    );
  }
}
