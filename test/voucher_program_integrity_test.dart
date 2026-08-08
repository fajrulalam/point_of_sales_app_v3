import 'package:flutter_test/flutter_test.dart';
import 'package:point_of_sales_app_v3/Services/VoucherProgramService.dart';

void main() {
  test('caps B2B nominal at the bill remaining after ordinary vouchers', () {
    final payment = B2BPaymentBreakdown.calculate(
      billTotal: 75000,
      requestedNominal: 100000,
      programId: 'program-1',
    );

    expect(payment.nominal, 75000);
    expect(payment.remaining, 0);
    expect(payment.cashAmount, 0);
  });

  test('keeps B2B nominal separate from extra payment breakdown', () {
    final payment = B2BPaymentBreakdown.calculate(
      billTotal: 100000,
      requestedNominal: 60000,
      programId: 'program-1',
      extraPaymentMethod: 'Cash + QRIS',
      qrisAmount: 25000,
    );

    expect(payment.nominal, 60000);
    expect(payment.remaining, 40000);
    expect(payment.cashAmount, 15000);
    expect(payment.qrisAmount, 25000);
    expect(payment.toFinancialFields().keys,
        containsAll(<String>['totalVoucher', 'totalB2BRedeemed']));
  });

  test('supports online extra payment without counting voucher nominal as cash',
      () {
    final payment = B2BPaymentBreakdown.calculate(
      billTotal: 120000,
      requestedNominal: 20000,
      programId: 'program-1',
      extraPaymentMethod: 'Online',
    );

    expect(payment.onlineAmount, 100000);
    expect(payment.cashAmount, 0);
    expect(payment.qrisAmount, 0);
  });

  test('reads normalized split details with numeric legacy values', () {
    final payment = B2BPaymentBreakdown.fromStatus(
      {
        'paymentMethod': 'Program',
        'voucherProgramId': 'program-1',
        'programNominal': '40.000',
        'programExtraPaymentMethod': 'Cash + QRIS',
        'programExtraSplitDetails': {
          'cashAmount': 30000.0,
          'qrisAmount': '30.000',
        },
        'voucherProgram': {
          'id': 'program-1',
          'nominal': 40000,
          'extraPaymentMethod': 'Cash + QRIS',
          'extraCashAmount': 30000,
          'extraQrisAmount': 30000,
        },
      },
      total: 100000,
    );

    expect(payment.nominal, 40000);
    expect(payment.cashAmount, 30000);
    expect(payment.qrisAmount, 30000);
    expect(payment.isAmbiguousLegacy, isFalse);
  });

  test('parses formatted legacy nominal values without inventing a split', () {
    final payment = B2BPaymentBreakdown.fromStatus(
      {
        'paymentMethod': 'Program',
        'voucherProgramId': 'program-1',
        'programNominal': '40.000',
        'programExtraPaymentMethod': 'Cash',
      },
      total: 100000,
    );

    expect(payment.nominal, 40000);
    expect(payment.cashAmount, 60000);
    expect(payment.isAmbiguousLegacy, isFalse);
  });

  test('marks legacy records with missing split details as ambiguous', () {
    final payment = B2BPaymentBreakdown.fromStatus(
      {
        'paymentMethod': 'Program',
        'voucherProgramId': 'program-1',
        'programNominal': 40000,
        'programExtraPaymentMethod': 'Cash + QRIS',
      },
      total: 100000,
    );

    expect(payment.isAmbiguousLegacy, isTrue);
  });

  test('rejects a B2B bill with no valid remainder payment method', () {
    expect(
      () => B2BPaymentBreakdown.calculate(
        billTotal: 100000,
        requestedNominal: 40000,
        programId: 'program-1',
      ),
      throwsA(isA<VoucherProgramException>()),
    );
  });

  test('calculates partial and full settlement status transitions', () {
    final partial = VoucherProgramService.calculateSettlement(
      totalRedeemed: 100000,
      totalSettled: 0,
      amount: 40000,
      currentStatus: 'active',
    );
    final full = VoucherProgramService.calculateSettlement(
      totalRedeemed: 100000,
      totalSettled: 40000,
      amount: 60000,
      currentStatus: 'active',
    );

    expect(partial.newTotalSettled, 40000);
    expect(partial.resultingStatus, 'active');
    expect(full.newTotalSettled, 100000);
    expect(full.resultingStatus, 'paid');
  });

  test('rejects overpayment and unsafe edit deltas', () {
    expect(
      () => VoucherProgramService.calculateSettlement(
        totalRedeemed: 100000,
        totalSettled: 90000,
        amount: 10001,
        currentStatus: 'active',
      ),
      throwsA(isA<VoucherProgramException>()),
    );
    final increased = VoucherProgramService.calculateEditDelta(
      currentRedeemed: 100000,
      currentSettled: 100000,
      oldNominal: 40000,
      newNominal: 60000,
    );
    expect(increased.delta, 20000);
    expect(increased.resultingRedeemed, 120000);
    expect(increased.resultingStatus, 'active');
    expect(
      () => VoucherProgramService.calculateEditDelta(
        currentRedeemed: 100000,
        currentSettled: 100000,
        oldNominal: 40000,
        newNominal: 30000,
      ),
      throwsA(isA<VoucherProgramException>()),
    );
  });
}
