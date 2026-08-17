import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgBridgeService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgDeliveryService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgProductLinkService.dart';

/// Applies every SDRG delivery that resolves cleanly, with no confirmation
/// tap -- as soon as SDRG records a sale, or as soon as a product it was
/// waiting on gets linked.
///
/// The one thing this never decides on its own: a cancellation that would
/// push stock below zero, which usually means the goods have already been
/// used. Reversing that anyway has to stay a person's call; everything else
/// -- a fresh sale, an edited quantity, a clean cancellation, a newly linked
/// product -- applies itself.
class SdrgAutoAcceptService {
  SdrgAutoAcceptService._();

  static StreamSubscription<List<SdrgDelivery>>? _deliverySub;
  static StreamSubscription<Map<String, SdrgDeliveryReceipt>>? _receiptSub;

  static List<SdrgDelivery> _deliveries = const [];
  static Map<String, SdrgDeliveryReceipt> _receipts = const {};
  static final Set<String> _inFlight = {};
  static bool _running = false;

  static bool get isRunning => _running;

  /// Starts watching. Safe to call more than once -- only one pair of
  /// subscriptions is ever active. Never throws or blocks: a failure to
  /// connect is logged and simply retried on the next change, the same way a
  /// single delivery's failure never stops the others.
  static void start() {
    if (_running || !SdrgBridgeService.isConfigured) return;
    _running = true;

    _deliverySub = SdrgBridgeService.watchDeliveries().listen(
      (deliveries) {
        _deliveries = deliveries;
        _reconcile();
      },
      onError: (Object error) =>
          debugPrint('SDRG auto-accept: delivery stream error: $error'),
    );
    _receiptSub = SdrgDeliveryService.watchReceipts().listen(
      (receipts) {
        _receipts = receipts;
        _reconcile();
      },
      onError: (Object error) =>
          debugPrint('SDRG auto-accept: receipt stream error: $error'),
    );
  }

  static Future<void> stop() async {
    _running = false;
    await _deliverySub?.cancel();
    await _receiptSub?.cancel();
    _deliverySub = null;
    _receiptSub = null;
  }

  /// Re-checks everything right away, rather than waiting for the next
  /// delivery or receipt change. Nothing about saving a product link touches
  /// either of those collections, so linking a previously-blocked product
  /// would otherwise sit unnoticed until some unrelated change happened to
  /// fire the streams again.
  static Future<void> reconcileNow() => _reconcile();

  static Future<void> _reconcile() async {
    final links = await SdrgProductLinkService.fetchLinks();

    for (final delivery in _deliveries) {
      final receipt = _receipts[delivery.orderId] ?? SdrgDeliveryReceipt.none;
      if (receipt.acceptedRevision >= delivery.revision) continue;
      if (_inFlight.contains(delivery.orderId)) continue;

      final resolved =
          SdrgProductLinkService.resolveLines(delivery.lines, links);
      if (resolved.any((line) => line.block != null)) {
        continue; // a product still needs linking
      }

      final resolution =
          SdrgProductLinkService.quantitiesByInventoryItem(resolved);
      if (resolution.hasFractional) continue; // needs a manual override

      _inFlight.add(delivery.orderId);
      unawaited(_tryApply(delivery, resolution, receipt));
    }
  }

  static Future<void> _tryApply(
    SdrgDelivery delivery,
    SdrgQuantityResolution resolution,
    SdrgDeliveryReceipt receipt,
  ) async {
    try {
      // Fresh stock numbers immediately before deciding: the cache may still
      // be empty if the app only just started and no screen has loaded it yet.
      await InventoryService().refreshInventoryCache();

      final deltas = SdrgDeliveryService.computeDeltas(
        delivery: delivery,
        resolution: resolution,
        receipt: receipt,
      );
      if (SdrgDeliveryService.negativeStockShortfalls(deltas, resolution)
          .isNotEmpty) {
        return; // a person has to choose how to handle this one
      }

      await SdrgDeliveryService.acceptDelivery(
        delivery: delivery,
        resolution: resolution,
        receipt: receipt,
      );
    } catch (error) {
      debugPrint('SDRG auto-accept failed for ${delivery.orderId}: $error');
    } finally {
      _inFlight.remove(delivery.orderId);
    }
  }
}
