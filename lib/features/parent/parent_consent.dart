// lib/features/parent/parent_consent.dart — a parent's consent to link a child under the country's minor age
// (Learning Hub F3, CONTRACT §3, D-1311).
//   ParentConsentBody          the consent text (version [kConsentVersion]) and its checkbox; plain values
//   showParentConsentDialog    the dialog: the box must be ticked before "I agree" works; true when agreed
//   ConsentNeededNotice        the line + "Give consent" button on a child card whose `needs_consent` is true
//   ConsentRequiredView        a child tab's whole-page state for 403 `consent_required` (plain values)
//   ParentConsentRequired      the same with its action: the dialog, then POST; `onGranted` reloads the tab
//   revokeParentConsentFlow    "Revoke consent" on a child card: GET (is there one?), appConfirm, DELETE
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
import 'package:flutter_education_app/design/app_overlays.dart';

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (childName != null && childName!.isNotEmpty) ...[
          Text(childName!, style: AppType.section(context)),
          AppSpace.gapXs,
        ],
        Text(consentText(), style: AppType.body(context)),
        AppSpace.gapSm,
        InkWell(
          key: const ValueKey('consent.box'),
          borderRadius: AppRadius.controlAll,
          onTap: () => onChanged(!accepted),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Row(
              children: [
                Checkbox(
                  value: accepted,
                  activeColor: c.primary,
                  semanticLabel: _t('أوافق على الإقرار أعلاه', 'I agree to the statement above'),
                  onChanged: (v) => onChanged(v ?? false),
                ),
                Expanded(child: Text(_t('أقرّ وأوافق', 'I confirm and agree'), style: AppType.row(context))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConsentDialogBody extends StatefulWidget {
  const _ConsentDialogBody({required this.childName});
  final String? childName;

  @override
  State<_ConsentDialogBody> createState() => _ConsentDialogBodyState();
}

class _ConsentDialogBodyState extends State<_ConsentDialogBody> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParentConsentBody(accepted: _on, childName: widget.childName, onChanged: (v) => setState(() => _on = v)),
        AppSpace.gapMd,
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton.ghost(label: _t('إلغاء', 'Cancel'), onPressed: () => Navigator.of(context).pop(false)),
            AppSpace.gapXs,
            AppButton.primary(
              key: const ValueKey('consent.agree'),
              label: _t('أوافق', 'I agree'),
              onPressed: _on ? () => Navigator.of(context).pop(true) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Ask for the consent. True only when the box is ticked and "I agree" is pressed.
Future<bool> showParentConsentDialog(BuildContext context, {String? childName}) async {
  final r = await showAppDialog<bool>(
    context,
    title: _t('موافقة ولي الأمر', 'Parent consent'),
    icon: Icons.verified_user_outlined,
    body: _ConsentDialogBody(childName: childName),
  );
  return r == true;
}

/// A child card's "consent needed" line with its action.
class ConsentNeededNotice extends StatelessWidget {
  const ConsentNeededNotice({super.key, required this.onGive, this.busy = false});

  final VoidCallback onGive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _t('هذا الطالب دون السن القانونية: نحتاج موافقتك على الربط.',
              'This student is under the legal age: we need your consent to the link.'),
          style: AppType.meta(context).copyWith(color: context.colors.warning),
        ),
        AppSpace.gapXs,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.tonal(
            key: const ValueKey('consent.give'),
            label: _t('إعطاء الموافقة', 'Give consent'),
            icon: Icons.verified_user_outlined,
            size: AppButtonSize.sm,
            busy: busy,
            onPressed: busy ? null : onGive,
          ),
        ),
      ],
    );
  }
}

/// True for the 403 `consent_required` a child's games / Quran / grammar route answers (D-1371).
bool isConsentRequired(Object e) {
  if (e is! ApiException) return false;
  return (e.code ?? e.detail['code']?.toString()) == 'consent_required';
}

/// A child tab's state when the server needs this parent's consent first: why, and the action that gives it.
class ConsentRequiredView extends StatelessWidget {
  const ConsentRequiredView({super.key, required this.onGive, this.childName, this.busy = false});

  final VoidCallback onGive;
  final String? childName;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final name = childName?.trim() ?? '';
    return AppEmpty(
      key: const ValueKey('consent.required'),
      icon: Icons.verified_user_outlined,
      title: _t('نحتاج موافقتك أولاً', 'Your consent is needed first'),
      message: name.isEmpty
          ? _t('هذا الطالب دون السن القانونية، فلا نعرض بياناته لولي الأمر إلا بعد موافقته.',
              'This student is under the legal age, so their data is shown to a parent only after the parent consents.')
          : _t('$name دون السن القانونية، فلا نعرض بياناته لولي الأمر إلا بعد موافقته.',
              '$name is under the legal age, so their data is shown to a parent only after the parent consents.'),
      actionLabel: _t('إعطاء الموافقة', 'Give consent'),
      onAction: busy ? null : onGive,
    );
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
/// revoke, said so), then asks with [appConfirm] and sends DELETE. True when a consent was revoked.
Future<bool> revokeParentConsentFlow(BuildContext context, int studentId, String childName, {ApiClient? api}) async {
  final client = api ?? ApiClient();
  try {
    final v = await client.get('/api/v1/parent/children/$studentId/consent');
    if (v is! Map || v['granted'] != true) {
      showAppNotice(_t('لا توجد موافقة مسجّلة منك لهذا الطالب', 'You have no recorded consent for this student'));
      return false;
    }
    if (!context.mounted) return false;
    final ok = await appConfirm(
      context,
      danger: true,
      confirmLabel: _t('سحب الموافقة', 'Revoke consent'),
      message: _t(
          'سحب موافقتك على متابعة $childName؟ لن ترى ألعابه وحفظه ونحوه حتى توافق مرة أخرى. يبقى الربط كما هو.',
          'Revoke your consent for $childName? You will not see their games, Quran and grammar until you consent '
              'again. The link stays.'),
    );
    if (!ok) return false;
    await client.delete('/api/v1/parent/children/$studentId/consent');
    showAppNotice(_t('سُحبت موافقتك', 'Your consent was revoked'));
    return true;
  } catch (e) {
    showAppNotice(apiErrorText(ApiException.from(e)), error: true);
    return false;
  }
}
