import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Models/RecommendationModels.dart';
import 'package:point_of_sales_app_v3/Services/RecommendationService.dart';

class RecommendationListWidget extends StatefulWidget {
  final List<Recommendation> recommendations;
  final Function(String) onRecommendationTap;
  final List<String> menuItems; // Available menu items to filter variations

  const RecommendationListWidget({
    Key? key,
    required this.recommendations,
    required this.onRecommendationTap,
    this.menuItems = const [],
  }) : super(key: key);

  @override
  State<RecommendationListWidget> createState() =>
      _RecommendationListWidgetState();
}

class _RecommendationListWidgetState extends State<RecommendationListWidget> {
  // Track which categories are expanded
  final Set<int> _expandedIndices = {};

  @override
  Widget build(BuildContext context) {
    if (widget.recommendations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Tidak ada rekomendasi',
            style: GoogleFonts.poppins(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Rekomendasi',
                  style: GoogleFonts.poppins(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.recommendations.length} kategori',
                  style: GoogleFonts.poppins(
                    color: Colors.blue.shade700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Recommendations List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: widget.recommendations.length,
              itemBuilder: (context, index) {
                final rec = widget.recommendations[index];
                final isExpanded = _expandedIndices.contains(index);
                return _buildCategoryCard(rec, index, isExpanded);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(Recommendation rec, int index, bool isExpanded) {
    // Get available variations for this category
    final variations = _getAvailableVariations(rec.itemName);
    final hasVariations = variations.length > 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Category header (always visible)
          InkWell(
            onTap: () {
              if (hasVariations) {
                // Toggle expansion
                setState(() {
                  if (isExpanded) {
                    _expandedIndices.remove(index);
                  } else {
                    _expandedIndices.add(index);
                  }
                });
              } else if (variations.length == 1) {
                // Only one variation, add it directly
                widget.onRecommendationTap(variations.first);
              }
            },
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(8),
              bottom: Radius.circular(isExpanded ? 0 : 8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Category icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getCategoryIcon(rec.itemName),
                      color: Colors.blue.shade700,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Category name and variations count
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rec.itemName,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        if (hasVariations)
                          Text(
                            '${variations.length} variasi tersedia',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Confidence badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getConfidenceColor(rec.confidence),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(rec.confidence * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Expand/collapse icon
                  if (hasVariations) ...[
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded variations list
          if (isExpanded && hasVariations)
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Column(
                children: [
                  const Divider(height: 1),
                  ...variations.map((variation) => _buildVariationItem(variation)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVariationItem(String variation) {
    return InkWell(
      onTap: () => widget.onRecommendationTap(variation),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.add_circle_outline,
              size: 18,
              color: Colors.green.shade600,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                variation,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  /// Get available variations for a category, filtered by menu items
  List<String> _getAvailableVariations(String categoryName) {
    final canonicalName = categoryName.toLowerCase().trim();
    
    // Get all variations from the service
    final allVariations =
        RecommendationService.instance.expandItemName(canonicalName);

    // If no menu items provided, return all variations
    if (widget.menuItems.isEmpty) {
      return allVariations;
    }

    // Filter to only include variations that exist in the menu
    final normalizedMenu =
        widget.menuItems.map((m) => m.toLowerCase().trim()).toSet();

    final availableVariations = allVariations.where((variation) {
      return normalizedMenu.contains(variation.toLowerCase().trim());
    }).toList();

    // If no variations match, at least show the category name if it exists in menu
    if (availableVariations.isEmpty) {
      // Check if the category name itself exists in menu
      if (normalizedMenu.contains(canonicalName)) {
        return [categoryName];
      }
      // Otherwise return empty - this category should not be shown
      return [];
    }

    return availableVariations;
  }

  /// Get icon for a category
  IconData _getCategoryIcon(String categoryName) {
    final name = categoryName.toLowerCase();
    if (name.contains('mie')) return Icons.ramen_dining;
    if (name.contains('nasi') || name.contains('goreng')) return Icons.rice_bowl;
    if (name.contains('teh') || name.contains('kopi') || name.contains('float'))
      return Icons.local_cafe;
    if (name.contains('air') || name.contains('jeruk') || name.contains('es'))
      return Icons.local_drink;
    if (name.contains('penyetan') || name.contains('sayur'))
      return Icons.restaurant;
    if (name.contains('gorengan') || name.contains('cireng') || name.contains('sosis'))
      return Icons.fastfood;
    return Icons.lunch_dining;
  }

  /// Get color based on confidence level
  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green.shade600;
    if (confidence >= 0.6) return Colors.blue.shade600;
    if (confidence >= 0.5) return Colors.orange.shade600;
    return Colors.grey.shade600;
  }
}
