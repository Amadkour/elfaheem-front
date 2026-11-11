// Layout smoke tests for the older shared widgets restyled in the Warm Editorial sweep (lib/utils/widget, the ads
// pieces): 320x640 and 1400x900, Arabic and English, textScaler 1.3, no overflow (test/ui/layout_harness.dart).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart' show AdCard;
import 'package:flutter_education_app/utils/widget/count_badge.dart';
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
import 'package:flutter_education_app/utils/widget/rating_widget.dart';
import 'package:flutter_education_app/utils/widget/refresh_button.dart';
import 'package:flutter_education_app/utils/widget/swipe_request_card.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'كلية الهندسة والعلوم التطبيقية وتكنولوجيا المعلومات — الفرع الرئيسي بالمنصورة الجديدة';

Widget _scroll(List<Widget> children) => ListView(padding: const EdgeInsets.all(16), children: children);

RateResponse _rate(int id, int value) => RateResponse(
      id: id,
      studentId: id,
      sourceId: 1,
      type: RateType.course,
      value: value,
      review: null,
      createdAt: DateTime(2026, 11, 1),
    );

final _summary = RatingSummary(
  ratings: [for (var i = 0; i < 40; i++) _rate(i, 1 + i % 5)],
  total: 40,
  average: 3.6,
);

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('AdCard: a text ad as a block, compact thumbnails', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        SizedBox(height: 190, child: AdCard(ad: const {'id': 7, 'title': _long, 'body': _long, 'target_type': 'url'}, onTap: () {}, onReact: (_) {})),
        SizedBox(height: 190, child: AdCard(ad: const {'id': 8, 'title': 'Sale', 'media_type': 'link', 'target_type': 'none', 'likes': 3}, onReact: (_) {})),
        const Row(children: [
          SizedBox(width: 96, height: 54, child: AdCard(ad: {'id': 1, 'title': _long}, compact: true)),
          SizedBox(width: 96, height: 54, child: AdCard(ad: {'id': 2, 'title': 'v', 'media_type': 'video'}, compact: true)),
        ]),
      ]),
    );
  });

  testWidgets('RatingWidget: full card with a pick and the review well, compact row', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        RatingWidget(type: RateType.course, sourceId: '1', canEdit: true, compact: false, rateSummary: _summary),
        RatingWidget(type: RateType.course, sourceId: '2', canEdit: false, compact: false, rateSummary: _summary),
        Row(children: [Flexible(child: RatingWidget(type: RateType.course, sourceId: '3', canEdit: true, rateSummary: _summary))]),
      ]),
      act: (tester) async {
        final star = find.byIcon(Icons.star_outline_rounded);
        if (star.evaluate().isNotEmpty) {
          await tester.tap(star.last, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 400));
        }
      },
    );
  });

  testWidgets('Request queue pieces: card shell, hint, info rows, actions, state view', (tester) async {
    final ctl = SwipeCardController(busy: false, approve: () async {}, reject: () async {});
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        const SwipeHintBanner(count: 12),
        RequestCardShell(
          child: Column(children: [
            const Row(children: [RequestAvatar(name: _long), SizedBox(width: 12), Expanded(child: Text(_long))]),
            const RequestInfoRow(icon: Icons.payments_rounded, label: _long, value: _long, copyable: true),
            RequestActionButtons(ctl: ctl, approveLabel: _long, rejectLabel: _long),
          ]),
        ),
        SizedBox(height: 420, child: RequestStateView(icon: Icons.inbox_rounded, message: _long, actionLabel: _long, onAction: () {})),
      ]),
    );
  });

  testWidgets('Paging strip, footer, refresh pill and the tile count overlay', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _scroll([
        const PagedCountCard(loaded: 40, total: 13400, loadingMore: true, done: false),
        const PagedCountCard(loaded: 134, total: 134, loadingMore: false, done: true),
        const PagedListFooter(loadingMore: true, hasMore: true),
        const PagedListFooter(loadingMore: false, hasMore: false),
        Align(alignment: AlignmentDirectional.centerStart, child: RefreshButton(onTap: () async {})),
        const TileCountOverlay(count: 120, child: ListTile(title: Text(_long))),
      ]),
    );
  });
}
