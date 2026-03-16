import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Services/ShoppingService.dart';
import 'package:intl/intl.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({Key? key}) : super(key: key);

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Belanja',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Daftar Supplier'),
            Tab(icon: Icon(Icons.list_alt), text: 'Pesanan Belanja'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          SuppliersView(),
          ShoppingOrdersView(),
        ],
      ),
    );
  }
}

class SuppliersView extends StatelessWidget {
  const SuppliersView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: () => _showAddSupplierDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Tambah Supplier'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Supplier>>(
            stream: ShoppingService.getSuppliersStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final suppliers = snapshot.data ?? [];
              if (suppliers.isEmpty) {
                return const Center(child: Text('Belum ada supplier. Silahkan tambah.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: suppliers.length,
                itemBuilder: (context, index) {
                  final supplier = suppliers[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ExpansionTile(
                      title: Text(
                        supplier.name,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${supplier.items.length} Barang'),
                      children: [
                        ...supplier.items.map((item) => ListTile(
                              dense: true,
                              title: Text(item.name),
                              subtitle: Text('Unit: ${item.unit}'),
                              trailing: item.isPerishable
                                  ? const Chip(
                                      label: Text('Perishable', style: TextStyle(fontSize: 10)),
                                      backgroundColor: Colors.orangeAccent,
                                    )
                                  : null,
                            )),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                onPressed: () => ShoppingService.deleteSupplier(supplier.id),
                                icon: const Icon(Icons.delete, color: Colors.red),
                                label: const Text('Hapus', style: TextStyle(color: Colors.red)),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _showEditSupplierDialog(context, supplier),
                                icon: const Icon(Icons.edit),
                                label: const Text('Edit'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _showCreateOrderDialog(context, supplier),
                                icon: const Icon(Icons.shopping_cart),
                                label: const Text('Buat Pesanan'),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddSupplierDialog(BuildContext context) {
    final nameController = TextEditingController();
    List<SupplierItem> items = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final itemNameController = TextEditingController();
          final itemUnitController = TextEditingController(text: 'pcs');
          bool isPerishable = false;

          return AlertDialog(
            title: Text('Tambah Supplier', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nama Supplier', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: itemNameController,
                          decoration: const InputDecoration(labelText: 'Nama Barang', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: itemUnitController,
                          decoration: const InputDecoration(labelText: 'Unit', isDense: true),
                        ),
                      ),
                      Checkbox(
                        value: isPerishable,
                        onChanged: (v) => setDialogState(() => isPerishable = v ?? false),
                      ),
                      const Text('Perish?'),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Color(0xFF2E7D32)),
                        onPressed: () {
                          if (itemNameController.text.isNotEmpty) {
                            setDialogState(() {
                              items.add(SupplierItem(
                                name: itemNameController.text,
                                unit: itemUnitController.text,
                                isPerishable: isPerishable,
                              ));
                              itemNameController.clear();
                              itemUnitController.text = 'pcs';
                              isPerishable = false;
                            });
                          }
                        },
                      )
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(items[index].name),
                          subtitle: Text('Unit: ${items[index].unit} | Perishable: ${items[index].isPerishable}\n(Tekan untuk mengedit)'),
                          isThreeLine: true,
                          onTap: () {
                            setDialogState(() {
                              itemNameController.text = items[index].name;
                              itemUnitController.text = items[index].unit;
                              isPerishable = items[index].isPerishable;
                              items.removeAt(index);
                            });
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                items.removeAt(index);
                              });
                            },
                          ),
                        );
                      },
                    ),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isNotEmpty) {
                    await ShoppingService.addSupplier(nameController.text, items);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditSupplierDialog(BuildContext context, Supplier supplier) {
    final nameController = TextEditingController(text: supplier.name);
    List<SupplierItem> items = List.from(supplier.items);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final itemNameController = TextEditingController();
          final itemUnitController = TextEditingController(text: 'pcs');
          bool isPerishable = false;

          return AlertDialog(
            title: Text('Edit Supplier', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nama Supplier', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: itemNameController,
                          decoration: const InputDecoration(labelText: 'Nama Barang', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: itemUnitController,
                          decoration: const InputDecoration(labelText: 'Unit', isDense: true),
                        ),
                      ),
                      Checkbox(
                        value: isPerishable,
                        onChanged: (v) => setDialogState(() => isPerishable = v ?? false),
                      ),
                      const Text('Perish?'),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Color(0xFF2E7D32)),
                        onPressed: () {
                          if (itemNameController.text.isNotEmpty) {
                            setDialogState(() {
                              items.add(SupplierItem(
                                name: itemNameController.text,
                                unit: itemUnitController.text,
                                isPerishable: isPerishable,
                              ));
                              itemNameController.clear();
                              itemUnitController.text = 'pcs';
                              isPerishable = false;
                            });
                          }
                        },
                      )
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(items[index].name),
                          subtitle: Text('Unit: ${items[index].unit} | Perishable: ${items[index].isPerishable}\n(Tekan untuk mengedit)'),
                          isThreeLine: true,
                          onTap: () {
                            setDialogState(() {
                              itemNameController.text = items[index].name;
                              itemUnitController.text = items[index].unit;
                              isPerishable = items[index].isPerishable;
                              items.removeAt(index);
                            });
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setDialogState(() {
                                items.removeAt(index);
                              });
                            },
                          ),
                        );
                      },
                    ),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isNotEmpty) {
                    await ShoppingService.updateSupplier(supplier.id, nameController.text, items);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateOrderDialog(BuildContext context, Supplier supplier) {
    if (supplier.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier tidak mempunyai barang.')));
      return;
    }

    final Map<int, TextEditingController> controllers = {};
    for (int i = 0; i < supplier.items.length; i++) {
      controllers[i] = TextEditingController(text: '0');
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Buat Pesanan ke ${supplier.name}', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Masukkan jumlah yang akan dipesan. Angka 0 tidak akan dimasukkan ke order.', style: GoogleFonts.poppins(fontSize: 12)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: supplier.items.length,
                  itemBuilder: (context, index) {
                    final item = supplier.items[index];
                    return ListTile(
                      title: Text(item.name),
                      subtitle: Text(item.unit),
                      trailing: SizedBox(
                        width: 100,
                        child: TextField(
                          controller: controllers[index],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              List<ShoppingOrderItem> borderItems = [];
              for (int i = 0; i < supplier.items.length; i++) {
                int qty = int.tryParse(controllers[i]?.text ?? '0') ?? 0;
                if (qty > 0) {
                  borderItems.add(ShoppingOrderItem(
                    name: supplier.items[i].name,
                    quantity: qty,
                    unit: supplier.items[i].unit,
                    isPerishable: supplier.items[i].isPerishable,
                  ));
                }
              }

              if (borderItems.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada item yang dipesan')));
                return;
              }

              await ShoppingService.createOrder(supplier.id, supplier.name, borderItems);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order berhasil dibuat')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
            child: const Text('Buat & Simpan'),
          ),
        ],
      ),
    );
  }
}

class ShoppingOrdersView extends StatefulWidget {
  const ShoppingOrdersView({Key? key}) : super(key: key);

  @override
  State<ShoppingOrdersView> createState() => _ShoppingOrdersViewState();
}

class _ShoppingOrdersViewState extends State<ShoppingOrdersView> {
  DateTime? _startDate;
  DateTime? _endDate;

  Future<void> _pickDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null 
          ? DateTimeRange(start: _startDate!, end: _endDate!) 
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                _startDate != null && _endDate != null
                    ? '${DateFormat('dd MMM yyyy').format(_startDate!)} - ${DateFormat('dd MMM yyyy').format(_endDate!)}'
                    : 'Hari Ini (${DateFormat('dd MMM yyyy').format(DateTime.now())})',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF2E7D32)),
              ),
              const SizedBox(width: 8),
              if (_startDate != null)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: _clearDateRange,
                  tooltip: 'Hapus Filter',
                ),
              ElevatedButton.icon(
                onPressed: () => _pickDateRange(context),
                icon: const Icon(Icons.date_range),
                label: const Text('Filter Tanggal'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ShoppingOrder>>(
            stream: ShoppingService.getOrdersStream(startDate: _startDate, endDate: _endDate),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              
              final orders = snapshot.data ?? [];
              if (orders.isEmpty) {
                return const Center(child: Text('Belum ada riwayat pesanan shopping.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final dateStr = DateFormat('dd MMM yyyy HH:mm').format(order.date);
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: order.status == 'completed' ? Colors.green.shade50 : Colors.white,
                    child: ExpansionTile(
                      title: Text(
                        'Order - ${order.supplierName}',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('Tanggal: $dateStr | Status: ${order.status.toUpperCase()}'),
                      children: [
                        ...order.items.map((item) => ListTile(
                              dense: true,
                              title: Text(item.name),
                              trailing: Text('${item.quantity} ${item.unit}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            )),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => ShoppingService.generateOrderPdf(order),
                                icon: const Icon(Icons.picture_as_pdf),
                                label: const Text('PDF'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                              ),
                              if (order.status != 'completed') ...[
                                ElevatedButton.icon(
                                  onPressed: () => _showCorrectionDialog(context, order),
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Correction'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => _showCompleteOrderDialog(context, order),
                                  icon: const Icon(Icons.check_circle),
                                  label: const Text('Complete Shopping'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                ),
                              ]
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCorrectionDialog(BuildContext context, ShoppingOrder order) {
    if (order.items.isEmpty) return;

    final Map<int, TextEditingController> controllers = {};
    for (int i = 0; i < order.items.length; i++) {
      controllers[i] = TextEditingController(text: order.items[i].quantity.toString());
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Koreksi Pesanan', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ubah jumlah barang yang datang. Jika tidak datang, ubah menjadi 0.', style: GoogleFonts.poppins(fontSize: 12)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: order.items.length,
                  itemBuilder: (context, index) {
                    final item = order.items[index];
                    return ListTile(
                      title: Text(item.name),
                      subtitle: Text(item.unit),
                      trailing: SizedBox(
                        width: 100,
                        child: TextField(
                          controller: controllers[index],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              List<ShoppingOrderItem> correctedItems = [];
              for (int i = 0; i < order.items.length; i++) {
                int qty = int.tryParse(controllers[i]?.text ?? '0') ?? 0;
                correctedItems.add(ShoppingOrderItem(
                  name: order.items[i].name,
                  quantity: qty,
                  unit: order.items[i].unit,
                  isPerishable: order.items[i].isPerishable,
                ));
              }

              await ShoppingService.updateOrderItems(order.id, correctedItems);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pesanan berhasil dikoreksi')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Simpan Koreksi'),
          ),
        ],
      ),
    );
  }

  void _showCompleteOrderDialog(BuildContext context, ShoppingOrder order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Selesaikan Order?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: const Text('Pastikan barang yang datang sudah sesuai. Jika belum sesuai, Anda dapat melakukan Koreksi (Correction). Setelah diselesaikan, barang akan ditambahkan ke Inventory stok sesuai dengan jumlah yang tercatat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              await ShoppingService.completeOrder(order);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Ya, Selesai'),
          ),
        ],
      ),
    );
  }
}
