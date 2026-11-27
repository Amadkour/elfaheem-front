// Owner decisions 2026-11-27 (rd/ow-book): the bank-transfer proof sheet (every field required by the admin, and
// none) and the study profile's interests chips, at 320x640 and 1400x900, Arabic + English, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/booking/booking_mine_card.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart';
import 'package:flutter_education_app/features/booking/booking_transfer_sheet.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_form.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي Office of Student Affairs and Research';

void main() {
  final name = TextEditingController(), phone = TextEditingController(), ref = TextEditingController();

  Widget form(BkTransferInfo info, {String? photo, String? error}) => SingleChildScrollView(
        child: BkTransferForm(
          info: info,
          amount: '199 ر.س',
          name: name,
          phone: phone,
          reference: ref,
          photoName: photo,
          error: error,
          onPick: () {},
          onSend: () {},
        ),
      );

  testWidgets('bank transfer sheet: full details, every field, an error', (t) async {
    await expectNoLayoutErrors(
      t,
      () => form(
        const BkTransferInfo(
          bankName: _long,
          accountName: _long,
          iban: 'SA0380000000608010167519',
          swift: 'RJHISARI',
          instructions: _long,
          needPhone: true,
          needReference: true,
        ),
        photo: 'IMG_20261127_120000_receipt_of_the_transfer.png',
        error: _long,
      ),
    );
  });

  testWidgets('bank transfer sheet: no details yet', (t) async {
    await expectNoLayoutErrors(t, () => form(const BkTransferInfo()));
  });

  testWidgets('interests chips', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: StudyInterestsPicker(
          choices: [for (var i = 1; i <= 14; i++) (i, i.isEven ? _long : 'البرمجة')],
          picked: const [2, 3],
          onChanged: (_) {},
        ),
      ),
    );
  });

  testWidgets('booking card: a rejected transfer, one under review', (t) async {
    const rejected = BkBooking(
      id: 1,
      status: 'pending_payment',
      price: 199,
      currency: 'SAR',
      transfer: BkTransferState(paymentId: 9, status: 'rejected', reason: _long),
    );
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: BkMineCard(booking: rejected, onPay: () {}, onSendProof: () {})));
    const pending = BkBooking(id: 2, status: 'pending_payment', transfer: BkTransferState(paymentId: 10, status: 'pending'));
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: BkMineCard(booking: pending, onPay: () {}, onSendProof: () {})));
  });
}
