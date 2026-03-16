import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryItem {
  String id;
  String name;
  int stock;
  String unit; // e.g., "pcs", "kg", "liter"
  bool isPerishable; // NEW: Track if item needs daily reset

  InventoryItem({
    required this.id,
    required this.name,
    required this.stock,
    this.unit = 'pcs',
    this.isPerishable = false,
  });

  factory InventoryItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InventoryItem(
      id: doc.id,
      name: data['name'] ?? '',
      stock: data['stock'] ?? 0,
      unit: data['unit'] ?? 'pcs',
      isPerishable: data['isPerishable'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'stock': stock,
      'unit': unit,
      'isPerishable': isPerishable,
    };
  }
}

class MenuIngredient {
  String inventoryItemId;
  String inventoryItemName;
  int quantityNeeded;

  MenuIngredient({
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.quantityNeeded,
  });

  factory MenuIngredient.fromMap(Map<String, dynamic> map) {
    return MenuIngredient(
      inventoryItemId: map['inventoryItemId'] ?? '',
      inventoryItemName: map['inventoryItemName'] ?? '',
      quantityNeeded: map['quantityNeeded'] ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'inventoryItemId': inventoryItemId,
      'inventoryItemName': inventoryItemName,
      'quantityNeeded': quantityNeeded,
    };
  }
}

/// Daily stock log for tracking inventory movements
class DailyStockLog {
  String id; // Format: "YYYY-MM-DD_{inventoryItemId}"
  String date; // Format: "YYYY-MM-DD"
  String inventoryItemId;
  String inventoryItemName;
  bool isPerishable;
  
  int startingStock; // Stock at beginning of day
  int stockAdded; // Total added during the day
  int stockUsed; // Total used in orders
  int stockWasted; // Perishables left at end of day
  int endingStock; // Stock at end of day
  
  Timestamp? lastUpdated;

  DailyStockLog({
    required this.id,
    required this.date,
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.isPerishable,
    this.startingStock = 0,
    this.stockAdded = 0,
    this.stockUsed = 0,
    this.stockWasted = 0,
    this.endingStock = 0,
    this.lastUpdated,
  });

  factory DailyStockLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DailyStockLog(
      id: doc.id,
      date: data['date'] ?? '',
      inventoryItemId: data['inventoryItemId'] ?? '',
      inventoryItemName: data['inventoryItemName'] ?? '',
      isPerishable: data['isPerishable'] ?? false,
      startingStock: data['startingStock'] ?? 0,
      stockAdded: data['stockAdded'] ?? 0,
      stockUsed: data['stockUsed'] ?? 0,
      stockWasted: data['stockWasted'] ?? 0,
      endingStock: data['endingStock'] ?? 0,
      lastUpdated: data['lastUpdated'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'inventoryItemId': inventoryItemId,
      'inventoryItemName': inventoryItemName,
      'isPerishable': isPerishable,
      'startingStock': startingStock,
      'stockAdded': stockAdded,
      'stockUsed': stockUsed,
      'stockWasted': stockWasted,
      'endingStock': endingStock,
      'lastUpdated': FieldValue.serverTimestamp(),
    };
  }
}

/// Individual stock transaction for detailed tracking
class StockTransaction {
  String type; // 'add', 'use', 'waste', 'reset'
  int quantity;
  String reason; // e.g., "Order #123", "End of day reset", "Manual add"
  Timestamp timestamp;

  StockTransaction({
    required this.type,
    required this.quantity,
    required this.reason,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'quantity': quantity,
      'reason': reason,
      'timestamp': timestamp,
    };
  }
}
