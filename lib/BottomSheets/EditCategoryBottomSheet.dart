import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';

class EditCategoryBottomSheet extends StatefulWidget {
  final String categoryName;

  const EditCategoryBottomSheet({Key? key, required this.categoryName}) : super(key: key);

  @override
  State<EditCategoryBottomSheet> createState() => _EditCategoryBottomSheetState();
}

class _EditCategoryBottomSheetState extends State<EditCategoryBottomSheet> {
  final categoryNameController = TextEditingController();
  XFile? selectedLocalFile;
  bool isUploading = false;
  bool _imageDeleted = false;
  final ImagePicker _picker = ImagePicker();
  String? currentImagePath;

  @override
  void initState() {
    super.initState();
    categoryNameController.text = widget.categoryName;
    _fetchCategoryImage();
  }

  Future<void> _fetchCategoryImage() async {
    try {
      final doc = await FirebaseFirestore.instance.collection(Col.name('Categories')).doc(widget.categoryName).get();
      if (doc.exists && doc.data()!.containsKey('imagePath')) {
        setState(() {
          currentImagePath = doc['imagePath'];
        });
      }
    } catch (e) {
      print("Error fetching category image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              Text(
                'Edit Kategori',
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (isUploading)
                const CircularProgressIndicator()
              else
                IconButton(
                  onPressed: _saveCategory,
                  icon: const Icon(Icons.check, color: Color(0xFF2E7D32)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: categoryNameController,
            decoration: const InputDecoration(
              labelText: 'Nama Kategori',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 150,
              width: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(12),
              ),
              child: selectedLocalFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(selectedLocalFile!.path), fit: BoxFit.cover),
                    )
                  : (!_imageDeleted && currentImagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(currentImagePath!, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.add_a_photo, size: 50, color: Colors.grey)),
            ),
          ),
          if ((selectedLocalFile != null) || (!_imageDeleted && currentImagePath != null))
            TextButton.icon(
              onPressed: _deleteImage,
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              label: const Text('Hapus Foto', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  void _deleteImage() {
    setState(() {
      selectedLocalFile = null;
      _imageDeleted = true;
    });
  }

  Future<void> _pickImage() async {
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
        });
      }
    }
  }

  Future<void> _saveCategory() async {
    if (categoryNameController.text.isEmpty) return;

    setState(() {
      isUploading = true;
    });

    try {
      final newName = categoryNameController.text;
      String? imageUrl = _imageDeleted ? null : currentImagePath;

      // 1. Upload new image if selected
      if (selectedLocalFile != null) {
         // Read file as bytes to avoid path/permission issues during upload
         final fileBytes = await File(selectedLocalFile!.path).readAsBytes();
         
         final storageRef = FirebaseStorage.instance.ref();
         final fileName = "category_${DateTime.now().millisecondsSinceEpoch}.jpg";
         final imageRef = storageRef.child("category_images/$fileName");
         
         await imageRef.putData(
           fileBytes, 
           SettableMetadata(contentType: 'image/jpeg')
         ).timeout(const Duration(seconds: 30));
         
         imageUrl = await imageRef.getDownloadURL();
      }

      final firestore = FirebaseFirestore.instance;
      final oldDocRef = firestore.collection(Col.name('Categories')).doc(widget.categoryName);
      final newDocRef = firestore.collection(Col.name('Categories')).doc(newName);

      // 2. Update Image Path in Categories Collection for the OLD name first (in case name didn't change)
      // Actually, if name changed, we make a new doc. If name logic is confusing, handle separate cases.
      
      if (widget.categoryName != newName) {
        // Name Changed:
        // A. Create new category doc
        await newDocRef.set({
          if (imageUrl != null) 'imagePath': imageUrl,
          'name': newName,
        });

        // B. Update ALL menu items
        final menuQuery = await firestore.collection(Col.name('Canteens')).doc('canteen375').collection('MenuCollection')
            .where('category', isEqualTo: widget.categoryName).get();

        final batch = firestore.batch();
        for (var doc in menuQuery.docs) {
          batch.update(doc.reference, {'category': newName});
        }
        await batch.commit();

        // C. Delete old category doc
        await oldDocRef.delete();

      } else {
        // Name NOT Changed — update or remove image
        if (imageUrl != null) {
          await oldDocRef.set({
            'imagePath': imageUrl,
            'name': newName,
          }, SetOptions(merge: true));
        } else {
          // Image was deleted: remove the imagePath field
          await oldDocRef.update({
            'imagePath': FieldValue.delete(),
          });
        }
      }

      if (mounted) Navigator.pop(context);

    } catch (e) {
      print("Error saving category: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }
}
