import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';

/// Represents an individual item in a self-order
class SelfOrderItem {
  final String namaPesanan;
  final int harga;
  final int dineInQuantity;
  final int takeAwayQuantity;
  final bool isMakanan;
  final List<SelectedOption> selectedOptions;

  SelfOrderItem({
    required this.namaPesanan,
    required this.harga,
    required this.dineInQuantity,
    required this.takeAwayQuantity,
    this.isMakanan = true,
    this.selectedOptions = const [],
  });

  factory SelfOrderItem.fromMap(Map<String, dynamic> map) {
    return SelfOrderItem(
      namaPesanan: map['namaPesanan'] ?? '',
      harga: (map['harga'] ?? 0).toInt(),
      dineInQuantity: (map['dineInQuantity'] ?? 0).toInt(),
      takeAwayQuantity: (map['takeAwayQuantity'] ?? 0).toInt(),
      isMakanan: map['isMakanan'] ?? true,
      selectedOptions: (map['selectedOptions'] as List<dynamic>?)
              ?.map((o) => SelectedOption.fromMap(o as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'namaPesanan': namaPesanan,
      'harga': harga,
      'dineInQuantity': dineInQuantity,
      'takeAwayQuantity': takeAwayQuantity,
      'isMakanan': isMakanan,
      'selectedOptions': selectedOptions.map((o) => o.toMap()).toList(),
    };
  }

  int get totalQuantity => dineInQuantity + takeAwayQuantity;

  int get optionsTotal =>
      selectedOptions.fold(0, (sum, o) => sum + o.priceAdjustment);

  int get effectivePrice => harga + optionsTotal;

  int get itemTotal => effectivePrice * totalQuantity;
}

/// Represents a self-order placed by a member through the Member's app
class SelfOrder {
  final String id;
  final String canteenId;
  final int customerNumber;
  final String customerPhone;
  final bool isMember;
  final String memberId;
  final String namaCustomer;
  final String status;
  final List<SelfOrderItem> orderItems;
  final int total;
  final String transactionMethod;
  final String waktuPengambilan;
  final DateTime waktuPesan;
  final String? declineReason;
  final String? shortCode; // Keep for UI compatibility if needed, fallback to customerNumber

  SelfOrder({
    required this.id,
    required this.canteenId,
    required this.customerNumber,
    required this.customerPhone,
    required this.isMember,
    required this.memberId,
    required this.namaCustomer,
    required this.status,
    required this.orderItems,
    required this.total,
    required this.transactionMethod,
    required this.waktuPengambilan,
    required this.waktuPesan,
    this.declineReason,
    this.shortCode,
  });

  factory SelfOrder.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse timestamp
    DateTime parsedWaktuPesan;
    if (data['waktuPesan'] is Timestamp) {
      parsedWaktuPesan = (data['waktuPesan'] as Timestamp).toDate();
    } else {
      parsedWaktuPesan = DateTime.now();
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
      canteenId: data['canteenId'] ?? '',
      customerNumber: (data['customerNumber'] ?? 0).toInt(),
      customerPhone: data['customerPhone'] ?? '',
      isMember: data['isMember'] ?? false,
      memberId: data['memberId'] ?? data['userId'] ?? '',
      namaCustomer: data['namaCustomer'] ?? data['memberName'] ?? '',
      status: data['status'] ?? 'Unpaid',
      orderItems: items,
      total: (data['total'] ?? 0).toInt(),
      transactionMethod: data['transactionMethod'] ?? 'Self Order',
      waktuPengambilan: data['waktuPengambilan'] ?? 'Tidak Memesan',
      waktuPesan: parsedWaktuPesan,
      declineReason: data['declineReason'],
      shortCode: data['shortCode'] ?? (data['customerNumber']?.toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'canteenId': canteenId,
      'customerNumber': customerNumber,
      'customerPhone': customerPhone,
      'isMember': isMember,
      'memberId': memberId,
      'namaCustomer': namaCustomer,
      'status': status,
      'orderItems': orderItems.map((item) => item.toMap()).toList(),
      'total': total,
      'transactionMethod': transactionMethod,
      'waktuPengambilan': waktuPengambilan,
      'waktuPesan': Timestamp.fromDate(waktuPesan),
      'declineReason': declineReason,
      'shortCode': shortCode,
    };
  }

  // Helper getters for compatibility and UI
  String get memberName => namaCustomer;
  String get userId => memberId;
  DateTime get timestamp => waktuPesan;
  String get displayShortCode => shortCode ?? customerNumber.toString();

  // Calculated subtotal for UI if needed
  int get calculatedSubtotal =>
      orderItems.fold(0, (sum, item) => sum + item.itemTotal);

  int get subtotal => calculatedSubtotal;
  int get takeAwayFee => total - subtotal;

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
    String? canteenId,
    int? customerNumber,
    String? customerPhone,
    bool? isMember,
    String? memberId,
    String? namaCustomer,
    String? status,
    List<SelfOrderItem>? orderItems,
    int? total,
    String? transactionMethod,
    String? waktuPengambilan,
    DateTime? waktuPesan,
    String? declineReason,
    String? shortCode,
  }) {
    return SelfOrder(
      id: id ?? this.id,
      canteenId: canteenId ?? this.canteenId,
      customerNumber: customerNumber ?? this.customerNumber,
      customerPhone: customerPhone ?? this.customerPhone,
      isMember: isMember ?? this.isMember,
      memberId: memberId ?? this.memberId,
      namaCustomer: namaCustomer ?? this.namaCustomer,
      status: status ?? this.status,
      orderItems: orderItems ?? this.orderItems,
      total: total ?? this.total,
      transactionMethod: transactionMethod ?? this.transactionMethod,
      waktuPengambilan: waktuPengambilan ?? this.waktuPengambilan,
      waktuPesan: waktuPesan ?? this.waktuPesan,
      declineReason: declineReason ?? this.declineReason,
      shortCode: shortCode ?? this.shortCode,
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
