import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

/// Mirrors the cashier's in-progress basket to Realtime Database so the
/// customer-facing tablet (Membership_App, logged in as an admin) can show
/// a live "cross-check your order" view while the cashier is still typing.
///
/// Writes are fire-and-forget and debounced — a display sync failure or a
/// burst of rapid taps must never slow down or interrupt checkout.
class LiveBasketService {
  LiveBasketService._();
  static final LiveBasketService instance = LiveBasketService._();

  Timer? _debounce;

  DatabaseReference get _ref {
    final root = Col.testingMode.value ? 'zTesting_liveBasket' : 'liveBasket';
    return FirebaseDatabase.instance.ref(root).child('current');
  }

  void publish({
    required List<PesananObject> items,
    required int total,
    required int packagingFee,
    required bool isTakeAway,
  }) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _write(items, total, packagingFee, isTakeAway);
    });
  }

  Future<void> _write(
    List<PesananObject> items,
    int total,
    int packagingFee,
    bool isTakeAway,
  ) async {
    try {
      final itemCount =
          items.fold<int>(0, (acc, item) => acc + item.totalQuantity);

      await _ref.set({
        'items': items
            .map((item) => {
                  'name': item.namaPesanan,
                  'dineInQuantity': item.dineInQuantity,
                  'takeAwayQuantity': item.takeAwayQuantity,
                  'quantity': item.totalQuantity,
                  'unitPrice': item.effectivePrice,
                  'subtotal': item.subtotal,
                  'note': item.customerNote,
                  'options': item.selectedOptions
                      .map((o) => {
                            'group': o.groupName,
                            'option': o.optionName,
                            'priceAdjustment': o.priceAdjustment,
                          })
                      .toList(),
                })
            .toList(),
        'itemCount': itemCount,
        'packagingFee': packagingFee,
        'total': total,
        'isTakeAway': isTakeAway,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      print('[LiveBasketService] Failed to publish basket: $e');
    }
  }
}
