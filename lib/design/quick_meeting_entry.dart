// lib/design/quick_meeting_entry.dart
//
// QuickMeetingIcon — "Meet now" in a home header (HomeHeader.actions), next to the calendar and the bell: one tap
// opens an online, private meeting starting now and joins it (startQuickMeeting in
// lib/features/shared/calendar/calendar_meeting.dart, live-rooms-spec §7). In Organization mode the meeting
// belongs to the open organization. Hidden by the kill switch `live.quick_meeting` and for guests.
library;

import 'package:flutter/material.dart';

import '../config/theme/theme_config_provider.dart';
import '../core/app_mode.dart';
import '../features/admin/admin_common.dart' show t;
import '../features/shared/calendar/calendar_meeting.dart' show startQuickMeeting;
import '../utils/widget/parent_component.dart';

class QuickMeetingIcon extends StatefulWidget {
  const QuickMeetingIcon({super.key});

  @override
  State<QuickMeetingIcon> createState() => _QuickMeetingIconState();
}

class _QuickMeetingIconState extends State<QuickMeetingIcon> {
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final mode = AppModeController.instance;
      await startQuickMeeting(context, orgId: mode.isOrg ? mode.currentOrgId : null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = t('اجتماع مباشر الآن', 'Meet now');
    return ParentComponent(
      featureKey: 'live.quick_meeting',
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: _start,
            child: Container(
              padding: const EdgeInsets.all(7),
              margin: const EdgeInsets.all(5),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: c.danger),
              child: SizedBox.square(
                dimension: 20,
                child: _busy
                    ? Padding(padding: const EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2, color: c.onHero))
                    : Icon(Icons.video_call_rounded, color: c.onHero, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
