// Pure logic of the Exam Engine taking flow (Phase 5, D-018) — what the layout harness and unit tests cover.
//
// Server contract: ../../../../../back/FLUTTER_API_CHANGES.md, "phase 5". Nothing here touches the network or the
// widget tree; `ExamTakingScreen` drives these pieces.
import 'dart:convert';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;

/// The authoritative timer: the server tells `remaining_seconds` at `server_time`; we count down from that instant
/// with the device clock's DELTA, never its absolute value, so a wrong device clock cannot help or hurt.
class ServerClock {
  ServerClock({required this.remainingSeconds, required DateTime receivedAt, this.deadlineAt}) : _receivedAt = receivedAt;
  final int? remainingSeconds;
  final DateTime _receivedAt;
  final DateTime? deadlineAt;

  int? remainingAt(DateTime now) {
    if (remainingSeconds == null) return null;
    final elapsed = now.difference(_receivedAt).inSeconds;
    final left = remainingSeconds! - elapsed;
    return left < 0 ? 0 : left;
  }

  bool get timed => remainingSeconds != null;

  static ServerClock? fromAttempt(Map<String, dynamic> attempt, DateTime receivedAt) {
    if (attempt['remaining_seconds'] == null) return ServerClock(remainingSeconds: null, receivedAt: receivedAt);
    return ServerClock(remainingSeconds: asInt(attempt['remaining_seconds']), receivedAt: receivedAt,
        deadlineAt: attempt['deadline_at'] == null ? null : DateTime.tryParse('${attempt['deadline_at']}Z'));
  }
}

/// "12:34" / "1:02:03" from seconds.
String clockText(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// A question of the paper as the student sees it.
class PaperQuestion {
  PaperQuestion({required this.questionId, required this.type, required this.points, required this.body, this.answer, this.saveSeq = 0,
      required this.sectionIndex, required this.index});
  final int questionId;
  final String type;
  final double points;
  final Map<String, dynamic> body;
  Map<String, dynamic>? answer;
  int saveSeq;
  final int sectionIndex;
  final int index;

  String get prompt => '${body['prompt'] ?? ''}';
  List<Map<String, dynamic>> get options => asMapList(body['options']);
  bool get answered => answer != null && answer!.values.any((v) => v != null && v != '' && v != const [] && !(v is List && v.isEmpty) && !(v is Map && v.isEmpty));
}

class PaperSection {
  PaperSection({required this.sectionId, required this.title, this.instructions, required this.mode, required this.navigation,
      this.timeBoxMinutes, required this.questions});
  final int sectionId;
  final String title;
  final String? instructions;
  final String mode;
  final String navigation;
  final int? timeBoxMinutes;
  final List<PaperQuestion> questions;
  bool get oneWay => navigation == 'one_way';
  bool get paper => mode == 'paper';
}

/// The paper flattened for navigation, with the section structure kept.
class Paper {
  Paper(this.sections);
  final List<PaperSection> sections;

  static Paper fromJson(Map<String, dynamic> paper) {
    final secs = <PaperSection>[];
    var si = 0;
    for (final s in asMapList(paper['sections'])) {
      final qs = <PaperQuestion>[];
      var qi = 0;
      for (final q in asMapList(s['questions'])) {
        qs.add(PaperQuestion(questionId: asInt(q['question_id']), type: '${q['type']}', points: (q['points'] as num?)?.toDouble() ?? 0,
            body: asMap(q['body']), answer: q['answer'] == null ? null : asMap(q['answer']), saveSeq: asInt(q['save_seq']),
            sectionIndex: si, index: qi));
        qi++;
      }
      secs.add(PaperSection(sectionId: asInt(s['section_id']), title: '${s['title'] ?? ''}', instructions: s['instructions'] as String?,
          mode: '${s['mode'] ?? 'online'}', navigation: '${s['navigation'] ?? 'free'}',
          timeBoxMinutes: s['time_box_minutes'] == null ? null : asInt(s['time_box_minutes']), questions: qs));
      si++;
    }
    return Paper(secs);
  }

  List<PaperQuestion> get all => [for (final s in sections) ...s.questions];
  int get answeredCount => all.where((q) => q.answered).length;
  int get onlineCount => [for (final s in sections) if (!s.paper) ...s.questions].length;

  /// May the student move from `from` to `to`? One-way sections refuse going back inside the section.
  bool canNavigate(PaperQuestion from, PaperQuestion to) {
    if (from.sectionIndex != to.sectionIndex) return to.sectionIndex >= from.sectionIndex || !sections[from.sectionIndex].oneWay;
    if (!sections[from.sectionIndex].oneWay) return true;
    return to.index >= from.index;
  }
}

/// Pending saves, one per question, with the monotonic `save_seq` the server de-duplicates on. A save that fails
/// stays queued; a newer answer for the same question replaces the queued one and bumps the sequence.
class AutosaveQueue {
  final Map<int, Map<String, dynamic>> _pending = {};
  final Map<int, int> _seq = {};

  void put(PaperQuestion q, Map<String, dynamic> answer) {
    q.answer = answer;
    q.saveSeq = (_seq[q.questionId] ?? q.saveSeq) + 1;
    _seq[q.questionId] = q.saveSeq;
    _pending[q.questionId] = {'question_id': q.questionId, 'answer': answer, 'save_seq': q.saveSeq};
  }

  bool get isEmpty => _pending.isEmpty;
  int get length => _pending.length;

  /// The batch to send; call [ack] with the server's `saved` + `ignored` lists afterwards.
  List<Map<String, dynamic>> batch() => _pending.values.map((e) => Map<String, dynamic>.from(e)).toList();

  void ack(List<Map<String, dynamic>> sent, Iterable<dynamic> savedOrIgnored) {
    final done = savedOrIgnored.map((e) => asInt(e)).toSet();
    for (final item in sent) {
      final qid = asInt(item['question_id']);
      final current = _pending[qid];
      if (current != null && done.contains(qid) && current['save_seq'] == item['save_seq']) _pending.remove(qid);
    }
  }
}

/// What the UI does with the server's `actions` after an events upload.
class PolicyAction {
  PolicyAction(this.consequence, this.category);
  final String consequence;
  final String category;
  bool get locks => consequence == 'lock';
  bool get submits => consequence == 'auto_submit';
  bool get warns => consequence == 'warn';
}

List<PolicyAction> actionsOf(Map<String, dynamic> reply) =>
    [for (final a in asMapList(reply['actions'])) PolicyAction('${a['consequence']}', '${a['category']}')];

/// Integrity events the platform layer reports; batched and sent every few seconds or at once for the serious ones.
class EventBuffer {
  final List<Map<String, dynamic>> _events = [];
  static const urgent = {'other_app', 'screenshot', 'multiple_faces'};

  void add(String kind, {Map<String, dynamic>? meta}) {
    _events.add({'kind': kind, 'client_at': DateTime.now().toUtc().toIso8601String(), if (meta != null) 'meta': meta});
  }

  bool get isEmpty => _events.isEmpty;
  bool get hasUrgent => _events.any((e) => urgent.contains(e['kind']));
  List<Map<String, dynamic>> drain() {
    final out = List<Map<String, dynamic>>.from(_events);
    _events.clear();
    return out;
  }
}

/// Bilingual texts for the taking flow's codes.
String examCodeText(String code) => switch (code) {
      'consent_required' => t('اقرأ الإقرار واقبله قبل بدء الاختبار', 'Read and accept the consent text before starting'),
      'consent_changed' => t('تغيّر نص الإقرار — اقرأ النسخة الجديدة ثم اقبلها', 'The consent text changed — read the new version and accept it'),
      'bad_passcode' => t('رمز الدخول غير صحيح', 'Wrong passcode'),
      'platform_not_allowed' => t('هذا الاختبار غير متاح على هذه المنصة', 'This exam is not available on this platform'),
      'not_a_student' => t('هذا الاختبار ليس لك', 'This exam is not for you'),
      'exam_not_open' => t('الاختبار غير متاح الآن', 'The exam is not open now'),
      'exam_not_started' => t('لم يبدأ الاختبار بعد', 'The exam has not started yet'),
      'exam_ended' => t('انتهى وقت الاختبار', 'The exam has ended'),
      'no_attempts_left' => t('استهلكت محاولاتك في هذا الاختبار', 'You have used all your attempts'),
      'exam_session_invalid' => t('انتهت جلسة الاختبار — يُعاد فتحها', 'The exam session expired — reopening'),
      'device_mismatch' => t('تابع الاختبار من الجهاز الذي بدأته عليه', 'Continue the exam on the device you started it on'),
      'deadline_passed' => t('انتهى الوقت وتم تسليم إجاباتك المحفوظة', 'Time is up — your saved answers were submitted'),
      'attempt_locked' => t('أُقفلت المحاولة — تواصل مع المراقب', 'The attempt is locked — contact the invigilator'),
      'one_way_section' => t('هذا القسم لا يسمح بالعودة إلى سؤال سابق', 'This section does not allow going back'),
      'attempt_submitted' => t('سُلّمت المحاولة بالفعل', 'Already submitted'),
      'event_not_consented' => t('هذا النوع من المراقبة غير مُفعَّل', 'This kind of monitoring is not enabled'),
      _ => code,
    };

/// The visible monitoring indicator text, from the accepted consent's `requires`.
String? monitoringText(Map<String, dynamic> requires) {
  final on = <String>[];
  if (requires['camera'] == true) on.add(t('الكاميرا', 'camera'));
  if (requires['mic'] == true) on.add(t('الميكروفون', 'microphone'));
  if (requires['screen'] == true) on.add(t('الشاشة', 'screen'));
  if (on.isEmpty) return null;
  return t('المراقبة مفعّلة: ${on.join('، ')}', 'Monitoring on: ${on.join(', ')}');
}

/// SHA-free hash check helper: the server compares the hash we send with the text's; we only pass it through.
String consentHashOf(Map<String, dynamic> consent) => '${consent['text_hash'] ?? ''}';

/// Answer encoders per type (what the server expects).
Map<String, dynamic> encodeSingle(String optionId) => {'option': optionId};
Map<String, dynamic> encodeMulti(Iterable<String> ids) => {'options': ids.toList()..sort()};
Map<String, dynamic> encodeTrueFalse(bool v) => {'value': v};
Map<String, dynamic> encodeBlanks(List<String> blanks) => {'blanks': blanks};
Map<String, dynamic> encodeMatching(Map<String, String> pairs) => {'pairs': pairs};
Map<String, dynamic> encodeOrdering(List<String> order) => {'order': order};
Map<String, dynamic> encodeNumeric(String value, {String? unit}) => {'value': value.trim(), if (unit != null && unit.isNotEmpty) 'unit': unit};
Map<String, dynamic> encodeText(String text) => {'text': text};

/// For tests: a stable JSON of an answer map.
String answerKey(Map<String, dynamic>? a) => a == null ? '' : jsonEncode(a);
