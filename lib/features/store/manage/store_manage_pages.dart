// lib/features/store/manage/store_manage_pages.dart
//
// The digital store's management pages (learning hub phase 5, D-1336). The widgets they draw are plain-value ones in
// store_manage_views.dart; these pages own the calls.
//
//   StoreManagePage       a teacher's / super admin's own items: the list (status chips) and the editor beside it on
//                         wide screens (>= 1000 px), the editor pushed as its own page on phones. Kill switch
//                         `store.manage`; a teacher needs the store setting `teacher_items` (403 store_manage_forbidden
//                         → an empty state that says so).
//   StoreItemEditor       loads the form's choices (countries, categories, the country's stages / subjects) and runs
//                         save / cover / upload (presign → PUT → confirm with progress) / publish / hide / delete.
//   StoreAdminHubPage     the super admin's store: My items · Review queue · Orders (kill switch `admin.store`).
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../../admin/admin_page.dart';
import '../../help/help_info_button.dart';
import '../../profile/teacher/t2_frame.dart';
import '../../admin/sup/sup_kit.dart';
import 'package:flutter_education_app/config/app_config.dart';
import '../../../utils/widget/base_page.dart';
import 'store_manage_api.dart';
import 'store_manage_views.dart';

const _api = StoreManageApi();

/// The width from which the editor sits beside the list.
const double kStoreSplitWidth = 1000;

// ═════════════════════════════════════════════════════════════════════════════
//  Items (teacher + super admin)
// ═════════════════════════════════════════════════════════════════════════════

/// The list + editor without a page around it (the admin hub shows it as a tab).
class StoreItemsPane extends StatefulWidget {
  const StoreItemsPane({super.key, this.teacherHero = false});

  /// The teacher's redesigned page (Tea2Money.dc.html?screen=store): the hero band with New item and the figures,
  /// the list riding up over it in one scroll. The admin hub's tab keeps the plain list.
  final bool teacherHero;

  @override
  State<StoreItemsPane> createState() => StoreItemsPaneState();
}

class StoreItemsPaneState extends State<StoreItemsPane> {
  List<StoreManageItem> _items = const [];
  bool _loading = true;
  String? _error;
  String? _status;
  int? _openId;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final (page, err) = await _api.items();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
      if (page != null) _items = page.items;
    });
  }

  void _changed(StoreManageItem it) {
    setState(() {
      final i = _items.indexWhere((x) => x.id == it.id);
      _items = i < 0 ? [it, ..._items] : ([..._items]..[i] = it);
      _openId = it.id;
      _creating = false;
    });
  }

  void _deleted(int id) {
    setState(() {
      _items = [for (final x in _items) if (x.id != id) x];
      if (_openId == id) _openId = null;
    });
    load();
  }

  void _open(StoreManageItem? it, bool wide) {
    if (wide) {
      setState(() {
        _openId = it?.id;
        _creating = it == null;
      });
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StoreItemEditorPage(item: it, onChanged: _changed, onDeleted: _deleted),
    ));
  }

  /// The redesign: one scroll, the hero (New item, the counts), then the list card and, from [kStoreSplitWidth],
  /// the editor beside it.
  Widget _heroLayout(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= kStoreSplitWidth;
        final open = _items.where((x) => x.id == _openId).firstOrNull;
        final published = _items.where((x) => x.status == 'published').length;
        final sold = _items.fold<int>(0, (n, x) => n + x.salesCount);
        final hero = AppHero(
          title: t('ملخصاتك وبنوك أسئلتك للبيع', 'Your summaries and question banks for sale'),
          subtitle: t('كتب وملخصات ومذكرات تبيعها للطلاب.', 'Books, summaries and notes you sell to students.'),
          actions: [AppButton.hot(label: t('عنصر جديد', 'New item'), icon: Icons.add_rounded, onPressed: () => _open(null, wide))],
          stats: _items.isEmpty
              ? const []
              : [
                  AppHeroStat(value: '${_items.length}', label: t('عناصر', 'Items')),
                  AppHeroStat(value: '$published', label: t('منشورة', 'Published')),
                  AppHeroStat(value: '$sold', label: t('نسخة مباعة', 'Copies sold')),
                ],
        );
        final list = AppCard(
          child: StoreItemsListBody(
            items: _items,
            status: _status,
            loading: _loading,
            selectedId: wide ? _openId : null,
            onStatus: (s) => setState(() => _status = s),
            onOpen: (it) => _open(it, wide),
            onNew: () => _open(null, wide),
          ),
        );
        final editor = (open == null && !_creating)
            ? AppCard(
                child: AppEmpty(
                  icon: Icons.touch_app_outlined,
                  title: t('اختر عنصراً', 'Pick an item'),
                  message: t('أو أنشئ عنصراً جديداً لتعديله هنا.', 'Or create a new one to edit it here.'),
                ),
              )
            : AppCard(
                child: StoreItemEditor(key: ValueKey(open?.id ?? 'new'), item: open, onChanged: _changed, onDeleted: _deleted),
              );
        return AppRefresh(
          onRefresh: load,
          child: T2HeroScroll(hero: hero, children: [
            if (_error != null && _items.isEmpty)
              AppCard(child: _errorState())
            else if (!wide)
              list
            else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 2, child: list),
                AppSpace.gapLg,
                Expanded(flex: 3, child: editor),
              ]),
          ]),
        );
      });

  Widget _errorState() {
    final forbidden = _error == 'store_manage_forbidden';
    return AppEmpty(
      icon: forbidden ? Icons.storefront_outlined : Icons.cloud_off_rounded,
      title: forbidden ? t('البيع في المتجر غير مفعّل لحسابك', 'Selling in the store is not on for your account') : t('تعذّر التحميل', 'Could not load'),
      message: forbidden ? t('تفعّله إدارة المنصة للمعلمين.', 'The platform admins switch it on for teachers.') : null,
      actionLabel: forbidden ? null : t('إعادة المحاولة', 'Retry'),
      onAction: forbidden
          ? null
          : () {
              setState(() {
                _error = null;
                _loading = true;
              });
              load();
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.teacherHero) return _heroLayout(context);
    if (_error != null && _items.isEmpty) {
      final forbidden = _error == 'store_manage_forbidden';
      return AppEmpty(
        icon: forbidden ? Icons.storefront_outlined : Icons.cloud_off_rounded,
        title: forbidden ? t('البيع في المتجر غير مفعّل لحسابك', 'Selling in the store is not on for your account') : t('تعذّر التحميل', 'Could not load'),
        message: forbidden ? t('تفعّله إدارة المنصة للمعلمين.', 'The platform admins switch it on for teachers.') : null,
        actionLabel: forbidden ? null : t('إعادة المحاولة', 'Retry'),
        onAction: forbidden
            ? null
            : () {
                setState(() {
                  _error = null;
                  _loading = true;
                });
                load();
              },
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= kStoreSplitWidth;
      final open = _items.where((x) => x.id == _openId).firstOrNull;
      final list = ListView(padding: AdminPage.bodyPadding(context, fab: true), children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton.primary(label: t('عنصر جديد', 'New item'), icon: Icons.add_rounded, onPressed: () => _open(null, wide)),
        ),
        AppSpace.gapSm,
        StoreItemsListBody(
          items: _items,
          status: _status,
          loading: _loading,
          selectedId: wide ? _openId : null,
          onStatus: (s) => setState(() => _status = s),
          onOpen: (it) => _open(it, wide),
          onNew: () => _open(null, wide),
        ),
      ]);
      if (!wide) return AppRefresh(onRefresh: load, child: list);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 2, child: AppRefresh(onRefresh: load, child: list)),
        AppSpace.gapLg,
        Expanded(
          flex: 3,
          child: (open == null && !_creating)
              ? AppEmpty(
                  icon: Icons.touch_app_outlined,
                  title: t('اختر عنصراً', 'Pick an item'),
                  message: t('أو أنشئ عنصراً جديداً لتعديله هنا.', 'Or create a new one to edit it here.'),
                )
              : SingleChildScrollView(
                  padding: AdminPage.bodyPadding(context, fab: true),
                  child: StoreItemEditor(
                    key: ValueKey(open?.id ?? 'new'),
                    item: open,
                    onChanged: _changed,
                    onDeleted: _deleted,
                  ),
                ),
        ),
      ]);
    });
  }
}

class StoreManagePage extends StatelessWidget {
  const StoreManagePage({super.key});

  @override
  Widget build(BuildContext context) => T2Scope(
        child: BasePage(
          enableFooterWidget: false,
          appBar: AppHeader(
            title: t('عناصري في المتجر', 'My store items'),
            actions: const [HelpInfoButton(pageId: 'store.manage')],
          ),
          child: const StoreItemsPane(teacherHero: true),
        ),
      );
}

/// The editor as its own page (phones).
class StoreItemEditorPage extends StatelessWidget {
  const StoreItemEditorPage({super.key, this.item, required this.onChanged, required this.onDeleted});
  final StoreManageItem? item;
  final ValueChanged<StoreManageItem> onChanged;
  final ValueChanged<int> onDeleted;

  @override
  Widget build(BuildContext context) => AdminPage(
        width: AppWidth.form,
        title: item == null ? t('عنصر جديد', 'New item') : t('تعديل العنصر', 'Edit item'),
        icon: Icons.menu_book_rounded,
        body: SingleChildScrollView(
          padding: AdminPage.bodyPadding(context, fab: true),
          child: StoreItemEditor(
            item: item,
            onChanged: onChanged,
            onDeleted: (id) {
              onDeleted(id);
              Navigator.of(context).maybePop();
            },
          ),
        ),
      );
}

/// Loads the choices and runs every action of one item's form.
class StoreItemEditor extends StatefulWidget {
  const StoreItemEditor({super.key, this.item, required this.onChanged, required this.onDeleted});
  final StoreManageItem? item;
  final ValueChanged<StoreManageItem> onChanged;
  final ValueChanged<int> onDeleted;

  @override
  State<StoreItemEditor> createState() => _StoreItemEditorState();
}

class _StoreItemEditorState extends State<StoreItemEditor> implements StoreFormActions {
  late StoreManageItem? _item = widget.item;
  List<StoreChoice<String>> _countries = const [];
  List<StoreChoice<int>> _categories = const [];
  String? _country;
  EduCountryCatalog? _catalog;
  bool _saving = false;
  final Map<String, double> _uploading = {};

  @override
  void initState() {
    super.initState();
    _country = widget.item?.countryCode;
    _loadChoices();
  }

  Future<void> _loadChoices() async {
    final results = await Future.wait([_api.countries(), _api.categories()]);
    if (!mounted) return;
    final cs = results[0] as List<StoreChoice<String>>;
    setState(() {
      _countries = cs;
      _categories = results[1] as List<StoreChoice<int>>;
      _country ??= cs.isEmpty ? null : cs.first.id;
    });
    if (_country != null) await _loadCatalog(_country!);
  }

  Future<void> _loadCatalog(String code) async {
    final cat = await EduCatalog.instance.load(code);
    if (!mounted || code != _country) return;
    setState(() => _catalog = cat);
  }

  void _set(StoreManageItem it) {
    setState(() => _item = it);
    widget.onChanged(it);
  }

  @override
  void country(String code) {
    setState(() {
      _country = code;
      _catalog = null;
    });
    _loadCatalog(code);
  }

  @override
  Future<void> save(Map<String, dynamic> body) async {
    setState(() => _saving = true);
    final it = _item;
    final r = it == null ? await _api.create({for (final e in body.entries) if (e.value != null) e.key: e.value}) : await _api.update(it.id, body, wasStatus: it.status);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) _set(r);
  }

  @override
  Future<String?> pickCover() async {
    if (_item == null) return null; // the form saves a new item first (the cover route needs its id)
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null || !mounted) return null;
    final bytes = await f.readAsBytes();
    if (!mounted) return null;
    final cropped = await showAppImageCropper(context, bytes, shape: CropShape.square, allowTransparent: false);
    if (cropped == null) return null;
    final it = _item;
    if (it == null || !mounted) return null;
    final base = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    final r = await _api.uploadCover(it.id, cropped, '${base.isEmpty ? 'cover' : base}.png', wasStatus: it.status);
    if (r == null || !mounted) return null;
    _set(r);
    return r.coverUrl;
  }

  static String _type(String name) => switch (name.split('.').last.toLowerCase()) {
        'pdf' => 'application/pdf',
        'epub' => 'application/epub+zip',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  @override
  Future<void> upload(String kind) async {
    final it = _item;
    if (it == null) return;
    final ext = kind == 'file' ? ['pdf', 'epub'] : ['pdf', 'jpg', 'jpeg', 'png', 'webp'];
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ext);
    if (f == null || !mounted) return;
    final size = await f.length() ?? 0;
    if (size > kStoreMaxFileBytes) {
      showAppNotice(storeErrorText('store_file_too_large')!, error: true);
      return;
    }
    setState(() => _uploading[kind] = 0);
    Uint8List bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (_) {
      if (mounted) setState(() => _uploading.remove(kind));
      showAppNotice(t('تعذّرت قراءة الملف', 'The file could not be read'), error: true);
      return;
    }
    final r = await _api.upload(it.id, kind: kind, fileName: f.name, bytes: bytes, contentType: _type(f.name), onProgress: (p) {
      if (mounted) setState(() => _uploading[kind] = p.clamp(0, 1));
    });
    if (!mounted) return;
    setState(() => _uploading.remove(kind));
    if (r != null) _set(r);
  }

  @override
  Future<void> publish() async {
    final it = _item;
    if (it == null) return;
    setState(() => _saving = true);
    final r = await _api.publish(it.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) _set(r);
  }

  @override
  Future<void> hide() async {
    final it = _item;
    if (it == null) return;
    setState(() => _saving = true);
    final r = await _api.update(it.id, {'status': 'hidden'}, ok: t('أُخفي العنصر', 'Item hidden'));
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) _set(r);
  }

  @override
  Future<void> delete() async {
    final it = _item;
    if (it == null) return;
    if (!await appConfirm(context,
        danger: true,
        confirmLabel: t('حذف', 'Delete'),
        message: t('حذف «${it.title}»؟ إن اشتراه أحد يُخفى بدل أن يُحذف.', 'Delete "${it.title}"? If anyone bought it, it is hidden instead.'))) {
      return;
    }
    final r = await _api.delete(it.id);
    if (r == null) return;
    showAppNotice(r.$1 ? t('حُذف', 'Deleted') : t('اشتراه طلاب، فأُخفي بدل الحذف', 'Students bought it, so it was hidden instead'));
    widget.onDeleted(it.id);
  }

  @override
  Widget build(BuildContext context) {
    return StoreItemForm(
      item: _item,
      actions: this,
      countries: {for (final c in _countries) c.id: c.name},
      country: _country,
      stages: _catalog?.stages ?? const [],
      subjects: _catalog?.subjects ?? const [],
      categories: _categories,
      saving: _saving,
      uploading: Map.of(_uploading),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Super admin: review queue + orders
// ═════════════════════════════════════════════════════════════════════════════

class StoreReviewPane extends StatefulWidget {
  const StoreReviewPane({super.key, this.onCount});
  final ValueChanged<int>? onCount;

  @override
  State<StoreReviewPane> createState() => _StoreReviewPaneState();
}

class _StoreReviewPaneState extends State<StoreReviewPane> {
  List<StoreManageItem> _items = const [];
  bool _loading = true, _failed = false;
  int? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _api.pending();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = p == null;
      if (p != null) _items = p.items;
    });
    if (p != null) widget.onCount?.call(p.total);
  }

  Future<void> _review(StoreManageItem it, bool approve) async {
    String? note;
    if (!approve) {
      note = await showAppSheet<String>(context, (_) => StoreRejectSheet(title: it.title));
      if (note == null) return;
    }
    setState(() => _busy = it.id);
    final r = await _api.review(it.id, approve: approve, note: note);
    if (!mounted) return;
    setState(() => _busy = null);
    if (r != null) {
      setState(() => _items = [for (final x in _items) if (x.id != it.id) x]);
      widget.onCount?.call(_items.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return AppEmpty(
        icon: Icons.cloud_off_rounded,
        title: t('تعذّر التحميل', 'Could not load'),
        actionLabel: t('إعادة المحاولة', 'Retry'),
        onAction: () {
          setState(() => _failed = false);
          _load();
        },
      );
    }
    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: AdminPage.bodyPadding(context, fab: true), children: [
        StoreReviewQueueBody(items: _items, loading: _loading, busyId: _busy, onApprove: (it) => _review(it, true), onReject: (it) => _review(it, false)),
      ]),
    );
  }
}

class StoreOrdersPane extends StatefulWidget {
  const StoreOrdersPane({super.key});

  @override
  State<StoreOrdersPane> createState() => _StoreOrdersPaneState();
}

class _StoreOrdersPaneState extends State<StoreOrdersPane> {
  static const _page = 50;
  List<StoreOrderRow> _orders = const [];
  AppTableState _state = AppTableState.loading;
  String? _status;
  bool _hasMore = false, _more = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (append) setState(() => _more = true);
    final p = await _api.orders(status: _status, skip: append ? _orders.length : 0, limit: _page);
    if (!mounted) return;
    setState(() {
      _more = false;
      if (p == null) {
        if (!append) _state = AppTableState.error;
        return;
      }
      _orders = append ? [..._orders, ...p.items] : p.items;
      _hasMore = p.hasMore;
      _state = AppTableState.ready;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StoreOrdersBody(
      orders: _orders,
      status: _status,
      state: _state,
      onRetry: () {
        setState(() => _state = AppTableState.loading);
        _load();
      },
      hasMore: _hasMore,
      loadingMore: _more,
      onLoadMore: _hasMore && !_more ? () => _load(append: true) : null,
      onStatus: (s) {
        setState(() {
          _status = s;
          _state = AppTableState.loading;
        });
        _load();
      },
      onExport: () => showAppExportSheet(context, bilingualExport(() => storeOrdersExport(_orders, status: _status))),
    );
  }
}

/// The admins' store: own items for every admin; the review queue and the orders for the super admin only (the
/// server answers 403 `admin_required` to `admin` / `developer` on `/admin/store/*`).
class StoreAdminHubPage extends StatefulWidget {
  const StoreAdminHubPage({super.key, required this.superAdmin, this.initialTab = 0});
  final bool superAdmin;
  final int initialTab;

  @override
  State<StoreAdminHubPage> createState() => _StoreAdminHubPageState();
}

class _StoreAdminHubPageState extends State<StoreAdminHubPage> {
  late int _tab = widget.initialTab;
  int? _pending;

  @override
  Widget build(BuildContext context) {
    if (!widget.superAdmin) return const StoreManagePage();
    // the redesign (SupFinance store): what waits for review leads the super admin's hero, the three parts are its pill
    final waiting = _pending ?? 0;
    return SupPage(
      title: t('المتجر الرقمي', 'Digital store'),
      kicker: 't2_sstore_kicker'.tr,
      headline: waiting > 0 ? 't2_sstore_waiting'.tr.replaceAll('{n}', '$waiting') : 't2_sstore_head'.tr,
      line: t('العناصر ومراجعتها وطلبات الشراء.', 'Items, their review and the purchase orders.'),
      helpPageId: 'admin.store',
      actions: [
        if (waiting > 0 && _tab != 1)
          SupHeroButton(label: 't2_sstore_review'.tr, icon: Icons.rule_rounded, onTap: () => setState(() => _tab = 1)),
      ],
      tabs: [
        AppTabItem(t('العناصر', 'Items'), icon: Icons.menu_book_rounded),
        AppTabItem(t('المراجعة', 'Review'), icon: Icons.rule_rounded, count: _pending),
        AppTabItem(t('الطلبات', 'Orders'), icon: Icons.receipt_long_rounded),
      ],
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      body: SupTabStack(index: _tab, children: [
        const StoreItemsPane(),
        StoreReviewPane(onCount: (n) => setState(() => _pending = n == 0 ? null : n)),
        const StoreOrdersPane(),
      ]),
    );
  }
}
