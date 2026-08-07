import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Services/UserMessageService.dart';

enum InventoryAuditSeverity { error, warning, info }

class InventoryAuditFinding {
  final InventoryAuditSeverity severity;
  final String code;
  final String message;
  final String? sourceType;
  final String? sourceId;

  const InventoryAuditFinding({
    required this.severity,
    required this.code,
    required this.message,
    this.sourceType,
    this.sourceId,
  });
}

class InventoryAuditReport {
  final DateTime generatedAt;
  final List<InventoryAuditFinding> findings;

  const InventoryAuditReport({
    required this.generatedAt,
    required this.findings,
  });

  int get errors => findings
      .where((finding) => finding.severity == InventoryAuditSeverity.error)
      .length;

  int get warnings => findings
      .where((finding) => finding.severity == InventoryAuditSeverity.warning)
      .length;
}

/// Read-only integrity checks for the inventory graph and persisted audit
/// flags. It deliberately does not repair or rewrite existing documents.
class InventoryAuditService {
  static final InventoryAuditService _instance =
      InventoryAuditService._internal();
  factory InventoryAuditService() => _instance;
  InventoryAuditService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String canteenId = 'canteen375';

  CollectionReference<Map<String, dynamic>> _canteenCollection(String name) {
    return _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection(name);
  }

  static int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static String _asString(dynamic value) => value?.toString() ?? '';

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<InventoryAuditReport> runAudit() async {
    final findings = <InventoryAuditFinding>[];

    void add(
      InventoryAuditSeverity severity,
      String code,
      String message, {
      String? sourceType,
      String? sourceId,
    }) {
      findings.add(InventoryAuditFinding(
        severity: severity,
        code: code,
        message: message,
        sourceType: sourceType,
        sourceId: sourceId,
      ));
    }

    final inventorySnapshot = await _canteenCollection('Inventory').get();
    final inventoryById = <String, Map<String, dynamic>>{
      for (final doc in inventorySnapshot.docs) doc.id: doc.data(),
    };
    final inventoryIdsByName = <String, List<String>>{};
    for (final doc in inventorySnapshot.docs) {
      final name = _asString(doc.data()['name']).trim();
      if (name.isNotEmpty) {
        inventoryIdsByName.putIfAbsent(name, () => []).add(doc.id);
      }
      final stock = _asInt(doc.data()['stock']);
      if (stock < 0) {
        add(
          InventoryAuditSeverity.warning,
          'negative_stock',
          '${doc.data()['name'] ?? doc.id} memiliki stok $stock.',
          sourceType: 'inventory',
          sourceId: doc.id,
        );
      }
    }
    final uniqueInventoryNames = <String, String>{
      for (final entry in inventoryIdsByName.entries)
        if (entry.value.length == 1) entry.key: entry.value.single,
    };

    String? resolveInventory(String? id, String name) {
      final stableId = id?.trim() ?? '';
      if (stableId.isNotEmpty) {
        return inventoryById.containsKey(stableId) ? stableId : null;
      }
      return uniqueInventoryNames[name.trim()];
    }

    final menuSnapshot = await _canteenCollection('MenuCollection').get();
    final menuIds = menuSnapshot.docs.map((doc) => doc.id).toSet();
    final menuIdsByName = <String, List<String>>{};
    for (final doc in menuSnapshot.docs) {
      final data = doc.data();
      final menuName = _asString(data['namaMenu']);
      if (menuName.trim().isNotEmpty) {
        menuIdsByName.putIfAbsent(menuName.trim(), () => []).add(doc.id);
      }
      for (final ingredient in _mapList(data['ingredients'])) {
        final id = _asString(ingredient['inventoryItemId']);
        final name = _asString(ingredient['inventoryItemName']);
        if (resolveInventory(id, name) == null) {
          add(
            InventoryAuditSeverity.error,
            'missing_menu_inventory_reference',
            'Menu "$menuName" merujuk ke bahan stok "$name" ($id) yang tidak ditemukan.',
            sourceType: 'menu',
            sourceId: doc.id,
          );
        } else if (id.isEmpty || !inventoryById.containsKey(id)) {
          add(
            InventoryAuditSeverity.info,
            'legacy_menu_inventory_reference',
            'Menu "$menuName" menemukan bahan "$name" melalui nama lama.',
            sourceType: 'menu',
            sourceId: doc.id,
          );
        }
        if (_asInt(ingredient['quantityNeeded']) <= 0) {
          add(
            InventoryAuditSeverity.warning,
            'invalid_menu_ingredient_quantity',
            'Menu "$menuName" memiliki jumlah bahan "$name" yang tidak valid.',
            sourceType: 'menu',
            sourceId: doc.id,
          );
        }
      }
    }
    final menuNames = <String, String>{
      for (final entry in menuIdsByName.entries)
        if (entry.value.length == 1) entry.key: entry.value.single,
    };

    final optionSnapshot = await _canteenCollection('OptionGroups').get();
    final optionGroupIds = optionSnapshot.docs.map((doc) => doc.id).toSet();
    final optionIds = <String>{};
    final optionGroupNames = <String, List<String>>{};
    final optionNamesByGroup = <String, Map<String, int>>{};
    for (final groupDoc in optionSnapshot.docs) {
      final groupData = groupDoc.data();
      final groupName = _asString(groupData['name']);
      if (groupName.trim().isNotEmpty) {
        optionGroupNames
            .putIfAbsent(groupName.trim(), () => [])
            .add(groupDoc.id);
      }
      final linkedMenuItems = groupData['linkedMenuItems'] is List
          ? groupData['linkedMenuItems'] as List
          : const [];
      for (final menuId in linkedMenuItems) {
        final linkedId = _asString(menuId);
        if (linkedId.isNotEmpty && !menuIds.contains(linkedId)) {
          add(
            InventoryAuditSeverity.error,
            'missing_option_menu_reference',
            'Grup opsi "$groupName" terhubung ke menu $linkedId yang tidak ditemukan.',
            sourceType: 'option_group',
            sourceId: groupDoc.id,
          );
        }
      }
      for (final option in _mapList(groupData['options'])) {
        final optionId = _asString(option['id']);
        if (optionId.isNotEmpty) optionIds.add('${groupDoc.id}:$optionId');
        final optionName = _asString(option['name']);
        final names = optionNamesByGroup.putIfAbsent(groupDoc.id, () => {});
        final normalizedOptionName = optionName.trim();
        if (normalizedOptionName.isNotEmpty) {
          names[normalizedOptionName] = (names[normalizedOptionName] ?? 0) + 1;
        }
        for (final ingredient in _mapList(option['ingredients'])) {
          final id = _asString(ingredient['inventoryItemId']);
          final name = _asString(ingredient['inventoryItemName']);
          if (resolveInventory(id, name) == null) {
            add(
              InventoryAuditSeverity.error,
              'missing_option_inventory_reference',
              'Opsi "$optionName" dalam "$groupName" merujuk ke bahan stok "$name" ($id) yang tidak ditemukan.',
              sourceType: 'option_group',
              sourceId: groupDoc.id,
            );
          } else if (id.isEmpty || !inventoryById.containsKey(id)) {
            add(
              InventoryAuditSeverity.info,
              'legacy_option_inventory_reference',
              'Opsi "$optionName" menemukan bahan "$name" melalui nama lama.',
              sourceType: 'option_group',
              sourceId: groupDoc.id,
            );
          }
          if (_asInt(ingredient['quantityNeeded']) <= 0) {
            add(
              InventoryAuditSeverity.warning,
              'invalid_option_ingredient_quantity',
              'Opsi "$optionName" dalam "$groupName" memiliki jumlah bahan "$name" yang tidak valid.',
              sourceType: 'option_group',
              sourceId: groupDoc.id,
            );
          }
        }
      }
    }

    final supplierSnapshot = await _canteenCollection('suppliers').get();
    final supplierIds = supplierSnapshot.docs.map((doc) => doc.id).toSet();
    for (final supplierDoc in supplierSnapshot.docs) {
      final supplierName = _asString(supplierDoc.data()['name']);
      for (final item in _mapList(supplierDoc.data()['items'])) {
        final itemName = _asString(item['name']);
        final itemId = _asString(item['inventoryItemId']);
        if (resolveInventory(itemId, itemName) == null) {
          add(
            InventoryAuditSeverity.error,
            'missing_supplier_inventory_reference',
            'Barang "$itemName" dari supplier "$supplierName" tidak memiliki tautan ke stok.',
            sourceType: 'supplier',
            sourceId: supplierDoc.id,
          );
        } else if (itemId.isEmpty || !inventoryById.containsKey(itemId)) {
          add(
            InventoryAuditSeverity.info,
            'legacy_supplier_inventory_reference',
            'Barang "$itemName" dari supplier "$supplierName" menggunakan pencocokan nama lama.',
            sourceType: 'supplier',
            sourceId: supplierDoc.id,
          );
        }
      }
    }

    final shoppingSnapshot = await _canteenCollection('shoppingOrders').get();
    for (final orderDoc in shoppingSnapshot.docs) {
      final data = orderDoc.data();
      final supplierId = _asString(data['supplierId']);
      if (supplierId.isEmpty || !supplierIds.contains(supplierId)) {
        add(
          InventoryAuditSeverity.error,
          'missing_shopping_supplier_reference',
          'Pesanan belanja ${orderDoc.id} merujuk ke supplier ${supplierId.isEmpty ? '(ID kosong)' : supplierId} yang tidak ditemukan.',
          sourceType: 'shopping_order',
          sourceId: orderDoc.id,
        );
      }
      for (final item in _mapList(data['items'])) {
        final itemName = _asString(item['name']);
        final itemId = _asString(item['inventoryItemId']);
        if (resolveInventory(itemId, itemName) == null &&
            _asInt(item['quantity']) > 0) {
          add(
            InventoryAuditSeverity.error,
            'unresolved_shopping_inventory_link',
            'Barang "$itemName" pada pesanan belanja ${orderDoc.id} tidak dapat ditemukan.',
            sourceType: 'shopping_order',
            sourceId: orderDoc.id,
          );
        }
        if (_asInt(item['quantity']) < 0) {
          add(
            InventoryAuditSeverity.warning,
            'invalid_shopping_quantity',
            'Pesanan belanja ${orderDoc.id} memiliki jumlah negatif untuk "$itemName".',
            sourceType: 'shopping_order',
            sourceId: orderDoc.id,
          );
        }
      }
      _addStoredFlags(
          add, data['inventoryAuditFlags'], 'shopping_order', orderDoc.id);
    }

    final statusSnapshot =
        await _firestore.collection(Col.name('Status')).get();
    final statusById = <String, Map<String, dynamic>>{
      for (final doc in statusSnapshot.docs) doc.id: doc.data(),
    };
    for (final statusDoc in statusSnapshot.docs) {
      final data = statusDoc.data();
      for (final item in _mapList(data['orderItems'])) {
        final menuId = _asString(item['menuItemId']);
        final menuName = _asString(item['namaPesanan']);
        final normalizedMenuName = menuName.trim();
        if (menuId.isNotEmpty && !menuIds.contains(menuId)) {
          add(
            InventoryAuditSeverity.error,
            'missing_sale_menu_reference',
            'Penjualan ${statusDoc.id} merujuk ke ID menu $menuId (nama "$menuName") yang tidak ditemukan.',
            sourceType: 'sale',
            sourceId: statusDoc.id,
          );
        } else if (menuId.isEmpty &&
            !menuNames.containsKey(normalizedMenuName)) {
          add(
            InventoryAuditSeverity.error,
            'missing_sale_menu_reference',
            'Penjualan ${statusDoc.id} merujuk ke menu "$menuName" ($menuId) yang tidak ditemukan.',
            sourceType: 'sale',
            sourceId: statusDoc.id,
          );
        } else if (menuId.isEmpty &&
            menuNames.containsKey(normalizedMenuName)) {
          add(
            InventoryAuditSeverity.info,
            'legacy_sale_menu_reference',
            'Penjualan ${statusDoc.id} menemukan menu "$menuName" tanpa ID menu tetap.',
            sourceType: 'sale',
            sourceId: statusDoc.id,
          );
        }
        for (final option in _mapList(item['selectedOptions'])) {
          final groupId = _asString(option['groupId']);
          final optionId = _asString(option['optionId']);
          final groupName = _asString(option['groupName']).trim();
          final groupByName = optionGroupNames[groupName];
          final resolvedGroupId = groupId.isNotEmpty
              ? groupId
              : (groupByName?.length == 1 ? groupByName!.single : null);
          if (groupId.isNotEmpty && !optionGroupIds.contains(groupId)) {
            add(
              InventoryAuditSeverity.error,
              'missing_sale_option_group_reference',
              'Penjualan ${statusDoc.id} merujuk ke grup opsi $groupId yang tidak ditemukan.',
              sourceType: 'sale',
              sourceId: statusDoc.id,
            );
          } else if (groupId.isEmpty && resolvedGroupId == null) {
            add(
              InventoryAuditSeverity.error,
              'missing_sale_option_group_reference',
              'Penjualan ${statusDoc.id} memiliki grup opsi "$groupName" yang tidak dapat ditemukan.',
              sourceType: 'sale',
              sourceId: statusDoc.id,
            );
          } else if (groupId.isNotEmpty &&
              optionId.isNotEmpty &&
              !optionIds.contains('$groupId:$optionId')) {
            add(
              InventoryAuditSeverity.error,
              'missing_sale_option_reference',
              'Penjualan ${statusDoc.id} merujuk ke opsi $optionId dalam grup $groupId yang tidak ditemukan.',
              sourceType: 'sale',
              sourceId: statusDoc.id,
            );
          } else if (optionId.isEmpty &&
              (optionNamesByGroup[resolvedGroupId]
                          ?[_asString(option['optionName']).trim()] ??
                      0) !=
                  1) {
            add(
              InventoryAuditSeverity.error,
              'missing_sale_option_reference',
              'Penjualan ${statusDoc.id} memiliki opsi "${_asString(option['optionName'])}" yang tidak dapat ditemukan.',
              sourceType: 'sale',
              sourceId: statusDoc.id,
            );
          } else if (groupId.isEmpty || optionId.isEmpty) {
            add(
              InventoryAuditSeverity.info,
              'legacy_sale_option_reference',
              'Penjualan ${statusDoc.id} menemukan opsi berdasarkan nama, bukan ID tetap.',
              sourceType: 'sale',
              sourceId: statusDoc.id,
            );
          }
        }
      }
      _addStoredFlags(add, data['inventoryAuditFlags'], 'sale', statusDoc.id);
    }

    final operationSnapshot = await _canteenCollection('Orders').get();
    for (final operationDoc in operationSnapshot.docs) {
      _addStoredFlags(
          add, operationDoc.data()['auditFlags'], 'operation', operationDoc.id);
    }

    final openBillLocksSnapshot =
        await _canteenCollection('OpenBillLocks').get();
    for (final lockDoc in openBillLocksSnapshot.docs) {
      final statusDocId = _asString(lockDoc.data()['statusDocId']);
      if (statusDocId.isEmpty || !statusById.containsKey(statusDocId)) {
        add(
          InventoryAuditSeverity.warning,
          'missing_open_bill_lock_reference',
          'Kunci tagihan terbuka ${lockDoc.id} menunjuk ke status $statusDocId yang tidak ditemukan.',
          sourceType: 'open_bill_lock',
          sourceId: lockDoc.id,
        );
      }
    }

    final dailyLogsSnapshot = await _canteenCollection('DailyStockLogs').get();
    final canonicalPattern = RegExp(r'^\d{4}-\d{2}-\d{2}_.+$');
    for (final logDoc in dailyLogsSnapshot.docs) {
      final data = logDoc.data();
      final date = _asString(data['date']);
      final itemId = _asString(data['inventoryItemId']);
      final expectedId = itemId.isEmpty
          ? ''
          : InventoryService.canonicalDailyLogId(date, itemId);
      if (itemId.isEmpty || !inventoryById.containsKey(itemId)) {
        add(
          InventoryAuditSeverity.error,
          'daily_log_missing_inventory_reference',
          'Log stok harian ${logDoc.id} tidak memiliki referensi bahan stok yang valid.',
          sourceType: 'daily_stock_log',
          sourceId: logDoc.id,
        );
      }
      if (date.isEmpty ||
          !canonicalPattern.hasMatch(logDoc.id) ||
          (expectedId.isNotEmpty && logDoc.id != expectedId)) {
        add(
          InventoryAuditSeverity.warning,
          'inconsistent_daily_stock_log_id',
          'Kunci log stok harian ${logDoc.id} tidak mengikuti format YYYY-MM-DD_inventoryItemId.',
          sourceType: 'daily_stock_log',
          sourceId: logDoc.id,
        );
      }
    }

    return InventoryAuditReport(
      generatedAt: DateTime.now(),
      findings: List.unmodifiable(findings),
    );
  }

  static void _addStoredFlags(
    void Function(
      InventoryAuditSeverity,
      String,
      String, {
      String? sourceType,
      String? sourceId,
    }) add,
    dynamic rawFlags,
    String sourceType,
    String sourceId,
  ) {
    if (rawFlags is! List) return;
    for (final rawFlag in rawFlags) {
      if (rawFlag is! Map) continue;
      final flag =
          InventoryAuditFlag.fromMap(Map<String, dynamic>.from(rawFlag));
      const sourceLabels = {
        'shopping_order': 'Pesanan belanja',
        'sale': 'Penjualan',
        'operation': 'Operasi',
      };
      final sourceLabel = sourceLabels[sourceType] ?? 'Data';
      add(
        InventoryAuditSeverity.warning,
        'stored_${flag.code}',
        '$sourceLabel $sourceId: ${UserMessageService.fromText(flag.message, fallback: 'Terdapat masalah pada data stok.')}',
        sourceType: sourceType,
        sourceId: sourceId,
      );
    }
  }
}
