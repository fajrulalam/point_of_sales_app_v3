import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';

class EndOfDayService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String canteenId = 'canteen375';

  /// Check if we missed an end-of-day reset and trigger it if needed
  static Future<void> checkAndAutoResetPerishables() async {
    try {
      // Wait for authentication if not ready (important for anonymous logins)
      int authAttempts = 0;
      while (FirebaseAuth.instance.currentUser == null && authAttempts < 5) {
        await Future.delayed(const Duration(milliseconds: 1000));
        authAttempts++;
      }

      final metadataRef = _firestore
          .collection('Canteens')
          .doc(canteenId)
          .collection('Metadata')
          .doc('InventoryLogs');

      final doc = await metadataRef.get();
      final today = _getTodayDateString();
      
      if (doc.exists) {
        final lastResetDate = doc.data()?['last_reset_date'] as String?;
        if (lastResetDate == today) {
          print('✅ Perishables already reset for today ($today)');
          return;
        }
      }

      // If we're here, either it's the first time or target date is reached
      print('🔄 Triggering automated perishable reset for $today');
      await autoResetPerishables();
      
      // Update the last reset date
      await metadataRef.set({
        'last_reset_date': today,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
    } catch (e) {
      print('❌ Error in checkAndAutoResetPerishables: $e');
    }
  }

  /// Show end of day dialog to record perishable waste and reset stock
  static Future<void> showEndOfDayDialog(BuildContext context) async {
    final inventoryService = InventoryService();
    await inventoryService.refreshInventoryCache();

    // Get all perishable items
    final perishablesSnapshot = await _firestore
        .collection('Canteens')
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

  /// Automatically reset perishables at end of day (to be called by scheduler)
  static Future<void> autoResetPerishables() async {
    try {
      final perishablesSnapshot = await _firestore
          .collection('Canteens')
          .doc(canteenId)
          .collection('Inventory')
          .where('isPerishable', isEqualTo: true)
          .get();

      final batch = _firestore.batch();
      final today = _getTodayDateString();

      for (var doc in perishablesSnapshot.docs) {
        final data = doc.data();
        final int currentStock = (data['stock'] ?? 0) as int;
        final itemName = data['name'] ?? '';

        if (currentStock > 0) {
          // Log the waste
          final logId = '${today}_$itemName';
          final logRef = _firestore
              .collection('Canteens')
              .doc(canteenId)
              .collection('DailyStockLogs')
              .doc(logId);

          batch.set(logRef, {
            'date': today,
            'inventoryItemId': doc.id,
            'inventoryItemName': itemName,
            'isPerishable': true,
            'stockWasted': currentStock,
            'endingStock': 0,
            'lastUpdated': FieldValue.serverTimestamp(),
            'autoReset': true,
          }, SetOptions(merge: true));

          // Reset stock to 0
          batch.update(doc.reference, {'stock': 0});
        }
      }

      await batch.commit();
      
      // Update the last reset date metadata so we don't auto-reset again today
      await _firestore
          .collection('Canteens')
          .doc(canteenId)
          .collection('Metadata')
          .doc('InventoryLogs')
          .set({
        'last_reset_date': today,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('✅ Auto-reset perishables completed for $today');
    } catch (e) {
      print('❌ Error auto-resetting perishables: $e');
    }
  }

  /// Helper to get today's date as string
  static String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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
      final batch = FirebaseFirestore.instance.batch();
      final today = EndOfDayService._getTodayDateString();

      for (var item in widget.perishables) {
        final inputWaste = int.tryParse(_controllers[item.id]!.text) ?? 0;
        final actualWaste = inputWaste;

        // Log the waste
        final logId = '${today}_${item.name}';
        final logRef = FirebaseFirestore.instance
            .collection('Canteens')
            .doc(EndOfDayService.canteenId)
            .collection('DailyStockLogs')
            .doc(logId);

        batch.set(logRef, {
          'date': today,
          'inventoryItemId': item.id,
          'inventoryItemName': item.name,
          'isPerishable': true,
          'stockWasted': actualWaste,
          'endingStock': 0,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Reset stock to 0
        final itemRef = FirebaseFirestore.instance
            .collection('Canteens')
            .doc(EndOfDayService.canteenId)
            .collection('Inventory')
            .doc(item.id);

        batch.update(itemRef, {'stock': 0});
      }

      await batch.commit();
      
      // Refresh inventory cache to trigger UI updates
      await InventoryService().refreshInventoryCache();

      // Update the last reset date metadata so auto-reset doesn't trigger today
      await FirebaseFirestore.instance
          .collection('Canteens')
          .doc(EndOfDayService.canteenId)
          .collection('Metadata')
          .doc('InventoryLogs')
          .set({
        'last_reset_date': today,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  'End of day completed successfully',
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
            content: Text('Error: $e'),
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
