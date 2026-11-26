// S-B learn screens: demo data (CAST.md: Faisal, أ. ماجد الشهري, الرياضيات ثاني ثانوي, الدوال اللوغاريتمية) and the
// small fakes the layout tests and goldens share.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/records/records_api.dart';
import 'package:flutter_education_app/features/sessions/material/components/lesson_material_view.dart';
import 'package:flutter_education_app/features/sessions/material/session_material_model.dart';
import 'package:flutter_education_app/features/sessions/video/vod_lesson_page.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// POST /courses/{id}/unlock that answers with an error (or succeeds when [statusCode] is null).
class SbLearnUnlock {
  SbLearnUnlock({this.statusCode, this.detail = const {}});

  final int? statusCode;
  final Map<String, dynamic> detail;
  final calls = <String>[];

  Future<void> call(String code) async {
    calls.add(code);
    if (statusCode == null) return;
    throw ApiException(statusCode: statusCode!, message: 'error', body: {'detail': detail}, code: detail['code']?.toString());
  }
}

/// The library over a fixed list.
class SbLearnRecordsApi implements RecordsApi {
  SbLearnRecordsApi(this.items);

  final List<RecordItem> items;

  @override
  Future<List<RecordItem>> list() async => items;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RecordItem _rec(int id, int meeting, String title, String day, double seconds, {String status = 'done'}) => RecordItem.fromJson({
      'recording_id': id,
      'kind': 'meeting',
      'status': status,
      'quality': '720p',
      'destination': 'google_drive',
      'duration_seconds': seconds,
      'created_at': '2026-11-${day}T17:20:00',
      'title': title,
      'meeting': {
        'id': meeting,
        'title': meeting == 1 ? _t('الرياضيات', 'Mathematics') : _t('الفيزياء', 'Physics'),
        'starts_at': '2026-11-${day}T16:30:00'
      },
      'can_edit': false,
      'can_play': status == 'done',
    })!;

/// Two groups (maths three, physics two), as the reference draws them.
List<RecordItem> sbRecords() => [
      _rec(1, 1, _t('الدوال العكسية', 'Inverse functions'), '17', 2980),
      _rec(2, 1, _t('مراجعة الوحدة الأولى', 'Unit 1 review'), '22', 3000),
      _rec(3, 1, _t('تحويلات الدوال', 'Function transformations'), '15', 2912),
      _rec(4, 2, _t('قوانين نيوتن', "Newton's laws"), '24', 3000),
      _rec(5, 2, _t('الحركة في بعد واحد', 'Motion in one dimension'), '17', 2955),
    ];

SessionMaterialModel sbMaterial(int id, String name, {SessionMaterialType type = SessionMaterialType.video}) =>
    SessionMaterialModel(id: id, sessionId: 8, name: name, type: type, order: id, createdAt: DateTime(2026), durationSeconds: 1920, completed: false);

/// The lesson content of "الدوال اللوغاريتمية" with the quiz in [quiz].
Widget sbLessonView({LessonQuizState quiz = LessonQuizState.start}) => Builder(builder: (context) {
      final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
      return Padding(
        padding: EdgeInsets.all(g),
        child: LessonMaterialView(
          video: LessonVideoData(
            minutes: 38,
            stoppedAt: const Duration(minutes: 12, seconds: 30),
            progress: 0.33,
            onPlay: () {},
          ),
          files: [
            LessonFileData(kind: LessonFileKind.pdf, title: _t('ملخص الدرس', 'Lesson summary'), meta: _t('PDF، ٤ صفحات', 'PDF, 4 pages'), done: true, onTap: () {}),
            LessonFileData(kind: LessonFileKind.doc, title: _t('ورقة عمل', 'Worksheet'), meta: _t('صفحتين', '2 pages'), onTap: () {}),
            LessonFileData(kind: LessonFileKind.image, title: _t('جدول اللوغاريتمات', 'Logarithm table'), meta: _t('صورة', 'Picture'), done: true, onTap: () {}),
            LessonFileData(kind: LessonFileKind.link, title: _t('تمارين إضافية', 'Extra exercises'), meta: _t('رابط', 'Link'), onTap: () {}),
            LessonFileData(kind: LessonFileKind.recorded, title: _t('تسجيل حصة المراجعة', 'Review class recording'), meta: _t('ننزّله ٦٢٪', 'Downloading 62%'), downloading: 0.62, onTap: () {}),
            LessonFileData(kind: LessonFileKind.cards, title: _t('بطاقات مراجعة', 'Review cards'), meta: _t('١٢ بطاقة', '12 cards'), onTap: () {}),
          ],
          quiz: LessonQuizData(
            state: quiz,
            questions: 10,
            minutes: 15,
            score: quiz == LessonQuizState.passed ? 90 : 55,
            left: quiz == LessonQuizState.start ? 3 : 2,
            onOpen: () {},
          ),
        ),
      );
    });

/// The lesson player page around a stand-in stage (no video controller in a test).
Widget sbPlayerPage({required bool wide, Widget? stage}) => Builder(builder: (context) {
      final c = context.colors;
      final w = MediaQuery.sizeOf(context).width;
      final box = stage ??
          ColoredBox(
            color: c.kit.deep,
            child: Center(
              child: Text(_t('لو٢ ٨ = ٣', 'log2 8 = 3'), style: AppType.headline(context).copyWith(color: c.onHero)),
            ),
          );
      final isWide = wide && w >= 1000;
      return VodLessonLayout(
        wide: isWide,
        header: VodLessonHeader(
          title: _t('٨. الدوال اللوغاريتمية', '8. Logarithmic functions'),
          subtitle: _t('الرياضيات ٢ ثانوي، أ. ماجد الشهري', 'Maths 2nd secondary, Mr Majed Alshehri'),
          onBack: () {},
          trailing: isWide ? VodPagePill(label: _t('باقي لك ٧ مشاهدات هالشهر', '7 views left this month')) : null,
        ),
        player: isWide
            ? ClipRRect(borderRadius: BorderRadius.circular(AppRadius.cardWide), child: AspectRatio(aspectRatio: 16 / 9, child: box))
            : SizedBox(height: (w * 0.78).clamp(300.0, 440.0).toDouble(), child: box),
        actions: VodLessonActions(onDownload: () {}, onSummary: () {}),
        list: VodLessonList(position: 8, total: 24, entries: [
          VodLessonEntry(number: 6, title: _t('مراجعة الوحدة الأولى', 'Unit 1 review'), state: VodLessonState.done, badge: '42:00', onTap: () {}),
          VodLessonEntry(number: 7, title: _t('الدوال الأسية', 'Exponential functions'), state: VodLessonState.live, badge: _t('مباشر', 'Live'), onTap: () {}),
          VodLessonEntry(number: 8, title: _t('الدوال اللوغاريتمية', 'Logarithmic functions'), state: VodLessonState.current, caption: _t('تشتغل الحين، ٤٨٪', 'Playing now, 48%'), badge: '38:10'),
          VodLessonEntry(number: 9, title: _t('خصائص اللوغاريتمات', 'Properties of logarithms'), state: VodLessonState.locked, badge: '32:00'),
          VodLessonEntry(number: 10, title: _t('حل المعادلات الأسية', 'Solving exponential equations'), state: VodLessonState.locked, caption: _t('حصة الأحد', 'Sunday class'), badge: '50:00'),
          VodLessonEntry(number: 11, title: _t('اختبار الوحدة الثانية', 'Unit 2 test'), state: VodLessonState.locked, caption: _t('الخميس', 'Thursday'), badge: _t('٢٠ سؤال', '20 questions')),
        ]),
      );
    });
