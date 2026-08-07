import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Classes/Assets.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/BottomSheets/AddOrEditMenu.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Services/UserMessageService.dart';

class MenuManagementWidget extends StatefulWidget {
  final List<MenuObject> menuObjectList_makanan;
  final List<MenuObject> menuObjectList_minuman;
  final List<AssetsObject> listGambar;
  final List<String> categoryOrder;
  final Function(AssetsObject)? onDeleteCatalogImage;

  const MenuManagementWidget({
    Key? key,
    required this.menuObjectList_makanan,
    required this.menuObjectList_minuman,
    required this.listGambar,
    this.categoryOrder = const [],
    this.onDeleteCatalogImage,
  }) : super(key: key);

  @override
  State<MenuManagementWidget> createState() => _MenuManagementWidgetState();
}

class _MenuManagementWidgetState extends State<MenuManagementWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedCategory;
  String? _selectedOptionGroupId;
  final _searchController = TextEditingController();
  final _optionSearchController = TextEditingController();
  String _searchQuery = '';
  String _optionSearchQuery = '';
  final _optionGroupService = OptionGroupService();
  Timer? _debounceTimer;
  Timer? _optionDebounceTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    await InventoryService().refreshInventoryCache();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _optionSearchController.dispose();
    _debounceTimer?.cancel();
    _optionDebounceTimer?.cancel();
    super.dispose();
  }

  List<MenuObject> get _allMenuItems =>
      [...widget.menuObjectList_makanan, ...widget.menuObjectList_minuman];

  List<MenuObject> get _allFilteredMenuItems {
    if (_searchQuery.isEmpty) return _allMenuItems;
    return _allMenuItems.where((item) {
      return item.namaMenu.toLowerCase().contains(_searchQuery) ||
          item.category.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  Map<String, List<MenuObject>> get _groupedByCategory {
    final grouped = <String, List<MenuObject>>{};
    for (var item in _allMenuItems) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    // Sort items within each category by sortOrder
    for (var key in grouped.keys) {
      grouped[key]!.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return grouped;
  }

  List<String> get _sortedCategories {
    final categories = _groupedByCategory.keys.toList();
    categories.sort((a, b) {
      final indexA = widget.categoryOrder.indexOf(a);
      final indexB = widget.categoryOrder.indexOf(b);
      if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
      if (indexA != -1) return -1;
      if (indexB != -1) return 1;
      return a.compareTo(b);
    });
    return categories;
  }

  Map<String, List<MenuObject>> get _filteredGroupedByCategory {
    if (_searchQuery.isEmpty) return _groupedByCategory;

    final filteredMap = <String, List<MenuObject>>{};
    _groupedByCategory.forEach((category, items) {
      final filteredItems = items.where((item) {
        return item.namaMenu
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            item.category.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
      filteredMap[category] = filteredItems;
    });
    return filteredMap;
  }

  void _onSearchChanged(String value) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _searchQuery = value.toLowerCase());
    });
  }

  void _onOptionSearchChanged(String value) {
    if (_optionDebounceTimer?.isActive ?? false) _optionDebounceTimer!.cancel();
    _optionDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _optionSearchQuery = value.toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMenuOverviewTab(),
                _buildOptionGroupsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: Col.testingMode,
        builder: (context, isTesting, child) {
          if (!isTesting) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () => _showMigrasiConfirmation(context),
            backgroundColor: Colors.orange.shade800,
            icon: const Icon(Icons.sync_alt, color: Colors.white),
            label: Text(
              'Migrasi Menu',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMigrasiConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Konfirmasi Migrasi Menu',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Aksi ini akan MENGHAPUS SEMUA menu di mode testing dan menyalin semua menu dari production ke testing. Apakah Anda yakin?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Batal',
              style: GoogleFonts.poppins(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              _performMigration();
            },
            child: Text(
              'Ya, Migrasi',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performMigration() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      ),
    );

    try {
      await Col.migrateMenuCollection();

      // Refresh inventory cache to ensure consistency
      await InventoryService().refreshInventoryCache();

      if (mounted) {
        Navigator.pop(context); // Remove loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Migrasi menu berhasil diselesaikan',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Remove loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gagal melakukan migrasi: ${UserMessageService.fromError(e)}',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
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
        labelStyle:
            GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle:
            GoogleFonts.poppins(fontWeight: FontWeight.normal, fontSize: 14),
        tabs: const [
          Tab(text: 'MENU OVERVIEW'),
          Tab(text: 'OPTION GROUPS'),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MENU OVERVIEW TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMenuOverviewTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Left Pane: Categories
          SizedBox(
            width: 280,
            child: _buildCategoriesPane(),
          ),
          const SizedBox(width: 16),
          // Right Pane: Items
          Expanded(child: _buildItemsPane()),
        ],
      ),
    );
  }

  Widget _buildCategoriesPane() {
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
          _buildSearchBar(
              _searchController, 'Cari nama menu...', _onSearchChanged),
          _buildCategoryHeader(),
          Expanded(child: _buildCategoryList()),
        ],
      ),
    );
  }

  Widget _buildSearchBar(TextEditingController controller, String hint,
      Function(String) onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey.shade400),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCategoryHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            'CATEGORIES',
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
            onSelected: _handleCategoryAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reorder',
                child: Row(
                  children: [
                    Icon(Icons.swap_vert, size: 20),
                    SizedBox(width: 8),
                    Text('Atur Urutan'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    Icon(Icons.add, size: 20),
                    SizedBox(width: 8),
                    Text('Tambah Kategori'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleCategoryAction(String action) {
    if (action == 'reorder') {
      _showCategoryReorderDialog();
    } else if (action == 'add') {
      _showAddCategoryDialog();
    }
  }

  Widget _buildCategoryList() {
    final categories = _sortedCategories;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final itemCount = _filteredGroupedByCategory[category]?.length ?? 0;
        final isSelected = _selectedCategory == category;

        return InkWell(
          onTap: () => setState(() => _selectedCategory = category),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE8F5E9) : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color:
                      isSelected ? const Color(0xFF2E7D32) : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    category,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color:
                          isSelected ? const Color(0xFF1B5E20) : Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF2E7D32)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$itemCount',
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
      child: Column(
        children: [
          _buildItemsHeader(),
          Expanded(child: _buildItemsList()),
        ],
      ),
    );
  }

  Widget _buildItemsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            'ITEMS',
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
              if (value == 'add_makanan') {
                _addOrEditMenu(context,
                    query: 'add',
                    makananOrMinuman: 'Makanan',
                    initialCategory: _selectedCategory,
                    existingCategories: _sortedCategories);
              } else if (value == 'add_minuman') {
                _addOrEditMenu(context,
                    query: 'add',
                    makananOrMinuman: 'Minuman',
                    initialCategory: _selectedCategory,
                    existingCategories: _sortedCategories);
              } else if (value == 'reorder_items') {
                _showItemReorderDialog();
              }
            },
            itemBuilder: (context) {
              // Determine if selected category is all Makanan or all Minuman
              bool? categoryIsMakanan;
              if (_selectedCategory != null) {
                final categoryItems =
                    _groupedByCategory[_selectedCategory] ?? [];
                if (categoryItems.isNotEmpty) {
                  categoryIsMakanan = categoryItems.first.isMakanan;
                }
              }

              return [
                if (_selectedCategory != null)
                  const PopupMenuItem(
                    value: 'reorder_items',
                    child: Row(
                      children: [
                        Icon(Icons.swap_vert, size: 20),
                        SizedBox(width: 8),
                        Text('Atur Urutan'),
                      ],
                    ),
                  ),
                if (categoryIsMakanan != false)
                  const PopupMenuItem(
                    value: 'add_makanan',
                    child: Row(
                      children: [
                        Icon(Icons.restaurant, size: 20),
                        SizedBox(width: 8),
                        Text('Tambah Makanan'),
                      ],
                    ),
                  ),
                if (categoryIsMakanan != true)
                  const PopupMenuItem(
                    value: 'add_minuman',
                    child: Row(
                      children: [
                        Icon(Icons.local_cafe, size: 20),
                        SizedBox(width: 8),
                        Text('Tambah Minuman'),
                      ],
                    ),
                  ),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    List<MenuObject> items;

    if (_selectedCategory != null) {
      items = _filteredGroupedByCategory[_selectedCategory] ?? [];
    } else {
      items = _allFilteredMenuItems;
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _selectedCategory != null
                  ? 'Tidak ada item di kategori ini'
                  : 'Pilih kategori untuk melihat item',
              style: GoogleFonts.poppins(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildItemCard(items[index]),
    );
  }

  Widget _buildItemCard(MenuObject item) {
    final isPortrait = item.imageAspectRatio == '3:4';
    final imgWidth = 72.0;
    final imgHeight = isPortrait ? 96.0 : 72.0;

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
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: imgWidth,
              height: imgHeight,
              color: Colors.grey.shade100,
              child: item.imagePath != 'tidak ada'
                  ? CachedNetworkImage(
                      imageUrl: item.imagePath,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.fastfood, color: Colors.grey),
                    )
                  : const Icon(Icons.fastfood, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.namaMenu,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    if (item.isRecommended)
                      Icon(Icons.star, color: Colors.amber.shade600, size: 20),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Rp${_formatCurrency(item.harga)}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF2E7D32),
                  ),
                ),
                if (item.menuDescription.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.menuDescription,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Actions
          _buildEditButton(item),
          const SizedBox(width: 8),
          _buildDeleteButton(item),
        ],
      ),
    );
  }

  Widget _buildEditButton(MenuObject item) {
    return OutlinedButton(
      onPressed: () => _addOrEditMenu(
        context,
        query: 'edit',
        makananOrMinuman: item.isMakanan ? 'Makanan' : 'Minuman',
        menuObject: item,
        existingCategories: _sortedCategories,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2E7D32),
        side: const BorderSide(color: Color(0xFF2E7D32)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text('Edit'),
    );
  }

  Widget _buildDeleteButton(MenuObject item) {
    return IconButton(
      onPressed: () => _confirmDelete(item),
      icon: Icon(Icons.close, color: Colors.red.shade400),
      tooltip: 'Hapus',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OPTION GROUPS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOptionGroupsTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Left Pane: Option Groups List
          SizedBox(
            width: 280,
            child: _buildOptionGroupsPane(),
          ),
          const SizedBox(width: 16),
          // Right Pane: Options Detail
          Expanded(child: _buildOptionsDetailPane()),
        ],
      ),
    );
  }

  Widget _buildOptionGroupsPane() {
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
          // Create New Button
          Container(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: _showCreateOptionGroupDialog,
              icon: const Icon(Icons.add),
              label: const Text('Buat Option Group Baru'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
                side: const BorderSide(color: Color(0xFF2E7D32)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          _buildSearchBar(_optionSearchController,
              'Cari berdasarkan nama grup opsi', _onOptionSearchChanged),
          _buildOptionGroupsHeader(),
          Expanded(child: _buildOptionGroupsList()),
        ],
      ),
    );
  }

  Widget _buildOptionGroupsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            'OPTION GROUPS',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Icon(Icons.more_vert, color: Colors.grey.shade600, size: 20),
        ],
      ),
    );
  }

  Widget _buildOptionGroupsList() {
    return StreamBuilder<List<OptionGroup>>(
      stream: _optionGroupService.getOptionGroupsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final groups = snapshot.data ?? [];
        final filteredGroups = _optionSearchQuery.isEmpty
            ? groups
            : groups
                .where((g) => g.name.toLowerCase().contains(_optionSearchQuery))
                .toList();

        if (filteredGroups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.tune, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  'Belum ada option group',
                  style: GoogleFonts.poppins(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: filteredGroups.length,
          itemBuilder: (context, index) {
            final group = filteredGroups[index];
            final isSelected = _selectedOptionGroupId == group.id;

            return InkWell(
              onTap: () => setState(() => _selectedOptionGroupId = group.id),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFFE8F5E9) : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                      color: isSelected
                          ? const Color(0xFF2E7D32)
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.name,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected
                              ? const Color(0xFF1B5E20)
                              : Colors.black87,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF2E7D32)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${group.optionCount}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              isSelected ? Colors.white : Colors.grey.shade700,
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

  Widget _buildOptionsDetailPane() {
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
      child: _selectedOptionGroupId == null
          ? _buildNoOptionGroupSelected()
          : _buildOptionGroupDetail(),
    );
  }

  Widget _buildNoOptionGroupSelected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tune, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Pilih option group untuk melihat detail',
            style: GoogleFonts.poppins(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionGroupDetail() {
    return StreamBuilder<List<OptionGroup>>(
      stream: _optionGroupService.getOptionGroupsStream(),
      builder: (context, snapshot) {
        final groups = snapshot.data ?? [];
        final group = groups.firstWhere(
          (g) => g.id == _selectedOptionGroupId,
          orElse: () => OptionGroup(id: '', name: ''),
        );

        if (group.id.isEmpty) {
          return _buildNoOptionGroupSelected();
        }

        return Column(
          children: [
            _buildOptionGroupDetailHeader(group),
            Expanded(child: _buildOptionsList(group)),
          ],
        );
      },
    );
  }

  Widget _buildOptionGroupDetailHeader(OptionGroup group) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'OPTIONS',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _showEditOptionGroupDialog(group),
                child: Text(
                  'Edit',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Status badges
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatusBadge(
                group.statusLabel,
                group.isRequired ? Colors.red : Colors.green,
              ),
              _buildSelectionRuleBadge(group),
              if (group.linkedMenuItems.isNotEmpty)
                _buildLinkedToBadge(group.linkedMenuItems),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSelectionRuleBadge(OptionGroup group) {
    String label;
    if (group.minSelection > 0 &&
        group.maxSelection > 0 &&
        group.minSelection == group.maxSelection) {
      label = 'Pilih tepat ${group.minSelection}';
    } else if (group.minSelection > 0 && group.maxSelection == 0) {
      label = 'Pilih minimal ${group.minSelection}';
    } else if (group.minSelection == 0 && group.maxSelection > 0) {
      label = 'Pilih maksimal ${group.maxSelection}';
    } else {
      label = 'Bebas pilih';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.orange.shade800,
        ),
      ),
    );
  }

  Widget _buildLinkedToBadge(List<String> linkedItems) {
    return FutureBuilder<List<String>>(
      future: _getLinkedMenuNames(linkedItems),
      builder: (context, snapshot) {
        final names = snapshot.data ?? [];
        final displayText = names.isEmpty
            ? 'Belum terhubung'
            : 'Terhubung ke: ${names.take(2).join(", ")}${names.length > 2 ? " +${names.length - 2}" : ""}';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Text(
            displayText,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.blue.shade700,
            ),
          ),
        );
      },
    );
  }

  Future<List<String>> _getLinkedMenuNames(List<String> menuIds) async {
    final names = <String>[];
    for (final id in menuIds) {
      final doc = await FirebaseFirestore.instance
          .collection(Col.name('Canteens'))
          .doc('canteen375')
          .collection('MenuCollection')
          .doc(id)
          .get();
      if (doc.exists) {
        names.add((doc.data() as Map<String, dynamic>)['namaMenu'] ?? id);
      }
    }
    return names;
  }

  Widget _buildOptionsList(OptionGroup group) {
    if (group.options.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.list, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Belum ada opsi dalam grup ini',
              style: GoogleFonts.poppins(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _showAddOptionDialog(group),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Opsi'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: group.options.length + 1,
      itemBuilder: (context, index) {
        if (index == group.options.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => _showAddOptionDialog(group),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Opsi'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
              ),
            ),
          );
        }

        final option = group.options[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.name,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          option.formattedPrice,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: option.priceAdjustment > 0
                                ? const Color(0xFF2E7D32)
                                : option.priceAdjustment < 0
                                    ? const Color(0xFFE65100)
                                    : Colors.grey.shade600,
                          ),
                        ),
                        if (option.ingredients.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inventory_2_outlined,
                                      size: 12, color: Colors.blue.shade700),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      option.ingredients.map((ing) {
                                        final item = InventoryService()
                                                .allInventoryItems[
                                            ing.inventoryItemId];
                                        return item != null
                                            ? item.name
                                            : 'Unknown';
                                      }).join(', '),
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _showEditOptionDialog(group, option),
                icon: Icon(Icons.edit, size: 20, color: Colors.grey.shade600),
              ),
              IconButton(
                onPressed: () => _confirmDeleteOption(group, option),
                icon: Icon(Icons.close, size: 20, color: Colors.red.shade400),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatCurrency(int value) {
    return value.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  void _addOrEditMenu(BuildContext context,
      {required String query,
      required String makananOrMinuman,
      MenuObject? menuObject,
      String? initialCategory,
      required List<String> existingCategories}) {
    showModalBottomSheet(
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16.0),
          topRight: Radius.circular(16.0),
        ),
      ),
      builder: (context) => AddMenuBottomSheet(
        query: query,
        makananOrMinuman: makananOrMinuman,
        menuObject: menuObject,
        listGambar: widget.listGambar,
        onDeleteCatalogImage: widget.onDeleteCatalogImage,
        initialCategory: initialCategory,
        existingCategories: existingCategories,
      ),
    );
  }

  void _confirmDelete(MenuObject item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Menu'),
        content: Text('Yakin ingin menghapus "${item.namaMenu}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              _deleteMenu(item.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteMenu(String menuId) async {
    final firestore = FirebaseFirestore.instance;
    final canteenDoc =
        firestore.collection(Col.name('Canteens')).doc('canteen375');

    // 1. Delete the Menu
    await canteenDoc.collection('MenuCollection').doc(menuId).delete();

    // 2. Scrub the menuId from all Option Groups to prevent Ghost Links
    final linkedGroups = await canteenDoc
        .collection('OptionGroups')
        .where('linkedMenuItems', arrayContains: menuId)
        .get();

    if (linkedGroups.docs.isNotEmpty) {
      WriteBatch batch = firestore.batch();
      for (var groupDoc in linkedGroups.docs) {
        batch.update(groupDoc.reference, {
          'linkedMenuItems': FieldValue.arrayRemove([menuId]),
        });
      }
      await batch.commit();
    }
  }

  void _showCategoryReorderDialog() {
    final categories = List<String>.from(_sortedCategories);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Atur Urutan Kategori',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            height: 400,
            child: ReorderableListView.builder(
              itemCount: categories.length,
              onReorder: (oldIndex, newIndex) {
                setDialogState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = categories.removeAt(oldIndex);
                  categories.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                return ListTile(
                  key: Key(categories[index]),
                  leading: const Icon(Icons.drag_handle),
                  title: Text(categories[index]),
                  trailing: Text(
                      '${_groupedByCategory[categories[index]]?.length ?? 0}'),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection(Col.name('Canteens'))
                    .doc('canteen375')
                    .collection('Metadata')
                    .doc('MenuConfig')
                    .set(
                        {'categoryOrder': categories}, SetOptions(merge: true));
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32)),
              child:
                  const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showItemReorderDialog() {
    if (_selectedCategory == null) return;

    final items = List<MenuObject>.from(
      _groupedByCategory[_selectedCategory] ?? [],
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Atur Urutan: $_selectedCategory',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 400,
            height: 400,
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'Tidak ada item di kategori ini',
                      style: GoogleFonts.poppins(color: Colors.grey),
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: items.length,
                    onReorder: (oldIndex, newIndex) {
                      setDialogState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = items.removeAt(oldIndex);
                        items.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        key: Key(item.id),
                        leading: const Icon(Icons.drag_handle),
                        title: Text(
                          item.namaMenu,
                          style: GoogleFonts.poppins(fontSize: 14),
                        ),
                        subtitle: Text(
                          'Rp${_formatCurrency(item.harga)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                        trailing: Text(
                          '${index + 1}',
                          style: GoogleFonts.poppins(
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final firestore = FirebaseFirestore.instance;
                final batch = firestore.batch();
                final collection = firestore
                    .collection(Col.name('Canteens'))
                    .doc('canteen375')
                    .collection('MenuCollection');

                for (int i = 0; i < items.length; i++) {
                  batch.update(
                    collection.doc(items[i].id),
                    {'sortOrder': i},
                  );
                  // Update local model too
                  items[i].sortOrder = i;
                }

                await batch.commit();
                if (mounted) setState(() {});
                Navigator.pop(context);

                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Urutan item di $_selectedCategory berhasil disimpan',
                      style: GoogleFonts.poppins(),
                    ),
                    backgroundColor: const Color(0xFF2E7D32),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
              ),
              child:
                  const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCategoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Kategori Baru'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nama Kategori',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final newOrder = [...widget.categoryOrder, controller.text];
                await FirebaseFirestore.instance
                    .collection(Col.name('Canteens'))
                    .doc('canteen375')
                    .collection('Metadata')
                    .doc('MenuConfig')
                    .set({'categoryOrder': newOrder}, SetOptions(merge: true));
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32)),
            child: const Text('Tambah', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showCreateOptionGroupDialog() {
    final nameController = TextEditingController();
    final valueController = TextEditingController(text: '1');
    bool isRequired = false;
    String? selectionRule;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Buat Option Group Baru',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Group',
                    hintText: 'Contoh: Tambah Mie, Level Pedas',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Wajib dipilih'),
                  subtitle: const Text('Pelanggan harus memilih salah satu'),
                  value: isRequired,
                  onChanged: (v) => setDialogState(() => isRequired = v),
                ),
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Aturan Pemilihan',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Biarkan tidak dipilih jika pelanggan bebas memilih berapa saja.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Minimal'),
                      selected: selectionRule == 'at_least',
                      selectedColor: const Color(0xFFE8F5E9),
                      onSelected: (selected) {
                        setDialogState(() {
                          selectionRule = selected ? 'at_least' : null;
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Tepat'),
                      selected: selectionRule == 'exactly',
                      selectedColor: const Color(0xFFE8F5E9),
                      onSelected: (selected) {
                        setDialogState(() {
                          selectionRule = selected ? 'exactly' : null;
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Maksimal'),
                      selected: selectionRule == 'at_most',
                      selectedColor: const Color(0xFFE8F5E9),
                      onSelected: (selected) {
                        setDialogState(() {
                          selectionRule = selected ? 'at_most' : null;
                        });
                      },
                    ),
                  ],
                ),
                if (selectionRule != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        selectionRule == 'at_least'
                            ? 'Pilih minimal'
                            : selectionRule == 'exactly'
                                ? 'Pilih tepat'
                                : 'Pilih maksimal',
                        style: GoogleFonts.poppins(fontSize: 14),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: valueController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 8, horizontal: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('opsi', style: GoogleFonts.poppins(fontSize: 14)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  int minSel = 0;
                  int maxSel = 0;
                  final val = int.tryParse(valueController.text) ?? 1;

                  if (selectionRule == 'at_least') {
                    minSel = val;
                    maxSel = 0;
                  } else if (selectionRule == 'exactly') {
                    minSel = val;
                    maxSel = val;
                  } else if (selectionRule == 'at_most') {
                    minSel = 0;
                    maxSel = val;
                  }

                  Navigator.pop(context);
                  await _optionGroupService.createOptionGroup(OptionGroup(
                    id: '',
                    name: nameController.text,
                    isRequired: isRequired,
                    minSelection: minSel,
                    maxSelection: maxSel,
                  ));
                } else {
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32)),
              child: const Text('Buat', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditOptionGroupDialog(OptionGroup group) {
    final nameController = TextEditingController(text: group.name);
    bool isRequired = group.isRequired;

    // Derive the current rule from minSelection/maxSelection
    String? selectionRule;
    int selectionValue = 1;
    if (group.minSelection > 0 &&
        group.maxSelection > 0 &&
        group.minSelection == group.maxSelection) {
      selectionRule = 'exactly';
      selectionValue = group.minSelection;
    } else if (group.minSelection > 0 && group.maxSelection == 0) {
      selectionRule = 'at_least';
      selectionValue = group.minSelection;
    } else if (group.minSelection == 0 && group.maxSelection > 0) {
      selectionRule = 'at_most';
      selectionValue = group.maxSelection;
    }
    // else: no rule (both 0)

    final valueController =
        TextEditingController(text: selectionValue.toString());

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit Option Group',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Group',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Wajib dipilih'),
                  value: isRequired,
                  onChanged: (v) => setDialogState(() => isRequired = v),
                ),
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Aturan Pemilihan',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Biarkan tidak dipilih jika pelanggan bebas memilih berapa saja.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Minimal'),
                      selected: selectionRule == 'at_least',
                      selectedColor: const Color(0xFFE8F5E9),
                      onSelected: (selected) {
                        setDialogState(() {
                          selectionRule = selected ? 'at_least' : null;
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Tepat'),
                      selected: selectionRule == 'exactly',
                      selectedColor: const Color(0xFFE8F5E9),
                      onSelected: (selected) {
                        setDialogState(() {
                          selectionRule = selected ? 'exactly' : null;
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Maksimal'),
                      selected: selectionRule == 'at_most',
                      selectedColor: const Color(0xFFE8F5E9),
                      onSelected: (selected) {
                        setDialogState(() {
                          selectionRule = selected ? 'at_most' : null;
                        });
                      },
                    ),
                  ],
                ),
                if (selectionRule != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        selectionRule == 'at_least'
                            ? 'Pilih minimal'
                            : selectionRule == 'exactly'
                                ? 'Pilih tepat'
                                : 'Pilih maksimal',
                        style: GoogleFonts.poppins(fontSize: 14),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: valueController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 8, horizontal: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('opsi', style: GoogleFonts.poppins(fontSize: 14)),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showLinkMenuItemsDialog(group);
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('Hubungkan ke Menu'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (group.linkedMenuItems.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Tidak bisa hapus group yang masih terhubung ke menu'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                _confirmDeleteOptionGroup(group);
              },
              child: const Text('Hapus', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  int minSel = 0;
                  int maxSel = 0;
                  final val = int.tryParse(valueController.text) ?? 1;

                  if (selectionRule == 'at_least') {
                    minSel = val;
                    maxSel = 0;
                  } else if (selectionRule == 'exactly') {
                    minSel = val;
                    maxSel = val;
                  } else if (selectionRule == 'at_most') {
                    minSel = 0;
                    maxSel = val;
                  }

                  Navigator.pop(context);
                  await _optionGroupService.updateOptionGroup(OptionGroup(
                    id: group.id,
                    name: nameController.text,
                    isRequired: isRequired,
                    minSelection: minSel,
                    maxSelection: maxSel,
                    options: group.options,
                    linkedMenuItems: group.linkedMenuItems,
                  ));
                } else {
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32)),
              child:
                  const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLinkMenuItemsDialog(OptionGroup group) {
    final selectedIds = Set<String>.from(group.linkedMenuItems);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Hubungkan ke Menu',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            height: 400,
            child: ListView.builder(
              itemCount: _allMenuItems.length,
              itemBuilder: (context, index) {
                final item = _allMenuItems[index];
                final isLinked = selectedIds.contains(item.id);

                return CheckboxListTile(
                  title: Text(item.namaMenu),
                  subtitle: Text(item.category),
                  value: isLinked,
                  onChanged: (checked) {
                    setDialogState(() {
                      if (checked == true) {
                        selectedIds.add(item.id);
                      } else {
                        selectedIds.remove(item.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _optionGroupService.linkMenuItems(
                    group.id, selectedIds.toList());
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32)),
              child:
                  const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteOptionGroup(OptionGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Option Group'),
        content: Text('Yakin ingin menghapus "${group.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _optionGroupService.deleteOptionGroup(group.id);
              setState(() => _selectedOptionGroupId = null);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientLinkingSection(
    List<MenuIngredient> ingredients,
    void Function(void Function()) setDialogState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              'Bahan Baku',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Hubungkan opsi ini ke bahan baku untuk pelacakan stok otomatis.',
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        ...ingredients.asMap().entries.map((entry) {
          final idx = entry.key;
          final ing = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ing.inventoryItemName,
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Qty: ${ing.quantityNeeded}',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: Colors.red.shade400),
                  onPressed: () =>
                      setDialogState(() => ingredients.removeAt(idx)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        StreamBuilder<List<InventoryItem>>(
          stream: InventoryService().getInventoryStream(),
          builder: (context, snapshot) {
            final items = snapshot.data ?? [];
            items.sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            return OutlinedButton.icon(
              onPressed: items.isEmpty
                  ? null
                  : () => _showAddIngredientPicker(
                      items, ingredients, setDialogState),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                'Tambah Bahan',
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
                side: const BorderSide(color: Color(0xFF2E7D32)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showAddIngredientPicker(
    List<InventoryItem> inventoryItems,
    List<MenuIngredient> ingredients,
    void Function(void Function()) setParentState,
  ) {
    InventoryItem? selectedItem;
    final qtyController = TextEditingController(text: '1');

    // Filter out items that are already linked
    final linkedIds = ingredients.map((i) => i.inventoryItemId).toSet();
    final available =
        inventoryItems.where((i) => !linkedIds.contains(i.id)).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Semua bahan baku sudah ditambahkan.',
              style: GoogleFonts.poppins()),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPickerState) => AlertDialog(
          title: Text('Pilih Bahan Baku',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<InventoryItem>(
                value: selectedItem,
                decoration: const InputDecoration(
                  labelText: 'Bahan Baku',
                  border: OutlineInputBorder(),
                ),
                items: available.map((item) {
                  return DropdownMenuItem(
                    value: item,
                    child: Text('${item.name} (${item.stock} ${item.unit})'),
                  );
                }).toList(),
                onChanged: (val) => setPickerState(() => selectedItem = val),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Jumlah Dibutuhkan',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: selectedItem == null
                  ? null
                  : () {
                      final qty = int.tryParse(qtyController.text) ?? 1;
                      if (qty <= 0) return;
                      setParentState(() {
                        ingredients.add(MenuIngredient(
                          inventoryItemId: selectedItem!.id,
                          inventoryItemName: selectedItem!.name,
                          quantityNeeded: qty,
                        ));
                      });
                      Navigator.pop(ctx);
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32)),
              child:
                  const Text('Tambah', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOptionDialog(OptionGroup group) {
    final nameController = TextEditingController();
    final priceController = TextEditingController(text: '0');
    final ingredients = <MenuIngredient>[];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Tambah Opsi',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Opsi',
                      hintText: 'Contoh: Telur Dadar, Sawi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tambahan Harga (Rp)',
                      hintText: '0 untuk gratis',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildIngredientLinkingSection(ingredients, setDialogState),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  final newOptions = [
                    ...group.options,
                    OptionItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameController.text,
                      priceAdjustment: int.tryParse(priceController.text) ?? 0,
                      ingredients: ingredients,
                    ),
                  ];
                  await _optionGroupService.updateOptionGroup(OptionGroup(
                    id: group.id,
                    name: group.name,
                    isRequired: group.isRequired,
                    minSelection: group.minSelection,
                    maxSelection: group.maxSelection,
                    options: newOptions,
                    linkedMenuItems: group.linkedMenuItems,
                  ));
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32)),
              child:
                  const Text('Tambah', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditOptionDialog(OptionGroup group, OptionItem option) {
    final nameController = TextEditingController(text: option.name);
    final priceController =
        TextEditingController(text: option.priceAdjustment.toString());
    final ingredients = List<MenuIngredient>.from(option.ingredients);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit Opsi',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Opsi',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tambahan Harga (Rp)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildIngredientLinkingSection(ingredients, setDialogState),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  final updatedOptions = group.options.map((o) {
                    if (identical(o, option)) {
                      return OptionItem(
                        id: o.id.isNotEmpty
                            ? o.id
                            : DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameController.text,
                        priceAdjustment:
                            int.tryParse(priceController.text) ?? 0,
                        ingredients: ingredients,
                      );
                    }
                    return o;
                  }).toList();

                  await _optionGroupService.updateOptionGroup(OptionGroup(
                    id: group.id,
                    name: group.name,
                    isRequired: group.isRequired,
                    minSelection: group.minSelection,
                    maxSelection: group.maxSelection,
                    options: updatedOptions,
                    linkedMenuItems: group.linkedMenuItems,
                  ));
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32)),
              child:
                  const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteOption(OptionGroup group, OptionItem option) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Opsi'),
        content: Text('Yakin ingin menghapus "${option.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final updatedOptions =
                  group.options.where((o) => !identical(o, option)).toList();
              await _optionGroupService.updateOptionGroup(OptionGroup(
                id: group.id,
                name: group.name,
                isRequired: group.isRequired,
                minSelection: group.minSelection,
                maxSelection: group.maxSelection,
                options: updatedOptions,
                linkedMenuItems: group.linkedMenuItems,
              ));
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
