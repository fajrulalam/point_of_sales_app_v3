import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Classes/Assets.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';
import 'package:point_of_sales_app_v3/BottomSheets/AddOrEditMenu.dart';

class MenuManagementWidget extends StatefulWidget {
  final List<MenuObject> menuObjectList_makanan;
  final List<MenuObject> menuObjectList_minuman;
  final List<AssetsObject> listGambar;
  final List<String> categoryOrder;

  const MenuManagementWidget({
    Key? key,
    required this.menuObjectList_makanan,
    required this.menuObjectList_minuman,
    required this.listGambar,
    this.categoryOrder = const [],
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _optionSearchController.dispose();
    super.dispose();
  }

  List<MenuObject> get _allMenuItems =>
      [...widget.menuObjectList_makanan, ...widget.menuObjectList_minuman];

  Map<String, List<MenuObject>> get _groupedByCategory {
    final grouped = <String, List<MenuObject>>{};
    for (var item in _allMenuItems) {
      grouped.putIfAbsent(item.category, () => []).add(item);
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade100,
      child: Column(
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
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF1A1A1A),
        unselectedLabelColor: Colors.grey.shade500,
        indicatorColor: const Color(0xFF2E7D32),
        indicatorWeight: 3,
        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.normal, fontSize: 14),
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
          _buildSearchBar(_searchController, 'Cari nama menu...', (value) {
            setState(() => _searchQuery = value.toLowerCase());
          }),
          _buildCategoryHeader(),
          Expanded(child: _buildCategoryList()),
        ],
      ),
    );
  }

  Widget _buildSearchBar(
      TextEditingController controller, String hint, Function(String) onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
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
        final itemCount = _groupedByCategory[category]?.length ?? 0;
        final isSelected = _selectedCategory == category;

        return InkWell(
          onTap: () => setState(() => _selectedCategory = category),
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
                    category,
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
                _addOrEditMenu(context, query: 'add', makananOrMinuman: 'Makanan');
              } else if (value == 'add_minuman') {
                _addOrEditMenu(context, query: 'add', makananOrMinuman: 'Minuman');
              }
            },
            itemBuilder: (context) => [
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    List<MenuObject> items;
    
    if (_selectedCategory != null) {
      items = _groupedByCategory[_selectedCategory] ?? [];
    } else {
      items = _allMenuItems;
    }

    if (_searchQuery.isNotEmpty) {
      items = items.where((item) {
        return item.namaMenu.toLowerCase().contains(_searchQuery) ||
            item.category.toLowerCase().contains(_searchQuery);
      }).toList();
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
              width: 72,
              height: 72,
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
                    if (item.isFeatured)
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
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.description,
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
              label: const Text('Create New Option Group'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
                side: const BorderSide(color: Color(0xFF2E7D32)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          _buildSearchBar(_optionSearchController, 'Search by option group name', (value) {
            setState(() => _optionSearchQuery = value.toLowerCase());
          }),
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
            : groups.where((g) => g.name.toLowerCase().contains(_optionSearchQuery)).toList();

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
                        group.name,
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
                        '${group.optionCount}',
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

  Widget _buildLinkedToBadge(List<String> linkedItems) {
    return FutureBuilder<List<String>>(
      future: _getLinkedMenuNames(linkedItems),
      builder: (context, snapshot) {
        final names = snapshot.data ?? [];
        final displayText = names.isEmpty
            ? 'No links'
            : 'Linked to: ${names.take(2).join(", ")}${names.length > 2 ? " +${names.length - 2}" : ""}';

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
          .collection('Canteens')
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
                    Text(
                      option.formattedPrice,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: option.priceAdjustment > 0
                            ? const Color(0xFF2E7D32)
                            : Colors.grey.shade600,
                      ),
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
      MenuObject? menuObject}) {
    showModalBottomSheet(
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
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

  void _deleteMenu(String menuId) {
    FirebaseFirestore.instance
        .collection('Canteens')
        .doc('canteen375')
        .collection('MenuCollection')
        .doc(menuId)
        .delete();
  }

  void _showCategoryReorderDialog() {
    final categories = List<String>.from(_sortedCategories);
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Atur Urutan Kategori', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
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
                  trailing: Text('${_groupedByCategory[categories[index]]?.length ?? 0}'),
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
                    .collection('Canteens')
                    .doc('canteen375')
                    .collection('Metadata')
                    .doc('MenuConfig')
                    .set({'categoryOrder': categories}, SetOptions(merge: true));
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
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
                    .collection('Canteens')
                    .doc('canteen375')
                    .collection('Metadata')
                    .doc('MenuConfig')
                    .set({'categoryOrder': newOrder}, SetOptions(merge: true));
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            child: const Text('Tambah', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showCreateOptionGroupDialog() {
    final nameController = TextEditingController();
    bool isRequired = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Buat Option Group Baru', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Column(
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  await _optionGroupService.createOptionGroup(OptionGroup(
                    id: '',
                    name: nameController.text,
                    isRequired: isRequired,
                  ));
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
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

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit Option Group', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Column(
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
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showLinkMenuItemsDialog(group);
                },
                icon: const Icon(Icons.link),
                label: const Text('Kelola Link Menu Items'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (group.linkedMenuItems.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tidak bisa hapus group yang masih terhubung ke menu'),
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
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  await _optionGroupService.updateOptionGroup(OptionGroup(
                    id: group.id,
                    name: nameController.text,
                    isRequired: isRequired,
                    options: group.options,
                    linkedMenuItems: group.linkedMenuItems,
                  ));
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
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
          title: Text('Link ke Menu Items', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
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
                await _optionGroupService.linkMenuItems(group.id, selectedIds.toList());
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
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

  void _showAddOptionDialog(OptionGroup group) {
    final nameController = TextEditingController();
    final priceController = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Opsi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
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
          ],
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
                  ),
                ];
                await _optionGroupService.updateOptionGroup(OptionGroup(
                  id: group.id,
                  name: group.name,
                  isRequired: group.isRequired,
                  options: newOptions,
                  linkedMenuItems: group.linkedMenuItems,
                ));
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            child: const Text('Tambah', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditOptionDialog(OptionGroup group, OptionItem option) {
    final nameController = TextEditingController(text: option.name);
    final priceController = TextEditingController(text: option.priceAdjustment.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Opsi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
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
          ],
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
                  if (o.id == option.id) {
                    return OptionItem(
                      id: o.id,
                      name: nameController.text,
                      priceAdjustment: int.tryParse(priceController.text) ?? 0,
                    );
                  }
                  return o;
                }).toList();
                
                await _optionGroupService.updateOptionGroup(OptionGroup(
                  id: group.id,
                  name: group.name,
                  isRequired: group.isRequired,
                  options: updatedOptions,
                  linkedMenuItems: group.linkedMenuItems,
                ));
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
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
              final updatedOptions = group.options.where((o) => o.id != option.id).toList();
              await _optionGroupService.updateOptionGroup(OptionGroup(
                id: group.id,
                name: group.name,
                isRequired: group.isRequired,
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
