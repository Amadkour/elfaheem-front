// ─────────────────────────────────────────────────────────────────────────────
// add_item_dialog.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPopIn;

/// Asks for one line of text (a course goal, a requirement, …) and hands it to [onAdd] when it is not empty.
///
/// The kit's paper dialog (the same shell as `appConfirm`): the kit field, Cancel and Add as kit buttons in the
/// app's language (they were Arabic-only), Enter adds.
Future<void> addItemDialog(String hint, void Function(String) onAdd, BuildContext context) async {
  final ctrl = TextEditingController();
  final dir = Directionality.of(context);

  final result = await showDialog<String>(
    context: context,
    barrierColor: appScrimColor(context),
    builder: (dialogContext) => Directionality(
      textDirection: dir,
      child: AddItemPanel(hint: hint, ctrl: ctrl),
    ),
  );
  ctrl.dispose();

  if (result != null && result.isNotEmpty) onAdd(result);
}

/// The dialog's panel from plain values (public so a layout test can pump it). Pops the trimmed text, or null.
class AddItemPanel extends StatelessWidget {
  const AddItemPanel({super.key, required this.hint, required this.ctrl});

  final String hint;
  final TextEditingController ctrl;

  /// The widest the question gets (matches the confirm dialog).
  static const double _maxWidth = AppConfirmDialog.maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    void submit() => Navigator.pop(context, ctrl.text.trim());
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpace.md),
      child: AppPopIn(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Material(
            color: c.cardBg,
            surfaceTintColor: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sheet),
              side: AppElevation.border(context, 4)?.top ?? BorderSide.none,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(hint, style: AppType.section(context)),
                  AppSpace.gapMd,
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    style: AppType.body(context).copyWith(color: c.textDark),
                    decoration: appFieldDecoration(context, hint: hint),
                  ),
                  AppSpace.gapLg,
                  Row(children: [
                    Expanded(
                      child: AppButton.secondary(
                        key: const ValueKey('add_item.cancel'),
                        label: 'cancel'.tr,
                        expand: true,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    AppSpace.gapSm,
                    Expanded(
                      child: AppButton.primary(
                        key: const ValueKey('add_item.add'),
                        label: 'btn_add'.tr,
                        icon: Icons.add_rounded,
                        expand: true,
                        onPressed: submit,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
