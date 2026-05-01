import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Services/LoaderWidget.dart';

class EditOrderService {
  static Future<void> processEditOrder({
    required BuildContext context,
    required String statusDocId,
    required Map<String, dynamic> originalStatusData,
    required List<PesananObject> newPesananList,
    required int newTotalHarga,
    required int newBiayaBungkus,
    required Map<String, MenuObject> menuMap,
    required Map<String, Map<String, OptionItem>> optionGroupLookup,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function() printReceipt,
  }) async {
    final fs = FirebaseFirestore.instance;
    final batch = fs.batch();

    if (context.mounted) {
      LoaderWidget.showLoaderDialog(context, message: "Menyimpan perubahan...");
    }

    try {
      // 1. Revert Old Revenue
      final oldTotal = originalStatusData['total'] as int? ?? 0;
      final oldSubTotal = originalStatusData['subTotal'] as int? ?? 0;
      final oldTakeAwayFee = originalStatusData['takeAwayFee'] as int? ?? 0;

      final revertMap = <String, dynamic>{
        'total': FieldValue.increment(-oldTotal),
        'subTotal': FieldValue.increment(-oldSubTotal),
        'takeAwayFee': FieldValue.increment(-oldTakeAwayFee),
      };

      // Revert Payment Method
      final bool isSplitPayment = originalStatusData['isSplitPayment'] == true;
      if (isSplitPayment) {
        final splitDetails = originalStatusData['splitDetails'] ?? {};
        final cash = splitDetails['cashAmount'] as int? ?? 0;
        final qris = splitDetails['qrisAmount'] as int? ?? 0;
        if (cash > 0) revertMap['Cash'] = FieldValue.increment(-cash);
        if (qris > 0) revertMap['QRIS'] = FieldValue.increment(-qris);
      } else {
        final paymentMethod = originalStatusData['paymentMethod'];
        if (paymentMethod != null && paymentMethod != 'Program') {
          revertMap[paymentMethod] = FieldValue.increment(-oldTotal);
        } else if (paymentMethod == 'Program') {
          final programExtraPaymentMethod = originalStatusData['programExtraPaymentMethod'];
          if (programExtraPaymentMethod != null) {
            final oldProgramNominal = originalStatusData['programNominal'] as int? ?? 0;
            final remaining = oldTotal - oldProgramNominal;
            if (remaining > 0) {
              if (programExtraPaymentMethod == 'Cash + QRIS') {
                final split = originalStatusData['programExtraSplitDetails'] ?? {};
                final cash = split['cashAmount'] as int? ?? 0;
                final qris = split['qrisAmount'] as int? ?? 0;
                if (cash > 0) revertMap['Cash'] = FieldValue.increment(-cash);
                if (qris > 0) revertMap['QRIS'] = FieldValue.increment(-qris);
              } else {
                revertMap[programExtraPaymentMethod] = FieldValue.increment(-remaining);
              }
            }
          }
        }
      }

      // Revert old item quantities from DailyTransaction
      final oldOrderItemsRaw = originalStatusData['orderItems'] as List<dynamic>? ?? [];
      final oldPesananList = <PesananObject>[];

      for (var item in oldOrderItemsRaw) {
        final name = item['namaPesanan'] ?? '';
        final qty = (item['dineInQuantity'] as int? ?? 0) + (item['takeAwayQuantity'] as int? ?? 0);
        if (qty > 0 && name.isNotEmpty) {
          revertMap[name] = FieldValue.increment(-qty);
        }

        // Parse options to revert stock
        final selectedOptsRaw = item['selectedOptions'] as List<dynamic>? ?? [];
        final selectedOpts = selectedOptsRaw.map((e) => SelectedOption.fromMap(e as Map<String, dynamic>)).toList();
        oldPesananList.add(PesananObject(
          namaPesanan: name,
          harga: item['harga'] ?? 0,
          dineInQuantity: item['dineInQuantity'] ?? 0,
          takeAwayQuantity: item['takeAwayQuantity'] ?? 0,
          selectedOptions: selectedOpts,
        ));
      }

      // Apply revert to Daily/Monthly/Yearly (if they are for today)
      // Note: If the order was from a previous day, we should use its original date.
      // Assuming EditOrderScreen only shows today's orders.
      final oldWaktuPesan = originalStatusData['waktuPesan'] as Timestamp?;
      DateTime orderDate = oldWaktuPesan?.toDate() ?? DateTime.now();
      String formattedDate = DateFormat('yyyy-MM-dd').format(orderDate);
      String orderMonth = DateFormat('yyyy-MM').format(orderDate);
      String orderYear = DateFormat('yyyy').format(orderDate);

      final docDaily = fs.collection(Col.name('DailyTransaction')).doc(formattedDate);
      batch.set(docDaily, revertMap, SetOptions(merge: true));

      final docMonthly = fs.collection(Col.name('MonthlyTransaction')).doc(orderMonth);
      batch.set(docMonthly, revertMap, SetOptions(merge: true));

      final docYearly = fs.collection(Col.name('YearlyTransaction')).doc(orderYear);
      batch.set(docYearly, revertMap, SetOptions(merge: true));

      // Revert Old Stock
      await _appendRevertIngredientsToBatch(oldPesananList, menuMap, optionGroupLookup, batch: batch);

      // 2. Apply New Revenue
      final newSubTotal = newTotalHarga - newBiayaBungkus;
      final applyMap = <String, dynamic>{
        'total': FieldValue.increment(newTotalHarga),
        'subTotal': FieldValue.increment(newSubTotal),
        'takeAwayFee': FieldValue.increment(newBiayaBungkus),
      };

      // For edits, we will just use Cash as default or preserve original payment method if possible.
      // Let's preserve original if total didn't change much, or default to Cash.
      // Better: Use the old payment method.
      if (isSplitPayment) {
        // If it was split, just dump the new total difference into Cash
        final splitDetails = originalStatusData['splitDetails'] ?? {};
        final oldCash = splitDetails['cashAmount'] as int? ?? 0;
        final oldQris = splitDetails['qrisAmount'] as int? ?? 0;
        final newCash = newTotalHarga > oldQris ? newTotalHarga - oldQris : 0;
        applyMap['Cash'] = FieldValue.increment(newCash);
        applyMap['QRIS'] = FieldValue.increment(newTotalHarga > oldQris ? oldQris : newTotalHarga);
      } else {
        final paymentMethod = originalStatusData['paymentMethod'] ?? 'Cash/QRIS';
        if (paymentMethod != 'Program') {
          applyMap[paymentMethod] = FieldValue.increment(newTotalHarga);
        } else {
          // If it was program, the program nominal is fixed. Rest to extra payment.
          final oldProgramNominal = originalStatusData['programNominal'] as int? ?? 0;
          final remaining = newTotalHarga - oldProgramNominal;
          if (remaining > 0) {
            final programExtraPaymentMethod = originalStatusData['programExtraPaymentMethod'] ?? 'Cash/QRIS';
            if (programExtraPaymentMethod == 'Cash + QRIS') {
              applyMap['Cash'] = FieldValue.increment(remaining);
            } else {
              applyMap[programExtraPaymentMethod] = FieldValue.increment(remaining);
            }
          }
        }
      }

      for (var pesanan in newPesananList) {
        applyMap[pesanan.namaPesanan] = FieldValue.increment(pesanan.totalQuantity);
      }

      batch.set(docDaily, applyMap, SetOptions(merge: true));
      batch.set(docMonthly, applyMap, SetOptions(merge: true));
      batch.set(docYearly, applyMap, SetOptions(merge: true));

      // Apply New Stock
      await _appendDeductIngredientsToBatch(newPesananList, menuMap, optionGroupLookup, batch: batch);

      // 3. Overwrite Status Document
      final newOrderItems = newPesananList.map((order) {
        final menu = menuMap[order.namaPesanan];
        return {
          'namaPesanan': order.namaPesanan,
          'harga': order.harga,
          'dineInQuantity': order.dineInQuantity,
          'takeAwayQuantity': order.takeAwayQuantity,
          'selectedOptions': order.selectedOptions.map((o) => o.toMap()).toList(),
          'isMakanan': menu?.isMakanan ?? false,
          'customerNote': order.customerNote ?? '',
          'status': '',
          'dineInPreparedQuantity': 0,
          'takeAwayPreparedQuantity': 0,
        };
      }).toList();

      final statusRef = fs.collection(Col.name('Status')).doc(statusDocId);
      final newStatusMap = {
        ...originalStatusData,
        'orderItems': newOrderItems,
        'total': newTotalHarga,
        'subTotal': newSubTotal,
        'takeAwayFee': newBiayaBungkus,
        'lastEditedAt': FieldValue.serverTimestamp(),
      };
      
      // Update Split Payment details if necessary
      if (isSplitPayment) {
        final splitDetails = originalStatusData['splitDetails'] ?? {};
        final oldQris = splitDetails['qrisAmount'] as int? ?? 0;
        final newCash = newTotalHarga > oldQris ? newTotalHarga - oldQris : 0;
        newStatusMap['splitDetails'] = {
          'cashAmount': newCash,
          'qrisAmount': newTotalHarga > oldQris ? oldQris : newTotalHarga,
        };
      }

      batch.set(statusRef, newStatusMap, SetOptions(merge: false));

      await batch.commit();

      if (context.mounted) {
        Navigator.pop(context); // Close loader
        printReceipt(); // Print new receipt
      }

    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengubah pesanan: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static List<MenuIngredient> _resolveOptionIngredients(
      List<SelectedOption> selectedOptions, Map<String, Map<String, OptionItem>> optionGroupLookup) {
    final ingredients = <MenuIngredient>[];
    for (var selected in selectedOptions) {
      final groupMap = optionGroupLookup[selected.groupId];
      if (groupMap == null) continue;
      final optionItem = groupMap[selected.optionId];
      if (optionItem == null) continue;
      ingredients.addAll(optionItem.ingredients);
    }
    return ingredients;
  }

  static Future<void> _appendDeductIngredientsToBatch(
      List<PesananObject> pesananList,
      Map<String, MenuObject> menuMap,
      Map<String, Map<String, OptionItem>> optionGroupLookup,
      {required WriteBatch batch}) async {
    final aggregated = <String, Map<String, dynamic>>{};
    for (var pesanan in pesananList) {
      final menu = menuMap[pesanan.namaPesanan];
      if (menu == null) continue;
      final optIngredients = _resolveOptionIngredients(pesanan.selectedOptions, optionGroupLookup);
      final singleMenuAgg = InventoryService().aggregateIngredients(menu.ingredients, optIngredients, pesanan.totalQuantity);
      for (var entry in singleMenuAgg.entries) {
        if (aggregated.containsKey(entry.key)) {
          aggregated[entry.key]!['totalRequired'] = (aggregated[entry.key]!['totalRequired'] as int) + (entry.value['totalRequired'] as int);
        } else {
          aggregated[entry.key] = {
            'name': entry.value['name'],
            'totalRequired': entry.value['totalRequired'],
          };
        }
      }
    }
    await InventoryService().batchDeductAggregatedIngredients(aggregated, batch);
  }

  static Future<void> _appendRevertIngredientsToBatch(
      List<PesananObject> pesananList,
      Map<String, MenuObject> menuMap,
      Map<String, Map<String, OptionItem>> optionGroupLookup,
      {required WriteBatch batch}) async {
    final aggregated = <String, Map<String, dynamic>>{};
    for (var pesanan in pesananList) {
      final menu = menuMap[pesanan.namaPesanan];
      if (menu == null) continue;
      final optIngredients = _resolveOptionIngredients(pesanan.selectedOptions, optionGroupLookup);
      final singleMenuAgg = InventoryService().aggregateIngredients(menu.ingredients, optIngredients, pesanan.totalQuantity);
      for (var entry in singleMenuAgg.entries) {
        if (aggregated.containsKey(entry.key)) {
          aggregated[entry.key]!['totalRequired'] = (aggregated[entry.key]!['totalRequired'] as int) + (entry.value['totalRequired'] as int);
        } else {
          aggregated[entry.key] = {
            'name': entry.value['name'],
            'totalRequired': entry.value['totalRequired'],
          };
        }
      }
    }
    
    // Instead of deducting, we add back
    final fs = FirebaseFirestore.instance;
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    for (var entry in aggregated.entries) {
      final inventoryId = entry.key;
      final stockName = entry.value['name'] as String;
      final totalRequired = entry.value['totalRequired'] as int;

      final docRef = fs.collection(Col.name('Canteens')).doc('canteen375').collection('Inventory').doc(inventoryId);
      batch.set(docRef, {'stock': FieldValue.increment(totalRequired)}, SetOptions(merge: true));

      final logId = '${today}_$inventoryId';
      final logRef = fs.collection(Col.name('Canteens')).doc('canteen375').collection('DailyStockLogs').doc(logId);
      batch.set(logRef, {
        'date': today,
        'inventoryItemId': inventoryId,
        'inventoryItemName': stockName,
        'stockUsed': FieldValue.increment(-totalRequired), // Subtract from usage
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
