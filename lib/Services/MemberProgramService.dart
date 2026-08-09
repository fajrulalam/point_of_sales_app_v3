import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Models/MemberProgramModels.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

class MemberProgramException implements Exception {
  final String message;

  const MemberProgramException(this.message);

  @override
  String toString() => message;
}

/// Transaction coordinator for member lifetime points, monthly competition
/// records, and cashback campaign progress.
///
/// Checkout callers must prepare an intent before opening their Firestore
/// transaction and then call [queueOrderInTransaction] from inside that
/// transaction.  The method reads every referenced document before queuing a
/// write, so Firestore retries cannot duplicate a reward.
class MemberProgramService {
  MemberProgramService._();

  static FirebaseFirestore get _fs => FirebaseFirestore.instance;

  static const _jakartaOffset = Duration(hours: 7);
  static const _campaignType = 'cashbackCampaign';
  static const _activeCampaignStatus = 'active';
  static const _archivedCampaignStatus = 'archived';

  static int parseInt(dynamic value, [int fallback = 0]) =>
      MemberProgramValues.intValue(value, fallback);

  static String normalizeCategory(dynamic value) =>
      MemberProgramValues.categoryValue(value);

  static String _memberDisplayName(Map<String, dynamic> data) {
    final value = (data['fullName'] ?? data['name'] ?? data['nama'] ?? '')
        .toString()
        .trim();
    return value.length <= 120 ? value : value.substring(0, 120);
  }

  /// Returns a wall-clock representation whose fields are Jakarta time.
  /// This is useful for calendar formatting, but it is not the original
  /// instant and must not be used for elapsed-time comparisons.
  static DateTime _jakarta(DateTime value) => value.toUtc().add(_jakartaOffset);

  static DateTime _jakartaMonthEndInstant(int year, int month) {
    final wallClock = DateTime.utc(year, month + 1, 0, 23, 59, 59);
    return wallClock.subtract(_jakartaOffset);
  }

  static DateTime nowJakarta() => _jakarta(DateTime.now());

  static String periodIdFor(DateTime value) =>
      DateFormat('yyyy-MM').format(_jakarta(value));

  static MemberPointsCalculation calculatePoints({
    required int finalBill,
    int b2bNominal = 0,
  }) {
    return MemberPointsCalculation.calculate(
      finalBill: finalBill,
      b2bNominal: b2bNominal,
    );
  }

  static bool isPeriodEnded(String periodId, {DateTime? now}) {
    final parts = periodId.split('-');
    if (parts.length != 2) return false;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return false;
    }
    final current = (now ?? DateTime.now()).toUtc();
    final end = _jakartaMonthEndInstant(year, month);
    return current.isAfter(end);
  }

  static String categoryLabel(String category) =>
      MemberProgramValues.categoryLabel(category);

  static List<CompetitionMemberRecord> rankCompetitionMembers(
    Iterable<CompetitionMemberRecord> records, {
    String? category,
  }) {
    final normalized = category == null ? null : normalizeCategory(category);
    final result = records
        .where((record) =>
            (normalized == null || record.category == normalized) &&
            record.category.isNotEmpty &&
            record.memberId.isNotEmpty)
        .toList()
      ..sort((a, b) {
        final points = b.customerPoints.compareTo(a.customerPoints);
        if (points != 0) return points;
        final spend = b.amountSpent.compareTo(a.amountSpent);
        if (spend != 0) return spend;
        final transactions =
            b.numberOfTransaction.compareTo(a.numberOfTransaction);
        if (transactions != 0) return transactions;
        return a.memberId.compareTo(b.memberId);
      });
    return result;
  }

  static DateTime prizeExpiryFor(String periodId, {DateTime? now}) {
    final parts = periodId.split('-');
    final year = int.tryParse(parts.first) ?? (now ?? DateTime.now()).year;
    final month = parts.length > 1
        ? (int.tryParse(parts[1]) ?? (now ?? DateTime.now()).month)
        : (now ?? DateTime.now()).month;
    // Store the instant corresponding to 23:59:59 on the final Jakarta day
    // of the month following the competition month.
    return _jakartaMonthEndInstant(year, month + 1);
  }

  /// Selects the one campaign that may receive the current transaction's
  /// points.  Expiry is the primary priority and the campaign ID makes ties
  /// deterministic across devices.
  static CampaignCandidate? selectCampaignCandidate(
    Iterable<CampaignCandidate> candidates, {
    required DateTime eventAt,
  }) {
    final eligible = candidates.where((candidate) {
      if (!_isCampaignActive(candidate.groupData, eventAt)) return false;
      final threshold = parseInt(candidate.groupData['threshold']);
      final value = parseInt(candidate.groupData['value']);
      if (threshold <= 0 || value <= 0) return false;
      final existing = candidate.existingVoucherData;
      if (existing == null) return true;
      final existingStatus = existing['status']?.toString().toUpperCase();
      return existing['isClaimed'] != true && existingStatus == 'IN_PROGRESS';
    }).toList()
      ..sort((a, b) {
        final aDate = _date(a.groupData['expireDate']);
        final bDate = _date(b.groupData['expireDate']);
        if (aDate != null && bDate != null) {
          final dateCompare = aDate.compareTo(bDate);
          if (dateCompare != 0) return dateCompare;
        }
        return a.groupId.compareTo(b.groupId);
      });
    return eligible.isEmpty ? null : eligible.first;
  }

  static String _safeId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'unknown';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  static String _hashId(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  static String campaignVoucherId(String groupId, String memberId) {
    final safeGroup = _safeId(groupId);
    final safeMember = _safeId(memberId);
    final readable = 'campaign_${safeGroup}_$safeMember';
    if (readable.length <= 120 &&
        safeGroup == groupId &&
        safeMember == memberId) {
      return readable;
    }
    return 'campaign_${_hashId(groupId)}_${_hashId(memberId)}';
  }

  static String prizeVoucherId(
      String periodId, String category, int rank, String memberId) {
    return 'competition_${_safeId(periodId)}_${_safeId(category)}_${rank}_${_hashId(memberId)}';
  }

  static bool _isSafeLegacyMemberKey(String memberId) =>
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(memberId);

  static DateTime? _date(dynamic value) => MemberProgramValues.dateValue(value);

  static bool _campaignDatesContain(
      Map<String, dynamic> data, DateTime eventAt) {
    final active = _date(data['activeDate']);
    final expires = _date(data['expireDate']);
    if (active == null || expires == null || expires.isBefore(active)) {
      return false;
    }
    return !eventAt.isBefore(active) && !eventAt.isAfter(expires);
  }

  static bool _isCampaignActive(Map<String, dynamic> data, DateTime eventAt) {
    if (data['type']?.toString() != _campaignType) return false;
    final status = data['status']?.toString().toLowerCase() ?? '';
    final isActive = data['isActive'] == true;
    // New writes always carry an explicit status.  Treat legacy records with
    // missing or unknown status as invalid rather than allowing a malformed
    // campaign to continue issuing financial vouchers.
    if (!isActive || status != _activeCampaignStatus) return false;
    if (parseInt(data['threshold']) <= 0 || parseInt(data['value']) <= 0) {
      return false;
    }
    return _campaignDatesContain(data, eventAt);
  }

  static Future<MemberProgramPreparation> prepareOrder({
    required String operationId,
    required String sourceType,
    required String sourceId,
    required String? memberId,
    required int grossTotal,
    required int finalBill,
    int b2bNominal = 0,
    DateTime? eventAt,
  }) async {
    final event = eventAt ?? DateTime.now();
    final periodId = periodIdFor(event);
    final points = calculatePoints(
      finalBill: finalBill,
      b2bNominal: b2bNominal,
    );
    // finalBill is already the bill after ordinary voucher discounts.  B2B is
    // a payment sponsorship inside that bill, so it must not be subtracted a
    // second time when the ordinary discount is recorded.
    final ordinaryDiscount = (grossTotal - finalBill).clamp(0, grossTotal);
    final flags = <String>[];
    final normalizedMemberId = memberId?.trim() ?? '';
    final memberSelected = normalizedMemberId.isNotEmpty;

    DocumentSnapshot<Map<String, dynamic>>? memberSnapshot;
    if (normalizedMemberId.isNotEmpty) {
      try {
        memberSnapshot = await _fs
            .collection(Col.name('Members'))
            .doc(normalizedMemberId)
            .get();
      } catch (_) {
        flags.add('member_lookup_failed');
      }
    }

    final memberExists = memberSnapshot?.exists == true;
    final memberData = memberSnapshot?.data() ?? const <String, dynamic>{};
    final memberName = _memberDisplayName(memberData);
    final category = normalizeCategory(
      memberData['category'] ??
          memberData['memberCategory'] ??
          memberData['role'],
    );
    if (memberSelected && !memberExists) {
      flags.add('member_reference_missing');
    }
    if (memberSelected && category.isEmpty) {
      flags.add('member_category_missing_or_unknown');
    }

    CampaignCandidate? campaign;
    var campaignLookupFailed = false;
    if (memberExists && points.pointsDelta > 0) {
      try {
        campaign = await _findCampaignCandidate(
          memberId: normalizedMemberId,
          eventAt: event,
        );
      } catch (_) {
        campaignLookupFailed = true;
        flags.add('campaign_lookup_failed');
      }
    }

    return MemberProgramPreparation(
      operationId: operationId,
      sourceType: sourceType,
      sourceId: sourceId,
      memberId: normalizedMemberId,
      memberName: memberName,
      periodId: periodId,
      category: category,
      eventAt: event,
      grossTotal: grossTotal,
      finalBill: finalBill,
      ordinaryVoucherDiscount: ordinaryDiscount,
      points: points,
      memberSelected: memberSelected,
      memberExists: memberExists,
      campaign: campaign,
      campaignLookupFailed: campaignLookupFailed,
      auditFlags: flags,
    );
  }

  static Future<CampaignCandidate?> _findCampaignCandidate({
    required String memberId,
    required DateTime eventAt,
  }) async {
    // Both queries are independent, so issue them concurrently. Filters are
    // tightened to match exactly what selectCampaignCandidate/_isCampaignActive
    // already require client-side (isActive/status=='active' for groups,
    // type==_campaignType for vouchers) — this only reduces bytes transferred,
    // it cannot change which candidate is ultimately selected.
    final results = await Future.wait([
      _fs
          .collection(Col.name('voucherGroup'))
          .where('type', isEqualTo: _campaignType)
          .where('isActive', isEqualTo: true)
          .where('status', isEqualTo: _activeCampaignStatus)
          .get(),
      _fs
          .collection(Col.name('vouchers'))
          .where('userId', isEqualTo: memberId)
          .where('type', isEqualTo: _campaignType)
          .get(),
    ]);
    final groups = results[0];
    final vouchers = results[1];
    final byGroup = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final voucher in vouchers.docs) {
      final groupId = voucher.data()['voucherGroupId']?.toString();
      if (groupId == null || groupId.isEmpty) {
        continue;
      }
      final previous = byGroup[groupId];
      if (previous == null || voucher.id.compareTo(previous.id) < 0) {
        byGroup[groupId] = voucher;
      }
    }

    final candidates = groups.docs.map((group) {
      final existing = byGroup[group.id];
      return CampaignCandidate(
        groupId: group.id,
        voucherId: existing?.id ?? campaignVoucherId(group.id, memberId),
        groupData: group.data(),
        existingVoucherData: existing?.data(),
      );
    });
    return selectCampaignCandidate(candidates, eventAt: eventAt);
  }

  static DocumentReference<Map<String, dynamic>> _memberRef(String memberId) =>
      _fs.collection(Col.name('Members')).doc(memberId);

  static DocumentReference<Map<String, dynamic>> _pointLedgerRef(
          String operationId) =>
      _fs.collection(Col.name('pointTransactions')).doc(operationId);

  static DocumentReference<Map<String, dynamic>> _programOperationRef(
          String operationId) =>
      _fs.collection(Col.name('memberProgramOperations')).doc(operationId);

  static DocumentReference<Map<String, dynamic>> _competitionPeriodRef(
          String periodId) =>
      _fs.collection(Col.name('competitionRecords')).doc(periodId);

  static DocumentReference<Map<String, dynamic>> _competitionMemberRef(
          String periodId, String memberId) =>
      _competitionPeriodRef(periodId).collection('members').doc(memberId);

  static DocumentReference<Map<String, dynamic>> _legacyCompetitionRef(
          String periodId) =>
      _competitionPeriodRef(periodId);

  static Future<MemberProgramOperationResult> queueOrderInTransaction({
    required Transaction transaction,
    required MemberProgramPreparation preparation,
  }) async {
    final operationId = preparation.operationId;
    final ledgerRef = _pointLedgerRef(operationId);
    final programOperationRef = _programOperationRef(operationId);
    final periodRef = _competitionPeriodRef(preparation.periodId);
    final competitionMemberRef =
        _competitionMemberRef(preparation.periodId, preparation.memberId);
    final memberRef =
        preparation.memberId.isEmpty ? null : _memberRef(preparation.memberId);
    final legacyRef = _legacyCompetitionRef(preparation.periodId);
    final campaignGroupRef = preparation.campaign == null
        ? null
        : _fs
            .collection(Col.name('voucherGroup'))
            .doc(preparation.campaign!.groupId);
    final campaignVoucherRef = preparation.campaign == null
        ? null
        : _fs
            .collection(Col.name('vouchers'))
            .doc(preparation.campaign!.voucherId);

    // Every read occurs before any write.  This is required because Firestore
    // may replay a transaction callback after a concurrent update.
    final ledgerSnapshot = await transaction.get(ledgerRef);
    final operationSnapshot = await transaction.get(programOperationRef);
    final periodSnapshot = await transaction.get(periodRef);
    final memberSnapshot =
        memberRef == null ? null : await transaction.get(memberRef);
    if (preparation.memberId.isNotEmpty) {
      await transaction.get(competitionMemberRef);
    }
    // legacyRef and periodRef are the same document (_legacyCompetitionRef
    // just aliases _competitionPeriodRef), so reuse periodSnapshot instead of
    // fetching it a second time.
    final legacySnapshot =
        _isSafeLegacyMemberKey(preparation.memberId) ? periodSnapshot : null;
    final campaignGroupSnapshot = campaignGroupRef == null
        ? null
        : await transaction.get(campaignGroupRef);
    final campaignVoucherSnapshot = campaignVoucherRef == null
        ? null
        : await transaction.get(campaignVoucherRef);

    final alreadyCompleted = (ledgerSnapshot.exists &&
            ledgerSnapshot.data()?['status']?.toString().toLowerCase() ==
                'completed') ||
        (operationSnapshot.exists &&
            operationSnapshot.data()?['status']?.toString().toLowerCase() ==
                'completed');
    if (alreadyCompleted) {
      return const MemberProgramOperationResult.alreadyApplied();
    }

    final flags = [...preparation.auditFlags];
    if (!preparation.memberSelected) {
      transaction.set(
        programOperationRef,
        {
          'schemaVersion': 2,
          'operationId': operationId,
          'status': 'skipped',
          'reason': 'member_not_selected',
          'auditFlags': flags,
          'completedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return MemberProgramOperationResult.skipped(flags: flags);
    }
    final memberIsValid = memberSnapshot?.exists == true;
    final periodStatus =
        periodSnapshot.data()?['status']?.toString().toLowerCase() ?? 'open';
    final periodFinalized =
        periodStatus == 'finalized' || periodStatus == 'finalizing';

    if (!memberIsValid) {
      flags.add('points_not_applied_member_missing');
      final pendingLedger = preparation.toLedgerMap(
        eventType: 'earn',
        pointsDelta: preparation.points.pointsDelta,
        status: 'pending',
      )..addAll({
          'memberProgramStatus': 'pending',
          'campaignStatus': 'pending',
        });
      transaction.set(ledgerRef, pendingLedger, SetOptions(merge: true));
      transaction.set(
        programOperationRef,
        {
          'schemaVersion': 2,
          'operationId': operationId,
          'status': 'pending',
          'reason': 'member_reference_missing',
          'auditFlags': flags,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return MemberProgramOperationResult.pending(flags: flags);
    }

    if (isPeriodEnded(preparation.periodId)) {
      flags.add('competition_period_ended');
      final pendingLedger = preparation.toLedgerMap(
        eventType: 'earn',
        pointsDelta: preparation.points.pointsDelta,
        status: 'pending',
      )..addAll({
          'memberProgramStatus': 'pending',
          'campaignStatus': 'pending',
        });
      transaction.set(ledgerRef, pendingLedger, SetOptions(merge: true));
      transaction.set(
        programOperationRef,
        {
          'schemaVersion': 2,
          'operationId': operationId,
          'status': 'pending',
          'reason': 'competition_period_ended',
          'auditFlags': flags,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return MemberProgramOperationResult.pending(flags: flags);
    }

    if (periodFinalized) {
      flags.add('points_period_finalized');
      final pendingLedger = preparation.toLedgerMap(
        eventType: 'earn',
        pointsDelta: preparation.points.pointsDelta,
        status: 'pending',
      )..addAll({
          'memberProgramStatus': 'pending',
          'campaignStatus': 'pending',
        });
      transaction.set(ledgerRef, pendingLedger, SetOptions(merge: true));
      transaction.set(
        programOperationRef,
        {
          'schemaVersion': 2,
          'operationId': operationId,
          'status': 'pending',
          'reason': 'competition_period_finalized',
          'auditFlags': flags,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return MemberProgramOperationResult.pending(flags: flags);
    }

    if (periodSnapshot.exists && periodStatus != 'open') {
      flags.add('competition_period_status_invalid');
      final pendingLedger = preparation.toLedgerMap(
        eventType: 'earn',
        pointsDelta: preparation.points.pointsDelta,
        status: 'pending',
      )..addAll({
          'memberProgramStatus': 'pending',
          'campaignStatus': 'pending',
        });
      transaction.set(ledgerRef, pendingLedger, SetOptions(merge: true));
      transaction.set(
        programOperationRef,
        {
          'schemaVersion': 2,
          'operationId': operationId,
          'status': 'pending',
          'reason': 'competition_period_status_invalid',
          'auditFlags': flags,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return MemberProgramOperationResult.pending(flags: flags);
    }

    if (preparation.points.pointsDelta != 0) {
      transaction.update(memberRef!, {
        'points': FieldValue.increment(preparation.points.pointsDelta),
        'pointsUpdatedAt': FieldValue.serverTimestamp(),
      });
    }

    transaction.set(
      competitionMemberRef,
      {
        'schemaVersion': 2,
        'memberId': preparation.memberId,
        if (preparation.memberName.isNotEmpty)
          'memberName': preparation.memberName,
        'category': preparation.category,
        'customerPoints': FieldValue.increment(preparation.points.pointsDelta),
        'amountSpent': FieldValue.increment(preparation.points.eligibleAmount),
        'numberOfTransaction': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    transaction.set(
      periodRef,
      {
        'schemaVersion': 2,
        'periodId': preparation.periodId,
        'status': periodSnapshot.exists
            ? (periodSnapshot.data()?['status'] ?? 'open')
            : 'open',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (legacySnapshot != null &&
        _isSafeLegacyMemberKey(preparation.memberId)) {
      transaction.set(
        legacyRef,
        {
          preparation.memberId: {
            if (preparation.memberName.isNotEmpty)
              'memberName': preparation.memberName,
            'category': preparation.category,
            'customerPoints':
                FieldValue.increment(preparation.points.pointsDelta),
            'amountSpent':
                FieldValue.increment(preparation.points.eligibleAmount),
            'numberOfTransaction': FieldValue.increment(1),
          },
        },
        SetOptions(merge: true),
      );
    } else if (preparation.memberId.isNotEmpty) {
      flags.add('legacy_competition_key_not_materialized');
    }

    var campaignStatus = 'none';
    if (preparation.campaignLookupFailed) {
      campaignStatus = 'pending';
      flags.add('campaign_progress_pending');
    } else if (preparation.campaign != null &&
        preparation.points.pointsDelta > 0) {
      final campaign = preparation.campaign!;
      final groupData = campaignGroupSnapshot?.data();
      if (groupData == null ||
          !_isCampaignActive(groupData, preparation.eventAt)) {
        campaignStatus = 'pending';
        flags.add('campaign_reference_missing_or_inactive');
      } else {
        final threshold = parseInt(groupData['threshold']);
        final value = parseInt(groupData['value']);
        final voucherData = campaignVoucherSnapshot?.data();
        final currentStatus =
            voucherData?['status']?.toString().toUpperCase() ?? '';
        final currentClaimed = voucherData?['isClaimed'] == true ||
            currentStatus == 'CLAIMED' ||
            currentStatus == 'DISABLED';
        if (currentClaimed) {
          campaignStatus = 'pending';
          flags.add('campaign_voucher_already_claimed');
        } else if (voucherData != null && currentStatus != 'IN_PROGRESS') {
          campaignStatus = 'pending';
          flags.add('campaign_voucher_not_in_progress');
        } else {
          final currentPoints = parseInt(voucherData?['userPoints'], 0);
          final nextPoints = currentPoints + preparation.points.pointsDelta;
          final nextStatus =
              nextPoints >= threshold ? 'READY_TO_CLAIM' : 'IN_PROGRESS';
          final voucherFields = <String, dynamic>{
            'schemaVersion': 2,
            'voucherId': campaign.voucherId,
            'voucherGroupId': campaign.groupId,
            'type': _campaignType,
            'userId': preparation.memberId,
            'userPoints': nextPoints,
            'threshold': threshold,
            'value': value,
            'valueRemaining': value,
            'valueUsed': 0,
            'sekaliPakai': true,
            'isActive': true,
            'isClaimed': false,
            'status': nextStatus,
            'activeDate': groupData['activeDate'],
            'expireDate': groupData['expireDate'],
            'transactionRequirement': parseInt(
              groupData['transactionRequirement'],
            ),
            'voucherName': groupData['voucherName'] ?? 'Voucher Campaign',
            'nama': memberSnapshot!.data()?['fullName'] ??
                memberSnapshot.data()?['name'] ??
                memberSnapshot.data()?['nama'] ??
                '',
            'lastUpdatedAt': FieldValue.serverTimestamp(),
            'lastPointOperationId': operationId,
          };
          if (campaignVoucherSnapshot?.exists == true) {
            transaction.update(campaignVoucherRef!, voucherFields);
          } else {
            transaction.set(campaignVoucherRef!, {
              ...voucherFields,
              'createdAt': FieldValue.serverTimestamp(),
            });
            transaction.update(campaignGroupRef!, {
              'totalParticipants': FieldValue.increment(1),
            });
          }
          campaignStatus = 'applied';
        }
      }
    }

    final ledger = preparation.toLedgerMap(
      eventType: 'earn',
      pointsDelta: preparation.points.pointsDelta,
    )..addAll({
        'memberProgramStatus': 'completed',
        'campaignStatus': campaignStatus,
      });
    transaction.set(ledgerRef, ledger, SetOptions(merge: true));
    transaction.set(
      programOperationRef,
      {
        'schemaVersion': 2,
        'operationId': operationId,
        'status': 'completed',
        'pointsDelta': preparation.points.pointsDelta,
        'campaignStatus': campaignStatus,
        'auditFlags': flags,
        'completedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return MemberProgramOperationResult.applied(flags: flags);
  }

  /// Completes campaign progress for an already-completed point operation
  /// whose campaign lookup or campaign write was temporarily unavailable.
  /// Points and competition totals are deliberately not touched here: those
  /// were committed by the original checkout and the campaign portion has its
  /// own idempotent retry marker.
  static Future<MemberProgramOperationResult> retryCampaignProgress(
      String operationId) async {
    final ledgerRef = _pointLedgerRef(operationId);
    final operationRef = _programOperationRef(operationId);
    final initialLedgerSnapshot = await ledgerRef.get();
    if (!initialLedgerSnapshot.exists) {
      throw const MemberProgramException('Ledger poin tidak ditemukan.');
    }
    final initialLedger = initialLedgerSnapshot.data() ?? <String, dynamic>{};
    if (initialLedger['status']?.toString().toLowerCase() != 'completed' ||
        initialLedger['eventType']?.toString() != 'earn') {
      throw const MemberProgramException(
          'Operasi poin belum selesai atau tidak dapat dicoba ulang.');
    }
    if (initialLedger['campaignStatus']?.toString().toLowerCase() ==
        'applied') {
      return const MemberProgramOperationResult.alreadyApplied();
    }

    final memberId = initialLedger['memberId']?.toString() ?? '';
    final eventAt = _date(initialLedger['eventAt']);
    if (memberId.isEmpty || eventAt == null) {
      throw const MemberProgramException(
          'Data campaign pada ledger tidak lengkap dan perlu penyesuaian administrator.');
    }
    final pointsDelta = parseInt(
      initialLedger['campaignPointsDelta'],
      parseInt(initialLedger['pointsDelta']),
    );
    if (pointsDelta <= 0) {
      return const MemberProgramOperationResult.alreadyApplied();
    }

    var groupId = initialLedger['campaignGroupId']?.toString() ?? '';
    var voucherId = initialLedger['campaignVoucherId']?.toString() ?? '';
    if (groupId.isEmpty || voucherId.isEmpty) {
      final candidate = await _findCampaignCandidate(
        memberId: memberId,
        eventAt: eventAt,
      );
      if (candidate == null) {
        throw const MemberProgramException(
            'Tidak ada campaign aktif yang dapat menerima progres transaksi ini.');
      }
      groupId = candidate.groupId;
      voucherId = candidate.voucherId;
    }

    final groupRef = _fs.collection(Col.name('voucherGroup')).doc(groupId);
    final voucherRef = _fs.collection(Col.name('vouchers')).doc(voucherId);
    final memberRef = _memberRef(memberId);
    return _fs.runTransaction((transaction) async {
      final ledgerSnapshot = await transaction.get(ledgerRef);
      final operationSnapshot = await transaction.get(operationRef);
      final memberSnapshot = await transaction.get(memberRef);
      final groupSnapshot = await transaction.get(groupRef);
      final voucherSnapshot = await transaction.get(voucherRef);

      final ledger = ledgerSnapshot.data() ?? <String, dynamic>{};
      final operation = operationSnapshot.data() ?? <String, dynamic>{};
      if (ledger['campaignStatus']?.toString().toLowerCase() == 'applied' ||
          operation['campaignStatus']?.toString().toLowerCase() == 'applied') {
        return const MemberProgramOperationResult.alreadyApplied();
      }
      if (!memberSnapshot.exists || !groupSnapshot.exists) {
        throw const MemberProgramException(
            'Member atau campaign tidak ditemukan. Progres campaign tertunda untuk audit.');
      }
      final groupData = groupSnapshot.data() ?? <String, dynamic>{};
      if (!_isCampaignActive(groupData, eventAt)) {
        throw const MemberProgramException(
            'Campaign sudah tidak aktif pada waktu transaksi dan tidak dapat menerima progres ulang.');
      }
      final threshold = parseInt(groupData['threshold']);
      final value = parseInt(groupData['value']);
      if (threshold <= 0 || value <= 0) {
        throw const MemberProgramException(
            'Definisi campaign tidak valid dan perlu diperiksa administrator.');
      }

      final flags = <String>[];
      final existing = voucherSnapshot.data();
      final existingStatus =
          existing?['status']?.toString().toUpperCase() ?? '';
      if (existing?['lastPointOperationId']?.toString() == operationId) {
        flags.add('campaign_progress_already_materialized');
      } else if (existing != null) {
        if (existingStatus == 'CLAIMED' ||
            existingStatus == 'DISABLED' ||
            existing['isClaimed'] == true) {
          throw const MemberProgramException(
              'Voucher campaign sudah diklaim atau dinonaktifkan; progres tidak boleh ditebak ulang.');
        }
        if (existingStatus != 'IN_PROGRESS') {
          throw const MemberProgramException(
              'Status voucher campaign ambigu; progres perlu penyesuaian administrator.');
        }
        final currentPoints = parseInt(existing['userPoints']);
        final nextPoints = currentPoints + pointsDelta;
        transaction.update(voucherRef, {
          'userPoints': nextPoints,
          'threshold': threshold,
          'value': value,
          'status': nextPoints >= threshold ? 'READY_TO_CLAIM' : 'IN_PROGRESS',
          'isActive': true,
          'isClaimed': false,
          'lastPointOperationId': operationId,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final nextPoints = pointsDelta;
        transaction.set(voucherRef, {
          'schemaVersion': 2,
          'voucherId': voucherId,
          'voucherGroupId': groupId,
          'type': _campaignType,
          'userId': memberId,
          'userPoints': nextPoints,
          'threshold': threshold,
          'value': value,
          'valueRemaining': value,
          'valueUsed': 0,
          'sekaliPakai': true,
          'isActive': true,
          'isClaimed': false,
          'status': nextPoints >= threshold ? 'READY_TO_CLAIM' : 'IN_PROGRESS',
          'activeDate': groupData['activeDate'],
          'expireDate': groupData['expireDate'],
          'transactionRequirement': parseInt(
            groupData['transactionRequirement'],
          ),
          'voucherName': groupData['voucherName'] ?? 'Voucher Campaign',
          'nama': memberSnapshot.data()?['fullName'] ??
              memberSnapshot.data()?['name'] ??
              memberSnapshot.data()?['nama'] ??
              '',
          'lastPointOperationId': operationId,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(groupRef, {
          'totalParticipants': FieldValue.increment(1),
        });
      }
      if (flags.isEmpty) flags.add('campaign_progress_retried');
      final existingFlags = ledger['auditFlags'] is List
          ? (ledger['auditFlags'] as List)
              .map((value) => value.toString())
              .toList()
          : <String>[];
      final mergedFlags = <String>{...existingFlags, ...flags}.toList();
      transaction.set(
        ledgerRef,
        {
          'campaignGroupId': groupId,
          'campaignVoucherId': voucherId,
          'campaignStatus': 'applied',
          'auditFlags': mergedFlags,
          'campaignRetriedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      transaction.set(
        operationRef,
        {
          'status': 'completed',
          'campaignStatus': 'applied',
          'campaignGroupId': groupId,
          'campaignVoucherId': voucherId,
          'auditFlags': mergedFlags,
          'campaignRetriedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return MemberProgramOperationResult.applied(flags: mergedFlags);
    });
  }

  /// Applies the member-program delta for a completed-order edit.  The old
  /// earn operation is never overwritten: a compensating reverse entry and a
  /// new edit entry are written under distinct immutable IDs.
  static Future<MemberProgramOperationResult> queueOrderEditInTransaction({
    required Transaction transaction,
    required String editOperationId,
    required String originalPointOperationId,
    required MemberProgramPreparation newPreparation,
  }) async {
    final editRef = _programOperationRef(editOperationId);
    final oldLedgerRef = _pointLedgerRef(originalPointOperationId);
    final reverseLedgerRef = _pointLedgerRef('${editOperationId}_reverse');
    final newLedgerRef = _pointLedgerRef(editOperationId);
    final memberRef = newPreparation.memberId.isEmpty
        ? null
        : _memberRef(newPreparation.memberId);
    final periodRef = _competitionPeriodRef(newPreparation.periodId);
    final competitionMemberRef = _competitionMemberRef(
      newPreparation.periodId,
      newPreparation.memberId,
    );
    final editSnapshot = await transaction.get(editRef);
    if (editSnapshot.exists &&
        editSnapshot.data()?['status']?.toString().toLowerCase() ==
            'completed') {
      return const MemberProgramOperationResult.alreadyApplied();
    }
    final oldLedger = await transaction.get(oldLedgerRef);
    if (!oldLedger.exists ||
        oldLedger.data()?['status']?.toString().toLowerCase() != 'completed') {
      throw const MemberProgramException(
          'Riwayat poin pesanan lama tidak ditemukan. Edit diblokir agar saldo tidak salah.');
    }
    final oldData = oldLedger.data() ?? <String, dynamic>{};
    final oldMemberId = oldData['memberId']?.toString() ?? '';
    if (!newPreparation.memberSelected ||
        oldMemberId.isEmpty ||
        oldMemberId != newPreparation.memberId) {
      throw const MemberProgramException(
          'Member pesanan lama tidak cocok. Edit memerlukan penyesuaian administrator.');
    }
    final periodId = oldData['periodId']?.toString() ?? '';
    if (periodId.isEmpty || periodId != newPreparation.periodId) {
      throw const MemberProgramException(
          'Periode poin pesanan berubah dan tidak aman untuk diedit.');
    }
    final periodSnapshot = await transaction.get(periodRef);
    final memberSnapshot = await transaction.get(memberRef!);
    await transaction.get(competitionMemberRef);
    // _legacyCompetitionRef(periodId) is the same document as periodRef here
    // (periodId == newPreparation.periodId, checked above), so reuse
    // periodSnapshot instead of fetching it a second time.
    final legacySnapshot =
        _isSafeLegacyMemberKey(newPreparation.memberId) ? periodSnapshot : null;

    final oldCampaignGroupId = oldData['campaignGroupId']?.toString();
    final oldCampaignVoucherId = oldData['campaignVoucherId']?.toString();
    final oldCampaignGroupRef =
        oldCampaignGroupId == null || oldCampaignGroupId.isEmpty
            ? null
            : _fs.collection(Col.name('voucherGroup')).doc(oldCampaignGroupId);
    final oldCampaignVoucherRef =
        oldCampaignVoucherId == null || oldCampaignVoucherId.isEmpty
            ? null
            : _fs.collection(Col.name('vouchers')).doc(oldCampaignVoucherId);
    final oldCampaignGroupSnapshot = oldCampaignGroupRef == null
        ? null
        : await transaction.get(oldCampaignGroupRef);
    final oldCampaignVoucherSnapshot = oldCampaignVoucherRef == null
        ? null
        : await transaction.get(oldCampaignVoucherRef);
    final newCampaignGroupRef = newPreparation.campaign == null
        ? null
        : _fs
            .collection(Col.name('voucherGroup'))
            .doc(newPreparation.campaign!.groupId);
    final newCampaignVoucherRef = newPreparation.campaign == null
        ? null
        : _fs
            .collection(Col.name('vouchers'))
            .doc(newPreparation.campaign!.voucherId);
    final newCampaignGroupSnapshot = newCampaignGroupRef == null
        ? null
        : await transaction.get(newCampaignGroupRef);
    final newCampaignVoucherSnapshot = newCampaignVoucherRef == null
        ? null
        : await transaction.get(newCampaignVoucherRef);
    final sameCampaignVoucher = oldCampaignVoucherRef != null &&
        newCampaignVoucherRef != null &&
        oldCampaignVoucherRef.path == newCampaignVoucherRef.path;

    if (!memberSnapshot.exists) {
      throw const MemberProgramException(
          'Member pesanan tidak ditemukan. Edit diblokir.');
    }
    if (periodSnapshot.data()?['status']?.toString().toLowerCase() ==
            'finalized' ||
        isPeriodEnded(periodId)) {
      throw const MemberProgramException(
          'Periode kompetisi sudah ditutup. Edit memerlukan penyesuaian administrator.');
    }

    final oldPoints = parseInt(oldData['pointsDelta']);
    final oldEligible = parseInt(oldData['eligibleAmount']);
    final newPoints = newPreparation.points.pointsDelta;
    final newEligible = newPreparation.points.eligibleAmount;
    final oldCampaignChanged = oldCampaignGroupId != null ||
        oldCampaignVoucherId != null ||
        newPreparation.campaign != null;
    final oldVoucherData = oldCampaignVoucherSnapshot?.data();
    final oldVoucherStatus =
        oldVoucherData?['status']?.toString().toUpperCase() ?? '';
    final oldVoucherClaimed = oldVoucherData?['isClaimed'] == true ||
        oldVoucherStatus == 'CLAIMED' ||
        oldVoucherStatus == 'DISABLED';
    if (oldVoucherClaimed && oldCampaignChanged && oldPoints != newPoints) {
      throw const MemberProgramException(
          'Voucher campaign sudah diklaim atau dinonaktifkan. Edit memerlukan penyesuaian administrator.');
    }

    final flags = <String>[...newPreparation.auditFlags];
    if (!newPreparation.category.isNotEmpty) {
      flags.add('member_category_missing_or_unknown');
    }
    if (oldPoints != newPoints) {
      transaction.update(memberRef, {
        'points': FieldValue.increment(newPoints - oldPoints),
        'pointsUpdatedAt': FieldValue.serverTimestamp(),
      });
    }
    transaction.set(
      competitionMemberRef,
      {
        'schemaVersion': 2,
        'memberId': newPreparation.memberId,
        'category': newPreparation.category,
        'customerPoints': FieldValue.increment(newPoints - oldPoints),
        'amountSpent': FieldValue.increment(newEligible - oldEligible),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (legacySnapshot != null && _isSafeLegacyMemberKey(oldMemberId)) {
      transaction.set(
        _legacyCompetitionRef(periodId),
        <String, dynamic>{
          oldMemberId: {
            'category': newPreparation.category,
            'customerPoints': FieldValue.increment(newPoints - oldPoints),
            'amountSpent': FieldValue.increment(newEligible - oldEligible),
          },
        },
        SetOptions(merge: true),
      );
    } else {
      flags.add('legacy_competition_key_not_materialized');
    }

    var campaignStatus = 'none';
    final hasOldCampaignReference =
        oldCampaignGroupId != null || oldCampaignVoucherId != null;
    if (hasOldCampaignReference &&
        (oldCampaignGroupRef == null ||
            oldCampaignVoucherRef == null ||
            oldVoucherData == null ||
            oldCampaignGroupSnapshot?.exists != true)) {
      throw const MemberProgramException(
          'Riwayat voucher campaign pesanan tidak lengkap. Edit memerlukan penyesuaian administrator.');
    }
    if (oldCampaignGroupRef != null &&
        oldCampaignVoucherRef != null &&
        !sameCampaignVoucher) {
      if (!oldVoucherClaimed && oldPoints != 0) {
        final oldCampaignData = oldVoucherData!;
        if (oldCampaignGroupSnapshot
                ?.data()?['status']
                ?.toString()
                .toLowerCase() ==
            _archivedCampaignStatus) {
          throw const MemberProgramException(
              'Campaign lama sudah diarsipkan. Edit memerlukan penyesuaian administrator.');
        }
        final current = parseInt(oldCampaignData['userPoints']);
        final next = current - oldPoints;
        if (next < 0) {
          throw const MemberProgramException(
              'Progress voucher campaign tidak konsisten. Edit diblokir untuk audit administrator.');
        }
        final threshold = parseInt(oldCampaignData['threshold']);
        transaction.update(oldCampaignVoucherRef, {
          'userPoints': next,
          'status': next >= threshold ? 'READY_TO_CLAIM' : 'IN_PROGRESS',
          'isActive': true,
          'isClaimed': false,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'lastPointOperationId': editOperationId,
        });
        campaignStatus = 'reversed_and_reapplied';
      }
    }

    if (newPreparation.campaign != null &&
        (newPoints > 0 || (sameCampaignVoucher && newPoints != oldPoints))) {
      final campaign = newPreparation.campaign!;
      final campaignPointDelta =
          sameCampaignVoucher ? newPoints - oldPoints : newPoints;
      final groupData = newCampaignGroupSnapshot?.data();
      if (groupData == null ||
          !_isCampaignActive(groupData, newPreparation.eventAt)) {
        if (campaignPointDelta != 0) {
          throw const MemberProgramException(
              'Campaign tujuan tidak aktif atau definisinya tidak valid. Edit diblokir agar progres campaign tidak hilang.');
        }
        campaignStatus = 'unchanged';
      } else {
        final threshold = parseInt(groupData['threshold']);
        final value = parseInt(groupData['value']);
        final existing = newCampaignVoucherSnapshot?.data();
        final status = existing?['status']?.toString().toUpperCase() ?? '';
        if (existing != null &&
            campaignPointDelta != 0 &&
            (status == 'CLAIMED' ||
                status == 'DISABLED' ||
                existing['isClaimed'] == true)) {
          throw const MemberProgramException(
              'Voucher campaign tujuan sudah diklaim. Edit memerlukan penyesuaian administrator.');
        }
        if (existing != null &&
            status != 'IN_PROGRESS' &&
            status != 'READY_TO_CLAIM' &&
            campaignPointDelta != 0) {
          throw const MemberProgramException(
              'Status voucher campaign tidak valid. Edit memerlukan penyesuaian administrator.');
        }
        final current = parseInt(existing?['userPoints']);
        if (campaignPointDelta == 0) {
          campaignStatus = 'unchanged';
        } else {
          final next = current + campaignPointDelta;
          if (next < 0) {
            throw const MemberProgramException(
                'Progress voucher campaign tidak konsisten setelah edit.');
          }
          final fields = <String, dynamic>{
            'schemaVersion': 2,
            'voucherId': campaign.voucherId,
            'voucherGroupId': campaign.groupId,
            'type': _campaignType,
            'userId': newPreparation.memberId,
            'userPoints': next,
            'threshold': threshold,
            'value': value,
            'valueRemaining': existing?['valueRemaining'] ?? value,
            'valueUsed': parseInt(existing?['valueUsed']),
            'sekaliPakai': existing?['sekaliPakai'] ?? true,
            'isActive': true,
            'isClaimed': false,
            'status': next >= threshold ? 'READY_TO_CLAIM' : 'IN_PROGRESS',
            'activeDate': groupData['activeDate'],
            'expireDate': groupData['expireDate'],
            'transactionRequirement':
                parseInt(groupData['transactionRequirement']),
            'lastUpdatedAt': FieldValue.serverTimestamp(),
            'lastPointOperationId': editOperationId,
          };
          if (newCampaignVoucherSnapshot?.exists == true) {
            transaction.update(newCampaignVoucherRef!, fields);
          } else {
            transaction.set(newCampaignVoucherRef!, {
              ...fields,
              'createdAt': FieldValue.serverTimestamp(),
            });
            transaction.update(newCampaignGroupRef!, {
              'totalParticipants': FieldValue.increment(1),
            });
          }
          campaignStatus = sameCampaignVoucher ? 'adjusted' : 'reapplied';
        }
      }
    }

    transaction.set(
      reverseLedgerRef,
      {
        ...oldData,
        'schemaVersion': 2,
        'operationId': '${editOperationId}_reverse',
        'sourceType': 'edit_reverse',
        'sourceId': newPreparation.sourceId,
        'eventType': 'reverse',
        'pointsDelta': -oldPoints,
        'eligibleAmount': -oldEligible,
        'reversalOf': originalPointOperationId,
        'reason': 'order_edit_compensation',
        'status': 'completed',
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    final newLedger = newPreparation.toLedgerMap(
      eventType: 'earn',
      pointsDelta: newPoints,
      reversalOf: originalPointOperationId,
      reason: 'order_edit_reapply',
    )..addAll({
        'memberProgramStatus': 'completed',
        'campaignStatus': campaignStatus,
        'oldPointsDelta': oldPoints,
        'oldEligibleAmount': oldEligible,
      });
    transaction.set(newLedgerRef, newLedger);
    transaction.set(
      editRef,
      {
        'schemaVersion': 2,
        'operationId': editOperationId,
        'status': 'completed',
        'sourceType': 'edit',
        'sourceId': newPreparation.sourceId,
        'originalPointOperationId': originalPointOperationId,
        'pointsDelta': newPoints - oldPoints,
        'campaignStatus': campaignStatus,
        'auditFlags': flags,
        'completedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return MemberProgramOperationResult.applied(flags: flags);
  }

  /// Records an explicit administrator correction without editing a materialized
  /// counter directly.  The member balance and immutable ledger marker are
  /// committed together, so a retry can only produce one adjustment.
  static Future<MemberProgramOperationResult> applyAdministratorAdjustment({
    required String operationId,
    required String memberId,
    required int pointsDelta,
    required String reason,
    required String sourceId,
    required String actorId,
    String? periodId,
  }) async {
    if (operationId.trim().isEmpty ||
        memberId.trim().isEmpty ||
        actorId.trim().isEmpty ||
        sourceId.trim().isEmpty ||
        reason.trim().isEmpty ||
        pointsDelta == 0) {
      throw const MemberProgramException(
          'Data penyesuaian poin administrator tidak lengkap.');
    }
    final normalizedPeriod = periodId ?? periodIdFor(DateTime.now());
    final memberRef = _memberRef(memberId.trim());
    final ledgerRef = _pointLedgerRef(operationId);
    final operationRef = _programOperationRef(operationId);
    return _fs.runTransaction((transaction) async {
      final operationSnapshot = await transaction.get(operationRef);
      final ledgerSnapshot = await transaction.get(ledgerRef);
      final memberSnapshot = await transaction.get(memberRef);
      if (operationSnapshot.data()?['status']?.toString().toLowerCase() ==
              'completed' ||
          ledgerSnapshot.data()?['status']?.toString().toLowerCase() ==
              'completed') {
        return const MemberProgramOperationResult.alreadyApplied();
      }
      if (!memberSnapshot.exists) {
        throw const MemberProgramException(
            'Member untuk penyesuaian tidak ditemukan.');
      }
      transaction.update(memberRef, {
        'points': FieldValue.increment(pointsDelta),
        'pointsUpdatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(
        ledgerRef,
        {
          'schemaVersion': 2,
          'operationId': operationId,
          'sourceType': 'administrator_adjustment',
          'sourceId': sourceId,
          'memberId': memberId.trim(),
          'periodId': normalizedPeriod,
          'eventType': 'manual_adjustment',
          'status': 'completed',
          'pointsDelta': pointsDelta,
          'eligibleAmount': 0,
          'grossTotal': 0,
          'finalBill': 0,
          'b2bNominal': 0,
          'reason': reason.trim(),
          'actorId': actorId.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      transaction.set(
        operationRef,
        {
          'schemaVersion': 2,
          'operationId': operationId,
          'status': 'completed',
          'eventType': 'manual_adjustment',
          'memberId': memberId.trim(),
          'sourceId': sourceId,
          'pointsDelta': pointsDelta,
          'reason': reason.trim(),
          'actorId': actorId.trim(),
          'completedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return const MemberProgramOperationResult.applied();
    });
  }

  static Future<LocalVoucherClaimPreparation>
      prepareLocalVoucherClaimInTransaction({
    required Transaction transaction,
    required String voucherId,
    required int usedAmount,
    String? operationId,
  }) async {
    if (voucherId.trim().isEmpty || usedAmount <= 0) {
      throw const MemberProgramException(
          'Voucher atau nilai pemakaian tidak valid.');
    }
    final voucherRef = _fs.collection(Col.name('vouchers')).doc(voucherId);
    final voucherSnapshot = await transaction.get(voucherRef);
    if (!voucherSnapshot.exists) {
      throw const MemberProgramException('Voucher tidak ditemukan.');
    }
    final data = voucherSnapshot.data() ?? <String, dynamic>{};
    final now = DateTime.now();
    final activeDate = _date(data['activeDate']);
    final expireDate = _date(data['expireDate']);
    if (activeDate == null ||
        expireDate == null ||
        expireDate.isBefore(activeDate) ||
        now.isBefore(activeDate) ||
        now.isAfter(expireDate)) {
      throw const MemberProgramException('Voucher sudah tidak berlaku.');
    }
    final status = data['status']?.toString().toUpperCase() ?? '';
    final isActive = data['isActive'] == true;
    if (!isActive ||
        status == 'CLAIMED' ||
        status == 'DISABLED' ||
        status == 'EXPIRED') {
      throw const MemberProgramException(
          'Voucher tidak aktif atau sudah digunakan.');
    }
    if (data['sekaliPakai'] is! bool) {
      throw const MemberProgramException(
          'Data tipe penggunaan voucher tidak valid.');
    }
    final singleUse = data['sekaliPakai'] as bool;
    final faceValue = parseInt(data['value']);
    if (faceValue <= 0 || usedAmount > faceValue) {
      throw const MemberProgramException('Nilai voucher tidak valid.');
    }
    final remaining = parseInt(data['valueRemaining'], faceValue);
    if (!singleUse && (remaining <= 0 || usedAmount > remaining)) {
      throw const MemberProgramException('Saldo voucher tidak mencukupi.');
    }
    final groupId = data['voucherGroupId']?.toString();
    DocumentReference<Map<String, dynamic>>? groupRef;
    DocumentSnapshot<Map<String, dynamic>>? groupSnapshot;
    if (groupId != null && groupId.isNotEmpty) {
      groupRef = _fs.collection(Col.name('voucherGroup')).doc(groupId);
      groupSnapshot = await transaction.get(groupRef);
      final groupData = groupSnapshot.data();
      if (groupData == null ||
          !_isCampaignActive(groupData, now) ||
          groupData['status']?.toString().toLowerCase() ==
              _archivedCampaignStatus) {
        throw const MemberProgramException(
            'Kampanye voucher ini sedang tidak aktif.');
      }
    }
    final nextRemaining = singleUse ? 0 : remaining - usedAmount;
    final claimTransition = singleUse || nextRemaining == 0;
    final voucherType = data['type']?.toString();
    if ((voucherType == _campaignType || voucherType == 'competitionPrize') &&
        (groupId == null || groupId.isEmpty) &&
        voucherType == _campaignType) {
      throw const MemberProgramException('Referensi kampanye voucher hilang.');
    }
    if (voucherType == _campaignType &&
        data['status']?.toString().toUpperCase() != 'READY_TO_CLAIM') {
      throw const MemberProgramException(
          'Voucher campaign belum siap digunakan.');
    }
    if (voucherType == 'competitionPrize' &&
        data['status']?.toString().toUpperCase() != 'READY_TO_CLAIM') {
      throw const MemberProgramException(
          'Voucher hadiah kompetisi belum siap digunakan.');
    }
    final voucherUpdates = <String, dynamic>{
      'valueUsed': FieldValue.increment(usedAmount),
      if (!singleUse) 'valueRemaining': nextRemaining,
      'lastClaimedAt': FieldValue.serverTimestamp(),
      'lastClaimOperationId': operationId ?? voucherId,
      if (claimTransition) 'status': 'CLAIMED',
      if (claimTransition) 'isClaimed': true,
    };
    final groupUpdates = <String, dynamic>{
      'totalRedemptions': FieldValue.increment(1),
      if (claimTransition) 'totalClaimed': FieldValue.increment(1),
    };
    // Read the group above even for legacy records, so a missing group never
    // silently passes validation.
    if (groupRef != null && groupSnapshot?.exists != true) {
      throw const MemberProgramException('Referensi kampanye voucher hilang.');
    }
    return LocalVoucherClaimPreparation(
      voucherRef: voucherRef,
      groupRef: groupRef,
      voucherUpdates: voucherUpdates,
      groupUpdates: groupUpdates,
    );
  }

  static void commitLocalVoucherClaimInTransaction({
    required Transaction transaction,
    required LocalVoucherClaimPreparation preparation,
  }) {
    transaction.update(preparation.voucherRef, preparation.voucherUpdates);
    if (preparation.groupRef != null) {
      transaction.update(preparation.groupRef!, preparation.groupUpdates);
    }
  }

  static DocumentReference<Map<String, dynamic>> _competitionPrizeRef(
          String periodId) =>
      _fs.collection(Col.name('competitionPrizes')).doc(periodId);

  static Future<List<CompetitionMemberRecord>> loadCompetitionMembers(
      String periodId) async {
    final snapshot =
        await _competitionPeriodRef(periodId).collection('members').get();
    return snapshot.docs
        .map((doc) => CompetitionMemberRecord.fromMap(doc.id, doc.data()))
        .toList();
  }

  /// Finalizes a completed Jakarta calendar month.  The first transaction
  /// changes the period to `finalizing`, which prevents late checkout/edit
  /// mutations.  The second transaction writes the immutable winner and prize
  /// voucher set under deterministic IDs, so a retry cannot issue duplicates.
  static Future<List<CompetitionWinner>> finalizeCompetitionMonth({
    required String periodId,
    PrizeConfiguration configuration = PrizeConfiguration.defaults,
    String? actorId,
  }) async {
    if (!isPeriodEnded(periodId)) {
      throw const MemberProgramException(
          'Bulan kompetisi belum berakhir di zona waktu Jakarta.');
    }
    final periodRef = _competitionPeriodRef(periodId);
    final prizeRef = _competitionPrizeRef(periodId);
    final finalizationOperationId = 'finalize_$periodId';
    final lockResult = await _fs.runTransaction<String>((transaction) async {
      final snapshot = await transaction.get(periodRef);
      final data = snapshot.data() ?? <String, dynamic>{};
      final status = data['status']?.toString().toLowerCase() ?? 'open';
      if (status == 'finalized') return 'already_finalized';
      final existingOperation = data['finalizationOperationId']?.toString();
      if (status == 'finalizing' &&
          existingOperation != null &&
          existingOperation != finalizationOperationId) {
        throw const MemberProgramException(
            'Finalisasi bulan ini sedang diproses administrator lain.');
      }
      transaction.set(
        periodRef,
        {
          'schemaVersion': 2,
          'periodId': periodId,
          'status': 'finalizing',
          'finalizationOperationId': finalizationOperationId,
          'finalizationActorId': actorId,
          'finalizationStartedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return 'locked';
    });

    if (lockResult == 'already_finalized') {
      return _readStoredWinners(periodId);
    }

    final records = await loadCompetitionMembers(periodId);
    final winners = <CompetitionWinner>[];
    for (final category in configuration.amountsByCategory.keys) {
      final ranked = rankCompetitionMembers(records, category: category);
      for (var index = 0; index < ranked.length && index < 3; index++) {
        final rank = index + 1;
        final record = ranked[index];
        final amount = configuration.amountFor(category, rank);
        if (amount <= 0) continue;
        winners.add(
          CompetitionWinner(
            periodId: periodId,
            category: category,
            rank: rank,
            memberId: record.memberId,
            points: record.customerPoints,
            amountSpent: record.amountSpent,
            numberOfTransaction: record.numberOfTransaction,
            prizeAmount: amount,
            voucherId: prizeVoucherId(
              periodId,
              category,
              rank,
              record.memberId,
            ),
          ),
        );
      }
    }

    final expiry = prizeExpiryFor(periodId);
    if (!DateTime.now().toUtc().isBefore(expiry.toUtc())) {
      throw const MemberProgramException(
          'Masa penerbitan hadiah untuk periode ini sudah berakhir.');
    }
    await _fs.runTransaction((transaction) async {
      final periodSnapshot = await transaction.get(periodRef);
      final prizeSnapshot = await transaction.get(prizeRef);
      final status = periodSnapshot.data()?['status']?.toString().toLowerCase();
      if (status == 'finalized' || prizeSnapshot.exists) return;
      if (status != 'finalizing' ||
          periodSnapshot.data()?['finalizationOperationId'] !=
              finalizationOperationId) {
        throw const MemberProgramException(
            'Kunci finalisasi bulan tidak valid atau sudah berubah.');
      }

      final voucherRefs = <DocumentReference<Map<String, dynamic>>>[
        for (final winner in winners)
          _fs.collection(Col.name('vouchers')).doc(winner.voucherId),
      ];
      final voucherSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final voucherRef in voucherRefs) {
        voucherSnapshots.add(await transaction.get(voucherRef));
      }

      for (var winnerIndex = 0; winnerIndex < winners.length; winnerIndex++) {
        final winner = winners[winnerIndex];
        final winnerRef = prizeRef
            .collection('winners')
            .doc('${winner.category}_${winner.rank}');
        final voucherRef = voucherRefs[winnerIndex];
        final existingVoucher = voucherSnapshots[winnerIndex];
        if (existingVoucher.exists) {
          final existingData = existingVoucher.data() ?? <String, dynamic>{};
          if (existingData['competitionPrizePeriod'] != periodId ||
              existingData['userId'] != winner.memberId ||
              parseInt(existingData['value']) != winner.prizeAmount) {
            throw const MemberProgramException(
                'Voucher hadiah dengan ID yang sama memiliki data berbeda.');
          }
          final existingStatus =
              existingData['status']?.toString().toUpperCase() ?? '';
          if (existingData['isClaimed'] == true ||
              existingStatus == 'CLAIMED' ||
              existingStatus == 'DISABLED' ||
              existingStatus == 'EXPIRED') {
            throw const MemberProgramException(
                'Voucher hadiah dengan ID yang sama sudah digunakan atau dinonaktifkan.');
          }
          if (existingStatus != 'READY_TO_CLAIM') {
            throw const MemberProgramException(
                'Voucher hadiah dengan ID yang sama memiliki status ambigu.');
          }
        }
        transaction.set(
            winnerRef,
            {
              ...winner.toMap(),
              'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        if (!existingVoucher.exists) {
          transaction.set(
            voucherRef,
            {
              'schemaVersion': 2,
              'voucherId': winner.voucherId,
              'type': 'competitionPrize',
              'competitionPrizePeriod': periodId,
              'competitionCategory': winner.category,
              'competitionRank': winner.rank,
              'userId': winner.memberId,
              'value': winner.prizeAmount,
              'valueRemaining': winner.prizeAmount,
              'valueUsed': 0,
              'sekaliPakai': true,
              'isActive': true,
              'isClaimed': false,
              'status': 'READY_TO_CLAIM',
              'activeDate': Timestamp.fromDate(DateTime.now()),
              'expireDate': Timestamp.fromDate(expiry),
              'voucherName':
                  'Hadiah Kompetisi ${categoryLabel(winner.category)} #${winner.rank}',
              'issuedByOperationId': finalizationOperationId,
              'updatedAt': FieldValue.serverTimestamp(),
              'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
      transaction.set(
        prizeRef,
        {
          'schemaVersion': 2,
          'periodId': periodId,
          'status': 'finalized',
          'finalizationOperationId': finalizationOperationId,
          'actorId': actorId,
          'finalizedAt': FieldValue.serverTimestamp(),
          'prizeExpiry': Timestamp.fromDate(expiry),
          'configuration': configuration.toMap(),
          'winners': winners.map((winner) => winner.toMap()).toList(),
        },
        SetOptions(merge: true),
      );
      transaction.update(periodRef, {
        'status': 'finalized',
        'finalizedAt': FieldValue.serverTimestamp(),
        'finalizationOperationId': finalizationOperationId,
      });
    });
    return winners;
  }

  static Future<List<CompetitionWinner>> _readStoredWinners(
      String periodId) async {
    final snapshot = await _competitionPrizeRef(periodId).get();
    final raw = snapshot.data()?['winners'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) {
      final data = Map<String, dynamic>.from(item);
      return CompetitionWinner(
        periodId: data['periodId']?.toString() ?? periodId,
        category: data['category']?.toString() ?? '',
        rank: parseInt(data['rank']),
        memberId: data['memberId']?.toString() ?? '',
        points: parseInt(data['points']),
        amountSpent: parseInt(data['amountSpent']),
        numberOfTransaction: parseInt(data['numberOfTransaction']),
        prizeAmount: parseInt(data['prizeAmount']),
        voucherId: data['voucherId']?.toString() ?? '',
      );
    }).toList();
  }

  static FirebaseFirestore _externalFirestore() =>
      FirebaseFirestore.instanceFor(app: Firebase.app('e-santren'));

  static DateTime _requiredVoucherDate(
      Map<String, dynamic> data, String field) {
    final value = _date(data[field]);
    if (value == null) {
      throw MemberProgramException('Data tanggal voucher $field tidak valid.');
    }
    return value;
  }

  static Map<String, int> _reservationAmounts(dynamic raw) {
    if (raw is! Map) return <String, int>{};
    final result = <String, int>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString() ?? '';
      if (key.isEmpty) continue;
      final amount = parseInt(entry.value);
      if (amount > 0) result[key] = amount;
    }
    return result;
  }

  static Map<String, DateTime> _reservationExpiries(dynamic raw) {
    if (raw is! Map) return <String, DateTime>{};
    final result = <String, DateTime>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString() ?? '';
      final expiry = _date(entry.value);
      if (key.isNotEmpty && expiry != null) result[key] = expiry;
    }
    return result;
  }

  static Map<String, Timestamp> _timestampMap(Map<String, DateTime> values) {
    return values.map(
      (key, value) => MapEntry(key, Timestamp.fromDate(value)),
    );
  }

  static Future<void> reserveExternalVoucher({
    required String operationId,
    required String voucherCode,
    required int amount,
    Duration reservationDuration = const Duration(minutes: 15),
  }) async {
    if (operationId.trim().isEmpty ||
        voucherCode.trim().isEmpty ||
        amount <= 0) {
      throw const MemberProgramException('Data reservasi voucher tidak valid.');
    }
    final fs = _externalFirestore();
    final operationRef = fs.collection('operationClaims').doc(operationId);
    final voucherRef = fs.collection(Col.name('vouchers')).doc(voucherCode);
    final expiresAt = DateTime.now().add(reservationDuration);
    await fs.runTransaction((transaction) async {
      final operationSnapshot = await transaction.get(operationRef);
      final existingOperation = operationSnapshot.data();
      final existingStatus =
          existingOperation?['status']?.toString().toLowerCase();
      if (existingStatus == 'completed') return;
      if (existingStatus == 'reserved') {
        final existingAmount = parseInt(existingOperation?['amount']);
        final existingExpiry =
            _date(existingOperation?['reservationExpiresAt']);
        if (existingOperation?['voucherCode'] == voucherCode &&
            existingAmount == amount &&
            existingExpiry != null &&
            existingExpiry.isAfter(DateTime.now())) {
          return;
        }
        throw const MemberProgramException(
            'Voucher eksternal sudah sedang dicadangkan oleh transaksi lain.');
      }
      final voucherSnapshot = await transaction.get(voucherRef);
      if (!voucherSnapshot.exists) {
        throw const MemberProgramException(
            'Voucher e-santren tidak ditemukan.');
      }
      final data = voucherSnapshot.data() ?? <String, dynamic>{};
      final activeDate = _requiredVoucherDate(data, 'activeDate');
      final expireDate = _requiredVoucherDate(data, 'expireDate');
      final now = DateTime.now();
      if (expireDate.isBefore(activeDate) ||
          now.isBefore(activeDate) ||
          now.isAfter(expireDate)) {
        throw const MemberProgramException(
            'Voucher e-santren sudah tidak berlaku.');
      }
      if (data['isActive'] != true ||
          data['isClaimed'] == true ||
          data['status']?.toString().toUpperCase() == 'DISABLED' ||
          data['status']?.toString().toUpperCase() == 'EXPIRED' ||
          data['status']?.toString().toUpperCase() == 'CLAIMED') {
        throw const MemberProgramException(
            'Voucher e-santren tidak aktif atau sudah digunakan.');
      }
      if (data['sekaliPakai'] is! bool) {
        throw const MemberProgramException(
            'Data tipe penggunaan voucher e-santren tidak valid.');
      }
      final singleUse = data['sekaliPakai'] as bool;
      final faceValue = parseInt(data['value']);
      final remaining = parseInt(data['valueRemaining'], faceValue);
      if (faceValue <= 0 || remaining <= 0 || amount > remaining) {
        throw const MemberProgramException(
            'Nilai voucher e-santren tidak valid.');
      }
      if (!singleUse) {
        final reservations = _reservationAmounts(data['reservationAmounts']);
        final reservationExpiries =
            _reservationExpiries(data['reservationExpiries']);
        final globalReservationExpiry = _date(data['reservationExpiresAt']);
        if (reservationExpiries.isEmpty &&
            globalReservationExpiry != null &&
            !globalReservationExpiry.isAfter(now)) {
          reservations.clear();
        } else {
          for (final key in reservationExpiries.keys.toList()) {
            if (!reservationExpiries[key]!.isAfter(now)) {
              reservationExpiries.remove(key);
              reservations.remove(key);
            }
          }
        }
        final legacyOwner = data['reservationOperationId']?.toString();
        final legacyReserved = globalReservationExpiry != null &&
                !globalReservationExpiry.isAfter(now)
            ? 0
            : parseInt(data['reservedAmount']);
        final otherReserved = reservations.entries
                .where((entry) => entry.key != operationId)
                .fold<int>(
                    0, (runningTotal, entry) => runningTotal + entry.value) +
            (reservations.isEmpty && legacyOwner != operationId
                ? legacyReserved
                : 0);
        if (otherReserved + amount > remaining) {
          throw const MemberProgramException(
              'Saldo voucher e-santren sedang tidak mencukupi.');
        }
        reservations[operationId] = amount;
        reservationExpiries[operationId] = expiresAt;
        transaction.update(voucherRef, {
          'reservedAmount': otherReserved + amount,
          'reservationAmounts': reservations,
          'reservationExpiries': _timestampMap(reservationExpiries),
          'reservationOperationId': operationId,
          'reservationExpiresAt': Timestamp.fromDate(expiresAt),
        });
      } else {
        final reservedBy = data['reservedOperationId']?.toString();
        if (reservedBy != null &&
            reservedBy.isNotEmpty &&
            reservedBy != operationId) {
          final existingExpiry = _date(data['reservationExpiresAt']);
          if (existingExpiry == null || existingExpiry.isAfter(now)) {
            throw const MemberProgramException(
                'Voucher e-santren sedang dicadangkan transaksi lain.');
          }
        }
        transaction.update(voucherRef, {
          'reservedOperationId': operationId,
          'reservationExpiresAt': Timestamp.fromDate(expiresAt),
        });
      }
      transaction.set(
        operationRef,
        {
          'schemaVersion': 1,
          'operationId': operationId,
          'voucherCode': voucherCode,
          'amount': amount,
          'status': 'reserved',
          'reservedAt': FieldValue.serverTimestamp(),
          'reservationExpiresAt': Timestamp.fromDate(expiresAt),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> finalizeExternalVoucher({
    required String operationId,
    required String voucherCode,
    required int amount,
  }) async {
    final fs = _externalFirestore();
    final operationRef = fs.collection('operationClaims').doc(operationId);
    final voucherRef = fs.collection(Col.name('vouchers')).doc(voucherCode);
    await fs.runTransaction((transaction) async {
      final operationSnapshot = await transaction.get(operationRef);
      final operation = operationSnapshot.data();
      if (operation?['status']?.toString().toLowerCase() == 'completed') return;
      if (operation?['status']?.toString().toLowerCase() != 'reserved' ||
          parseInt(operation?['amount']) != amount ||
          operation?['voucherCode'] != voucherCode) {
        throw const MemberProgramException(
            'Reservasi voucher e-santren tidak ditemukan atau sudah kedaluwarsa.');
      }
      final voucherSnapshot = await transaction.get(voucherRef);
      if (!voucherSnapshot.exists) {
        throw const MemberProgramException(
            'Voucher e-santren tidak ditemukan.');
      }
      final data = voucherSnapshot.data() ?? <String, dynamic>{};
      final operationExpiry = _date(operation?['reservationExpiresAt']);
      if (operationExpiry == null || !operationExpiry.isAfter(DateTime.now())) {
        throw const MemberProgramException(
            'Reservasi voucher e-santren sudah kedaluwarsa.');
      }
      final expiry = _requiredVoucherDate(data, 'expireDate');
      if (DateTime.now().isAfter(expiry)) {
        throw const MemberProgramException(
            'Voucher e-santren sudah kedaluwarsa.');
      }
      if (data['sekaliPakai'] is! bool) {
        throw const MemberProgramException(
            'Data tipe penggunaan voucher e-santren tidak valid.');
      }
      final singleUse = data['sekaliPakai'] as bool;
      final faceValue = parseInt(data['value']);
      final remaining = parseInt(data['valueRemaining'], faceValue);
      if (data['isActive'] != true ||
          data['isClaimed'] == true ||
          data['status']?.toString().toUpperCase() == 'DISABLED' ||
          data['status']?.toString().toUpperCase() == 'EXPIRED' ||
          data['status']?.toString().toUpperCase() == 'CLAIMED' ||
          faceValue <= 0 ||
          remaining <= 0 ||
          amount > remaining) {
        throw const MemberProgramException(
            'Saldo voucher e-santren sudah berubah.');
      }
      final reservationExpiry = _date(data['reservationExpiresAt']);
      if (reservationExpiry == null ||
          !reservationExpiry.isAfter(DateTime.now())) {
        throw const MemberProgramException(
            'Reservasi voucher e-santren sudah kedaluwarsa.');
      }
      final reservations = _reservationAmounts(data['reservationAmounts']);
      if (singleUse) {
        if (data['reservedOperationId']?.toString() != operationId) {
          throw const MemberProgramException(
              'Reservasi voucher e-santren dimiliki transaksi lain.');
        }
      } else if (reservations.isNotEmpty) {
        if (reservations[operationId] != amount) {
          throw const MemberProgramException(
              'Reservasi saldo voucher e-santren tidak cocok.');
        }
      } else if (data['reservationOperationId']?.toString() != operationId) {
        throw const MemberProgramException(
            'Reservasi saldo voucher e-santren tidak ditemukan.');
      }
      final groupId = data['voucherGroupId']?.toString();
      DocumentReference<Map<String, dynamic>>? groupRef;
      DocumentSnapshot<Map<String, dynamic>>? groupSnapshot;
      if (groupId != null && groupId.isNotEmpty) {
        groupRef = fs.collection(Col.name('voucherGroup')).doc(groupId);
        groupSnapshot = await transaction.get(groupRef);
        if (groupSnapshot.exists != true) {
          throw const MemberProgramException(
              'Referensi campaign voucher e-santren tidak ditemukan.');
        }
      }
      final updates = <String, dynamic>{
        'lastClaimOperationId': operationId,
        'lastClaimedAt': FieldValue.serverTimestamp(),
        if (singleUse) 'isClaimed': true,
        if (singleUse) 'status': 'CLAIMED',
        if (!singleUse) 'valueRemaining': remaining - amount,
        if (!singleUse)
          'reservedAmount': (parseInt(data['reservedAmount']) - amount)
              .clamp(0, parseInt(data['reservedAmount'])),
        if (!singleUse && remaining - amount <= 0) 'isClaimed': true,
        if (!singleUse && remaining - amount <= 0) 'status': 'CLAIMED',
      };
      if (singleUse) {
        updates['reservedOperationId'] = FieldValue.delete();
        updates['reservationExpiresAt'] = FieldValue.delete();
      } else {
        reservations.remove(operationId);
        final reservationExpiries =
            _reservationExpiries(data['reservationExpiries']);
        reservationExpiries.remove(operationId);
        updates['reservedAmount'] = reservations.values
            .fold<int>(0, (runningTotal, value) => runningTotal + value);
        updates['reservationAmounts'] =
            reservations.isEmpty ? FieldValue.delete() : reservations;
        updates['reservationExpiries'] = reservationExpiries.isEmpty
            ? FieldValue.delete()
            : _timestampMap(reservationExpiries);
        if (reservations.isEmpty) {
          updates['reservationOperationId'] = FieldValue.delete();
          updates['reservationExpiresAt'] = FieldValue.delete();
        } else if (reservationExpiries.isNotEmpty) {
          final latestExpiry = reservationExpiries.values.reduce(
            (latest, value) => value.isAfter(latest) ? value : latest,
          );
          updates['reservationExpiresAt'] = Timestamp.fromDate(latestExpiry);
        }
      }
      transaction.update(voucherRef, updates);
      if (groupRef != null && groupSnapshot?.exists == true) {
        final transition = singleUse || remaining - amount <= 0;
        transaction.update(groupRef, {
          'totalRedemptions': FieldValue.increment(1),
          if (transition) 'totalClaimed': FieldValue.increment(1),
        });
      }
      transaction.set(
        operationRef,
        {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> releaseExternalVoucher({
    required String operationId,
    required String voucherCode,
  }) async {
    final fs = _externalFirestore();
    final operationRef = fs.collection('operationClaims').doc(operationId);
    final voucherRef = fs.collection(Col.name('vouchers')).doc(voucherCode);
    await fs.runTransaction((transaction) async {
      final operationSnapshot = await transaction.get(operationRef);
      final operation = operationSnapshot.data();
      if (operation?['status']?.toString().toLowerCase() != 'reserved') return;
      final voucherSnapshot = await transaction.get(voucherRef);
      if (voucherSnapshot.exists) {
        final data = voucherSnapshot.data() ?? <String, dynamic>{};
        if (data['sekaliPakai'] is! bool) {
          throw const MemberProgramException(
              'Data tipe penggunaan voucher e-santren tidak valid.');
        }
        final singleUse = data['sekaliPakai'] as bool;
        if (singleUse) {
          if (data['reservedOperationId'] == operationId) {
            transaction.update(voucherRef, {
              'reservedOperationId': FieldValue.delete(),
              'reservationExpiresAt': FieldValue.delete(),
            });
          }
        } else {
          final reservations = _reservationAmounts(data['reservationAmounts']);
          final reservationExpiries =
              _reservationExpiries(data['reservationExpiries']);
          if (reservations.isNotEmpty &&
              !reservations.containsKey(operationId)) {
            transaction.set(
              operationRef,
              {
                'status': 'released',
                'releasedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            return;
          }
          if (reservations.isEmpty &&
              data['reservationOperationId']?.toString() != operationId) {
            transaction.set(
              operationRef,
              {
                'status': 'released',
                'releasedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            return;
          }
          reservations.remove(operationId);
          reservationExpiries.remove(operationId);
          final nextReserved = reservations.values
              .fold<int>(0, (runningTotal, value) => runningTotal + value);
          final updates = <String, dynamic>{
            'reservedAmount': nextReserved,
            'reservationAmounts':
                reservations.isEmpty ? FieldValue.delete() : reservations,
            'reservationExpiries': reservationExpiries.isEmpty
                ? FieldValue.delete()
                : _timestampMap(reservationExpiries),
          };
          if (reservations.isEmpty) {
            updates['reservationOperationId'] = FieldValue.delete();
            updates['reservationExpiresAt'] = FieldValue.delete();
          } else if (reservationExpiries.isNotEmpty) {
            final latestExpiry = reservationExpiries.values.reduce(
              (latest, value) => value.isAfter(latest) ? value : latest,
            );
            updates['reservationExpiresAt'] = Timestamp.fromDate(latestExpiry);
          }
          transaction.update(voucherRef, updates);
        }
      }
      transaction.set(
        operationRef,
        {
          'status': 'released',
          'releasedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> markExternalClaimStatus(
    String operationId, {
    required String status,
    String? error,
  }) async {
    if (!{'pending', 'failed', 'completed'}.contains(status)) {
      throw const MemberProgramException('Status klaim eksternal tidak valid.');
    }
    final ref =
        _fs.collection(Col.name('externalVoucherClaims')).doc(operationId);
    await _fs.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = snapshot.data() ?? <String, dynamic>{};
      if (current['status']?.toString().toLowerCase() == 'completed' &&
          status != 'completed') {
        return;
      }
      transaction.set(
        ref,
        {
          'status': status,
          'lastError': error,
          'updatedAt': FieldValue.serverTimestamp(),
          if (status == 'completed')
            'completedAt': FieldValue.serverTimestamp(),
          if (status != 'completed') 'attempts': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> retryExternalClaim(String operationId) async {
    final ref =
        _fs.collection(Col.name('externalVoucherClaims')).doc(operationId);
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      throw const MemberProgramException(
          'Outbox voucher eksternal tidak ditemukan.');
    }
    final data = snapshot.data() ?? <String, dynamic>{};
    final code = data['voucherCode']?.toString() ?? '';
    final amount = parseInt(data['amount']);
    await reserveExternalVoucher(
      operationId: operationId,
      voucherCode: code,
      amount: amount,
    );
    try {
      await finalizeExternalVoucher(
        operationId: operationId,
        voucherCode: code,
        amount: amount,
      );
      await markExternalClaimStatus(operationId, status: 'completed');
    } catch (error) {
      await markExternalClaimStatus(
        operationId,
        status: 'failed',
        error: error.toString(),
      );
      rethrow;
    }
  }

  static void queueExternalClaimInTransaction({
    required Transaction transaction,
    required String operationId,
    required String voucherCode,
    required int amount,
    required String sourceType,
    required String sourceId,
    DocumentSnapshot<Map<String, dynamic>>? existingSnapshot,
  }) {
    final ref =
        _fs.collection(Col.name('externalVoucherClaims')).doc(operationId);
    final existing = existingSnapshot?.data();
    if (existing?['status']?.toString().toLowerCase() == 'completed') return;
    if (existing != null &&
        (existing['voucherCode']?.toString() != voucherCode ||
            parseInt(existing['amount']) != amount)) {
      throw const MemberProgramException(
          'Marker voucher eksternal sudah digunakan untuk transaksi berbeda.');
    }
    transaction.set(
      ref,
      {
        'schemaVersion': 1,
        'operationId': operationId,
        'voucherCode': voucherCode,
        'amount': amount,
        'sourceType': sourceType,
        'sourceId': sourceId,
        'status': 'pending',
        'attempts': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<String> createCampaign({
    required String name,
    required int threshold,
    required int value,
    required int transactionRequirement,
    required DateTime activeDate,
    required DateTime expireDate,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const MemberProgramException('Nama campaign wajib diisi.');
    }
    if (threshold <= 0) {
      throw const MemberProgramException(
          'Target poin harus lebih besar dari nol.');
    }
    if (value <= 0) {
      throw const MemberProgramException(
          'Nilai voucher harus lebih besar dari nol.');
    }
    if (transactionRequirement < 0) {
      throw const MemberProgramException('Syarat transaksi tidak valid.');
    }
    if (expireDate.isBefore(activeDate)) {
      throw const MemberProgramException(
          'Tanggal berakhir harus setelah tanggal mulai.');
    }
    final ref = _fs.collection(Col.name('voucherGroup')).doc();
    await ref.set({
      'schemaVersion': 2,
      'activeDate': Timestamp.fromDate(activeDate),
      'createdAt': FieldValue.serverTimestamp(),
      'expireDate': Timestamp.fromDate(expireDate),
      'isActive': true,
      'status': _activeCampaignStatus,
      'revision': 0,
      'threshold': threshold,
      'totalClaimed': 0,
      'totalParticipants': 0,
      'totalRedemptions': 0,
      'type': _campaignType,
      'value': value,
      'transactionRequirement': transactionRequirement,
      'voucherGroupId': ref.id,
      'voucherName': trimmedName,
    });
    return ref.id;
  }

  static Future<void> archiveCampaign(String groupId) async {
    final ref = _fs.collection(Col.name('voucherGroup')).doc(groupId);
    await _fs.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        throw const MemberProgramException('Campaign tidak ditemukan.');
      }
      final data = snapshot.data() ?? const <String, dynamic>{};
      if (data['status']?.toString().toLowerCase() == _archivedCampaignStatus &&
          data['isActive'] == false) {
        return;
      }
      transaction.update(ref, {
        'schemaVersion': 2,
        'status': _archivedCampaignStatus,
        'isActive': false,
        'revision': parseInt(data['revision']) + 1,
        'archivedAt': FieldValue.serverTimestamp(),
      });
    });

    // The group state is authoritative and makes concurrent redemptions fail
    // closed.  Marking existing vouchers is a best-effort materialization;
    // failures remain visible to the audit and do not delete history.
    final vouchers = await _fs
        .collection(Col.name('vouchers'))
        .where('voucherGroupId', isEqualTo: groupId)
        .get();
    for (var i = 0; i < vouchers.docs.length; i += 400) {
      final batch = _fs.batch();
      for (final voucher in vouchers.docs.skip(i).take(400)) {
        final status = voucher.data()['status']?.toString() ?? '';
        if (status != 'CLAIMED' && status != 'EXPIRED') {
          batch.update(voucher.reference, {
            'status': 'DISABLED',
            'isActive': false,
            'disabledReason': 'campaign_archived',
            'disabledAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
    }
  }
}
