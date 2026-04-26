import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Widgets/MenuGridWidget.dart';
import 'package:point_of_sales_app_v3/Widgets/SidebarWidget.dart' show kDarkTeal;

class OrderingViewWidget extends StatefulWidget {
  final List<MenuObject> menuObjectList_makanan;
  final List<MenuObject> menuObjectList_minuman;
  final List<String> categoryOrder;
  final bool isTakeAway;
  final Function(bool) onTakeAwayChanged;
  final Function(MenuObject) onMenuTap;

  const OrderingViewWidget({
    Key? key,
    required this.menuObjectList_makanan,
    required this.menuObjectList_minuman,
    required this.categoryOrder,
    required this.isTakeAway,
    required this.onTakeAwayChanged,
    required this.onMenuTap,
  }) : super(key: key);

  @override
  State<OrderingViewWidget> createState() => _OrderingViewWidgetState();
}

class _OrderingViewWidgetState extends State<OrderingViewWidget> {
  // 0 = Makanan, 1 = Minuman
  int _topTabIndex = 0;
  String? _selectedCategory; // null = "Semua"
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _topTabIndex);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  List<MenuObject> get _currentItems =>
      _topTabIndex == 0 ? widget.menuObjectList_makanan : widget.menuObjectList_minuman;

  List<String> get _currentCategories {
    final categories = _currentItems.map((e) => e.category).toSet().toList();
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

  List<MenuObject> get _filteredItems {
    // Search overrides category filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      final allItems = [
        ...widget.menuObjectList_makanan,
        ...widget.menuObjectList_minuman,
      ];
      return allItems
          .where((m) => m.namaMenu.toLowerCase().contains(query))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    if (_selectedCategory != null) {
      // Single category: sort by sortOrder only
      return _currentItems
          .where((m) => m.category == _selectedCategory)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    // "Semua": sort by categoryOrder first, then sortOrder within each category
    final catOrder = widget.categoryOrder;
    return List<MenuObject>.from(_currentItems)
      ..sort((a, b) {
        final catA = catOrder.indexOf(a.category);
        final catB = catOrder.indexOf(b.category);
        // Unknown categories go to end
        final orderA = catA == -1 ? 999 : catA;
        final orderB = catB == -1 ? 999 : catB;
        if (orderA != orderB) return orderA.compareTo(orderB);
        return a.sortOrder.compareTo(b.sortOrder);
      });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // === TOP LAYER: Makanan / Minuman + Search ===
          _buildTopBar(),
          // === SECOND LAYER: Category chips (hidden during search) ===
          if (_searchQuery.isEmpty) _buildCategoryChips(),
          // === MENU ITEMS GRID (swipeable between Makanan / Minuman) ===
          Expanded(
            child: _searchQuery.isNotEmpty
                ? (_filteredItems.isEmpty
                    ? _buildEmptyState()
                    : MenuGridWidget(
                        menuObjectList: _filteredItems,
                        onMenuTap: widget.onMenuTap,
                      ))
                : PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _topTabIndex = index;
                        _selectedCategory = null;
                      });
                    },
                    children: [
                      _buildPageContent(0),
                      _buildPageContent(1),
                    ],
                  ),
          ),
          // === BUNGKUS CHECKBOX ===
          const Divider(height: 1),
          _buildTakeAwayRow(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // Makanan / Minuman toggle
          _buildTopTab('Makanan', 0),
          const SizedBox(width: 4),
          _buildTopTab('Minuman', 1),
          const SizedBox(width: 16),
          // Search bar
          Expanded(child: _buildSearchBar()),
        ],
      ),
    );
  }

  Widget _buildPageContent(int tabIndex) {
    final items = tabIndex == 0
        ? widget.menuObjectList_makanan
        : widget.menuObjectList_minuman;

    List<MenuObject> filtered;
    if (_selectedCategory != null) {
      filtered = items
          .where((m) => m.category == _selectedCategory)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    } else {
      final catOrder = widget.categoryOrder;
      filtered = List<MenuObject>.from(items)
        ..sort((a, b) {
          final catA = catOrder.indexOf(a.category);
          final catB = catOrder.indexOf(b.category);
          final orderA = catA == -1 ? 999 : catA;
          final orderB = catB == -1 ? 999 : catB;
          if (orderA != orderB) return orderA.compareTo(orderB);
          return a.sortOrder.compareTo(b.sortOrder);
        });
    }

    if (filtered.isEmpty) return _buildEmptyState();
    return MenuGridWidget(
      menuObjectList: filtered,
      onMenuTap: widget.onMenuTap,
    );
  }

  Widget _buildTopTab(String label, int index) {
    final isActive = _searchQuery.isEmpty && _topTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _topTabIndex = index;
          _selectedCategory = null;
          _searchQuery = '';
          _searchController.clear();
        });
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? kDarkTeal : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() => _searchQuery = value.trim());
        },
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Cari menu...',
          hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey.shade500),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final categories = _currentCategories;
    final allCount = _currentItems.length;

    return Container(
      height: 48,
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // "Semua" chip
          _buildCategoryChip('Semua', allCount, null),
          ...categories.map((cat) {
            final count = _currentItems.where((m) => m.category == cat).length;
            return _buildCategoryChip(cat, count, cat);
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, int count, String? categoryValue) {
    final isActive = _selectedCategory == categoryValue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedCategory = categoryValue);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? kDarkTeal.withValues(alpha: 0.1) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? kDarkTeal : Colors.grey.shade300,
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? kDarkTeal : Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isActive ? kDarkTeal : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTakeAwayRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Checkbox(
            value: widget.isTakeAway,
            onChanged: (value) => widget.onTakeAwayChanged(value ?? false),
          ),
          GestureDetector(
            onTap: () => widget.onTakeAwayChanged(!widget.isTakeAway),
            child: const Text('Bungkus'),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty
                ? 'Tidak ada menu "$_searchQuery"'
                : 'Tidak ada menu dalam kategori ini',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
