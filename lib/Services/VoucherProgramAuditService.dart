import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Services/VoucherProgramService.dart';

/// Read-only B2B reconciliation.  It intentionally never calls update,
/// delete, or repair: historical findings must be reviewed before any
/// correction is made.
class VoucherProgramAuditService {
  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static int _amount(dynamic value) {
    if (value is num) return value.toInt();
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return 0;
    final direct = int.tryParse(raw);
    if (direct != null) return direct;
    return int.tryParse(raw.replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  }

  static String? _dateKey(dynamic value) {
    DateTime? date;
    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is String) {
      date = DateTime.tryParse(value);
    }
    if (date == null) return null;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String? _monthKey(String? dateKey) =>
      dateKey == null || dateKey.length < 7 ? null : dateKey.substring(0, 7);

  static String? _yearKey(String? dateKey) =>
      dateKey == null || dateKey.length < 4 ? null : dateKey.substring(0, 4);

  static Future<List<VoucherProgramAuditFinding>> run() async {
    final findings = <VoucherProgramAuditFinding>[];
    final programSnap = await _fs.collection(Col.name('voucherPrograms')).get();
    final programs = <String, VoucherProgram>{};
    final expectedDailyRedemptions = <String, int>{};
    final expectedMonthlyRedemptions = <String, int>{};
    final expectedYearlyRedemptions = <String, int>{};
    final expectedDailySettlements = <String, int>{};
    final expectedMonthlySettlements = <String, int>{};
    final expectedYearlySettlements = <String, int>{};

    for (final doc in programSnap.docs) {
      final program = VoucherProgram.fromSnapshot(doc);
      programs[doc.id] = program;
      if (!{'active', 'paid', 'closed'}.contains(program.status)) {
        findings.add(VoucherProgramAuditFinding(
          code: 'program_status_invalid',
          severity: 'error',
          message: 'Status program voucher tidak valid: ${program.status}.',
          documentId: doc.id,
        ));
      }
      if (program.totalRedeemed < 0 || program.totalSettled < 0) {
        findings.add(VoucherProgramAuditFinding(
          code: 'program_counter_invalid',
          severity: 'error',
          message: 'Counter program voucher bernilai negatif.',
          documentId: doc.id,
        ));
      }
      if (program.totalSettled > program.totalRedeemed) {
        findings.add(VoucherProgramAuditFinding(
          code: 'program_counter_mismatch',
          severity: 'error',
          message: 'Total pembayaran melebihi total voucher yang ditebus.',
          documentId: doc.id,
          details: {
            'totalRedeemed': program.totalRedeemed,
            'totalSettled': program.totalSettled,
          },
        ));
      }

      final redemptionSnap =
          await doc.reference.collection('redemptions').get();
      var ledgerRedeemed = 0;
      final operationIds = <String>{};
      for (final ledger in redemptionSnap.docs) {
        final data = ledger.data();
        final rawOperationId = data['operationId']?.toString().trim();
        final operationId = rawOperationId == null || rawOperationId.isEmpty
            ? ledger.id
            : rawOperationId;
        if (rawOperationId == null || rawOperationId.isEmpty) {
          findings.add(VoucherProgramAuditFinding(
            code: 'redemption_operation_marker_missing',
            severity: 'warning',
            message: 'Ledger redemption tidak memiliki operation marker.',
            documentId: '${doc.id}/${ledger.id}',
          ));
        }
        if (!operationIds.add(operationId)) {
          findings.add(VoucherProgramAuditFinding(
            code: 'duplicate_redemption_record',
            severity: 'error',
            message: 'Ditemukan operation ID redemption duplikat.',
            documentId: '${doc.id}/${ledger.id}',
            details: {'operationId': operationId},
          ));
        }
        final eventType = data['eventType']?.toString() ?? 'redemption';
        final amount = _amount(data['amountDelta'] ?? data['amount']);
        final validAmount = eventType == 'edit' ? amount != 0 : amount > 0;
        if (!validAmount) {
          findings.add(VoucherProgramAuditFinding(
            code: 'redemption_amount_invalid',
            severity: 'error',
            message: 'Nominal redemption kosong atau tidak valid.',
            documentId: '${doc.id}/${ledger.id}',
          ));
        }
        if (data['status']?.toString() != 'completed') {
          findings.add(VoucherProgramAuditFinding(
            code: 'redemption_record_invalid',
            severity: 'error',
            message: 'Ledger redemption belum berstatus completed.',
            documentId: '${doc.id}/${ledger.id}',
          ));
        }
        ledgerRedeemed += amount;
      }
      if (program.totalRedeemed != 0 && redemptionSnap.docs.isEmpty) {
        findings.add(VoucherProgramAuditFinding(
          code: 'legacy_redemption_marker_missing',
          severity: 'warning',
          message:
              'Program memiliki total redemption tetapi tidak memiliki ledger operation marker.',
          documentId: doc.id,
        ));
      } else if (redemptionSnap.docs.isNotEmpty &&
          ledgerRedeemed != program.totalRedeemed) {
        findings.add(VoucherProgramAuditFinding(
          code: 'redemption_ledger_mismatch',
          severity: 'error',
          message: 'Total redemption berbeda dari jumlah ledger.',
          documentId: doc.id,
          details: {
            'counter': program.totalRedeemed,
            'ledger': ledgerRedeemed,
          },
        ));
      }

      final settlementSnap =
          await doc.reference.collection('settlements').get();
      var ledgerSettled = 0;
      final settlementOperationIds = <String>{};
      for (final ledger in settlementSnap.docs) {
        final data = ledger.data();
        final rawOperationId = data['operationId']?.toString().trim();
        if (rawOperationId == null || rawOperationId.isEmpty) {
          findings.add(VoucherProgramAuditFinding(
            code: 'settlement_operation_marker_missing',
            severity: 'warning',
            message: 'Ledger settlement tidak memiliki operation marker.',
            documentId: '${doc.id}/${ledger.id}',
          ));
        } else if (!settlementOperationIds.add(rawOperationId)) {
          findings.add(VoucherProgramAuditFinding(
            code: 'duplicate_settlement_record',
            severity: 'error',
            message: 'Ditemukan operation ID settlement duplikat.',
            documentId: '${doc.id}/${ledger.id}',
            details: {'operationId': rawOperationId},
          ));
        }
        final amount = _amount(data['amount']);
        final method = data['paymentMethod']?.toString();
        if (amount <= 0 || !{'Cash', 'QRIS', 'Online'}.contains(method)) {
          findings.add(VoucherProgramAuditFinding(
            code: 'settlement_record_invalid',
            severity: 'error',
            message:
                'Ledger pembayaran program memiliki nominal atau metode tidak valid.',
            documentId: '${doc.id}/${ledger.id}',
          ));
        }
        if (data['status']?.toString() != 'completed') {
          findings.add(VoucherProgramAuditFinding(
            code: 'settlement_record_invalid',
            severity: 'error',
            message: 'Ledger settlement belum berstatus completed.',
            documentId: '${doc.id}/${ledger.id}',
          ));
        }
        final settlementDate = _dateKey(data['settlementDate']);
        if (settlementDate == null) {
          findings.add(VoucherProgramAuditFinding(
            code: 'settlement_date_missing',
            severity: 'warning',
            message: 'Ledger settlement tidak memiliki tanggal pembayaran.',
            documentId: '${doc.id}/${ledger.id}',
          ));
        } else if (amount > 0 && data['status']?.toString() == 'completed') {
          expectedDailySettlements[settlementDate] =
              (expectedDailySettlements[settlementDate] ?? 0) + amount;
          final month = _monthKey(settlementDate);
          final year = _yearKey(settlementDate);
          if (month != null) {
            expectedMonthlySettlements[month] =
                (expectedMonthlySettlements[month] ?? 0) + amount;
          }
          if (year != null) {
            expectedYearlySettlements[year] =
                (expectedYearlySettlements[year] ?? 0) + amount;
          }
        }
        ledgerSettled += amount;
      }
      if (program.totalSettled != 0 && settlementSnap.docs.isEmpty) {
        findings.add(VoucherProgramAuditFinding(
          code: 'legacy_settlement_marker_missing',
          severity: 'warning',
          message:
              'Program memiliki total pembayaran tetapi tidak memiliki ledger settlement.',
          documentId: doc.id,
        ));
      } else if (settlementSnap.docs.isNotEmpty &&
          ledgerSettled != program.totalSettled) {
        findings.add(VoucherProgramAuditFinding(
          code: 'settlement_ledger_mismatch',
          severity: 'error',
          message: 'Total pembayaran berbeda dari jumlah ledger settlement.',
          documentId: doc.id,
          details: {
            'counter': program.totalSettled,
            'ledger': ledgerSettled,
          },
        ));
      }
    }

    final statusSnap = await _fs.collection(Col.name('Status')).get();
    for (final statusDoc in statusSnap.docs) {
      final data = statusDoc.data();
      final isProgramPayment = data['paymentMethod']?.toString() == 'Program' ||
          data['voucherProgramId'] != null ||
          data['voucherProgram'] is Map ||
          data['b2bPayment'] is Map;
      if (!isProgramPayment) continue;
      final payment = B2BPaymentBreakdown.fromStatus(
        data,
        total: _amount(data['total']),
      );
      final programId =
          payment.programId ?? data['voucherProgramId']?.toString().trim();
      if (programId == null || programId.isEmpty) {
        findings.add(VoucherProgramAuditFinding(
          code: 'order_program_missing',
          severity: 'error',
          message: 'Pesanan B2B tidak memiliki referensi program voucher.',
          documentId: statusDoc.id,
        ));
      }
      final program = programId == null ? null : programs[programId];
      if (program == null && programId != null) {
        findings.add(VoucherProgramAuditFinding(
          code: 'order_program_missing',
          severity: 'error',
          message: 'Pesanan merujuk program voucher yang tidak ditemukan.',
          documentId: statusDoc.id,
          details: {'programId': programId},
        ));
      } else if (program != null && program.status == 'closed') {
        findings.add(VoucherProgramAuditFinding(
          code: 'order_program_closed',
          severity: 'warning',
          message: 'Pesanan merujuk program voucher yang sudah ditutup.',
          documentId: statusDoc.id,
          details: {'programId': programId},
        ));
      }
      if (payment.nominal <= 0) {
        findings.add(VoucherProgramAuditFinding(
          code: 'order_b2b_nominal_invalid',
          severity: 'error',
          message: 'Pesanan B2B memiliki nominal voucher yang tidak valid.',
          documentId: statusDoc.id,
        ));
      }
      if (payment.isAmbiguousLegacy) {
        findings.add(VoucherProgramAuditFinding(
          code: 'order_b2b_details_ambiguous',
          severity: 'warning',
          message:
              'Rincian pembayaran B2B lama tidak lengkap; jangan menebak saat edit.',
          documentId: statusDoc.id,
        ));
      }
      if (data['voucherProgramOperationId']?.toString().trim().isEmpty ??
          true) {
        findings.add(VoucherProgramAuditFinding(
          code: 'order_operation_marker_missing',
          severity: 'warning',
          message: 'Pesanan B2B lama tidak memiliki operation marker.',
          documentId: statusDoc.id,
        ));
      }
      final rawDate = data['wasOpenBill'] == true
          ? (data['settledAt'] ?? data['waktuPesan'])
          : data['waktuPesan'];
      final dateKey = _dateKey(rawDate);
      if (dateKey != null) {
        expectedDailyRedemptions[dateKey] =
            (expectedDailyRedemptions[dateKey] ?? 0) + payment.nominal;
        final month = _monthKey(dateKey);
        final year = _yearKey(dateKey);
        if (month != null) {
          expectedMonthlyRedemptions[month] =
              (expectedMonthlyRedemptions[month] ?? 0) + payment.nominal;
        }
        if (year != null) {
          expectedYearlyRedemptions[year] =
              (expectedYearlyRedemptions[year] ?? 0) + payment.nominal;
        }
      }
    }

    final dailySnap = await _fs.collection(Col.name('DailyTransaction')).get();
    final monthlySnap =
        await _fs.collection(Col.name('MonthlyTransaction')).get();
    final yearlySnap =
        await _fs.collection(Col.name('YearlyTransaction')).get();
    final dailyById = {for (final doc in dailySnap.docs) doc.id: doc};
    final monthlyById = {for (final doc in monthlySnap.docs) doc.id: doc};
    final yearlyById = {for (final doc in yearlySnap.docs) doc.id: doc};

    void checkFinancialTotals(
      Map<String, int> expected,
      Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> storedDocs,
      String period,
      String field,
      String code,
      String message,
    ) {
      for (final entry in expected.entries) {
        final doc = storedDocs[entry.key];
        final stored = doc == null ? 0 : _amount(doc.data()[field]);
        if (doc == null || stored < entry.value) {
          findings.add(VoucherProgramAuditFinding(
            code: code,
            severity: 'error',
            message: message,
            documentId: entry.key,
            details: {
              'period': period,
              'expectedMinimum': entry.value,
              'stored': stored,
            },
          ));
        }
      }
    }

    checkFinancialTotals(
      expectedDailyRedemptions,
      dailyById,
      'daily',
      'totalVoucher',
      'financial_b2b_total_missing',
      'Total redemption B2B di transaksi harian kurang dari data pesanan.',
    );
    checkFinancialTotals(
      expectedMonthlyRedemptions,
      monthlyById,
      'monthly',
      'totalVoucher',
      'financial_b2b_total_missing',
      'Total redemption B2B di transaksi bulanan kurang dari data pesanan.',
    );
    checkFinancialTotals(
      expectedYearlyRedemptions,
      yearlyById,
      'yearly',
      'totalVoucher',
      'financial_b2b_total_missing',
      'Total redemption B2B di transaksi tahunan kurang dari data pesanan.',
    );

    void checkSettlementTotals(
      Map<String, int> expected,
      Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> storedDocs,
      String period,
    ) {
      for (final entry in expected.entries) {
        final doc = storedDocs[entry.key];
        final storedVoucher =
            doc == null ? 0 : _amount(doc.data()['totalVoucherSettled']);
        final storedB2b =
            doc == null ? 0 : _amount(doc.data()['totalB2BSettled']);
        final stored = storedVoucher > storedB2b ? storedVoucher : storedB2b;
        if (doc == null || stored < entry.value) {
          findings.add(VoucherProgramAuditFinding(
            code: 'financial_b2b_settlement_total_missing',
            severity: 'error',
            message: 'Total pembayaran B2B di laporan $period belum lengkap.',
            documentId: entry.key,
            details: {
              'period': period,
              'expectedMinimum': entry.value,
              'stored': stored,
            },
          ));
        }
      }
    }

    checkSettlementTotals(expectedDailySettlements, dailyById, 'harian');
    checkSettlementTotals(expectedMonthlySettlements, monthlyById, 'bulanan');
    checkSettlementTotals(expectedYearlySettlements, yearlyById, 'tahunan');
    return findings;
  }
}
