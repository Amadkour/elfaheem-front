// lib/design/calendar_entry.dart — the way into the personal calendar ('/calendar': every source the user belongs
// to), the same for every role (Track C.1):
//
//   CalendarEntryIcon   the small tinted icon for a home header / app bar (HomeHeader.actions, ScreenAppBar.actions)
//   CalendarEntryTile   the "Calendar" row of a More / profile list (SettingsGroup children)
//
// Both hide behind the kill switch `calendar.entry`. Layout test: test/ui/app_refresh_layout_test.dart.
library;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import '../features/shared/profile/components/setting_title.dart';
import '../utils/widget/parent_component.dart';

const calendarEntryFeatureKey = 'calendar.entry';

void openMyCalendar(BuildContext context) => Navigator.of(context).pushNamed('/calendar');

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
              child: const Icon(Icons.event_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class CalendarEntryTile extends StatelessWidget {
  const CalendarEntryTile({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ParentComponent(
      featureKey: calendarEntryFeatureKey,
      child: SettingsTile(
        icon: Icons.event_rounded,
        iconBg: c.tealTint,
        iconColor: c.accent2,
        label: 'my_calendar'.tr,
        onTap: () => openMyCalendar(context),
      ),
    );
  }
}
