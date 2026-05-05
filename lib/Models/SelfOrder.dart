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
  final String orderCode;
  final String customerPhone;
  final bool isMember;
  final String memberId;
  final String namaCustomer;
  final String status;
  final List<SelfOrderItem> orderItems;
  final int total;
  final int directSubTotal;
  final int directTakeAwayFee;
  final String transactionMethod;
  final String waktuPengambilan;
  final DateTime waktuPesan;
  final String? declineReason;

  SelfOrder({
    required this.id,
    required this.canteenId,
    required this.orderCode,
    required this.customerPhone,
    required this.isMember,
    required this.memberId,
    required this.namaCustomer,
    required this.status,
    required this.orderItems,
    required this.total,
    required this.directSubTotal,
    required this.directTakeAwayFee,
    required this.transactionMethod,
    required this.waktuPengambilan,
    required this.waktuPesan,
    this.declineReason,
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
      orderCode: data['orderCode'] ?? '',
      customerPhone: data['customerPhone'] ?? '',
      isMember: data['isMember'] ?? false,
      memberId: data['memberId'] ?? data['userId'] ?? '',
      namaCustomer: data['namaCustomer'] ?? data['memberName'] ?? '',
      status: data['status'] ?? 'Pending',
      orderItems: items,
      total: (data['total'] ?? 0).toInt(),
      directSubTotal: (data['subTotal'] ?? 0).toInt(),
      directTakeAwayFee: (data['takeAwayFee'] ?? 0).toInt(),
      transactionMethod: data['transactionMethod'] ?? 'SelfOrder',
      waktuPengambilan: data['waktuPengambilan'] ?? 'Tidak Memesan',
      waktuPesan: parsedWaktuPesan,
      declineReason: data['declineReason'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'canteenId': canteenId,
      'orderCode': orderCode,
      'customerPhone': customerPhone,
      'isMember': isMember,
      'memberId': memberId,
      'namaCustomer': namaCustomer,
      'status': status,
      'orderItems': orderItems.map((item) => item.toMap()).toList(),
      'total': total,
      'subTotal': directSubTotal,
      'takeAwayFee': directTakeAwayFee,
      'transactionMethod': transactionMethod,
      'waktuPengambilan': waktuPengambilan,
      'waktuPesan': Timestamp.fromDate(waktuPesan),
      'declineReason': declineReason,
    };
  }

  // Helper getters for compatibility and UI
  String get memberName => namaCustomer;
  String get userId => memberId;
  DateTime get timestamp => waktuPesan;
  String get displayShortCode => orderCode;

  // Use direct fields from Firestore, fallback to calculated values
  int get calculatedSubtotal =>
      orderItems.fold(0, (sum, item) => sum + item.itemTotal);

  int get subtotal => directSubTotal > 0 ? directSubTotal : calculatedSubtotal;
  int get takeAwayFee => directTakeAwayFee;

  bool get isUnpaid => status == 'Pending';
  bool get isPaid => status == 'Paid';
  bool get isDeclined => status == 'Declined';
  bool get isProcessing => status == 'Serving';

  bool get hasTakeAwayItems =>
      orderItems.any((item) => item.takeAwayQuantity > 0);
  bool get hasDineInItems => orderItems.any((item) => item.dineInQuantity > 0);

  int get totalItemCount =>
      orderItems.fold(0, (sum, item) => sum + item.totalQuantity);

  SelfOrder copyWith({
    String? id,
    String? canteenId,
    String? orderCode,
    String? customerPhone,
    bool? isMember,
    String? memberId,
    String? namaCustomer,
    String? status,
    List<SelfOrderItem>? orderItems,
    int? total,
    int? directSubTotal,
    int? directTakeAwayFee,
    String? transactionMethod,
    String? waktuPengambilan,
    DateTime? waktuPesan,
    String? declineReason,
  }) {
    return SelfOrder(
      id: id ?? this.id,
      canteenId: canteenId ?? this.canteenId,
      orderCode: orderCode ?? this.orderCode,
      customerPhone: customerPhone ?? this.customerPhone,
      isMember: isMember ?? this.isMember,
      memberId: memberId ?? this.memberId,
      namaCustomer: namaCustomer ?? this.namaCustomer,
      status: status ?? this.status,
      orderItems: orderItems ?? this.orderItems,
      total: total ?? this.total,
      directSubTotal: directSubTotal ?? this.directSubTotal,
      directTakeAwayFee: directTakeAwayFee ?? this.directTakeAwayFee,
      transactionMethod: transactionMethod ?? this.transactionMethod,
      waktuPengambilan: waktuPengambilan ?? this.waktuPengambilan,
      waktuPesan: waktuPesan ?? this.waktuPesan,
      declineReason: declineReason ?? this.declineReason,
    );
  }
}

/// Status constants for self-orders
class SelfOrderStatus {
  static const String unpaid = 'Pending';
  static const String processing = 'Serving';
  static const String paid = 'Paid';
  static const String declined = 'Declined';
}
