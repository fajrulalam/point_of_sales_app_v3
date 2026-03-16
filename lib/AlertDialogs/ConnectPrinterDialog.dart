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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Connect to printer',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (printerIsConnected) {
                      Navigator.pop(context, selectedDevice);
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Simpan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Visibility(
              visible: printReceipt,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<BluetoothDevice>(
                              hint: const Text('Pilih printer'),
                              value: selectedDevice,
                              isExpanded: true,
                              items: devices
                                  .map((e) => DropdownMenuItem(
                                      child: Text(e.name ?? 'Unknown Device'),
                                      value: e))
                                  .toList(),
                              onChanged: (device) {
                                setState(() {
                                  selectedDevice = device;
                                  printer.connect(selectedDevice!);
                                  checkIfPrinterIsConnected();
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          height: 12,
                          width: 12,
                          decoration: BoxDecoration(
                            color: printerIsConnected ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (printerIsConnected ? Colors.green : Colors.grey)
                                    .withOpacity(0.3),
                                spreadRadius: 2,
                                blurRadius: 5,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () => testPrinter('test'),
                      icon: const Icon(Icons.print),
                      label: const Text("Coba Printer"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      await Future.delayed(const Duration(milliseconds: 500));

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
