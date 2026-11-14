// features/certificates/student/my_certificates_provider.dart
//
// Loads every certificate of every course of the current student, requests /
// cancels requests, and saves a certificate image to the device.

import 'dart:developer';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_saver/file_saver.dart';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/features/certificates/student/my_certificate_model.dart';

class MyCertificatesProvider extends BaseProvider {
  final ApiClient _api;

  MyCertificatesProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<MyCertificate> items = [];
  bool loading = false;
  bool loadFailed = false;
  final Set<int> busyCertIds = {};      // request / cancel in flight
  final Set<int> downloadingIds = {};   // download in flight

  int get issuedCount => items.where((c) => c.isIssued).length;

  Future<void> load() async {
    loading = true;
    loadFailed = false;
    notifyListeners();
    final r = await run(() => _api.get('/api/v1/my-certificates'));
    if (r is List) {
      items = r.whereType<Map<String, dynamic>>().map(MyCertificate.fromJson).toList();
    } else {
      loadFailed = true;
    }
    loading = false;
    notifyListeners();
  }

  /// Returns 'issued' (course was finished → certificate issued right away),
  /// 'pending' (waiting for the teacher) or null on failure.
  Future<String?> requestCertificate(int certificateId, {String? note}) async {
    busyCertIds.add(certificateId);
    notifyListeners();
    final r = await run(() => _api.post(
          '/api/v1/certificates/$certificateId/request',
          body: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
        ));
    busyCertIds.remove(certificateId);
    String? status;
    if (r is Map<String, dynamic>) status = r['status'] as String?;
    await load(); // reflect the new state (and the new image if it was issued)
    return status;
  }

  Future<bool> cancelRequest(int certificateId) async {
    busyCertIds.add(certificateId);
    notifyListeners();
    bool ok = false;
    try {
      final res = await _api.dio.delete('/api/v1/certificates/$certificateId/request');
      ok = res.statusCode == 204 || res.statusCode == 200;
    } catch (e) {
      log('cancelRequest ❌ $e');
    }
    busyCertIds.remove(certificateId);
    await load();
    return ok;
  }

  /// Downloads the certificate PNG and saves it on the device
  /// (Downloads / Files app on mobile+desktop, browser download on web).
  Future<bool> download(MyCertificate cert, {required bool arabic}) async {
    final url = cert.urlFor(arabic);
    if (url == null) return false;
    downloadingIds.add(cert.certificateId);
    notifyListeners();
    try {
      final res = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(res.data ?? const []);
      if (bytes.isEmpty) return false;
      final safe = cert.title.replaceAll(RegExp(r'[^\w؀-ۿ]+'), '_');
      await FileSaver.instance.saveFile(
        name: 'certificate_${safe}_${cert.courseId}_${cert.langFor(arabic)}',
        bytes: bytes,
        fileExtension: 'png',
        mimeType: MimeType.png,
      );
      return true;
    } catch (e) {
      log('certificate download ❌ $e');
      return false;
    } finally {
      downloadingIds.remove(cert.certificateId);
      notifyListeners();
    }
  }
}
