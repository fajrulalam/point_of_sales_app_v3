import 'dart:async';
import 'dart:math';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/AlertDialogs/ConnectPrinterDialog.dart';
import 'package:point_of_sales_app_v3/BottomSheets/AddOrEditMenu.dart';
import 'package:point_of_sales_app_v3/Screens/Home.dart';
import 'package:point_of_sales_app_v3/Services/LoaderWidget.dart';
import 'package:point_of_sales_app_v3/Services/OrderConfirmationService.dart';
import 'package:point_of_sales_app_v3/Services/ThousandsSeparatorInputFormatter.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:point_of_sales_app_v3/Classes/Menu.dart';
import '../Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Classes/Assets.dart';
import 'package:cached_network_image/cached_network_image.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);
  static String id = 'Home';

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Timer? timer;
  Color orderButtonColor = Colors.white;
  Color menuButtonColor = Colors.grey.shade300;
  Color printButtonColor = Colors.grey.shade300;
  double oderButtonOffset_y = 0;
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
  TextEditingController uangYangDiterimaController = TextEditingController();
  TextEditingController customerNameController = TextEditingController();
  bool isUangKurang = false;
  bool isTakeAway = false;

  BluetoothDevice? selectedDevice;
  BlueThermalPrinter printer = BlueThermalPrinter.instance;
  bool printerIsConnected = false;
  int jumlahItem = 0;
  int biayaBungkus = 0;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    getMenu();
    getListGambar();
    // FirebaseFirestore.instance
    //     .collection("Canteens")
    //     .add({"test": 'halooo'}).then((value) {
    //   print('success');
    // });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        // For Android.
        statusBarColor: Colors.transparent,
        // For iOS.
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Container(
          child: Row(children: [
            Container(
              width: 80,
              child: Card(
                elevation: 2,
                child: Container(
                  color: Colors.teal.shade100,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          //drop shadow
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: orderButtonColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.5),
                                blurRadius: 1,
                                spreadRadius: 1,
                                //make the shadow on the right
                                offset: Offset(0, oderButtonOffset_y),
                              ),
                            ],
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: IconButton(
                              onPressed: () {
                                changeButtonColors('order');
                                print('pressed');
                              },
                              icon: Icon(Icons.restaurant)),
                        ),
                        SizedBox(height: 12),
                        Container(
                          //drop shadow
                          decoration: BoxDecoration(
                            //rounded corners
                            borderRadius: BorderRadius.circular(8),
                            color: menuButtonColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.5),
                                blurRadius: 1,
                                spreadRadius: 1,
                                //make the shadow on the right
                                offset: Offset(0, menuButtonOffset_y),
                              ),
                            ],
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: IconButton(
                              onPressed: () {
                                changeButtonColors('menu');
                                print('pressed');
                              },
                              icon: Icon(Icons.menu_book)),
                        ),
                        SizedBox(height: 12),
                        Container(
                          //drop shadow
                          decoration: BoxDecoration(
                            //rounded corners
                            borderRadius: BorderRadius.circular(8),
                            color: printButtonColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.5),
                                blurRadius: 1,
                                spreadRadius: 1,
                                //make the shadow on the right
                                offset: Offset(0, printButtonOffset_y),
                              ),
                            ],
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Stack(
                            children: [
                              //circle indicator positioned in top right
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: printerIsConnected
                                        ? Colors.green
                                        : Colors.black38,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              Center(
                                child: GestureDetector(
                                  onLongPress: () {
                                    checkIfPrinterIsConnected();
                                    testPrinter('test');
                                  },
                                  child: IconButton(
                                      onPressed: () {
                                        changeButtonColors('print');
                                        showDialog(
                                            context: context,
                                            builder: (BuildContext context) {
                                              return ConnectPrinterDialog();
                                            }).then((value) {
                                          changeButtonColors('order');

                                          try {
                                            selectedDevice = value;
                                            printer.connect(selectedDevice!);
                                          } catch (e) {
                                            //snackbar 'Tidak terhubung ke printer'
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                              content: Text(
                                                  'Tidak terhubung ke printer'),
                                              duration: Duration(seconds: 2),
                                            ));
                                          }
                                          checkIfPrinterIsConnected();
                                        });
                                      },
                                      icon: Icon(Icons.print)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Spacer(),
                        Container(
                          //drop shadow
                          decoration: BoxDecoration(
                            color: Colors.redAccent.shade100,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.5),
                                blurRadius: 1,
                                spreadRadius: 1,
                                //make the shadow on the right
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          margin: const EdgeInsets.only(
                              left: 4.0, right: 4.0, bottom: 12.0),
                          child: IconButton(
                              onPressed: () {
                                FirebaseFirestore.instance
                                    .collection("Canteens")
                                    .doc('canteen375')
                                    .update({'customerNumber': 0});

                                FirebaseFirestore.instance
                                    .collection("RecentyServed")
                                    .get()
                                    .then((value) {
                                  List documentID = [];
                                  //loop through all the QueryDocumentSnapshot
                                  value.docs.forEach((element) {
                                    documentID.add(element.id);
                                  });

                                  documentID.forEach((element) {
                                    FirebaseFirestore.instance
                                        .collection("RecentyServed")
                                        .doc(element)
                                        .delete();
                                  });
                                });
                              },
                              icon: Icon(Icons.restart_alt)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (menuButtonColor == Colors.grey.shade300)
              Expanded(
                flex: 8,
                child: Container(
                  color: Colors.white,
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                            child: TabBar(
                          labelColor: Colors.teal,
                          labelStyle:
                              GoogleFonts.poppins(fontWeight: FontWeight.bold),
                          unselectedLabelStyle: GoogleFonts.poppins(
                              fontWeight: FontWeight.normal),
                          unselectedLabelColor: Colors.grey.shade400,
                          indicatorColor: Colors.teal,
                          tabs: const [
                            Tab(
                              text: 'Makanan',
                            ),
                            Tab(
                              text: 'Minuman',
                            ),
                          ],
                        )),
                        Expanded(
                            child: TabBarView(
                          children: [
                            makananGridView(context, menuObjectList_makanan),
                            makananGridView(context, menuObjectList_minuman),
                          ],
                        )),
                        Divider(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Spacer(),
                            Checkbox(
                                value: isTakeAway,
                                onChanged: (bungkusOrNot) {
                                  setState(() {
                                    isTakeAway = bungkusOrNot!;
                                  });
                                }),
                            GestureDetector(
                                onTap: () {
                                  setState(() {
                                    isTakeAway = !isTakeAway;
                                  });
                                },
                                child: Text('Bungkus')),
                            SizedBox(
                              width: 24,
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ),
            if (menuButtonColor == Colors.grey.shade300)
              Expanded(
                flex: 4,
                child: Container(
                  //make it have elevation
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.5),
                        blurRadius: 3,
                        spreadRadius: 3,
                        //make the shadow on the right
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.teal.shade100,
                            //add border to the bottom
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
                                'Nomor Berikutnya: $nomorBerikutnya',
                                style: GoogleFonts.poppins(
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.1,
                                    fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                      ),
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
                          child: ListView.builder(
                            itemCount: pesananList.length,
                            itemBuilder: (BuildContext context, int index) {
                              final order = pesananList[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0, vertical: 4.0),
                                child: Container(
                                  margin: const EdgeInsets.only(top: 4.0),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade300,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Item name:
                                      Text(
                                        order.namaPesanan,
                                        style: GoogleFonts.montserrat(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.1,
                                          fontSize: 18,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      // Two counters side by side:
                                      Row(
                                        children: [
                                          // Dine In Counter:
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text("Dine In",
                                                    style: GoogleFonts.poppins(
                                                        fontSize: 14)),
                                                Row(
                                                  children: [
                                                    IconButton(
                                                      onPressed: () {
                                                        setState(() {
                                                          if (order
                                                                  .dineInQuantity >
                                                              0) {
                                                            order
                                                                .dineInQuantity--;
                                                            // If no items remain at all, remove the order:
                                                            if (order
                                                                    .totalQuantity ==
                                                                0) {
                                                              pesananList
                                                                  .removeAt(
                                                                      index);
                                                            }
                                                          }
                                                          getTotal();
                                                        });
                                                      },
                                                      icon: Icon(
                                                        Icons
                                                            .remove_circle_outline_rounded,
                                                        color: Colors.redAccent,
                                                        size: 24,
                                                      ),
                                                    ),
                                                    Text(
                                                      order.dineInQuantity
                                                          .toString(),
                                                      style:
                                                          GoogleFonts.poppins(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      onPressed: () {
                                                        setState(() {
                                                          order
                                                              .dineInQuantity++;
                                                          getTotal();
                                                        });
                                                      },
                                                      icon: Icon(
                                                        Icons
                                                            .add_circle_outline_rounded,
                                                        color: Colors.green,
                                                        size: 24,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Take Away Counter:
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text("Take Away",
                                                    style: GoogleFonts.poppins(
                                                        fontSize: 14)),
                                                Row(
                                                  children: [
                                                    IconButton(
                                                      onPressed: () {
                                                        setState(() {
                                                          if (order
                                                                  .takeAwayQuantity >
                                                              0) {
                                                            order
                                                                .takeAwayQuantity--;
                                                            if (order
                                                                    .totalQuantity ==
                                                                0) {
                                                              pesananList
                                                                  .removeAt(
                                                                      index);
                                                            }
                                                          }
                                                          getTotal();
                                                        });
                                                      },
                                                      icon: Icon(
                                                        Icons
                                                            .remove_circle_outline_rounded,
                                                        color: Colors.redAccent,
                                                        size: 24,
                                                      ),
                                                    ),
                                                    Text(
                                                      order.takeAwayQuantity
                                                          .toString(),
                                                      style:
                                                          GoogleFonts.poppins(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      onPressed: () {
                                                        setState(() {
                                                          order
                                                              .takeAwayQuantity++;
                                                          getTotal();
                                                        });
                                                      },
                                                      icon: Icon(
                                                        Icons
                                                            .add_circle_outline_rounded,
                                                        color: Colors.green,
                                                        size: 24,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8),
                                      // Display the subtotal for this order line:
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Container(
                                          color: Colors.grey.shade200,
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 12.0, vertical: 5.0),
                                          margin: EdgeInsets.only(right: 8.0),
                                          child: Text(
                                            'Rp ${NumberFormat.decimalPattern().format(order.subtotal).replaceAll(',', '.')}',
                                            style: GoogleFonts.notoSans(
                                              color: Colors.black54,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.1,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            // Wrap the inner Column in a SingleChildScrollView to avoid overflow.
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Conditionally display the Biaya Bungkus row.
                                  if (biayaBungkus > 0) ...[
                                    Row(
                                      children: [
                                        Text(
                                          'Biaya Bungkus',
                                          style: GoogleFonts.poppins(
                                            color: Colors.grey,
                                            fontWeight: FontWeight
                                                .w300, // thin text weight
                                            letterSpacing: 0.1,
                                            fontSize: 18,
                                          ),
                                        ),
                                        Spacer(),
                                        Text(
                                          'Rp ${NumberFormat.decimalPattern().format(biayaBungkus).replaceAll(',', '.')}',
                                          style: GoogleFonts.poppins(
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w300,
                                            letterSpacing: 0.1,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 4),
                                  ],
                                  // Total row remains unchanged.
                                  Row(
                                    children: [
                                      Text(
                                        'Total',
                                        style: GoogleFonts.poppins(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.1,
                                          fontSize: 18,
                                        ),
                                      ),
                                      Spacer(),
                                      Text(
                                        'Rp ${NumberFormat.decimalPattern().format(totalHarga).replaceAll(',', '.')}',
                                        style: GoogleFonts.poppins(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.1,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // The BELI button remains at the bottom.
                                  Container(
                                    margin: const EdgeInsets.only(
                                        left: 16.0, right: 16.0, top: 4),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12.0),
                                        ),
                                        backgroundColor: Colors.teal,
                                      ),
                                      onPressed: () {
                                        OrderConfirmationService.showOrderConfirmationDialog(
                                          context: context,
                                          pesananList: pesananList,
                                          totalHarga: totalHarga,
                                          isTakeAway: isTakeAway,
                                          biayaBungkus: biayaBungkus,
                                          customerNameController: customerNameController,
                                          uangYangDiterimaController: uangYangDiterimaController,
                                          nomorBerikutnya: nomorBerikutnya,
                                          quoteKejujuran: quoteKejujuran,
                                          getTotal: getTotal,
                                          printReceipt: ({int discountAmount = 0, int originalTotal = 0}) => printReceipt(pesananList, nomorBerikutnya, totalHarga, isTakeAway, discountAmount: discountAmount, originalTotal: originalTotal),
                                          getYear: getYear,
                                          getMonth: getMonth,
                                          getDate: getDate,
                                          setJumlahItem: (value) => jumlahItem = value,
                                        );
                                      },
                                      child: Text(
                                        'BELI',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (menuButtonColor == Colors.white)
              Expanded(
                  flex: 11,
                  child: Container(
                      margin: EdgeInsets.only(top: 16),
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      color: Colors.white,
                      child: Row(
                        children: [
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Makanan',
                                      style: GoogleFonts.montserrat(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black54)),
                                  SizedBox(
                                    width: 24,
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      addOrEditMenu(context,
                                          query: 'add',
                                          makananOrMinuman: 'Makanan');
                                    },
                                    child: Container(
                                      height: 35,
                                      width: 50,
                                      decoration: BoxDecoration(
                                          color: Colors.blueAccent,
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      child: InkWell(
                                        child: Icon(
                                          Icons.add,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  )
                                ],
                              ),
                              SizedBox(
                                height: 16,
                              ),
                              Container(
                                height:
                                    MediaQuery.of(context).size.height * 0.8,
                                child: ListView.separated(
                                    separatorBuilder: (context, index) =>
                                        Divider(
                                          color: Colors.grey.withOpacity(0.5),
                                          height: 0.4,
                                        ),
                                    itemCount: menuObjectList_makanan.length,
                                    shrinkWrap: true,
                                    itemBuilder:
                                        (BuildContext context, int index) {
                                      return ListTile(
                                        title: Text(
                                            menuObjectList_makanan[index]
                                                .namaMenu,
                                            style: GoogleFonts.poppins()),
                                        trailing: Container(
                                          width: 135,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              OutlinedButton(
                                                child: Icon(Icons.edit),
                                                onPressed: () {
                                                  addOrEditMenu(context,
                                                      query: 'edit',
                                                      makananOrMinuman:
                                                          'Makanan',
                                                      menuObject:
                                                          menuObjectList_makanan[
                                                              index]);
                                                  print(
                                                      'pressed edit makananan');
                                                },
                                              ),
                                              OutlinedButton(
                                                child: Icon(
                                                  Icons.delete,
                                                  color: Colors.redAccent,
                                                ),
                                                onPressed: () {
                                                  FirebaseFirestore.instance
                                                      .collection('Canteens')
                                                      .doc('canteen375')
                                                      .collection(
                                                          'MenuCollection')
                                                      .doc(
                                                          menuObjectList_makanan[
                                                                  index]
                                                              .id)
                                                      .delete();
                                                  print(
                                                      'pressed hapus makanan');
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                              )
                            ],
                          )),
                          SizedBox(
                            width: 16,
                          ),
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Minuman',
                                      style: GoogleFonts.montserrat(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black54)),
                                  SizedBox(
                                    width: 24,
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      addOrEditMenu(context,
                                          query: 'add',
                                          makananOrMinuman: 'Minuman');
                                    },
                                    child: Container(
                                      height: 35,
                                      width: 50,
                                      decoration: BoxDecoration(
                                          color: Colors.blueAccent,
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                      child: InkWell(
                                        child: Icon(
                                          Icons.add,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  )
                                ],
                              ),
                              SizedBox(
                                height: 16,
                              ),
                              Container(
                                height:
                                    MediaQuery.of(context).size.height * 0.8,
                                child: ListView.separated(
                                    separatorBuilder: (context, index) =>
                                        Divider(
                                          color: Colors.grey.withOpacity(0.5),
                                          height: 0.4,
                                        ),
                                    itemCount: menuObjectList_minuman.length,
                                    shrinkWrap: true,
                                    itemBuilder:
                                        (BuildContext context, int index) {
                                      return ListTile(
                                        title: Text(
                                            menuObjectList_minuman[index]
                                                .namaMenu,
                                            style: GoogleFonts.poppins()),
                                        trailing: Container(
                                          width: 135,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              OutlinedButton(
                                                child: Icon(Icons.edit),
                                                onPressed: () {
                                                  print('pressed edit miniman');
                                                  addOrEditMenu(context,
                                                      query: 'edit',
                                                      makananOrMinuman:
                                                          'Minuman',
                                                      menuObject:
                                                          menuObjectList_minuman[
                                                              index]);
                                                },
                                              ),
                                              OutlinedButton(
                                                child: Icon(
                                                  Icons.delete,
                                                  color: Colors.redAccent,
                                                ),
                                                onPressed: () {
                                                  FirebaseFirestore.instance
                                                      .collection('Canteens')
                                                      .doc('canteen375')
                                                      .collection(
                                                          'MenuCollection')
                                                      .doc(
                                                          menuObjectList_minuman[
                                                                  index]
                                                              .id)
                                                      .delete();

                                                  print(
                                                      'pressed delete minuman ${menuObjectList_makanan[index].id}');
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                              )
                            ],
                          ))
                        ],
                      )))
          ]),
        ),
      ),
    );
  }

  void getTotal() {
    // First, calculate the subtotal for all orders.
    int subtotal = pesananList.fold(0, (acc, order) => acc + order.subtotal);

    // If the "Bungkus" (take-away) checkbox is ticked,
    // sum only the takeAwayQuantity from each order.

    int totalTakeAway =
        pesananList.fold(0, (sum, order) => sum + order.takeAwayQuantity);
    // For every 4 take-away items, charge 1000.
    biayaBungkus = (totalTakeAway ~/ 4) * 1000;

    // The final total is the subtotal plus the packaging fee.
    totalHarga = subtotal + biayaBungkus;
    setState(() {});
  }

  void getMenu() {
    DocumentReference customerNumber =
        FirebaseFirestore.instance.collection('Canteens').doc('canteen375');

    customerNumber.snapshots().listen((event) {
      //change document snapshot 'event' to a map
      Map map = event.data() as Map<String, dynamic>;
      setState(() {
        nomorBerikutnya = map['customerNumber'] + 1;
      });
    });

    CollectionReference menuCollection = FirebaseFirestore.instance
        .collection('Canteens')
        .doc('canteen375')
        .collection('MenuCollection');
    menuCollection.snapshots().listen((snapshot) {
      setState(() {
        menuObjectList = MenuClass.getAllMenus(snapshot);
        menuObjectList_makanan = menuObjectList
            .where((element) => element.isMakanan == true)
            .toList();
        menuObjectList_minuman = menuObjectList
            .where((element) => element.isMakanan == false)
            .toList();
      });
      print('MENU ${menuObjectList[0].namaMenu}');
      print('MENU ${menuObjectList[1].namaMenu}');
    });
  }

  Widget makananGridView(
      BuildContext context, List<MenuObject> menuObjectList) {
    return GridView.builder(
      itemCount: menuObjectList.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.width ~/ 240,
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
        childAspectRatio: 180 / 180,
      ),
      itemBuilder: (BuildContext context, int index) {
        if (menuObjectList.isEmpty) {
          return Center(
            child: CircularProgressIndicator(),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                print('tapped ${menuObjectList[index].namaMenu}');
                int orderIndex = pesananList.indexWhere((element) =>
                    element.namaPesanan == menuObjectList[index].namaMenu);

                if (orderIndex == -1) {
                  if (isTakeAway) {
                    // Create a new order with 1 take-away item.
                    pesananList.add(PesananObject(
                      namaPesanan: menuObjectList[index].namaMenu,
                      harga: menuObjectList[index].harga,
                      dineInQuantity: 0,
                      takeAwayQuantity: 1,
                    ));
                  } else {
                    // Create a new order with 1 dine-in item.
                    pesananList.add(PesananObject(
                      namaPesanan: menuObjectList[index].namaMenu,
                      harga: menuObjectList[index].harga,
                      dineInQuantity: 1,
                      takeAwayQuantity: 0,
                    ));
                  }
                } else {
                  // Increment the appropriate quantity.
                  if (isTakeAway) {
                    pesananList[orderIndex].takeAwayQuantity++;
                  } else {
                    pesananList[orderIndex].dineInQuantity++;
                  }
                }
                getTotal();
                setState(() {});
              },
              borderRadius: BorderRadius.circular(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (menuObjectList[index].imagePath != 'tidak ada')
                    Container(
                      height: 110,
                      width: 110,
                      child: Image(
                        image: CachedNetworkImageProvider(
                            menuObjectList[index].imagePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  Text(
                    menuObjectList[index].namaMenu,
                    style: GoogleFonts.montserrat(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String getYear() {
    //get this year and return it as string
    DateTime now = DateTime.now();
    String year = DateFormat('yyyy').format(now);
    return year;
  }

  String getMonth() {
    //get this year-month and return it as string  (format yyyy-mm)
    DateTime now = DateTime.now();
    String month = DateFormat('yyyy-MM').format(now);
    return month;
  }

  String getDate() {
    //get this year-month and return it as string  (format yyyy-mm)
    DateTime now = DateTime.now();
    String date = DateFormat('yyyy-MM-dd').format(now);
    return date;
  }

  void _startTimer(int index, {bool isTakeAway = false}) {
    timer = Timer.periodic(Duration(milliseconds: 1000), (_) {
      // Haptic feedback for each increment.
      HapticFeedback.heavyImpact();
      setState(() {
        if (isTakeAway) {
          pesananList[index].takeAwayQuantity += 10;
        } else {
          pesananList[index].dineInQuantity += 10;
        }
        getTotal();
      });
    });
  }

  void _stopTimer() {
    timer?.cancel();
  }

  void changeButtonColors(String s) {
    switch (s) {
      case 'print':
        printButtonColor = Colors.white;
        printButtonOffset_y = 0;
        menuButtonOffset_y = 4;
        menuButtonColor = Colors.grey.shade300;
        orderButtonColor = Colors.grey.shade300;
        oderButtonOffset_y = 4;
        break;
      case 'order':
        printButtonColor = Colors.grey.shade300;
        printButtonOffset_y = 4;
        menuButtonOffset_y = 4;
        menuButtonColor = Colors.grey.shade300;
        orderButtonColor = Colors.white;
        oderButtonOffset_y = 0;
        break;
      case 'menu':
        printButtonColor = Colors.grey.shade300;
        printButtonOffset_y = 4;
        menuButtonOffset_y = 0;
        menuButtonColor = Colors.white;
        orderButtonColor = Colors.grey.shade300;
        oderButtonOffset_y = 4;
        break;
      default:
        print('nothing');
    }

    setState(() {});
  }

  Future<void> checkIfPrinterIsConnected() async {
    if ((await printer.isConnected)!) {
      print("Printer is connected ${selectedDevice?.name!}");
      setState(() {
        printerIsConnected = true;
      });
    } else {
      print("Printer is not connected");
      printerIsConnected = false;
    }
  }

  void printReceipt(List<PesananObject> pesananList, int nomorBerikutnya,
      int totalHarga, bool isTakeAway, {int discountAmount = 0, int originalTotal = 0}) {
    if (!printerIsConnected) return;
    printer.printCustom("375 Canteen", 3, 1);
    printer.printNewLine();
    printer.printNewLine();
    printer.printCustom("No. $nomorBerikutnya", 3, 1);
    printer.printNewLine();
    printer.print3Column('ITEM.', 'QTY', 'SUBTOTAL', 1);
    pesananList.forEach((element) {
      printer.print3Column(element.namaPesanan,
          element.totalQuantity.toString(), element.subtotal.toString(), 1);
    });
    if (isTakeAway) {
      printer.print3Column(
          'Bungkus', jumlahItem.toString(), biayaBungkus.toString(), 1);
    }
    if (discountAmount > 0) {
      printer.printNewLine();
      printer.printCustom('SUBTOTAL: Rp $originalTotal', 1, 0);
      printer.printCustom('DISKON: -Rp $discountAmount', 1, 0);
    }
    printer.printNewLine();
    printer.printCustom('TOT.: Rp $totalHarga', 3, 0);
    printer.printNewLine();
    printer.printNewLine();
    printer.printNewLine();
    printer.printNewLine();
  }

  Future<void> testPrinter(String invoice) async {
    if (printerIsConnected) {
      await Future.delayed(Duration(milliseconds: 500));

      /**
       * SIZE
       * 0 :  Normal
       * 1 :  Nomral Bold
       * 2 : Medium Bold
       * 3 : Large Bold
       *
       * ALIGN
       * 0 : Left
       * 1 : Center
       * 2 : Right
       */
      printer.printCustom("Pinter sudah terhubung.", 3, 1);
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();
      printer.paperCut();

      // printer.printer.printCustom(invoice_update.santriPembayar!.name!, 2, 1);
    }
  }

  Future<void> listExample() async {
    final storageRef = FirebaseStorage.instance.ref().child("/pos375_assets");
    final listResult = await storageRef.listAll();

    for (var prefix in listResult.prefixes) {
      print(prefix);
    }
    List<String> imageList = [];

    for (var item in listResult.items) {
      imageList.add(
          'gs://point-of-sales-app-25e2b.appspot.com/pos375_assets/${item.name}');
    }

    print(imageList);
  }

  Future<void> getListGambar() async {
    FirebaseFirestore.instance.collection('assets').get().then((value) {
      listGambar = AssetsClass.getImageAssets(value);
    });
  }

  void addOrEditMenu(
    BuildContext context, {
    required String query,
    required String makananOrMinuman,
    MenuObject? menuObject,
  }) {
    showModalBottomSheet(
        isScrollControlled: true,
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        context: context,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16.0), topRight: Radius.circular(16.0)),
        ),
        builder: (context) {
          if (query == 'edit') {
            return AddMenuBottomSheet(
              query: query,
              makananOrMinuman: makananOrMinuman,
              menuObject: menuObject,
              listGambar: listGambar,
            );
          } else {
            return AddMenuBottomSheet(
              query: query,
              makananOrMinuman: makananOrMinuman,
              listGambar: listGambar,
            );
          }
        }).then((value) {
      print('hello it works like this kok');
    });
  }
}
