import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';

class OrderListWidget extends StatelessWidget {
  final List<PesananObject> pesananList;
  final Function(int) onIncrementDineIn;
  final Function(int) onDecrementDineIn;
  final Function(int) onIncrementTakeAway;
  final Function(int) onDecrementTakeAway;

  const OrderListWidget({
    Key? key,
    required this.pesananList,
    required this.onIncrementDineIn,
    required this.onDecrementDineIn,
    required this.onIncrementTakeAway,
    required this.onDecrementTakeAway,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: pesananList.length,
      itemBuilder: (BuildContext context, int index) {
        final order = pesananList[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Container(
            margin: const EdgeInsets.only(top: 4.0),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade300,
                  width: 0.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item name
                Text(
                  order.namaPesanan,
                  style: GoogleFonts.montserrat(
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                    fontSize: 18,
                  ),
                ),
                // Selected options
                if (order.selectedOptions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: order.selectedOptions.map((opt) {
                        final isDiscount = opt.priceAdjustment < 0;
                        final priceLabel = opt.priceAdjustment > 0
                            ? ' (+${NumberFormat.decimalPattern().format(opt.priceAdjustment).replaceAll(',', '.')})'
                            : opt.priceAdjustment < 0
                                ? ' (-${NumberFormat.decimalPattern().format(opt.priceAdjustment.abs()).replaceAll(',', '.')})'
                                : '';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDiscount ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${opt.optionName}$priceLabel',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: isDiscount ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 8),
                // Two counters side by side
                Row(
                  children: [
                    // Dine In Counter
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Dine In",
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => onDecrementDineIn(index),
                                icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: Colors.redAccent,
                                  size: 24,
                                ),
                              ),
                              Text(
                                order.dineInQuantity.toString(),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                onPressed: () => onIncrementDineIn(index),
                                icon: const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: Colors.green,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Take Away Counter
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Take Away",
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => onDecrementTakeAway(index),
                                icon: const Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: Colors.redAccent,
                                  size: 24,
                                ),
                              ),
                              Text(
                                order.takeAwayQuantity.toString(),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                onPressed: () => onIncrementTakeAway(index),
                                icon: const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: Colors.green,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Display the subtotal for this order line
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    color: Colors.grey.shade200,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12.0, vertical: 5.0),
                    margin: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      'Rp ${NumberFormat.decimalPattern().format(order.subtotal).replaceAll(',', '.')}',
                      style: GoogleFonts.notoSans(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
