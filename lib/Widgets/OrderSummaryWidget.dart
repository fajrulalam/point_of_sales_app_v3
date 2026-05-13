import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';

class OrderSummaryWidget extends StatelessWidget {
  final int biayaBungkus;
  final int totalHarga;
  final List<PesananObject> pesananList;
  final List<MenuObject> allMenus;
  final VoidCallback onBuyPressed;

  const OrderSummaryWidget({
    Key? key,
    required this.biayaBungkus,
    required this.totalHarga,
    required this.pesananList,
    required this.allMenus,
    required this.onBuyPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    int totalMakanan = 0;
    int totalMinuman = 0;

    for (var order in pesananList) {
      final menu = allMenus.firstWhere(
        (m) => m.id == order.menuItemId,
        orElse: () => MenuObject(id: '', namaMenu: '', harga: 0, isMakanan: true, imagePath: ''),
      );
      if (menu.isMakanan) {
        totalMakanan += order.totalQuantity;
      } else {
        totalMinuman += order.totalQuantity;
      }
    }

    return Container(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Item Summary
              if (totalMakanan > 0 || totalMinuman > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (totalMakanan > 0)
                      Text(
                        'Total Makanan: $totalMakanan',
                        style: GoogleFonts.poppins(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (totalMinuman > 0)
                      Text(
                        'Total Minuman: $totalMinuman',
                        style: GoogleFonts.poppins(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              // Conditionally display the Biaya Bungkus row
              if (biayaBungkus > 0) ...[
                Row(
                  children: [
                    Text(
                      'Biaya Bungkus',
                      style: GoogleFonts.poppins(
                        color: Colors.grey,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.1,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Rp ${NumberFormat.decimalPattern().format(biayaBungkus).replaceAll(',', '.')}',
                      style: GoogleFonts.poppins(
                        color: Colors.grey,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.1,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              // Total row
              Row(
                children: [
                  Text(
                    'Total',
                    style: GoogleFonts.poppins(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Rp ${NumberFormat.decimalPattern().format(totalHarga).replaceAll(',', '.')}',
                    style: GoogleFonts.poppins(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              // BELI button
              Container(
                margin: const EdgeInsets.only(left: 16.0, right: 16.0, top: 4),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    backgroundColor: const Color(0xFF2E7D32),
                  ),
                  onPressed: onBuyPressed,
                  child: Text(
                    'BELI',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
