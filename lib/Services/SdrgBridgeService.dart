import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:point_of_sales_app_v3/Services/SdrgBridgeCredentials.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

/// Read-only link to Sentra Distribusi Rejoso Gemilang (`warehouse-375`), the
/// wholesaler Canteen375 restocks from.
///
/// SDRG mirrors every paid sale to Canteen375 into a delivery outbox. This
/// service is the only place that talks to that project, and it never writes:
/// the POS records what it has accepted in its own project instead, so no
/// cross-project write credentials are needed and no cross-project transaction
/// is ever attempted. That mirrors the two-project protocol already documented
/// in `docs/e_santren_voucher_claim_protocol.md`.
class SdrgBridgeService {
  SdrgBridgeService._();

  /// Name of the secondary [FirebaseApp] initialised in `main.dart`.
  static const String appName = 'warehouse-375';

  /// Dedicated read-only account in the SDRG project
  /// (`users/{uid}.role == 'bridge'`, allow-listed by UID in SDRG's
  /// `firestore.rules`). See `docs/sdrg_stock_bridge_protocol.md`.
  ///
  /// The email is not sensitive and lives here directly. The password comes
  /// from `SdrgBridgeCredentials.dart`, a file this repo's `.gitignore`
  /// deliberately excludes -- this repository is public, so unlike the
  /// existing `admin@canteen375.com` constant in `LoginScreen.dart`, this one
  /// must never reach git history at all, not even a scoped, read-only one.
  /// No `--dart-define` flag needed: it's a plain import, created once per
  /// machine.
  static const String bridgeEmail = 'bridge@warehouse375.com';
  static const String bridgePassword = sdrgBridgePassword;

  static bool get isConfigured =>
      bridgeEmail.isNotEmpty && bridgePassword.isNotEmpty;

  /// Deliveries older than this are not worth showing; the query stays a
  /// single-field range so it needs no composite index.
  static const Duration _window = Duration(days: 60);

  static FirebaseFirestore get _firestore =>
      FirebaseFirestore.instanceFor(app: Firebase.app(appName));

  static FirebaseAuth get _auth =>
      FirebaseAuth.instanceFor(app: Firebase.app(appName));

  /// POS testing mode reads SDRG's staging environment, so the two never mix.
  static String get outboxCollection => Col.testingMode.value
      ? 'deliveries_canteen375_test'
      : 'deliveries_canteen375';

  static String get _linkCollection => Col.testingMode.value
      ? 'pos_product_links_test'
      : 'pos_product_links';

  static Future<void>? _signIn;

  /// Signed in lazily on first use rather than at app start: the bridge is a
  /// side feature and must never delay or break launch.
  static Future<void> ensureSignedIn() {
    if (_auth.currentUser != null) return Future.value();
    return _signIn ??= _auth
        .signInWithEmailAndPassword(
          email: bridgeEmail,
          password: bridgePassword,
        )
        .then((_) {})
        .whenComplete(() => _signIn = null);
  }

  /// Links configured in the SDRG web app, keyed by SDRG product ID.
  ///
  /// These are defaults only. A link saved on this device wins, so the POS
  /// always has the final say over its own stock.
  static Future<Map<String, SdrgRemoteLink>> fetchRemoteLinks() async {
    if (!isConfigured) return const {};
    try {
      await ensureSignedIn();
      final snapshot = await _firestore.collection(_linkCollection).get();
      return {
        for (final doc in snapshot.docs)
          doc.id: SdrgRemoteLink(
            sdrgProductId: doc.id,
            sdrgProductName: doc.data()['sdrg_product_name']?.toString() ?? '',
            sdrgBaseUnit: doc.data()['sdrg_base_unit']?.toString() ?? '',
            inventoryItemId: doc.data()['inventory_item_id']?.toString() ?? '',
            inventoryItemName:
                doc.data()['inventory_item_name']?.toString() ?? '',
            posUnit: doc.data()['pos_unit']?.toString() ?? '',
          ),
      };
    } catch (error) {
      debugPrint('SDRG link fetch skipped: $error');
      return const {};
    }
  }

  /// Emits every delivery SDRG has published for Canteen375 within [_window].
  ///
  /// Errors surface as a stream error so callers can show an offline state; the
  /// bridge being unreachable must never take down the screen hosting it.
  static Stream<List<SdrgDelivery>> watchDeliveries() async* {
    if (!isConfigured) {
      throw StateError(
          'Akun jembatan SDRG belum dikonfigurasi. Lihat SdrgBridgeService.bridgeEmail.');
    }
    await ensureSignedIn();
    yield* _firestore
        .collection(outboxCollection)
        .where('order_created_at',
            isGreaterThanOrEqualTo:
                Timestamp.fromDate(DateTime.now().subtract(_window)))
        .orderBy('order_created_at', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => SdrgDelivery.fromFirestore(doc)).toList());
  }
}

/// A product link configured in the SDRG web app.
///
/// Deliberately a separate type from the local link so the precedence rule
/// stays visible at the call site rather than hidden behind a merge.
class SdrgRemoteLink {
  final String sdrgProductId;
  final String sdrgProductName;
  final String sdrgBaseUnit;
  final String inventoryItemId;
  final String inventoryItemName;
  final String posUnit;

  const SdrgRemoteLink({
    required this.sdrgProductId,
    required this.sdrgProductName,
    required this.sdrgBaseUnit,
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.posUnit,
  });
}

/// A single line of a delivery. [baseQty] is the only quantity SDRG publishes
/// for stock purposes, and it is always expressed in [baseUnit].
class SdrgDeliveryLine {
  final String productId;
  final String productName;
  final num baseQty;
  final String baseUnit;

  const SdrgDeliveryLine({
    required this.productId,
    required this.productName,
    required this.baseQty,
    required this.baseUnit,
  });

  factory SdrgDeliveryLine.fromMap(Map<String, dynamic> map) {
    return SdrgDeliveryLine(
      productId: map['product_id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? '',
      baseQty: map['base_qty'] is num ? map['base_qty'] as num : 0,
      baseUnit: map['base_unit']?.toString() ?? '',
    );
  }
}

/// A paid sale SDRG has published for Canteen375.
///
/// [revision] increases whenever SDRG edits or cancels the underlying order, so
/// the POS can tell an unseen delivery from one it has already acted on.
class SdrgDelivery {
  final String orderId;
  final int revision;
  final String status;
  final String? customerId;
  final List<SdrgDeliveryLine> lines;
  final DateTime? orderCreatedAt;

  const SdrgDelivery({
    required this.orderId,
    required this.revision,
    required this.status,
    required this.customerId,
    required this.lines,
    required this.orderCreatedAt,
  });

  bool get isCancelled => status == 'cancelled';

  factory SdrgDelivery.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawLines =
        data['lines'] is List ? data['lines'] as List<dynamic> : const [];
    return SdrgDelivery(
      orderId: data['order_id']?.toString() ?? doc.id,
      revision: data['revision'] is num ? (data['revision'] as num).toInt() : 1,
      status: data['status']?.toString() ?? 'completed',
      customerId: data['customer_id']?.toString(),
      lines: rawLines
          .whereType<Map<String, dynamic>>()
          .map(SdrgDeliveryLine.fromMap)
          .where((line) => line.productId.isNotEmpty)
          .toList(),
      orderCreatedAt: data['order_created_at'] is Timestamp
          ? (data['order_created_at'] as Timestamp).toDate()
          : null,
    );
  }
}
