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
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/features/student/courses/details/course_detail_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import '../org/org_providers.dart';
import '../org/org_ui.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Home slider
// ═════════════════════════════════════════════════════════════════════════════

/// App pages an ad can open (named routes).
Map<String, String> adPages() => {
      '/subscription': t('الاشتراكات والباقات', 'Subscription plans'),
      '/notifications': t('الإشعارات', 'Notifications'),
      '/downloads': t('التنزيلات', 'Downloads'),
      '/profile': t('حسابي', 'My account'),
      '/home': t('الرئيسية', 'Home'),
    };

/// Home "featured" slider — sits after the greeting / search / next class, before the organization block:
/// personal content first, ads second. Auto-plays, pauses while the finger is on it, 👍 / 👎 per ad.
class HomeAdsSlider extends StatefulWidget {
  const HomeAdsSlider({super.key, this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 14)});
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
    try {
      final r = await ApiClient().get('/api/v1/ads/feed');
      if (!mounted || r is! Map) return;
      setState(() => _ads = asMapList(r['items']));
      _timer?.cancel();
      if (_ads.length > 1) {
        _timer = Timer.periodic(const Duration(seconds: 6), (_) {
          if (_hold || !_pc.hasClients) return;
          _pc.animateToPage((_page + 1) % _ads.length, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
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
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => CourseDetailScreen(course: CourseModel.fromJson(Map<String, dynamic>.from(r)))));
        }
      } catch (_) {
        toast(t('تعذّر فتح الكورس', 'Could not open the course'), error: true);
      }
    } else if (type == 'page' && value.startsWith('/')) {
      Navigator.of(context).pushNamed(value);
    } else if (ad['media_type'] == 'video' && '${ad['media_url'] ?? ''}'.isNotEmpty) {
      await launchUrl(Uri.parse(orgFileUrl('${ad['media_url']}')), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ads.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: LayoutBuilder(builder: (context, box) {
            final ratio = box.maxWidth > 700 ? 16 / 5.6 : 16 / 8.5;      // calmer, wider banner on tablets / web
            return Listener(
              onPointerDown: (_) => _hold = true,
              onPointerUp: (_) => _hold = false,
              child: AspectRatio(
                aspectRatio: ratio,
                child: Stack(children: [
                  PageView.builder(
                    controller: _pc,
                    itemCount: _ads.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => AdCard(ad: _ads[i], onTap: () => _open(_ads[i]), onReact: (v) => _react(i, v)),
                  ),
                  if (_ads.length > 1)
                    PositionedDirectional(
                      bottom: 12,
                      end: 16,
                      child: Row(children: [
                        for (var i = 0; i < _ads.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            width: i == _page ? 16 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: i == _page ? 0.95 : 0.5), borderRadius: BorderRadius.circular(4)),
                          ),
                      ]),
                    ),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// One ad: full-bleed media, soft gradient, title / text, CTA hint, 👍 / 👎 glass pills, discreet "Ad" tag.
class AdCard extends StatelessWidget {
  const AdCard({super.key, required this.ad, this.onTap, this.onReact});
  final Map<String, dynamic> ad;
  final VoidCallback? onTap;
  final ValueChanged<int>? onReact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = '${ad['media_url'] ?? ''}';
    final isVideo = ad['media_type'] == 'video';
    final showImage = media.isNotEmpty && ad['media_type'] == 'image';
    final hasTarget = '${ad['target_type'] ?? 'none'}' != 'none' || isVideo;
    final mine = asInt(ad['my_reaction']);
    Widget glass(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18))),
          child: child,
        );
    Widget react(IconData on, IconData off, int v, int n) => InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onReact == null ? null : () => onReact!(v),
          child: glass(Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(mine == v ? on : off, size: 15, color: Colors.white),
            if (n > 0) ...[const SizedBox(width: 4), Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11.5))],
          ])),
        );
    return Material(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      color: c.primary,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          if (showImage)
            Image.network(orgFileUrl(media), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
          else
            DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd, colors: [c.primary, c.primaryDark]))),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Colors.transparent, Color(0xC0000000)], stops: [0, 0.35, 1]),
            ),
          ),
          if (isVideo)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6))),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
              ),
            ),
          PositionedDirectional(
            top: 12,
            start: 12,
            child: Row(children: [
              if (onReact != null) ...[
                react(Icons.thumb_up_alt_rounded, Icons.thumb_up_alt_outlined, 1, asInt(ad['likes'])),
                const SizedBox(width: 6),
                react(Icons.thumb_down_alt_rounded, Icons.thumb_down_alt_outlined, -1, asInt(ad['dislikes'])),
              ],
            ]),
          ),
          PositionedDirectional(
            top: 12,
            end: 12,
            child: glass(Text(t('إعلان', 'Ad'), style: const TextStyle(fontFamily: 'tajawal', fontSize: 10.5, color: Colors.white))),
          ),
          PositionedDirectional(
            start: 18,
            end: 70,
            bottom: 16,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${ad['title']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'tajawal', fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
              if ('${ad['body'] ?? ''}'.isNotEmpty)
                Text('${ad['body']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: Colors.white.withValues(alpha: 0.9))),
              if (hasTarget) ...[
                const SizedBox(height: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(isVideo && '${ad['target_type']}' == 'none' ? t('شاهد الآن', 'Watch now') : t('اكتشف', 'Discover'),
                      style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
                ]),
              ],
            ]),
          ),
        ]),
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(edit == null ? t('إعلان جديد', 'New ad') : t('تعديل الإعلان', 'Edit ad')),
            ChoiceRow<String>(label: t('النوع', 'Type'),
                options: {'image': t('صورة', 'Image'), 'video': t('فيديو', 'Video'), 'link': t('رابط / نص', 'Link / text')},
                value: mediaType, onChanged: (v) => set(() => mediaType = v)),
            Field(controller: title, label: t('العنوان', 'Title')),
            Field(controller: body, label: t('وصف قصير', 'Short text'), maxLines: 2),
            if (mediaType == 'image')
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await orgPickAndUpload('/api/v1/ads/media', extensions: const ['png', 'jpg', 'jpeg', 'webp'],
                      context: ctx, cropShape: CropShape.wide);
                  if (r != null) set(() => media.text = '${r['url']}');
                },
                icon: Icon(media.text.isEmpty ? Icons.add_photo_alternate_rounded : Icons.check_circle_rounded),
                label: Text(media.text.isEmpty ? t('رفع صورة الإعلان', 'Upload the ad image') : t('تغيير الصورة', 'Change image')),
              ),
            if (mediaType == 'video') ...[
              // a link (YouTube / Vimeo / file URL) OR a video from this device (mp4 / webm / mov, up to 60 MB)
              Field(controller: media, label: t('رابط الفيديو', 'Video link'), ltr: true),
              OutlinedButton.icon(
                onPressed: () async {
                  set(() => uploading = true);
                  final r = await orgPickAndUpload('/api/v1/ads/media', extensions: const ['mp4', 'webm', 'mov']);
                  set(() {
                    uploading = false;
                    if (r != null) media.text = '${r['url']}';
                  });
                },
                icon: uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.video_library_rounded),
                label: Text(t('أو اختر فيديو من جهازك', 'or choose a video from your device')),
              ),
            ],
            const SizedBox(height: 8),
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
              Text(t('يظهر لـ', 'Shown to'), style: orgText(ctx, size: 12.5, color: c.textLight)),
              Wrap(spacing: 8, children: [
                for (final e in {'student': t('الطلاب', 'Students'), 'teacher': t('المعلمين', 'Teachers'), 'parent': t('أولياء الأمور', 'Parents')}.entries)
                  FilterChip(label: Text(e.value), selected: roles.contains(e.key),
                      onSelected: (on) => set(() => on ? roles.add(e.key) : roles.remove(e.key))),
              ]),
            ] else
              Text(t('يظهر لطلاب كورساتك فقط', 'Shown to the students of your courses only'), style: orgText(ctx, size: 12.5, color: c.textMedium)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => pickDate(true), child: Text(start == null ? t('يبدأ', 'Starts') : shortDate(start!.toIso8601String())))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => pickDate(false), child: Text(end == null ? t('ينتهي', 'Ends') : shortDate(end!.toIso8601String())))),
            ]),
            if (teacher && quote != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OrgPill(t('التكلفة: ${quote!['cost']} (${quote!['days']} يوم)', 'Cost: ${quote!['cost']} (${quote!['days']} days)'),
                    icon: Icons.payments_rounded, color: c.warning),
              ),
            if (!teacher) OrgSwitchRow(title: t('مفعّل', 'Active'), value: active, onChanged: (v) => set(() => active = v)),
            const SizedBox(height: 10),
            PrimaryButton(
              isLoading: busy,
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

Widget _adRow(BuildContext context, Map<String, dynamic> a, {required VoidCallback onTap, List<Widget> actions = const []}) {
  final c = context.colors;
  final st = '${a['status']}';
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
    child: RowCard(
      accent: st == 'pending' ? c.warning : (a['is_active'] == false ? c.textLight : null),
      onTap: onTap,
      child: Row(children: [
        SizedBox(width: 92, child: AspectRatio(aspectRatio: 16 / 9, child: AdCard(ad: a))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              StatusChip(statusLabel(st == 'approved' ? 'active' : st), statusColor(context, st == 'approved' ? 'active' : st)),
              OrgPill('👁 ${a['impressions']} · 👆 ${a['clicks']} · ${a['ctr']}%', color: c.textMedium),
              OrgPill('👍 ${a['likes'] ?? 0} · 👎 ${a['dislikes'] ?? 0}', color: c.textMedium),
              if ((a['cost'] ?? 0) > 0) OrgPill('${a['cost']} ${a['paid'] == true ? '✓' : ''}', icon: Icons.payments_rounded, color: c.warning),
              if (a['owner'] != null && a['owner_kind'] == 'teacher') OrgPill('${asMap(a['owner'])['name']}', icon: Icons.person_rounded),
            ]),
          ]),
        ),
        ...actions,
      ]),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Super admin
// ═════════════════════════════════════════════════════════════════════════════

class AdminAdsPage extends StatelessWidget {
  const AdminAdsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('/api/v1/admin/ads')..refresh(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgPaged>();
        return BasePage(
          useWebCard: true,
          maxWith: 960,
          appBar: ScreenAppBar(title: t('الإعلانات', 'Ads'), actions: [
            IconButton(tooltip: t('إعدادات إعلانات المعلمين', 'Teacher ads settings'), onPressed: () => _settings(context), icon: const Icon(Icons.tune_rounded)),
            IconButton(tooltip: t('إعلان جديد', 'New ad'), onPressed: () async {
              if (await showAdEditor(context, base: '/api/v1/admin/ads')) p.refresh();
            }, icon: const Icon(Icons.add_rounded)),
          ]),
          child: Column(children: [
            const SizedBox(height: 8),
            FilterChips<String>(
              options: {'': t('الكل', 'All'), 'pending': t('بانتظار المراجعة', 'Waiting'), 'approved': t('نشطة', 'Live'), 'rejected': t('مرفوضة', 'Rejected')},
              value: '${p.filters['status'] ?? ''}',
              onChanged: (v) => p.setFilter('status', v),
            ),
            Expanded(
              child: PagedList<OrgPaged>(
                emptyText: t('لا إعلانات بعد', 'No ads yet'),
                itemBuilder: (context, a) => _adRow(context, a,
                    onTap: () async {
                      if (await showAdEditor(context, base: '/api/v1/admin/ads', edit: a)) p.refresh();
                    },
                    actions: [
                      if (a['status'] == 'pending') ...[
                        IconButton(icon: Icon(Icons.check_circle_rounded, color: context.colors.success), onPressed: () async {
                          if (await OrgApi.i.post('/api/v1/admin/ads/${a['id']}/approve', {'paid': true}, t('تمت الموافقة', 'Approved')) != null) p.refresh();
                        }),
                        IconButton(icon: Icon(Icons.cancel_rounded, color: context.colors.danger), onPressed: () async {
                          final note = await askText(context, title: t('سبب الرفض', 'Reason'), multiline: true);
                          if (note != null && await OrgApi.i.post('/api/v1/admin/ads/${a['id']}/reject', {'note': note}, t('تم', 'Done')) != null) p.refresh();
                        }),
                      ],
                      IconButton(icon: Icon(Icons.delete_outline_rounded, color: context.colors.danger), onPressed: () async {
                        if (await confirm(context, message: t('حذف الإعلان؟', 'Delete this ad?'), danger: true) &&
                            await OrgApi.i.del('/api/v1/admin/ads/${a['id']}', t('تم الحذف', 'Deleted')) != null) p.refresh();
                      }),
                    ]),
              ),
            ),
          ]),
        );
      }),
    );
  }

  Future<void> _settings(BuildContext context) async {
    final s = await OrgApi.i.getMap('/api/v1/admin/ads/settings');
    if (s == null || !context.mounted) return;
    bool enabled = s['teacher_ads_enabled'] == true, approval = s['requires_approval'] != false;
    final price = TextEditingController(text: '${s['price_per_day'] ?? 0}');
    final days = TextEditingController(text: '${s['max_days'] ?? 30}');
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('إعلانات المعلمين', 'Teacher ads')),
            OrgSwitchRow(title: t('السماح للمعلمين بالإعلان', 'Allow teachers to advertise'),
                subtitle: t('لطلاب كورساتهم فقط', 'To their own students only'), value: enabled, onChanged: (v) => set(() => enabled = v)),
            OrgSwitchRow(title: t('مراجعة كل إعلان قبل نشره', 'Review every ad before it goes live'), value: approval, onChanged: (v) => set(() => approval = v)),
            Field(controller: price, label: t('السعر لكل يوم', 'Price per day'), keyboard: TextInputType.number, ltr: true),
            Field(controller: days, label: t('أقصى مدة (أيام)', 'Max duration (days)'), keyboard: TextInputType.number, ltr: true),
            PrimaryButton(isLoading: false, label: t('حفظ', 'Save'), onPressed: () async {
              final r = await OrgApi.i.put('/api/v1/admin/ads/settings', {
                'teacher_ads_enabled': enabled, 'requires_approval': approval,
                'price_per_day': double.tryParse(price.text) ?? 0, 'max_days': int.tryParse(days.text) ?? 30,
              }, t('تم الحفظ', 'Saved'));
              if (r != null && ctx.mounted) Navigator.pop(ctx);
            }),
          ]),
        )));
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: t('إعلاناتي', 'My ads')),
      child: _blocked != null
          ? OrgEmpty(icon: Icons.campaign_rounded, title: t('الإعلانات غير متاحة حالياً', 'Ads are not available right now'), message: _blocked)
          : OrgAsync(
              loading: _items == null,
              failed: false,
              onRetry: _load,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                floatingActionButton: FloatingActionButton.extended(
                  heroTag: 'tads',
                  onPressed: () async {
                    if (await showAdEditor(context, base: '/api/v1/teacher/ads', teacher: true)) _load();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(t('إعلان جديد', 'New ad')),
                ),
                body: ListView(padding: const EdgeInsets.only(top: 10, bottom: 100), children: [
                  if (_settings != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                          t('السعر ${_settings!['price_per_day']} لليوم${_settings!['requires_approval'] == true ? ' · يراجع فريق المنصة كل إعلان' : ''}',
                              'Price ${_settings!['price_per_day']} per day${_settings!['requires_approval'] == true ? ' · every ad is reviewed' : ''}'),
                          style: orgText(context, size: 12.5, color: c.textMedium)),
                    ),
                  if ((_items ?? const []).isEmpty)
                    OrgEmpty(icon: Icons.campaign_rounded, title: t('أعلن عن كورساتك لطلابك', 'Promote your courses to your students')),
                  for (final a in _items ?? const <Map<String, dynamic>>[])
                    _adRow(context, a,
                        onTap: () async {
                          if (await showAdEditor(context, base: '/api/v1/teacher/ads', edit: a, teacher: true)) _load();
                        },
                        actions: [
                          IconButton(icon: Icon(Icons.delete_outline_rounded, color: c.danger), onPressed: () async {
                            if (await confirm(context, message: t('حذف الإعلان؟', 'Delete this ad?'), danger: true) &&
                                await OrgApi.i.del('/api/v1/teacher/ads/${a['id']}', t('تم الحذف', 'Deleted')) != null) _load();
                          }),
                        ]),
                ]),
              ),
            ),
    );
  }
}
