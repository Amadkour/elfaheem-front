// components/exts.dart
//
// The live room's small questions and notices (publish, play audio, disconnect, reconnect, recording, errors …),
// drawn by the kit's dialog (paper, radius 28, an editorial headline beside a tinted mark, the warm scrim, AppPopIn;
// D-612): Cancel / No as a ghost button, the answer as the solid primary (the danger fill when it ends something).
// Each keeps its old result: true / false / null when dismissed.
import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../design/app_kit.dart';

/// A yes / no question: [no] pops false, [yes] pops true.
Future<bool?> _ask(
  BuildContext context, {
  required String title,
  required String message,
  required String no,
  required String yes,
  IconData? icon,
  bool danger = false,
}) =>
    showAppDialog<bool>(
      context,
      title: title,
      icon: icon,
      danger: danger,
      body: Text(message),
      actions: [
        Builder(builder: (ctx) => AppButton.ghost(label: no, onPressed: () => Navigator.pop(ctx, false))),
        Builder(
          builder: (ctx) => danger
              ? AppButton.danger(label: yes, onPressed: () => Navigator.pop(ctx, true))
              : AppButton.primary(label: yes, onPressed: () => Navigator.pop(ctx, true)),
        ),
      ],
    );

/// A notice with one OK button that pops [result].
Future<T?> _tell<T>(BuildContext context, {required String title, required String message, IconData? icon, T? result, bool danger = false}) =>
    showAppDialog<T>(
      context,
      title: title,
      icon: icon,
      danger: danger,
      body: Text(message),
      actions: [
        Builder(builder: (ctx) => AppButton.primary(label: 'lk_ok'.tr, onPressed: () => Navigator.pop(ctx, result))),
      ],
    );

extension LKExampleExt on BuildContext {
  Future<bool?> showPublishDialog() => _ask(
        this,
        title: 'lk_publish_title'.tr,
        message: 'lk_publish_content'.tr,
        no: 'lk_no'.tr,
        yes: 'lk_yes'.tr,
        icon: Icons.videocam_rounded,
      );

  Future<bool?> showPlayAudioManuallyDialog() => _ask(
        this,
        title: 'lk_play_audio_title'.tr,
        message: 'lk_play_audio_content'.tr,
        no: 'lk_ignore'.tr,
        yes: 'lk_play_audio_btn'.tr,
        icon: Icons.volume_up_rounded,
      );

  Future<bool?> showUnPublishDialog() => _ask(
        this,
        title: 'lk_unpublish_title'.tr,
        message: 'lk_unpublish_content'.tr,
        no: 'lk_no'.tr,
        yes: 'lk_yes'.tr,
        icon: Icons.videocam_off_rounded,
      );

  Future<void> showErrorDialog(dynamic exception) => _tell<void>(
        this,
        title: 'lk_error_title'.tr,
        message: exception.toString(),
        icon: Icons.error_outline_rounded,
        danger: true,
      );

  Future<bool?> showDisconnectDialog() => _ask(
        this,
        title: 'lk_disconnect_title'.tr,
        message: 'lk_disconnect_content'.tr,
        no: 'cancel'.tr,
        yes: 'lk_disconnect_btn'.tr,
        icon: Icons.call_end_rounded,
        danger: true,
      );

  Future<bool?> showReconnectDialog() => _ask(
        this,
        title: 'lk_reconnect_title'.tr,
        message: 'lk_reconnect_content'.tr,
        no: 'cancel'.tr,
        yes: 'lk_reconnect_btn'.tr,
        icon: Icons.sync_rounded,
      );

  Future<void> showReconnectSuccessDialog() => _tell<void>(
        this,
        title: 'lk_reconnect_title'.tr,
        message: 'lk_reconnect_success_content'.tr,
        icon: Icons.check_circle_rounded,
      );

  Future<bool?> showSendDataDialog() => _ask(
        this,
        title: 'lk_send_data_title'.tr,
        message: 'lk_send_data_content'.tr,
        no: 'cancel'.tr,
        yes: 'lk_send_btn'.tr,
        icon: Icons.send_rounded,
      );

  Future<bool?> showDataReceivedDialog(String data) => _tell<bool>(
        this,
        title: 'lk_received_data_title'.tr,
        message: data,
        icon: Icons.mark_chat_read_rounded,
        result: true,
      );

  Future<bool?> showRecordingStatusChangedDialog(bool isActiveRecording) => _tell<bool>(
        this,
        title: 'lk_recording_reminder_title'.tr,
        message: isActiveRecording ? 'lk_recording_active'.tr : 'lk_recording_stopped'.tr,
        icon: Icons.fiber_manual_record_rounded,
        result: true,
      );

  Future<bool?> showSubscribePermissionDialog() => _ask(
        this,
        title: 'lk_subscribe_permission_title'.tr,
        message: 'lk_subscribe_permission_content'.tr,
        no: 'lk_no'.tr,
        yes: 'lk_yes'.tr,
        icon: Icons.lock_open_rounded,
      );

  /// A developer tool: one 48 px row per scenario.
  Future<SimulateScenarioResult?> showSimulateScenarioDialog() => showAppDialog<SimulateScenarioResult>(
        this,
        title: 'lk_simulate_scenario_title'.tr,
        icon: Icons.science_rounded,
        body: Builder(
          builder: (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in SimulateScenarioResult.values)
                InkWell(
                  borderRadius: AppRadius.controlAll,
                  onTap: () => Navigator.pop(ctx, e),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppTouch.min),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xs),
                        child: Text(e.name, style: AppType.row(ctx)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

enum SimulateScenarioResult {
  signalReconnect,
  fullReconnect,
  speakerUpdate,
  nodeFailure,
  migration,
  serverLeave,
  switchCandidate,
  e2eeKeyRatchet,
  participantName,
  participantMetadata,
  clear,
}
