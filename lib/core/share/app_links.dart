// lib/core/share/app_links.dart — ONE link scheme for everything the app shares (D-307). Pure Dart, unit-tested
// (test/org/app_links_test.dart).
//
//   https://nextbrain.site/c/<courseId>?ref=<sharer>   a course (kept: the referral counter reads `ref`)
//   https://nextbrain.site/@<username>                 a public profile: a teacher (D-074)
//   https://nextbrain.site/live/<token>                a live room's guest link (no account)
//   https://nextbrain.site/s/<kind>/<id>               everything else: material · session · meeting · roadmap ·
//                                                      teacher (by id) · course (an alias of /c/)
//   https://nextbrain.site/s/page/<pageId>?<params>    a page of the route registry (D-170, core/routing/app_routes)
//
// Root form on purpose: nginx sends a person on to the web app under /app/ (D-270), the phone apps claim `/s/` with
// App Links / Universal Links (android/app/src/main/AndroidManifest.xml, web/.well-known/*), and a chat app's
// preview crawler gets the server's Open-Graph card (`/api/v1/share/og/s/{kind}/{id}`). main.dart's router turns a
// `/s/…` route into the share-link page (features/shared/share/share_link_page.dart), which opens the target for a
// signed-in person and shows a public preview + Sign in to everyone else.
library;

/// What a link points at.
enum AppLinkKind {
  course,
  teacher,
  material,
  session,
  meeting,
  roadmap,
  page;

  /// The `/s/<kind>/` segment.
  String get segment => name;

  static AppLinkKind? tryParse(String? s) {
    for (final k in values) {
      if (k.name == s) return k;
    }
    return null;
  }
}

class AppLink {
  const AppLink._(this.kind, {this.id, this.pageId, this.params = const {}, this.ref});

  /// A course (`/c/<id>`, with the sharer's id as `ref` for the share counter).
  const AppLink.course(int id, {int? ref}) : this._(AppLinkKind.course, id: id, ref: ref);
  const AppLink.teacher(int id) : this._(AppLinkKind.teacher, id: id);
  const AppLink.material(int id) : this._(AppLinkKind.material, id: id);
  const AppLink.session(int id) : this._(AppLinkKind.session, id: id);
  const AppLink.meeting(int id) : this._(AppLinkKind.meeting, id: id);
  const AppLink.roadmap(int courseId) : this._(AppLinkKind.roadmap, id: courseId);

  /// A page of the route registry by its stable id (`calendar`, `course` + {courseId: 12}, …).
  const AppLink.page(String pageId, [Map<String, String> params = const {}])
      : this._(AppLinkKind.page, pageId: pageId, params: params);

  /// The public site every link is built on (the web build may pass its own origin, see [url]).
  static const site = 'https://nextbrain.site';

  final AppLinkKind kind;
  final int? id;
  final String? pageId;
  final Map<String, String> params;
  final int? ref;

  /// The in-app route of the link (what Flutter's deep linking hands to `onGenerateRoute`).
  String get route {
    switch (kind) {
      case AppLinkKind.course:
        return '/c/$id${ref != null ? '?ref=$ref' : ''}';
      case AppLinkKind.page:
        final path = '/s/page/${Uri.encodeComponent(pageId ?? '')}';
        return params.isEmpty ? path : Uri(path: path, queryParameters: params).toString();
      default:
        return '/s/${kind.segment}/$id';
    }
  }

  /// The full link on [origin] (default [site]; the web app passes the site it is served from).
  String url([String origin = site]) {
    final o = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
    return '$o$route';
  }

  /// `/s/<kind>/<id>`, `/s/page/<id>?…`, `/c/<id>?ref=` (a route, a path under `/app/` or a full URL) → the link,
  /// else null. A profile link (`/@name`) is parsed by public_profile.dart's `profileLinkFrom`, not here.
  static AppLink? parse(String? location) {
    if (location == null || location.isEmpty) return null;
    final uri = Uri.tryParse(location.trim());
    if (uri == null) return null;
    var segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty && segs.first == 'app') segs = segs.sublist(1); // the web app's base path (D-270)
    if (segs.length == 2 && segs[0] == 'c') {
      final id = int.tryParse(segs[1]);
      return id != null && id > 0 ? AppLink.course(id, ref: int.tryParse(uri.queryParameters['ref'] ?? '')) : null;
    }
    if (segs.length != 3 || segs[0] != 's') return null;
    final kind = AppLinkKind.tryParse(segs[1]);
    if (kind == null) return null;
    if (kind == AppLinkKind.page) {
      final id = segs[2];
      if (!RegExp(r'^[a-z][a-z0-9_.]{0,63}$').hasMatch(id)) return null;
      return AppLink.page(id, Map.of(uri.queryParameters));
    }
    final id = int.tryParse(segs[2]);
    if (id == null || id <= 0) return null;
    return AppLink._(kind, id: id, ref: kind == AppLinkKind.course ? int.tryParse(uri.queryParameters['ref'] ?? '') : null);
  }

  @override
  bool operator ==(Object other) =>
      other is AppLink && other.route == route;

  @override
  int get hashCode => route.hashCode;

  @override
  String toString() => 'AppLink($route)';
}
