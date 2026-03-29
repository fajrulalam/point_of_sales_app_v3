import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:point_of_sales_app_v3/BottomSheets/EditCategoryBottomSheet.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Widgets/MenuGridWidget.dart';
import 'package:point_of_sales_app_v3/Widgets/SidebarWidget.dart' show kDarkTeal;
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

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
  String? selectedCategoryMakanan;
  String? selectedCategoryMinuman;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TabBar(
              labelColor: const Color(0xFF1A1A1A),
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.normal, fontSize: 14),
              unselectedLabelColor: Colors.grey.shade500,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: kDarkTeal.withOpacity(0.08),
                border: Border(
                  bottom: BorderSide(
                    color: kDarkTeal,
                    width: 3,
                  ),
                ),
              ),
              tabs: const [
                Tab(text: 'Makanan'),
                Tab(text: 'Minuman'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildSubCategoryView(
                    items: widget.menuObjectList_makanan,
                    selectedCategory: selectedCategoryMakanan,
                    onCategorySelected: (category) {
                      setState(() {
                        selectedCategoryMakanan = category;
                      });
                    },
                    onBack: () {
                      setState(() {
                        selectedCategoryMakanan = null;
                      });
                    },
                  ),
                  _buildSubCategoryView(
                    items: widget.menuObjectList_minuman,
                    selectedCategory: selectedCategoryMinuman,
                    onCategorySelected: (category) {
                      setState(() {
                        selectedCategoryMinuman = category;
                      });
                    },
                    onBack: () {
                      setState(() {
                        selectedCategoryMinuman = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                Checkbox(
                  value: widget.isTakeAway,
                  onChanged: (value) => widget.onTakeAwayChanged(value ?? false),
                ),
                GestureDetector(
                  onTap: () => widget.onTakeAwayChanged(!widget.isTakeAway),
                  child: const Text('Bungkus'),
                ),
                const SizedBox(width: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubCategoryView({
    required List<MenuObject> items,
    required String? selectedCategory,
    required Function(String) onCategorySelected,
    required VoidCallback onBack,
  }) {
    if (selectedCategory == null) {
      // Show Category Grid
      final categories = items.map((e) => e.category).toSet().toList();
      
      // Sort by position in categoryOrder, unknowns go to end
      categories.sort((a, b) {
        final indexA = widget.categoryOrder.indexOf(a);
        final indexB = widget.categoryOrder.indexOf(b);
        
        // If both are in the order list, sort by their position
        if (indexA != -1 && indexB != -1) return indexA.compareTo(indexB);
        // If only a is in list, a comes first
        if (indexA != -1) return -1;
        // If only b is in list, b comes first
        if (indexB != -1) return 1;
        // If neither is in list, sort alphabetically
        return a.compareTo(b);
      });

      return GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, index) {
          final category = categories[index];
          return _CategoryCard(
            category: category,
            onTap: () => onCategorySelected(category),
            onLongPress: () async {
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (context) => EditCategoryBottomSheet(categoryName: category),
              );
              // Trigger rebuild if necessary, though StreamBuilder/FutureBuilder in card handles image.
              // If name changed, parent widget might need set state to refresh list, but 
              // OrderingViewWidget gets lists from parent. Parent needs to refresh.
              // For now, we assume simple image edits.
              // If name changed, the category list derived from items might be stale until parent refreshes data.
              
            },
          );
        },
      );
    } else {
      // Show Items Grid for Selected Category
      final filteredItems =
          items.where((e) => e.category == selectedCategory).toList();

      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_ios),
                  color: kDarkTeal,
                ),
                Text(
                  selectedCategory,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: kDarkTeal,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: MenuGridWidget(
              menuObjectList: filteredItems,
              onMenuTap: widget.onMenuTap,
            ),
          ),
        ],
      );
    }
  }
}

class _CategoryCard extends StatelessWidget {
  final String category;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CategoryCard({
    required this.category,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection(Col.name('Categories')).doc(category).snapshots(),
      builder: (context, snapshot) {
        String? imagePath;
        if (snapshot.hasData && snapshot.data!.exists) {
           final data = snapshot.data!.data() as Map<String, dynamic>;
           if (data.containsKey('imagePath')) {
             imagePath = data['imagePath'];
           }
        }

        return InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Background Image or Gradient
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: imagePath != null
                        ? CachedNetworkImage(
                            imageUrl: imagePath,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: Colors.grey.shade200),
                            errorWidget: (context, url, error) => _buildDefaultGradient(),
                          )
                        : _buildDefaultGradient(),
                  ),
                ),
                // Overlay for Readability
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.black.withOpacity(0.3),
                    ),
                  ),
                ),
                // Category Name
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      category,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14, // Smaller font for 4-column grid
                        fontWeight: FontWeight.bold,
                        shadows: [
                          const Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
                        ],
                      ),
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

  Widget _buildDefaultGradient() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kDarkTeal.withOpacity(0.7), kDarkTeal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}
