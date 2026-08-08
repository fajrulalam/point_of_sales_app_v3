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
      name: map['name']?.toString() ?? '',
      unit: map['unit']?.toString() ?? 'pcs',
      isPerishable: map['isPerishable'] == true,
      inventoryItemId: map['inventoryItemId']?.toString(),
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
    final rawQuantity = map['quantity'];
    return ShoppingOrderItem(
      name: map['name']?.toString() ?? '',
      quantity: rawQuantity is num
          ? rawQuantity.toInt()
          : int.tryParse('$rawQuantity') ?? 0,
      unit: map['unit']?.toString() ?? 'pcs',
      isPerishable: map['isPerishable'] == true,
      inventoryItemId: map['inventoryItemId']?.toString(),
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
    final rawDate = data['date'];
    return ShoppingOrder(
      id: doc.id,
      supplierId: data['supplierId']?.toString() ?? '',
      supplierName: data['supplierName']?.toString() ?? '',
      date: rawDate is Timestamp ? rawDate.toDate() : DateTime.now(),
      items: (data['items'] as List<dynamic>? ?? [])
          .map((i) => ShoppingOrderItem.fromMap(i))
          .toList(),
      status: data['status']?.toString().toLowerCase() ?? 'pending',
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

  static Future<void> updateSupplier(
      String id, String name, List<SupplierItem> items) async {
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

  static Stream<List<ShoppingOrder>> getOrdersStream(
      {DateTime? startDate, DateTime? endDate}) {
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
      // Default performance: Only show the last 7 days of orders
      final now = DateTime.now();
      final startOfRange = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
      final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

      query = query
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfRange))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfToday));
    }

    return query.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => ShoppingOrder.fromFirestore(doc)).toList());
  }

  static Future<void> updateOrderItems(
      String orderId, List<ShoppingOrderItem> items) async {
    if (items.any((item) => item.quantity < 0)) {
      throw Exception('Jumlah belanja tidak boleh negatif.');
    }
    final orderRef = _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('shoppingOrders')
        .doc(orderId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(orderRef);
      if (!snapshot.exists) throw Exception('Pesanan tidak ditemukan.');
      final status =
          (snapshot.data()?['status']?.toString() ?? 'pending').toLowerCase();
      if (status != 'pending') {
        throw Exception('Pesanan yang sudah dikonfirmasi tidak dapat diubah.');
      }
      transaction.update(orderRef, {
        'items': items.map((i) => i.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<ShoppingOrder> createOrder(String supplierId,
      String supplierName, List<ShoppingOrderItem> items) async {
    if (items.any((item) => item.quantity < 0)) {
      throw Exception('Jumlah belanja tidak boleh negatif.');
    }
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
      'updatedAt': FieldValue.serverTimestamp(),
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

  static Future<InventoryOperationResult> completeOrder(
      ShoppingOrder order) async {
    final orderRef = _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('shoppingOrders')
        .doc(order.id);

    final inventoryCol = _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('Inventory');

    // Name fallback is prepared outside the transaction. Stable IDs are still
    // preferred, and duplicate names are treated as ambiguous.
    final inventorySnapshot = await inventoryCol.get();
    final idsByName = <String, List<String>>{};
    for (final doc in inventorySnapshot.docs) {
      final name = doc.data()['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) idsByName.putIfAbsent(name, () => []).add(doc.id);
    }
    String? resolveId(ShoppingOrderItem item) {
      final stableId = item.inventoryItemId?.trim() ?? '';
      if (stableId.isNotEmpty) return stableId;
      final nameMatches = idsByName[item.name.trim()] ?? const <String>[];
      return nameMatches.length == 1 ? nameMatches.single : null;
    }

    final operationRef = _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('Orders')
        .doc('shopping_${order.id}');

    final result = await _firestore
        .runTransaction<InventoryOperationResult>((transaction) async {
      final operationSnapshot = await transaction.get(operationRef);
      if (operationSnapshot.exists &&
          operationSnapshot.data()?['status']?.toString().toLowerCase() ==
              'completed') {
        return const InventoryOperationResult.alreadyApplied();
      }

      final orderSnapshot = await transaction.get(orderRef);
      if (!orderSnapshot.exists) throw Exception('Pesanan tidak ditemukan.');
      final data = orderSnapshot.data() ?? <String, dynamic>{};
      final status = (data['status']?.toString() ?? 'pending').toLowerCase();
      if (status == 'completed')
        return const InventoryOperationResult.alreadyApplied();
      if (status != 'pending') {
        throw Exception('Status pesanan tidak dapat dikonfirmasi: $status');
      }

      final rawItems = data['items'] is List
          ? data['items'] as List<dynamic>
          : const <dynamic>[];
      final flags = <InventoryAuditFlag>[];
      if (data['items'] != null && data['items'] is! List) {
        flags.add(InventoryAuditFlag(
          code: 'invalid_shopping_items',
          message:
              'Daftar barang pesanan belanja tidak tersimpan dengan benar dan dilewati.',
          sourceType: 'shopping_order',
          sourceId: order.id,
        ));
      }
      final mapItems = rawItems.whereType<Map>().toList();
      if (mapItems.length != rawItems.length) {
        flags.add(InventoryAuditFlag(
          code: 'invalid_shopping_item_entry',
          message: 'One or more malformed shopping items were skipped.',
          sourceType: 'shopping_order',
          sourceId: order.id,
        ));
      }
      final latestItems = mapItems
          .map((item) =>
              ShoppingOrderItem.fromMap(Map<String, dynamic>.from(item)))
          .toList();
      final deltas = <StockDelta>[];
      for (final item in latestItems) {
        if (item.quantity <= 0) {
          if (item.quantity < 0) {
            flags.add(InventoryAuditFlag(
              code: 'invalid_shopping_quantity',
              message:
                  'Shopping item "${item.name}" has a negative quantity and was skipped.',
              inventoryItemName: item.name,
              sourceType: 'shopping_order',
              sourceId: order.id,
            ));
          }
          continue;
        }
        final resolvedId = resolveId(item);
        deltas.add(StockDelta(
          inventoryItemId: resolvedId ?? '',
          inventoryItemName: item.name,
          stockChange: item.quantity,
          stockAddedChange: item.quantity,
        ));
        if (resolvedId == null) {
          flags.add(InventoryAuditFlag(
            code: 'missing_shopping_inventory_link',
            message:
                'Shopping item "${item.name}" has no stable or unique exact-name inventory link.',
            inventoryItemId: item.inventoryItemId,
            inventoryItemName: item.name,
            sourceType: 'shopping_order',
            sourceId: order.id,
            requiredQuantity: item.quantity,
          ));
        }
      }

      final stockResult =
          await InventoryService().applyStockDeltasInTransaction(
        transaction,
        deltas,
        sourceType: 'shopping_order',
        sourceId: order.id,
        additionalAuditFlags: flags,
      );
      final auditFlags = stockResult.auditFlags;
      transaction.update(orderRef, {
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'inventoryOperationId': 'shopping_${order.id}',
        'inventoryAuditFlags': auditFlags.map((flag) => flag.toMap()).toList(),
      });
      transaction.set(
          operationRef,
          {
            'status': 'completed',
            'type': 'shopping_completion',
            'sourceId': order.id,
            'completedAt': FieldValue.serverTimestamp(),
            'auditFlags': auditFlags.map((flag) => flag.toMap()).toList(),
          },
          SetOptions(merge: true));
      return InventoryOperationResult.applied(flags: auditFlags);
    });

    await InventoryService().refreshInventoryCache();
    return result;
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
                style:
                    pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
            pw.Text('Supplier: ${order.supplierName}',
                style: pw.TextStyle(fontSize: 18)),
            pw.Text(
                'Tanggal: ${order.date.day}/${order.date.month}/${order.date.year}',
                style: const pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 30),
            pw.Table.fromTextArray(
              context: context,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.green700,
              ),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
              cellHeight: 30,
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
      calculatedHeight > PdfPageFormat.a4.height
          ? calculatedHeight
          : PdfPageFormat.a4.height,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Pesanan Belanja (Shopping Order)',
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('Supplier: ${order.supplierName}',
                  style: pw.TextStyle(fontSize: 18)),
              pw.Text(
                  'Tanggal: ${order.date.day}/${order.date.month}/${order.date.year}',
                  style: const pw.TextStyle(fontSize: 16)),
              pw.SizedBox(height: 30),
              pw.Table.fromTextArray(
                context: context,
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                headerAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.green700,
                ),
                oddRowDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                ),
                cellHeight: 30,
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
    final sanitizedName =
        order.supplierName.replaceAll(RegExp(r'[^\w\s]'), '_');
    final fileName =
        'pesanan_${sanitizedName}_${order.date.year}${order.date.month.toString().padLeft(2, '0')}${order.date.day.toString().padLeft(2, '0')}.jpg';
    final filePath = p.join(tempDir.path, fileName);

    // Rasterise the first page of the PDF into raw PNG bytes
    final pages = await Printing.raster(pdfBytes, dpi: 200).toList();
    final pngBytes = await pages.first.toPng();

    // Decode PNG and composite onto white background, then encode as JPEG
    // This fixes the transparent-background-turns-black issue on Android
    final decoded = img.decodePng(pngBytes);
    if (decoded == null)
      throw Exception('Failed to decode rasterized PDF page');
    final whiteBackground =
        img.Image(width: decoded.width, height: decoded.height)
          ..clear(img.ColorRgb8(255, 255, 255));
    img.compositeImage(whiteBackground, decoded);
    final jpegBytes = img.encodeJpg(whiteBackground, quality: 90);

    final file = File(filePath);
    await file.writeAsBytes(jpegBytes);
    return filePath;
  }

  /// Deletes a pending shopping order.
  static Future<void> deleteOrder(String orderId) async {
    final orderRef = _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('shoppingOrders')
        .doc(orderId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(orderRef);
      if (!snapshot.exists) return;
      final status =
          (snapshot.data()?['status']?.toString() ?? 'pending').toLowerCase();
      if (status != 'pending') {
        throw Exception('Pesanan yang sudah dikonfirmasi tidak dapat dihapus.');
      }
      transaction.delete(orderRef);
    });
  }

  /// Generates the order image and opens it with the device's native image viewer.
  static Future<void> openOrderAsImage(ShoppingOrder order) async {
    final imagePath = await saveOrderAsImage(order);
    await OpenFile.open(imagePath);
  }
}
