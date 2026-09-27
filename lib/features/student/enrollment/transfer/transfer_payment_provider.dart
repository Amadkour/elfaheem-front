/// transfer_payment_provider.dart — bank-transfer / InstaPay submission flow.
///
/// Student picks bank_transfer or instapay in EnrollmentProvider, which
/// pushes TransferPaymentScreen; this provider drives that screen:
///   GET  /api/v1/payments/transfer-methods?course_id=  -> receiving details
///   POST /api/v1/payments/transfer                      -> submit proof (multipart)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart';

import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../enrollment_models.dart';

enum TransferSubmitStep { form, submitting, submitted, failed }

class TransferPaymentProvider extends BaseProvider {
  TransferPaymentProvider({
    required this.courseId,
    required this.method,
    ApiClient? api,
  }) : api = api ?? ApiClient();

  final int courseId;
  final String method; // "bank_transfer" | "instapay"
  final ApiClient api;

  TransferMethodDetails? _details;
  TransferSubmitStep _step = TransferSubmitStep.form;
  String? _failureReason;
  XFile? _proofImage;

  TransferMethodDetails? get details => _details;

  TransferSubmitStep get step => _step;

  String? get failureReason => _failureReason;

  XFile? get proofImage => _proofImage;
  Uint8List? proofImageBytes;

  bool get isBankTransfer => method == 'bank_transfer';

  Future<void> setProofImage(XFile file) async {
    _proofImage = file;
    proofImageBytes = await file.readAsBytes();
    notifyListeners();
  }

  Future<void> loadDetails() async {
    final json = asJsonMap(
      await run(
        () async =>
            api.get('/api/v1/payments/transfer-methods?course_id=$courseId'),
      ),
    );
    if (json != null) _details = TransferMethodDetails.fromJson(json);
    notifyListeners();
  }

  Future<void> cancelAndRetryManualTransfer() async {
    final r = await run(
      () => api.post(
        '/api/v1/payments/transfers/cancel-mine',
        queryParams: {'course_id': courseId},
      ),
    );
  }

  Future<bool> submit({
    required String senderName,
    String? senderPhone,
    String? transferReference,
  }) async {
    if (_proofImage == null) {
      _failureReason = 'الرجاء إرفاق صورة إيصال التحويل';
      notifyListeners();
      return false;
    }
    _step = TransferSubmitStep.submitting;
    notifyListeners();

    try {
      await cancelAndRetryManualTransfer();

      await api.postMultipart(
        '/api/v1/payments/transfer',
        fields: {
          'course_id': courseId.toString(),
          'method': method,
          'sender_name': senderName,
          if (senderPhone != null && senderPhone.isNotEmpty)
            'sender_phone': senderPhone,
          if (transferReference != null && transferReference.isNotEmpty)
            'transfer_reference': transferReference,
        },
        filePath: _proofImage!.path,
        fileBytes: proofImageBytes,
        fileName: _proofImage!.name,
        fileField: 'proof_image',
      );
      _step = TransferSubmitStep.submitted;
      notifyListeners();
      return true;
    } catch (e) {
      _step = TransferSubmitStep.failed;
      _failureReason = 'تعذّر إرسال طلب التحويل: $e';
      notifyListeners();
      return false;
    }
  }
}
