import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';

/// Represents an individual item in a self-order
class SelfOrderItem {
  final String menuItemId;
  final String namaPesanan;
  final int harga;
  final int dineInQuantity;
  final int takeAwayQuantity;
  final bool isMakanan;
  final List<SelectedOption> selectedOptions;

  SelfOrderItem({
    this.menuItemId = '',
    required this.namaPesanan,
    required this.harga,
    required this.dineInQuantity,
    required this.takeAwayQuantity,
    this.isMakanan = true,
    this.selectedOptions = const [],
  });

  factory SelfOrderItem.fromMap(Map<String, dynamic> map) {
    List<SelectedOption> parsedOptions = [];
    try {
      if (map['selectedOptions'] != null && map['selectedOptions'] is List) {
        parsedOptions = (map['selectedOptions'] as List)
            .map((o) {
              if (o is Map) {
                return SelectedOption.fromMap(Map<String, dynamic>.from(o));
              }
              return null;
            })
            .whereType<SelectedOption>()
            .toList();
      }
    } catch (e) {
      print('Error parsing selectedOptions: $e');
    }

    return SelfOrderItem(
      menuItemId: map['menuItemId']?.toString() ?? '',
      namaPesanan: map['namaPesanan']?.toString() ?? '',
      harga: int.tryParse(map['harga']?.toString() ?? '0') ?? 0,
      dineInQuantity: int.tryParse(map['dineInQuantity']?.toString() ?? '0') ?? 0,
      takeAwayQuantity: int.tryParse(map['takeAwayQuantity']?.toString() ?? '0') ?? 0,
      isMakanan: map['isMakanan'] == true,
      selectedOptions: parsedOptions,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'menuItemId': menuItemId,
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
    try {
      final data = doc.data() as Map<String, dynamic>? ?? {};

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
            .map((item) {
              if (item is Map) {
                return SelfOrderItem.fromMap(Map<String, dynamic>.from(item));
              }
              return null;
            })
            .whereType<SelfOrderItem>()
            .toList();
      }

      return SelfOrder(
        id: doc.id,
        canteenId: data['canteenId']?.toString() ?? '',
        orderCode: data['orderCode']?.toString() ?? '',
        customerPhone: data['customerPhone']?.toString() ?? '',
        isMember: data['isMember'] == true,
        memberId: (data['memberId'] ?? data['userId'])?.toString() ?? '',
        namaCustomer: (data['namaCustomer'] ?? data['memberName'])?.toString() ?? '',
        status: data['status']?.toString() ?? 'Pending',
        orderItems: items,
        total: int.tryParse(data['total']?.toString() ?? '0') ?? 0,
        directSubTotal: int.tryParse(data['subTotal']?.toString() ?? '0') ?? 0,
        directTakeAwayFee: int.tryParse(data['takeAwayFee']?.toString() ?? '0') ?? 0,
        transactionMethod: data['transactionMethod']?.toString() ?? 'SelfOrder',
        waktuPengambilan: data['waktuPengambilan']?.toString() ?? 'Tidak Memesan',
        waktuPesan: parsedWaktuPesan,
        declineReason: data['declineReason']?.toString(),
      );
    } catch (e, stacktrace) {
      print('Error parsing SelfOrder from doc ${doc.id}: $e');
      print(stacktrace);
      // Return a fallback empty order to prevent stream from completely failing
      return SelfOrder(
        id: doc.id,
        canteenId: 'error',
        orderCode: 'ERROR',
        customerPhone: '',
        isMember: false,
        memberId: '',
        namaCustomer: 'Error Loading',
        status: 'Error',
        orderItems: [],
        total: 0,
        directSubTotal: 0,
        directTakeAwayFee: 0,
        transactionMethod: 'Error',
        waktuPengambilan: '',
        waktuPesan: DateTime.now(),
      );
    }
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
