// lib/design/calendar_entry.dart — the way into the personal calendar ('/calendar': every source the user belongs
// to), the same for every role (Track C.1):
//
//   CalendarEntryIcon   the small tinted icon for a home header / app bar (HomeHeader.actions, ScreenAppBar.actions)
//   CalendarEntryTile   the "Calendar" row of a More / profile list (AppSettingsGroup / SettingsGroup children)
//   ChatEntryTile       the "Messages" row of the same lists, with the unread count (kill switch `chat`, D-374)
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

/// Alfaheem Messages (D-330): the same small button in every role's shell and home header, with its unread count.
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

/// The Messages row of every role's profile / More page, with the unread count of the attention feed (D-374).
class ChatEntryTile extends StatelessWidget implements AppSettingsSearchable {
  const ChatEntryTile({super.key});

  @override
  String get searchText => '${'chat_title'.tr} messages chat رسائل محادثة';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AttentionService.instance,
        builder: (context, _) => AppSettingsTile(
          featureKey: chatEntryFeatureKey,
          icon: Icons.forum_rounded,
          color: context.colors.primary,
          label: 'chat_title'.tr,
          subtitle: 'chat_tile_subtitle'.tr,
          keywords: 'messages chat inbox رسائل محادثات',
          badge: AttentionService.instance.count(AttentionTabs.chat),
          onTap: () => AppShellNav.navigatorFor(context).pushNamed('/chat'),
        ),
      );
}

class CalendarEntryTile extends StatelessWidget implements AppSettingsSearchable {
  const CalendarEntryTile({super.key});

  @override
  String get searchText => 'my_calendar'.tr;

  @override
  Widget build(BuildContext context) => AppSettingsTile(
        featureKey: calendarEntryFeatureKey,
        icon: Icons.event_rounded,
        // the primary, like the Messages row above it: gold is reserved for streaks and achievements (system.md §2)
        color: context.colors.primary,
        label: 'my_calendar'.tr,
        onTap: () => openMyCalendar(context),
      );
}
