import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Screens/InventoryScreen.dart';
import 'package:point_of_sales_app_v3/Services/ShoppingService.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({Key? key}) : super(key: key);

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Warm the inventory cache so displayName() resolves linked names everywhere
    // (supplier rows, order rows, correction dialogs, shared PDFs).
    InventoryService().refreshInventoryCache().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Belanja',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A)),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF1A1A1A),
              unselectedLabelColor: Colors.grey.shade500,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                border: Border(
                  bottom: BorderSide(
                    color: Color(0xFF2E7D32),
                    width: 3,
                  ),
                ),
              ),
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.normal, fontSize: 14),
              tabs: const [
                Tab(text: 'Daftar Supplier'),
                Tab(text: 'Pesanan Belanja'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          SuppliersView(),
          ShoppingOrdersView(),
        ],
      ),
    );
  }
}

class SuppliersView extends StatefulWidget {
  const SuppliersView({Key? key}) : super(key: key);

  @override
  State<SuppliersView> createState() => _SuppliersViewState();
}

class _SuppliersViewState extends State<SuppliersView> {
  String? _selectedSupplierId;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    final inventoryService = InventoryService();
    if (inventoryService.allInventoryItems.isEmpty) {
      await inventoryService.refreshInventoryCache();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Pane: Suppliers
          SizedBox(
            width: 280,
            child: _buildSuppliersPane(),
          ),
          const SizedBox(width: 16),
          // Right Pane: Items
          Expanded(child: _buildItemsPane()),
        ],
      ),
    );
  }

  Widget _buildSuppliersPane() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSearchBar(),
          _buildSuppliersHeader(),
          Expanded(child: _buildSuppliersList()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Cari nama barang...',
          hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildSuppliersHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            'SUPPLIERS',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade600, size: 20),
            onSelected: (value) {
              if (value == 'add') {
                _showAddSupplierDialog(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    Icon(Icons.add, size: 20),
                    SizedBox(width: 8),
                    Text('Tambah Supplier'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuppliersList() {
    return StreamBuilder<List<Supplier>>(
      stream: ShoppingService.getSuppliersStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final suppliers = snapshot.data ?? [];
        if (suppliers.isEmpty) {
          return Center(
            child: Text('Belum ada supplier.', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: suppliers.length,
          itemBuilder: (context, index) {
            final supplier = suppliers[index];
            final isSelected = _selectedSupplierId == supplier.id;

            return InkWell(
              onTap: () => setState(() => _selectedSupplierId = supplier.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFE8F5E9) : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                      color: isSelected ? const Color(0xFF2E7D32) : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        supplier.name,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected ? const Color(0xFF1B5E20) : Colors.black87,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${supplier.items.length}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildItemsPane() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _selectedSupplierId == null
          ? _buildNoSupplierSelected()
          : _buildSupplierDetails(),
    );
  }

  Widget _buildNoSupplierSelected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Pilih supplier untuk melihat item',
            style: GoogleFonts.poppins(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierDetails() {
    return StreamBuilder<List<Supplier>>(
      stream: ShoppingService.getSuppliersStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final suppliers = snapshot.data!;
        final supplier = suppliers.firstWhere(
          (s) => s.id == _selectedSupplierId,
          orElse: () => Supplier(id: '', name: '', items: []),
        );

        if (supplier.id.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedSupplierId != null) {
              setState(() => _selectedSupplierId = null);
            }
          });
          return const SizedBox.shrink();
        }

        List<SupplierItem> items = supplier.items;
        if (_searchQuery.isNotEmpty) {
          items = items.where((item) => item.name.toLowerCase().contains(_searchQuery)).toList();
        }

        return Column(
          children: [
            _buildItemsHeader(supplier),
            Expanded(child: _buildItemsList(supplier, items)),
          ],
        );
      },
    );
  }

  Widget _buildItemsHeader(Supplier supplier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            'ITEMS - ${supplier.name.toUpperCase()}',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade600, size: 20),
            onSelected: (value) {
              if (value == 'add_item') {
                _showAddOrEditItemDialog(context, supplier);
              } else if (value == 'edit_supplier') {
                _showEditSupplierNameDialog(context, supplier);
              } else if (value == 'delete_supplier') {
                _confirmDeleteSupplier(context, supplier);
              } else if (value == 'create_order') {
                _showCreateOrderDialog(context, supplier);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add_item',
                child: Row(children: [Icon(Icons.add_box, size: 20), SizedBox(width: 8), Text('Tambah Barang')]),
              ),
              const PopupMenuItem(
                value: 'create_order',
                child: Row(children: [Icon(Icons.shopping_cart, size: 20), SizedBox(width: 8), Text('Buat Pesanan')]),
              ),
              const PopupMenuItem(
                value: 'edit_supplier',
                child: Row(children: [Icon(Icons.edit, size: 20), SizedBox(width: 8), Text('Edit Nama Supplier')]),
              ),
              PopupMenuItem(
                value: 'delete_supplier',
                child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red), SizedBox(width: 8), Text('Hapus Supplier', style: TextStyle(color: Colors.red))]),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildItemsList(Supplier supplier, List<SupplierItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty ? 'Barang tidak ditemukan' : 'Belum ada barang di supplier ini',
              style: GoogleFonts.poppins(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildItemCard(supplier, item);
      },
    );
  }

  Widget _buildItemCard(Supplier supplier, SupplierItem item) {
    final originalIndex = supplier.items.indexOf(item);
    final inventoryService = InventoryService();
    int currentStock = 0;
    if (item.inventoryItemId != null && item.inventoryItemId!.isNotEmpty) {
      currentStock = inventoryService.allInventoryItems[item.inventoryItemId]?.stock ?? 0;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2, color: Color(0xFF2E7D32)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ShoppingService.displayName(item.inventoryItemId, item.name),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Unit: ${item.unit} • Stok: $currentStock',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (item.isPerishable)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Perishable',
                          style: GoogleFonts.poppins(fontSize: 10, color: Colors.deepOrange),
                        ),
                      ),
                    if (item.inventoryItemId != null && item.inventoryItemId!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.link, size: 12, color: Colors.green.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Linked to Inventory',
                              style: GoogleFonts.poppins(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _showAddOrEditItemDialog(context, supplier, editItem: item, itemIndex: originalIndex),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2E7D32),
              side: const BorderSide(color: Color(0xFF2E7D32)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Edit'),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.close, color: Colors.red.shade400),
            tooltip: 'Hapus',
            onPressed: () {
              List<SupplierItem> updatedItems = List.from(supplier.items);
              updatedItems.removeAt(originalIndex);
              ShoppingService.updateSupplier(supplier.id, supplier.name, updatedItems);
            },
          ),
        ],
      ),
    );
  }

  void _showAddSupplierDialog(BuildContext context) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tambah Supplier', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nama Supplier', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await ShoppingService.addSupplier(nameController.text, []);
                if (context.mounted) Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showEditSupplierNameDialog(BuildContext context, Supplier supplier) {
    final nameController = TextEditingController(text: supplier.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Nama Supplier', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nama Supplier', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await ShoppingService.updateSupplier(supplier.id, nameController.text, supplier.items);
                if (context.mounted) Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSupplier(BuildContext context, Supplier supplier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus Supplier', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text('Apakah Anda yakin ingin menghapus supplier ${supplier.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              await ShoppingService.deleteSupplier(supplier.id);
              if (mounted) {
                setState(() => _selectedSupplierId = null);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddOrEditItemDialog(BuildContext context, Supplier supplier, {SupplierItem? editItem, int? itemIndex}) async {
    final service = InventoryService();
    if (service.allInventoryItems.isEmpty) {
      await service.refreshInventoryCache();
    }
    if (!context.mounted) return;

    final inventoryItems = service.allInventoryItems.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (inventoryItems.isEmpty) {
      _showGoToInventoryDialog(
        context,
        'Belum ada bahan di Inventory. Silakan daftarkan bahan terlebih dahulu sebelum menambahkannya ke supplier.',
      );
      return;
    }

    // Exclude items already linked to this supplier (except the one being edited)
    final existingLinkedIds = <String>{};
    for (int i = 0; i < supplier.items.length; i++) {
      if (i == itemIndex) continue;
      final id = supplier.items[i].inventoryItemId;
      if (id != null && id.isNotEmpty) existingLinkedIds.add(id);
    }
    final availableItems = inventoryItems
        .where((inv) => !existingLinkedIds.contains(inv.id))
        .toList();

    InventoryItem? selected;
    if (editItem?.inventoryItemId != null) {
      for (final inv in inventoryItems) {
        if (inv.id == editItem!.inventoryItemId) {
          selected = inv;
          break;
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: Text(
              editItem == null ? 'Tambah Barang dari Inventory' : 'Ganti Barang dari Inventory',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pilih bahan yang sudah terdaftar di Inventory.',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Autocomplete<InventoryItem>(
                    initialValue: selected != null
                        ? TextEditingValue(text: selected!.name)
                        : const TextEditingValue(),
                    optionsBuilder: (TextEditingValue value) {
                      final q = value.text.toLowerCase().trim();
                      if (q.isEmpty) return availableItems;
                      return availableItems
                          .where((inv) => inv.name.toLowerCase().contains(q));
                    },
                    displayStringForOption: (inv) => inv.name,
                    onSelected: (inv) => setDialogState(() => selected = inv),
                    fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Cari bahan...',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    controller.clear();
                                    setDialogState(() => selected = null);
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                    optionsViewBuilder: (ctx, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 400),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: options.length,
                              itemBuilder: (c, i) {
                                final inv = options.elementAt(i);
                                return ListTile(
                                  dense: true,
                                  title: Text(inv.name),
                                  subtitle: Text('Unit: ${inv.unit}${inv.isPerishable ? " • Perishable" : ""}'),
                                  onTap: () => onSelected(inv),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (selected != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                selected!.name,
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Text('Unit: ${selected!.unit}', style: GoogleFonts.poppins(fontSize: 12)),
                          if (selected!.isPerishable)
                            Text('Perishable', style: GoogleFonts.poppins(fontSize: 12, color: Colors.deepOrange)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Bahan belum ada di Inventory?',
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const InventoryScreen()),
                          );
                        },
                        icon: const Icon(Icons.add_circle_outline, size: 16),
                        label: const Text('Daftarkan'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
              ElevatedButton(
                onPressed: selected == null
                    ? null
                    : () async {
                        final inv = selected!;
                        final updatedItems = List<SupplierItem>.from(supplier.items);
                        final newItem = SupplierItem(
                          name: inv.name,
                          unit: inv.unit.isEmpty ? 'pcs' : inv.unit,
                          isPerishable: inv.isPerishable,
                          inventoryItemId: inv.id,
                        );

                        if (editItem == null) {
                          updatedItems.add(newItem);
                        } else if (itemIndex != null) {
                          updatedItems[itemIndex] = newItem;
                        }

                        await ShoppingService.updateSupplier(
                            supplier.id, supplier.name, updatedItems);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white),
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showGoToInventoryDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Inventory Kosong', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(message, style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InventoryScreen()),
              );
            },
            icon: const Icon(Icons.inventory_2),
            label: const Text('Ke Inventory'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateOrderDialog(BuildContext context, Supplier supplier) async {
    if (supplier.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier tidak mempunyai barang.')));
      return;
    }

    final inventoryService = InventoryService();
    if (inventoryService.allInventoryItems.isEmpty) {
      await inventoryService.refreshInventoryCache();
    }
    if (!context.mounted) return;

    final Map<int, TextEditingController> controllers = {};
    for (int i = 0; i < supplier.items.length; i++) {
      controllers[i] = TextEditingController(text: '0');
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Buat Pesanan ke ${supplier.name}', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Masukkan jumlah yang akan dipesan. Angka 0 tidak akan dimasukkan ke order.', style: GoogleFonts.poppins(fontSize: 12)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: supplier.items.length,
                  itemBuilder: (context, index) {
                    final item = supplier.items[index];
                    int currentStock = 0;
                    if (item.inventoryItemId != null && item.inventoryItemId!.isNotEmpty) {
                      currentStock = inventoryService.allInventoryItems[item.inventoryItemId]?.stock ?? 0;
                    }
                    return ListTile(
                      title: Text(ShoppingService.displayName(item.inventoryItemId, item.name)),
                      subtitle: Text('${item.unit} • Stok: $currentStock'),
                      trailing: SizedBox(
                        width: 100,
                        child: TextField(
                          controller: controllers[index],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              List<ShoppingOrderItem> borderItems = [];
              for (int i = 0; i < supplier.items.length; i++) {
                int qty = int.tryParse(controllers[i]?.text ?? '0') ?? 0;
                if (qty > 0) {
                  final src = supplier.items[i];
                  borderItems.add(ShoppingOrderItem(
                    name: ShoppingService.displayName(src.inventoryItemId, src.name),
                    quantity: qty,
                    unit: src.unit,
                    isPerishable: src.isPerishable,
                    inventoryItemId: src.inventoryItemId,
                  ));
                }
              }

              if (borderItems.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada item yang dipesan')));
                return;
              }

              final ShoppingOrder newOrder = await ShoppingService.createOrder(supplier.id, supplier.name, borderItems);
              if (context.mounted) {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 8),
                        Text('Order Berhasil Dibuat', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    content: Text(
                      'Pesanan ke ${supplier.name} berhasil disimpan.\nIngin mengirim PDF ke WhatsApp?',
                      style: GoogleFonts.poppins(fontSize: 14),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Lewati', style: GoogleFonts.poppins(color: Colors.grey)),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.send, size: 18),
                        label: Text('Kirim ke WhatsApp', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            final pdfPath = await ShoppingService.saveOrderAsImage(newOrder);
                            final orderMessage = newOrder.items
                                .map((item) => '(${item.quantity}${item.unit}) ${ShoppingService.displayName(item.inventoryItemId, item.name)}')
                                .join('\n');
                            await Share.shareXFiles(
                              [XFile(pdfPath, mimeType: 'image/jpeg')],
                              text: orderMessage,
                            );
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Gagal membagikan PDF: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
            child: const Text('Buat & Simpan'),
          ),
        ],
      ),
    );
  }
}

class ShoppingOrdersView extends StatefulWidget {
  const ShoppingOrdersView({Key? key}) : super(key: key);

  @override
  State<ShoppingOrdersView> createState() => _ShoppingOrdersViewState();
}

class _ShoppingOrdersViewState extends State<ShoppingOrdersView> {
  DateTime? _startDate;
  DateTime? _endDate;

  Future<void> _pickDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null 
          ? DateTimeRange(start: _startDate!, end: _endDate!) 
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                _startDate != null && _endDate != null
                    ? '${DateFormat('dd MMM yyyy').format(_startDate!)} - ${DateFormat('dd MMM yyyy').format(_endDate!)}'
                    : 'Hari Ini (${DateFormat('dd MMM yyyy').format(DateTime.now())})',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF2E7D32)),
              ),
              const SizedBox(width: 8),
              if (_startDate != null)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: _clearDateRange,
                  tooltip: 'Hapus Filter',
                ),
              ElevatedButton.icon(
                onPressed: () => _pickDateRange(context),
                icon: const Icon(Icons.date_range),
                label: const Text('Filter Tanggal'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ShoppingOrder>>(
            stream: ShoppingService.getOrdersStream(startDate: _startDate, endDate: _endDate),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              
              final orders = snapshot.data ?? [];
              if (orders.isEmpty) {
                return const Center(child: Text('Belum ada riwayat pesanan shopping.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final dateStr = DateFormat('dd MMM yyyy HH:mm').format(order.date);
                  
                  return GestureDetector(
                    onLongPress: order.status != 'completed'
                        ? () => _showDeleteOrderDialog(context, order)
                        : null,
                    child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: order.status == 'completed' ? Colors.green.shade50 : Colors.white,
                    child: ExpansionTile(
                      title: Text(
                        'Order - ${order.supplierName}',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('Tanggal: $dateStr | Status: ${order.status.toUpperCase()}'),
                      children: [
                        ...order.items.map((item) => ListTile(
                              dense: true,
                              title: Text(ShoppingService.displayName(item.inventoryItemId, item.name)),
                              trailing: Text('${item.quantity} ${item.unit}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            )),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => ShoppingService.openOrderAsImage(order),
                                icon: const Icon(Icons.image),
                                label: const Text('Gambar'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _shareOrder(context, order),
                                icon: const Icon(Icons.send),
                                label: const Text('Share'),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
                              ),
                              if (order.status != 'completed') ...[
                                ElevatedButton.icon(
                                  onPressed: () => _showCorrectionDialog(context, order),
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Correction'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => _showCompleteOrderDialog(context, order),
                                  icon: const Icon(Icons.check_circle),
                                  label: const Text('Complete Shopping'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                ),
                              ]
                            ],
                          ),
                        )
                      ],
                    ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDeleteOrderDialog(BuildContext context, ShoppingOrder order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text('Hapus Pesanan?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Pesanan ke ${order.supplierName} akan dihapus secara permanen.',
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete, size: 18),
            label: Text('Hapus', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ShoppingService.deleteOrder(order.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pesanan berhasil dihapus')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _shareOrder(BuildContext context, ShoppingOrder order) async {
    try {
      final pdfPath = await ShoppingService.saveOrderAsImage(order);
      final orderMessage = order.items
          .map((item) => '(${item.quantity}${item.unit}) ${ShoppingService.displayName(item.inventoryItemId, item.name)}')
          .join('\n');
      await Share.shareXFiles(
        [XFile(pdfPath, mimeType: 'image/jpeg')],
        text: orderMessage,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membagikan PDF: $e')),
        );
      }
    }
  }

  void _showCorrectionDialog(BuildContext context, ShoppingOrder order) {
    if (order.items.isEmpty) return;

    final Map<int, TextEditingController> controllers = {};
    for (int i = 0; i < order.items.length; i++) {
      controllers[i] = TextEditingController(text: order.items[i].quantity.toString());
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Koreksi Pesanan', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ubah jumlah barang yang datang. Jika tidak datang, ubah menjadi 0.', style: GoogleFonts.poppins(fontSize: 12)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: order.items.length,
                  itemBuilder: (context, index) {
                    final item = order.items[index];
                    return ListTile(
                      title: Text(ShoppingService.displayName(item.inventoryItemId, item.name)),
                      subtitle: Text(item.unit),
                      trailing: SizedBox(
                        width: 100,
                        child: TextField(
                          controller: controllers[index],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              List<ShoppingOrderItem> correctedItems = [];
              for (int i = 0; i < order.items.length; i++) {
                int qty = int.tryParse(controllers[i]?.text ?? '0') ?? 0;
                correctedItems.add(ShoppingOrderItem(
                  name: ShoppingService.displayName(order.items[i].inventoryItemId, order.items[i].name),
                  quantity: qty,
                  unit: order.items[i].unit,
                  isPerishable: order.items[i].isPerishable,
                  inventoryItemId: order.items[i].inventoryItemId,
                ));
              }

              await ShoppingService.updateOrderItems(order.id, correctedItems);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pesanan berhasil dikoreksi')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Simpan Koreksi'),
          ),
        ],
      ),
    );
  }

  void _showCompleteOrderDialog(BuildContext context, ShoppingOrder order) {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          bool isSaving = false;
          return AlertDialog(
            title: Text('Selesaikan Order?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            content: const Text('Pastikan barang yang datang sudah sesuai. Jika belum sesuai, Anda dapat melakukan Koreksi (Correction). Setelah diselesaikan, barang akan ditambahkan ke Inventory stok sesuai dengan jumlah yang tercatat.'),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        try {
                          await ShoppingService.completeOrder(order);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Stok berhasil ditambahkan ke Inventory')),
                            );
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialogState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Gagal menyelesaikan pesanan: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Ya, Selesai'),
              ),
            ],
          );
        },
      ),
    );
  }
}
