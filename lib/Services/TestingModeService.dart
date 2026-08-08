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
    'competitionPrizes',
    'DailyFinancialReport',
    'DailyTransaction',
    'Expenses',
    'Members',
    'MonthlyFinancialReport',
    'MonthlyTransaction',
    'OrderHistory',
    'pointTransactions',
    'RecentlyServed',
    'SelfOrders',
    'Status',
    'Stock',
    'StockImageDaily',
    'StockSnapshotDaily',
    'StockTransactionDaily',
    'StockTransactionDetail',
    'voucher',
    'vouchers',
    'voucherGroup',
    'voucherProgram',
    'voucherPrograms',
    'memberProgramOperations',
    'externalVoucherClaims',
    'YearlyFinancialReport',
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

  // ── Data migration ────────────────────────────────────────────────

  /// Manually migrate MenuCollection from Production to Testing.
  /// Deletes existing test items before copying from production.
  static Future<void> migrateMenuCollection() async {
    final fs = FirebaseFirestore.instance;
    const docId = 'canteen375';
    const sub = 'MenuCollection';

    // 1. Delete existing test data
    final testSnap = await fs
        .collection('zTesting_Canteens')
        .doc(docId)
        .collection(sub)
        .get();

    if (testSnap.docs.isNotEmpty) {
      final deleteChunks = _chunkList(testSnap.docs, 400);
      for (final chunk in deleteChunks) {
        final batch = fs.batch();
        for (final doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }

    // 2. Fetch production data
    final prodSnap =
        await fs.collection('Canteens').doc(docId).collection(sub).get();

    // 3. Copy to test
    if (prodSnap.docs.isNotEmpty) {
      final copyChunks = _chunkList(prodSnap.docs, 400);
      for (final chunk in copyChunks) {
        final batch = fs.batch();
        for (final doc in chunk) {
          batch.set(
            fs
                .collection('zTesting_Canteens')
                .doc(docId)
                .collection(sub)
                .doc(doc.id),
            doc.data(),
          );
        }
        await batch.commit();
      }
    }
  }

  static Future<void> _migrateIfNeeded() async {
    final fs = FirebaseFirestore.instance;

    // Check if already migrated by looking for the canteen doc
    final check =
        await fs.collection('zTesting_Canteens').doc('canteen375').get();
    if (check.exists) {
      // Older testing-mode data may already contain the canteen copy but not
      // the B2B root collection.  Migrate that collection independently.
      await _migrateVoucherPrograms(fs);
      await _migrateMemberProgramCollections(fs);
      return;
    }

    debugPrint('[TestingMode] Migrating seed data …');

    // 1. Migrate Categories (flat)
    await _migrateFlat(fs, 'Categories');

    // 2. Migrate Members (flat)
    await _migrateFlat(fs, 'Members');

    // 3. Migrate B2B programs and their operation ledgers.
    await _migrateVoucherPrograms(fs);

    // 4. Migrate member points, competition, campaign, and external outbox
    // roots only when the corresponding testing collection is still empty.
    await _migrateMemberProgramCollections(fs);

    // 5. Migrate Canteens + subcollections
    await _migrateCanteens(fs);

    debugPrint('[TestingMode] Migration complete.');
  }

  /// Copy every document from [source] → zTesting_[source].
  static Future<void> _migrateFlat(FirebaseFirestore fs, String source) async {
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

  /// Copies voucherPrograms without mutating production.  Nested ledgers are
  /// copied as well so testing mode can exercise idempotency against realistic
  /// historical data.
  static Future<void> _migrateVoucherPrograms(FirebaseFirestore fs) async {
    final testCollection = fs.collection('zTesting_voucherPrograms');
    final existing = await testCollection.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final source = await fs.collection('voucherPrograms').get();
    for (final chunk in _chunkList(source.docs, 400)) {
      final batch = fs.batch();
      for (final doc in chunk) {
        batch.set(testCollection.doc(doc.id), doc.data());
      }
      await batch.commit();
    }
    for (final doc in source.docs) {
      for (final sub in ['redemptions', 'settlements', 'closures']) {
        final nested = await doc.reference.collection(sub).get();
        for (final chunk in _chunkList(nested.docs, 400)) {
          final batch = fs.batch();
          for (final child in chunk) {
            batch.set(testCollection.doc(doc.id).collection(sub).doc(child.id),
                child.data());
          }
          await batch.commit();
        }
      }
    }
    debugPrint(
        '[TestingMode]   voucherPrograms: ${source.docs.length} docs copied.');
  }

  static Future<void> _migrateMemberProgramCollections(
      FirebaseFirestore fs) async {
    const roots = [
      'competitionRecords',
      'competitionPrizes',
      'pointTransactions',
      'memberProgramOperations',
      'externalVoucherClaims',
      'voucherGroup',
      'vouchers',
    ];
    for (final root in roots) {
      final target = fs.collection('zTesting_$root');
      if ((await target.limit(1).get()).docs.isNotEmpty) continue;
      final source = await fs.collection(root).get();
      for (final chunk in _chunkList(source.docs, 400)) {
        final batch = fs.batch();
        for (final doc in chunk) {
          batch.set(target.doc(doc.id), doc.data());
        }
        await batch.commit();
      }
      if (root == 'competitionRecords') {
        for (final period in source.docs) {
          final members = await period.reference.collection('members').get();
          for (final chunk in _chunkList(members.docs, 400)) {
            final batch = fs.batch();
            for (final member in chunk) {
              batch.set(
                target.doc(period.id).collection('members').doc(member.id),
                member.data(),
              );
            }
            await batch.commit();
          }
        }
      }
      if (root == 'competitionPrizes') {
        for (final prize in source.docs) {
          final winners = await prize.reference.collection('winners').get();
          for (final chunk in _chunkList(winners.docs, 400)) {
            final batch = fs.batch();
            for (final winner in chunk) {
              batch.set(
                target.doc(prize.id).collection('winners').doc(winner.id),
                winner.data(),
              );
            }
            await batch.commit();
          }
        }
      }
      debugPrint('[TestingMode]   $root: ${source.docs.length} docs copied.');
    }
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
      'OpenBillLocks',
      'Orders',
      'SelfOrders',
      'StockCollection',
      'shoppingOrders',
      'suppliers',
    ];

    // Copy the canteen document itself
    final canteenDoc = await fs.collection('Canteens').doc(docId).get();
    if (canteenDoc.exists) {
      await fs
          .collection('zTesting_Canteens')
          .doc(docId)
          .set(canteenDoc.data()!);
    }

    // Copy each subcollection
    for (final sub in subcollections) {
      final snap =
          await fs.collection('Canteens').doc(docId).collection(sub).get();

      // Firestore batch limit is 500 — chunk if needed
      final chunks = _chunkList(snap.docs, 400);
      for (final chunk in chunks) {
        final batch = fs.batch();
        for (final doc in chunk) {
          batch.set(
            fs
                .collection('zTesting_Canteens')
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
      chunks.add(
          list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return chunks;
  }
}
