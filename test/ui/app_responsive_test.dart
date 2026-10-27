// The one breakpoint system (D-061): which shell a width gets.
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shellFor: phone < 700, rail 700-999, wide >= 1000', () {
    expect(Breakpoints.mobile, 700);
    expect(Breakpoints.desktop, 1000);
    expect(Breakpoints.shellFor(320), AppShellKind.mobile);
    expect(Breakpoints.shellFor(699), AppShellKind.mobile);
    expect(Breakpoints.shellFor(700), AppShellKind.rail);
    expect(Breakpoints.shellFor(852), AppShellKind.rail, reason: 'a landscape phone gets the rail on every platform');
    expect(Breakpoints.shellFor(999), AppShellKind.rail);
    expect(Breakpoints.shellFor(1000), AppShellKind.wide);
    expect(Breakpoints.shellFor(1400), AppShellKind.wide);
  });

  test('content never stretches past contentMax', () {
    expect(Breakpoints.contentMax, lessThan(Breakpoints.desktop));
  });
}
