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

  test('accepts only the narrowly defined legacy competition voucher shape',
      () {
    final legacy = <String, dynamic>{
      'type': 'competitionReward',
      'status': 'READY_TO_CLAIM',
      'value': 50000,
      'activeDate': DateTime(2026, 8, 1),
      'expireDate': DateTime(2026, 8, 31, 23, 59, 59),
    };

    expect(MemberProgramService.isLegacyCompetitionReward(legacy), isTrue);
    expect(MemberProgramService.isVoucherActive(legacy), isTrue);
    expect(
      MemberProgramService.isVoucherActive(
        legacy,
        allowLegacyCompetitionReward: false,
      ),
      isFalse,
    );
    expect(
      MemberProgramService.voucherSingleUse(
        legacy,
        enforceProgramType: true,
      ),
      isTrue,
    );
    expect(
      MemberProgramService.voucherSingleUse(
        legacy,
        allowLegacyCompetitionReward: false,
      ),
      isNull,
    );
    expect(
      MemberProgramService.isVoucherStructurallyRedeemable(legacy),
      isTrue,
    );
    expect(
      MemberProgramService.isVoucherDateWindowOpen(
        legacy,
        now: DateTime(2026, 8, 20),
      ),
      isTrue,
    );

    final explicitlyDisabled = {
      ...legacy,
      'isActive': false,
    };
    expect(
      MemberProgramService.isVoucherStructurallyRedeemable(explicitlyDisabled),
      isFalse,
    );

    final reusableCampaign = <String, dynamic>{
      'type': 'cashbackCampaign',
      'status': 'READY_TO_CLAIM',
      'isActive': true,
      'sekaliPakai': false,
      'value': 50000,
      'valueRemaining': 50000,
      'activeDate': DateTime(2026, 8, 1),
      'expireDate': DateTime(2026, 8, 31, 23, 59, 59),
    };
    expect(
      MemberProgramService.voucherSingleUse(
        reusableCampaign,
        enforceProgramType: true,
      ),
      isTrue,
    );
    expect(
      MemberProgramService.voucherSingleUse(reusableCampaign),
      isFalse,
    );
    expect(
      MemberProgramService.isVoucherStructurallyRedeemable(reusableCampaign),
      isTrue,
    );

    final alreadyUsed = {
      ...legacy,
      'valueUsed': 50000,
    };
    expect(
      MemberProgramService.isVoucherStructurallyRedeemable(alreadyUsed),
      isFalse,
    );

    final malformed = {
      ...legacy,
      'type': 'voucher',
    };
    expect(
      MemberProgramService.isVoucherStructurallyRedeemable(malformed),
      isFalse,
    );
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
      const CompetitionMemberRecord(
        memberId: 'zero-point',
        category: 'santri',
        customerPoints: 0,
        amountSpent: 999999,
        numberOfTransaction: 99,
      ),
    ];

    final ranked = MemberProgramService.rankCompetitionMembers(
      records,
      category: 'Santri',
    );
    expect(ranked.map((record) => record.memberId), ['a-member', 'z-member']);
  });

  test('keeps cumulative root totals over partial canonical migration records',
      () {
    final merged = MemberProgramService.mergeCompetitionRecords(
      legacyData: {
        'legacy-member': {
          'customerPoints': 14,
          'amountSpent': 169000,
          'numberOfTransaction': 9,
        },
      },
      canonicalRecords: const [
        CompetitionMemberRecord(
          memberId: 'legacy-member',
          category: 'mahasiswa',
          customerPoints: 4,
          amountSpent: 52000,
          numberOfTransaction: 3,
        ),
        CompetitionMemberRecord(
          memberId: 'canonical-only',
          category: 'santri',
          customerPoints: 2,
          amountSpent: 20000,
          numberOfTransaction: 1,
        ),
      ],
      memberProfiles: const {
        'legacy-member': {'category': 'Mahasiswa'},
      },
    );

    final legacy =
        merged.firstWhere((record) => record.memberId == 'legacy-member');
    expect(legacy.customerPoints, 14);
    expect(legacy.amountSpent, 169000);
    expect(legacy.numberOfTransaction, 9);
    expect(legacy.category, 'mahasiswa');
    expect(merged.any((record) => record.memberId == 'canonical-only'), isTrue);
  });

  test('default competition prizes are 50k, 25k, and 15k', () {
    expect(PrizeConfiguration.defaults.amountFor('santri', 1), 50000);
    expect(PrizeConfiguration.defaults.amountFor('mahasiswa', 2), 25000);
    expect(PrizeConfiguration.defaults.amountFor('staff_guru_dosen', 3), 15000);
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
