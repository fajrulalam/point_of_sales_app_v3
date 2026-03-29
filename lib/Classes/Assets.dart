import 'package:cloud_firestore/cloud_firestore.dart';

class AssetsObject {
  String id;
  bool isMakanan;
  String path;

  AssetsObject({
    required this.id,
    required this.isMakanan,
    required this.path,
  });
}

class AssetsClass {
  static List<AssetsObject> getImageAssets(QuerySnapshot<Object?> snapshot) {
    List<AssetsObject> assets = [];

    for (var element in snapshot.docs) {
      assets.add(
        AssetsObject(
          id: element.id,
          isMakanan: element['isMakanan'],
          path: element['path'],
        ),
      );
    }

    return assets;
  }
}
