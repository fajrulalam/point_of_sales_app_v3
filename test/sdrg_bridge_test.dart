import 'package:flutter_test/flutter_test.dart';
import 'package:point_of_sales_app_v3/Services/SdrgBridgeService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgDeliveryService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgProductLinkService.dart';

SdrgDeliveryLine _line(String productId, num baseQty,
        {String unit = 'kg', String? name}) =>
    SdrgDeliveryLine(
      productId: productId,
      productName: name ?? productId,
      baseQty: baseQty,
      baseUnit: unit,
    );

SdrgProductLink _link(String sdrgProductId, String inventoryItemId,
        {String unit = 'kg'}) =>
    SdrgProductLink(
      sdrgProductId: sdrgProductId,
      sdrgProductName: sdrgProductId,
      sdrgBaseUnit: unit,
      inventoryItemId: inventoryItemId,
      inventoryItemName: inventoryItemId,
      posUnit: unit,
    );

SdrgDelivery _delivery(
  List<SdrgDeliveryLine> lines, {
  int revision = 1,
  String status = 'completed',
}) =>
    SdrgDelivery(
      orderId: '2026-08-14-0001',
      revision: revision,
      status: status,
      customerId: 'CANTEEN_ABCD',
      lines: lines,
      orderCreatedAt: null,
    );

SdrgQuantityResolution _resolve(
  SdrgDelivery delivery,
  Map<String, SdrgProductLink> links,
) =>
    SdrgProductLinkService.quantitiesByInventoryItem(
      SdrgProductLinkService.resolveLines(delivery.lines, links),
    );

void main() {
  group('line resolution', () {
    test('flags a product that has no link yet', () {
      final resolved =
          SdrgProductLinkService.resolveLines([_line('GP_1234', 5)], const {});

      expect(resolved.single.block, SdrgLineBlock.unmapped);
      expect(resolved.single.isApplicable, isFalse);
    });

    test('flags a base unit that changed in SDRG after the link was made', () {
      final resolved = SdrgProductLinkService.resolveLines(
        [_line('GP_1234', 5, unit: 'gram')],
        {'GP_1234': _link('GP_1234', 'Gula_1', unit: 'kg')},
      );

      expect(resolved.single.block, SdrgLineBlock.unitDrift);
    });

    test('accepts a matching unit regardless of case and padding', () {
      final resolved = SdrgProductLinkService.resolveLines(
        [_line('GP_1234', 5, unit: ' KG ')],
        {'GP_1234': _link('GP_1234', 'Gula_1', unit: 'kg')},
      );

      expect(resolved.single.block, isNull);
      expect(resolved.single.isApplicable, isTrue);
    });
  });

  group('quantity resolution', () {
    test('sums two SDRG products that map to one inventory item', () {
      final resolution = _resolve(
        _delivery([_line('BRS_A', 5), _line('BRS_B', 3)]),
        {
          'BRS_A': _link('BRS_A', 'Beras_1'),
          'BRS_B': _link('BRS_B', 'Beras_1'),
        },
      );

      expect(resolution.quantities, {'Beras_1': 8});
      expect(resolution.hasFractional, isFalse);
    });

    test('coalesces before checking, so fractional halves that total a whole pass', () {
      final resolution = _resolve(
        _delivery([_line('BRS_A', 2.5), _line('BRS_B', 2.5)]),
        {
          'BRS_A': _link('BRS_A', 'Beras_1'),
          'BRS_B': _link('BRS_B', 'Beras_1'),
        },
      );

      expect(resolution.quantities, {'Beras_1': 5});
      expect(resolution.hasFractional, isFalse);
    });

    test('blocks a total that is not a whole number rather than rounding it', () {
      final resolution = _resolve(
        _delivery([_line('GP_1234', 2.5)]),
        {'GP_1234': _link('GP_1234', 'Gula_1')},
      );

      expect(resolution.quantities, isEmpty);
      expect(resolution.hasFractional, isTrue);
      expect(resolution.fractional['Gula_1'], 2.5);
    });

    test('excludes blocked lines from the applicable quantities', () {
      final resolution = _resolve(
        _delivery([_line('GP_1234', 5), _line('UNKNOWN', 9)]),
        {'GP_1234': _link('GP_1234', 'Gula_1')},
      );

      expect(resolution.quantities, {'Gula_1': 5});
    });
  });

  group('net deltas', () {
    test('a first acceptance applies the full quantity', () {
      final delivery = _delivery([_line('GP_1234', 5)]);
      final links = {'GP_1234': _link('GP_1234', 'Gula_1')};

      final deltas = SdrgDeliveryService.computeDeltas(
        delivery: delivery,
        resolution: _resolve(delivery, links),
        receipt: SdrgDeliveryReceipt.none,
      );

      expect(deltas, {'Gula_1': 5});
    });

    test('an increased revision applies only the difference', () {
      final delivery = _delivery([_line('GP_1234', 8)], revision: 2);
      final links = {'GP_1234': _link('GP_1234', 'Gula_1')};

      final deltas = SdrgDeliveryService.computeDeltas(
        delivery: delivery,
        resolution: _resolve(delivery, links),
        receipt: const SdrgDeliveryReceipt(
          sdrgOrderId: '2026-08-14-0001',
          acceptedRevision: 1,
          state: SdrgReceiptState.applied,
          appliedByPosItem: {'Gula_1': 5},
        ),
      );

      expect(deltas, {'Gula_1': 3});
    });

    test('a reduced revision takes stock back out', () {
      final delivery = _delivery([_line('GP_1234', 2)], revision: 2);
      final links = {'GP_1234': _link('GP_1234', 'Gula_1')};

      final deltas = SdrgDeliveryService.computeDeltas(
        delivery: delivery,
        resolution: _resolve(delivery, links),
        receipt: const SdrgDeliveryReceipt(
          sdrgOrderId: '2026-08-14-0001',
          acceptedRevision: 1,
          state: SdrgReceiptState.applied,
          appliedByPosItem: {'Gula_1': 5},
        ),
      );

      expect(deltas, {'Gula_1': -3});
    });

    test('an item dropped from the order is fully reversed', () {
      final delivery = _delivery([_line('GP_1234', 5)], revision: 2);
      final links = {
        'GP_1234': _link('GP_1234', 'Gula_1'),
        'TLR_9999': _link('TLR_9999', 'Telur_1'),
      };

      final deltas = SdrgDeliveryService.computeDeltas(
        delivery: delivery,
        resolution: _resolve(delivery, links),
        receipt: const SdrgDeliveryReceipt(
          sdrgOrderId: '2026-08-14-0001',
          acceptedRevision: 1,
          state: SdrgReceiptState.applied,
          appliedByPosItem: {'Gula_1': 5, 'Telur_1': 30},
        ),
      );

      expect(deltas, {'Telur_1': -30});
    });

    test('a cancellation targets zero without a separate code path', () {
      final delivery =
          _delivery([_line('GP_1234', 5)], revision: 2, status: 'cancelled');
      final links = {'GP_1234': _link('GP_1234', 'Gula_1')};

      final deltas = SdrgDeliveryService.computeDeltas(
        delivery: delivery,
        resolution: _resolve(delivery, links),
        receipt: const SdrgDeliveryReceipt(
          sdrgOrderId: '2026-08-14-0001',
          acceptedRevision: 1,
          state: SdrgReceiptState.applied,
          appliedByPosItem: {'Gula_1': 5},
        ),
      );

      expect(deltas, {'Gula_1': -5});
    });

    test('re-applying the same revision is a no-op', () {
      final delivery = _delivery([_line('GP_1234', 5)]);
      final links = {'GP_1234': _link('GP_1234', 'Gula_1')};

      final deltas = SdrgDeliveryService.computeDeltas(
        delivery: delivery,
        resolution: _resolve(delivery, links),
        receipt: const SdrgDeliveryReceipt(
          sdrgOrderId: '2026-08-14-0001',
          acceptedRevision: 1,
          state: SdrgReceiptState.applied,
          appliedByPosItem: {'Gula_1': 5},
        ),
      );

      expect(deltas, isEmpty);
    });

    test('cancelling a delivery that was never accepted changes nothing', () {
      final delivery = _delivery([_line('GP_1234', 5)], status: 'cancelled');
      final links = {'GP_1234': _link('GP_1234', 'Gula_1')};

      final deltas = SdrgDeliveryService.computeDeltas(
        delivery: delivery,
        resolution: _resolve(delivery, links),
        receipt: SdrgDeliveryReceipt.none,
      );

      expect(deltas, isEmpty);
    });
  });

  group('idempotency ledger', () {
    test('is keyed per revision so a later revision is not swallowed', () {
      expect(SdrgDeliveryService.ledgerId('2026-08-14-0001', 1),
          'sdrg_2026-08-14-0001_r1');
      expect(SdrgDeliveryService.ledgerId('2026-08-14-0001', 2),
          isNot(SdrgDeliveryService.ledgerId('2026-08-14-0001', 1)));
    });
  });
}
