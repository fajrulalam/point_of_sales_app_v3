import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgBridgeService.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

// A link stored on this device is always the POS's own, whatever it says.


/// Maps an SDRG product onto one of our inventory items.
///
/// SDRG and the POS keep separate catalogues, so the link is stored on our side
/// and confirmed by a human once per product. [sdrgBaseUnit] is recorded so a
/// later change to the product's unit in SDRG can be detected rather than
/// silently reinterpreted.
/// Where a link was configured. Shown in the delivery card so it is clear
/// whether a mapping came from this device or from the SDRG web app.
enum SdrgLinkSource { pos, sdrg }

class SdrgProductLink {
  final String sdrgProductId;
  final String sdrgProductName;
  final String sdrgBaseUnit;
  final String inventoryItemId;
  final String inventoryItemName;
  final String posUnit;
  final SdrgLinkSource source;

  const SdrgProductLink({
    required this.sdrgProductId,
    required this.sdrgProductName,
    required this.sdrgBaseUnit,
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.posUnit,
    this.source = SdrgLinkSource.pos,
  });

  Map<String, dynamic> toMap() => {
        'sdrgProductId': sdrgProductId,
        'sdrgProductName': sdrgProductName,
        'sdrgBaseUnit': sdrgBaseUnit,
        'inventoryItemId': inventoryItemId,
        'inventoryItemName': inventoryItemName,
        'posUnit': posUnit,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory SdrgProductLink.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return SdrgProductLink(
      sdrgProductId: data['sdrgProductId']?.toString() ?? doc.id,
      sdrgProductName: data['sdrgProductName']?.toString() ?? '',
      sdrgBaseUnit: data['sdrgBaseUnit']?.toString() ?? '',
      inventoryItemId: data['inventoryItemId']?.toString() ?? '',
      inventoryItemName: data['inventoryItemName']?.toString() ?? '',
      posUnit: data['posUnit']?.toString() ?? '',
    );
  }
}

/// Why a delivery line cannot be turned into a stock movement.
enum SdrgLineBlock {
  /// No [SdrgProductLink] exists for this SDRG product yet.
  unmapped,

  /// SDRG changed the product's base unit after the link was confirmed, so the
  /// quantity may no longer mean what the link assumes.
  unitDrift,

  /// The quantity does not land on a whole number. POS stock is an integer, and
  /// rounding either way would invent or destroy stock invisibly.
  nonIntegerQuantity,
}

/// One SDRG delivery line resolved against our inventory.
class SdrgResolvedLine {
  final SdrgDeliveryLine line;
  final SdrgProductLink? link;
  final SdrgLineBlock? block;

  const SdrgResolvedLine({required this.line, this.link, this.block});

  bool get isApplicable => block == null && link != null;
}

class SdrgProductLinkService {
  SdrgProductLinkService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String canteenId = 'canteen375';

  static CollectionReference<Map<String, dynamic>> get _collection => _firestore
      .collection(Col.name('Canteens'))
      .doc(canteenId)
      .collection('SdrgProductLinks');

  static Future<Map<String, SdrgProductLink>> fetchLocalLinks() async {
    final snapshot = await _collection.get();
    return {
      for (final doc in snapshot.docs)
        doc.id: SdrgProductLink.fromFirestore(doc),
    };
  }

  /// Links from both sides, with anything configured on this device winning.
  ///
  /// SDRG's web app is the convenient place to do the bulk of the linking, but
  /// the POS owns its own stock, so a local link always overrides the remote
  /// one for that product.
  static Future<Map<String, SdrgProductLink>> fetchLinks() async {
    final results = await Future.wait([
      fetchLocalLinks(),
      SdrgBridgeService.fetchRemoteLinks(),
    ]);
    final local = results[0] as Map<String, SdrgProductLink>;
    final remote = results[1] as Map<String, SdrgRemoteLink>;

    return {
      for (final entry in remote.entries)
        if (entry.value.inventoryItemId.isNotEmpty)
          entry.key: SdrgProductLink(
            sdrgProductId: entry.value.sdrgProductId,
            sdrgProductName: entry.value.sdrgProductName,
            sdrgBaseUnit: entry.value.sdrgBaseUnit,
            inventoryItemId: entry.value.inventoryItemId,
            inventoryItemName: entry.value.inventoryItemName,
            posUnit: entry.value.posUnit,
            source: SdrgLinkSource.sdrg,
          ),
      ...local,
    };
  }

  static Future<void> saveLink(SdrgProductLink link) async {
    await _collection.doc(link.sdrgProductId).set(
          link.toMap(),
          SetOptions(merge: true),
        );
  }

  static Future<void> removeLink(String sdrgProductId) async {
    await _collection.doc(sdrgProductId).delete();
  }

  /// Resolves each delivery line against the saved links, flagging anything
  /// that must not be applied automatically.
  static List<SdrgResolvedLine> resolveLines(
    List<SdrgDeliveryLine> lines,
    Map<String, SdrgProductLink> links,
  ) {
    return lines.map((line) {
      final link = links[line.productId];
      if (link == null || link.inventoryItemId.isEmpty) {
        return SdrgResolvedLine(line: line, block: SdrgLineBlock.unmapped);
      }
      if (_normalizeUnit(link.sdrgBaseUnit) != _normalizeUnit(line.baseUnit)) {
        return SdrgResolvedLine(
          line: line,
          link: link,
          block: SdrgLineBlock.unitDrift,
        );
      }
      return SdrgResolvedLine(line: line, link: link);
    }).toList();
  }

  /// Totals the resolved lines per POS inventory item.
  ///
  /// Coalescing happens *before* the whole-number check on purpose: two SDRG
  /// products can legitimately map to one inventory item, and each half may be
  /// fractional while the total is not.
  static SdrgQuantityResolution quantitiesByInventoryItem(
      List<SdrgResolvedLine> resolved) {
    final totals = <String, num>{};
    final names = <String, String>{};
    for (final entry in resolved) {
      if (!entry.isApplicable) continue;
      final id = entry.link!.inventoryItemId;
      totals[id] = (totals[id] ?? 0) + entry.line.baseQty;
      names[id] = entry.link!.inventoryItemName;
    }

    final quantities = <String, int>{};
    final fractional = <String, num>{};
    totals.forEach((id, total) {
      final rounded = total.round();
      if ((total - rounded).abs() > 1e-6) {
        fractional[id] = total;
      } else {
        quantities[id] = rounded;
      }
    });

    return SdrgQuantityResolution(
      quantities: quantities,
      fractional: fractional,
      names: names,
    );
  }

  /// Suggests a POS inventory item for an unmapped SDRG product.
  ///
  /// Only an unambiguous normalized-name match is offered, and it is a
  /// suggestion the operator still has to confirm: a wrong link corrupts stock
  /// silently, which is far worse than leaving a product unmapped.
  static String? suggestInventoryItemId(String sdrgProductName) {
    final target = _normalizeName(sdrgProductName);
    if (target.isEmpty) return null;

    final matches = <String>[];
    for (final item in InventoryService().allInventoryItems.values) {
      if (_normalizeName(item.name) == target) matches.add(item.id);
    }
    return matches.length == 1 ? matches.single : null;
  }

  static String _normalizeName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _normalizeUnit(String value) => value.toLowerCase().trim();
}

class SdrgQuantityResolution {
  /// Whole-number quantities, keyed by POS inventory item ID.
  final Map<String, int> quantities;

  /// Totals that did not land on a whole number, keyed the same way. These
  /// block acceptance rather than being rounded.
  final Map<String, num> fractional;

  final Map<String, String> names;

  const SdrgQuantityResolution({
    required this.quantities,
    required this.fractional,
    required this.names,
  });

  bool get hasFractional => fractional.isNotEmpty;
}
