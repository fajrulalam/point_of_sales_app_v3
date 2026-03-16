import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Models/Member.dart';
import 'package:point_of_sales_app_v3/Widgets/MarketingProgressCard.dart';

class MemberProgressBottomSheet extends StatelessWidget {
  final Member member;
  final Map<String, int> competitionPoints;

  const MemberProgressBottomSheet({
    Key? key,
    required this.member,
    required this.competitionPoints,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
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
                    .collection('vouchers')
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
                    final aTime = aData['lastUpdatedAt'] as Timestamp?;
                    final bTime = bData['lastUpdatedAt'] as Timestamp?;
                    if (aTime == null && bTime == null) return 0;
                    if (aTime == null) return 1;
                    if (bTime == null) return -1;
                    return bTime.compareTo(aTime);
                  });
                  final compPoints = competitionPoints[member.id] ?? 0;

                  return ListView(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      _buildSectionHeader('Competition Progress'),
                      MarketingProgressCard(
                        title: 'Monthly Competition',
                        value: '$compPoints Pts',
                        label: 'Competition Points',
                        icon: Icons.emoji_events,
                        color: Colors.amber,
                        progress: null,
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

                          return MarketingProgressCard(
                            title: data['voucherName'] ?? 'Voucher',
                            value: '$points / $threshold',
                            label: 'Progress Poin',
                            icon: statusIcon,
                            color: statusColor,
                            progress: progress,
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
}
