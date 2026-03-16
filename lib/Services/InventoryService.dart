import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';

class InventoryService {
  static final InventoryService _instance = InventoryService._internal();
  factory InventoryService() => _instance;
  InventoryService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String canteenId = 'canteen375';

  // Cache for inventory items
  Map<String, InventoryItem> _inventoryCache = {};

  /// Fetch all inventory items and cache them
  Future<void> refreshInventoryCache() async {
    try {
      final snapshot = await _firestore
          .collection('Canteens')
          .doc(canteenId)
          .collection('Inventory')
          .get();

      _inventoryCache.clear();
      for (var doc in snapshot.docs) {
        final item = InventoryItem.fromFirestore(doc);
        _inventoryCache[item.id] = item;
      }
    } catch (e) {
      print('Error refreshing inventory cache: $e');
    }
  }

  /// Get inventory item by ID
  InventoryItem? getInventoryItem(String id) {
    return _inventoryCache[id];
  }

  /// Check if a menu item is available (warns if stock is low)
  Future<MenuAvailability> checkMenuAvailability(MenuObject menu, int quantity) async {
    // If no ingredients, item is always available
    if (menu.ingredients.isEmpty) {
      return MenuAvailability(
        isAvailable: true,
        message: 'Available',
      );
    }

    // Refresh cache to get latest stock
    await refreshInventoryCache();

    bool hasInsufficient = false;
    String warningMessage = '';

    // Check each ingredient
    for (var ingredient in menu.ingredients) {
      final inventoryItem = _inventoryCache[ingredient.inventoryItemId];
      
      if (inventoryItem == null) {
        return MenuAvailability(
          isAvailable: false, // Core data missing is still an error
          message: 'Ingredient "${ingredient.inventoryItemName}" not found in inventory',
          missingIngredient: ingredient.inventoryItemName,
        );
      }

      final requiredStock = ingredient.quantityNeeded * quantity;
      if (inventoryItem.stock < requiredStock) {
        hasInsufficient = true;
        warningMessage += '${ingredient.inventoryItemName} (Stock: ${inventoryItem.stock}), ';
      }
    }

    if (hasInsufficient) {
      return MenuAvailability(
        isAvailable: true, // Allow proceeding even if stock is low
        hasWarning: true,
        message: 'Stok kurang: ${warningMessage.substring(0, warningMessage.length - 2)}',
      );
    }

    return MenuAvailability(
      isAvailable: true,
      message: 'Available',
    );
  }

  /// Deduct ingredients from inventory when an order is placed
  Future<bool> deductIngredients(MenuObject menu, int quantity) async {
    if (menu.ingredients.isEmpty) return true;

    try {
      // Use a batch write for atomicity
      final batch = _firestore.batch();
      final ingredientsToLog = <Map<String, dynamic>>[];

      for (var ingredient in menu.ingredients) {
        final docRef = _firestore
            .collection('Canteens')
            .doc(canteenId)
            .collection('Inventory')
            .doc(ingredient.inventoryItemId);

        final requiredStock = ingredient.quantityNeeded * quantity;
        
        // Get current stock
        final doc = await docRef.get();
        if (!doc.exists) {
          print('Ingredient ${ingredient.inventoryItemName} not found');
          return false;
        }

        final data = doc.data()!;
        final int currentStock = (data['stock'] ?? 0) as int;
        final isPerishable = data['isPerishable'] ?? false;
        
        // Allowed to go negative: Removed the (currentStock < requiredStock) check

        // Deduct stock
        batch.update(docRef, {'stock': currentStock - requiredStock});
        
        // Store for logging after successful batch
        ingredientsToLog.add({
          'id': ingredient.inventoryItemId,
          'name': ingredient.inventoryItemName,
          'quantity': requiredStock,
          'isPerishable': isPerishable,
        });
      }

      await batch.commit();
      
      // Log all stock usage
      for (var ing in ingredientsToLog) {
        await _logStockUsage(
          ing['id'],
          ing['name'],
          ing['quantity'],
          'Order: ${menu.namaMenu} x$quantity',
          ing['isPerishable'],
        );
      }
      
      await refreshInventoryCache(); // Refresh cache after update
      return true;
    } catch (e) {
      print('Error deducting ingredients: $e');
      return false;
    }
  }

  /// Get all inventory items
  Stream<List<InventoryItem>> getInventoryStream() {
    return _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('Inventory')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => InventoryItem.fromFirestore(doc))
            .toList());
  }

  /// Update inventory stock
  Future<void> updateInventoryStock(String inventoryId, int newStock) async {
    // Get current stock for logging difference
    final doc = await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('Inventory')
        .doc(inventoryId)
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      final int oldStock = (data['stock'] ?? 0) as int;
      final int diff = newStock - oldStock;
      final itemName = data['name'] ?? '';
      final isPerishable = data['isPerishable'] ?? false;

      if (diff > 0) {
        // Log as added stock
        await _logStockAdded(inventoryId, itemName, diff, 'Manual restock', isPerishable);
      } else if (diff < 0) {
        // Log as usage (for auditing/corrections)
        await _logStockUsage(inventoryId, itemName, diff.abs(), 'Manual adjustment/reduction', isPerishable);
      }
    }

    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('Inventory')
        .doc(inventoryId)
        .update({'stock': newStock});
    
    await refreshInventoryCache();
  }

  /// Add new inventory item
  Future<String> addInventoryItem(String name, int stock, String unit, {bool isPerishable = false}) async {
    final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final docId = '${name}_$epoch';
    
    final docRef = _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('Inventory')
        .doc(docId);

    await docRef.set({
      'name': name,
      'stock': stock,
      'unit': unit,
      'isPerishable': isPerishable,
    });
    
    await refreshInventoryCache();
    
    // Log the initial stock
    if (stock > 0) {
      await _logStockAdded(docId, name, stock, 'Initial stock', isPerishable);
    }
    
    return docId;
  }

  /// Log stock usage (when used in orders)
  Future<void> _logStockUsage(String inventoryItemId, String itemName, int quantity, String reason, bool isPerishable) async {
    final today = _getTodayDateString();
    final logId = '${today}_$itemName';

    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('DailyStockLogs')
        .doc(logId)
        .set({
      'date': today,
      'inventoryItemId': inventoryItemId,
      'inventoryItemName': itemName,
      'isPerishable': isPerishable,
      'stockUsed': FieldValue.increment(quantity),
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Log stock added (when manually restocked)
  Future<void> _logStockAdded(String inventoryItemId, String itemName, int quantity, String reason, bool isPerishable) async {
    final today = _getTodayDateString();
    final logId = '${today}_$itemName';

    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('DailyStockLogs')
        .doc(logId)
        .set({
      'date': today,
      'inventoryItemId': inventoryItemId,
      'inventoryItemName': itemName,
      'isPerishable': isPerishable,
      'stockAdded': FieldValue.increment(quantity),
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Log stock waste (perishables at end of day)
  Future<void> _logStockWaste(String inventoryItemId, String itemName, int quantity, bool isPerishable) async {
    final today = _getTodayDateString();
    final logId = '${today}_$itemName';

    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('DailyStockLogs')
        .doc(logId)
        .set({
      'date': today,
      'inventoryItemId': inventoryItemId,
      'inventoryItemName': itemName,
      'isPerishable': isPerishable,
      'stockWasted': FieldValue.increment(quantity),
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Update inventory item metadata (name, unit, isPerishable)
  Future<void> updateInventoryItem(String id, String name, String unit, bool isPerishable) async {
    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('Inventory')
        .doc(id)
        .update({
      'name': name,
      'unit': unit,
      'isPerishable': isPerishable,
    });
    await refreshInventoryCache();
  }

  /// Delete inventory item
  Future<void> deleteInventoryItem(String id) async {
    await _firestore
        .collection('Canteens')
        .doc(canteenId)
        .collection('Inventory')
        .doc(id)
        .delete();
    await refreshInventoryCache();
  }

  /// Helper to get today's date as string (YYYY-MM-DD)
  String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

class MenuAvailability {
  final bool isAvailable;
  final bool hasWarning;
  final String message;
  final String? missingIngredient;
  final int? availableQuantity;

  MenuAvailability({
    required this.isAvailable,
    this.hasWarning = false,
    required this.message,
    this.missingIngredient,
    this.availableQuantity,
  });
}
