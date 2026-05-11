import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Controllers/HomeController.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

class ConnectPrinterDialog extends StatefulWidget {
  final HomeController controller;

  const ConnectPrinterDialog({Key? key, required this.controller})
      : super(key: key);

  @override
  State<ConnectPrinterDialog> createState() => _ConnectPrinterDialogState();
}

class _ConnectPrinterDialogState extends State<ConnectPrinterDialog>
    with SingleTickerProviderStateMixin {
  bool printReceipt = true;
  bool printerIsConnected = false;
  List<BluetoothDevice> devices = [];
  BluetoothDevice? selectedDevice;
  BlueThermalPrinter printer = BlueThermalPrinter.instance;
  late TabController _tabController;
  bool _isReprinting = false;
  String? _reprintingOrderId;
  DateTime _selectedDate = DateTime.now();
  bool _isLoadingPrinters = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _syncPrinterState();
    getPrinters();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _syncPrinterState() {
    printerIsConnected = widget.controller.printerIsConnected;
    selectedDevice = widget.controller.selectedDevice;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildPrinterSection(),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            _buildReprintSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Pengaturan Printer',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (printerIsConnected) {
              Navigator.pop(context, selectedDevice);
            } else {
              Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.save, size: 18),
          label: const Text('Simpan'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildPrinterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Koneksi Printer',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _isLoadingPrinters
                          ? Row(
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Mencari printer...',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            )
                          : DropdownButtonHideUnderline(
                              child: DropdownButton<BluetoothDevice>(
                                hint: Text(
                                  devices.isEmpty
                                      ? 'Tidak ada printer ditemukan'
                                      : 'Pilih printer',
                                ),
                                value: selectedDevice,
                                isExpanded: true,
                                items: devices
                                    .map((e) => DropdownMenuItem(
                                        child: Text(e.name ?? 'Unknown Device'),
                                        value: e))
                                    .toList(),
                                onChanged: devices.isEmpty
                                    ? null
                                    : (device) async {
                                        if (device != null) {
                                          setState(() => selectedDevice = device);
                                          await _handleNewConnection(device);
                                        }
                                      },
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 10,
                      width: 10,
                      decoration: BoxDecoration(
                        color: printerIsConnected ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (printerIsConnected
                                    ? Colors.green
                                    : Colors.grey)
                                .withOpacity(0.3),
                            spreadRadius: 1,
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => testPrinter('test'),
              icon: const Icon(Icons.print, size: 18),
              label: const Text("Tes"),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
                side: const BorderSide(color: Color(0xFF2E7D32)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2E7D32),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Widget _buildReprintSection() {
    final bool isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    final String dateLabel = isToday
        ? 'Hari Ini'
        : DateFormat('dd MMM yyyy').format(_selectedDate);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cetak Ulang Struk',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text(
                  dateLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF2E7D32),
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: const Color(0xFF2E7D32),
            labelStyle: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            tabs: const [
              Tab(text: 'Antrian Aktif'),
              Tab(text: 'Sudah Selesai'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildActiveList(),
                _buildCompletedList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveList() {
    final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(Col.name('Status'))
          .where('waktuPesan', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('waktuPesan', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('waktuPesan', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_empty, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  'Tidak ada pesanan aktif',
                  style: GoogleFonts.poppins(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildOrderTile(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildCompletedList() {
    final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(Col.name('RecentlyServed'))
          .where('timestampServe', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestampServe', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('timestampServe', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  'Tidak ada pesanan selesai',
                  style: GoogleFonts.poppins(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildRecentlyServedTile(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildRecentlyServedTile(String docId, Map<String, dynamic> data) {
    final int customerNumber = data['customerNumber'] ?? 0;
    final String namaCustomer = data['namaCustomer'] ?? '-';
    final int total = data['total'] ?? 0;
    final rawTimestamp = data['timestampServe'];
    final String transactionMethod = data['transactionMethod'] ?? '';
    final bool isReprinting = _isReprinting && _reprintingOrderId == docId;

    String formattedTime = '-';
    if (rawTimestamp is Timestamp) {
      formattedTime = DateFormat('HH:mm').format(rawTimestamp.toDate());
    } else if (rawTimestamp is DateTime) {
      formattedTime = DateFormat('HH:mm').format(rawTimestamp);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '#$customerNumber',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2E7D32),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  namaCustomer.isEmpty ? 'Customer' : namaCustomer,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'Rp ${_formatCurrency(total)}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: const Color(0xFF2E7D32),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• $formattedTime',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (transactionMethod.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          transactionMethod,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: ElevatedButton.icon(
              onPressed: printerIsConnected && !isReprinting
                  ? () => _handleReprint(docId, data)
                  : null,
              icon: isReprinting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print, size: 16),
              label: Text(isReprinting ? '' : 'Cetak'),
              style: ElevatedButton.styleFrom(
                backgroundColor: printerIsConnected
                    ? const Color(0xFF2E7D32)
                    : Colors.grey,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTile(String docId, Map<String, dynamic> data) {
    final int customerNumber = data['customerNumber'] ?? 0;
    final String namaCustomer = data['namaCustomer'] ?? '-';
    final int total = data['total'] ?? 0;
    final Timestamp? waktuPesan = data['waktuPesan'];
    final String status = data['status'] ?? '';
    final bool isReprinting = _isReprinting && _reprintingOrderId == docId;

    String formattedTime = '-';
    if (waktuPesan != null) {
      formattedTime = DateFormat('HH:mm').format(waktuPesan.toDate());
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Order Number Badge
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '#$customerNumber',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2E7D32),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Order Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  namaCustomer.isEmpty ? 'Customer' : namaCustomer,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'Rp ${_formatCurrency(total)}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: const Color(0xFF2E7D32),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• $formattedTime',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (status.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: _getStatusColor(status),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Reprint Button
          SizedBox(
            width: 100,
            child: ElevatedButton.icon(
              onPressed: printerIsConnected && !isReprinting
                  ? () => _handleReprint(docId, data)
                  : null,
              icon: isReprinting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print, size: 16),
              label: Text(isReprinting ? '' : 'Cetak'),
              style: ElevatedButton.styleFrom(
                backgroundColor: printerIsConnected
                    ? const Color(0xFF2E7D32)
                    : Colors.grey,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReprint(String docId, Map<String, dynamic> data) async {
    setState(() {
      _isReprinting = true;
      _reprintingOrderId = docId;
    });

    try {
      await widget.controller.reprintFromOrder(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  'Struk berhasil dicetak ulang',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Gagal mencetak: $e',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isReprinting = false;
          _reprintingOrderId = null;
        });
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'serving':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _handleNewConnection(BluetoothDevice device) async {
    try {
      // If already connected to this device, just verify and skip reconnect
      final alreadyConnected = (await printer.isConnected) ?? false;
      if (alreadyConnected && widget.controller.selectedDevice?.address == device.address) {
        await checkIfPrinterIsConnected();
        return;
      }

      try {
        await printer.disconnect();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
      
      await printer.connect(device);
      await checkIfPrinterIsConnected();
    } catch (e) {
      print("❌ Connection error: $e");
      if (e.toString().contains("already connected")) {
        await checkIfPrinterIsConnected();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghubungkan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatCurrency(int value) {
    return value.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  Future<void> checkIfPrinterIsConnected() async {
    if ((await printer.isConnected)!) {
      print("Printer is connected ${selectedDevice?.name!}");
      setState(() {
        printerIsConnected = true;
      });
      widget.controller.printerIsConnected = true;
      widget.controller.selectedDevice = selectedDevice;
    } else {
      print("Printer is not connected");
      setState(() {
        printerIsConnected = false;
      });
      widget.controller.printerIsConnected = false;
    }
  }

  Future<void> testPrinter(String invoice) async {
    // Check the real device connection status first
    await checkIfPrinterIsConnected();
    
    if (printerIsConnected) {
      try {
        await widget.controller.testPrinter(invoice);
      } catch (e) {
        print("❌ Printer error during test: $e");
        setState(() {
          printerIsConnected = false;
        });
        widget.controller.printerIsConnected = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Koneksi printer terputus: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Printer belum terhubung',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> getPrinters() async {
    setState(() => _isLoadingPrinters = true);
    try {
      devices = await printer.getBondedDevices();
      // Match the previously selected device to the new list by address,
      // since getPrinters() returns new BluetoothDevice object instances.
      if (selectedDevice != null && devices.isNotEmpty) {
        final match = devices.cast<BluetoothDevice?>().firstWhere(
          (d) => d?.address == selectedDevice!.address,
          orElse: () => null,
        );
        if (match != null) {
          selectedDevice = match;
        }
      }
    } catch (e) {
      print('Error fetching printers: $e');
      devices = [];
    }
    if (mounted) {
      setState(() => _isLoadingPrinters = false);
    }
  }
}
