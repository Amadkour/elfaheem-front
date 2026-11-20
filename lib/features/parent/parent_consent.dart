// lib/features/parent/parent_consent.dart — a parent's consent to link a child under the country's minor age
// (Learning Hub F3, CONTRACT §3, D-1311).
//   ParentConsentBody          the consent text (version [kConsentVersion]) and its checkbox; plain values
//   showParentConsentDialog    the dialog: the box must be ticked before "I agree" works; true when agreed
//   ConsentNeededNotice        the line + "Give consent" button on a child card whose `needs_consent` is true
// The server answers 422 `consent_required` to a redeem without consent; `needs_consent` in /parent/children marks an
// already linked child. POST /parent/children/{id}/consent {accepted: true, text_version} records it for the latter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
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
