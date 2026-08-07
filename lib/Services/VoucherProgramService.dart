import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

class VoucherProgramService {
  static final _fs = FirebaseFirestore.instance;

  static Stream<List<Map<String, dynamic>>> getActiveProgramsStream() {
    return _fs
        .collection(Col.name('voucherPrograms'))
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
            (snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  static Future<List<Map<String, dynamic>>> getActivePrograms() async {
    final snap = await _fs
        .collection(Col.name('voucherPrograms'))
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<List<Map<String, dynamic>>> getAllPrograms() async {
    final snap = await _fs
        .collection(Col.name('voucherPrograms'))
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<void> createProgram({
    required String programName,
    required String institutionName,
    int defaultNominal = 0,
    String notes = '',
  }) async {
    final epochSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final encodedName = programName.replaceAll(' ', '_');
    final docId = '${epochSec}_$encodedName';

    await _fs.collection(Col.name('voucherPrograms')).doc(docId).set({
      'programName': programName,
      'institutionName': institutionName,
      'status': 'active',
      'totalRedeemed': 0,
      'totalSettled': 0,
      'defaultNominal': defaultNominal,
      'createdAt': FieldValue.serverTimestamp(),
      'canteenId': 'canteen375_plazaUnipdu',
      'notes': notes,
    });
  }

  static Future<void> updateProgram(
      String id, Map<String, dynamic> updates) async {
    await _fs.collection(Col.name('voucherPrograms')).doc(id).update(updates);
  }

  static Future<void> closeProgram(String id) async {
    await _fs
        .collection(Col.name('voucherPrograms'))
        .doc(id)
        .update({'status': 'closed'});
  }

  /// Records an institution payment, adding the settled amount to the correct
  /// payment accumulator in DailyTransaction, MonthlyTransaction, and
  /// YearlyTransaction for [settlementDate] (defaults to today).
  static Future<void> settleProgram({
    required String programId,
    required int settledAmount,
    required String paymentMethod,
    DateTime? settlementDate,
  }) async {
    final date = settlementDate ?? DateTime.now();
    final dayKey = DateFormat('yyyy-MM-dd').format(date);
    final monthKey = DateFormat('yyyy-MM').format(date);
    final yearKey = DateFormat('yyyy').format(date);

    final String field;
    if (paymentMethod == 'Cash') {
      field = 'totalCash';
    } else if (paymentMethod == 'QRIS') {
      field = 'totalQris';
    } else {
      field = 'totalOnline';
    }

    final batch = _fs.batch();

    final dailyRef = _fs.collection(Col.name('DailyTransaction')).doc(dayKey);
    batch.set(dailyRef, {field: FieldValue.increment(settledAmount)},
        SetOptions(merge: true));

    final monthlyRef =
        _fs.collection(Col.name('MonthlyTransaction')).doc(monthKey);
    batch.set(monthlyRef, {field: FieldValue.increment(settledAmount)},
        SetOptions(merge: true));

    final yearlyRef =
        _fs.collection(Col.name('YearlyTransaction')).doc(yearKey);
    batch.set(yearlyRef, {field: FieldValue.increment(settledAmount)},
        SetOptions(merge: true));

    final programRef =
        _fs.collection(Col.name('voucherPrograms')).doc(programId);

    final programSnap = await programRef.get();
    final currentRedeemed = (programSnap.data()?['totalRedeemed'] ?? 0) as int;
    final currentSettled = (programSnap.data()?['totalSettled'] ?? 0) as int;
    final newSettled = currentSettled + settledAmount;
    final newStatus = newSettled >= currentRedeemed ? 'paid' : 'active';

    batch.update(programRef, {
      'totalSettled': FieldValue.increment(settledAmount),
      'status': newStatus,
      'lastSettledAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Called inside the order WriteBatch to increment program totalRedeemed.
  static void addRedemptionToBatch({
    required WriteBatch batch,
    required String programId,
    required int amount,
  }) {
    final programRef =
        _fs.collection(Col.name('voucherPrograms')).doc(programId);
    batch.update(programRef, {
      'totalRedeemed': FieldValue.increment(amount),
    });
  }

  /// Transaction equivalent used by idempotent checkout commits.
  static void addRedemptionToTransaction({
    required Transaction transaction,
    required String programId,
    required int amount,
  }) {
    final programRef =
        _fs.collection(Col.name('voucherPrograms')).doc(programId);
    transaction.update(programRef, {
      'totalRedeemed': FieldValue.increment(amount),
    });
  }

  /// Checks for active voucher programs from previous days and prompts the user
  /// if they have been settled. If settled, records the payment to yesterday's account.
  static Future<void> checkAndPromptPendingVouchers(
      BuildContext context) async {
    final activePrograms = await getActivePrograms();
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final yesterday = now.subtract(const Duration(days: 1));

    for (var program in activePrograms) {
      final redeemed = (program['totalRedeemed'] ?? 0) as int;
      final settled = (program['totalSettled'] ?? 0) as int;
      final outstanding = redeemed - settled;

      if (outstanding <= 0) continue;

      final lastPrompted = program['lastPromptedDate'] as String?;
      if (lastPrompted == today) continue;

      final createdAt = program['createdAt'];
      DateTime? createdDate;
      if (createdAt is Timestamp) createdDate = createdAt.toDate();
      if (createdDate != null) {
        final createdDay = DateFormat('yyyy-MM-dd').format(createdDate);
        if (createdDay == today) continue;
      }

      if (!context.mounted) return;

      await _showSettlementPrompt(
          context, program, outstanding, today, yesterday);
    }
  }

  static Future<void> _showSettlementPrompt(
      BuildContext context,
      Map<String, dynamic> program,
      int outstanding,
      String today,
      DateTime yesterday) async {
    final name = program['programName'] ?? 'Program Voucher';
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
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sudah Lunas',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (isSettled == null) return;

    if (isSettled) {
      if (!context.mounted) return;
      String selectedMethod = 'Cash';
      final bool? methodConfirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: Text('Metode Pembayaran',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Pilih metode pembayaran untuk pelunasan Rp ${formatter.format(outstanding)}:',
                    style: GoogleFonts.poppins()),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: ['Cash', 'QRIS', 'Online'].map((m) {
                    return ChoiceChip(
                      label: Text(m),
                      selected: selectedMethod == m,
                      selectedColor: const Color(0xFFC8E6C9),
                      labelStyle: GoogleFonts.poppins(
                        fontWeight: selectedMethod == m
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selectedMethod == m
                            ? const Color(0xFF2E7D32)
                            : Colors.black87,
                      ),
                      onSelected: (_) =>
                          setStateDialog(() => selectedMethod = m),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Batal', style: GoogleFonts.poppins()),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF069494),
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Simpan',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );

      if (methodConfirmed == true) {
        await settleProgram(
          programId: program['id'],
          settledAmount: outstanding,
          paymentMethod: selectedMethod,
          settlementDate: yesterday,
        );
        await closeProgram(program['id']);
      } else {
        return; // Cancelled payment method, ask again next time
      }
    }

    await _fs
        .collection(Col.name('voucherPrograms'))
        .doc(program['id'])
        .update({
      'lastPromptedDate': today,
    });
  }
}
