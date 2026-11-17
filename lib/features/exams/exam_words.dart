// lib/features/exams/exam_words.dart
//
// Counts the exam screens say often, with Arabic's 1 / 2 / 3–10 / 11+ forms (D-1131: "3 سؤالاً" was everywhere).
library;

import 'package:flutter_education_app/core/plural.dart';

/// "5 questions" / "٥ أسئلة".
String questionsText(int n) =>
    countText(n, ar1: 'سؤال واحد', ar2: 'سؤالان', arFew: '{n} أسئلة', arMany: '{n} سؤالاً', en1: '1 question', en: '{n} questions');

/// "5 questions ready".
String questionsReadyText(int n) => countText(n,
    ar1: 'سؤال واحد جاهز', ar2: 'سؤالان جاهزان', arFew: '{n} أسئلة جاهزة', arMany: '{n} سؤالاً جاهزاً', en1: '1 question ready', en: '{n} questions ready');

/// "5 open answers".
String openAnswersText(int n) => countText(n,
    ar1: 'إجابة مفتوحة واحدة', ar2: 'إجابتان مفتوحتان', arFew: '{n} إجابات مفتوحة', arMany: '{n} إجابة مفتوحة', en1: '1 open answer', en: '{n} open answers');
