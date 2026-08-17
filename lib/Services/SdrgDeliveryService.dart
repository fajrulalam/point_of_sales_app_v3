import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgBridgeService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgProductLinkService.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

/// What the POS has done about an SDRG delivery.
enum SdrgReceiptState {
  /// Stock has been moved to match the accepted revision.
  applied,

  /// SDRG cancelled the order and the stock has been taken back out.
  reversed,

  /// SDRG cancelled the order but the goods were already consumed here, so the
  /// reversal was declined and the difference is still outstanding.
  reversalPending,
}

/// The POS-side record of an SDRG delivery.
///
/// [appliedByPosItem] is keyed by *our* inventory item rather than by SDRG line
/// on purpose: it survives a product link being corrected, and it makes the
/// first acceptance, a later edit, and a cancellation all the same subtraction.
class SdrgDeliveryReceipt {
  final String sdrgOrderId;
  final int acceptedRevision;
  final SdrgReceiptState state;
  final Map<String, int> appliedByPosItem;
  final Map<String, int> unreconciled;

  const SdrgDeliveryReceipt({
    required this.sdrgOrderId,
    required this.acceptedRevision,
    required this.state,
    required this.appliedByPosItem,
    this.unreconciled = const {},
  });

  static const SdrgDeliveryReceipt none = SdrgDeliveryReceipt(
    sdrgOrderId: '',
    acceptedRevision: 0,
    state: SdrgReceiptState.applied,
    appliedByPosItem: {},
  );

  bool get exists => sdrgOrderId.isNotEmpty;

  factory SdrgDeliveryReceipt.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return SdrgDeliveryReceipt(
      sdrgOrderId: data['sdrgOrderId']?.toString() ?? doc.id,
      acceptedRevision: InventoryService.toInt(data['acceptedRevision']),
      state: _stateFromName(data['state']?.toString()),
      appliedByPosItem: _intMap(data['appliedByPosItem']),
      unreconciled: _intMap(data['unreconciled']),
    );
  }

  static Map<String, int> _intMap(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, int>{};
    raw.forEach((key, value) {
      final id = key?.toString() ?? '';
      if (id.isEmpty) return;
      result[id] = InventoryService.toInt(value);
    });
    return result;
  }

  static SdrgReceiptState _stateFromName(String? name) {
    switch (name) {
      case 'reversed':
        return SdrgReceiptState.reversed;
      case 'reversalPending':
        return SdrgReceiptState.reversalPending;
      default:
        return SdrgReceiptState.applied;
    }
  }
}

/// Raised when applying a delivery would push an inventory item below zero.
///
/// This happens when SDRG cancels an order whose goods the canteen has already
/// used. Reversing anyway is sometimes right, but it must be a deliberate
/// choice with the numbers on screen, never a silent write.
class SdrgNegativeStockException implements Exception {
  final List<SdrgNegativeStockItem> items;

  const SdrgNegativeStockException(this.items);

  @override
  String toString() => 'Stok akan menjadi negatif untuk ${items.length} bahan.';
}

class SdrgNegativeStockItem {
  final String inventoryItemId;
  final String inventoryItemName;
  final int change;
  final int stockBefore;

  const SdrgNegativeStockItem({
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.change,
    required this.stockBefore,
  });

  int get stockAfter => stockBefore + change;
}

class SdrgDeliveryService {
  SdrgDeliveryService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String canteenId = 'canteen375';

  static CollectionReference<Map<String, dynamic>> get _receipts => _firestore
      .collection(Col.name('Canteens'))
      .doc(canteenId)
      .collection('SdrgDeliveries');

  /// Shared with the sale and shopping flows, so one order can only ever be
  /// applied once per revision no matter which screen triggers it.
  static CollectionReference<Map<String, dynamic>> get _ledger => _firestore
      .collection(Col.name('Canteens'))
      .doc(canteenId)
      .collection('Orders');

  static String ledgerId(String sdrgOrderId, int revision) =>
      'sdrg_${sdrgOrderId}_r$revision';

  static Stream<Map<String, SdrgDeliveryReceipt>> watchReceipts() {
    return _receipts.snapshots().map((snapshot) => {
          for (final doc in snapshot.docs)
            doc.id: SdrgDeliveryReceipt.fromFirestore(doc),
        });
  }

  /// Net change per inventory item needed to bring us from what we have already
  /// applied to what [delivery] now says.
  ///
  /// A cancelled delivery targets zero, which is why cancellation needs no
  /// separate code path.
  static Map<String, int> computeDeltas({
    required SdrgDelivery delivery,
    required SdrgQuantityResolution resolution,
    required SdrgDeliveryReceipt receipt,
  }) {
    final target = delivery.isCancelled
        ? const <String, int>{}
        : resolution.quantities;
    final applied = receipt.appliedByPosItem;

    final deltas = <String, int>{};
    for (final id in {...target.keys, ...applied.keys}) {
      final change = (target[id] ?? 0) - (applied[id] ?? 0);
      if (change != 0) deltas[id] = change;
    }
    return deltas;
  }

  /// Inventory items where applying [deltas] would push stock below zero.
  ///
  /// Shared by the manual and automatic accept paths, so both agree on
  /// exactly the same threshold for what needs a person to decide.
  static List<SdrgNegativeStockItem> negativeStockShortfalls(
    Map<String, int> deltas,
    SdrgQuantityResolution resolution,
  ) {
    final inventory = InventoryService();
    final shortfalls = <SdrgNegativeStockItem>[];
    deltas.forEach((id, change) {
      if (change >= 0) return;
      final item = inventory.getInventoryItem(id);
      final before = item?.stock ?? 0;
      if (before + change < 0) {
        shortfalls.add(SdrgNegativeStockItem(
          inventoryItemId: id,
          inventoryItemName: item?.name ?? resolution.names[id] ?? id,
          change: change,
          stockBefore: before,
        ));
      }
    });
    return shortfalls;
  }

  /// Applies [delivery] at its current revision.
  ///
  /// Set [allowNegativeStock] only after the operator has confirmed a reversal
  /// that outruns what is left on the shelf.
  static Future<InventoryOperationResult> acceptDelivery({
    required SdrgDelivery delivery,
    required SdrgQuantityResolution resolution,
    required SdrgDeliveryReceipt receipt,
    bool allowNegativeStock = false,
    List<InventoryAuditFlag> additionalAuditFlags = const [],
  }) async {
    final deltas = computeDeltas(
      delivery: delivery,
      resolution: resolution,
      receipt: receipt,
    );

    if (!allowNegativeStock) {
      final shortfalls = negativeStockShortfalls(deltas, resolution);
      if (shortfalls.isNotEmpty) throw SdrgNegativeStockException(shortfalls);
    }

    final inventory = InventoryService();
    final revision = delivery.revision;
    final ledgerRef = _ledger.doc(ledgerId(delivery.orderId, revision));
    final receiptRef = _receipts.doc(delivery.orderId);
    final targetQuantities = delivery.isCancelled
        ? const <String, int>{}
        : resolution.quantities;

    final result = await _firestore
        .runTransaction<InventoryOperationResult>((transaction) async {
      // Every read happens before the first write, including the reads inside
      // applyStockDeltasInTransaction below.
      final ledgerSnapshot = await transaction.get(ledgerRef);
      if (ledgerSnapshot.exists &&
          ledgerSnapshot.data()?['status']?.toString().toLowerCase() ==
              'completed') {
        return const InventoryOperationResult.alreadyApplied();
      }

      final receiptSnapshot = await transaction.get(receiptRef);
      final storedRevision = receiptSnapshot.exists
          ? InventoryService.toInt(receiptSnapshot.data()?['acceptedRevision'])
          : 0;
      if (storedRevision != receipt.acceptedRevision) {
        throw Exception(
            'Penerimaan ini sudah diproses di perangkat lain. Muat ulang dan coba lagi.');
      }

      final stockResult = await inventory.applyStockDeltasInTransaction(
        transaction,
        [
          for (final entry in deltas.entries)
            StockDelta(
              inventoryItemId: entry.key,
              inventoryItemName:
                  resolution.names[entry.key] ?? entry.key,
              stockChange: entry.value,
              // Only genuine restocks feed the daily "added" figure; a reversal
              // must not inflate it.
              stockAddedChange: entry.value > 0 ? entry.value : 0,
            ),
        ],
        sourceType: 'sdrg_delivery',
        sourceId: '${delivery.orderId}#r$revision',
        additionalAuditFlags: additionalAuditFlags,
      );

      final state = delivery.isCancelled
          ? SdrgReceiptState.reversed
          : SdrgReceiptState.applied;

      transaction.set(
        receiptRef,
        {
          'sdrgOrderId': delivery.orderId,
          'sdrgRevision': revision,
          'sdrgStatus': delivery.status,
          'acceptedRevision': revision,
          'state': state.name,
          'appliedByPosItem': targetQuantities,
          'unreconciled': FieldValue.delete(),
          'auditFlags': stockResult.auditFlags.map((f) => f.toMap()).toList(),
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      transaction.set(
        ledgerRef,
        {
          'status': 'completed',
          'type': 'sdrg_delivery',
          'sourceId': delivery.orderId,
          'revision': revision,
          'completedAt': FieldValue.serverTimestamp(),
          'auditFlags': stockResult.auditFlags.map((f) => f.toMap()).toList(),
        },
        SetOptions(merge: true),
      );

      return InventoryOperationResult.applied(flags: stockResult.auditFlags);
    });

    await inventory.refreshInventoryCache();
    return result;
  }

  /// Records that a cancellation was acknowledged but not reversed, because the
  /// goods had already been used. The outstanding quantities are kept so a
  /// stock count can close the gap later.
  static Future<void> deferReversal({
    required SdrgDelivery delivery,
    required SdrgDeliveryReceipt receipt,
  }) async {
    await _receipts.doc(delivery.orderId).set(
      {
        'sdrgOrderId': delivery.orderId,
        'sdrgRevision': delivery.revision,
        'sdrgStatus': delivery.status,
        'acceptedRevision': delivery.revision,
        'state': SdrgReceiptState.reversalPending.name,
        // Still on our shelves as far as the books are concerned.
        'appliedByPosItem': receipt.appliedByPosItem,
        'unreconciled': receipt.appliedByPosItem,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
