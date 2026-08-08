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
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/UserMessageService.dart';

class AddMenuBottomSheet extends StatefulWidget {
  final String query;
  final String makananOrMinuman;
  final MenuObject? menuObject;
  final List<AssetsObject> listGambar;
  final Function(AssetsObject)? onDeleteCatalogImage;
  final String? initialCategory;
  final List<String> existingCategories;
  const AddMenuBottomSheet(
      {Key? key,
      required this.query,
      this.menuObject,
      required this.makananOrMinuman,
      required this.listGambar,
      this.onDeleteCatalogImage,
      this.initialCategory,
      required this.existingCategories})
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
  bool isRecommended = false;
  String? _existingImageUrl;
  String _imageAspectRatio = '1:1';
  int _sortOrder = 0;
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
      descriptionController.text = widget.menuObject!.menuDescription;
      unitsPerPackageController.text =
          widget.menuObject!.unitsPerPackage.toString();
      isRecommended = widget.menuObject!.isRecommended;
      selectedImageIndex = listGambar.indexWhere(
          (element) => element.path == widget.menuObject!.imagePath);
      if (selectedImageIndex == -1) {
        _existingImageUrl = widget.menuObject!.imagePath;
      }
      selectedIngredients = List.from(widget.menuObject!.ingredients);
      _imageAspectRatio = widget.menuObject!.imageAspectRatio;
      _sortOrder = widget.menuObject!.sortOrder;
    } else {
      categoryController.text = widget.initialCategory ?? 'Umum';
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
                  const SizedBox(
                      height: 80), // Added padding for better scrolling
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
          boxShadow: isUploading
              ? null
              : [
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
            _buildTextField(
                namaMakananController, 'Nama ${widget.makananOrMinuman}'),
            const SizedBox(width: 16),
            _buildPriceField(),
            const SizedBox(width: 16),
            _buildCategoryDropdown(),
            const SizedBox(width: 16),
            _buildTextField(unitsPerPackageController, 'Stok per Paket',
                isNumber: true),
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
                  hintText:
                      'Contoh: Nasi putih, ayam goreng, sambal, lalapan...',
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
        color: isRecommended ? Colors.amber.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRecommended ? Colors.amber.shade400 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRecommended ? Icons.star : Icons.star_border,
            color: isRecommended ? Colors.amber.shade600 : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            'Populer',
            style: GoogleFonts.poppins(
              fontWeight: isRecommended ? FontWeight.w600 : FontWeight.normal,
              color:
                  isRecommended ? Colors.amber.shade800 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: isRecommended,
            onChanged: (value) => setState(() => isRecommended = value),
            activeColor: Colors.amber.shade600,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label,
      {bool isNumber = false}) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        inputFormatters:
            isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    // Ensure the current value is in the list
    final List<String> categories = List.from(widget.existingCategories);
    if (categoryController.text.isNotEmpty &&
        !categories.contains(categoryController.text)) {
      categories.add(categoryController.text);
    }
    if (categories.isEmpty) categories.add('Umum');

    return Expanded(
      child: DropdownButtonFormField<String>(
        value: categoryController.text.isEmpty
            ? categories.first
            : categoryController.text,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Kategori',
        ),
        items: categories.map((String category) {
          return DropdownMenuItem<String>(
            value: category,
            child: Text(category, style: _labelStyle),
          );
        }).toList(),
        onChanged: (String? newValue) {
          if (newValue != null) {
            setState(() {
              categoryController.text = newValue;
            });
          }
        },
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
      label: Text('Atur Bahan (${selectedIngredients.length})',
          style: _labelStyle),
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
              crossAxisCount: (constraints.maxWidth / 150).floor().clamp(1, 8),
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
                    _existingImageUrl = null;
                    _imageAspectRatio = '1:1';
                  });
                },
                onLongPress: () =>
                    _confirmDeleteCatalogImage(listGambar[actualIndex]),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _pickAndCropImage() async {
    // Let user pick aspect ratio before opening gallery
    final bool? useSquare = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pilih Rasio Gambar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop_square),
              title: const Text('1:1 (Kotak)'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.crop_portrait),
              title: const Text('3:4 (Potret)'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );

    if (useSquare == null) return; // user dismissed

    final bool isSquare = useSquare;
    final CropAspectRatio cropRatio = isSquare
        ? const CropAspectRatio(ratioX: 1, ratioY: 1)
        : const CropAspectRatio(ratioX: 3, ratioY: 4);
    final CropAspectRatioPreset initPreset = isSquare
        ? CropAspectRatioPreset.square
        : CropAspectRatioPreset.original;

    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: isSquare ? 1024 : 1365,
    );
    if (image != null) {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: cropRatio,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Potong Gambar',
            toolbarColor: const Color(0xFF81C784),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: initPreset,
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
          _imageAspectRatio = isSquare ? '1:1' : '3:4';
        });
      }
    }
  }

  Future<void> _handleSave() async {
    if (namaMakananController.text == '' ||
        hargaMakananController.text == '' ||
        categoryController.text == '' ||
        (selectedImageIndex == -1 &&
            selectedLocalFile == null &&
            _existingImageUrl == null)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            content: Text('Mohon isi semua field dan pilih gambar menu')));
      return;
    }

    setState(() => isUploading = true);

    try {
      String finalImagePath = '';
      if (selectedLocalFile != null) {
        final storageRef = FirebaseStorage.instance.ref();
        final fileName =
            "${DateTime.now().millisecondsSinceEpoch}_${selectedLocalFile!.name}";
        final imageRef = storageRef.child("menu_images/$fileName");
        final fileBytes = await File(selectedLocalFile!.path).readAsBytes();
        await imageRef
            .putData(fileBytes, SettableMetadata(contentType: 'image/jpeg'))
            .timeout(const Duration(seconds: 30));
        finalImagePath = await imageRef.getDownloadURL();

        // Automatically save gallery uploads to catalog
        await FirebaseFirestore.instance.collection(Col.name('assets')).add({
          'path': finalImagePath,
          'isMakanan': widget.makananOrMinuman == 'Makanan',
        });
      } else if (selectedImageIndex != -1) {
        finalImagePath = listGambar[selectedImageIndex].path;
      } else {
        finalImagePath = _existingImageUrl!;
      }

      final menuCollectionRef = FirebaseFirestore.instance
          .collection(Col.name('Canteens'))
          .doc('canteen375')
          .collection('MenuCollection');

      final newDocId = widget.query == 'add'
          ? menuCollectionRef.doc().id
          : widget.menuObject!.id;

      await menuCollectionRef.doc(newDocId).set({
        'namaMenu': namaMakananController.text,
        'harga': int.parse(hargaMakananController.text.replaceAll(".", '')),
        'imagePath': finalImagePath,
        'isMakanan': widget.makananOrMinuman == 'Makanan',
        'category': categoryController.text,
        'menuDescription': descriptionController.text,
        'isRecommended': isRecommended,
        'unitsPerPackage': int.tryParse(unitsPerPackageController.text) ?? 1,
        'ingredients': selectedIngredients.map((ing) => ing.toMap()).toList(),
        'imageAspectRatio': _imageAspectRatio,
        'sortOrder': _sortOrder,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(
                  'Gagal menyimpan menu: ${UserMessageService.fromError(e)}')));
      }
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }

  void _confirmDeleteCatalogImage(AssetsObject asset) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus dari Katalog'),
        content: const Text(
          'Yakin ingin menghapus gambar ini dari katalog? Menu yang menggunakan gambar ini akan dikembalikan ke icon default.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDeleteCatalogImage?.call(asset);
              // If the deleted image was selected, reset it
              if (selectedImageIndex != -1 &&
                  listGambar[selectedImageIndex].path == asset.path) {
                setState(() {
                  selectedImageIndex = -1;
                });
              } else if (_existingImageUrl == asset.path) {
                setState(() {
                  _existingImageUrl = null;
                });
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showIngredientsDialog() async {
    final tempIngredients = List<MenuIngredient>.from(selectedIngredients);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
              'Atur Bahan untuk ${namaMakananController.text.isEmpty ? "Menu Ini" : namaMakananController.text}',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, fontSize: 18)),
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
                allInventory.sort((a, b) =>
                    a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                return Column(
                  children: [
                    // Selected ingredients list
                    if (tempIngredients.isNotEmpty) ...[
                      Text('Bahan Terpilih:',
                          style:
                              GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...tempIngredients.map((ing) {
                        return Card(
                          child: ListTile(
                            title: Text(ing.inventoryItemName),
                            subtitle:
                                Text('Jumlah per porsi: ${ing.quantityNeeded}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle,
                                      color: Colors.red),
                                  onPressed: () {
                                    if (ing.quantityNeeded > 1) {
                                      setDialogState(() {
                                        ing.quantityNeeded--;
                                      });
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle,
                                      color: Colors.green),
                                  onPressed: () {
                                    setDialogState(() {
                                      ing.quantityNeeded++;
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
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
                    Text('Tambah Bahan:',
                        style:
                            GoogleFonts.poppins(fontWeight: FontWeight.bold)),
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
                              icon: const Icon(Icons.add_circle,
                                  color: Color(0xFF2E7D32)),
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
  final VoidCallback? onLongPress;

  const _LocalPickerTile(
      {required this.selectedFile, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selectedFile != null ? const Color(0xFFE8F5E9) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selectedFile != null
              ? const Color(0xFF2E7D32)
              : Colors.grey.shade300,
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
                const Icon(Icons.add_photo_alternate_rounded,
                    size: 40, color: Color(0xFF2E7D32)),
                const SizedBox(height: 8),
                Text('Pilih dari Galeri',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2E7D32))),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.all(8.0),
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
                    style:
                        GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
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
  final VoidCallback? onLongPress;

  const _CatalogImageTile({
    required this.isSelected,
    required this.imageUrl,
    required this.onTap,
    this.onLongPress,
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
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: 200,
                  memCacheHeight: 200,
                  fadeInDuration: Duration.zero,
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
