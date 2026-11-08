// lib/design/calendar_entry.dart — the way into the personal calendar ('/calendar': every source the user belongs
// to), the same for every role (Track C.1):
//
//   CalendarEntryIcon   the small tinted icon for a home header / app bar (HomeHeader.actions, ScreenAppBar.actions)
//   CalendarEntryTile   the "Calendar" row of a More / profile list (AppSettingsGroup / SettingsGroup children)
//
// Both hide behind the kill switch `calendar.entry`. Layout test: test/ui/app_refresh_layout_test.dart.
library;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/attention/attention_service.dart';
import '../config/theme/theme_config_provider.dart';
import '../utils/widget/parent_component.dart';
import 'chrome_button.dart';
import 'app_settings.dart';
import 'app_shell_nav.dart' show AppShellNav;

const calendarEntryFeatureKey = 'calendar.entry';
const chatEntryFeatureKey = 'chat';

void openMyCalendar(BuildContext context) => AppShellNav.navigatorFor(context).pushNamed('/calendar');

/// NextBrain Messages (D-330): the same small button in every role's shell and home header, with its unread count.
class ChatEntryIcon extends StatelessWidget {
  const ChatEntryIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ParentComponent(
      featureKey: chatEntryFeatureKey,
      child: ListenableBuilder(
        listenable: AttentionService.instance,
        builder: (context, _) => ChromeIconButton(
          icon: Icons.forum_rounded,
          label: 'chat_title'.tr,
          badge: AttentionService.instance.count(AttentionTabs.chat),
          onTap: () => AppShellNav.navigatorFor(context).pushNamed('/chat'),
        ),
      ),
    );
  }
}

class CalendarEntryIcon extends StatelessWidget {
  const CalendarEntryIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ParentComponent(
      featureKey: calendarEntryFeatureKey,
      child: ChromeIconButton(
        icon: Icons.event_rounded,
        label: 'my_calendar'.tr,
        onTap: () => openMyCalendar(context),
      ),
    );
  }
}

class CalendarEntryTile extends StatelessWidget implements AppSettingsSearchable {
  const CalendarEntryTile({super.key});

  @override
  String get searchText => 'my_calendar'.tr;

  @override
  Widget build(BuildContext context) => AppSettingsTile(
        featureKey: calendarEntryFeatureKey,
        icon: Icons.event_rounded,
        color: context.colors.accent2,
        label: 'my_calendar'.tr,
        onTap: () => openMyCalendar(context),
      );
}
