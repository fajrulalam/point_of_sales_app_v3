import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';

class MenuObject {
  String id;
  String namaMenu;
  int harga;
  bool isMakanan;
  String imagePath;
  String category;
  List<MenuIngredient> ingredients;
  int unitsPerPackage;
  bool isFeatured;
  String description;

  MenuObject({
    required this.id,
    required this.namaMenu,
    required this.harga,
    required this.isMakanan,
    required this.imagePath,
    this.category = 'Umum',
    this.ingredients = const [],
    this.unitsPerPackage = 1,
    this.isFeatured = false,
    this.description = '',
  });
}

class MenuClass {
  static List<MenuObject> getAllMenus(QuerySnapshot<Object?> snapshot) {
    List<MenuObject> menus = [];

    for (var element in snapshot.docs) {
      final data = element.data() as Map<String, dynamic>;
      menus.add(
        MenuObject(
          id: element.id,
          namaMenu: data['namaMenu'],
          harga: data['harga'],
          isMakanan: data['isMakanan'],
          imagePath: data['imagePath'],
          category: data.containsKey('category') ? data['category'] : 'Umum',
          unitsPerPackage: data.containsKey('unitsPerPackage') ? data['unitsPerPackage'] : 1,
          isFeatured: data['isFeatured'] ?? false,
          description: data['description'] ?? '',
          ingredients: data.containsKey('ingredients')
              ? (data['ingredients'] as List<dynamic>)
                  .map((ing) => MenuIngredient.fromMap(ing as Map<String, dynamic>))
                  .toList()
              : [],
        ),
      );
    }

    return menus;
  }
}
