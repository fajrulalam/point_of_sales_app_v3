import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Services/VoucherProgramService.dart';

void main() {
  const definedFirestoreHost =
      String.fromEnvironment('FIRESTORE_EMULATOR_HOST');
  const definedAuthHost = String.fromEnvironment('FIREBASE_AUTH_EMULATOR_HOST');
  const definedRunFlag = String.fromEnvironment('RUN_FIREBASE_EMULATOR_TESTS');
  final firestoreHost = Platform.environment['FIRESTORE_EMULATOR_HOST'] ??
      (definedFirestoreHost.isEmpty ? null : definedFirestoreHost);
  final runEmulatorTests =
      Platform.environment['RUN_FIREBASE_EMULATOR_TESTS'] == '1' ||
          definedRunFlag == '1' ||
          definedRunFlag.toLowerCase() == 'true';
  if (firestoreHost == null ||
      firestoreHost.trim().isEmpty ||
      !runEmulatorTests) {
    test(
      'voucher emulator tests require FIRESTORE_EMULATOR_HOST',
      () {},
      skip:
          'Set RUN_FIREBASE_EMULATOR_TESTS=1 with FIRESTORE_EMULATOR_HOST and run the Firestore/Auth emulators on a Flutter integration target.',
    );
    return;
  }

  late FirebaseFirestore firestore;
  FirebaseAuth? auth;
  late String firestoreAddress;
  late int firestorePort;
  late String authHost;
  late int authPort;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final firestoreParts = firestoreHost.split(':');
    firestoreAddress = firestoreParts.first;
    firestorePort = firestoreParts.length > 1
        ? int.tryParse(firestoreParts.last) ?? 8080
        : 8080;
    final authAddress = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] ??
        (definedAuthHost.isEmpty ? '$firestoreAddress:9099' : definedAuthHost);
    final authParts = authAddress.split(':');
    authHost = authParts.first;
    authPort =
        authParts.length > 1 ? int.tryParse(authParts.last) ?? 9099 : 9099;

    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'demo-api-key',
          appId: '1:1234567890:android:emulator',
          messagingSenderId: '1234567890',
          projectId: 'point-of-sales-app-25e2b',
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
    Col.testingMode.value = true;
  });

  tearDownAll(() async {
    Col.testingMode.value = false;
    await auth?.signOut();
  });

  test('redemption and settlement stay duplicate-safe under concurrency',
      () async {
    // defaultNominal is deliberately above requestedNominal (4000 < 5000) so
    // each redemption floors to 5000 — see calculateRedemptionLedgerAmount.
    final programId = await VoucherProgramService.createProgram(
      programName: 'Emulator ${DateTime.now().microsecondsSinceEpoch}',
      institutionName: 'Test Institution',
      defaultNominal: 5000,
    );

    Future<void> redeem(String operationId) async {
      await firestore.runTransaction((transaction) async {
        final preparation =
            await VoucherProgramService.prepareRedemptionInTransaction(
          transaction: transaction,
          programId: programId,
          requestedNominal: 4000,
          billTotal: 5000,
          operationId: operationId,
          sourceType: 'emulator_test',
          sourceId: operationId,
        );
        VoucherProgramService.commitRedemptionInTransaction(
          transaction: transaction,
          preparation: preparation,
          sourceType: 'emulator_test',
          sourceId: operationId,
        );
      });
    }

    await Future.wait([
      redeem('redeem-duplicate'),
      redeem('redeem-duplicate'),
      redeem('redeem-second'),
    ]);

    final afterRedemption = await VoucherProgramService.getProgram(programId);
    // Two distinct operations each floor to 5000 (4000 requested < 5000
    // defaultNominal): 5000 + 5000 = 10000, not the raw 4000 + 4000 = 8000.
    expect(afterRedemption?['totalRedeemed'], 10000);

    await Future.wait([
      VoucherProgramService.settleProgram(
        programId: programId,
        settledAmount: 3000,
        paymentMethod: 'Cash',
        operationId: 'settle-duplicate',
      ),
      VoucherProgramService.settleProgram(
        programId: programId,
        settledAmount: 3000,
        paymentMethod: 'Cash',
        operationId: 'settle-duplicate',
      ),
    ]);

    final afterPartial = await VoucherProgramService.getProgram(programId);
    expect(afterPartial?['totalSettled'], 3000);
    expect(afterPartial?['status'], 'active');

    await expectLater(
      VoucherProgramService.settleProgram(
        programId: programId,
        settledAmount: 7001,
        paymentMethod: 'QRIS',
        operationId: 'settle-overpayment',
      ),
      throwsA(isA<VoucherProgramException>()),
    );

    await VoucherProgramService.settleProgram(
      programId: programId,
      settledAmount: 7000,
      paymentMethod: 'QRIS',
      operationId: 'settle-final',
    );
    final finalProgram = await VoucherProgramService.getProgram(programId);
    expect(finalProgram?['totalSettled'], 10000);
    expect(finalProgram?['status'], 'paid');
  });

  test('floors a redemption below defaultNominal up to the program face value',
      () async {
    final programId = await VoucherProgramService.createProgram(
      programName: 'Floor ${DateTime.now().microsecondsSinceEpoch}',
      institutionName: 'Floor Institution',
      defaultNominal: 15000,
    );

    await firestore.runTransaction((transaction) async {
      final preparation =
          await VoucherProgramService.prepareRedemptionInTransaction(
        transaction: transaction,
        programId: programId,
        requestedNominal: 12000,
        billTotal: 12000,
        operationId: 'floor-redemption',
        sourceType: 'emulator_test',
        sourceId: 'floor-redemption',
      );
      VoucherProgramService.commitRedemptionInTransaction(
        transaction: transaction,
        preparation: preparation,
        sourceType: 'emulator_test',
        sourceId: 'floor-redemption',
      );
    });

    final program = await VoucherProgramService.getProgram(programId);
    expect(program?['totalRedeemed'], 15000);

    // The ledger doc backs VoucherProgramAuditService's invariant that the
    // sum of ledger amounts always equals totalRedeemed, so it must carry
    // the floored value too, not the raw bill-capped 12000.
    final ledgerDoc = await firestore
        .collection(Col.name('voucherPrograms'))
        .doc(programId)
        .collection('redemptions')
        .doc('floor-redemption')
        .get();
    expect(ledgerDoc.data()?['amount'], 15000);
  });

  test(
      'a combined redemption above defaultNominal (e.g. the x2 multiplier) is recorded as-is',
      () async {
    final programId = await VoucherProgramService.createProgram(
      programName: 'Multiplier ${DateTime.now().microsecondsSinceEpoch}',
      institutionName: 'Multiplier Institution',
      defaultNominal: 15000,
    );

    await firestore.runTransaction((transaction) async {
      final preparation =
          await VoucherProgramService.prepareRedemptionInTransaction(
        transaction: transaction,
        programId: programId,
        requestedNominal: 30000,
        billTotal: 32000,
        operationId: 'multiplier-redemption',
        sourceType: 'emulator_test',
        sourceId: 'multiplier-redemption',
      );
      VoucherProgramService.commitRedemptionInTransaction(
        transaction: transaction,
        preparation: preparation,
        sourceType: 'emulator_test',
        sourceId: 'multiplier-redemption',
      );
    });

    final program = await VoucherProgramService.getProgram(programId);
    expect(program?['totalRedeemed'], 30000);
  });

  test(
      'a program with no defaultNominal configured redeems the bill-capped amount',
      () async {
    final programId = await VoucherProgramService.createProgram(
      programName: 'NoDefault ${DateTime.now().microsecondsSinceEpoch}',
      institutionName: 'NoDefault Institution',
    );

    await firestore.runTransaction((transaction) async {
      final preparation =
          await VoucherProgramService.prepareRedemptionInTransaction(
        transaction: transaction,
        programId: programId,
        requestedNominal: 12000,
        billTotal: 12000,
        operationId: 'no-default-redemption',
        sourceType: 'emulator_test',
        sourceId: 'no-default-redemption',
      );
      VoucherProgramService.commitRedemptionInTransaction(
        transaction: transaction,
        preparation: preparation,
        sourceType: 'emulator_test',
        sourceId: 'no-default-redemption',
      );
    });

    final program = await VoucherProgramService.getProgram(programId);
    expect(program?['totalRedeemed'], 12000);
  });

  test(
      'a replayed redemption keeps its original floored amount even if defaultNominal changes afterward',
      () async {
    final programId = await VoucherProgramService.createProgram(
      programName: 'Replay ${DateTime.now().microsecondsSinceEpoch}',
      institutionName: 'Replay Institution',
      defaultNominal: 15000,
    );

    Future<void> redeemOnce() => firestore.runTransaction((transaction) async {
          final preparation =
              await VoucherProgramService.prepareRedemptionInTransaction(
            transaction: transaction,
            programId: programId,
            requestedNominal: 12000,
            billTotal: 12000,
            operationId: 'replay-redemption',
            sourceType: 'emulator_test',
            sourceId: 'replay-redemption',
          );
          VoucherProgramService.commitRedemptionInTransaction(
            transaction: transaction,
            preparation: preparation,
            sourceType: 'emulator_test',
            sourceId: 'replay-redemption',
          );
        });

    await redeemOnce();
    final afterFirst = await VoucherProgramService.getProgram(programId);
    expect(afterFirst?['totalRedeemed'], 15000);

    await VoucherProgramService.updateProgram(
      programId,
      {'defaultNominal': 5000},
      expectedRevision: (afterFirst?['revision'] as num?)?.toInt() ?? 0,
    );

    // Same operationId as before: this must replay as already-applied and
    // keep the original 15000, not re-floor against the new defaultNominal.
    await redeemOnce();
    final afterReplay = await VoucherProgramService.getProgram(programId);
    expect(afterReplay?['totalRedeemed'], 15000);
  });

  test(
      'editing a program-paid order without changing intent leaves totalRedeemed unchanged',
      () async {
    final programId = await VoucherProgramService.createProgram(
      programName: 'EditGrow ${DateTime.now().microsecondsSinceEpoch}',
      institutionName: 'EditGrow Institution',
      defaultNominal: 15000,
    );

    await firestore.runTransaction((transaction) async {
      final preparation =
          await VoucherProgramService.prepareRedemptionInTransaction(
        transaction: transaction,
        programId: programId,
        requestedNominal: 12000,
        billTotal: 12000,
        operationId: 'edit-grow-sale',
        sourceType: 'emulator_test',
        sourceId: 'edit-grow-sale',
      );
      VoucherProgramService.commitRedemptionInTransaction(
        transaction: transaction,
        preparation: preparation,
        sourceType: 'emulator_test',
        sourceId: 'edit-grow-sale',
      );
    });

    // EditOrderService always re-requests the same old (unfloored) nominal
    // when only the bill total grows, so both sides floor identically here.
    await firestore.runTransaction((transaction) async {
      final editPreparation =
          await VoucherProgramService.prepareEditInTransaction(
        transaction: transaction,
        operationId: 'edit-grow-edit',
        oldProgramId: programId,
        oldNominal: 12000,
        newProgramId: programId,
        newNominal: 12000,
      );
      VoucherProgramService.commitEditInTransaction(
        transaction: transaction,
        preparation: editPreparation,
        sourceId: 'edit-grow-edit',
      );
    });

    final program = await VoucherProgramService.getProgram(programId);
    expect(program?['totalRedeemed'], 15000);
  });

  test('removing a program from an edited order reverses the floored amount',
      () async {
    final programId = await VoucherProgramService.createProgram(
      programName: 'EditRemove ${DateTime.now().microsecondsSinceEpoch}',
      institutionName: 'EditRemove Institution',
      defaultNominal: 15000,
    );

    await firestore.runTransaction((transaction) async {
      final preparation =
          await VoucherProgramService.prepareRedemptionInTransaction(
        transaction: transaction,
        programId: programId,
        requestedNominal: 12000,
        billTotal: 12000,
        operationId: 'edit-remove-sale',
        sourceType: 'emulator_test',
        sourceId: 'edit-remove-sale',
      );
      VoucherProgramService.commitRedemptionInTransaction(
        transaction: transaction,
        preparation: preparation,
        sourceType: 'emulator_test',
        sourceId: 'edit-remove-sale',
      );
    });

    await firestore.runTransaction((transaction) async {
      final editPreparation =
          await VoucherProgramService.prepareEditInTransaction(
        transaction: transaction,
        operationId: 'edit-remove-edit',
        oldProgramId: programId,
        oldNominal: 12000,
        newProgramId: null,
        newNominal: 0,
      );
      VoucherProgramService.commitEditInTransaction(
        transaction: transaction,
        preparation: editPreparation,
        sourceId: 'edit-remove-edit',
      );
    });

    final program = await VoucherProgramService.getProgram(programId);
    expect(program?['totalRedeemed'], 0);
  });

  test('settlement and closing race never creates an invalid balance',
      () async {
    final programId = await VoucherProgramService.createProgram(
      programName: 'Race ${DateTime.now().microsecondsSinceEpoch}',
      institutionName: 'Race Institution',
    );

    await firestore.runTransaction((transaction) async {
      final preparation =
          await VoucherProgramService.prepareRedemptionInTransaction(
        transaction: transaction,
        programId: programId,
        requestedNominal: 1000,
        billTotal: 1000,
        operationId: 'race-redemption',
        sourceType: 'emulator_test',
        sourceId: 'race-redemption',
      );
      VoucherProgramService.commitRedemptionInTransaction(
        transaction: transaction,
        preparation: preparation,
        sourceType: 'emulator_test',
        sourceId: 'race-redemption',
      );
    });

    await Future.wait([
      VoucherProgramService.settleProgram(
        programId: programId,
        settledAmount: 1000,
        paymentMethod: 'Cash',
        operationId: 'race-settlement',
      ).catchError((_) => const VoucherProgramOperationResult()),
      VoucherProgramService.closeProgram(
        programId,
        operationId: 'race-close',
      ).catchError((_) {}),
    ]);

    final program = await VoucherProgramService.getProgram(programId);
    final redeemed = (program?['totalRedeemed'] as num?)?.toInt() ?? 0;
    final settled = (program?['totalSettled'] as num?)?.toInt() ?? 0;
    expect(settled, lessThanOrEqualTo(redeemed));
    expect(program?['status'], isIn(<String>['active', 'paid', 'closed']));
    if (program?['status'] == 'closed') {
      expect(settled, redeemed);
    }
  });
}
