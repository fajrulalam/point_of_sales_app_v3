import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';

class OptionItem {
  String id;
  String name;
  int priceAdjustment; // 0 for free, positive for add-on price
  List<MenuIngredient> ingredients;

  OptionItem({
    required this.id,
    required this.name,
    this.priceAdjustment = 0,
    this.ingredients = const [],
  });

  factory OptionItem.fromMap(Map<String, dynamic> map, {String? id}) {
    return OptionItem(
      id: id ?? map['id'] ?? '',
      name: map['name'] ?? '',
      priceAdjustment: map['priceAdjustment'] ?? 0,
      ingredients: map.containsKey('ingredients')
          ? (map['ingredients'] as List<dynamic>)
              .map((ing) => MenuIngredient.fromMap(ing as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'priceAdjustment': priceAdjustment,
      'ingredients': ingredients.map((ing) => ing.toMap()).toList(),
    };
  }

  String get formattedPrice {
    if (priceAdjustment == 0) return 'Gratis';
    final prefix = priceAdjustment > 0 ? '+' : '-';
    final formatted = priceAdjustment.abs().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return '${prefix}Rp$formatted';
  }
}

class OptionGroup {
  String id;
  String name;
  bool isRequired; // true = mandatory selection, false = optional
  int minSelection; // minimum items to select (0 for optional)
  int maxSelection; // maximum items to select (0 = unlimited)
  List<OptionItem> options;
  List<String> linkedMenuItems; // List of menu item IDs this group is linked to

  OptionGroup({
    required this.id,
    required this.name,
    this.isRequired = false,
    this.minSelection = 0,
    this.maxSelection = 0,
    this.options = const [],
    this.linkedMenuItems = const [],
  });

  factory OptionGroup.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return OptionGroup(
      id: doc.id,
      name: data['name'] ?? '',
      isRequired: data['isRequired'] ?? false,
      minSelection: data['minSelection'] ?? 0,
      maxSelection: data['maxSelection'] ?? 0,
      options: (data['options'] as List<dynamic>?)
              ?.map((o) => OptionItem.fromMap(o as Map<String, dynamic>))
              .toList() ??
          [],
      linkedMenuItems: List<String>.from(data['linkedMenuItems'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'isRequired': isRequired,
      'minSelection': minSelection,
      'maxSelection': maxSelection,
      'options': options.map((o) => o.toMap()).toList(),
      'linkedMenuItems': linkedMenuItems,
    };
  }

  String get statusLabel => isRequired ? 'Wajib' : 'Opsional';

  int get optionCount => options.length;
}

class OptionGroupService {
  static final OptionGroupService _instance = OptionGroupService._internal();
  factory OptionGroupService() => _instance;
  OptionGroupService._internal();

  final _firestore = FirebaseFirestore.instance;
  
  CollectionReference get _collection => _firestore
      .collection(Col.name('Canteens'))
      .doc('canteen375')
      .collection('OptionGroups');

  Stream<List<OptionGroup>> getOptionGroupsStream() {
    return _collection.orderBy('name').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => OptionGroup.fromFirestore(doc)).toList();
    });
  }

  Future<void> createOptionGroup(OptionGroup group) async {
    await _collection.add(group.toMap());
  }

  Future<void> updateOptionGroup(OptionGroup group) async {
    await _collection.doc(group.id).update(group.toMap());
  }

  Future<void> deleteOptionGroup(String groupId) async {
    await _collection.doc(groupId).delete();
  }

  Future<void> linkMenuItems(String groupId, List<String> menuItemIds) async {
    await _collection.doc(groupId).update({'linkedMenuItems': menuItemIds});
  }

}
