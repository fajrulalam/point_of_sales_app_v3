import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Widgets/MenuGridWidget.dart';

class OrderingViewWidget extends StatelessWidget {
  final List<MenuObject> menuObjectList_makanan;
  final List<MenuObject> menuObjectList_minuman;
  final bool isTakeAway;
  final Function(bool) onTakeAwayChanged;
  final Function(MenuObject) onMenuTap;

  const OrderingViewWidget({
    Key? key,
    required this.menuObjectList_makanan,
    required this.menuObjectList_minuman,
    required this.isTakeAway,
    required this.onTakeAwayChanged,
    required this.onMenuTap,
  }) : super(key: key);

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
              labelColor: Colors.teal,
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              unselectedLabelStyle:
                  GoogleFonts.poppins(fontWeight: FontWeight.normal),
              unselectedLabelColor: Colors.grey.shade400,
              indicatorColor: Colors.teal,
              tabs: const [
                Tab(text: 'Makanan'),
                Tab(text: 'Minuman'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  MenuGridWidget(
                    menuObjectList: menuObjectList_makanan,
                    onMenuTap: onMenuTap,
                  ),
                  MenuGridWidget(
                    menuObjectList: menuObjectList_minuman,
                    onMenuTap: onMenuTap,
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
                  value: isTakeAway,
                  onChanged: (value) => onTakeAwayChanged(value ?? false),
                ),
                GestureDetector(
                  onTap: () => onTakeAwayChanged(!isTakeAway),
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
}
