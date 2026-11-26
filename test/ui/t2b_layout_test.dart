// Redesign group T2b (teacher: schedule, account, complaints, messages) on a phone and a wide window, ar / en, text
// 1.3: the schedule hero, the hero pills and figures, the proposal card, the account hero, its shortcut cards and
// page, the complaints page's teacher hero, the messages hero.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart' show T2bProposalCard;
import 'package:flutter_education_app/features/calendar/schedule_page.dart' show T2bScheduleHero;
import 'package:flutter_education_app/features/messaging/chat/chat_page.dart' show T2bChatHero;
import 'package:flutter_education_app/features/messaging/chat/chat_store.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_model.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_widgets.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart' show T2Scope;
import 'package:flutter_education_app/features/profile/teacher/t2b_account.dart';
import 'package:flutter_education_app/features/profile/teacher/t2b_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'عبدالرحمن محمد إبراهيم عبدالعزيز السيد Abdelrahman Mohamed Ibrahim';

Widget _scroll(Widget child) => T2Scope(child: SingleChildScrollView(child: child));

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('schedule hero', (t) async {
    await expectNoLayoutErrors(t, () => _scroll(T2bScheduleHero(
          from: '22',
          to: '28 نوفمبر',
          kicker: 'الثلاثاء ٢٤ نوفمبر',
          line: '$_long شغّالة الحين.',
          live: 12,
          meetings: 4,
          exams: 2,
          invites: 1,
          calendar: true,
          onTab: (_) {},
          onNew: () {},
          onMeetNow: () {},
          onExport: () {},
        )));
  });

  testWidgets('hero pills and figures', (t) async {
    await expectNoLayoutErrors(t, () => _scroll(AppHeroSurface(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(children: [
              T2bHeroPills(index: 1, onChanged: (_) {}, items: [
                for (var i = 0; i < 6; i++) T2bPill('$_long $i', icon: Icons.groups_outlined, count: i * 40),
              ]),
              const SizedBox(height: AppSpace.md),
              const T2bHeroFigures(stats: [
                AppHeroStat(value: '1234567', label: _long),
                AppHeroStat(value: '4', label: 'اجتماعات'),
                AppHeroStat(value: '2', label: 'اختبارات'),
                AppHeroStat(value: '1', label: 'دعوة تنتظر ردّك'),
              ]),
              const SizedBox(height: AppSpace.md),
              T2bHeroButton(label: _long, icon: Icons.share_outlined, onTap: () {}),
            ]),
          ),
        )));
  });

  testWidgets('proposal card', (t) async {
    await expectNoLayoutErrors(
        t, () => _scroll(T2bProposalCard(name: _long, when: 'الأربعاء ٢٥ نوفمبر ٩:٠٠ م – ١٠:٠٠ م', onAccept: () {})));
  });

  testWidgets('account page', (t) async {
    await expectNoLayoutErrors(
      t,
      () => T2bAccountPage(
        hero: T2bAccountHero(
          name: _long,
          verified: true,
          chips: const [(Icons.shield_outlined, 'معلم موثّق', false), (null, _long, false), (null, '@a.very.long.username', true)],
          stats: const [
            AppHeroStat(value: '4', label: 'دورات'),
            AppHeroStat(value: '56', label: 'طالب'),
            AppHeroStat(value: '4.8', label: 'التقييم'),
          ],
          onEdit: () {},
          onShare: () {},
        ),
        shortcuts: [
          for (final (i, a) in AppAccent.values.take(4).indexed)
            T2bShortcut(id: '$i', accent: a, icon: Icons.fact_check_outlined, title: _long, meta: _long, badge: i == 0 ? '3 طلبات' : null, onTap: () {}),
        ],
        sections: [
          for (var i = 0; i < 3; i++)
            (2, AppSettingsGroup(title: _long, children: [AppSettingsTile(icon: Icons.person_outline, label: _long, onTap: () {})])),
        ],
        exits: T2bAccountExits(onLogout: () {}, onDelete: () {}),
      ),
      scaffold: false,
    );
  });

  testWidgets('complaints teacher hero', (t) async {
    final search = TextEditingController();
    addTearDown(search.dispose);
    await expectNoLayoutErrors(
      t,
      () => T2Scope(
        child: ComplaintsHubView(
          teacher: true,
          segment: HubSegment.mine,
          showToResolve: true,
          mine: const [],
          toResolve: const [],
          filter: HubFilter.all,
          query: '',
          now: DateTime.utc(2026, 11, 24),
          searchController: search,
          onSegment: (_) {},
          onFilter: (_) {},
          onNew: () {},
          onOpen: (_) {},
          onAction: (_, _) {},
          onRefresh: () async {},
          onClearFilters: () {},
        ),
      ),
    );
  });

  testWidgets('messages hero', (t) async {
    await expectNoLayoutErrors(t, () => _scroll(T2bChatHero(hub: ChatHub.instance, onNewChat: () {})));
  });
}
