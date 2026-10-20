// lib/features/org/home_org_mix.dart
//
// The organization part of the student / teacher home, sized by GET /api/v1/home/mix:
//   org_weight 10  not in any organization          → the slim "join your university" card only
//   org_weight 50  organization + independent courses → organizations card + 2 latest news
//   org_weight 70  organization only                  → a full block: each organization, 3 news, quick actions
// "required" items (mandatory forms, terms to accept) open in a sheet by themselves — once per app session.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../admin/admin_common.dart';
import 'org_common.dart';
import 'org_providers.dart' show orgBase;
import 'org_member_pages.dart' show OrgHomeEntry;
import 'org_member_space.dart' show OrgFormFillScreen, OrgMemberSpace;
import 'org_terms_pages.dart' show TermCard;
import 'org_ui.dart';
import 'org_availability_pages.dart' show AvailabilityRequestScreen;

class HomeOrgMix extends StatefulWidget {
  const HomeOrgMix({super.key});

  @override
  State<HomeOrgMix> createState() => _HomeOrgMixState();
}

class _HomeOrgMixState extends State<HomeOrgMix> {
  static bool _requiredShown = false;   // once per app session
  static bool _blockingOpen = false;
  Map<String, dynamic>? _mix;
  List<Map<String, dynamic>> _news = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient().get('/api/v1/home/mix');
      if (!mounted || r is! Map) return;
      final mix = Map<String, dynamic>.from(r);
      setState(() => _mix = mix);
      if (asInt(mix['org_weight']) >= 50) {
        final f = await ApiClient().get('/api/v1/org/public/me/feed', queryParams: {'size': 3});
        if (mounted && f is Map) setState(() => _news = asMapList(f['items']));
      }
      final req = asMapList(mix['required']);
      // BLOCKING: availability requests open as a frozen screen until submitted (every time, not once per session)
      final block = req.where((x) => x['kind'] == 'availability').toList();
      if (block.isNotEmpty && !_blockingOpen && mounted) {
        _blockingOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          for (final b in block) {
            if (!mounted) break;
            await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => AvailabilityRequestScreen(requestId: asInt(b['id']))));
          }
          _blockingOpen = false;
          _load();
        });
        return;
      }
      req.removeWhere((x) => x['kind'] == 'availability');
      if (req.isNotEmpty && !_requiredShown && mounted) {
        _requiredShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _showRequired(req));
      }
    } catch (_) {}
  }

  Future<void> _showRequired(List<Map<String, dynamic>> req) async {
    await showAdminSheet<void>(context, (ctx) {
      final c = ctx.colors;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SheetHeader(t('مطلوب منك', 'Needs your action')),
          Text(t('مؤسستك تحتاج منك هذه الخطوات — دقيقة واحدة وتنتهي 🌿', 'Your institution needs these from you — it takes a minute 🌿'),
              style: orgText(ctx, color: c.textMedium)),
          const SizedBox(height: 12),
          for (final r in req)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OrgActionCard(
                icon: r['kind'] == 'form' ? Icons.edit_document : Icons.gavel_rounded,
                color: c.warning,
                title: '${r['title']}',
                subtitle: r['kind'] == 'form' ? t('نموذج إلزامي', 'Mandatory form') : t('لائحة تحتاج موافقتك', 'Needs your agreement'),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (r['kind'] == 'form') {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgFormFillScreen(formId: asInt(r['id']))));
                  } else {
                    final t0 = await ApiClient().get('$orgBase/public/${r['org_id']}/terms');
                    final item = asMapList((t0 as Map)['items']).where((x) => x['id'] == r['id']).toList();
                    if (item.isNotEmpty && mounted) {
                      await showAdminSheet<void>(context, (c2) => SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          child: TermCard(item: item.first, onAcked: () => Navigator.pop(c2))));
                    }
                  }
                  _requiredShown = false;
                  _load();
                },
              ),
            ),
        ]),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = _mix;
    final weight = asInt(m?['org_weight']);
    if (m == null || weight <= 10) return const OrgHomeEntry();
    final c = context.colors;
    final orgs = asMapList(m['organizations']);
    final req = asMapList(m['required']);
    final full = weight >= 70;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (req.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OrgActionCard(icon: Icons.notification_important_rounded, color: c.warning, badge: req.length,
              title: t('مطلوب منك', 'Needs your action'), subtitle: '${req.first['title']}', onTap: () => _showRequired(req)),
        ),
      for (final o in orgs.take(full ? 3 : 1))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OrgActionCard(
            icon: orgTypeIcons[o['type']] ?? Icons.account_balance_rounded,
            color: orgColor(context, o),
            title: orgNameOf(o),
            subtitle: t('الأخبار · الإدارات · طلباتي · الشكاوى · اللوائح', 'News · departments · requests · complaints · rules'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgMemberSpace(org: o))),
          ),
        ),
      for (final n in _news.take(full ? 3 : 2))
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.divider)),
          child: Row(children: [
            Icon(Icons.campaign_rounded, color: c.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${n['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
                Text('${orgNameOf(asMap(n['organization']))} · ${relTime(n['publish_at'])}', style: orgText(context, size: 11.5, color: c.textLight)),
              ]),
            ),
          ]),
        ),
      if (full) const OrgHomeEntry(),
    ]);
  }
}
