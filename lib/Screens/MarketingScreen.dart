import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Models/Member.dart';
import 'package:point_of_sales_app_v3/Services/MemberService.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

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
  Map<String, Map<String, dynamic>> _competitionRecords = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rebuild FAB on tab change
    });
    _loadMembers();
    _loadCampaigns();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoadingMembers = true);
    try {
      final members = await _memberService.getCachedMembers();
      
      // Fetch competition points for current month
      final now = DateTime.now();
      final monthDocId = DateFormat('yyyy-MM').format(now);
      final competitionDoc = await FirebaseFirestore.instance
          .collection(Col.name('competitionRecords'))
          .doc(monthDocId)
          .get();

      Map<String, int> pointsMap = {};
      Map<String, Map<String, dynamic>> recordsMap = {};
      if (competitionDoc.exists) {
        final data = competitionDoc.data() as Map<String, dynamic>;
        data.forEach((key, value) {
          if (value is Map && value.containsKey('customerPoints')) {
            recordsMap[key] = {
              'customerPoints': (value['customerPoints'] as num?)?.toInt() ?? 0,
              'amountSpent': (value['amountSpent'] as num?)?.toInt() ?? 0,
              'numberOfTransaction': (value['numberOfTransaction'] as num?)?.toInt() ?? 0,
            };
            pointsMap[key] = (value['customerPoints'] as num?)?.toInt() ?? 0;
          }
        });
      }

      // Sort members by competition points descending
      final sortedMembers = List<Member>.from(members);
      sortedMembers.sort((a, b) {
        final recordA = recordsMap[a.id] ?? {'customerPoints': 0, 'amountSpent': 0, 'numberOfTransaction': 0};
        final recordB = recordsMap[b.id] ?? {'customerPoints': 0, 'amountSpent': 0, 'numberOfTransaction': 0};
        
        int pointsCompare = recordB['customerPoints'].compareTo(recordA['customerPoints']);
        if (pointsCompare != 0) return pointsCompare;
        
        int amountCompare = recordB['amountSpent'].compareTo(recordA['amountSpent']);
        if (amountCompare != 0) return amountCompare;
        
        return recordB['numberOfTransaction'].compareTo(recordA['numberOfTransaction']);
      });

      setState(() {
        _allMembers = sortedMembers; // Cache full sorted list
        _members = sortedMembers;
        _competitionPoints = pointsMap;
        _competitionRecords = recordsMap; // Cache for local filtering
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update cache: $e')),
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
      
      // Data Integrity: If forceRefresh is on, verify counts to fix "Data Mismatch"
      if (forceRefresh) {
        for (var doc in docs) {
          final participants = await FirebaseFirestore.instance
              .collection(Col.name('vouchers'))
              .where('voucherGroupId', isEqualTo: doc.id)
              .count()
              .get();
              
          final claimed = await FirebaseFirestore.instance
              .collection(Col.name('vouchers'))
              .where('voucherGroupId', isEqualTo: doc.id)
              .where('status', isEqualTo: 'CLAIMED')
              .count()
              .get();

          // Sync the document if there's a mismatch
          if (doc['totalParticipants'] != participants.count || 
              doc['totalClaimed'] != claimed.count) {
            await doc.reference.update({
              'totalParticipants': participants.count,
              'totalClaimed': claimed.count,
            });
          }
        }
      }
          
      setState(() {
        _campaigns = docs;
        _campaigns.sort((a, b) {
           final aData = a.data() as Map<String, dynamic>;
           final bData = b.data() as Map<String, dynamic>;
           final aTime = aData['createdAt'] as Timestamp?;
           final bTime = bData['createdAt'] as Timestamp?;
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
            child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(confirmContext);
              final Uri url = Uri.parse(
                  'https://canteen-375-registration.vercel.app/register');
              if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tidak dapat membuka halaman pendaftaran')),
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
                    : (startDate?.add(const Duration(days: 30)) ?? DateTime.now()),
                firstDate: isStart ? DateTime.now() : (startDate ?? DateTime.now()),
                lastDate: DateTime(2100),
              );
              if (date != null) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: isStart ? TimeOfDay.now() : const TimeOfDay(hour: 23, minute: 59),
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
              } else if (int.tryParse(thresholdController.text) == null || int.parse(thresholdController.text) <= 0) {
                setModalState(() => thresholdError = 'Masukkan angka yang valid');
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
                setModalState(() => requirementsError = 'Syarat transaksi wajib diisi');
                hasError = true;
              } else if (parseCurrency(requirementsController.text) <= 0) {
                setModalState(() => requirementsError = 'Masukkan nilai yang valid');
                hasError = true;
              }
              
              if (startDate == null || endDate == null) {
                setModalState(() => dateError = 'Pilih tanggal mulai dan berakhir');
                hasError = true;
              } else if (endDate!.isBefore(startDate!)) {
                setModalState(() => dateError = 'Tanggal berakhir harus setelah tanggal mulai');
                hasError = true;
              }
              
              if (hasError) return;
              
              Navigator.pop(modalContext);
              setState(() => _isLoadingCampaigns = true);

              try {
                String safeName = nameController.text.trim().replaceAll(' ', '_');
                String voucherGroupId =
                    'campaign_${DateFormat('yyyy-MM-dd').format(DateTime.now())}_${safeName}_${DateTime.now().millisecondsSinceEpoch}';

                await FirebaseFirestore.instance
                    .collection(Col.name('voucherGroup'))
                    .doc(voucherGroupId)
                    .set({
                  'activeDate': Timestamp.fromDate(startDate!),
                  'createdAt': FieldValue.serverTimestamp(),
                  'expireDate': Timestamp.fromDate(endDate!),
                  'isActive': true,
                  'threshold': int.parse(thresholdController.text),
                  'totalClaimed': 0,
                  'totalParticipants': 0,
                  'type': 'cashbackCampaign',
                  'value': parseCurrency(valueController.text),
                  'transactionRequirement': parseCurrency(requirementsController.text),
                  'voucherGroupId': voucherGroupId,
                  'voucherName': nameController.text.trim(),
                });

                await _loadCampaigns();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Gagal membuat campaign: $e')),
                );
              } finally {
                if (mounted) {
                  setState(() => _isLoadingCampaigns = false);
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
                        helperText: 'Member mengumpulkan poin dari transaksi (1 poin per Rp 10.000)',
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        errorText: thresholdError,
                        prefixIcon: const Icon(Icons.emoji_events_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setModalState(() => thresholdError = null),
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
                            selection: TextSelection.collapsed(offset: formatted.length),
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
                        helperText: 'Member harus belanja minimal ini saat redeem voucher',
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
                            selection: TextSelection.collapsed(offset: formatted.length),
                          );
                        }),
                      ],
                      onChanged: (_) => setModalState(() => requirementsError = null),
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
                                  color: dateError != null ? Colors.red : Colors.grey.shade400,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today, 
                                      size: 18, 
                                      color: startDate != null ? const Color(0xFF2E7D32) : Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      startDate == null
                                          ? 'Mulai'
                                          : DateFormat('dd MMM yyyy\nHH:mm').format(startDate!),
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: startDate != null ? Colors.black87 : Colors.grey,
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
                          child: Icon(Icons.arrow_forward, color: Colors.grey.shade400),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => selectDate(false),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: dateError != null ? Colors.red : Colors.grey.shade400,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today, 
                                      size: 18, 
                                      color: endDate != null ? const Color(0xFF2E7D32) : Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      endDate == null
                                          ? 'Berakhir'
                                          : DateFormat('dd MMM yyyy\nHH:mm').format(endDate!),
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: endDate != null ? Colors.black87 : Colors.grey,
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
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.red),
                        ),
                      ),
                    
                    const SizedBox(height: 24),
                    
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(modalContext),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.grey.shade400),
                            ),
                            child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey.shade700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: validateAndSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text('Buat Campaign', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Cari member (nama atau telepon)...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
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
              : _members.isEmpty
                  ? _buildMemberEmptyState()
                  : RefreshIndicator(
                      onRefresh: _handleRefreshMembers,
                      color: const Color(0xFF2E7D32),
                      child: ListView.builder(
                        itemCount: _members.length,
                        itemBuilder: (context, index) {
                          final member = _members[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: ListTile(
                               leading: CircleAvatar(
                                 backgroundColor: const Color(0xFFE8F5E9),
                                 child: Text(member.name[0].toUpperCase()),
                               ),
                              title: Text(member.name,
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500)),
                              subtitle: Text(member.phoneNumber),
                               trailing: ElevatedButton(
                                 onPressed: () => _showMemberProgressSheet(member),
                                 style: ElevatedButton.styleFrom(
                                   backgroundColor: const Color(0xFFE8F5E9),
                                   foregroundColor: const Color(0xFF1B5E20),
                                   elevation: 0,
                                   padding: const EdgeInsets.symmetric(horizontal: 12),
                                   shape: RoundedRectangleBorder(
                                       borderRadius: BorderRadius.circular(8)),
                                 ),
                                 child: const Text('Progress', style: TextStyle(fontSize: 12)),
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
            onPressed: _showAddCampaignModal,
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
                      (campaign['activeDate'] as Timestamp).toDate();
                  final endDate =
                      (campaign['expireDate'] as Timestamp).toDate();
                  final isActive = campaign['isActive'] ?? false;
                  
                  final now = DateTime.now();
                  final isCurrentlyRunning = isActive && now.isAfter(startDate) && now.isBefore(endDate);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isCurrentlyRunning ? Colors.green.shade200 : Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => _showCampaignDetailsSheet(campaignDoc),
                      onLongPress: () => _showCampaignOptionsMenu(campaignDoc),
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
                                        fontWeight: FontWeight.w600, fontSize: 16),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCurrentlyRunning ? Colors.green.shade100 : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isCurrentlyRunning ? 'Aktif' : 'Nonaktif',
                                    style: TextStyle(
                                      color: isCurrentlyRunning ? Colors.green.shade800 : Colors.grey.shade700,
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
                                      Icon(Icons.card_giftcard, size: 18, color: Colors.orange.shade700),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Rp ${NumberFormat.decimalPattern().format(campaign['value'] ?? 0)}',
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
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${campaign['threshold'] ?? 0} pts',
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
                                Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(
                                  '${DateFormat('dd MMM').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            
                            // Min Transaction
                            Row(
                              children: [
                                Icon(Icons.receipt_long, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(
                                  'Min. transaksi Rp ${NumberFormat.decimalPattern().format(campaign['transactionRequirement'] ?? 0)}',
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
                                _buildCampaignStat(Icons.people, '${campaign['totalParticipants'] ?? 0}', 'Peserta'),
                                const SizedBox(width: 24),
                                _buildCampaignStat(Icons.check_circle, '${campaign['totalClaimed'] ?? 0}', 'Diklaim'),
                                const Spacer(),
                                Icon(Icons.chevron_right, color: Colors.grey.shade400),
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
            ListTile(
              leading: Icon(
                campaign['isActive'] == true ? Icons.pause_circle : Icons.play_circle,
                color: campaign['isActive'] == true ? Colors.orange : Colors.green,
              ),
              title: Text(
                campaign['isActive'] == true ? 'Nonaktifkan Campaign' : 'Aktifkan Campaign',
                style: GoogleFonts.poppins(),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _toggleCampaignStatus(campaignDoc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text('Hapus Campaign', style: GoogleFonts.poppins(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteCampaign(campaignDoc);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleCampaignStatus(QueryDocumentSnapshot campaignDoc) async {
    final campaign = campaignDoc.data() as Map<String, dynamic>;
    final currentStatus = campaign['isActive'] ?? false;
    
    try {
      await campaignDoc.reference.update({'isActive': !currentStatus});
      await _loadCampaigns();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !currentStatus ? 'Campaign diaktifkan' : 'Campaign dinonaktifkan',
            ),
            backgroundColor: !currentStatus ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengubah status: $e')),
        );
      }
    }
  }

  void _confirmDeleteCampaign(QueryDocumentSnapshot campaignDoc) {
    final campaign = campaignDoc.data() as Map<String, dynamic>;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus Campaign?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'Campaign "${campaign['voucherName']}" akan dihapus permanen. Voucher peserta yang sudah ada akan tetap tersimpan.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await campaignDoc.reference.delete();
                await _loadCampaigns();
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Campaign berhasil dihapus'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal menghapus campaign: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Hapus', style: GoogleFonts.poppins()),
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
                            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
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
                        final status = data['status'] ?? 'UNKNOWN';
                        final points = data['userPoints'] ?? 0;
                        final threshold = data['threshold'] ?? 0;
                        final progress = (points / threshold).clamp(0.0, 1.0);
                        
                        // Fallback: If 'nama' is missing in voucher, find it from our local members list
                        final userId = data['userId'];
                        String participantName = data['nama'] ?? '';
                        if (participantName.trim().isEmpty && userId != null) {
                          try {
                            participantName = _members.firstWhere((m) => m.id == userId).name;
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
                      child: Text(member.name[0].toUpperCase(),
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

                    List<QueryDocumentSnapshot> vouchers = snapshot.data?.docs ?? [];
                    // Sort client-side to avoid requiring a Firestore composite index
                    vouchers.sort((a, b) {
                      final aData = a.data() as Map<String, dynamic>;
                      final bData = b.data() as Map<String, dynamic>;
                      final aTime = aData['lastUpdatedAt'] as Timestamp?;
                      final bTime = bData['lastUpdatedAt'] as Timestamp?;
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
                        _buildSectionHeader('Competition Progress'),
                        _buildProgressCard(
                          'Monthly Competition',
                          '$compPoints Pts',
                          'Competition Points',
                          Icons.emoji_events,
                          Colors.amber,
                          null,
                        ),
                        const SizedBox(height: 24),
                        _buildSectionHeader('Campaign Vouchers'),
                        if (vouchers.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text('Tidak ada voucher aktif',
                                style: GoogleFonts.poppins(color: Colors.grey)),
                          )
                        else
                          ...vouchers.take(3).map((v) {
                            final data = v.data() as Map<String, dynamic>;
                            final status = data['status'] ?? 'UNKNOWN';
                            final points = data['userPoints'] ?? 0;
                            final threshold = data['threshold'] ?? 0;
                            final progress = (points / threshold).clamp(0.0, 1.0);
                            
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Marketing & Member',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
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
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.normal, fontSize: 14),
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
        onPressed: _tabController.index == 0
            ? _showAddMemberDialog
            : _showAddCampaignModal,
        backgroundColor: const Color(0xFF2E7D32),
        icon: Icon(_tabController.index == 0 ? Icons.person_add : Icons.add,
            color: Colors.white),
        label: Text(
            _tabController.index == 0 ? 'Member Baru' : 'Buat Campaign',
            style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
