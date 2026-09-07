import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:point_of_sales_app_v3/Models/Member.dart';
import 'package:point_of_sales_app_v3/Services/MemberService.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Services/UserMessageService.dart';
import 'package:point_of_sales_app_v3/Services/MemberProgramService.dart';
import 'package:point_of_sales_app_v3/Services/MemberProgramAuditService.dart';
import 'package:point_of_sales_app_v3/Models/MemberProgramModels.dart';

class MarketingScreen extends StatefulWidget {
  const MarketingScreen({Key? key}) : super(key: key);

  @override
  _MarketingScreenState createState() => _MarketingScreenState();
}

class _MarketingScreenState extends State<MarketingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Member Tab State
  final MemberService _memberService = MemberService.instance;
  List<Member> _members = [];
  List<Member> _allMembers = []; // Cached full list for local filtering
  bool _isLoadingMembers = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce; // Debounce timer for search

  // Campaign Tab State
  bool _isLoadingCampaigns = false;
  List<QueryDocumentSnapshot> _campaigns = [];

  // Competition Points State (cached for local filtering)
  Map<String, int> _competitionPoints = {};
  Map<String, int> _competitionRanks = {};
  bool _isProcessingProgramAction = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rebuild FAB on tab change
    });

    // Listen for testing mode changes to refresh data
    Col.testingMode.addListener(_onTestingModeChanged);

    _initializeData();
  }

  Future<void> _initializeData() async {
    if (mounted) setState(() => _isLoadingMembers = true);
    await _memberService.fetchAndCacheMembers();
    if (mounted) {
      _loadMembers();
      _loadCampaigns();
    }
  }

  void _onTestingModeChanged() async {
    if (mounted) {
      setState(() => _isLoadingMembers = true);
      // Wait for the service to finish clearing and re-fetching
      await _memberService.fetchAndCacheMembers();
      if (mounted) {
        await _loadMembers();
        _loadCampaigns();
      }
    }
  }

  @override
  void dispose() {
    Col.testingMode.removeListener(_onTestingModeChanged);
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoadingMembers = true);
    try {
      final members = await _memberService.getCachedMembers();

      final monthDocId = MemberProgramService.periodIdFor(DateTime.now());
      final competitionMembers =
          await MemberProgramService.loadCompetitionMembers(monthDocId);
      final ranked =
          MemberProgramService.rankCompetitionMembers(competitionMembers);
      final pointsMap = <String, int>{};
      final recordsMap = <String, Map<String, dynamic>>{};
      for (final record in competitionMembers) {
        recordsMap[record.memberId] = {
          'customerPoints': record.customerPoints,
          'amountSpent': record.amountSpent,
          'numberOfTransaction': record.numberOfTransaction,
          'category': record.category,
        };
        pointsMap[record.memberId] = record.customerPoints;
      }

      // Sort members by competition points descending
      final sortedMembers = List<Member>.from(members);
      sortedMembers.sort((a, b) {
        final recordA = recordsMap[a.id] ??
            {'customerPoints': 0, 'amountSpent': 0, 'numberOfTransaction': 0};
        final recordB = recordsMap[b.id] ??
            {'customerPoints': 0, 'amountSpent': 0, 'numberOfTransaction': 0};

        int pointsCompare =
            recordB['customerPoints'].compareTo(recordA['customerPoints']);
        if (pointsCompare != 0) return pointsCompare;

        int amountCompare =
            recordB['amountSpent'].compareTo(recordA['amountSpent']);
        if (amountCompare != 0) return amountCompare;

        final transactionCompare = recordB['numberOfTransaction']
            .compareTo(recordA['numberOfTransaction']);
        if (transactionCompare != 0) return transactionCompare;
        return a.id.compareTo(b.id);
      });

      setState(() {
        _allMembers = sortedMembers; // Cache full sorted list
        _members = sortedMembers;
        _competitionPoints = pointsMap;
        _competitionRanks = {
          for (var index = 0; index < ranked.length; index++)
            ranked[index].memberId: index + 1
        };
        _isLoadingMembers = false;
      });
    } catch (e) {
      print('Error loading members/points: $e');
      setState(() => _isLoadingMembers = false);
    }
  }

  Future<void> _handleRefreshMembers() async {
    setState(() => _isLoadingMembers = true);
    try {
      await _memberService.forceSync();
      await _loadMembers();
    } catch (e) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
                'Gagal memperbarui data member: ${UserMessageService.fromError(e)}'),
          ),
        );
    } finally {
      setState(() => _isLoadingMembers = false);
    }
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);

    // Cancel any existing debounce timer
    _searchDebounce?.cancel();

    // If query is empty, show all members immediately
    if (query.isEmpty) {
      setState(() => _members = _allMembers);
      return;
    }

    // Debounce search by 500ms (optimized for tablet typing speed)
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _executeSearch(query);
    });
  }

  void _executeSearch(String query) {
    // Filter locally from cached data (no Firestore call needed)
    final lowerQuery = query.toLowerCase();
    final results = _allMembers.where((member) {
      return member.name.toLowerCase().contains(lowerQuery) ||
          member.phoneNumber.contains(query);
    }).toList();

    // Results are already sorted since _allMembers is sorted
    if (mounted) {
      setState(() => _members = results);
    }
  }

  Future<void> _loadCampaigns({bool forceRefresh = false}) async {
    setState(() => _isLoadingCampaigns = true);
    try {
      final query = FirebaseFirestore.instance
          .collection(Col.name('voucherGroup'))
          .where('type', isEqualTo: 'cashbackCampaign');

      final snapshot = forceRefresh
          ? await query.get(const GetOptions(source: Source.server))
          : await query.get();

      final docs = snapshot.docs;

      setState(() {
        _campaigns = docs;
        _campaigns.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = MemberProgramValues.dateValue(aData['createdAt']);
          final bTime = MemberProgramValues.dateValue(bData['createdAt']);
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });
      });
    } catch (e) {
      print('Error loading campaigns: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCampaigns = false);
    }
  }

  void _showAddMemberDialog() {
    showDialog(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: Text('Daftar Member Baru',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'Anda akan diarahkan ke halaman pendaftaran member eksternal. Lanjutkan?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext),
            child:
                Text('Batal', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(confirmContext);
              final Uri url = Uri.parse(
                  'https://canteen-375-registration.vercel.app/register');
              if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      const SnackBar(
                          content:
                              Text('Tidak dapat membuka halaman pendaftaran')),
                    );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            child: Text('Ya, Lanjutkan', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showAddCampaignModal() {
    final nameController = TextEditingController();
    final thresholdController = TextEditingController();
    final valueController = TextEditingController();
    final requirementsController = TextEditingController();

    DateTime? startDate;
    DateTime? endDate;

    // Validation state
    String? nameError;
    String? thresholdError;
    String? valueError;
    String? requirementsError;
    String? dateError;
    var isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Currency formatter for Rupiah fields
            String formatCurrency(String value) {
              if (value.isEmpty) return '';
              final number = int.tryParse(value.replaceAll('.', '')) ?? 0;
              return NumberFormat('#,###', 'id_ID').format(number);
            }

            int parseCurrency(String value) {
              return int.tryParse(value.replaceAll('.', '')) ?? 0;
            }

            Future<void> selectDate(bool isStart) async {
              final date = await showDatePicker(
                context: context,
                initialDate: isStart
                    ? DateTime.now()
                    : (startDate?.add(const Duration(days: 30)) ??
                        DateTime.now()),
                firstDate:
                    isStart ? DateTime.now() : (startDate ?? DateTime.now()),
                lastDate: DateTime(2100),
              );
              if (date != null) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: isStart
                      ? TimeOfDay.now()
                      : const TimeOfDay(hour: 23, minute: 59),
                );
                if (time != null) {
                  setModalState(() {
                    final combined = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                    if (isStart) {
                      startDate = combined;
                      // Auto-clear end date if it's before new start date
                      if (endDate != null && endDate!.isBefore(startDate!)) {
                        endDate = null;
                      }
                    } else {
                      endDate = combined;
                    }
                    dateError = null;
                  });
                }
              }
            }

            void validateAndSubmit() async {
              if (isSubmitting) return;
              // Reset errors
              setModalState(() {
                nameError = null;
                thresholdError = null;
                valueError = null;
                requirementsError = null;
                dateError = null;
              });

              bool hasError = false;

              if (nameController.text.trim().isEmpty) {
                setModalState(() => nameError = 'Nama campaign wajib diisi');
                hasError = true;
              }

              if (thresholdController.text.isEmpty) {
                setModalState(() => thresholdError = 'Target poin wajib diisi');
                hasError = true;
              } else if (int.tryParse(thresholdController.text) == null ||
                  int.parse(thresholdController.text) <= 0) {
                setModalState(
                    () => thresholdError = 'Masukkan angka yang valid');
                hasError = true;
              }

              if (valueController.text.isEmpty) {
                setModalState(() => valueError = 'Nilai cashback wajib diisi');
                hasError = true;
              } else if (parseCurrency(valueController.text) <= 0) {
                setModalState(() => valueError = 'Masukkan nilai yang valid');
                hasError = true;
              }

              if (requirementsController.text.isEmpty) {
                setModalState(
                    () => requirementsError = 'Syarat transaksi wajib diisi');
                hasError = true;
              } else if (parseCurrency(requirementsController.text) <= 0) {
                setModalState(
                    () => requirementsError = 'Masukkan nilai yang valid');
                hasError = true;
              }

              if (startDate == null || endDate == null) {
                setModalState(
                    () => dateError = 'Pilih tanggal mulai dan berakhir');
                hasError = true;
              } else if (endDate!.isBefore(startDate!)) {
                setModalState(() =>
                    dateError = 'Tanggal berakhir harus setelah tanggal mulai');
                hasError = true;
              }

              if (hasError) return;

              setModalState(() => isSubmitting = true);
              setState(() => _isLoadingCampaigns = true);

              try {
                await MemberProgramService.createCampaign(
                  name: nameController.text,
                  threshold: int.parse(thresholdController.text),
                  value: parseCurrency(valueController.text),
                  transactionRequirement:
                      parseCurrency(requirementsController.text),
                  activeDate: startDate!,
                  expireDate: endDate!,
                );

                await _loadCampaigns();

                if (modalContext.mounted) Navigator.pop(modalContext);

                if (!mounted) return;
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 12),
                          const Text('Campaign berhasil dibuat'),
                        ],
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                          'Gagal membuat kampanye: ${UserMessageService.fromError(e)}'),
                    ),
                  );
              } finally {
                if (mounted) {
                  setState(() => _isLoadingCampaigns = false);
                }
                if (modalContext.mounted) {
                  setModalState(() => isSubmitting = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.campaign, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 12),
                        Text('Buat Campaign Baru',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 18)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Campaign Name
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Nama Campaign',
                        hintText: 'Misal: Promo Akhir Tahun',
                        border: const OutlineInputBorder(),
                        errorText: nameError,
                        prefixIcon: const Icon(Icons.label_outline),
                      ),
                      onChanged: (_) => setModalState(() => nameError = null),
                    ),
                    const SizedBox(height: 16),

                    // Target Points
                    TextField(
                      controller: thresholdController,
                      decoration: InputDecoration(
                        labelText: 'Target Poin',
                        hintText: 'Misal: 10',
                        helperText:
                            'Member mengumpulkan poin dari transaksi (1 poin per Rp 10.000)',
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        errorText: thresholdError,
                        prefixIcon: const Icon(Icons.emoji_events_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) =>
                          setModalState(() => thresholdError = null),
                    ),
                    const SizedBox(height: 16),

                    // Cashback Value (with Rupiah formatting)
                    TextField(
                      controller: valueController,
                      decoration: InputDecoration(
                        labelText: 'Nilai Cashback',
                        hintText: '50.000',
                        prefixText: 'Rp ',
                        border: const OutlineInputBorder(),
                        errorText: valueError,
                        prefixIcon: const Icon(Icons.card_giftcard_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          if (newValue.text.isEmpty) return newValue;
                          final formatted = formatCurrency(newValue.text);
                          return TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                                offset: formatted.length),
                          );
                        }),
                      ],
                      onChanged: (_) => setModalState(() => valueError = null),
                    ),
                    const SizedBox(height: 16),

                    // Min Transaction Requirement
                    TextField(
                      controller: requirementsController,
                      decoration: InputDecoration(
                        labelText: 'Syarat Minimum Transaksi untuk Redeem',
                        hintText: '20.000',
                        prefixText: 'Rp ',
                        helperText:
                            'Member harus belanja minimal ini saat redeem voucher',
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        errorText: requirementsError,
                        prefixIcon: const Icon(Icons.receipt_long_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          if (newValue.text.isEmpty) return newValue;
                          final formatted = formatCurrency(newValue.text);
                          return TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                                offset: formatted.length),
                          );
                        }),
                      ],
                      onChanged: (_) =>
                          setModalState(() => requirementsError = null),
                    ),
                    const SizedBox(height: 20),

                    // Date Selection
                    Text('Periode Campaign',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500, fontSize: 14)),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => selectDate(true),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: dateError != null
                                      ? Colors.red
                                      : Colors.grey.shade400,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today,
                                      size: 18,
                                      color: startDate != null
                                          ? const Color(0xFF2E7D32)
                                          : Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      startDate == null
                                          ? 'Mulai'
                                          : DateFormat('dd MMM yyyy\nHH:mm')
                                              .format(startDate!),
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: startDate != null
                                            ? Colors.black87
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward,
                              color: Colors.grey.shade400),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => selectDate(false),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: dateError != null
                                      ? Colors.red
                                      : Colors.grey.shade400,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today,
                                      size: 18,
                                      color: endDate != null
                                          ? const Color(0xFF2E7D32)
                                          : Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      endDate == null
                                          ? 'Berakhir'
                                          : DateFormat('dd MMM yyyy\nHH:mm')
                                              .format(endDate!),
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: endDate != null
                                            ? Colors.black87
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (dateError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          dateError!,
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.red),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.pop(modalContext),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.grey.shade400),
                            ),
                            child: Text('Batal',
                                style: GoogleFonts.poppins(
                                    color: Colors.grey.shade700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : validateAndSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text('Buat Campaign',
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMemberEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchQuery.isEmpty ? Icons.people_outline : Icons.search_off,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'Belum ada member terdaftar'
                : 'Member tidak ditemukan',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Member akan muncul setelah mendaftar melalui\nweb app atau ditambahkan dari sini'
                : 'Coba gunakan kata kunci lain',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddMemberDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Tambah Member'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    final visibleMembers = _members;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Peringkat Global ${MemberProgramService.periodIdFor(DateTime.now())} • 3 Pemenang',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Cari member (nama atau telepon)...',
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: _isLoadingMembers
              ? const Center(child: CircularProgressIndicator())
              : visibleMembers.isEmpty
                  ? _buildMemberEmptyState()
                  : RefreshIndicator(
                      onRefresh: _handleRefreshMembers,
                      color: const Color(0xFF2E7D32),
                      child: ListView.builder(
                        itemCount: visibleMembers.length,
                        itemBuilder: (context, index) {
                          final member = visibleMembers[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFE8F5E9),
                                child: Text(member.name.isEmpty
                                    ? '?'
                                    : member.name[0].toUpperCase()),
                              ),
                              title: Text(
                                  _competitionRanks.containsKey(member.id)
                                      ? '#${_competitionRanks[member.id]} • ${member.name}'
                                      : member.name,
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500)),
                              subtitle: Text(member.phoneNumber),
                              trailing: ElevatedButton(
                                onPressed: () =>
                                    _showMemberProgressSheet(member),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE8F5E9),
                                  foregroundColor: const Color(0xFF1B5E20),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Progres',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildCampaignEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.campaign_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Belum ada campaign',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Buat campaign pertama untuk memulai\nprogram loyalitas member',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed:
                _isProcessingProgramAction ? null : _showAddCampaignModal,
            icon: const Icon(Icons.add),
            label: const Text('Buat Campaign'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampaignsTab() {
    return _isLoadingCampaigns
        ? const Center(child: CircularProgressIndicator())
        : _campaigns.isEmpty
            ? _buildCampaignEmptyState()
            : RefreshIndicator(
                onRefresh: () => _loadCampaigns(forceRefresh: true),
                color: const Color(0xFF2E7D32),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _campaigns.length,
                  itemBuilder: (context, index) {
                    final campaignDoc = _campaigns[index];
                    final campaign = campaignDoc.data() as Map<String, dynamic>;
                    final startDate =
                        MemberProgramValues.dateValue(campaign['activeDate']);
                    final endDate =
                        MemberProgramValues.dateValue(campaign['expireDate']);
                    final campaignStatus =
                        campaign['status']?.toString().toLowerCase() ?? '';
                    final isActive = campaign['isActive'] == true &&
                        campaignStatus == 'active';

                    final now = DateTime.now();
                    final isCurrentlyRunning = isActive &&
                        startDate != null &&
                        endDate != null &&
                        !now.isBefore(startDate) &&
                        !now.isAfter(endDate);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isCurrentlyRunning
                              ? Colors.green.shade200
                              : Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => _showCampaignDetailsSheet(campaignDoc),
                        onLongPress: () =>
                            _showCampaignOptionsMenu(campaignDoc),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header: Title + Status
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      campaign['voucherName'] ?? 'No Name',
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isCurrentlyRunning
                                          ? Colors.green.shade100
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isCurrentlyRunning ? 'Aktif' : 'Nonaktif',
                                      style: TextStyle(
                                        color: isCurrentlyRunning
                                            ? Colors.green.shade800
                                            : Colors.grey.shade700,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Key Info Row: Reward + Target
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(Icons.card_giftcard,
                                            size: 18,
                                            color: Colors.orange.shade700),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Rp ${NumberFormat.decimalPattern().format(MemberProgramService.parseInt(campaign['value']))}',
                                          style: GoogleFonts.poppins(
                                            color: Colors.orange.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE8F5E9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${MemberProgramService.parseInt(campaign['threshold'])} pts',
                                      style: GoogleFonts.poppins(
                                        color: const Color(0xFF1B5E20),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Date Range (condensed)
                              Row(
                                children: [
                                  Icon(Icons.schedule,
                                      size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 6),
                                  Text(
                                    startDate != null && endDate != null
                                        ? '${DateFormat('dd MMM').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}'
                                        : 'Tanggal campaign tidak valid',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color:
                                          startDate != null && endDate != null
                                              ? Colors.grey.shade700
                                              : Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),

                              // Min Transaction
                              Row(
                                children: [
                                  Icon(Icons.receipt_long,
                                      size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Min. transaksi Rp ${NumberFormat.decimalPattern().format(MemberProgramService.parseInt(campaign['transactionRequirement']))}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),

                              const Divider(height: 20),

                              // Stats Row
                              Row(
                                children: [
                                  _buildCampaignStat(
                                      Icons.people,
                                      '${MemberProgramService.parseInt(campaign['totalParticipants'])}',
                                      'Peserta'),
                                  const SizedBox(width: 24),
                                  _buildCampaignStat(
                                      Icons.check_circle,
                                      '${MemberProgramService.parseInt(campaign['totalClaimed'])}',
                                      'Diklaim'),
                                  const Spacer(),
                                  Icon(Icons.chevron_right,
                                      color: Colors.grey.shade400),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
  }

  Widget _buildCampaignStat(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  void _showCampaignOptionsMenu(QueryDocumentSnapshot campaignDoc) {
    final campaign = campaignDoc.data() as Map<String, dynamic>;
    final isArchived =
        campaign['status']?.toString().toLowerCase() == 'archived' ||
            campaign['isActive'] != true;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                campaign['voucherName'] ?? 'Campaign',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blue),
              title: Text('Lihat Detail', style: GoogleFonts.poppins()),
              onTap: () {
                Navigator.pop(context);
                _showCampaignDetailsSheet(campaignDoc);
              },
            ),
            if (!isArchived)
              ListTile(
                leading:
                    const Icon(Icons.archive_outlined, color: Colors.orange),
                title: Text('Arsipkan Campaign',
                    style: GoogleFonts.poppins(color: Colors.orange.shade800)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmArchiveCampaign(campaignDoc);
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _confirmArchiveCampaign(QueryDocumentSnapshot campaignDoc) {
    final campaign = campaignDoc.data() as Map<String, dynamic>;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Arsipkan Campaign?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'Campaign "${campaign['voucherName']}" akan dihentikan. Riwayat tetap disimpan dan voucher yang belum digunakan akan dinonaktifkan.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('Batal', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_isProcessingProgramAction) return;
              setState(() => _isProcessingProgramAction = true);
              Navigator.pop(context);
              try {
                await MemberProgramService.archiveCampaign(campaignDoc.id);
                await _loadCampaigns();

                if (mounted) {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Campaign berhasil diarsipkan'),
                        backgroundColor: Colors.green,
                      ),
                    );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                            'Gagal mengarsipkan kampanye: ${UserMessageService.fromError(e)}'),
                      ),
                    );
                }
              }
              if (mounted) setState(() => _isProcessingProgramAction = false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            child: Text('Arsipkan', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showCampaignDetailsSheet(QueryDocumentSnapshot campaignDoc) {
    final campaignData = campaignDoc.data() as Map<String, dynamic>;
    final campaignId = campaignDoc.id;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      campaignData['voucherName'] ?? 'Detail Campaign',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF861216),
                      ),
                    ),
                    Text(
                      'Monitoring Progress Peserta',
                      style: GoogleFonts.poppins(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              Expanded(
                child: FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection(Col.name('vouchers'))
                      .where('voucherGroupId', isEqualTo: campaignId)
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final vouchers = snapshot.data?.docs ?? [];

                    if (vouchers.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'Belum ada peserta di campaign ini',
                              style: GoogleFonts.poppins(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: vouchers.length,
                      itemBuilder: (context, index) {
                        final v = vouchers[index];
                        final data = v.data() as Map<String, dynamic>;
                        final status = data['status']?.toString() ?? 'UNKNOWN';
                        final points =
                            MemberProgramService.parseInt(data['userPoints']);
                        final threshold =
                            MemberProgramService.parseInt(data['threshold']);
                        final progress = threshold <= 0
                            ? 0.0
                            : (points / threshold).clamp(0.0, 1.0);

                        // Fallback: If 'nama' is missing in voucher, find it from our local members list
                        final userId = data['userId'];
                        String participantName = data['nama'] ?? '';
                        if (participantName.trim().isEmpty && userId != null) {
                          try {
                            participantName =
                                _members.firstWhere((m) => m.id == userId).name;
                          } catch (_) {
                            participantName = 'Member Terhapus';
                          }
                        }
                        if (participantName.isEmpty) participantName = 'Member';

                        Color statusColor;
                        IconData statusIcon;
                        switch (status) {
                          case 'CLAIMED':
                            statusColor = Colors.grey;
                            statusIcon = Icons.check_circle;
                            break;
                          case 'READY_TO_CLAIM':
                            statusColor = Colors.green;
                            statusIcon = Icons.card_giftcard;
                            break;
                          case 'EXPIRED':
                            statusColor = Colors.red;
                            statusIcon = Icons.cancel;
                            break;
                          default:
                            statusColor = Colors.blue;
                            statusIcon = Icons.timer;
                        }

                        return _buildProgressCard(
                          participantName,
                          '$points / $threshold',
                          'Progress Poin',
                          statusIcon,
                          statusColor,
                          progress,
                          subtitle: 'Status: $status',
                          voucherCode: v.id,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMemberAdjustmentDialog(Member member) {
    final pointsController = TextEditingController();
    final reasonController = TextEditingController();
    String? errorText;
    var isSubmitting = false;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Penyesuaian Poin Administrator',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Member: ${member.name}',
                  style: GoogleFonts.poppins(fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: pointsController,
                enabled: !isSubmitting,
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true),
                decoration: InputDecoration(
                  labelText: 'Perubahan poin (+/-)',
                  hintText: 'Contoh: 10 atau -5',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() => errorText = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                enabled: !isSubmitting,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Alasan wajib diisi',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  isSubmitting ? null : () => Navigator.pop(dialogContext),
              child: Text('Batal', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final delta = int.tryParse(
                          pointsController.text.trim().replaceAll('.', ''));
                      final reason = reasonController.text.trim();
                      if (delta == null || delta == 0) {
                        setDialogState(() =>
                            errorText = 'Masukkan perubahan poin selain nol.');
                        return;
                      }
                      if (reason.isEmpty) {
                        setDialogState(() => errorText = 'Alasan wajib diisi.');
                        return;
                      }
                      if (_isProcessingProgramAction) return;
                      setDialogState(() => isSubmitting = true);
                      setState(() => _isProcessingProgramAction = true);
                      Navigator.pop(dialogContext);
                      try {
                        final user = FirebaseAuth.instance.currentUser;
                        final actorId = user?.uid ?? user?.email ?? '';
                        if (actorId.isEmpty) {
                          throw const MemberProgramException(
                              'Identitas administrator tidak tersedia.');
                        }
                        await MemberProgramService.applyAdministratorAdjustment(
                          operationId:
                              'manual_${member.id}_${DateTime.now().microsecondsSinceEpoch}',
                          memberId: member.id,
                          pointsDelta: delta,
                          reason: reason,
                          sourceId: member.id,
                          actorId: actorId,
                        );
                        await _loadMembers();
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(const SnackBar(
                                content: Text(
                                    'Penyesuaian poin berhasil disimpan.')));
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(SnackBar(
                                content: Text(
                                    'Penyesuaian gagal: ${UserMessageService.fromError(e)}')));
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isProcessingProgramAction = false);
                        }
                        pointsController.dispose();
                        reasonController.dispose();
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Simpan', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      ),
    );
  }

  void _showMemberProgressSheet(Member member) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFFE8F5E9),
                      child: Text(
                          member.name.isEmpty
                              ? '?'
                              : member.name[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(member.name,
                              style: GoogleFonts.poppins(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(member.phoneNumber,
                              style: GoogleFonts.poppins(
                                  color: Colors.grey.shade600, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Penyesuaian poin administrator',
                      onPressed: _isProcessingProgramAction
                          ? null
                          : () => _showMemberAdjustmentDialog(member),
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              Expanded(
                child: FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection(Col.name('vouchers'))
                      .where('userId', isEqualTo: member.id)
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    List<QueryDocumentSnapshot> vouchers =
                        snapshot.data?.docs ?? [];
                    // Sort client-side to avoid requiring a Firestore composite index
                    vouchers.sort((a, b) {
                      final aData = a.data() as Map<String, dynamic>;
                      final bData = b.data() as Map<String, dynamic>;
                      final aTime =
                          MemberProgramValues.dateValue(aData['lastUpdatedAt']);
                      final bTime =
                          MemberProgramValues.dateValue(bData['lastUpdatedAt']);
                      if (aTime == null && bTime == null) return 0;
                      if (aTime == null) return 1;
                      if (bTime == null) return -1;
                      return bTime.compareTo(aTime);
                    });
                    final compPoints = _competitionPoints[member.id] ?? 0;

                    return ListView(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        _buildSectionHeader('Progres Kompetisi'),
                        _buildProgressCard(
                          'Kompetisi Bulanan',
                          '$compPoints Pts',
                          'Poin Kompetisi',
                          Icons.emoji_events,
                          Colors.amber,
                          null,
                        ),
                        const SizedBox(height: 24),
                        _buildSectionHeader('Voucher Kampanye'),
                        if (vouchers.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text('Tidak ada voucher aktif',
                                style: GoogleFonts.poppins(color: Colors.grey)),
                          )
                        else
                          ...vouchers.take(3).map((v) {
                            final data = v.data() as Map<String, dynamic>;
                            final status =
                                data['status']?.toString() ?? 'UNKNOWN';
                            final points = MemberProgramService.parseInt(
                                data['userPoints']);
                            final threshold = MemberProgramService.parseInt(
                                data['threshold']);
                            final progress = threshold <= 0
                                ? 0.0
                                : (points / threshold).clamp(0.0, 1.0);

                            Color statusColor;
                            IconData statusIcon;
                            switch (status) {
                              case 'CLAIMED':
                                statusColor = Colors.grey;
                                statusIcon = Icons.check_circle;
                                break;
                              case 'EXPIRED':
                                statusColor = Colors.red;
                                statusIcon = Icons.cancel;
                                break;
                              case 'READY_TO_CLAIM':
                                statusColor = Colors.green;
                                statusIcon = Icons.card_giftcard;
                                break;
                              default:
                                statusColor = Colors.blue;
                                statusIcon = Icons.timer;
                            }

                            return _buildProgressCard(
                              data['voucherName'] ?? 'Voucher',
                              '$points / $threshold',
                              'Progress Poin',
                              statusIcon,
                              statusColor,
                              progress,
                              subtitle: 'Status: $status',
                              voucherCode: v.id,
                            );
                          }).toList(),
                        const SizedBox(height: 32),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF1B5E20),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildProgressCard(
    String title,
    String value,
    String label,
    IconData icon,
    Color color,
    double? progress, {
    String? subtitle,
    String? voucherCode,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              offset: const Offset(0, 4),
              blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: GoogleFonts.poppins(
                              color: Colors.grey.shade600, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: 15)),
                  Text(label,
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade500, fontSize: 10)),
                ],
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: color.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
          ],
          if (voucherCode != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.qr_code, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'KODE: $voucherCode',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showMemberProgramAudit() async {
    if (_isProcessingProgramAction) return;
    setState(() => _isProcessingProgramAction = true);
    List<MemberProgramAuditFinding> findings = const [];
    String? error;
    try {
      findings = await MemberProgramAuditService().runAudit();
    } catch (e) {
      error = UserMessageService.fromError(e);
    } finally {
      if (mounted) setState(() => _isProcessingProgramAction = false);
    }
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Audit gagal: $error')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Audit Member Program',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 560,
          height: 440,
          child: findings.isEmpty
              ? Center(
                  child: Text('Tidak ditemukan temuan audit.',
                      style: GoogleFonts.poppins()))
              : ListView.separated(
                  itemCount: findings.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (_, index) {
                    final finding = findings[index];
                    final color = finding.severity == 'high'
                        ? Colors.red.shade700
                        : finding.severity == 'medium'
                            ? Colors.orange.shade800
                            : Colors.blueGrey;
                    final canRetryExternal =
                        finding.code == 'external_voucher_claim_pending';
                    final canRetryCampaign =
                        finding.code == 'member_program_campaign_pending';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.warning_amber_rounded, color: color),
                      title: Text(finding.message,
                          style: GoogleFonts.poppins(fontSize: 12)),
                      subtitle: Text(
                        '${finding.severity.toUpperCase()} • ${finding.code}\n${finding.documentPath ?? ''}',
                        style: GoogleFonts.poppins(
                            fontSize: 10, color: Colors.grey.shade700),
                      ),
                      trailing: canRetryExternal || canRetryCampaign
                          ? TextButton(
                              onPressed: _isProcessingProgramAction
                                  ? null
                                  : () => canRetryExternal
                                      ? _retryExternalClaimFromFinding(
                                          finding,
                                        )
                                      : _retryCampaignFromFinding(finding),
                              child: Text('Coba lagi',
                                  style: GoogleFonts.poppins(fontSize: 11)),
                            )
                          : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Tutup', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  Future<void> _retryExternalClaimFromFinding(
      MemberProgramAuditFinding finding) async {
    final path = finding.documentPath;
    if (path == null || path.trim().isEmpty || _isProcessingProgramAction) {
      return;
    }
    final operationId = path.split('/').last;
    if (operationId.isEmpty) return;

    setState(() => _isProcessingProgramAction = true);
    try {
      await MemberProgramService.retryExternalClaim(operationId);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Klaim voucher e-santren sedang dicoba ulang.'),
            backgroundColor: Colors.green,
          ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(
                'Gagal mencoba ulang klaim e-santren: ${UserMessageService.fromError(e)}'),
          ));
      }
    } finally {
      if (mounted) setState(() => _isProcessingProgramAction = false);
    }
  }

  Future<void> _retryCampaignFromFinding(
      MemberProgramAuditFinding finding) async {
    final path = finding.documentPath;
    if (path == null || path.trim().isEmpty || _isProcessingProgramAction) {
      return;
    }
    final operationId = path.split('/').last;
    if (operationId.isEmpty) return;

    setState(() => _isProcessingProgramAction = true);
    try {
      await MemberProgramService.retryCampaignProgress(operationId);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Progres campaign berhasil dicoba ulang.'),
            backgroundColor: Colors.green,
          ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(
                'Gagal mencoba ulang progres campaign: ${UserMessageService.fromError(e)}'),
          ));
      }
    } finally {
      if (mounted) setState(() => _isProcessingProgramAction = false);
    }
  }

  Future<void> _finalizePreviousCompetitionMonth() async {
    if (_isProcessingProgramAction) return;
    setState(() => _isProcessingProgramAction = true);
    try {
      final now = MemberProgramService.nowJakarta();
      final previousMonth = DateTime(now.year, now.month - 1, 15);
      final periodId = MemberProgramService.periodIdFor(previousMonth);
      final winners = await MemberProgramService.finalizeCompetitionMonth(
        periodId: periodId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Kompetisi $periodId Difinalisasi',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 520,
            child: winners.isEmpty
                ? Text('Tidak ada pemenang yang memenuhi syarat.',
                    style: GoogleFonts.poppins())
                : ListView(
                    shrinkWrap: true,
                    children: winners
                        .map((winner) => ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 14,
                                child: Text('${winner.rank}'),
                              ),
                              title: Text(
                                  '${winner.rankingMode == CompetitionRankingMode.global ? 'Global' : MemberProgramService.categoryLabel(winner.category)} • ${winner.memberId}',
                                  style: GoogleFonts.poppins(fontSize: 12)),
                              subtitle: Text(
                                  'Rp ${NumberFormat.decimalPattern('id_ID').format(winner.prizeAmount)} • ${winner.voucherId}',
                                  style: GoogleFonts.poppins(fontSize: 11)),
                            ))
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Tutup', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(
                  'Gagal finalisasi kompetisi: ${UserMessageService.fromError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isProcessingProgramAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Marketing & Member',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            onPressed:
                _isProcessingProgramAction ? null : _showMemberProgramAudit,
            tooltip: 'Audit Member Program',
          ),
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: _isProcessingProgramAction
                ? null
                : _finalizePreviousCompetitionMonth,
            tooltip: 'Finalisasi Bulan Kompetisi',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isProcessingProgramAction
                ? null
                : () {
                    _handleRefreshMembers();
                    _loadCampaigns(forceRefresh: true);
                  },
            tooltip: 'Refresh Data',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF1A1A1A),
              unselectedLabelColor: Colors.grey.shade500,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                border: Border(
                  bottom: BorderSide(
                    color: Color(0xFF2E7D32),
                    width: 3,
                  ),
                ),
              ),
              labelStyle: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.poppins(
                  fontWeight: FontWeight.normal, fontSize: 14),
              tabs: const [
                Tab(text: 'Daftar Member'),
                Tab(text: 'Periodic Campaign'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMembersTab(),
          _buildCampaignsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessingProgramAction
            ? null
            : (_tabController.index == 0
                ? _showAddMemberDialog
                : _showAddCampaignModal),
        backgroundColor: const Color(0xFF2E7D32),
        icon: Icon(_tabController.index == 0 ? Icons.person_add : Icons.add,
            color: Colors.white),
        label: Text(_tabController.index == 0 ? 'Member Baru' : 'Buat Campaign',
            style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
