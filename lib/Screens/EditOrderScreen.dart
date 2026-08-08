import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Services/UserMessageService.dart';

class EditOrderScreen extends StatefulWidget {
  final bool isEmbedded;
  final Function(Map<String, dynamic>)? onOrderSelected;

  const EditOrderScreen({
    Key? key,
    this.isEmbedded = false,
    this.onOrderSelected,
  }) : super(key: key);

  @override
  State<EditOrderScreen> createState() => _EditOrderScreenState();
}

class _EditOrderScreenState extends State<EditOrderScreen> {
  final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  Stream<QuerySnapshot> _getTodayOrdersStream() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return FirebaseFirestore.instance
        .collection(Col.name('Status'))
        .where('waktuPesan', isGreaterThanOrEqualTo: startOfDay)
        .where('waktuPesan', isLessThanOrEqualTo: endOfDay)
        .orderBy('waktuPesan', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = StreamBuilder<QuerySnapshot>(
      stream: _getTodayOrdersStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Gagal memuat pesanan: ${UserMessageService.fromError(snapshot.error)}',
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Tidak ada pesanan aktif sekarang',
                  style: GoogleFonts.poppins(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final orderItems = data['orderItems'] as List<dynamic>? ?? [];
            final total = data['total'] as int? ?? 0;
            final customerNumber = data['customerNumber'] as int? ?? 0;
            final customerName = data['namaCustomer'] as String?;
            final status = data['status'] ?? 'Unknown';
            final isCancelled = status == 'Cancelled';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            customerName != null && customerName.isNotEmpty
                                ? 'Order #$customerNumber - $customerName'
                                : 'Order #$customerNumber',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isCancelled
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isCancelled ? 'Dibatalkan' : 'Selesai',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isCancelled
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Total: ${_currencyFormat.format(total)}',
                      style: GoogleFonts.poppins(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    ...orderItems.map((item) {
                      final name = item['namaPesanan'] ?? '';
                      final qty = (item['dineInQuantity'] as int? ?? 0) +
                          (item['takeAwayQuantity'] as int? ?? 0);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('- $qty x $name',
                            style: GoogleFonts.poppins(fontSize: 13)),
                      );
                    }).toList(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isCancelled
                            ? null
                            : () {
                                final result = {
                                  'id': doc.id,
                                  'data': data,
                                };
                                if (widget.isEmbedded) {
                                  widget.onOrderSelected?.call(result);
                                } else {
                                  Navigator.pop(context, result);
                                }
                              },
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Rubah Pesanan'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (widget.isEmbedded) {
      return Container(
        color: Colors.grey.shade50,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                children: [
                  Text(
                    'Edit Pesanan Hari Ini',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Edit Pesanan Hari Ini',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A)),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 1,
      ),
      body: content,
    );
  }
}
