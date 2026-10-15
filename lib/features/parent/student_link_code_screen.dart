// lib/features/student/parent_link/student_link_code_screen.dart
// Student: generate the temporary single-use code a parent needs, copy / share it,
// see the parents already linked (and unlink one).
//
// Opened from the student's profile:  Navigator.push(... StudentLinkCodeScreen())
// Needs: share_plus (Share.share).  Remove the share button if you do not use it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/parent/parent_link_providers.dart';
import 'package:flutter_education_app/features/parent/parent_widgets.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_config.dart';
class StudentLinkCodeScreen extends StatelessWidget {
  const StudentLinkCodeScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => StudentLinkProvider()..load(),
        child: const _Body(),
      );
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _mmss(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = context.watch<StudentLinkProvider>();
    final c = context.colors;
    final left = p.secondsLeft;

    return BasePage(
      appBar: ScreenAppBar(title: 'pl_link_code_title'.tr),
      child: RefreshIndicator(
        onRefresh: p.load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('pl_link_code_hint'.tr, style: c.caption),
            const SizedBox(height: 16),
            PlCard(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                if (p.codeVisible) ...[
                  SelectableText(
                    p.code!,
                    textDirection: TextDirection.ltr,
                    style: c.h2.copyWith(fontSize: 38, letterSpacing: 6, color: c.primary),
                  ),
                  const SizedBox(height: 8),
                  Text('${'pl_expires_in'.tr} ${_mmss(left)}',
                      style: TextStyle(color: left < 60 ? c.danger : c.success, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded),
                      label: Text('pl_copy'.tr),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: p.code!));
                        Helpers.showMessage('pl_copied'.tr);
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.share_rounded),
                      label: Text('pl_share'.tr),
                      onPressed: () => Share.share('${'pl_share_text'.tr}\n${p.code!}'),
                    ),
                  ]),
                ] else ...[
                  Icon(p.hasActive ? Icons.hourglass_bottom_rounded : Icons.key_rounded,
                      size: 54, color: c.primary),
                  const SizedBox(height: 10),
                  Text(p.hasActive ? 'pl_code_hidden'.tr : 'pl_no_active_code'.tr,
                      textAlign: TextAlign.center, style: c.caption),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: p.isLoading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.autorenew_rounded),
                    label: Text(p.codeVisible ? 'pl_new_code'.tr : 'pl_generate_code'.tr),
                    onPressed: p.isLoading
                        ? null
                        : () async {
                            final ok = await p.generate();
                            if (!ok) plToast(p.errorMessage);
                          },
                  ),
                ),
                const SizedBox(height: 8),
                Text('pl_code_once'.tr, textAlign: TextAlign.center, style: c.caption.copyWith(fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 12),
            Text('pl_linked_parents'.tr, style: c.h2.copyWith(fontSize: 16)),
            const SizedBox(height: 8),
            if (p.parents.isEmpty)
              PlCard(child: Text('pl_no_parents'.tr, style: c.caption))
            else
              for (final e in p.parents)
                PlCard(
                  child: Row(children: [
                    Icon(Icons.family_restroom_rounded, color: c.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${e['name']}', style: c.h2.copyWith(fontSize: 15))),
                    IconButton(
                      tooltip: 'pl_unlink'.tr,
                      icon: Icon(Icons.link_off_rounded, color: c.danger),
                      onPressed: () async {
                        final ok = await Helpers.confirmDialog(context);
                        if (ok == true && context.mounted) {
                          final done = await p.unlink(e['link_id'] as int);
                          if (!done) plToast(p.errorMessage);
                        }
                      },
                    ),
                  ]),
                ),
          ],
        ),
      ),
    );
  }
}
