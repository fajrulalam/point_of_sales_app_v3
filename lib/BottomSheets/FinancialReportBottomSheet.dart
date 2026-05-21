import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/BottomSheets/QuickExpenseBottomSheet.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

class FinancialReportBottomSheet extends StatefulWidget {
  const FinancialReportBottomSheet({Key? key}) : super(key: key);

  @override
  State<FinancialReportBottomSheet> createState() =>
      _FinancialReportBottomSheetState();
}

class _FinancialReportBottomSheetState
    extends State<FinancialReportBottomSheet> {
  final _cashController = TextEditingController();
  final _qrisController = TextEditingController();
  final _onlineController = TextEditingController();

  int? _systemTotal;
  int _totalVoucher = 0;
  bool _isLoadingTotal = true;

  // Expenses fetched from Firestore
  List<Map<String, dynamic>> _todayExpenses = [];
  bool _isLoadingExpenses = true;

  @override
  void initState() {
    super.initState();
    _fetchSystemTotal();
    _fetchTodayExpenses();
    _fetchSavedReport();
  }

  @override
  void dispose() {
    _cashController.dispose();
    _qrisController.dispose();
    _onlineController.dispose();
    super.dispose();
  }

  Future<void> _fetchSavedReport() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final doc = await FirebaseFirestore.instance
          .collection(Col.name('DailyFinancialReport'))
          .doc(today)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final actualCash = data['actualCash'] as int?;
        final actualQris = data['actualQris'] as int?;
        final actualOnline = data['actualOnline'] as int?;

        if (mounted) {
          setState(() {
            if (actualCash != null) {
              _cashController.text = _fmt(actualCash);
            }
            if (actualQris != null) {
              _qrisController.text = _fmt(actualQris);
            }
            if (actualOnline != null) {
              _onlineController.text = _fmt(actualOnline);
            }
          });
        }
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _fetchSystemTotal() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final doc = await FirebaseFirestore.instance
          .collection(Col.name('DailyTransaction'))
          .doc(today)
          .get();

      if (doc.exists && doc.data() != null) {
        setState(() {
          _systemTotal = (doc.data()!['total'] ?? 0) as int;
          _totalVoucher = (doc.data()!['totalVoucher'] ?? 0) as int;
          _isLoadingTotal = false;
        });
      } else {
        setState(() {
          _systemTotal = 0;
          _totalVoucher = 0;
          _isLoadingTotal = false;
        });
      }
    } catch (e) {
      setState(() {
        _systemTotal = 0;
        _totalVoucher = 0;
        _isLoadingTotal = false;
      });
    }
  }

  Future<void> _fetchTodayExpenses() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snap = await FirebaseFirestore.instance
          .collection(Col.name('Expenses'))
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('timestamp', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _todayExpenses = snap.docs
              .map((d) => d.data())
              .where((e) => e['addedFromDashboardWeb'] != true)
              .toList();
          _isLoadingExpenses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _todayExpenses = [];
          _isLoadingExpenses = false;
        });
      }
    }
  }

  String _maskRevenue(int value) {
    if (value == 0) return 'Rp 0';
    final formatted = NumberFormat.decimalPattern('id_ID').format(value);
    if (formatted.length <= 1) return 'Rp $formatted';

    final first = formatted[0];
    final rest = formatted.substring(1).replaceAll(RegExp(r'[0-9]'), '*');
    return 'Rp $first$rest';
  }

  String _fmt(int value) {
    return NumberFormat.decimalPattern('id_ID').format(value);
  }

  int _parseFormattedNumber(String text) {
    if (text.isEmpty) return 0;
    return int.tryParse(text.replaceAll('.', '')) ?? 0;
  }

  static final _currencyFormatter = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
    TextInputFormatter.withFunction((oldValue, newValue) {
      if (newValue.text.isEmpty) return newValue;
      final plain = newValue.text.replaceAll('.', '');
      if (plain.isEmpty) return newValue;
      final format = NumberFormat("#,###", "id_ID");
      final newText = format.format(int.parse(plain));
      return TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }),
  ];

  // Compute expense totals from Firestore data
  int get _expensesCash => _todayExpenses
      .where((e) => e['sourceAccount'] == 'Cash')
      .fold(0, (sum, e) => sum + ((e['amount'] ?? 0) as int));

  int get _expensesQris => _todayExpenses
      .where((e) => e['sourceAccount'] == 'QRIS')
      .fold(0, (sum, e) => sum + ((e['amount'] ?? 0) as int));

  int get _expensesOnline => _todayExpenses
      .where((e) => e['sourceAccount'] == 'Online')
      .fold(0, (sum, e) => sum + ((e['amount'] ?? 0) as int));

  int get _expensesTotal => _expensesCash + _expensesQris + _expensesOnline;

  Future<void> _submitReport() async {
    final inputCash = _parseFormattedNumber(_cashController.text);
    final inputQris = _parseFormattedNumber(_qrisController.text);
    final inputOnline = _parseFormattedNumber(_onlineController.text);

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fs = FirebaseFirestore.instance;
    final doc =
        await fs.collection(Col.name('DailyTransaction')).doc(today).get();

    final data = doc.data() ?? {};
    final totalCash = (data['totalCash'] ?? 0) as int;
    final totalQris = (data['totalQris'] ?? 0) as int;
    final totalOnline = (data['totalOnline'] ?? 0) as int;

    final expensesCash = _expensesCash;
    final expensesQris = _expensesQris;
    final expensesOnline = _expensesOnline;

    final netExpectedCash = totalCash - expensesCash;
    final netExpectedQris = totalQris - expensesQris;

    final cashMatch = inputCash == netExpectedCash;
    final qrisMatch = inputQris == netExpectedQris;
    final platformCommission = inputOnline - (totalOnline - expensesOnline);
    const onlineMatch = true;
    final allMatch = cashMatch && qrisMatch && onlineMatch;

    // Fetch previous day's closing balance for running saldo
    final prevSnap = await fs
        .collection(Col.name('DailyFinancialReport'))
        .where(FieldPath.documentId, isLessThan: today)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(1)
        .get();

    final prevData =
        prevSnap.docs.isNotEmpty ? prevSnap.docs.first.data() : {};
    final prevClosingCash = (prevData['closingCash'] ?? 0) as int;
    final prevClosingQris = (prevData['closingQris'] ?? 0) as int;
    final prevClosingOnline = (prevData['closingOnline'] ?? 0) as int;

    final discrepancyCash = inputCash - (totalCash - expensesCash);
    final discrepancyQris = inputQris - (totalQris - expensesQris);

    final closingCash = prevClosingCash + inputCash - expensesCash;
    final closingQris = prevClosingQris + inputQris - expensesQris;
    final closingOnline = prevClosingOnline + inputOnline - expensesOnline;

    if (!mounted) return;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _ValidationDialog(
        inputCash: inputCash,
        inputQris: inputQris,
        inputOnline: inputOnline,
        systemCash: netExpectedCash,
        systemQris: netExpectedQris,
        totalOnline: totalOnline,
        totalVoucher: _totalVoucher,
        platformCommission: platformCommission,
        allMatch: allMatch,
        cashMatch: cashMatch,
        qrisMatch: qrisMatch,
        onlineMatch: onlineMatch,
      ),
    );

    if (result == 'save' && mounted) {
      final reportRef =
          fs.collection(Col.name('DailyFinancialReport')).doc(today);

      final parts = today.split('-');
      final month = '${parts[0]}-${parts[1]}';
      final year = parts[0];

      final currentReportSnap = await reportRef.get();
      final currentData = currentReportSnap.data() ?? {};

      // Calculate deltas to prevent double-counting if submitted multiple times
      final deltaSysCash = totalCash - ((currentData['systemSalesCash'] ?? 0) as int);
      final deltaSysQris = totalQris - ((currentData['systemSalesQris'] ?? 0) as int);
      final deltaSysOnline = totalOnline - ((currentData['systemSalesOnline'] ?? 0) as int);
      final deltaVoucher = _totalVoucher - ((currentData['totalVoucher'] ?? 0) as int);

      final deltaExpCash = expensesCash - ((currentData['expensesCash'] ?? 0) as int);
      final deltaExpQris = expensesQris - ((currentData['expensesQris'] ?? 0) as int);
      final deltaExpOnline = expensesOnline - ((currentData['expensesOnline'] ?? 0) as int);

      final deltaActCash = inputCash - ((currentData['actualCash'] ?? 0) as int);
      final deltaActQris = inputQris - ((currentData['actualQris'] ?? 0) as int);
      final deltaActOnline = inputOnline - ((currentData['actualOnline'] ?? 0) as int);

      final deltaDiscCash = discrepancyCash - ((currentData['discrepancyCash'] ?? 0) as int);
      final deltaDiscQris = discrepancyQris - ((currentData['discrepancyQris'] ?? 0) as int);
      final deltaDiscOnline = platformCommission - ((currentData['discrepancyOnline'] ?? 0) as int);

      final batch = fs.batch();

      batch.set(reportRef, {
        'date': today,
        'month': month,
        'systemSalesCash': totalCash,
        'systemSalesQris': totalQris,
        'systemSalesOnline': totalOnline,
        'totalVoucher': _totalVoucher,
        'expensesCash': expensesCash,
        'expensesQris': expensesQris,
        'expensesOnline': expensesOnline,
        'actualCash': inputCash,
        'actualQris': inputQris,
        'actualOnline': inputOnline,
        'discrepancyCash': discrepancyCash,
        'discrepancyQris': discrepancyQris,
        'discrepancyOnline': platformCommission,
        'closingCash': closingCash,
        'closingQris': closingQris,
        'closingOnline': closingOnline,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final monthRef = fs.collection(Col.name('MonthlyFinancialReport')).doc(month);
      batch.set(monthRef, {
        'month': month,
        'systemSalesCash': FieldValue.increment(deltaSysCash),
        'systemSalesQris': FieldValue.increment(deltaSysQris),
        'systemSalesOnline': FieldValue.increment(deltaSysOnline),
        'totalVoucher': FieldValue.increment(deltaVoucher),
        'expensesCash': FieldValue.increment(deltaExpCash),
        'expensesQris': FieldValue.increment(deltaExpQris),
        'expensesOnline': FieldValue.increment(deltaExpOnline),
        'actualCash': FieldValue.increment(deltaActCash),
        'actualQris': FieldValue.increment(deltaActQris),
        'actualOnline': FieldValue.increment(deltaActOnline),
        'discrepancyCash': FieldValue.increment(deltaDiscCash),
        'discrepancyQris': FieldValue.increment(deltaDiscQris),
        'discrepancyOnline': FieldValue.increment(deltaDiscOnline),
        // Closing balances for the month can simply be overwritten by the latest day's values
        'closingCash': closingCash,
        'closingQris': closingQris,
        'closingOnline': closingOnline,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final yearRef = fs.collection(Col.name('YearlyFinancialReport')).doc(year);
      batch.set(yearRef, {
        'year': year,
        'systemSalesCash': FieldValue.increment(deltaSysCash),
        'systemSalesQris': FieldValue.increment(deltaSysQris),
        'systemSalesOnline': FieldValue.increment(deltaSysOnline),
        'totalVoucher': FieldValue.increment(deltaVoucher),
        'expensesCash': FieldValue.increment(deltaExpCash),
        'expensesQris': FieldValue.increment(deltaExpQris),
        'expensesOnline': FieldValue.increment(deltaExpOnline),
        'actualCash': FieldValue.increment(deltaActCash),
        'actualQris': FieldValue.increment(deltaActQris),
        'actualOnline': FieldValue.increment(deltaActOnline),
        'discrepancyCash': FieldValue.increment(deltaDiscCash),
        'discrepancyQris': FieldValue.increment(deltaDiscQris),
        'discrepancyOnline': FieldValue.increment(deltaDiscOnline),
        'closingCash': closingCash,
        'closingQris': closingQris,
        'closingOnline': closingOnline,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  'Laporan keuangan harian berhasil disimpan',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.assessment, color: Colors.amber.shade800, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Laporan Keuangan Harian',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection1SystemRevenue(),
                  const SizedBox(height: 24),
                  _buildSection2IncomeInput(),
                  const SizedBox(height: 24),
                  _buildVoucherPiutangInfo(),
                  const SizedBox(height: 24),
                  _buildSection3ExpensesSummary(),
                  const SizedBox(height: 32),
                  _buildSubmitButton(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection1SystemRevenue() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Perhitungan Sistem',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          _isLoadingTotal
              ? const SizedBox(
                  height: 32,
                  width: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _maskRevenue(_systemTotal ?? 0),
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSection2IncomeInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pemasukan Hari Ini',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Masukkan jumlah uang yang diterima berdasarkan metode pembayaran',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 16),
        _buildIncomeField(
          controller: _cashController,
          label: 'Uang Cash (Rp)',
          icon: Icons.payments_outlined,
          color: Colors.green,
        ),
        const SizedBox(height: 12),
        _buildIncomeField(
          controller: _qrisController,
          label: 'Uang QRIS (Rp)',
          icon: Icons.qr_code_2,
          color: Colors.blue,
        ),
        const SizedBox(height: 12),
        _buildIncomeField(
          controller: _onlineController,
          label: 'Uang Online (Rp)',
          icon: Icons.language,
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildIncomeField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: _currencyFormatter,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(fontSize: 14),
        prefixIcon: Icon(icon, color: color),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2),
        ),
      ),
      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildVoucherPiutangInfo() {
    if (_isLoadingTotal) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined,
              color: Colors.purple.shade700, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Piutang Voucher B2B (hari ini)',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.purple.shade800,
                  ),
                ),
                Text(
                  'Transaksi ini belum masuk kas — menunggu pembayaran dari institusi.',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.purple.shade400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Rp ${_fmt(_totalVoucher)}',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.purple.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection3ExpensesSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Pengeluaran Hari Ini',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                await QuickExpenseBottomSheet.show(context);
                // Refresh expenses after returning
                _fetchTodayExpenses();
              },
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: Text(
                'Tambah',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange.shade700,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingExpenses)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_todayExpenses.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 32, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'Belum ada pengeluaran hari ini',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          )
        else ...[
          // Summary by source
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              children: [
                _expenseSummaryRow(
                    'Cash', _expensesCash, Icons.payments_outlined, Colors.green),
                if (_expensesQris > 0) ...[
                  const SizedBox(height: 6),
                  _expenseSummaryRow(
                      'QRIS', _expensesQris, Icons.qr_code_2, Colors.blue),
                ],
                if (_expensesOnline > 0) ...[
                  const SizedBox(height: 6),
                  _expenseSummaryRow(
                      'Online', _expensesOnline, Icons.language, Colors.purple),
                ],
                const Divider(height: 16),
                Row(
                  children: [
                    Text(
                      'Total Pengeluaran',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Rp ${_fmt(_expensesTotal)}',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Individual expense items
          ...List.generate(_todayExpenses.length, (i) {
            final expense = _todayExpenses[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    _sourceIcon(expense['sourceAccount'] ?? 'Cash'),
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      expense['category'] ?? '-',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Text(
                    'Rp ${_fmt((expense['amount'] ?? 0) as int)}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            );
          }),
          Text(
            '${_todayExpenses.length} pengeluaran tercatat',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ],
    );
  }

  Widget _expenseSummaryRow(
      String label, int amount, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700),
        ),
        const Spacer(),
        Text(
          'Rp ${_fmt(amount)}',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.orange.shade700,
          ),
        ),
      ],
    );
  }

  IconData _sourceIcon(String source) {
    switch (source) {
      case 'QRIS':
        return Icons.qr_code_2;
      case 'Online':
        return Icons.language;
      default:
        return Icons.payments_outlined;
    }
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _submitReport,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber.shade700,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: Text(
          'Rekap Harian',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ValidationDialog extends StatelessWidget {
  final int inputCash;
  final int inputQris;
  final int inputOnline;
  final int systemCash;
  final int systemQris;
  final int totalOnline;
  final int totalVoucher;
  final int platformCommission;
  final bool allMatch;
  final bool cashMatch;
  final bool qrisMatch;
  final bool onlineMatch;

  const _ValidationDialog({
    required this.inputCash,
    required this.inputQris,
    required this.inputOnline,
    required this.systemCash,
    required this.systemQris,
    required this.totalOnline,
    required this.totalVoucher,
    required this.platformCommission,
    required this.allMatch,
    required this.cashMatch,
    required this.qrisMatch,
    required this.onlineMatch,
  });

  String _fmt(int value) {
    return NumberFormat.decimalPattern('id_ID').format(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            allMatch ? Icons.check_circle : Icons.warning_amber_rounded,
            color: allMatch ? Colors.green : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            allMatch ? 'Konfirmasi Laporan' : 'Peringatan Selisih',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
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
              allMatch
                  ? 'Semua nilai sesuai dengan hitungan Netto (Gross Income - Petty Cash).'
                  : 'Terdapat selisih antara input fisik Anda dan sistem (Net Accounting).',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 20),
            _buildComparisonRow('Cash', inputCash, systemCash, cashMatch),
            const SizedBox(height: 10),
            _buildComparisonRow('QRIS', inputQris, systemQris, qrisMatch),
            const SizedBox(height: 10),
            _buildOnlineRow(),
            if (totalVoucher > 0) ...[
              const SizedBox(height: 10),
              _buildVoucherRow(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'edit'),
          child: Text(
            'Ubah',
            style: GoogleFonts.poppins(color: Colors.grey.shade700),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, 'save'),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                allMatch ? const Color(0xFF2E7D32) : Colors.orange.shade700,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(
            'Simpan',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonRow(
      String label, int input, int system, bool match) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: match ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: match ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            match ? Icons.check_circle : Icons.warning,
            color: match ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!match)
                  Text(
                    'Input: Rp ${_fmt(input)}  vs  Net Harapan: Rp ${_fmt(system)}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  )
                else
                  Text(
                    'Rp ${_fmt(input)} - Sesuai',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.green.shade700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Online',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Diterima: Rp ${_fmt(inputOnline)}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.blue.shade800,
                  ),
                ),
                if (platformCommission > 0)
                  Text(
                    'Potongan Platform: Rp ${_fmt(platformCommission)} (otomatis)',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoucherRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined,
              color: Colors.purple.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Piutang Voucher B2B',
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Belum masuk kas — menunggu pembayaran institusi: Rp ${_fmt(totalVoucher)}',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.purple.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
