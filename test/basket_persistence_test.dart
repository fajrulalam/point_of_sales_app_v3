import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Services/BasketPersistenceService.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Col.testingMode.value = false;
  });

  group('PesananObject serialization', () {
    test('roundtrip serialization with options and notes', () {
      final original = PesananObject(
        menuItemId: 'menu_123',
        namaPesanan: 'Nasi Goreng Spesial',
        harga: 15000,
        dineInQuantity: 2,
        takeAwayQuantity: 1,
        selectedOptions: [
          SelectedOption(
            groupId: 'opt_group_pedas',
            optionId: 'opt_sedang',
            groupName: 'Tingkat Pedas',
            optionName: 'Sedang',
            priceAdjustment: 0,
          ),
          SelectedOption(
            groupId: 'opt_group_telur',
            optionId: 'opt_ceplok',
            groupName: 'Pilihan Telur',
            optionName: 'Telur Ceplok',
            priceAdjustment: 3000,
          ),
        ],
        customerNote: 'Jangan pakai acar',
      );

      final map = original.toMap();
      final restored = PesananObject.fromMap(map);

      expect(restored.menuItemId, equals('menu_123'));
      expect(restored.namaPesanan, equals('Nasi Goreng Spesial'));
      expect(restored.harga, equals(15000));
      expect(restored.dineInQuantity, equals(2));
      expect(restored.takeAwayQuantity, equals(1));
      expect(restored.totalQuantity, equals(3));
      expect(restored.customerNote, equals('Jangan pakai acar'));
      expect(restored.selectedOptions.length, equals(2));
      expect(restored.selectedOptions[0].groupName, equals('Tingkat Pedas'));
      expect(restored.selectedOptions[0].optionName, equals('Sedang'));
      expect(restored.selectedOptions[1].groupName, equals('Pilihan Telur'));
      expect(restored.selectedOptions[1].priceAdjustment, equals(3000));
      expect(restored.effectivePrice, equals(18000));
      expect(restored.subtotal, equals(54000));
      expect(restored.orderKey, equals(original.orderKey));
    });

    test('deserialization with missing or null fields provides safe defaults', () {
      final emptyMap = <String, dynamic>{};
      final restored = PesananObject.fromMap(emptyMap);

      expect(restored.menuItemId, equals(''));
      expect(restored.namaPesanan, equals(''));
      expect(restored.harga, equals(0));
      expect(restored.dineInQuantity, equals(0));
      expect(restored.takeAwayQuantity, equals(0));
      expect(restored.selectedOptions, isEmpty);
      expect(restored.customerNote, isNull);
    });
  });

  group('BasketPersistenceService', () {
    test('saves and loads active draft properly', () async {
      final items = [
        PesananObject(
          menuItemId: 'es_teh',
          namaPesanan: 'Es Teh Manis',
          harga: 5000,
          dineInQuantity: 2,
          takeAwayQuantity: 0,
        ),
      ];

      final draft = BasketDraft(
        items: items,
        isTakeAway: false,
        customerName: 'Ahmad',
        uangYangDiterima: '20.000',
        selectedMemberId: 'member_777',
        savedAt: DateTime.now(),
      );

      await BasketPersistenceService.saveDraft(draft);

      final loaded = await BasketPersistenceService.loadDraft();
      expect(loaded, isNotNull);
      expect(loaded!.items.length, equals(1));
      expect(loaded.items.first.namaPesanan, equals('Es Teh Manis'));
      expect(loaded.items.first.dineInQuantity, equals(2));
      expect(loaded.customerName, equals('Ahmad'));
      expect(loaded.uangYangDiterima, equals('20.000'));
      expect(loaded.selectedMemberId, equals('member_777'));
      expect(loaded.isTakeAway, isFalse);
    });

    test('clears draft when cart is empty or clearDraft() called', () async {
      final items = [
        PesananObject(
          menuItemId: 'item_1',
          namaPesanan: 'Mie Ayam',
          harga: 12000,
          dineInQuantity: 1,
        ),
      ];

      final draft = BasketDraft(
        items: items,
        savedAt: DateTime.now(),
      );

      await BasketPersistenceService.saveDraft(draft);
      var loaded = await BasketPersistenceService.loadDraft();
      expect(loaded, isNotNull);

      await BasketPersistenceService.clearDraft();
      loaded = await BasketPersistenceService.loadDraft();
      expect(loaded, isNull);
    });

    test('discards expired drafts older than maxDraftAgeHours (12 hours)', () async {
      final items = [
        PesananObject(
          menuItemId: 'item_yesterday',
          namaPesanan: 'Kopi Susu Kemarin',
          harga: 10000,
          dineInQuantity: 1,
        ),
      ];

      // Draft saved 14 hours ago
      final expiredDate = DateTime.now().subtract(const Duration(hours: 14));
      final expiredDraft = BasketDraft(
        items: items,
        customerName: 'Old Customer',
        savedAt: expiredDate,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pos_basket_draft', jsonEncode(expiredDraft.toMap()));

      final loaded = await BasketPersistenceService.loadDraft();
      expect(loaded, isNull);

      // Verify that the expired entry was pruned from storage
      expect(prefs.containsKey('pos_basket_draft'), isFalse);
    });

    test('keeps fresh drafts younger than 12 hours', () async {
      final items = [
        PesananObject(
          menuItemId: 'item_recent',
          namaPesanan: 'Kopi Susu 20 Menit Lalu',
          harga: 10000,
          dineInQuantity: 1,
        ),
      ];

      final recentDate = DateTime.now().subtract(const Duration(minutes: 20));
      final recentDraft = BasketDraft(
        items: items,
        customerName: 'Recent Customer',
        savedAt: recentDate,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pos_basket_draft', jsonEncode(recentDraft.toMap()));

      final loaded = await BasketPersistenceService.loadDraft();
      expect(loaded, isNotNull);
      expect(loaded!.customerName, equals('Recent Customer'));
    });
  });

  group('Online order take-away conversion', () {
    test('converts all dine-in items to take-away and zeroes dineInQuantity', () {
      final items = [
        PesananObject(
          menuItemId: 'nasi_goreng',
          namaPesanan: 'Nasi Goreng',
          harga: 15000,
          dineInQuantity: 3,
          takeAwayQuantity: 1,
        ),
        PesananObject(
          menuItemId: 'es_teh',
          namaPesanan: 'Es Teh',
          harga: 5000,
          dineInQuantity: 2,
          takeAwayQuantity: 0,
        ),
      ];

      // Simulate Online order confirmation conversion
      for (final item in items) {
        item.takeAwayQuantity = item.totalQuantity;
        item.dineInQuantity = 0;
      }

      expect(items[0].dineInQuantity, equals(0));
      expect(items[0].takeAwayQuantity, equals(4));
      expect(items[0].totalQuantity, equals(4));

      expect(items[1].dineInQuantity, equals(0));
      expect(items[1].takeAwayQuantity, equals(2));
      expect(items[1].totalQuantity, equals(2));

      // Verify persistence correctly saves them as takeaway
      final draft = BasketDraft(
        items: items,
        customerName: 'GoFood',
        isTakeAway: true,
        savedAt: DateTime.now(),
      );

      final map = draft.toMap();
      final restored = BasketDraft.fromMap(map);

      expect(restored.customerName, equals('GoFood'));
      expect(restored.isTakeAway, isTrue);
      expect(restored.items[0].dineInQuantity, equals(0));
      expect(restored.items[0].takeAwayQuantity, equals(4));
      expect(restored.items[1].dineInQuantity, equals(0));
      expect(restored.items[1].takeAwayQuantity, equals(2));
    });
  });
}
