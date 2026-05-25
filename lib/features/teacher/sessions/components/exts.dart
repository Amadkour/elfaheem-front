import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';

extension LKExampleExt on BuildContext {
  //
  Future<bool?> showPublishDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: Text('lk_publish_title'.tr),
      content: Text('lk_publish_content'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('lk_no'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('lk_yes'.tr),
        ),
      ],
    ),
  );

  Future<bool?> showPlayAudioManuallyDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: Text('lk_play_audio_title'.tr),
      content: Text('lk_play_audio_content'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('lk_ignore'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('lk_play_audio_btn'.tr),
        ),
      ],
    ),
  );

  Future<bool?> showUnPublishDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: Text('lk_unpublish_title'.tr),
      content: Text('lk_unpublish_content'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('lk_no'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('lk_yes'.tr),
        ),
      ],
    ),
  );

  Future<void> showErrorDialog(dynamic exception) => showDialog<void>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: Text('lk_error_title'.tr),
      content: Text(exception.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('lk_ok'.tr),
        )
      ],
    ),
  );

  Future<bool?> showDisconnectDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: Text('lk_disconnect_title'.tr),
      content: Text('lk_disconnect_content'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('cancel'.tr),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx, true);
          },
          child: Text('lk_disconnect_btn'.tr),
        ),
      ],
    ),
  );

  Future<bool?> showReconnectDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: Text('lk_reconnect_title'.tr),
      content: Text('lk_reconnect_content'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('cancel'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('lk_reconnect_btn'.tr),
        ),
      ],
    ),
  );

  Future<void> showReconnectSuccessDialog() => showDialog<void>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: Text('lk_reconnect_title'.tr),
      content: Text('lk_reconnect_success_content'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('lk_ok'.tr),
        ),
      ],
    ),
  );

  Future<bool?> showSendDataDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: Text('lk_send_data_title'.tr),
      content: Text('lk_send_data_content'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('cancel'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('lk_send_btn'.tr),
        ),
      ],
    ),
  );

  Future<bool?> showDataReceivedDialog(String data) => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: Text('lk_received_data_title'.tr),
      content: Text(data),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('lk_ok'.tr),
        ),
      ],
    ),
  );

  Future<bool?> showRecordingStatusChangedDialog(
      bool isActiveRecording) =>
      showDialog<bool>(
        context: this,
        builder: (ctx) => AlertDialog(
          title: Text('lk_recording_reminder_title'.tr),
          content: Text(isActiveRecording
              ? 'lk_recording_active'.tr
              : 'lk_recording_stopped'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('lk_ok'.tr),
            ),
          ],
        ),
      );

  Future<bool?> showSubscribePermissionDialog() => showDialog<bool>(
    context: this,
    builder: (ctx) => AlertDialog(
      title: Text('lk_subscribe_permission_title'.tr),
      content: Text('lk_subscribe_permission_content'.tr),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('lk_no'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('lk_yes'.tr),
        ),
      ],
    ),
  );

  Future<SimulateScenarioResult?> showSimulateScenarioDialog() =>
      showDialog<SimulateScenarioResult>(
        context: this,
        builder: (ctx) => SimpleDialog(
          title: Text('lk_simulate_scenario_title'.tr),
          children: SimulateScenarioResult.values
              .map((e) => SimpleDialogOption(
            child: Text(e.name),
            onPressed: () => Navigator.pop(ctx, e),
          ))
              .toList(),
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