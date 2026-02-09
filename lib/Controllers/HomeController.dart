import 'dart:async';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Assets.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';

class HomeController extends ChangeNotifier {
  // State variables
  Color orderButtonColor = Colors.white;
  Color menuButtonColor = Colors.grey.shade300;
  Color printButtonColor = Colors.grey.shade300;
  double orderButtonOffset_y = 0;
  double menuButtonOffset_y = 4;
  double printButtonOffset_y = 4;

  int nomorBerikutnya = 0;
  List<MenuObject> menuObjectList = [];
  List<MenuObject> menuObjectList_makanan = [];
  List<MenuObject> menuObjectList_minuman = [];
  List<PesananObject> pesananList = [];
  List<AssetsObject> listGambar = [];

  List<String> quoteKejujuran = [
    'Jujur itu menyenangkan',
    'Jujur itu menyehatkan',
    'Jujur itu menguntungkan',
    'Jujur itu membebaskan',
    'Jujur itu menyelamatkan',
    'Jujur itu menyatukan',
    'Jujur itu mempererat persaudaraan',
    'Jujur itu mempererat persahabatan',
    'Bukalah hatimu dan bertindaklah jujur',
    'Jujur itu kewajiban, bukan pilihan',
    'Jujur itu kebutuhan, bukan keinginan',
  ];

  int totalHarga = 0;
  int jumlahItem = 0;
  int biayaBungkus = 0;
  bool isUangKurang = false;
  bool isTakeAway = false;

  // Printer related
  BluetoothDevice? selectedDevice;
  BlueThermalPrinter printer = BlueThermalPrinter.instance;
  bool printerIsConnected = false;

  Timer? timer;

  // Initialize controller
  void initialize() {
    getMenu();
    getListGambar();
  }

  // Menu Management
  void getMenu() {
    DocumentReference customerNumber =
        FirebaseFirestore.instance.collection('Canteens').doc('canteen375');

    customerNumber.snapshots().listen((event) {
      Map map = event.data() as Map<String, dynamic>;
      nomorBerikutnya = map['customerNumber'] + 1;
      notifyListeners();
    });

    CollectionReference menuCollection = FirebaseFirestore.instance
        .collection('Canteens')
        .doc('canteen375')
        .collection('MenuCollection');

    menuCollection.snapshots().listen((snapshot) {
      menuObjectList = MenuClass.getAllMenus(snapshot);
      menuObjectList_makanan =
          menuObjectList.where((element) => element.isMakanan == true).toList();
      menuObjectList_minuman = menuObjectList
          .where((element) => element.isMakanan == false)
          .toList();
      notifyListeners();
    });
  }

  Future<void> getListGambar() async {
    FirebaseFirestore.instance.collection('assets').get().then((value) {
      listGambar = AssetsClass.getImageAssets(value);
      notifyListeners();
    });
  }

  // Order Management
  void addToOrder(MenuObject menu, bool isTakeAway) {
    int orderIndex = pesananList
        .indexWhere((element) => element.namaPesanan == menu.namaMenu);

    if (orderIndex == -1) {
      if (isTakeAway) {
        pesananList.add(PesananObject(
          namaPesanan: menu.namaMenu,
          harga: menu.harga,
          dineInQuantity: 0,
          takeAwayQuantity: 1,
        ));
      } else {
        pesananList.add(PesananObject(
          namaPesanan: menu.namaMenu,
          harga: menu.harga,
          dineInQuantity: 1,
          takeAwayQuantity: 0,
        ));
      }
    } else {
      if (isTakeAway) {
        pesananList[orderIndex].takeAwayQuantity++;
      } else {
        pesananList[orderIndex].dineInQuantity++;
      }
    }
    getTotal();
  }

  void incrementDineIn(int index) {
    pesananList[index].dineInQuantity++;
    getTotal();
  }

  void decrementDineIn(int index) {
    if (pesananList[index].dineInQuantity > 0) {
      pesananList[index].dineInQuantity--;
      if (pesananList[index].totalQuantity == 0) {
        pesananList.removeAt(index);
      }
    }
    getTotal();
  }

  void incrementTakeAway(int index) {
    pesananList[index].takeAwayQuantity++;
    getTotal();
  }

  void decrementTakeAway(int index) {
    if (pesananList[index].takeAwayQuantity > 0) {
      pesananList[index].takeAwayQuantity--;
      if (pesananList[index].totalQuantity == 0) {
        pesananList.removeAt(index);
      }
    }
    getTotal();
  }

  void toggleTakeAway() {
    isTakeAway = !isTakeAway;
    notifyListeners();
  }

  void setTakeAway(bool value) {
    isTakeAway = value;
    notifyListeners();
  }

  // Add recommended item (via association rules)
  void addRecommendedItem(String itemName, int quantity) {
    // Find the menu item by name (case-insensitive)
    final menuItem = menuObjectList.firstWhere(
      (menu) => menu.namaMenu.toLowerCase() == itemName.toLowerCase(),
      orElse: () => menuObjectList.first, // Fallback (shouldn't happen)
    );

    // Check if item already exists in order
    final orderIndex = pesananList.indexWhere((element) =>
        element.namaPesanan.toLowerCase() == itemName.toLowerCase());

    if (orderIndex == -1) {
      // Add new item with viaAssociationRules = true
      if (isTakeAway) {
        pesananList.add(PesananObject(
          namaPesanan: menuItem.namaMenu,
          harga: menuItem.harga,
          dineInQuantity: 0,
          takeAwayQuantity: quantity,
          viaAssociationRules: true,
        ));
      } else {
        pesananList.add(PesananObject(
          namaPesanan: menuItem.namaMenu,
          harga: menuItem.harga,
          dineInQuantity: quantity,
          takeAwayQuantity: 0,
          viaAssociationRules: true,
        ));
      }
      print(
          '✅ Added recommended item: ${menuItem.namaMenu} (via association rules)');
    } else {
      // Item exists, increment quantity and mark as via association rules
      if (isTakeAway) {
        pesananList[orderIndex].takeAwayQuantity += quantity;
      } else {
        pesananList[orderIndex].dineInQuantity += quantity;
      }
      pesananList[orderIndex].viaAssociationRules = true;
      print(
          '✅ Incremented recommended item: ${menuItem.namaMenu} (via association rules)');
    }

    getTotal();
    notifyListeners();
  }

  // Price Calculations
  void getTotal() {
    int subtotal = pesananList.fold(0, (acc, order) => acc + order.subtotal);
    int totalTakeAway =
        pesananList.fold(0, (sum, order) => sum + order.takeAwayQuantity);
    biayaBungkus = (totalTakeAway ~/ 4) * 1000;
    totalHarga = subtotal + biayaBungkus;
    notifyListeners();
  }

  // Button State Management
  void changeButtonColors(String buttonType) {
    switch (buttonType) {
      case 'print':
        printButtonColor = Colors.white;
        printButtonOffset_y = 0;
        menuButtonOffset_y = 4;
        menuButtonColor = Colors.grey.shade300;
        orderButtonColor = Colors.grey.shade300;
        orderButtonOffset_y = 4;
        break;
      case 'order':
        printButtonColor = Colors.grey.shade300;
        printButtonOffset_y = 4;
        menuButtonOffset_y = 4;
        menuButtonColor = Colors.grey.shade300;
        orderButtonColor = Colors.white;
        orderButtonOffset_y = 0;
        break;
      case 'menu':
        printButtonColor = Colors.grey.shade300;
        printButtonOffset_y = 4;
        menuButtonOffset_y = 0;
        menuButtonColor = Colors.white;
        orderButtonColor = Colors.grey.shade300;
        orderButtonOffset_y = 4;
        break;
      default:
        break;
    }
    notifyListeners();
  }

  // Printer Management
  Future<void> checkIfPrinterIsConnected() async {
    if ((await printer.isConnected)!) {
      printerIsConnected = true;
    } else {
      printerIsConnected = false;
    }
    notifyListeners();
  }

  Future<void> connectPrinter(BluetoothDevice device) async {
    try {
      selectedDevice = device;
      await printer.connect(device);
      await checkIfPrinterIsConnected();
    } catch (e) {
      print('Error connecting to printer: $e');
      rethrow;
    }
  }

  Future<void> printReceipt(List<PesananObject> pesananList,
      int nomorBerikutnya, int totalHarga, bool isTakeAway,
      {int discountAmount = 0, int originalTotal = 0}) async {
    // Check actual printer connection status dynamically
    await checkIfPrinterIsConnected();

    if (!printerIsConnected) {
      print('⚠️ Printer not connected - skipping receipt print');
      return;
    }

    try {
      printer.printCustom("375 Canteen", 3, 1);
      printer.printNewLine();
      DateTime now = DateTime.now();
      String formattedDate = DateFormat('dd-MM-yy HH:mm').format(now);
      print2Column(formattedDate, "No. $nomorBerikutnya", 3);
      // printer.print2Column();
      printer.printNewLine();
      print2Column('ITEM (QTY)', 'SUBTOTAL', 58);
      for (var element in pesananList) {
        String itemName = element.namaPesanan;
        if (itemName.length > 15) {
          itemName = itemName.substring(0, 15);
          itemName += "..";
        }
        print2ColumnSmall(itemName + "(" + element.totalQuantity.toString() +")",
             element.subtotal.toString());
      }
      if (isTakeAway) {
        print2ColumnSmall(
            'Bungkus (' +  jumlahItem.toString()+")", biayaBungkus.toString());
      }
      if (discountAmount > 0) {
        printer.printNewLine();
        printer.printCustom('SUBTOTAL: Rp $originalTotal', 1, 0);
        printer.printCustom('DISKON: -Rp $discountAmount', 1, 0);
      }
      printer.printNewLine();
      printer.printCustom('TOTAL: Rp $totalHarga', 3, 0);
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();
      print('✅ Receipt printed successfully');
    } catch (e) {
      print('❌ Error printing receipt: $e');
    }
  }

  Future<void> testPrinter(String invoice) async {
    if (printerIsConnected) {
      await Future.delayed(const Duration(milliseconds: 500));
      printer.printCustom("Pinter sudah terhubung.", 3, 1);
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();
      printer.paperCut();
    }
  }

  // Timer Management
  void startTimer(int index, {bool isTakeAway = false}) {
    timer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      HapticFeedback.heavyImpact();
      if (isTakeAway) {
        pesananList[index].takeAwayQuantity += 10;
      } else {
        pesananList[index].dineInQuantity += 10;
      }
      getTotal();
    });
  }

  void stopTimer() {
    timer?.cancel();
  }

  // Date/Time Utilities
  String getYear() {
    DateTime now = DateTime.now();
    String year = DateFormat('yyyy').format(now);
    return year;
  }

  String getMonth() {
    DateTime now = DateTime.now();
    String month = DateFormat('yyyy-MM').format(now);
    return month;
  }

  String getDate() {
    DateTime now = DateTime.now();
    String date = DateFormat('yyyy-MM-dd').format(now);
    return date;
  }

  // Reset customer number
  Future<void> resetCustomerNumber() async {
    await FirebaseFirestore.instance
        .collection("Canteens")
        .doc('canteen375')
        .update({'customerNumber': 0});

    final recentlyServed =
        await FirebaseFirestore.instance.collection("RecentyServed").get();

    for (var doc in recentlyServed.docs) {
      await doc.reference.delete();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void print2Column(String left, String right, int size) {
    // 58mm printers usually have 32 characters per line.
    // 80mm printers usually have 42-48.
    int maxChars = 32;

    // Calculate how many spaces we need between the two strings
    int spaces = maxChars - left.length - right.length;

    // Ensure we have at least one space
    if (spaces < 1) spaces = 1;

    String fullLine = left + (" " * spaces) + right;

    // printCustom(String text, int size, int align)
    // align: 0 = Left, 1 = Center, 2 = Right
    printer.printCustom(fullLine, size, 0);
  }

  void print2ColumnSmall(String left, String right) {
    // Small font (size 0) allows for more characters per line.
    // Standard 58mm = ~42 chars. Standard 80mm = ~56-64 chars.
    int maxChars = 42;

    int spaces = maxChars - left.length - right.length;

    // Safety check: if the text is too long, ensure at least one space
    if (spaces < 1) spaces = 1;

    String fullLine = left + (" " * spaces) + right;

    // Size '0' is the smallest font size in blue_thermal_printer
    // Align '0' keeps it left-justified
    printer.printCustom(fullLine, 0, 0);
  }

  void printDynamicSize({
    required String left,
    required String right,
    int size = 0,      // Default to small
    int fontType = 0,  // 0: Normal, 1: Bold (if supported)
  }) {
    // 1. Determine max characters based on font size (for 58mm printers)
    // Size 0 = 42 chars | Size 1 = 32 chars | Size 2 = 21 chars | Size 3 = 14 chars
    int maxChars;
    switch (size) {
      case 0:  maxChars = 42; break;
      case 1:  maxChars = 32; break;
      case 2:  maxChars = 21; break;
      case 3:  maxChars = 14; break;
      default: maxChars = 32;
    }

    // 2. Ensure right side (the value/price) is never cut off
    // We reserve enough space for the right string + 1 space
    int maxLeftWidth = maxChars - right.length - 1;

    // 3. Truncate left side if it's too long
    String leftFinal = (left.length > maxLeftWidth)
        ? "${left.substring(0, maxLeftWidth - 3)}.."
        : left;

    // 4. Calculate exact spacing
    int spacesCount = maxChars - leftFinal.length - right.length;
    if (spacesCount < 1) spacesCount = 1;

    // 5. Build and print the line
    String line = leftFinal + (" " * spacesCount) + right;
    printer.printCustom(line, size, 0);
  }
}
