import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';

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

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onMenuTap(menuObjectList[index]),
              borderRadius: BorderRadius.circular(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (menuObjectList[index].imagePath != 'tidak ada')
                    SizedBox(
                      height: 110,
                      width: 110,
                      child: Image(
                        image: CachedNetworkImageProvider(
                            menuObjectList[index].imagePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  Text(
                    menuObjectList[index].namaMenu,
                    style: GoogleFonts.montserrat(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
