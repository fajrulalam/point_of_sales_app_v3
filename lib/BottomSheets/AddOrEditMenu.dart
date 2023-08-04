import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Assets.dart';
import 'package:point_of_sales_app_v3/Classes/Menu.dart';

class AddMenuBottomSheet extends StatefulWidget {
  final String query;
  final String makananOrMinuman;
  final MenuObject? menuObject;
  final List<AssetsObject> listGambar;
  const AddMenuBottomSheet(
      {Key? key,
      required this.query,
      this.menuObject,
      required this.makananOrMinuman,
      required this.listGambar})
      : super(key: key);

  @override
  State<AddMenuBottomSheet> createState() => _AddMenuBottomSheetState();
}

class _AddMenuBottomSheetState extends State<AddMenuBottomSheet> {
  final namaMakananController = TextEditingController();
  final hargaMakananController = TextEditingController();
  List<AssetsObject> listGambar = [];
  int selectedImageIndex = -1;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    if (widget.makananOrMinuman == 'Makanan') {
      listGambar = widget.listGambar
          .where((element) => element.isMakanan == true)
          .toList();
    } else {
      listGambar = widget.listGambar
          .where((element) => element.isMakanan == false)
          .toList();
    }

    if (widget.query == 'edit') {
      namaMakananController.text = widget.menuObject!.namaMenu;
      hargaMakananController.text = widget.menuObject!.harga.toString();
      selectedImageIndex = listGambar.indexWhere(
          (element) => element.path == widget.menuObject!.imagePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(),
      height: MediaQuery.of(context).size.height * 0.85,
      width:
          MediaQuery.of(context).size.width * 0.8, // Set the desired width here
      child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(children: [
            Row(
              children: [
                Spacer(),
                Text(
                  widget.query == 'add'
                      ? 'Tambah Menu'
                      : 'Edit ${widget.menuObject?.namaMenu}',
                  style: GoogleFonts.montserrat(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Spacer(),
                Container(
                  width: 70,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey),
                    color: Colors.blueAccent,
                  ),
                  child: InkWell(
                    onTap: () {
                      if (namaMakananController.text == '' ||
                          hargaMakananController.text == '' ||
                          selectedImageIndex == -1) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Mohon isi semua field dan pilih gambar menu')));
                        return;
                      }
                      FirebaseFirestore.instance
                          .collection("Canteens")
                          .doc('canteen375')
                          .collection('MenuCollection')
                          .doc(widget.query == 'edit'
                              ? widget.menuObject!.id
                              : namaMakananController.text)
                          .set({
                        'namaMenu': namaMakananController.text,
                        'harga': int.parse(
                            hargaMakananController.text.replaceAll(".", '')),
                        'imagePath': listGambar[selectedImageIndex].path,
                        'isMakanan':
                            widget.makananOrMinuman == 'Makanan' ? true : false,
                      }).then((value) {
                        Navigator.pop(context);
                      });
                    },
                    child: Center(
                        child: Icon(
                      Icons.save,
                      size: 20,
                      color: Colors.white,
                    )),
                  ),
                )
              ],
            ),
            SizedBox(
              height: 16,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: namaMakananController,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Nama ${widget.makananOrMinuman}'),
                  ),
                ),
                SizedBox(
                  width: 16,
                ),
                Expanded(
                  child: TextField(
                    controller: hargaMakananController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        final plainNumber = newValue.text.replaceAll('.', '');
                        final format = NumberFormat("#,###", "id_ID");
                        final newText = format.format(int.parse(plainNumber));
                        return TextEditingValue(
                          text: newText,
                          selection:
                              TextSelection.collapsed(offset: newText.length),
                        );
                      }),
                    ],
                    decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Harga ${widget.makananOrMinuman} (Rp.)'),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 16,
            ),
            Container(
              height: 300,
              child: GridView.builder(
                itemCount: listGambar.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.of(context).size.width ~/ 180,
                  mainAxisSpacing: 12.0,
                  crossAxisSpacing: 12.0,
                  childAspectRatio: 180 / 180,
                ),
                itemBuilder: (BuildContext context, int index) {
                  if (listGambar.isEmpty) {
                    return Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: index == selectedImageIndex
                          ? Colors.yellow.shade600
                          : Colors.white,
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
                          setState(() {
                            selectedImageIndex = index;
                          });
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              height: 110,
                              width: 110,
                              child: Image(
                                image: CachedNetworkImageProvider(
                                    listGambar[index].path),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          ])),
    );
  }
}
