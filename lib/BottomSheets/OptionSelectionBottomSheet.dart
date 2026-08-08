import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';

class OptionSelectionBottomSheet extends StatefulWidget {
  final MenuObject menu;
  final List<OptionGroup> linkedGroups;
  final List<SelectedOption>? initialOptions;
  final int? initialQuantity;

  const OptionSelectionBottomSheet({
    Key? key,
    required this.menu,
    required this.linkedGroups,
    this.initialOptions,
    this.initialQuantity,
  }) : super(key: key);

  /// Shows the bottom sheet and returns the selected options per group with their quantity, or null if cancelled.
  static Future<List<({List<SelectedOption> options, int quantity})>?> show(
    BuildContext context, {
    required MenuObject menu,
    required List<OptionGroup> linkedGroups,
    List<SelectedOption>? initialOptions,
    int? initialQuantity,
  }) {
    return showModalBottomSheet<
        List<({List<SelectedOption> options, int quantity})>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OptionSelectionBottomSheet(
        menu: menu,
        linkedGroups: linkedGroups,
        initialOptions: initialOptions,
        initialQuantity: initialQuantity,
      ),
    );
  }

  @override
  State<OptionSelectionBottomSheet> createState() =>
      _OptionSelectionBottomSheetState();
}

class _OptionSelectionBottomSheetState
    extends State<OptionSelectionBottomSheet> {
  final List<_GroupConfig> _groups = [];

  bool get isEditMode =>
      widget.initialOptions != null || widget.initialQuantity != null;

  @override
  void initState() {
    super.initState();
    final config = _GroupConfig(widget.linkedGroups);
    if (widget.initialOptions != null) {
      for (var selectedOpt in widget.initialOptions!) {
        final groupSelections = config.selections[selectedOpt.groupId];
        if (groupSelections != null) {
          groupSelections.add(selectedOpt.optionName);
        }
      }
    }
    if (widget.initialQuantity != null) {
      config.quantity = widget.initialQuantity!;
    }
    _groups.add(config);
  }

  int get _totalPrice {
    int total = 0;
    for (var groupConfig in _groups) {
      int optionsTotal = 0;
      for (var group in widget.linkedGroups) {
        final selected = groupConfig.selections[group.id] ?? {};
        for (var option in group.options) {
          if (selected.contains(option.name)) {
            optionsTotal += option.priceAdjustment;
          }
        }
      }
      total += (widget.menu.harga + optionsTotal) * groupConfig.quantity;
    }
    return total;
  }

  int get _quantity {
    return _groups.fold(0, (sum, group) => sum + group.quantity);
  }

  bool _validate() {
    bool allValid = true;
    for (var i = 0; i < _groups.length; i++) {
      final groupConfig = _groups[i];
      for (var group in widget.linkedGroups) {
        final selected = groupConfig.selections[group.id] ?? {};
        if (group.isRequired && selected.isEmpty) {
          groupConfig.errors[group.id] =
              'Pilih minimal ${group.minSelection > 0 ? group.minSelection : 1} opsi';
          allValid = false;
        } else if (group.minSelection > 0 &&
            selected.length < group.minSelection) {
          groupConfig.errors[group.id] =
              'Pilih minimal ${group.minSelection} opsi';
          allValid = false;
        } else {
          groupConfig.errors[group.id] = null;
        }
      }
    }
    return allValid;
  }

  void _toggleOption(int index, OptionGroup group, OptionItem option) {
    final groupConfig = _groups[index];
    final bool isSelected =
        (groupConfig.selections[group.id] ?? {}).contains(option.name);

    // If selecting (not deselecting), check stock for a warning
    if (!isSelected) {
      final maxServings = InventoryService().getMaxServings(option.ingredients);
      if (maxServings != null && maxServings <= 0) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                  'Peringatan: Stok "${option.name}" habis, tapi tetap bisa ditambahkan.'),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }

    setState(() {
      final selected = groupConfig.selections[group.id]!;
      if (selected.contains(option.name)) {
        selected.remove(option.name);
      } else {
        // Enforce maxSelection
        if (group.maxSelection > 0 && selected.length >= group.maxSelection) {
          // If max is 1, replace selection (radio behavior)
          if (group.maxSelection == 1) {
            selected.clear();
            selected.add(option.name);
          }
          return;
        }
        selected.add(option.name);
      }
      groupConfig.errors[group.id] = null;
    });
  }

  void _handleConfirm() {
    if (!_validate()) {
      setState(() {});
      return;
    }

    final results = <({List<SelectedOption> options, int quantity})>[];
    for (var groupConfig in _groups) {
      final groupResults = <SelectedOption>[];
      for (var group in widget.linkedGroups) {
        final selected = groupConfig.selections[group.id] ?? {};
        for (var option in group.options) {
          if (selected.contains(option.name)) {
            groupResults.add(SelectedOption(
              groupId: group.id,
              optionId: option.id,
              groupName: group.name,
              optionName: option.name,
              priceAdjustment: option.priceAdjustment,
            ));
          }
        }
      }
      results.add((options: groupResults, quantity: groupConfig.quantity));
    }
    Navigator.pop(context, results);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...List.generate(
                      _groups.length, (index) => _buildGroupCard(index)),
                  if (!isEditMode) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _groups.add(_GroupConfig(widget.linkedGroups));
                          });
                        },
                        icon: const Icon(Icons.add, color: Color(0xFF2E7D32)),
                        label: Text(
                          '+ Tambahkan Variasi Lain',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(
                              color: Color(0xFF2E7D32), width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.menu.namaMenu,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rp ${NumberFormat.decimalPattern().format(widget.menu.harga).replaceAll(',', '.')}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF2E7D32),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            isEditMode ? 'Ubah opsi' : 'Pilih opsi',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(int index) {
    final groupConfig = _groups[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                const Icon(Icons.widgets_outlined,
                    size: 18, color: Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                Text(
                  'Kombinasi #${index + 1}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                if (_groups.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                    onPressed: () {
                      setState(() {
                        _groups.removeAt(index);
                      });
                    },
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          // Option selection list
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...widget.linkedGroups
                    .map((group) =>
                        _buildGroupSection(groupConfig, group, index))
                    .toList(),
                const Divider(height: 24),
                // Local quantity controls inside each card
                Row(
                  children: [
                    Text(
                      'Jumlah untuk kombinasi ini:',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildQtyButton(
                            icon: Icons.remove,
                            onTap: groupConfig.quantity > 1
                                ? () => setState(() => groupConfig.quantity--)
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '${groupConfig.quantity}',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _buildQtyButton(
                            icon: Icons.add,
                            onTap: () => setState(() => groupConfig.quantity++),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSection(
      _GroupConfig groupConfig, OptionGroup group, int index) {
    final selected = groupConfig.selections[group.id] ?? {};
    final error = groupConfig.errors[group.id];

    String subtitle = group.isRequired ? 'Wajib' : 'Opsional';
    if (group.maxSelection == 1) {
      subtitle += ' • Pilih 1';
    } else if (group.maxSelection > 1) {
      subtitle += ' • Maks ${group.maxSelection}';
    }
    if (group.minSelection > 1) {
      subtitle += ' • Min ${group.minSelection}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                group.name,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: group.isRequired
                      ? const Color(0xFFE8F5E9)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: group.isRequired
                        ? const Color(0xFF2E7D32)
                        : Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error,
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.red),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.options.map((option) {
              final isSelected = selected.contains(option.name);
              final maxServings =
                  InventoryService().getMaxServings(option.ingredients);
              return _buildOptionChip(option, isSelected, maxServings, () {
                _toggleOption(index, group, option);
              });
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChip(OptionItem option, bool isSelected, int? maxServings,
      VoidCallback onTap) {
    final bool hasStock = maxServings != null;
    final bool outOfStock = hasStock && maxServings <= 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (option.priceAdjustment < 0
                  ? const Color(0xFFFFF3E0)
                  : const Color(0xFFE8F5E9))
              : outOfStock
                  ? Colors.grey.shade100
                  : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (option.priceAdjustment < 0
                    ? const Color(0xFFE65100)
                    : const Color(0xFF2E7D32))
                : outOfStock
                    ? Colors.grey.shade300
                    : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.check_circle,
                  size: 16,
                  color: option.priceAdjustment < 0
                      ? const Color(0xFFE65100)
                      : const Color(0xFF2E7D32),
                ),
              ),
            Text(
              option.name,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? (option.priceAdjustment < 0
                        ? const Color(0xFFE65100)
                        : const Color(0xFF2E7D32))
                    : outOfStock
                        ? Colors.grey.shade400
                        : Colors.black87,
              ),
            ),
            if (option.priceAdjustment != 0) ...[
              const SizedBox(width: 6),
              Text(
                option.formattedPrice,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: isSelected
                      ? (option.priceAdjustment < 0
                          ? const Color(0xFFE65100).withValues(alpha: 0.8)
                          : const Color(0xFF2E7D32).withValues(alpha: 0.8))
                      : outOfStock
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                ),
              ),
            ],
            if (hasStock) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: outOfStock
                      ? Colors.red.shade50
                      : maxServings <= 5
                          ? Colors.orange.shade50
                          : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  outOfStock ? 'Habis (0)' : '$maxServings',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: outOfStock
                        ? Colors.red
                        : maxServings <= 5
                            ? Colors.orange.shade800
                            : Colors.green.shade800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            // Left: Total
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Total',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  'Rp ${NumberFormat.decimalPattern().format(_totalPrice).replaceAll(',', '.')}',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2E7D32),
                  ),
                ),
                Text(
                  '$_quantity Item',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Right: Batal + Tambahkan
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Batal',
                style: GoogleFonts.poppins(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _handleConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                isEditMode ? 'Simpan Perubahan' : 'Tambahkan',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQtyButton({required IconData icon, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? Colors.grey.shade300 : const Color(0xFF2E7D32),
        ),
      ),
    );
  }
}

class _GroupConfig {
  // groupId -> set of selected option names
  final Map<String, Set<String>> selections = {};
  // Track validation errors per group for this combination
  final Map<String, String?> errors = {};
  int quantity = 1;

  _GroupConfig(List<OptionGroup> groups) {
    for (var group in groups) {
      selections[group.id] = {};
      errors[group.id] = null;
    }
  }
}
