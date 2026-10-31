// An export share link (`/e/<token>`) opened while signed out is kept through the login and opened once by the
// first signed-in screen (main.dart's `_Guard` calls ExportLinkPending.consume).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/export/export_studio_api.dart' show exportLinkTokenFromRoute;
import 'package:flutter_education_app/features/shared/exports/export_link_open_page.dart' show ExportLinkPending;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a link kept while signed out opens once after sign-in', (tester) async {
    final opened = <String>[];
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      onGenerateRoute: (s) {
        opened.add(s.name ?? '');
        return MaterialPageRoute(settings: s, builder: (_) => const SizedBox());
      },
    ));
    opened.clear();
    const token = 'abcDEF123_-xyz';
    ExportLinkPending.set(token);
    expect(ExportLinkPending.token, token);
    expect(ExportLinkPending.consume(key.currentState!), isTrue);
    await tester.pumpAndSettle();
    expect(opened, ['/e/$token']);
    expect(exportLinkTokenFromRoute(opened.single), token);
    // once only
    expect(ExportLinkPending.token, isNull);
    expect(ExportLinkPending.consume(key.currentState!), isFalse);
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
  });
}
