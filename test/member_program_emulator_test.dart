import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:point_of_sales_app_v3/Models/MemberProgramModels.dart';
import 'package:point_of_sales_app_v3/Services/MemberProgramService.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

void main() {
  const definedFirestoreHost =
      String.fromEnvironment('FIRESTORE_EMULATOR_HOST');
  const definedAuthHost = String.fromEnvironment('FIREBASE_AUTH_EMULATOR_HOST');
  const definedRunFlag = String.fromEnvironment('RUN_FIREBASE_EMULATOR_TESTS');
  final firestoreHost =
      definedFirestoreHost.isEmpty ? null : definedFirestoreHost;
  final runEmulatorTests =
      definedRunFlag == '1' || definedRunFlag.toLowerCase() == 'true';

  if (firestoreHost == null ||
      firestoreHost.trim().isEmpty ||
      !runEmulatorTests) {
    test(
      'member program emulator tests require FIRESTORE_EMULATOR_HOST',
      () {},
      skip:
          'Set RUN_FIREBASE_EMULATOR_TESTS=1 with FIRESTORE and Auth emulators running.',
    );
    return;
  }

  late FirebaseFirestore firestore;
  FirebaseAuth? auth;
  late String emulatorUid;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final firestoreParts = definedFirestoreHost.split(':');
    final firestoreAddress = firestoreParts.first;
    final firestorePort = firestoreParts.length > 1
        ? int.tryParse(firestoreParts.last) ?? 8080
        : 8080;
    final authAddress =
        definedAuthHost.isEmpty ? '$firestoreAddress:9099' : definedAuthHost;
    final authParts = authAddress.split(':');
    final authHost = authParts.first;
    final authPort =
        authParts.length > 1 ? int.tryParse(authParts.last) ?? 9099 : 9099;

    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'demo-api-key',
          appId: '1:1234567890:android:member-program-emulator',
          messagingSenderId: '1234567890',
          projectId: 'demo-global-competition',
        ),
      );
    } on FirebaseException catch (error) {
      if (error.code != 'duplicate-app') rethrow;
    }
    firestore = FirebaseFirestore.instance;
    final authClient = FirebaseAuth.instance;
    auth = authClient;
    firestore.useFirestoreEmulator(firestoreAddress, firestorePort);
    await authClient.useAuthEmulator(authHost, authPort);
    try {
      await authClient.createUserWithEmailAndPassword(
        email: 'admin@canteen375.com',
        password: 'emulator-password-123',
      );
    } on FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') rethrow;
      await authClient.signInWithEmailAndPassword(
        email: 'admin@canteen375.com',
        password: 'emulator-password-123',
      );
    }
    final currentUser = authClient.currentUser;
    if (currentUser == null) {
      throw StateError('Emulator authentication did not produce a user');
    }
    emulatorUid = currentUser.uid;
    Col.testingMode.value = true;
  });

  tearDownAll(() async {
    Col.testingMode.value = false;
    await auth?.signOut();
  });

  test('concurrent duplicate point award updates member and campaign once',
      () async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    // The plus sign exercises the legacy root-map path for IDs that are not
    // valid dotted field-path segments.
    final memberId = 'member_${suffix}_+628123';
    final campaignId = 'campaign_$suffix';
    final operationId = 'sale_$suffix';
    final periodId = MemberProgramService.periodIdFor(DateTime.now());
    final now = DateTime.now();

    await firestore.collection(Col.name('Members')).doc(memberId).set({
      'fullName': 'Emulator Member',
      'uid': emulatorUid,
      'role': 'member',
      'category': 'Santri',
      'points': 0,
    });
    await firestore.collection(Col.name('voucherGroup')).doc(campaignId).set({
      'schemaVersion': 2,
      'voucherGroupId': campaignId,
      'type': 'cashbackCampaign',
      'voucherName': 'Emulator Campaign',
      'status': 'active',
      'isActive': true,
      'activeDate': Timestamp.fromDate(now.subtract(const Duration(days: 1))),
      'expireDate': Timestamp.fromDate(now.add(const Duration(days: 1))),
      'threshold': 3,
      'value': 50000,
      'transactionRequirement': 0,
      'totalParticipants': 0,
      'totalClaimed': 0,
      'totalRedemptions': 0,
    });

    Future<void> award() async {
      final preparation = await MemberProgramService.prepareOrder(
        operationId: operationId,
        sourceType: 'emulator_test',
        sourceId: operationId,
        memberId: memberId,
        grossTotal: 30000,
        finalBill: 30000,
      );
      await firestore.runTransaction((transaction) async {
        await MemberProgramService.queueOrderInTransaction(
          transaction: transaction,
          preparation: preparation,
        );
      });
    }

    await Future.wait([award(), award()]);

    final member =
        await firestore.collection(Col.name('Members')).doc(memberId).get();
    final voucher = await firestore
        .collection(Col.name('vouchers'))
        .doc(MemberProgramService.campaignVoucherId(campaignId, memberId))
        .get();
    final group = await firestore
        .collection(Col.name('voucherGroup'))
        .doc(campaignId)
        .get();
    final competition = await firestore
        .collection(Col.name('competitionRecords'))
        .doc(periodId)
        .collection('members')
        .doc(memberId)
        .get();
    final legacyCompetition = await firestore
        .collection(Col.name('competitionRecords'))
        .doc(periodId)
        .get();
    final ledgers = await firestore
        .collection(Col.name('pointTransactions'))
        .where('operationId', isEqualTo: operationId)
        .get();

    expect(MemberProgramValues.intValue(member.data()?['points']), 3);
    expect(MemberProgramValues.intValue(voucher.data()?['userPoints']), 3);
    expect(voucher.data()?['status'], 'READY_TO_CLAIM');
    expect(MemberProgramValues.intValue(group.data()?['totalParticipants']), 1);
    expect(
      MemberProgramValues.intValue(competition.data()?['customerPoints']),
      3,
    );
    expect(competition.data()?['numberOfTransaction'], 1);
    final legacyRecord =
        legacyCompetition.data()?[memberId] as Map<String, dynamic>?;
    expect(MemberProgramValues.intValue(legacyRecord?['customerPoints']), 3);
    expect(MemberProgramValues.intValue(legacyRecord?['amountSpent']), 30000);
    expect(
        MemberProgramValues.intValue(legacyRecord?['numberOfTransaction']), 1);
    expect(ledgers.docs.length, 1);
  });

  test('sale, self-order, settlement and edit share the global pool', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final periodId = MemberProgramService.periodIdFor(DateTime.now());
    for (final source in ['sale', 'self_order', 'open_bill_settlement']) {
      final memberId = '${source}_$suffix';
      final operationId = '${source}_earn_$suffix';
      await firestore.collection(Col.name('Members')).doc(memberId).set({
        'fullName': source,
        'uid': emulatorUid,
        'points': 0,
        'category': '',
      });
      final preparation = await MemberProgramService.prepareOrder(
        operationId: operationId,
        sourceType: source,
        sourceId: operationId,
        memberId: memberId,
        grossTotal: 20000,
        finalBill: 20000,
      );
      await firestore.runTransaction((transaction) =>
          MemberProgramService.queueOrderInTransaction(
              transaction: transaction, preparation: preparation));
      final editId = '${source}_edit_$suffix';
      final edited = await MemberProgramService.prepareOrder(
        operationId: editId,
        sourceType: 'edit',
        sourceId: operationId,
        memberId: memberId,
        grossTotal: 10000,
        finalBill: 10000,
      );
      Future<void> edit() async {
        await firestore.runTransaction((transaction) =>
            MemberProgramService.queueOrderEditInTransaction(
                transaction: transaction,
                editOperationId: editId,
                originalPointOperationId: operationId,
                newPreparation: edited));
      }

      await edit();
      await edit();
      final period = await firestore
          .collection(Col.name('competitionRecords'))
          .doc(periodId)
          .get();
      expect(period.data()?['rankingMode'], 'global');
      expect(period.data()?[memberId]['customerPoints'], 1);
      expect(period.data()?[memberId]['amountSpent'], 10000);
      expect(period.data()?[memberId]['numberOfTransaction'], 1);
      expect(
          (await firestore.collection(Col.name('Members')).doc(memberId).get())
              .data()?['points'],
          1);
      final reverse = await firestore
          .collection(Col.name('pointTransactions'))
          .doc('${editId}_reverse')
          .get();
      expect(reverse.data()?['pointsDelta'], -2);
    }
  });

  test('finalization ranks cumulative root data and is idempotent', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final memberId = 'finalizer_member_$suffix';
    const periodId = '2026-10';
    final finalizationTime = DateTime.utc(2026, 11, 1);

    await firestore.collection(Col.name('Members')).doc(memberId).set({
      'fullName': 'Finalizer Member',
      'uid': emulatorUid,
      'role': 'member',
      'category': 'Santri',
      'points': 0,
    });
    await firestore
        .collection(Col.name('competitionRecords'))
        .doc(periodId)
        .set({
      'periodId': periodId,
      ...CompetitionRankingMode.global.metadata,
      'status': 'open',
      memberId: {
        'customerPoints': 10,
        'amountSpent': 100000,
        'numberOfTransaction': 4,
        'category': 'santri',
      },
      '${memberId}_2': {
        'customerPoints': 8,
        'amountSpent': 80000,
        'numberOfTransaction': 3,
        'category': 'santri'
      },
      '${memberId}_3': {
        'customerPoints': 6,
        'amountSpent': 60000,
        'numberOfTransaction': 2,
        'category': 'santri'
      },
      '${memberId}_4': {
        'customerPoints': 4,
        'amountSpent': 40000,
        'numberOfTransaction': 1,
        'category': 'mahasiswa'
      },
    });
    await firestore
        .collection(Col.name('competitionRecords'))
        .doc(periodId)
        .collection('members')
        .doc(memberId)
        .set({
      'schemaVersion': 2,
      'memberId': memberId,
      'category': 'santri',
      'customerPoints': 2,
      'amountSpent': 20000,
      'numberOfTransaction': 1,
    });

    final firstRun = await MemberProgramService.finalizeCompetitionMonth(
      periodId: periodId,
      actorId: emulatorUid,
      now: finalizationTime,
    );
    expect(firstRun, hasLength(3));
    expect(firstRun.first.points, 10);
    expect(firstRun.map((winner) => winner.prizeAmount), [50000, 25000, 15000]);
    expect(firstRun.map((winner) => winner.category).toSet(), {'santri'});

    final secondRun = await MemberProgramService.finalizeCompetitionMonth(
      periodId: periodId,
      actorId: emulatorUid,
      now: finalizationTime,
    );
    expect(secondRun, hasLength(3));
    expect(secondRun.first.memberId, memberId);
    expect(secondRun.first.prizeAmount, 50000);

    final prize = await firestore
        .collection(Col.name('competitionPrizes'))
        .doc(periodId)
        .get();
    expect(prize.data()?['status'], 'finalized');
    expect(prize.data()?['rankingMode'], 'global');
    expect(prize.data()?['winnerCount'], 3);
    final winnerDocs = await prize.reference.collection('winners').get();
    expect(
        winnerDocs.docs.map((doc) => doc.id), ['rank_1', 'rank_2', 'rank_3']);
    final vouchers = await firestore
        .collection(Col.name('vouchers'))
        .where('competitionPrizePeriod', isEqualTo: periodId)
        .where('userId', isEqualTo: memberId)
        .get();
    expect(vouchers.docs, hasLength(1));
    expect(vouchers.docs.single.data()['value'], 50000);
  });

  test('legacy periods cannot issue extra global rewards', () async {
    final periodRef =
        firestore.collection(Col.name('competitionRecords')).doc('2026-08');
    await periodRef.set({
      'status': 'open',
      'legacy': {'customerPoints': 100}
    });
    await expectLater(
        MemberProgramService.finalizeCompetitionMonth(
            periodId: '2026-08', now: DateTime.utc(2026, 9, 7)),
        throwsA(isA<MemberProgramException>()));
    expect((await periodRef.get()).data()?['status'], 'open');
    expect(
        (await firestore
                .collection(Col.name('competitionPrizes'))
                .doc('2026-08')
                .get())
            .exists,
        isFalse);
  });

  test('competition and campaign vouchers can be claimed only once', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final now = DateTime.now();
    final activeDate = now.subtract(const Duration(minutes: 5));
    final expireDate = now.add(const Duration(hours: 1));

    Future<void> claimVoucher({
      required String voucherId,
      required int usedAmount,
      required String operationId,
    }) async {
      await firestore.runTransaction((transaction) async {
        final preparation =
            await MemberProgramService.prepareLocalVoucherClaimInTransaction(
          transaction: transaction,
          voucherId: voucherId,
          usedAmount: usedAmount,
          operationId: operationId,
        );
        MemberProgramService.commitLocalVoucherClaimInTransaction(
          transaction: transaction,
          preparation: preparation,
        );
      });
    }

    final globalVoucherId = 'global_competition_$suffix';
    await firestore.collection(Col.name('vouchers')).doc(globalVoucherId).set({
      'type': 'competitionPrize',
      'competitionPrizePeriod': '2026-09',
      'competitionRank': 1,
      'rankingMode': 'global',
      'status': 'READY_TO_CLAIM',
      'isActive': true,
      'isClaimed': false,
      'sekaliPakai': true,
      'value': 50000,
      'valueRemaining': 50000,
      'activeDate': activeDate,
      'expireDate': expireDate,
    });
    await claimVoucher(
        voucherId: globalVoucherId,
        usedAmount: 50000,
        operationId: 'global_claim_$suffix');
    expect(
        (await firestore
                .collection(Col.name('vouchers'))
                .doc(globalVoucherId)
                .get())
            .data()?['status'],
        'CLAIMED');
    await expectLater(
        claimVoucher(
            voucherId: globalVoucherId,
            usedAmount: 50000,
            operationId: 'global_repeat_$suffix'),
        throwsA(isA<MemberProgramException>()));

    for (final invalid in ['EXPIRED', 'DISABLED']) {
      final voucherId = '${invalid}_$suffix';
      await firestore.collection(Col.name('vouchers')).doc(voucherId).set({
        'type': 'competitionPrize',
        'competitionPrizePeriod': '2026-09',
        'competitionRank': 1,
        'rankingMode': 'global',
        'status': invalid,
        'isActive': invalid != 'DISABLED',
        'value': 50000,
        'activeDate': activeDate,
        'expireDate': invalid == 'EXPIRED' ? activeDate : expireDate,
      });
      await expectLater(
          claimVoucher(
              voucherId: voucherId,
              usedAmount: 50000,
              operationId: '${invalid}_claim_$suffix'),
          throwsA(isA<MemberProgramException>()));
    }

    final competitionVoucherId = 'legacy_competition_$suffix';
    await firestore
        .collection(Col.name('vouchers'))
        .doc(competitionVoucherId)
        .set({
      'type': 'competitionReward',
      'status': 'READY_TO_CLAIM',
      'value': 50000,
      'activeDate': activeDate,
      'expireDate': expireDate,
    });

    await claimVoucher(
      voucherId: competitionVoucherId,
      usedAmount: 50000,
      operationId: 'competition_claim_$suffix',
    );
    final claimedCompetition = await firestore
        .collection(Col.name('vouchers'))
        .doc(competitionVoucherId)
        .get();
    expect(claimedCompetition.data()?['status'], 'CLAIMED');
    expect(claimedCompetition.data()?['isActive'], isTrue);
    expect(claimedCompetition.data()?['isClaimed'], isTrue);
    expect(claimedCompetition.data()?['valueRemaining'], 0);
    expect(claimedCompetition.data()?['sekaliPakai'], isTrue);
    await expectLater(
      claimVoucher(
        voucherId: competitionVoucherId,
        usedAmount: 50000,
        operationId: 'competition_claim_again_$suffix',
      ),
      throwsA(isA<MemberProgramException>()),
    );

    final campaignId = 'campaign_$suffix';
    final campaignVoucherId = 'campaign_voucher_$suffix';
    await firestore.collection(Col.name('voucherGroup')).doc(campaignId).set({
      'voucherGroupId': campaignId,
      'type': 'cashbackCampaign',
      'status': 'active',
      'isActive': true,
      'activeDate': activeDate,
      'expireDate': expireDate,
      'threshold': 1,
      'value': 50000,
      'transactionRequirement': 0,
      'totalParticipants': 1,
      'totalClaimed': 0,
      'totalRedemptions': 0,
    });
    await firestore
        .collection(Col.name('vouchers'))
        .doc(campaignVoucherId)
        .set({
      'type': 'cashbackCampaign',
      'voucherGroupId': campaignId,
      'status': 'READY_TO_CLAIM',
      'isActive': true,
      'sekaliPakai': false,
      'value': 50000,
      'valueRemaining': 50000,
      'activeDate': activeDate,
      'expireDate': expireDate,
    });

    await claimVoucher(
      voucherId: campaignVoucherId,
      usedAmount: 20000,
      operationId: 'campaign_claim_$suffix',
    );
    final claimedCampaign = await firestore
        .collection(Col.name('vouchers'))
        .doc(campaignVoucherId)
        .get();
    expect(claimedCampaign.data()?['status'], 'CLAIMED');
    expect(claimedCampaign.data()?['isClaimed'], isTrue);
    expect(claimedCampaign.data()?['valueRemaining'], 0);
    expect(claimedCampaign.data()?['sekaliPakai'], isTrue);
    await expectLater(
      claimVoucher(
        voucherId: campaignVoucherId,
        usedAmount: 20000,
        operationId: 'campaign_claim_again_$suffix',
      ),
      throwsA(isA<MemberProgramException>()),
    );
  });
}
