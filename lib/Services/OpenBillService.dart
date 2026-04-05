import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Models/OpenBill.dart';

/// OpenBillService — now reads/writes entirely from the root Status collection.
///
/// Open bills are Status docs where:
///   - transactionMethod == 'Open Bill'
///   - isClosed == false
///
/// Settled (former open) bills are Status docs where:
///   - isClosed == true
class OpenBillService {
  OpenBillService._privateConstructor();
  static final OpenBillService instance = OpenBillService._privateConstructor();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _statusRef => _firestore.collection(Col.name('Status'));

  // ──────────────────────────────────────────────────────────────
  // Streams
  // ──────────────────────────────────────────────────────────────

  /// Listen to all currently-open bills (objects).
  Stream<List<OpenBill>> getOpenBillsStream() {
    return _statusRef
        .where('isClosed', isEqualTo: false)
        .orderBy('waktuPesan', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => OpenBill.fromStatusDoc(doc))
            .toList());
  }

  /// Raw QuerySnapshot stream of all active orders (for Printer Dialog).
  Stream<QuerySnapshot> getRawActiveOrdersStream() {
    return _statusRef
        .where('isClosed', isEqualTo: false)
        .orderBy('waktuPesan', descending: true)
        .snapshots();
  }

  /// Stream of all settled bills (closed Status documents)
  Stream<QuerySnapshot> getSettledBillsStream() {
    return _statusRef
        .where('isClosed', isEqualTo: true)
        .orderBy('settledAt', descending: true)
        .limit(30)
        .snapshots();
  }

  /// Stream from Root RecentlyServed collection (Legacy/Backup source).
  Stream<QuerySnapshot> getRootRecentlyServedStream() {
    return _firestore.collection(Col.name('RecentlyServed'))
        .orderBy('waktuPesan', descending: true)
        .limit(20)
        .snapshots();
  }

  // ──────────────────────────────────────────────────────────────
  // Settlement
  // ──────────────────────────────────────────────────────────────

  /// Marks the open bill Status doc as settled.
  Future<void> settleBill({
    required String statusDocId,
    required String paymentMethod,
    required int finalTotal,
    int discountAmount = 0,
    String? voucherCode,
    WriteBatch? existingBatch,
    int? subTotal,
    int? takeAwayFee,
  }) async {
    final batch = existingBatch ?? _firestore.batch();
    final statusRef = _statusRef.doc(statusDocId);

    batch.update(statusRef, {
      'isClosed': true,
      'settledAt': FieldValue.serverTimestamp(),
      'wasOpenBill': true,
      'finalTotal': finalTotal,
      'discountAmount': discountAmount,
      if (voucherCode != null) 'voucherCode': voucherCode,
      if (subTotal != null) 'subTotal': subTotal,
      if (takeAwayFee != null) 'takeAwayFee': takeAwayFee,
      'paymentMethod': paymentMethod,
      'total': finalTotal,
    });

    if (existingBatch == null) {
      await batch.commit();
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────

  /// Fetch active open bill for a member.
  Future<DocumentSnapshot?> getExistingOpenBill(String memberId) async {
    final query = await _statusRef
        .where('memberId', isEqualTo: memberId)
        .where('transactionMethod', isEqualTo: 'Open Bill')
        .where('isClosed', isEqualTo: false)
        .limit(1)
        .get();

    return query.docs.isNotEmpty ? query.docs.first : null;
  }

  /// Fetch credit limit.
  Future<int> getCreditLimit() async {
    final settingsDoc = await _firestore
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('Metadata')
        .doc('Settings')
        .get();

    if (settingsDoc.exists && settingsDoc.data() != null) {
      final data = settingsDoc.data()!;
      if (data.containsKey('openBillCreditLimit')) {
        return (data['openBillCreditLimit'] as num).toInt();
      }
    }
    return 300000; // Default
  }
}
