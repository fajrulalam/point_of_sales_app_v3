import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/UserMessageService.dart';

class EndOfDayService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String canteenId = 'canteen375';

  /// Check if we missed an end-of-day reset and trigger it if needed
  static Future<void> checkAndAutoResetPerishables() async {
    int retryCount = 0;
    const int maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        // Wait for authentication if not ready (important for anonymous logins)
        int authAttempts = 0;
        while (FirebaseAuth.instance.currentUser == null && authAttempts < 5) {
          await Future.delayed(const Duration(milliseconds: 1000));
          authAttempts++;
        }

        final metadataRef = _firestore
            .collection(Col.name('Canteens'))
            .doc(canteenId)
            .collection('Metadata')
            .doc('InventoryLogs');

        final today = _getTodayDateString();

        // Fetch perishables first because query cannot be done inside transaction
        final perishablesSnapshot = await _firestore
            .collection(Col.name('Canteens'))
            .doc(canteenId)
            .collection('Inventory')
            .where('isPerishable', isEqualTo: true)
            .get();

        if (perishablesSnapshot.docs.isEmpty) return;

        await _firestore.runTransaction((transaction) async {
          final metadataDoc = await transaction.get(metadataRef);

          // Ensure data() is not null before checking field
          if (metadataDoc.exists && metadataDoc.data() != null) {
            final lastResetDate = metadataDoc.data()!['last_reset_date'];
            if (_isResetDate(lastResetDate, today)) {
              print('✅ Perishables already reset for today ($today)');
              return; // Abort silently if already reset by another device
            }
          }

          print(
              '🔄 Triggering automated perishable reset for $today via Transaction');

          // Read every current inventory document before queuing any reset
          // writes. A sale/restock racing this reset therefore causes a
          // transaction retry instead of an absolute stale-stock overwrite.
          final currentSnapshots =
              <String, DocumentSnapshot<Map<String, dynamic>>>{};
          for (final doc in perishablesSnapshot.docs) {
            currentSnapshots[doc.id] = await transaction.get(doc.reference);
          }

          for (final doc in perishablesSnapshot.docs) {
            final currentSnapshot = currentSnapshots[doc.id];
            if (currentSnapshot == null || !currentSnapshot.exists) continue;
            final data = currentSnapshot.data() ?? <String, dynamic>{};
            final currentStock = InventoryService.toInt(data['stock']);
            final itemName = data['name']?.toString() ?? '';

            if (currentStock > 0) {
              final logId = InventoryService.canonicalDailyLogId(today, doc.id);
              final logRef = _firestore
                  .collection(Col.name('Canteens'))
                  .doc(canteenId)
                  .collection('DailyStockLogs')
                  .doc(logId);

              transaction.set(
                  logRef,
                  {
                    'date': today,
                    'inventoryItemId': doc.id,
                    'inventoryItemName': itemName,
                    'isPerishable': true,
                    'stockWasted': FieldValue.increment(currentStock),
                    'endingStock': 0,
                    'lastUpdated': FieldValue.serverTimestamp(),
                    'autoReset': true,
                  },
                  SetOptions(merge: true));

              transaction.update(doc.reference, {
                'stock': 0,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
            }
          }

          transaction.set(
              metadataRef,
              {
                'last_reset_date': today,
                'last_updated': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
        });

        print('✅ Auto-reset perishables completed safely for $today');
        return; // Success, exit the loop
      } catch (e) {
        final errorStr = e.toString();
        if (errorStr.contains('unavailable') ||
            errorStr.contains('network-error')) {
          retryCount++;
          if (retryCount < maxRetries) {
            final delay = Duration(seconds: retryCount * 3);
            print(
                '⚠️ Firestore unavailable in checkAndAutoResetPerishables, retrying in ${delay.inSeconds}s (Attempt $retryCount/$maxRetries)...');
            await Future.delayed(delay);
            continue;
          }
        }
        print('❌ Error in checkAndAutoResetPerishables: $e');
        break; // Exit loop on non-retryable error or max retries reached
      }
    }
  }

  /// Show end of day dialog to record perishable waste and reset stock
  static Future<void> showEndOfDayDialog(BuildContext context) async {
    final inventoryService = InventoryService();
    await inventoryService.refreshInventoryCache();

    // Get all perishable items
    final perishablesSnapshot = await _firestore
        .collection(Col.name('Canteens'))
        .doc(canteenId)
        .collection('Inventory')
        .where('isPerishable', isEqualTo: true)
        .get();

    if (perishablesSnapshot.docs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tidak ada item perishable yang perlu direset',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
      return;
    }

    final perishables = perishablesSnapshot.docs
        .map((doc) => InventoryItem.fromFirestore(doc))
        .toList();

    if (context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _EndOfDayDialog(perishables: perishables),
      );
    }
  }

  /// Helper to get today's date as string
  static String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static bool _isResetDate(dynamic value, String today) {
    if (value is Timestamp) {
      final date = value.toDate();
      final formatted =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      return formatted == today;
    }
    if (value is DateTime) {
      final formatted =
          '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
      return formatted == today;
    }
    return value?.toString() == today;
  }
}

class _EndOfDayDialog extends StatefulWidget {
  final List<InventoryItem> perishables;

  const _EndOfDayDialog({required this.perishables});

  @override
  State<_EndOfDayDialog> createState() => _EndOfDayDialogState();
}

class _EndOfDayDialogState extends State<_EndOfDayDialog> {
  final Map<String, TextEditingController> _controllers = {};
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    for (var item in widget.perishables) {
      _controllers[item.id] = TextEditingController(
        text: item.stock.toString(),
      );
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _processEndOfDay() async {
    setState(() => _isProcessing = true);

    try {
      final today = EndOfDayService._getTodayDateString();
      final firestore = FirebaseFirestore.instance;
      final inventoryCollection = firestore
          .collection(Col.name('Canteens'))
          .doc(EndOfDayService.canteenId)
          .collection('Inventory');
      final logCollection = firestore
          .collection(Col.name('Canteens'))
          .doc(EndOfDayService.canteenId)
          .collection('DailyStockLogs');
      final metadataRef = firestore
          .collection(Col.name('Canteens'))
          .doc(EndOfDayService.canteenId)
          .collection('Metadata')
          .doc('InventoryLogs');

      await firestore.runTransaction((transaction) async {
        final metadataSnapshot = await transaction.get(metadataRef);
        final lastResetDate = metadataSnapshot.data()?['last_reset_date'];
        if (EndOfDayService._isResetDate(lastResetDate, today)) {
          // Manual and automatic resets share the same day marker. A second
          // confirmation must not add the same waste to the daily log again.
          return;
        }
        final currentSnapshots =
            <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final item in widget.perishables) {
          currentSnapshots[item.id] =
              await transaction.get(inventoryCollection.doc(item.id));
        }

        // All reads are above. The reset writes below therefore retry against
        // the latest stock if a sale or restock races this dialog.
        for (final item in widget.perishables) {
          final itemSnapshot = currentSnapshots[item.id];
          if (itemSnapshot == null || !itemSnapshot.exists) continue;
          final data = itemSnapshot.data() ?? <String, dynamic>{};
          final currentStock = InventoryService.toInt(data['stock']);
          if (currentStock != item.stock) {
            throw Exception(
                'Stok ${item.name} berubah dari ${item.stock} menjadi $currentStock. Muat ulang sebelum reset.');
          }
          final inputWaste = int.tryParse(_controllers[item.id]!.text) ?? 0;
          final actualWaste = inputWaste < 0 ? 0 : inputWaste;
          final itemRef = inventoryCollection.doc(item.id);
          transaction.set(
            logCollection
                .doc(InventoryService.canonicalDailyLogId(today, item.id)),
            {
              'date': today,
              'inventoryItemId': item.id,
              'inventoryItemName': data['name']?.toString() ?? item.name,
              'isPerishable': true,
              'stockWasted': FieldValue.increment(actualWaste),
              'endingStock': 0,
              'stockBeforeReset': currentStock,
              'lastUpdated': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          transaction.update(itemRef, {
            'stock': 0,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
        transaction.set(
            metadataRef,
            {
              'last_reset_date': today,
              'last_updated': FieldValue.serverTimestamp(),
              'resetType': 'manual',
            },
            SetOptions(merge: true));
      });

      await InventoryService().refreshInventoryCache();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  'Penutupan hari berhasil diselesaikan',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal menyelesaikan penutupan hari: ${UserMessageService.fromError(e)}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.nightlight_round, color: Colors.indigo),
          const SizedBox(width: 12),
          Text(
            'End of Day - Perishables',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masukkan jumlah item perishable yang tersisa:',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: widget.perishables.length,
                itemBuilder: (context, index) {
                  final item = widget.perishables[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Perishable Item',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _controllers[item.id],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Waste (${item.unit})',
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              style: GoogleFonts.poppins(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
          child: Text('Batal', style: GoogleFonts.poppins()),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _processEndOfDay,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text('Complete End of Day', style: GoogleFonts.poppins()),
        ),
      ],
    );
  }
}
