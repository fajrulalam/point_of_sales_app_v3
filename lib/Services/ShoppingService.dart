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

  /// Resolves a supplier/order item's display name to the linked inventory
  /// item's current name, falling back to [fallback] when no inventoryItemId
  /// is set or the cache cannot resolve it. Callers should ensure the
  /// InventoryService cache is warm (call `refreshInventoryCache` on screen
  /// init) so renames in Inventory propagate to Shopping immediately.
  static String displayName(String? inventoryItemId, String fallback) {
    if (inventoryItemId != null && inventoryItemId.isNotEmpty) {
      final inv = InventoryService().allInventoryItems[inventoryItemId];
      if (inv != null) return inv.name;
    }
    return fallback;
  }

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
    final orderRef = _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('shoppingOrders')
        .doc(order.id);

    // Guard: re-fetch current status to avoid double-increment on rapid double-tap
    // or concurrent completion from another device.
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw Exception('Pesanan tidak ditemukan.');
    }
    if ((orderSnap.data()?['status'] as String?) == 'completed') {
      return;
    }

    final inventoryCol = _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('Inventory');
    final dailyLogsCol = _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('DailyStockLogs');

    // Aggregate quantities in memory, keyed by the inventory doc id we resolve to.
    // `_StockTarget.exists` tells us whether we can update() or must create/merge-set().
    final Map<String, _StockTarget> targets = {};
    // Names pending creation inside this order (no id, no name match in DB) —
    // reused so duplicate names within one order coalesce into one new inventory doc.
    final Map<String, String> pendingDocIdsByName = {};

    for (final item in order.items) {
      if (item.quantity <= 0) continue;

      String? docId = item.inventoryItemId;
      bool existsInDb = false;

      if (docId != null && docId.isNotEmpty) {
        final snap = await inventoryCol.doc(docId).get();
        existsInDb = snap.exists;
      }

      // Fallback: no id OR the linked doc was deleted — try matching by name
      if (docId == null || docId.isEmpty || !existsInDb) {
        final nameMatch = await inventoryCol
            .where('name', isEqualTo: item.name)
            .limit(1)
            .get();

        if (nameMatch.docs.isNotEmpty) {
          docId = nameMatch.docs.first.id;
          existsInDb = true;
        } else if (pendingDocIdsByName.containsKey(item.name)) {
          // Same name already queued for creation in this order — reuse the id
          docId = pendingDocIdsByName[item.name]!;
          existsInDb = false;
        } else {
          final epoch = DateTime.now().millisecondsSinceEpoch;
          final encodedName = item.name.replaceAll(' ', '_');
          docId = '${encodedName}_$epoch';
          pendingDocIdsByName[item.name] = docId;
          existsInDb = false;
        }
      }

      final existing = targets[docId];
      if (existing != null) {
        existing.qty += item.quantity;
      } else {
        targets[docId] = _StockTarget(
          item: item,
          qty: item.quantity,
          exists: existsInDb,
        );
      }
    }

    // Single batch so order-status update + all inventory writes commit atomically.
    // Each item contributes at most 2 writes (inventory + daily log) plus the
    // order update, so a realistic shopping order stays well under the 500-op limit.
    final batch = _firestore.batch();
    batch.update(orderRef, {'status': 'completed'});

    final today = _getTodayDateString();

    for (final entry in targets.entries) {
      final docId = entry.key;
      final target = entry.value;
      final invRef = inventoryCol.doc(docId);

      if (target.exists) {
        batch.update(invRef, {'stock': FieldValue.increment(target.qty)});
      } else {
        // Either the linked doc was deleted post-order, or the item has no id and
        // no name match — create/merge the doc so stock is not lost.
        batch.set(invRef, {
          'name': target.item.name,
          'stock': FieldValue.increment(target.qty),
          'unit': target.item.unit.isEmpty ? 'pcs' : target.item.unit,
          'isPerishable': target.item.isPerishable,
        }, SetOptions(merge: true));
      }

      // Audit trail — keep parity with InventoryService._logStockAdded so daily
      // reports reflect stock received from shopping orders.
      final logRef = dailyLogsCol.doc('${today}_$docId');
      batch.set(logRef, {
        'date': today,
        'inventoryItemId': docId,
        'inventoryItemName': displayName(docId, target.item.name),
        'isPerishable': target.item.isPerishable,
        'stockAdded': FieldValue.increment(target.qty),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    await InventoryService().refreshInventoryCache();
  }

  static String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static Future<void> generateOrderPdf(ShoppingOrder order) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
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
                      displayName(item.inventoryItemId, item.name),
                      item.unit,
                      item.quantity.toString(),
                    ]),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save());
  }

  static Future<String> saveOrderAsImage(ShoppingOrder order) async {
    final doc = pw.Document();

    final calculatedHeight = 250.0 + (order.items.length + 1) * 35.0;
    final pageFormat = PdfPageFormat(
      PdfPageFormat.a4.width,
      calculatedHeight > PdfPageFormat.a4.height ? calculatedHeight : PdfPageFormat.a4.height,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
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
                        displayName(item.inventoryItemId, item.name),
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

class _StockTarget {
  final ShoppingOrderItem item;
  int qty;
  final bool exists;

  _StockTarget({
    required this.item,
    required this.qty,
    required this.exists,
  });
}
