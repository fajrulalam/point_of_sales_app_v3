import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

/// A domain error that is safe to show to a cashier after it has been mapped
/// by UserMessageService (the message itself is already Indonesian).
class VoucherProgramException implements Exception {
  final String message;

  const VoucherProgramException(this.message);

  @override
  String toString() => message;
}

/// B2B amounts are stored as integer rupiah, but a few legacy documents used
/// formatted strings such as `"40.000"`.  Do not use the generic inventory
/// parser here: this helper deliberately understands Indonesian currency
/// formatting while still accepting the numeric Firebase types.
int _parseB2BAmount(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return fallback;
  final direct = int.tryParse(raw);
  if (direct != null) return direct;
  final digits = raw.replaceAll(RegExp(r'[^0-9-]'), '');
  return int.tryParse(digits) ?? fallback;
}

/// A normalized B2B payment breakdown.  The voucher nominal is not a cash
/// payment; only [cashAmount], [qrisAmount], and [onlineAmount] enter the
/// corresponding cash/payment totals.
class B2BPaymentBreakdown {
  final String? programId;
  final int nominal;
  final int remaining;
  final String? extraPaymentMethod;
  final int cashAmount;
  final int qrisAmount;
  final int onlineAmount;
  final bool isAmbiguousLegacy;

  const B2BPaymentBreakdown._({
    required this.programId,
    required this.nominal,
    required this.remaining,
    required this.extraPaymentMethod,
    required this.cashAmount,
    required this.qrisAmount,
    required this.onlineAmount,
    this.isAmbiguousLegacy = false,
  });

  bool get isProgram => programId != null && programId!.trim().isNotEmpty;

  /// Ordinary vouchers are applied before this calculation.  A cashier can
  /// enter a nominal larger than the remaining bill; the authoritative result
  /// is capped instead of creating a phantom credit.
  static B2BPaymentBreakdown calculate({
    required int billTotal,
    required int requestedNominal,
    String? programId,
    String? extraPaymentMethod,
    int qrisAmount = 0,
  }) {
    if (programId == null || programId.trim().isEmpty) {
      return const B2BPaymentBreakdown._(
        programId: null,
        nominal: 0,
        remaining: 0,
        extraPaymentMethod: null,
        cashAmount: 0,
        qrisAmount: 0,
        onlineAmount: 0,
      );
    }
    if (billTotal <= 0) {
      throw const VoucherProgramException(
          'Program voucher tidak dapat digunakan pada tagihan nol.');
    }
    if (requestedNominal <= 0) {
      throw const VoucherProgramException(
          'Nominal voucher harus lebih dari 0.');
    }

    final nominal = min(requestedNominal, billTotal);
    final remaining = billTotal - nominal;
    final method = extraPaymentMethod?.trim();
    if (remaining == 0) {
      return B2BPaymentBreakdown._(
        programId: programId.trim(),
        nominal: nominal,
        remaining: 0,
        extraPaymentMethod: null,
        cashAmount: 0,
        qrisAmount: 0,
        onlineAmount: 0,
      );
    }
    if (method == null || method.isEmpty) {
      throw const VoucherProgramException(
          'Pilih metode pembayaran untuk sisa tagihan.');
    }

    switch (method) {
      case 'Cash':
        return B2BPaymentBreakdown._(
          programId: programId.trim(),
          nominal: nominal,
          remaining: remaining,
          extraPaymentMethod: method,
          cashAmount: remaining,
          qrisAmount: 0,
          onlineAmount: 0,
        );
      case 'QRIS':
        return B2BPaymentBreakdown._(
          programId: programId.trim(),
          nominal: nominal,
          remaining: remaining,
          extraPaymentMethod: method,
          cashAmount: 0,
          qrisAmount: remaining,
          onlineAmount: 0,
        );
      case 'Online':
        return B2BPaymentBreakdown._(
          programId: programId.trim(),
          nominal: nominal,
          remaining: remaining,
          extraPaymentMethod: method,
          cashAmount: 0,
          qrisAmount: 0,
          onlineAmount: remaining,
        );
      case 'Cash + QRIS':
        if (qrisAmount < 0 || qrisAmount > remaining) {
          throw const VoucherProgramException(
              'Jumlah QRIS tidak boleh melebihi sisa tagihan.');
        }
        return B2BPaymentBreakdown._(
          programId: programId.trim(),
          nominal: nominal,
          remaining: remaining,
          extraPaymentMethod: method,
          cashAmount: remaining - qrisAmount,
          qrisAmount: qrisAmount,
          onlineAmount: 0,
        );
      default:
        throw const VoucherProgramException('Metode pembayaran tidak valid.');
    }
  }

  /// Reads the normalized fields first and falls back to the legacy top-level
  /// fields.  [total] is the bill total stored on the order/status document.
  /// Legacy records without enough split detail are deliberately marked
  /// ambiguous so an edit can reject them safely rather than guessing.
  static B2BPaymentBreakdown fromStatus(
    Map<String, dynamic> data, {
    required int total,
  }) {
    final nested = data['voucherProgram'] is Map
        ? Map<String, dynamic>.from(data['voucherProgram'] as Map)
        : data['b2bPayment'] is Map
            ? Map<String, dynamic>.from(data['b2bPayment'] as Map)
            : <String, dynamic>{};
    final rawId = nested['id'] ?? data['voucherProgramId'];
    final id = rawId?.toString().trim();
    final isProgram = data['paymentMethod']?.toString() == 'Program' ||
        (id != null && id.isNotEmpty);
    if (!isProgram) return B2BPaymentBreakdown.none;

    final rawNominal = nested['nominal'] ?? data['programNominal'];
    final requestedNominal = _parseB2BAmount(rawNominal);
    final safeTotal = max(0, total);
    final nominal = min(max(requestedNominal, 0), safeTotal);
    final remaining = safeTotal - nominal;
    final rawMethod =
        nested['extraPaymentMethod'] ?? data['programExtraPaymentMethod'];
    final method = rawMethod?.toString();
    final topSplit = data['programExtraSplitDetails'] is Map
        ? Map<String, dynamic>.from(data['programExtraSplitDetails'] as Map)
        : <String, dynamic>{};
    final nestedSplit = nested['extraSplitDetails'] is Map
        ? Map<String, dynamic>.from(nested['extraSplitDetails'] as Map)
        : <String, dynamic>{};
    final split = <String, dynamic>{...topSplit, ...nestedSplit};
    final nestedCash = nested['extraCashAmount'] ?? split['cashAmount'];
    final nestedQris = nested['extraQrisAmount'] ?? split['qrisAmount'];
    final nestedOnline = nested['extraOnlineAmount'] ?? split['onlineAmount'];

    var cash = 0;
    var qris = 0;
    var online = 0;
    // A legacy record is not automatically unsafe: plain Cash/QRIS/Online
    // totals are reconstructible from the bill.  Only missing/contradictory
    // split details are ambiguous and must be rejected by edit logic.
    var ambiguous = false;
    if (remaining > 0) {
      switch (method) {
        case 'Cash':
          cash = remaining;
          break;
        case 'QRIS':
          qris = remaining;
          break;
        case 'Online':
          online = remaining;
          break;
        case 'Cash + QRIS':
          if (split.isEmpty && nestedCash == null && nestedQris == null) {
            ambiguous = true;
          } else {
            qris = _parseB2BAmount(nestedQris);
            cash = _parseB2BAmount(nestedCash);
            if (cash + qris != remaining) ambiguous = true;
          }
          break;
        default:
          ambiguous = true;
      }
    }
    if (nestedOnline != null) online = _parseB2BAmount(nestedOnline);
    if (requestedNominal > safeTotal) ambiguous = true;

    return B2BPaymentBreakdown._(
      programId: id == null || id.isEmpty ? null : id,
      nominal: nominal,
      remaining: remaining,
      extraPaymentMethod: remaining == 0 ? null : method,
      cashAmount: cash,
      qrisAmount: qris,
      onlineAmount: online,
      isAmbiguousLegacy: ambiguous,
    );
  }

  static const none = B2BPaymentBreakdown._(
    programId: null,
    nominal: 0,
    remaining: 0,
    extraPaymentMethod: null,
    cashAmount: 0,
    qrisAmount: 0,
    onlineAmount: 0,
  );

  Map<String, dynamic> toMap() => {
        if (programId != null) 'id': programId,
        'nominal': nominal,
        'remaining': remaining,
        'extraPaymentMethod': extraPaymentMethod,
        'extraCashAmount': cashAmount,
        'extraQrisAmount': qrisAmount,
        'extraOnlineAmount': onlineAmount,
        'extraSplitDetails': {
          'cashAmount': cashAmount,
          'qrisAmount': qrisAmount,
          'onlineAmount': onlineAmount,
        },
      };

  Map<String, dynamic> toStatusFields({required String operationId}) {
    return {
      'paymentMethod': 'Program',
      'voucherProgramId': programId,
      'programNominal': nominal,
      'programExtraPaymentMethod': extraPaymentMethod,
      'programExtraSplitDetails': {
        'cashAmount': cashAmount,
        'qrisAmount': qrisAmount,
        'onlineAmount': onlineAmount,
      },
      'voucherProgramOperationId': operationId,
      'voucherProgram': toMap(),
      'b2bPayment': toMap(),
    };
  }

  Map<String, dynamic> toFinancialFields() => {
        'totalVoucher': FieldValue.increment(nominal),
        'totalB2BRedeemed': FieldValue.increment(nominal),
      };
}

class VoucherProgram {
  final String id;
  final String programName;
  final String institutionName;
  final String status;
  final int totalRedeemed;
  final int totalSettled;
  final int defaultNominal;
  final int revision;
  final Map<String, dynamic> raw;

  const VoucherProgram({
    required this.id,
    required this.programName,
    required this.institutionName,
    required this.status,
    required this.totalRedeemed,
    required this.totalSettled,
    required this.defaultNominal,
    required this.revision,
    this.raw = const {},
  });

  factory VoucherProgram.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return VoucherProgram(
      id: snapshot.id,
      programName: data['programName']?.toString() ?? '',
      institutionName: data['institutionName']?.toString() ?? '',
      status: data['status']?.toString().toLowerCase() ?? '',
      totalRedeemed: _parseB2BAmount(data['totalRedeemed']),
      totalSettled: _parseB2BAmount(data['totalSettled']),
      defaultNominal: _parseB2BAmount(data['defaultNominal']),
      revision: _parseB2BAmount(data['revision']),
      raw: data,
    );
  }

  int get outstanding => totalRedeemed - totalSettled;
}

class VoucherProgramOperationResult {
  final bool wasAlreadyApplied;
  final String? operationId;
  final int? amount;

  const VoucherProgramOperationResult({
    this.wasAlreadyApplied = false,
    this.operationId,
    this.amount,
  });

  const VoucherProgramOperationResult.alreadyApplied()
      : wasAlreadyApplied = true,
        operationId = null,
        amount = null;
}

class VoucherSettlementCalculation {
  final int newTotalSettled;
  final String resultingStatus;

  const VoucherSettlementCalculation({
    required this.newTotalSettled,
    required this.resultingStatus,
  });
}

class VoucherProgramEditDelta {
  final int delta;
  final int resultingRedeemed;
  final String resultingStatus;

  const VoucherProgramEditDelta({
    required this.delta,
    required this.resultingRedeemed,
    required this.resultingStatus,
  });
}

class VoucherProgramRedemptionPreparation {
  final bool wasAlreadyApplied;
  final String operationId;
  final String programId;
  final int amount;
  final DocumentReference<Map<String, dynamic>> programRef;
  final DocumentReference<Map<String, dynamic>> ledgerRef;

  const VoucherProgramRedemptionPreparation({
    required this.wasAlreadyApplied,
    required this.operationId,
    required this.programId,
    required this.amount,
    required this.programRef,
    required this.ledgerRef,
  });
}

class VoucherProgramEditAdjustment {
  final String programId;
  final int delta;
  final String resultingStatus;
  final DocumentReference<Map<String, dynamic>> programRef;
  final DocumentReference<Map<String, dynamic>> ledgerRef;
  final int oldNominal;
  final int newNominal;

  const VoucherProgramEditAdjustment({
    required this.programId,
    required this.delta,
    required this.resultingStatus,
    required this.programRef,
    required this.ledgerRef,
    required this.oldNominal,
    required this.newNominal,
  });
}

class VoucherProgramEditPreparation {
  final bool wasAlreadyApplied;
  final String operationId;
  final List<VoucherProgramEditAdjustment> adjustments;

  const VoucherProgramEditPreparation({
    required this.wasAlreadyApplied,
    required this.operationId,
    required this.adjustments,
  });
}

class VoucherProgramAuditFinding {
  final String code;
  final String severity;
  final String message;
  final String? documentId;
  final Map<String, dynamic> details;

  const VoucherProgramAuditFinding({
    required this.code,
    required this.severity,
    required this.message,
    this.documentId,
    this.details = const {},
  });

  Map<String, dynamic> toMap() => {
        'code': code,
        'severity': severity,
        'message': message,
        if (documentId != null) 'documentId': documentId,
        if (details.isNotEmpty) 'details': details,
      };
}

class VoucherProgramService {
  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  /// Parses both native numeric Firebase values and formatted legacy rupiah
  /// strings such as `40.000`.
  static int parseAmount(dynamic value, [int fallback = 0]) =>
      _parseB2BAmount(value, fallback);

  static CollectionReference<Map<String, dynamic>> get _programs =>
      _fs.collection(Col.name('voucherPrograms'));

  static DocumentReference<Map<String, dynamic>> _programRef(String id) =>
      _programs.doc(id);

  static String _operationDocId(String id) =>
      id.replaceAll('/', '_').replaceAll(' ', '_');

  static VoucherSettlementCalculation calculateSettlement({
    required int totalRedeemed,
    required int totalSettled,
    required int amount,
    required String currentStatus,
  }) {
    if (amount <= 0) {
      throw const VoucherProgramException(
          'Jumlah pembayaran harus lebih dari 0.');
    }
    if (totalRedeemed < 0 || totalSettled < 0 || totalSettled > totalRedeemed) {
      throw const VoucherProgramException(
          'Saldo program tidak konsisten. Periksa audit B2B terlebih dahulu.');
    }
    if (currentStatus == 'closed') {
      throw const VoucherProgramException(
          'Program yang sudah ditutup tidak dapat menerima pembayaran.');
    }
    final outstanding = totalRedeemed - totalSettled;
    if (amount > outstanding) {
      throw const VoucherProgramException(
          'Pembayaran melebihi sisa piutang program.');
    }
    final newSettled = totalSettled + amount;
    return VoucherSettlementCalculation(
      newTotalSettled: newSettled,
      resultingStatus: newSettled == totalRedeemed ? 'paid' : 'active',
    );
  }

  static VoucherProgramEditDelta calculateEditDelta({
    required int currentRedeemed,
    required int currentSettled,
    required int oldNominal,
    required int newNominal,
  }) {
    if (currentRedeemed < 0 ||
        currentSettled < 0 ||
        oldNominal < 0 ||
        newNominal < 0) {
      throw const VoucherProgramException('Nominal voucher tidak valid.');
    }
    final delta = newNominal - oldNominal;
    final resultingRedeemed = currentRedeemed + delta;
    if (resultingRedeemed < currentSettled) {
      throw const VoucherProgramException(
          'Perubahan pesanan membuat pembayaran melebihi total voucher.');
    }
    return VoucherProgramEditDelta(
      delta: delta,
      resultingRedeemed: resultingRedeemed,
      resultingStatus: resultingRedeemed == currentSettled ? 'paid' : 'active',
    );
  }

  static List<Map<String, dynamic>> _mapsFromQuery(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final result = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    result.sort((a, b) {
      final aTime = a['createdAt'] is Timestamp
          ? (a['createdAt'] as Timestamp).millisecondsSinceEpoch
          : 0;
      final bTime = b['createdAt'] is Timestamp
          ? (b['createdAt'] as Timestamp).millisecondsSinceEpoch
          : 0;
      return bTime.compareTo(aTime);
    });
    return result;
  }

  static Stream<List<Map<String, dynamic>>> getActiveProgramsStream() {
    return _programs
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snap) => _mapsFromQuery(snap));
  }

  static Future<List<Map<String, dynamic>>> getActivePrograms() async {
    final snap = await _programs.where('status', isEqualTo: 'active').get();
    return _mapsFromQuery(snap);
  }

  static Future<List<Map<String, dynamic>>> getAllPrograms() async {
    final snap = await _programs.get();
    return _mapsFromQuery(snap);
  }

  static Future<Map<String, dynamic>?> getProgram(String id) async {
    final snap = await _programRef(id).get();
    if (!snap.exists) return null;
    return {'id': snap.id, ...?snap.data()};
  }

  static Future<String> createProgram({
    required String programName,
    required String institutionName,
    int defaultNominal = 0,
    String notes = '',
  }) async {
    final name = programName.trim();
    final institution = institutionName.trim();
    if (name.isEmpty) {
      throw const VoucherProgramException('Nama program wajib diisi.');
    }
    if (institution.isEmpty) {
      throw const VoucherProgramException('Nama institusi wajib diisi.');
    }
    if (defaultNominal < 0) {
      throw const VoucherProgramException(
          'Nominal default tidak boleh negatif.');
    }
    final ref = _programs.doc();
    await ref.set({
      'programName': name,
      'institutionName': institution,
      'status': 'active',
      'totalRedeemed': 0,
      'totalSettled': 0,
      'defaultNominal': defaultNominal,
      'revision': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'canteenId': 'canteen375_plazaUnipdu',
      'notes': notes.trim(),
    });
    return ref.id;
  }

  static Future<void> updateProgram(
    String id,
    Map<String, dynamic> updates, {
    int? expectedRevision,
  }) async {
    if (id.trim().isEmpty) {
      throw const VoucherProgramException('Program voucher tidak ditemukan.');
    }
    const allowed = {
      'programName',
      'institutionName',
      'defaultNominal',
      'notes',
    };
    if (updates.keys.any((key) => !allowed.contains(key))) {
      throw const VoucherProgramException('Data program tidak valid.');
    }
    final sanitized = <String, dynamic>{};
    if (updates.containsKey('programName')) {
      final value = updates['programName']?.toString().trim() ?? '';
      if (value.isEmpty) {
        throw const VoucherProgramException('Nama program wajib diisi.');
      }
      sanitized['programName'] = value;
    }
    if (updates.containsKey('institutionName')) {
      final value = updates['institutionName']?.toString().trim() ?? '';
      if (value.isEmpty) {
        throw const VoucherProgramException('Nama institusi wajib diisi.');
      }
      sanitized['institutionName'] = value;
    }
    if (updates.containsKey('defaultNominal')) {
      final value = parseAmount(updates['defaultNominal']);
      if (value < 0) {
        throw const VoucherProgramException(
            'Nominal default tidak boleh negatif.');
      }
      sanitized['defaultNominal'] = value;
    }
    if (updates.containsKey('notes')) {
      sanitized['notes'] = updates['notes']?.toString().trim() ?? '';
    }
    if (sanitized.isEmpty) return;

    await _fs.runTransaction((transaction) async {
      final ref = _programRef(id);
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw const VoucherProgramException('Program voucher tidak ditemukan.');
      }
      final program = VoucherProgram.fromSnapshot(snapshot);
      if (program.status == 'closed') {
        throw const VoucherProgramException(
            'Program yang sudah ditutup tidak dapat diedit.');
      }
      if (expectedRevision != null && program.revision != expectedRevision) {
        throw const VoucherProgramException(
            'Program sudah diubah oleh perangkat lain. Muat ulang terlebih dahulu.');
      }
      transaction.update(ref, {
        ...sanitized,
        'revision': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> closeProgram(
    String id, {
    String? operationId,
    String? lastPromptedDate,
  }) async {
    final closeId = _operationDocId(
        operationId ?? 'close_${id}_${DateTime.now().microsecondsSinceEpoch}');
    await _fs.runTransaction((transaction) async {
      final programRef = _programRef(id);
      final markerRef = programRef.collection('closures').doc(closeId);
      final programSnapshot = await transaction.get(programRef);
      final markerSnapshot = await transaction.get(markerRef);
      if (markerSnapshot.exists &&
          markerSnapshot.data()?['status']?.toString() == 'completed') {
        return;
      }
      if (!programSnapshot.exists) {
        throw const VoucherProgramException('Program voucher tidak ditemukan.');
      }
      final program = VoucherProgram.fromSnapshot(programSnapshot);
      if (program.status == 'closed') {
        transaction.set(
            markerRef,
            {
              'operationId': closeId,
              'status': 'completed',
              'eventType': 'close',
              'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        return;
      }
      if (program.outstanding != 0) {
        throw const VoucherProgramException(
            'Program hanya dapat ditutup setelah seluruh piutang lunas.');
      }
      transaction.update(programRef, {
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'revision': FieldValue.increment(1),
        if (lastPromptedDate != null) 'lastPromptedDate': lastPromptedDate,
      });
      transaction.set(
          markerRef,
          {
            'operationId': closeId,
            'status': 'completed',
            'eventType': 'close',
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }

  /// Records an actual institution payment.  The program counter, ledger
  /// marker, and financial totals all commit together, so retries cannot count
  /// the same payment twice.
  static Future<VoucherProgramOperationResult> settleProgram({
    required String programId,
    required int settledAmount,
    required String paymentMethod,
    DateTime? settlementDate,
    String? operationId,
  }) async {
    final method = paymentMethod.trim();
    if (!{'Cash', 'QRIS', 'Online'}.contains(method)) {
      throw const VoucherProgramException('Metode pembayaran tidak valid.');
    }
    if (settledAmount <= 0) {
      throw const VoucherProgramException(
          'Jumlah pembayaran harus lebih dari 0.');
    }
    final date = settlementDate ?? DateTime.now();
    final opId = _operationDocId(operationId ??
        'settlement_${programId}_${DateTime.now().microsecondsSinceEpoch}');

    return _fs
        .runTransaction<VoucherProgramOperationResult>((transaction) async {
      final programRef = _programRef(programId);
      final ledgerRef = programRef.collection('settlements').doc(opId);
      final dailyRef = _fs
          .collection(Col.name('DailyTransaction'))
          .doc(DateFormat('yyyy-MM-dd').format(date));
      final monthlyRef = _fs
          .collection(Col.name('MonthlyTransaction'))
          .doc(DateFormat('yyyy-MM').format(date));
      final yearlyRef = _fs
          .collection(Col.name('YearlyTransaction'))
          .doc(DateFormat('yyyy').format(date));

      final programSnapshot = await transaction.get(programRef);
      final ledgerSnapshot = await transaction.get(ledgerRef);
      final dailySnapshot = await transaction.get(dailyRef);
      final monthlySnapshot = await transaction.get(monthlyRef);
      final yearlySnapshot = await transaction.get(yearlyRef);
      if (ledgerSnapshot.exists &&
          ledgerSnapshot.data()?['status']?.toString() == 'completed') {
        final existing = ledgerSnapshot.data() ?? <String, dynamic>{};
        final existingAmount = _parseB2BAmount(existing['amount']);
        final existingMethod = existing['paymentMethod']?.toString();
        if (existingAmount != settledAmount || existingMethod != method) {
          throw const VoucherProgramException(
              'Operation pembayaran sudah digunakan dengan data berbeda.');
        }
        return VoucherProgramOperationResult(
          wasAlreadyApplied: true,
          operationId: opId,
          amount: settledAmount,
        );
      }
      if (!programSnapshot.exists) {
        throw const VoucherProgramException('Program voucher tidak ditemukan.');
      }
      final program = VoucherProgram.fromSnapshot(programSnapshot);
      if (program.status == 'closed') {
        throw const VoucherProgramException(
            'Program yang sudah ditutup tidak dapat menerima pembayaran.');
      }
      final settlement = calculateSettlement(
        totalRedeemed: program.totalRedeemed,
        totalSettled: program.totalSettled,
        amount: settledAmount,
        currentStatus: program.status,
      );
      final accumulator = <String, dynamic>{
        method == 'Cash'
            ? 'totalCash'
            : method == 'QRIS'
                ? 'totalQris'
                : 'totalOnline': FieldValue.increment(settledAmount),
        'totalVoucherSettled': FieldValue.increment(settledAmount),
        'totalB2BSettled': FieldValue.increment(settledAmount),
        'lastB2BSettlementAt': FieldValue.serverTimestamp(),
      };
      transaction.set(dailyRef, accumulator, SetOptions(merge: true));
      transaction.set(monthlyRef, accumulator, SetOptions(merge: true));
      transaction.set(yearlyRef, accumulator, SetOptions(merge: true));
      transaction.update(programRef, {
        'totalSettled': FieldValue.increment(settledAmount),
        'status': settlement.resultingStatus,
        'lastSettledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'revision': FieldValue.increment(1),
      });
      transaction.set(
          ledgerRef,
          {
            'operationId': opId,
            'eventType': 'settlement',
            'amount': settledAmount,
            'paymentMethod': method,
            'settlementDate': DateFormat('yyyy-MM-dd').format(date),
            'status': 'completed',
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      // Keep these reads in the transaction.  They make concurrent financial
      // updates retry against the latest documents instead of silently
      // overwriting an absolute value.
      if (dailySnapshot.exists ||
          monthlySnapshot.exists ||
          yearlySnapshot.exists) {
        // The snapshots are intentionally consumed by the transaction read set.
      }
      return VoucherProgramOperationResult(
        operationId: opId,
        amount: settledAmount,
      );
    });
  }

  /// Called before any order write is queued.  Firestore requires all reads
  /// before writes in a transaction; callers therefore prepare first and then
  /// call [commitRedemptionInTransaction].
  static Future<VoucherProgramRedemptionPreparation>
      prepareRedemptionInTransaction({
    required Transaction transaction,
    required String programId,
    required int requestedNominal,
    required int billTotal,
    required String operationId,
    required String sourceType,
    required String sourceId,
  }) async {
    if (programId.trim().isEmpty) {
      throw const VoucherProgramException('Program voucher tidak ditemukan.');
    }
    if (billTotal <= 0 || requestedNominal <= 0) {
      throw const VoucherProgramException('Nominal voucher tidak valid.');
    }
    final safeOperationId = _operationDocId(operationId);
    final programRef = _programRef(programId.trim());
    final ledgerRef = programRef.collection('redemptions').doc(safeOperationId);
    final programSnapshot = await transaction.get(programRef);
    final ledgerSnapshot = await transaction.get(ledgerRef);
    if (ledgerSnapshot.exists &&
        ledgerSnapshot.data()?['status']?.toString() == 'completed') {
      return VoucherProgramRedemptionPreparation(
        wasAlreadyApplied: true,
        operationId: safeOperationId,
        programId: programId.trim(),
        amount: InventoryService.toInt(ledgerSnapshot.data()?['amount']),
        programRef: programRef,
        ledgerRef: ledgerRef,
      );
    }
    if (!programSnapshot.exists) {
      throw const VoucherProgramException('Program voucher tidak ditemukan.');
    }
    final program = VoucherProgram.fromSnapshot(programSnapshot);
    if (program.status != 'active') {
      throw const VoucherProgramException(
          'Program voucher tidak aktif dan tidak dapat digunakan.');
    }
    final amount = min(requestedNominal, billTotal);
    return VoucherProgramRedemptionPreparation(
      wasAlreadyApplied: false,
      operationId: safeOperationId,
      programId: programId.trim(),
      amount: amount,
      programRef: programRef,
      ledgerRef: ledgerRef,
    );
  }

  static void commitRedemptionInTransaction({
    required Transaction transaction,
    required VoucherProgramRedemptionPreparation preparation,
    required String sourceType,
    required String sourceId,
  }) {
    if (preparation.wasAlreadyApplied) return;
    transaction.update(preparation.programRef, {
      'totalRedeemed': FieldValue.increment(preparation.amount),
      'status': 'active',
      'lastRedeemedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'revision': FieldValue.increment(1),
    });
    transaction.set(
        preparation.ledgerRef,
        {
          'operationId': preparation.operationId,
          'eventType': 'redemption',
          'sourceType': sourceType,
          'sourceId': sourceId,
          'amount': preparation.amount,
          'amountDelta': preparation.amount,
          'status': 'completed',
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
  }

  /// Prepares the B2B counter delta for a safe order edit.  The old and new
  /// program documents and operation markers are read before any edit writes.
  static Future<VoucherProgramEditPreparation> prepareEditInTransaction({
    required Transaction transaction,
    required String operationId,
    String? oldProgramId,
    required int oldNominal,
    String? newProgramId,
    required int newNominal,
  }) async {
    final oldId = oldProgramId?.trim();
    final newId = newProgramId?.trim();
    if (oldNominal < 0 || newNominal < 0) {
      throw const VoucherProgramException('Nominal voucher tidak valid.');
    }
    if ((oldId == null || oldId.isEmpty) && (newId == null || newId.isEmpty)) {
      return VoucherProgramEditPreparation(
        wasAlreadyApplied: false,
        operationId: operationId,
        adjustments: const [],
      );
    }
    if (newId != null && newId.isNotEmpty && newNominal <= 0) {
      throw const VoucherProgramException(
          'Nominal voucher harus lebih dari 0.');
    }

    final ids = <String>{
      if (oldId != null && oldId.isNotEmpty) oldId,
      if (newId != null && newId.isNotEmpty) newId,
    };
    final programSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    final markers = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final id in ids) {
      final ref = _programRef(id);
      programSnapshots[id] = await transaction.get(ref);
      final markerRef =
          ref.collection('redemptions').doc(_operationDocId(operationId));
      markers[id] = await transaction.get(markerRef);
    }
    if (markers.values.any((snapshot) =>
        snapshot.exists &&
        snapshot.data()?['status']?.toString() == 'completed')) {
      return VoucherProgramEditPreparation(
        wasAlreadyApplied: true,
        operationId: operationId,
        adjustments: const [],
      );
    }

    final adjustments = <VoucherProgramEditAdjustment>[];
    for (final id in ids) {
      final snapshot = programSnapshots[id]!;
      if (!snapshot.exists) {
        throw VoucherProgramException('Program voucher "$id" tidak ditemukan.');
      }
      final program = VoucherProgram.fromSnapshot(snapshot);
      if (program.status == 'closed') {
        throw const VoucherProgramException(
            'Pesanan yang terhubung ke program tertutup tidak dapat diedit.');
      }
      if (program.status != 'active' && program.status != 'paid') {
        throw const VoucherProgramException(
            'Status program voucher tidak valid.');
      }
      final oldForProgram = id == oldId ? oldNominal : 0;
      final newForProgram = id == newId ? newNominal : 0;
      final deltaCalculation = calculateEditDelta(
        currentRedeemed: program.totalRedeemed,
        currentSettled: program.totalSettled,
        oldNominal: oldForProgram,
        newNominal: newForProgram,
      );
      final delta = deltaCalculation.delta;
      if (delta == 0) continue;
      final markerRef = _programRef(id)
          .collection('redemptions')
          .doc(_operationDocId(operationId));
      adjustments.add(VoucherProgramEditAdjustment(
        programId: id,
        delta: delta,
        resultingStatus: deltaCalculation.resultingStatus,
        programRef: _programRef(id),
        ledgerRef: markerRef,
        oldNominal: oldForProgram,
        newNominal: newForProgram,
      ));
    }
    return VoucherProgramEditPreparation(
      wasAlreadyApplied: false,
      operationId: operationId,
      adjustments: adjustments,
    );
  }

  static void commitEditInTransaction({
    required Transaction transaction,
    required VoucherProgramEditPreparation preparation,
    required String sourceId,
  }) {
    if (preparation.wasAlreadyApplied) return;
    for (final adjustment in preparation.adjustments) {
      transaction.update(adjustment.programRef, {
        'totalRedeemed': FieldValue.increment(adjustment.delta),
        'status': adjustment.resultingStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastEditedAt': FieldValue.serverTimestamp(),
        'revision': FieldValue.increment(1),
      });
      transaction.set(
          adjustment.ledgerRef,
          {
            'operationId': _operationDocId(preparation.operationId),
            'eventType': 'edit',
            'sourceType': 'edit',
            'sourceId': sourceId,
            'amountDelta': adjustment.delta,
            'oldNominal': adjustment.oldNominal,
            'newNominal': adjustment.newNominal,
            'status': 'completed',
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }
  }

  /// Compatibility helpers are retained for old, unreachable legacy code.
  /// Active checkout paths must use prepare/commit above because a raw
  /// increment cannot be made duplicate-safe by itself.
  @Deprecated(
      'Use prepareRedemptionInTransaction and commitRedemptionInTransaction')
  static void addRedemptionToBatch({
    required WriteBatch batch,
    required String programId,
    required int amount,
  }) {
    if (amount <= 0) return;
    batch.update(_programRef(programId), {
      'totalRedeemed': FieldValue.increment(amount),
    });
  }

  @Deprecated(
      'Use prepareRedemptionInTransaction and commitRedemptionInTransaction')
  static void addRedemptionToTransaction({
    required Transaction transaction,
    required String programId,
    required int amount,
  }) {
    if (amount <= 0) return;
    transaction.update(_programRef(programId), {
      'totalRedeemed': FieldValue.increment(amount),
    });
  }

  /// Checks older active programs and offers a cashier a settlement flow.  The
  /// prompt itself is not financial state; settlement and closing are guarded
  /// by the transactional methods above.
  static Future<void> checkAndPromptPendingVouchers(
      BuildContext context) async {
    try {
      final activePrograms = await getActivePrograms();
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      final yesterday = now.subtract(const Duration(days: 1));
      for (final program in activePrograms) {
        final redeemed = parseAmount(program['totalRedeemed']);
        final settled = parseAmount(program['totalSettled']);
        final outstanding = redeemed - settled;
        if (outstanding <= 0 || program['lastPromptedDate'] == today) continue;
        final createdAt = program['createdAt'];
        if (createdAt is Timestamp &&
            DateFormat('yyyy-MM-dd').format(createdAt.toDate()) == today) {
          continue;
        }
        if (!context.mounted) return;
        await _showSettlementPrompt(
            context, program, outstanding, today, yesterday);
      }
    } catch (_) {
      // A prompt is convenience UI.  It must never prevent the POS from
      // opening when the program collection is temporarily unavailable.
    }
  }

  static Future<void> _showSettlementPrompt(
    BuildContext context,
    Map<String, dynamic> program,
    int outstanding,
    String today,
    DateTime yesterday,
  ) async {
    final name = program['programName']?.toString() ?? 'Program Voucher';
    final formatter = NumberFormat.decimalPattern('id_ID');
    final bool? isSettled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Voucher Belum Lunas',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          'Program "$name" masih memiliki piutang sebesar Rp ${formatter.format(outstanding)} dari hari sebelumnya.\n\nApakah tagihan ini sudah dilunasi?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Belum', style: GoogleFonts.poppins(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sudah Lunas',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (isSettled != true || !context.mounted) return;
    var selectedMethod = 'Cash';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text('Metode Pembayaran',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Wrap(
            spacing: 8,
            children: ['Cash', 'QRIS', 'Online']
                .map((method) => ChoiceChip(
                      label: Text(method),
                      selected: selectedMethod == method,
                      onSelected: (_) =>
                          setStateDialog(() => selectedMethod = method),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final opId = 'prompt_${program['id']}_$today';
    await settleProgram(
      programId: program['id'].toString(),
      settledAmount: outstanding,
      paymentMethod: selectedMethod,
      settlementDate: yesterday,
      operationId: opId,
    );
    await closeProgram(
      program['id'].toString(),
      operationId: 'close_$opId',
      lastPromptedDate: today,
    );
  }
}
