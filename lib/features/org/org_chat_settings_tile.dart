// lib/features/org/org_chat_settings_tile.dart — the organization's switch for private chat between its students (D-330).
// Off by default; the server enforces it (`/orgs/{id}/chat-settings`, right organization.update).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppSettingsSearchable, AppSettingsTile, AppSwitch, showAppNotice;

import '../admin/admin_common.dart' show t;

class OrgChatSettingsTile extends StatefulWidget implements AppSettingsSearchable {
  const OrgChatSettingsTile({super.key, required this.orgId, this.api});
  final int orgId;
  final ApiClient? api;

  @override
  String get searchText => t('الرسائل بين الطلاب', 'Messages between students');

  @override
  State<OrgChatSettingsTile> createState() => _OrgChatSettingsTileState();
}

class _OrgChatSettingsTileState extends State<OrgChatSettingsTile> {
  bool? _on;
  String get _path => '/api/v1/org/orgs/${widget.orgId}/chat-settings';
  ApiClient get _c => widget.api ?? ApiClient();

  @override
  void initState() {
    super.initState();
    _c.get(_path).then((r) {
      if (mounted) setState(() => _on = (r as Map)['student_dm'] == true);
    }).catchError((Object _) {
      if (mounted) setState(() => _on = false);
    });
  }

  Future<void> _set(bool v) async {
    final was = _on;
    setState(() => _on = v);
    try {
      await _c.put(_path, body: {'student_dm': v});
    } catch (e) {
      if (mounted) setState(() => _on = was);
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AppSettingsTile(
        icon: Icons.forum_rounded,
        label: t('الرسائل بين الطلاب', 'Messages between students'),
        subtitle: t('متوقفة افتراضيًا. عند تفعيلها يمكن للطلاب المراسلة الخاصة بينهم.', 'Off by default. When on, students can message each other privately.'),
        trailing: AppSwitch(value: _on ?? false, onChanged: _on == null ? null : _set),
      );
}
