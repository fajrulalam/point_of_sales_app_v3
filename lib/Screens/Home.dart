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
import 'package:point_of_sales_app_v3/Services/OpenBillService.dart';
import 'package:point_of_sales_app_v3/Models/SelfOrder.dart';
import 'package:point_of_sales_app_v3/Models/OpenBill.dart';
import 'package:point_of_sales_app_v3/BottomSheets/OptionSelectionBottomSheet.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
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
import 'package:point_of_sales_app_v3/Screens/LiveTabsScreen.dart';
import 'package:point_of_sales_app_v3/BottomSheets/FinancialReportBottomSheet.dart';
import 'package:point_of_sales_app_v3/BottomSheets/QuickExpenseBottomSheet.dart';
import 'package:point_of_sales_app_v3/Screens/VoucherProgramScreen.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

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
  String _activeRoute = 'pos_order';
  bool _sidebarMinimized = false;
  
  // Self-orders & Open Bills
  final SelfOrderService _selfOrderService = SelfOrderService.instance;
  final OpenBillService _openBillService = OpenBillService.instance;
  StreamSubscription<int>? _selfOrdersCountSubscription;
  StreamSubscription<List<OpenBill>>? _openBillsSubscription;
  int _pendingSelfOrdersCount = 0;
  int _pendingOpenBillsCount = 0;

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
      onError: (e) => print('Error in self-orders stream: $e'),
    );

    // Subscribe to open bills stream for badge
    _openBillsSubscription = _openBillService.getOpenBillsStream().listen(
      (bills) {
        if (mounted) {
          setState(() {
            _pendingOpenBillsCount = bills.length;
          });
        }
      },
      onError: (e) => print('Error in open bills stream: $e'),
    );
  }

  Future<void> _initializeRecommendationService() async {
    // HIDDEN: Recommendation feature is fully disabled to avoid unnecessary processing.
    // Backend code is kept for thesis documentation but not executed at runtime.
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerUpdate);
    controller.dispose();
    uangYangDiterimaController.dispose();
    customerNameController.dispose();
    _selfOrdersCountSubscription?.cancel();
    _openBillsSubscription?.cancel();
    super.dispose();
  }

  void _onControllerUpdate() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const double expandedWidth = 220;
    final double sidebarWidth = _sidebarMinimized ? 0 : expandedWidth;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
    body: Stack(
      children: [
        // 1. Layout Base (Content + Space for Sidebar)
        Row(
          children: [
            // Dummy space filler to push main content
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              width: sidebarWidth,
            ),
            // Main Content Area
            Expanded(
              child: _buildMainContent(),
            ),
          ],
        ),
        // 2. Sidebar (on top)
        SidebarWidget(
          printerIsConnected: controller.printerIsConnected,
          liveTabsCount: _pendingSelfOrdersCount + _pendingOpenBillsCount,
          activeRoute: _activeRoute,
          isExpanded: true, // Always true when not minimized
          isMinimized: _sidebarMinimized,
          onExpandToggled: () => setState(() {
            _sidebarMinimized = !_sidebarMinimized;
          }),
          onMinimizeToggled: () => setState(() {
            _sidebarMinimized = !_sidebarMinimized;
          }),
          onOrderPressed: () => setState(() => _activeRoute = 'pos_order'),
          onMenuPressed: () => setState(() => _activeRoute = 'pos_menu'),
          onPrintPressed: () => _handlePrintPressed(),
          onPrintLongPress: () => _handlePrintLongPress(),
          onResetPressed: () => controller.resetCustomerNumber(),
          onRulesPressed: null,
          onInventoryPressed: () => _navigateToInventory(),
          onShoppingPressed: () => _navigateToShopping(),
          onSelfOrdersPressed: () => _navigateToSelfOrders(),
          onMembersPressed: () => _navigateToMembers(),
          onQuickExpensePressed: () => _showQuickExpense(),
          onFinancialReportPressed: () => _showFinancialReport(),
          onVoucherProgramPressed: () => _navigateToVoucherProgram(),
          onTestingModeToggled: _handleTestingModeToggle,
          onLogoutPressed: _handleLogout,
        ),
        // 3. Floating Bubble (Direct child of Stack to fix hit-testing)
        if (_sidebarMinimized)
          Positioned(
            left: 20,
            bottom: 32,
            child: _buildFloatingBubble(),
          ),
        // 4. Testing mode banner
        if (Col.testingMode.value)
          Positioned(
            top: 0,
            left: sidebarWidth,
            right: 0,
            child: Container(
              color: Colors.orange.shade700,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: const Center(
                child: Text(
                  'TESTING MODE — data will not affect production',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  ),
);
}

Widget _buildFloatingBubble() {
  return InkWell(
    onTap: () => setState(() {
      _sidebarMinimized = false;
    }),
    child: Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF069494), // kDarkTeal
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF069494).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.restaurant_menu_rounded,
            color: Color(0xFFF5C518), // kWarmYellow
            size: 28,
          ),
          if (_pendingSelfOrdersCount + _pendingOpenBillsCount > 0)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Center(
                  child: Text(
                    '${_pendingSelfOrdersCount + _pendingOpenBillsCount}',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Widget _buildMainContent() {
  if (_activeRoute == 'pos_order') {
    return Row(children: _buildOrderingView());
  } else if (_activeRoute == 'pos_menu') {
    return _buildMenuManagementView();
  } else if (_activeRoute == 'inventory') {
    return const InventoryScreen();
  } else if (_activeRoute == 'shopping') {
    return const ShoppingScreen();
  } else if (_activeRoute == 'selforders') {
    return LiveTabsScreen(
      onAcceptOrder: _handleAcceptSelfOrder,
      homeController: controller,
    );
  } else if (_activeRoute == 'members') {
    return const MarketingScreen();
  } else if (_activeRoute == 'voucher_program') {
    return const VoucherProgramScreen();
  }
  return const SizedBox.shrink();
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
          onMenuTap: (menu) => _handleMenuTap(menu),
        ),
      ),
      // Order List and Summary
      Expanded(
        flex: 3,
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
                    color: const Color(0xFFF5F5F0),
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
                    onNoteChanged: (index, note) {
                      setState(() {
                        controller.pesananList[index].customerNote = note;
                      });
                    },
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
        onDeleteCatalogImage: controller.deleteCatalogImage,
      ),
    );
  }

  Future<void> _handleMenuTap(dynamic menu) async {
    final linkedGroups = controller.getLinkedOptionGroups(menu.id);

    if (linkedGroups.isEmpty) {
      await controller.addToOrder(menu, controller.isTakeAway);
      return;
    }

    final result = await OptionSelectionBottomSheet.show(
      context,
      menu: menu,
      linkedGroups: linkedGroups,
    );

    if (result != null) {
      await controller.addToOrder(
        menu,
        controller.isTakeAway,
        options: result.options,
        quantity: result.quantity,
      );
    }
  }

  void _handlePrintPressed() {
    final prevRoute = _activeRoute;
    setState(() => _activeRoute = 'printer');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ConnectPrinterDialog(controller: controller);
      },
    ).then((value) {
      if (mounted) {
        setState(() => _activeRoute = prevRoute);
      }
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
      printReceipt: controller.printReceipt,
      getYear: controller.getYear,
      getMonth: controller.getMonth,
      getDate: controller.getDate,
      setJumlahItem: (value) => controller.jumlahItem = value,
      addRecommendedItem: controller.addRecommendedItem,
      menuItems: menuItemNames,
      printerIsConnected: controller.printerIsConnected,
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

  void _navigateToVoucherProgram() {
    setState(() => _activeRoute = 'voucher_program');
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
      printReceipt: ({
        List<PesananObject>? customPesananList,
        int? overrideNomorBerikutnya,
        int? overrideTotalHarga,
        bool? overrideIsTakeAway,
        int discountAmount = 0,
        int originalTotal = 0,
      }) async =>
          await controller.printReceipt(
        customPesananList: customPesananList ?? pesananList,
        overrideNomorBerikutnya: overrideNomorBerikutnya ?? controller.nomorBerikutnya,
        overrideTotalHarga: overrideTotalHarga ?? order.total,
        overrideIsTakeAway: overrideIsTakeAway ?? isTakeAway,
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

  void _showQuickExpense() {
    final prevRoute = _activeRoute;
    setState(() => _activeRoute = 'quick_expense');

    QuickExpenseBottomSheet.show(context).then((_) {
      if (mounted) {
        setState(() => _activeRoute = prevRoute);
      }
    });
  }

  void _showFinancialReport() {
    final prevRoute = _activeRoute;
    setState(() => _activeRoute = 'financial');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FinancialReportBottomSheet(),
    ).then((_) {
      if (mounted) {
        setState(() => _activeRoute = prevRoute);
      }
    });
  }

  Future<void> _handleTestingModeToggle() async {
    final turning = Col.testingMode.value ? 'OFF' : 'ON';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Turn $turning Testing Mode?'),
        content: Text(
          Col.testingMode.value
              ? 'Switching back to production data.'
              : 'All reads/writes will go to testing collections. '
                'Data will be migrated on first activation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Col.testingMode.value ? Colors.teal : Colors.orange,
            ),
            child: Text('Turn $turning'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Col.toggle();
      if (mounted) {
        // Reinitialize controller to reload data from the new collections
        controller.removeListener(_onControllerUpdate);
        controller.dispose();
        controller = HomeController();
        controller.addListener(_onControllerUpdate);
        controller.onShowMessage = (message, {bool isError = false}) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        };
        controller.initialize();
        setState(() {});
      }
    }
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
