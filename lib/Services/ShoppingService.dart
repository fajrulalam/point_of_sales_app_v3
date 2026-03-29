import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:open_file/open_file.dart';

class SupplierItem {
  final String name;
  final String unit;
  final bool isPerishable;
  final String? inventoryItemId;

  SupplierItem({
    required this.name,
    required this.unit,
    required this.isPerishable,
    this.inventoryItemId,
  });

  factory SupplierItem.fromMap(Map<String, dynamic> map) {
    return SupplierItem(
      name: map['name'] ?? '',
      unit: map['unit'] ?? 'pcs',
      isPerishable: map['isPerishable'] ?? false,
      inventoryItemId: map['inventoryItemId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'unit': unit,
      'isPerishable': isPerishable,
      if (inventoryItemId != null) 'inventoryItemId': inventoryItemId,
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
  final String? inventoryItemId;

  ShoppingOrderItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.isPerishable,
    this.inventoryItemId,
  });

  factory ShoppingOrderItem.fromMap(Map<String, dynamic> map) {
    return ShoppingOrderItem(
      name: map['name'] ?? '',
      quantity: map['quantity'] ?? 0,
      unit: map['unit'] ?? 'pcs',
      isPerishable: map['isPerishable'] ?? false,
      inventoryItemId: map['inventoryItemId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'isPerishable': isPerishable,
      if (inventoryItemId != null) 'inventoryItemId': inventoryItemId,
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
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('suppliers')
        .doc(id)
        .delete();
  }

  static Stream<List<ShoppingOrder>> getOrdersStream({DateTime? startDate, DateTime? endDate}) {
    var query = _firestore
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('shoppingOrders')
        .doc(orderId)
        .update({
      'items': items.map((i) => i.toMap()).toList(),
    });
  }

  static Future<ShoppingOrder> createOrder(String supplierId, String supplierName, List<ShoppingOrderItem> items) async {
    final docRef = await _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('shoppingOrders')
        .add({
      'supplierId': supplierId,
      'supplierName': supplierName,
      'date': FieldValue.serverTimestamp(),
      'items': items.map((i) => i.toMap()).toList(),
      'status': 'pending',
    });
    return ShoppingOrder(
      id: docRef.id,
      supplierId: supplierId,
      supplierName: supplierName,
      date: DateTime.now(),
      items: items,
      status: 'pending',
    );
  }

  static Future<void> completeOrder(ShoppingOrder order) async {
    final batch = _firestore.batch();
    
    // Update order status
    final orderRef = _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('shoppingOrders')
        .doc(order.id);
    batch.update(orderRef, {'status': 'completed'});

    // Memory aggregators to prevent multi-update errors per-batch and name collision races
    final Map<String, int> incrementById = {};
    final Map<String, int> incrementByName = {};
    final Map<String, ShoppingOrderItem> rawNewItems = {};

    final inventoryService = InventoryService();
    
    // Process items entirely in memory first
    for (var item in order.items) {
      if (item.inventoryItemId != null && item.inventoryItemId!.isNotEmpty) {
        incrementById[item.inventoryItemId!] = (incrementById[item.inventoryItemId!] ?? 0) + item.quantity;
      } else {
        // Fallback to name search
        final existingSnapshot = await _firestore
            .collection(Col.name('Canteens'))
            .doc(canteenId)
            .collection('Inventory')
            .where('name', isEqualTo: item.name)
            .limit(1)
            .get();

        if (existingSnapshot.docs.isNotEmpty) {
           final docId = existingSnapshot.docs.first.id;
           incrementById[docId] = (incrementById[docId] ?? 0) + item.quantity;
        } else {
           incrementByName[item.name] = (incrementByName[item.name] ?? 0) + item.quantity;
           rawNewItems[item.name] = item;
        }
      }
    }

    // Translate aggregations to batch writes safely
    for (var docId in incrementById.keys) {
      final ref = _firestore
          .collection(Col.name('Canteens'))
          .doc(canteenId)
          .collection('Inventory')
          .doc(docId);
      batch.update(ref, {'stock': FieldValue.increment(incrementById[docId]!)});
    }

    for (var name in incrementByName.keys) {
      final item = rawNewItems[name]!;
      final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final encodedName = name.replaceAll(' ', '_');
      final newDocId = '${encodedName}_$epoch';

      final inventoryRef = _firestore
          .collection(Col.name('Canteens'))
          .doc(canteenId)
          .collection('Inventory')
          .doc(newDocId);

      batch.set(inventoryRef, {
        'name': name,
        'stock': incrementByName[name]!,
        'unit': item.unit.isEmpty ? 'pcs' : item.unit,
        'isPerishable': item.isPerishable,
      });
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
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save());
  }

  /// Renders the order PDF as a PNG image and returns the file path.
  static Future<String> saveOrderAsImage(ShoppingOrder order) async {
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
            ],
          );
        },
      ),
    );

    final pdfBytes = await doc.save();
    final tempDir = await getTemporaryDirectory();
    final sanitizedName = order.supplierName.replaceAll(RegExp(r'[^\w\s]'), '_');
    final fileName = 'pesanan_${sanitizedName}_${order.date.year}${order.date.month.toString().padLeft(2, '0')}${order.date.day.toString().padLeft(2, '0')}.jpg';
    final filePath = p.join(tempDir.path, fileName);

    // Rasterise the first page of the PDF into raw PNG bytes
    final pages = await Printing.raster(pdfBytes, dpi: 200).toList();
    final pngBytes = await pages.first.toPng();

    // Decode PNG and composite onto white background, then encode as JPEG
    // This fixes the transparent-background-turns-black issue on Android
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) throw Exception('Failed to decode rasterized PDF page');
    final whiteBackground = img.Image(width: decoded.width, height: decoded.height)
      ..clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(whiteBackground, decoded);
    final jpegBytes = img.encodeJpg(whiteBackground, quality: 90);

    final file = File(filePath);
    await file.writeAsBytes(jpegBytes);
    return filePath;
  }

  /// Deletes a pending shopping order.
  static Future<void> deleteOrder(String orderId) async {
    await _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('shoppingOrders')
        .doc(orderId)
        .delete();
  }

  /// Generates the order image and opens it with the device's native image viewer.
  static Future<void> openOrderAsImage(ShoppingOrder order) async {
    final imagePath = await saveOrderAsImage(order);
    await OpenFile.open(imagePath);
  }
}
