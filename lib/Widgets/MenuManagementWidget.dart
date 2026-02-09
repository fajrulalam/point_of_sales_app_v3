import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Classes/Assets.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/BottomSheets/AddOrEditMenu.dart';

class MenuManagementWidget extends StatelessWidget {
  final List<MenuObject> menuObjectList_makanan;
  final List<MenuObject> menuObjectList_minuman;
  final List<AssetsObject> listGambar;

  const MenuManagementWidget({
    Key? key,
    required this.menuObjectList_makanan,
    required this.menuObjectList_minuman,
    required this.listGambar,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: Colors.white,
      child: Row(
        children: [
          // Makanan Section
          Expanded(
            child: _buildMenuSection(
              context: context,
              title: 'Makanan',
              menuList: menuObjectList_makanan,
              makananOrMinuman: 'Makanan',
            ),
          ),
          const SizedBox(width: 16),
          // Minuman Section
          Expanded(
            child: _buildMenuSection(
              context: context,
              title: 'Minuman',
              menuList: menuObjectList_minuman,
              makananOrMinuman: 'Minuman',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection({
    required BuildContext context,
    required String title,
    required List<MenuObject> menuList,
    required String makananOrMinuman,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: GoogleFonts.montserrat(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
            const SizedBox(width: 24),
            GestureDetector(
              onTap: () => _addOrEditMenu(
                context,
                query: 'add',
                makananOrMinuman: makananOrMinuman,
              ),
              child: Container(
                height: 35,
                width: 50,
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const InkWell(
                  child: Icon(
                    Icons.add,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: ListView.separated(
            separatorBuilder: (context, index) => Divider(
              color: Colors.grey.withOpacity(0.5),
              height: 0.4,
            ),
            itemCount: menuList.length,
            shrinkWrap: true,
            itemBuilder: (BuildContext context, int index) {
              return ListTile(
                title: Text(
                  menuList[index].namaMenu,
                  style: GoogleFonts.poppins(),
                ),
                trailing: SizedBox(
                  width: 135,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton(
                        child: const Icon(Icons.edit),
                        onPressed: () => _addOrEditMenu(
                          context,
                          query: 'edit',
                          makananOrMinuman: makananOrMinuman,
                          menuObject: menuList[index],
                        ),
                      ),
                      OutlinedButton(
                        child: const Icon(
                          Icons.delete,
                          color: Colors.redAccent,
                        ),
                        onPressed: () => _deleteMenu(menuList[index].id),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _addOrEditMenu(
    BuildContext context, {
    required String query,
    required String makananOrMinuman,
    MenuObject? menuObject,
  }) {
    showModalBottomSheet(
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16.0),
          topRight: Radius.circular(16.0),
        ),
      ),
      builder: (context) {
        if (query == 'edit') {
          return AddMenuBottomSheet(
            query: query,
            makananOrMinuman: makananOrMinuman,
            menuObject: menuObject,
            listGambar: listGambar,
          );
        } else {
          return AddMenuBottomSheet(
            query: query,
            makananOrMinuman: makananOrMinuman,
            listGambar: listGambar,
          );
        }
      },
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
}
