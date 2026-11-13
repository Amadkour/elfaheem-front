// lib/features/shared/certificates_issue/cert_issue_actions.dart
//
// Small actions every issuing screen shares: open a download link, save a file, copy a link, ask a reason / a
// name, edit a recipient's values, show a certificate image.
library;


import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_tokens.dart';
import 'cert_issue_logic.dart';

/// A server file URL ("/files/…" relative to the API, or absolute) opened outside the app (download / viewer).
Future<void> certOpenUrl(String? url) async {
  if (url == null || url.isEmpty) return;
  var u = url;
  if (u.startsWith('/')) {
    final base = AppConfig.baseUrl.endsWith('/') ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1) : AppConfig.baseUrl;
    u = '$base$u';
  }
  final uri = Uri.tryParse(u);
  final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) showAppNotice('ci_open_failed'.tr, error: true);
}

/// Saves [bytes] as a file (a download on the web, the device's save flow on phones).
Future<bool> certSaveFile(String name, Uint8List bytes, String ext) async {
  try {
    await FileSaver.instance.saveFile(
      name: name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'),
      bytes: bytes,
      fileExtension: ext,
      mimeType: ext == 'xlsx' ? MimeType.microsoftExcel : (ext == 'csv' ? MimeType.csv : MimeType.other),
    );
    showAppNotice('ci_file_saved'.tr);
    return true;
  } catch (_) {
    showAppNotice('ci_file_failed'.tr, error: true);
    return false;
  }
}

Future<void> certCopy(String? text) async {
  if (text == null || text.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: text));
  showAppNotice('ci_link_copied'.tr);
}

/// One line of text in a dialog (a list name, a revoke reason). Null = cancelled.
Future<String?> certAskText(BuildContext context,
    {required String title, required String label, String? message, String? initial, String? confirm, bool danger = false,
    bool required = true}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final c = ctx.colors;
      return StatefulBuilder(builder: (ctx, set) {
        final ok = !required || ctrl.text.trim().isNotEmpty;
        return AlertDialog(
          title: Text(title, style: AppType.section(ctx)),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (message != null) ...[Text(message, style: AppType.meta(ctx)), const SizedBox(height: AppSpace.sm)],
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 255,
                onChanged: (_) => set(() {}),
                onSubmitted: (v) {
                  if (!required || v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
                },
                decoration: InputDecoration(labelText: label),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr)),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: c.dangerBase) : null,
              onPressed: ok ? () => Navigator.pop(ctx, ctrl.text.trim()) : null,
              child: Text(confirm ?? 'save'.tr),
            ),
          ],
        );
      });
    },
  );
}

/// The result of the values editor.
class CertValuesEdit {
  const CertValuesEdit(this.values, {this.sendEmail = false, this.issueNow = false, this.reason});
  final Map<String, String> values;
  final bool sendEmail;
  final bool issueNow;
  final String? reason;
}

/// A sheet with one field per column (a review row, a new person on a list, a re-issue). The switches appear only
/// when their label is given.
Future<CertValuesEdit?> certEditValues(
  BuildContext context, {
  required String title,
  required List<IssueColumn> columns,
  Map<String, String> initial = const {},
  String? confirm,
  String? sendEmailLabel,
  String? issueNowLabel,
  bool issueNowDefault = true,
  bool askReason = false,
}) {
  final ctrls = {for (final c in columns) c.key: TextEditingController(text: initial[c.key] ?? '')};
  final reason = TextEditingController();
  var sendEmail = false;
  var issueNow = issueNowDefault;
  return showAppSheet<CertValuesEdit>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final nameOk = (ctrls['student_name']?.text.trim() ?? 'x').isNotEmpty;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSheetHeader(title),
            for (final col in columns)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: TextField(
                  controller: ctrls[col.key],
                  onChanged: (_) => set(() {}),
                  keyboardType: col.key == 'email' ? TextInputType.emailAddress : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: col.label,
                    hintText: col.required ? null : 'ci_optional'.tr,
                  ),
                ),
              ),
            if (askReason)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: TextField(
                  controller: reason,
                  decoration: InputDecoration(labelText: 'ci_reason'.tr, hintText: 'ci_optional'.tr),
                ),
              ),
            if (issueNowLabel != null)
              AppSwitchTile(value: issueNow, onChanged: (v) => set(() => issueNow = v), title: issueNowLabel),
            if (sendEmailLabel != null)
              AppSwitchTile(value: sendEmail, onChanged: (v) => set(() => sendEmail = v), title: sendEmailLabel),
            const SizedBox(height: AppSpace.sm),
            AppPrimaryButton(
              label: confirm ?? 'save'.tr,
              icon: Icons.check_rounded,
              onPressed: nameOk
                  ? () => Navigator.pop(
                        ctx,
                        CertValuesEdit({for (final e in ctrls.entries) e.key: e.value.text.trim()},
                            sendEmail: sendEmail, issueNow: issueNow, reason: reason.text.trim()),
                      )
                  : null,
            ),
          ]),
        );
      }));
}

/// The certificate image(s) in a dialog, with the language switch when there are two.
Future<void> certShowImage(BuildContext context, IssuedCert cert) {
  final langs = [if (cert.urlAr != null) 'ar', if (cert.urlEn != null) 'en'];
  if (langs.isEmpty) return Future.value();
  var lang = langs.contains(AppConfig.lang) ? AppConfig.lang : langs.first;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final url = lang == 'ar' ? cert.urlAr! : cert.urlEn!;
      return Dialog(
        insetPadding: const EdgeInsets.all(AppSpace.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(cert.recipientName, style: AppType.section(ctx), maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(tooltip: 'close'.tr, onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
              ]),
              if (langs.length > 1)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [for (final l in langs) ButtonSegment(value: l, label: Text(certLangLabel(l)))],
                    selected: {lang},
                    onSelectionChanged: (s) => set(() => lang = s.first),
                  ),
                ),
              const SizedBox(height: AppSpace.sm),
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(url, fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Padding(
                            padding: EdgeInsets.all(AppSpace.xl),
                            child: Icon(Icons.broken_image_outlined, size: AppIconSize.hero),
                          )),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                OutlinedButton.icon(
                  onPressed: () => certOpenUrl(url),
                  icon: const Icon(Icons.download_rounded, size: AppIconSize.md),
                  label: Text('ci_download_image'.tr),
                ),
                if (cert.verifyUrl != null)
                  OutlinedButton.icon(
                    onPressed: () => certCopy(cert.verifyUrl),
                    icon: const Icon(Icons.link_rounded, size: AppIconSize.md),
                    label: Text('ci_copy_link'.tr),
                  ),
              ]),
            ]),
          ),
        ),
      );
    }),
  );
}
