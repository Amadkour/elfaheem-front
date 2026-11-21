// lib/features/teachers/teachers_models.dart — Learning Hub v2 teachers and packages (D-1620 .. D-1639): the shapes
// of docs/learning-hub-v2/CONTRACT.md §1 (TeacherProfile) and §2 (Package), the subject list, the wizard checks and
// the one mapping from a package to what its Join button says (packageJoinState).
//
// One flow for every subject (quran, tajweed, fiqh, nahw): the Quran teacher card (lib/features/quran/) reads the
// same table on the server, so this file replaces nothing there; the Quran pages link here.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/course_price_tag.dart' show coursePriceLabel;
import 'package:flutter_education_app/features/home/student/models.dart' show AppCurrencyX;

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

// ── closed lists (server enums) ───────────────────────────────────────────────

const List<String> kTeacherSubjects = ['quran', 'tajweed', 'fiqh', 'nahw'];
const List<String> kTeacherGenders = ['male', 'female'];
const List<String> kTeacherDocTypes = ['ijazah', 'certificate', 'id', 'other'];
/// Kept from the Quran card (Corrections v2 C1): how a session is held, and where (a separate list).
const List<String> kTeacherSessionTypes = ['individual', 'group'];
const List<String> kTeacherDeliveryModes = ['online', 'offline'];
const List<String> kPackageLevels = ['all', 'beginner', 'intermediate', 'advanced'];
const List<String> kPackageDeliveries = ['online', 'offline', 'both'];
const List<String> kPackageOverbook = ['none', 'allow', 'waitlist'];
const List<String> kPackageCurrencies = ['EGP', 'SAR', 'USD'];

/// Image or PDF, at most 10 MB (the server sniffs the bytes again).
const List<String> kTeacherDocExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'webp'];
const int kTeacherDocMaxBytes = 10 * 1024 * 1024;

String teacherSubjectLabel(String s) => switch (s) {
      'quran' => _t('القرآن', 'Quran'),
      'tajweed' => _t('التجويد', 'Tajweed'),
      'fiqh' => _t('الفقه', 'Fiqh'),
      'nahw' => _t('النحو', 'Arabic grammar'),
      _ => s,
    };

String teacherGenderLabel(String? g) => switch (g) {
      'male' => _t('معلم', 'Male teacher'),
      'female' => _t('معلمة', 'Female teacher'),
      _ => _t('غير محدد', 'Not set'),
    };

String teacherDocTypeLabel(String d) => switch (d) {
      'ijazah' => _t('إجازة', 'Ijazah'),
      'certificate' => _t('شهادة', 'Certificate'),
      'id' => _t('إثبات هوية', 'ID document'),
      _ => _t('مستند آخر', 'Other document'),
    };

String teacherStatusLabel(String? s) => switch (s) {
      'approved' => _t('معتمد', 'Approved'),
      'pending' => _t('قيد المراجعة', 'Under review'),
      'rejected' => _t('مرفوض', 'Rejected'),
      'draft' => _t('مسودة', 'Draft'),
      _ => _t('لم يبدأ', 'Not started'),
    };

String teacherSessionTypeLabel(String s) => switch (s) {
      'group' => _t('جماعي', 'Group'),
      _ => _t('فردي', 'One to one'),
    };

String packageLevelLabel(String l) => switch (l) {
      'beginner' => _t('مبتدئ', 'Beginner'),
      'intermediate' => _t('متوسط', 'Intermediate'),
      'advanced' => _t('متقدم', 'Advanced'),
      _ => _t('كل المستويات', 'All levels'),
    };

String packageDeliveryLabel(String d) => switch (d) {
      'offline' => _t('حضوري', 'In person'),
      'both' => _t('أونلاين وحضوري', 'Online and in person'),
      _ => _t('أونلاين', 'Online'),
    };

String packageStatusLabel(String s) => switch (s) {
      'published' => _t('منشورة', 'Published'),
      'paused' => _t('متوقفة مؤقتاً', 'Paused'),
      'closed' => _t('مغلقة', 'Closed'),
      _ => _t('مسودة', 'Draft'),
    };

/// One line per overbooking choice (the wizard shows it under the choice).
String packageOverbookLabel(String o) => switch (o) {
      'allow' => _t('السماح بالزيادة', 'Allow extra seats'),
      'waitlist' => _t('قائمة انتظار', 'Waiting list'),
      _ => _t('بلا زيادة', 'No extra seats'),
    };

String packageOverbookHelp(String o) => switch (o) {
      'allow' => _t('يستمر الحجز بعد اكتمال المقاعد، وتقرر أنت كيف تستوعبهم.',
          'Booking stays open after the seats fill; you decide how to fit everyone.'),
      'waitlist' => _t('عند الاكتمال ينضم الطلاب لقائمة انتظار دون دفع، ويُرقّى الأول عند خروج أحد.',
          'When full, students join a waiting list without paying; the first moves up when a seat frees.'),
      _ => _t('عند اكتمال المقاعد يتوقف الحجز.', 'Booking stops when the seats are full.'),
    };

// ── parsing helpers ──────────────────────────────────────────────────────────

int _int(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
int? _intOrNull(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double _dbl(Object? v, [double d = 0]) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? d;
double? _dblOrNull(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
String _str(Object? v) => v == null ? '' : '$v';
String? _strOrNull(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
List<String> _strs(Object? v) => [if (v is List) for (final e in v) if (e != null && '$e'.isNotEmpty) '$e'];
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => [if (v is List) for (final e in v) if (e is Map) Map<String, dynamic>.from(e)];

/// The server's naive UTC strings ("…Z"-less) read as UTC.
DateTime? teachersParseUtc(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final hasZone = v.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(v);
  return DateTime.tryParse(hasZone ? v : '${v}Z')?.toUtc();
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "YYYY-MM-DD" → a local calendar day (null when not a date).
DateTime? parseYmd(Object? v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${v ?? ''}');
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

String formatYmd(DateTime d) => _ymd(d);

// ── teacher profile ──────────────────────────────────────────────────────────

class TeacherDoc {
  const TeacherDoc({required this.id, required this.docType, required this.fileName, this.status = 'pending', this.rejectionReason, this.size});

  factory TeacherDoc.fromJson(Map<String, dynamic> j) => TeacherDoc(
        id: _int(j['id']),
        docType: _str(j['doc_type']).isEmpty ? 'other' : _str(j['doc_type']),
        fileName: _str(j['file_name']),
        status: _str(j['status']).isEmpty ? 'pending' : _str(j['status']),
        rejectionReason: _strOrNull(j['rejection_reason']),
        size: _intOrNull(j['size'] ?? j['file_size']),
      );

  final int id;
  final String docType, fileName, status;
  final String? rejectionReason;

  /// Bytes, when the server sends it (the contract does not promise it; the wizard knows it at upload).
  final int? size;

  bool get isPdf => fileName.toLowerCase().endsWith('.pdf');
}

class TeacherReview {
  const TeacherReview({required this.name, required this.rating, this.comment, this.createdAt});

  factory TeacherReview.fromJson(Map<String, dynamic> j) => TeacherReview(
        name: _str(j['name'] ?? j['student_name'] ?? j['first_name']),
        rating: _dbl(j['rating']),
        comment: _strOrNull(j['comment'] ?? j['text']),
        createdAt: teachersParseUtc(j['created_at']),
      );

  final String name;
  final double rating;
  final String? comment;
  final DateTime? createdAt;
}

class TeacherProfile {
  const TeacherProfile({
    required this.userId,
    this.name = '',
    this.avatarUrl,
    this.gender,
    this.subjects = const [],
    this.bio = '',
    this.qualifications = '',
    this.languages = const [],
    this.yearsExperience = 0,
    this.goals = const [],
    this.sessionTypes = const [],
    this.delivery = const [],
    this.status = 'draft',
    this.rejectionReason,
    this.submittedAt,
    this.reviewedAt,
    this.documents = const [],
    this.rating,
    this.reviewsCount = 0,
    this.packagesCount = 0,
    this.nextFree,
    this.packages = const [],
    this.reviews = const [],
  });

  /// No profile yet (GET /me/teacher-profile answered 404 `no_profile`): a fresh draft.
  static const TeacherProfile empty = TeacherProfile(userId: 0, status: 'none');

  factory TeacherProfile.fromJson(Object? raw) {
    final j = _map(raw);
    final g = _str(j['gender']);
    return TeacherProfile(
      userId: _int(j['user_id'] ?? j['id']),
      name: _str(j['name']),
      avatarUrl: _strOrNull(j['avatar_url']),
      gender: switch (g) { 'male' || 'm' => 'male', 'female' || 'f' => 'female', _ => null },
      subjects: [for (final s in _strs(j['subjects'])) if (kTeacherSubjects.contains(s)) s],
      bio: _str(j['bio']),
      qualifications: _str(j['qualifications']),
      languages: _strs(j['languages']),
      yearsExperience: _int(j['years_experience']),
      goals: _strs(j['goals']),
      sessionTypes: _strs(j['session_types']),
      delivery: [for (final d in _strs(j['delivery'])) if (kTeacherDeliveryModes.contains(d)) d],
      status: _str(j['status']).isEmpty ? 'draft' : _str(j['status']),
      rejectionReason: _strOrNull(j['rejection_reason']),
      submittedAt: teachersParseUtc(j['submitted_at']),
      reviewedAt: teachersParseUtc(j['reviewed_at']),
      documents: [for (final d in _maps(j['documents'])) TeacherDoc.fromJson(d)],
      rating: _dblOrNull(j['rating']),
      reviewsCount: _int(j['reviews_count']),
      packagesCount: _int(j['packages_count']),
      nextFree: teachersParseUtc(j['next_free']),
      packages: [for (final p in _maps(j['packages'])) TeacherPackage.fromJson(p)],
      reviews: [for (final r in _maps(j['reviews'])) TeacherReview.fromJson(r)],
    );
  }

  final int userId;
  final String name;
  final String? avatarUrl;
  final String? gender;
  final List<String> subjects;
  final String bio, qualifications;
  final List<String> languages;
  final int yearsExperience;
  final List<String> goals, sessionTypes;

  /// online / offline (Corrections v2 C1).
  final List<String> delivery;

  /// draft | pending | approved | rejected ("none" = no profile yet, never from the server).
  final String status;
  final String? rejectionReason;
  final DateTime? submittedAt, reviewedAt;
  final List<TeacherDoc> documents;
  final double? rating;
  final int reviewsCount, packagesCount;
  final DateTime? nextFree;
  final List<TeacherPackage> packages;
  final List<TeacherReview> reviews;

  bool get exists => status != 'none';
  bool get approved => status == 'approved';
  bool get pending => status == 'pending';
  bool get rejected => status == 'rejected';

  /// Documents can be removed until the profile is approved (DELETE refuses afterwards).
  bool get docsEditable => !approved;
}

/// What the wizard sends with PUT /me/teacher-profile (the whole object).
class TeacherProfileDraft {
  TeacherProfileDraft({
    this.name = '',
    this.gender,
    List<String>? subjects,
    this.bio = '',
    this.qualifications = '',
    List<String>? languages,
    this.yearsExperience = 0,
    this.avatarUrl,
    List<String>? goals,
    List<String>? sessionTypes,
    List<String>? delivery,
  })  : subjects = subjects ?? [],
        languages = languages ?? [],
        goals = goals ?? [],
        sessionTypes = sessionTypes ?? [],
        delivery = delivery ?? [];

  factory TeacherProfileDraft.of(TeacherProfile p) => TeacherProfileDraft(
        name: p.name,
        gender: p.gender,
        subjects: [...p.subjects],
        bio: p.bio,
        qualifications: p.qualifications,
        languages: [...p.languages],
        yearsExperience: p.yearsExperience,
        avatarUrl: p.avatarUrl,
        goals: [...p.goals],
        sessionTypes: [...p.sessionTypes],
        delivery: [...p.delivery],
      );

  String name;
  String? gender;
  List<String> subjects;
  String bio, qualifications;
  List<String> languages;
  int yearsExperience;
  String? avatarUrl;
  List<String> goals, sessionTypes, delivery;

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'gender': gender,
        'subjects': [for (final s in kTeacherSubjects) if (subjects.contains(s)) s],
        'bio': bio.trim(),
        'qualifications': qualifications.trim(),
        'languages': [for (final l in languages) if (l.trim().isNotEmpty) l.trim()],
        'years_experience': yearsExperience,
        'avatar_url': avatarUrl,
        'goals': goals,
        'session_types': [for (final s in kTeacherSessionTypes) if (sessionTypes.contains(s)) s],
        'delivery': [for (final d in kTeacherDeliveryModes) if (delivery.contains(d)) d],
      };

  /// Changing one of these on an approved profile sends it back to review (contract §1).
  bool reReviewsAgainst(TeacherProfile p) =>
      p.approved &&
      (gender != p.gender ||
          qualifications.trim() != p.qualifications.trim() ||
          ({...subjects}.length != {...p.subjects}.length || !subjects.every(p.subjects.contains)));
}

/// The onboarding wizard's steps.
enum TeacherStep { profile, subjects, documents, review }

/// The first problem of one wizard step (null = the step may be left). Mirrors the server's `profile_incomplete`
/// (name, gender, ≥ 1 subject, bio, ≥ 1 document) plus the ranges the fields allow.
String? teacherStepError(TeacherStep step, TeacherProfileDraft d, {int documents = 0}) {
  switch (step) {
    case TeacherStep.profile:
      if (d.name.trim().length < 2) return _t('اكتب اسمك كما يراه الطلاب', 'Write your name as students will see it');
      if (d.name.trim().length > 120) return _t('الاسم أطول من 120 حرفاً', 'The name is longer than 120 characters');
      if (d.gender == null) return _t('اختر: معلم أم معلمة', 'Choose: male or female teacher');
      if (d.bio.trim().length < 20) return _t('اكتب نبذة من 20 حرفاً على الأقل', 'Write an introduction of at least 20 characters');
      if (d.bio.trim().length > 4000) return _t('النبذة أطول من 4000 حرف', 'The introduction is longer than 4000 characters');
      if (d.yearsExperience < 0 || d.yearsExperience > 70) return _t('سنوات الخبرة من 0 إلى 70', 'Years of experience run from 0 to 70');
      return null;
    case TeacherStep.subjects:
      if (d.subjects.isEmpty) return _t('اختر مادة واحدة على الأقل', 'Choose at least one subject');
      if (d.qualifications.trim().length > 2000) return _t('المؤهلات أطول من 2000 حرف', 'The qualifications are longer than 2000 characters');
      return null;
    case TeacherStep.documents:
      if (documents < 1) return _t('أرفق مستنداً واحداً على الأقل (إجازة أو شهادة)', 'Attach at least one document (an ijazah or a certificate)');
      return null;
    case TeacherStep.review:
      for (final s in TeacherStep.values) {
        if (s == TeacherStep.review) break;
        final e = teacherStepError(s, d, documents: documents);
        if (e != null) return e;
      }
      return null;
  }
}

/// The first step with a problem (the review step's "Fix" goes there), null when the draft can be submitted.
TeacherStep? teacherFirstBadStep(TeacherProfileDraft d, {int documents = 0}) {
  for (final s in TeacherStep.values) {
    if (s == TeacherStep.review) break;
    if (teacherStepError(s, d, documents: documents) != null) return s;
  }
  return null;
}

/// A document picked on the device: the checks the wizard runs before sending it (null = fine).
String? teacherDocPickError(String fileName, int bytes) {
  final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase() : '';
  if (!kTeacherDocExtensions.contains(ext)) return _t('صورة أو ملف PDF فقط', 'Only an image or a PDF');
  if (bytes <= 0) return _t('الملف فارغ', 'The file is empty');
  if (bytes > kTeacherDocMaxBytes) return _t('الملف أكبر من 10 ميجابايت', 'The file is larger than 10 MB');
  return null;
}

// ── packages ─────────────────────────────────────────────────────────────────

class PackageTeacher {
  const PackageTeacher({required this.userId, this.name = '', this.avatarUrl, this.gender});

  factory PackageTeacher.fromJson(Object? raw) {
    final j = _map(raw);
    return PackageTeacher(userId: _int(j['user_id'] ?? j['id']), name: _str(j['name']), avatarUrl: _strOrNull(j['avatar_url']), gender: _strOrNull(j['gender']));
  }

  final int userId;
  final String name;
  final String? avatarUrl, gender;
}

class PackageEnrollment {
  const PackageEnrollment({required this.status, this.position, this.expiresAt});

  static PackageEnrollment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final s = _str(j['status']);
    if (s.isEmpty) return null;
    return PackageEnrollment(
      status: s,
      position: _intOrNull(j['position']),
      expiresAt: teachersParseUtc(j['expires_at'] ?? j['hold_until'] ?? j['offer_expires_at']),
    );
  }

  /// pending_payment (a 30 min hold) | active | waitlisted | offered (24 h to pay) | expired | cancelled
  /// (Corrections v2 C3).
  final String status;
  final int? position;

  /// When a pending_payment hold or an offer ends (the countdown).
  final DateTime? expiresAt;

  /// The seat is mine or held for me (expired / cancelled are not: the student may join again).
  bool get live => const {'pending_payment', 'active', 'waitlisted', 'offered'}.contains(status);
}

class TeacherPackage {
  const TeacherPackage({
    required this.id,
    this.teacherId = 0,
    this.teacher,
    this.subject = 'quran',
    this.title = '',
    this.description = '',
    this.goal = '',
    this.level = 'all',
    this.delivery = 'online',
    this.location,
    this.sessionsCount = 8,
    this.sessionMinutes = 60,
    this.schedule,
    this.seriesId,
    this.startDate,
    this.maxStudents = 10,
    this.overbook = 'none',
    this.overbookLimit,
    this.price = 0,
    this.currency = 'EGP',
    this.discountPercent,
    this.finalPrice = 0,
    this.status = 'draft',
    this.seatsTaken = 0,
    this.waitlistCount = 0,
    this.myEnrollment,
    this.createdAt,
  });

  factory TeacherPackage.fromJson(Object? raw) {
    final j = _map(raw);
    final teacher = j['teacher'] is Map ? PackageTeacher.fromJson(j['teacher']) : null;
    final price = _dbl(j['price']);
    final discount = _intOrNull(j['discount_percent']);
    return TeacherPackage(
      id: _int(j['id']),
      teacherId: _int(j['teacher_id'] ?? teacher?.userId),
      teacher: teacher,
      subject: _str(j['subject']).isEmpty ? 'quran' : _str(j['subject']),
      title: _str(j['title']),
      description: _str(j['description']),
      goal: _str(j['goal']),
      level: _str(j['level']).isEmpty ? 'all' : _str(j['level']),
      delivery: _str(j['delivery']).isEmpty ? 'online' : _str(j['delivery']),
      location: _strOrNull(j['location']),
      sessionsCount: _int(j['sessions_count'], 1),
      sessionMinutes: _int(j['session_minutes'], 60),
      schedule: j['schedule'] is Map ? Map<String, dynamic>.from(j['schedule'] as Map) : null,
      seriesId: _intOrNull(j['series_id']),
      startDate: parseYmd(j['start_date']),
      maxStudents: _int(j['max_students'], 1),
      overbook: _str(j['overbook']).isEmpty ? 'none' : _str(j['overbook']),
      overbookLimit: _intOrNull(j['overbook_limit']),
      price: price,
      currency: _str(j['currency']).isEmpty ? 'EGP' : _str(j['currency']).toUpperCase(),
      discountPercent: discount,
      finalPrice: j['final_price'] == null ? packageFinalPrice(price, discount) : _dbl(j['final_price']),
      status: _str(j['status']).isEmpty ? 'draft' : _str(j['status']),
      seatsTaken: _int(j['seats_taken']),
      waitlistCount: _int(j['waitlist_count']),
      myEnrollment: PackageEnrollment.fromJson(j['my_enrollment']),
      createdAt: teachersParseUtc(j['created_at']),
    );
  }

  final int id, teacherId;
  final PackageTeacher? teacher;
  final String subject, title, description, goal, level, delivery;
  final String? location;
  final int sessionsCount, sessionMinutes;
  final Map<String, dynamic>? schedule;
  final int? seriesId;
  final DateTime? startDate;
  final int maxStudents;
  final String overbook;

  /// overbook = allow: extra seats above [maxStudents] (null = no limit).
  final int? overbookLimit;
  final double price;
  final String currency;
  final int? discountPercent;
  final double finalPrice;
  final String status;
  final int seatsTaken, waitlistCount;
  final PackageEnrollment? myEnrollment;
  final DateTime? createdAt;

  int get seatsLeft => (maxStudents - seatsTaken).clamp(0, maxStudents);
  bool get isFull => seatsLeft <= 0;

  /// Full and nothing more can be taken (an allowed overbooking with room left is not).
  bool get isClosedFull =>
      isFull && !(overbook == 'allow' && (overbookLimit == null || seatsTaken < maxStudents + overbookLimit!));
  bool get hasDiscount => (discountPercent ?? 0) > 0 && price > 0;
  bool get isFree => finalPrice <= 0;
}

/// price × (1 − discount %), rounded to cents (what the server's `final_price` is).
double packageFinalPrice(double price, int? discountPercent) {
  final d = (discountPercent ?? 0).clamp(0, 90);
  return (price * (100 - d) / 100 * 100).roundToDouble() / 100;
}

/// The one price text (the course formatter: "free", "150 ج.م", "EGP 150", "$150").
String packagePriceLabel(double price, String currency) => coursePriceLabel(AppCurrencyX.fromCode(currency), price);

/// What the student's button shows for a package.
enum PackageJoinState {
  /// a free seat is open
  join,

  /// a paid seat is open: Join starts the checkout
  pay,

  /// full, overbook = waitlist: join the waiting list (never charged)
  joinWaitlist,

  /// full, overbook = none
  full,

  /// draft / paused: not open
  notOpen,
  closed,

  /// my seat
  active,
  waitlisted,

  /// a seat held 30 min for my payment: "Pay now" with a countdown
  pendingPayment,

  /// promoted from the waiting list: 24 h to pay, highlighted
  offered,
}

PackageJoinState packageJoinState(TeacherPackage p) {
  switch (p.myEnrollment?.status) {
    case 'active':
      return PackageJoinState.active;
    case 'waitlisted':
      return PackageJoinState.waitlisted;
    case 'pending_payment':
      return PackageJoinState.pendingPayment;
    case 'offered':
      return PackageJoinState.offered;
  }
  // expired / cancelled / none: the student may join again
  if (p.status == 'closed') return PackageJoinState.closed;
  if (p.status != 'published') return PackageJoinState.notOpen;
  if (p.isClosedFull) return p.overbook == 'waitlist' ? PackageJoinState.joinWaitlist : PackageJoinState.full;
  return p.isFree ? PackageJoinState.join : PackageJoinState.pay;
}

/// The words of a join state (a button label for the open ones, a status line for the others).
String packageJoinLabel(PackageJoinState s, {int? position}) => switch (s) {
      PackageJoinState.join => _t('انضم', 'Join'),
      PackageJoinState.pay => _t('انضم وادفع', 'Join and pay'),
      PackageJoinState.joinWaitlist => _t('انضم لقائمة الانتظار', 'Join the waiting list'),
      PackageJoinState.full => _t('اكتملت المقاعد', 'Full'),
      PackageJoinState.notOpen => _t('غير متاحة الآن', 'Not open now'),
      PackageJoinState.closed => _t('أُغلقت الباقة', 'Closed'),
      PackageJoinState.active => _t('أنت مشترك', 'You are in'),
      PackageJoinState.waitlisted => position == null
          ? _t('في قائمة الانتظار', 'On the waiting list')
          : _t('في قائمة الانتظار: رقم $position', 'On the waiting list: number $position'),
      PackageJoinState.pendingPayment => _t('ادفع الآن', 'Pay now'),
      PackageJoinState.offered => _t('مقعد محجوز لك: ادفع الآن', 'A seat is offered to you: pay now'),
    };

/// True when the state is a button the student can press (pending payment = "Pay now").
bool packageJoinActionable(PackageJoinState s) =>
    s == PackageJoinState.join || s == PackageJoinState.pay || s == PackageJoinState.joinWaitlist || s == PackageJoinState.pendingPayment || s == PackageJoinState.offered;

/// The seat is mine or held for me.
bool packageJoinMine(PackageJoinState s) =>
    s == PackageJoinState.active || s == PackageJoinState.waitlisted || s == PackageJoinState.pendingPayment || s == PackageJoinState.offered;

/// "12:04" / "23 h 10 min" left on a hold or an offer (null when there is no end or it passed).
String? packageHoldLeft(DateTime? endsAt, {DateTime? now}) {
  if (endsAt == null) return null;
  final d = endsAt.difference((now ?? DateTime.now()).toUtc());
  if (d.isNegative) return null;
  if (d.inHours >= 1) return _t('${d.inHours} س ${d.inMinutes % 60} د', '${d.inHours} h ${d.inMinutes % 60} min');
  return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// POST /packages/{id}/enroll.
class PackageEnrollResult {
  const PackageEnrollResult({required this.status, this.position, this.checkout, this.expiresAt});

  factory PackageEnrollResult.fromJson(Object? raw) {
    final j = _map(raw);
    final checkout = j['checkout'] is Map ? Map<String, dynamic>.from(j['checkout'] as Map) : null;
    return PackageEnrollResult(
      status: _str(j['status']).isEmpty ? 'active' : _str(j['status']),
      position: _intOrNull(j['position']),
      checkout: checkout,
      expiresAt: teachersParseUtc(j['expires_at'] ?? j['hold_until']),
    );
  }

  /// active | waitlisted | pending_payment (a paid seat, held 30 min until paid).
  final String status;
  final int? position;

  /// The store-style payment start (Corrections v2 C2): `{url, token, provider, amount_minor, is_sandbox}`.
  final Map<String, dynamic>? checkout;
  final DateTime? expiresAt;

  /// The page to open: the store's `url` (an older shape's `checkout_url` is read too).
  String get checkoutUrl => checkout == null ? '' : '${checkout!['url'] ?? checkout!['checkout_url'] ?? ''}'.trim();

  bool get needsPayment => checkoutUrl.isNotEmpty;
  bool get waitlisted => status == 'waitlisted';

  /// The state the package shows right after this answer.
  PackageJoinState get state => needsPayment
      ? PackageJoinState.pendingPayment
      : waitlisted
          ? PackageJoinState.waitlisted
          : PackageJoinState.active;
}

/// One roster row (GET /packages/{id}/enrollments).
class PackageRosterRow {
  const PackageRosterRow({required this.studentId, required this.name, this.avatarUrl, required this.status, this.position, this.joinedAt});

  /// The server nests the person: `{id, student: {user_id, name, avatar_url}, status, position, …}`
  /// (`package_service.py`); a flat row is still read for an older shape.
  factory PackageRosterRow.fromJson(Map<String, dynamic> j) {
    final st = _map(j['student']);
    return PackageRosterRow(
      studentId: _int(st['user_id'] ?? st['id'] ?? j['student_id'] ?? j['user_id']),
      name: _str(st['name'] ?? j['name'] ?? j['student_name']),
      avatarUrl: _strOrNull(st['avatar_url'] ?? st['image_url'] ?? j['avatar_url'] ?? j['image_url']),
      status: _str(j['status']),
      position: _intOrNull(j['position']),
      joinedAt: teachersParseUtc(j['created_at'] ?? j['joined_at']),
    );
  }

  final int studentId;
  final String name;
  final String? avatarUrl;
  final String status;
  final int? position;
  final DateTime? joinedAt;
}

List<PackageRosterRow> packageRosterFromJson(Object? raw) {
  final items = raw is Map ? raw['items'] : raw;
  return [for (final m in _maps(items)) PackageRosterRow.fromJson(m)];
}

/// A package payment that arrived with no seat to give, so the money goes back (GET /admin/packages/refunds-due;
/// D-1640). [reason] is `left` | `closed` | `duplicate`.
class PackageRefundDue {
  const PackageRefundDue({
    required this.paymentId,
    required this.packageId,
    required this.packageTitle,
    required this.studentId,
    required this.studentName,
    required this.amount,
    required this.currency,
    this.provider = '',
    this.gatewayId,
    required this.reason,
    this.paidAt,
  });

  factory PackageRefundDue.fromJson(Map<String, dynamic> j) {
    final pkg = _map(j['package']), st = _map(j['student']);
    return PackageRefundDue(
      paymentId: _int(j['payment_id'] ?? j['id']),
      packageId: _int(pkg['id']),
      packageTitle: _str(pkg['title']),
      studentId: _int(st['user_id'] ?? st['id']),
      studentName: _str(st['name']),
      amount: _dbl(j['amount']),
      currency: _str(j['currency']),
      provider: _str(j['provider']),
      gatewayId: _strOrNull(j['gateway_id']),
      reason: _str(j['reason']),
      paidAt: teachersParseUtc(j['paid_at']),
    );
  }

  final int paymentId, packageId, studentId;
  final String packageTitle, studentName, currency, provider, reason;
  final double amount;
  final String? gatewayId;
  final DateTime? paidAt;
}

List<PackageRefundDue> packageRefundsFromJson(Object? raw) {
  final items = raw is Map ? raw['items'] : raw;
  return [for (final m in _maps(items)) PackageRefundDue.fromJson(m)];
}

/// Why the payment is owed back, as one plain sentence.
String packageRefundReasonText(String reason) => switch (reason) {
      'left' => _t('ترك الطالب الباقة قبل وصول الدفعة.', 'The student left the package before the payment arrived.'),
      'closed' => _t('أُغلقت الباقة قبل وصول الدفعة.', 'The package was closed before the payment arrived.'),
      'duplicate' => _t('دفع الطالب لمقعد مدفوع من قبل.', 'The student paid for a seat that was already paid.'),
      _ => _t('لم تمنح هذه الدفعة مقعداً.', 'This payment gave no seat.'),
    };

List<TeacherPackage> packagesFromJson(Object? raw) {
  final items = raw is Map ? raw['items'] : raw;
  return [for (final m in _maps(items)) TeacherPackage.fromJson(m)];
}

/// What the package wizard edits (POST / PUT /packages: the whole object).
class PackageDraft {
  PackageDraft({
    this.subject,
    this.title = '',
    this.description = '',
    this.goal = '',
    this.level = 'all',
    this.delivery = 'online',
    this.location = '',
    this.sessionsCount = 8,
    this.sessionMinutes = 60,
    this.startDate,
    this.schedule,
    this.maxStudents = 10,
    this.overbook = 'waitlist',
    this.overbookLimit,
    this.price = 0,
    this.currency = 'EGP',
    this.discountPercent = 0,
  });

  /// Sensible defaults: the teacher's first subject, 8 sessions of an hour from next week, 10 seats with a waiting
  /// list, free until a price is typed.
  factory PackageDraft.defaults({List<String> subjects = const [], DateTime? today}) {
    final d = today ?? DateTime.now();
    return PackageDraft(
      subject: subjects.isEmpty ? null : subjects.first,
      startDate: DateTime(d.year, d.month, d.day).add(const Duration(days: 7)),
    );
  }

  factory PackageDraft.of(TeacherPackage p) => PackageDraft(
        subject: p.subject,
        title: p.title,
        description: p.description,
        goal: p.goal,
        level: p.level,
        delivery: p.delivery,
        location: p.location ?? '',
        sessionsCount: p.sessionsCount,
        sessionMinutes: p.sessionMinutes,
        startDate: p.startDate,
        schedule: p.schedule == null ? null : Map<String, dynamic>.from(p.schedule!),
        maxStudents: p.maxStudents,
        overbook: p.overbook,
        overbookLimit: p.overbookLimit,
        price: p.price,
        currency: p.currency,
        discountPercent: p.discountPercent ?? 0,
      );

  String? subject;
  String title, description, goal, level, delivery, location;
  int sessionsCount, sessionMinutes;
  DateTime? startDate;
  Map<String, dynamic>? schedule;
  int maxStudents;
  String overbook;

  /// overbook = allow: extra seats (null = no limit).
  int? overbookLimit;
  double price;
  String currency;
  int discountPercent;

  bool get needsLocation => delivery != 'online';
  double get finalPrice => packageFinalPrice(price, discountPercent);

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'title': title.trim(),
        'description': description.trim(),
        'goal': goal.trim(),
        'level': level,
        'delivery': delivery,
        'location': needsLocation && location.trim().isNotEmpty ? location.trim() : null,
        'sessions_count': sessionsCount,
        'session_minutes': sessionMinutes,
        'schedule': schedule,
        'start_date': startDate == null ? null : _ymd(startDate!),
        'max_students': maxStudents,
        'overbook': overbook,
        'overbook_limit': overbook == 'allow' ? overbookLimit : null,
        'price': price,
        'currency': currency,
        'discount_percent': discountPercent <= 0 ? null : discountPercent,
      };
}

/// The package wizard's steps.
enum PackageStep { basics, schedule, price }

/// Field → problem for one step (empty = the step may be left). The ranges are the contract's (§2).
Map<String, String> packageStepErrors(PackageStep step, PackageDraft d, {DateTime? today, bool locked = false}) {
  final e = <String, String>{};
  switch (step) {
    case PackageStep.basics:
      if (d.subject == null || !kTeacherSubjects.contains(d.subject)) e['subject'] = _t('اختر المادة', 'Choose the subject');
      if (d.title.trim().length < 3) e['title'] = _t('اكتب عنواناً من 3 أحرف على الأقل', 'Write a title of at least 3 characters');
      if (d.title.trim().length > 200) e['title'] = _t('العنوان أطول من 200 حرف', 'The title is longer than 200 characters');
      if (d.description.trim().length > 4000) e['description'] = _t('الوصف أطول من 4000 حرف', 'The description is longer than 4000 characters');
      if (d.needsLocation && d.location.trim().isEmpty) e['location'] = _t('اكتب مكان الجلسات الحضورية', 'Write where the in-person sessions happen');
    case PackageStep.schedule:
      if (d.sessionsCount < 1 || d.sessionsCount > 200) e['sessions_count'] = _t('عدد الجلسات من 1 إلى 200', 'Sessions run from 1 to 200');
      if (d.sessionMinutes < 15 || d.sessionMinutes > 240) e['session_minutes'] = _t('مدة الجلسة من 15 إلى 240 دقيقة', 'A session lasts 15 to 240 minutes');
      if (d.startDate == null) {
        e['start_date'] = _t('اختر تاريخ البدء', 'Choose the start date');
      } else if (!locked) {
        final n = today ?? DateTime.now();
        if (d.startDate!.isBefore(DateTime(n.year, n.month, n.day))) e['start_date'] = _t('تاريخ البدء في الماضي', 'The start date is in the past');
      }
    case PackageStep.price:
      if (d.price < 0) e['price'] = _t('السعر لا يقل عن صفر', 'The price cannot be below zero');
      if (d.price > 1000000) e['price'] = _t('السعر كبير جداً', 'The price is too high');
      if (d.discountPercent < 0 || d.discountPercent > 90) e['discount_percent'] = _t('الخصم من 0 إلى 90٪', 'The discount runs from 0 to 90 %');
      if (d.maxStudents < 1 || d.maxStudents > 500) e['max_students'] = _t('عدد الطلاب من 1 إلى 500', 'Students run from 1 to 500');
      if (d.overbook == 'allow' && d.overbookLimit != null && (d.overbookLimit! < 1 || d.overbookLimit! > 500)) {
        e['overbook_limit'] = _t('المقاعد الإضافية من 1 إلى 500، أو اتركها فارغة بلا حد',
            'Extra seats run from 1 to 500, or leave it blank for no limit');
      }
      if (!kPackageOverbook.contains(d.overbook)) e['overbook'] = _t('اختر ماذا يحدث عند الاكتمال', 'Choose what happens when full');
  }
  return e;
}

/// Every step's problems at once (the Save button checks this).
Map<String, String> packageDraftErrors(PackageDraft d, {DateTime? today, bool locked = false}) => {
      for (final s in PackageStep.values) ...packageStepErrors(s, d, today: today, locked: locked),
    };

// ── discovery ────────────────────────────────────────────────────────────────

class TeacherFilters {
  const TeacherFilters({this.subject, this.gender, this.delivery, this.priceMin, this.priceMax, this.minRating, this.available = false, this.q = ''});

  static const TeacherFilters none = TeacherFilters();

  final String? subject, gender, delivery;
  final double? priceMin, priceMax, minRating;
  final bool available;
  final String q;

  /// How many filters are set (the search text is not a filter).
  int get count => [subject, gender, delivery, priceMin, priceMax, minRating].where((e) => e != null).length + (available ? 1 : 0);

  TeacherFilters copyWith({
    Object? subject = _keep,
    Object? gender = _keep,
    Object? delivery = _keep,
    Object? priceMin = _keep,
    Object? priceMax = _keep,
    Object? minRating = _keep,
    bool? available,
    String? q,
  }) =>
      TeacherFilters(
        subject: subject == _keep ? this.subject : subject as String?,
        gender: gender == _keep ? this.gender : gender as String?,
        delivery: delivery == _keep ? this.delivery : delivery as String?,
        priceMin: priceMin == _keep ? this.priceMin : priceMin as double?,
        priceMax: priceMax == _keep ? this.priceMax : priceMax as double?,
        minRating: minRating == _keep ? this.minRating : minRating as double?,
        available: available ?? this.available,
        q: q ?? this.q,
      );

  Map<String, dynamic> toQuery({required int page, int size = 20}) => {
        if (subject != null) 'subject': subject,
        if (gender != null) 'gender': gender,
        if (delivery != null) 'delivery': delivery,
        if (priceMin != null) 'price_min': _num(priceMin!),
        if (priceMax != null) 'price_max': _num(priceMax!),
        if (minRating != null) 'min_rating': _num(minRating!),
        if (available) 'available': 'true',
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'size': size.clamp(1, 50),
      };

  static String _num(double v) => v == v.truncateToDouble() ? '${v.toInt()}' : '$v';
}

const Object _keep = Object();

class TeacherListPage {
  const TeacherListPage({required this.items, required this.total, required this.page});

  factory TeacherListPage.fromJson(Object? raw) {
    final j = _map(raw);
    final items = [for (final m in _maps(j['items'])) TeacherProfile.fromJson(m)];
    return TeacherListPage(items: items, total: _int(j['total'], items.length), page: _int(j['page'], 1));
  }

  final List<TeacherProfile> items;
  final int total, page;
}

/// GET /me/teachers: a teacher of mine with the packages I am in and the next session.
class MyTeacher {
  const MyTeacher({required this.teacher, this.activePackages = const [], this.nextSession});

  factory MyTeacher.fromJson(Map<String, dynamic> j) {
    final next = j['next_session'];
    return MyTeacher(
      teacher: TeacherProfile.fromJson(j['teacher'] is Map ? j['teacher'] : j),
      activePackages: [for (final p in _maps(j['active_packages'])) TeacherPackage.fromJson(p)],
      nextSession: next is Map ? teachersParseUtc(next['starts_at']) : teachersParseUtc(next),
    );
  }

  final TeacherProfile teacher;
  final List<TeacherPackage> activePackages;
  final DateTime? nextSession;
}

List<MyTeacher> myTeachersFromJson(Object? raw) {
  final items = raw is Map ? raw['items'] : raw;
  return [for (final m in _maps(items)) MyTeacher.fromJson(m)];
}
