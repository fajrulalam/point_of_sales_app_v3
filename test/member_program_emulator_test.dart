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
    final memberId = 'member_$suffix';
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
    expect(ledgers.docs.length, 1);
  });
}
