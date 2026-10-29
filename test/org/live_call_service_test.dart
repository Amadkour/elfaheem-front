// LiveCallService (widgets/live_call_service.dart): the Android "in a live session" foreground service's
// channel — start sends the notification texts in the app language and answers the native bool, stop is
// sent, the notification's Leave reaches the callback, and nothing is sent on other platforms.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_call_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.flutter_education_app/live_call');
  final calls = <MethodCall>[];
  var answer = true;

  setUp(() {
    AppConfig.lang = 'en';
    calls.clear();
    answer = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'stop' ? null : answer;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('Android: start sends the texts in the app language and answers the native bool', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await LiveCallService.start(), isTrue);
    expect(calls.single.method, 'start');
    final args = Map<String, Object?>.from(calls.single.arguments as Map);
    expect(args['title'], 'In a live session');
    expect(args['leave'], 'Leave');
    expect(args.keys.toSet(), {'title', 'text', 'leave', 'channelName'});

    AppConfig.lang = 'ar';
    answer = false; // no microphone permission / refused natively
    expect(await LiveCallService.start(), isFalse);
    expect((calls.last.arguments as Map)['title'], 'في جلسة مباشرة');
  });

  test('Android: stop is sent; a missing plugin is no error', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await LiveCallService.stop();
    expect(calls.single.method, 'stop');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    expect(await LiveCallService.start(), isFalse);
    await LiveCallService.stop();
  });

  test('Android: the notification\'s Leave reaches the callback', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var left = 0;
    LiveCallService.onLeaveRequested = () => left++;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('leaveRequested')),
      (_) {},
    );
    expect(left, 1);
    LiveCallService.onLeaveRequested = null;
  });

  test('other platforms: nothing is sent', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(LiveCallService.supported, isFalse);
    expect(await LiveCallService.start(), isFalse);
    await LiveCallService.stop();
    expect(await LiveCallService.isRunning(), isFalse);
    expect(calls, isEmpty);
  });
}
