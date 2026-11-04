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
import 'package:flutter_education_app/design/app_states.dart' show AppErrorState, appErrorMessage;
import 'package:flutter_education_app/design/app_tokens.dart';

import '../admin/admin_common.dart';
import 'org_common.dart';
import 'org_providers.dart' show orgBase;
import 'org_member_pages.dart' show OrgHomeEntry;
import 'org_member_space.dart' show OrgFormFillScreen;
import 'org_terms_pages.dart' show TermCard;
import 'org_ui.dart';
import 'org_availability_pages.dart' show AvailabilityRequestScreen;
import 'org_academic_pages.dart' show MyAcademicPathPage;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import '../admin/admin_list.dart' show IconBadge;

class HomeOrgMix extends StatefulWidget {
  const HomeOrgMix({super.key});

  @override
  State<HomeOrgMix> createState() => _HomeOrgMixState();
}

class _HomeOrgMixState extends State<HomeOrgMix> {
  static bool _requiredShown = false;   // once per app session
  static bool _blockingOpen = false;
  Map<String, dynamic>? _mix;
  Object? _error; // the load failed and nothing is on screen yet: a compact Retry instead of a vanished block

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
      setState(() {
        _mix = mix;
        _error = null;
      });
      // (organization news now lives on the organization's own home tab — no feed call here)
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
    } catch (e) {
      if (mounted && _mix == null) setState(() => _error = e);
    }
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
                icon: r['kind'] == 'form' ? Icons.edit_document : (r['kind'] == 'department_choice' ? Icons.how_to_vote_rounded : Icons.gavel_rounded),
                color: c.warning,
                title: '${r['title']}',
                subtitle: r['kind'] == 'form' ? t('نموذج إلزامي', 'Mandatory form')
                    : (r['kind'] == 'department_choice' ? t('اختر قسمك العلمي', 'Choose your department') : t('لائحة تحتاج موافقتك', 'Needs your agreement')),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (r['kind'] == 'platform') {
                    await showPlatformRequirement(context, r);
                  } else if (r['kind'] == 'department_choice') {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BasePage(useWebCard: true, maxWith: 760,
                        appBar: ScreenAppBar(title: t('مساري الأكاديمي', 'My academic path')), child: MyAcademicPathPage(orgId: asInt(r['org_id'])))));
                  } else if (r['kind'] == 'form') {
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
    // "Needs your action" lives in ONE place: the unified inbox entry (InboxEntry) above this block.
    // Here only the "join your university" entry for people outside any organization; the organization itself
    // lives in its own home tab.
    if (m == null && _error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: AppErrorState(
            compact: true,
            message: appErrorMessage(_error),
            onRetry: () {
              setState(() => _error = null);
              _load();
            }),
      );
    }
    if (m == null || weight <= 10) return const OrgHomeEntry();
    return const SizedBox.shrink();
  }
}


/// A requirement from the platform: read it, then "I agree" (ack) or "Got it" (info).
Future<void> showPlatformRequirement(BuildContext context, Map<String, dynamic> r) async {
  await showAdminSheet<void>(context, (ctx) {
    final c = ctx.colors;
    final ack = r['ack_kind'] != 'info';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBadge(ack ? Icons.fact_check_rounded : Icons.info_rounded, ack ? c.warning : c.primary, size: 46),
          const SizedBox(width: 12),
          Expanded(child: Text('${r['title']}', style: orgText(ctx, size: 17, w: FontWeight.w800))),
        ]),
        if ('${r['body'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Text('${r['body']}', style: orgText(ctx, color: c.textMedium))),
        if ('${r['link_url'] ?? ''}'.isNotEmpty)
          TextButton.icon(onPressed: () => openFileUrl('${r['link_url']}'), icon: const Icon(Icons.open_in_new_rounded), label: Text(t('فتح الرابط', 'Open the link'))),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () async {
            try {
              await ApiClient().post('/api/v1/requirements/${r['id']}/ack');
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (_) {}
          },
          icon: Icon(ack ? Icons.check_rounded : Icons.thumb_up_alt_rounded),
          label: Text(ack ? t('قرأت وأوافق', 'I have read and agree') : t('تم الاطلاع', 'Got it')),
        ),
      ]),
    );
  });
}
