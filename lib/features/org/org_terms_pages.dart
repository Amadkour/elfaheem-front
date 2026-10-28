// lib/features/org/org_terms_pages.dart
//
//   OrgTermsAdminPage   staff (module `terms`): titled paragraphs, images or documents — per audience, optional
//                       "must acknowledge", ordered, active / hidden, who acknowledged
//   OrgTermsView        members: the terms that apply to them, image preview, open documents, "I agree"
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_providers.dart';
import 'org_ui.dart';
import 'package:flutter_education_app/design/app_refresh.dart';

Map<String, String> _kinds() => {'text': t('نص', 'Text'), 'image': t('صورة', 'Image'), 'document': t('مستند', 'Document')};
const _kindIcons = {'text': Icons.article_rounded, 'image': Icons.image_rounded, 'document': Icons.description_rounded};

class OrgTermsAdminPage extends StatefulWidget {
  const OrgTermsAdminPage({super.key});

  @override
  State<OrgTermsAdminPage> createState() => _OrgTermsAdminPageState();
}

class _OrgTermsAdminPageState extends State<OrgTermsAdminPage> {
  List<Map<String, dynamic>>? _items;
  bool _failed = false;

  String get _base => '${context.read<OrgSession>().base}/terms';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap(_base);
    if (!mounted) return;
    setState(() {
      _items = r == null ? _items : asMapList(r['items']);
      _failed = r == null && _items == null;
    });
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final s = context.read<OrgSession>();
    String kind = '${item?['kind'] ?? 'text'}';
    final title = TextEditingController(text: '${item?['title'] ?? ''}');
    final body = TextEditingController(text: '${item?['body'] ?? ''}');
    String? fileUrl = item?['file_url'] as String?, fileName = item?['file_name'] as String?;
    Map<String, dynamic> audience = asMap(item?['audience']).isEmpty ? {'roles': <String>[], 'sub_orgs': true} : asMap(item?['audience']);
    bool ack = item?['requires_ack'] == true, active = item?['is_active'] != false, busy = false;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(item == null ? t('بند جديد', 'New item') : t('تعديل البند', 'Edit item')),
              ChoiceRow<String>(label: t('النوع', 'Type'), options: _kinds(), value: kind, onChanged: (v) => set(() => kind = v)),
              Field(controller: title, label: t('العنوان — مثلاً: لائحة الحضور والغياب', 'Title — e.g. Attendance policy')),
              if (kind == 'text') Field(controller: body, label: t('نص البند', 'Text'), maxLines: 8),
              if (kind != 'text') ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    final f = await orgPickAndUpload('${s.base}/uploads',
                        extensions: kind == 'image' ? const ['png', 'jpg', 'jpeg', 'webp'] : null,
                        context: ctx, cropShape: CropShape.wide);
                    if (f != null) set(() {
                      fileUrl = '${f['url']}';
                      fileName = '${f['name']}';
                    });
                  },
                  icon: Icon(fileUrl == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
                      color: fileUrl == null ? null : c.success),
                  label: Text(fileUrl == null ? (kind == 'image' ? t('رفع صورة', 'Upload image') : t('رفع مستند', 'Upload document')) : '${fileName ?? ''}'),
                ),
                const SizedBox(height: 8),
                Field(controller: body, label: t('وصف قصير (اختياري)', 'Short description (optional)'), maxLines: 3),
              ],
              OrgAudiencePicker(value: audience, onChanged: (v) => set(() => audience = v)),
              OrgSwitchRow(
                  title: t('يجب الموافقة عليه', 'Must be acknowledged'),
                  subtitle: t('يظهر على الرئيسية للأعضاء حتى يضغطوا "أوافق" — ويُطلب مجدداً عند تعديل النص',
                      'Shows on members\' home until they tap "I agree" — asked again when the wording changes'),
                  value: ack,
                  onChanged: (v) => set(() => ack = v)),
              OrgSwitchRow(title: t('ظاهر للأعضاء', 'Visible to members'), value: active, onChanged: (v) => set(() => active = v)),
              const SizedBox(height: 8),
              PrimaryButton(
                isLoading: busy,
                label: t('حفظ', 'Save'),
                onPressed: () async {
                  set(() => busy = true);
                  final b = {'kind': kind, 'title': title.text.trim(), 'body': body.text.trim(), 'file_url': fileUrl,
                    'file_name': fileName, 'audience': audience, 'requires_ack': ack, 'is_active': active};
                  final r = item == null ? await OrgApi.i.post(_base, b, t('أُضيف البند', 'Added')) : await OrgApi.i.put('$_base/${item['id']}', b, t('تم الحفظ', 'Saved'));
                  if (!ctx.mounted) return;
                  set(() => busy = false);
                  if (r != null) Navigator.pop(ctx);
                },
              ),
            ]),
          );
        }));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final items = _items;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: s.can('terms', 'insert')
          ? FloatingActionButton.extended(
              heroTag: 'terms_new', onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: Text(t('بند جديد', 'New item')))
          : null,
      body: OrgAsync(
        loading: items == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: items == null
            ? const SizedBox.shrink()
            : items.isEmpty
                ? OrgEmpty(icon: Icons.gavel_rounded, title: t('لا لوائح بعد', 'No regulations yet'),
                    message: t('أضف لوائح المؤسسة نصاً أو صورة أو مستنداً، وحدّد من يراها.', 'Add your rules as text, images or documents and choose who sees each.'),
                    actionLabel: s.can('terms', 'insert') ? t('إضافة أول بند', 'Add the first item') : null, onAction: () => _edit())
                : ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 100), children: [
                    for (final it in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: RowCard(
                          accent: it['is_active'] == false ? c.textLight : null,
                          onTap: s.can('terms', 'update') ? () => _edit(it) : null,
                          child: Row(children: [
                            IconBadge(_kindIcons['${it['kind']}'] ?? Icons.article_rounded, c.primary, size: 42),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${it['title']}', style: orgText(context, w: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  OrgPill(_kinds()['${it['kind']}'] ?? ''),
                                  if (it['requires_ack'] == true)
                                    OrgPill(t('${it['ack_count']} وافقوا', '${it['ack_count']} agreed'), icon: Icons.verified_rounded, color: c.success),
                                  if (it['is_active'] == false) OrgPill(t('مخفي', 'Hidden'), color: c.textLight),
                                ]),
                              ]),
                            ),
                            if (s.can('terms', 'delete'))
                              IconButton(tooltip: t('حذف', 'Delete'), 
                                icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                                onPressed: () async {
                                  if (await confirm(context, message: t('حذف البند؟', 'Delete this item?'), danger: true) &&
                                      await OrgApi.i.del('$_base/${it['id']}', t('تم الحذف', 'Deleted')) != null) {
                                    _load();
                                  }
                                },
                              ),
                          ]),
                        ),
                      ),
                  ]),
      ),
    );
  }
}

/// Member side: the terms that apply to me, with "I agree" where required.
class OrgTermsView extends StatefulWidget {
  const OrgTermsView({super.key, required this.orgId});
  final int orgId;

  @override
  State<OrgTermsView> createState() => _OrgTermsViewState();
}

class _OrgTermsViewState extends State<OrgTermsView> {
  List<Map<String, dynamic>>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap('$orgBase/public/${widget.orgId}/terms');
    if (!mounted) return;
    setState(() {
      _items = r == null ? _items : asMapList(r['items']);
      _failed = r == null && _items == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return OrgAsync(
      loading: items == null && !_failed,
      failed: _failed,
      onRetry: _load,
      child: items == null
          ? const SizedBox.shrink()
          : items.isEmpty
              ? OrgEmpty(icon: Icons.gavel_rounded, title: t('لا لوائح منشورة', 'No regulations published'))
              : AppRefresh(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 40), children: [
                    for (final it in items) TermCard(item: it, onAcked: _load),
                  ]),
                ),
    );
  }
}

class TermCard extends StatelessWidget {
  const TermCard({super.key, required this.item, this.onAcked});
  final Map<String, dynamic> item;
  final VoidCallback? onAcked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kind = '${item['kind']}';
    final needAck = item['requires_ack'] == true && item['acked'] != true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: needAck ? c.warning.withValues(alpha: 0.5) : c.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (kind == 'image' && '${item['file_url'] ?? ''}'.isNotEmpty)
          GestureDetector(
            onTap: () => openFileUrl('${item['file_url']}'),
            child: Image.network(orgFileUrl('${item['file_url']}'), width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(height: 0)),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBadge(_kindIcons[kind] ?? Icons.article_rounded, c.primary, size: 36),
              const SizedBox(width: 10),
              Expanded(child: Text('${item['title']}', style: orgText(context, size: 15, w: FontWeight.w800))),
              if (item['acked'] == true) OrgPill(t('وافقت', 'Agreed'), icon: Icons.verified_rounded, color: c.success),
            ]),
            if ('${item['body'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('${item['body']}', style: orgText(context, color: c.textMedium)),
            ],
            if (kind == 'document')
              TextButton.icon(
                onPressed: () => openFileUrl('${item['file_url']}'),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text('${item['file_name'] ?? t('فتح المستند', 'Open document')}'),
              ),
            if (needAck) ...[
              const SizedBox(height: 10),
              PrimaryButton(
                isLoading: false,
                label: t('قرأت وأوافق', 'I have read and agree'),
                icon: Icons.check_rounded,
                iconBefore: true,
                onPressed: () async {
                  if (await OrgApi.i.post('$orgBase/public/terms/${item['id']}/ack', null, t('شكراً لك 🌿', 'Thank you 🌿')) != null) onAcked?.call();
                },
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
