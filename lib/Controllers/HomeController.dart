import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
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
import 'package:point_of_sales_app_v3/Services/UserMessageService.dart';

class HomeController extends ChangeNotifier {
  final List<StreamSubscription> _subscriptions = [];
  bool _disposed = false;

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
    // Clear existing subscriptions if any
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    DocumentReference customerNumber = FirebaseFirestore.instance
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('Metadata')
        .doc('customerNumber');

    _subscriptions.add(customerNumber.snapshots().listen((event) {
      if (_disposed) return;
      Map map = event.data() as Map<String, dynamic>;
      nomorBerikutnya = map['customerNumber'] + 1;
      notifyListeners();
    }));

    CollectionReference menuCollection = FirebaseFirestore.instance
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('MenuCollection');

    _subscriptions.add(menuCollection.snapshots().listen((snapshot) {
      if (_disposed) return;
      menuObjectList = MenuClass.getAllMenus(snapshot);
      menuObjectList_makanan =
          menuObjectList.where((element) => element.isMakanan == true).toList();
      menuObjectList_minuman = menuObjectList
          .where((element) => element.isMakanan == false)
          .toList();
      notifyListeners();
    }));

    // Fetch category order from MenuConfig
    _subscriptions.add(FirebaseFirestore.instance
        .collection(Col.name('Canteens'))
        .doc('canteen375')
        .collection('Metadata')
        .doc('MenuConfig')
        .snapshots()
        .listen((snapshot) {
      if (_disposed) return;
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        categoryOrder = List<String>.from(data['categoryOrder'] ?? []);
        notifyListeners();
      }
    }));

    // Stream option groups for use in ordering flow
    _subscriptions
        .add(OptionGroupService().getOptionGroupsStream().listen((groups) {
      if (_disposed) return;
      optionGroups = groups;
      notifyListeners();
    }));
  }

  void getListGambar() {
    _subscriptions.add(FirebaseFirestore.instance
        .collection(Col.name('assets'))
        .snapshots()
        .listen((value) {
      if (_disposed) return;
      listGambar = AssetsClass.getImageAssets(value);
      notifyListeners();
    }));
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
      onShowMessage?.call('Gambar berhasil dihapus dari katalog',
          isError: false);
    } catch (e) {
      onShowMessage?.call(
        'Gagal menghapus gambar: ${UserMessageService.fromError(e)}',
        isError: true,
      );
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
  List<MenuIngredient> _resolveOptionIngredients(
      List<SelectedOption> selectedOptions) {
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
      final selectedOpts = selectedOptsRaw
          .map((e) => SelectedOption.fromMap(e as Map<String, dynamic>))
          .toList();

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

  Future<void> addToOrder(MenuObject menu, bool isTakeAway,
      {List<SelectedOption>? options, int quantity = 1}) async {
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

      int orderIndex =
          pesananList.indexWhere((element) => element.orderKey == matchKey);

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
      orderIndex =
          pesananList.indexWhere((element) => element.orderKey == matchKey);

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
    final optionIngredients =
        _resolveOptionIngredients(pesananList[index].selectedOptions);
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
    final optionIngredients =
        _resolveOptionIngredients(pesananList[index].selectedOptions);
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
    }
    getTotal();
  }

  void removeItem(int index) {
    if (index >= 0 && index < pesananList.length) {
      pesananList.removeAt(index);
      getTotal();
    }
  }

  Future<void> updateOrderOptions(
      int index, List<SelectedOption> newOptions, int newQuantity) async {
    if (index < 0 || index >= pesananList.length) return;

    final order = pesananList[index];
    final menu = menuObjectList.firstWhere(
      (m) => m.id == order.menuItemId,
      orElse: () => menuObjectList.firstWhere(
          (m) => m.namaMenu == order.namaPesanan,
          orElse: () => MenuObject(
              id: order.menuItemId,
              namaMenu: order.namaPesanan,
              harga: order.harga,
              isMakanan: true,
              imagePath: '')),
    );

    // Check availability
    final inventoryService = InventoryService();
    final optionIngredients = _resolveOptionIngredients(newOptions);
    final availability = await inventoryService.checkOrderAvailability(
      menu,
      optionIngredients,
      newQuantity,
    );

    if (!availability.isAvailable) {
      onShowMessage?.call(
        'Tidak bisa mengubah opsi: ${availability.message}',
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

    // Determine the target item's key if we update it
    final tempOrder = PesananObject(
      menuItemId: menu.id,
      namaPesanan: menu.namaMenu,
      harga: menu.harga,
      selectedOptions: newOptions,
    );

    // Check if another item in cart matches the new orderKey
    int matchIndex = pesananList
        .indexWhere((element) => element.orderKey == tempOrder.orderKey);

    if (matchIndex != -1 && matchIndex != index) {
      // Merge this item's new quantity into the existing matched item
      final matchedOrder = pesananList[matchIndex];
      // Keep original order's choice of Dine In / Take Away if possible
      if (order.dineInQuantity > 0 && order.takeAwayQuantity == 0) {
        matchedOrder.dineInQuantity += newQuantity;
      } else if (order.takeAwayQuantity > 0 && order.dineInQuantity == 0) {
        matchedOrder.takeAwayQuantity += newQuantity;
      } else {
        if (isTakeAway) {
          matchedOrder.takeAwayQuantity += newQuantity;
        } else {
          matchedOrder.dineInQuantity += newQuantity;
        }
      }
      // Remove the edited item from the list since it's merged
      pesananList.removeAt(index);
    } else {
      // Replace/overwrite in place
      order.selectedOptions = newOptions;
      if (order.dineInQuantity > 0 && order.takeAwayQuantity == 0) {
        order.dineInQuantity = newQuantity;
        order.takeAwayQuantity = 0;
      } else if (order.takeAwayQuantity > 0 && order.dineInQuantity == 0) {
        order.takeAwayQuantity = newQuantity;
        order.dineInQuantity = 0;
      } else {
        if (isTakeAway) {
          order.takeAwayQuantity = newQuantity;
          order.dineInQuantity = 0;
        } else {
          order.dineInQuantity = newQuantity;
          order.takeAwayQuantity = 0;
        }
      }
    }

    getTotal();
    notifyListeners();
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
              unitsPerPackage: 1),
        );

        // Calculate packages for this item: ceil(quantity / unitsPerPackage)
        int packagesNeeded =
            (order.takeAwayQuantity / menu.unitsPerPackage).ceil();
        totalPackages += packagesNeeded;
      }
    }

    jumlahItem =
        totalPackages; // Use this to track total physical packages for takeaway
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

  Future<ui.Image> _loadUiImage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(data.buffer.asUint8List(), completer.complete);
    return completer.future;
  }

  Future<void> _printReceiptHeader({
    bool isReprint = false,
    bool isSettled = false,
    bool isTest = false,
  }) async {
    bool imagePrinted = false;

    try {
      // 1. Setup Canvas Dimensions (384px is standard for 58mm)
      const double paperWidth = 384.0;
      const double canvasHeight = 140.0;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      // Fill background white
      final paint = ui.Paint()..color = ui.Color(0xFFFFFFFF);
      canvas.drawRect(ui.Rect.fromLTWH(0, 0, paperWidth, canvasHeight), paint);

      // 2. Draw Logo
      final ui.Image logoImage =
          await _loadUiImage('assets/Logo Canteen375 (PNG).png');
      const double logoSize = 110.0;
      canvas.drawImageRect(
        logoImage,
        ui.Rect.fromLTWH(
            0, 0, logoImage.width.toDouble(), logoImage.height.toDouble()),
        ui.Rect.fromLTWH(0, 15, logoSize, logoSize),
        ui.Paint(),
      );

      // 3. Draw Branding Text with Custom Fonts
      final double textLeft = logoSize + 10;

      // Title: Canteen 375 (Playfair Display Bold)
      final titlePainter = TextPainter(
        text: TextSpan(
          text: 'Canteen 375',
          style: GoogleFonts.playfairDisplay(
            color: Colors.black,
            fontSize: 48,
            fontWeight: FontWeight.bold,
            letterSpacing: -1.5,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      titlePainter.paint(canvas, ui.Offset(textLeft, 25));

      // Tagline: Sehat.Bersih.Nikmat (Montserrat Medium)
      final taglinePainter = TextPainter(
        text: TextSpan(
          text: 'Sehat · Bersih · Nikmat',
          style: TextStyle(
            color: ui.Color(0xFF333333),
            fontSize: 24,
            fontWeight: FontWeight.w500,
            fontFamily: 'Montserrat',
            letterSpacing: -1.0,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      taglinePainter.paint(canvas, ui.Offset(textLeft, 85));

      // 4. Convert Canvas to Printer-ready Image
      final picture = recorder.endRecording();
      final imgRes =
          await picture.toImage(paperWidth.toInt(), canvasHeight.toInt());
      final byteData = await imgRes.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        // Process with 'image' package to ensure it's grayscale/1-bit for best thermal results
        final img.Image? decoded =
            img.decodeImage(byteData.buffer.asUint8List());
        if (decoded != null) {
          final Directory tempDir = await getTemporaryDirectory();
          final File headerFile = File('${tempDir.path}/canteen_header_v2.png');

          // Grayscale conversion helps the thermal printer handle colors better
          final img.Image gray = img.grayscale(decoded);
          await headerFile.writeAsBytes(img.encodePng(gray));

          await printer.printImage(headerFile.path);
          printer.printNewLine();
          imagePrinted = true;
        }
      }
    } catch (e) {
      print('❌ Advanced Header Error: $e');
    }

    // Fallback to text-only if image failed
    if (!imagePrinted) {
      printer.printCustom("================================", 0, 1);
      printer.printCustom("Canteen 375", 3, 1);
      printer.printCustom("Sehat.Bersih.Nikmat", 0, 1);
      printer.printCustom("UNIPDU PLAZA AREA", 0, 1);
      printer.printCustom("================================", 0, 1);
    }

    if (isTest) {
      printer.printNewLine();
      printer.printCustom("--- TES PRINTER ---", 1, 1);
    }
    if (isReprint) {
      printer.printNewLine();
      printer.printCustom("*** CETAK ULANG ***", 1, 1);
    }
    if (isSettled) {
      printer.printCustom("*** TAGIHAN SELESAI ***", 1, 1);
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
    String? customerName,
    int? voucherRemaining, // Added for multi-use vouchers
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
    final List<PesananObject> displayPesananList =
        customPesananList ?? pesananList;

    try {
      await _printReceiptHeader();
      printer.printNewLine();
      DateTime now = DateTime.now();
      String formattedDate = DateFormat('dd-MM-yy HH:mm').format(now);

      // Date and Queue Number - Small font
      print2ColumnSmall(formattedDate, "No. $displayNomor");

      // Customer Name - Small font
      if (customerName != null && customerName.isNotEmpty) {
        printer.printCustom("$customerName", 1, 0);
      }

      printer.printNewLine();
      print2ColumnSmall('(QTY) ITEM', 'SUBTOTAL');

      // Sort items: Food (isMakanan: true) first, then Drinks
      final List<PesananObject> sortedPesananList =
          List<PesananObject>.from(displayPesananList);
      sortedPesananList.sort((a, b) {
        final menuA = menuObjectList.firstWhere(
          (m) => m.id == a.menuItemId,
          orElse: () => MenuObject(
              id: '', namaMenu: '', harga: 0, isMakanan: true, imagePath: ''),
        );
        final menuB = menuObjectList.firstWhere(
          (m) => m.id == b.menuItemId,
          orElse: () => MenuObject(
              id: '', namaMenu: '', harga: 0, isMakanan: true, imagePath: ''),
        );
        if (menuA.isMakanan && !menuB.isMakanan) return -1;
        if (!menuA.isMakanan && menuB.isMakanan) return 1;
        return 0;
      });

      for (var element in sortedPesananList) {
        int optionsAdj = 0;
        for (var opt in element.selectedOptions) {
          optionsAdj += opt.priceAdjustment;
        }
        int effectivePrice = element.harga + optionsAdj;

        void printItemLine(String name, int qty, int sub) {
          String displayName = name;
          if (displayName.length > 25) {
            displayName = displayName.substring(0, 25) + "..";
          }
          print2ColumnSmall("($qty) $displayName", sub.toString());
          for (var opt in element.selectedOptions) {
            String optLine = '  + ${opt.optionName}';
            String optPrice = '+${opt.priceAdjustment}';
            print2ColumnSmall(optLine, optPrice);
          }
          if (element.customerNote != null &&
              element.customerNote!.isNotEmpty) {
            printer.printCustom('  * ${element.customerNote}', 0, 0);
          }
        }

        if (element.dineInQuantity > 0) {
          printItemLine(element.namaPesanan, element.dineInQuantity,
              effectivePrice * element.dineInQuantity);
        }
        if (element.takeAwayQuantity > 0) {
          printItemLine(
              "${element.namaPesanan} (bgks)",
              element.takeAwayQuantity,
              effectivePrice * element.takeAwayQuantity);
        }
      }
      if (displayTakeAway) {
        final int displayBiayaBungkus = overrideBiayaBungkus ?? biayaBungkus;
        final int displayJumlahItem = overrideBiayaBungkus != null
            ? displayPesananList.fold<int>(
                0, (sum, o) => sum + o.takeAwayQuantity)
            : jumlahItem;
        print2ColumnSmall(
            'Bungkus ($displayJumlahItem)', displayBiayaBungkus.toString());
      }
      if (discountAmount > 0) {
        printer.printNewLine();
        print2ColumnSmall('SUBTOTAL', 'Rp $originalTotal');
        print2ColumnSmall('DISKON', '-Rp $discountAmount');

        if (voucherRemaining != null) {
          print2ColumnSmall('SISA VOUCHER', 'Rp $voucherRemaining');
        }
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
      final bool isRecentlyServedFormat =
          orderItems.isNotEmpty && orderItems.first.containsKey('quantity');

      bool hasTakeAway = isRecentlyServedFormat
          ? orderItems.any((item) => (item['orderType'] ?? '') == 'take-away')
          : orderItems.any((item) => (item['takeAwayQuantity'] ?? 0) > 0);

      await _printReceiptHeader(isReprint: true);

      String formattedDate = waktuPesan != null
          ? DateFormat('dd-MM-yy HH:mm').format(waktuPesan)
          : DateFormat('dd-MM-yy HH:mm').format(DateTime.now());

      // Date and Queue Number - Small font
      print2ColumnSmall(formattedDate, "No. $customerNumber");

      // Customer Name - Medium font
      final String? customerName = orderData["namaCustomer"];
      if (customerName != null && customerName.isNotEmpty) {
        printer.printCustom("$customerName", 1, 0);
      }

      printer.printNewLine();
      print2ColumnSmall('(QTY) ITEM', 'SUBTOTAL');

      // Sort items: Food (isMakanan: true) first, then Drinks
      final List<dynamic> sortedOrderItems = List<dynamic>.from(orderItems);
      sortedOrderItems.sort((a, b) {
        final bool isMakananA = a['isMakanan'] ?? true;
        final bool isMakananB = b['isMakanan'] ?? true;
        if (isMakananA && !isMakananB) return -1;
        if (!isMakananA && isMakananB) return 1;
        return 0;
      });

      for (var item in sortedOrderItems) {
        String itemName = item['namaPesanan'] ?? '';
        int harga =
            (item['harga'] ?? 0) is num ? (item['harga'] as num).toInt() : 0;
        final List<dynamic> selectedOpts = item['selectedOptions'] ?? [];
        final String? note = item['customerNote'];

        int optionsAdj = 0;
        for (var opt in selectedOpts) {
          optionsAdj += ((opt['priceAdjustment'] ?? 0) as num).toInt();
        }
        int effectivePrice = harga + optionsAdj;

        void printReprintLine(String name, int qty) {
          String displayName = name;
          if (displayName.length > 25) {
            displayName = displayName.substring(0, 25) + "..";
          }
          print2ColumnSmall(
              "($qty) $displayName", (effectivePrice * qty).toString());
          for (var opt in selectedOpts) {
            String optName = opt['optionName'] ?? '';
            int adj = ((opt['priceAdjustment'] ?? 0) as num).toInt();
            String optPrice = '+$adj';
            print2ColumnSmall('  + $optName', optPrice);
          }
          if (note != null && note.isNotEmpty) {
            printer.printCustom('  * ${note}', 0, 0);
          }
        }

        if (isRecentlyServedFormat) {
          int qty = (item['quantity'] ?? 0) is num
              ? (item['quantity'] as num).toInt()
              : 0;
          bool isTA = (item['orderType'] ?? '') == 'take-away';
          printReprintLine(isTA ? "$itemName (bgks)" : itemName, qty);
        } else {
          int dineIn = (item['dineInQuantity'] ?? 0) is num
              ? (item['dineInQuantity'] as num).toInt()
              : 0;
          int takeAway = (item['takeAwayQuantity'] ?? 0) is num
              ? (item['takeAwayQuantity'] as num).toInt()
              : 0;

          if (dineIn > 0) {
            printReprintLine(itemName, dineIn);
          }
          if (takeAway > 0) {
            printReprintLine("$itemName (bgks)", takeAway);
          }
        }
      }

      if (hasTakeAway) {
        if (isRecentlyServedFormat) {
          int bungkusFee = (orderData['bungkus'] ?? 0) is num
              ? (orderData['bungkus'] as num).toInt()
              : 0;
          if (bungkusFee > 0) {
            print2ColumnSmall('Bungkus', bungkusFee.toString());
          }
        } else {
          int bungkusFee = (orderData['takeAwayFee'] ?? 0) is num
              ? (orderData['takeAwayFee'] as num).toInt()
              : 0;
          int takeAwayCount = orderItems.fold<int>(
              0,
              (sum, item) =>
                  sum + (((item['takeAwayQuantity'] ?? 0) as num).toInt()));
          if (bungkusFee > 0) {
            print2ColumnSmall(
                'Bungkus ($takeAwayCount)', bungkusFee.toString());
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
      final String memberName =
          data['namaCustomer'] ?? data['memberName'] ?? 'Member';
      final int finalTotal =
          data['finalTotal'] ?? data['total'] ?? data['totalAmount'] ?? 0;
      final int originalTotal =
          data['totalAmount'] ?? data['total'] ?? finalTotal;
      final int discountAmount = data['discountAmount'] ?? 0;
      final String paymentMethod = data['paymentMethod'] ?? '';

      // Support both new (flat orderItems) and legacy (nested orders[].items[]) formats
      final List<dynamic>? flatItems = data['orderItems'];
      final List<dynamic>? legacyOrders = data['orders'];

      final DateTime? settledAt = data['settledAt'] != null
          ? (data['settledAt'] as dynamic).toDate()
          : null;

      await _printReceiptHeader(isSettled: true, isReprint: true);

      String formattedDate = settledAt != null
          ? DateFormat('dd-MM-yy HH:mm').format(settledAt)
          : DateFormat('dd-MM-yy HH:mm').format(DateTime.now());

      // Date and Method - Small font
      print2ColumnSmall(formattedDate, paymentMethod);

      // Customer Name - Medium font
      printer.printCustom("$memberName", 1, 0);

      printer.printNewLine();
      print2ColumnSmall('ITEM (QTY)', 'SUBTOTAL');

      if (flatItems != null && flatItems.isNotEmpty) {
        // New Status doc format: flat orderItems array
        for (var item in flatItems) {
          String itemName = item['namaPesanan'] ?? '';
          int dineIn = item['dineInQuantity'] ?? 0;
          int takeAway = item['takeAwayQuantity'] ?? 0;
          int harga = item['harga'] ?? 0;

          int optionsAdj = 0;
          final List<dynamic> selectedOpts = item['selectedOptions'] ?? [];
          for (var opt in selectedOpts) {
            optionsAdj += (opt['priceAdjustment'] ?? 0) as int;
          }
          int effectivePrice = harga + optionsAdj;

          void printItemLine(String name, int qty) {
            String displayName = name;
            if (displayName.length > 20) {
              displayName = "${displayName.substring(0, 20)}..";
            }
            int subtotal = effectivePrice * qty;
            print2ColumnSmall("$displayName($qty)", subtotal.toString());

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

          if (dineIn > 0) {
            printItemLine(itemName, dineIn);
          }
          if (takeAway > 0) {
            printItemLine("$itemName (bgks)", takeAway);
          }
        }

        // Print packing fee if applicable for flatItems format
        final int takeAwayFee = (data['takeAwayFee'] ?? 0) is num
            ? (data['takeAwayFee'] as num).toInt()
            : 0;
        if (takeAwayFee > 0) {
          print2ColumnSmall('Bungkus', takeAwayFee.toString());
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
        await _printReceiptHeader(isTest: true);
        printer.printNewLine();
        printer.printQRcode('Canteen 375 - Test', 200, 200, 1);
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
    _disposed = true;
    for (var sub in _subscriptions) {
      sub.cancel();
    }
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
    // Small font (size 0) - allows for more characters
    // Standard 58mm with size 0 = ~42 chars.
    int maxChars = 42;

    int spaces = maxChars - left.length - right.length;

    // Safety check: if the text is too long, ensure at least one space
    if (spaces < 1) spaces = 1;

    String fullLine = left + (" " * spaces) + right;

    // Use size 0 for smallest text
    printer.printCustom(fullLine, 0, 0);
  }

  void printDynamicSize({
    required String left,
    required String right,
    int size = 0, // Default to small
    int fontType = 0, // 0: Normal, 1: Bold (if supported)
  }) {
    // 1. Determine max characters based on font size (for 58mm printers)
    // Size 0 = 42 chars | Size 1 = 32 chars | Size 2 = 21 chars | Size 3 = 14 chars
    int maxChars;
    switch (size) {
      case 0:
        maxChars = 42;
        break;
      case 1:
        maxChars = 32;
        break;
      case 2:
        maxChars = 21;
        break;
      case 3:
        maxChars = 14;
        break;
      default:
        maxChars = 32;
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
