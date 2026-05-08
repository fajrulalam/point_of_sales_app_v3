import 'dart:async';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Assets.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import 'package:point_of_sales_app_v3/Classes/OptionGroup.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/EndOfDayService.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Models/SelfOrder.dart';

class HomeController extends ChangeNotifier {
  // Callback for showing error messages (e.g., snackbars)
  Function(String message, {bool isError})? onShowMessage;
  // State variables

  int nomorBerikutnya = 0;
  
  // Edit mode state
  bool isEditMode = false;
  String? editDocumentId;
  Map<String, dynamic>? editOriginalData;
  
  // Self Order mode state
  bool isSelfOrderMode = false;
  SelfOrder? currentSelfOrder;
  
  List<MenuObject> menuObjectList = [];
  List<MenuObject> menuObjectList_makanan = [];
  List<MenuObject> menuObjectList_minuman = [];
  List<PesananObject> pesananList = [];
  List<AssetsObject> listGambar = [];
  List<String> categoryOrder = []; // Category display order from MenuConfig
  List<OptionGroup> optionGroups = []; // Cached option groups for quick lookup

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
  Future<void> initialize() async {
    // Wait for authentication if not ready
    int authAttempts = 0;
    while (FirebaseAuth.instance.currentUser == null && authAttempts < 5) {
      await Future.delayed(const Duration(milliseconds: 1000));
      authAttempts++;
    }

    getMenu();
    getListGambar();
    
    // Check for missed perishable resets from previous days
    EndOfDayService.checkAndAutoResetPerishables();
  }

  // Menu Management
  void getMenu() {
    DocumentReference customerNumber = FirebaseFirestore.instance
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('Metadata')
        .doc('customerNumber');

    customerNumber.snapshots().listen((event) {
      Map map = event.data() as Map<String, dynamic>;
      nomorBerikutnya = map['customerNumber'] + 1;
      notifyListeners();
    });

    CollectionReference menuCollection = FirebaseFirestore.instance
        .collection(Col.name('Canteens'))
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

    // Fetch category order from MenuConfig
    FirebaseFirestore.instance
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('Metadata')
        .doc('MenuConfig')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        categoryOrder = List<String>.from(data['categoryOrder'] ?? []);
        notifyListeners();
      }
    });

    // Stream option groups for use in ordering flow
    OptionGroupService().getOptionGroupsStream().listen((groups) {
      optionGroups = groups;
      notifyListeners();
    });
  }

  void getListGambar() {
    FirebaseFirestore.instance.collection(Col.name('assets')).snapshots().listen((value) {
      listGambar = AssetsClass.getImageAssets(value);
      notifyListeners();
    });
  }

  Future<void> deleteCatalogImage(AssetsObject asset) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      
      // 1. Update all menu items using this image
      final menuQuery = await firestore
          .collection(Col.name('Canteens'))
          .doc('canteen375')
          .collection('MenuCollection')
          .where('imagePath', isEqualTo: asset.path)
          .get();
          
      for (var doc in menuQuery.docs) {
        batch.update(doc.reference, {'imagePath': 'tidak ada'});
      }
      
      // 2. Delete the asset document
      batch.delete(firestore.collection(Col.name('assets')).doc(asset.id));
      
      await batch.commit();
      onShowMessage?.call('Gambar berhasil dihapus dari katalog', isError: false);
    } catch (e) {
      onShowMessage?.call('Gagal menghapus gambar: $e', isError: true);
    }
  }

  /// Returns all OptionGroups linked to the given menu item ID.
  List<OptionGroup> getLinkedOptionGroups(String menuItemId) {
    return optionGroups
        .where((g) => g.linkedMenuItems.contains(menuItemId))
        .toList();
  }

  /// Resolve selected options into a flat list of MenuIngredients
  /// using the cached optionGroups data.
  List<MenuIngredient> _resolveOptionIngredients(List<SelectedOption> selectedOptions) {
    final ingredients = <MenuIngredient>[];
    for (var selected in selectedOptions) {
      final group = optionGroups.firstWhere(
        (g) => g.id == selected.groupId,
        orElse: () => OptionGroup(id: '', name: ''),
      );
      if (group.id.isEmpty) continue;
      final optionItem = group.options.firstWhere(
        (o) => o.id == selected.optionId,
        orElse: () => OptionItem(id: '', name: ''),
      );
      if (optionItem.id.isEmpty) continue;
      ingredients.addAll(optionItem.ingredients);
    }
    return ingredients;
  }

  // --- Edit Order Mode ---
  void loadOrderForEdit(Map<String, dynamic> statusData, String documentId) {
    isEditMode = true;
    editDocumentId = documentId;
    editOriginalData = statusData;

    pesananList.clear();
    final List<dynamic> orderItems = statusData['orderItems'] ?? [];
    for (var item in orderItems) {
      final selectedOptsRaw = item['selectedOptions'] as List<dynamic>? ?? [];
      final selectedOpts = selectedOptsRaw.map((e) => SelectedOption.fromMap(e as Map<String, dynamic>)).toList();
      
      pesananList.add(PesananObject(
        menuItemId: item['menuItemId'] ?? '',
        namaPesanan: item['namaPesanan'] ?? '',
        harga: item['harga'] ?? 0,
        dineInQuantity: item['dineInQuantity'] ?? 0,
        takeAwayQuantity: item['takeAwayQuantity'] ?? 0,
        selectedOptions: selectedOpts,
      )..customerNote = item['customerNote']);
    }

    getTotal();
    notifyListeners();
  }

  void clearEditMode() {
    isEditMode = false;
    editDocumentId = null;
    editOriginalData = null;
    pesananList.clear();
    getTotal();
    notifyListeners();
  }

  // --- Self Order Mode ---
  void loadSelfOrder(SelfOrder order) {
    // If there's an existing order, clear it first
    if (isEditMode) clearEditMode();
    
    isSelfOrderMode = true;
    currentSelfOrder = order;

    pesananList.clear();
    for (var item in order.orderItems) {
      pesananList.add(PesananObject(
        menuItemId: item.menuItemId,
        namaPesanan: item.namaPesanan,
        harga: item.harga,
        dineInQuantity: item.dineInQuantity,
        takeAwayQuantity: item.takeAwayQuantity,
        selectedOptions: item.selectedOptions,
      ));
    }

    // Set takeaway global flag if any item is takeaway
    isTakeAway = order.directTakeAwayFee > 0 ||
        order.orderItems.any((it) => it.takeAwayQuantity > 0);

    getTotal();
    notifyListeners();
  }

  void clearSelfOrderMode() {
    isSelfOrderMode = false;
    currentSelfOrder = null;
    pesananList.clear();
    getTotal();
    notifyListeners();
  }
  // -----------------------
  // -----------------------

  // Order Management
  bool _addToOrderLock = false;

  Future<void> addToOrder(MenuObject menu, bool isTakeAway, {List<SelectedOption>? options, int quantity = 1}) async {
    if (_addToOrderLock) return;
    _addToOrderLock = true;

    try {
      final selectedOpts = options ?? const [];

      final matchKey = PesananObject(
        menuItemId: menu.id,
        namaPesanan: menu.namaMenu,
        harga: menu.harga,
        selectedOptions: selectedOpts,
      ).orderKey;

      int orderIndex = pesananList
          .indexWhere((element) => element.orderKey == matchKey);

      int newQuantity = quantity;
      if (orderIndex != -1) {
        newQuantity = pesananList[orderIndex].totalQuantity + quantity;
      }

      final inventoryService = InventoryService();
      final optionIngredients = _resolveOptionIngredients(selectedOpts);
      final availability = await inventoryService.checkOrderAvailability(
        menu,
        optionIngredients,
        newQuantity,
      );

      if (!availability.isAvailable) {
        onShowMessage?.call(
          'Tidak bisa menambah ${menu.namaMenu}: ${availability.message}',
          isError: true,
        );
        return;
      }

      if (availability.hasWarning) {
        onShowMessage?.call(
          'Peringatan: ${availability.message}',
          isError: false,
        );
      }

      // Re-check after the async gap to prevent duplicate rows from rapid taps
      orderIndex = pesananList
          .indexWhere((element) => element.orderKey == matchKey);

      if (orderIndex == -1) {
        pesananList.add(PesananObject(
          menuItemId: menu.id,
          namaPesanan: menu.namaMenu,
          harga: menu.harga,
          dineInQuantity: isTakeAway ? 0 : quantity,
          takeAwayQuantity: isTakeAway ? quantity : 0,
          selectedOptions: selectedOpts,
        ));
      } else {
        if (isTakeAway) {
          pesananList[orderIndex].takeAwayQuantity += quantity;
        } else {
          pesananList[orderIndex].dineInQuantity += quantity;
        }
      }
      getTotal();
    } finally {
      _addToOrderLock = false;
    }
  }

  Future<void> incrementDineIn(int index) async {
    // Find the menu object for this order
    final menuItem = menuObjectList.firstWhere(
      (menu) => menu.namaMenu == pesananList[index].namaPesanan,
      orElse: () => menuObjectList.first,
    );

    // Calculate the new quantity we're trying to reach
    final newQuantity = pesananList[index].dineInQuantity + 1;
    final totalNewQuantity = newQuantity + pesananList[index].takeAwayQuantity;

    // Check availability (menu + option ingredients aggregated)
    final inventoryService = InventoryService();
    final optionIngredients = _resolveOptionIngredients(pesananList[index].selectedOptions);
    final availability = await inventoryService.checkOrderAvailability(
      menuItem,
      optionIngredients,
      totalNewQuantity,
    );

    if (!availability.isAvailable) {
      // Data missing error (e.g. ingredient not found) - still block
      onShowMessage?.call(
        'Tidak bisa menambah ${menuItem.namaMenu}: ${availability.message}',
        isError: true,
      );
      return; // Don't increment
    }

    if (availability.hasWarning) {
      // Show warning but proceed
      onShowMessage?.call(
        'Peringatan: ${availability.message}',
        isError: false,
      );
    }

    // If available (or warned), increment
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

  Future<void> incrementTakeAway(int index) async {
    // Find the menu object for this order
    final menuItem = menuObjectList.firstWhere(
      (menu) => menu.namaMenu == pesananList[index].namaPesanan,
      orElse: () => menuObjectList.first,
    );

    // Calculate the new quantity we're trying to reach
    final newQuantity = pesananList[index].takeAwayQuantity + 1;
    final totalNewQuantity = newQuantity + pesananList[index].dineInQuantity;

    // Check availability (menu + option ingredients aggregated)
    final inventoryService = InventoryService();
    final optionIngredients = _resolveOptionIngredients(pesananList[index].selectedOptions);
    final availability = await inventoryService.checkOrderAvailability(
      menuItem,
      optionIngredients,
      totalNewQuantity,
    );

    if (!availability.isAvailable) {
      // Data missing error (e.g. ingredient not found) - still block
      onShowMessage?.call(
        'Tidak bisa menambah ${menuItem.namaMenu}: ${availability.message}',
        isError: true,
      );
      return; // Don't increment
    }

    if (availability.hasWarning) {
      // Show warning but proceed
      onShowMessage?.call(
        'Peringatan: ${availability.message}',
        isError: false,
      );
    }

    // If available (or warned), increment
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

  // Add recommended item (kept for potential future use)
  void addRecommendedItem(String itemName, int quantity) {
    // Find the menu item by name (case-insensitive)
    final menuItem = menuObjectList.firstWhere(
      (menu) => menu.namaMenu.toLowerCase() == itemName.toLowerCase(),
      orElse: () => menuObjectList.first,
    );

    // Check if item already exists in order
    final orderIndex = pesananList.indexWhere((element) =>
        element.namaPesanan.toLowerCase() == itemName.toLowerCase());

    if (orderIndex == -1) {
      if (isTakeAway) {
        pesananList.add(PesananObject(
          menuItemId: menuItem.id,
          namaPesanan: menuItem.namaMenu,
          harga: menuItem.harga,
          dineInQuantity: 0,
          takeAwayQuantity: quantity,
        ));
      } else {
        pesananList.add(PesananObject(
          menuItemId: menuItem.id,
          namaPesanan: menuItem.namaMenu,
          harga: menuItem.harga,
          dineInQuantity: quantity,
          takeAwayQuantity: 0,
        ));
      }
    } else {
      if (isTakeAway) {
        pesananList[orderIndex].takeAwayQuantity += quantity;
      } else {
        pesananList[orderIndex].dineInQuantity += quantity;
      }
    }

    getTotal();
    notifyListeners();
  }

  // Price Calculations
  void getTotal() {
    int subtotal = pesananList.fold(0, (acc, order) => acc + order.subtotal);
    
    int totalPackages = 0;
    for (var order in pesananList) {
      if (order.takeAwayQuantity > 0) {
        // Find corresponding MenuObject to get its unitsPerPackage
        final menu = menuObjectList.firstWhere(
          (m) => m.namaMenu == order.namaPesanan,
          orElse: () => MenuObject(
            id: '', 
            namaMenu: order.namaPesanan, 
            harga: order.harga, 
            isMakanan: true, 
            imagePath: '', 
            unitsPerPackage: 1
          ),
        );
        
        // Calculate packages for this item: ceil(quantity / unitsPerPackage)
        int packagesNeeded = (order.takeAwayQuantity / menu.unitsPerPackage).ceil();
        totalPackages += packagesNeeded;
      }
    }

    jumlahItem = totalPackages; // Use this to track total physical packages for takeaway
    biayaBungkus = (totalPackages ~/ 4) * 1000;
    totalHarga = subtotal + biayaBungkus;
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

  Future<void> printReceipt({
    List<PesananObject>? customPesananList,
    int? overrideNomorBerikutnya,
    int? overrideTotalHarga,
    bool? overrideIsTakeAway,
    int discountAmount = 0,
    int originalTotal = 0,
    int? overrideBiayaBungkus,
  }) async {
    // Check actual printer connection status dynamically
    await checkIfPrinterIsConnected();

    if (!printerIsConnected) {
      print('⚠️ Printer not connected - skipping receipt print');
      return;
    }

    final int displayNomor = overrideNomorBerikutnya ?? nomorBerikutnya;
    final int displayTotal = overrideTotalHarga ?? totalHarga;
    final bool displayTakeAway = overrideIsTakeAway ?? isTakeAway;
    final List<PesananObject> displayPesananList = customPesananList ?? pesananList;

    try {
      printer.printCustom("Canteen 375", 3, 1);
      printer.printNewLine();
      DateTime now = DateTime.now();
      String formattedDate = DateFormat('dd-MM-yy HH:mm').format(now);
      print2Column(formattedDate, "No. $displayNomor", 3);
      // printer.print2Column();
      printer.printNewLine();
      print2Column('ITEM (QTY)', 'SUBTOTAL', 58);
      for (var element in displayPesananList) {
        String itemName = element.namaPesanan;
        if (itemName.length > 15) {
          itemName = itemName.substring(0, 15);
          itemName += "..";
        }
        print2ColumnSmall(itemName + "(" + element.totalQuantity.toString() +")",
             element.subtotal.toString());
        for (var opt in element.selectedOptions) {
          String optLine = '  + ${opt.optionName}';
          String optPrice = opt.priceAdjustment > 0
              ? '+${opt.priceAdjustment}'
              : '';
          print2ColumnSmall(optLine, optPrice);
        }
        if (element.customerNote != null && element.customerNote!.isNotEmpty) {
          printer.printCustom('  * ${element.customerNote}', 1, 0);
        }
      }
      if (displayTakeAway) {
        final int displayBiayaBungkus = overrideBiayaBungkus ?? biayaBungkus;
        final int displayJumlahItem = overrideBiayaBungkus != null
            ? displayPesananList.fold<int>(0, (sum, o) => sum + o.takeAwayQuantity)
            : jumlahItem;
        print2ColumnSmall(
            'Bungkus ($displayJumlahItem)', displayBiayaBungkus.toString());
      }
      if (discountAmount > 0) {
        printer.printNewLine();
        printer.printCustom('SUBTOTAL: Rp $originalTotal', 1, 0);
        printer.printCustom('DISKON: -Rp $discountAmount', 1, 0);
      }
      printer.printNewLine();
      printer.printCustom('TOTAL: Rp $displayTotal', 3, 0);
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();
      print('✅ Receipt printed successfully');
    } catch (e) {
      print('❌ Error printing receipt: $e');
      printerIsConnected = false;
      notifyListeners();
    }
  }

  /// Reprint a receipt from a previously stored order (Status or RecentlyServed collection)
  Future<void> reprintFromOrder(Map<String, dynamic> orderData) async {
    await checkIfPrinterIsConnected();

    if (!printerIsConnected) {
      print('⚠️ Printer not connected - cannot reprint');
      return;
    }

    try {
      final int customerNumber = orderData['customerNumber'] ?? 0;
      final int total = orderData['total'] ?? 0;
      final List<dynamic> orderItems = orderData['orderItems'] ?? [];
      DateTime? waktuPesan;
      final rawWaktu = orderData['waktuPesan'];
      if (rawWaktu is Timestamp) {
        waktuPesan = rawWaktu.toDate();
      } else if (rawWaktu is DateTime) {
        waktuPesan = rawWaktu;
      } else if (rawWaktu is String) {
        final epoch = int.tryParse(rawWaktu);
        if (epoch != null) {
          waktuPesan = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
        }
      }

      // Detect data format: RecentlyServed uses 'quantity', Status uses 'dineInQuantity'/'takeAwayQuantity'
      final bool isRecentlyServedFormat = orderItems.isNotEmpty && orderItems.first.containsKey('quantity');

      bool hasTakeAway = isRecentlyServedFormat
          ? orderItems.any((item) => (item['orderType'] ?? '') == 'take-away')
          : orderItems.any((item) => (item['takeAwayQuantity'] ?? 0) > 0);

      printer.printCustom("Canteen 375", 3, 1);
      printer.printCustom("*** CETAK ULANG ***", 1, 1);
      printer.printNewLine();

      String formattedDate = waktuPesan != null
          ? DateFormat('dd-MM-yy HH:mm').format(waktuPesan)
          : DateFormat('dd-MM-yy HH:mm').format(DateTime.now());
      print2Column(formattedDate, "No. $customerNumber", 3);
      printer.printNewLine();
      print2Column('ITEM (QTY)', 'SUBTOTAL', 58);

      for (var item in orderItems) {
        String itemName = item['namaPesanan'] ?? '';
        int harga = (item['harga'] ?? 0) is num ? (item['harga'] as num).toInt() : 0;

        int totalQty;
        if (isRecentlyServedFormat) {
          totalQty = (item['quantity'] ?? 0) is num ? (item['quantity'] as num).toInt() : 0;
        } else {
          int dineIn = (item['dineInQuantity'] ?? 0) is num ? (item['dineInQuantity'] as num).toInt() : 0;
          int takeAway = (item['takeAwayQuantity'] ?? 0) is num ? (item['takeAwayQuantity'] as num).toInt() : 0;
          totalQty = dineIn + takeAway;
        }

        int optionsAdj = 0;
        final List<dynamic> selectedOpts = item['selectedOptions'] ?? [];
        for (var opt in selectedOpts) {
          optionsAdj += ((opt['priceAdjustment'] ?? 0) as num).toInt();
        }
        int effectivePrice = harga + optionsAdj;
        int subtotal = effectivePrice * totalQty;

        if (itemName.length > 15) {
          itemName = itemName.substring(0, 15) + "..";
        }
        print2ColumnSmall("$itemName($totalQty)", subtotal.toString());

        for (var opt in selectedOpts) {
          String optName = opt['optionName'] ?? '';
          int adj = ((opt['priceAdjustment'] ?? 0) as num).toInt();
          String optPrice = adj > 0 ? '+$adj' : '';
          print2ColumnSmall('  + $optName', optPrice);
        }
        final String? note = item['customerNote'];
        if (note != null && note.isNotEmpty) {
          printer.printCustom('  * $note', 1, 0);
        }
      }

      if (hasTakeAway) {
        if (isRecentlyServedFormat) {
          int bungkusFee = (orderData['bungkus'] ?? 0) is num ? (orderData['bungkus'] as num).toInt() : 0;
          if (bungkusFee > 0) {
            print2ColumnSmall('Bungkus', bungkusFee.toString());
          }
        } else {
          int bungkusFee = (orderData['takeAwayFee'] ?? 0) is num
              ? (orderData['takeAwayFee'] as num).toInt()
              : 0;
          int takeAwayCount = orderItems.fold<int>(
              0, (sum, item) => sum + (((item['takeAwayQuantity'] ?? 0) as num).toInt()));
          if (bungkusFee > 0) {
            print2ColumnSmall('Bungkus ($takeAwayCount)', bungkusFee.toString());
          }
        }
      }

      printer.printNewLine();
      printer.printCustom('TOTAL: Rp $total', 3, 0);
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();

      print('✅ Receipt reprinted successfully for order #$customerNumber');
    } catch (e) {
      print('❌ Error reprinting receipt: $e');
      printerIsConnected = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Reprint a settled open bill receipt
  Future<void> reprintSettledBill(Map<String, dynamic> data) async {
    await checkIfPrinterIsConnected();

    if (!printerIsConnected) {
      print('⚠️ Printer not connected - cannot reprint');
      return;
    }

    try {
      final String memberName = data['namaCustomer'] ?? data['memberName'] ?? 'Member';
      final int finalTotal = data['finalTotal'] ?? data['total'] ?? data['totalAmount'] ?? 0;
      final int originalTotal = data['totalAmount'] ?? data['total'] ?? finalTotal;
      final int discountAmount = data['discountAmount'] ?? 0;
      final String paymentMethod = data['paymentMethod'] ?? '';

      // Support both new (flat orderItems) and legacy (nested orders[].items[]) formats
      final List<dynamic>? flatItems = data['orderItems'];
      final List<dynamic>? legacyOrders = data['orders'];

      final DateTime? settledAt = data['settledAt'] != null
          ? (data['settledAt'] as dynamic).toDate()
          : null;

      printer.printCustom("Canteen 375", 3, 1);
      printer.printCustom("*** TAGIHAN SELESAI ***", 1, 1);
      printer.printCustom("*** CETAK ULANG ***", 1, 1);
      printer.printNewLine();

      String formattedDate = settledAt != null
          ? DateFormat('dd-MM-yy HH:mm').format(settledAt)
          : DateFormat('dd-MM-yy HH:mm').format(DateTime.now());
      print2Column(formattedDate, paymentMethod, 3);
      printer.printCustom("Pelanggan: $memberName", 0, 0);
      printer.printNewLine();
      print2Column('ITEM (QTY)', 'SUBTOTAL', 58);

      if (flatItems != null && flatItems.isNotEmpty) {
        // New Status doc format: flat orderItems array
        for (var item in flatItems) {
          String itemName = item['namaPesanan'] ?? '';
          int dineIn = item['dineInQuantity'] ?? 0;
          int takeAway = item['takeAwayQuantity'] ?? 0;
          int harga = item['harga'] ?? 0;
          int totalQty = dineIn + takeAway;

          int optionsAdj = 0;
          final List<dynamic> selectedOpts = item['selectedOptions'] ?? [];
          for (var opt in selectedOpts) {
            optionsAdj += (opt['priceAdjustment'] ?? 0) as int;
          }
          int effectivePrice = harga + optionsAdj;
          int subtotal = effectivePrice * totalQty;

          if (itemName.length > 15) {
            itemName = "${itemName.substring(0, 15)}..";
          }
          print2ColumnSmall("$itemName($totalQty)", subtotal.toString());

          for (var opt in selectedOpts) {
            String optName = opt['optionName'] ?? '';
            int adj = opt['priceAdjustment'] ?? 0;
            String optPrice = adj > 0 ? '+$adj' : '';
            print2ColumnSmall('  + $optName', optPrice);
          }
          final String? note = item['customerNote'];
          if (note != null && note.isNotEmpty) {
            printer.printCustom('  * $note', 1, 0);
          }
        }
      } else if (legacyOrders != null) {
        // Legacy format: orders[].items[]
        for (var order in legacyOrders) {
          final List<dynamic> items = order['items'] ?? [];
          for (var item in items) {
            String itemName = item['namaPesanan'] ?? '';
            int dineIn = item['dineInQuantity'] ?? 0;
            int takeAway = item['takeAwayQuantity'] ?? 0;
            int harga = item['harga'] ?? 0;
            int totalQty = dineIn + takeAway;

            int optionsAdj = 0;
            final List<dynamic> selectedOpts = item['selectedOptions'] ?? [];
            for (var opt in selectedOpts) {
              optionsAdj += (opt['priceAdjustment'] ?? 0) as int;
            }
            int effectivePrice = harga + optionsAdj;
            int subtotal = effectivePrice * totalQty;

            if (itemName.length > 15) {
              itemName = "${itemName.substring(0, 15)}..";
            }
            print2ColumnSmall("$itemName($totalQty)", subtotal.toString());

            for (var opt in selectedOpts) {
              String optName = opt['optionName'] ?? '';
              int adj = opt['priceAdjustment'] ?? 0;
              String optPrice = adj > 0 ? '+$adj' : '';
              print2ColumnSmall('  + $optName', optPrice);
            }
            final String? note = item['customerNote'];
            if (note != null && note.isNotEmpty) {
              printer.printCustom('  * $note', 1, 0);
            }
          }

          int takeAwayFee = order['orderTakeAwayFee'] ?? 0;
          if (takeAwayFee > 0) {
            print2ColumnSmall('Bungkus', takeAwayFee.toString());
          }
        }
      }

      printer.printNewLine();

      if (discountAmount > 0) {
        print2ColumnSmall('Subtotal', 'Rp $originalTotal');
        print2ColumnSmall('Diskon', '-Rp $discountAmount');
      }

      printer.printCustom('TOTAL: Rp $finalTotal', 3, 0);
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();

      print('✅ Settled bill receipt reprinted for $memberName');
    } catch (e) {
      print('❌ Error reprinting settled bill: $e');
      printerIsConnected = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> testPrinter(String invoice) async {
    await checkIfPrinterIsConnected();
    if (printerIsConnected) {
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        printer.printCustom("Pinter sudah terhubung.", 3, 1);
        printer.printNewLine();
        printer.printNewLine();
        printer.printNewLine();
        printer.paperCut();
      } catch (e) {
        print('❌ Error testing printer: $e');
        printerIsConnected = false;
        notifyListeners();
      }
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
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('Metadata')
        .doc('customerNumber')
        .set({'customerNumber': 0}, SetOptions(merge: true));

    final recentlyServed = await FirebaseFirestore.instance
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection(Col.name('RecentlyServed'))
        .get();

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
