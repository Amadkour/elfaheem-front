// lib/features/admin/admin_organizations_page.dart
//
// PLATFORM admins review organizations: Waiting · Approved · Needs changes · Suspended.
// Approve (optionally trusting a university to approve its own faculties), ask for changes with a note,
// suspend / reactivate, and create organization-admin accounts.        API: /api/v1/admin/orgs
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../org/org_common.dart' show openFileUrl, orgTypeIcons, orgTypeLabels;
import '../org/org_providers.dart';
import '../org/org_ui.dart';
import 'admin_common.dart';
import 'admin_list.dart';
import 'package:flutter_education_app/utils/widget/phone_field.dart';

const _base = '/api/v1/admin/orgs';

/// Badge for the admin hub: how many organizations wait for a decision.
class AdminOrgReviewCount extends ChangeNotifier {
  int pending = 0;

  Future<void> load() async {
    final r = await OrgApi.i.getMap('$_base/stats');
    pending = asInt(r?['pending']);
    notifyListeners();
  }
}

class AdminOrganizationsPage extends StatelessWidget {
  const AdminOrganizationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OrgPaged(_base, {'status': 'pending'})..refresh(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgPaged>();
        final c = context.colors;
        return BasePage(
          useWebCard: true,
          maxWith: 1000,
          appBar: ScreenAppBar(title: t('المؤسسات', 'Organizations'), actions: [
            IconButton(
              tooltip: t('حساب مدير مؤسسة', 'Org-admin account'),
              onPressed: () => _createOrgAdmin(context),
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ]),
          child: Column(children: [
            const SizedBox(height: 8),
            FilterChips<String>(
              options: {
                'pending': t('بانتظار المراجعة', 'Waiting'),
                'approved': t('معتمدة', 'Approved'),
                'rejected': t('تحتاج تعديل', 'Needs changes'),
                'suspended': t('موقوفة', 'Suspended'),
              },
              value: '${p.filters['status']}',
              onChanged: (v) => p.setFilter('status', v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SearchBox(hint: t('اسم المؤسسة أو رقم الترخيص', 'Name or licence number'), onChanged: p.setSearch),
            ),
            Expanded(
              child: PagedList<OrgPaged>(
                emptyText: p.filters['status'] == 'pending'
                    ? t('لا طلبات تنتظر — أحسنت 🎉', 'No applications waiting — well done 🎉')
                    : t('لا شيء هنا', 'Nothing here'),
                itemBuilder: (context, row) {
                  final creator = asMap(row['creator']);
                  final parent = asMap(row['parent']);
                  final col = hexColor(row['color'], c.primary);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
                    child: RowCard(
                      accent: row['status'] == 'pending' ? c.warning : null,
                      onTap: () => _openReview(context, asInt(row['id'])),
                      child: Row(children: [
                        IconBadge(orgTypeIcons[row['type']] ?? Icons.domain_rounded, col, size: 46),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(orgNameOf(row), style: orgText(context, w: FontWeight.w800)),
                            Text(
                                [
                                  orgTypeLabels()[row['type']] ?? '',
                                  if (parent.isNotEmpty) '${t('تابعة لـ', 'under')} ${orgNameOf(parent)}',
                                  if (creator.isNotEmpty) '${t('بواسطة', 'by')} ${creator['name']}',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: orgText(context, size: 12, color: c.textMedium)),
                            const SizedBox(height: 4),
                            Wrap(spacing: 6, children: [
                              StatusChip(statusLabel('${row['status']}'), statusColor(context, '${row['status']}')),
                              if (row['submitted_at'] != null) OrgPill(relTime(row['submitted_at']), color: c.textLight),
                              if (asMapList(row['documents']).isNotEmpty)
                                OrgPill(t('${asMapList(row['documents']).length} مستند', '${asMapList(row['documents']).length} docs'), icon: Icons.attach_file_rounded),
                            ]),
                          ]),
                        ),
                        Icon(Icons.chevron_right_rounded, color: c.textLight),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        );
      }),
    );
  }
}

Future<void> _openReview(BuildContext context, int id) async {
  final p = context.read<OrgPaged>();
  final d = await OrgApi.i.getMap('$_base/$id');
  if (d == null || !context.mounted) return;
  bool trustChildren = asMap(d['settings'])['child_approval'] == 'parent';
  bool busy = false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final status = '${d['status']}';
        final counts = asMap(d['counts']);
        Future<void> act(String action, {bool needNote = false}) async {
          String? note;
          if (needNote || action == 'approve') {
            note = await askText(ctx,
                title: switch (action) {
                  'reject' => t('ما الذي يحتاج تعديلاً؟', 'What needs to change?'),
                  'suspend' => t('سبب الإيقاف', 'Reason for suspension'),
                  _ => t('رسالة ترحيب (اختياري)', 'Welcome message (optional)'),
                },
                multiline: true);
            if (note == null) return;
            if (needNote && note.trim().isEmpty) {
              toast(t('اكتب السبب ليعرف المتقدم ما المطلوب', 'Write the reason so they know what to do'), error: true);
              return;
            }
          }
          set(() => busy = true);
          final r = await OrgApi.i.post('$_base/$id/$action', {
            'note': note,
            if (action == 'approve' && d['parent_id'] == null) 'child_approval': trustChildren ? 'parent' : 'platform',
          }, t('تم، وأُبلغ مدير المؤسسة', 'Done — the organization admin was notified'));
          if (!ctx.mounted) return;
          set(() => busy = false);
          if (r != null) {
            Navigator.pop(ctx);
            p.refresh();
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(orgNameOf(d)),
            Wrap(spacing: 6, children: [
              StatusChip(statusLabel(status), statusColor(ctx, status)),
              OrgPill(orgTypeLabels()[d['type']] ?? '${d['type']}'),
            ]),
            const SizedBox(height: 12),
            if ('${d['description'] ?? ''}'.isNotEmpty) Text('${d['description']}', style: orgText(ctx, color: c.textMedium)),
            const SizedBox(height: 8),
            KeyValue(t('رقم الترخيص', 'Licence no.'), '${d['license_no'] ?? ''}'),
            KeyValue(t('البريد', 'E-mail'), '${d['contact_email'] ?? ''}'),
            KeyValue(t('الهاتف', 'Phone'), '${d['contact_phone'] ?? ''}'),
            KeyValue(t('الموقع', 'Website'), '${d['website'] ?? ''}'),
            KeyValue(t('العنوان', 'Address'), '${d['address'] ?? ''}'),
            KeyValue(t('مقدم الطلب', 'Applicant'), '${asMap(d['creator'])['name'] ?? ''} ${asMap(d['creator'])['email'] ?? ''}'),
            if (asMap(d['parent']).isNotEmpty) KeyValue(t('المؤسسة الأم', 'Parent'), orgNameOf(asMap(d['parent']))),
            KeyValue(t('الحجم', 'Size'),
                t('${counts['members']} عضو · ${counts['departments']} إدارة · ${counts['sub_organizations']} فرع',
                    '${counts['members']} members · ${counts['departments']} departments · ${counts['sub_organizations']} branches')),
            for (final doc in asMapList(d['documents']))
              TextButton.icon(onPressed: () => openFileUrl('${doc['url']}'), icon: const Icon(Icons.description_rounded), label: Text('${doc['name']}')),
            if ('${d['review_note'] ?? ''}'.isNotEmpty) KeyValue(t('آخر ملاحظة', 'Last note'), '${d['review_note']}'),
            const Divider(height: 26),
            if (d['parent_id'] == null && status != 'rejected')
              OrgSwitchRow(
                title: t('الثقة بالمؤسسة لاعتماد فروعها', 'Trust it to approve its own branches'),
                subtitle: t('الكليات والأقسام التي ينشئها مديرها تعمل مباشرة دون مراجعة المنصة',
                    'Faculties and departments its admins create go live without platform review'),
                value: trustChildren,
                onChanged: (v) async {
                  set(() => trustChildren = v);
                  if (status == 'approved') {
                    await OrgApi.i.put('$_base/$id/policy', {'child_approval': v ? 'parent' : 'platform'}, t('تم', 'Done'));
                  }
                },
              ),
            const SizedBox(height: 8),
            if (status == 'pending') ...[
              PrimaryButton(isLoading: busy, background: c.success, label: t('اعتماد المؤسسة', 'Approve'),
                  icon: Icons.verified_rounded, iconBefore: true, onPressed: () => act('approve')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: c.warning,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: busy ? null : () => act('reject', needNote: true),
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(t('طلب تعديلات', 'Ask for changes'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
              ),
            ],
            if (status == 'approved')
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: c.danger,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: busy ? null : () => act('suspend', needNote: true),
                icon: const Icon(Icons.pause_circle_rounded),
                label: Text(t('إيقاف مؤقت', 'Suspend'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
              ),
            if (status == 'suspended')
              PrimaryButton(isLoading: busy, label: t('إعادة التفعيل', 'Reactivate'), icon: Icons.play_circle_rounded,
                  iconBefore: true, onPressed: () => act('reactivate')),
          ]),
        );
      }));
}

Future<void> _createOrgAdmin(BuildContext context) async {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  bool busy = false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('حساب مدير مؤسسة', 'Organization-admin account')),
            Text(t('يستطيع صاحب الحساب إنشاء جامعته أو كليته وإرسالها للمراجعة.', 'The account owner can create their university or faculty and send it for review.'),
                style: orgText(ctx, size: 12.5, color: ctx.colors.textMedium)),
            const SizedBox(height: 12),
            Field(controller: name, label: t('الاسم', 'Name')),
            Field(controller: email, label: t('البريد', 'E-mail'), ltr: true, keyboard: TextInputType.emailAddress),
            PhoneInputField(controller: phone, label: t('الهاتف (اختياري)', 'Phone (optional)')),   // same field as registration
            PrimaryButton(
              isLoading: busy,
              label: t('إنشاء الحساب', 'Create account'),
              onPressed: () async {
                set(() => busy = true);
                final r = await OrgApi.i.post('$_base/org-admins',
                    {'name': name.text.trim(), 'email': email.text.trim(), if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim()});
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (r is Map) {
                  Navigator.pop(ctx);
                  if (r['generated_password'] != null && context.mounted) {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(t('بيانات الدخول (تظهر مرة واحدة)', 'Login details (shown once)')),
                        content: SelectableText('${r['email']}\n${r['generated_password']}', textDirection: TextDirection.ltr),
                      ),
                    );
                  } else {
                    toast(t('الحساب موجود وجاهز', 'The account exists and is ready'));
                  }
                }
              },
            ),
          ]),
        );
      }));
}
