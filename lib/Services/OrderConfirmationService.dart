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
import 'package:point_of_sales_app_v3/Widgets/RecommendationListWidget.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:point_of_sales_app_v3/Models/Member.dart';
import 'package:point_of_sales_app_v3/Services/MemberService.dart';

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
    required Future<void> Function({int discountAmount, int originalTotal})
        printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
    required Function(String, int)
        addRecommendedItem, // Add callback to add item
    List<String> menuItems = const [], // Available menu items for filtering recommendations
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
        );
      },
    );

    if (result != null && result['confirmed'] == true) {
      int finalTotal = result['finalTotal'] ?? totalHarga;
      String? appliedVoucherCode = result['voucherCode'];
      bool isMember = result['isMember'] ?? false;
      String? memberId = result['memberId'];

      await _processOrder(
        context: context,
        pesananList: pesananList,
        totalHarga: finalTotal,
        originalTotal: totalHarga,
        isTakeAway: isTakeAway,
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
    required Future<void> Function({int discountAmount, int originalTotal})
        printReceipt,
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

      await _processSelfOrder(
        context: context,
        selfOrder: selfOrder,
        pesananList: pesananList,
        totalHarga: finalTotal,
        originalTotal: totalHarga,
        isTakeAway: isTakeAway,
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
    required TextEditingController customerNameController,
    required TextEditingController uangYangDiterimaController,
    required int nomorBerikutnya,
    required Function() getTotal,
    required Future<void> Function({int discountAmount, int originalTotal})
        printReceipt,
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
  }) async {
    // Validate stock availability for all items
    final inventoryService = InventoryService();
    final firestore = FirebaseFirestore.instance;

    // Get all menu items to check their ingredients
    final menuSnapshot = await firestore
        .collection('Canteens')
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

    // Check availability for each item in the order
    for (var pesanan in pesananList) {
      final menu = menuMap[pesanan.namaPesanan];
      if (menu == null) continue;

      final availability = await inventoryService.checkMenuAvailability(
        menu,
        pesanan.totalQuantity,
      );

      if (!availability.isAvailable) {
        if (context.mounted) {
          // Revert status back to Unpaid on failure
          await SelfOrderService.instance.updateStatus(
              selfOrder.id, SelfOrderStatus.unpaid);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Stok tidak cukup untuk ${pesanan.namaPesanan}: ${availability.message}',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
        return;
      }
    }

    LoaderWidget.showLoaderDialog(context, message: "Memproses pesanan...");

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

    map['total'] = FieldValue.increment(totalHarga);
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
        fs.collection("DailyTransaction").doc(datenowFormatted);
    batch.set(dailyTransaction, map, SetOptions(merge: true));

    DocumentReference monthlyTransaction =
        fs.collection("MonthlyTransaction").doc(getMonth());
    batch.set(monthlyTransaction, map, SetOptions(merge: true));

    DocumentReference yearlyTransaction =
        fs.collection("YearlyTransaction").doc(getYear());
    batch.set(yearlyTransaction, map, SetOptions(merge: true));

    List<Map<String, dynamic>> orderItems = pesananList.map((order) {
      return {
        'namaPesanan': order.namaPesanan,
        'dineInQuantity': order.dineInQuantity,
        'takeAwayQuantity': order.takeAwayQuantity,
      };
    }).toList();

    mapStatus['customerNumber'] = nomorBerikutnya + 1;
    mapStatus['orderItems'] = orderItems;
    mapStatus['status'] = 'Serving';
    mapStatus['namaCustomer'] = customerNameController.text;
    mapStatus['total'] = totalHarga;
    mapStatus['isMember'] = isMember;
    mapStatus['selfOrderId'] = selfOrder.id;
    mapStatus['selfOrderShortCode'] = selfOrder.shortCode;
    if (memberId != null) {
      mapStatus['memberId'] = memberId;
    }
    if (memberPhone != null) {
      mapStatus['customerPhone'] = memberPhone;
    }
    mapStatus['waktuPengambilan'] = 'Tidak Memesan';
    mapStatus['waktuPesan'] = FieldValue.serverTimestamp();

    DocumentReference statusRef =
        fs.collection("Status").doc('${nomorBerikutnya + 1}');
    batch.set(statusRef, mapStatus);

    DocumentReference customerNumber =
        fs.collection("Canteens").doc('canteen375');
    batch.update(customerNumber, {'customerNumber': FieldValue.increment(1)});

    try {
      await batch.commit();

      // Deduct ingredients from inventory
      for (var pesanan in pesananList) {
        final menu = menuMap[pesanan.namaPesanan];
        if (menu != null && menu.ingredients.isNotEmpty) {
          await inventoryService.deductIngredients(menu, pesanan.totalQuantity);
        }
      }

      if (appliedVoucherCode != null) {
        _claimVoucherAsync(appliedVoucherCode, isPosVoucher);
      }

      // Update member points and competition records
      if (isMember && memberId != null) {
        _incrementMemberPoints(memberId, totalHarga);
        _updateCompetitionRecord(memberId, totalHarga);
        _processPeriodicCashbackCampaign(
            memberId, totalHarga, customerNameController.text);
      }

      // Mark the self-order as paid
      await SelfOrderService.instance.markAsPaid(selfOrder.id);

      await printReceipt(
          discountAmount: discountAmount, originalTotal: originalTotal);
      Navigator.pop(context);

      int uangYangDiterima =
          int.parse(uangYangDiterimaController.text.replaceAll('.', ''));

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
      );

      onOrderCompleted?.call();
    } catch (error) {
      Navigator.pop(context);
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
                      selfOrder.shortCode,
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
                        'Rp ${NumberFormat.decimalPattern().format(uangYangDiterima - totalHarga).replaceAll(',', '.')}',
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
  static Future<List<Recommendation>> _generateRecommendations(
      List<PesananObject> pesananList) async {
    try {
      final recommendationService = RecommendationService.instance;

      if (!recommendationService.isInitialized) {
        print('⚠️ Recommendation system not initialized yet');
        return [];
      }

      // Extract item names from the order
      final orderItems = pesananList.map((order) => order.namaPesanan).toList();

      print('🛒 Current order items: ${orderItems.join(", ")}');

      // Get recommendations
      final recommendations =
          await recommendationService.getRecommendations(orderItems);

      if (recommendations.isEmpty) {
        print('📭 No recommendations found for this order');
      } else {
        print('✨ ====== RECOMMENDATIONS ======');
        print('📊 Found ${recommendations.length} recommendations:');
        print('');

        for (int i = 0; i < recommendations.length; i++) {
          final rec = recommendations[i];
          print(
              '${i + 1}. ${rec.itemName} (${(rec.confidence * 100).toStringAsFixed(1)}% confidence)');
          print('   Based on: ${rec.basedOn.join(", ")}');
          print('');
        }
        print('================================');
      }

      return recommendations;
    } catch (e) {
      print('❌ Error generating recommendations: $e');
      return [];
    }
  }

  static Future<void> _processOrder({
    required BuildContext context,
    required List<PesananObject> pesananList,
    required int totalHarga,
    required int originalTotal,
    required bool isTakeAway,
    required TextEditingController customerNameController,
    required TextEditingController uangYangDiterimaController,
    required int nomorBerikutnya,
    required Function() getTotal,
    required Future<void> Function({int discountAmount, int originalTotal})
        printReceipt,
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
  }) async {
    // 🔍 STEP 1: Validate stock availability for all items
    final inventoryService = InventoryService();
    final firestore = FirebaseFirestore.instance;
    
    // Get all menu items to check their ingredients
    final menuSnapshot = await firestore
        .collection('Canteens')
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
    
    // Check availability for each item in the order
    for (var pesanan in pesananList) {
      final menu = menuMap[pesanan.namaPesanan];
      if (menu == null) continue;
      
      final availability = await inventoryService.checkMenuAvailability(
        menu,
        pesanan.totalQuantity,
      );
      
      if (!availability.isAvailable) {
        // Close loader and show error
        if (context.mounted) {
          Navigator.pop(context); // Close loader
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Stok tidak cukup untuk ${pesanan.namaPesanan}: ${availability.message}',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
        return; // Abort order
      }
    }
    
    LoaderWidget.showLoaderDialog(context, message: "Mohon tunggu...");

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

    map['total'] = FieldValue.increment(totalHarga);
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
        fs.collection("DailyTransaction").doc(datenowFormatted);
    batch.set(dailyTransaction, map, SetOptions(merge: true));

    DocumentReference monthlyTransaction =
        fs.collection("MonthlyTransaction").doc(getMonth());
    batch.set(monthlyTransaction, map, SetOptions(merge: true));

    DocumentReference yearlyTransaction =
        fs.collection("YearlyTransaction").doc(getYear());
    batch.set(yearlyTransaction, map, SetOptions(merge: true));

    List<Map<String, dynamic>> orderItems = pesananList.map((order) {
      return {
        'namaPesanan': order.namaPesanan,
        'dineInQuantity': order.dineInQuantity,
        'takeAwayQuantity': order.takeAwayQuantity,
      };
    }).toList();

    mapStatus['customerNumber'] = nomorBerikutnya + 1;
    mapStatus['orderItems'] = orderItems;
    mapStatus['status'] = 'Serving';
    mapStatus['namaCustomer'] = customerNameController.text;
    mapStatus['total'] = totalHarga;
    mapStatus['isMember'] = isMember;
    if (memberId != null) {
      mapStatus['memberId'] = memberId;
    }
    if (memberPhone != null) {
      mapStatus['customerPhone'] = memberPhone;
    }
    mapStatus['waktuPengambilan'] = 'Tidak Memesan';
    mapStatus['waktuPesan'] = FieldValue.serverTimestamp();

    DocumentReference statusRef =
        fs.collection("Status").doc('${nomorBerikutnya + 1}');
    batch.set(statusRef, mapStatus);

    DocumentReference customerNumber =
        fs.collection("Canteens").doc('canteen375');
    batch.update(customerNumber, {'customerNumber': FieldValue.increment(1)});

    try {
      await batch.commit();

      // 📦 STEP 2: Deduct ingredients from inventory
      for (var pesanan in pesananList) {
        final menu = menuMap[pesanan.namaPesanan];
        if (menu != null && menu.ingredients.isNotEmpty) {
          await inventoryService.deductIngredients(menu, pesanan.totalQuantity);
        }
      }

      if (appliedVoucherCode != null) {
        _claimVoucherAsync(appliedVoucherCode, isPosVoucher);
      }

      // 💳 STEP 3: Update member points and competition records
      if (isMember && memberId != null) {
        _incrementMemberPoints(memberId, totalHarga);
        _updateCompetitionRecord(memberId, totalHarga);
        _processPeriodicCashbackCampaign(memberId, totalHarga, customerNameController.text);
      }

      await printReceipt(
          discountAmount: discountAmount, originalTotal: originalTotal);
      Navigator.pop(context);

      int uangYangDiterima =
          int.parse(uangYangDiterimaController.text.replaceAll('.', ''));

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
      );
    } catch (error) {
      Navigator.pop(context);
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
                        'Rp ${NumberFormat.decimalPattern().format(uangYangDiterima - totalHarga)}',
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

  static void _claimVoucherAsync(String voucherCode, bool isPosVoucher) async {
    try {
      if (isPosVoucher) {
        FirebaseFirestore fs = FirebaseFirestore.instance;
        DocumentReference voucherRef =
            fs.collection("vouchers").doc(voucherCode);

        // Fetch document to get voucherGroupId
        DocumentSnapshot doc = await voucherRef.get();
        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          String? groupId = data['voucherGroupId'];

          await voucherRef.update({'status': 'CLAIMED'});

          if (groupId != null) {
            await fs.collection('voucherGroup').doc(groupId).update({
              'totalClaimed': FieldValue.increment(1),
            });
            print('📈 Incremented totalClaimed for group $groupId');
          }
        }
      } else {
        FirebaseFirestore eSantrenFs =
            FirebaseFirestore.instanceFor(app: Firebase.app('e-santren'));
        DocumentReference voucherRef =
            eSantrenFs.collection("vouchers").doc(voucherCode);
        await voucherRef.update({'isClaimed': true});
      }
      print('✅ Voucher $voucherCode claimed successfully');
    } catch (e) {
      print('❌ Failed to claim voucher $voucherCode: $e');
    }
  }

  static Future<Map<String, dynamic>?> _validateVoucher(
      String voucherCode, int currentTotal) async {
    try {
      FirebaseFirestore fs = FirebaseFirestore.instance;
      DocumentSnapshot doc =
          await fs.collection("vouchers").doc(voucherCode).get();

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
            await eSantrenFs.collection("vouchers").doc(voucherCode).get();
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
          await fs.collection("vouchers").doc(voucherCode).update({
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
      DocumentReference memberRef = fs.collection("Members").doc(memberId);

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
          fs.collection("competitionRecords").doc(monthDocId);

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
          .collection('voucherGroup')
          .where('isActive', isEqualTo: true)
          .where('type', isEqualTo: 'cashbackCampaign')
          .get();

      if (activeCampaigns.docs.isEmpty) return;

      // Fetch user's existing vouchers to check status and avoid composite index requirement
      QuerySnapshot userVouchers = await fs
          .collection('vouchers')
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

        await fs.collection('vouchers').doc(newVoucherId).set({
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
  }

  @override
  void dispose() {
    customerNameFocusNode.dispose();
    uangFocusNode.dispose();
    voucherFocusNode.dispose();
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
      title: Center(
        child: Text(
          'Konfirmasi Pesanan',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            fontSize: 18,
          ),
        ),
      ),
      content: SizedBox(
        height: applyPromo
            ? (voucherApplied ? 450 : 420)
            : (widget.isTakeAway ? 350 : 320),
        width: widget.recommendations.isNotEmpty ? 700 : 400,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left side: Order confirmation form
            Expanded(
              flex: widget.recommendations.isNotEmpty ? 6 : 1,
              child: SingleChildScrollView(
                child: Column(
                  children: [
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
                          if (textEditingValue.text == '') {
                            return const Iterable<Member>.empty();
                          }
                          return await MemberService.instance
                              .searchCachedMembers(textEditingValue.text);
                        },
                        onSelected: (Member selection) {
                          setState(() {
                            _selectedMember = selection;
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
                                _selectedMember = null;
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Cari Nama/HP Member',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4.0),
                              ),
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
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: TextField(
                            focusNode: uangFocusNode,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]')),
                              TextInputFormatter.withFunction(
                                  (oldValue, newValue) {
                                final plainNumber =
                                    newValue.text.replaceAll('.', '');
                                final format = NumberFormat("#,###", "id_ID");
                                final newText =
                                    format.format(int.parse(plainNumber));
                                return TextEditingValue(
                                  text: newText,
                                  selection: TextSelection.collapsed(
                                      offset: newText.length),
                                );
                              }),
                            ],
                            controller: widget.uangYangDiterimaController,
                            decoration: InputDecoration(
                              labelText: 'Uang yang diterima (Rp)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                            ),
                            onPressed: () {
                              int uangYangDiterima = int.parse(widget
                                  .uangYangDiterimaController.text
                                  .replaceAll('.', ''));
                              if (uangYangDiterima >= displayTotal) {
                                Navigator.pop(context, {
                                  'confirmed': true,
                                  'finalTotal': displayTotal,
                                  'isMember': isMember,
                                  'memberId': _selectedMember?.id,
                                  'memberPhone': _selectedMember?.phoneNumber,
                                  'voucherCode': voucherApplied
                                      ? voucherController.text
                                      : null,
                                  'isPosVoucher': voucherApplied ? isPosVoucher : false,
                                });
                              } else {
                                SnackBar snackBar = const SnackBar(
                                  content:
                                      Text('Uang yang diterima masih kurang'),
                                  backgroundColor: Colors.redAccent,
                                );
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(snackBar);
                              }
                            },
                            child: const Text('OK'),
                          ),
                        )
                      ],
                    ),
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

  late FocusNode uangFocusNode;
  late FocusNode voucherFocusNode;

  @override
  void initState() {
    super.initState();
    uangFocusNode = FocusNode();
    voucherFocusNode = FocusNode();
    currentTotal = widget.totalHarga;
    _loadMembers();
    
    // Pre-fill customer name from self-order
    widget.customerNameController.text = widget.selfOrder.memberName;
  }

  @override
  void dispose() {
    uangFocusNode.dispose();
    voucherFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final members = await MemberService.instance.getCachedMembers();
    setState(() {
      _members = members;
      // Try to find matching member by userId
      _selectedMember = _members.cast<Member?>().firstWhere(
        (m) => m?.id == widget.selfOrder.userId,
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
              widget.selfOrder.shortCode,
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

                    // Cash input
                    TextField(
                      focusNode: uangFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          if (newValue.text.isEmpty) return newValue;
                          final plainNumber = newValue.text.replaceAll('.', '');
                          if (plainNumber.isEmpty) return newValue;
                          final format = NumberFormat("#,###", "id_ID");
                          final newText = format.format(int.parse(plainNumber));
                          return TextEditingValue(
                            text: newText,
                            selection:
                                TextSelection.collapsed(offset: newText.length),
                          );
                        }),
                      ],
                      controller: widget.uangYangDiterimaController,
                      decoration: InputDecoration(
                        labelText: 'Uang yang diterima (Rp)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, null),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Batal',
                              style: GoogleFonts.poppins(color: Colors.grey.shade700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              final inputText = widget
                                  .uangYangDiterimaController.text
                                  .replaceAll('.', '');
                              if (inputText.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Masukkan uang yang diterima'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                                return;
                              }
                              int uangYangDiterima = int.parse(inputText);
                              if (uangYangDiterima >= displayTotal) {
                                Navigator.pop(context, {
                                  'confirmed': true,
                                  'finalTotal': displayTotal,
                                  'isMember': _selectedMember != null,
                                  'memberId': _selectedMember?.id ??
                                      widget.selfOrder.userId,
                                  'memberPhone': _selectedMember?.phoneNumber,
                                  'voucherCode':
                                      voucherApplied ? voucherController.text : null,
                                  'isPosVoucher':
                                      voucherApplied ? isPosVoucher : false,
                                });
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Uang yang diterima masih kurang'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },
                            child: Text(
                              'Konfirmasi Pembayaran',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
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
