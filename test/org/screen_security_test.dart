// ScreenSecurity (lib/core/screen_security.dart, D-083): the window is protected while at least one protected screen
// (course video, exam) owns it — one closing never switches another's protection off — and a whole-screen share
// clears only an OWNERLESS protection (the presenter's app must not be black in the share), never an open
// protected screen's; the share's end puts back what it changed.
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/screen_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sec = ScreenSecurity.instance;
  late List<String> calls;

  void on(TargetPlatform p) {
    sec.debugReset();
    calls = [];
    sec.debugTarget = p;
    sec.debugPlatform = (call, args) async => calls.add(args.isEmpty ? call : '$call $args');
  }

  tearDown(sec.debugReset);

  test('owners: the protection goes with the LAST owner, once', () async {
    on(TargetPlatform.android);
    final player = Object(), exam = Object();
    await sec.protect(player);
    await sec.protect(player); // idempotent
    await sec.protect(exam);
    expect(calls, ['protect']);
    await sec.release(player);
    expect(sec.isProtected, isTrue);
    expect(calls, ['protect'], reason: 'the exam still needs it');
    await sec.release(exam);
    await sec.release(exam);
    expect(calls, ['protect', 'unprotect']);
    expect(sec.isProtected, isFalse);
  });

  test('Android share: clears an ownerless FLAG_SECURE; never an open protected screen\'s', () async {
    on(TargetPlatform.android);
    await sec.beginShare();
    await sec.beginShare(); // idempotent
    expect(calls, ['shareBegin {clearSecure: true}']);
    expect(sec.sharing, isTrue);
    await sec.endShare();
    await sec.endShare();
    expect(calls, ['shareBegin {clearSecure: true}', 'shareEnd']);

    on(TargetPlatform.android);
    final player = Object();
    await sec.protect(player);
    await sec.beginShare();
    expect(calls.last, 'shareBegin {clearSecure: false}', reason: 'the course video stays protected');
  });

  test('iOS share: the screen_protector layer is lifted only when no protected screen is open, and restored', () async {
    on(TargetPlatform.iOS);
    await sec.beginShare();
    expect(calls, ['unprotect']);
    await sec.endShare();
    expect(calls, ['unprotect'], reason: 'nothing was protected before');

    on(TargetPlatform.iOS);
    final exam = Object();
    await sec.protect(exam);
    await sec.beginShare();
    expect(calls, ['protect'], reason: 'an exam paper never goes out in a broadcast');
    await sec.endShare();
    expect(calls, ['protect', 'protect']);
  });

  test('a protected screen opened DURING a share protects at once (protection wins)', () async {
    on(TargetPlatform.android);
    await sec.beginShare();
    final player = Object();
    await sec.protect(player);
    expect(calls.last, 'protect');
    await sec.release(player);
    expect(calls.last, 'unprotect');
    await sec.endShare();
    expect(calls.last, 'shareEnd');
  });
}
