// lib/features/admin/admin_parent_requests_page.dart
// Admin / super-admin: parent ⇄ student link requests — list, filters, detail with the answers and the
// attached documents, approve / reject (the decision, its author and the note are recorded server-side).
// Documents are private: each "open" asks the server for a 5-minute signed link.
// Needs: url_launcher (to open PDFs).
//
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminParentRequestsPage()));
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../parent/parent_link_providers.dart';
import '../parent/parent_widgets.dart';

class AdminParentRequestsPage extends StatelessWidget {
  const AdminParentRequestsPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AdminParentLinkProvider()..loadRequests(),
        child: const _List(),
      );
}

class _List extends StatefulWidget {
  const _List();

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  /// 1 s after the last keystroke (or Enter) → one request.
  void _runSearch(String v) {
    final p = context.read<AdminParentLinkProvider>();
    if (p.search == v.trim()) return;
    p.search = v.trim();
    p.loadRequests();
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        context.read<AdminParentLinkProvider>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminParentLinkProvider>();
    final c = context.colors;
    return BasePage(
      useWebCard: true,
maxWith: 1100,
      appBar: ScreenAppBar(title: 'pl_requests_title'.tr),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'pl_search_hint'.tr,
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              isDense: true,
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(seconds: 1), () {
                if (mounted) _runSearch(v);
              });
            },
            onSubmitted: (v) {
              _debounce?.cancel();
              _runSearch(v);
            },
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final s in ['pending', 'approved', 'rejected', 'failed', 'cancelled', ''])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text(s.isEmpty ? 'pl_all'.tr : '${'pl_status_$s'.tr}${s == 'pending' && p.pendingTotal > 0 ? ' (${p.pendingTotal})' : ''}'),
                    selected: p.status == s,
                    onSelected: (_) => p.setFilter(status: s),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: p.isLoading && p.items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : p.hasError && p.items.isEmpty
                  ? PlError(p.errorMessage ?? '', onRetry: p.loadRequests)
                  : p.items.isEmpty
                      ? PlEmpty('pl_no_requests'.tr)
                      : RefreshIndicator(
                          onRefresh: p.loadRequests,
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(16),
                            itemCount: p.items.length + (p.page < p.pages ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i >= p.items.length) {
                                return const Padding(
                                    padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                              }
                              final r = p.items[i];
                              return PlCard(
                                onTap: () async {
                                  await Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => ChangeNotifierProvider.value(
                                        value: p, child: _Detail(id: r['id'] as int)),
                                  ));
                                },
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text('${r['parent_name']}  →  ${r['student_name']}',
                                            style: c.h2.copyWith(fontSize: 15))),
                                    PlStatusChip('${r['status']}'),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${'pl_mode_${r['mode']}'.tr} · ${plDateTime(r['created_at'])}'
                                      '${(r['documents_count'] ?? 0) > 0 ? ' · 📎 ${r['documents_count']}' : ''}',
                                      style: c.caption),
                                ]),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
class _Detail extends StatefulWidget {
  const _Detail({required this.id});

  final int id;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  Map<String, dynamic>? _d;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final p = context.read<AdminParentLinkProvider>();
    final d = await p.detail(widget.id);
    if (!mounted) return;
    if (d == null) plToast(p.errorMessage);
    setState(() => _d = d);
  }

  Future<void> _decide(bool approve) async {
    final note = await plAskText(context, approve ? 'pl_approve'.tr : 'pl_reject'.tr,
        hint: approve ? 'pl_note_optional'.tr : 'pl_reject_reason'.tr, required: !approve);
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    final p = context.read<AdminParentLinkProvider>();
    final r = await p.decide(widget.id, approve: approve, note: note);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) _d = r;
    });
    plToast(r == null ? p.errorMessage : 'pl_decision_saved'.tr);
  }

  Future<void> _openDoc(Map<String, dynamic> doc) async {
    final p = context.read<AdminParentLinkProvider>();
    final link = await p.documentLink(doc['id'] as int);
    if (link == null || !mounted) {
      plToast(p.errorMessage);
      return;
    }
    final url = p.absoluteUrl('${link['path']}');
    if (doc['file_type'] == 'pdf') {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Padding(
                    padding: const EdgeInsets.all(32), child: Text('pl_file_load_failed'.tr))),
          ),
          PositionedDirectional(
              top: 4, end: 4, child: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx))),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: context.colors.caption)),
          Expanded(child: SelectableText(v.isEmpty ? '—' : v)),
        ]),
      );

  Widget _person(String title, Map m) => PlCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: context.colors.h2.copyWith(fontSize: 14)),
          const SizedBox(height: 6),
          _kv('pl_name'.tr, '${m['name'] ?? ''}'),
          _kv('E-mail', '${m['email'] ?? ''}'),
          _kv('pl_phone'.tr, '${m['phone'] ?? ''}'),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = _d;
    return BasePage(
      appBar: ScreenAppBar(title: 'pl_request_details'.tr),
      child: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                PlStatusChip('${d['status']}'),
                const SizedBox(width: 10),
                Text('${'pl_mode_${d['mode']}'.tr} · ${plDateTime(d['created_at'])}', style: c.caption),
              ]),
              const SizedBox(height: 12),
              _person('pl_parent'.tr, d['parent'] as Map? ?? {}),
              _person('pl_student'.tr, d['student'] as Map? ?? {}),
              if ((d['answers'] as List).isNotEmpty)
                PlCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('pl_answers'.tr, style: c.h2.copyWith(fontSize: 14)),
                    const SizedBox(height: 6),
                    for (final a in plList(d['answers'])) _kv(plLabel(a), '${a['value']}'),
                  ]),
                ),
              if ((d['documents'] as List).isNotEmpty)
                PlCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('pl_documents'.tr, style: c.h2.copyWith(fontSize: 14)),
                    for (final x in plList(d['documents']))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(x['file_type'] == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                            color: c.primary),
                        title: Text(plLabel(x)),
                        subtitle: Text('${x['file_name'] ?? ''} · ${((x['file_size'] as num?) ?? 0) ~/ 1024} KB'),
                        trailing: const Icon(Icons.open_in_new_rounded),
                        onTap: () => _openDoc(x),
                      ),
                  ]),
                ),
              if (d['verification_result'] != null)
                PlCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('pl_verification'.tr, style: c.h2.copyWith(fontSize: 14)),
                    const SizedBox(height: 6),
                    _kv('pl_verified'.tr, (d['verification_result'] as Map)['verified'] == true ? '✔' : '✘'),
                    _kv('pl_reason'.tr, '${(d['verification_result'] as Map)['reason']}'),
                    _kv('HTTP', '${(d['verification_result'] as Map)['http_status'] ?? '—'}'),
                  ]),
                ),
              if (d['status'] != 'pending' && d['reviewed_at'] != null)
                PlCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('pl_decision'.tr, style: c.h2.copyWith(fontSize: 14)),
                    const SizedBox(height: 6),
                    _kv('pl_by'.tr, '${d['reviewer_name'] ?? '—'}'),
                    _kv('pl_at'.tr, plDateTime(d['reviewed_at'])),
                    _kv('pl_admin_note'.tr, '${d['decision_note'] ?? ''}'),
                  ]),
                ),
              if (d['status'] == 'pending') ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                      icon: const Icon(Icons.close_rounded),
                      label: Text('pl_reject'.tr),
                      onPressed: _busy ? null : () => _decide(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check_rounded),
                      label: Text('pl_approve'.tr),
                      onPressed: _busy ? null : () => _decide(true),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 24),
            ]),
    );
  }
}
