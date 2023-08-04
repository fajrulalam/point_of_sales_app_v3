import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ConnectPrinterDialog extends StatefulWidget {
  const ConnectPrinterDialog({Key? key}) : super(key: key);

  @override
  State<ConnectPrinterDialog> createState() => _ConnectPrinterDialogState();
}

class _ConnectPrinterDialogState extends State<ConnectPrinterDialog> {
  bool printReceipt = true;
  bool printerIsConnected = false;
  List<BluetoothDevice> devices = [];
  BluetoothDevice? selectedDevice;
  BlueThermalPrinter printer = BlueThermalPrinter.instance;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    getPrinters();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Container(
            width: 300,
            height: 150,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      child: Center(
                        child: Text(
                          'Connect to printer',
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        if (printerIsConnected) {
                          Navigator.pop(context, selectedDevice);
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      child: Container(
                        width: 90,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          border: Border.all(color: Colors.grey, width: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.save,
                              color: Colors.white,
                            ),
                            SizedBox(
                              width: 4,
                            ),
                            Text('Simpan',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                            //toggle switch
                            // Switch(
                            //   value: printReceipt,
                            //   onChanged: (value) async {
                            //     setState(() {
                            //       printReceipt = !printReceipt;
                            //     });
                            //
                            //     if (printReceipt == false) {
                            //       await printer.disconnect();
                            //       checkIfPrinterIsConnected();
                            //       setState(() {});
                            //     }
                            //   },
                            // ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Visibility(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: DropdownButton<BluetoothDevice>(
                                  hint: const Text('Pilih printer'),
                                  value: selectedDevice,
                                  items: devices
                                      .map((e) => DropdownMenuItem(
                                          child: Text(e.name!), value: e))
                                      .toList(),
                                  onChanged: (device) {
                                    setState(() {
                                      selectedDevice = device;
                                      printer.connect(selectedDevice!);
                                      checkIfPrinterIsConnected();
                                    });
                                  }),
                            ),
                            SizedBox(width: 30),
                            Container(
                              height: 12,
                              width: 12,
                              decoration: BoxDecoration(
                                color: printerIsConnected
                                    ? Colors.green
                                    : Colors.grey,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: printerIsConnected
                                        ? Colors.green.withOpacity(0.3)
                                        : Colors.grey.withOpacity(0.3),
                                    spreadRadius: 2,
                                    blurRadius: 5,
                                    offset: Offset(0, 0),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Container(
                          width: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey, width: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: InkWell(
                              onTap: () {
                                testPrinter('test');
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.print),
                                  SizedBox(width: 4),
                                  Text("Coba Printer"),
                                ],
                              )),
                        ),
                        //green indicator if the printer is connected
                      ],
                    ),
                    visible: printReceipt),
              ],
            ),
          ),
        ));
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
      printer.printCustom("Percobaan printer", 3, 1);
      printer.printNewLine();
      printer.printQRcode('Test printer', 200, 200, 1);
      printer.printNewLine();
      printer.printNewLine();
      printer.paperCut();

      // printer.printer.printCustom(invoice_update.santriPembayar!.name!, 2, 1);
    }
  }

  Future<void> getPrinters() async {
    devices = await printer.getBondedDevices();
    setState(() {});
  }
}
