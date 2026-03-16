import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Models/SelfOrder.dart';
import 'package:point_of_sales_app_v3/Services/SelfOrderService.dart';

class SelfOrdersScreen extends StatefulWidget {
  final Function(SelfOrder order)? onAcceptOrder;

  const SelfOrdersScreen({
    Key? key,
    this.onAcceptOrder,
  }) : super(key: key);

  @override
  State<SelfOrdersScreen> createState() => _SelfOrdersScreenState();
}

class _SelfOrdersScreenState extends State<SelfOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SelfOrderService _selfOrderService = SelfOrderService.instance;
  final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Pesanan Mandiri',
          style:
              GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.pending_actions), text: 'Menunggu'),
            Tab(icon: Icon(Icons.check_circle), text: 'Selesai'),
            Tab(icon: Icon(Icons.cancel), text: 'Ditolak'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrderList(SelfOrderStatus.unpaid),
          _buildOrderList(SelfOrderStatus.paid),
          _buildOrderList(SelfOrderStatus.declined),
        ],
      ),
    );
  }

  Widget _buildOrderList(String statusFilter) {
    return StreamBuilder<List<SelfOrder>>(
      stream: _selfOrderService.getSelfOrdersStream(statusFilter: statusFilter),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Terjadi kesalahan',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final orders = snapshot.data ?? [];

        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getEmptyIcon(statusFilter),
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  _getEmptyMessage(statusFilter),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            return _buildOrderCard(orders[index], statusFilter);
          },
        );
      },
    );
  }

  IconData _getEmptyIcon(String status) {
    switch (status) {
      case SelfOrderStatus.unpaid:
        return Icons.inbox_outlined;
      case SelfOrderStatus.paid:
        return Icons.check_circle_outline;
      case SelfOrderStatus.declined:
        return Icons.cancel_outlined;
      default:
        return Icons.inbox_outlined;
    }
  }

  String _getEmptyMessage(String status) {
    switch (status) {
      case SelfOrderStatus.unpaid:
        return 'Tidak ada pesanan yang menunggu';
      case SelfOrderStatus.paid:
        return 'Belum ada pesanan yang selesai';
      case SelfOrderStatus.declined:
        return 'Belum ada pesanan yang ditolak';
      default:
        return 'Tidak ada pesanan';
    }
  }

  Widget _buildOrderCard(SelfOrder order, String statusFilter) {
    final dateStr = DateFormat('dd MMM yyyy HH:mm').format(order.timestamp);
    final isUnpaid = statusFilter == SelfOrderStatus.unpaid;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _getStatusColor(order.status).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _getStatusColor(order.status).withOpacity(0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        order.shortCode,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.memberName,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          dateStr,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                _buildStatusChip(order.status),
              ],
            ),
          ),

          // Order Items
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Item Pesanan',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                ...order.orderItems.map((item) => _buildOrderItemRow(item)),
                const Divider(height: 24),

                // Pricing
                _buildPriceRow('Subtotal', order.subtotal),
                if (order.takeAwayFee > 0)
                  _buildPriceRow('Biaya Bungkus', order.takeAwayFee),
                const SizedBox(height: 8),
                _buildPriceRow('Total', order.total, isTotal: true),

                // Decline reason (if applicable)
                if (order.isDeclined && order.declineReason != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Alasan: ${order.declineReason}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action Buttons (only for unpaid orders)
          if (isUnpaid)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showDeclineDialog(order),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Tolak'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => _handleAcceptOrder(order),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Terima & Bayar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderItemRow(SelfOrderItem item) {
    final quantities = <String>[];
    if (item.dineInQuantity > 0) {
      quantities.add('Dine In x${item.dineInQuantity}');
    }
    if (item.takeAwayQuantity > 0) {
      quantities.add('Take Away x${item.takeAwayQuantity}');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF2E7D32),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.namaPesanan,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  quantities.join(' | '),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _currencyFormat.format(item.itemTotal),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, int amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: isTotal ? 15 : 13,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
              color: isTotal ? Colors.black : Colors.grey.shade700,
            ),
          ),
          Text(
            _currencyFormat.format(amount),
            style: GoogleFonts.poppins(
              fontSize: isTotal ? 16 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? const Color(0xFF2E7D32) : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getStatusLabel(status),
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case SelfOrderStatus.unpaid:
        return Colors.orange;
      case SelfOrderStatus.processing:
        return Colors.blue;
      case SelfOrderStatus.paid:
        return Colors.green;
      case SelfOrderStatus.declined:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case SelfOrderStatus.unpaid:
        return 'Menunggu';
      case SelfOrderStatus.processing:
        return 'Diproses';
      case SelfOrderStatus.paid:
        return 'Selesai';
      case SelfOrderStatus.declined:
        return 'Ditolak';
      default:
        return status;
    }
  }

  void _handleAcceptOrder(SelfOrder order) {
    if (widget.onAcceptOrder != null) {
      widget.onAcceptOrder!(order);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fitur terima pesanan sedang dalam pengembangan',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _showDeclineDialog(SelfOrder order) {
    String? selectedReason;
    final customReasonController = TextEditingController();
    bool showCustomField = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.cancel, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Tolak Pesanan',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pilih alasan penolakan:',
                    style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  ...DeclineReasons.defaultReasons.map((reason) {
                    final isOther = reason == DeclineReasons.other;
                    return RadioListTile<String>(
                      title: Text(reason, style: GoogleFonts.poppins()),
                      value: reason,
                      groupValue: selectedReason,
                      activeColor: const Color(0xFF2E7D32),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() {
                          selectedReason = value;
                          showCustomField = isOther;
                        });
                      },
                    );
                  }),
                  if (showCustomField) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: customReasonController,
                      decoration: InputDecoration(
                        labelText: 'Alasan lainnya',
                        hintText: 'Masukkan alasan...',
                        border: const OutlineInputBorder(),
                        labelStyle: GoogleFonts.poppins(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    Text('Batal', style: GoogleFonts.poppins(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: selectedReason == null
                    ? null
                    : () => _declineOrder(order, selectedReason!,
                        customReasonController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('Tolak Pesanan', style: GoogleFonts.poppins()),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _declineOrder(
      SelfOrder order, String reason, String customReason) async {
    Navigator.pop(context);

    final finalReason =
        reason == DeclineReasons.other && customReason.isNotEmpty
            ? customReason
            : reason;

    try {
      await _selfOrderService.declineOrder(order.id, finalReason);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  'Pesanan ${order.shortCode} berhasil ditolak',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal menolak pesanan: $e',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
