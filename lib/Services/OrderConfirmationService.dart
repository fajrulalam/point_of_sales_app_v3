import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Models/RecommendationModels.dart';
import 'package:point_of_sales_app_v3/Services/LoaderWidget.dart';
import 'package:point_of_sales_app_v3/Services/RecommendationService.dart';
import 'package:point_of_sales_app_v3/Widgets/RecommendationListWidget.dart';

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
    required List<String> quoteKejujuran,
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

      await _processOrder(
        context: context,
        pesananList: pesananList,
        totalHarga: finalTotal,
        originalTotal: totalHarga,
        isTakeAway: isTakeAway,
        customerNameController: customerNameController,
        uangYangDiterimaController: uangYangDiterimaController,
        nomorBerikutnya: nomorBerikutnya,
        quoteKejujuran: quoteKejujuran,
        getTotal: getTotal,
        printReceipt: printReceipt,
        getYear: getYear,
        getMonth: getMonth,
        getDate: getDate,
        setJumlahItem: setJumlahItem,
        appliedVoucherCode: appliedVoucherCode,
        discountAmount: totalHarga - finalTotal,
      );
    } else {
      uangYangDiterimaController.clear();
    }
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
    required List<String> quoteKejujuran,
    required Function() getTotal,
    required Future<void> Function({int discountAmount, int originalTotal})
        printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
    String? appliedVoucherCode,
    int discountAmount = 0,
  }) async {
    LoaderWidget.showLoaderDialog(context, message: "Mohon tunggu...");

    Map<String, dynamic> map = {};
    Map<String, dynamic> mapStatus = {};

    String namapesananSerialized = "";
    String quantitypesananSerialized = "";
    int viaAssociationRulesCount = 0;

    for (var element in pesananList) {
      map[element.namaPesanan] = FieldValue.increment(element.totalQuantity);
      namapesananSerialized += '${element.namaPesanan}, ';
      quantitypesananSerialized += '${element.totalQuantity}, ';

      // Count items added via association rules
      if (element.viaAssociationRules) {
        viaAssociationRulesCount += element.totalQuantity;
      }
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

    // Track items added via association rules recommendation system
    if (viaAssociationRulesCount > 0) {
      map["viaAssociationRulesCount"] =
          FieldValue.increment(viaAssociationRulesCount);
      print(
          '📊 Tracking $viaAssociationRulesCount items added via association rules');
    }

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

    int bungkusInt = 0;
    if (isTakeAway == true) bungkusInt = 1;

    List<Map<String, dynamic>> orderItems = pesananList.map((order) {
      return {
        'namaPesanan': order.namaPesanan,
        'dineInQuantity': order.dineInQuantity,
        'takeAwayQuantity': order.takeAwayQuantity,
        'viaAssociationRules':
            order.viaAssociationRules, // Track recommendation source
      };
    }).toList();

    mapStatus['customerNumber'] = nomorBerikutnya + 1;
    mapStatus['orderItems'] = orderItems;
    mapStatus['status'] = 'Serving';
    mapStatus['bungkus'] = bungkusInt;
    mapStatus['namaCustomer'] = customerNameController.text;
    mapStatus['total'] = totalHarga;
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

      if (appliedVoucherCode != null) {
        _claimVoucherAsync(appliedVoucherCode);
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
        quoteKejujuran: quoteKejujuran,
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
    required List<String> quoteKejujuran,
    required List<PesananObject> pesananList,
    required TextEditingController customerNameController,
    required TextEditingController uangYangDiterimaController,
    required Function() getTotal,
    required Function(int) setJumlahItem,
  }) async {
    int min = 0;
    int max = quoteKejujuran.length - 1;
    final random = Random();
    int randomNumber = min + random.nextInt(max - min + 1);

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
                  const SizedBox(height: 16),
                  Text(
                    quoteKejujuran[randomNumber],
                    style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: Colors.black87.withOpacity(1)),
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

  static void _claimVoucherAsync(String voucherCode) async {
    try {
      FirebaseFirestore eSantrenFs =
          FirebaseFirestore.instanceFor(app: Firebase.app('e-santren'));
      DocumentReference voucherRef =
          eSantrenFs.collection("vouchers").doc(voucherCode);
      await voucherRef.update({'isClaimed': true});
      print('Voucher $voucherCode claimed successfully');
    } catch (e) {
      print('Failed to claim voucher $voucherCode: $e');
    }
  }

  static Future<Map<String, dynamic>?> _validateVoucher(
      String voucherCode) async {
    try {
      FirebaseFirestore eSantrenFs =
          FirebaseFirestore.instanceFor(app: Firebase.app('e-santren'));
      DocumentSnapshot doc =
          await eSantrenFs.collection("vouchers").doc(voucherCode).get();

      if (!doc.exists) {
        return {'error': 'Voucher tidak ditemukan'};
      }

      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      DateTime now = DateTime.now();

      DateTime activeDate = (data['activeDate'] as Timestamp).toDate();
      DateTime expireDate = (data['expireDate'] as Timestamp).toDate();
      bool isClaimed = data['isClaimed'] ?? false;
      bool isActive = data['isActive'] ?? false;

      if (now.isBefore(activeDate) || now.isAfter(expireDate)) {
        return {'error': 'Voucher sudah tidak berlaku'};
      }

      if (isClaimed) {
        return {'error': 'Voucher sudah digunakan'};
      }

      if (!isActive) {
        return {'error': 'Voucher tidak aktif'};
      }

      return {
        'success': true,
        'nama': data['nama'],
        'value': data['value'],
      };
    } catch (e) {
      return {'error': 'Terjadi kesalahan saat memvalidasi voucher'};
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
  late int
      currentTotal; // Track current total that updates when items are added

  @override
  void initState() {
    super.initState();
    currentTotal = widget.totalHarga; // Initialize with the starting total
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
    final customerNameFocusNode = FocusNode();
    final uangFocusNode = FocusNode();
    final voucherFocusNode = FocusNode();

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
            ? (voucherApplied ? 420 : 380)
            : (widget.isTakeAway ? 280 : 250),
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
                    if (applyPromo) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 7,
                            child: TextField(
                              controller: voucherController,
                              focusNode: voucherFocusNode,
                              maxLength: 6,
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
                                      if (voucherController.text.length != 6) {
                                        setState(() {
                                          voucherError =
                                              'Code voucher harus 6 karakter';
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
                                                  voucherController.text);

                                      setState(() {
                                        isValidatingVoucher = false;
                                        if (result != null &&
                                            result['error'] != null) {
                                          voucherError = result['error'];
                                          voucherApplied = false;
                                          voucherName = null;
                                          voucherValue = 0;
                                        } else if (result != null) {
                                          voucherError = null;
                                          voucherApplied = true;
                                          voucherName = result['nama'];
                                          voucherValue = result['value'];
                                          widget.customerNameController.text =
                                              result['nama'];
                                        } else {
                                          voucherError =
                                              'Terjadi kesalahan tidak diketahui';
                                          voucherApplied = false;
                                          voucherName = null;
                                          voucherValue = 0;
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
                    TextField(
                      controller: widget.customerNameController,
                      focusNode: customerNameFocusNode,
                      enabled: !voucherApplied,
                      onSubmitted: (_) {
                        FocusScope.of(context).requestFocus(uangFocusNode);
                      },
                      decoration: InputDecoration(
                        labelText: 'Nama Customer (opsional)',
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
                              backgroundColor: Colors.teal,
                            ),
                            onPressed: () {
                              int uangYangDiterima = int.parse(widget
                                  .uangYangDiterimaController.text
                                  .replaceAll('.', ''));
                              if (uangYangDiterima >= displayTotal) {
                                Navigator.pop(context, {
                                  'confirmed': true,
                                  'finalTotal': displayTotal,
                                  'voucherCode': voucherApplied
                                      ? voucherController.text
                                      : null,
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
            // Right side: Recommendations
            if (widget.recommendations.isNotEmpty) ...[
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
