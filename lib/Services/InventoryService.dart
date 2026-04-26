import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
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
  
  /// Expose the current inventory cache for selection dropdowns
  Map<String, InventoryItem> get allInventoryItems => _inventoryCache;

  /// Fetch all inventory items and cache them
  Future<void> refreshInventoryCache() async {
    try {
      final snapshot = await _firestore
          .collection(Col.name('Canteens'))
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

  /// Max servings possible from current cache for a list of ingredients.
  /// Returns null if no ingredients, or the minimum stock/quantityNeeded ratio.
  int? getMaxServings(List<MenuIngredient> ingredients) {
    if (ingredients.isEmpty) return null;
    int? min;
    for (final ing in ingredients) {
      final item = _inventoryCache[ing.inventoryItemId];
      if (item == null || ing.quantityNeeded <= 0) continue;
      final servings = item.stock ~/ ing.quantityNeeded;
      if (min == null || servings < min) min = servings;
    }
    return min;
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



  /// Aggregate ingredients from menu + selected options into a single map.
  /// Returns {inventoryItemId: {name, totalQuantity}} with duplicates merged.
  Map<String, Map<String, dynamic>> aggregateIngredients(
    List<MenuIngredient> menuIngredients,
    List<MenuIngredient> optionIngredients,
    int quantity,
  ) {
    final aggregated = <String, Map<String, dynamic>>{};

    for (var ingredient in [...menuIngredients, ...optionIngredients]) {
      if (aggregated.containsKey(ingredient.inventoryItemId)) {
        aggregated[ingredient.inventoryItemId]!['quantityNeeded'] =
            (aggregated[ingredient.inventoryItemId]!['quantityNeeded'] as int) +
                ingredient.quantityNeeded;
      } else {
        aggregated[ingredient.inventoryItemId] = {
          'name': ingredient.inventoryItemName,
          'quantityNeeded': ingredient.quantityNeeded,
        };
      }
    }

    // Multiply by order quantity
    for (var entry in aggregated.values) {
      entry['totalRequired'] = (entry['quantityNeeded'] as int) * quantity;
    }

    return aggregated;
  }

  /// Check availability considering both menu ingredients and option ingredients.
  Future<MenuAvailability> checkOrderAvailability(
    MenuObject menu,
    List<MenuIngredient> optionIngredients,
    int quantity,
  ) async {
    if (menu.ingredients.isEmpty && optionIngredients.isEmpty) {
      return MenuAvailability(isAvailable: true, message: 'Available');
    }

    await refreshInventoryCache();

    final aggregated = aggregateIngredients(
      menu.ingredients, optionIngredients, quantity,
    );

    bool hasInsufficient = false;
    String warningMessage = '';

    for (var entry in aggregated.entries) {
      final inventoryItem = _inventoryCache[entry.key];
      if (inventoryItem == null) {
        return MenuAvailability(
          isAvailable: false,
          message: 'Ingredient "${entry.value['name']}" not found in inventory',
          missingIngredient: entry.value['name'] as String,
        );
      }

      final required = entry.value['totalRequired'] as int;
      if (inventoryItem.stock < required) {
        hasInsufficient = true;
        warningMessage += '${entry.value['name']} (Stock: ${inventoryItem.stock}), ';
      }
    }

    if (hasInsufficient) {
      return MenuAvailability(
        isAvailable: true,
        hasWarning: true,
        message: 'Stok kurang: ${warningMessage.substring(0, warningMessage.length - 2)}',
      );
    }

    return MenuAvailability(isAvailable: true, message: 'Available');
  }

  /// Append deductions for a fully aggregated ingredient list into a WriteBatch using increment
  Future<void> batchDeductAggregatedIngredients(
    Map<String, Map<String, dynamic>> finalAggregated,
    WriteBatch batch,
  ) async {
    if (finalAggregated.isEmpty) return;

    await refreshInventoryCache();
    final today = _getTodayDateString();

    for (var entry in finalAggregated.entries) {
      final inventoryId = entry.key;
      final stockName = entry.value['name'] as String;
      final totalRequired = entry.value['totalRequired'] as int;

      final inventoryItem = _inventoryCache[inventoryId];
      final isPerishable = inventoryItem?.isPerishable ?? false;

      // 1. Queue stock deduction safely using Firebase increment
      final docRef = _firestore
          .collection(Col.name('Canteens'))
          .doc(canteenId)
          .collection('Inventory')
          .doc(inventoryId);

      batch.update(docRef, {'stock': FieldValue.increment(-totalRequired)});

      // 2. Queue daily stock usage log safely
      final logId = '${today}_$inventoryId';
      final logRef = _firestore
          .collection(Col.name('Canteens'))
          .doc(canteenId)
          .collection('DailyStockLogs')
          .doc(logId);

      batch.set(logRef, {
        'date': today,
        'inventoryItemId': inventoryId,
        'inventoryItemName': stockName,
        'isPerishable': isPerishable,
        'stockUsed': FieldValue.increment(totalRequired),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Same as batchDeductAggregatedIngredients but for Firestore Transactions
  Future<void> transactionDeductAggregatedIngredients(
    Map<String, Map<String, dynamic>> finalAggregated,
    Transaction transaction,
  ) async {
    if (finalAggregated.isEmpty) return;

    await refreshInventoryCache();
    final today = _getTodayDateString();

    for (var entry in finalAggregated.entries) {
      final inventoryId = entry.key;
      final stockName = entry.value['name'] as String;
      final totalRequired = entry.value['totalRequired'] as int;

      final inventoryItem = _inventoryCache[inventoryId];
      final isPerishable = inventoryItem?.isPerishable ?? false;

      // 1. Queue stock deduction safely using Firebase increment
      final docRef = _firestore
          .collection(Col.name('Canteens'))
          .doc(canteenId)
          .collection('Inventory')
          .doc(inventoryId);

      transaction.update(docRef, {'stock': FieldValue.increment(-totalRequired)});

      // 2. Queue daily stock usage log safely
      final logId = '${today}_$inventoryId';
      final logRef = _firestore
          .collection(Col.name('Canteens'))
          .doc(canteenId)
          .collection('DailyStockLogs')
          .doc(logId);

      transaction.set(logRef, {
        'date': today,
        'inventoryItemId': inventoryId,
        'inventoryItemName': stockName,
        'isPerishable': isPerishable,
        'stockUsed': FieldValue.increment(totalRequired),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Get all inventory items
  Stream<List<InventoryItem>> getInventoryStream() {
    return _firestore
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
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
        .collection(Col.name('Canteens'))
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

  /// Delete inventory item safely
  Future<void> deleteInventoryItem(String id) async {
    bool isUsed = false;
    String usedWhere = '';

    // 1. Check MenuCollection
    final menuQuery = await _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('MenuCollection')
        .get();

    for (var doc in menuQuery.docs) {
      final data = doc.data();
      final ingredients = (data['ingredients'] as List<dynamic>?) ?? [];
      for (var ing in ingredients) {
        if (ing['inventoryItemId'] == id) {
          isUsed = true;
          usedWhere = 'Menu "${data['namaMenu']}"';
          break;
        }
      }
      if (isUsed) break;
    }

    // 2. Check OptionGroups
    if (!isUsed) {
      final optionsQuery = await _firestore
          .collection(Col.name('Canteens'))
          .doc(canteenId)
          .collection('OptionGroups')
          .get();

      for (var doc in optionsQuery.docs) {
        final data = doc.data();
        final options = (data['options'] as List<dynamic>?) ?? [];
        for (var opt in options) {
          final ingredients = (opt['ingredients'] as List<dynamic>?) ?? [];
          for (var ing in ingredients) {
            if (ing['inventoryItemId'] == id) {
              isUsed = true;
              usedWhere = 'Opsi "${opt['name']}" di Grup "${data['name']}"';
              break;
            }
          }
          if (isUsed) break;
        }
        if (isUsed) break;
      }
    }

    if (isUsed) {
      throw Exception('Bahan tidak dapat dihapus karena sedang digunakan dalam $usedWhere. Hapus bahan ini dari resep terlebih dahulu.');
    }

    await _firestore
        .collection(Col.name('Canteens'))
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
