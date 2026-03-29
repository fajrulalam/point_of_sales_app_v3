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
  bool isRecommended;
  String menuDescription;
  int sortOrder;
  String imageAspectRatio;

  MenuObject({
    required this.id,
    required this.namaMenu,
    required this.harga,
    required this.isMakanan,
    required this.imagePath,
    this.category = 'Umum',
    this.ingredients = const [],
    this.unitsPerPackage = 1,
    this.isRecommended = false,
    this.menuDescription = '',
    this.sortOrder = 0,
    this.imageAspectRatio = '1:1',
  });
}

class MenuClass {
  static List<MenuObject> getAllMenus(QuerySnapshot<Object?> snapshot) {
    List<MenuObject> menus = [];

    int parseInt(dynamic value, int defaultValue) {
      if (value == null) return defaultValue;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    for (var element in snapshot.docs) {
      try {
        final data = element.data() as Map<String, dynamic>;
        menus.add(
          MenuObject(
            id: element.id,
            namaMenu: data['namaMenu']?.toString() ?? 'Unnamed Item',
            harga: parseInt(data['harga'], 0),
            isMakanan: data['isMakanan'] ?? true,
            imagePath: data['imagePath'] ?? 'tidak ada',
            category: data['category']?.toString() ?? 'Umum',
            unitsPerPackage: parseInt(data['unitsPerPackage'], 1),
            isRecommended: data['isRecommended'] ?? false,
            menuDescription: data['menuDescription']?.toString() ?? '',
            sortOrder: parseInt(data['sortOrder'], 0),
            imageAspectRatio: data['imageAspectRatio']?.toString() ?? '1:1',
            ingredients: data.containsKey('ingredients') && data['ingredients'] != null
                ? (data['ingredients'] as List<dynamic>)
                    .map((ing) => MenuIngredient.fromMap(ing as Map<String, dynamic>))
                    .toList()
                : [],
          ),
        );
      } catch (e) {
        print('Error parsing menu item ${element.id}: $e');
      }
    }

    return menus;
  }
}
