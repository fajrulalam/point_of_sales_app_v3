import 'package:cloud_firestore/cloud_firestore.dart';

class AssetsObject {
  bool isMakanan;
  String path;

  AssetsObject({
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
          isMakanan: element['isMakanan'],
          path: element['path'],
        ),
      );
    }

    return assets;
  }
}
