// Every help page id wired in lib/ must exist in the help seed (invented ids) or AppRoutes (D-170).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/core/routing/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Help ids wired before the back end's help_seed has them: onboarding phase A, snapshot regenerated at merge.
const _pendingHelpIds = {'org.onboarding', 'org.onboarding.types'};

void main() {
  test('wired help page ids exist in help_seed or AppRoutes', () {
    final seed = (jsonDecode(File('test/fixtures/help_page_ids.json').readAsStringSync())['ids'] as List).cast<String>().toSet();
    final routes = {
      for (final h in AppRoutes.homes) h.id,
      AppRoutes.course.id,
      AppRoutes.calendar.id,
      AppRoutes.inbox.id,
      AppRoutes.notifications.id,
      AppRoutes.subscription.id,
      AppRoutes.editAccount.id,
      AppRoutes.changePassword.id,
      AppRoutes.downloads.id,
      AppRoutes.orgMember.id,
    };
    final re = RegExp(r"(?:helpPageId: |HelpInfoButton\(pageId: |HelpTourTarget\(pageId: )'([a-z0-9_./]+)'");
    final wired = <String, String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.replaceAll(Platform.pathSeparator, '/').contains('features/help/')) continue;
      for (final m in re.allMatches(f.readAsStringSync())) {
        wired[m.group(1)!] = f.path;
      }
    }
    expect(wired, isNotEmpty);
    for (final e in wired.entries) {
      expect(seed.contains(e.key) || routes.contains(e.key) || _pendingHelpIds.contains(e.key), isTrue, reason: '${e.key} (${e.value}) is neither in help_seed nor AppRoutes');
    }
  });

  test('home tab ids follow home.<role>/<tab>', () {
    for (final h in AppRoutes.homes) {
      expect(h.id.startsWith('home.'), isTrue);
    }
  });
}
