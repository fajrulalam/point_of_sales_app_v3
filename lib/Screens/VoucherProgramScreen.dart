import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Services/VoucherProgramService.dart';

class VoucherProgramScreen extends StatefulWidget {
  const VoucherProgramScreen({Key? key}) : super(key: key);

  @override
  State<VoucherProgramScreen> createState() => _VoucherProgramScreenState();
}

class _VoucherProgramScreenState extends State<VoucherProgramScreen> {
  List<Map<String, dynamic>> _programs = [];
  bool _isLoading = true;
  bool _showAll = false;

  static final _fmt =
      NumberFormat.decimalPattern('id_ID');

  @override
  void initState() {
    super.initState();
    _loadPrograms();
  }

  Future<void> _loadPrograms() async {
    setState(() => _isLoading = true);
    final list = _showAll
        ? await VoucherProgramService.getAllPrograms()
        : await VoucherProgramService.getActivePrograms();
    if (mounted) setState(() { _programs = list; _isLoading = false; });
  }

  String _fmt2(int v) => 'Rp ${_fmt.format(v)}';

  Color _statusColor(String status) {
    switch (status) {
      case 'paid': return Colors.green.shade700;
      case 'closed': return Colors.grey.shade600;
      default: return const Color(0xFF069494);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'paid': return 'Lunas';
      case 'closed': return 'Ditutup';
      default: return 'Aktif';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Program Voucher B2B',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: const Color(0xFF069494),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() => _showAll = !_showAll);
              _loadPrograms();
            },
            icon: Icon(_showAll ? Icons.filter_list_off : Icons.filter_list,
                size: 18),
            label: Text(
              _showAll ? 'Hanya Aktif' : 'Semua',
              style: GoogleFonts.poppins(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF069494),
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Buat Program',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _programs.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadPrograms,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _programs.length,
                    itemBuilder: (_, i) => _buildCard(_programs[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            _showAll ? 'Belum ada program' : 'Tidak ada program aktif',
            style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            'Tekan "+ Buat Program" untuk memulai',
            style: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> program) {
    final id = program['id'] as String;
    final name = program['programName'] ?? '';
    final institution = program['institutionName'] ?? '';
    final status = program['status'] ?? 'active';
    final redeemed = (program['totalRedeemed'] ?? 0) as int;
    final settled = (program['totalSettled'] ?? 0) as int;
    final outstanding = redeemed - settled;
    final notes = program['notes'] ?? '';
    final defaultNominal = (program['defaultNominal'] ?? 0) as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        institution,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (defaultNominal > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Nominal: ${_fmt2(defaultNominal)} / voucher',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor(status).withOpacity(0.4)),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor(status),
                    ),
                  ),
                ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                notes,
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
            const SizedBox(height: 12),
            // Financial summary
            Row(
              children: [
                _buildStat('Total Ditebus', redeemed, Colors.orange.shade700),
                const SizedBox(width: 12),
                _buildStat('Sudah Dibayar', settled, Colors.green.shade700),
                const SizedBox(width: 12),
                _buildStat(
                  'Sisa Piutang',
                  outstanding,
                  outstanding > 0 ? Colors.red.shade700 : Colors.grey.shade500,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showEditDialog(id, name, institution, notes, defaultNominal),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text('Edit', style: GoogleFonts.poppins(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
                if (status == 'active') ...[
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _showSettleDialog(id, name, outstanding),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: Text('Catat Pembayaran',
                        style: GoogleFonts.poppins(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF069494),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _confirmSettle(id, name, outstanding),
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: Text('Tutup & Lunasi', style: GoogleFonts.poppins(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                  fontSize: 10, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 2),
            Text(
              _fmt2(value),
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final instCtrl = TextEditingController();
    final nominalCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Buat Program Baru',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(nameCtrl, 'Nama Program', 'Cth: UNIPDU Fak. Bisnis'),
              const SizedBox(height: 12),
              _dialogTextField(instCtrl, 'Nama Institusi', 'Cth: UNIPDU'),
              const SizedBox(height: 12),
              TextField(
                controller: nominalCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  TextInputFormatter.withFunction((old, newVal) {
                    if (newVal.text.isEmpty) return newVal;
                    final plain = newVal.text.replaceAll('.', '');
                    if (plain.isEmpty) return newVal;
                    final formatted =
                        NumberFormat('#,###', 'id_ID').format(int.parse(plain));
                    return TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }),
                ],
                decoration: InputDecoration(
                  labelText: 'Nominal Voucher (Rp)',
                  hintText: 'Cth: 15000',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              _dialogTextField(notesCtrl, 'Catatan (opsional)', ''),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF069494),
                foregroundColor: Colors.white),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final inst = instCtrl.text.trim();
              if (name.isEmpty || inst.isEmpty) return;
              final nominal = int.tryParse(nominalCtrl.text.replaceAll('.', '')) ?? 0;
              Navigator.pop(ctx);
              await VoucherProgramService.createProgram(
                programName: name,
                institutionName: inst,
                defaultNominal: nominal,
                notes: notesCtrl.text.trim(),
              );
              _loadPrograms();
            },
            child: Text('Buat', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
      String id, String name, String institution, String notes, int defaultNominal) {
    final nameCtrl = TextEditingController(text: name);
    final instCtrl = TextEditingController(text: institution);
    final nominalCtrl = TextEditingController(
      text: defaultNominal > 0
          ? NumberFormat('#,###', 'id_ID').format(defaultNominal)
          : '',
    );
    final notesCtrl = TextEditingController(text: notes);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Program',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(nameCtrl, 'Nama Program', ''),
              const SizedBox(height: 12),
              _dialogTextField(instCtrl, 'Nama Institusi', ''),
              const SizedBox(height: 12),
              TextField(
                controller: nominalCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  TextInputFormatter.withFunction((old, newVal) {
                    if (newVal.text.isEmpty) return newVal;
                    final plain = newVal.text.replaceAll('.', '');
                    if (plain.isEmpty) return newVal;
                    final formatted =
                        NumberFormat('#,###', 'id_ID').format(int.parse(plain));
                    return TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }),
                ],
                decoration: InputDecoration(
                  labelText: 'Nominal Voucher (Rp)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              _dialogTextField(notesCtrl, 'Catatan (opsional)', ''),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF069494),
                foregroundColor: Colors.white),
            onPressed: () async {
              final n = nameCtrl.text.trim();
              final i = instCtrl.text.trim();
              if (n.isEmpty || i.isEmpty) return;
              final nominal =
                  int.tryParse(nominalCtrl.text.replaceAll('.', '')) ?? 0;
              Navigator.pop(ctx);
              await VoucherProgramService.updateProgram(id, {
                'programName': n,
                'institutionName': i,
                'defaultNominal': nominal,
                'notes': notesCtrl.text.trim(),
              });
              _loadPrograms();
            },
            child: Text('Simpan',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showSettleDialog(String id, String name, int outstanding) {
    final amountCtrl = TextEditingController();
    String selectedMethod = 'Cash';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Catat Pembayaran',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey.shade700),
                ),
                if (outstanding > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Sisa piutang: ${_fmt2(outstanding)}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    TextInputFormatter.withFunction((old, newVal) {
                      if (newVal.text.isEmpty) return newVal;
                      final plain = newVal.text.replaceAll('.', '');
                      if (plain.isEmpty) return newVal;
                      final formatted =
                          NumberFormat('#,###', 'id_ID').format(int.parse(plain));
                      return TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(
                            offset: formatted.length),
                      );
                    }),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Jumlah dibayar (Rp)',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Metode Pembayaran',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['Cash', 'QRIS', 'Online'].map((m) {
                    return ChoiceChip(
                      label: Text(m),
                      selected: selectedMethod == m,
                      selectedColor: const Color(0xFFC8E6C9),
                      labelStyle: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: selectedMethod == m
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selectedMethod == m
                            ? const Color(0xFF2E7D32)
                            : Colors.black87,
                      ),
                      onSelected: (_) =>
                          setStateDialog(() => selectedMethod = m),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Batal', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF069494),
                  foregroundColor: Colors.white),
              onPressed: () async {
                final plain =
                    amountCtrl.text.replaceAll('.', '').replaceAll(',', '');
                final amount = int.tryParse(plain) ?? 0;
                if (amount <= 0) return;
                Navigator.pop(ctx);
                await VoucherProgramService.settleProgram(
                  programId: id,
                  settledAmount: amount,
                  paymentMethod: selectedMethod,
                );
                _loadPrograms();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      'Pembayaran ${_fmt2(amount)} via $selectedMethod dicatat',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                    backgroundColor: Colors.green,
                  ));
                }
              },
              child: Text('Simpan',
                  style:
                      GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSettle(String id, String name, int outstanding) {
    String selectedMethod = 'Cash';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Tutup & Lunasi Program?',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Program "$name" akan ditutup dan sisa piutang sebesar ${_fmt2(outstanding)} akan dilunasi.',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                if (outstanding > 0) ...[
                  const SizedBox(height: 16),
                  Text('Metode Pembayaran',
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Cash', 'QRIS', 'Online'].map((m) {
                      return ChoiceChip(
                        label: Text(m),
                        selected: selectedMethod == m,
                        selectedColor: const Color(0xFFC8E6C9),
                        labelStyle: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: selectedMethod == m
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selectedMethod == m
                              ? const Color(0xFF2E7D32)
                              : Colors.black87,
                        ),
                        onSelected: (_) =>
                            setStateDialog(() => selectedMethod = m),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Batal', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                if (outstanding > 0) {
                  await VoucherProgramService.settleProgram(
                    programId: id,
                    settledAmount: outstanding,
                    paymentMethod: selectedMethod,
                  );
                }
                await VoucherProgramService.closeProgram(id);
                _loadPrograms();
              },
              child: Text('Tutup & Lunasi',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogTextField(
      TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      style: GoogleFonts.poppins(fontSize: 14),
    );
  }
}
