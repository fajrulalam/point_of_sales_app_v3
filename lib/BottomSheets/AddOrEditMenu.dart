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
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';

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
  final categoryController = TextEditingController();
  final descriptionController = TextEditingController();
  final unitsPerPackageController = TextEditingController(text: '1');
  List<AssetsObject> listGambar = [];
  int selectedImageIndex = -1;
  XFile? selectedLocalFile;
  bool isUploading = false;
  bool isFeatured = false;
  List<MenuIngredient> selectedIngredients = [];
  final ImagePicker _picker = ImagePicker();
  final _inventoryService = InventoryService();
  static final _currencyFormat = NumberFormat("#,###", "id_ID");

  static final _titleStyle = GoogleFonts.poppins(
      fontSize: 28, fontWeight: FontWeight.w800, color: Colors.black87);
  static final _labelStyle = GoogleFonts.poppins(fontSize: 14);
  static final _buttonTextStyle = GoogleFonts.poppins(
      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16);
  static const _edgeInsets16 = EdgeInsets.all(16.0);
  static const _edgeInsetsHorizontal24Vertical12 = 
      EdgeInsets.symmetric(horizontal: 24, vertical: 12);

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
      categoryController.text = widget.menuObject!.category;
      descriptionController.text = widget.menuObject!.description;
      unitsPerPackageController.text = widget.menuObject!.unitsPerPackage.toString();
      isFeatured = widget.menuObject!.isFeatured;
      selectedImageIndex = listGambar.indexWhere(
          (element) => element.path == widget.menuObject!.imagePath);
      selectedIngredients = List.from(widget.menuObject!.ingredients);
    } else {
      categoryController.text = 'Umum';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          margin: EdgeInsets.zero,
          height: constraints.maxHeight,
          width: constraints.maxWidth,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      Text(
                        widget.query == 'add'
                            ? 'Tambah Menu Baru'
                            : 'Edit ${widget.menuObject?.namaMenu}',
                        style: _titleStyle,
                      ),
                      const Spacer(),
                      _buildSaveButton(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildFormFields(),
                  const SizedBox(height: 16),
                  _buildImageGrid(),
                  const SizedBox(height: 80), // Added padding for better scrolling
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: isUploading ? null : _handleSave,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isUploading ? Colors.grey : const Color(0xFF81C784),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isUploading ? null : [
            BoxShadow(
              color: const Color(0xFF81C784).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            if (isUploading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            else
              const Icon(Icons.check_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              isUploading ? 'Menyimpan...' : 'Simpan',
              style: _buttonTextStyle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormFields() {
    return Column(
      children: [
        Row(
          children: [
            _buildTextField(namaMakananController, 'Nama ${widget.makananOrMinuman}'),
            const SizedBox(width: 16),
            _buildPriceField(),
            const SizedBox(width: 16),
            _buildTextField(categoryController, 'Kategori'),
            const SizedBox(width: 16),
            _buildTextField(unitsPerPackageController, 'Stok per Paket', isNumber: true),
            const SizedBox(width: 16),
            _buildIngredientButton(),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Deskripsi / Bahan-bahan',
                  hintText: 'Contoh: Nasi putih, ayam goreng, sambal, lalapan...',
                ),
              ),
            ),
            const SizedBox(width: 16),
            _buildFeaturedToggle(),
          ],
        ),
      ],
    );
  }

  Widget _buildFeaturedToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isFeatured ? Colors.amber.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFeatured ? Colors.amber.shade400 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFeatured ? Icons.star : Icons.star_border,
            color: isFeatured ? Colors.amber.shade600 : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            'Populer',
            style: GoogleFonts.poppins(
              fontWeight: isFeatured ? FontWeight.w600 : FontWeight.normal,
              color: isFeatured ? Colors.amber.shade800 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: isFeatured,
            onChanged: (value) => setState(() => isFeatured = value),
            activeColor: Colors.amber.shade600,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {bool isNumber = false}) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
        ),
      ),
    );
  }

  Widget _buildPriceField() {
    return Expanded(
      child: TextField(
        controller: hargaMakananController,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          TextInputFormatter.withFunction((oldValue, newValue) {
            if (newValue.text.isEmpty) return newValue;
            try {
              final plainNumber = newValue.text.replaceAll('.', '');
              if (plainNumber.isEmpty) return newValue;
              final double value = double.parse(plainNumber);
              final newText = _currencyFormat.format(value);
              return TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: newText.length),
              );
            } catch (e) {
              return oldValue;
            }
          }),
        ],
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: 'Harga ${widget.makananOrMinuman} (Rp.)',
        ),
      ),
    );
  }

  Widget _buildIngredientButton() {
    return ElevatedButton.icon(
      onPressed: _showIngredientsDialog,
      icon: const Icon(Icons.inventory_2, size: 18),
      label: Text('Atur Bahan (${selectedIngredients.length})', style: _labelStyle),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade100,
        foregroundColor: Colors.blue.shade800,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildImageGrid() {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GridView.builder(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            itemCount: listGambar.length + 1,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: (constraints.maxWidth / 180).floor().clamp(1, 6),
              mainAxisSpacing: 12.0,
              crossAxisSpacing: 12.0,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _LocalPickerTile(
                  selectedFile: selectedLocalFile,
                  onTap: _pickAndCropImage,
                );
              }
              final actualIndex = index - 1;
              return _CatalogImageTile(
                isSelected: actualIndex == selectedImageIndex,
                imageUrl: listGambar[actualIndex].path,
                onTap: () {
                  setState(() {
                    selectedImageIndex = actualIndex;
                    selectedLocalFile = null;
                  });
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _pickAndCropImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image != null) {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Potong Gambar',
            toolbarColor: const Color(0xFF81C784),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Potong Gambar',
            aspectRatioLockEnabled: true,
          ),
        ],
      );
      if (croppedFile != null) {
        setState(() {
          selectedLocalFile = XFile(croppedFile.path);
          selectedImageIndex = -1;
        });
      }
    }
  }

  Future<void> _handleSave() async {
    if (namaMakananController.text == '' ||
        hargaMakananController.text == '' ||
        categoryController.text == '' ||
        (selectedImageIndex == -1 && selectedLocalFile == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mohon isi semua field dan pilih gambar menu')));
      return;
    }

    setState(() => isUploading = true);

    try {
      String finalImagePath = '';
      if (selectedLocalFile != null) {
        final storageRef = FirebaseStorage.instance.ref();
        final fileName = "${DateTime.now().millisecondsSinceEpoch}_${selectedLocalFile!.name}";
        final imageRef = storageRef.child("menu_images/$fileName");
        final fileBytes = await File(selectedLocalFile!.path).readAsBytes();
        await imageRef.putData(fileBytes, SettableMetadata(contentType: 'image/jpeg')).timeout(const Duration(seconds: 30));
        finalImagePath = await imageRef.getDownloadURL();
      } else {
        finalImagePath = listGambar[selectedImageIndex].path;
      }

      await FirebaseFirestore.instance
          .collection("Canteens")
          .doc('canteen375')
          .collection('MenuCollection')
          .doc(widget.query == 'edit' ? widget.menuObject!.id : namaMakananController.text)
          .set({
        'namaMenu': namaMakananController.text,
        'harga': int.parse(hargaMakananController.text.replaceAll(".", '')),
        'imagePath': finalImagePath,
        'isMakanan': widget.makananOrMinuman == 'Makanan',
        'category': categoryController.text,
        'description': descriptionController.text,
        'isFeatured': isFeatured,
        'unitsPerPackage': int.tryParse(unitsPerPackageController.text) ?? 1,
        'ingredients': selectedIngredients.map((ing) => ing.toMap()).toList(),
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan menu: $e')));
      }
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }


  Future<void> _showIngredientsDialog() async {
    final tempIngredients = List<MenuIngredient>.from(selectedIngredients);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Atur Bahan untuk ${namaMakananController.text.isEmpty ? "Menu Ini" : namaMakananController.text}',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SizedBox(
            width: 500,
            height: 400,
            child: StreamBuilder<List<InventoryItem>>(
              stream: _inventoryService.getInventoryStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allInventory = snapshot.data!;

                return Column(
                  children: [
                    // Selected ingredients list
                    if (tempIngredients.isNotEmpty) ...[
                      Text('Bahan Terpilih:', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...tempIngredients.map((ing) {
                        return Card(
                          child: ListTile(
                            title: Text(ing.inventoryItemName),
                            subtitle: Text('Jumlah per porsi: ${ing.quantityNeeded}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                                  onPressed: () {
                                    if (ing.quantityNeeded > 1) {
                                      setDialogState(() {
                                        ing.quantityNeeded--;
                                      });
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle, color: Colors.green),
                                  onPressed: () {
                                    setDialogState(() {
                                      ing.quantityNeeded++;
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    setDialogState(() {
                                      tempIngredients.remove(ing);
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                      const Divider(),
                    ],
                    // Available ingredients to add
                    Text('Tambah Bahan:', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: allInventory.length,
                        itemBuilder: (context, index) {
                          final item = allInventory[index];
                          final isAlreadySelected = tempIngredients
                              .any((ing) => ing.inventoryItemId == item.id);

                          if (isAlreadySelected) return const SizedBox.shrink();

                          return ListTile(
                            title: Text(item.name),
                            subtitle: Text('Stok: ${item.stock} ${item.unit}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle, color: Color(0xFF2E7D32)),
                              onPressed: () {
                                setDialogState(() {
                                  tempIngredients.add(MenuIngredient(
                                    inventoryItemId: item.id,
                                    inventoryItemName: item.name,
                                    quantityNeeded: 1,
                                  ));
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  selectedIngredients = tempIngredients;
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
              ),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalPickerTile extends StatelessWidget {
  final XFile? selectedFile;
  final VoidCallback onTap;

  const _LocalPickerTile({required this.selectedFile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selectedFile != null ? const Color(0xFFE8F5E9) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selectedFile != null ? const Color(0xFF2E7D32) : Colors.grey.shade300,
          width: selectedFile != null ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selectedFile == null) ...[
                const Icon(Icons.add_photo_alternate_rounded, size: 40, color: Color(0xFF2E7D32)),
                const SizedBox(height: 8),
                Text('Pilih dari Galeri',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF2E7D32))),
              ] else ...[
                SizedBox(
                  height: 110,
                  width: 110,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(selectedFile!.path),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('Terganti',
                    style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogImageTile extends StatelessWidget {
  final bool isSelected;
  final String imageUrl;
  final VoidCallback onTap;

  const _CatalogImageTile({
    required this.isSelected,
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? Colors.yellow.shade600 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 110,
                width: 110,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: 200,
                  memCacheHeight: 200,
                  fadeInDuration: Duration.zero, // Optimization: No fade-in overhead
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
