// lib/features/admin/admin_content_page.dart
//
// Admin: everything the public "About us" and "Terms & conditions" screens show.
//
//   About us   identity (name · tagline · mission/motivation · logo)
//              stats banner · team (with photos) · contact channels
//   Privacy & terms   the Privacy policy and the Terms of service users read (D-308, admin_legal_page.dart)
//   Terms (older apps) version / last-updated + the accordion sections that installed app versions still read;
//              saving the Terms of service in "Privacy & terms" replaces them
//
// Every list can be added to, edited (AR + EN), shown/hidden with one tap,
// deleted and re-ordered by dragging.  Same look as admin_required_documents_page.
//
// Reads : GET  /api/v1/admin/content/about | /terms          (raw, both languages)
// Writes: POST/PATCH/DELETE /api/v1/app-content/...          (existing router)
// Order : POST /api/v1/admin/content/{stats|team|contacts|sections}/reorder
// Photos: POST /api/v1/app-content/about/info/logo · /about/team/{id}/image
//         (needs the `image_picker` package — see _pickImage)
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/student/courses/details/components/app_responsive.dart'
    show Breakpoints;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'admin_common.dart';
import 'admin_legal_page.dart' show AdminLegalPanel;
import 'admin_page.dart';
import 'cfg_common.dart';
import 'admin_premium_widgets.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppListSkeleton, AppRefresh, AppKpiGrid, AppKpiCard, AppTabs, AppTabItem, AppSpace, appErrorMessage, AppBanner;
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  icons · contact types · quick-start presets
// ═════════════════════════════════════════════════════════════════════════════

/// icon_name (stored in the DB) → icon. Use the same map in the public About /
/// Terms screens so users see the icon the admin picked.
const Map<String, IconData> kContentIcons = {
  'star': Icons.star_rounded,
  'rocket_launch': Icons.rocket_launch_rounded,
  'lightbulb': Icons.lightbulb_rounded,
  'school': Icons.school_rounded,
  'groups': Icons.groups_rounded,
  'verified': Icons.verified_rounded,
  'security': Icons.security_rounded,
  'support_agent': Icons.support_agent_rounded,
  'devices': Icons.devices_rounded,
  'speed': Icons.speed_rounded,
  'workspace_premium': Icons.workspace_premium_rounded,
  'favorite': Icons.favorite_rounded,
  'insights': Icons.insights_rounded,
  'language': Icons.language_rounded,
  'menu_book': Icons.menu_book_rounded,
  'quiz': Icons.quiz_rounded,
  'play_circle': Icons.play_circle_rounded,
  'emoji_events': Icons.emoji_events_rounded,
  'bolt': Icons.bolt_rounded,
  'public': Icons.public_rounded,
  'schedule': Icons.schedule_rounded,
  'payments': Icons.payments_rounded,
  'gavel': Icons.gavel_rounded,
  'description': Icons.description_rounded,
  'policy': Icons.policy_rounded,
  'privacy_tip': Icons.privacy_tip_rounded,
  'lock': Icons.lock_rounded,
  'handshake': Icons.handshake_rounded,
  'gpp_good': Icons.gpp_good_rounded,
  'flag': Icons.flag_rounded,
};

IconData contentIcon(String? name) => kContentIcons[name] ?? Icons.star_rounded;

/// ContactInfo.type values the public screen understands.
const Map<String, IconData> kContactTypes = {
  'email': Icons.email_rounded,
  'phone': Icons.phone_rounded,
  'whatsapp': Icons.chat_rounded,
  'telegram': Icons.send_rounded,
  'website': Icons.language_rounded,
  'facebook': Icons.facebook_rounded,
  'instagram': Icons.camera_alt_rounded,
  'youtube': Icons.smart_display_rounded,
  'address': Icons.location_on_rounded,
};

IconData contactIcon(String? type) => kContactTypes[type] ?? Icons.link_rounded;

/// Gradient pairs (light → base) taken from the APP THEME, so the admin pages follow the
/// colours set in the dashboard instead of a fixed rainbow.
class _Pal {
  _Pal(ThemeConfigProvider c)
      : primary = [c.primaryLight, c.primary],
        gold = [c.heroTint(c.accent2, 0.25), c.accent2],
        green = [c.heroTint(c.success, 0.25), c.success],
        purple = [c.heroTint(c.purple, 0.25), c.purple],
        warm = [c.heroTint(c.warning, 0.25), c.warning];

  final List<Color> primary, gold, green, purple, warm;

  List<List<Color>> get all => [primary, gold, green, purple, warm];
}

_Pal _pal(BuildContext context) => _Pal(context.colors);

class _Preset {
  const _Preset(this.ar, this.en, this.icon);

  final String ar, en, icon;
}

// Data (stored in both languages), not translation keys.
const _termsPresets = [
  _Preset('قبول الشروط', 'Acceptance of terms', 'gavel'),
  _Preset('سياسة الخصوصية', 'Privacy policy', 'privacy_tip'),
  _Preset('سياسة الاسترداد', 'Refund policy', 'payments'),
  _Preset('قواعد الاستخدام', 'User conduct', 'policy'),
  _Preset('الملكية الفكرية', 'Intellectual property', 'lock'),
  _Preset('حماية الحساب', 'Account security', 'security'),
];

const _statPresets = [
  _Preset('طالب مسجّل', 'Registered students', 'groups'),
  _Preset('معلم معتمد', 'Certified teachers', 'verified'),
  _Preset('دورة تعليمية', 'Courses', 'menu_book'),
  _Preset('ساعة محتوى', 'Hours of content', 'schedule'),
];

// ═════════════════════════════════════════════════════════════════════════════
//  page
// ═════════════════════════════════════════════════════════════════════════════

class AdminContentPage extends StatefulWidget {
  const AdminContentPage({super.key});

  @override
  State<AdminContentPage> createState() => _AdminContentPageState();
}

class _AdminContentPageState extends State<AdminContentPage> {
  static const _read = '/api/v1/admin/content';
  static const _write = '/api/v1/app-content';

  final _api = ApiClient();

  int _tab = 0; // 0 = about · 1 = privacy & terms (D-308) · 2 = the older terms sections
  bool _loading = true;
  Object? _error;
  String? _uploading; // path of the running upload

  Map<String, dynamic>? _info;
  List<Map<String, dynamic>> _stats = [], _team = [], _contacts = [];
  Map<String, dynamic>? _meta;
  List<Map<String, dynamic>> _sections = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── data ───────────────────────────────────────────────────────────────────
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final got = await Future.wait([_api.get('$_read/about'), _api.get('$_read/terms')]);
      final a = asMap(got[0]);
      final t = asMap(got[1]);
      _info = a['info'] is Map ? asMap(a['info']) : null;
      _stats = asMapList(a['stats']);
      _team = asMapList(a['team']);
      _contacts = asMapList(a['contacts']);
      _meta = t['meta'] is Map ? asMap(t['meta']) : null;
      _sections = asMapList(t['sections']);
      _error = null;
    } catch (e) {
      // a failed refresh keeps what is on screen
      if (_info == null && _sections.isEmpty && _team.isEmpty) {
        _error = ApiException.from(e);
      } else {
        toast(appErrorMessage(e), error: true);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run(Future<dynamic> Function() job, {String? ok}) async {
    try {
      await job();
      if (ok != null) toast(ok.tr);
      await _load(silent: true);
    } catch (e) {
      toast(appErrorMessage(e), error: true);
    }
  }

  /// Create (existing == null) or update one row of a list.
  Future<void> _upsert(String path, Map<String, dynamic>? existing, Map<String, dynamic> body) =>
      _run(
            () => existing == null
            ? _api.post('$_write$path', body: body)
            : _api.patch('$_write$path/${existing['id']}', body: body),
        ok: 'content_saved',
      );

  Future<void> _toggleActive(String path, Map<String, dynamic> row) async {
    final v = !asBool(row['is_active'], true);
    try {
      await _api.patch('$_write$path/${row['id']}', body: {'is_active': v});
      if (mounted) setState(() => row['is_active'] = v);
    } catch (e) {
      toast(appErrorMessage(e), error: true);
    }
  }

  Future<void> _delete(String path, Map<String, dynamic> row, String confirmKey) async {
    final ok = await confirm(context,
        message: confirmKey.tr, confirmLabel: 'delete'.tr, danger: true);
    if (!ok) return;
    await _run(() => _api.delete('$_write$path/${row['id']}'), ok: 'content_deleted');
  }

  Future<void> _reorder(String kind, List<Map<String, dynamic>> list, int from, int to) async {
    if (to > from) to--;
    final it = list.removeAt(from);
    list.insert(to, it);
    setState(() {});
    try {
      await _api.post('$_read/$kind/reorder', body: {'ids': list.map((e) => e['id']).toList()});
    } catch (e) {
      toast(appErrorMessage(e), error: true);
      _load(silent: true);
    }
  }

  /// Gallery → bytes → multipart. Swap this one function if the project already
  /// uses another picker (file_picker, …); only the bytes + file name matter.
  Future<void> _pickImage(String path) async {
    final ({Uint8List bytes, String name})? img;
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 88);
      if (x == null || !mounted) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      img = await cropImageWithName(context, bytes, x.name);
    } catch (e) {
      toast(appErrorMessage(e), error: true);
      return;
    }
    if (img == null || !mounted) return;
    setState(() => _uploading = path);
    try {
      final bytes = img.bytes;
      await _api.postMultipart(
        '$_write$path',
        fields: const {},
        fileField: 'file',
        fileName: img.name,
        fileBytes: bytes,
      );
      toast('content_photo_saved'.tr);
      await _load(silent: true);
    } catch (e) {
      toast(appErrorMessage(e), error: true);
    }
    if (mounted) setState(() => _uploading = null);
  }

  Future<void> _removeTeamPhoto(Map<String, dynamic> m) async {
    await _run(() => _api.delete('$_write/about/team/${m['id']}/image'), ok: 'content_photo_removed');
  }

  // ── forms ──────────────────────────────────────────────────────────────────
  Future<void> _form(
      _FormCfg cfg, {
        Map<String, dynamic>? item,
        required String path,
        int? nextOrder,
        bool single = false, // singleton rows (about info / terms meta): always PATCH, no id
      }) async {
    final body = await showAdminSheet<Map<String, dynamic>>(
        context, (ctx) => _EntityForm(cfg: cfg, item: item));
    if (body == null) return;
    if (single) {
      await _run(() => _api.patch('$_write$path', body: body), ok: 'content_saved');
      return;
    }
    if (item == null && nextOrder != null) body['order'] = nextOrder;
    await _upsert(path, item, body);
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  bool get _ar => AppConfig.lang == 'ar';

  String _loc(Map<String, dynamic>? m, String base) {
    final ar = asStr(m?['${base}_ar']);
    final en = asStr(m?['${base}_en']);
    return _ar ? (ar.isEmpty ? en : ar) : (en.isEmpty ? ar : en);
  }

  String _other(Map<String, dynamic>? m, String base) {
    final ar = asStr(m?['${base}_ar']);
    final en = asStr(m?['${base}_en']);
    return _ar ? en : ar;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  building blocks
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _hero() {
    if (_tab == 1) return const SizedBox.shrink(); // the legal panel draws its own cards
    if (_tab == 0) {
      return AppKpiGrid(maxColumns: 3, children: [
        AppKpiCard(icon: Icons.bar_chart_rounded, value: '${_stats.length}', label: t('إحصاءات', 'Stats')),
        AppKpiCard(icon: Icons.groups_rounded, value: '${_team.length}', label: t('الفريق', 'Team')),
        AppKpiCard(icon: Icons.alternate_email_rounded, value: '${_contacts.length}', label: t('قنوات التواصل', 'Contacts')),
      ]);
    }
    final active = _sections.where((e) => asBool(e['is_active'], true)).length;
    final version = asStr(_meta?['version']);
    return AppKpiGrid(maxColumns: 3, children: [
      if (version.isNotEmpty) AppKpiCard(icon: Icons.tag_rounded, value: version, label: t('الإصدار', 'Version')),
      AppKpiCard(icon: Icons.view_agenda_rounded, value: '${_sections.length}', label: t('الأقسام', 'Sections')),
      AppKpiCard(icon: Icons.visibility_rounded, value: '$active', label: t('ظاهرة', 'Visible')),
    ]);
  }

  Widget _tabs() => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: AppTabs(
          expand: true,
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
          items: [
            AppTabItem('content_tab_about'.tr, icon: Icons.info_outline_rounded),
            AppTabItem(t('الخصوصية والشروط', 'Privacy & terms'), icon: Icons.policy_rounded),
            AppTabItem(t('الشروط (الإصدارات القديمة)', 'Terms (older apps)'), icon: Icons.gavel_rounded),
          ],
        ),
      );

  Widget _pill({
    required String label,
    required IconData icon,
    required Color color,
    required bool on,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    final fg = on ? color : c.textLight;
    return Material(
      color: on ? color.withValues(alpha: 0.13) : c.inputBg,
      shape: StadiumBorder(side: BorderSide(color: on ? color.withValues(alpha: 0.5) : c.divider)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: AppSpace.xxs),
            Text(label,
                style: AppType.overline(context).copyWith(color: fg)),
          ]),
        ),
      ),
    );
  }

  /// Card that holds one editable list (header + add button + draggable rows).
  Widget _block({
    required IconData icon,
    required List<Color> colors,
    required String titleKey,
    required String hintKey,
    required String addKey,
    required VoidCallback onAdd,
    required String kind,
    required List<Map<String, dynamic>> items,
    required Widget Function(int index, Map<String, dynamic> row) row,
  }) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.block),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ServiceIcon(icon: icon, colors: colors, size: 40),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titleKey.tr, style: AppType.section(context)),
                  Text(trp('content_items_n', {'n': items.length}),
                      style: AppType.overline(context).copyWith(color: c.textLight)),
                ]),
              ),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(addKey.tr,
                    style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                ),
              ),
            ]),
            const SizedBox(height: AppSpace.sm),
            Text(hintKey.tr,
                style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w500, height: 1.5)),
            const SizedBox(height: AppSpace.sm),
            if (items.isEmpty)
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: onAdd,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.lg, horizontal: AppSpace.sm),
                  decoration: BoxDecoration(
                    color: c.inputBg,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: c.divider),
                  ),
                  child: Column(children: [
                    Icon(Icons.add_circle_outline_rounded, color: colors.last, size: 30),
                    const SizedBox(height: AppSpace.xs),
                    Text('content_empty_list'.tr,
                        textAlign: TextAlign.center,
                        style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
                  ]),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: items.length,
                onReorder: (a, b) => _reorder(kind, items, a, b),
                itemBuilder: (_, i) => row(i, items[i]),
              ),
          ]),
        ),
      ),
    );
  }

  /// One draggable row. [leading] is the icon / avatar / value badge.
  Widget _row({
    required String kind,
    required int index,
    required Map<String, dynamic> data,
    required Widget leading,
    required String title,
    String? subtitle,
    String? body,
    required String path,
    required String deleteKey,
    required VoidCallback onEdit,
    List<Widget> extraActions = const [],
  }) {
    final c = context.colors;
    final active = asBool(data['is_active'], true);
    return Container(
      key: ValueKey('$kind-${data['id']}'),
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onEdit,
          child: Opacity(
            opacity: active ? 1 : 0.62,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.xs, AppSpace.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  leading,
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.bodyStrong(context)),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w500)),
                      ],
                      if (body != null && body.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xxs),
                        Text(body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.meta(context).copyWith(color: c.textLight, fontWeight: FontWeight.w500, height: 1.45)),
                      ],
                    ]),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.xs),
                      child: Icon(Icons.drag_indicator_rounded, color: c.textLight),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpace.xs),
                Row(children: [
                  _pill(
                    label: active ? 'content_visible'.tr : 'content_hidden'.tr,
                    icon: active ? Icons.check_circle_rounded : Icons.visibility_off_rounded,
                    color: _pal(context).green.last,
                    on: active,
                    onTap: () => _toggleActive(path, data),
                  ),
                  const Spacer(),
                  ...extraActions,
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'btn_edit'.tr,
                    icon: Icon(Icons.edit_rounded, size: 20, color: c.textMedium),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'delete'.tr,
                    icon: Icon(Icons.delete_outline_rounded, size: 21, color: c.danger),
                    onPressed: () => _delete(path, data, deleteKey),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _networkImage(String url, double size, Widget fallback, {double radius = 16}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  About tab
  // ═══════════════════════════════════════════════════════════════════════════

  /// The splash footer ("Powered by Double Y" + its small logo) as the splash will show it, with its buttons.
  Widget _splashFooterBlock(Map<String, dynamic> info) {
    final c = context.colors;
    final line = _loc(info, 'splash_footer');
    final logo = asStr(info['splash_logo_url']);
    final uploading = _uploading == '/about/info/splash-logo';
    final empty = line.isEmpty && logo.isEmpty;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.vertical_align_bottom_rounded, size: 16, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text('content_splash_footer'.tr,
                style: AppType.meta(context).copyWith(color: c.primary, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text('content_splash_footer_hint'.tr,
            style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w500, height: 1.5)),
        const SizedBox(height: AppSpace.sm),
        if (empty && !uploading)
          Text('content_splash_footer_empty'.tr,
              style: AppType.label(context).copyWith(color: c.textLight, fontWeight: FontWeight.w600))
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (uploading)
              Icon(Icons.cloud_upload_rounded, size: 26, color: context.colors.primary)
            else if (logo.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96, maxHeight: 26),
                child: Image.network(logo, height: 26, fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(Icons.broken_image_rounded, size: 20, color: c.textLight)),
              ),
            if ((uploading || logo.isNotEmpty) && line.isNotEmpty) const SizedBox(width: AppSpace.xs),
            if (line.isNotEmpty)
              Flexible(
                child: Text(line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
              ),
          ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: 10, runSpacing: 8, children: [
          AppButton.secondary(
            label: 'content_upload_splash_logo'.tr,
            icon: Icons.add_photo_alternate_rounded,
            onPressed: uploading ? null : () => _pickImage('/about/info/splash-logo'),
          ),
          if (logo.isNotEmpty)
            TextButton.icon(
              onPressed: uploading
                  ? null
                  : () => _run(() => _api.delete('$_write/about/info/splash-logo'), ok: 'content_photo_removed'),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text('content_remove_splash_logo'.tr, style: TextStyle(fontFamily: AppFonts.family)),
            ),
        ]),
      ]),
    );
  }

  Widget _identityCard() {
    final c = context.colors;
    final info = _info;
    final logo = asStr(info?['logo_url']);
    final mission = _loc(info, 'mission');
    final uploading = _uploading == '/about/info/logo';

    final logoBox = Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.block),
        border: Border.all(color: c.divider),
      ),
      child: uploading
          ? Center(child: Icon(Icons.cloud_upload_rounded, size: 28, color: c.primary))
          : logo.isNotEmpty
          ? _networkImage(logo, 74, Icon(Icons.broken_image_rounded, color: c.textLight), radius: 22)
          : ServiceIcon(icon: Icons.school_rounded, colors: _pal(context).primary, size: 74),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.block),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ServiceIcon(icon: Icons.badge_rounded, colors: _pal(context).primary, size: 40),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text('content_identity'.tr,
                    style: AppType.section(context)),
              ),
            ]),
            const SizedBox(height: AppSpace.sm),
            Text('content_identity_hint'.tr,
                style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w500, height: 1.5)),
            const SizedBox(height: AppSpace.md),
            if (info == null)
              Text('content_not_set'.tr,
                  style: AppType.label(context).copyWith(color: c.textLight, fontWeight: FontWeight.w600))
            else ...[
              Row(children: [
                logoBox,
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_loc(info, 'name'),
                        style: AppType.section(context)),
                    if (_other(info, 'name').isNotEmpty)
                      Text(_other(info, 'name'),
                          style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w500)),
                    if (_loc(info, 'tagline').isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xs),
                      Text(_loc(info, 'tagline'),
                          style: AppType.meta(context).copyWith(color: c.primary, fontWeight: FontWeight.w600, height: 1.4)),
                    ],
                  ]),
                ),
              ]),
              if (mission.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: c.primary.withValues(alpha: 0.22)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.flag_rounded, size: 16, color: c.primary),
                      const SizedBox(width: AppSpace.xs),
                      Flexible(child: Text('content_mission'.tr,
                          style: AppType.meta(context).copyWith(color: c.primary, fontWeight: FontWeight.w600))),
                    ]),
                    const SizedBox(height: AppSpace.xs),
                    Text(mission,
                        style: AppType.label(context).copyWith(color: c.textDark, height: 1.6)),
                  ]),
                ),
              ],
              _splashFooterBlock(info),
            ],
            const SizedBox(height: AppSpace.md),
            Wrap(spacing: 10, runSpacing: 8, children: [
              AppButton.primary(
                label: 'btn_edit'.tr,
                icon: Icons.edit_rounded,
                onPressed: () => _form(_aboutCfg, item: info, path: '/about/info', single: true),
              ),
              AppButton.secondary(
                label: 'content_upload_logo'.tr,
                icon: Icons.add_photo_alternate_rounded,
                onPressed: uploading ? null : () => _pickImage('/about/info/logo'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  List<Widget> _aboutTab() {
    final c = context.colors;
    return [
      _identityCard(),

      // stats ----------------------------------------------------------------
      _block(
        icon: Icons.bar_chart_rounded,
        colors: _pal(context).green,
        titleKey: 'content_stats',
        hintKey: 'content_stats_hint',
        addKey: 'content_add',
        kind: 'stats',
        items: _stats,
        onAdd: () => _form(_statCfg, path: '/about/stats', nextOrder: _stats.length + 1),
        row: (i, s) => _row(
          kind: 'stats',
          index: i,
          data: s,
          path: '/about/stats',
          deleteKey: 'content_delete_stat',
          onEdit: () => _form(_statCfg, item: s, path: '/about/stats'),
          leading: Container(
            constraints: const BoxConstraints(minWidth: 60),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
            // the figure on the emerald block tint (a stat is "done / counted"), never a gradient wash
            decoration: BoxDecoration(color: c.blockEmerald, borderRadius: AppRadius.controlAll),
            child: Text(_loc(s, 'value'),
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: AppType.figure(context).copyWith(color: c.blockAccentInk(c.primary, c.blockEmerald))),
          ),
          title: _loc(s, 'label'),
          subtitle: _other(s, 'label'),
        ),
      ),

      // team -------------------------------------------------------------------
      _block(
        icon: Icons.groups_rounded,
        colors: _pal(context).purple,
        titleKey: 'content_team',
        hintKey: 'content_team_hint',
        addKey: 'content_add',
        kind: 'team',
        items: _team,
        onAdd: () => _form(_teamCfg, path: '/about/team', nextOrder: _team.length + 1),
        row: (i, m) {
          final photo = asStr(m['image_url']);
          final path = '/about/team/${m['id']}/image';
          final busy = _uploading == path;
          final emoji = asStr(m['emoji']);
          // the member's own emoji (content) or a person mark, on a faint tint (never a gradient wash)
          final tint = Color.alphaBlend(_pal(context).purple.last.withValues(alpha: 0.14), c.cardBg);
          final fallback = Container(
            width: AppTouch.min,
            height: AppTouch.min,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tint, borderRadius: AppRadius.controlAll),
            child: emoji.isNotEmpty
                ? Text(emoji, style: AppType.figureLarge(context))
                : Icon(Icons.person_rounded, color: c.blockAccentInk(_pal(context).purple.last, tint)),
          );
          return _row(
            kind: 'team',
            index: i,
            data: m,
            path: '/about/team',
            deleteKey: 'content_delete_member',
            onEdit: () => _form(_teamCfg, item: m, path: '/about/team'),
            leading: busy
                ? SizedBox(
                width: 50,
                height: 50,
                child: Center(child: Icon(Icons.cloud_upload_rounded, size: 26, color: c.primary)))
                : photo.isNotEmpty
                ? _networkImage(photo, 50, fallback)
                : fallback,
            title: _loc(m, 'name'),
            subtitle: _loc(m, 'role'),
            extraActions: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'content_upload_photo'.tr,
                icon: Icon(Icons.add_a_photo_rounded, size: 20, color: c.primary),
                onPressed: busy ? null : () => _pickImage(path),
              ),
              if (photo.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'content_remove_photo'.tr,
                  icon: Icon(Icons.hide_image_rounded, size: 20, color: c.textMedium),
                  onPressed: () => _removeTeamPhoto(m),
                ),
            ],
          );
        },
      ),

      // contacts ---------------------------------------------------------------
      _block(
        icon: Icons.alternate_email_rounded,
        colors: _pal(context).gold,
        titleKey: 'content_contacts',
        hintKey: 'content_contacts_hint',
        addKey: 'content_add',
        kind: 'contacts',
        items: _contacts,
        onAdd: () => _form(_contactCfg, path: '/about/contacts', nextOrder: _contacts.length + 1),
        row: (i, k) => _row(
          kind: 'contacts',
          index: i,
          data: k,
          path: '/about/contacts',
          deleteKey: 'content_delete_contact',
          onEdit: () => _form(_contactCfg, item: k, path: '/about/contacts'),
          leading: ServiceIcon(
              icon: contactIcon(k['type'] as String?), colors: _pal(context).gold, size: 46),
          title: _loc(k, 'label').isEmpty ? 'content_type_${asStr(k['type'])}'.tr : _loc(k, 'label'),
          subtitle: asStr(k['value']),
        ),
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Terms tab
  // ═══════════════════════════════════════════════════════════════════════════

  List<Widget> _termsTab() {
    final c = context.colors;
    final meta = _meta;
    final dateAr = asStr(meta?['last_updated_ar']);
    final dateEn = asStr(meta?['last_updated_en']);
    final date = _ar ? (dateAr.isEmpty ? dateEn : dateAr) : (dateEn.isEmpty ? dateAr : dateEn);

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: AppBanner(
          icon: Icons.history_rounded,
          color: c.warning,
          text: t('هذه الأقسام تقرؤها إصدارات التطبيق القديمة فقط. الشروط التي يراها المستخدمون الآن في تبويب «الخصوصية والشروط»، وحفظها هناك يستبدل هذه الأقسام.',
              'Only older app versions read these sections. The terms users see now are in the Privacy & terms tab, and saving them there replaces these sections.'),
          action: TextButton(onPressed: () => setState(() => _tab = 1), child: Text(t('فتح', 'Open'))),
        ),
      ),
      Container(
        margin: const EdgeInsets.only(bottom: AppSpace.md),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(AppRadius.block),
          border: Border.all(color: c.divider),
          boxShadow: c.cardShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ServiceIcon(icon: Icons.update_rounded, colors: _pal(context).gold, size: 40),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text('content_terms_version'.tr,
                      style: AppType.section(context)),
                ),
                IconButton(
                  tooltip: 'btn_edit'.tr,
                  icon: Icon(Icons.edit_rounded, color: c.primary),
                  onPressed: () => _form(_metaCfg, item: meta, path: '/terms/meta', single: true),
                ),
              ]),
              const SizedBox(height: AppSpace.sm),
              if (meta == null)
                Text('content_not_set'.tr,
                    style: AppType.label(context).copyWith(color: c.textLight, fontWeight: FontWeight.w600))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  StatusChip(trp('content_version_n', {'v': asStr(meta['version'], '—')}),
                      _pal(context).gold.last),
                  if (date.isNotEmpty) StatusChip(date, _pal(context).purple.last),
                ]),
            ]),
          ),
        ),
      ),
      _block(
        icon: Icons.view_agenda_rounded,
        colors: _pal(context).warm,
        titleKey: 'content_sections',
        hintKey: 'content_sections_hint',
        addKey: 'content_add',
        kind: 'sections',
        items: _sections,
        onAdd: () => _form(_sectionCfg, path: '/terms/sections', nextOrder: _sections.length + 1),
        row: (i, s) => _row(
          kind: 'sections',
          index: i,
          data: s,
          path: '/terms/sections',
          deleteKey: 'content_delete_section',
          onEdit: () => _form(_sectionCfg, item: s, path: '/terms/sections'),
          leading: ServiceIcon(
              icon: contentIcon(s['icon_name'] as String?),
              colors: _pal(context).all[asInt(s['id']) % _pal(context).all.length],
              size: 46),
          title: _loc(s, 'title'),
          subtitle: _other(s, 'title'),
          body: _loc(s, 'body'),
        ),
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>(); // whole page re-translates when the language changes

    Widget body;
    if (_loading) {
      body = const AppListSkeleton();
    } else if (_error != null) {
      body = cfgErrorState(_error, onRetry: _load);
    } else {
      body = AppRefresh(
        onRefresh: () => _load(silent: true),
        child: ListView(
          padding: AdminPage.bodyPadding(context),
          children: [
            _hero(),
            AppSpace.gapMd,
            _tabs(),
            if (_tab == 0) ..._aboutTab() else if (_tab == 1) const AdminLegalPanel() else ..._termsTab(),
          ],
        ),
      );
    }

    return AdminPage(
      title: t('من نحن والشروط', 'About & terms'),
      subtitle: 'content_page_title'.tr,
      icon: Icons.info_rounded,
      maxWidth: Breakpoints.contentMax,
      onRefresh: () => _load(silent: _info != null),
      body: body,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  form configuration
// ═════════════════════════════════════════════════════════════════════════════

class _FieldSpec {
  const _FieldSpec(this.key, this.labelKey, {this.ltr = false, this.lines = 1, this.required = false});

  final String key;
  final String labelKey;
  final bool ltr;
  final int lines;
  final bool required;
}

class _FormCfg {
  const _FormCfg({
    required this.newKey,
    required this.editKey,
    required this.fields,
    this.icons,
    this.defaultIcon = 'star',
    this.presets = const [],
    this.presetKeyAr,
    this.presetKeyEn,
    this.contactTypes = false,
    this.hasActive = true,
  });

  final String newKey, editKey;
  final List<_FieldSpec> fields;

  /// Show the icon picker (writes `icon_name`).
  final Map<String, IconData>? icons;
  final String defaultIcon;

  /// Quick-start chips: which two fields a preset fills.
  final List<_Preset> presets;
  final String? presetKeyAr, presetKeyEn;

  /// Show the contact-type picker (writes `type` + `icon_name`).
  final bool contactTypes;

  /// Show the visible/hidden switch.
  final bool hasActive;
}

const _aboutCfg = _FormCfg(
  newKey: 'content_edit_identity',
  editKey: 'content_edit_identity',
  hasActive: false,
  fields: [
    _FieldSpec('name_ar', 'content_f_name_ar', required: true),
    _FieldSpec('name_en', 'content_f_name_en', ltr: true),
    _FieldSpec('tagline_ar', 'content_f_tagline_ar'),
    _FieldSpec('tagline_en', 'content_f_tagline_en', ltr: true),
    _FieldSpec('mission_ar', 'content_f_mission_ar', lines: 4),
    _FieldSpec('mission_en', 'content_f_mission_en', lines: 4, ltr: true),
    _FieldSpec('splash_footer_ar', 'content_f_splash_footer_ar'),
    _FieldSpec('splash_footer_en', 'content_f_splash_footer_en', ltr: true),
  ],
);

const _statCfg = _FormCfg(
  newKey: 'content_new_stat',
  editKey: 'content_edit_stat',
  presets: _statPresets,
  presetKeyAr: 'label_ar',
  presetKeyEn: 'label_en',
  fields: [
    _FieldSpec('value_ar', 'content_f_value_ar', required: true),
    _FieldSpec('value_en', 'content_f_value_en', ltr: true),
    _FieldSpec('label_ar', 'content_f_label_ar', required: true),
    _FieldSpec('label_en', 'content_f_label_en', ltr: true),
  ],
);

const _teamCfg = _FormCfg(
  newKey: 'content_new_member',
  editKey: 'content_edit_member',
  fields: [
    _FieldSpec('name_ar', 'content_f_name_ar', required: true),
    _FieldSpec('name_en', 'content_f_name_en', ltr: true),
    _FieldSpec('role_ar', 'content_f_role_ar', required: true),
    _FieldSpec('role_en', 'content_f_role_en', ltr: true),
    _FieldSpec('emoji', 'content_f_emoji'),
  ],
);

const _contactCfg = _FormCfg(
  newKey: 'content_new_contact',
  editKey: 'content_edit_contact',
  contactTypes: true,
  fields: [
    _FieldSpec('value', 'content_f_value', ltr: true, required: true),
    _FieldSpec('label_ar', 'content_f_label_ar'),
    _FieldSpec('label_en', 'content_f_label_en', ltr: true),
  ],
);

const _metaCfg = _FormCfg(
  newKey: 'content_edit_version',
  editKey: 'content_edit_version',
  hasActive: false,
  fields: [
    _FieldSpec('version', 'content_f_version', ltr: true),
    _FieldSpec('last_updated_ar', 'content_f_updated_ar'),
    _FieldSpec('last_updated_en', 'content_f_updated_en', ltr: true),
  ],
);

const _sectionCfg = _FormCfg(
  newKey: 'content_new_section',
  editKey: 'content_edit_section',
  icons: kContentIcons,
  defaultIcon: 'description',
  presets: _termsPresets,
  presetKeyAr: 'title_ar',
  presetKeyEn: 'title_en',
  fields: [
    _FieldSpec('title_ar', 'content_f_title_ar', required: true),
    _FieldSpec('title_en', 'content_f_title_en', ltr: true),
    _FieldSpec('body_ar', 'content_f_body_ar', lines: 6, required: true),
    _FieldSpec('body_en', 'content_f_body_en', lines: 6, ltr: true),
  ],
);

// ═════════════════════════════════════════════════════════════════════════════
//  add / edit form (bottom sheet)
// ═════════════════════════════════════════════════════════════════════════════

/// Owns its controllers, so they are disposed only after the sheet's closing
/// animation. Pops with the request body, or null when dismissed.
class _EntityForm extends StatefulWidget {
  const _EntityForm({required this.cfg, this.item});

  final _FormCfg cfg;
  final Map<String, dynamic>? item;

  @override
  State<_EntityForm> createState() => _EntityFormState();
}

class _EntityFormState extends State<_EntityForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late String _icon;
  late String _type;
  late bool _active;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    final d = widget.item;
    _c = {
      for (final f in widget.cfg.fields) f.key: TextEditingController(text: asStr(d?[f.key])),
    };
    _icon = asStr(d?['icon_name'], widget.cfg.defaultIcon);
    if (!kContentIcons.containsKey(_icon)) _icon = widget.cfg.defaultIcon;
    _type = asStr(d?['type'], 'email');
    _active = asBool(d?['is_active'], true);
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  void _usePreset(_Preset p) => setState(() {
    final ka = widget.cfg.presetKeyAr, ke = widget.cfg.presetKeyEn;
    if (ka != null) _c[ka]?.text = p.ar;
    if (ke != null) _c[ke]?.text = p.en;
    if (widget.cfg.icons != null) _icon = p.icon;
  });

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final cfg = widget.cfg;
    // Optional fields are sent as '' (not null) so clearing a field really clears it
    // — the API ignores nulls on PATCH.
    final body = <String, dynamic>{
      for (final f in cfg.fields) f.key: _c[f.key]!.text.trim(),
      if (cfg.icons != null) 'icon_name': _icon,
      if (cfg.contactTypes) ...{'type': _type, 'icon_name': _type},
      if (cfg.hasActive) 'is_active': _active,
    };
    Navigator.pop(context, body);
  }

  Widget _label(String key) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.xs, top: AppSpace.xxs),
    child: Text(key.tr,
        style: AppType.meta(context).copyWith(color: context.colors.textMedium, fontWeight: FontWeight.w600)),
  );

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final cfg = widget.cfg;
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader((_isNew ? cfg.newKey : cfg.editKey).tr),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_isNew && cfg.presets.isNotEmpty) ...[
                _label('content_quick_start'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in cfg.presets)
                    ActionChip(
                      avatar: cfg.icons == null
                          ? null
                          : Icon(contentIcon(p.icon), size: 16, color: c.primary),
                      label: Text(ar ? p.ar : p.en,
                          style: AppType.meta(context)),
                      backgroundColor: c.inputBg,
                      side: BorderSide(color: c.divider),
                      onPressed: () => _usePreset(p),
                    ),
                ]),
                const SizedBox(height: AppSpace.md),
              ],
              if (cfg.contactTypes) ...[
                _label('content_contact_type'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in kContactTypes.entries)
                    ChoiceChip(
                      avatar: Icon(e.value, size: 16, color: _type == e.key ? c.primary : c.textMedium),
                      label: Text('content_type_${e.key}'.tr,
                          style: AppType.meta(context).copyWith(color: _type == e.key ? c.primary : c.textMedium, fontWeight: FontWeight.w600)),
                      selected: _type == e.key,
                      showCheckmark: false,
                      selectedColor: c.primary.withValues(alpha: 0.13),
                      backgroundColor: c.inputBg,
                      side: BorderSide(color: _type == e.key ? c.primary : c.divider),
                      onSelected: (_) => setState(() => _type = e.key),
                    ),
                ]),
                const SizedBox(height: AppSpace.md),
              ],
              for (final f in cfg.fields)
                Field(
                  controller: _c[f.key]!,
                  label: f.labelKey.tr,
                  ltr: f.ltr,
                  maxLines: f.lines,
                  validator: f.required
                      ? (v) => (v ?? '').trim().isEmpty ? 'content_required'.tr : null
                      : null,
                ),
              if (cfg.icons != null) ...[
                _label('content_icon'),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final e in cfg.icons!.entries)
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      onTap: () => setState(() => _icon = e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _icon == e.key ? c.primary.withValues(alpha: 0.12) : c.inputBg,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          border: Border.all(
                              color: _icon == e.key ? c.primary : c.divider,
                              width: _icon == e.key ? 2 : 1),
                        ),
                        child: Icon(e.value,
                            color: _icon == e.key ? c.primary : c.textMedium, size: 24),
                      ),
                    ),
                ]),
                const SizedBox(height: AppSpace.md),
              ],
              if (cfg.hasActive)
                PremiumSwitchRow(
                  icon: Icons.visibility_rounded,
                  title: 'content_visible'.tr,
                  subtitle: 'content_visible_hint'.tr,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              const SizedBox(height: AppSpace.xs),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                  ),
                  child: Text('save'.tr,
                      style: AppType.section(context).copyWith(color: c.onHero)),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
