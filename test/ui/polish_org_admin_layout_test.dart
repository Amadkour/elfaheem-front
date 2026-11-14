// Layout smoke tests for the org / admin / ads pieces touched by the screen-by-screen polish (Track A2, area 3):
// 320x640 and 1400x900, Arabic and English, textScaler 1.3, no overflow (test/ui/layout_harness.dart).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_education_app/features/admin/admin_common.dart';
import 'package:flutter_education_app/features/admin/admin_list.dart';
import 'package:flutter_education_app/features/admin/admin_premium_widgets.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart' show AdCard;
import 'package:flutter_education_app/features/org/org_common.dart' show OrgHero;
import 'package:flutter_education_app/features/org/org_announcements.dart' show AnnouncementCard;
import 'package:flutter_education_app/features/org/org_people_page.dart' show OrgMemberRowView;
import 'package:flutter_education_app/features/org/org_services_pages.dart' show ComplaintBubble;
import 'package:flutter_education_app/features/org/org_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'كلية الهندسة والعلوم التطبيقية وتكنولوجيا المعلومات — الفرع الرئيسي بالمنصورة الجديدة';

Widget _scroll(List<Widget> children) => ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: children);

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('OrgMemberRowView: active with many chips, pending with approve / reject, ended', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(builder: (context) {
        return _scroll([
          OrgMemberRowView(
            name: _long,
            email: 'a.very.long.address.for.a.member@faculty-of-engineering.example.edu.eg',
            chips: [
              StatusChip(t('طالب', 'Student'), Colors.indigo),
              for (var i = 0; i < 6; i++) InfoChip(Icons.apartment_rounded, '$_long $i', Colors.grey),
            ],
            period: t('عضو منذ 1 سبتمبر 2026 · تنتهي 30 يونيو 2027', 'Member since 1 Sep 2026 · ends 30 Jun 2027'),
            trailing: [PopupMenuButton<String>(itemBuilder: (_) => const [])],
          ),
          OrgMemberRowView(
            name: 'Sara',
            email: 's@x.io',
            chips: [StatusChip(t('مدرس', 'Teacher'), Colors.indigo)],
            trailing: [
              IconButton(tooltip: t('موافقة', 'Approve'), onPressed: () {}, icon: const Icon(Icons.check_circle_rounded)),
              IconButton(tooltip: t('رفض', 'Reject'), onPressed: () {}, icon: const Icon(Icons.cancel_rounded)),
            ],
          ),
          OrgMemberRowView(name: _long, email: '', period: _long, periodEnded: true),
        ]);
      }),
    );
  });

  testWidgets('OrgHero and PremiumHero with a long name and footer pills', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        const OrgHero(org: {'name': _long, 'type': 'university'}, subtitle: _long),
        OrgHero(
          org: const {'name': 'NB', 'type': 'school', 'color': '#0F7B5F'},
          trailing: IconButton(tooltip: 'x', onPressed: () {}, icon: const Icon(Icons.swap_horiz_rounded)),
        ),
        PremiumHero(
          icon: Icons.payments_rounded,
          colors: AdminPalette.green,
          title: _long,
          subtitle: _long,
          footer: Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < 5; i++) HeroPill('$_long $i', icon: Icons.bolt_rounded),
          ]),
        ),
      ]),
    );
  });

  testWidgets('AdCard: plain, with reactions and a target, video', (tester) async {
    Widget card(Map<String, dynamic> ad, {bool react = false}) =>
        SizedBox(height: 190, child: AdCard(ad: ad, onTap: () {}, onReact: react ? (_) {} : null));
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        card({'title': _long, 'body': _long}),
        card({'title': 'Sale', 'body': '', 'target_type': 'course', 'likes': 120, 'dislikes': 4, 'my_reaction': 1}, react: true),
        card({'title': _long, 'media_type': 'video', 'media_url': '', 'target_type': 'none'}, react: true),
      ]),
    );
  });

  testWidgets('loading, failed and empty states: skeleton, OrgAsync, ErrorRetry, OrgEmpty', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        const SizedBox(height: 200, child: AppListSkeleton(items: 3, withAvatar: false)),
        const AppListSkeleton(items: 2),
        OrgAsync(loading: true, failed: false, onRetry: () {}, child: const SizedBox()),
        OrgAsync(loading: false, failed: true, onRetry: () {}, child: const SizedBox()),
        SizedBox(height: 320, child: ErrorRetry(message: _long, onRetry: () {})),
        const OrgEmpty(icon: Icons.inbox_rounded, title: _long, message: _long),
      ]),
    );
  });

  testWidgets('SheetHeader with a long title and PremiumSaveBar', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Column(children: [
        const SheetHeader(_long),
        const Spacer(),
        PremiumSaveBar(label: _long, onPressed: () {}),
      ]),
    );
  });

  testWidgets('shared org kit: section title, stat grid, action cards, pills, info rows', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        OrgSectionTitle(_long, subtitle: _long, action: TextButton(onPressed: () {}, child: Text(t('الكل', 'See all')))),
        OrgGrid(children: [
          for (var i = 0; i < 4; i++) OrgStatTile(icon: Icons.people_rounded, label: _long, value: '${1234567 * (i + 1)}', onTap: () {}),
        ]),
        OrgActionCard(icon: Icons.apartment_rounded, title: _long, subtitle: _long, badge: 120, onTap: () {}),
        OrgActionCard(icon: Icons.inbox_rounded, title: _long, trailing: const OrgPill(_long, icon: Icons.bolt_rounded)),
        Wrap(spacing: 6, runSpacing: 6, children: [for (var i = 0; i < 4; i++) OrgPill('$_long $i', icon: Icons.tag_rounded)]),
        const OrgInfoRow(Icons.mail_rounded, 'someone.with.a.really.long.address@faculty.example.edu.eg', ltr: true),
        const OrgInfoRow(Icons.place_rounded, _long),
      ]),
    );
  });

  testWidgets('shared admin kit: Section, KeyValue, EmptyState, FilterChips, SearchBox, Field, RowCard', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        Section(title: _long, icon: Icons.tune_rounded, trailing: TextButton(onPressed: () {}, child: const Text('Edit')),
            child: const Column(children: [KeyValue(_long, _long), KeyValue('ID', '#1234567890')])),
        const EmptyState(_long),
        FilterChips<String>(value: 'a', options: {for (var i = 0; i < 6; i++) 'k$i': '$_long $i', 'a': 'A'}, onChanged: (_) {}),
        SearchBox(hint: _long, onChanged: (_) {}),
        Field(controller: TextEditingController(text: _long), label: _long),
        RowCard(
          accent: Colors.orange,
          onTap: () {},
          child: Row(children: [
            const IconBadge(Icons.receipt_long_rounded, Colors.teal),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (var i = 0; i < 4; i++) InfoChip(Icons.schedule_rounded, '$_long $i', Colors.grey),
                StatusChip(_long, Colors.red),
              ]),
            ),
          ]),
        ),
      ]),
    );
  });

  testWidgets('premium admin cards: PremiumCard, select tiles, switch rows', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        PremiumCard(icon: Icons.lock_rounded, colors: AdminPalette.indigo, title: _long, hint: _long, children: [
          PremiumSelectTile(selected: true, color: Colors.indigo, onTap: () {}, title: _long, subtitle: _long,
              leading: const ServiceIcon(icon: Icons.mail_rounded, colors: [Colors.indigo, Colors.blue]),
              trailing: const Icon(Icons.check_circle_rounded)),
          PremiumSelectTile(selected: false, color: Colors.teal, onTap: () {}, title: 'Google'),
          PremiumSwitchRow(title: _long, subtitle: _long, icon: Icons.security_rounded, value: true, onChanged: (_) {}),
          PremiumSwitchRow(title: 'MFA', value: false, onChanged: (_) {}),
        ]),
      ]),
    );
  });

  testWidgets('complaint thread bubbles: staff name, internal note, attachments; both sides', (tester) async {
    Map<String, dynamic> msg(bool staff, {bool internal = false}) => {
          'from_staff': staff,
          'is_internal': internal,
          'sender': {'name': _long},
          'body': '$_long $_long',
          'attachments': [
            {'name': 'a-very-long-attachment-file-name-for-the-complaint-scan-2026-10-28.pdf', 'url': 'x'},
          ],
          'created_at': '2026-10-28T10:00:00Z',
        };
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        ComplaintBubble(m: msg(true), staffView: true),
        ComplaintBubble(m: msg(true, internal: true), staffView: true),
        ComplaintBubble(m: msg(false), staffView: true),
        ComplaintBubble(m: msg(true), staffView: false),
        ComplaintBubble(m: {'from_staff': false, 'sender': <String, dynamic>{}, 'body': 'ok'}, staffView: false),
      ]),
    );
  });

  testWidgets('AnnouncementCard: full and compact with long text and counts', (tester) async {
    final a = {
      'id': 1,
      'title': _long,
      'body': '$_long · $_long',
      'publish_at': '2026-10-27T08:00:00Z',
      'likes': 12345,
      'dislikes': 67,
      'comments': 890,
      'priority': 'high',
      'pinned': true,
      'me': {'viewed': true, 'clicked': true, 'reaction': 'like'},
    };
    await expectNoLayoutErrors(
      tester,
      () => _scroll([AnnouncementCard(item: a), AnnouncementCard(item: a, compact: true)]),
    );
  });
}
