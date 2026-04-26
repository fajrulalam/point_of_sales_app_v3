import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Models/SelfOrder.dart';

class OpenBillOrder {
  final DateTime timestamp;
  final List<SelfOrderItem> items;
  final int orderTotal;
  final int orderTakeAwayFee;

  OpenBillOrder({
    required this.timestamp,
    required this.items,
    required this.orderTotal,
    required this.orderTakeAwayFee,
  });

  factory OpenBillOrder.fromMap(Map<String, dynamic> map) {
    DateTime parsedTimestamp = map['timestamp'] != null 
        ? (map['timestamp'] as Timestamp).toDate() 
        : DateTime.now();

    List<SelfOrderItem> parsedItems = [];
    if (map['items'] != null && map['items'] is List) {
      parsedItems = (map['items'] as List)
          .map((item) => SelfOrderItem.fromMap(item as Map<String, dynamic>))
          .toList();
    }

    return OpenBillOrder(
      timestamp: parsedTimestamp,
      items: parsedItems,
      orderTotal: (map['orderTotal'] ?? 0).toInt(),
      orderTakeAwayFee: (map['orderTakeAwayFee'] ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': Timestamp.fromDate(timestamp),
      'items': items.map((item) => item.toMap()).toList(),
      'orderTotal': orderTotal,
      'orderTakeAwayFee': orderTakeAwayFee,
    };
  }
}

class OpenBill {
  final String memberId;
  final String memberName;
  final DateTime createdAt;
  final int totalAmount;
  final List<OpenBillOrder> orders;
  final String status;
  final String? statusDocId;
  final int customerNumber;
  final int takeAwayFee;

  OpenBill({
    required this.memberId,
    required this.memberName,
    required this.createdAt,
    required this.totalAmount,
    required this.orders,
    required this.status,
    this.statusDocId,
    this.customerNumber = 0,
    this.takeAwayFee = 0,
  });

  /// Parse from a root Status doc (NEW data flow)
  factory OpenBill.fromStatusDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    DateTime parsedCreatedAt = data['waktuPesan'] != null
        ? (data['waktuPesan'] as Timestamp).toDate()
        : DateTime.now();

    int storedTakeAwayFee = (data['takeAwayFee'] ?? 0).toInt();

    // Parse order history if available; fall back to flat orderItems for legacy docs
    List<OpenBillOrder> parsedOrders = [];
    if (data['orderHistory'] != null && data['orderHistory'] is List && (data['orderHistory'] as List).isNotEmpty) {
      parsedOrders = (data['orderHistory'] as List)
          .map((o) => OpenBillOrder.fromMap(o as Map<String, dynamic>))
          .toList();
    } else {
      // Legacy: build a single OpenBillOrder from the flat orderItems array
      List<SelfOrderItem> allItems = [];
      if (data['orderItems'] != null && data['orderItems'] is List) {
        allItems = (data['orderItems'] as List)
            .map((item) => SelfOrderItem.fromMap(item as Map<String, dynamic>))
            .toList();
      }
      if (allItems.isNotEmpty) {
        parsedOrders = [
          OpenBillOrder(
            timestamp: parsedCreatedAt,
            items: allItems,
            orderTotal: (data['total'] ?? 0).toInt(),
            orderTakeAwayFee: storedTakeAwayFee,
          )
        ];
      }
    }

    return OpenBill(
      memberId: data['memberId'] ?? doc.id,
      memberName: data['namaCustomer'] ?? '',
      createdAt: parsedCreatedAt,
      totalAmount: (data['total'] ?? 0).toInt(),
      orders: parsedOrders,
      status: (data['isClosed'] == true) ? 'settled' : 'open',
      statusDocId: doc.id,
      customerNumber: (data['customerNumber'] ?? 0).toInt(),
      takeAwayFee: storedTakeAwayFee,
    );
  }

  /// Parse from deeply nested OpenBills doc (LEGACY — kept for backwards compat)
  factory OpenBill.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    DateTime parsedCreatedAt = data['createdAt'] != null 
        ? (data['createdAt'] as Timestamp).toDate() 
        : DateTime.now();

    List<OpenBillOrder> parsedOrders = [];
    if (data['orders'] != null && data['orders'] is List) {
      parsedOrders = (data['orders'] as List)
          .map((o) => OpenBillOrder.fromMap(o as Map<String, dynamic>))
          .toList();
    }

    return OpenBill(
      memberId: doc.id,
      memberName: data['memberName'] ?? '',
      createdAt: parsedCreatedAt,
      totalAmount: (data['totalAmount'] ?? 0).toInt(),
      orders: parsedOrders,
      status: data['status'] ?? 'open',
      statusDocId: data['statusDocId'] as String?,
      customerNumber: (data['customerNumber'] ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'memberId': memberId,
      'memberName': memberName,
      'createdAt': Timestamp.fromDate(createdAt),
      'totalAmount': totalAmount,
      'orders': orders.map((o) => o.toMap()).toList(),
      'status': status,
      if (statusDocId != null) 'statusDocId': statusDocId,
      'customerNumber': customerNumber,
      'takeAwayFee': takeAwayFee,
    };
  }
  
  bool get isOpen => status == 'open';
  bool get isFlagged => status == 'flagged';
}

class SettledBill extends OpenBill {
  final DateTime settledAt;
  final String paymentMethod;
  final int finalTotal;
  final int discountAmount;
  final String? voucherCode;

  SettledBill({
    required super.memberId,
    required super.memberName,
    required super.createdAt,
    required super.totalAmount,
    required super.orders,
    required this.settledAt,
    required this.paymentMethod,
    required this.finalTotal,
    required this.discountAmount,
    this.voucherCode,
    super.status = 'settled',
  });

  factory SettledBill.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Parse base OpenBill fields
    final baseBill = OpenBill.fromFirestore(doc);

    // Parse SettledBill specific fields
    DateTime parsedSettledAt = data['settledAt'] != null 
        ? (data['settledAt'] as Timestamp).toDate() 
        : DateTime.now();

    return SettledBill(
      memberId: baseBill.memberId,
      memberName: baseBill.memberName,
      createdAt: baseBill.createdAt,
      totalAmount: baseBill.totalAmount,
      orders: baseBill.orders,
      settledAt: parsedSettledAt,
      paymentMethod: data['paymentMethod'] ?? 'Unknown',
      finalTotal: (data['finalTotal'] ?? baseBill.totalAmount).toInt(),
      discountAmount: (data['discountAmount'] ?? 0).toInt(),
      voucherCode: data['voucherCode'],
    );
  }

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    map.addAll({
      'settledAt': Timestamp.fromDate(settledAt),
      'paymentMethod': paymentMethod,
      'finalTotal': finalTotal,
      'discountAmount': discountAmount,
      if (voucherCode != null) 'voucherCode': voucherCode,
    });
    return map;
  }
}
