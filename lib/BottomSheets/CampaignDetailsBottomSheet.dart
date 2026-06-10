import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Models/Member.dart';
import 'package:point_of_sales_app_v3/Widgets/MarketingProgressCard.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

class CampaignDetailsBottomSheet extends StatelessWidget {
  final QueryDocumentSnapshot campaignDoc;
  final List<Member> members;

  const CampaignDetailsBottomSheet({
    Key? key,
    required this.campaignDoc,
    required this.members,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final campaignData = campaignDoc.data() as Map<String, dynamic>;
    final campaignId = campaignDoc.id;

    return DraggableScrollableSheet(
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
                      final status = data['status'] ?? 'UNKNOWN';
                      final points = data['userPoints'] ?? 0;
                      final threshold = data['threshold'] ?? 0;
                      final progress = (points / threshold).clamp(0.0, 1.0);

                      // Fallback: If 'nama' is missing in voucher, find it from our local members list
                      final userId = data['userId'];
                      String participantName = data['nama'] ?? '';
                      if (participantName.trim().isEmpty && userId != null) {
                        try {
                          participantName =
                              members.firstWhere((m) => m.id == userId).name;
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

                      return MarketingProgressCard(
                        title: participantName,
                        value: '$points / $threshold',
                        label: 'Progress Poin',
                        icon: statusIcon,
                        color: statusColor,
                        progress: progress,
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
    );
  }
}
