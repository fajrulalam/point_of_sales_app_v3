import 'package:flutter_test/flutter_test.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/UserMessageService.dart';

void main() {
  test('aggregates shared menu and option ingredients across a quantity', () {
    final result = StockRequirementCalculator.aggregateIngredients(
      [
        MenuIngredient(
          inventoryItemId: 'syrup',
          inventoryItemName: 'Syrup',
          quantityNeeded: 2,
        ),
        MenuIngredient(
          inventoryItemId: 'syrup',
          inventoryItemName: 'Syrup',
          quantityNeeded: 1,
        ),
      ],
      [
        MenuIngredient(
          inventoryItemId: 'syrup',
          inventoryItemName: 'Syrup',
          quantityNeeded: 1,
        ),
      ],
      3,
    );

    expect(result['syrup']!['quantityNeeded'], 4);
    expect(result['syrup']!['totalRequired'], 12);
  });

  test('coalesces duplicate stock movements into one net delta', () {
    final result = InventoryService.coalesceStockDeltas([
      const StockDelta(
        inventoryItemId: 'flour',
        inventoryItemName: 'Flour',
        stockChange: -4,
        stockUsedChange: 4,
      ),
      const StockDelta(
        inventoryItemId: 'flour',
        inventoryItemName: 'Flour',
        stockChange: -3,
        stockUsedChange: 3,
      ),
    ]);

    expect(result, hasLength(1));
    expect(result.single.stockChange, -7);
    expect(result.single.stockUsedChange, 7);
  });

  test('classifies restored edit stock as added stock', () {
    final restored = InventoryService.coalesceStockDeltas([
      const StockDelta(
        inventoryItemId: 'sauce',
        inventoryItemName: 'Sauce',
        stockChange: 4,
        stockAddedChange: 4,
      ),
      const StockDelta(
        inventoryItemId: 'sauce',
        inventoryItemName: 'Sauce',
        stockChange: -1,
        stockUsedChange: 1,
      ),
    ]).single;

    expect(restored.stockChange, 3);
    expect(restored.stockAddedChange, 4);
    expect(restored.stockUsedChange, 1);
  });

  test('does not invent stock usage for non-positive ingredient quantities',
      () {
    final result = StockRequirementCalculator.aggregateIngredients(
      [
        MenuIngredient(
          inventoryItemId: 'valid',
          inventoryItemName: 'Valid ingredient',
          quantityNeeded: 2,
        ),
        MenuIngredient(
          inventoryItemId: 'zero',
          inventoryItemName: 'Zero ingredient',
          quantityNeeded: 0,
        ),
        MenuIngredient(
          inventoryItemId: 'negative',
          inventoryItemName: 'Negative ingredient',
          quantityNeeded: -1,
        ),
      ],
      const [],
      4,
    );

    expect(result, hasLength(1));
    expect(result['valid']!['totalRequired'], 8);
  });

  test('keeps unresolved components visible as audit-ready deltas', () {
    final result = InventoryService.coalesceStockDeltas([
      const StockDelta(
        inventoryItemId: '',
        inventoryItemName: 'Legacy ingredient',
        stockChange: -2,
        stockUsedChange: 2,
      ),
    ]);

    expect(result.single.inventoryItemId, isEmpty);
    expect(result.single.inventoryItemName, 'Legacy ingredient');
  });

  test('detects only active legacy ingredient references', () {
    final modernMenu = MenuObject(
      id: 'menu-modern',
      namaMenu: 'Modern menu',
      harga: 10000,
      isMakanan: true,
      imagePath: '',
      ingredients: [
        MenuIngredient(
          inventoryItemId: 'inventory-1',
          inventoryItemName: 'Ingredient 1',
          quantityNeeded: 1,
        ),
      ],
    );
    final legacyOption = OptionItem(
      id: 'option-legacy',
      name: 'Legacy option',
      ingredients: [
        MenuIngredient(
          inventoryItemId: '',
          inventoryItemName: 'Legacy ingredient',
          quantityNeeded: 1,
        ),
      ],
    );
    final order = PesananObject(
      menuItemId: modernMenu.id,
      namaPesanan: modernMenu.namaMenu,
      harga: modernMenu.harga,
      dineInQuantity: 1,
      selectedOptions: [
        SelectedOption(
          groupId: 'group-1',
          optionId: legacyOption.id,
          groupName: 'Options',
          optionName: legacyOption.name,
        ),
      ],
    );

    expect(
      InventoryService.orderHasLegacyInventoryReferences(
        [order],
        menuLookup: {'__id__${modernMenu.id}': modernMenu},
        optionLookup: {
          'group-1': {legacyOption.id: legacyOption},
        },
      ),
      isTrue,
    );

    final modernOrder = PesananObject(
      menuItemId: modernMenu.id,
      namaPesanan: modernMenu.namaMenu,
      harga: modernMenu.harga,
      dineInQuantity: 1,
    );
    expect(
      InventoryService.orderHasLegacyInventoryReferences(
        [modernOrder],
        menuLookup: {'__id__${modernMenu.id}': modernMenu},
        optionLookup: const {},
      ),
      isFalse,
    );
  });

  test('uses the canonical daily log key', () {
    expect(
      InventoryService.canonicalDailyLogId('2026-08-07', 'inventory-123'),
      '2026-08-07_inventory-123',
    );
  });

  test('operation results distinguish an applied operation from a replay', () {
    final applied = InventoryOperationResult.applied(
      flags: const [
        InventoryAuditFlag(
          code: 'stock_shortage',
          message: 'shortage',
        ),
      ],
    );
    const replay = InventoryOperationResult.alreadyApplied();

    expect(applied.wasApplied, isTrue);
    expect(applied.auditFlags, hasLength(1));
    expect(replay.wasAlreadyApplied, isTrue);
  });

  test('translates inventory warnings into Indonesian', () {
    expect(
      UserMessageService.fromText(
        'Ingredient "Risol" not found in inventory',
      ),
      'Bahan "Risol" tidak ditemukan di stok',
    );
  });

  test('does not expose technical Firebase error text to cashier', () {
    expect(
      UserMessageService.fromText('Chain validation failed'),
      contains('Koneksi aman ke server gagal'),
    );
  });
}
