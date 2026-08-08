import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Models/MemberProgramModels.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

/// Read-only reconciliation for the member-program subsystem.
///
/// This service deliberately never updates a document.  Findings are meant
/// for an administrator to review before using a separate adjustment or data
/// repair workflow.
class MemberProgramAuditService {
  MemberProgramAuditService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<MemberProgramAuditFinding>> runAudit() async {
    final findings = <MemberProgramAuditFinding>[];
    final members = await _firestore.collection(Col.name('Members')).get();
    final ledgers =
        await _firestore.collection(Col.name('pointTransactions')).get();
    final operations =
        await _firestore.collection(Col.name('memberProgramOperations')).get();
    final vouchers = await _firestore.collection(Col.name('vouchers')).get();
    final groups = await _firestore.collection(Col.name('voucherGroup')).get();
    final prizes =
        await _firestore.collection(Col.name('competitionPrizes')).get();
    final outbox =
        await _firestore.collection(Col.name('externalVoucherClaims')).get();

    _auditMembers(findings, members.docs);
    _auditPointLedger(findings, members.docs, ledgers.docs, operations.docs);
    _auditCampaigns(findings, groups.docs, vouchers.docs);
    _auditPrizes(findings, prizes.docs, vouchers.docs);
    _auditExternalClaims(findings, outbox.docs);
    await _auditCompetition(findings, ledgers.docs);
    await _auditOrderMarkers(findings);
    return findings;
  }

  static bool _hasNumericValue(dynamic value) =>
      value is num ||
      (value is String && RegExp(r'^-?\d[\d.,\s]*$').hasMatch(value.trim()));

  void _auditMembers(
    List<MemberProgramAuditFinding> findings,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    for (final doc in documents) {
      final data = doc.data();
      final rawPoints = data['points'];
      final points = MemberProgramValues.intValue(rawPoints);
      if (rawPoints != null && !_hasNumericValue(rawPoints)) {
        findings.add(MemberProgramAuditFinding(
          code: 'member_points_malformed',
          severity: 'high',
          message: 'Saldo poin member tidak berupa angka yang dapat dibaca.',
          documentPath: doc.reference.path,
        ));
      }
      if (points < 0) {
        findings.add(MemberProgramAuditFinding(
          code: 'member_points_negative',
          severity: 'high',
          message: 'Saldo poin member bernilai negatif.',
          documentPath: doc.reference.path,
          details: {'points': points},
        ));
      }
      if (MemberProgramValues.categoryValue(
              data['category'] ?? data['memberCategory'] ?? data['role'])
          .isEmpty) {
        findings.add(MemberProgramAuditFinding(
          code: 'member_category_unknown',
          severity: 'medium',
          message: 'Kategori member tidak dikenali untuk pemeringkatan hadiah.',
          documentPath: doc.reference.path,
        ));
      }
    }
  }

  void _auditPointLedger(
    List<MemberProgramAuditFinding> findings,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> members,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> ledgers,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> operations,
  ) {
    final totals = <String, int>{};
    final memberIds = members.map((doc) => doc.id).toSet();
    final operationIds = operations.map((doc) => doc.id).toSet();
    final ledgerIdsByOperation = <String, String>{};
    final sourceOperations = <String, String>{};
    for (final doc in ledgers) {
      final data = doc.data();
      final operationId = data['operationId']?.toString() ?? '';
      if (operationId.isNotEmpty) {
        ledgerIdsByOperation[operationId] = doc.id;
      }
      final memberId = data['memberId']?.toString() ?? '';
      final status = data['status']?.toString().toLowerCase();
      final eventType = data['eventType']?.toString();
      if (status != 'completed' && status != 'pending') {
        findings.add(MemberProgramAuditFinding(
          code: 'point_ledger_status_invalid',
          severity: 'high',
          message: 'Status ledger poin tidak valid.',
          documentPath: doc.reference.path,
        ));
      }
      if (!_hasNumericValue(data['pointsDelta']) ||
          !_hasNumericValue(data['eligibleAmount'])) {
        findings.add(MemberProgramAuditFinding(
          code: 'point_ledger_amount_malformed',
          severity: 'high',
          message: 'Nilai poin atau eligible amount pada ledger tidak valid.',
          documentPath: doc.reference.path,
        ));
      }
      if (operationId.isEmpty || operationId != doc.id) {
        findings.add(MemberProgramAuditFinding(
          code: 'point_operation_marker_missing',
          severity: 'high',
          message: 'Ledger poin tidak memiliki operation ID yang konsisten.',
          documentPath: doc.reference.path,
        ));
      }
      if (!memberIds.contains(memberId)) {
        findings.add(MemberProgramAuditFinding(
          code: 'point_member_reference_missing',
          severity: 'high',
          message: 'Ledger poin merujuk member yang tidak ditemukan.',
          documentPath: doc.reference.path,
          details: {'memberId': memberId},
        ));
      }
      if (!operationIds.contains(doc.id)) {
        findings.add(MemberProgramAuditFinding(
          code: 'point_operation_record_missing',
          severity: 'high',
          message: 'Ledger poin tidak memiliki marker operasi member-program.',
          documentPath: doc.reference.path,
        ));
      }
      if (status == 'completed') {
        if (eventType == 'earn' &&
            MemberProgramValues.intValue(data['pointsDelta']) > 0 &&
            data['campaignStatus']?.toString().toLowerCase() == 'pending') {
          findings.add(MemberProgramAuditFinding(
            code: 'member_program_campaign_pending',
            severity: 'high',
            message:
                'Poin sudah tercatat tetapi progres campaign belum selesai dan perlu dicoba ulang.',
            documentPath: doc.reference.path,
            details: {
              'campaignGroupId': data['campaignGroupId'],
              'campaignVoucherId': data['campaignVoucherId'],
            },
          ));
        }
        if (eventType != 'earn' &&
            eventType != 'reverse' &&
            eventType != 'manual_adjustment') {
          findings.add(MemberProgramAuditFinding(
            code: 'point_event_type_invalid',
            severity: 'high',
            message: 'Jenis event ledger poin tidak valid.',
            documentPath: doc.reference.path,
          ));
        }
        totals[memberId] = (totals[memberId] ?? 0) +
            MemberProgramValues.intValue(data['pointsDelta']);
        if (eventType == 'earn' && data['sourceType']?.toString() != 'edit') {
          final sourceType = data['sourceType']?.toString() ?? '';
          final sourceId = data['sourceId']?.toString() ?? '';
          if (sourceType.isNotEmpty && sourceId.isNotEmpty) {
            final sourceKey = '$sourceType/$sourceId';
            final previous = sourceOperations[sourceKey];
            if (previous != null && previous != doc.id) {
              findings.add(MemberProgramAuditFinding(
                code: 'duplicate_point_source_operation',
                severity: 'high',
                message:
                    'Satu transaksi memiliki lebih dari satu ledger poin earn.',
                documentPath: doc.reference.path,
                details: {'otherOperationId': previous, 'sourceId': sourceId},
              ));
            } else {
              sourceOperations[sourceKey] = doc.id;
            }
          }
        }
      }
    }
    for (final operation in operations) {
      final data = operation.data();
      final status = data['status']?.toString().toLowerCase();
      if (status == 'completed' &&
          !ledgerIdsByOperation.containsKey(operation.id)) {
        findings.add(MemberProgramAuditFinding(
          code: 'member_program_operation_ledger_missing',
          severity: 'high',
          message:
              'Marker operasi member-program selesai tetapi ledger poinnya tidak ditemukan.',
          documentPath: operation.reference.path,
        ));
      }
    }
    for (final member in members) {
      final expected = totals[member.id] ?? 0;
      final actual = MemberProgramValues.intValue(member.data()['points']);
      if (expected != actual) {
        findings.add(MemberProgramAuditFinding(
          code: 'member_points_ledger_mismatch',
          severity: 'high',
          message: 'Saldo poin member berbeda dari total ledger completed.',
          documentPath: member.reference.path,
          details: {'memberPoints': actual, 'ledgerPoints': expected},
        ));
      }
    }
  }

  void _auditCampaigns(
    List<MemberProgramAuditFinding> findings,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> groups,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> vouchers,
  ) {
    final byGroup =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final voucher in vouchers) {
      final data = voucher.data();
      final groupId = data['voucherGroupId']?.toString();
      final isMemberProgramVoucher =
          data['type']?.toString() == 'cashbackCampaign' ||
              data['type']?.toString() == 'competitionPrize';
      if (groupId != null && groupId.isNotEmpty) {
        byGroup.putIfAbsent(groupId, () => []).add(voucher);
      }
      final status = data['status']?.toString().toUpperCase() ?? '';
      if (isMemberProgramVoucher &&
          !{
            'IN_PROGRESS',
            'READY_TO_CLAIM',
            'CLAIMED',
            'EXPIRED',
            'DISABLED',
          }.contains(status)) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_voucher_status_invalid',
          severity: 'high',
          message: 'Status voucher campaign tidak valid.',
          documentPath: voucher.reference.path,
        ));
      }
      final value = MemberProgramValues.intValue(data['value']);
      if (isMemberProgramVoucher && value <= 0) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_voucher_value_invalid',
          severity: 'high',
          message: 'Nilai voucher campaign tidak valid.',
          documentPath: voucher.reference.path,
        ));
      }
      if (isMemberProgramVoucher && data['sekaliPakai'] is! bool) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_voucher_usage_type_invalid',
          severity: 'high',
          message: 'Tipe penggunaan voucher campaign tidak valid.',
          documentPath: voucher.reference.path,
        ));
      }
      if (data['type']?.toString() == 'cashbackCampaign' &&
          (groupId == null || groupId.isEmpty)) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_voucher_group_reference_missing',
          severity: 'high',
          message: 'Voucher campaign tidak memiliki referensi campaign.',
          documentPath: voucher.reference.path,
        ));
      }
      if (isMemberProgramVoucher &&
          (data['userId']?.toString().trim().isEmpty ?? true)) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_voucher_member_reference_missing',
          severity: 'high',
          message: 'Voucher campaign tidak memiliki referensi member.',
          documentPath: voucher.reference.path,
        ));
      }
      final active = MemberProgramValues.dateValue(data['activeDate']);
      final expire = MemberProgramValues.dateValue(data['expireDate']);
      if (isMemberProgramVoucher &&
          (active == null || expire == null || expire.isBefore(active))) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_voucher_dates_invalid',
          severity: 'high',
          message: 'Tanggal aktif/berakhir voucher campaign tidak valid.',
          documentPath: voucher.reference.path,
        ));
      }
      if (isMemberProgramVoucher &&
          ((data['status']?.toString().toUpperCase() == 'CLAIMED') !=
              (data['isClaimed'] == true))) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_voucher_claim_flag_contradiction',
          severity: 'high',
          message: 'Status dan flag klaim voucher campaign tidak konsisten.',
          documentPath: voucher.reference.path,
        ));
      }
      if (isMemberProgramVoucher &&
          MemberProgramValues.intValue(data['valueRemaining']) < 0) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_voucher_balance_negative',
          severity: 'high',
          message: 'Saldo voucher campaign bernilai negatif.',
          documentPath: voucher.reference.path,
        ));
      }
    }
    for (final group in groups) {
      final data = group.data();
      if (data['type']?.toString() != 'cashbackCampaign') continue;
      final status = data['status']?.toString().toLowerCase();
      if (status != 'active' && status != 'archived') {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_status_invalid',
          severity: 'high',
          message: 'Status campaign tidak valid.',
          documentPath: group.reference.path,
        ));
      }
      if ((status == 'active' && data['isActive'] != true) ||
          (status == 'archived' && data['isActive'] != false)) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_active_flag_contradiction',
          severity: 'high',
          message: 'Status dan flag aktif campaign tidak konsisten.',
          documentPath: group.reference.path,
        ));
      }
      final threshold = MemberProgramValues.intValue(data['threshold']);
      final value = MemberProgramValues.intValue(data['value']);
      final active = MemberProgramValues.dateValue(data['activeDate']);
      final expire = MemberProgramValues.dateValue(data['expireDate']);
      final participantCount =
          MemberProgramValues.intValue(data['totalParticipants']);
      final claimedCount = MemberProgramValues.intValue(data['totalClaimed']);
      final redemptionCount =
          MemberProgramValues.intValue(data['totalRedemptions']);
      if (![
        data['threshold'],
        data['value'],
        data['totalParticipants'],
        data['totalClaimed'],
        data['totalRedemptions']
      ].every(_hasNumericValue)) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_numeric_field_missing_or_malformed',
          severity: 'high',
          message: 'Field angka campaign hilang atau tidak dapat dibaca.',
          documentPath: group.reference.path,
        ));
      }
      if (threshold <= 0 ||
          value <= 0 ||
          active == null ||
          expire == null ||
          expire.isBefore(active)) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_definition_invalid',
          severity: 'high',
          message: 'Threshold, nilai, atau tanggal campaign tidak valid.',
          documentPath: group.reference.path,
        ));
      }
      if (participantCount < 0 || claimedCount < 0 || redemptionCount < 0) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_counter_invalid',
          severity: 'high',
          message: 'Counter campaign bernilai negatif atau tidak valid.',
          documentPath: group.reference.path,
        ));
      }
      final related = byGroup[group.id] ?? const [];
      final participants = related
          .map((doc) => doc.data()['userId']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .length;
      final claimed = related
          .where((doc) =>
              doc.data()['status']?.toString().toUpperCase() == 'CLAIMED')
          .length;
      if (MemberProgramValues.intValue(data['totalParticipants']) !=
          participants) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_participant_counter_mismatch',
          severity: 'medium',
          message: 'Counter peserta campaign berbeda dari voucher tersimpan.',
          documentPath: group.reference.path,
          details: {
            'stored': MemberProgramValues.intValue(data['totalParticipants']),
            'observed': participants,
          },
        ));
      }
      if (MemberProgramValues.intValue(data['totalClaimed']) != claimed) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_claim_counter_mismatch',
          severity: 'medium',
          message: 'Counter voucher diklaim berbeda dari status voucher.',
          documentPath: group.reference.path,
          details: {
            'stored': MemberProgramValues.intValue(data['totalClaimed']),
            'observed': claimed,
          },
        ));
      }
      final redemptions = related
          .map((doc) => MemberProgramValues.intValue(doc.data()['valueUsed']))
          .where((value) => value > 0)
          .length;
      final storedRedemptions =
          MemberProgramValues.intValue(data['totalRedemptions']);
      if (storedRedemptions < claimed || storedRedemptions < redemptions) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_redemption_counter_invalid',
          severity: 'medium',
          message:
              'Counter pemakaian campaign lebih kecil dari voucher yang digunakan.',
          documentPath: group.reference.path,
          details: {
            'stored': storedRedemptions,
            'claimed': claimed,
            'vouchersWithUsage': redemptions,
          },
        ));
      }
      final seen = <String, String>{};
      for (final voucher in related) {
        final userId = voucher.data()['userId']?.toString() ?? '';
        if (userId.isEmpty) continue;
        final previous = seen['$userId:${group.id}'];
        if (previous != null && previous != voucher.id) {
          findings.add(MemberProgramAuditFinding(
            code: 'campaign_duplicate_member_voucher',
            severity: 'high',
            message:
                'Member memiliki lebih dari satu voucher pada campaign yang sama.',
            documentPath: voucher.reference.path,
            details: {'otherVoucherId': previous},
          ));
        }
        seen['$userId:${group.id}'] = voucher.id;
      }
    }
    for (final voucher in vouchers) {
      final groupId = voucher.data()['voucherGroupId']?.toString();
      if (groupId != null && !groups.any((group) => group.id == groupId)) {
        findings.add(MemberProgramAuditFinding(
          code: 'campaign_reference_missing',
          severity: 'high',
          message: 'Voucher merujuk campaign yang tidak ditemukan.',
          documentPath: voucher.reference.path,
        ));
      }
    }
  }

  void _auditPrizes(
    List<MemberProgramAuditFinding> findings,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> prizes,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> vouchers,
  ) {
    final voucherById = {for (final voucher in vouchers) voucher.id: voucher};
    for (final prize in prizes) {
      final winners = prize.data()['winners'];
      if (winners is! List) {
        findings.add(MemberProgramAuditFinding(
          code: 'competition_winners_missing',
          severity: 'high',
          message:
              'Dokumen finalisasi kompetisi tidak memiliki daftar pemenang.',
          documentPath: prize.reference.path,
        ));
        continue;
      }
      for (final raw in winners) {
        if (raw is! Map) continue;
        final voucherId = raw['voucherId']?.toString() ?? '';
        final voucher = voucherById[voucherId];
        if (voucher == null || voucher.data()['type'] != 'competitionPrize') {
          findings.add(MemberProgramAuditFinding(
            code: 'competition_prize_voucher_missing',
            severity: 'high',
            message:
                'Voucher hadiah kompetisi tidak ditemukan atau tipenya salah.',
            documentPath: prize.reference.path,
            details: {'voucherId': voucherId},
          ));
        } else {
          final data = voucher.data();
          if (data['competitionPrizePeriod']?.toString() != prize.id ||
              data['userId']?.toString() != raw['memberId']?.toString() ||
              MemberProgramValues.intValue(data['value']) !=
                  MemberProgramValues.intValue(raw['prizeAmount'])) {
            findings.add(MemberProgramAuditFinding(
              code: 'competition_prize_voucher_inconsistent',
              severity: 'high',
              message: 'Data voucher hadiah berbeda dari daftar pemenang.',
              documentPath: voucher.reference.path,
            ));
          }
        }
      }
    }
    final winnerVoucherIds = <String>{};
    for (final prize in prizes) {
      final winners = prize.data()['winners'];
      if (winners is List) {
        for (final raw in winners.whereType<Map>()) {
          final id = raw['voucherId']?.toString();
          if (id != null && id.isNotEmpty) winnerVoucherIds.add(id);
        }
      }
    }
    for (final voucher in vouchers) {
      if (voucher.data()['type']?.toString() == 'competitionPrize' &&
          !winnerVoucherIds.contains(voucher.id)) {
        findings.add(MemberProgramAuditFinding(
          code: 'competition_prize_voucher_orphaned',
          severity: 'high',
          message: 'Voucher hadiah kompetisi tidak memiliki winner record.',
          documentPath: voucher.reference.path,
        ));
      }
    }
  }

  void _auditExternalClaims(
    List<MemberProgramAuditFinding> findings,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> claims,
  ) {
    for (final claim in claims) {
      final status = claim.data()['status']?.toString().toLowerCase() ?? '';
      if (!{'pending', 'failed', 'completed'}.contains(status)) {
        findings.add(MemberProgramAuditFinding(
          code: 'external_voucher_claim_status_invalid',
          severity: 'high',
          message: 'Status outbox voucher e-santren tidak valid.',
          documentPath: claim.reference.path,
        ));
      }
      if ((claim.data()['voucherCode']?.toString().trim().isEmpty ?? true) ||
          MemberProgramValues.intValue(claim.data()['amount']) <= 0) {
        findings.add(MemberProgramAuditFinding(
          code: 'external_voucher_claim_data_invalid',
          severity: 'high',
          message: 'Kode atau nominal outbox voucher e-santren tidak valid.',
          documentPath: claim.reference.path,
        ));
      }
      if (status == 'pending' || status == 'failed') {
        findings.add(MemberProgramAuditFinding(
          code: 'external_voucher_claim_pending',
          severity: 'high',
          message:
              'Klaim voucher e-santren belum selesai dan perlu dicoba ulang.',
          documentPath: claim.reference.path,
          details: {'status': status, 'lastError': claim.data()['lastError']},
        ));
      }
      if (claim.data()['operationId']?.toString() != claim.id) {
        findings.add(MemberProgramAuditFinding(
          code: 'external_operation_marker_missing',
          severity: 'high',
          message: 'Marker operasi voucher eksternal tidak konsisten.',
          documentPath: claim.reference.path,
        ));
      }
    }
  }

  Future<void> _auditCompetition(List<MemberProgramAuditFinding> findings,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> ledgers) async {
    final periods =
        await _firestore.collection(Col.name('competitionRecords')).get();
    final expected = <String, Map<String, int>>{};
    for (final ledger in ledgers) {
      final data = ledger.data();
      if (data['status']?.toString().toLowerCase() != 'completed' ||
          data['eventType']?.toString() == 'manual_adjustment') {
        continue;
      }
      final periodId = data['periodId']?.toString() ?? '';
      final memberId = data['memberId']?.toString() ?? '';
      if (periodId.isEmpty || memberId.isEmpty) continue;
      final key = '$periodId/$memberId';
      final bucket = expected.putIfAbsent(
          key, () => {'points': 0, 'amount': 0, 'transactions': 0});
      bucket['points'] =
          bucket['points']! + MemberProgramValues.intValue(data['pointsDelta']);
      bucket['amount'] = bucket['amount']! +
          MemberProgramValues.intValue(data['eligibleAmount']);
      final sourceType = data['sourceType']?.toString() ?? '';
      if (data['eventType'] == 'earn' &&
          sourceType != 'edit' &&
          sourceType != 'edit_reverse') {
        bucket['transactions'] = bucket['transactions']! + 1;
      }
    }
    for (final period in periods.docs) {
      final rootData = period.data();
      final legacyKeys = rootData.entries.where((entry) =>
          entry.value is Map &&
          (entry.value as Map).containsKey('customerPoints'));
      if (legacyKeys.isNotEmpty) {
        findings.add(MemberProgramAuditFinding(
          code: 'legacy_flat_competition_record',
          severity: 'medium',
          message: 'Periode masih memiliki record kompetisi flat legacy.',
          documentPath: period.reference.path,
          details: {'memberCount': legacyKeys.length},
        ));
      }
      final canonical = await period.reference.collection('members').get();
      final canonicalIds = <String>{};
      for (final member in canonical.docs) {
        canonicalIds.add(member.id);
        final category =
            MemberProgramValues.categoryValue(member.data()['category']);
        if (category.isEmpty) {
          findings.add(MemberProgramAuditFinding(
            code: 'competition_category_unknown',
            severity: 'medium',
            message: 'Record kompetisi tidak memiliki kategori yang valid.',
            documentPath: member.reference.path,
          ));
        }
        final key = '${period.id}/${member.id}';
        final expectedRecord =
            expected[key] ?? {'points': 0, 'amount': 0, 'transactions': 0};
        final actual = member.data();
        if (MemberProgramValues.intValue(actual['customerPoints']) !=
                expectedRecord['points'] ||
            MemberProgramValues.intValue(actual['amountSpent']) !=
                expectedRecord['amount'] ||
            MemberProgramValues.intValue(actual['numberOfTransaction']) !=
                expectedRecord['transactions']) {
          findings.add(MemberProgramAuditFinding(
            code: 'competition_record_ledger_mismatch',
            severity: 'high',
            message: 'Record kompetisi berbeda dari ledger poin completed.',
            documentPath: member.reference.path,
            details: {
              'record': actual,
              'ledger': expectedRecord,
            },
          ));
        }
      }
      for (final entry in expected.entries
          .where((entry) => entry.key.startsWith('${period.id}/'))) {
        final memberId = entry.key.substring(period.id.length + 1);
        if (!canonicalIds.contains(memberId)) {
          findings.add(MemberProgramAuditFinding(
            code: 'competition_record_missing_from_ledger',
            severity: 'high',
            message:
                'Ledger poin memiliki transaksi tanpa record kompetisi canonical.',
            documentPath: period.reference.path,
            details: {'memberId': memberId, 'ledger': entry.value},
          ));
        }
      }
    }
    final periodIds = periods.docs.map((period) => period.id).toSet();
    for (final key in expected.keys) {
      final separator = key.indexOf('/');
      if (separator <= 0) continue;
      final periodId = key.substring(0, separator);
      if (!periodIds.contains(periodId)) {
        findings.add(MemberProgramAuditFinding(
          code: 'competition_period_missing_from_ledger',
          severity: 'high',
          message:
              'Ledger poin completed memiliki periode kompetisi yang tidak ditemukan.',
          documentPath: 'competitionRecords/$periodId',
          details: {'periodId': periodId},
        ));
      }
    }
  }

  Future<void> _auditOrderMarkers(
      List<MemberProgramAuditFinding> findings) async {
    final statuses = await _firestore.collection(Col.name('Status')).get();
    for (final status in statuses.docs) {
      final data = status.data();
      if (data['isMember'] == true &&
          (data['memberProgramOperationId'] == null &&
              data['pointsOperationId'] == null)) {
        findings.add(MemberProgramAuditFinding(
          code: 'member_order_operation_marker_missing',
          severity: 'high',
          message: 'Pesanan member tidak memiliki marker operasi poin.',
          documentPath: status.reference.path,
        ));
      }
    }
  }
}
