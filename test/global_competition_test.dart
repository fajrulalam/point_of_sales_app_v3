import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:point_of_sales_app_v3/Models/MemberProgramModels.dart';
import 'package:point_of_sales_app_v3/Services/MemberProgramService.dart';
import 'package:point_of_sales_app_v3/Services/MemberProgramAuditService.dart';

void main() {
  final fixtures = jsonDecode(
      File('test/fixtures/competition-policy.json').readAsStringSync()) as List;
  for (final fixture in fixtures) {
    test(fixture['name'], () {
      final records = (fixture['records'] as List).map((data) =>
          CompetitionMemberRecord.fromMap(
              data['memberId'], Map<String, dynamic>.from(data)));
      final winners = MemberProgramService.buildCompetitionWinners(
          fixture['periodId'], records);
      expect(
          winners
              .map((winner) => {
                    'memberId': winner.memberId,
                    'rank': winner.rank,
                    'prizeAmount': winner.prizeAmount,
                    'voucherId': winner.voucherId,
                    'documentId': winner.documentId,
                  })
              .toList(),
          fixture['expected']);
      expect(
          MemberProgramAuditService.globalPrizeIssues({
            ...CompetitionRankingMode.global.metadata,
            'configuration': PrizeConfiguration.defaults.toMap(),
            'winners': winners.map((winner) => winner.toMap()).toList(),
          }),
          isEmpty);
    });
  }

  test('mode boundary and explicit metadata', () {
    expect(CompetitionRankingMode.forPeriod('2026-08'),
        CompetitionRankingMode.category);
    expect(CompetitionRankingMode.forPeriod('2026-09'),
        CompetitionRankingMode.global);
    expect(CompetitionRankingMode.forPeriod('2027-01'),
        CompetitionRankingMode.global);
    expect(
        CompetitionRankingMode.forPeriod('2026-08', {'rankingMode': 'global'}),
        CompetitionRankingMode.global);
    expect(
        CompetitionRankingMode.forPeriod('2026-09', {'rankingMode': 'invalid'}),
        CompetitionRankingMode.global);
    final records = (fixtures[0]['records'] as List).map((data) =>
        CompetitionMemberRecord.fromMap(
            data['memberId'], Map<String, dynamic>.from(data)));
    expect(
        MemberProgramService.buildCompetitionWinners('2026-08', records)
            .map((w) => [w.memberId, w.rank]),
        [
          ['z-member', 1],
          ['a-member', 1],
          ['top+6281', 1],
        ]);
  });

  test(
      'audit detects duplicate ranks and wrong amounts without requiring categories',
      () {
    final valid = {
      ...CompetitionRankingMode.global.metadata,
      'configuration': PrizeConfiguration.defaults.toMap(),
      'winners': [
        {
          'memberId': 'one',
          'rank': 1,
          'points': 9,
          'prizeAmount': 50000,
          'voucherId': 'v1',
          'rankingMode': 'global'
        },
        {
          'memberId': 'two',
          'rank': 1,
          'points': 8,
          'prizeAmount': 15000,
          'voucherId': 'v2',
          'rankingMode': 'global'
        },
      ],
    };
    expect(MemberProgramAuditService.globalPrizeIssues(valid),
        contains('competition_global_winner_invalid'));
  });
}
