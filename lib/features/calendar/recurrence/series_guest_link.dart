// lib/features/calendar/recurrence/series_guest_link.dart — the ONE guest link of a repeating meeting (D-1720).
//
// Every date of a series is its own meeting with its own room, so a meeting's share link changed on every repeat.
// The series has a link of its own: `<site>/live/<token>` is the same for every date, and the server sends whoever
// opens it to the date that is on now (or shows the next one).
//
//   SeriesLinkApi              GET | POST | PUT | DELETE /api/v1/me/calendar/series/{id}/guest-link — the share
//                              sheet's API (LiveRoomApi) pointed at the series, so `ShareLinkSheet` is reused as is
//   showSeriesGuestLinkSheet   the share sheet: copy, share, QR, speak / listen, cap, PIN, revoke
//   copySeriesGuestLink        one tap: the link (made on the first tap) to the clipboard
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/live/live_lobby_sheets.dart' show ShareLinkSheet;
import 'package:flutter_education_app/features/live/live_room.dart';

class SeriesLinkApi extends LiveRoomApi {
  SeriesLinkApi(this.seriesId, {super.api})
      : _client = api ?? ApiClient(),
        super(const LiveRoomRef.meeting(0));

  final int seriesId;
  final ApiClient _client;

  Map<String, dynamic> _asMap(dynamic r) => r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};

  @override
  Future<LiveLink?> link() async {
    try {
      final r = _asMap(await _client.get('/api/v1/me/calendar/series/$seriesId/guest-link'));
      if ('${r['url'] ?? r['token'] ?? ''}'.isEmpty) return null;
      return LiveLink.fromJson(r);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<LiveLink> createLink({required bool canPublish, int? maxGuests, String? pin}) async =>
      LiveLink.fromJson(_asMap(await _client.post('/api/v1/me/calendar/series/$seriesId/guest-link', body: {
        'can_publish': canPublish,
        'max_guests': maxGuests,
        if (pin != null && pin.isNotEmpty) 'pin': pin,
      })));

  @override
  Future<LiveLink> updateLink({bool? direct, bool? canPublish}) async =>
      LiveLink.fromJson(_asMap(await _client.put('/api/v1/me/calendar/series/$seriesId/guest-link', body: {
        'direct': ?direct,
        'can_publish': ?canPublish,
      })));

  @override
  Future<void> deleteLink() => _client.delete('/api/v1/me/calendar/series/$seriesId/guest-link');
}

/// The share sheet of the series' link ([title]: put next to the URL when sharing).
Future<void> showSeriesGuestLinkSheet(BuildContext context, {required int seriesId, String? title, SeriesLinkApi? api}) =>
    showAppSheet<void>(
        context, (_) => ShareLinkSheet(ref: const LiveRoomRef.meeting(0), title: title, api: api ?? SeriesLinkApi(seriesId)));

/// Copies the series' guest link, making it on the first tap ([known]: the link the list already holds). Returns
/// the link, or null when it could not be made (the person was told).
Future<LiveLink?> copySeriesGuestLink(int seriesId, {LiveLink? known, SeriesLinkApi? api}) async {
  final a = api ?? SeriesLinkApi(seriesId);
  try {
    final l = known ?? await a.link() ?? await a.createLink(canPublish: true);
    await Clipboard.setData(ClipboardData(text: l.url));
    showAppNotice('series_link_copied'.tr);
    return l;
  } catch (e) {
    showAppNotice(liveRoomErrorText(e), error: true);
    return null;
  }
}
