// companion_platform.dart — what differs by platform for the companion device (D-520): which device is "the phone", what
// to call this computer on the phone's prompt, and how the room's sound is silenced here while the phone is the speaker.
library;

export 'companion_platform_stub.dart' if (dart.library.js_interop) 'companion_platform_web.dart';
