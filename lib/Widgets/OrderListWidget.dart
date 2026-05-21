import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';

class OrderListWidget extends StatelessWidget {
  final List<PesananObject> pesananList;
  final Function(int) onIncrementDineIn;
  final Function(int) onDecrementDineIn;
  final Function(int) onIncrementTakeAway;
  final Function(int) onDecrementTakeAway;
  final Function(int, String?) onNoteChanged;
  final Function(int) onRemoveItem;
  final Function(int) onEditOptions;
  final List<MenuObject> allMenus;
  final List<OptionGroup> allOptionGroups;

  const OrderListWidget({
    Key? key,
    required this.pesananList,
    required this.onIncrementDineIn,
    required this.onDecrementDineIn,
    required this.onIncrementTakeAway,
    required this.onDecrementTakeAway,
    required this.onNoteChanged,
    required this.onRemoveItem,
    required this.onEditOptions,
    this.allMenus = const [],
    this.allOptionGroups = const [],
  }) : super(key: key);

  Future<void> _showNoteDialog(
      BuildContext context, int index, String? currentNote) async {
    final controller = TextEditingController(text: currentNote ?? '');
    final result = await showDialog<dynamic>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(Icons.edit_note_rounded,
                  color: Colors.orange.shade700, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Catatan - ${pesananList[index].namaPesanan}',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Tulis permintaan khusus...',
              hintStyle: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade400),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          actions: [
            if (currentNote != null && currentNote.isNotEmpty)
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, '\x00'),
                icon:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: Text('Hapus',
                    style: GoogleFonts.poppins(color: Colors.redAccent)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'CANCEL'),
              child: Text('Batal',
                  style: GoogleFonts.poppins(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Simpan',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );

    if (result == 'CANCEL') return;

    if (result == '\x00') {
      onNoteChanged(index, null);
    } else {
      // If result is null (barrier dismissal), use the controller text
      final textToSave = (result is String ? result : controller.text).trim();
      onNoteChanged(index, textToSave.isEmpty ? null : textToSave);
    }
  }

  bool _hasOptions(PesananObject order) {
    return allOptionGroups.any((g) => g.linkedMenuItems.contains(order.menuItemId));
  }

  @override
  Widget build(BuildContext context) {
    // 1. Separate items into food and drinks while preserving original indices
    final foodItems = <MapEntry<int, PesananObject>>[];
    final drinkItems = <MapEntry<int, PesananObject>>[];

    for (int i = 0; i < pesananList.length; i++) {
      final order = pesananList[i];
      final menu = allMenus.firstWhere(
        (m) => m.id == order.menuItemId,
        orElse: () => MenuObject(id: '', namaMenu: '', harga: 0, isMakanan: true, imagePath: ''),
      );
      if (menu.isMakanan) {
        foodItems.add(MapEntry(i, order));
      } else {
        drinkItems.add(MapEntry(i, order));
      }
    }

    return ListView(
      children: [
        if (foodItems.isNotEmpty) ...[
          _buildCategoryHeader('MAKANAN'),
          ...foodItems.map((entry) => _buildOrderItem(context, entry.key, entry.value)).toList(),
        ],
        if (foodItems.isNotEmpty && drinkItems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Divider(
              color: Colors.grey.shade600,
              thickness: 1.5,
              indent: 12,
              endIndent: 12,
            ),
          ),
        if (drinkItems.isNotEmpty) ...[
          _buildCategoryHeader('MINUMAN'),
          ...drinkItems.map((entry) => _buildOrderItem(context, entry.key, entry.value)).toList(),
        ],
      ],
    );
  }

  Widget _buildCategoryHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade50,
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildOrderItem(BuildContext context, int index, PesananObject order) {
    final hasNote = order.customerNote != null && order.customerNote!.isNotEmpty;
    final isCustomizable = _hasOptions(order);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: isCustomizable ? () => onEditOptions(index) : null,
        child: Container(
          margin: const EdgeInsets.only(top: 4.0),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.shade300,
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Item name — tap to add note
              GestureDetector(
                onTap: () => _showNoteDialog(context, index, order.customerNote),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.namaPesanan,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Icon(
                      hasNote ? Icons.sticky_note_2 : Icons.note_add_outlined,
                      size: 18,
                      color: hasNote ? Colors.orange.shade700 : Colors.grey.shade400,
                    ),
                    const SizedBox(width: 8),
                    FutureBuilder<MenuAvailability>(
                      future: InventoryService().checkPesananAvailability(
                          order, allMenus, allOptionGroups),
                      builder: (context, snapshot) {
                        if (snapshot.hasData &&
                            (snapshot.data?.hasWarning ?? false)) {
                          return Tooltip(
                            message: snapshot.data?.message ?? 'Stok kurang',
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 20,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
              // Selected options
              if (order.selectedOptions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: order.selectedOptions.map((opt) {
                      final isDiscount = opt.priceAdjustment < 0;
                      final priceLabel = opt.priceAdjustment > 0
                          ? ' (+${NumberFormat.decimalPattern().format(opt.priceAdjustment).replaceAll(',', '.')})'
                          : opt.priceAdjustment < 0
                              ? ' (-${NumberFormat.decimalPattern().format(opt.priceAdjustment.abs()).replaceAll(',', '.')})'
                              : '';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDiscount
                              ? const Color(0xFFFFF3E0)
                              : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${opt.optionName}$priceLabel',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: isDiscount
                                ? const Color(0xFFE65100)
                                : const Color(0xFF2E7D32),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              // Customer note display — tap to edit
              if (hasNote)
                GestureDetector(
                  onTap: () => _showNoteDialog(context, index, order.customerNote),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_note_rounded,
                              size: 14, color: Colors.orange.shade700),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              order.customerNote!,
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // Two counters side by side
              Row(
                children: [
                  // Dine In Counter
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Dine In",
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => onDecrementDineIn(index),
                              icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: Colors.redAccent,
                                size: 24,
                              ),
                            ),
                            Text(
                              order.dineInQuantity.toString(),
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            IconButton(
                              onPressed: () => onIncrementDineIn(index),
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                                color: Colors.green,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Take Away Counter
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Take Away",
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => onDecrementTakeAway(index),
                              icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: Colors.redAccent,
                                size: 24,
                              ),
                            ),
                            Text(
                              order.takeAwayQuantity.toString(),
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            IconButton(
                              onPressed: () => onIncrementTakeAway(index),
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                                color: Colors.green,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Bottom row: Hapus button on left (if qty == 0) and subtotal price on right
              Padding(
                padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (order.totalQuantity == 0)
                      TextButton.icon(
                        onPressed: () => onRemoveItem(index),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                          size: 18,
                        ),
                        label: Text(
                          'Hapus',
                          style: GoogleFonts.poppins(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFFFEBEE), // Faint red background
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    Container(
                      color: Colors.grey.shade200,
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 5.0),
                      child: Text(
                        'Rp ${NumberFormat.decimalPattern().format(order.subtotal).replaceAll(',', '.')}',
                        style: GoogleFonts.notoSans(
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
