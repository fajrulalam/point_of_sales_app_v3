import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class OrderSummaryWidget extends StatelessWidget {
  final int biayaBungkus;
  final int totalHarga;
  final VoidCallback onBuyPressed;

  const OrderSummaryWidget({
    Key? key,
    required this.biayaBungkus,
    required this.totalHarga,
    required this.onBuyPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                    backgroundColor: Colors.teal,
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
