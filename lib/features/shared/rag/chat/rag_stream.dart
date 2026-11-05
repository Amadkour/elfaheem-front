// The answer stream: `GET /api/v1/rag/queries/{id}/stream` (Server-Sent Events). The model's text arrives as it is
// written, so the chat shows it live instead of waiting for the poll.
//
//   event: delta  {"text":"Hel"}                      append
//   event: delta  {"text":"","replace":"<full text>"} a rewrite: the text so far is replaced
//   event: done   <the full query payload>            the final answer (citations, chunks, actions, …)
//   event: error  {"code":"query_failed|stream_timeout|query_not_found","message":"…"}
//   : ping                                            every 15 s (ignored by the parser)
//
// Polling stays the fallback ([RagStreamClient.follow] returns null): a server without the route (404 / 405 / 501),
// a stream that is not `text/event-stream`, a dropped connection, an `error` event, a stall. The parser is the live
// events client's ([SseParser]); like that stream this one is plain (no envelope) and carries the bearer token in a
// header, which package:http can send on every platform (a fetch body on the web).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/live_events_client.dart' show SseEvent, SseParser, streamHeaders;
import 'package:http/http.dart' as http;

/// What the stream said so far. Pure: feed it frames in order.
class RagStreamState {
  /// The answer text so far.
  String text = '';

  /// The `done` event's payload (the full query row), once it arrived.
  Map<String, dynamic>? finalPayload;

  /// The `error` event's code, once it arrived.
  String? errorCode;

  bool get finished => finalPayload != null || errorCode != null;

  /// Applies one frame; returns true when [text] changed.
  bool apply(SseEvent e) {
    if (finished) return false;
    switch (e.name) {
      case 'delta':
        final j = e.json;
        final replace = j['replace'];
        if (replace is String) {
          final changed = replace != text;
          text = replace;
          return changed;
        }
        final add = j['text'];
        if (add is String && add.isNotEmpty) {
          text += add;
          return true;
        }
        return false;
      case 'done':
        final j = e.json;
        finalPayload = j.isEmpty ? <String, dynamic>{} : j;
        return false;
      case 'error':
        final code = e.json['code'];
        errorCode = code is String && code.isNotEmpty ? code : 'query_failed';
        return false;
      default:
        return false; // ping / message / anything newer
    }
  }
}

/// Whether a response status means "no stream here, poll instead".
bool ragStreamUnsupported(int status) => status != 200;

/// Opens the answer stream of one query.
class RagStreamClient {
  RagStreamClient({http.Client Function()? clientFactory, Future<String?> Function()? token, String? baseUrl, this.stallAfter = const Duration(seconds: 45)})
      : _factory = clientFactory ?? http.Client.new,
        _token = token,
        _baseUrl = baseUrl;

  final http.Client Function() _factory;
  final Future<String?> Function()? _token;
  final String? _baseUrl;

  /// No byte (not even a ping, every 15 s) for this long: the stream is dead, poll.
  final Duration stallAfter;

  static String path(int id) => '/api/v1/rag/queries/$id/stream';

  Uri uri(int id) => Uri.parse('${_baseUrl ?? AppConfig.baseUrl}${path(id)}');

  /// Follows query [id]; [onText] gets the full text so far after every change. Returns the `done` payload, or null
  /// when the caller should poll instead (anything went wrong or the stream ended without a final answer).
  /// [timeout] bounds the whole wait.
  Future<Map<String, dynamic>?> follow(int id, {required void Function(String text) onText, Duration timeout = const Duration(minutes: 3)}) async {
    final client = _factory();
    final state = RagStreamState();
    final parser = SseParser();
    StreamSubscription<String>? sub;
    try {
      String? token;
      try {
        token = await (_token != null ? _token() : ApiClient().accessToken);
      } catch (_) {}
      final req = http.Request('GET', uri(id))..headers.addAll(streamHeaders(token: token));
      final res = await client.send(req).timeout(const Duration(seconds: 20));
      if (ragStreamUnsupported(res.statusCode)) return null;
      final type = res.headers['content-type'] ?? '';
      if (type.isNotEmpty && !type.contains('text/event-stream')) return null;
      final done = Completer<void>();
      Timer? stall;
      void arm() {
        stall?.cancel();
        stall = Timer(stallAfter, () {
          if (!done.isCompleted) done.complete();
        });
      }

      arm();
      sub = res.stream.transform(utf8.decoder).listen(
        (chunk) {
          arm();
          for (final e in parser.feed(chunk)) {
            if (state.apply(e)) onText(state.text);
            if (state.finished && !done.isCompleted) done.complete();
          }
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future.timeout(timeout, onTimeout: () {});
      stall?.cancel();
      return state.finalPayload;
    } catch (_) {
      return null;
    } finally {
      await sub?.cancel();
      client.close();
    }
  }
}
