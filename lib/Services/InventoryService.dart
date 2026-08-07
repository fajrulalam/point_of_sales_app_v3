import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';

enum InventoryOperationStatus { applied, alreadyApplied }

class InventoryAuditFlag {
  final String code;
  final String message;
  final String? inventoryItemId;
  final String? inventoryItemName;
  final String? sourceType;
  final String? sourceId;
  final int? requiredQuantity;
  final int? stockBefore;
  final int? stockAfter;
  final int? deficit;

  const InventoryAuditFlag({
    required this.code,
    required this.message,
    this.inventoryItemId,
    this.inventoryItemName,
    this.sourceType,
    this.sourceId,
    this.requiredQuantity,
    this.stockBefore,
    this.stockAfter,
    this.deficit,
  });

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'message': message,
      if (inventoryItemId != null) 'inventoryItemId': inventoryItemId,
      if (inventoryItemName != null) 'inventoryItemName': inventoryItemName,
      if (sourceType != null) 'sourceType': sourceType,
      if (sourceId != null) 'sourceId': sourceId,
      if (requiredQuantity != null) 'requiredQuantity': requiredQuantity,
      if (stockBefore != null) 'stockBefore': stockBefore,
      if (stockAfter != null) 'stockAfter': stockAfter,
      if (deficit != null) 'deficit': deficit,
    };
  }

  factory InventoryAuditFlag.fromMap(Map<String, dynamic> map) {
    int? asInt(dynamic value) =>
        value is num ? value.toInt() : int.tryParse('$value');
    return InventoryAuditFlag(
      code: map['code']?.toString() ?? 'unknown_audit_flag',
      message: map['message']?.toString() ?? '',
      inventoryItemId: map['inventoryItemId']?.toString(),
      inventoryItemName: map['inventoryItemName']?.toString(),
      sourceType: map['sourceType']?.toString(),
      sourceId: map['sourceId']?.toString(),
      requiredQuantity: asInt(map['requiredQuantity']),
      stockBefore: asInt(map['stockBefore']),
      stockAfter: asInt(map['stockAfter']),
      deficit: asInt(map['deficit']),
    );
  }
}

class InventoryOperationResult {
  final InventoryOperationStatus status;
  final List<InventoryAuditFlag> auditFlags;
  final int? customerNumber;

  const InventoryOperationResult({
    required this.status,
    this.auditFlags = const [],
    this.customerNumber,
  });

  bool get wasApplied => status == InventoryOperationStatus.applied;
  bool get wasAlreadyApplied =>
      status == InventoryOperationStatus.alreadyApplied;

  factory InventoryOperationResult.applied({
    List<InventoryAuditFlag> flags = const [],
    int? customerNumber,
  }) {
    return InventoryOperationResult(
      status: InventoryOperationStatus.applied,
      auditFlags: List.unmodifiable(flags),
      customerNumber: customerNumber,
    );
  }

  const InventoryOperationResult.alreadyApplied()
      : status = InventoryOperationStatus.alreadyApplied,
        auditFlags = const [],
        customerNumber = null;
}

class StockRequirement {
  final String inventoryItemId;
  final String inventoryItemName;
  final int quantity;

  const StockRequirement({
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.quantity,
  });
}

class StockRequirementCalculation {
  final List<StockRequirement> requirements;
  final List<StockDelta> deltas;
  final List<InventoryAuditFlag> auditFlags;

  const StockRequirementCalculation({
    required this.requirements,
    required this.deltas,
    this.auditFlags = const [],
  });
}

class StockDelta {
  final String inventoryItemId;
  final String inventoryItemName;
  final int stockChange;
  final int stockUsedChange;
  final int stockAddedChange;

  const StockDelta({
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.stockChange,
    this.stockUsedChange = 0,
    this.stockAddedChange = 0,
  });
}

class StockTransactionResult {
  final List<InventoryAuditFlag> auditFlags;

  const StockTransactionResult({this.auditFlags = const []});
}

class StockTransactionPreparation {
  final List<StockDelta> deltas;
  final Map<String, DocumentSnapshot<Map<String, dynamic>>> snapshots;
  final List<InventoryAuditFlag> auditFlags;
  final String date;

  const StockTransactionPreparation({
    required this.deltas,
    required this.snapshots,
    required this.auditFlags,
    required this.date,
  });
}

/// Pure stock-requirement calculation kept separate from Firebase access so it
/// can be unit-tested without initializing a Firebase app.
class StockRequirementCalculator {
  static Map<String, Map<String, dynamic>> aggregateIngredients(
    List<MenuIngredient> menuIngredients,
    List<MenuIngredient> optionIngredients,
    int quantity,
  ) {
    if (quantity <= 0) return {};
    final aggregated = <String, Map<String, dynamic>>{};
    for (final ingredient in [...menuIngredients, ...optionIngredients]) {
      if (ingredient.quantityNeeded <= 0) continue;
      final inventoryKey = ingredient.inventoryItemId.trim().isNotEmpty
          ? ingredient.inventoryItemId.trim()
          : '__unresolved__:${ingredient.inventoryItemName.trim()}';
      if (aggregated.containsKey(inventoryKey)) {
        aggregated[inventoryKey]!['quantityNeeded'] =
            (aggregated[inventoryKey]!['quantityNeeded'] as int) +
                ingredient.quantityNeeded;
      } else {
        aggregated[inventoryKey] = {
          'name': ingredient.inventoryItemName,
          'quantityNeeded': ingredient.quantityNeeded,
        };
      }
    }
    for (final entry in aggregated.values) {
      entry['totalRequired'] = (entry['quantityNeeded'] as int) * quantity;
    }
    return aggregated;
  }
}

class InventoryService {
  static final InventoryService _instance = InventoryService._internal();
  factory InventoryService() => _instance;
  InventoryService._internal() {
    // Listen for testing mode changes to clear cache and refresh data
    Col.testingMode.addListener(_handleModeChange);
  }

  void _handleModeChange() {
    _inventoryCache.clear();
    refreshInventoryCache();
  }

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

  CollectionReference<Map<String, dynamic>> get _inventoryCollection =>
      _firestore
          .collection(Col.name('Canteens'))
          .doc(canteenId)
          .collection('Inventory');

  CollectionReference<Map<String, dynamic>> get _dailyLogsCollection =>
      _firestore
          .collection(Col.name('Canteens'))
          .doc(canteenId)
          .collection('DailyStockLogs');

  static String canonicalDailyLogId(String date, String inventoryItemId) {
    return '${date}_$inventoryItemId';
  }

  String todayDateString() => _getTodayDateString();

  static int toInt(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }

  /// Exact-name matches are only safe when the name is unique.
  Map<String, String> exactInventoryNameIndex() {
    final idsByName = <String, List<String>>{};
    for (final item in _inventoryCache.values) {
      final name = item.name.trim();
      if (name.isEmpty) continue;
      idsByName.putIfAbsent(name, () => []).add(item.id);
    }
    return {
      for (final entry in idsByName.entries)
        if (entry.value.length == 1) entry.key: entry.value.single,
    };
  }

  /// Stable ID first, then exact legacy name. Unresolved components remain
  /// unresolved so callers can flag them rather than inventing inventory.
  String? resolveInventoryItemId(
      String? inventoryItemId, String inventoryItemName) {
    final id = inventoryItemId?.trim() ?? '';
    // A populated ID is authoritative. Falling back by name in that case can
    // silently redirect a broken reference to a different inventory record.
    if (id.isNotEmpty) return id;
    return exactInventoryNameIndex()[inventoryItemName.trim()];
  }

  /// Max servings possible from current cache for a list of ingredients.
  /// Returns null if no ingredients, or the minimum stock/quantityNeeded ratio.
  int? getMaxServings(List<MenuIngredient> ingredients) {
    if (ingredients.isEmpty) return null;
    int? min;
    for (final ing in ingredients) {
      final resolvedId = resolveInventoryItemId(
        ing.inventoryItemId,
        ing.inventoryItemName,
      );
      final item = resolvedId == null ? null : _inventoryCache[resolvedId];
      if (item == null || ing.quantityNeeded <= 0) continue;
      final servings = item.stock ~/ ing.quantityNeeded;
      if (min == null || servings < min) min = servings;
    }
    return min;
  }

  /// Check if a menu item is available (warns if stock is low)
  Future<MenuAvailability> checkMenuAvailability(
      MenuObject menu, int quantity) async {
    // If no ingredients, item is always available
    if (menu.ingredients.isEmpty) {
      return MenuAvailability(
        isAvailable: true,
        message: 'Tersedia',
      );
    }

    // Refresh cache to get latest stock
    await refreshInventoryCache();

    bool hasInsufficient = false;
    String warningMessage = '';

    // Check each ingredient
    for (var ingredient in menu.ingredients) {
      final resolvedId = resolveInventoryItemId(
        ingredient.inventoryItemId,
        ingredient.inventoryItemName,
      );
      final inventoryItem =
          resolvedId == null ? null : _inventoryCache[resolvedId];

      if (inventoryItem == null) {
        return MenuAvailability(
          isAvailable: true,
          hasWarning: true,
          message:
              'Bahan "${ingredient.inventoryItemName}" tidak ditemukan di stok',
          missingIngredient: ingredient.inventoryItemName,
        );
      }

      final requiredStock = ingredient.quantityNeeded * quantity;
      if (inventoryItem.stock < requiredStock) {
        hasInsufficient = true;
        warningMessage +=
            '${ingredient.inventoryItemName} (stok: ${inventoryItem.stock}), ';
      }
    }

    if (hasInsufficient) {
      return MenuAvailability(
        isAvailable: true, // Allow proceeding even if stock is low
        hasWarning: true,
        message:
            'Stok kurang: ${warningMessage.substring(0, warningMessage.length - 2)}',
      );
    }

    return MenuAvailability(
      isAvailable: true,
      message: 'Tersedia',
    );
  }

  /// Aggregate ingredients from menu + selected options into a single map.
  /// Returns {inventoryItemId: {name, totalQuantity}} with duplicates merged.
  Map<String, Map<String, dynamic>> aggregateIngredients(
    List<MenuIngredient> menuIngredients,
    List<MenuIngredient> optionIngredients,
    int quantity,
  ) {
    return StockRequirementCalculator.aggregateIngredients(
      menuIngredients,
      optionIngredients,
      quantity,
    );
  }

  /// Calculates all stock movements for an order before any Firestore read or
  /// write. The returned deltas are intentionally unresolved when a menu,
  /// option, or inventory reference cannot be found; the transaction layer
  /// turns those into audit flags without creating substitute inventory docs.
  StockRequirementCalculation calculateOrderStockDeltas(
    List<PesananObject> orders, {
    required Map<String, MenuObject> menuLookup,
    required Map<String, Map<String, OptionItem>> optionLookup,
    required bool deduct,
    required String sourceType,
    required String sourceId,
  }) {
    final deltas = <StockDelta>[];
    final flags = <InventoryAuditFlag>[];

    MenuObject? findMenu(PesananObject order) {
      final stableId = order.menuItemId.trim();
      if (stableId.isNotEmpty) {
        final byId = menuLookup['__id__$stableId'];
        if (byId != null) return byId;
        for (final menu in menuLookup.values) {
          if (menu.id == stableId) return menu;
        }
        // A populated menu ID is authoritative. Do not redirect a broken
        // reference to a different menu that happens to share its name.
        return null;
      }

      // Exact-name lookup is retained only for legacy order records that do
      // not carry a stable menu ID. Callers may provide __name__ keys that
      // suppress ambiguous duplicate names; the direct key preserves
      // compatibility with older callers that only have a name map.
      return menuLookup['__name__${order.namaPesanan.trim()}'] ??
          menuLookup[order.namaPesanan];
    }

    for (final order in orders) {
      final quantity = order.totalQuantity;
      if (quantity <= 0) {
        if (quantity < 0) {
          flags.add(InventoryAuditFlag(
            code: 'invalid_order_quantity',
            message:
                'Menu "${order.namaPesanan}" memiliki jumlah pesanan negatif dan dilewati.',
            sourceType: sourceType,
            sourceId: sourceId,
          ));
        }
        continue;
      }

      final menu = findMenu(order);
      if (menu == null) {
        flags.add(InventoryAuditFlag(
          code: 'missing_menu_reference',
          message: 'Menu "${order.namaPesanan}" tidak dapat ditemukan.',
          sourceType: sourceType,
          sourceId: sourceId,
        ));
        continue;
      }

      final optionIngredients = <MenuIngredient>[];
      for (final selected in order.selectedOptions) {
        final stableGroupId = selected.groupId.trim();
        final group = stableGroupId.isNotEmpty
            ? optionLookup[stableGroupId]
            : optionLookup['__name__${selected.groupName.trim()}'];
        if (group == null) {
          flags.add(InventoryAuditFlag(
            code: 'missing_option_group_reference',
            message:
                'Grup opsi "${selected.groupName}" untuk menu "${order.namaPesanan}" tidak dapat ditemukan.',
            sourceType: sourceType,
            sourceId: sourceId,
          ));
          continue;
        }
        final stableOptionId = selected.optionId.trim();
        final option = stableOptionId.isNotEmpty
            ? group[stableOptionId]
            : group['__name__${selected.optionName.trim()}'];
        if (option == null) {
          flags.add(InventoryAuditFlag(
            code: 'missing_option_reference',
            message:
                'Opsi "${selected.optionName}" untuk menu "${order.namaPesanan}" tidak dapat ditemukan.',
            sourceType: sourceType,
            sourceId: sourceId,
          ));
          continue;
        }
        optionIngredients.addAll(option.ingredients);
      }

      final allIngredients = <MenuIngredient>[
        ...menu.ingredients,
        ...optionIngredients,
      ];
      for (final ingredient in allIngredients) {
        if (ingredient.quantityNeeded <= 0) {
          flags.add(InventoryAuditFlag(
            code: 'invalid_ingredient_quantity',
            message:
                'Bahan "${ingredient.inventoryItemName}" memiliki jumlah tidak valid dan dilewati.',
            inventoryItemId: ingredient.inventoryItemId.trim().isEmpty
                ? null
                : ingredient.inventoryItemId.trim(),
            inventoryItemName: ingredient.inventoryItemName,
            sourceType: sourceType,
            sourceId: sourceId,
          ));
        }
      }

      final aggregated = aggregateIngredients(
        menu.ingredients,
        optionIngredients,
        quantity,
      );
      for (final entry in aggregated.entries) {
        final required = toInt(entry.value['totalRequired']);
        if (required <= 0) continue;
        final name = entry.value['name']?.toString() ?? '';
        final unresolvedKey = entry.key.startsWith('__unresolved__');
        final resolvedId = resolveInventoryItemId(
          unresolvedKey ? null : entry.key,
          name,
        );
        deltas.add(StockDelta(
          inventoryItemId: resolvedId ?? '',
          inventoryItemName: name,
          stockChange: deduct ? -required : required,
          stockUsedChange: deduct ? required : -required,
        ));
      }
    }

    final coalescedDeltas = coalesceStockDeltas(deltas);
    return StockRequirementCalculation(
      requirements: List.unmodifiable(coalescedDeltas
          .map((delta) => StockRequirement(
                inventoryItemId: delta.inventoryItemId,
                inventoryItemName: delta.inventoryItemName,
                quantity: delta.stockChange.abs(),
              ))
          .toList()),
      deltas: coalescedDeltas,
      auditFlags: List.unmodifiable(flags),
    );
  }

  /// Check availability considering both menu ingredients and option ingredients.
  Future<MenuAvailability> checkOrderAvailability(
    MenuObject menu,
    List<MenuIngredient> optionIngredients,
    int quantity,
  ) async {
    if (menu.ingredients.isEmpty && optionIngredients.isEmpty) {
      return MenuAvailability(isAvailable: true, message: 'Tersedia');
    }

    await refreshInventoryCache();

    final aggregated = aggregateIngredients(
      menu.ingredients,
      optionIngredients,
      quantity,
    );

    bool hasInsufficient = false;
    String warningMessage = '';

    for (var entry in aggregated.entries) {
      final resolvedId = resolveInventoryItemId(
        entry.key.startsWith('__unresolved__') ? null : entry.key,
        entry.value['name']?.toString() ?? '',
      );
      final inventoryItem =
          resolvedId == null ? null : _inventoryCache[resolvedId];
      if (inventoryItem == null) {
        return MenuAvailability(
          isAvailable: true,
          hasWarning: true,
          message: 'Bahan "${entry.value['name']}" tidak ditemukan di stok',
          missingIngredient: entry.value['name'] as String,
        );
      }

      final required = entry.value['totalRequired'] as int;
      if (inventoryItem.stock < required) {
        hasInsufficient = true;
        warningMessage +=
            '${entry.value['name']} (stok: ${inventoryItem.stock}), ';
      }
    }

    if (hasInsufficient) {
      return MenuAvailability(
        isAvailable: true,
        hasWarning: true,
        message:
            'Stok kurang: ${warningMessage.substring(0, warningMessage.length - 2)}',
      );
    }

    return MenuAvailability(isAvailable: true, message: 'Tersedia');
  }

  /// Helper to check availability for a PesananObject (combines menu + options)
  Future<MenuAvailability> checkPesananAvailability(
    PesananObject pesanan,
    List<MenuObject> allMenus,
    List<OptionGroup> allGroups,
  ) async {
    final stableId = pesanan.menuItemId.trim();
    final menu = stableId.isNotEmpty
        ? allMenus.firstWhere(
            (m) => m.id == stableId,
            orElse: () => MenuObject(
                id: '',
                namaMenu: pesanan.namaPesanan,
                harga: pesanan.harga,
                isMakanan: true,
                imagePath: ''),
          )
        : allMenus.where((m) => m.namaMenu == pesanan.namaPesanan).length == 1
            ? allMenus.firstWhere((m) => m.namaMenu == pesanan.namaPesanan)
            : MenuObject(
                id: '',
                namaMenu: pesanan.namaPesanan,
                harga: pesanan.harga,
                isMakanan: true,
                imagePath: '');

    if (menu.id.isEmpty &&
        menu.ingredients.isEmpty &&
        pesanan.selectedOptions.isEmpty) {
      return MenuAvailability(isAvailable: true, message: 'Tersedia');
    }

    final optionIngredients = <MenuIngredient>[];
    for (var selected in pesanan.selectedOptions) {
      final group = allGroups.firstWhere(
        (g) => g.id == selected.groupId,
        orElse: () => OptionGroup(id: '', name: ''),
      );
      if (group.id.isEmpty) continue;
      final optionItem = group.options.firstWhere(
        (o) => o.id == selected.optionId || o.name == selected.optionName,
        orElse: () => OptionItem(id: '', name: ''),
      );
      if (optionItem.id.isEmpty) continue;
      optionIngredients.addAll(optionItem.ingredients);
    }

    return checkOrderAvailability(
        menu, optionIngredients, pesanan.totalQuantity);
  }

  List<StockDelta> stockDeltasFromAggregated(
    Map<String, Map<String, dynamic>> finalAggregated, {
    required bool deduct,
  }) {
    final deltas = <StockDelta>[];
    for (final entry in finalAggregated.entries) {
      final quantity = toInt(entry.value['totalRequired']);
      if (quantity <= 0) continue;
      final id = entry.key.startsWith('__unresolved__') ? '' : entry.key;
      deltas.add(StockDelta(
        inventoryItemId: id,
        inventoryItemName: entry.value['name']?.toString() ?? '',
        stockChange: deduct ? -quantity : quantity,
        stockUsedChange: deduct ? quantity : 0,
        stockAddedChange: deduct ? 0 : quantity,
      ));
    }
    return coalesceStockDeltas(deltas);
  }

  static List<StockDelta> coalesceStockDeltas(List<StockDelta> deltas) {
    final byId = <String, StockDelta>{};
    final unresolved = <StockDelta>[];
    for (final delta in deltas) {
      if (delta.inventoryItemId.trim().isEmpty) {
        unresolved.add(delta);
        continue;
      }
      final existing = byId[delta.inventoryItemId];
      if (existing == null) {
        byId[delta.inventoryItemId] = delta;
      } else {
        byId[delta.inventoryItemId] = StockDelta(
          inventoryItemId: delta.inventoryItemId,
          inventoryItemName: existing.inventoryItemName.isNotEmpty
              ? existing.inventoryItemName
              : delta.inventoryItemName,
          stockChange: existing.stockChange + delta.stockChange,
          stockUsedChange: existing.stockUsedChange + delta.stockUsedChange,
          stockAddedChange: existing.stockAddedChange + delta.stockAddedChange,
        );
      }
    }
    return [...byId.values, ...unresolved];
  }

  /// Reads inventory documents needed by a movement. Callers may perform
  /// additional transaction reads before queuing writes.
  Future<StockTransactionPreparation> prepareStockDeltasInTransaction(
    Transaction transaction,
    List<StockDelta> deltas, {
    String? businessDate,
    String? sourceType,
    String? sourceId,
    List<InventoryAuditFlag> additionalAuditFlags = const [],
  }) async {
    final coalesced = coalesceStockDeltas(deltas);
    final flags = <InventoryAuditFlag>[...additionalAuditFlags];
    final snapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};

    for (final delta in coalesced) {
      final id = delta.inventoryItemId.trim();
      if (id.isEmpty) {
        flags.add(InventoryAuditFlag(
          code: 'missing_inventory_reference',
          message:
              'Bahan stok "${delta.inventoryItemName}" tidak dapat ditemukan.',
          inventoryItemName: delta.inventoryItemName,
          sourceType: sourceType,
          sourceId: sourceId,
          requiredQuantity: delta.stockChange.abs(),
        ));
        continue;
      }
      snapshots[id] = await transaction.get(_inventoryCollection.doc(id));
    }

    final date = businessDate ?? _getTodayDateString();
    for (final delta in coalesced) {
      final id = delta.inventoryItemId.trim();
      if (id.isEmpty) continue;
      final snapshot = snapshots[id]!;
      if (!snapshot.exists) {
        flags.add(InventoryAuditFlag(
          code: 'missing_inventory_reference',
          message: 'Bahan stok "${delta.inventoryItemName}" ($id) tidak ada.',
          inventoryItemId: id,
          inventoryItemName: delta.inventoryItemName,
          sourceType: sourceType,
          sourceId: sourceId,
          requiredQuantity: delta.stockChange.abs(),
        ));
        continue;
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final before = toInt(data['stock']);
      final after = before + delta.stockChange;
      if (delta.stockChange < 0 && after < 0) {
        flags.add(InventoryAuditFlag(
          code: 'stock_shortage',
          message:
              'Stok "${data['name'] ?? delta.inventoryItemName}" menjadi negatif.',
          inventoryItemId: id,
          inventoryItemName:
              data['name']?.toString() ?? delta.inventoryItemName,
          sourceType: sourceType,
          sourceId: sourceId,
          requiredQuantity: -delta.stockChange,
          stockBefore: before,
          stockAfter: after,
          deficit: -after,
        ));
      }
    }

    return StockTransactionPreparation(
      deltas: coalesced,
      snapshots: snapshots,
      auditFlags: List.unmodifiable(flags),
      date: date,
    );
  }

  /// Queues writes for a preparation whose reads have completed.
  void queuePreparedStockDeltas(
    Transaction transaction,
    StockTransactionPreparation preparation,
  ) {
    for (final delta in preparation.deltas) {
      final id = delta.inventoryItemId.trim();
      if (id.isEmpty) continue;
      final snapshot = preparation.snapshots[id];
      if (snapshot == null || !snapshot.exists) continue;
      final data = snapshot.data() ?? <String, dynamic>{};
      transaction.update(_inventoryCollection.doc(id), {
        'stock': data['stock'] == null || data['stock'] is num
            ? FieldValue.increment(delta.stockChange)
            : toInt(data['stock']) + delta.stockChange,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      final logData = <String, dynamic>{
        'date': preparation.date,
        'inventoryItemId': id,
        'inventoryItemName':
            data['name']?.toString() ?? delta.inventoryItemName,
        'isPerishable': data['isPerishable'] == true,
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      if (delta.stockUsedChange != 0) {
        logData['stockUsed'] = FieldValue.increment(delta.stockUsedChange);
      }
      if (delta.stockAddedChange != 0) {
        logData['stockAdded'] = FieldValue.increment(delta.stockAddedChange);
      }
      transaction.set(
        _dailyLogsCollection.doc(canonicalDailyLogId(preparation.date, id)),
        logData,
        SetOptions(merge: true),
      );
    }
  }

  /// Applies stock movements inside the caller's transaction. All inventory
  /// documents are read before any write is queued.
  Future<StockTransactionResult> applyStockDeltasInTransaction(
    Transaction transaction,
    List<StockDelta> deltas, {
    String? businessDate,
    String? sourceType,
    String? sourceId,
    List<InventoryAuditFlag> additionalAuditFlags = const [],
  }) async {
    final preparation = await prepareStockDeltasInTransaction(
      transaction,
      deltas,
      businessDate: businessDate,
      sourceType: sourceType,
      sourceId: sourceId,
      additionalAuditFlags: additionalAuditFlags,
    );
    queuePreparedStockDeltas(transaction, preparation);
    return StockTransactionResult(auditFlags: preparation.auditFlags);
  }

  /// Batch compatibility helper for older callers. It never creates missing
  /// inventory records; transactional callers should use the method above.
  Future<StockTransactionResult> batchDeductAggregatedIngredients(
    Map<String, Map<String, dynamic>> finalAggregated,
    WriteBatch batch,
  ) async {
    if (finalAggregated.isEmpty) return const StockTransactionResult();

    await refreshInventoryCache();
    final today = _getTodayDateString();
    final flags = <InventoryAuditFlag>[];

    for (final delta
        in stockDeltasFromAggregated(finalAggregated, deduct: true)) {
      final inventoryId = delta.inventoryItemId;
      final totalRequired = -delta.stockChange;
      final inventoryItem = _inventoryCache[inventoryId];
      if (inventoryId.isEmpty || inventoryItem == null) {
        flags.add(InventoryAuditFlag(
          code: 'missing_inventory_reference',
          message:
              'Bahan stok "${delta.inventoryItemName}" tidak dapat ditemukan.',
          inventoryItemId: inventoryId.isEmpty ? null : inventoryId,
          inventoryItemName: delta.inventoryItemName,
          requiredQuantity: totalRequired,
        ));
        continue;
      }

      final docRef = _inventoryCollection.doc(inventoryId);
      batch.update(docRef, {
        'stock': FieldValue.increment(-totalRequired),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      batch.set(
          _dailyLogsCollection.doc(canonicalDailyLogId(today, inventoryId)),
          {
            'date': today,
            'inventoryItemId': inventoryId,
            'inventoryItemName': inventoryItem.name,
            'isPerishable': inventoryItem.isPerishable,
            'stockUsed': FieldValue.increment(totalRequired),
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }
    return StockTransactionResult(auditFlags: List.unmodifiable(flags));
  }

  /// Same as batchDeductAggregatedIngredients but for Firestore transactions.
  Future<StockTransactionResult> transactionDeductAggregatedIngredients(
    Map<String, Map<String, dynamic>> finalAggregated,
    Transaction transaction,
  ) async {
    return applyStockDeltasInTransaction(
      transaction,
      stockDeltasFromAggregated(finalAggregated, deduct: true),
    );
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
  Future<void> updateInventoryStock(
    String inventoryId,
    int newStock, {
    int? expectedStock,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final docRef = _inventoryCollection.doc(inventoryId);
      final doc = await transaction.get(docRef);
      if (!doc.exists) throw Exception('Inventory item tidak ditemukan.');

      final data = doc.data() ?? <String, dynamic>{};
      final oldStock = toInt(data['stock']);
      if (expectedStock != null && oldStock != expectedStock) {
        throw Exception(
            'Stok berubah dari $expectedStock menjadi $oldStock. Muat ulang sebelum menetapkan stok.');
      }
      final diff = newStock - oldStock;
      transaction.update(docRef, {
        'stock': newStock,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      if (diff != 0) {
        final date = _getTodayDateString();
        transaction.set(
          _dailyLogsCollection.doc(canonicalDailyLogId(date, inventoryId)),
          {
            'date': date,
            'inventoryItemId': inventoryId,
            'inventoryItemName': data['name']?.toString() ?? '',
            'isPerishable': data['isPerishable'] == true,
            if (diff > 0) 'stockAdded': FieldValue.increment(diff),
            if (diff < 0) 'stockUsed': FieldValue.increment(-diff),
            'reason': 'Manual stock adjustment',
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

    await refreshInventoryCache();
  }

  /// Add new inventory item
  Future<String> addInventoryItem(String name, int stock, String unit,
      {bool isPerishable = false}) async {
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
  Future<void> _logStockUsage(String inventoryItemId, String itemName,
      int quantity, String reason, bool isPerishable) async {
    final today = _getTodayDateString();
    final logId = canonicalDailyLogId(today, inventoryItemId);

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
  Future<void> _logStockAdded(String inventoryItemId, String itemName,
      int quantity, String reason, bool isPerishable) async {
    final today = _getTodayDateString();
    final logId = canonicalDailyLogId(today, inventoryItemId);

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
  Future<void> _logStockWaste(String inventoryItemId, String itemName,
      int quantity, bool isPerishable) async {
    final today = _getTodayDateString();
    final logId = canonicalDailyLogId(today, inventoryItemId);

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

  /// Update inventory metadata and, when supplied, the absolute stock value
  /// in one transaction. This prevents a concurrent sale from being hidden
  /// by an edit dialog that was opened against an older stock value.
  Future<void> updateInventoryItem(
    String id,
    String name,
    String unit,
    bool isPerishable, {
    int? newStock,
    int? expectedStock,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final docRef = _inventoryCollection.doc(id);
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) throw Exception('Inventory item tidak ditemukan.');

      final data = snapshot.data() ?? <String, dynamic>{};
      final oldStock = toInt(data['stock']);
      if (expectedStock != null && oldStock != expectedStock) {
        throw Exception(
            'Stok berubah dari $expectedStock menjadi $oldStock. Muat ulang sebelum menyimpan perubahan.');
      }

      final updates = <String, dynamic>{
        'name': name,
        'unit': unit,
        'isPerishable': isPerishable,
      };
      if (newStock != null) {
        final diff = newStock - oldStock;
        updates['stock'] = newStock;
        updates['lastUpdated'] = FieldValue.serverTimestamp();
        transaction.update(docRef, updates);
        if (diff != 0) {
          final date = _getTodayDateString();
          transaction.set(
            _dailyLogsCollection.doc(canonicalDailyLogId(date, id)),
            {
              'date': date,
              'inventoryItemId': id,
              'inventoryItemName': name,
              'isPerishable': isPerishable,
              if (diff > 0) 'stockAdded': FieldValue.increment(diff),
              if (diff < 0) 'stockUsed': FieldValue.increment(-diff),
              'reason': 'Manual inventory edit',
              'lastUpdated': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      } else {
        transaction.update(docRef, updates);
      }
    });
    await refreshInventoryCache();
  }

  /// Delete inventory item safely
  Future<void> deleteInventoryItem(String id) async {
    bool isUsed = false;
    String usedWhere = '';
    final itemSnapshot = await _inventoryCollection.doc(id).get();
    if (!itemSnapshot.exists) {
      throw Exception('Inventory item tidak ditemukan.');
    }
    final inventoryName = itemSnapshot.data()?['name']?.toString().trim() ?? '';

    bool isReferenceToItem(dynamic rawIngredient) {
      if (rawIngredient is! Map) return false;
      final ingredient = Map<String, dynamic>.from(rawIngredient);
      final linkedId = ingredient['inventoryItemId']?.toString().trim() ?? '';
      final linkedName =
          ingredient['inventoryItemName']?.toString().trim() ?? '';
      return linkedId == id ||
          (linkedId.isEmpty &&
              inventoryName.isNotEmpty &&
              linkedName == inventoryName);
    }

    // 1. Check MenuCollection
    final menuQuery = await _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('MenuCollection')
        .get();

    for (var doc in menuQuery.docs) {
      final data = doc.data();
      final ingredients = data['ingredients'] is List
          ? data['ingredients'] as List<dynamic>
          : const <dynamic>[];
      for (var ing in ingredients) {
        if (isReferenceToItem(ing)) {
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
        final options = data['options'] is List
            ? data['options'] as List<dynamic>
            : const <dynamic>[];
        for (var opt in options) {
          final ingredients = opt is Map && opt['ingredients'] is List
              ? opt['ingredients'] as List<dynamic>
              : const <dynamic>[];
          for (var ing in ingredients) {
            if (isReferenceToItem(ing)) {
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
      throw Exception(
          'Bahan tidak dapat dihapus karena sedang digunakan dalam $usedWhere. Hapus bahan ini dari resep terlebih dahulu.');
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
