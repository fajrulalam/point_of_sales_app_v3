import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared value objects for the member points, competition, and campaign
/// subsystems.  These models deliberately tolerate the numeric legacy values
/// found in older Firestore documents while all new writes use integers.
class MemberProgramValues {
  const MemberProgramValues._();

  static int intValue(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return fallback;
      final direct = int.tryParse(raw);
      if (direct != null) return direct;
      final negative = raw.startsWith('-');
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return fallback;
      final parsed = int.tryParse(digits);
      if (parsed == null) return fallback;
      return negative ? -parsed : parsed;
    }
    return fallback;
  }

  static DateTime? dateValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String categoryValue(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'santri' || normalized.contains('santri')) {
      return 'santri';
    }
    if (normalized == 'mahasiswa' || normalized.contains('mahasiswa')) {
      return 'mahasiswa';
    }
    if (normalized.contains('staff') ||
        normalized.contains('staf') ||
        normalized.contains('guru') ||
        normalized.contains('dosen')) {
      return 'staff_guru_dosen';
    }
    return '';
  }

  static String categoryLabel(String category) {
    switch (category) {
      case 'santri':
        return 'Santri';
      case 'mahasiswa':
        return 'Mahasiswa';
      case 'staff_guru_dosen':
        return 'Staff/Guru/Dosen';
      default:
        return category;
    }
  }
}

class MemberPointsCalculation {
  final int finalBill;
  final int b2bNominal;
  final int eligibleAmount;
  final int pointsDelta;

  const MemberPointsCalculation({
    required this.finalBill,
    required this.b2bNominal,
    required this.eligibleAmount,
    required this.pointsDelta,
  });

  factory MemberPointsCalculation.calculate({
    required int finalBill,
    int b2bNominal = 0,
  }) {
    final normalizedBill = finalBill < 0 ? 0 : finalBill;
    final normalizedB2B = b2bNominal < 0 ? 0 : b2bNominal;
    final eligible = (normalizedBill - normalizedB2B).clamp(0, normalizedBill);
    return MemberPointsCalculation(
      finalBill: normalizedBill,
      b2bNominal: normalizedB2B,
      eligibleAmount: eligible,
      pointsDelta: eligible ~/ 10000,
    );
  }
}

class CampaignCandidate {
  final String groupId;
  final String voucherId;
  final Map<String, dynamic> groupData;
  final Map<String, dynamic>? existingVoucherData;

  const CampaignCandidate({
    required this.groupId,
    required this.voucherId,
    required this.groupData,
    this.existingVoucherData,
  });

  String get status => existingVoucherData?['status']?.toString() ?? '';

  int get userPoints =>
      MemberProgramValues.intValue(existingVoucherData?['userPoints']);
}

class MemberProgramPreparation {
  final String operationId;
  final String sourceType;
  final String sourceId;
  final String memberId;
  final String memberName;
  final String periodId;
  final String category;
  final DateTime eventAt;
  final int grossTotal;
  final int finalBill;
  final int ordinaryVoucherDiscount;
  final MemberPointsCalculation points;
  final bool memberSelected;
  final bool memberExists;
  final CampaignCandidate? campaign;
  final bool campaignLookupFailed;
  final List<String> auditFlags;

  const MemberProgramPreparation({
    required this.operationId,
    required this.sourceType,
    required this.sourceId,
    required this.memberId,
    required this.memberName,
    required this.periodId,
    required this.category,
    required this.eventAt,
    required this.grossTotal,
    required this.finalBill,
    required this.ordinaryVoucherDiscount,
    required this.points,
    required this.memberSelected,
    required this.memberExists,
    required this.campaign,
    required this.campaignLookupFailed,
    required this.auditFlags,
  });

  bool get hasMemberProgramData => memberExists && memberId.trim().isNotEmpty;

  Map<String, dynamic> toLedgerMap({
    required String eventType,
    required int pointsDelta,
    String? reversalOf,
    String? reason,
    String status = 'completed',
  }) {
    return {
      'schemaVersion': 2,
      'operationId': operationId,
      'sourceType': sourceType,
      'sourceId': sourceId,
      'memberId': memberId,
      'periodId': periodId,
      'category': category,
      'eventType': eventType,
      'status': status,
      'grossTotal': grossTotal,
      'finalBill': finalBill,
      'ordinaryVoucherDiscount': ordinaryVoucherDiscount,
      'b2bNominal': points.b2bNominal,
      'eligibleAmount': points.eligibleAmount,
      'pointsDelta': pointsDelta,
      'campaignGroupId': campaign?.groupId,
      'campaignVoucherId': campaign?.voucherId,
      'campaignPointsDelta': pointsDelta,
      'reversalOf': reversalOf,
      'reason': reason,
      'eventAt': Timestamp.fromDate(eventAt),
      'createdAt': FieldValue.serverTimestamp(),
      if (auditFlags.isNotEmpty) 'auditFlags': auditFlags,
    };
  }
}

class MemberProgramOperationResult {
  final bool applied;
  final bool alreadyApplied;
  final bool pending;
  final bool skipped;
  final List<String> auditFlags;

  const MemberProgramOperationResult({
    required this.applied,
    required this.alreadyApplied,
    required this.pending,
    this.skipped = false,
    this.auditFlags = const [],
  });

  const MemberProgramOperationResult.applied({List<String> flags = const []})
      : this(
          applied: true,
          alreadyApplied: false,
          pending: false,
          auditFlags: flags,
        );

  const MemberProgramOperationResult.alreadyApplied()
      : this(applied: false, alreadyApplied: true, pending: false);

  const MemberProgramOperationResult.skipped({List<String> flags = const []})
      : this(
          applied: false,
          alreadyApplied: false,
          pending: false,
          skipped: true,
          auditFlags: flags,
        );

  const MemberProgramOperationResult.pending({List<String> flags = const []})
      : this(
          applied: false,
          alreadyApplied: false,
          pending: true,
          auditFlags: flags,
        );
}

class CompetitionMemberRecord {
  final String memberId;
  final String category;
  final int customerPoints;
  final int amountSpent;
  final int numberOfTransaction;

  const CompetitionMemberRecord({
    required this.memberId,
    required this.category,
    required this.customerPoints,
    required this.amountSpent,
    required this.numberOfTransaction,
  });

  factory CompetitionMemberRecord.fromMap(
      String memberId, Map<String, dynamic> data) {
    return CompetitionMemberRecord(
      memberId: memberId,
      category: MemberProgramValues.categoryValue(data['category']),
      customerPoints: MemberProgramValues.intValue(data['customerPoints']),
      amountSpent: MemberProgramValues.intValue(data['amountSpent']),
      numberOfTransaction:
          MemberProgramValues.intValue(data['numberOfTransaction']),
    );
  }

  Map<String, dynamic> toMap() => {
        'schemaVersion': 2,
        'memberId': memberId,
        'category': category,
        'customerPoints': customerPoints,
        'amountSpent': amountSpent,
        'numberOfTransaction': numberOfTransaction,
      };
}

class CompetitionWinner {
  final String periodId;
  final String category;
  final int rank;
  final String memberId;
  final int points;
  final int amountSpent;
  final int numberOfTransaction;
  final int prizeAmount;
  final String voucherId;

  const CompetitionWinner({
    required this.periodId,
    required this.category,
    required this.rank,
    required this.memberId,
    required this.points,
    required this.amountSpent,
    required this.numberOfTransaction,
    required this.prizeAmount,
    required this.voucherId,
  });

  Map<String, dynamic> toMap() => {
        'schemaVersion': 2,
        'periodId': periodId,
        'category': category,
        'rank': rank,
        'memberId': memberId,
        'points': points,
        'amountSpent': amountSpent,
        'numberOfTransaction': numberOfTransaction,
        'prizeAmount': prizeAmount,
        'voucherId': voucherId,
      };
}

class PrizeConfiguration {
  final Map<String, Map<int, int>> amountsByCategory;
  final int? validityMonths;

  const PrizeConfiguration({
    required this.amountsByCategory,
    this.validityMonths,
  });

  static const defaults = PrizeConfiguration(
    amountsByCategory: {
      'santri': {1: 50000, 2: 25000, 3: 15000},
      'mahasiswa': {1: 50000, 2: 25000, 3: 15000},
      'staff_guru_dosen': {1: 50000, 2: 25000, 3: 15000},
    },
  );

  int amountFor(String category, int rank) =>
      amountsByCategory[category]?[rank] ?? 0;

  Map<String, dynamic> toMap() => {
        'schemaVersion': 1,
        'validityMonths': validityMonths,
        'amountsByCategory': amountsByCategory.map(
          (category, ranks) => MapEntry(
            category,
            ranks.map((rank, amount) => MapEntry(rank.toString(), amount)),
          ),
        ),
      };
}

class ExternalVoucherClaim {
  final String operationId;
  final String voucherCode;
  final int amount;
  final String sourceType;
  final String sourceId;
  final String status;

  const ExternalVoucherClaim({
    required this.operationId,
    required this.voucherCode,
    required this.amount,
    required this.sourceType,
    required this.sourceId,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
        'schemaVersion': 1,
        'operationId': operationId,
        'voucherCode': voucherCode,
        'amount': amount,
        'sourceType': sourceType,
        'sourceId': sourceId,
        'status': status,
      };
}

/// Read preparation for a local POS voucher claim.  It is intentionally
/// separate from the transaction write so checkout can read every voucher and
/// campaign document before it queues any write.
class LocalVoucherClaimPreparation {
  final DocumentReference<Map<String, dynamic>> voucherRef;
  final DocumentReference<Map<String, dynamic>>? groupRef;
  final Map<String, dynamic> voucherUpdates;
  final Map<String, dynamic> groupUpdates;

  const LocalVoucherClaimPreparation({
    required this.voucherRef,
    required this.groupRef,
    required this.voucherUpdates,
    required this.groupUpdates,
  });
}

class MemberProgramAuditFinding {
  final String code;
  final String severity;
  final String message;
  final String? documentPath;
  final Map<String, dynamic> details;

  const MemberProgramAuditFinding({
    required this.code,
    required this.severity,
    required this.message,
    this.documentPath,
    this.details = const {},
  });

  Map<String, dynamic> toMap() => {
        'code': code,
        'severity': severity,
        'message': message,
        'documentPath': documentPath,
        'details': details,
      };
}
