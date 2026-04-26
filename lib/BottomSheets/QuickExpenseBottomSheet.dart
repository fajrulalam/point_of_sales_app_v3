import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

class QuickExpenseBottomSheet extends StatefulWidget {
  const QuickExpenseBottomSheet({Key? key}) : super(key: key);

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QuickExpenseBottomSheet(),
    );
  }

  @override
  State<QuickExpenseBottomSheet> createState() =>
      _QuickExpenseBottomSheetState();
}

class _QuickExpenseBottomSheetState extends State<QuickExpenseBottomSheet> {
  final _categoryController = TextEditingController();
  final _amountController = TextEditingController();
  String _sourceAccount = 'Cash';
  bool _isSaving = false;

  // Today's expenses loaded from Firestore
  List<Map<String, dynamic>> _todayExpenses = [];
  bool _isLoadingExpenses = true;

  @override
  void initState() {
    super.initState();
    _fetchTodayExpenses();
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _amountController.dispose();
    super.dispose();
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

  int _parseFormattedNumber(String text) {
    if (text.isEmpty) return 0;
    return int.tryParse(text.replaceAll('.', '')) ?? 0;
  }

  String _fmt(int value) {
    return NumberFormat.decimalPattern('id_ID').format(value);
  }

  Future<void> _fetchTodayExpenses() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snap = await FirebaseFirestore.instance
          .collection(Col.name('Expenses'))
          .where('addedFromDashboardWeb', isEqualTo: false)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('timestamp', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _todayExpenses = snap.docs.map((d) {
            final data = d.data();
            data['docId'] = d.id;
            return data;
          }).toList();
          _isLoadingExpenses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingExpenses = false);
      }
    }
  }

  Future<void> _saveExpense() async {
    final category = _categoryController.text.trim();
    final amount = _parseFormattedNumber(_amountController.text);

    if (category.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Isi kategori dan jumlah terlebih dahulu',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection(Col.name('Expenses')).add({
        'category': category,
        'canteenId': 'canteen375_plazaUnipdu',
        'amount': amount,
        'sourceAccount': _sourceAccount,
        'timestamp': FieldValue.serverTimestamp(),
        'addedFromDashboardWeb': false,
      });

      _categoryController.clear();
      _amountController.clear();
      setState(() {
        _sourceAccount = 'Cash';
        _isSaving = false;
      });

      // Refresh the list
      await _fetchTodayExpenses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  'Pengeluaran berhasil dicatat',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteExpense(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Hapus Pengeluaran?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text('Data yang sudah dihapus tidak bisa dikembalikan.',
            style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Hapus', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection(Col.name('Expenses'))
          .doc(docId)
          .delete();
      await _fetchTodayExpenses();
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
                Icon(Icons.receipt_long, color: Colors.orange.shade700, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Catat Pengeluaran',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context, _todayExpenses.isNotEmpty),
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
                top: 16,
                bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildExpenseForm(),
                  const SizedBox(height: 24),
                  _buildTodayExpensesList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tambah Pengeluaran Baru',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.orange.shade800,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _categoryController,
            decoration: InputDecoration(
              labelText: 'Kategori (mis. Kerupuk, Es Batu)',
              labelStyle: GoogleFonts.poppins(fontSize: 13),
              prefixIcon: Icon(Icons.category_outlined, color: Colors.orange.shade600),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.orange.shade600, width: 2),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: _currencyFormatter,
                  decoration: InputDecoration(
                    labelText: 'Jumlah (Rp)',
                    labelStyle: GoogleFonts.poppins(fontSize: 13),
                    prefixIcon: Icon(Icons.payments_outlined, color: Colors.orange.shade600),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.orange.shade600, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  value: _sourceAccount,
                  decoration: InputDecoration(
                    labelText: 'Sumber Dana',
                    labelStyle: GoogleFonts.poppins(fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: ['Cash', 'QRIS', 'Online']
                      .map((acc) => DropdownMenuItem(
                            value: acc,
                            child: Text(acc, style: GoogleFonts.poppins(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _sourceAccount = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveExpense,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_circle_outline),
              label: Text(
                _isSaving ? 'Menyimpan...' : 'Simpan Pengeluaran',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayExpensesList() {
    final totalToday = _todayExpenses.fold<int>(
        0, (sum, e) => sum + ((e['amount'] ?? 0) as int));

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
            if (!_isLoadingExpenses && _todayExpenses.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Total: Rp ${_fmt(totalToday)}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingExpenses)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_todayExpenses.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'Belum ada pengeluaran hari ini',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          )
        else
          ...List.generate(_todayExpenses.length, (i) {
            final expense = _todayExpenses[i];
            final sourceIcon = _sourceIcon(expense['sourceAccount'] ?? 'Cash');
            final sourceColor = _sourceColor(expense['sourceAccount'] ?? 'Cash');
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: sourceColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(sourceIcon, size: 18, color: sourceColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          expense['category'] ?? '-',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          expense['sourceAccount'] ?? 'Cash',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Rp ${_fmt((expense['amount'] ?? 0) as int)}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => _deleteExpense(expense['docId']),
                    icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade300),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            );
          }),
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

  Color _sourceColor(String source) {
    switch (source) {
      case 'QRIS':
        return Colors.blue;
      case 'Online':
        return Colors.purple;
      default:
        return Colors.green;
    }
  }
}
