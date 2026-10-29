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
import '../config/theme/theme_config_provider.dart';
import '../utils/widget/parent_component.dart';
import 'app_settings.dart';
import 'app_shell_nav.dart' show AppShellNav;

const calendarEntryFeatureKey = 'calendar.entry';

void openMyCalendar(BuildContext context) => AppShellNav.navigatorFor(context).pushNamed('/calendar');

class CalendarEntryIcon extends StatelessWidget {
  const CalendarEntryIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ParentComponent(
      featureKey: calendarEntryFeatureKey,
      child: Tooltip(
        message: 'my_calendar'.tr,
        child: Semantics(
          button: true,
          label: 'my_calendar'.tr,
          child: GestureDetector(
            onTap: () => openMyCalendar(context),
            child: Container(
              padding: const EdgeInsets.all(7),
              margin: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: context.colors.accent2,
              ),
              child: Icon(Icons.event_rounded, color: context.colors.onHero, size: 20),
            ),
          ),
        ),
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
