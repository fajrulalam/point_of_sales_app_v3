import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/AlertDialogs/ConnectPrinterDialog.dart';
import 'package:point_of_sales_app_v3/Controllers/HomeController.dart';
import 'package:point_of_sales_app_v3/Screens/LoginScreen.dart';
import 'package:point_of_sales_app_v3/Services/OrderConfirmationService.dart';
import 'package:point_of_sales_app_v3/Services/RecommendationService.dart';
import 'package:point_of_sales_app_v3/Services/MemberService.dart';
import 'package:point_of_sales_app_v3/Services/SelfOrderService.dart';
import 'package:point_of_sales_app_v3/Models/SelfOrder.dart';
import 'package:point_of_sales_app_v3/Widgets/MenuManagementWidget.dart';
import 'package:point_of_sales_app_v3/Widgets/OrderListWidget.dart';
import 'package:point_of_sales_app_v3/Widgets/OrderSummaryWidget.dart';
import 'package:point_of_sales_app_v3/Widgets/OrderingViewWidget.dart';
import 'package:point_of_sales_app_v3/Widgets/RulesTableDialog.dart';
import 'package:point_of_sales_app_v3/Widgets/SidebarWidget.dart';
import 'package:point_of_sales_app_v3/Screens/InventoryScreen.dart';
import 'package:point_of_sales_app_v3/Services/EndOfDayService.dart';
import 'package:point_of_sales_app_v3/Screens/MarketingScreen.dart';
import 'package:point_of_sales_app_v3/Screens/ShoppingScreen.dart';
import 'package:point_of_sales_app_v3/Screens/SelfOrdersScreen.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);
  static String id = 'Home';

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late HomeController controller;
  TextEditingController uangYangDiterimaController = TextEditingController();
  TextEditingController customerNameController = TextEditingController();
  String _activeRoute = 'pos'; // 'pos', 'inventory', 'shopping', 'members', 'selforders'
  
  // Self-orders
  final SelfOrderService _selfOrderService = SelfOrderService.instance;
  StreamSubscription<int>? _selfOrdersCountSubscription;
  int _pendingSelfOrdersCount = 0;

  @override
  void initState() {
    super.initState();
    controller = HomeController();
    controller.addListener(_onControllerUpdate);
    
    // Set up message callback for showing snackbars
    controller.onShowMessage = (message, {bool isError = false}) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError ? Icons.error : Icons.info,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: isError ? Colors.red.shade700 : Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    };
    
    controller.initialize();
    
    // Initialize members cache
    MemberService.instance.initializeCache();

    // Initialize recommendation service and show snackbar
    _initializeRecommendationService();
    
    // Subscribe to self-orders count stream for badge
    _selfOrdersCountSubscription = _selfOrderService.getUnpaidOrderCountStream().listen(
      (count) {
        if (mounted) {
          setState(() {
            _pendingSelfOrdersCount = count;
          });
        }
      },
      onError: (error) {
        print('Error listening to self-orders count: $error');
      },
    );
  }

  Future<void> _initializeRecommendationService() async {
    // HIDDEN: Recommendation feature UI is hidden but backend remains for thesis documentation
    // Initialize silently without showing snackbar
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted) return;
    
    // Still initialize the service (backend kept for documentation)
    await RecommendationService.instance.initialize();
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerUpdate);
    controller.dispose();
    uangYangDiterimaController.dispose();
    customerNameController.dispose();
    _selfOrdersCountSubscription?.cancel();
    super.dispose();
  }

  void _onControllerUpdate() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Row(
          children: [
            // Sidebar
            SidebarWidget(
              orderButtonColor: controller.orderButtonColor,
              menuButtonColor: controller.menuButtonColor,
              printButtonColor: controller.printButtonColor,
              orderButtonOffset: controller.orderButtonOffset_y,
              menuButtonOffset: controller.menuButtonOffset_y,
              printButtonOffset: controller.printButtonOffset_y,
              printerIsConnected: controller.printerIsConnected,
              selfOrdersCount: _pendingSelfOrdersCount,
              onOrderPressed: () {
                setState(() => _activeRoute = 'pos');
                controller.changeButtonColors('order');
              },
              onMenuPressed: () {
                setState(() => _activeRoute = 'pos');
                controller.changeButtonColors('menu');
              },
              onPrintPressed: () => _handlePrintPressed(),
              onPrintLongPress: () => _handlePrintLongPress(),
              onResetPressed: () => controller.resetCustomerNumber(),
              // HIDDEN: Recommendation feature UI hidden but backend kept for thesis documentation
              onRulesPressed: null,
              onInventoryPressed: () => _navigateToInventory(),
              onShoppingPressed: () => _navigateToShopping(),
              onSelfOrdersPressed: () => _navigateToSelfOrders(),
              onMembersPressed: () => _navigateToMembers(),
              onLogoutPressed: _handleLogout,
            ),
            // Main Content Area
            if (_activeRoute == 'pos') ...[
              if (controller.menuButtonColor == Colors.grey.shade300)
                ..._buildOrderingView(),
              if (controller.menuButtonColor == Colors.white)
                _buildMenuManagementView(),
            ] else if (_activeRoute == 'inventory')
              const Expanded(flex: 12, child: InventoryScreen())
            else if (_activeRoute == 'shopping')
              const Expanded(flex: 12, child: ShoppingScreen())
            else if (_activeRoute == 'selforders')
              Expanded(
                flex: 12,
                child: SelfOrdersScreen(
                  onAcceptOrder: _handleAcceptSelfOrder,
                ),
              )
            else if (_activeRoute == 'members')
              const Expanded(flex: 12, child: MarketingScreen()),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildOrderingView() {
    return [
      // Ordering View (Menu Grid with Tabs)
      Expanded(
        flex: 8,
        child: OrderingViewWidget(
          menuObjectList_makanan: controller.menuObjectList_makanan,
          menuObjectList_minuman: controller.menuObjectList_minuman,
          categoryOrder: controller.categoryOrder,
          isTakeAway: controller.isTakeAway,
          onTakeAwayChanged: (value) => controller.setTakeAway(value),
          onMenuTap: (menu) =>
              controller.addToOrder(menu, controller.isTakeAway),
        ),
      ),
      // Order List and Summary
      Expanded(
        flex: 4,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.5),
                blurRadius: 3,
                spreadRadius: 3,
                offset: const Offset(1, 1),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header with customer number
              Expanded(
                flex: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12.0),
                      child: Text(
                        'Nomor Berikutnya: ${controller.nomorBerikutnya}',
                        style: GoogleFonts.poppins(
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Order List
              Expanded(
                flex: 6,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.shade500,
                        width: 1,
                      ),
                    ),
                  ),
                  child: OrderListWidget(
                    pesananList: controller.pesananList,
                    onIncrementDineIn: (index) =>
                        controller.incrementDineIn(index),
                    onDecrementDineIn: (index) =>
                        controller.decrementDineIn(index),
                    onIncrementTakeAway: (index) =>
                        controller.incrementTakeAway(index),
                    onDecrementTakeAway: (index) =>
                        controller.decrementTakeAway(index),
                  ),
                ),
              ),
              // Order Summary
              Expanded(
                flex: 2,
                child: OrderSummaryWidget(
                  biayaBungkus: controller.biayaBungkus,
                  totalHarga: controller.totalHarga,
                  onBuyPressed: _handleBuyPressed,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildMenuManagementView() {
    return Expanded(
      flex: 11,
      child: MenuManagementWidget(
        menuObjectList_makanan: controller.menuObjectList_makanan,
        menuObjectList_minuman: controller.menuObjectList_minuman,
        listGambar: controller.listGambar,
        categoryOrder: controller.categoryOrder,
      ),
    );
  }

  void _handlePrintPressed() {
    controller.changeButtonColors('print');
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return const ConnectPrinterDialog();
      },
    ).then((value) {
      controller.changeButtonColors('order');
      if (value != null) {
        controller.connectPrinter(value).catchError((e) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tidak terhubung ke printer'),
              duration: Duration(seconds: 2),
            ),
          );
        });
      }
    });
  }

  void _handlePrintLongPress() {
    controller.checkIfPrinterIsConnected();
    controller.testPrinter('test');
  }

  void _handleBuyPressed() {
    // Get all available menu item names for filtering recommendations
    final menuItemNames = controller.menuObjectList
        .map((menu) => menu.namaMenu)
        .toList();

    OrderConfirmationService.showOrderConfirmationDialog(
      context: context,
      pesananList: controller.pesananList,
      totalHarga: controller.totalHarga,
      isTakeAway: controller.isTakeAway,
      biayaBungkus: controller.biayaBungkus,
      customerNameController: customerNameController,
      uangYangDiterimaController: uangYangDiterimaController,
      nomorBerikutnya: controller.nomorBerikutnya,
      getTotal: controller.getTotal,
      printReceipt: ({int discountAmount = 0, int originalTotal = 0}) async =>
          await controller.printReceipt(
        controller.pesananList,
        controller.nomorBerikutnya,
        controller.totalHarga,
        controller.isTakeAway,
        discountAmount: discountAmount,
        originalTotal: originalTotal,
      ),
      getYear: controller.getYear,
      getMonth: controller.getMonth,
      getDate: controller.getDate,
      setJumlahItem: (value) => controller.jumlahItem = value,
      addRecommendedItem: controller.addRecommendedItem,
      menuItems: menuItemNames,
    );
  }

  void _navigateToInventory() {
    setState(() => _activeRoute = 'inventory');
  }

  void _navigateToMembers() {
    setState(() => _activeRoute = 'members');
  }

  void _navigateToShopping() {
    setState(() => _activeRoute = 'shopping');
  }

  void _navigateToSelfOrders() {
    setState(() => _activeRoute = 'selforders');
  }

  void _handleAcceptSelfOrder(SelfOrder order) {
    // Convert self-order to pesanan list and process
    final pesananList = _selfOrderService.convertToPesananList(order);
    final isTakeAway = _selfOrderService.isTakeAwayOrder(order);
    
    // Pre-fill customer name
    customerNameController.text = order.memberName;
    
    // Get all available menu item names for filtering recommendations
    final menuItemNames = controller.menuObjectList
        .map((menu) => menu.namaMenu)
        .toList();

    OrderConfirmationService.showSelfOrderConfirmationDialog(
      context: context,
      selfOrder: order,
      pesananList: pesananList,
      totalHarga: order.total,
      isTakeAway: isTakeAway,
      biayaBungkus: order.takeAwayFee,
      customerNameController: customerNameController,
      uangYangDiterimaController: uangYangDiterimaController,
      nomorBerikutnya: controller.nomorBerikutnya,
      getTotal: controller.getTotal,
      printReceipt: ({int discountAmount = 0, int originalTotal = 0}) async =>
          await controller.printReceipt(
        pesananList,
        controller.nomorBerikutnya,
        order.total,
        isTakeAway,
        discountAmount: discountAmount,
        originalTotal: originalTotal,
      ),
      getYear: controller.getYear,
      getMonth: controller.getMonth,
      getDate: controller.getDate,
      setJumlahItem: (value) => controller.jumlahItem = value,
      addRecommendedItem: controller.addRecommendedItem,
      menuItems: menuItemNames,
      onOrderCompleted: () {
        // Clear the customer name after order is completed
        customerNameController.clear();
        uangYangDiterimaController.clear();
      },
    );
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Apakah Anda yakin ingin logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          LoginScreen.id, 
          (route) => false
        );
      }
    }
  }
}
