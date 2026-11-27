// lib/features/parent/signup/pa_child_code_page.dart — "your child's account is ready" (Pa2Gate `screen=done&kid=new`)
// and the sign-in code block of a child page.
//
//   ParentChildCodePage   the success tick, the child's card (linked), the 6-digit code shown ONCE, how long it lasts,
//                         "Send the code on WhatsApp" (wa.me with the server's share text) and "Go to Today"
//   PaChildCodeBlock      on the page of a child this parent created: whether a code is active and for how long, and
//                         "New code" (the old unused one stops working), which opens the page above
//   paSendPendingChild    the dashboard's first frame: a child the join flow kept for later is created now
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/share/external_link.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../config/app_config.dart';
import '../pa_kit.dart';
import 'pa_child_api.dart';

/// "Your child's account is ready" with the code.
class ParentChildCodePage extends StatelessWidget {
  const ParentChildCodePage({super.key, required this.child, required this.code, this.parentName, this.fresh = true});

  final PaCreatedChild child;
  final PaLoginCode code;

  /// The parent's first name for the greeting ("Welcome, Ahmed").
  final String? parentName;

  /// true: the account was just made (sign-up); false: a new code for an existing child.
  final bool fresh;

  Future<void> _whatsapp() async {
    final text = code.share.isNotEmpty ? code.share : paFmt('pa_code_share_fallback', {'name': child.firstName, 'code': code.display});
    await openExternalLink('https://wa.me/?text=${Uri.encodeComponent(text)}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final wide = paWide(context);
    final name = parentName?.trim() ?? '';
    final hours = code.hours > 0 ? code.hours : 48;
    final hero = AppHero(
      kicker: 'pa_done'.tr,
      title: name.isEmpty ? 'pa_done_title'.tr : paFmt('pa_welcome_name', {'name': name}),
      subtitle: paFmt(fresh ? 'pa_code_sub_new' : 'pa_code_sub_again', {'name': child.firstName}),
    );
    final card = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: AppDashSize.ring * 1.2,
            height: AppDashSize.ring * 1.2,
            decoration: BoxDecoration(shape: BoxShape.circle, color: kit.ok.color),
            child: Icon(Icons.check_rounded, color: c.onHero, size: AppIconSize.hero),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(paFmt('pa_child_ready', {'name': child.firstName}), textAlign: TextAlign.center, style: AppType.pageTitle(context)),
        Text(fresh ? 'pa_child_ready_sub'.tr : 'pa_code_new_sub'.tr, textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: c.textMedium)),
        const SizedBox(height: AppSpace.md),
        AppTile(
          leading: PaKidAvatar(id: child.id, name: child.name, size: AppDashSize.glyph),
          title: child.name,
          subtitle: child.grade.isEmpty ? null : child.grade,
          trailing: AppStatusBadge(label: 'pa_linked'.tr, tone: AppTone.success),
        ),
        const SizedBox(height: AppSpace.sm),
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: kit.well,
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: kit.line, width: AppBorder.strong),
          ),
          child: Column(children: [
            Text(paFmt('pa_code_label', {'name': child.firstName}), style: AppType.meta(context)),
            const SizedBox(height: AppSpace.xs),
            Semantics(
              label: paFmt('pa_code_label', {'name': child.firstName}),
              value: code.code.split('').join(' '),
              child: ExcludeSemantics(
                child: FittedBox(
                  child: Text(
                    appDigits(code.display),
                    key: const ValueKey('pa.code.value'),
                    textDirection: TextDirection.ltr,
                    style: AppType.figureLarge(context).copyWith(fontSize: AppIconSize.hero, letterSpacing: AppSpace.xxs, color: c.textDark),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(paFmt('pa_code_send_hint', {'name': child.firstName}), textAlign: TextAlign.center, style: AppType.row(context)),
            AppButton.ghost(
              label: 'pa_copy'.tr,
              icon: Icons.copy_rounded,
              size: AppButtonSize.sm,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code.code));
                showAppNotice('pa_copied'.tr);
              },
            ),
          ]),
        ),
        const SizedBox(height: AppSpace.sm),
        PaNote(icon: Icons.schedule_rounded, text: paFmt('pa_code_once', {'h': appDigits('$hours')})),
        const SizedBox(height: AppSpace.md),
        AppButton.primary(
          key: const ValueKey('pa.code.whatsapp'),
          label: 'pa_send_whatsapp'.tr,
          icon: Icons.chat_rounded,
          expand: true,
          onPressed: _whatsapp,
        ),
        const SizedBox(height: AppSpace.xs),
        AppButton.secondary(
          key: const ValueKey('pa.code.done'),
          label: 'pa_go_today'.tr,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]),
    );
    return paRole(BasePage(
      appBar: ScreenAppBar(title: fresh ? 'pa_signup_done'.tr : 'pa_code_title'.tr),
      child: PaHeroPage(hero: hero, width: wide ? AppWidth.form : AppWidth.full, body: card),
    ));
  }
}

/// The sign-in code of a child this parent created (shown on the child's page).
class PaChildCodeBlock extends StatefulWidget {
  const PaChildCodeBlock({super.key, required this.childId, required this.name, required this.grade, this.api});

  final int childId;
  final String name, grade;
  final PaChildApi? api;

  /// For [ParentChildPage.codeBlock]: only a child this parent created, and only with `parent.create_child` on.
  static Widget? forRow(BuildContext context, Map<String, dynamic> row) {
    if (row['created_by_me'] != true || !paCreateChildOn()) return null;
    final id = (row['id'] as num?)?.toInt();
    if (id == null) return null;
    return PaChildCodeBlock(childId: id, name: '${row['name'] ?? ''}', grade: '${row['grade_name'] ?? ''}');
  }

  @override
  State<PaChildCodeBlock> createState() => _PaChildCodeBlockState();
}

class _PaChildCodeBlockState extends State<PaChildCodeBlock> {
  late final PaChildApi _api = widget.api ?? PaChildApi();
  PaCodeStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _api.status(widget.childId).then((s) {
      if (mounted) setState(() => _status = s);
    }).catchError((_) {});
  }

  Future<void> _newCode() async {
    setState(() => _busy = true);
    try {
      final code = await _api.newCode(widget.childId);
      if (!mounted || code == null) return;
      final first = widget.name.split(' ').first;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ParentChildCodePage(
          fresh: false,
          code: code,
          child: PaCreatedChild(id: widget.childId, name: widget.name, firstName: first, gradeAr: widget.grade, gradeEn: widget.grade),
        ),
      ));
      if (mounted) setState(() => _status = PaCodeStatus(active: true, secondsLeft: code.ttlSeconds));
    } catch (e) {
      showAppNotice(apiErrorText(ApiException.from(e)), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final left = s?.secondsLeft;
    final line = s == null
        ? null
        : s.active
            ? paFmt('pa_code_active', {'h': appDigits('${((left ?? 0) / 3600).ceil()}')})
            : 'pa_code_none'.tr;
    return AppCard(
      title: 'pa_code_title'.tr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(paFmt('pa_code_block_hint', {'name': widget.name.split(' ').first}), style: AppType.body(context)),
        if (line != null) ...[
          const SizedBox(height: AppSpace.xs),
          AppStatusBadge(label: line, tone: s!.active ? AppTone.success : AppTone.neutral),
        ],
        const SizedBox(height: AppSpace.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.secondary(
            key: ValueKey('pa.code.new.${widget.childId}'),
            label: 'pa_code_new'.tr,
            icon: Icons.refresh_rounded,
            busy: _busy,
            onPressed: _busy ? null : _newCode,
          ),
        ),
      ]),
    );
  }
}

/// The child the join flow kept: created now that the parent has a session, then the code page. Quiet when there is
/// none; a refused create keeps nothing (the parent adds the child from Children).
Future<void> paSendPendingChild(BuildContext context, {String? parentName, PaChildApi? api}) async {
  if (!paCreateChildOn()) return;
  final d = await PaChildDraft.load();
  if (d == null || !context.mounted) return;
  try {
    final made = await (api ?? PaChildApi()).create(d);
    await PaChildDraft.clear();
    final code = made?.code;
    if (made == null || code == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ParentChildCodePage(child: made, code: code, parentName: parentName),
    ));
  } catch (e) {
    await PaChildDraft.clear();
    showAppNotice(apiErrorText(ApiException.from(e)), error: true);
  }
}

