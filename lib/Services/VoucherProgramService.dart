import 'package:cloud_firestore/cloud_firestore.dart';
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
        .map((snap) => snap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
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
    await _fs
        .collection(Col.name('voucherPrograms'))
        .doc(id)
        .update(updates);
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

    final dailyRef =
        _fs.collection(Col.name('DailyTransaction')).doc(dayKey);
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
    final currentRedeemed =
        (programSnap.data()?['totalRedeemed'] ?? 0) as int;
    final currentSettled =
        (programSnap.data()?['totalSettled'] ?? 0) as int;
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
}
