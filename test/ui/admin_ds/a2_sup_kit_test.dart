// The Super Admin frame of the redesign (group A2, lib/features/admin/sup/sup_kit.dart): no layout error at
// 320x640 and 1400x900 (ar + en, text x1.3) with tabs, hero figures, hero buttons and a scrolling body; the open tab
// scrolls the hero away; nothing keeps ticking under Reduce motion.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/sup/sup_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../layout_harness.dart';

class _Demo extends StatefulWidget {
  const _Demo();

  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  int _tab = 0;

  Widget _list(String tag) => ListView(
        key: ValueKey('list.$tag'),
        padding: SupPage.bodyPadding(context),
        children: [
          for (var i = 0; i < 30; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: SupCard(
                title: 'أ. ماجد الشهري — طلب سحب رقم $i بعنوان طويل جدًا ليلتف على سطرين',
                icon: Icons.account_balance_wallet_rounded,
                trailing: const AppStatusBadge(label: 'قيد الانتظار', tone: AppTone.warning),
                child: Text('$tag $i', style: AppType.body(context)),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) => SupPage(
        title: 'مدفوعات المعلمين',
        kicker: 'مدفوعات المعلمين',
        headline: '٧ طلبات سحب تنتظرك، أقدمها من ٤ أيام',
        line: 'التحويل التلقائي يطلع من حساب المنصة فورًا بعد موافقتك.',
        onRefresh: () async {},
        actions: [
          SupHeroButton(label: 'تصدير', icon: Icons.download_rounded, onTap: () {}),
          AppButton.primary(label: 'اعتمد المحدد', onPressed: () {}),
          SupMoreButton(items: [SupMenuItem(label: 'الرسوم', icon: Icons.percent_rounded, onTap: () {})]),
        ],
        stats: const [
          AppHeroStat(value: '28,600 EGP', label: 'بانتظار الاعتماد، ٦ طلبات'),
          AppHeroStat(value: '3', label: 'طلبات تحتاج تسوية'),
          AppHeroStat(value: '184,000', label: 'انصرف هالشهر'),
          AppHeroStat(value: '1', label: 'تحويل غير مؤكد', delta: '+1'),
        ],
        tabs: [supTab('الطلبات', count: 7), supTab('المعلمون'), supTab('الإعدادات')],
        tab: _tab,
        onTab: (i) => setState(() => _tab = i),
        body: SupTabStack(index: _tab, children: [_list('a'), _list('b'), _list('c')]),
      );
}

void main() {
  late StorageService storage;

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    AppConfig.lang = 'ar';
  });

  Widget host() => ChangeNotifierProvider(create: (_) => LangProvider(storage: storage), child: const _Demo());

  testWidgets('layout: phone and desktop, ar and en, text x1.3', (t) async {
    await expectNoLayoutErrors(t, host, scaffold: false, frames: 6);
  });

  testWidgets('a single body carries the hero away; kept-alive tabs keep their own offsets', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(layoutHost(
      ChangeNotifierProvider(
        create: (_) => LangProvider(storage: storage),
        child: Builder(
        builder: (context) => SupPage(
          title: 'سلة الدورات',
          headline: 'الدورات المحذوفة تنتظر هنا',
          body: ListView(key: const ValueKey('single'), children: [for (var i = 0; i < 40; i++) ListTile(title: Text('$i'))]),
        ),
      ),
      ),
      scaffold: false,
      scale: 1,
    ));
    await t.pump(const Duration(milliseconds: 500));
    final headline = find.text('الدورات المحذوفة تنتظر هنا');
    final top0 = t.getTopLeft(headline).dy;
    await t.drag(find.byKey(const ValueKey('single')), const Offset(0, -60));
    await t.pump(const Duration(milliseconds: 500));
    expect(t.getTopLeft(headline).dy, lessThan(top0), reason: 'the hero scrolls with the body');

    await t.pumpWidget(layoutHost(host(), scaffold: false, scale: 1));
    await t.pump(const Duration(milliseconds: 500));
    await t.drag(find.byKey(const ValueKey('list.a')), const Offset(0, -300));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('المعلمون'));
    await t.pump(const Duration(milliseconds: 500));
    final b = t.state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('list.b')), matching: find.byType(Scrollable)));
    expect(b.position.pixels, 0, reason: 'a hidden tab never scrolled with the open one');
  });

  testWidgets('Reduce motion: the page settles (no loop keeps ticking)', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1400, 900);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(layoutHost(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: host(),
        ),
      ),
      scaffold: false,
      scale: 1,
    ));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(t.takeException(), isNull);
  });
}
