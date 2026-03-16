import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';

class MenuGridWidget extends StatelessWidget {
  final List<MenuObject> menuObjectList;
  final Function(MenuObject) onMenuTap;

  const MenuGridWidget({
    Key? key,
    required this.menuObjectList,
    required this.onMenuTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: menuObjectList.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.width ~/ 240,
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
        childAspectRatio: 180 / 180,
      ),
      itemBuilder: (BuildContext context, int index) {
        if (menuObjectList.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final menu = menuObjectList[index];

        return FutureBuilder<MenuAvailability>(
          future: InventoryService().checkMenuAvailability(menu, 1),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final isAvailable = snapshot.data?.isAvailable ?? true;
            final hasWarning = snapshot.data?.hasWarning ?? false;
            final availabilityMessage = snapshot.data?.message ?? '';

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasWarning
                      ? Colors.orange.shade300
                      : (isAvailable ? Colors.grey.shade300 : Colors.red.shade300),
                  width: (hasWarning || !isAvailable) ? 2 : 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isAvailable
                      ? () => onMenuTap(menu)
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.white),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      availabilityMessage,
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: Colors.red.shade700,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (menu.imagePath != 'tidak ada')
                              SizedBox(
                                height: 110,
                                width: 110,
                                child: Image(
                                  image:
                                      CachedNetworkImageProvider(menu.imagePath),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Text(
                                menu.namaMenu,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.montserrat(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Ingredient indicator
                      if (menu.ingredients.isNotEmpty)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: hasWarning
                                  ? Colors.orange
                                  : (isAvailable ? Colors.green : Colors.red),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.inventory_2,
                                  size: 12,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  hasWarning ? 'LOW' : (isAvailable ? 'OK' : 'X'),
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Warning overlay for Low Stock
                      if (hasWarning)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.warning_amber_rounded,
                                size: 16, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
