// lib/features/ads/ads_pages.dart
//
//   HomeAdsSlider    top of the student / teacher home: auto-playing, image / video / link, tap → URL / course / page
//   AdminAdsPage     super admin: all ads, create / edit, approve or reject teacher ads (paid?), teacher-ads settings
//   TeacherAdsPage   teachers (when the platform allows it): own ads for their students, cost = days × price
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/downloads_availability.dart' show linkAvailableHere;
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/features/courses/student/details/course_detail_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../admin/admin_common.dart';
import '../admin/admin_labels.dart' show disposeAfterRoute;
import '../admin/admin_page.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import '../org/org_providers.dart';
import '../org/org_ui.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Home slider
// ═════════════════════════════════════════════════════════════════════════════

/// App pages an ad can open (named routes).
Map<String, String> adPages() => {
      '/subscription': t('الاشتراكات والباقات', 'Subscription plans'),
      '/notifications': t('الإشعارات', 'Notifications'),
      '/downloads': t('التنزيلات (التطبيق فقط)', 'Downloads (app only)'), // no Downloads page on the web
      '/profile': t('حسابي', 'My account'),
      '/home': t('الرئيسية', 'Home'),
    };

/// Home "featured" slider — sits after the greeting / search / next class, before the organization block:
/// personal content first, ads second. Auto-plays, pauses while the finger is on it, a like / dislike per ad.
///
/// Editorial (D-613): a picture ad is the picture under a reading scrim, a text ad is a tinted block (peach / sky,
/// stable per ad) with its title in the editorial headline. The page marks sit under the banner on the canvas, so
/// they read on every ad. The slider arrives once (it loads after the home), and the picture drifts a few pixels
/// against the swipe (parallax).
class HomeAdsSlider extends StatefulWidget {
  const HomeAdsSlider({super.key, this.padding = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.sm)});
  final EdgeInsetsGeometry padding;

  @override
  State<HomeAdsSlider> createState() => _HomeAdsSliderState();
}

class _HomeAdsSliderState extends State<HomeAdsSlider> {
  List<Map<String, dynamic>> _ads = const [];
  final _pc = PageController();
  Timer? _timer;
  int _page = 0;
  bool _hold = false;

  /// How long one page turn of the auto-play takes.
  static const _turn = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // The feed is per account (audience, impressions): a signed-out guest has none, and asking would only
    // answer 401 (QA: guest home).
    if (!ApiClient().hasSession) return;
    try {
      final r = await ApiClient().get('/api/v1/ads/feed');
      if (!mounted || r is! Map) return;
      setState(() => _ads = asMapList(r['items']));
      _timer?.cancel();
      if (_ads.length > 1) {
        _timer = Timer.periodic(const Duration(seconds: 6), (_) {
          if (_hold || !_pc.hasClients || !mounted) return;
          final next = (_page + 1) % _ads.length;
          // Reduce motion: the page changes in place instead of sliding.
          if (appMotionOff(context)) {
            _pc.jumpToPage(next);
          } else {
            _pc.animateToPage(next, duration: _turn, curve: AppEase.out);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _react(int i, int value) async {
    final ad = _ads[i];
    final next = ad['my_reaction'] == value ? 0 : value;          // tap again = undo
    try {
      final r = await ApiClient().post('/api/v1/ads/${ad['id']}/react', body: {'value': next});
      if (r is Map && mounted) setState(() => _ads[i] = {...ad, ...Map<String, dynamic>.from(r)});
    } catch (_) {}
  }

  Future<void> _open(Map<String, dynamic> ad) async {
    Map<String, dynamic> target = {'target_type': ad['target_type'], 'target_value': ad['target_value']};
    try {
      final r = await ApiClient().post('/api/v1/ads/${ad['id']}/click');
      if (r is Map) target = Map<String, dynamic>.from(r);
    } catch (_) {}
    if (!mounted) return;
    final type = '${target['target_type']}', value = '${target['target_value'] ?? ''}';
    if (type == 'url' && value.isNotEmpty) {
      await launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
    } else if (type == 'course' && int.tryParse(value) != null) {
      try {
        final r = await ApiClient().get('/api/v1/courses/$value');
        if (r is Map && mounted) {
          final course = CourseModel.fromJson(Map<String, dynamic>.from(r));
          Navigator.of(context).push(MaterialPageRoute(settings: RouteSettings(name: '/course-detail', arguments: course), builder: (_) => CourseDetailScreen(course: course)));
        }
      } catch (_) {
        toast(t('تعذّر فتح الكورس', 'Could not open the course'), error: true);
      }
    } else if (type == 'page' && value.startsWith('/')) {
      // an ad pointing to Downloads is for the app: on the web it opens nothing
      if (linkAvailableHere(value)) Navigator.of(context).pushNamed(value);
    } else if (ad['media_type'] == 'video' && '${ad['media_url'] ?? ''}'.isNotEmpty) {
      await launchUrl(Uri.parse(orgFileUrl('${ad['media_url']}')), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ads.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: AppWidthBox(
        width: AppWidth.content,
        gutters: false,
        child: AppReveal(
          index: 0,
          group: 'home-ads',
          child: LayoutBuilder(builder: (context, box) {
            final ratio = box.maxWidth > 700 ? 16 / 5.6 : 16 / 8.5;      // calmer, wider banner on tablets / web
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Listener(
                onPointerDown: (_) => _hold = true,
                onPointerUp: (_) => _hold = false,
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: _ads.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => AdCard(ad: _ads[i], onTap: () => _open(_ads[i]), onReact: (v) => _react(i, v)),
                  ),
                ),
              ),
              if (_ads.length > 1) ...[
                AppSpace.gapXs,
                _AdPageMarks(count: _ads.length, page: _page),
              ],
            ]);
          }),
        ),
      ),
    );
  }
}

/// The page marks under the slider: the open ad a short emerald bar, the others quiet dots on the canvas.
class _AdPageMarks extends StatelessWidget {
  const _AdPageMarks({required this.count, required this.page});
  final int count, page;

  /// The mark's thickness, a dot's width and the open bar's width.
  static const double _dot = 6, _bar = 18;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return ExcludeSemantics(
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: motion.base,
            curve: AppEase.out,
            margin: const EdgeInsets.symmetric(horizontal: AppSpace.xxs / 2),
            width: i == page ? _bar : _dot,
            height: _dot,
            decoration: BoxDecoration(
              color: i == page ? c.primary : c.textLight.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
      ]),
    );
  }
}

/// One ad. A picture ad: the picture full bleed under a reading scrim, the title and text in on-hero ink. A text,
/// link or video ad without a picture: a tinted block (peach / sky, the same for the same ad everywhere) with the
/// title in the editorial headline. Like / dislike and the discreet "Ad" tag sit on top as small plates; [compact]
/// (a list thumbnail) keeps only the picture or the block and the kind's mark.
class AdCard extends StatelessWidget {
  const AdCard({super.key, required this.ad, this.onTap, this.onReact, this.compact = false});
  final Map<String, dynamic> ad;
  final VoidCallback? onTap;
  final ValueChanged<int>? onReact;
  final bool compact;

  /// Wider than this the ad is a banner on a tablet or the web: a display title and the large kind mark.
  static const double _wideAd = 700;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = '${ad['media_url'] ?? ''}';
    final isVideo = ad['media_type'] == 'video';
    final showImage = media.isNotEmpty && ad['media_type'] == 'image';
    final hasTarget = '${ad['target_type'] ?? 'none'}' != 'none' || isVideo;
    final mine = asInt(ad['my_reaction']);
    final block = AppBlockColors.of(context, AppBlockTone.forKey('ad-${ad['id'] ?? ad['title']}'));
    // The inks of this card: on-hero over a picture, the block's inks on a tint.
    final ink = showImage ? c.onHero : block.ink;
    final muted = showImage ? c.onHeroMuted : block.muted;
    final radius = BorderRadius.circular(compact ? AppRadius.chip : AppRadius.block);

    // A small plate on the card: dark glass over a picture, paper over a tint.
    Widget plate(Widget child) => DecoratedBox(
          decoration: BoxDecoration(
            color: showImage ? c.heroShade.withValues(alpha: 0.32) : c.cardBg.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: showImage ? c.onHero.withValues(alpha: 0.2) : c.divider, width: AppBorder.hairline),
          ),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs + AppSpace.xxs / 2, vertical: AppSpace.xxs), child: child),
        );
    // Like / dislike: the plate is small, its target is the full 48 px.
    Widget react(IconData on, IconData off, int v, int n, String label) => Semantics(
          button: true,
          selected: mine == v,
          label: label,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onReact == null ? null : () => onReact!(v),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              child: Center(
                widthFactor: 1,
                child: plate(Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(mine == v ? on : off, size: AppIconSize.sm, color: ink),
                  if (n > 0) ...[
                    const SizedBox(width: AppSpace.xxs),
                    Text('$n', style: AppType.meta(context).copyWith(color: ink, fontFeatures: const [FontFeature.tabularFigures()])),
                  ],
                ])),
              ),
            ),
          ),
        );

    final Widget surface = showImage
        ? AppParallaxImage(
            axis: Axis.horizontal,
            image: Image.network(orgFileUrl(media), fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: block.surface)),
          )
        : ColoredBox(color: block.surface);

    final kindIcon = isVideo
        ? Icons.play_arrow_rounded
        : ad['media_type'] == 'link'
            ? Icons.link_rounded
            : Icons.campaign_rounded;

    List<Widget> layers(bool wide) => <Widget>[
      surface,
      // The reading scrim: only under the text at the bottom of a picture, never a wash over the whole ad.
      if (showImage && !compact)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.heroShade.withValues(alpha: 0.18), c.heroShade.withValues(alpha: 0), c.heroShade.withValues(alpha: 0.78)],
              stops: const [0, 0.32, 1],
            ),
          ),
        ),
      if (compact && !showImage)
        Center(child: Icon(kindIcon, size: AppIconSize.lg, color: block.muted))
      else if (isVideo && (compact || showImage))
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: showImage ? c.heroShade.withValues(alpha: 0.35) : c.cardBg,
              shape: BoxShape.circle,
              border: Border.all(color: showImage ? c.onHero.withValues(alpha: 0.6) : c.divider, width: AppBorder.strong),
            ),
            child: Padding(
              padding: EdgeInsets.all(compact ? AppSpace.xxs : AppSpace.sm),
              child: Icon(Icons.play_arrow_rounded, color: ink, size: compact ? AppIconSize.md : AppIconSize.xl),
            ),
          ),
        ),
      // A wide text ad: its kind's mark drawn large and quiet at the end, so the block reads as a poster, not an
      // empty box (phones keep the room for the title).
      if (wide && !compact && !showImage)
        PositionedDirectional(
          end: AppSpace.xxl,
          top: 0,
          bottom: 0,
          child: Center(child: Icon(kindIcon, size: AppIconSize.hero * 3, color: block.muted.withValues(alpha: 0.16))),
        ),
      if (!compact) ...[
        if (onReact != null)
          PositionedDirectional(
            top: AppSpace.xxs,
            start: AppSpace.xxs,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              react(Icons.thumb_up_alt_rounded, Icons.thumb_up_alt_outlined, 1, asInt(ad['likes']), t('أعجبني', 'Like')),
              react(Icons.thumb_down_alt_rounded, Icons.thumb_down_alt_outlined, -1, asInt(ad['dislikes']), t('لم يعجبني', 'Dislike')),
            ]),
          ),
        PositionedDirectional(
          top: AppSpace.sm,
          end: AppSpace.sm,
          child: plate(Text(t('إعلان', 'Ad'), style: AppType.meta(context).copyWith(color: muted))),
        ),
        PositionedDirectional(
          start: AppSpace.lg,
          end: AppSpace.lg,
          bottom: AppSpace.md,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${ad['title']}',
                maxLines: showImage ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: (showImage ? AppType.section(context) : wide ? AppType.display(context) : AppType.headline(context)).copyWith(color: ink, height: 1.1)),
            if ('${ad['body'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text('${ad['body']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: muted)),
            ],
            if (hasTarget) ...[
              AppSpace.gapXs,
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(isVideo && '${ad['target_type']}' == 'none' ? t('شاهد الآن', 'Watch now') : t('اكتشف', 'Discover'),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(color: showImage ? ink : block.accentInk(c.primary), fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: AppSpace.xxs),
                Icon(isVideo ? Icons.play_circle_rounded : Icons.arrow_forward_rounded, size: AppIconSize.sm, color: showImage ? ink : block.accentInk(c.primary)),
              ]),
            ],
          ]),
        ),
      ],
    ];

    return Material(
      color: block.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: showImage || block.border == null ? BorderSide.none : BorderSide(color: block.border!, width: AppBorder.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(builder: (context, box) => Stack(fit: StackFit.expand, children: layers(box.maxWidth > _wideAd))),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Editor (platform & teachers)
// ═════════════════════════════════════════════════════════════════════════════

Future<bool> showAdEditor(BuildContext context, {required String base, Map<String, dynamic>? edit, bool teacher = false}) async {
  final title = TextEditingController(text: '${edit?['title'] ?? ''}');
  final body = TextEditingController(text: '${edit?['body'] ?? ''}');
  final media = TextEditingController(text: '${edit?['media_url'] ?? ''}');
  final target = TextEditingController(text: '${edit?['target_value'] ?? ''}');
  String mediaType = '${edit?['media_type'] ?? 'image'}', targetType = '${edit?['target_type'] ?? 'none'}';
  final roles = {...((asMap(edit?['audience'])['roles'] as List?) ?? const []).map((e) => '$e')};
  DateTime? start = DateTime.tryParse('${edit?['starts_at'] ?? ''}'), end = DateTime.tryParse('${edit?['ends_at'] ?? ''}');
  bool active = edit?['is_active'] != false, busy = false, saved = false;
  Map<String, dynamic>? quote;
  bool uploading = false;
  // every course the ad may open: published courses (platform) / own courses (teacher)
  List<Map<String, dynamic>> courses = const [];
  try {
    final r = await ApiClient().get('/api/v1/ads/course-options');
    if (r is Map) courses = asMapList(r['items']);
  } catch (_) {}
  if (!context.mounted) return false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Future<void> requote() async {
          if (!teacher || start == null || end == null) return;
          final days = end!.difference(start!).inHours / 24;
          final r = await OrgApi.i.getMap('/api/v1/teacher/ads/quote', {'days': days.ceil().clamp(1, 365)});
          set(() => quote = r);
        }

        Future<void> pickDate(bool isStart) async {
          final d = await showDatePicker(context: ctx, firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: (isStart ? start : end) ?? DateTime.now());
          if (d != null) set(() => isStart ? start = d : end = d);
          await requote();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(edit == null ? t('إعلان جديد', 'New ad') : t('تعديل الإعلان', 'Edit ad')),
            ChoiceRow<String>(label: t('النوع', 'Type'),
                options: {'image': t('صورة', 'Image'), 'video': t('فيديو', 'Video'), 'link': t('رابط / نص', 'Link / text')},
                value: mediaType, onChanged: (v) => set(() => mediaType = v)),
            Field(controller: title, label: t('العنوان', 'Title')),
            Field(controller: body, label: t('وصف قصير', 'Short text'), maxLines: 2),
            if (mediaType == 'image')
              AppButton.secondary(
                onPressed: () async {
                  final r = await orgPickAndUpload('/api/v1/ads/media', extensions: const ['png', 'jpg', 'jpeg', 'webp'],
                      context: ctx, cropShape: CropShape.wide, allowTransparent: false); // the server stores a JPEG
                  if (r != null) set(() => media.text = '${r['url']}');
                },
                icon: media.text.isEmpty ? Icons.add_photo_alternate_rounded : Icons.check_circle_rounded,
                label: media.text.isEmpty ? t('رفع صورة الإعلان', 'Upload the ad image') : t('تغيير الصورة', 'Change image'),
              ),
            if (mediaType == 'video') ...[
              // a link (YouTube / Vimeo / file URL) OR a video from this device (mp4 / webm / mov, up to 60 MB)
              Field(controller: media, label: t('رابط الفيديو', 'Video link'), ltr: true),
              AppSpace.gapXs,
              AppButton.secondary(
                busy: uploading,
                onPressed: () async {
                  set(() => uploading = true);
                  final r = await orgPickAndUpload('/api/v1/ads/media', extensions: const ['mp4', 'webm', 'mov']);
                  set(() {
                    uploading = false;
                    if (r != null) media.text = '${r['url']}';
                  });
                },
                icon: Icons.video_library_rounded,
                label: t('أو اختر فيديو من جهازك', 'or choose a video from your device'),
              ),
            ],
            AppSpace.gapXs,
            ChoiceRow<String>(label: t('عند الضغط', 'On tap'),
                options: {'none': t('لا شيء', 'Nothing'), 'url': t('رابط خارجي', 'External link'), 'course': t('كورس', 'Course'), 'page': t('صفحة في التطبيق', 'App page')},
                value: targetType, onChanged: (v) => set(() {
                  targetType = v;
                  target.clear();
                })),
            if (targetType == 'url') Field(controller: target, label: 'https://…', ltr: true),
            if (targetType == 'course')
              OrgPickField<String>(
                label: t('الكورس', 'Course'),
                icon: Icons.menu_book_rounded,
                value: target.text.isEmpty ? null : target.text,
                options: {for (final co in courses) '${co['id']}': '${co['title']}'},
                onChanged: (v) => set(() => target.text = v ?? ''),
              ),
            if (targetType == 'page')
              OrgPickField<String>(
                label: t('الصفحة', 'Page'),
                icon: Icons.web_rounded,
                value: target.text.isEmpty ? null : target.text,
                options: adPages(),
                onChanged: (v) => set(() => target.text = v ?? ''),
              ),
            if (!teacher) ...[
              AppFieldLabel(t('يظهر لـ', 'Shown to')),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final e in {'student': t('الطلاب', 'Students'), 'teacher': t('المعلمين', 'Teachers'), 'parent': t('أولياء الأمور', 'Parents')}.entries)
                  AppChoiceChip(label: e.value, selected: roles.contains(e.key),
                      onTap: () => set(() => roles.contains(e.key) ? roles.remove(e.key) : roles.add(e.key))),
              ]),
            ] else
              Text(t('يظهر لطلاب كورساتك فقط', 'Shown to the students of your courses only'), style: AppType.meta(ctx).copyWith(color: c.textMedium)),
            AppSpace.gapSm,
            Row(children: [
              Expanded(
                  child: AppButton.secondary(
                      icon: Icons.event_rounded,
                      onPressed: () => pickDate(true),
                      label: start == null ? t('يبدأ', 'Starts') : shortDate(start!.toIso8601String()))),
              AppSpace.gapXs,
              Expanded(
                  child: AppButton.secondary(
                      icon: Icons.event_busy_rounded,
                      onPressed: () => pickDate(false),
                      label: end == null ? t('ينتهي', 'Ends') : shortDate(end!.toIso8601String()))),
            ]),
            if (teacher && quote != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: AppStatusBadge(
                    label: t('التكلفة: ${quote!['cost']} (${quote!['days']} يوم)', 'Cost: ${quote!['cost']} (${quote!['days']} days)'),
                    icon: Icons.payments_rounded,
                    tone: AppTone.warning),
              ),
            if (!teacher) AppSwitchTile(title: t('مفعّل', 'Active'), value: active, onChanged: (v) => set(() => active = v)),
            AppSpace.gapMd,
            AppButton.primary(
              expand: true,
              busy: busy,
              label: teacher && edit == null ? t('إرسال للمراجعة', 'Send for review') : t('حفظ', 'Save'),
              onPressed: () async {
                set(() => busy = true);
                final b = {
                  'title': title.text.trim(), 'body': body.text.trim(), 'media_type': mediaType,
                  'media_url': media.text.trim().isEmpty ? null : media.text.trim(),
                  'target_type': targetType, 'target_value': target.text.trim().isEmpty ? null : target.text.trim(),
                  'audience': {'roles': roles.toList()}, 'is_active': active,
                  'starts_at': start?.toIso8601String(), 'ends_at': end?.toIso8601String(),
                };
                final r = edit == null ? await OrgApi.i.post(base, b, t('تم الحفظ', 'Saved')) : await OrgApi.i.put('$base/${edit['id']}', b, t('تم الحفظ', 'Saved'));
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (r != null) {
                  saved = true;
                  Navigator.pop(ctx);
                }
              },
            ),
          ]),
        );
      }));
  return saved;
}

/// One performance figure of an ad: a quiet vector mark and the number (tabular, so a column of rows lines up).
Widget _adStat(BuildContext context, IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: AppIconSize.sm, color: context.colors.textLight),
      const SizedBox(width: AppSpace.xxs),
      Flexible(
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    ]);

/// A teacher's ad in their list: a paper card with the ad's own thumbnail (its picture or its tinted block), the
/// title, the review status and the figures.
Widget _adRow(BuildContext context, Map<String, dynamic> a, {required VoidCallback onTap, List<Widget> actions = const []}) {
  final st = '${a['status']}';
  final cost = a['cost'];
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs + AppSpace.xxs / 2),
    child: AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Row(children: [
        SizedBox(width: _thumbWidth, child: AspectRatio(aspectRatio: 16 / 9, child: AdCard(ad: a, compact: true))),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppStatusBadge(label: _adStatusLabel(st), tone: _adTone(st), dense: true),
              if (a['is_active'] == false && st != 'rejected') AppStatusBadge(label: t('متوقف', 'Off'), tone: AppTone.neutral, dense: true),
              _adStat(context, Icons.visibility_rounded, '${a['impressions'] ?? 0}'),
              _adStat(context, Icons.ads_click_rounded, '${a['clicks'] ?? 0} · ${a['ctr'] ?? 0}%'),
              _adStat(context, Icons.thumb_up_alt_outlined, '${a['likes'] ?? 0}'),
              _adStat(context, Icons.thumb_down_alt_outlined, '${a['dislikes'] ?? 0}'),
              if (cost is num && cost > 0)
                AppStatusBadge(
                    label: '$cost',
                    icon: a['paid'] == true ? Icons.check_circle_rounded : Icons.payments_rounded,
                    tone: a['paid'] == true ? AppTone.success : AppTone.warning,
                    dense: true),
              if (a['owner'] != null && a['owner_kind'] == 'teacher') _adStat(context, Icons.person_rounded, '${asMap(a['owner'])['name']}'),
            ]),
          ]),
        ),
        ...actions,
      ]),
    ),
  );
}

/// The thumbnail's width in a teacher's ad row (a 16:9 picture beside the title).
const double _thumbWidth = AppTouch.min * 2;

// ═════════════════════════════════════════════════════════════════════════════
//  Super admin
// ═════════════════════════════════════════════════════════════════════════════

class AdminAdsPage extends StatelessWidget {
  const AdminAdsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('/api/v1/admin/ads')..refresh(),
      child: const _AdminAdsView(),
    );
  }
}

AppTone _adTone(String s) => switch (s) {
      'approved' => AppTone.success,
      'rejected' => AppTone.danger,
      'pending' => AppTone.warning,
      _ => AppTone.neutral,
    };

String _adStatusLabel(String s) => switch (s) {
      'approved' => t('نشط', 'Live'),
      'pending' => t('بانتظار المراجعة', 'Waiting'),
      'rejected' => t('مرفوض', 'Rejected'),
      _ => statusLabel(s),
    };

class _AdminAdsView extends StatefulWidget {
  const _AdminAdsView();

  @override
  State<_AdminAdsView> createState() => _AdminAdsViewState();
}

class _AdminAdsViewState extends State<_AdminAdsView> {
  static const _base = '/api/v1/admin/ads';
  DateTime? _loadedAt;
  final Set<Object> _busy = {};

  Future<void> _refresh(OrgPaged p) async {
    await p.refresh();
    if (mounted) setState(() => _loadedAt = DateTime.now());
  }

  /// Approve asks whether the teacher paid for it (the server still receives `paid`, now chosen) and confirms.
  Future<void> _approve(OrgPaged p, Map<String, dynamic> a) async {
    final cost = a['cost'];
    // Paid by default, as Approve always recorded before; the admin picks Not paid when it was not.
    bool paid = a['paid'] != false;
    final ok = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          return AppSheetContent(title: t('الموافقة على الإعلان', 'Approve the ad'), children: [
            Text('${a['title']}', style: AppType.section(ctx)),
            AppSpace.gapXs,
            Text(
              (cost is num) && cost > 0
                  ? t('تكلفة الإعلان $cost. هل دفع المعلّن؟', 'The ad costs $cost. Has the advertiser paid?')
                  : t('هذا الإعلان لا تكلفة له.', 'This ad has no cost.'),
              style: AppType.body(ctx),
            ),
            AppSpace.gapSm,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppChoiceChip(label: t('مدفوع', 'Paid'), icon: Icons.check_circle_rounded, selected: paid, onTap: () => set(() => paid = true)),
              AppChoiceChip(label: t('غير مدفوع', 'Not paid'), icon: Icons.money_off_rounded, selected: !paid, onTap: () => set(() => paid = false)),
            ]),
            AppSpace.gapMd,
            AppButton.primary(label: t('موافقة ونشر', 'Approve and publish'), icon: Icons.check_rounded, expand: true, onPressed: () => Navigator.pop(ctx, true)),
          ]);
        }));
    if (ok != true || !mounted) return;
    await _run(a, () async {
      if (await OrgApi.i.post('$_base/${a['id']}/approve', {'paid': paid}, t('تمت الموافقة', 'Approved')) != null) p.refresh();
    });
  }

  Future<void> _reject(OrgPaged p, Map<String, dynamic> a) async {
    final note = await askText(context, title: t('سبب الرفض', 'Reason'), multiline: true);
    if (note == null || !mounted) return;
    await _run(a, () async {
      if (await OrgApi.i.post('$_base/${a['id']}/reject', {'note': note}, t('تم', 'Done')) != null) p.refresh();
    });
  }

  Future<void> _delete(OrgPaged p, Map<String, dynamic> a) async {
    if (!await appConfirm(context, message: t('حذف الإعلان «${a['title']}»؟', 'Delete the ad "${a['title']}"?'), danger: true) || !mounted) return;
    await _run(a, () async {
      if (await OrgApi.i.del('$_base/${a['id']}', t('تم الحذف', 'Deleted')) != null) p.refresh();
    });
  }

  /// One action at a time per ad (no double tap).
  Future<void> _run(Map<String, dynamic> a, Future<void> Function() fn) async {
    final id = a['id'] as Object;
    if (!_busy.add(id)) return;
    try {
      await fn();
    } finally {
      _busy.remove(id);
    }
  }

  Future<void> _edit(OrgPaged p, [Map<String, dynamic>? a]) async {
    if (await showAdEditor(context, base: _base, edit: a)) p.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgPaged>();
    final first = p.rows.isEmpty;
    return AdminPage(
      helpPageId: 'admin.ads',
      width: AppWidth.wide,
      title: t('الإعلانات', 'Ads'),
      icon: Icons.ads_click_rounded,
      onRefresh: p.isLoading ? null : () => _refresh(p),
      updatedAt: _loadedAt,
      primaryAction: AppButton.primary(label: t('إعلان جديد', 'New ad'), icon: Icons.add_rounded, onPressed: () => _edit(p)),
      body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: AppDataTable<Map<String, dynamic>>(
          state: p.isLoading && first
              ? AppTableState.loading
              : p.error != null && first
                  ? AppTableState.error
                  : AppTableState.ready,
          errorText: p.error,
          onRetry: p.refresh,
          rows: p.rows,
          toolbarTrailing: AppButton.tonal(
              label: t('إعدادات إعلانات المعلمين', 'Teacher ads settings'), icon: Icons.tune_rounded, size: AppButtonSize.sm, onPressed: () => _settings(context)),
          filters: [
            AppTableFilter(
              label: t('الحالة', 'Status'),
              value: (p.filters['status'] as String?)?.isEmpty ?? true ? null : '${p.filters['status']}',
              options: [
                ('pending', t('بانتظار المراجعة', 'Waiting')),
                ('approved', t('نشطة', 'Live')),
                ('rejected', t('مرفوضة', 'Rejected')),
              ],
              onChanged: (v) => p.setFilter('status', v),
            ),
          ],
          empty: AppEmpty(icon: Icons.ads_click_rounded, title: t('لا إعلانات بعد', 'No ads yet')),
          hasMore: p.hasMore,
          loadingMore: p.loadingMore,
          onLoadMore: p.loadMore,
          onRowTap: (a) => _edit(p, a),
          columns: [
            AppTableColumn<Map<String, dynamic>>(
              key: 'title',
              label: t('الإعلان', 'Ad'),
              primary: true,
              flex: 3,
              cell: (context, a) {
                final isTeacher = a['owner'] != null && a['owner_kind'] == 'teacher';
                return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('${a['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                  if (isTeacher) Text('${asMap(a['owner'])['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ]);
              },
            ),
            AppTableColumn<Map<String, dynamic>>(
              key: 'status',
              label: t('الحالة', 'Status'),
              cell: (context, a) {
                final st = '${a['status']}';
                return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                  AppStatusBadge(label: _adStatusLabel(st), tone: _adTone(st)),
                  if (a['is_active'] == false && st != 'rejected') AppStatusBadge(label: t('متوقف', 'Off'), tone: AppTone.neutral),
                ]);
              },
            ),
            AppTableColumn<Map<String, dynamic>>(
              key: 'stats',
              label: t('الأداء', 'Performance'),
              flex: 2,
              cell: (context, a) => Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
                _adStat(context, Icons.visibility_rounded, '${a['impressions'] ?? 0}'),
                _adStat(context, Icons.ads_click_rounded, '${a['clicks'] ?? 0} · ${a['ctr'] ?? 0}%'),
                _adStat(context, Icons.thumb_up_alt_outlined, '${a['likes'] ?? 0}'),
                _adStat(context, Icons.thumb_down_alt_outlined, '${a['dislikes'] ?? 0}'),
              ]),
            ),
            AppTableColumn<Map<String, dynamic>>(
              key: 'cost',
              label: t('التكلفة', 'Cost'),
              showOnPhone: false,
              cell: (context, a) {
                final cost = a['cost'];
                if (cost is! num || cost <= 0) return Text('—', style: AppType.meta(context));
                return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('$cost', style: AppType.row(context)),
                  AppStatusBadge(label: a['paid'] == true ? t('مدفوع', 'Paid') : t('غير مدفوع', 'Not paid'), tone: a['paid'] == true ? AppTone.success : AppTone.warning, dense: true),
                ]);
              },
            ),
          ],
          rowActions: (a) => [
            if (a['status'] == 'pending') AppRowAction(icon: Icons.check_circle_rounded, label: t('موافقة', 'Approve'), onTap: () => _approve(p, a)),
            if (a['status'] == 'pending') AppRowAction(icon: Icons.cancel_rounded, label: t('رفض', 'Reject'), onTap: () => _reject(p, a)),
            AppRowAction(icon: Icons.edit_rounded, label: t('تعديل', 'Edit'), onTap: () => _edit(p, a)),
            AppRowAction(icon: Icons.delete_outline_rounded, label: t('حذف', 'Delete'), danger: true, onTap: () => _delete(p, a)),
          ],
        ),
      ),
    );
  }

  Future<void> _settings(BuildContext context) async {
    final s = await OrgApi.i.getMap('$_base/settings');
    if (s == null || !context.mounted) return;
    bool enabled = s['teacher_ads_enabled'] == true, approval = s['requires_approval'] != false, busy = false;
    final price = TextEditingController(text: '${s['price_per_day'] ?? 0}');
    final days = TextEditingController(text: '${s['max_days'] ?? 30}');
    String? priceErr, daysErr;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          Future<void> save() async {
            if (busy) return;
            final pr = double.tryParse(price.text.trim());
            final dy = int.tryParse(days.text.trim());
            set(() {
              priceErr = pr == null || pr < 0 ? t('أدخل سعرًا صحيحًا (0 = مجاني)', 'Enter a valid price (0 = free)') : null;
              daysErr = dy == null || dy < 1 || dy > 365 ? t('أدخل عددًا من 1 إلى 365', 'Enter a number from 1 to 365') : null;
            });
            if (priceErr != null || daysErr != null) return;
            set(() => busy = true);
            final r = await OrgApi.i.put('$_base/settings', {
              'teacher_ads_enabled': enabled, 'requires_approval': approval,
              'price_per_day': pr, 'max_days': dy,
            }, t('تم الحفظ', 'Saved'));
            if (!ctx.mounted) return;
            if (r != null) {
              Navigator.pop(ctx);
            } else {
              set(() => busy = false);
            }
          }

          Widget err(String? e) => e == null
              ? const SizedBox.shrink()
              : Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: Text(e, style: AppType.meta(ctx).copyWith(color: ctx.colors.danger)));
          return AppSheetContent(title: t('إعلانات المعلمين', 'Teacher ads'), children: [
            AppSwitchTile(
                title: t('السماح للمعلمين بالإعلان', 'Allow teachers to advertise'),
                subtitle: t('لطلاب كورساتهم فقط', 'To their own students only'),
                value: enabled,
                onChanged: (v) => set(() => enabled = v)),
            AppSwitchTile(title: t('مراجعة كل إعلان قبل نشره', 'Review every ad before it goes live'), value: approval, onChanged: (v) => set(() => approval = v)),
            AppNumberField(controller: price, label: t('السعر لكل يوم', 'Price per day'), min: 0, decimals: 2),
            err(priceErr),
            AppNumberField(controller: days, label: t('أقصى مدة (أيام)', 'Max duration (days)'), min: 0),
            err(daysErr),
            AppButton.primary(label: t('حفظ', 'Save'), busy: busy, expand: true, onPressed: busy ? null : save),
          ]);
        }));
    disposeAfterRoute([price, days]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Teachers
// ═════════════════════════════════════════════════════════════════════════════

class TeacherAdsPage extends StatefulWidget {
  const TeacherAdsPage({super.key});

  @override
  State<TeacherAdsPage> createState() => _TeacherAdsPageState();
}

class _TeacherAdsPageState extends State<TeacherAdsPage> {
  List<Map<String, dynamic>>? _items;
  Map<String, dynamic>? _settings;
  String? _blocked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient().get('/api/v1/teacher/ads');
      if (!mounted) return;
      setState(() {
        _items = asMapList((r as Map)['items']);
        _settings = asMap(r['settings']);
        _blocked = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _blocked = e.message);
    }
  }

  Future<void> _create() async {
    if (await showAdEditor(context, base: '/api/v1/teacher/ads', teacher: true)) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items ?? const <Map<String, dynamic>>[];
    return BasePage(
      useWebCard: true,
      width: AppWidth.content,
      appBar: ScreenAppBar(title: t('إعلاناتي', 'My ads')),
      child: _blocked != null
          ? AppEmpty(icon: Icons.campaign_rounded, title: t('الإعلانات غير متاحة حالياً', 'Ads are not available right now'), message: _blocked)
          : _items == null
              ? const AppListSkeleton(items: 3, withAvatar: false)
              : Scaffold(
                  backgroundColor: Colors.transparent,
                  floatingActionButton: items.isEmpty
                      ? null
                      : FloatingActionButton.extended(
                          heroTag: 'tads',
                          onPressed: _create,
                          icon: const Icon(Icons.add_rounded),
                          label: Text(t('إعلان جديد', 'New ad')),
                        ),
                  body: ListView(padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xxxl + AppSpace.xl), children: [
                    // The terms of advertising: the page's one tinted block.
                    if (_settings != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
                        child: AppBlock(
                          tone: AppBlockTone.sky,
                          padding: AppSpace.card,
                          child: Row(children: [
                            Icon(Icons.payments_rounded, size: AppIconSize.lg, color: AppBlockColors.of(context, AppBlockTone.sky).accentInk(c.primary)),
                            const SizedBox(width: AppSpace.sm),
                            Expanded(
                              child: Text(
                                  t('السعر ${_settings!['price_per_day']} لليوم${_settings!['requires_approval'] == true ? ' · يراجع فريق المنصة كل إعلان' : ''}',
                                      'Price ${_settings!['price_per_day']} per day${_settings!['requires_approval'] == true ? ' · every ad is reviewed' : ''}'),
                                  style: AppType.bodyStrong(context)),
                            ),
                          ]),
                        ),
                      ),
                    if (items.isEmpty)
                      AppEmpty(
                          icon: Icons.campaign_rounded,
                          title: t('أعلن عن كورساتك لطلابك', 'Promote your courses to your students'),
                          actionLabel: t('إعلان جديد', 'New ad'),
                          onAction: _create),
                    for (var i = 0; i < items.length; i++)
                      AppReveal(
                        index: i,
                        group: 'teacher-ads',
                        child: _adRow(context, items[i],
                            onTap: () async {
                              if (await showAdEditor(context, base: '/api/v1/teacher/ads', edit: items[i], teacher: true)) _load();
                            },
                            actions: [
                              IconButton(tooltip: t('حذف', 'Delete'), icon: Icon(Icons.delete_outline_rounded, color: c.danger), onPressed: () async {
                                if (await confirm(context, message: t('حذف الإعلان؟', 'Delete this ad?'), danger: true) &&
                                    await OrgApi.i.del('/api/v1/teacher/ads/${items[i]['id']}', t('تم الحذف', 'Deleted')) != null) _load();
                              }),
                            ]),
                      ),
                  ]),
                ),
    );
  }
}
