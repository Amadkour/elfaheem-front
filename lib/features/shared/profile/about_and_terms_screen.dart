// ─────────────────────────────────────────────────────────────────────────────
// features/shared/profile/about_and_terms_screen.dart
// Premium About Us + Terms & Conditions — dark/light adaptive, Web & Mobile
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';
import '../../../utils/helpers.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';
import '../../student/courses/details/components/app_responsive.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  About Screen
// ══════════════════════════════════════════════════════════════════════════════

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _features = [
    (Icons.play_circle_outline_rounded,  'كورسات مباشرة ومسجلة',    'تعلّم في أي وقت مع محتوى تفاعلي عالي الجودة'),
    (Icons.people_alt_outlined,          'نخبة من المدرسين',         'أفضل المدرسين في مجالات القدرات والتحصيلي والإنجليزي'),
    (Icons.quiz_outlined,                'اختبارات تفاعلية',         'قياس مستواك بنماذج محاكاة وأسئلة حديثة'),
    (Icons.emoji_events_outlined,        'شهادات معتمدة',            'احصل على شهادة إتمام لكل كورس تنهيه بنجاح'),
    (Icons.support_agent_rounded,        'دعم فوري',                 'فريق دعم جاهز على مدار الساعة لمساعدتك'),
    (Icons.devices_outlined,             'جميع الأجهزة',             'استخدم التطبيق من هاتفك أو الحاسوب بكل سهولة'),
  ];

  static const _team = [
    ('أحمد محمد',   'المؤسس والرئيس التنفيذي',    '👨‍💼'),
    ('سارة علي',    'مديرة المحتوى التعليمي',      '👩‍🏫'),
    ('خالد إبراهيم','مدير التقنية',                '👨‍💻'),
    ('نورة حسن',   'مديرة خدمة العملاء',          '👩‍💼'),
  ];

  @override
  Widget build(BuildContext context) {
    final c      = context.colors;
    final isWide = context.showSidebar;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        useWebCard: true,
        child: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'من نحن'),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      child: Column(children: [
                        // ── Hero ──────────────────────────────────────────
                        _HeroBanner(isWide: isWide),
                        const SizedBox(height: 32),

                        // ── Mission ───────────────────────────────────────
                        _SectionTitle(text: 'رسالتنا'),
                        const SizedBox(height: 12),
                        _MissionCard(),
                        const SizedBox(height: 32),

                        // ── Stats ─────────────────────────────────────────
                        _StatsRow(),
                        const SizedBox(height: 32),

                        // ── Features ──────────────────────────────────────
                        _SectionTitle(text: 'ما يميّزنا'),
                        const SizedBox(height: 16),
                        _FeaturesGrid(features: _features, isWide: isWide),
                        const SizedBox(height: 32),

                        // ── Team ──────────────────────────────────────────
                        _SectionTitle(text: 'فريقنا'),
                        const SizedBox(height: 16),
                        _TeamRow(team: _team),
                        const SizedBox(height: 32),

                        // ── Contact ───────────────────────────────────────
                        _ContactCard(),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Hero Banner ───────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.isWide});
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: 24, vertical: isWide ? 52 : 36),
      decoration: BoxDecoration(
        gradient: c.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: c.primaryShadow,
      ),
      child: Column(children: [
        // Logo ring
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.15),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.4), width: 2),
          ),
          child: const Icon(Icons.school_rounded,
              size: 52, color: Colors.white),
        ),
        const SizedBox(height: 20),
        const Text(
          'مركز الفهيم',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          'قدرات · تحصيلي · الإنجليزي',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.85)),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.4)),
          ),
          child: const Text(
            'منصة التعليم الرائدة في المملكة',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

// ── Section Title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Container(width: 4, height: 22, color: c.primary,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 10),
      Text(text, style: c.h2.copyWith(fontSize: 18)),
    ]);
  }
}

// ── Mission Card ──────────────────────────────────────────────────────────────

class _MissionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
      ),
      child: Column(children: [
        Icon(Icons.format_quote_rounded, color: c.primary, size: 32),
        const SizedBox(height: 12),
        Text(
          'نسعى في مركز الفهيم إلى تقديم تجربة تعليمية متكاملة تُمكّن كل طالب من '
          'الوصول إلى أفضل المدرسين وأحدث المحتويات التعليمية، لنبني معاً جيلاً '
          'مؤهلاً ومتفوقاً يستحق المستقبل.',
          style: c.body.copyWith(
              height: 1.9, fontSize: 15, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

// ── Stats Row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  static const _stats = [
    ('١٠٠٠+', 'طالب مسجّل'),
    ('٥٠+',   'مدرس متخصص'),
    ('٢٠٠+',  'كورس متاح'),
    ('٩٨٪',   'رضا الطلاب'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: _stats.map((s) {
          final (val, label) = s;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Text(val,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: c.primary)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 11, color: c.textMedium)),
          ]);
        }).toList(),
      ),
    );
  }
}

// ── Features Grid ─────────────────────────────────────────────────────────────

class _FeaturesGrid extends StatelessWidget {
  const _FeaturesGrid(
      {required this.features, required this.isWide});
  final List<(IconData, String, String)> features;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    if (isWide) {
      // 3-column grid on web
      final rows = <Widget>[];
      for (int i = 0; i < features.length; i += 3) {
        rows.add(Row(children: [
          for (int j = i; j < i + 3 && j < features.length; j++) ...[
            Expanded(child: _FeatureCard(data: features[j])),
            if (j < i + 2 && j < features.length - 1)
              const SizedBox(width: 12),
          ],
        ]));
        if (i + 3 < features.length) rows.add(const SizedBox(height: 12));
      }
      return Column(children: rows);
    }
    // 2-column grid on mobile
    final rows = <Widget>[];
    for (int i = 0; i < features.length; i += 2) {
      rows.add(Row(children: [
        Expanded(child: _FeatureCard(data: features[i])),
        const SizedBox(width: 12),
        if (i + 1 < features.length)
          Expanded(child: _FeatureCard(data: features[i + 1]))
        else
          const Expanded(child: SizedBox()),
      ]));
      if (i + 2 < features.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.data});
  final (IconData, String, String) data;

  @override
  Widget build(BuildContext context) {
    final (icon, title, desc) = data;
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: c.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 12),
        Text(title,
            style: c.h3.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text(desc,
            style: c.caption.copyWith(height: 1.5, fontSize: 11),
            maxLines: 3),
      ]),
    );
  }
}

// ── Team Row ──────────────────────────────────────────────────────────────────

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team});
  final List<(String, String, String)> team;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: team.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final (name, role, emoji) = team[i];
          final c = context.colors;
          return Container(
            width: 130,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(c.radiusMedium),
              boxShadow: c.cardShadow,
            ),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 8),
              Text(name,
                  style: c.h3.copyWith(fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(role,
                  style: c.caption.copyWith(fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 2),
            ]),
          );
        },
      ),
    );
  }
}

// ── Contact Card ──────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
        border: Border.all(color: c.divider),
      ),
      child: Column(children: [
        Text('تواصل معنا', style: c.h2.copyWith(fontSize: 16)),
        const SizedBox(height: 16),
        _ContactRow(
            icon: Icons.email_outlined,
            label: 'support@elfaheem.sa',
            color: const Color(0xFF3B82F6)),
        const SizedBox(height: 12),
        _ContactRow(
            icon: Icons.phone_outlined,
            label: '+966 5X XXX XXXX',
            color: const Color(0xFF10B981)),
        const SizedBox(height: 12),
        _ContactRow(
            icon: Icons.location_on_outlined,
            label: 'الرياض، المملكة العربية السعودية',
            color: const Color(0xFFF59E0B)),
      ]),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(label,
            style: c.body.copyWith(fontSize: 14),
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Terms & Conditions Screen
// ══════════════════════════════════════════════════════════════════════════════

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final Set<int> _expanded = {0};

  static const _sections = [
    (
      Icons.gavel_rounded,
      'القبول بالشروط',
      'باستخدامك لتطبيق مركز الفهيم فإنك توافق على الالتزام بهذه الشروط والأحكام. '
          'إذا كنت لا توافق على أي بند من هذه الشروط، يُرجى التوقف عن استخدام التطبيق فوراً. '
          'يحتفظ المركز بحق تعديل هذه الشروط في أي وقت مع إشعار مسبق.',
    ),
    (
      Icons.person_outline_rounded,
      'حساب المستخدم',
      'يتحمل المستخدم مسؤولية الحفاظ على سرية بيانات حسابه وكلمة مروره. '
          'يجب أن تكون المعلومات المقدمة عند التسجيل صحيحة ودقيقة. '
          'يحق للمركز إلغاء أي حساب ينتهك سياساتنا دون إشعار مسبق.',
    ),
    (
      Icons.school_outlined,
      'استخدام المحتوى التعليمي',
      'جميع المواد التعليمية المتاحة على المنصة محمية بحقوق الملكية الفكرية. '
          'يُحظر تحميل أو نقل أو إعادة نشر أي محتوى دون إذن كتابي مسبق. '
          'يُسمح باستخدام المحتوى للأغراض التعليمية الشخصية فقط.',
    ),
    (
      Icons.payment_outlined,
      'المدفوعات والاسترداد',
      'تُعالج المدفوعات بشكل آمن عبر بوابات دفع معتمدة. '
          'يمكن طلب استرداد المبلغ خلال 7 أيام من تاريخ الشراء إذا لم يتم '
          'الوصول إلى أكثر من 20٪ من محتوى الكورس. '
          'لا تُسترد رسوم الاشتراكات بعد انتهاء مدة الاسترداد.',
    ),
    (
      Icons.shield_outlined,
      'الخصوصية وحماية البيانات',
      'نلتزم بحماية بياناتك الشخصية وفق أعلى معايير الأمان. '
          'لا نشارك بياناتك مع أطراف ثالثة إلا بموافقتك الصريحة أو لمتطلبات قانونية. '
          'يمكنك طلب حذف بياناتك في أي وقت عبر التواصل مع فريق الدعم.',
    ),
    (
      Icons.block_outlined,
      'السلوك المحظور',
      'يُحظر استخدام المنصة لأغراض غير مشروعة أو مسيئة. '
          'لا يجوز انتحال شخصية مستخدمين آخرين أو المدرسين أو إدارة المركز. '
          'يُمنع منعاً باتاً نشر محتوى مسيء أو غير لائق في أي جزء من المنصة.',
    ),
    (
      Icons.update_rounded,
      'تحديثات الشروط',
      'يحق لمركز الفهيم تحديث هذه الشروط والأحكام دورياً. '
          'سيتم إشعارك بأي تغييرات جوهرية عبر البريد الإلكتروني أو إشعارات التطبيق. '
          'استمرارك في استخدام المنصة بعد التحديث يُعدّ قبولاً ضمنياً للشروط الجديدة.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        useWebCard: true,
        child: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'الشروط والأحكام'),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: Breakpoints.contentMax),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      child: Column(children: [
                        // ── Header card ────────────────────────────────────
                        _TermsHeader(),
                        const SizedBox(height: 20),
                        // ── Sections ───────────────────────────────────────
                        ...List.generate(_sections.length, (i) {
                          final (icon, title, body) = _sections[i];
                          final isOpen = _expanded.contains(i);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _TermsSection(
                              index: i,
                              icon: icon,
                              title: title,
                              body: body,
                              isOpen: isOpen,
                              onToggle: () => setState(() {
                                if (isOpen) {
                                  _expanded.remove(i);
                                } else {
                                  _expanded.add(i);
                                }
                              }),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        // ── Footer note ────────────────────────────────────
                        _TermsFooter(),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Terms Header ──────────────────────────────────────────────────────────────

class _TermsHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.primary.withValues(alpha: 0.08),
            c.accent.withValues(alpha: 0.05),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.primary.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: c.primaryGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: c.primaryShadow,
          ),
          child:
              const Icon(Icons.description_outlined, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('الشروط والأحكام',
                style: c.h2.copyWith(fontSize: 16)),
            const SizedBox(height: 4),
            Text('آخر تحديث: يناير ٢٠٢٥',
                style: c.caption.copyWith(fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

// ── Terms Section ─────────────────────────────────────────────────────────────

class _TermsSection extends StatelessWidget {
  const _TermsSection({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
    required this.isOpen,
    required this.onToggle,
  });
  final int index;
  final IconData icon;
  final String title;
  final String body;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
        border: isOpen
            ? Border.all(color: c.primary.withValues(alpha: 0.3), width: 1.5)
            : null,
      ),
      child: Column(children: [
        // ── Header row ──────────────────────────────────────────────────
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              // Number badge
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isOpen ? c.primary : c.primaryTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    size: 17,
                    color: isOpen ? Colors.white : c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: c.h3.copyWith(
                      fontSize: 14,
                      color: isOpen ? c.primary : c.textDark),
                ),
              ),
              AnimatedRotation(
                turns: isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: isOpen ? c.primary : c.textLight,
                ),
              ),
            ]),
          ),
        ),
        // ── Body ────────────────────────────────────────────────────────
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState:
              isOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(children: [
              Divider(color: c.divider, height: 1),
              const SizedBox(height: 14),
              Text(body,
                  style: c.body.copyWith(height: 1.8, fontSize: 14),
                  textAlign: TextAlign.start),
            ]),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

// ── Terms Footer ──────────────────────────────────────────────────────────────

class _TermsFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.success.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.verified_outlined, color: c.success, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'باستمرارك في استخدام مركز الفهيم، فأنت تقر بأنك قرأت '
            'وفهمت ووافقت على جميع الشروط والأحكام المذكورة أعلاه.',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                height: 1.7,
                color: c.success.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }
}
