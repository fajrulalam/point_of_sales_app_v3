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
    final hasPortraitImage =
        menuObjectList.any((m) => m.imageAspectRatio == '3:4');
    final gridAspectRatio = hasPortraitImage ? 0.6 : 0.8;

    return GridView.builder(
      itemCount: menuObjectList.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.width ~/ 240,
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
        childAspectRatio: gridAspectRatio,
      ),
      itemBuilder: (BuildContext context, int index) {
        if (menuObjectList.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final menu = menuObjectList[index];
        final isPortrait = menu.imageAspectRatio == '3:4';
        final imgHeight = isPortrait ? 147.0 : 110.0;
        final imgWidth = 110.0;

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
                      : (isAvailable
                          ? Colors.grey.shade300
                          : Colors.red.shade300),
                  width: (hasWarning || !isAvailable) ? 2 : 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isAvailable
                      ? () => onMenuTap(menu)
                      : () {
                          ScaffoldMessenger.of(context)
                            ..clearSnackBars()
                            ..showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Colors.white),
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
                                height: imgHeight,
                                width: imgWidth,
                                child: Image(
                                  image: CachedNetworkImageProvider(
                                      menu.imagePath),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Flexible(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  menu.namaMenu,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (menu.ingredients.isNotEmpty)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Builder(builder: (_) {
                            final maxServings = InventoryService()
                                .getMaxServings(menu.ingredients);
                            final count = maxServings ?? 0;
                            final Color bg;
                            if (count <= 0) {
                              bg = Colors.red;
                            } else if (count <= 5) {
                              bg = Colors.orange;
                            } else {
                              bg = Colors.green;
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.inventory_2,
                                      size: 12, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$count',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
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
