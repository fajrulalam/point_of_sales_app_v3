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
import 'package:point_of_sales_app_v3/Services/UserMessageService.dart';
import 'package:point_of_sales_app_v3/Services/VoucherProgramService.dart';

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
    required Function(
            {String? customerName, List<PesananObject>? activePesananList})
        printReceipt,
  }) async {
    return _processEditOrderTransactional(
      context: context,
      statusDocId: statusDocId,
      originalStatusData: originalStatusData,
      newPesananList: newPesananList,
      newTotalHarga: newTotalHarga,
      newBiayaBungkus: newBiayaBungkus,
      menuMap: menuMap,
      optionGroupLookup: optionGroupLookup,
      getYear: getYear,
      getMonth: getMonth,
      getDate: getDate,
      printReceipt: printReceipt,
    );
  }

  // The old batch implementation below is intentionally left unreachable
  // until historical callers are migrated; the transactional path above is
  // authoritative for all current edits.
  /*
    final activePesananList = newPesananList.where((p) => p.totalQuantity > 0).toList();
    if (activePesananList.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
          const SnackBar(
            content: Text('Pesanan tidak boleh kosong. Silakan hapus pesanan atau masukkan minimal 1 item.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

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

      final bool isOpenBill = originalStatusData['transactionMethod'] == 'Open Bill' &&
          originalStatusData['isClosed'] == false;

      // Apply revert to Daily/Monthly/Yearly (if they are for today and not an active open bill)
      // Note: If the order was from a previous day, we should use its original date.
      // Assuming EditOrderScreen only shows today's orders.
      if (!isOpenBill) {
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
      }

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

      for (var pesanan in activePesananList) {
        applyMap[pesanan.namaPesanan] = FieldValue.increment(pesanan.totalQuantity);
      }

      if (!isOpenBill) {
        final oldWaktuPesan = originalStatusData['waktuPesan'] as Timestamp?;
        DateTime orderDate = oldWaktuPesan?.toDate() ?? DateTime.now();
        String formattedDate = DateFormat('yyyy-MM-dd').format(orderDate);
        String orderMonth = DateFormat('yyyy-MM').format(orderDate);
        String orderYear = DateFormat('yyyy').format(orderDate);

        final docDaily = fs.collection(Col.name('DailyTransaction')).doc(formattedDate);
        final docMonthly = fs.collection(Col.name('MonthlyTransaction')).doc(orderMonth);
        final docYearly = fs.collection(Col.name('YearlyTransaction')).doc(orderYear);

        batch.set(docDaily, applyMap, SetOptions(merge: true));
        batch.set(docMonthly, applyMap, SetOptions(merge: true));
        batch.set(docYearly, applyMap, SetOptions(merge: true));
      }

      // Apply New Stock
      await _appendDeductIngredientsToBatch(activePesananList, menuMap, optionGroupLookup, batch: batch);

      // 3. Update Status Document (preserving kitchen progress)
      // Build a lookup of original items keyed by orderKey so we can
      // preserve kitchen-side progress (preparedQuantity, status) for
      // items that haven't been removed.
      final oldItemsByKey = <String, Map<String, dynamic>>{};
      for (var item in oldOrderItemsRaw) {
        final key = _buildOrderKeyFromMap(item);
        oldItemsByKey[key] = Map<String, dynamic>.from(item as Map);
      }

      final newOrderItems = activePesananList.map((order) {
        final menu = menuMap[order.namaPesanan];
        final orderKey = order.orderKey;
        final oldItem = oldItemsByKey[orderKey];

        return {
          'menuItemId': order.menuItemId.isNotEmpty
              ? order.menuItemId
              : (oldItem?['menuItemId'] ?? menu?.id ?? ''),
          'namaPesanan': order.namaPesanan,
          'harga': order.harga,
          'dineInQuantity': order.dineInQuantity,
          'takeAwayQuantity': order.takeAwayQuantity,
          'selectedOptions': order.selectedOptions.map((o) => o.toMap()).toList(),
          'isMakanan': menu?.isMakanan ?? false,
          'customerNote': order.customerNote ?? '',
          // Preserve kitchen progress for items that already existed;
          // new items start at zero.
          'status': oldItem?['status'] ?? '',
          'dineInPreparedQuantity': oldItem?['dineInPreparedQuantity'] ?? 0,
          'takeAwayPreparedQuantity': oldItem?['takeAwayPreparedQuantity'] ?? 0,
          'orderedAt': oldItem?['orderedAt'] ?? DateTime.now().millisecondsSinceEpoch,
        };
      }).toList();

      // Use batch.update instead of batch.set(merge:false) to avoid
      // overwriting concurrent kitchen-app changes to other fields.
      final statusRef = fs.collection(Col.name('Status')).doc(statusDocId);
      final Map<String, dynamic> updateFields = {
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
        updateFields['splitDetails'] = {
          'cashAmount': newCash,
          'qrisAmount': newTotalHarga > oldQris ? oldQris : newTotalHarga,
        };
      }

      batch.update(statusRef, updateFields);

      await batch.commit();

      if (context.mounted) {
        Navigator.pop(context); // Close loader
        printReceipt(
          customerName: originalStatusData['namaCustomer'],
          activePesananList: activePesananList,
        ); // Print new receipt
      }

    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(
          SnackBar(
            content: Text(
                'Gagal mengubah pesanan: ${UserMessageService.fromError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  */

  static MenuObject? _findMenu(
      PesananObject pesanan, Map<String, MenuObject> menuMap) {
    final stableId = pesanan.menuItemId.trim();
    if (stableId.isNotEmpty) {
      final byId = menuMap['__id__$stableId'];
      if (byId != null) return byId;
      for (final menu in menuMap.values) {
        if (menu.id == stableId) return menu;
      }
      return null;
    }
    final byName = menuMap['__name__${pesanan.namaPesanan.trim()}'] ??
        menuMap[pesanan.namaPesanan];
    if (byName != null) return byName;
    return null;
  }

  static List<SelectedOption> _parseSelectedOptions(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => SelectedOption.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  static PesananObject _parseStoredOrderItem(Map<String, dynamic> item) {
    return PesananObject(
      menuItemId: item['menuItemId']?.toString() ?? '',
      namaPesanan: item['namaPesanan']?.toString() ?? '',
      harga: InventoryService.toInt(item['harga']),
      dineInQuantity: InventoryService.toInt(item['dineInQuantity']),
      takeAwayQuantity: InventoryService.toInt(item['takeAwayQuantity']),
      selectedOptions: _parseSelectedOptions(item['selectedOptions']),
      customerNote: item['customerNote']?.toString(),
    );
  }

  static Future<StockTransactionPreparation> _prepareNetStock(
    Transaction transaction, {
    required List<PesananObject> oldOrders,
    required List<PesananObject> newOrders,
    required Map<String, MenuObject> menuMap,
    required Map<String, Map<String, OptionItem>> optionGroupLookup,
    required String statusDocId,
  }) async {
    final inventory = InventoryService();
    final returned = inventory.calculateOrderStockDeltas(
      oldOrders,
      menuLookup: menuMap,
      optionLookup: optionGroupLookup,
      deduct: false,
      sourceType: 'edit',
      sourceId: statusDocId,
    );
    final deducted = inventory.calculateOrderStockDeltas(
      newOrders,
      menuLookup: menuMap,
      optionLookup: optionGroupLookup,
      deduct: true,
      sourceType: 'edit',
      sourceId: statusDocId,
    );
    return inventory.prepareStockDeltasInTransaction(
      transaction,
      [
        ...returned.deltas,
        ...deducted.deltas,
      ],
      sourceType: 'edit',
      sourceId: statusDocId,
      additionalAuditFlags: [
        ...returned.auditFlags,
        ...deducted.auditFlags,
      ],
    );
  }

  static Map<String, int> _paymentBreakdown(
      Map<String, dynamic> data, int total) {
    final result = <String, int>{};
    void add(String field, int amount) {
      if (amount != 0) result[field] = (result[field] ?? 0) + amount;
    }

    // Normalized B2B data is authoritative even if a legacy document also
    // contains stale ordinary split-payment fields.
    if (data['paymentMethod']?.toString() == 'Program') {
      final breakdown = B2BPaymentBreakdown.fromStatus(data, total: total);
      add('totalCash', breakdown.cashAmount);
      add('totalQris', breakdown.qrisAmount);
      add('totalOnline', breakdown.onlineAmount);
      add('totalVoucher', breakdown.nominal);
      return result;
    }
    if (data['isSplitPayment'] == true) {
      final split = data['splitDetails'] is Map
          ? Map<String, dynamic>.from(data['splitDetails'] as Map)
          : <String, dynamic>{};
      add('totalCash', InventoryService.toInt(split['cashAmount']));
      add('totalQris', InventoryService.toInt(split['qrisAmount']));
      return result;
    }
    final method = data['paymentMethod']?.toString();
    if (method == 'Cash') add('totalCash', total);
    if (method == 'QRIS') add('totalQris', total);
    if (method == 'Online') add('totalOnline', total);
    return result;
  }

  static Future<void> _processEditOrderTransactional({
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
    required Function(
            {String? customerName, List<PesananObject>? activePesananList})
        printReceipt,
  }) async {
    final activeOrders =
        newPesananList.where((item) => item.totalQuantity > 0).toList();
    if (activeOrders.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('Pesanan tidak boleh kosong.'),
              backgroundColor: Colors.red,
            ),
          );
      }
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final statusRef = firestore.collection(Col.name('Status')).doc(statusDocId);
    final expectedRevision =
        InventoryService.toInt(originalStatusData['orderRevision']);
    final operationId = _buildEditOperationId(
      statusDocId,
      expectedRevision,
      activeOrders,
      newTotalHarga,
      newBiayaBungkus,
    );
    final operationRef = firestore
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('Orders')
        .doc(operationId);

    if (context.mounted) {
      LoaderWidget.showLoaderDialog(context, message: 'Menyimpan perubahan...');
    }
    var loaderPopped = false;
    try {
      await InventoryService().refreshInventoryCache();
      final result = await firestore
          .runTransaction<InventoryOperationResult>((transaction) async {
        final operationSnapshot = await transaction.get(operationRef);
        if (operationSnapshot.exists &&
            operationSnapshot.data()?['status']?.toString().toLowerCase() ==
                'completed') {
          return const InventoryOperationResult.alreadyApplied();
        }
        final statusSnapshot = await transaction.get(statusRef);
        if (!statusSnapshot.exists) throw Exception('Pesanan tidak ditemukan.');
        final current = statusSnapshot.data() ?? <String, dynamic>{};
        final currentRevision =
            InventoryService.toInt(current['orderRevision']);
        if (currentRevision != expectedRevision) {
          throw Exception(
              'Pesanan sudah diubah oleh perangkat lain. Muat ulang sebelum mengedit lagi.');
        }
        final oldTotal = InventoryService.toInt(current['total']);
        final oldB2b = current['paymentMethod']?.toString() == 'Program'
            ? B2BPaymentBreakdown.fromStatus(current, total: oldTotal)
            : B2BPaymentBreakdown.none;
        if (current['paymentMethod']?.toString() == 'Program' &&
            (oldB2b.programId == null ||
                oldB2b.nominal <= 0 ||
                oldB2b.isAmbiguousLegacy)) {
          throw const VoucherProgramException(
              'Pesanan voucher lama memiliki rincian B2B yang tidak lengkap dan tidak aman untuk diedit.');
        }
        B2BPaymentBreakdown? newB2b;
        if (oldB2b.isProgram) {
          final cappedNominal =
              oldB2b.nominal < newTotalHarga ? oldB2b.nominal : newTotalHarga;
          final newRemainingBeforeSplit = newTotalHarga - cappedNominal;
          final qris = oldB2b.qrisAmount > newRemainingBeforeSplit
              ? newRemainingBeforeSplit
              : oldB2b.qrisAmount;
          newB2b = B2BPaymentBreakdown.calculate(
            billTotal: newTotalHarga,
            requestedNominal: oldB2b.nominal,
            programId: oldB2b.programId,
            extraPaymentMethod: oldB2b.extraPaymentMethod,
            qrisAmount: qris,
          );
        }
        final b2bEdit = await VoucherProgramService.prepareEditInTransaction(
          transaction: transaction,
          operationId: operationId,
          oldProgramId: oldB2b.programId,
          oldNominal: oldB2b.nominal,
          newProgramId: newB2b?.programId,
          newNominal: newB2b?.nominal ?? 0,
        );
        final oldItems = (current['orderItems'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((item) =>
                _parseStoredOrderItem(Map<String, dynamic>.from(item)))
            .toList();
        final preparation = await _prepareNetStock(
          transaction,
          oldOrders: oldItems,
          newOrders: activeOrders,
          menuMap: menuMap,
          optionGroupLookup: optionGroupLookup,
          statusDocId: statusDocId,
        );

        final oldSubTotal = InventoryService.toInt(current['subTotal']);
        final oldTakeAwayFee = InventoryService.toInt(current['takeAwayFee']);
        final newSubTotal = newTotalHarga - newBiayaBungkus;
        final financialDelta = <String, dynamic>{
          'total': FieldValue.increment(newTotalHarga - oldTotal),
          'subTotal': FieldValue.increment(newSubTotal - oldSubTotal),
          'takeAwayFee': FieldValue.increment(newBiayaBungkus - oldTakeAwayFee),
        };
        final oldPayments = _paymentBreakdown(current, oldTotal);
        final newPaymentData = newB2b == null
            ? current
            : <String, dynamic>{
                ...current,
                ...newB2b.toStatusFields(operationId: operationId),
              };
        final newPayments = _paymentBreakdown(newPaymentData, newTotalHarga);
        for (final key in {...oldPayments.keys, ...newPayments.keys}) {
          final delta = (newPayments[key] ?? 0) - (oldPayments[key] ?? 0);
          if (delta != 0) financialDelta[key] = FieldValue.increment(delta);
        }
        if (newB2b != null && newB2b.nominal != oldB2b.nominal) {
          financialDelta['totalVoucher'] =
              FieldValue.increment(newB2b.nominal - oldB2b.nominal);
          financialDelta['totalB2BRedeemed'] =
              FieldValue.increment(newB2b.nominal - oldB2b.nominal);
        }
        final oldCounts = <String, int>{};
        for (final item in oldItems) {
          oldCounts[item.namaPesanan] =
              (oldCounts[item.namaPesanan] ?? 0) + item.totalQuantity;
        }
        final newCounts = <String, int>{};
        for (final item in activeOrders) {
          newCounts[item.namaPesanan] =
              (newCounts[item.namaPesanan] ?? 0) + item.totalQuantity;
        }
        for (final key in {...oldCounts.keys, ...newCounts.keys}) {
          final delta = (newCounts[key] ?? 0) - (oldCounts[key] ?? 0);
          if (delta != 0) financialDelta[key] = FieldValue.increment(delta);
        }

        if (current['transactionMethod'] != 'Open Bill' ||
            current['isClosed'] == true) {
          final rawDate = current['waktuPesan'];
          final date = rawDate is Timestamp ? rawDate.toDate() : DateTime.now();
          final dateKey = DateFormat('yyyy-MM-dd').format(date);
          final monthKey = DateFormat('yyyy-MM').format(date);
          final yearKey = DateFormat('yyyy').format(date);
          transaction.set(
            firestore.collection(Col.name('DailyTransaction')).doc(dateKey),
            financialDelta,
            SetOptions(merge: true),
          );
          transaction.set(
            firestore.collection(Col.name('MonthlyTransaction')).doc(monthKey),
            financialDelta,
            SetOptions(merge: true),
          );
          transaction.set(
            firestore.collection(Col.name('YearlyTransaction')).doc(yearKey),
            financialDelta,
            SetOptions(merge: true),
          );
        }

        InventoryService().queuePreparedStockDeltas(transaction, preparation);
        VoucherProgramService.commitEditInTransaction(
          transaction: transaction,
          preparation: b2bEdit,
          sourceId: statusDocId,
        );
        final oldItemsByKey = <String, Map<String, dynamic>>{};
        for (final raw in (current['orderItems'] as List<dynamic>? ?? [])) {
          if (raw is Map) {
            final map = Map<String, dynamic>.from(raw);
            oldItemsByKey[_buildOrderKeyFromMap(map)] = map;
          }
        }
        final newOrderItems = activeOrders.map((order) {
          final menu = _findMenu(order, menuMap);
          final old = oldItemsByKey[order.orderKey];
          return <String, dynamic>{
            'menuItemId': order.menuItemId.isNotEmpty
                ? order.menuItemId
                : (old?['menuItemId'] ?? menu?.id ?? ''),
            'namaPesanan': order.namaPesanan,
            'harga': order.harga,
            'dineInQuantity': order.dineInQuantity,
            'takeAwayQuantity': order.takeAwayQuantity,
            'selectedOptions':
                order.selectedOptions.map((o) => o.toMap()).toList(),
            'isMakanan': menu?.isMakanan ?? false,
            'customerNote': order.customerNote ?? '',
            'status': old?['status'] ?? '',
            'dineInPreparedQuantity': old?['dineInPreparedQuantity'] ?? 0,
            'takeAwayPreparedQuantity': old?['takeAwayPreparedQuantity'] ?? 0,
            'orderedAt':
                old?['orderedAt'] ?? DateTime.now().millisecondsSinceEpoch,
          };
        }).toList();
        final statusUpdates = <String, dynamic>{
          'orderItems': newOrderItems,
          'total': newTotalHarga,
          'subTotal': newSubTotal,
          'takeAwayFee': newBiayaBungkus,
          'lastEditedAt': FieldValue.serverTimestamp(),
          'orderRevision': currentRevision + 1,
        };
        if (preparation.auditFlags.isNotEmpty) {
          statusUpdates['inventoryAuditFlags'] = FieldValue.arrayUnion(
              preparation.auditFlags.map((flag) => flag.toMap()).toList());
        }
        if (newB2b != null) {
          statusUpdates.addAll(newB2b.toStatusFields(operationId: operationId));
          statusUpdates['isSplitPayment'] = false;
          statusUpdates['splitDetails'] = FieldValue.delete();
        }
        transaction.update(statusRef, statusUpdates);
        transaction.set(
            operationRef,
            {
              'status': 'completed',
              'type': 'edit',
              'sourceId': statusDocId,
              'completedAt': FieldValue.serverTimestamp(),
              'auditFlags':
                  preparation.auditFlags.map((flag) => flag.toMap()).toList(),
            },
            SetOptions(merge: true));
        return InventoryOperationResult.applied(flags: preparation.auditFlags);
      });

      if (result.wasAlreadyApplied) {
        if (context.mounted) {
          loaderPopped = true;
          Navigator.pop(context);
        }
        return;
      }
      if (context.mounted) {
        loaderPopped = true;
        Navigator.pop(context);
        await printReceipt(
          customerName: originalStatusData['namaCustomer']?.toString(),
          activePesananList: activeOrders,
        );
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('Pesanan berhasil diubah.')),
          );
      }
    } catch (e) {
      if (context.mounted && !loaderPopped) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
                content: Text(
                    'Gagal mengubah pesanan: ${UserMessageService.fromError(e)}'),
                backgroundColor: Colors.red),
          );
      }
    }
  }

  /// Gives each edit intent its own id while keeping identical retries
  /// idempotent. Different edits based on the same revision therefore reach
  /// the revision check instead of being mistaken for the same operation.
  static String _buildEditOperationId(
    String statusDocId,
    int expectedRevision,
    List<PesananObject> orders,
    int total,
    int takeAwayFee,
  ) {
    final raw = [
      statusDocId,
      expectedRevision,
      total,
      takeAwayFee,
      ...orders.map((order) =>
          '${order.orderKey}:${order.dineInQuantity}:${order.takeAwayQuantity}:${order.harga}'),
    ].join('|');
    var hash = 2166136261;
    for (final codeUnit in raw.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 'edit_${expectedRevision}_$hash';
  }

  /// Builds the same orderKey that [PesananObject.orderKey] produces,
  /// but from the raw Firestore map stored in `orderItems`.
  static String _buildOrderKeyFromMap(dynamic item) {
    final menuItemId = item['menuItemId']?.toString() ?? '';
    final namaPesanan = item['namaPesanan']?.toString() ?? '';
    final base = menuItemId.isNotEmpty ? menuItemId : namaPesanan;

    final selectedOptions = item['selectedOptions'] is List
        ? item['selectedOptions'] as List<dynamic>
        : const <dynamic>[];
    if (selectedOptions.isEmpty) return base;

    final optionKeys = selectedOptions
        .whereType<Map>()
        .map((o) =>
            '${o['groupName']?.toString() ?? ''}:${o['optionName']?.toString() ?? ''}')
        .toList()
      ..sort();
    return '$base|${optionKeys.join(',')}';
  }

  static List<MenuIngredient> _resolveOptionIngredients(
      List<SelectedOption> selectedOptions,
      Map<String, Map<String, OptionItem>> optionGroupLookup) {
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
      final optIngredients =
          _resolveOptionIngredients(pesanan.selectedOptions, optionGroupLookup);
      final singleMenuAgg = InventoryService().aggregateIngredients(
          menu.ingredients, optIngredients, pesanan.totalQuantity);
      for (var entry in singleMenuAgg.entries) {
        if (aggregated.containsKey(entry.key)) {
          aggregated[entry.key]!['totalRequired'] =
              (aggregated[entry.key]!['totalRequired'] as int) +
                  (entry.value['totalRequired'] as int);
        } else {
          aggregated[entry.key] = {
            'name': entry.value['name'],
            'totalRequired': entry.value['totalRequired'],
          };
        }
      }
    }
    await InventoryService()
        .batchDeductAggregatedIngredients(aggregated, batch);
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
      final optIngredients =
          _resolveOptionIngredients(pesanan.selectedOptions, optionGroupLookup);
      final singleMenuAgg = InventoryService().aggregateIngredients(
          menu.ingredients, optIngredients, pesanan.totalQuantity);
      for (var entry in singleMenuAgg.entries) {
        if (aggregated.containsKey(entry.key)) {
          aggregated[entry.key]!['totalRequired'] =
              (aggregated[entry.key]!['totalRequired'] as int) +
                  (entry.value['totalRequired'] as int);
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
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    for (var entry in aggregated.entries) {
      final inventoryId = entry.key;
      final stockName = entry.value['name'] as String;
      final totalRequired = entry.value['totalRequired'] as int;

      final docRef = fs
          .collection(Col.name('Canteens'))
          .doc('canteen375')
          .collection('Inventory')
          .doc(inventoryId);
      batch.set(docRef, {'stock': FieldValue.increment(totalRequired)},
          SetOptions(merge: true));

      final logId = '${today}_$inventoryId';
      final logRef = fs
          .collection(Col.name('Canteens'))
          .doc('canteen375')
          .collection('DailyStockLogs')
          .doc(logId);
      batch.set(
          logRef,
          {
            'date': today,
            'inventoryItemId': inventoryId,
            'inventoryItemName': stockName,
            'stockUsed':
                FieldValue.increment(-totalRequired), // Subtract from usage
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }
  }
}
