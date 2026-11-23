// lib/features/games/admin/v4/hub_links.dart — the Games hub's built-in page links (Games v4, CONTRACT §10): the
// content bank, the review queue, the import wizard and the reciters. Declared here, not registered at start-up, so a
// link can never go missing because a file was not loaded. Later pages (levels, analytics, rewards, seed console) add
// one entry to [gamesHubBuiltInLinks].
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/admin/v4/analytics_page.dart';
import 'package:flutter_education_app/features/admin/rewards/admin_rewards_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/bank_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/breaks_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/cosmetics_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/seed_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/hub_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/import_wizard.dart';
import 'package:flutter_education_app/features/games/admin/v4/levels_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/reciters_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/review_page.dart';

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

List<GamesHubLink> gamesHubBuiltInLinks() => [
      GamesHubLink(
        id: 'bank',
        titleAr: 'بنك الأسئلة',
        titleEn: 'Question bank',
        subAr: 'أضف الأسئلة وعدّلها وابحث فيها',
        subEn: 'Add, edit and search questions',
        icon: Icons.library_books_rounded,
        sort: 10,
        open: (c) => _push(c, const BankPage()),
      ),
      GamesHubLink(
        id: 'review',
        titleAr: 'المراجعة الشرعية',
        titleEn: 'Religious review',
        subAr: 'اعتمد الأسئلة الشرعية أو ارفضها',
        subEn: 'Approve or reject religious questions',
        icon: Icons.fact_check_rounded,
        sort: 20,
        open: (c) => _push(c, const GamesReviewPage()),
      ),
      GamesHubLink(
        id: 'import',
        titleAr: 'استيراد الأسئلة',
        titleEn: 'Import questions',
        subAr: 'من ملف Excel أو CSV أو JSON',
        subEn: 'From an Excel, CSV or JSON file',
        icon: Icons.upload_file_rounded,
        sort: 30,
        open: (c) => _push(c, const GamesImportPage()),
      ),
      GamesHubLink(
        id: 'reciters',
        titleAr: 'القرّاء',
        titleEn: 'Reciters',
        subAr: 'القرّاء المتاحون للطلاب وتراخيصهم',
        subEn: 'Reciters offered to learners, and their licences',
        icon: Icons.record_voice_over_rounded,
        sort: 40,
        open: (c) => _push(c, const RecitersPage()),
      ),
      GamesHubLink(
        id: 'levels',
        titleAr: 'المستويات',
        titleEn: 'Levels',
        subAr: 'رتّب المستويات وأنشئها وجرّبها وانشرها',
        subEn: 'Order, build, try and publish levels',
        icon: Icons.stairs_rounded,
        sort: 50,
        open: (c) => _push(c, const GamesLevelsPage()),
      ),
      GamesHubLink(
        id: 'analytics',
        titleAr: 'إحصاءات الألعاب',
        titleEn: 'Games analytics',
        subAr: 'اللعب والإنهاء وأصعب الأسئلة',
        subEn: 'Plays, completion and the hardest questions',
        icon: Icons.insights_rounded,
        sort: 60,
        open: (c) => _push(c, const GamesAnalyticsPage()),
      ),
      GamesHubLink(
        id: 'rewards',
        titleAr: 'جوائز الألعاب',
        titleEn: 'Game rewards',
        subAr: 'بطل اليوم لكل فئة عمرية والقسائم والدعوات',
        subEn: 'Daily winners per age group, coupons and referrals',
        icon: Icons.emoji_events_rounded,
        sort: 70,
        open: (c) => _push(c, const AdminRewardsPage()),
      ),
      GamesHubLink(
        id: 'breaks',
        titleAr: 'الاستراحات وأولياء الأمور',
        titleEn: 'Breaks & parents',
        subAr: 'العب الآن وتذكير الاستراحة وملخص ولي الأمر',
        subEn: 'Play now, break reminders and the parent summary',
        icon: Icons.self_improvement_rounded,
        sort: 80,
        open: (c) => _push(c, const GamesBreaksPage()),
      ),
      GamesHubLink(
        id: 'cosmetics',
        titleAr: 'ملابس اللاعب',
        titleEn: 'Outfits',
        subAr: 'القبعات والملابس وأسعارها بالعملات',
        subEn: 'Hats, outfits and their coin prices',
        icon: Icons.checkroom_rounded,
        sort: 90,
        open: (c) => _push(c, const GamesCosmeticsPage()),
      ),
      GamesHubLink(
        id: 'seed',
        titleAr: 'الأسئلة الجاهزة',
        titleEn: 'Seed console',
        subAr: 'املأ البنك بأسئلة جاهزة لكل مادة',
        subEn: 'Fill the bank with ready questions per subject',
        icon: Icons.auto_awesome_rounded,
        sort: 100,
        open: (c) => _push(c, const GamesSeedPage()),
      ),
    ];
