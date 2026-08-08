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
    expect(afterRedemption?['totalRedeemed'], 8000);

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
        settledAmount: 5001,
        paymentMethod: 'QRIS',
        operationId: 'settle-overpayment',
      ),
      throwsA(isA<VoucherProgramException>()),
    );

    await VoucherProgramService.settleProgram(
      programId: programId,
      settledAmount: 5000,
      paymentMethod: 'QRIS',
      operationId: 'settle-final',
    );
    final finalProgram = await VoucherProgramService.getProgram(programId);
    expect(finalProgram?['totalSettled'], 8000);
    expect(finalProgram?['status'], 'paid');
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
