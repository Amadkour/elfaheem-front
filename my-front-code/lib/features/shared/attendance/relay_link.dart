/// features/attendance/relay_link.dart
///
/// Transport-independent pieces of the relay link, shared by the Nearby Connections transport
/// (Android) and the Bluetooth LE transport (iPhone, and Android↔iPhone).
///
/// Transport choice (first that works on the phone wins; the app never depends on one):
///   1. Nearby Connections  — Android (BLE + Wi-Fi Direct, fastest)
///   2. Bluetooth LE GATT   — iPhone, and Android phones talking to iPhones
/// GPS and Wi-Fi are NOT transports (they need no phone-to-phone link): they are the optional
/// location evidence in attendance_location.dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Android phones also advertise / scan over plain BLE so iPhones can reach them. Set to false
/// if running both transports at once ever disturbs Nearby on a particular device.
const bool kAndroidAlsoUsesBle = true;

enum RelayFailure { bluetoothOff, noRelay, linkLost, timeout, unknown }

class RelayException implements Exception {
  const RelayException(this.kind, [this.detail]);
  final RelayFailure kind;
  final String? detail;
  @override
  String toString() => 'RelayException($kind, $detail)';
}

typedef RelayHandler = Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

/// An open connection to ONE nearby phone.
abstract class RelayLink {
  String get endpointId;

  /// Sends [msg] and waits for the single reply.
  Future<Map<String, dynamic>> request(Map<String, dynamic> msg,
      {Duration timeout = const Duration(seconds: 25)});

  Future<void> close();
}

/// Gathers links from every transport that is searching at the same time.
class RelayCollector {
  RelayCollector(this.want);
  final int want;
  final List<RelayLink> links = [];
  final List<RelayException> errors = [];
  final List<String> notes = [];
  final Completer<void> _enough = Completer<void>();

  bool get satisfied => links.length >= want;
  Future<void> get enough => _enough.future;

  /// false → the link was surplus and has been closed.
  bool add(RelayLink l) {
    if (satisfied) {
      l.close();
      return false;
    }
    links.add(l);
    if (satisfied && !_enough.isCompleted) _enough.complete();
    return true;
  }

  void cancel() {
    if (!_enough.isCompleted) _enough.complete();
  }
}

bool isReply(Map<String, dynamic> m) {
  final t = m['t'];
  return t == 'window' || t == 'result' || t == 'error' || (t == 'witness' && m.containsKey('sig'));
}

bool isRequest(Map<String, dynamic> m) {
  final t = m['t'];
  return t == 'hello' || t == 'submit' || (t == 'witness' && m.containsKey('att'));
}

Uint8List encodeMsg(Map<String, dynamic> m) => Uint8List.fromList(utf8.encode(jsonEncode(m)));

Map<String, dynamic>? decodeMsg(List<int> bytes) {
  try {
    final d = jsonDecode(utf8.decode(bytes));
    return d is Map ? Map<String, dynamic>.from(d) : null;
  } catch (_) {
    return null;
  }
}

/// Splits [data] into frames: 1 header byte (1 = more follows, 0 = last) + up to [size] bytes.
/// BLE characteristics carry far less than a signed request, so messages are chunked.
List<Uint8List> frameMessage(Uint8List data, {int size = 100}) {
  final out = <Uint8List>[];
  var i = 0;
  do {
    final end = (i + size < data.length) ? i + size : data.length;
    final last = end >= data.length;
    out.add(Uint8List.fromList([last ? 0 : 1, ...data.sublist(i, end)]));
    i = end;
  } while (i < data.length);
  return out;
}

/// Re-assembles frames per sender. Returns the full message when the last frame arrives.
class FrameAssembler {
  final Map<String, BytesBuilder> _buf = {};

  Uint8List? add(String sender, List<int> frame) {
    if (frame.isEmpty) return null;
    final b = _buf.putIfAbsent(sender, () => BytesBuilder(copy: false));
    b.add(frame.sublist(1));
    if (b.length > 64 * 1024) {
      _buf.remove(sender); // runaway sender: drop it
      return null;
    }
    if (frame[0] == 0) {
      _buf.remove(sender);
      return b.takeBytes();
    }
    return null;
  }

  void drop(String sender) => _buf.remove(sender);
}
