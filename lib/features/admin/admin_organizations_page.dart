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
import 'package:flutter_education_app/design/app_inputs.dart';

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
              tooltip: t('مديرو المؤسسات', 'Organization admins'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminOrgAdminsPage())),
              icon: const Icon(Icons.manage_accounts_rounded),
            ),
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
  bool sharingOn = asMap(asMap(d['settings'])['sharing'])['enabled'] != false;
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
            if (d['parent_id'] == null && status == 'approved')
              OrgSwitchRow(
                key: const ValueKey('org.sharing'),
                title: t('مشاركة البيانات مع المؤسسات الأخرى', 'Data sharing with other organizations'),
                subtitle: t('إيقافها يمنع هذه المؤسسة من عرض أي مشاركة أو التحقق من خريجيها', 'Off: this organization cannot offer shares or answer graduate verification'),
                value: sharingOn,
                onChanged: (v) async {
                  set(() => sharingOn = v);
                  await OrgApi.i.put('$_base/$id/sharing', {'enabled': v}, t('تم', 'Done'));
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
            const SizedBox(height: 10),
            // who pays what in this organization (staff · admins · students; plans & prices)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => _billingSheet(ctx, asInt(d['id']), orgNameOf(d)),
              icon: const Icon(Icons.payments_rounded),
              label: Text(t('رسوم العضوية', 'Membership fees'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      }));
}

Future<void> _createOrgAdmin(BuildContext context) async {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  bool busy = false, verify = true;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('حساب مدير مؤسسة', 'Organization-admin account')),
            Text(t('يستطيع صاحب الحساب إنشاء جامعته أو كليته وإرسالها للمراجعة.', 'The account owner can create their university or faculty and send it for review.'),
                style: orgText(ctx, size: 12.5, color: ctx.colors.textMedium)),
            const SizedBox(height: 12),
            Field(controller: name, label: t('الاسم', 'Name')),
            AppEmailField(controller: email, label: t('البريد', 'E-mail')),
            PhoneInputField(controller: phone, label: t('الهاتف (اختياري)', 'Phone (optional)')),   // same field as registration
            OrgSwitchRow(
              title: t('تأكيد البريد الإلكتروني', 'Verify the e-mail'),
              subtitle: t('نرسل رمزاً للبريد ويؤكّده المدير عند أول دخول', 'We e-mail a code; the admin confirms it at first sign-in'),
              value: verify,
              onChanged: (v) => set(() => verify = v),
            ),
            const SizedBox(height: 6),
            PrimaryButton(
              isLoading: busy,
              label: t('إنشاء الحساب', 'Create account'),
              onPressed: () async {
                set(() => busy = true);
                final r = await OrgApi.i.post('$_base/org-admins',
                    {'name': name.text.trim(), 'email': email.text.trim(), 'send_verification': verify,
                      if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim()});
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

// ═════════════════════════════════════════════════════════════════════════════
//  Organization admins — the platform manages the people who run organizations
// ═════════════════════════════════════════════════════════════════════════════

class AdminOrgAdminsPage extends StatelessWidget {
  const AdminOrgAdminsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('$_base/org-admins')..refresh(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgPaged>();
        final c = context.colors;
        return BasePage(
          useWebCard: true,
          maxWith: 900,
          appBar: ScreenAppBar(title: t('مديرو المؤسسات', 'Organization admins'), actions: [
            IconButton(
              tooltip: t('حساب جديد', 'New account'),
              onPressed: () async {
                await _createOrgAdmin(context);
                p.refresh();
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ]),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: SearchBox(hint: t('الاسم أو البريد أو الهاتف', 'Name, e-mail or phone'), onChanged: p.setSearch),
            ),
            Expanded(
              child: PagedList<OrgPaged>(
                emptyText: t('لا يوجد مديرو مؤسسات بعد', 'No organization admins yet'),
                itemBuilder: (context, row) {
                  final verified = row['email_verified'] == true;
                  final active = row['is_active'] != false;
                  final orgs = asMapList(row['organizations']);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
                    child: RowCard(
                      accent: active ? null : c.danger,
                      onTap: () => _manageOrgAdmin(context, row),
                      child: Row(children: [
                        AdminAvatar(name: '${row['name']}', url: row['image_url'] as String?),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${row['name']}', style: orgText(context, w: FontWeight.w800)),
                            Text('${row['email']}', textDirection: TextDirection.ltr,
                                style: orgText(context, size: 12, color: c.textMedium)),
                            const SizedBox(height: 4),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              OrgPill(verified ? t('بريد مؤكَّد', 'E-mail verified') : t('بريد غير مؤكَّد', 'E-mail not verified'),
                                  color: verified ? c.success : c.warning,
                                  icon: verified ? Icons.verified_rounded : Icons.mark_email_unread_rounded),
                              if (!active) OrgPill(t('معطَّل', 'Disabled'), color: c.danger, icon: Icons.block_rounded),
                              for (final o in orgs.take(2)) OrgPill(orgNameOf(o), icon: Icons.domain_rounded, color: c.textMedium),
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

Future<void> _manageOrgAdmin(BuildContext context, Map<String, dynamic> row) async {
  final p = context.read<OrgPaged>();
  final name = TextEditingController(text: '${row['name'] ?? ''}');
  final email = TextEditingController(text: '${row['email'] ?? ''}');
  final phone = TextEditingController(text: '${row['phone'] ?? ''}');
  bool active = row['is_active'] != false, busy = false;
  final url = '$_base/org-admins/${row['id']}';
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Future<void> showPassword(String pwd) => showDialog<void>(
              context: ctx,
              builder: (_) => AlertDialog(
                title: Text(t('كلمة المرور الجديدة (تظهر مرة واحدة)', 'New password (shown once)')),
                content: SelectableText(pwd, textDirection: TextDirection.ltr),
              ),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader('${row['name']}'),
            Field(controller: name, label: t('الاسم', 'Name')),
            AppEmailField(controller: email, label: t('البريد الإلكتروني', 'E-mail')),
            PhoneInputField(controller: phone, label: t('الهاتف', 'Phone')),
            OrgSwitchRow(
              title: t('الحساب مفعّل', 'Account active'),
              subtitle: t('عند التعطيل لا يستطيع تسجيل الدخول', 'When disabled they cannot sign in'),
              value: active,
              onChanged: (v) => set(() => active = v),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                set(() => busy = true);
                final r = await OrgApi.i.put(url, {
                  'name': name.text.trim(),
                  'email': email.text.trim(),
                  'phone': phone.text.trim(),
                  'is_active': active,
                }, email.text.trim().toLowerCase() != '${row['email']}'.toLowerCase()
                    ? t('تم الحفظ — أُرسل رمز تأكيد للبريد الجديد', 'Saved — a verification code was sent to the new e-mail')
                    : t('تم الحفظ', 'Saved'));
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (r != null) {
                  p.refresh();
                  Navigator.pop(ctx);
                }
              },
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    // type a password, or leave it empty to generate a strong one — they are signed out everywhere
                    final pwd = TextEditingController();
                    final go = await showDialog<bool>(
                      context: ctx,
                      builder: (dc) => AlertDialog(
                        scrollable: true,
                        title: Text(t('كلمة مرور جديدة', 'New password')),
                        content: Column(mainAxisSize: MainAxisSize.min, children: [
                          AppPasswordField(controller: pwd, label: t('اكتبها أو اتركها فارغة لتوليد واحدة قوية', 'Type it, or leave empty to generate a strong one'),
                              required: false, showStrength: true, minLength: 8),
                          Text(t('سيُسجَّل خروجه من كل الأجهزة.', 'They will be signed out on every device.'), style: const TextStyle(fontFamily: 'tajawal', fontSize: 12)),
                        ]),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(t('إلغاء', 'Cancel'))),
                          FilledButton(onPressed: () => Navigator.pop(dc, true), child: Text(t('حفظ', 'Save'))),
                        ],
                      ),
                    );
                    if (go != true) return;
                    final r = await OrgApi.i.post('$url/reset-password', {if (pwd.text.isNotEmpty) 'password': pwd.text});
                    if (r is Map && ctx.mounted) await showPassword('${r['generated_password']}');
                  },
                  icon: const Icon(Icons.key_rounded),
                  label: Text(t('كلمة مرور جديدة', 'New password')),
                ),
              ),
              const SizedBox(width: 8),
              if (row['email_verified'] != true)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: c.warning),
                    onPressed: () async {
                      final r = await OrgApi.i.post('$url/send-verification');
                      if (r is Map) {
                        toast(r['sent'] == true
                            ? t('أُرسل رمز التأكيد إلى البريد ✉️', 'Verification code sent ✉️')
                            : t('تعذّر الإرسال الآن — حاول لاحقاً', 'Could not send now — try later'), error: r['sent'] != true);
                      }
                    },
                    icon: const Icon(Icons.mark_email_read_rounded),
                    label: Text(t('إرسال تأكيد البريد', 'Send e-mail verification')),
                  ),
                ),
            ]),
          ]),
        );
      }));
}


/// Membership fees of one organization (platform admins): staff · admins · students (free / per course / per account
/// with this organization's own plans and prices).
Future<void> _billingSheet(BuildContext context, int orgId, String orgName) async {
  final url = '$_base/$orgId/billing';
  final b = await OrgApi.i.getMap(url);
  if (b == null || !context.mounted) return;
  bool staffFree = b['staff_free'] != false, adminsFree = b['admins_free'] != false, busy = false;
  String students = '${b['students'] ?? 'per_account'}';
  final platform = asMapList(b['platform_plans']);
  final chosen = Map<String, dynamic>.from(asMap(b['plans']));
  final prices = {for (final p in platform) '${p['code']}': TextEditingController(text: '${chosen['${p['code']}'] ?? p['price']}')};
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Widget mode(String key, IconData icon, String title, String sub) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => set(() => students = key),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: students == key ? c.primary.withValues(alpha: 0.08) : c.cardBg,
                    border: Border.all(color: students == key ? c.primary : c.divider, width: students == key ? 1.6 : 1),
                  ),
                  child: Row(children: [
                    Icon(icon, color: students == key ? c.primary : c.textMedium),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: orgText(ctx, w: FontWeight.w800)),
                      Text(sub, style: orgText(ctx, size: 12, color: c.textMedium)),
                    ])),
                    if (students == key) Icon(Icons.check_circle_rounded, color: c.primary),
                  ]),
                ),
              ),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader('${t('رسوم العضوية', 'Membership fees')} · $orgName'),
            OrgSwitchRow(title: t('مجاني لهيئة التدريس والموظفين', 'Free for teaching & admin staff'),
                subtitle: t('عند الإيقاف يلزمهم اشتراك', 'When off they need a subscription'), value: staffFree, onChanged: (v) => set(() => staffFree = v)),
            OrgSwitchRow(title: t('مجاني لمديري المؤسسة', 'Free for organization admins'), value: adminsFree, onChanged: (v) => set(() => adminsFree = v)),
            const SizedBox(height: 10),
            Text(t('الطلاب', 'Students'), style: orgText(ctx, w: FontWeight.w800)),
            const SizedBox(height: 8),
            mode('free', Icons.volunteer_activism_rounded, t('مجاني', 'Free'), t('بدون اشتراك، ومقررات المؤسسة بدون رسوم', 'No subscription; the organization\'s courses at no cost')),
            mode('per_course', Icons.menu_book_rounded, t('بالمقرر', 'Per course'), t('بدون اشتراك حساب — يدفع الطالب لكل مقرر', 'No account subscription — each course is paid')),
            mode('per_account', Icons.account_circle_rounded, t('بالحساب (اشتراك)', 'Per account (subscription)'), t('اشتراك بخطط وأسعار هذه المؤسسة', 'A subscription with this organization\'s plans & prices')),
            if (students == 'per_account') ...[
              const SizedBox(height: 6),
              Text(t('الخطط المتاحة وأسعارها لهذه المؤسسة', 'Plans offered & their prices for this organization'),
                  style: orgText(ctx, size: 12.5, w: FontWeight.w700, color: c.textMedium)),
              for (final p in platform)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Checkbox(value: chosen.containsKey('${p['code']}'),
                        onChanged: (v) => set(() => v == true ? chosen['${p['code']}'] = p['price'] : chosen.remove('${p['code']}'))),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('${p['name_ar']}', '${p['name_en']}'), style: orgText(ctx, w: FontWeight.w700)),
                      Text('${t('سعر المنصة', 'Platform price')}: ${p['price']} ${p['currency']}', style: orgText(ctx, size: 11.5, color: c.textLight)),
                    ])),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: prices['${p['code']}'],
                        enabled: chosen.containsKey('${p['code']}'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(isDense: true, suffixText: '${p['currency']}'),
                      ),
                    ),
                  ]),
                ),
            ],
            const SizedBox(height: 16),
            PrimaryButton(isLoading: busy, label: t('حفظ', 'Save'), onPressed: () async {
              set(() => busy = true);
              final r = await OrgApi.i.put(url, {
                'staff_free': staffFree, 'admins_free': adminsFree, 'students': students,
                'plans': students == 'per_account'
                    ? {for (final k in chosen.keys) k: double.tryParse(prices[k]?.text ?? '') ?? 0}
                    : <String, double>{},
              }, t('تم الحفظ — يطبَّق فوراً', 'Saved — applies right away'));
              if (!ctx.mounted) return;
              set(() => busy = false);
              if (r != null) Navigator.pop(ctx);
            }),
          ]),
        );
      }));
}
