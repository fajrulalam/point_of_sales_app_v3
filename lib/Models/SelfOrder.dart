import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an individual item in a self-order
class SelfOrderItem {
  final String namaPesanan;
  final int harga;
  final int dineInQuantity;
  final int takeAwayQuantity;
  final List<dynamic> selectedOptions;

  SelfOrderItem({
    required this.namaPesanan,
    required this.harga,
    required this.dineInQuantity,
    required this.takeAwayQuantity,
    this.selectedOptions = const [],
  });

  factory SelfOrderItem.fromMap(Map<String, dynamic> map) {
    return SelfOrderItem(
      namaPesanan: map['namaPesanan'] ?? '',
      harga: (map['harga'] ?? 0).toInt(),
      dineInQuantity: (map['dineInQuantity'] ?? 0).toInt(),
      takeAwayQuantity: (map['takeAwayQuantity'] ?? 0).toInt(),
      selectedOptions: map['selectedOptions'] ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'namaPesanan': namaPesanan,
      'harga': harga,
      'dineInQuantity': dineInQuantity,
      'takeAwayQuantity': takeAwayQuantity,
      'selectedOptions': selectedOptions,
    };
  }

  int get totalQuantity => dineInQuantity + takeAwayQuantity;

  int get itemTotal => harga * totalQuantity;
}

/// Represents a self-order placed by a member through the Member's app
class SelfOrder {
  final String id;
  final String memberName;
  final String userId;
  final String shortCode;
  final String status;
  final List<SelfOrderItem> orderItems;
  final int subtotal;
  final int takeAwayFee;
  final int total;
  final DateTime timestamp;
  final String? declineReason;

  SelfOrder({
    required this.id,
    required this.memberName,
    required this.userId,
    required this.shortCode,
    required this.status,
    required this.orderItems,
    required this.subtotal,
    required this.takeAwayFee,
    required this.total,
    required this.timestamp,
    this.declineReason,
  });

  factory SelfOrder.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse timestamp
    DateTime parsedTimestamp;
    if (data['timestamp'] is Timestamp) {
      parsedTimestamp = (data['timestamp'] as Timestamp).toDate();
    } else {
      parsedTimestamp = DateTime.now();
    }

    // Parse order items
    List<SelfOrderItem> items = [];
    if (data['orderItems'] != null && data['orderItems'] is List) {
      items = (data['orderItems'] as List)
          .map((item) => SelfOrderItem.fromMap(item as Map<String, dynamic>))
          .toList();
    }

    return SelfOrder(
      id: doc.id,
      memberName: data['memberName'] ?? '',
      userId: data['userId'] ?? '',
      shortCode: data['shortCode'] ?? '',
      status: data['status'] ?? 'Unpaid',
      orderItems: items,
      subtotal: (data['subtotal'] ?? 0).toInt(),
      takeAwayFee: (data['takeAwayFee'] ?? 0).toInt(),
      total: (data['total'] ?? 0).toInt(),
      timestamp: parsedTimestamp,
      declineReason: data['declineReason'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'memberName': memberName,
      'userId': userId,
      'shortCode': shortCode,
      'status': status,
      'orderItems': orderItems.map((item) => item.toMap()).toList(),
      'subtotal': subtotal,
      'takeAwayFee': takeAwayFee,
      'total': total,
      'timestamp': Timestamp.fromDate(timestamp),
      'declineReason': declineReason,
    };
  }

  bool get isUnpaid => status == 'Unpaid';
  bool get isPaid => status == 'Paid';
  bool get isDeclined => status == 'Declined';
  bool get isProcessing => status == 'Processing';

  bool get hasTakeAwayItems =>
      orderItems.any((item) => item.takeAwayQuantity > 0);
  bool get hasDineInItems => orderItems.any((item) => item.dineInQuantity > 0);

  int get totalItemCount =>
      orderItems.fold(0, (sum, item) => sum + item.totalQuantity);

  SelfOrder copyWith({
    String? id,
    String? memberName,
    String? userId,
    String? shortCode,
    String? status,
    List<SelfOrderItem>? orderItems,
    int? subtotal,
    int? takeAwayFee,
    int? total,
    DateTime? timestamp,
    String? declineReason,
  }) {
    return SelfOrder(
      id: id ?? this.id,
      memberName: memberName ?? this.memberName,
      userId: userId ?? this.userId,
      shortCode: shortCode ?? this.shortCode,
      status: status ?? this.status,
      orderItems: orderItems ?? this.orderItems,
      subtotal: subtotal ?? this.subtotal,
      takeAwayFee: takeAwayFee ?? this.takeAwayFee,
      total: total ?? this.total,
      timestamp: timestamp ?? this.timestamp,
      declineReason: declineReason ?? this.declineReason,
    );
  }
}

/// Status constants for self-orders
class SelfOrderStatus {
  static const String unpaid = 'Unpaid';
  static const String processing = 'Processing';
  static const String paid = 'Paid';
  static const String declined = 'Declined';
}
