import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Models/RecommendationModels.dart';
import 'package:point_of_sales_app_v3/Models/SelfOrder.dart';
import 'package:point_of_sales_app_v3/Services/LoaderWidget.dart';
import 'package:point_of_sales_app_v3/Services/RecommendationService.dart';
import 'package:point_of_sales_app_v3/Services/SelfOrderService.dart';
import 'package:point_of_sales_app_v3/Services/OpenBillService.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Models/OpenBill.dart';
import 'package:point_of_sales_app_v3/Widgets/RecommendationListWidget.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:point_of_sales_app_v3/Models/Member.dart';
import 'package:point_of_sales_app_v3/Services/MemberService.dart';
import 'package:point_of_sales_app_v3/Services/VoucherProgramService.dart';

class OrderConfirmationService {
  static Future<void> showOrderConfirmationDialog({
    required BuildContext context,
    required List<PesananObject> pesananList,
    required int totalHarga,
    required bool isTakeAway,
    required int biayaBungkus,
    required TextEditingController customerNameController,
    required TextEditingController uangYangDiterimaController,
    required int nomorBerikutnya,
    required Function() getTotal,
    required Future<void> Function({
      List<PesananObject>? customPesananList,
      int? overrideNomorBerikutnya,
      int? overrideTotalHarga,
      bool? overrideIsTakeAway,
      int discountAmount,
      int originalTotal,
    }) printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
    required Function(String, int)
        addRecommendedItem, // Add callback to add item
    List<String> menuItems = const [], // Available menu items for filtering recommendations
    bool printerIsConnected = false,
  }) async {
    if (pesananList.isEmpty) {
      return;
    }

    // 🎯 Generate recommendations based on current order
    final recommendations = await _generateRecommendations(pesananList);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return _OrderConfirmationDialog(
          totalHarga: totalHarga,
          isTakeAway: isTakeAway,
          biayaBungkus: biayaBungkus,
          customerNameController: customerNameController,
          uangYangDiterimaController: uangYangDiterimaController,
          recommendations: recommendations,
          pesananList: pesananList,
          onAddRecommendedItem: addRecommendedItem,
          getTotal: getTotal,
          menuItems: menuItems,
          printerIsConnected: printerIsConnected,
        );
      },
    );

    if (result != null && result['chargeToTab'] == true) {
      await _processOpenBillOrder(
        context: context,
        pesananList: pesananList,
        totalHarga: totalHarga,
        originalTotal: totalHarga,
        isTakeAway: isTakeAway,
        biayaBungkus: biayaBungkus,
        customerNameController: customerNameController,
        uangYangDiterimaController: uangYangDiterimaController,
        nomorBerikutnya: nomorBerikutnya,
        getTotal: getTotal,
        printReceipt: printReceipt,
        getYear: getYear,
        getMonth: getMonth,
        getDate: getDate,
        setJumlahItem: setJumlahItem,
        memberId: result['memberId'],
        memberName: result['memberName'],
        memberPhone: result['memberPhone'],
      );
    } else if (result != null && result['confirmed'] == true) {
      int finalTotal = result['finalTotal'] ?? totalHarga;
      String? appliedVoucherCode = result['voucherCode'];
      bool isMember = result['isMember'] ?? false;
      String? memberId = result['memberId'];
      String? paymentMethod = result['paymentMethod'];

      await _processOrder(
        context: context,
        pesananList: pesananList,
        totalHarga: finalTotal,
        originalTotal: totalHarga,
        isTakeAway: isTakeAway,
        biayaBungkus: biayaBungkus,
        customerNameController: customerNameController,
        uangYangDiterimaController: uangYangDiterimaController,
        nomorBerikutnya: nomorBerikutnya,
        getTotal: getTotal,
        printReceipt: printReceipt,
        getYear: getYear,
        getMonth: getMonth,
        getDate: getDate,
        setJumlahItem: setJumlahItem,
        isMember: isMember,
        memberId: memberId,
        memberPhone: result['memberPhone'],
        appliedVoucherCode: appliedVoucherCode,
        isPosVoucher: result['isPosVoucher'] ?? false,
        discountAmount: totalHarga - finalTotal,
        transactionMethod: paymentMethod,
        isSplitPayment: result['isSplitPayment'] ?? false,
        splitCashAmount: result['splitCashAmount'] ?? 0,
        splitQrisAmount: result['splitQrisAmount'] ?? 0,
        voucherProgramId: result['voucherProgramId'],
        programNominal: result['programNominal'] ?? 0,
        programExtraPaymentMethod: result['programExtraPaymentMethod'],
        programExtraSplitQrisAmount: result['programExtraSplitQrisAmount'] ?? 0,
      );
    } else {
      uangYangDiterimaController.clear();
    }
  }

  /// Show confirmation dialog for self-orders from Member's app
  /// Similar to showOrderConfirmationDialog but updates SelfOrder status on completion
  static Future<void> showSelfOrderConfirmationDialog({
    required BuildContext context,
    required SelfOrder selfOrder,
    required List<PesananObject> pesananList,
    required int totalHarga,
    required bool isTakeAway,
    required int biayaBungkus,
    required TextEditingController customerNameController,
    required TextEditingController uangYangDiterimaController,
    required int nomorBerikutnya,
    required Function() getTotal,
    required Future<void> Function({
      List<PesananObject>? customPesananList,
      int? overrideNomorBerikutnya,
      int? overrideTotalHarga,
      bool? overrideIsTakeAway,
      int discountAmount,
      int originalTotal,
    }) printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
    required Function(String, int) addRecommendedItem,
    List<String> menuItems = const [],
    VoidCallback? onOrderCompleted,
  }) async {
    if (pesananList.isEmpty) {
      return;
    }

    // Mark order as processing
    await SelfOrderService.instance.markAsProcessing(selfOrder.id);

    // Generate recommendations (may be empty for self-orders)
    final recommendations = await _generateRecommendations(pesananList);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _SelfOrderConfirmationDialog(
          selfOrder: selfOrder,
          totalHarga: totalHarga,
          isTakeAway: isTakeAway,
          biayaBungkus: biayaBungkus,
          customerNameController: customerNameController,
          uangYangDiterimaController: uangYangDiterimaController,
          recommendations: recommendations,
          pesananList: pesananList,
          onAddRecommendedItem: addRecommendedItem,
          getTotal: getTotal,
          menuItems: menuItems,
        );
      },
    );

    if (result != null && result['confirmed'] == true) {
      int finalTotal = result['finalTotal'] ?? totalHarga;
      String? appliedVoucherCode = result['voucherCode'];
      bool isMember = result['isMember'] ?? false;
      String? memberId = result['memberId'];
      String? paymentMethod = result['paymentMethod'];

      await _processSelfOrder(
        context: context,
        selfOrder: selfOrder,
        pesananList: pesananList,
        totalHarga: finalTotal,
        originalTotal: totalHarga,
        isTakeAway: isTakeAway,
        biayaBungkus: biayaBungkus,
        customerNameController: customerNameController,
        uangYangDiterimaController: uangYangDiterimaController,
        nomorBerikutnya: nomorBerikutnya,
        getTotal: getTotal,
        printReceipt: printReceipt,
        getYear: getYear,
        getMonth: getMonth,
        getDate: getDate,
        setJumlahItem: setJumlahItem,
        isMember: isMember,
        memberId: memberId,
        memberPhone: result['memberPhone'],
        appliedVoucherCode: appliedVoucherCode,
        isPosVoucher: result['isPosVoucher'] ?? false,
        discountAmount: totalHarga - finalTotal,
        onOrderCompleted: onOrderCompleted,
        transactionMethod: paymentMethod,
        isSplitPayment: result['isSplitPayment'] ?? false,
        splitCashAmount: result['splitCashAmount'] ?? 0,
        splitQrisAmount: result['splitQrisAmount'] ?? 0,
        voucherProgramId: result['voucherProgramId'],
        programNominal: result['programNominal'] ?? 0,
        programExtraPaymentMethod: result['programExtraPaymentMethod'],
        programExtraSplitQrisAmount: result['programExtraSplitQrisAmount'] ?? 0,
      );
    } else {
      // User cancelled - revert status back to Unpaid
      await SelfOrderService.instance.updateStatus(
          selfOrder.id, SelfOrderStatus.unpaid);
      uangYangDiterimaController.clear();
    }
  }

  /// Process a self-order (similar to _processOrder but updates SelfOrder status)
  static Future<void> _processSelfOrder({
    required BuildContext context,
    required SelfOrder selfOrder,
    required List<PesananObject> pesananList,
    required int totalHarga,
    required int originalTotal,
    required bool isTakeAway,
    required int biayaBungkus,
    required TextEditingController customerNameController,
    required TextEditingController uangYangDiterimaController,
    required int nomorBerikutnya,
    required Function() getTotal,
    required Future<void> Function({
      List<PesananObject>? customPesananList,
      int? overrideNomorBerikutnya,
      int? overrideTotalHarga,
      bool? overrideIsTakeAway,
      int discountAmount,
      int originalTotal,
    }) printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
    required bool isMember,
    String? memberId,
    String? memberPhone,
    String? appliedVoucherCode,
    bool isPosVoucher = false,
    int discountAmount = 0,
    VoidCallback? onOrderCompleted,
    String? transactionMethod,
    bool isSplitPayment = false,
    int splitCashAmount = 0,
    int splitQrisAmount = 0,
    String? voucherProgramId,
    int programNominal = 0,
    String? programExtraPaymentMethod,
    int programExtraSplitQrisAmount = 0,
  }) async {
    // Validate stock availability for all items
    final inventoryService = InventoryService();
    final firestore = FirebaseFirestore.instance;

    // Get all menu items to check their ingredients
    final menuSnapshot = await firestore
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('MenuCollection')
        .get();

    final menuMap = <String, MenuObject>{};
    for (var doc in menuSnapshot.docs) {
      final menu = MenuObject(
        id: doc.id,
        namaMenu: doc['namaMenu'],
        harga: doc['harga'],
        isMakanan: doc['isMakanan'],
        imagePath: doc['imagePath'],
        category: doc.data().containsKey('category') ? doc['category'] : 'Umum',
        ingredients: doc.data().containsKey('ingredients')
            ? (doc['ingredients'] as List<dynamic>)
                .map((ing) => MenuIngredient.fromMap(ing as Map<String, dynamic>))
                .toList()
                .cast<MenuIngredient>()
            : <MenuIngredient>[],
      );
      menuMap[menu.namaMenu] = menu;
    }

    // Fetch option groups for ingredient lookup
    final optionGroupSnapshot = await firestore
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('OptionGroups')
        .get();
    final optionGroupLookup = _buildOptionGroupLookup(optionGroupSnapshot);

    // Check availability for each item in the order
    for (var pesanan in pesananList) {
      final menu = menuMap[pesanan.namaPesanan];
      if (menu == null) continue;

      final optionIngredients = _resolveOptionIngredients(
        pesanan.selectedOptions, optionGroupLookup,
      );
      final availability = await inventoryService.checkOrderAvailability(
        menu,
        optionIngredients,
        pesanan.totalQuantity,
      );

      if (!availability.isAvailable) {
        if (context.mounted) {
          // Revert status back to Unpaid on failure
          await SelfOrderService.instance.updateStatus(
              selfOrder.id, SelfOrderStatus.unpaid);

          _showTopError(context, 'Stok tidak cukup untuk ${pesanan.namaPesanan}: ${availability.message}');
        }
        return;
      }
    }


    bool loaderPopped = false;
    if (context.mounted) {
      LoaderWidget.showLoaderDialog(context, message: "Memproses pesanan...");
    }


    Map<String, dynamic> map = {};
    Map<String, dynamic> mapStatus = {};

    String namapesananSerialized = "";
    String quantitypesananSerialized = "";

    for (var element in pesananList) {
      map[element.namaPesanan] = FieldValue.increment(element.totalQuantity);
      namapesananSerialized += '${element.namaPesanan}, ';
      quantitypesananSerialized += '${element.totalQuantity}, ';
    }

    namapesananSerialized =
        namapesananSerialized.substring(0, namapesananSerialized.length - 2);
    quantitypesananSerialized = quantitypesananSerialized.substring(
        0, quantitypesananSerialized.length - 2);

    int subTotal = totalHarga - biayaBungkus;
    map['total'] = FieldValue.increment(totalHarga);
    map['subTotal'] = FieldValue.increment(subTotal);
    map['takeAwayFee'] = FieldValue.increment(biayaBungkus);
    if (isSplitPayment) {
      _incrementPaymentAccumulator(map, 'Cash', splitCashAmount);
      _incrementPaymentAccumulator(map, 'QRIS', splitQrisAmount);
    } else if (voucherProgramId != null) {
      final remaining = totalHarga - programNominal;
      if (remaining > 0 && programExtraPaymentMethod != null) {
        if (programExtraPaymentMethod == 'Cash + QRIS') {
          _incrementPaymentAccumulator(map, 'Cash', remaining - programExtraSplitQrisAmount);
          _incrementPaymentAccumulator(map, 'QRIS', programExtraSplitQrisAmount);
        } else {
          _incrementPaymentAccumulator(map, programExtraPaymentMethod, remaining);
        }
      }
    } else if (transactionMethod != null) {
      _incrementPaymentAccumulator(map, transactionMethod, totalHarga);
    }
    map["year"] = getYear();
    map["month"] = getMonth();
    map["date"] = getDate();
    map["customerNumber"] = FieldValue.increment(1);
    map["timestamp"] = FieldValue.serverTimestamp();
    map["selfOrderId"] = selfOrder.id;

    FirebaseFirestore fs = FirebaseFirestore.instance;
    WriteBatch batch = fs.batch();

    DateTime now = DateTime.now();
    String datenowFormatted = DateFormat('yyyy-MM-dd').format(now);
    DocumentReference dailyTransaction =
        fs.collection(Col.name('DailyTransaction')).doc(datenowFormatted);
    batch.set(dailyTransaction, map, SetOptions(merge: true));

    DocumentReference monthlyTransaction =
        fs.collection(Col.name('MonthlyTransaction')).doc(getMonth());
    batch.set(monthlyTransaction, map, SetOptions(merge: true));

    DocumentReference yearlyTransaction =
        fs.collection(Col.name('YearlyTransaction')).doc(getYear());
    batch.set(yearlyTransaction, map, SetOptions(merge: true));

    List<Map<String, dynamic>> orderItems = pesananList.map((order) {
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

    mapStatus['customerNumber'] = nomorBerikutnya;
    mapStatus['orderItems'] = orderItems;
    mapStatus['status'] = 'Serving';
    mapStatus['namaCustomer'] = customerNameController.text;
    mapStatus['total'] = totalHarga;
    mapStatus['subTotal'] = subTotal;
    mapStatus['takeAwayFee'] = biayaBungkus;
    mapStatus['transactionMethod'] = 'Self Orders';
    if (isSplitPayment) {
      mapStatus['paymentMethod'] = 'Cash/QRIS';
      mapStatus['isSplitPayment'] = true;
      mapStatus['splitDetails'] = {
        'cashAmount': splitCashAmount,
        'qrisAmount': splitQrisAmount,
      };
    } else if (voucherProgramId != null) {
      mapStatus['paymentMethod'] = 'Program';
      mapStatus['voucherProgramId'] = voucherProgramId;
      mapStatus['programNominal'] = programNominal;
      final remaining = totalHarga - programNominal;
      if (remaining > 0 && programExtraPaymentMethod != null) {
        mapStatus['programExtraPaymentMethod'] = programExtraPaymentMethod;
        if (programExtraPaymentMethod == 'Cash + QRIS') {
          mapStatus['programExtraSplitDetails'] = {
            'cashAmount': remaining - programExtraSplitQrisAmount,
            'qrisAmount': programExtraSplitQrisAmount,
          };
        }
      }
    } else {
      mapStatus['paymentMethod'] = transactionMethod;
    }
    mapStatus['isMember'] = isMember;
    mapStatus['canteenId'] = selfOrder.canteenId;
    mapStatus['selfOrderId'] = selfOrder.id;
    mapStatus['selfOrderShortCode'] = selfOrder.displayShortCode;
    if (memberId != null) {
      mapStatus['memberId'] = memberId;
    }
    if (memberPhone != null) {
      mapStatus['customerPhone'] = memberPhone;
    }
    mapStatus['waktuPengambilan'] = selfOrder.waktuPengambilan;
    mapStatus['waktuPesan'] = FieldValue.serverTimestamp();

    // final canteenRef = fs.collection(Col.name('Canteens')).doc('canteen375');
    DocumentReference statusRef =
        fs.collection(Col.name('Status')).doc('${nomorBerikutnya}_plazaUnipdu');
    batch.set(statusRef, mapStatus);

    DocumentReference customerNumber = fs.collection(Col.name('Canteens')).doc('canteen375').collection('Metadata').doc('customerNumber');
    batch.update(customerNumber, {'customerNumber': FieldValue.increment(1)});

    // Deduct ingredients entirely within the same atomic batch
    await _appendAllIngredientsToBatch(pesananList, menuMap, optionGroupLookup, batch: batch);

    if (appliedVoucherCode != null) {
      await _appendVoucherToBatchOrTransaction(appliedVoucherCode, isPosVoucher, batch: batch);
    }

    if (voucherProgramId != null) {
      VoucherProgramService.addRedemptionToBatch(
        batch: batch, 
        programId: voucherProgramId, 
        amount: programNominal > 0 ? programNominal : totalHarga,
      );
    }

    try {
      await batch.commit();

      // Update member points and competition records
      if (isMember && memberId != null) {
        _incrementMemberPoints(memberId, totalHarga);
        _updateCompetitionRecord(memberId, totalHarga);
        _processPeriodicCashbackCampaign(
            memberId, totalHarga, customerNameController.text);
      }

      // Mark the self-order as paid
      await SelfOrderService.instance.markAsPaid(selfOrder.id);

      // 🖨️ Print receipt after successful finalization
      await printReceipt(
        customPesananList: pesananList,
        overrideNomorBerikutnya: nomorBerikutnya,
        overrideTotalHarga: totalHarga,
        overrideIsTakeAway: isTakeAway,
        discountAmount: discountAmount,
        originalTotal: originalTotal,
      );

      if (context.mounted) {
        loaderPopped = true;
        Navigator.pop(context);
      }

      String inputText = uangYangDiterimaController.text.replaceAll('.', '');
      int uangYangDiterima = int.tryParse(inputText) ?? 0;

      await _showSelfOrderSuccessDialog(
        context: context,
        selfOrder: selfOrder,
        nomorBerikutnya: nomorBerikutnya,
        uangYangDiterima: uangYangDiterima,
        totalHarga: totalHarga,
        originalTotal: originalTotal,
        discountAmount: discountAmount,
        pesananList: pesananList,
        customerNameController: customerNameController,
        uangYangDiterimaController: uangYangDiterimaController,
        getTotal: getTotal,
        setJumlahItem: setJumlahItem,
        splitCashAmount: isSplitPayment 
            ? splitCashAmount 
            : (voucherProgramId != null && programExtraPaymentMethod == 'Cash + QRIS' 
                ? (totalHarga - programNominal) - programExtraSplitQrisAmount 
                : 0),
        programNominal: programNominal,
      );

      onOrderCompleted?.call();
    } catch (error) {
      if (context.mounted && !loaderPopped) {
        Navigator.pop(context);
      }
      // Revert status on error
      await SelfOrderService.instance.updateStatus(
          selfOrder.id, SelfOrderStatus.unpaid);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memproses pesanan: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show success dialog specifically for self-orders
  static Future<void> _showSelfOrderSuccessDialog({
    required BuildContext context,
    required SelfOrder selfOrder,
    required int nomorBerikutnya,
    required int uangYangDiterima,
    required int totalHarga,
    required int originalTotal,
    required int discountAmount,
    required List<PesananObject> pesananList,
    required TextEditingController customerNameController,
    required TextEditingController uangYangDiterimaController,
    required Function() getTotal,
    required Function(int) setJumlahItem,
    int splitCashAmount = 0,
    int programNominal = 0,
  }) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pesanan Mandiri Berhasil',
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      selfOrder.displayShortCode,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nomor Antrian',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Text(
                    '$nomorBerikutnya',
                    style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                        fontSize: 42,
                        color: Colors.redAccent.withOpacity(0.9)),
                  ),
                  const SizedBox(height: 16),
                  if (discountAmount > 0) ...[
                    Text(
                      'Diskon: Rp ${NumberFormat.decimalPattern().format(discountAmount).replaceAll(',', '.')}',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Colors.green),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Kembalian:',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: Colors.black87),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Rp ${NumberFormat.decimalPattern().format(uangYangDiterima - (splitCashAmount > 0 ? splitCashAmount : (programNominal > 0 ? totalHarga - programNominal : totalHarga))).replaceAll(',', '.')}',
                        style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w600,
                            fontSize: 22,
                            color: Colors.black87),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Selesai',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    uangYangDiterimaController.clear();
    customerNameController.clear();
    setJumlahItem(0);
    getTotal();
  }

  /// Generate recommendations based on the current order
  /// HIDDEN: Association rules feature is hidden; skip processing to avoid delays.
  static Future<List<Recommendation>> _generateRecommendations(
      List<PesananObject> pesananList) async {
    return [];
  }

  static Future<void> _processOrder({
    required BuildContext context,
    required List<PesananObject> pesananList,
    required int totalHarga,
    required int originalTotal,
    required bool isTakeAway,
    required int biayaBungkus,
    required TextEditingController customerNameController,
    required TextEditingController uangYangDiterimaController,
    required int nomorBerikutnya,
    required Function() getTotal,
    required Future<void> Function({
      List<PesananObject>? customPesananList,
      int? overrideNomorBerikutnya,
      int? overrideTotalHarga,
      bool? overrideIsTakeAway,
      int discountAmount,
      int originalTotal,
    }) printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
    required bool isMember,
    String? memberId,
    String? memberPhone,
    String? appliedVoucherCode,
    bool isPosVoucher = false,
    int discountAmount = 0,
    String? transactionMethod,
    bool isSplitPayment = false,
    int splitCashAmount = 0,
    int splitQrisAmount = 0,
    String? voucherProgramId,
    int programNominal = 0,
    String? programExtraPaymentMethod,
    int programExtraSplitQrisAmount = 0,
  }) async {
    // 🔍 STEP 1: Validate stock availability for all items
    final inventoryService = InventoryService();
    final firestore = FirebaseFirestore.instance;
    
    // Get all menu items to check their ingredients
    final menuSnapshot = await firestore
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('MenuCollection')
        .get();
    
    final menuMap = <String, MenuObject>{};
    for (var doc in menuSnapshot.docs) {
      final menu = MenuObject(
        id: doc.id,
        namaMenu: doc['namaMenu'],
        harga: doc['harga'],
        isMakanan: doc['isMakanan'],
        imagePath: doc['imagePath'],
        category: doc.data().containsKey('category') ? doc['category'] : 'Umum',
        ingredients: doc.data().containsKey('ingredients')
            ? (doc['ingredients'] as List<dynamic>)
                .map((ing) => MenuIngredient.fromMap(ing as Map<String, dynamic>))
                .toList()
                .cast<MenuIngredient>()
            : <MenuIngredient>[],
      );
      menuMap[menu.namaMenu] = menu;
    }

    // Fetch option groups for ingredient lookup
    final optionGroupSnapshot = await firestore
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('OptionGroups')
        .get();
    final optionGroupLookup = _buildOptionGroupLookup(optionGroupSnapshot);
    
    // Check availability for each item in the order
    for (var pesanan in pesananList) {
      final menu = menuMap[pesanan.namaPesanan];
      if (menu == null) continue;

      final optionIngredients = _resolveOptionIngredients(
        pesanan.selectedOptions, optionGroupLookup,
      );
      final availability = await inventoryService.checkOrderAvailability(
        menu,
        optionIngredients,
        pesanan.totalQuantity,
      );
      
      if (!availability.isAvailable) {
        // Close loader and show error
        if (context.mounted) {
          Navigator.pop(context); // Close loader
          
          _showTopError(context, 'Stok tidak cukup untuk ${pesanan.namaPesanan}: ${availability.message}');
        }
        return; // Abort order
      }
    }
    
    bool loaderPopped = false;
    if (context.mounted) {
      LoaderWidget.showLoaderDialog(context, message: "Mohon tunggu...");
    }

    Map<String, dynamic> map = {};
    Map<String, dynamic> mapStatus = {};

    String namapesananSerialized = "";
    String quantitypesananSerialized = "";

    for (var element in pesananList) {
      map[element.namaPesanan] = FieldValue.increment(element.totalQuantity);
      namapesananSerialized += '${element.namaPesanan}, ';
      quantitypesananSerialized += '${element.totalQuantity}, ';
    }

    namapesananSerialized =
        namapesananSerialized.substring(0, namapesananSerialized.length - 2);
    quantitypesananSerialized = quantitypesananSerialized.substring(
        0, quantitypesananSerialized.length - 2);

    int subTotal = totalHarga - biayaBungkus;
    map['total'] = FieldValue.increment(totalHarga);
    map['subTotal'] = FieldValue.increment(subTotal);
    map['takeAwayFee'] = FieldValue.increment(biayaBungkus);
    if (isSplitPayment) {
      _incrementPaymentAccumulator(map, 'Cash', splitCashAmount);
      _incrementPaymentAccumulator(map, 'QRIS', splitQrisAmount);
    } else if (voucherProgramId != null) {
      // Nominal covered by program — increment accumulators for extra payment only
      final remaining = totalHarga - programNominal;
      if (remaining > 0 && programExtraPaymentMethod != null) {
        if (programExtraPaymentMethod == 'Cash + QRIS') {
          _incrementPaymentAccumulator(map, 'Cash', remaining - programExtraSplitQrisAmount);
          _incrementPaymentAccumulator(map, 'QRIS', programExtraSplitQrisAmount);
        } else {
          _incrementPaymentAccumulator(map, programExtraPaymentMethod, remaining);
        }
      }
    } else if (transactionMethod != null) {
      _incrementPaymentAccumulator(map, transactionMethod, totalHarga);
    }
    map["year"] = getYear();
    map["month"] = getMonth();
    map["date"] = getDate();
    map["customerNumber"] = FieldValue.increment(1);
    map["timestamp"] = FieldValue.serverTimestamp();

    FirebaseFirestore fs = FirebaseFirestore.instance;
    WriteBatch batch = fs.batch();

    DateTime now = DateTime.now();
    String datenowFormatted = DateFormat('yyyy-MM-dd').format(now);
    DocumentReference dailyTransaction =
        fs.collection(Col.name('DailyTransaction')).doc(datenowFormatted);
    batch.set(dailyTransaction, map, SetOptions(merge: true));

    DocumentReference monthlyTransaction =
        fs.collection(Col.name('MonthlyTransaction')).doc(getMonth());
    batch.set(monthlyTransaction, map, SetOptions(merge: true));

    DocumentReference yearlyTransaction =
        fs.collection(Col.name('YearlyTransaction')).doc(getYear());
    batch.set(yearlyTransaction, map, SetOptions(merge: true));

    List<Map<String, dynamic>> orderItems = pesananList.map((order) {
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

    mapStatus['customerNumber'] = nomorBerikutnya;
    mapStatus['orderItems'] = orderItems;
    mapStatus['status'] = 'Serving';
    mapStatus['namaCustomer'] = customerNameController.text;
    mapStatus['total'] = totalHarga;
    mapStatus['subTotal'] = subTotal;
    mapStatus['takeAwayFee'] = biayaBungkus;
    mapStatus['transactionMethod'] = 'Normal';
    if (isSplitPayment) {
      mapStatus['paymentMethod'] = 'Cash/QRIS';
      mapStatus['isSplitPayment'] = true;
      mapStatus['splitDetails'] = {
        'cashAmount': splitCashAmount,
        'qrisAmount': splitQrisAmount,
      };
    } else if (voucherProgramId != null) {
      mapStatus['paymentMethod'] = 'Program';
      mapStatus['voucherProgramId'] = voucherProgramId;
      mapStatus['programNominal'] = programNominal;
      final remaining = totalHarga - programNominal;
      if (remaining > 0 && programExtraPaymentMethod != null) {
        mapStatus['programExtraPaymentMethod'] = programExtraPaymentMethod;
        if (programExtraPaymentMethod == 'Cash + QRIS') {
          mapStatus['programExtraSplitDetails'] = {
            'cashAmount': remaining - programExtraSplitQrisAmount,
            'qrisAmount': programExtraSplitQrisAmount,
          };
        }
      }
    } else {
      mapStatus['paymentMethod'] = transactionMethod;
    }
    mapStatus['canteenId'] = 'canteen375_plazaUnipdu';
    mapStatus['isMember'] = isMember;
    if (memberId != null) {
      mapStatus['memberId'] = memberId;
    }
    if (memberPhone != null) {
      mapStatus['customerPhone'] = memberPhone;
    }
    mapStatus['waktuPengambilan'] = 'Tidak Memesan';
    mapStatus['waktuPesan'] = FieldValue.serverTimestamp();

    // final canteenRef = fs.collection(Col.name('Canteens')).doc('canteen375');
    DocumentReference statusRef =
        fs.collection(Col.name('Status')).doc('${nomorBerikutnya}_plazaUnipdu');
    batch.set(statusRef, mapStatus);

    DocumentReference customerNumber = fs.collection(Col.name('Canteens')).doc('canteen375').collection('Metadata').doc('customerNumber');
    batch.update(customerNumber, {'customerNumber': FieldValue.increment(1)});

    // Deduct ingredients entirely within the same atomic batch
    await _appendAllIngredientsToBatch(pesananList, menuMap, optionGroupLookup, batch: batch);
    
    if (appliedVoucherCode != null) {
      await _appendVoucherToBatchOrTransaction(appliedVoucherCode, isPosVoucher, batch: batch);
    }
    
    if (voucherProgramId != null) {
      VoucherProgramService.addRedemptionToBatch(
        batch: batch, 
        programId: voucherProgramId, 
        amount: programNominal > 0 ? programNominal : totalHarga,
      );
    }

    try {
      await batch.commit();

      // 💳 STEP 3: Update member points and competition records
      if (isMember && memberId != null) {
        _incrementMemberPoints(memberId, totalHarga);
        _updateCompetitionRecord(memberId, totalHarga);
        _processPeriodicCashbackCampaign(memberId, totalHarga, customerNameController.text);
      }

      // 🖨️ Print receipt after successful finalization
      await printReceipt(
        customPesananList: pesananList,
        overrideNomorBerikutnya: nomorBerikutnya,
        overrideTotalHarga: totalHarga,
        overrideIsTakeAway: isTakeAway,
        discountAmount: discountAmount,
        originalTotal: originalTotal,
      );

      if (context.mounted) {
        loaderPopped = true;
        Navigator.pop(context);
      }

      String inputText = uangYangDiterimaController.text.replaceAll('.', '');
      int uangYangDiterima = int.tryParse(inputText) ?? 0;

      await _showSuccessDialog(
        context: context,
        nomorBerikutnya: nomorBerikutnya,
        uangYangDiterima: uangYangDiterima,
        totalHarga: totalHarga,
        originalTotal: originalTotal,
        discountAmount: discountAmount,
        pesananList: pesananList,
        customerNameController: customerNameController,
        uangYangDiterimaController: uangYangDiterimaController,
        getTotal: getTotal,
        setJumlahItem: setJumlahItem,
        splitCashAmount: isSplitPayment 
            ? splitCashAmount 
            : (voucherProgramId != null && programExtraPaymentMethod == 'Cash + QRIS' 
                ? (totalHarga - programNominal) - programExtraSplitQrisAmount 
                : 0),
        programNominal: programNominal,
      );
    } catch (error) {
      if (context.mounted && !loaderPopped) {
        Navigator.pop(context);
      }
    }
  }

  static Future<void> _processOpenBillOrder({
    required BuildContext context,
    required List<PesananObject> pesananList,
    required int totalHarga,
    required int originalTotal,
    required bool isTakeAway,
    required int biayaBungkus,
    required TextEditingController customerNameController,
    required TextEditingController uangYangDiterimaController,
    required int nomorBerikutnya,
    required Function() getTotal,
    required Future<void> Function({
      List<PesananObject>? customPesananList,
      int? overrideNomorBerikutnya,
      int? overrideTotalHarga,
      bool? overrideIsTakeAway,
      int discountAmount,
      int originalTotal,
    }) printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
    required String memberId,
    required String memberName,
    required String? memberPhone,
  }) async {
    final inventoryService = InventoryService();
    final firestore = FirebaseFirestore.instance;
    
    final menuSnapshot = await firestore.collection(Col.name('Canteens')).doc('canteen375').collection('MenuCollection').get();
    final menuMap = <String, MenuObject>{};
    for (var doc in menuSnapshot.docs) {
      menuMap[doc['namaMenu']] = MenuObject(
        id: doc.id,
        namaMenu: doc['namaMenu'],
        harga: doc['harga'],
        isMakanan: doc['isMakanan'],
        imagePath: doc['imagePath'],
        category: doc.data().containsKey('category') ? doc['category'] : 'Umum',
        ingredients: doc.data().containsKey('ingredients')
            ? (doc['ingredients'] as List<dynamic>).map((ing) => MenuIngredient.fromMap(ing as Map<String, dynamic>)).toList()
            : <MenuIngredient>[],
      );
    }
    
    final optionGroupSnapshot = await firestore.collection(Col.name('Canteens')).doc('canteen375').collection('OptionGroups').get();
    final optionGroupLookup = _buildOptionGroupLookup(optionGroupSnapshot);
    
    for (var pesanan in pesananList) {
      final menu = menuMap[pesanan.namaPesanan];
      if (menu == null) continue;
      final optionIngredients = _resolveOptionIngredients(pesanan.selectedOptions, optionGroupLookup);
      final availability = await inventoryService.checkOrderAvailability(menu, optionIngredients, pesanan.totalQuantity);
      if (!availability.isAvailable) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stok tidak cukup untuk ${pesanan.namaPesanan}'), backgroundColor: Colors.red));
        }
        return;
      }
    }
    
    LoaderWidget.showLoaderDialog(context, message: "Menyimpan tagihan...");

    // ── Query root Status collection for existing open bill ──
    DocumentSnapshot? existingStatusDoc;
    try {
      existingStatusDoc = await OpenBillService.instance.getExistingOpenBill(memberId);
    } catch (_) {
      // If pre-read fails, proceed with creating a new Status doc
    }

    // ── Credit limit check ──
    try {
      final creditLimit = await OpenBillService.instance.getCreditLimit();
      int currentTotal = 0;
      if (existingStatusDoc != null && existingStatusDoc.exists) {
        final data = existingStatusDoc.data() as Map<String, dynamic>;
        currentTotal = (data['total'] ?? 0) as int;
      }
      int newTotal = currentTotal + totalHarga;
      if (newTotal > creditLimit) {
        Navigator.pop(context);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Total tagihan (Rp $newTotal) melebihi batas kredit (Rp $creditLimit). Selesaikan tagihan yang ada terlebih dahulu.'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
    } catch (e) {
      // Continue — credit limit check is a safeguard, not a blocker
    }

    // ── Build orderItems for the Status doc ──
    List<Map<String, dynamic>> orderItems = pesananList.map((order) {
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

    try {
      final WriteBatch batch = firestore.batch();

      if (existingStatusDoc != null && existingStatusDoc.exists) {
        // ── APPEND to existing Status doc ──
        final existingData = existingStatusDoc.data() as Map<String, dynamic>;
        List<dynamic> existingOrderItems = List.from(existingData['orderItems'] ?? []);
        existingOrderItems.addAll(orderItems);

        // Store food subtotal only (exclude take-away fee); fee is recalculated at settlement
        int foodSubtotal = totalHarga - biayaBungkus;
        batch.update(existingStatusDoc.reference, {
          'orderItems': existingOrderItems,
          'total': FieldValue.increment(foodSubtotal),
          'subTotal': FieldValue.increment(foodSubtotal),
          // takeAwayFee stays at 0; recalculated at settlement
        });
      } else {
        // ── CREATE new Status doc ──
        final String statusDocId = '${nomorBerikutnya}_plazaUnipdu';
        // Store food subtotal only (exclude take-away fee); fee is recalculated at settlement
        int foodSubtotal = totalHarga - biayaBungkus;
        Map<String, dynamic> mapStatus = {
          'customerNumber': nomorBerikutnya,
          'orderItems': orderItems,
          'status': 'Serving',
          'namaCustomer': memberName,
          'total': foodSubtotal,
          'subTotal': foodSubtotal,
          'takeAwayFee': 0,
          'transactionMethod': 'Open Bill',
          'paymentMethod': null,
          'isMember': true,
          'memberId': memberId,
          if (memberPhone != null) 'customerPhone': memberPhone,
          'waktuPengambilan': 'Tidak Memesan',
          'canteenId': "canteen375_plazaUnipdu",
          'waktuPesan': FieldValue.serverTimestamp(),
          'isClosed': false,
        };

        DocumentReference statusRef = firestore.collection(Col.name('Status')).doc(statusDocId);
        batch.set(statusRef, mapStatus);

        DocumentReference customerNumber = firestore.collection(Col.name('Canteens')).doc('canteen375').collection('Metadata').doc('customerNumber');
        batch.update(customerNumber, {'customerNumber': FieldValue.increment(1)});
      }

      // Deduct ingredients within the batch
      await _appendAllIngredientsToBatch(pesananList, menuMap, optionGroupLookup, batch: batch);

      await batch.commit();
    } catch (e) {
      Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
      return;
    }

    try {
      // Receipt printing is skipped here for Open Bills. It will be printed during settlement.
      Navigator.pop(context);

      await _showSuccessDialog(
        context: context,
        nomorBerikutnya: nomorBerikutnya,
        uangYangDiterima: totalHarga,
        totalHarga: totalHarga,
        originalTotal: originalTotal,
        discountAmount: 0,
        pesananList: pesananList,
        customerNameController: customerNameController,
        uangYangDiterimaController: uangYangDiterimaController,
        getTotal: getTotal,
        setJumlahItem: setJumlahItem,
      );
    } catch (error) {
      Navigator.pop(context);
    }
  }

  static void _incrementPaymentAccumulator(
      Map<String, dynamic> map, String method, int amount) {
    if (method == 'Cash') {
      map['totalCash'] = FieldValue.increment(amount);
    } else if (method == 'QRIS') {
      map['totalQris'] = FieldValue.increment(amount);
    } else if (method == 'Online') {
      map['totalOnline'] = FieldValue.increment(amount);
    }
  }

  static Future<void> _showSuccessDialog({
    required BuildContext context,
    required int nomorBerikutnya,
    required int uangYangDiterima,
    required int totalHarga,
    required int originalTotal,
    required int discountAmount,
    required List<PesananObject> pesananList,
    required TextEditingController customerNameController,
    required TextEditingController uangYangDiterimaController,
    required Function() getTotal,
    required Function(int) setJumlahItem,
    int splitCashAmount = 0,
    int programNominal = 0,
  }) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SizedBox(
              width: 300,
              height: discountAmount > 0 ? 250 : 200,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Pesanan berhasil',
                    style: GoogleFonts.montserrat(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$nomorBerikutnya',
                    style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                        fontSize: 36,
                        color: Colors.redAccent.withOpacity(0.8)),
                  ),
                  const SizedBox(height: 16),
                  if (discountAmount > 0) ...[
                    Text(
                      'Diskon: Rp ${NumberFormat.decimalPattern().format(discountAmount).replaceAll(',', '.')}',
                      style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Colors.green),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Kembalian:',
                        style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: Colors.black87.withOpacity(1)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Rp ${NumberFormat.decimalPattern().format(uangYangDiterima - (splitCashAmount > 0 ? splitCashAmount : (programNominal > 0 ? totalHarga - programNominal : totalHarga)))}',
                        style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w600,
                            fontSize: 24,
                            color: Colors.black87.withOpacity(1)),
                      )
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    pesananList.clear();
    uangYangDiterimaController.clear();
    customerNameController.clear();
    setJumlahItem(0);
    getTotal();
  }

  /// Build a nested lookup: {groupId: {optionId: OptionItem}}
  static Map<String, Map<String, OptionItem>> _buildOptionGroupLookup(
    QuerySnapshot snapshot,
  ) {
    final lookup = <String, Map<String, OptionItem>>{};
    for (var doc in snapshot.docs) {
      final group = OptionGroup.fromFirestore(doc);
      final optionMap = <String, OptionItem>{};
      for (var option in group.options) {
        optionMap[option.id] = option;
      }
      lookup[group.id] = optionMap;
    }
    return lookup;
  }

  /// Resolve a list of SelectedOptions into a flat list of MenuIngredients
  /// by looking up each option's ingredients from the option group data.
  static List<MenuIngredient> _resolveOptionIngredients(
    List<SelectedOption> selectedOptions,
    Map<String, Map<String, OptionItem>> optionGroupLookup,
  ) {
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

  static Future<void> _appendAllIngredientsToBatch(
    List<PesananObject> pesananList,
    Map<String, MenuObject> menuMap,
    Map<String, Map<String, OptionItem>> optionGroupLookup,
    {WriteBatch? batch, Transaction? transaction}
  ) async {
    if (batch == null && transaction == null) return;

    final aggregated = <String, Map<String, dynamic>>{};
    
    for (var pesanan in pesananList) {
      final menu = menuMap[pesanan.namaPesanan];
      if (menu == null) continue;
      
      final optIngredients = _resolveOptionIngredients(
        pesanan.selectedOptions, optionGroupLookup,
      );
      
      final singleMenuAgg = InventoryService().aggregateIngredients(
        menu.ingredients, optIngredients, pesanan.totalQuantity
      );
      
      for (var entry in singleMenuAgg.entries) {
        if (aggregated.containsKey(entry.key)) {
          aggregated[entry.key]!['totalRequired'] = 
              (aggregated[entry.key]!['totalRequired'] as int) + (entry.value['totalRequired'] as int);
        } else {
          aggregated[entry.key] = {
            'name': entry.value['name'],
            'totalRequired': entry.value['totalRequired'],
          };
        }
      }
    }

    if (batch != null) {
      await InventoryService().batchDeductAggregatedIngredients(aggregated, batch);
    } else if (transaction != null) {
      await InventoryService().transactionDeductAggregatedIngredients(aggregated, transaction);
    }
  }

  static Future<void> _appendVoucherToBatchOrTransaction(
      String voucherCode, bool isPosVoucher, {WriteBatch? batch, Transaction? transaction}) async {
    try {
      if (batch == null && transaction == null) return;
      
      if (isPosVoucher) {
        FirebaseFirestore fs = FirebaseFirestore.instance;
        DocumentReference voucherRef =
            fs.collection(Col.name("vouchers")).doc(voucherCode);

        // Fetch document to get voucherGroupId
        DocumentSnapshot doc;
        if (transaction != null) {
            doc = await transaction.get(voucherRef);
        } else {
            doc = await voucherRef.get();
        }
        
        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          String? groupId = data['voucherGroupId'];

          if (batch != null) batch.update(voucherRef, {'status': 'CLAIMED'});
          if (transaction != null) transaction.update(voucherRef, {'status': 'CLAIMED'});

          if (groupId != null) {
            var groupRef = fs.collection(Col.name('voucherGroup')).doc(groupId);
            if (batch != null) batch.update(groupRef, {'totalClaimed': FieldValue.increment(1)});
            if (transaction != null) transaction.update(groupRef, {'totalClaimed': FieldValue.increment(1)});
            print('📈 Incremented totalClaimed for group $groupId');
          }
        }
      } else {
        FirebaseFirestore eSantrenFs =
            FirebaseFirestore.instanceFor(app: Firebase.app('e-santren'));
        DocumentReference voucherRef =
            eSantrenFs.collection("vouchers").doc(voucherCode);
        if (batch != null) batch.update(voucherRef, {'isClaimed': true});
        if (transaction != null) transaction.update(voucherRef, {'isClaimed': true});
      }
      print('✅ Voucher $voucherCode claimed successfully inside atomic unit');
    } catch (e) {
      print('❌ Failed to claim voucher $voucherCode: $e');
    }
  }

  static Future<Map<String, dynamic>?> _validateVoucher(
      String voucherCode, int currentTotal) async {
    try {
      FirebaseFirestore fs = FirebaseFirestore.instance;
      DocumentSnapshot doc =
          await fs.collection(Col.name("vouchers")).doc(voucherCode).get();

      Map<String, dynamic>? data;
      bool isPosVoucher = false;

      if (doc.exists) {
        data = doc.data() as Map<String, dynamic>;
        isPosVoucher = true;
      } else {
        // Fallback to e-santren instance
        FirebaseFirestore eSantrenFs =
            FirebaseFirestore.instanceFor(app: Firebase.app('e-santren'));
        DocumentSnapshot eSantrenDoc =
            await eSantrenFs.collection(Col.name("vouchers")).doc(voucherCode).get();
        if (eSantrenDoc.exists) {
          data = eSantrenDoc.data() as Map<String, dynamic>;
        }
      }

      if (data == null) {
        return {'error': 'Voucher tidak ditemukan'};
      }

      DateTime now = DateTime.now();
      DateTime activeDate = (data['activeDate'] as Timestamp).toDate();
      DateTime expireDate = (data['expireDate'] as Timestamp).toDate();
      bool isClaimed = data['isClaimed'] ?? false;
      bool isActive = data['isActive'] ?? false;

      if (now.isBefore(activeDate) || now.isAfter(expireDate)) {
        return {'error': 'Voucher sudah tidak berlaku'};
      }

      if (isClaimed || (isPosVoucher && data['status'] == 'CLAIMED')) {
        return {'error': 'Voucher sudah digunakan'};
      }

      if (!isActive) {
        return {'error': 'Voucher tidak aktif'};
      }

      // 🎁 POS Specific Logic: Cashback Campaigns
      if (isPosVoucher && data['type'] == 'cashbackCampaign') {
        int userPoints = data['userPoints'] ?? 0;
        int threshold = data['threshold'] ?? 0;
        int requirement = data['transactionRequirement'] ?? 0;
        String status = data['status'] ?? '';

        // Expire voucher if it is past date but hasn't been officially set to EXPIRED yet
        if (now.isAfter(expireDate) && status == 'READY_TO_CLAIM') {
          await fs.collection(Col.name("vouchers")).doc(voucherCode).update({
            'status': 'EXPIRED',
          });
          return {'error': 'Voucher sudah tidak berlaku (Expired)'};
        }

        if (userPoints < threshold) {
          return {
            'error':
                'Insufficent Points: the user has $userPoints points while the required points are $threshold amount',
            'isSnackbarError': true,
          };
        }

        if (currentTotal < requirement) {
          return {
            'error':
                'Transaksi belum mencapai syarat minimal Rp ${NumberFormat.decimalPattern().format(requirement).replaceAll(',', '.')} untuk voucher ini',
            'isSnackbarError': true,
          };
        }
      }

      return {
        'success': true,
        'nama': data['nama'],
        'voucherName': data['voucherName'] ?? 'Voucher',
        'value': data['value'],
        'isPosVoucher': isPosVoucher,
        'userId': data['userId'],
      };
    } catch (e) {
      print('❌ Error validating voucher: $e');
      return {'error': 'Terjadi kesalahan saat memvalidasi voucher'};
    }
  }

  static void _incrementMemberPoints(String memberId, int totalHarga) async {
    try {
      int pointsToAdd = totalHarga ~/ 10000;
      if (pointsToAdd <= 0) return;

      FirebaseFirestore fs = FirebaseFirestore.instance;
      DocumentReference memberRef = fs.collection(Col.name('Members')).doc(memberId);

      await memberRef.update({
        'points': FieldValue.increment(pointsToAdd),
      });

      print('✅ Added $pointsToAdd points to member $memberId');
    } catch (e) {
      print('❌ Failed to increment member points: $e');
    }
  }

  static void _updateCompetitionRecord(String memberId, int totalHarga) async {
    try {
      FirebaseFirestore fs = FirebaseFirestore.instance;
      DateTime now = DateTime.now();
      String monthDocId = DateFormat('yyyy-MM').format(now);

      DocumentReference compRef =
          fs.collection(Col.name("competitionRecords")).doc(monthDocId);

      int pointsEarned = totalHarga ~/ 10000;

      // Use set with merge and dot notation for incremental updates to nested fields
      await compRef.set({
        memberId: {
          'amountSpent': FieldValue.increment(totalHarga),
          'customerPoints': FieldValue.increment(pointsEarned),
          'numberOfTransaction': FieldValue.increment(1),
        }
      }, SetOptions(merge: true));

      print('🏆 Updated competition record for $memberId in $monthDocId');
    } catch (e) {
      print('❌ Failed to update competition record: $e');
    }
  }

  static String _generateVoucherId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        4, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  static void _processPeriodicCashbackCampaign(String memberId, int totalHarga, String customerName) async {
    try {
      int pointsToAdd = totalHarga ~/ 10000;
      if (pointsToAdd <= 0) return; // Only process if points are earned

      FirebaseFirestore fs = FirebaseFirestore.instance;
      DateTime now = DateTime.now();
      
      QuerySnapshot activeCampaigns = await fs
          .collection(Col.name('voucherGroup'))
          .where('isActive', isEqualTo: true)
          .where('type', isEqualTo: 'cashbackCampaign')
          .get();

      if (activeCampaigns.docs.isEmpty) return;

      // Fetch user's existing vouchers to check status and avoid composite index requirement
      QuerySnapshot userVouchers = await fs
          .collection(Col.name('vouchers'))
          .where('userId', isEqualTo: memberId)
          .get();

      Set<String> claimedCampaignIds = {};
      Map<String, DocumentSnapshot> existingVouchersMap = {};
      
      for (var vDoc in userVouchers.docs) {
        Map<String, dynamic> vData = vDoc.data() as Map<String, dynamic>;
        if (vData['type'] == 'cashbackCampaign') {
          String groupId = vData['voucherGroupId'] ?? '';
          existingVouchersMap[groupId] = vDoc;
          if (vData['status'] == 'CLAIMED') {
            claimedCampaignIds.add(groupId);
          }
        }
      }

      List<QueryDocumentSnapshot> eligibleCampaigns = [];
      for (var doc in activeCampaigns.docs) {
        if (claimedCampaignIds.contains(doc.id)) continue; 

        Map<String, dynamic> campaignData = doc.data() as Map<String, dynamic>;
        Timestamp? activeTimestamp = campaignData['activeDate'] as Timestamp?;
        Timestamp? expireTimestamp = campaignData['expireDate'] as Timestamp?;
        
        if (activeTimestamp != null && expireTimestamp != null) {
          if (now.isAfter(activeTimestamp.toDate()) && now.isBefore(expireTimestamp.toDate())) {
            eligibleCampaigns.add(doc);
          }
        }
      }

      if (eligibleCampaigns.isEmpty) return;

      // Priority Algorithm: Sort by expiry date closest to now
      eligibleCampaigns.sort((a, b) {
        Timestamp expireA = (a.data() as Map<String, dynamic>)['expireDate'] as Timestamp;
        Timestamp expireB = (b.data() as Map<String, dynamic>)['expireDate'] as Timestamp;
        return expireA.compareTo(expireB);
      });

      // Apply points to the top priority campaign ONLY
      var priorityCampaignDoc = eligibleCampaigns.first;
      String voucherGroupId = priorityCampaignDoc.id;
      Map<String, dynamic> campaignData = priorityCampaignDoc.data() as Map<String, dynamic>;
      
      var existingVoucher = existingVouchersMap[voucherGroupId];

      if (existingVoucher != null) {
        Map<String, dynamic> voucherData = existingVoucher.data() as Map<String, dynamic>;
        if (voucherData['status'] == 'IN_PROGRESS' || voucherData['status'] == 'READY_TO_CLAIM') {
          int currentPoints = voucherData['userPoints'] ?? 0;
          int threshold = voucherData['threshold'] ?? 0;
          int newPoints = currentPoints + pointsToAdd;
          String newStatus = newPoints >= threshold ? 'READY_TO_CLAIM' : 'IN_PROGRESS';

          await existingVoucher.reference.update({
            'userPoints': newPoints,
            'status': newStatus,
            'lastUpdatedAt': FieldValue.serverTimestamp(),
          });
          print('🪙 Added $pointsToAdd points to prioritized campaign ${campaignData['voucherName']} for $memberId. New Status: $newStatus');
        }
      } else {
        String newVoucherId = _generateVoucherId();
        int threshold = campaignData['threshold'] ?? 0;
        String initialStatus = pointsToAdd >= threshold ? 'READY_TO_CLAIM' : 'IN_PROGRESS';

        await fs.collection(Col.name('vouchers')).doc(newVoucherId).set({
          'activeDate': campaignData['activeDate'],
          'createdAt': FieldValue.serverTimestamp(),
          'expireDate': campaignData['expireDate'],
          'isActive': true,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'nama': customerName,
          'status': initialStatus,
          'threshold': threshold,
          'type': 'cashbackCampaign',
          'transactionRequirement': campaignData['transactionRequirement'] ?? 0,
          'userId': memberId,
          'userPoints': pointsToAdd,
          'value': campaignData['value'],
          'voucherId': newVoucherId,
          'voucherGroupId': voucherGroupId,
          'voucherName': campaignData['voucherName'],
        });
        
        await priorityCampaignDoc.reference.update({
          'totalParticipants': FieldValue.increment(1),
        });
        print('🎟️ Created new prioritized cashback campaign voucher ${campaignData['voucherName']} for $memberId');
      }

    } catch (e) {
      print('❌ Failed to process periodic cashback campaign: $e');
    }
  }

  /// Show settlement dialog for an existing Open Bill
  static Future<void> showOpenBillSettlementDialog({
    required BuildContext context,
    required OpenBill openBill,
    required List<OpenBillOrder> billOrders,
    required bool printerIsConnected,
    required TextEditingController uangYangDiterimaController,
    required int nomorBerikutnya,
    required Future<void> Function({int discountAmount, int originalTotal, List<PesananObject>? customPesananList, int? overrideNomorBerikutnya, int? overrideTotalHarga, bool? overrideIsTakeAway})
        printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
  }) async {
    // 1. Aggregate all items from all orders in the open bill
    final List<PesananObject> aggregatedItems = [];
    
    for (var order in billOrders) {
      for (var item in order.items) {
        final pesanan = PesananObject(
          namaPesanan: item.namaPesanan,
          harga: item.harga,
          dineInQuantity: item.dineInQuantity,
          takeAwayQuantity: item.takeAwayQuantity,
          selectedOptions: item.selectedOptions.toList(),
        );
        
        int idx = aggregatedItems.indexWhere((ai) => ai.orderKey == pesanan.orderKey);
        if (idx == -1) {
          aggregatedItems.add(pesanan);
        } else {
          aggregatedItems[idx].dineInQuantity += pesanan.dineInQuantity;
          aggregatedItems[idx].takeAwayQuantity += pesanan.takeAwayQuantity;
        }
      }
    }

    // 2. Calculate take-away fee from aggregated items using unitsPerPackage
    int totalTakeAwayFee = 0;
    try {
      final menuSnapshot = await FirebaseFirestore.instance
          .collection(Col.name('Canteens'))
          .doc('canteen375')
          .collection('MenuCollection')
          .get();
      final menuUnitsMap = <String, int>{};
      for (var doc in menuSnapshot.docs) {
        final data = doc.data();
        menuUnitsMap[data['namaMenu'] ?? ''] = (data['unitsPerPackage'] ?? 1) as int;
      }

      int totalPackages = 0;
      for (var item in aggregatedItems) {
        if (item.takeAwayQuantity > 0) {
          int unitsPerPackage = menuUnitsMap[item.namaPesanan] ?? 1;
          int packagesNeeded = (item.takeAwayQuantity / unitsPerPackage).ceil();
          totalPackages += packagesNeeded;
        }
      }
      totalTakeAwayFee = (totalPackages ~/ 4) * 1000;
    } catch (e) {
      // If menu fetch fails, proceed with 0 take-away fee
      print('⚠️ Failed to calculate take-away fee for open bill: $e');
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _OpenBillSettlementDialog(
          openBill: openBill,
          printerIsConnected: printerIsConnected,
          aggregatedItems: aggregatedItems,
          totalTakeAwayFee: totalTakeAwayFee,
          uangYangDiterimaController: uangYangDiterimaController,
        );
      },
    );

    if (result != null && result['confirmed'] == true) {
      int finalTotal = result['finalTotal'] ?? (openBill.totalAmount + totalTakeAwayFee);
      String? appliedVoucherCode = result['voucherCode'];
      String? paymentMethod = result['paymentMethod'];

      int billTotalWithFee = openBill.totalAmount + totalTakeAwayFee;

      await _processOpenBillSettlement(
        context: context,
        openBill: openBill,
        aggregatedItems: aggregatedItems,
        totalHarga: finalTotal,
        originalTotal: billTotalWithFee,
        totalTakeAwayFee: totalTakeAwayFee,
        uangYangDiterimaController: uangYangDiterimaController,
        nomorBerikutnya: nomorBerikutnya,
        printReceipt: printReceipt,
        getYear: getYear,
        getMonth: getMonth,
        getDate: getDate,
        setJumlahItem: setJumlahItem,
        appliedVoucherCode: appliedVoucherCode,
        isPosVoucher: result['isPosVoucher'] ?? false,
        discountAmount: billTotalWithFee - finalTotal,
        transactionMethod: paymentMethod,
        isSplitPayment: result['isSplitPayment'] ?? false,
        splitCashAmount: result['splitCashAmount'] ?? 0,
        splitQrisAmount: result['splitQrisAmount'] ?? 0,
        voucherProgramId: result['voucherProgramId'],
        programNominal: result['programNominal'] ?? 0,
        programExtraPaymentMethod: result['programExtraPaymentMethod'],
        programExtraSplitQrisAmount: result['programExtraSplitQrisAmount'] ?? 0,
      );
    } else {
      uangYangDiterimaController.clear();
    }
  }

  /// Internal logic for completing an open bill settlement
  static Future<void> _processOpenBillSettlement({
    required BuildContext context,
    required OpenBill openBill,
    required List<PesananObject> aggregatedItems,
    required int totalHarga,
    required int originalTotal,
    required int totalTakeAwayFee,
    required TextEditingController uangYangDiterimaController,
    required int nomorBerikutnya,
    required Future<void> Function({int discountAmount, int originalTotal, List<PesananObject>? customPesananList, int? overrideNomorBerikutnya, int? overrideTotalHarga, bool? overrideIsTakeAway}) printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
    String? appliedVoucherCode,
    bool isPosVoucher = false,
    int discountAmount = 0,
    String? transactionMethod,
    bool isSplitPayment = false,
    int splitCashAmount = 0,
    int splitQrisAmount = 0,
    String? voucherProgramId,
    int programNominal = 0,
    String? programExtraPaymentMethod,
    int programExtraSplitQrisAmount = 0,
  }) async {
    LoaderWidget.showLoaderDialog(context, message: "Menyelesaikan tagihan...");
    
    FirebaseFirestore fs = FirebaseFirestore.instance;
    WriteBatch batch = fs.batch();
    
    // 1. Prepare Transaction Data
    Map<String, dynamic> map = {};
    for (var element in aggregatedItems) {
      map[element.namaPesanan] = FieldValue.increment(element.totalQuantity);
    }
    int subTotal = totalHarga - totalTakeAwayFee;
    map['total'] = FieldValue.increment(totalHarga);
    map['subTotal'] = FieldValue.increment(subTotal);
    map['takeAwayFee'] = FieldValue.increment(totalTakeAwayFee);
    if (isSplitPayment) {
      _incrementPaymentAccumulator(map, 'Cash', splitCashAmount);
      _incrementPaymentAccumulator(map, 'QRIS', splitQrisAmount);
    } else if (voucherProgramId != null) {
      final remaining = totalHarga - programNominal;
      if (remaining > 0 && programExtraPaymentMethod != null) {
        if (programExtraPaymentMethod == 'Cash + QRIS') {
          _incrementPaymentAccumulator(map, 'Cash', remaining - programExtraSplitQrisAmount);
          _incrementPaymentAccumulator(map, 'QRIS', programExtraSplitQrisAmount);
        } else {
          _incrementPaymentAccumulator(map, programExtraPaymentMethod, remaining);
        }
      }
    } else if (transactionMethod != null) {
      _incrementPaymentAccumulator(map, transactionMethod, totalHarga);
    }
    map["year"] = getYear();
    map["month"] = getMonth();
    map["date"] = getDate();
    map["timestamp"] = FieldValue.serverTimestamp();

    DateTime now = DateTime.now();
    String datenowFormatted = DateFormat('yyyy-MM-dd').format(now);
    DocumentReference dailyTransaction = fs.collection(Col.name('DailyTransaction')).doc(datenowFormatted);
    batch.set(dailyTransaction, map, SetOptions(merge: true));

    DocumentReference monthlyTransaction = fs.collection(Col.name('MonthlyTransaction')).doc(getMonth());
    batch.set(monthlyTransaction, map, SetOptions(merge: true));

    DocumentReference yearlyTransaction = fs.collection(Col.name('YearlyTransaction')).doc(getYear());
    batch.set(yearlyTransaction, map, SetOptions(merge: true));

    try {
      // 🗃️ STEP 2: Settle the open bill by updating the Status doc
      // Changes transactionMethod from 'Open Bill' to actual payment method,
      // sets isClosed=true, and records settlement metadata.
      if (openBill.statusDocId != null) {
        await OpenBillService.instance.settleBill(
          statusDocId: openBill.statusDocId!,
          paymentMethod: transactionMethod ?? 'Cash',
          finalTotal: totalHarga,
          discountAmount: discountAmount,
          subTotal: subTotal,
          takeAwayFee: totalTakeAwayFee,
          voucherCode: appliedVoucherCode,
          existingBatch: batch,
          isSplitPayment: isSplitPayment,
          splitDetails: isSplitPayment
              ? {'cashAmount': splitCashAmount, 'qrisAmount': splitQrisAmount}
              : null,
          voucherProgramId: voucherProgramId,
        );
      }

      if (appliedVoucherCode != null) {
        await _appendVoucherToBatchOrTransaction(appliedVoucherCode, isPosVoucher, batch: batch);
      }
      
      if (voucherProgramId != null) {
        VoucherProgramService.addRedemptionToBatch(
          batch: batch, 
          programId: voucherProgramId, 
          amount: programNominal > 0 ? programNominal : totalHarga,
        );
      }

      // 🏆 Commit the entire batch (Financials + Settlement) together!
      await batch.commit();

      // 💳 STEP 3: Update member points and competition records
      _incrementMemberPoints(openBill.memberId, totalHarga);
      _updateCompetitionRecord(openBill.memberId, totalHarga);
      _processPeriodicCashbackCampaign(openBill.memberId, totalHarga, openBill.memberName);

      // 📠 STEP 4: Print Receipt
      await printReceipt(
        customPesananList: aggregatedItems,
        overrideTotalHarga: totalHarga,
        overrideNomorBerikutnya: openBill.customerNumber,
        overrideIsTakeAway: totalTakeAwayFee > 0,
        discountAmount: discountAmount,
        originalTotal: originalTotal,
      );

      Navigator.pop(context); // Close loader

      int uangYangDiterima = int.parse(uangYangDiterimaController.text.replaceAll('.', ''));

      await _showSuccessDialog(
        context: context,
        nomorBerikutnya: openBill.customerNumber,
        uangYangDiterima: uangYangDiterima,
        totalHarga: totalHarga,
        originalTotal: originalTotal,
        discountAmount: discountAmount,
        pesananList: aggregatedItems,
        customerNameController: TextEditingController(text: openBill.memberName),
        uangYangDiterimaController: uangYangDiterimaController,
        getTotal: () {},
        setJumlahItem: setJumlahItem,
        splitCashAmount: isSplitPayment 
            ? splitCashAmount 
            : (voucherProgramId != null && programExtraPaymentMethod == 'Cash + QRIS' 
                ? (totalHarga - programNominal) - programExtraSplitQrisAmount 
                : 0),
        programNominal: programNominal,
      );
    } catch (e) {
      Navigator.pop(context);
      if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyelesaikan tagihan: $e'), backgroundColor: Colors.red));
      }
    }
  }
}

class _OrderConfirmationDialog extends StatefulWidget {
  final int totalHarga;
  final bool isTakeAway;
  final int biayaBungkus;
  final TextEditingController customerNameController;
  final TextEditingController uangYangDiterimaController;
  final List<Recommendation> recommendations;
  final List<PesananObject> pesananList;
  final Function(String, int) onAddRecommendedItem;
  final Function() getTotal;
  final List<String> menuItems;
  final bool printerIsConnected;

  const _OrderConfirmationDialog({
    required this.totalHarga,
    required this.isTakeAway,
    required this.biayaBungkus,
    required this.customerNameController,
    required this.uangYangDiterimaController,
    required this.recommendations,
    required this.pesananList,
    required this.onAddRecommendedItem,
    required this.getTotal,
    this.menuItems = const [],
    this.printerIsConnected = false,
  });

  @override
  _OrderConfirmationDialogState createState() =>
      _OrderConfirmationDialogState();
}

class _OrderConfirmationDialogState extends State<_OrderConfirmationDialog> {
  bool applyPromo = false;
  TextEditingController voucherController = TextEditingController();
  String? voucherName;
  int voucherValue = 0;
  bool voucherApplied = false;
  String? voucherError;
  bool isValidatingVoucher = false;
  bool isPosVoucher = false;
  late int
      currentTotal; // Track current total that updates when items are added
  List<Member> _members = [];
  Member? _selectedMember;
  bool isMember = true;
  String? _memberError;
  String? _selectedPaymentMethod;
  bool _isSplitPayment = false;
  int _splitQrisAmount = 0;
  TextEditingController _splitQrisController = TextEditingController();
  List<Map<String, dynamic>> _activePrograms = [];
  String? _selectedProgramId;
  TextEditingController _programNominalController = TextEditingController();
  int _programNominal = 0;
  String? _programExtraPaymentMethod;
  bool _isProgramExtraSplit = false;
  TextEditingController _programExtraQrisController = TextEditingController();
  int _programExtraQrisAmount = 0;
  int _programMultiplier = 1;
  int _baseProgramNominal = 0;
  String _lastSearchQuery = '';
  Iterable<Member> _lastOptionsFound = const Iterable<Member>.empty();

  late FocusNode customerNameFocusNode;
  late FocusNode uangFocusNode;
  late FocusNode voucherFocusNode;

  @override
  void initState() {
    super.initState();
    customerNameFocusNode = FocusNode();
    uangFocusNode = FocusNode();
    voucherFocusNode = FocusNode();
    currentTotal = widget.totalHarga; // Initialize with the starting total
    _loadMembers();
    _loadPrograms();
  }

  Future<void> _loadPrograms() async {
    final programs = await VoucherProgramService.getActivePrograms();
    if (mounted) {
      setState(() {
        _activePrograms = programs;
      });
    }
  }

  @override
  void dispose() {
    customerNameFocusNode.dispose();
    uangFocusNode.dispose();
    voucherFocusNode.dispose();
    _programNominalController.dispose();
    _programExtraQrisController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final members = await MemberService.instance.getCachedMembers();
    setState(() {
      _members = members;
    });
  }

  void _updateTotal() {
    setState(() {
      // Recalculate total from current order items
      int subtotal =
          widget.pesananList.fold(0, (acc, order) => acc + order.subtotal);
      int totalTakeAway = widget.pesananList.fold(
        0,
        (acc, order) => acc + order.takeAwayQuantity,
      );
      currentTotal = subtotal + (totalTakeAway * widget.biayaBungkus);
    });
  }

  @override
  Widget build(BuildContext context) {
    int displayTotal = currentTotal - voucherValue;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: null,
      content: SizedBox(
        width: MediaQuery.of(context).size.width,
        height: 520,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // First Column: Title + Top half of form (L2059-L2465)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Konfirmasi Pesanan',
                            style: GoogleFonts.poppins(
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: widget.printerIsConnected ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Total tagihan: '),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (voucherApplied && voucherValue > 0) ...[
                              Text(
                                'Rp ${NumberFormat.decimalPattern().format(widget.totalHarga).replaceAll(',', '.')}',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.1,
                                  fontSize: 14,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              Text(
                                'Rp ${NumberFormat.decimalPattern().format(displayTotal).replaceAll(',', '.')}',
                                style: GoogleFonts.poppins(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                  fontSize: 16,
                                ),
                              ),
                            ] else
                              Text(
                                'Rp ${NumberFormat.decimalPattern().format(displayTotal).replaceAll(',', '.')}',
                                style: GoogleFonts.poppins(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                  fontSize: 16,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (voucherApplied && voucherValue > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Diskon: Rp ${NumberFormat.decimalPattern().format(voucherValue).replaceAll(',', '.')}',
                        style: GoogleFonts.poppins(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (widget.isTakeAway)
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '(Biaya bungkus: ',
                                style: GoogleFonts.poppins(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.1,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Rp ${NumberFormat.decimalPattern().format(widget.biayaBungkus).replaceAll(',', '.')})',
                                style: GoogleFonts.poppins(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.1,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: applyPromo,
                              onChanged: (value) {
                                setState(() {
                                  applyPromo = value ?? false;
                                  if (!applyPromo) {
                                    voucherController.clear();
                                    voucherName = null;
                                    voucherValue = 0;
                                    voucherApplied = false;
                                    voucherError = null;
                                    isPosVoucher = false;
                                    widget.customerNameController.clear();
                                  }
                                });
                              },
                            ),
                            Text(
                              'Apply Promo',
                              style: GoogleFonts.poppins(
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        // Member Toggle
                        Row(
                          children: [
                            Checkbox(
                              value: isMember,
                              onChanged: (value) {
                                setState(() {
                                  isMember = value ?? true;
                                  if (!isMember) {
                                    _selectedMember = null;
                                    _memberError = null;
                                  }
                                });
                              },
                            ),
                            Text(
                              'Pelanggan Member',
                              style: GoogleFonts.poppins(
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (applyPromo) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 7,
                            child: TextField(
                              controller: voucherController,
                              focusNode: voucherFocusNode,
                              maxLength: 10,
                              keyboardType: TextInputType.text,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                labelText: 'Code Voucher',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(4.0),
                                ),
                                counterText: '',
                                errorText: voucherError,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextButton(
                              onPressed: isValidatingVoucher
                                  ? null
                                  : () async {
                                      if (voucherController.text.length < 4) {
                                        setState(() {
                                          voucherError =
                                              'Minimal 4 karakter';
                                        });
                                        return;
                                      }

                                      setState(() {
                                        isValidatingVoucher = true;
                                        voucherError = null;
                                      });

                                      final result =
                                          await OrderConfirmationService
                                              ._validateVoucher(
                                                  voucherController.text,
                                                  currentTotal);

                                      setState(() {
                                        isValidatingVoucher = false;
                                        if (result != null &&
                                            result['error'] != null) {
                                          if (result['isSnackbarError'] ==
                                              true) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content:
                                                      Text(result['error'])),
                                            );
                                          }
                                          voucherError = result['error'];
                                          voucherApplied = false;
                                          voucherName = null;
                                          voucherValue = 0;
                                          isPosVoucher = false;
                                        } else if (result != null) {
                                          voucherError = null;
                                          voucherApplied = true;
                                          voucherName = result['voucherName'];
                                          voucherValue = result['value'];
                                          isPosVoucher = result['isPosVoucher'] ?? false;

                                          // Automatically put customer name and handle member link
                                          String? returnedName = result['nama'];
                                          String? returnedUserId = result['userId'];

                                          if (returnedUserId != null) {
                                            // Prioritize linking to the actual member and using their name
                                            try {
                                              _selectedMember = _members.firstWhere(
                                                  (m) => m.id == returnedUserId);
                                              isMember = true;
                                              widget.customerNameController.text =
                                                  _selectedMember!.name;
                                              print(
                                                  "✅ Linked to member: ${_selectedMember!.name}");
                                            } catch (e) {
                                              // If member not in cache, fallback to name stored in voucher
                                              if (returnedName != null &&
                                                  returnedName.isNotEmpty) {
                                                widget.customerNameController
                                                    .text = returnedName;
                                              }
                                              print(
                                                  "⚠️ Member for voucher not found in cache: $returnedUserId");
                                            }
                                          } else if (returnedName != null &&
                                              returnedName.isNotEmpty) {
                                            // Handle vouchers that have a name but no userId
                                            widget.customerNameController.text =
                                                returnedName;
                                          }
                                        } else {
                                          voucherError =
                                              'Terjadi kesalahan tidak diketahui';
                                          voucherApplied = false;
                                          voucherName = null;
                                          voucherValue = 0;
                                          isPosVoucher = false;
                                        }
                                      });
                                    },
                              child: isValidatingVoucher
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (isMember)
                      Autocomplete<Member>(
                        focusNode: customerNameFocusNode,
                        textEditingController: widget.customerNameController,
                        displayStringForOption: (Member option) => option.name,
                        optionsBuilder: (TextEditingValue textEditingValue) async {
                          final query = textEditingValue.text;
                          if (query == '') {
                            return const Iterable<Member>.empty();
                          }
                          
                          _lastSearchQuery = query;
                          await Future.delayed(const Duration(milliseconds: 500));
                          
                          if (query != _lastSearchQuery) {
                            return _lastOptionsFound;
                          }
                          
                          _lastOptionsFound = await MemberService.instance
                              .searchCachedMembers(query);
                          return _lastOptionsFound;
                        },
                        onSelected: (Member selection) {
                          setState(() {
                            _selectedMember = selection;
                            _memberError = null;
                            widget.customerNameController.text = selection.name;
                          });
                        },
                        fieldViewBuilder: (context, controller, focusNode,
                            onFieldSubmitted) {
                          // Sync initial value handled by Autocomplete internally mostly
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            onChanged: (value) {
                              widget.customerNameController.text = value;
                              // Reset selection if input changes from the selected member's name
                              if (_selectedMember != null && value != _selectedMember!.name) {
                                setState(() {
                                  _selectedMember = null;
                                  _memberError = null;
                                });
                              } else if (_memberError != null) {
                                setState(() => _memberError = null);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Cari Nama/HP Member',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              errorText: _memberError,
                            ),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4.0,
                              child: SizedBox(
                                width: 350, // Fits the typical dialog width
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final Member option = options.elementAt(index);
                                    return ListTile(
                                      title: Text(
                                        "${option.name} ${option.phoneNumber}",
                                        style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                      ),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    else
                      TextField(

                        controller: widget.customerNameController,
                        focusNode: customerNameFocusNode,
                        decoration: InputDecoration(
                          labelText: 'Nama Customer',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 48, thickness: 1, indent: 20, endIndent: 20),
            // Second Column: Payment method until order confirmation
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Metode Pembayaran',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Cash', 'QRIS', 'Online', 'Cash + QRIS', 'Program'].map((method) {
                        final isSelected = _selectedPaymentMethod == method;
                        return ChoiceChip(
                          label: Text(method),
                          selected: isSelected,
                          selectedColor: const Color(0xFFC8E6C9),
                          labelStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? const Color(0xFF2E7D32) : Colors.black87,
                          ),
                          onSelected: (selected) {
                            setState(() {
                              _selectedPaymentMethod = selected ? method : null;
                              if (selected && method == 'Cash + QRIS') {
                                _isSplitPayment = true;
                                widget.uangYangDiterimaController.clear();
                                _splitQrisController.clear();
                                _splitQrisAmount = 0;
                              } else {
                                _isSplitPayment = false;
                                if (selected && method != 'Cash') {
                                  final format = NumberFormat("#,###", "id_ID");
                                  widget.uangYangDiterimaController.text =
                                      format.format(displayTotal);
                                } else if (selected && method == 'Cash') {
                                  widget.uangYangDiterimaController.clear();
                                }
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (_isSplitPayment) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _splitQrisController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                TextInputFormatter.withFunction((oldValue, newValue) {
                                  final plainNumber = newValue.text.replaceAll('.', '');
                                  if (plainNumber.isEmpty) return newValue;
                                  final format = NumberFormat("#,###", "id_ID");
                                  final newText = format.format(int.parse(plainNumber));
                                  return newValue.copyWith(
                                    text: newText,
                                    selection: TextSelection.collapsed(offset: newText.length),
                                  );
                                }),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Jumlah QRIS (Rp)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _splitQrisAmount = int.tryParse(val.replaceAll('.', '')) ?? 0;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Sisa Cash:', style: GoogleFonts.poppins(fontSize: 11, color: Colors.blue.shade700)),
                                  Text(
                                    'Rp ${NumberFormat("#,###", "id_ID").format((displayTotal - _splitQrisAmount).clamp(0, displayTotal))}',
                                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_selectedPaymentMethod == 'Program' && _activePrograms.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedProgramId,
                        items: _activePrograms.map((p) {
                          return DropdownMenuItem<String>(
                            value: p['id'],
                            child: Text('${p['programName']} (${p['institutionName']})'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedProgramId = val;
                            if (val != null) {
                              final prog = _activePrograms.firstWhere((p) => p['id'] == val, orElse: () => {});
                              final defNominal = ((prog['defaultNominal'] ?? 0) as num).toInt();
                              _programNominal = defNominal;
                              _baseProgramNominal = defNominal;
                              _programMultiplier = 1;
                              _programNominalController.text = defNominal > 0 ? NumberFormat('#,###', 'id_ID').format(defNominal) : '';
                              _programExtraPaymentMethod = null;
                              _isProgramExtraSplit = false;
                              _programExtraQrisAmount = 0;
                              _programExtraQrisController.clear();
                              widget.uangYangDiterimaController.clear();
                            }
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Pilih Program Voucher',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ],
                    // ─── PROGRAM PAYMENT SECTION ───
                    if (_selectedPaymentMethod == 'Program' && _selectedProgramId != null) ...[ 
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _programNominalController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                TextInputFormatter.withFunction((oldValue, newValue) {
                                  final plain = newValue.text.replaceAll('.', '');
                                  if (plain.isEmpty) return newValue;
                                  final fmt = NumberFormat('#,###', 'id_ID');
                                  final t = fmt.format(int.parse(plain));
                                  return newValue.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length));
                                }),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Nominal Voucher (Rp)',
                                helperText: 'Jumlah yang ditanggung program',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  int newTotal = int.tryParse(val.replaceAll('.', '')) ?? 0;
                                  _programNominal = newTotal;

                                  // Only reset multiplier if the user manually edited the total
                                  // to something other than base * multiplier
                                  if (newTotal != _baseProgramNominal * _programMultiplier) {
                                    _baseProgramNominal = newTotal;
                                    _programMultiplier = 1;
                                  }

                                  _programExtraPaymentMethod = null;
                                  _isProgramExtraSplit = false;
                                  _programExtraQrisAmount = 0;
                                  _programExtraQrisController.clear();
                                  widget.uangYangDiterimaController.clear();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _programMultiplier++;
                                _programNominal = _baseProgramNominal * _programMultiplier;
                                _programNominalController.text = NumberFormat('#,###', 'id_ID').format(_programNominal);
                              });
                            },
                            onLongPress: () {
                              setState(() {
                                _programMultiplier = 1;
                                _programNominal = _baseProgramNominal * _programMultiplier;
                                _programNominalController.text = NumberFormat('#,###', 'id_ID').format(_programNominal);
                              });
                            },
                            child: Container(
                              height: 56, // Fixed height to match TextField's input area
                              width: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFC8E6C9),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF2E7D32)),
                              ),
                              child: Text(
                                'x$_programMultiplier',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Builder(builder: (ctx) {
                        final remaining = displayTotal - _programNominal;
                        if (remaining <= 0) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(children: [
                              const Icon(Icons.check_circle, color: Colors.green, size: 16),
                              const SizedBox(width: 6),
                              Text('Voucher menutupi seluruh tagihan', style: GoogleFonts.poppins(fontSize: 12, color: Colors.green.shade700)),
                            ]),
                          );
                        }
                        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.shade200)),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text('Sisa yang harus dibayar:', style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange.shade800)),
                              Text('Rp ${NumberFormat("#,###", "id_ID").format(remaining)}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                            ]),
                          ),
                          const SizedBox(height: 10),
                          Text('Metode Pembayaran Sisa', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, runSpacing: 8, children: ['Cash', 'QRIS', 'Cash + QRIS'].map((m) {
                            final isSel = _programExtraPaymentMethod == m;
                            return ChoiceChip(
                              label: Text(m, style: GoogleFonts.poppins(fontSize: 12)),
                              selected: isSel,
                              selectedColor: const Color(0xFFC8E6C9),
                              labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: isSel ? FontWeight.w600 : FontWeight.w400, color: isSel ? const Color(0xFF2E7D32) : Colors.black87),
                              onSelected: (sel) {
                                setState(() {
                                  _programExtraPaymentMethod = sel ? m : null;
                                  _isProgramExtraSplit = sel && m == 'Cash + QRIS';
                                  _programExtraQrisAmount = 0;
                                  _programExtraQrisController.clear();
                                  if (sel && m == 'QRIS') {
                                    widget.uangYangDiterimaController.text = NumberFormat('#,###', 'id_ID').format(remaining);
                                  } else {
                                    widget.uangYangDiterimaController.clear();
                                  }
                                });
                              },
                            );
                          }).toList()),
                          if (_isProgramExtraSplit) ...[ 
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: TextField(
                                controller: _programExtraQrisController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                  TextInputFormatter.withFunction((oldValue, newValue) {
                                    final plain = newValue.text.replaceAll('.', '');
                                    if (plain.isEmpty) return newValue;
                                    final t = NumberFormat('#,###', 'id_ID').format(int.parse(plain));
                                    return newValue.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length));
                                  }),
                                ],
                                decoration: InputDecoration(labelText: 'Jumlah QRIS (Rp)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(4))),
                                onChanged: (val) => setState(() => _programExtraQrisAmount = int.tryParse(val.replaceAll('.', '')) ?? 0),
                              )),
                              const SizedBox(width: 12),
                              Expanded(child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue.shade200)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Sisa Cash:', style: GoogleFonts.poppins(fontSize: 11, color: Colors.blue.shade700)),
                                  Text('Rp ${NumberFormat("#,###", "id_ID").format((remaining - _programExtraQrisAmount).clamp(0, remaining))}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                                ]),
                              )),
                            ]),
                          ],
                          if (_programExtraPaymentMethod != null && _programExtraPaymentMethod != 'QRIS') ...[ 
                            const SizedBox(height: 10),
                            TextField(
                              controller: widget.uangYangDiterimaController,
                              focusNode: uangFocusNode,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                TextInputFormatter.withFunction((oldValue, newValue) {
                                  final plain = newValue.text.replaceAll('.', '');
                                  if (plain.isEmpty) return newValue;
                                  final t = NumberFormat('#,###', 'id_ID').format(int.parse(plain));
                                  return newValue.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length));
                                }),
                              ],
                              decoration: InputDecoration(
                                labelText: _isProgramExtraSplit ? 'Cash Diterima (Rp)' : 'Uang Diterima (Rp)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                            ),
                            Builder(builder: (ctx) {
                              final cashReceived = int.tryParse(widget.uangYangDiterimaController.text.replaceAll('.', '')) ?? 0;
                              final cashNeeded = _isProgramExtraSplit ? (remaining - _programExtraQrisAmount).clamp(0, remaining) : remaining;
                              final change = cashReceived - cashNeeded;
                              if (change <= 0) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('Kembalian: Rp ${NumberFormat("#,###", "id_ID").format(change)}', style: GoogleFonts.poppins(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                              );
                            }),
                          ],
                        ]);
                      }),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: () {
                            if (isMember && _selectedMember == null) {
                              final error = widget.customerNameController.text.trim().isEmpty ? 'Nama member wajib diisi' : 'Nama tidak ditemukan, pilih dari daftar';
                              setState(() { _memberError = error; });
                              _showTopError(context, error);
                              return;
                            }
                            if (!isMember && widget.customerNameController.text.trim().isEmpty) {
                              _showTopError(context, 'Nama customer wajib diisi');
                              return;
                            }
                            if (_programNominal <= 0) { _showTopError(context, 'Masukkan nominal voucher'); return; }
                            final remaining = displayTotal - _programNominal;
                            int extraQris = 0;
                            if (remaining > 0) {
                              if (_programExtraPaymentMethod == null) { _showTopError(context, 'Pilih metode pembayaran sisa'); return; }
                              if (_isProgramExtraSplit) {
                                if (_programExtraQrisAmount <= 0 || _programExtraQrisAmount >= remaining) { _showTopError(context, 'Jumlah QRIS tidak valid'); return; }
                                extraQris = _programExtraQrisAmount;
                                final cashReceived = int.tryParse(widget.uangYangDiterimaController.text.replaceAll('.', '')) ?? 0;
                                if (cashReceived < remaining - extraQris) { _showTopError(context, 'Cash yang diterima kurang'); return; }
                              } else if (_programExtraPaymentMethod == 'Cash') {
                                final cashReceived = int.tryParse(widget.uangYangDiterimaController.text.replaceAll('.', '')) ?? 0;
                                if (cashReceived < remaining) { _showTopError(context, 'Cash yang diterima kurang'); return; }
                              }
                            }
                            Navigator.pop(context, {
                              'confirmed': true, 'finalTotal': displayTotal, 'paymentMethod': 'Program',
                              'voucherProgramId': _selectedProgramId,
                              'programNominal': _programNominal,
                              'programExtraPaymentMethod': remaining > 0 ? _programExtraPaymentMethod : null,
                              'programExtraSplitQrisAmount': extraQris,
                              'isMember': isMember, 'memberId': _selectedMember?.id, 'memberPhone': _selectedMember?.phoneNumber,
                              'voucherCode': voucherApplied ? voucherController.text : null,
                              'isPosVoucher': voucherApplied ? isPosVoucher : false,
                            });
                          },
                          child: Text('OK', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                    // ─── NORMAL PAYMENT SECTION ───
                    if (_selectedPaymentMethod != 'Program') ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 7,
                            child: TextField(
                              focusNode: uangFocusNode,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                TextInputFormatter.withFunction((oldValue, newValue) {
                                  final plainNumber = newValue.text.replaceAll('.', '');
                                  final format = NumberFormat("#,###", "id_ID");
                                  final newText = format.format(int.parse(plainNumber));
                                  return TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length));
                                }),
                              ],
                              controller: widget.uangYangDiterimaController,
                              decoration: InputDecoration(
                                labelText: 'Uang yang diterima (Rp)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4.0)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 3,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                              onPressed: () {
                                if (isMember && _selectedMember == null) {
                                  final error = widget.customerNameController.text.trim().isEmpty ? 'Nama member wajib diisi' : 'Nama tidak ditemukan, pilih dari daftar';
                                  setState(() { _memberError = error; });
                                  _showTopError(context, error);
                                  return;
                                }
                                if (!isMember && widget.customerNameController.text.trim().isEmpty) {
                                  _showTopError(context, 'Nama customer wajib diisi');
                                  return;
                                }
                                if (_selectedPaymentMethod == null) { _showTopError(context, 'Pilih metode pembayaran'); return; }
                                if (_isSplitPayment) {
                                  if (_splitQrisAmount <= 0 || _splitQrisAmount >= displayTotal) { _showTopError(context, 'Jumlah QRIS tidak valid'); return; }
                                }
                                final inputText = widget.uangYangDiterimaController.text.replaceAll('.', '');
                                if (inputText.isEmpty) { _showTopError(context, 'Masukkan uang yang diterima'); return; }
                                int uangYangDiterima = int.parse(inputText);
                                final cashNeeded = _isSplitPayment ? displayTotal - _splitQrisAmount : displayTotal;
                                if (uangYangDiterima >= cashNeeded) {
                                  Navigator.pop(context, {
                                    'confirmed': true, 'finalTotal': displayTotal, 'paymentMethod': _selectedPaymentMethod,
                                    'isSplitPayment': _isSplitPayment, 'splitCashAmount': displayTotal - _splitQrisAmount, 'splitQrisAmount': _splitQrisAmount,
                                    'voucherProgramId': null,
                                    'isMember': isMember, 'memberId': _selectedMember?.id, 'memberPhone': _selectedMember?.phoneNumber,
                                    'voucherCode': voucherApplied ? voucherController.text : null,
                                    'isPosVoucher': voucherApplied ? isPosVoucher : false,
                                  });
                                } else {
                                  _showTopError(context, 'Uang yang diterima masih kurang');
                                }
                              },
                              child: Text('OK', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (isMember && _selectedMember != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('Simpan ke Tagihan (Open Bill)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange.shade800,
                            side: BorderSide(color: Colors.orange.shade800),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(context, {
                              'chargeToTab': true,
                              'memberId': _selectedMember!.id,
                              'memberName': _selectedMember!.name,
                              'memberPhone': _selectedMember!.phoneNumber,
                            });
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // HIDDEN: Recommendation feature UI hidden but backend kept for thesis documentation
            // Right side: Recommendations
            // ignore: dead_code
            if (false && widget.recommendations.isNotEmpty) ...[
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: RecommendationListWidget(
                  recommendations: widget.recommendations,
                  menuItems: widget.menuItems,
                  onRecommendationTap: (itemName) {
                    // Add the recommended item to the order
                    widget.onAddRecommendedItem(itemName, 1); // Add 1 quantity
                    widget.getTotal(); // Recalculate total in controller
                    _updateTotal(); // Update the dialog's total display

                    // Show confirmation snackbar
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ $itemName ditambahkan ke pesanan'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dialog for confirming self-orders from Member's app
class _SelfOrderConfirmationDialog extends StatefulWidget {
  final SelfOrder selfOrder;
  final int totalHarga;
  final bool isTakeAway;
  final int biayaBungkus;
  final TextEditingController customerNameController;
  final TextEditingController uangYangDiterimaController;
  final List<Recommendation> recommendations;
  final List<PesananObject> pesananList;
  final Function(String, int) onAddRecommendedItem;
  final Function() getTotal;
  final List<String> menuItems;

  const _SelfOrderConfirmationDialog({
    required this.selfOrder,
    required this.totalHarga,
    required this.isTakeAway,
    required this.biayaBungkus,
    required this.customerNameController,
    required this.uangYangDiterimaController,
    required this.recommendations,
    required this.pesananList,
    required this.onAddRecommendedItem,
    required this.getTotal,
    this.menuItems = const [],
  });

  @override
  _SelfOrderConfirmationDialogState createState() =>
      _SelfOrderConfirmationDialogState();
}

class _SelfOrderConfirmationDialogState
    extends State<_SelfOrderConfirmationDialog> {
  bool applyPromo = false;
  TextEditingController voucherController = TextEditingController();
  String? voucherName;
  int voucherValue = 0;
  bool voucherApplied = false;
  String? voucherError;
  bool isValidatingVoucher = false;
  bool isPosVoucher = false;
  late int currentTotal;
  List<Member> _members = [];
  Member? _selectedMember;
  String? _selectedPaymentMethod;
  bool _isSplitPayment = false;
  int _splitQrisAmount = 0;
  TextEditingController _splitQrisController = TextEditingController();
  List<Map<String, dynamic>> _activePrograms = [];
  String? _selectedProgramId;
  TextEditingController _programNominalController = TextEditingController();
  int _programNominal = 0;
  String? _programExtraPaymentMethod;
  bool _isProgramExtraSplit = false;
  TextEditingController _programExtraQrisController = TextEditingController();
  int _programExtraQrisAmount = 0;

  late FocusNode uangFocusNode;
  late FocusNode voucherFocusNode;

  @override
  void initState() {
    super.initState();
    uangFocusNode = FocusNode();
    voucherFocusNode = FocusNode();
    currentTotal = widget.totalHarga;
    _loadMembers();
    _loadPrograms();
    
    // Pre-fill customer name from self-order
    widget.customerNameController.text = widget.selfOrder.namaCustomer;
  }

  Future<void> _loadPrograms() async {
    final programs = await VoucherProgramService.getActivePrograms();
    if (mounted) {
      setState(() {
        _activePrograms = programs;
      });
    }
  }

  @override
  void dispose() {
    uangFocusNode.dispose();
    voucherFocusNode.dispose();
    _splitQrisController.dispose();
    _programNominalController.dispose();
    _programExtraQrisController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final members = await MemberService.instance.getCachedMembers();
    setState(() {
      _members = members;
      // Try to find matching member by memberId
      _selectedMember = _members.cast<Member?>().firstWhere(
        (m) => m?.id == widget.selfOrder.memberId,
        orElse: () => null,
      );
      if (_selectedMember != null) {
        widget.customerNameController.text = _selectedMember!.name;
      }
    });
  }

  void _updateTotal() {
    setState(() {
      int subtotal =
          widget.pesananList.fold(0, (acc, order) => acc + order.subtotal);
      int totalTakeAway = widget.pesananList.fold(
        0,
        (acc, order) => acc + order.takeAwayQuantity,
      );
      currentTotal = subtotal + (totalTakeAway * widget.biayaBungkus);
    });
  }

  Future<void> _validateAndApplyVoucher() async {
    if (voucherController.text.isEmpty) return;

    setState(() {
      isValidatingVoucher = true;
      voucherError = null;
    });

    final result = await OrderConfirmationService._validateVoucher(
        voucherController.text, currentTotal);

    setState(() {
      isValidatingVoucher = false;
      if (result?['success'] == true) {
        voucherApplied = true;
        voucherName = result!['voucherName'];
        voucherValue = result['value'] ?? 0;
        isPosVoucher = result['isPosVoucher'] ?? false;
      } else {
        voucherError = result?['error'] ?? 'Voucher tidak valid';
        if (result?['isSnackbarError'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(voucherError!),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    int displayTotal = currentTotal - voucherValue;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.smartphone, color: Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Text(
                'Pesanan Mandiri',
                style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.selfOrder.displayShortCode,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        height: applyPromo
            ? (voucherApplied ? 500 : 470)
            : (widget.isTakeAway ? 400 : 370),
        width: widget.recommendations.isNotEmpty ? 700 : 420,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: widget.recommendations.isNotEmpty ? 6 : 1,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order summary card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Member: ${widget.selfOrder.memberName}',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${widget.pesananList.length} item',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...widget.pesananList.map((item) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.namaPesanan} x${item.totalQuantity}',
                                        style: GoogleFonts.poppins(fontSize: 13),
                                      ),
                                    ),
                                    Text(
                                      'Rp ${NumberFormat.decimalPattern().format(item.subtotal).replaceAll(',', '.')}',
                                      style: GoogleFonts.poppins(fontSize: 13),
                                    ),
                                  ],
                                ),
                              )),
                          if (widget.selfOrder.takeAwayFee > 0) ...[
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Biaya Bungkus',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13, color: Colors.grey.shade600),
                                ),
                                Text(
                                  'Rp ${NumberFormat.decimalPattern().format(widget.selfOrder.takeAwayFee).replaceAll(',', '.')}',
                                  style: GoogleFonts.poppins(fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Total display
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Total: ',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (voucherApplied && voucherValue > 0) ...[
                          Text(
                            'Rp ${NumberFormat.decimalPattern().format(currentTotal).replaceAll(',', '.')}',
                            style: GoogleFonts.poppins(
                              color: Colors.grey,
                              fontSize: 14,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          'Rp ${NumberFormat.decimalPattern().format(displayTotal).replaceAll(',', '.')}',
                          style: GoogleFonts.poppins(
                            color:
                                voucherApplied ? Colors.green : const Color(0xFF2E7D32),
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Promo toggle
                    Row(
                      children: [
                        Switch(
                          value: applyPromo,
                          activeColor: const Color(0xFF2E7D32),
                          onChanged: (value) {
                            setState(() {
                              applyPromo = value;
                              if (!value) {
                                voucherApplied = false;
                                voucherValue = 0;
                                voucherController.clear();
                                voucherError = null;
                              }
                            });
                          },
                        ),
                        Text(
                          'Gunakan Promo/Voucher',
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                      ],
                    ),

                    // Voucher input
                    if (applyPromo) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: voucherController,
                              focusNode: voucherFocusNode,
                              decoration: InputDecoration(
                                labelText: 'Kode Voucher',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                errorText: voucherError,
                                suffixIcon: isValidatingVoucher
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              enabled: !voucherApplied,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed:
                                voucherApplied ? null : _validateAndApplyVoucher,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                            child: Text(voucherApplied ? 'Applied' : 'Apply'),
                          ),
                        ],
                      ),
                      if (voucherApplied) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.green.shade700, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                '$voucherName - Diskon Rp ${NumberFormat.decimalPattern().format(voucherValue).replaceAll(',', '.')}',
                                style: GoogleFonts.poppins(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),

                    // Payment method selection
                    Text(
                      'Metode Pembayaran',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Cash', 'QRIS', 'Online', 'Cash + QRIS', 'Program'].map((method) {
                        final isSelected = _selectedPaymentMethod == method;
                        return ChoiceChip(
                          label: Text(method),
                          selected: isSelected,
                          selectedColor: const Color(0xFFC8E6C9),
                          labelStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? const Color(0xFF2E7D32) : Colors.black87,
                          ),
                          onSelected: (selected) {
                            setState(() {
                              _selectedPaymentMethod = selected ? method : null;
                              if (selected && method == 'Cash + QRIS') {
                                _isSplitPayment = true;
                                widget.uangYangDiterimaController.clear();
                                _splitQrisController.clear();
                                _splitQrisAmount = 0;
                              } else {
                                _isSplitPayment = false;
                                if (selected && method != 'Cash') {
                                  final format = NumberFormat("#,###", "id_ID");
                                  widget.uangYangDiterimaController.text =
                                      format.format(displayTotal);
                                } else if (selected && method == 'Cash') {
                                  widget.uangYangDiterimaController.clear();
                                }
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (_isSplitPayment) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _splitQrisController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                TextInputFormatter.withFunction((oldValue, newValue) {
                                  final plainNumber = newValue.text.replaceAll('.', '');
                                  if (plainNumber.isEmpty) return newValue;
                                  final format = NumberFormat("#,###", "id_ID");
                                  final newText = format.format(int.parse(plainNumber));
                                  return newValue.copyWith(
                                    text: newText,
                                    selection: TextSelection.collapsed(offset: newText.length),
                                  );
                                }),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Jumlah QRIS (Rp)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _splitQrisAmount = int.tryParse(val.replaceAll('.', '')) ?? 0;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Sisa Cash:', style: GoogleFonts.poppins(fontSize: 11, color: Colors.blue.shade700)),
                                  Text(
                                    'Rp ${NumberFormat("#,###", "id_ID").format((displayTotal - _splitQrisAmount).clamp(0, displayTotal))}',
                                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_selectedPaymentMethod == 'Program' && _activePrograms.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedProgramId,
                        items: _activePrograms.map((p) {
                          return DropdownMenuItem<String>(
                            value: p['id'],
                            child: Text('${p['programName']} (${p['institutionName']})'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedProgramId = val;
                            if (val != null) {
                              final prog = _activePrograms.firstWhere((p) => p['id'] == val, orElse: () => {});
                              final defNominal = ((prog['defaultNominal'] ?? 0) as num).toInt();
                              _programNominal = defNominal;
                              _programNominalController.text = defNominal > 0 ? NumberFormat('#,###', 'id_ID').format(defNominal) : '';
                              _programExtraPaymentMethod = null;
                              _isProgramExtraSplit = false;
                              _programExtraQrisAmount = 0;
                              _programExtraQrisController.clear();
                              widget.uangYangDiterimaController.clear();
                            }
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Pilih Program Voucher',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                    // ─── PROGRAM PAYMENT SECTION ───
                    if (_selectedPaymentMethod == 'Program' && _selectedProgramId != null) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _programNominalController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final plain = newValue.text.replaceAll('.', '');
                            if (plain.isEmpty) return newValue;
                            final t = NumberFormat('#,###', 'id_ID').format(int.parse(plain));
                            return newValue.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length));
                          }),
                        ],
                        decoration: InputDecoration(labelText: 'Nominal Voucher (Rp)', helperText: 'Jumlah yang ditanggung program', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                        onChanged: (val) {
                          setState(() {
                            _programNominal = int.tryParse(val.replaceAll('.', '')) ?? 0;
                            _programExtraPaymentMethod = null; _isProgramExtraSplit = false;
                            _programExtraQrisAmount = 0; _programExtraQrisController.clear();
                            widget.uangYangDiterimaController.clear();
                          });
                        },
                      ),
                      Builder(builder: (ctx) {
                        final remaining = displayTotal - _programNominal;
                        if (remaining <= 0) {
                          return Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 16), const SizedBox(width: 6),
                            Text('Voucher menutupi seluruh tagihan', style: GoogleFonts.poppins(fontSize: 12, color: Colors.green.shade700)),
                          ]));
                        }
                        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.shade200)),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text('Sisa yang harus dibayar:', style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange.shade800)),
                              Text('Rp ${NumberFormat("#,###", "id_ID").format(remaining)}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                            ]),
                          ),
                          const SizedBox(height: 10),
                          Text('Metode Pembayaran Sisa', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, runSpacing: 8, children: ['Cash', 'QRIS', 'Cash + QRIS'].map((m) {
                            final isSel = _programExtraPaymentMethod == m;
                            return ChoiceChip(
                              label: Text(m, style: GoogleFonts.poppins(fontSize: 12)), selected: isSel,
                              selectedColor: const Color(0xFFC8E6C9),
                              labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: isSel ? FontWeight.w600 : FontWeight.w400, color: isSel ? const Color(0xFF2E7D32) : Colors.black87),
                              onSelected: (sel) {
                                setState(() {
                                  _programExtraPaymentMethod = sel ? m : null; _isProgramExtraSplit = sel && m == 'Cash + QRIS';
                                  _programExtraQrisAmount = 0; _programExtraQrisController.clear();
                                  if (sel && m == 'QRIS') { widget.uangYangDiterimaController.text = NumberFormat('#,###', 'id_ID').format(remaining); }
                                  else { widget.uangYangDiterimaController.clear(); }
                                });
                              },
                            );
                          }).toList()),
                          if (_isProgramExtraSplit) ...[
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: TextField(controller: _programExtraQrisController, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), TextInputFormatter.withFunction((o, n) { final plain = n.text.replaceAll('.',''); if (plain.isEmpty) return n; final t = NumberFormat('#,###','id_ID').format(int.parse(plain)); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); })], decoration: InputDecoration(labelText: 'Jumlah QRIS (Rp)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(4))), onChanged: (val) => setState(() => _programExtraQrisAmount = int.tryParse(val.replaceAll('.','')) ?? 0))),
                              const SizedBox(width: 12),
                              Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue.shade200)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Sisa Cash:', style: GoogleFonts.poppins(fontSize: 11, color: Colors.blue.shade700)), Text('Rp ${NumberFormat("#,###","id_ID").format((remaining - _programExtraQrisAmount).clamp(0, remaining))}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade900))]))),
                            ]),
                          ],
                          if (_programExtraPaymentMethod != null && _programExtraPaymentMethod != 'QRIS') ...[
                            const SizedBox(height: 10),
                            TextField(controller: widget.uangYangDiterimaController, focusNode: uangFocusNode, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), TextInputFormatter.withFunction((o, n) { final plain = n.text.replaceAll('.',''); if (plain.isEmpty) return n; final t = NumberFormat('#,###','id_ID').format(int.parse(plain)); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); })], decoration: InputDecoration(labelText: _isProgramExtraSplit ? 'Cash Diterima (Rp)' : 'Uang Diterima (Rp)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                            Builder(builder: (ctx) {
                              final cashReceived = int.tryParse(widget.uangYangDiterimaController.text.replaceAll('.', '')) ?? 0;
                              final cashNeeded = _isProgramExtraSplit ? (remaining - _programExtraQrisAmount).clamp(0, remaining) : remaining;
                              final change = cashReceived - cashNeeded;
                              if (change <= 0) return const SizedBox.shrink();
                              return Padding(padding: const EdgeInsets.only(top: 6), child: Text('Kembalian: Rp ${NumberFormat("#,###","id_ID").format(change)}', style: GoogleFonts.poppins(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.w600)));
                            }),
                          ],
                        ]);
                      }),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, null), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: BorderSide(color: Colors.grey.shade400), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey.shade700)))),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          onPressed: () {
                            if (_programNominal <= 0) { _showTopError(context, 'Masukkan nominal voucher'); return; }
                            final remaining = displayTotal - _programNominal;
                            int extraQris = 0;
                            if (remaining > 0) {
                              if (_programExtraPaymentMethod == null) { _showTopError(context, 'Pilih metode pembayaran sisa'); return; }
                              if (_isProgramExtraSplit) {
                                if (_programExtraQrisAmount <= 0 || _programExtraQrisAmount >= remaining) { _showTopError(context, 'Jumlah QRIS tidak valid'); return; }
                                extraQris = _programExtraQrisAmount;
                                final cashReceived = int.tryParse(widget.uangYangDiterimaController.text.replaceAll('.','')) ?? 0;
                                if (cashReceived < remaining - extraQris) { _showTopError(context, 'Cash yang diterima kurang'); return; }
                              } else if (_programExtraPaymentMethod == 'Cash') {
                                final cashReceived = int.tryParse(widget.uangYangDiterimaController.text.replaceAll('.','')) ?? 0;
                                if (cashReceived < remaining) { _showTopError(context, 'Cash yang diterima kurang'); return; }
                              }
                            }
                            Navigator.pop(context, {
                              'confirmed': true, 'finalTotal': displayTotal, 'paymentMethod': 'Program',
                              'voucherProgramId': _selectedProgramId, 'programNominal': _programNominal,
                              'programExtraPaymentMethod': remaining > 0 ? _programExtraPaymentMethod : null,
                              'programExtraSplitQrisAmount': extraQris,
                              'isMember': _selectedMember != null, 'memberId': _selectedMember?.id ?? widget.selfOrder.userId,
                              'memberPhone': _selectedMember?.phoneNumber,
                              'voucherCode': voucherApplied ? voucherController.text : null,
                              'isPosVoucher': voucherApplied ? isPosVoucher : false,
                            });
                          },
                          child: Text('Konfirmasi Pembayaran', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        )),
                      ]),
                    ],
                    // ─── NORMAL PAYMENT SECTION ───
                    if (_selectedPaymentMethod != 'Program') ...[
                      const SizedBox(height: 16),
                      TextField(
                        focusNode: uangFocusNode, keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            if (newValue.text.isEmpty) return newValue;
                            final plainNumber = newValue.text.replaceAll('.', '');
                            if (plainNumber.isEmpty) return newValue;
                            final format = NumberFormat("#,###", "id_ID");
                            final newText = format.format(int.parse(plainNumber));
                            return TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length));
                          }),
                        ],
                        controller: widget.uangYangDiterimaController,
                        decoration: InputDecoration(labelText: 'Uang yang diterima (Rp)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      ),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, null), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: BorderSide(color: Colors.grey.shade400), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey.shade700)))),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          onPressed: () {
                            if (_selectedPaymentMethod == null) { _showTopError(context, 'Pilih metode pembayaran'); return; }
                            final inputText = widget.uangYangDiterimaController.text.replaceAll('.', '');
                            if (inputText.isEmpty) { _showTopError(context, 'Masukkan uang yang diterima'); return; }
                            int uangYangDiterima = int.parse(inputText);
                            final cashNeeded = _isSplitPayment ? displayTotal - _splitQrisAmount : displayTotal;
                            if (uangYangDiterima >= cashNeeded) {
                              Navigator.pop(context, {
                                'confirmed': true, 'finalTotal': displayTotal, 'paymentMethod': _selectedPaymentMethod,
                                'isSplitPayment': _isSplitPayment, 'splitCashAmount': displayTotal - _splitQrisAmount, 'splitQrisAmount': _splitQrisAmount,
                                'voucherProgramId': null,
                                'isMember': _selectedMember != null, 'memberId': _selectedMember?.id ?? widget.selfOrder.userId,
                                'memberPhone': _selectedMember?.phoneNumber,
                                'voucherCode': voucherApplied ? voucherController.text : null,
                                'isPosVoucher': voucherApplied ? isPosVoucher : false,
                              });
                            } else {
                              _showTopError(context, 'Uang yang diterima masih kurang');
                            }
                          },
                          child: Text('Konfirmasi Pembayaran', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        )),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
            // HIDDEN: Recommendation feature UI hidden but backend kept for thesis documentation
            // Right side: Recommendations
            // ignore: dead_code
            if (false && widget.recommendations.isNotEmpty) ...[
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: RecommendationListWidget(
                  recommendations: widget.recommendations,
                  menuItems: widget.menuItems,
                  onRecommendationTap: (itemName) {
                    widget.onAddRecommendedItem(itemName, 1);
                    widget.getTotal();
                    _updateTotal();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$itemName ditambahkan ke pesanan'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dialog for settling an open bill
class _OpenBillSettlementDialog extends StatefulWidget {
  final OpenBill openBill;
  final bool printerIsConnected;
  final List<PesananObject> aggregatedItems;
  final int totalTakeAwayFee;
  final TextEditingController uangYangDiterimaController;

  const _OpenBillSettlementDialog({
    required this.openBill,
    required this.printerIsConnected,
    required this.aggregatedItems,
    required this.totalTakeAwayFee,
    required this.uangYangDiterimaController,
  });

  @override
  _OpenBillSettlementDialogState createState() => _OpenBillSettlementDialogState();
}

class _OpenBillSettlementDialogState extends State<_OpenBillSettlementDialog> {
  bool applyPromo = false;
  TextEditingController voucherController = TextEditingController();
  String? voucherName;
  int voucherValue = 0;
  bool voucherApplied = false;
  String? voucherError;
  bool isValidatingVoucher = false;
  bool isPosVoucher = false;
  String? _selectedPaymentMethod;
  List<Map<String, dynamic>> _activePrograms = [];
  String? _selectedProgramId;
  TextEditingController _programNominalController = TextEditingController();
  int _programNominal = 0;
  String? _programExtraPaymentMethod;
  bool _isProgramExtraSplit = false;
  TextEditingController _programExtraQrisController = TextEditingController();
  int _programExtraQrisAmount = 0;

  late FocusNode uangFocusNode;
  late FocusNode voucherFocusNode;

  @override
  void initState() {
    super.initState();
    uangFocusNode = FocusNode();
    voucherFocusNode = FocusNode();
    widget.uangYangDiterimaController.clear();
    _loadPrograms();
  }

  Future<void> _loadPrograms() async {
    final programs = await VoucherProgramService.getActivePrograms();
    if (mounted) {
      setState(() {
        _activePrograms = programs;
      });
    }
  }

  bool _isSplitPayment = false;
  int _splitQrisAmount = 0;
  TextEditingController _splitQrisController = TextEditingController();

  @override
  void dispose() {
    uangFocusNode.dispose();
    voucherFocusNode.dispose();
    _splitQrisController.dispose();
    _programNominalController.dispose();
    _programExtraQrisController.dispose();
    super.dispose();
  }

  Future<void> _validateAndApplyVoucher() async {
    if (voucherController.text.isEmpty) return;

    setState(() {
      isValidatingVoucher = true;
      voucherError = null;
    });

    final result = await OrderConfirmationService._validateVoucher(
        voucherController.text, widget.openBill.totalAmount + widget.totalTakeAwayFee);

    setState(() {
      isValidatingVoucher = false;
      if (result?['error'] != null) {
        voucherError = result!['error'];
        voucherApplied = false;
      } else if (result != null) {
        voucherApplied = true;
        voucherName = result['voucherName'];
        voucherValue = result['value'] ?? 0;
        isPosVoucher = result['isPosVoucher'] ?? false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    int baseTotal = widget.openBill.totalAmount + widget.totalTakeAwayFee;
    int displayTotal = baseTotal - voucherValue;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.receipt_long, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'Selesaikan Tagihan',
                style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.printerIsConnected ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.openBill.memberName,
            style: GoogleFonts.poppins(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Order Items List
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    ...widget.aggregatedItems.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.namaPesanan} x${item.totalQuantity}',
                                  style: GoogleFonts.poppins(fontSize: 13),
                                ),
                              ),
                              Text(
                                'Rp ${NumberFormat.decimalPattern().format(item.subtotal).replaceAll(',', '.')}',
                                style: GoogleFonts.poppins(fontSize: 13),
                              ),
                            ],
                          ),
                        )),
                    if (widget.totalTakeAwayFee > 0) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Biaya Bungkus',
                            style: GoogleFonts.poppins(
                                fontSize: 13, color: Colors.grey.shade600),
                          ),
                          Text(
                            'Rp ${NumberFormat.decimalPattern().format(widget.totalTakeAwayFee).replaceAll(',', '.')}',
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Total
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Total Tagihan: ',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  if (voucherApplied) ...[
                    Text(
                      'Rp ${NumberFormat.decimalPattern().format(baseTotal).replaceAll(',', '.')}',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey,
                          decoration: TextDecoration.lineThrough),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    'Rp ${NumberFormat.decimalPattern().format(displayTotal).replaceAll(',', '.')}',
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Voucher input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: voucherController,
                      focusNode: voucherFocusNode,
                      decoration: InputDecoration(
                        labelText: 'Kode Voucher',
                        border: const OutlineInputBorder(),
                        errorText: voucherError,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _validateAndApplyVoucher,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    child: const Text('Apply'),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              Text(
                'Metode Pembayaran',
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Cash', 'QRIS', 'Online', 'Cash + QRIS', 'Program'].map((method) {
                  final isSelected = _selectedPaymentMethod == method;
                  return ChoiceChip(
                    label: Text(method),
                    selected: isSelected,
                    selectedColor: const Color(0xFFC8E6C9),
                    labelStyle: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? const Color(0xFF2E7D32) : Colors.black87,
                    ),
                    onSelected: (val) {
                      setState(() {
                        _selectedPaymentMethod = val ? method : null;
                        if (val && method == 'Cash + QRIS') {
                          _isSplitPayment = true;
                          widget.uangYangDiterimaController.clear();
                          _splitQrisController.clear();
                          _splitQrisAmount = 0;
                        } else {
                          _isSplitPayment = false;
                          if (val && method != 'Cash') {
                            widget.uangYangDiterimaController.text =
                                NumberFormat("#,###", "id_ID").format(displayTotal);
                          } else if (val && method == 'Cash') {
                            widget.uangYangDiterimaController.clear();
                          }
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              if (_isSplitPayment) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _splitQrisController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final plainNumber = newValue.text.replaceAll('.', '');
                            if (plainNumber.isEmpty) return newValue;
                            final format = NumberFormat("#,###", "id_ID");
                            final newText = format.format(int.parse(plainNumber));
                            return newValue.copyWith(
                              text: newText,
                              selection: TextSelection.collapsed(offset: newText.length),
                            );
                          }),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Jumlah QRIS (Rp)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _splitQrisAmount = int.tryParse(val.replaceAll('.', '')) ?? 0;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sisa Cash:', style: GoogleFonts.poppins(fontSize: 11, color: Colors.blue.shade700)),
                            Text(
                              'Rp ${NumberFormat("#,###", "id_ID").format((displayTotal - _splitQrisAmount).clamp(0, displayTotal))}',
                              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_selectedPaymentMethod == 'Program' && _activePrograms.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedProgramId,
                  items: _activePrograms.map((p) {
                    return DropdownMenuItem<String>(
                      value: p['id'],
                      child: Text('${p['programName']} (${p['institutionName']})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedProgramId = val;
                      if (val != null) {
                        final prog = _activePrograms.firstWhere((p) => p['id'] == val, orElse: () => {});
                        final defNominal = ((prog['defaultNominal'] ?? 0) as num).toInt();
                        _programNominal = defNominal;
                        _programNominalController.text = defNominal > 0 ? NumberFormat('#,###', 'id_ID').format(defNominal) : '';
                        _programExtraPaymentMethod = null;
                        _isProgramExtraSplit = false;
                        _programExtraQrisAmount = 0;
                        _programExtraQrisController.clear();
                        widget.uangYangDiterimaController.clear();
                      }
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Pilih Program Voucher',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ],
              
              // ─── PROGRAM PAYMENT SECTION ───
              if (_selectedPaymentMethod == 'Program' && _selectedProgramId != null) ...[  
                const SizedBox(height: 12),
                TextField(
                  controller: _programNominalController, keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), TextInputFormatter.withFunction((o, n) { final plain = n.text.replaceAll('.',''); if (plain.isEmpty) return n; final t = NumberFormat('#,###','id_ID').format(int.parse(plain)); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); })],
                  decoration: InputDecoration(labelText: 'Nominal Voucher (Rp)', helperText: 'Jumlah yang ditanggung program', border: const OutlineInputBorder()),
                  onChanged: (val) {
                    setState(() {
                      _programNominal = int.tryParse(val.replaceAll('.', '')) ?? 0;
                      _programExtraPaymentMethod = null; _isProgramExtraSplit = false;
                      _programExtraQrisAmount = 0; _programExtraQrisController.clear();
                      widget.uangYangDiterimaController.clear();
                    });
                  },
                ),
                Builder(builder: (ctx) {
                  final remaining = displayTotal - _programNominal;
                  if (remaining <= 0) {
                    return Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [const Icon(Icons.check_circle, color: Colors.green, size: 16), const SizedBox(width: 6), Text('Voucher menutupi seluruh tagihan', style: GoogleFonts.poppins(fontSize: 12, color: Colors.green.shade700))]));
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.shade200)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Sisa:', style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange.shade800)), Text('Rp ${NumberFormat("#,###","id_ID").format(remaining)}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade900))])),
                    const SizedBox(height: 10),
                    Text('Metode Pembayaran Sisa', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: ['Cash', 'QRIS', 'Cash + QRIS'].map((m) {
                      final isSel = _programExtraPaymentMethod == m;
                      return ChoiceChip(label: Text(m, style: GoogleFonts.poppins(fontSize: 12)), selected: isSel, selectedColor: const Color(0xFFC8E6C9), labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: isSel ? FontWeight.w600 : FontWeight.w400, color: isSel ? const Color(0xFF2E7D32) : Colors.black87),
                        onSelected: (sel) { setState(() { _programExtraPaymentMethod = sel ? m : null; _isProgramExtraSplit = sel && m == 'Cash + QRIS'; _programExtraQrisAmount = 0; _programExtraQrisController.clear(); if (sel && m == 'QRIS') { widget.uangYangDiterimaController.text = NumberFormat('#,###','id_ID').format(remaining); } else { widget.uangYangDiterimaController.clear(); } }); });
                    }).toList()),
                    if (_isProgramExtraSplit) ...[const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: _programExtraQrisController, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), TextInputFormatter.withFunction((o, n) { final plain = n.text.replaceAll('.',''); if (plain.isEmpty) return n; final t = NumberFormat('#,###','id_ID').format(int.parse(plain)); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); })], decoration: const InputDecoration(labelText: 'Jumlah QRIS (Rp)', border: OutlineInputBorder()), onChanged: (val) => setState(() => _programExtraQrisAmount = int.tryParse(val.replaceAll('.','')) ?? 0))), const SizedBox(width: 12), Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue.shade200)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Sisa Cash:', style: GoogleFonts.poppins(fontSize: 11, color: Colors.blue.shade700)), Text('Rp ${NumberFormat("#,###","id_ID").format((remaining - _programExtraQrisAmount).clamp(0, remaining))}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade900))])))])],
                    if (_programExtraPaymentMethod != null && _programExtraPaymentMethod != 'QRIS') ...[const SizedBox(height: 10), TextField(controller: widget.uangYangDiterimaController, focusNode: uangFocusNode, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), TextInputFormatter.withFunction((o, n) { final plain = n.text.replaceAll('.',''); if (plain.isEmpty) return n; final t = NumberFormat('#,###','id_ID').format(int.parse(plain)); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); })], decoration: InputDecoration(labelText: _isProgramExtraSplit ? 'Cash Diterima (Rp)' : 'Uang Diterima (Rp)', border: const OutlineInputBorder(), prefixText: 'Rp ')), Builder(builder: (ctx) { final cashReceived = int.tryParse(widget.uangYangDiterimaController.text.replaceAll('.', '')) ?? 0; final cashNeeded = _isProgramExtraSplit ? (remaining - _programExtraQrisAmount).clamp(0, remaining) : remaining; final change = cashReceived - cashNeeded; if (change <= 0) return const SizedBox.shrink(); return Padding(padding: const EdgeInsets.only(top: 6), child: Text('Kembalian: Rp ${NumberFormat("#,###","id_ID").format(change)}', style: GoogleFonts.poppins(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.w600))); })],
                  ]);
                }),
              ],
              // ─── NORMAL PAYMENT SECTION ───
              if (_selectedPaymentMethod != 'Program') ...[  
                const SizedBox(height: 16),
                TextField(
                  controller: widget.uangYangDiterimaController, focusNode: uangFocusNode, keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, TextInputFormatter.withFunction((oldValue, newValue) { if (newValue.text.isEmpty) return newValue; final intValue = int.parse(newValue.text); final newText = NumberFormat('#,###', 'id_ID').format(intValue); return TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length)); })],
                  decoration: const InputDecoration(labelText: 'Uang yang Diterima', border: OutlineInputBorder(), prefixText: 'Rp '),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedPaymentMethod == null) { _showTopError(context, 'Pilih metode pembayaran'); return; }
            if (_selectedPaymentMethod == 'Program') {
              if (_selectedProgramId == null) { _showTopError(context, 'Pilih program voucher'); return; }
              if (_programNominal <= 0) { _showTopError(context, 'Masukkan nominal voucher'); return; }
              final remaining = displayTotal - _programNominal;
              int extraQris = 0;
              if (remaining > 0) {
                if (_programExtraPaymentMethod == null) { _showTopError(context, 'Pilih metode pembayaran sisa'); return; }
                if (_isProgramExtraSplit) {
                  if (_programExtraQrisAmount <= 0 || _programExtraQrisAmount >= remaining) { _showTopError(context, 'Jumlah QRIS tidak valid'); return; }
                  extraQris = _programExtraQrisAmount;
                  final cashReceived = int.tryParse(widget.uangYangDiterimaController.text.replaceAll('.','')) ?? 0;
                  if (cashReceived < remaining - extraQris) { _showTopError(context, 'Cash yang diterima kurang'); return; }
                } else if (_programExtraPaymentMethod == 'Cash') {
                  final cashReceived = int.tryParse(widget.uangYangDiterimaController.text.replaceAll('.','')) ?? 0;
                  if (cashReceived < remaining) { _showTopError(context, 'Cash yang diterima kurang'); return; }
                }
              }
              Navigator.pop(context, {
                'confirmed': true, 'finalTotal': displayTotal, 'paymentMethod': 'Program',
                'isSplitPayment': false, 'splitCashAmount': 0, 'splitQrisAmount': 0,
                'voucherProgramId': _selectedProgramId, 'programNominal': _programNominal,
                'programExtraPaymentMethod': remaining > 0 ? _programExtraPaymentMethod : null,
                'programExtraSplitQrisAmount': extraQris,
                'voucherCode': voucherApplied ? voucherController.text : null, 'isPosVoucher': isPosVoucher,
              });
              return;
            }
            if (_isSplitPayment) { if (_splitQrisAmount <= 0 || _splitQrisAmount >= displayTotal) { _showTopError(context, 'Jumlah QRIS tidak valid'); return; } }
            final totalDiterima = int.tryParse(widget.uangYangDiterimaController.text.replaceAll('.', '')) ?? 0;
            final cashNeeded = _isSplitPayment ? displayTotal - _splitQrisAmount : displayTotal;
            if (totalDiterima < cashNeeded) { _showTopError(context, 'Uang kurang'); return; }
            Navigator.pop(context, {
              'confirmed': true, 'finalTotal': displayTotal, 'paymentMethod': _selectedPaymentMethod,
              'isSplitPayment': _isSplitPayment, 'splitCashAmount': displayTotal - _splitQrisAmount, 'splitQrisAmount': _splitQrisAmount,
              'voucherProgramId': null,
              'voucherCode': voucherApplied ? voucherController.text : null, 'isPosVoucher': isPosVoucher,
            });
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
          child: Text('PROSES BAYAR', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

void _showTopError(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  if (overlay == null) return;
  
  late OverlayEntry overlayEntry;
  overlayEntry = OverlayEntry(
    builder: (context) => SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 10, left: 20, right: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => overlayEntry.remove(),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  
  overlay.insert(overlayEntry);
  Future.delayed(const Duration(seconds: 4), () {
    if (overlayEntry.mounted) overlayEntry.remove();
  });
}
