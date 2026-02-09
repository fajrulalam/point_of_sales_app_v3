import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/AlertDialogs/ConnectPrinterDialog.dart';
import 'package:point_of_sales_app_v3/Controllers/HomeController.dart';
import 'package:point_of_sales_app_v3/Services/OrderConfirmationService.dart';
import 'package:point_of_sales_app_v3/Services/RecommendationService.dart';
import 'package:point_of_sales_app_v3/Widgets/MenuManagementWidget.dart';
import 'package:point_of_sales_app_v3/Widgets/OrderListWidget.dart';
import 'package:point_of_sales_app_v3/Widgets/OrderSummaryWidget.dart';
import 'package:point_of_sales_app_v3/Widgets/OrderingViewWidget.dart';
import 'package:point_of_sales_app_v3/Widgets/RulesTableDialog.dart';
import 'package:point_of_sales_app_v3/Widgets/SidebarWidget.dart';

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

  @override
  void initState() {
    super.initState();
    controller = HomeController();
    controller.addListener(_onControllerUpdate);
    controller.initialize();
    
    // Initialize recommendation service and show snackbar
    _initializeRecommendationService();
  }

  Future<void> _initializeRecommendationService() async {
    // Wait for the widget to be fully built before showing snackbar
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted) return;
    
    final result = await RecommendationService.instance.initialize();
    
    if (!mounted) return;
    
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Recommendation rules fetched: ${result.ruleCount}',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.teal.shade600,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          action: SnackBarAction(
            label: 'Check rules',
            textColor: Colors.white,
            onPressed: () {
              RulesTableDialog.show(context);
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Failed to fetch recommendation rules: ${result.errorMessage ?? "Unknown error"}',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerUpdate);
    controller.dispose();
    uangYangDiterimaController.dispose();
    customerNameController.dispose();
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
              onOrderPressed: () => controller.changeButtonColors('order'),
              onMenuPressed: () => controller.changeButtonColors('menu'),
              onPrintPressed: () => _handlePrintPressed(),
              onPrintLongPress: () => _handlePrintLongPress(),
              onResetPressed: () => controller.resetCustomerNumber(),
              onRulesPressed: () => RulesTableDialog.show(context),
            ),
            // Main Content Area
            if (controller.menuButtonColor == Colors.grey.shade300)
              ..._buildOrderingView(),
            if (controller.menuButtonColor == Colors.white)
              _buildMenuManagementView(),
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
                    color: Colors.teal.shade100,
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
      quoteKejujuran: controller.quoteKejujuran,
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
}
