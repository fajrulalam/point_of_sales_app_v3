import 'package:cloud_firestore/cloud_firestore.dart';

class MenuObject {
  String id;
  String namaMenu;
  int harga;
  bool isMakanan;
  String imagePath;

  MenuObject({
    required this.id,
    required this.namaMenu,
    required this.harga,
    required this.isMakanan,
    required this.imagePath,
  });
}

class MenuClass {
  static List<MenuObject> getAllMenus(QuerySnapshot<Object?> snapshot) {
    List<MenuObject> menus = [];

    for (var element in snapshot.docs) {
      print(element['namaMenu']);
      menus.add(
        MenuObject(
          id: element.id,
          namaMenu: element['namaMenu'],
          harga: element['harga'],
          isMakanan: element['isMakanan'],
          imagePath: element['imagePath'],
        ),
      );
    }

    return menus;
  }
}
