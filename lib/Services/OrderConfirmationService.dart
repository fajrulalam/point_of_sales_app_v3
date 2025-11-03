import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Services/LoaderWidget.dart';

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
    required Function({int discountAmount, int originalTotal}) printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
  }) async {
    if (pesananList.isEmpty) {
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return _OrderConfirmationDialog(
          totalHarga: totalHarga,
          isTakeAway: isTakeAway,
          biayaBungkus: biayaBungkus,
          customerNameController: customerNameController,
          uangYangDiterimaController: uangYangDiterimaController,
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
    required Function({int discountAmount, int originalTotal}) printReceipt,
    required String Function() getYear,
    required String Function() getMonth,
    required String Function() getDate,
    required Function(int) setJumlahItem,
    String? appliedVoucherCode,
    int discountAmount = 0,
  }) async {
    LoaderWidget.showLoaderDialog(context, message: "Mohon tunggu...");

    Map<String, dynamic> map = {};
    Map<String, dynamic> map_status = {};

    String namaPesanan_serialized = "";
    String quantityPesanan_serialized = "";

    for (var element in pesananList) {
      map[element.namaPesanan] = FieldValue.increment(element.totalQuantity);
      namaPesanan_serialized += '${element.namaPesanan}, ';
      quantityPesanan_serialized += '${element.totalQuantity}, ';
    }

    namaPesanan_serialized =
        namaPesanan_serialized.substring(0, namaPesanan_serialized.length - 2);
    quantityPesanan_serialized = quantityPesanan_serialized.substring(
        0, quantityPesanan_serialized.length - 2);

    map['total'] = FieldValue.increment(totalHarga);
    map["year"] = getYear();
    map["month"] = getMonth();
    map["date"] = getDate();
    map["customerNumber"] = FieldValue.increment(1);
    map["timestamp"] = FieldValue.serverTimestamp();

    FirebaseFirestore fs = FirebaseFirestore.instance;
    WriteBatch batch = fs.batch();

    DateTime now = DateTime.now();
    String dateNow_formatted = DateFormat('yyyy-MM-dd').format(now);
    DocumentReference dailyTransaction =
        fs.collection("DailyTransaction").doc(dateNow_formatted);
    batch.set(dailyTransaction, map, SetOptions(merge: true));

    DocumentReference monthlyTransaction =
        fs.collection("MonthlyTransaction").doc(getMonth());
    batch.set(monthlyTransaction, map, SetOptions(merge: true));

    DocumentReference yearlyTransaction =
        fs.collection("YearlyTransaction").doc(getYear());
    batch.set(yearlyTransaction, map, SetOptions(merge: true));

    int bungkus_int = 0;
    if (isTakeAway == true) bungkus_int = 1;

    List<Map<String, dynamic>> orderItems = pesananList.map((order) {
      return {
        'namaPesanan': order.namaPesanan,
        'dineInQuantity': order.dineInQuantity,
        'takeAwayQuantity': order.takeAwayQuantity,
      };
    }).toList();

    map_status['customerNumber'] = nomorBerikutnya + 1;
    map_status['orderItems'] = orderItems;
    map_status['status'] = 'Serving';
    map_status['bungkus'] = bungkus_int;
    map_status['namaCustomer'] = customerNameController.text;
    map_status['total'] = totalHarga;
    map_status['waktuPengambilan'] = 'Tidak Memesan';
    map_status['waktuPesan'] = FieldValue.serverTimestamp();

    DocumentReference statusRef =
        fs.collection("Status").doc('${nomorBerikutnya + 1}');
    batch.set(statusRef, map_status);

    DocumentReference customerNumber =
        fs.collection("Canteens").doc('canteen375');
    batch.update(customerNumber, {'customerNumber': FieldValue.increment(1)});

    try {
      await batch.commit();

      if (appliedVoucherCode != null) {
        _claimVoucherAsync(appliedVoucherCode);
      }

      printReceipt(
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
            child: Container(
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
                  SizedBox(height: 16),
                  Text(
                    '${nomorBerikutnya}',
                    style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                        fontSize: 36,
                        color: Colors.redAccent.withOpacity(0.8)),
                  ),
                  SizedBox(height: 16),
                  if (discountAmount > 0) ...[
                    Text(
                      'Diskon: Rp ${NumberFormat.decimalPattern().format(discountAmount).replaceAll(',', '.')}',
                      style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Colors.green),
                    ),
                    SizedBox(height: 8),
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
                      SizedBox(width: 8),
                      Text(
                        'Rp ${NumberFormat.decimalPattern().format(uangYangDiterima - totalHarga)}',
                        style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w600,
                            fontSize: 24,
                            color: Colors.black87.withOpacity(1)),
                      )
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    '${quoteKejujuran[randomNumber]}',
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

  const _OrderConfirmationDialog({
    required this.totalHarga,
    required this.isTakeAway,
    required this.biayaBungkus,
    required this.customerNameController,
    required this.uangYangDiterimaController,
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

  @override
  Widget build(BuildContext context) {
    final customerNameFocusNode = FocusNode();
    final uangFocusNode = FocusNode();
    final voucherFocusNode = FocusNode();

    int displayTotal = widget.totalHarga - voucherValue;

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
      content: Container(
        height: applyPromo
            ? (voucherApplied ? 420 : 380)
            : (widget.isTakeAway ? 280 : 250),
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Total tagihan: '),
                  SizedBox(width: 8),
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
                SizedBox(height: 8),
                Text(
                  'Diskon: Rp ${NumberFormat.decimalPattern().format(voucherValue).replaceAll(',', '.')}',
                  style: GoogleFonts.poppins(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
              SizedBox(height: 16),
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
                        SizedBox(width: 8),
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
                    SizedBox(height: 16),
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
                SizedBox(height: 12),
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
                    SizedBox(width: 8),
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

                                final result = await OrderConfirmationService
                                    ._validateVoucher(voucherController.text);

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
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: 16),
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
              SizedBox(height: 16),
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
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
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
                            'voucherCode':
                                voucherApplied ? voucherController.text : null,
                          });
                        } else {
                          SnackBar snackBar = SnackBar(
                            content: Text('Uang yang diterima masih kurang'),
                            backgroundColor: Colors.redAccent,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(snackBar);
                        }
                      },
                      child: Text('OK'),
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
