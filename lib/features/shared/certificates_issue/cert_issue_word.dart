// lib/features/shared/certificates_issue/cert_issue_word.dart
//
// "Word (.docx)" for an issued certificate (2.1.6): the batch's design (GET /certificate-designs/{id}) filled with the
// certificate's own data, one file per language the batch issued, written by lib/design/export/cert_docx.dart.
// Every logo / signature field keeps its own picture.
//
// The {placeholders} follow the server's CertificateIssueService._variables as far as the issued record carries
// them: date (issue day), certificate title (the default one localized), organization name, course name (course
// batches, from the course), the row's values, student name, serial, verify link.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../design/export/cert_docx.dart';
import '../../../design/export/docx_fonts.dart';
import '../../../design/export/export_fonts.dart';
import '../../../design/export_hub/export_designer.dart' show loadExportImage;
import '../../teacher/certificates/designer/certificate_design_models.dart' show CertDesign, CertLangView, hexToColor, CertFieldKind;
import 'cert_issue_logic.dart';

/// The placeholder values of [cert] in [lang] (see the file header). [orgName] / [courseName] by language.
Map<String, String> certIssuedVariables(IssuedCert cert, IssueBatch? batch, String lang,
    {Map<String, String> orgName = const {}, Map<String, String> courseName = const {}}) {
  final at = cert.createdAt == null ? DateTime.now() : AppTime.toZone(cert.createdAt!.toUtc());
  String other(Map<String, String> m) => m[lang]?.isNotEmpty == true ? m[lang]! : (m[lang == 'ar' ? 'en' : 'ar'] ?? '');
  return {
    'date': certDate(at, lang),
    'org_name': other(orgName),
    'teacher_name': '',
    'certificate_title': certTitle(batch?.title ?? '', lang),
    'attendance': '',
    'progress': '',
    if (other(courseName).isNotEmpty) 'course_name': other(courseName),
    for (final e in cert.values.entries)
      if (e.key != 'email') e.key: e.value,
    'student_name': cert.recipientName,
    'serial': cert.serial,
    'verify_url': cert.verifyUrl ?? '',
    'student_image_url': '',
  };
}

/// A QR code of [data] as PNG bytes: [ink] modules on a white square with a quiet zone (like the renderer's
/// `_draw_qr_field`), [side] pixels.
Future<Uint8List?> certQrPng(String data, Color ink, {double side = 600}) async {
  try {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: ink),
      dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: ink),
    );
    final quiet = side * .07;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, side, side), Paint()..color = Colors.white);
    canvas.translate(quiet, quiet);
    painter.paint(canvas, Size.square(side - 2 * quiet));
    final image = await rec.endRecording().toImage(side.round(), side.round());
    final b = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return b == null ? null : Uint8List.sublistView(b);
  } catch (_) {
    return null;
  }
}

/// The Word file of [cert] in [view]'s language: images, QR codes and fonts loaded, then written.
Future<Uint8List> buildIssuedCertificateDocx(CertLangView view, Map<String, String> variables, {String title = ''}) async {
  final images = <String, Uint8List>{};
  for (final url in certImageUrls(view, variables)) {
    final b = await loadExportImage(url);
    if (b != null) images[url] = b;
  }
  final qr = <String, Uint8List>{};
  for (final e in certQrData(view, variables).entries) {
    if (e.value.isEmpty) continue;
    final f = view.fields.firstWhere((x) => x.id == e.key);
    final png = await certQrPng(e.value, hexToColor(f.color));
    if (png != null) qr[e.key] = png;
  }
  final ids = {for (final f in view.fields) if (f.visible && (f.kind == CertFieldKind.text || f.kind == CertFieldKind.signature)) f.font};
  final fonts = DocxFonts.build(await loadDocxFontFiles(ids));
  final files = {for (final id in ids) id: await ExportFonts.bytes(ExportFonts.byId(id).regularAsset)};
  return certificateDocx(view, variables: variables, images: images, qr: qr, fonts: fonts, fontFiles: files, title: title);
}

/// Every language file of [cert] (the batch's languages): (file name, bytes).
Future<List<(String, Uint8List)>> issuedCertificateWordFiles(IssuedCert cert, IssueBatch batch, {ApiClient? api}) async {
  final client = api ?? ApiClient();
  final r = await client.get('/api/v1/certificate-designs/${batch.designId}');
  final design = CertDesign.fromJson(Map<String, dynamic>.from(r as Map));
  final orgName = <String, String>{};
  for (final e in AppModeController.instance.entries) {
    final o = e['organization'];
    if (o is Map && '${o['id']}' == '${batch.orgId}') {
      orgName['ar'] = '${o['name_ar'] ?? o['name'] ?? ''}';
      orgName['en'] = '${o['name_en'] ?? o['name'] ?? ''}';
    }
  }
  final courseName = <String, String>{};
  if (batch.courseId != null) {
    try {
      final c = await client.get('/api/v1/courses/${batch.courseId}');
      if (c is Map) {
        courseName['ar'] = '${c['name_ar'] ?? c['name'] ?? ''}';
        courseName['en'] = '${c['name_en'] ?? c['name'] ?? ''}';
      }
    } catch (_) {}
  }
  final langs = [for (final l in batch.langs.isEmpty ? design.langs : batch.langs) if (l == 'ar' || l == 'en') l];
  final out = <(String, Uint8List)>[];
  for (final lang in langs) {
    final vars = certIssuedVariables(cert, batch, lang, orgName: orgName, courseName: courseName);
    final bytes = await buildIssuedCertificateDocx(design.view(lang), vars, title: cert.serial);
    final safe = (cert.serial.isEmpty ? 'certificate' : cert.serial).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    out.add(('$safe${langs.length > 1 ? '_$lang' : ''}.docx', bytes));
  }
  return out;
}
