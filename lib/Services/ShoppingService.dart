import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SupplierItem {
  final String name;
  final String unit;
  final bool isPerishable;

  SupplierItem({
    required this.name,
    required this.unit,
    required this.isPerishable,
  });

  factory SupplierItem.fromMap(Map<String, dynamic> map) {
    return SupplierItem(
      name: map['name'] ?? '',
      unit: map['unit'] ?? 'pcs',
      isPerishable: map['isPerishable'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'unit': unit,
      'isPerishable': isPerishable,
    };
  }
}

class Supplier {
  final String id;
  final String name;
  final List<SupplierItem> items;

  Supplier({
    required this.id,
    required this.name,
    required this.items,
  });

  factory Supplier.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Supplier(
      id: doc.id,
      name: data['name'] ?? '',
      items: (data['items'] as List<dynamic>? ?? [])
          .map((i) => SupplierItem.fromMap(i))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'items': items.map((i) => i.toMap()).toList(),
    };
  }
}

class ShoppingOrderItem {
  final String name;
  final int quantity;
  final String unit;
  final bool isPerishable;

  ShoppingOrderItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.isPerishable,
  });

  factory ShoppingOrderItem.fromMap(Map<String, dynamic> map) {
    return ShoppingOrderItem(
      name: map['name'] ?? '',
      quantity: map['quantity'] ?? 0,
      unit: map['unit'] ?? 'pcs',
      isPerishable: map['isPerishable'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'isPerishable': isPerishable,
    };
  }
}

class ShoppingOrder {
  final String id;
  final String supplierId;
  final String supplierName;
  final DateTime date;
  final List<ShoppingOrderItem> items;
  final String status;

  ShoppingOrder({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.date,
    required this.items,
    required this.status,
  });

  factory ShoppingOrder.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return ShoppingOrder(
      id: doc.id,
      supplierId: data['supplierId'] ?? '',
      supplierName: data['supplierName'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      items: (data['items'] as List<dynamic>? ?? [])
          .map((i) => ShoppingOrderItem.fromMap(i))
          .toList(),
      status: data['status'] ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'supplierId': supplierId,
      'supplierName': supplierName,
      'date': Timestamp.fromDate(date),
      'items': items.map((i) => i.toMap()).toList(),
      'status': status,
    };
  }
}

class ShoppingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String canteenId = 'canteen375';

  static Stream<List<Supplier>> getSuppliersStream() {
    return _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('suppliers')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Supplier.fromFirestore(doc)).toList());
  }

  static Future<void> addSupplier(String name, List<SupplierItem> items) async {
    final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final encodedName = name.replaceAll(' ', '_');
    final docId = '${encodedName}_$epoch';

    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('suppliers')
        .doc(docId)
        .set({
      'name': name,
      'items': items.map((i) => i.toMap()).toList(),
    });
  }

  static Future<void> updateSupplier(String id, String name, List<SupplierItem> items) async {
    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('suppliers')
        .doc(id)
        .update({
      'name': name,
      'items': items.map((i) => i.toMap()).toList(),
    });
  }

  static Future<void> deleteSupplier(String id) async {
    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('suppliers')
        .doc(id)
        .delete();
  }

  static Stream<List<ShoppingOrder>> getOrdersStream({DateTime? startDate, DateTime? endDate}) {
    var query = _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('shoppingOrders')
        .orderBy('date', descending: true);

    if (startDate != null && endDate != null) {
      query = query
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    } else {
      // Default performance: Only show today's orders
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

      query = query
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfToday));
    }

    return query.snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => ShoppingOrder.fromFirestore(doc)).toList());
  }

  static Future<void> updateOrderItems(String orderId, List<ShoppingOrderItem> items) async {
    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('shoppingOrders')
        .doc(orderId)
        .update({
      'items': items.map((i) => i.toMap()).toList(),
    });
  }

  static Future<void> createOrder(String supplierId, String supplierName, List<ShoppingOrderItem> items) async {
    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('shoppingOrders')
        .add({
      'supplierId': supplierId,
      'supplierName': supplierName,
      'date': FieldValue.serverTimestamp(),
      'items': items.map((i) => i.toMap()).toList(),
      'status': 'pending',
    });
  }

  static Future<void> completeOrder(ShoppingOrder order) async {
    final batch = _firestore.batch();
    
    // Update order status
    final orderRef = _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('shoppingOrders')
        .doc(order.id);
    batch.update(orderRef, {'status': 'completed'});

    // Add items to inventory. Check if exists by name first.
    final inventoryService = InventoryService();
    
    for (var item in order.items) {
      final existingSnapshot = await _firestore
          .collection('Canteens')
          .doc(canteenId)
          .collection('Inventory')
          .where('name', isEqualTo: item.name)
          .limit(1)
          .get();

      if (existingSnapshot.docs.isNotEmpty) {
        // Exists, update stock by incrementing
        batch.update(existingSnapshot.docs.first.reference, {
          'stock': FieldValue.increment(item.quantity)
        });
      } else {
        // Doesn't exist, create it with initial stock
        final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final encodedName = item.name.replaceAll(' ', '_');
        final inventoryDocId = '${encodedName}_$epoch';
        
        final inventoryRef = _firestore
            .collection('Canteens')
            .doc(canteenId)
            .collection('Inventory')
            .doc(inventoryDocId);

        batch.set(inventoryRef, {
          'name': item.name,
          'stock': item.quantity,
          'unit': item.unit.isEmpty ? 'pcs' : item.unit,
          'isPerishable': item.isPerishable,
        });
      }
    }

    await batch.commit();
    await inventoryService.refreshInventoryCache();
  }

  static Future<void> generateOrderPdf(ShoppingOrder order) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Pesanan Belanja (Shopping Order)',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('Supplier: ${order.supplierName}',
                  style: pw.TextStyle(fontSize: 18)),
              pw.Text(
                  'Tanggal: ${order.date.day}/${order.date.month}/${order.date.year}',
                  style: const pw.TextStyle(fontSize: 16)),
              pw.SizedBox(height: 30),
              pw.Table.fromTextArray(
                context: context,
                border: pw.TableBorder.all(),
                headerAlignment: pw.Alignment.centerLeft,
                data: <List<String>>[
                  <String>['Nama Item', 'Unit', 'Jumlah'],
                  ...order.items.map((item) => [
                        item.name,
                        item.unit,
                        item.quantity.toString(),
                      ]),
                ],
              ),
              pw.SizedBox(height: 50),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  children: [
                    pw.Text('Penerima / Admin'),
                    pw.SizedBox(height: 50),
                    pw.Text('____________________')
                  ]
                )
              )
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save());
  }
}
