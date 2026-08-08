import 'package:flutter_test/flutter_test.dart';
import 'package:point_of_sales_app_v3/Models/MemberProgramModels.dart';
import 'package:point_of_sales_app_v3/Services/MemberProgramService.dart';

void main() {
  test('calculates points after ordinary vouchers and excludes B2B nominal',
      () {
    final result = MemberProgramService.calculatePoints(
      finalBill: 80000,
      b2bNominal: 30000,
    );

    expect(result.eligibleAmount, 50000);
    expect(result.pointsDelta, 5);
  });

  test('clamps negative bills and sponsored nominal safely', () {
    final result = MemberProgramService.calculatePoints(
      finalBill: -100,
      b2bNominal: 5000,
    );

    expect(result.finalBill, 0);
    expect(result.eligibleAmount, 0);
    expect(result.pointsDelta, 0);
  });

  test('parses legacy numeric values and normalizes categories', () {
    expect(MemberProgramValues.intValue('50.000'), 50000);
    expect(MemberProgramService.normalizeCategory('Guru'), 'staff_guru_dosen');
    expect(MemberProgramService.normalizeCategory('MAHASISWA'), 'mahasiswa');
    expect(MemberProgramService.normalizeCategory('unknown'), isEmpty);
  });

  test('uses Jakarta calendar periods and following-month prize expiry', () {
    expect(
      MemberProgramService.periodIdFor(DateTime.utc(2026, 1, 31, 18)),
      '2026-02',
    );
    expect(
      MemberProgramService.prizeExpiryFor('2026-01').toUtc(),
      DateTime(2026, 2, 28, 23, 59, 59).toUtc(),
    );
    expect(
      MemberProgramService.isPeriodEnded(
        '2026-01',
        now: DateTime.utc(2026, 1, 31, 16, 59, 59),
      ),
      isFalse,
    );
    expect(
      MemberProgramService.isPeriodEnded(
        '2026-01',
        now: DateTime.utc(2026, 1, 31, 17),
      ),
      isTrue,
    );
  });

  test('ranks competition members with deterministic ties', () {
    final records = [
      const CompetitionMemberRecord(
        memberId: 'z-member',
        category: 'santri',
        customerPoints: 10,
        amountSpent: 100000,
        numberOfTransaction: 2,
      ),
      const CompetitionMemberRecord(
        memberId: 'a-member',
        category: 'santri',
        customerPoints: 10,
        amountSpent: 100000,
        numberOfTransaction: 2,
      ),
      const CompetitionMemberRecord(
        memberId: 'other-category',
        category: 'mahasiswa',
        customerPoints: 99,
        amountSpent: 999999,
        numberOfTransaction: 9,
      ),
    ];

    final ranked = MemberProgramService.rankCompetitionMembers(
      records,
      category: 'Santri',
    );
    expect(ranked.map((record) => record.memberId), ['a-member', 'z-member']);
  });

  test('campaign selection chooses earliest expiry and breaks ties by ID', () {
    Map<String, dynamic> group(String id, String expiry) => {
          'type': 'cashbackCampaign',
          'status': 'active',
          'isActive': true,
          'activeDate': DateTime(2026, 8, 1),
          'expireDate': DateTime.parse(expiry),
          'threshold': 10,
          'value': 50000,
        };

    final selected = MemberProgramService.selectCampaignCandidate(
      [
        CampaignCandidate(
          groupId: 'z-campaign',
          voucherId: 'voucher-z',
          groupData: group('z-campaign', '2026-08-20'),
        ),
        CampaignCandidate(
          groupId: 'a-campaign',
          voucherId: 'voucher-a',
          groupData: group('a-campaign', '2026-08-20'),
        ),
        CampaignCandidate(
          groupId: 'later-campaign',
          voucherId: 'voucher-later',
          groupData: group('later-campaign', '2026-08-30'),
        ),
      ],
      eventAt: DateTime(2026, 8, 8),
    );

    expect(selected?.groupId, 'a-campaign');
  });

  test('ready and claimed campaign vouchers are not selected again', () {
    final data = <String, dynamic>{
      'type': 'cashbackCampaign',
      'status': 'active',
      'isActive': true,
      'activeDate': DateTime(2026, 8, 1),
      'expireDate': DateTime(2026, 8, 20),
      'threshold': 10,
      'value': 50000,
    };
    final selected = MemberProgramService.selectCampaignCandidate(
      [
        CampaignCandidate(
          groupId: 'ready',
          voucherId: 'ready-voucher',
          groupData: data,
          existingVoucherData: const {
            'status': 'READY_TO_CLAIM',
            'userPoints': 10,
          },
        ),
        CampaignCandidate(
          groupId: 'claimed',
          voucherId: 'claimed-voucher',
          groupData: data,
          existingVoucherData: const {
            'status': 'CLAIMED',
            'isClaimed': true,
          },
        ),
      ],
      eventAt: DateTime(2026, 8, 8),
    );

    expect(selected, isNull);
  });

  test('campaign voucher IDs are deterministic and collision-resistant', () {
    expect(
      MemberProgramService.campaignVoucherId('campaign', 'member'),
      MemberProgramService.campaignVoucherId('campaign', 'member'),
    );
    expect(
      MemberProgramService.campaignVoucherId('campaign', 'member'),
      isNot(MemberProgramService.campaignVoucherId('campaign', 'other')),
    );
  });
}
