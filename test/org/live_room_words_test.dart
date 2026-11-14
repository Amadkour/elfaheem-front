// D-106: the live room's words follow its kind — a calendar meeting says «اجتماع» / "meeting", a course session
// keeps «الحصة» / "session" (lib/features/live/live_room_words.dart) — and no entry asks the pre-join page
// to join by itself any more.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/live/live_controls_api.dart';
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_education_app/features/live/live_room_words.dart';
import 'package:flutter_test/flutter_test.dart';

/// Arabic / English words of a course session, which a meeting text must never carry.
final _sessionWordsAr = RegExp('حص|جلس|درس|محاضر|المعلم|المعلّم|طالب|طلاب');
final _sessionWordsEn = RegExp(r'\b(session|sessions|class|lesson|teacher|student)s?\b', caseSensitive: false);

void main() {
  late Map<String, dynamic> file;

  setUpAll(() {
    file = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    translation = file;
  });

  setUp(() {
    AppConfig.lang = 'ar';
    LiveRoomWords.current = LiveRoomKind.session;
  });

  group('liveRoomNoun', () {
    test('Arabic: حصة / الحصة for a session, اجتماع / الاجتماع for a meeting', () {
      expect(liveRoomNoun(LiveRoomKind.session), 'حصة');
      expect(liveRoomNoun(LiveRoomKind.session, definite: true), 'الحصة');
      expect(liveRoomNoun(LiveRoomKind.meeting), 'اجتماع');
      expect(liveRoomNoun(LiveRoomKind.meeting, definite: true), 'الاجتماع');
    });

    test('English: session / meeting, capitalised on demand', () {
      AppConfig.lang = 'en';
      expect(liveRoomNoun(LiveRoomKind.session), 'session');
      expect(liveRoomNoun(LiveRoomKind.meeting), 'meeting');
      expect(liveRoomNoun(LiveRoomKind.meeting, capital: true), 'Meeting');
      expect(liveRoomNoun(LiveRoomKind.session, definite: true, capital: true), 'Session');
    });
  });

  group('liveTr', () {
    test('a meeting reads the _meeting key, a session the key itself (both languages)', () {
      expect(liveTr('lr_join_session', LiveRoomKind.meeting), 'انضم للاجتماع');
      expect(liveTr('lr_join_session', LiveRoomKind.session), 'انضم للحصة');
      expect(liveTr('lr_teacher_ended_title', LiveRoomKind.meeting), 'انتهى الاجتماع'); // masculine verb
      expect(liveTr('lr_teacher_ended_title', LiveRoomKind.session), 'انتهت الحصة');
      expect(liveTr('lr_live_session', LiveRoomKind.meeting), 'اجتماع مباشر');
      AppConfig.lang = 'en';
      expect(liveTr('lr_join_session', LiveRoomKind.meeting), 'Join meeting');
      expect(liveTr('lr_join_session', LiveRoomKind.session), 'Join Session');
      expect(liveTr('lr_may_be_recorded', LiveRoomKind.meeting), 'This meeting may be recorded');
    });

    test('a key without a meeting variant falls back to the key; an unknown key to itself', () {
      expect(liveTr('lr_microphone', LiveRoomKind.meeting), translate('lr_microphone'));
      expect(liveTr('no_such_key_xyz', LiveRoomKind.meeting), 'no_such_key_xyz');
    });

    test('without a kind: the open room (LiveRoomWords.current), entered and left by the room', () {
      expect(liveTr('lr_join_session'), 'انضم للحصة');
      LiveRoomWords.enter(LiveRoomKind.meeting);
      expect(liveTr('lr_join_session'), 'انضم للاجتماع');
      // A late dispose of an older session room does not undo the meeting that took over.
      LiveRoomWords.leave(LiveRoomKind.session);
      expect(LiveRoomWords.current, LiveRoomKind.meeting);
      LiveRoomWords.leave(LiveRoomKind.meeting);
      expect(LiveRoomWords.current, LiveRoomKind.session);
      expect(liveTr('lr_join_session'), 'انضم للحصة');
    });

    test('liveTrp fills the placeholders of the right variant', () {
      expect(liveTrp('lr_remove_guest_confirm', {'name': 'سارة'}, LiveRoomKind.meeting), startsWith('إزالة سارة من الاجتماع؟'));
      AppConfig.lang = 'en';
      expect(liveTrp('lr_remove_guest_confirm', {'name': 'Sara'}, LiveRoomKind.meeting), startsWith('Remove Sara from the meeting?'));
    });
  });

  test('every _meeting key: en + ar, a base key, and no session / class / teacher / student word', () {
    final keys = file.keys.where((k) => k.endsWith('_meeting')).toList();
    final ours = keys.where((k) => k.startsWith('lr_') || k.startsWith('guest_live_')).toList();
    expect(ours.length, greaterThanOrEqualTo(26));
    for (final k in ours) {
      final v = file[k] as Map<String, dynamic>;
      final en = '${v['en'] ?? ''}', ar = '${v['ar'] ?? ''}';
      expect(en.isNotEmpty && ar.isNotEmpty, isTrue, reason: '$k needs en + ar');
      expect(file.containsKey(k.substring(0, k.length - '_meeting'.length)), isTrue, reason: '$k has no base key');
      expect(_sessionWordsAr.hasMatch(ar), isFalse, reason: '$k (ar): $ar');
      expect(_sessionWordsEn.hasMatch(en), isFalse, reason: '$k (en): $en');
    }
  });

  test('liveT and liveRoleLabel', () {
    String pick(LiveRoomKind? k) => liveT(k, ar: 'ح', en: 's', meetingAr: 'ا', meetingEn: 'm');
    expect(pick(LiveRoomKind.session), 'ح');
    expect(pick(LiveRoomKind.meeting), 'ا');
    expect(pick(null), 'ح');
    LiveRoomWords.enter(LiveRoomKind.meeting);
    expect(pick(null), 'ا');
    expect(liveRoleLabel(host: true), 'المضيف');
    expect(liveRoleLabel(host: false), 'مشارك');
    expect(liveRoleLabel(host: true, kind: LiveRoomKind.session), translate('teacher'));
    expect(liveRoleLabel(host: false, kind: LiveRoomKind.session), translate('student'));
    AppConfig.lang = 'en';
    expect(liveRoleLabel(host: false, kind: LiveRoomKind.meeting), 'Participant');
    expect(pick(LiveRoomKind.meeting), 'm');
  });

  group('server codes by room kind', () {
    test('liveRoomCodeText: a meeting has ended / not started (masculine)', () {
      expect(liveRoomCodeText('live_ended', kind: LiveRoomKind.meeting), 'انتهى هذا الاجتماع.');
      expect(liveRoomCodeText('live_not_started', kind: LiveRoomKind.meeting), 'لم يبدأ الاجتماع بعد.');
      expect(liveRoomCodeText('live_ended', kind: LiveRoomKind.session), 'انتهت هذه الجلسة.');
      AppConfig.lang = 'en';
      expect(liveRoomCodeText('meeting_ended', kind: LiveRoomKind.meeting), 'This meeting has ended.');
    });

    test('liveJoinRefusalText / liveHostActionConfirm say meeting for a meeting', () {
      final removed = ApiException(statusCode: 403, message: 'x', code: 'participant_removed');
      expect(liveJoinRefusalText(removed, kind: LiveRoomKind.meeting), 'أخرجك المضيف من هذا الاجتماع.');
      expect(liveJoinRefusalText(removed, kind: LiveRoomKind.session), 'أخرجك المضيف من هذه الجلسة.');
      expect(liveHostActionConfirm(LiveHostAction.remove, 'سارة', kind: LiveRoomKind.meeting), contains('هذا الاجتماع'));
      AppConfig.lang = 'en';
      expect(liveHostActionConfirm(LiveHostAction.remove, 'Sara', kind: LiveRoomKind.meeting), contains('this meeting'));
    });

    test('guestLiveErrorText follows the link\'s room', () {
      final ended = ApiException(statusCode: 410, message: 'x', code: 'live_ended');
      expect(guestLiveErrorText(ended, kind: LiveRoomKind.meeting), 'انتهى الاجتماع.');
      expect(guestLiveErrorText(ended), translate('guest_live_err_ended'));
      AppConfig.lang = 'en';
      final full = ApiException(statusCode: 409, message: 'x', code: 'guest_limit_reached');
      expect(guestLiveErrorText(full, kind: LiveRoomKind.meeting), startsWith('The meeting is full'));
    });
  });

  test('no entry passes autoJoin to the pre-join page any more (D-106)', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;
        if (RegExp(r'\bautoJoin\s*:').hasMatch(l)) hits.add('${f.path}:${i + 1}: ${l.trim()}');
      }
    }
    // GuestLiveInfo keeps the server's `auto_join` (a DIRECT link: no lobby, no name step) — not a pre-join flag.
    hits.removeWhere((h) => h.contains('guest_live_api.dart') && h.contains("j['auto_join']"));
    expect(hits, isEmpty, reason: hits.join('\n'));
    final prejoin = File('lib/features/live/room/prejoin.dart').readAsStringSync();
    expect(prejoin.contains('_maybeAutoJoin'), isFalse);
    expect(prejoin.contains('widget.args.autoJoin'), isFalse);
  });
}
