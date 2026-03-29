import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';

class OptionSelectionBottomSheet extends StatefulWidget {
  final MenuObject menu;
  final List<OptionGroup> linkedGroups;

  const OptionSelectionBottomSheet({
    Key? key,
    required this.menu,
    required this.linkedGroups,
  }) : super(key: key);

  /// Shows the bottom sheet and returns the selected options, or null if cancelled.
  static Future<List<SelectedOption>?> show(
    BuildContext context, {
    required MenuObject menu,
    required List<OptionGroup> linkedGroups,
  }) {
    return showModalBottomSheet<List<SelectedOption>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OptionSelectionBottomSheet(
        menu: menu,
        linkedGroups: linkedGroups,
      ),
    );
  }

  @override
  State<OptionSelectionBottomSheet> createState() =>
      _OptionSelectionBottomSheetState();
}

class _OptionSelectionBottomSheetState
    extends State<OptionSelectionBottomSheet> {
  // groupId -> set of selected option names
  final Map<String, Set<String>> _selections = {};
  // Track validation errors per group
  final Map<String, String?> _errors = {};

  @override
  void initState() {
    super.initState();
    for (var group in widget.linkedGroups) {
      _selections[group.id] = {};
    }
  }

  int get _optionsTotal {
    int total = 0;
    for (var group in widget.linkedGroups) {
      final selected = _selections[group.id] ?? {};
      for (var option in group.options) {
        if (selected.contains(option.name)) {
          total += option.priceAdjustment;
        }
      }
    }
    return total;
  }

  int get _effectivePrice => widget.menu.harga + _optionsTotal;

  bool _validate() {
    bool valid = true;
    for (var group in widget.linkedGroups) {
      final selected = _selections[group.id] ?? {};
      if (group.isRequired && selected.isEmpty) {
        _errors[group.id] = 'Pilih minimal ${group.minSelection > 0 ? group.minSelection : 1} opsi';
        valid = false;
      } else if (group.minSelection > 0 && selected.length < group.minSelection) {
        _errors[group.id] = 'Pilih minimal ${group.minSelection} opsi';
        valid = false;
      } else {
        _errors[group.id] = null;
      }
    }
    return valid;
  }

  void _toggleOption(OptionGroup group, OptionItem option) {
    setState(() {
      final selected = _selections[group.id]!;
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
      _errors[group.id] = null;
    });
  }

  void _handleConfirm() {
    if (!_validate()) {
      setState(() {});
      return;
    }

    final result = <SelectedOption>[];
    for (var group in widget.linkedGroups) {
      final selected = _selections[group.id] ?? {};
      for (var option in group.options) {
        if (selected.contains(option.name)) {
          result.add(SelectedOption(
            groupId: group.id,
            optionId: option.id,
            groupName: group.name,
            optionName: option.name,
            priceAdjustment: option.priceAdjustment,
          ));
        }
      }
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
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
                children: widget.linkedGroups
                    .map((group) => _buildGroupSection(group))
                    .toList(),
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
            'Pilih opsi',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSection(OptionGroup group) {
    final selected = _selections[group.id] ?? {};
    final error = _errors[group.id];

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
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
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
                    fontSize: 11,
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
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.red),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.options.map((option) {
              final isSelected = selected.contains(option.name);
              return _buildOptionChip(option, isSelected, () {
                _toggleOption(group, option);
              });
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionChip(OptionItem option, bool isSelected, VoidCallback onTap) {
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
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (option.priceAdjustment < 0
                    ? const Color(0xFFE65100)
                    : const Color(0xFF2E7D32))
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
                    : Colors.black87,
              ),
            ),
            if (option.priceAdjustment != 0) ...[
              const SizedBox(width: 6),
              Text(
                option.formattedPrice,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: option.priceAdjustment < 0
                      ? const Color(0xFFE65100)
                      : Colors.grey.shade600,
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
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
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
                  'Rp ${NumberFormat.decimalPattern().format(_effectivePrice).replaceAll(',', '.')}',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
            const Spacer(),
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
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _handleConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Tambahkan',
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
}
