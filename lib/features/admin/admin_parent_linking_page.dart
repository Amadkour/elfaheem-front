// lib/features/admin/admin_parent_linking_page.dart — Parent linking: ONE page for the parent ⇄ student link
// requests (every admin) and the linking settings (super admin only). C-round consolidation of the two hub tiles
// "Parent requests" and "Parent-link settings"; both old pages still work on their own.
//
//   Requests   ParentRequestsBody: the table with search, status filter and the request detail (approve / reject).
//   Settings   ParentLinkSettingsForm: the whole settings form. Its Save is the header's one primary action while the
//              tab is open; Back and switching tabs with unsaved changes both ask first (a confirmed switch drops
//              the edits and reloads the server's values).
//
// A plain admin has no Settings tab, so no tab bar is drawn for them.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../design/app_kit.dart';
import '../parent/parent_link_providers.dart';
import 'admin_common.dart';
import 'adm_kit.dart' show admRole;
import 'sup/sup_kit.dart';
import 'admin_parent_link_settings_page.dart';
import 'admin_parent_requests_page.dart';

class AdminParentLinkingPage extends StatefulWidget {
  const AdminParentLinkingPage({super.key, this.openSettings = false});

  /// Open on the Settings tab (a super admin only; ignored for a plain admin).
  final bool openSettings;

  @override
  State<AdminParentLinkingPage> createState() => _AdminParentLinkingPageState();
}

class _AdminParentLinkingPageState extends State<AdminParentLinkingPage> {
  final AdminParentLinkProvider _requests = AdminParentLinkProvider();
  final AdminParentLinkProvider _settings = AdminParentLinkProvider();
  final ParentLinkSettingsHandle _handle = ParentLinkSettingsHandle();
  int _tab = 0;
  bool _settingsSeen = false;
  int _epoch = 0; // a new value rebuilds the form, dropping unsaved edits
  DateTime? _requestsAt;

  @override
  void initState() {
    super.initState();
    _requests.loadRequests();
    if (widget.openSettings) {
      _tab = 1;
      _settingsSeen = true;
    }
  }

  @override
  void dispose() {
    _requests.dispose();
    _settings.dispose();
    _handle.dispose();
    super.dispose();
  }

  Future<void> _select(int i) async {
    if (i == _tab) return;
    if (_tab == 1 && _handle.dirty) {
      final ok = await appConfirm(context,
          danger: true,
          confirmLabel: t('تجاهل التعديلات', 'Discard changes'),
          message: t('لديك تعديلات غير محفوظة في إعدادات الربط. تجاهلها والانتقال؟',
              'You have unsaved parent-link settings. Discard them and switch?'));
      if (!ok || !mounted) return;
      _epoch++;
    }
    setState(() {
      _tab = i;
      if (i == 1) _settingsSeen = true;
    });
  }

  Future<void> _reloadRequests() async {
    await _requests.loadRequests();
    if (mounted) setState(() => _requestsAt = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final hasSettings = isSuperNow(context);
    final tab = hasSettings ? _tab : 0;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = AppSpace.gutter(width);
    // on a phone the tab bar already costs a row: the subtitle would push the table off the screen
    final narrow = width < 600;
    return ListenableBuilder(
      listenable: Listenable.merge([_handle, _requests]),
      builder: (context, _) {
        final onSettings = tab == 1;
        // redesign A1 (AdmPeople links): the role's hero with the requests waiting, Requests / Settings on the hero
        final pending = _requests.pendingTotal;
        return SupPage(
          key: const ValueKey('admin_parent_linking'),
          role: admRole(context),
          width: AppWidth.wide,
          title: t('ربط أولياء الأمور', 'Parent linking'),
          kicker: 'admin_group_people'.tr,
          headline: onSettings
              ? t('قواعد ربط ولي الأمر بالطالب', 'The rules for linking a parent to a student')
              : (pending > 0 ? 'a1_links_waiting'.tr.replaceAll('{n}', '$pending') : 'pl_requests_title'.tr),
          line: narrow
              ? null
              : onSettings
                  ? t('تسري على الطلبات الجديدة فقط.', 'They apply to new requests only.')
                  : t('راجع المستندات، ووافق أو ارفض.', 'Review the documents, then approve or reject.'),
          // always a function: the frame re-creates its body when the refresh comes and goes (the settings form
          // would lose its state); a refresh that cannot run yet does nothing
          onRefresh: () async {
            if (onSettings) {
              if (!_handle.saving && _handle.ready) await _handle.reload?.call();
            } else if (!_requests.isLoading) {
              await _reloadRequests();
            }
          },
          updatedAt: onSettings ? _handle.loadedAt : _requestsAt,
          dirty: onSettings && _handle.dirty,
          actions: [
            if (onSettings && _handle.ready)
              AppButton.primary(
                  key: const ValueKey('admin_parent_linking.save'),
                  label: 'pl_save'.tr,
                  busy: _handle.saving,
                  onPressed: _handle.dirty ? () => _handle.save?.call() : null),
          ],
          tabs: hasSettings
              ? [
                  AppTabItem(t('الطلبات', 'Requests'), icon: Icons.inbox_rounded, count: pending > 0 ? pending : null),
                  AppTabItem(t('الإعدادات', 'Settings'), icon: Icons.settings_suggest_rounded),
                ]
              : null,
          tab: tab,
          onTab: _select,
          body: Padding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpace.sm, gutter, 0),
            child: IndexedStack(index: tab, children: [
              ChangeNotifierProvider<AdminParentLinkProvider>.value(value: _requests, child: const ParentRequestsBody()),
              if (hasSettings && _settingsSeen)
                ChangeNotifierProvider<AdminParentLinkProvider>.value(
                    value: _settings, child: ParentLinkSettingsForm(key: ValueKey('settings$_epoch'), handle: _handle))
              else
                const SizedBox.shrink(),
            ]),
          ),
        );
      },
    );
  }
}
