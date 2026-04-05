import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central service for testing mode.
///
/// Usage:  `FirebaseFirestore.instance.collection(Col.name('DailyTransaction'))`
/// In testing mode this resolves to `'zTesting_DailyTransaction'`.
class Col {
  Col._();

  static const _prefKey = 'testing_mode_enabled';

  /// Observable flag — listen with `ValueListenableBuilder`.
  static final ValueNotifier<bool> testingMode = ValueNotifier(false);

  /// Root collections that get the prefix in testing mode.
  static const _rootCollections = <String>{
    'Canteens',
    'Categories',
    'competitionRecords',
    'DailyFinancialReport',
    'DailyTransaction',
    'Expenses',
    'Members',
    'MonthlyTransaction',
    'OrderHistory',
    'RecentlyServed',
    'Status',
    'Stock',
    'StockImageDaily',
    'StockSnapshotDaily',
    'StockTransactionDaily',
    'StockTransactionDetail',
    'voucher',
    'vouchers',
    'voucherGroup',
    'YearlyTransaction',
  };

  /// Returns the (possibly prefixed) collection name.
  static String name(String collection) {
    if (testingMode.value && _rootCollections.contains(collection)) {
      return 'zTesting_$collection';
    }
    return collection;
  }

  /// Call once at app startup (before runApp).
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    testingMode.value = prefs.getBool(_prefKey) ?? false;
  }

  /// Toggle testing mode on/off. Persists the choice.
  /// When turning ON for the first time, migrates seed data.
  static Future<void> toggle() async {
    testingMode.value = !testingMode.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, testingMode.value);

    if (testingMode.value) {
      await _migrateIfNeeded();
    }
  }

  // ── One-time data migration ────────────────────────────────────────

  static Future<void> _migrateIfNeeded() async {
    final fs = FirebaseFirestore.instance;

    // Check if already migrated by looking for the canteen doc
    final check = await fs
        .collection('zTesting_Canteens')
        .doc('canteen375')
        .get();
    if (check.exists) return; // already migrated

    debugPrint('[TestingMode] Migrating seed data …');

    // 1. Migrate Categories (flat)
    await _migrateFlat(fs, 'Categories');

    // 2. Migrate Members (flat)
    await _migrateFlat(fs, 'Members');

    // 3. Migrate Canteens + subcollections
    await _migrateCanteens(fs);

    debugPrint('[TestingMode] Migration complete.');
  }

  /// Copy every document from [source] → zTesting_[source].
  static Future<void> _migrateFlat(
      FirebaseFirestore fs, String source) async {
    final snap = await fs.collection(source).get();
    final batch = fs.batch();
    for (final doc in snap.docs) {
      batch.set(
        fs.collection('zTesting_$source').doc(doc.id),
        doc.data(),
      );
    }
    await batch.commit();
    debugPrint('[TestingMode]   $source: ${snap.docs.length} docs copied.');
  }

  /// Deep-copy Canteens/canteen375 and all its subcollections.
  static Future<void> _migrateCanteens(FirebaseFirestore fs) async {
    const docId = 'canteen375';
    const subcollections = [
      'DailyStockLogs',
      'Inventory',
      'MenuCollection',
      'Metadata',
      'OptionGroups',
      'SelfOrders',
      'StockCollection',
      'shoppingOrders',
      'suppliers',
    ];

    // Copy the canteen document itself
    final canteenDoc =
        await fs.collection('Canteens').doc(docId).get();
    if (canteenDoc.exists) {
      await fs
          .collection('zTesting_Canteens')
          .doc(docId)
          .set(canteenDoc.data()!);
    }

    // Copy each subcollection
    for (final sub in subcollections) {
      final snap = await fs
          .collection('Canteens')
          .doc(docId)
          .collection(sub)
          .get();

      // Firestore batch limit is 500 — chunk if needed
      final chunks = _chunkList(snap.docs, 400);
      for (final chunk in chunks) {
        final batch = fs.batch();
        for (final doc in chunk) {
          batch.set(
            fs.collection('zTesting_Canteens')
                .doc(docId)
                .collection(sub)
                .doc(doc.id),
            doc.data(),
          );
        }
        await batch.commit();
      }
      debugPrint(
          '[TestingMode]   Canteens/$docId/$sub: ${snap.docs.length} docs.');
    }
  }

  static List<List<T>> _chunkList<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return chunks;
  }
}
