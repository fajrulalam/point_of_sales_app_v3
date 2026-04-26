import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Models/SelfOrder.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';

class SelfOrderService {
  static final SelfOrderService _instance = SelfOrderService._internal();
  factory SelfOrderService() => _instance;
  SelfOrderService._internal();

  static SelfOrderService get instance => _instance;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String canteenId = 'canteen375';

  /// Get the collection reference for self-orders
  static CollectionReference<Map<String, dynamic>> get _selfOrdersCollection =>
      _firestore
          .collection(Col.name('Canteens'))
          .doc(canteenId)
          .collection('SelfOrders');

  /// Get a real-time stream of self-orders
  /// Optionally filter by status (e.g., 'Unpaid', 'Paid', 'Declined')
  Stream<List<SelfOrder>> getSelfOrdersStream({String? statusFilter}) {
    Query<Map<String, dynamic>> query = _selfOrdersCollection;

    if (statusFilter != null && statusFilter.isNotEmpty) {
      query = query.where('status', isEqualTo: statusFilter);
    }

    return query.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => SelfOrder.fromFirestore(doc))
          .toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    });
  }

  /// Get a stream of only unpaid self-orders (for main view)
  Stream<List<SelfOrder>> getUnpaidOrdersStream() {
    return getSelfOrdersStream(statusFilter: SelfOrderStatus.unpaid);
  }

  /// Get a stream of the count of unpaid orders (for badge notification)
  Stream<int> getUnpaidOrderCountStream() {
    return _selfOrdersCollection
        .where('status', isEqualTo: SelfOrderStatus.unpaid)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Get a single self-order by ID
  Future<SelfOrder?> getSelfOrderById(String orderId) async {
    try {
      final doc = await _selfOrdersCollection.doc(orderId).get();
      if (doc.exists) {
        return SelfOrder.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error fetching self-order: $e');
      return null;
    }
  }

  /// Update the status of a self-order
  Future<void> updateStatus(String orderId, String newStatus,
      {String? declineReason}) async {
    final Map<String, dynamic> updateData = {
      'status': newStatus,
    };

    if (declineReason != null) {
      updateData['declineReason'] = declineReason;
    }

    if (newStatus == SelfOrderStatus.paid ||
        newStatus == SelfOrderStatus.declined) {
      updateData['processedAt'] = FieldValue.serverTimestamp();
    }

    await _selfOrdersCollection.doc(orderId).update(updateData);
  }

  /// Mark an order as processing (intermediate state before payment)
  Future<void> markAsProcessing(String orderId) async {
    await updateStatus(orderId, SelfOrderStatus.processing);
  }

  /// Mark an order as paid
  Future<void> markAsPaid(String orderId) async {
    await updateStatus(orderId, SelfOrderStatus.paid);
  }

  /// Decline an order with a reason
  Future<void> declineOrder(String orderId, String reason) async {
    await updateStatus(orderId, SelfOrderStatus.declined, declineReason: reason);
  }

  /// Convert a SelfOrder to a list of PesananObject for order processing
  /// This allows reusing the existing order confirmation flow
  List<PesananObject> convertToPesananList(SelfOrder selfOrder) {
    return selfOrder.orderItems.map((item) {
      return PesananObject(
        namaPesanan: item.namaPesanan,
        harga: item.harga,
        dineInQuantity: item.dineInQuantity,
        takeAwayQuantity: item.takeAwayQuantity,
        selectedOptions: item.selectedOptions,
      );
    }).toList();
  }

  /// Check if there are any items with dine-in quantities
  bool hasDineInItems(SelfOrder selfOrder) {
    return selfOrder.orderItems.any((item) => item.dineInQuantity > 0);
  }

  /// Check if there are any items with take-away quantities
  bool hasTakeAwayItems(SelfOrder selfOrder) {
    return selfOrder.orderItems.any((item) => item.takeAwayQuantity > 0);
  }

  /// Calculate if the order has take-away items (for biaya bungkus)
  bool isTakeAwayOrder(SelfOrder selfOrder) {
    return selfOrder.takeAwayFee > 0 || hasTakeAwayItems(selfOrder);
  }

  /// Get orders for today (useful for history view)
  Stream<List<SelfOrder>> getTodayOrdersStream() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return _selfOrdersCollection
        .where('waktuPesan',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
        .where('waktuPesan', isLessThanOrEqualTo: Timestamp.fromDate(endOfToday))
        .orderBy('waktuPesan', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => SelfOrder.fromFirestore(doc)).toList());
  }

  /// Delete a self-order (use with caution - typically only for testing)
  Future<void> deleteSelfOrder(String orderId) async {
    await _selfOrdersCollection.doc(orderId).delete();
  }
}

/// Common decline reasons for self-orders
class DeclineReasons {
  static const String outOfStock = 'Item tidak tersedia';
  static const String canteenClosed = 'Kantin tutup';
  static const String memberIssue = 'Masalah akun member';
  static const String other = 'Lainnya';

  static List<String> get defaultReasons => [
        outOfStock,
        canteenClosed,
        memberIssue,
        other,
      ];
}
