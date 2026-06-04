import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/EndOfDayService.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({Key? key}) : super(key: key);

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _inventoryService = InventoryService();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  /// inventoryItemId → list of display labels ("Menu: X", "Opsi: Y (Group)")
  Map<String, List<String>> _linkedItemsMap = {};

  static const _addGreen = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _buildLinkedItemsMap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _buildLinkedItemsMap() async {
    final map = <String, List<String>>{};

    try {
      final menuSnap = await FirebaseFirestore.instance
          .collection(Col.name('Canteens'))
          .doc('canteen375')
          .collection('MenuCollection')
          .get();
      final menus = MenuClass.getAllMenus(menuSnap);

      for (final menu in menus) {
        for (final ing in menu.ingredients) {
          map.putIfAbsent(ing.inventoryItemId, () => []).add(menu.namaMenu);
        }
      }

      final optionGroups =
          await OptionGroupService().getOptionGroupsStream().first;

      for (final group in optionGroups) {
        for (final opt in group.options) {
          for (final ing in opt.ingredients) {
            map
                .putIfAbsent(ing.inventoryItemId, () => [])
                .add('${opt.name} (${group.name})');
          }
        }
      }
    } catch (e) {
      // Non-critical; cards just won't show linked items
    }

    if (mounted) {
      setState(() => _linkedItemsMap = map);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = value.trim().toLowerCase();
      });
    });
  }

  List<InventoryItem> _applySearch(List<InventoryItem> items) {
    List<InventoryItem> filtered = items;
    if (_searchQuery.isNotEmpty) {
      filtered = items
          .where((item) => item.name.toLowerCase().contains(_searchQuery))
          .toList();
    }
    
    // Sort items alphabetically by name
    filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return filtered;
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          // Search bar (now flex 5 and first)
          Expanded(
            flex: 5,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Cari...',
                hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _debounce?.cancel();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _addGreen, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Add button (now flex 1 and second)
          Expanded(
            flex: 1,
            child: FilledButton.icon(
              onPressed: _showAddInventoryDialog,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: Text(
                'Tambah',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _addGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Manajemen Stok Bahan',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A)),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.nightlight_round),
            onPressed: () => EndOfDayService.showEndOfDayDialog(context),
            tooltip: 'Operasional Selesai (EndOfDay)',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddInventoryDialog,
            tooltip: 'Tambah Bahan Baru',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _inventoryService.refreshInventoryCache();
              },
              child: StreamBuilder<List<InventoryItem>>(
                stream: _inventoryService.getInventoryStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: Center(child: Text('Error: ${snapshot.error}')),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allItems = snapshot.data ?? [];

                  if (allItems.isEmpty) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'Belum ada bahan',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _showAddInventoryDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Tambah Bahan'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _addGreen,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final items = _applySearch(allItems);

                  if (items.isEmpty) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 60, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'Tidak ditemukan "$_searchQuery"',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 20, 24),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _buildStockCard(item);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockCard(InventoryItem item) {
    final linked = _linkedItemsMap[item.id] ?? [];

    return GestureDetector(
      onTap: () => _showSetStockDialog(item),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 22, 14),
          child: Row(
            children: [
              // Icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: item.stock <= 0
                      ? Colors.red.shade100
                      : item.stock <= 10
                          ? Colors.orange.shade100
                          : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.inventory_2,
                  size: 32,
                  color: item.stock <= 0
                      ? Colors.red
                      : item.stock <= 10
                          ? Colors.orange
                          : Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              // Name, unit, and linked items
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.isPerishable) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border:
                                  Border.all(color: Colors.orange.shade300),
                            ),
                            child: Text(
                              'PERISHABLE',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      'Unit: ${item.unit}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (linked.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: linked.map((label) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.link_rounded,
                                      size: 12, color: Colors.blue.shade600),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      label,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.blue.shade800,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit_outlined,
                        color: Colors.grey.shade600, size: 22),
                    onPressed: () => _showEditInventoryDialog(item),
                    tooltip: 'Edit bahan',
                    splashRadius: 22,
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item.stock}',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color:
                                item.stock <= 0 ? Colors.red : Colors.black,
                          ),
                        ),
                        Text(
                          item.unit,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSetStockDialog(InventoryItem item) async {
    final controller = TextEditingController(text: item.stock.toString());
    int currentStock = item.stock;
    int newStock = item.stock;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tetapkan Stok', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 20)),
              Text(item.name, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
            ],
          ),
          content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Stok saat ini',
                          style: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$currentStock ${item.unit}',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Stok baru', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                    autofocus: true,
                    style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    onChanged: (value) {
                      setDialogState(() {
                        newStock = int.tryParse(value) ?? 0;
                      });
                    },
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.orange.shade300, width: 2)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.orange.shade300, width: 2)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (newStock != currentStock)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: newStock > currentStock ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${newStock > currentStock ? "+" : ""}${newStock - currentStock} ${item.unit}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: newStock > currentStock ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ),
                ],
              ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ElevatedButton(
                onPressed: () async {
                  await _inventoryService.updateInventoryStock(item.id, newStock);
                  if (context.mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Perbarui Stok', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddInventoryDialog() async {
    final nameController = TextEditingController();
    final stockController = TextEditingController(text: '0');
    final unitController = TextEditingController(text: 'pcs');
    bool isPerishable = false;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Tambah Bahan Baru', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Bahan',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stockController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Stok Awal',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit (contoh: pcs, kg, liter)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: Text('Mudah Rusak', style: GoogleFonts.poppins()),
                  subtitle: Text('Stok akan reset ke 0 setiap hari', style: GoogleFonts.poppins(fontSize: 12)),
                  value: isPerishable,
                  onChanged: (value) {
                    setDialogState(() {
                      isPerishable = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Nama bahan tidak boleh kosong')),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      try {
                        await _inventoryService.addInventoryItem(
                          nameController.text,
                          int.tryParse(stockController.text) ?? 0,
                          unitController.text,
                          isPerishable: isPerishable,
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                          setDialogState(() => isSaving = false);
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Tambah'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditInventoryDialog(InventoryItem item) async {
    final nameController = TextEditingController(text: item.name);
    final unitController = TextEditingController(text: item.unit);
    final stockController = TextEditingController(text: item.stock.toString());
    bool isPerishable = item.isPerishable;
    bool isSaving = false;

    // --- Linking state ---
    // menuId → quantity (0 = not linked)
    final menuLinks = <String, int>{};
    // "groupId::optionId" → quantity
    final optionLinks = <String, int>{};

    List<MenuObject> allMenus = [];
    List<OptionGroup> allOptionGroups = [];
    bool isLoadingLinks = true;

    // Pre-fetch menus & option groups, populate current links
    Future<void> loadLinks(void Function(void Function()) setState) async {
      try {
        final menuSnap = await FirebaseFirestore.instance
            .collection(Col.name('Canteens'))
            .doc('canteen375')
            .collection('MenuCollection')
            .get();
        allMenus = MenuClass.getAllMenus(menuSnap);
        allOptionGroups =
            await OptionGroupService().getOptionGroupsStream().first;

        for (final menu in allMenus) {
          final ing = menu.ingredients.where(
            (i) => i.inventoryItemId == item.id,
          );
          menuLinks[menu.id] = ing.isNotEmpty ? ing.first.quantityNeeded : 0;
        }

        for (final group in allOptionGroups) {
          for (final opt in group.options) {
            final key = '${group.id}::${opt.id}';
            final ing = opt.ingredients.where(
              (i) => i.inventoryItemId == item.id,
            );
            optionLinks[key] =
                ing.isNotEmpty ? ing.first.quantityNeeded : 0;
          }
        }
      } catch (_) {}
      setState(() => isLoadingLinks = false);
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isLoadingLinks) {
            loadLinks(setDialogState);
          }
          return AlertDialog(
            title: Text('Edit Info Bahan',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nama Bahan',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stockController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Stok',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: unitController,
                      decoration: const InputDecoration(
                        labelText: 'Unit (contoh: pcs, kg, liter)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: Text('Mudah Rusak',
                          style: GoogleFonts.poppins()),
                      subtitle: Text(
                          'Stok akan reset ke 0 setiap hari',
                          style: GoogleFonts.poppins(fontSize: 12)),
                      value: isPerishable,
                      onChanged: (value) {
                        setDialogState(() {
                          isPerishable = value ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),

                    // --- Linked items section ---
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text('Hubungkan ke Menu',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (isLoadingLinks)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2)),
                      )
                    else ...[
                      ...allMenus.map((menu) {
                        final qty = menuLinks[menu.id] ?? 0;
                        final isLinked = qty > 0;
                        return _linkRow(
                          label: menu.namaMenu,
                          isLinked: isLinked,
                          qty: qty,
                          onToggle: (val) {
                            setDialogState(() {
                              menuLinks[menu.id] = val ? 1 : 0;
                            });
                          },
                          onQtyChanged: (val) {
                            setDialogState(() {
                              menuLinks[menu.id] = val;
                            });
                          },
                        );
                      }),
                      if (allOptionGroups
                          .any((g) => g.options.isNotEmpty)) ...[
                        const SizedBox(height: 12),
                        Text('Hubungkan ke Opsi',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        ...allOptionGroups.expand((group) {
                          return group.options.map((opt) {
                            final key = '${group.id}::${opt.id}';
                            final qty = optionLinks[key] ?? 0;
                            final isLinked = qty > 0;
                            return _linkRow(
                              label: '${opt.name} (${group.name})',
                              isLinked: isLinked,
                              qty: qty,
                              onToggle: (val) {
                                setDialogState(() {
                                  optionLinks[key] = val ? 1 : 0;
                                });
                              },
                              onQtyChanged: (val) {
                                setDialogState(() {
                                  optionLinks[key] = val;
                                });
                              },
                            );
                          });
                        }),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              Row(
                children: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () {
                            Navigator.pop(context);
                            _showDeleteConfirmation(item);
                          },
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.red),
                    child: const Text('Hapus'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed:
                        isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (nameController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Nama bahan tidak boleh kosong')),
                              );
                              return;
                            }

                            setDialogState(() => isSaving = true);
                            try {
                              await _inventoryService.updateInventoryItem(
                                item.id,
                                nameController.text,
                                unitController.text,
                                isPerishable,
                              );

                              final newStock =
                                  int.tryParse(stockController.text) ??
                                      item.stock;
                              if (newStock != item.stock) {
                                await _inventoryService
                                    .updateInventoryStock(
                                        item.id, newStock);
                              }

                              // Persist link changes
                              await _saveLinks(
                                item,
                                nameController.text,
                                allMenus,
                                allOptionGroups,
                                menuLinks,
                                optionLinks,
                              );

                              await _buildLinkedItemsMap();

                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  SnackBar(
                                      content: Text('Error: $e')),
                                );
                                setDialogState(
                                    () => isSaving = false);
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Text('Simpan'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _linkRow({
    required String label,
    required bool isLinked,
    required int qty,
    required ValueChanged<bool> onToggle,
    required ValueChanged<int> onQtyChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: isLinked,
              onChanged: (val) => onToggle(val ?? false),
              visualDensity: VisualDensity.compact,
              activeColor: _addGreen,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isLinked)
            SizedBox(
              width: 60,
              height: 32,
              child: TextField(
                controller: TextEditingController(text: '$qty'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 13),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6)),
                  isDense: true,
                ),
                onChanged: (val) {
                  final parsed = int.tryParse(val);
                  if (parsed != null && parsed > 0) onQtyChanged(parsed);
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveLinks(
    InventoryItem item,
    String currentName,
    List<MenuObject> allMenus,
    List<OptionGroup> allOptionGroups,
    Map<String, int> menuLinks,
    Map<String, int> optionLinks,
  ) async {
    final fs = FirebaseFirestore.instance;
    final batch = fs.batch();
    final menuCol = fs
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('MenuCollection');

    for (final menu in allMenus) {
      final desiredQty = menuLinks[menu.id] ?? 0;
      final existingIdx = menu.ingredients
          .indexWhere((i) => i.inventoryItemId == item.id);
      final wasLinked = existingIdx != -1;
      final shouldBeLinked = desiredQty > 0;

      if (!wasLinked && !shouldBeLinked) continue;

      final updatedIngredients =
          List<MenuIngredient>.from(menu.ingredients);

      if (shouldBeLinked && !wasLinked) {
        updatedIngredients.add(MenuIngredient(
          inventoryItemId: item.id,
          inventoryItemName: currentName,
          quantityNeeded: desiredQty,
        ));
      } else if (shouldBeLinked && wasLinked) {
        updatedIngredients[existingIdx] = MenuIngredient(
          inventoryItemId: item.id,
          inventoryItemName: currentName,
          quantityNeeded: desiredQty,
        );
      } else {
        updatedIngredients.removeAt(existingIdx);
      }

      batch.update(menuCol.doc(menu.id), {
        'ingredients':
            updatedIngredients.map((i) => i.toMap()).toList(),
      });
    }

    // Option groups: rebuild options list per group
    final affectedGroups = <String, OptionGroup>{};

    for (final group in allOptionGroups) {
      bool changed = false;
      final updatedOptions = group.options.map((opt) {
        final key = '${group.id}::${opt.id}';
        final desiredQty = optionLinks[key] ?? 0;
        final existingIdx = opt.ingredients
            .indexWhere((i) => i.inventoryItemId == item.id);
        final wasLinked = existingIdx != -1;
        final shouldBeLinked = desiredQty > 0;

        if (!wasLinked && !shouldBeLinked) return opt;

        changed = true;
        final updatedIngredients =
            List<MenuIngredient>.from(opt.ingredients);

        if (shouldBeLinked && !wasLinked) {
          updatedIngredients.add(MenuIngredient(
            inventoryItemId: item.id,
            inventoryItemName: currentName,
            quantityNeeded: desiredQty,
          ));
        } else if (shouldBeLinked && wasLinked) {
          updatedIngredients[existingIdx] = MenuIngredient(
            inventoryItemId: item.id,
            inventoryItemName: currentName,
            quantityNeeded: desiredQty,
          );
        } else {
          updatedIngredients.removeAt(existingIdx);
        }

        return OptionItem(
          id: opt.id,
          name: opt.name,
          priceAdjustment: opt.priceAdjustment,
          ingredients: updatedIngredients,
        );
      }).toList();

      if (changed) {
        affectedGroups[group.id] = OptionGroup(
          id: group.id,
          name: group.name,
          isRequired: group.isRequired,
          minSelection: group.minSelection,
          maxSelection: group.maxSelection,
          options: updatedOptions,
          linkedMenuItems: group.linkedMenuItems,
        );
      }
    }

    for (final group in affectedGroups.values) {
      await OptionGroupService().updateOptionGroup(group);
    }

    await batch.commit();
  }

  Future<void> _showDeleteConfirmation(InventoryItem item) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus Bahan?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text('Apakah Anda yakin ingin menghapus ${item.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _inventoryService.deleteInventoryItem(item.id);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}
