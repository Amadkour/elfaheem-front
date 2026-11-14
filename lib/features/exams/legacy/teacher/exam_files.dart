// features/exams/legacy/teacher/exam_files.dart
//
// Small helpers for the new exam features:
//   • ExamRules        attempts + per-student random paper rules
//   • ExamFile         a file received from the server (name + bytes)
//   • ImportResult     result of importing questions from Excel / CSV
//   • pickQuestionsFile / saveExamFile   pick an upload / save a download
//
// pubspec.yaml needs:
//   file_picker: ^13.1.0   (pickFile() / readAsBytes(); no withData flag)
//   file_saver:  ^0.7.0    (uses `fileExtension`; 0.2.x used `ext`)

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';

/// Attempts + random-paper rules of an exam.
class ExamRules {
  /// 0 = unlimited attempts, N > 0 = at most N attempts per student.
  final int maxSubmissions;

  /// null = every student gets every question, N = N random questions each.
  final int? questionsPerStudent;

  /// Random question order per student.
  final bool shuffleQuestions;

  /// Random option order per student.
  final bool shuffleOptions;

  const ExamRules({
    this.maxSubmissions = 0,
    this.questionsPerStudent,
    this.shuffleQuestions = false,
    this.shuffleOptions = false,
  });

  bool get unlimitedAttempts => maxSubmissions <= 0;
}

/// A file returned by the server (base64 on the wire).
class ExamFile {
  final String filename;
  final Uint8List bytes;
  const ExamFile(this.filename, this.bytes);
}

class ImportRowError {
  final int row;
  final String message;
  const ImportRowError(this.row, this.message);
}

class ImportResult {
  final int created;
  final int skipped;
  final int questionsCount;
  final List<ImportRowError> errors;

  const ImportResult({
    required this.created,
    required this.skipped,
    required this.questionsCount,
    required this.errors,
  });

  factory ImportResult.fromJson(Map<String, dynamic> j) => ImportResult(
    created: (j['created'] as num?)?.toInt() ?? 0,
    skipped: (j['skipped'] as num?)?.toInt() ?? 0,
    questionsCount: (j['questions_count'] as num?)?.toInt() ?? 0,
    errors: (j['errors'] as List? ?? [])
        .whereType<Map>()
        .map((e) => ImportRowError(
      (e['row'] as num?)?.toInt() ?? 0,
      e['message']?.toString() ?? '',
    ))
        .toList(),
  );
}

/// Lets the teacher pick an .xlsx / .csv file. Returns null if cancelled.
Future<ExamFile?> pickQuestionsFile() async {
  final f = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'csv'],
  );
  if (f == null) return null;
  // We upload the bytes, so read them from the picked file (v12+ API).
  final bytes = await f.readAsBytes();
  return ExamFile(f.name, bytes);
}

/// Saves a downloaded file (Downloads / share sheet / browser download).
Future<void> saveExamFile(ExamFile file) async {
  final dot = file.filename.lastIndexOf('.');
  final name = dot > 0 ? file.filename.substring(0, dot) : file.filename;
  final ext = dot > 0 ? file.filename.substring(dot + 1) : 'xlsx';
  await FileSaver.instance.saveFile(
    name: name,
    bytes: file.bytes,
    fileExtension: ext,
    mimeType: MimeType.microsoftExcel,
  );
}