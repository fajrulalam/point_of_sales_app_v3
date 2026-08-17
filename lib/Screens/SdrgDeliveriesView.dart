import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:point_of_sales_app_v3/Classes/Inventory.dart';
import 'package:point_of_sales_app_v3/Screens/InventoryScreen.dart';
import 'package:point_of_sales_app_v3/Services/InventoryService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgAutoAcceptService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgBridgeService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgDeliveryService.dart';
import 'package:point_of_sales_app_v3/Services/SdrgProductLinkService.dart';
import 'package:point_of_sales_app_v3/Services/UserMessageService.dart';

const Color _kGreen = Color(0xFF2E7D32);

/// Formats a quantity that is stored as a `num` but is almost always whole.
String _qty(num value) {
  if ((value - value.round()).abs() < 1e-6) return value.round().toString();
  return value.toString();
}

/// Deliveries published by Sentra Distribusi Rejoso Gemilang for Canteen375.
///
/// Stock is added automatically as soon as a delivery resolves cleanly --
/// SdrgAutoAcceptService watches for these independently of this screen being
/// open. What still shows up here needing a person: a product that has never
/// been linked, a quantity that doesn't land on a whole number, or a
/// cancellation that would push stock below zero.
class SdrgDeliveriesView extends StatefulWidget {
  const SdrgDeliveriesView({Key? key}) : super(key: key);

  @override
  State<SdrgDeliveriesView> createState() => _SdrgDeliveriesViewState();
}

class _SdrgDeliveriesViewState extends State<SdrgDeliveriesView> {
  Map<String, SdrgProductLink> _links = {};
  bool _loading = true;
  String? _busyOrderId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await InventoryService().refreshInventoryCache();
    final links = await SdrgProductLinkService.fetchLinks();
    if (!mounted) return;
    setState(() {
      _links = links;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!SdrgBridgeService.isConfigured) return const _SetupNeededCard();
    if (_loading) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<Map<String, SdrgDeliveryReceipt>>(
      stream: SdrgDeliveryService.watchReceipts(),
      builder: (context, receiptSnapshot) {
        final receipts = receiptSnapshot.data ?? const {};
        return StreamBuilder<List<SdrgDelivery>>(
          stream: SdrgBridgeService.watchDeliveries(),
          builder: (context, deliverySnapshot) {
            if (deliverySnapshot.hasError) {
              return _OfflineCard(onRetry: _load);
            }
            if (!deliverySnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final deliveries = deliverySnapshot.data!;
            if (deliveries.isEmpty) return const _EmptyCard();

            // Anything SDRG has changed since we last acted on it needs
            // attention again, which is why the comparison is by revision
            // rather than by presence.
            final pending = deliveries
                .where((d) =>
                    (receipts[d.orderId]?.acceptedRevision ?? 0) < d.revision)
                .toList();
            final settled = deliveries
                .where((d) =>
                    (receipts[d.orderId]?.acceptedRevision ?? 0) >= d.revision)
                .toList();

            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  if (pending.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Tidak ada pengiriman yang perlu perhatian.',
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ...pending.map((delivery) => _DeliveryCard(
                        delivery: delivery,
                        receipt: receipts[delivery.orderId] ??
                            SdrgDeliveryReceipt.none,
                        links: _links,
                        busy: _busyOrderId == delivery.orderId,
                        onLink: _showLinkDialog,
                        onAccept: _accept,
                        onDeferReversal: _deferReversal,
                      )),
                  if (settled.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Sudah diproses',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    ...settled.map((delivery) => _SettledTile(
                          delivery: delivery,
                          receipt: receipts[delivery.orderId]!,
                        )),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  SdrgQuantityResolution _resolve(SdrgDelivery delivery) {
    final resolved =
        SdrgProductLinkService.resolveLines(delivery.lines, _links);
    return SdrgProductLinkService.quantitiesByInventoryItem(resolved);
  }

  Future<void> _accept(SdrgDelivery delivery, SdrgDeliveryReceipt receipt) async {
    setState(() => _busyOrderId = delivery.orderId);
    try {
      await _runAccept(delivery, receipt, allowNegativeStock: false);
    } on SdrgNegativeStockException catch (error) {
      final confirmed = await _confirmNegativeStock(delivery, error);
      if (confirmed == _ReversalChoice.apply) {
        await _runAccept(delivery, receipt, allowNegativeStock: true);
      } else if (confirmed == _ReversalChoice.defer) {
        await SdrgDeliveryService.deferReversal(
            delivery: delivery, receipt: receipt);
        _toast('Pembatalan dicatat tanpa mengubah stok.');
      }
    } catch (error) {
      _toast('Gagal memproses: ${UserMessageService.fromError(error)}');
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  Future<void> _runAccept(
    SdrgDelivery delivery,
    SdrgDeliveryReceipt receipt, {
    required bool allowNegativeStock,
  }) async {
    final result = await SdrgDeliveryService.acceptDelivery(
      delivery: delivery,
      resolution: _resolve(delivery),
      receipt: receipt,
      allowNegativeStock: allowNegativeStock,
    );
    if (!mounted) return;
    _toast(result.wasAlreadyApplied
        ? 'Pengiriman ini sudah diproses sebelumnya.'
        : delivery.isCancelled
            ? 'Pembatalan diterapkan, stok dikembalikan.'
            : 'Stok berhasil ditambahkan.');
  }

  Future<void> _deferReversal(
      SdrgDelivery delivery, SdrgDeliveryReceipt receipt) async {
    setState(() => _busyOrderId = delivery.orderId);
    try {
      await SdrgDeliveryService.deferReversal(
          delivery: delivery, receipt: receipt);
      _toast('Pembatalan dicatat tanpa mengubah stok.');
    } catch (error) {
      _toast('Gagal mencatat: ${UserMessageService.fromError(error)}');
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<_ReversalChoice?> _confirmNegativeStock(
      SdrgDelivery delivery, SdrgNegativeStockException error) {
    return showDialog<_ReversalChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Stok akan menjadi negatif',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              delivery.isCancelled
                  ? 'SDRG membatalkan pesanan ${delivery.orderId}. Mengembalikan stok akan membuat jumlah berikut menjadi negatif, biasanya karena bahannya sudah terpakai.'
                  : 'Perubahan ini akan membuat jumlah berikut menjadi negatif.',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...error.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${item.inventoryItemName}: ${item.stockBefore} → ${item.stockAfter} (${item.change > 0 ? '+' : ''}${item.change})',
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _ReversalChoice.defer),
            child: const Text('Catat saja, jangan ubah stok'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, _ReversalChoice.apply),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white),
            child: const Text('Tetap terapkan'),
          ),
        ],
      ),
    );
  }

  /// Links one SDRG product to an inventory item. Deliberately mirrors the
  /// supplier-item picker in ShoppingScreen so the two feel the same.
  Future<void> _showLinkDialog(SdrgDeliveryLine line) async {
    final inventoryItems =
        InventoryService().allInventoryItems.values.toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (inventoryItems.isEmpty) {
      _toast('Belum ada bahan di Inventory. Daftarkan bahannya terlebih dahulu.');
      return;
    }

    final suggestedId =
        SdrgProductLinkService.suggestInventoryItemId(line.productName);
    InventoryItem? selected = suggestedId == null
        ? null
        : inventoryItems.where((item) => item.id == suggestedId).firstOrNull;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Tautkan Barang SDRG',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SDRG: ${line.productName}',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('Satuan: ${line.baseUnit}',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pilih bahan Inventory yang sepadan. Jumlah dari SDRG akan ditambahkan apa adanya, jadi satuannya harus sama.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                Autocomplete<InventoryItem>(
                  initialValue: selected != null
                      ? TextEditingValue(text: selected!.name)
                      : const TextEditingValue(),
                  optionsBuilder: (TextEditingValue value) {
                    final q = value.text.toLowerCase().trim();
                    if (q.isEmpty) return inventoryItems;
                    return inventoryItems
                        .where((inv) => inv.name.toLowerCase().contains(q));
                  },
                  displayStringForOption: (inv) => inv.name,
                  onSelected: (inv) => setDialogState(() => selected = inv),
                  fieldViewBuilder: (ctx, controller, focusNode, onSubmit) =>
                      TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Cari bahan...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  optionsViewBuilder: (ctx, onSelected, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxHeight: 240, maxWidth: 400),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: options.length,
                          itemBuilder: (c, i) {
                            final inv = options.elementAt(i);
                            return ListTile(
                              dense: true,
                              title: Text(inv.name),
                              subtitle: Text('Unit: ${inv.unit}'),
                              onTap: () => onSelected(inv),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (selected != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      '${_qty(line.baseQty)} ${line.baseUnit} → ${selected!.name} (${selected!.unit})',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text('Bahan belum ada di Inventory?',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey.shade700)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext, false);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const InventoryScreen()),
                        );
                      },
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('Daftarkan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Batal')),
            ElevatedButton(
              onPressed: selected == null
                  ? null
                  : () async {
                      await SdrgProductLinkService.saveLink(SdrgProductLink(
                        sdrgProductId: line.productId,
                        sdrgProductName: line.productName,
                        sdrgBaseUnit: line.baseUnit,
                        inventoryItemId: selected!.id,
                        inventoryItemName: selected!.name,
                        posUnit: selected!.unit,
                      ));
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen, foregroundColor: Colors.white),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      // Nothing about saving a link touches the delivery or receipt streams,
      // so without this the auto-accept watcher wouldn't notice a
      // previously-blocked delivery is now resolvable until some unrelated
      // change happened to fire those streams again.
      await SdrgAutoAcceptService.reconcileNow();
      await _load();
    }
  }
}

enum _ReversalChoice { apply, defer }

class _DeliveryCard extends StatelessWidget {
  final SdrgDelivery delivery;
  final SdrgDeliveryReceipt receipt;
  final Map<String, SdrgProductLink> links;
  final bool busy;
  final Future<void> Function(SdrgDeliveryLine line) onLink;
  final Future<void> Function(SdrgDelivery, SdrgDeliveryReceipt) onAccept;
  final Future<void> Function(SdrgDelivery, SdrgDeliveryReceipt)
      onDeferReversal;

  const _DeliveryCard({
    required this.delivery,
    required this.receipt,
    required this.links,
    required this.busy,
    required this.onLink,
    required this.onAccept,
    required this.onDeferReversal,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = SdrgProductLinkService.resolveLines(delivery.lines, links);
    final resolution =
        SdrgProductLinkService.quantitiesByInventoryItem(resolved);
    final blocked = resolved.where((line) => line.block != null).toList();
    final isRevision = receipt.exists && !delivery.isCancelled;
    final canAccept = blocked.isEmpty && !resolution.hasFractional;

    // The one case that still needs a person: reversing stock that has
    // already been used. Everything else that reaches this card resolves and
    // applies itself the moment SdrgAutoAcceptService next looks at it.
    final deltas = SdrgDeliveryService.computeDeltas(
      delivery: delivery,
      resolution: resolution,
      receipt: receipt,
    );
    final needsDecision = canAccept &&
        SdrgDeliveryService.negativeStockShortfalls(deltas, resolution)
            .isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: delivery.isCancelled
                ? Colors.red.shade200
                : Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'SDRG · ${delivery.orderId}',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (delivery.orderCreatedAt != null)
                  Text(
                    DateFormat('dd/MM/yy').format(delivery.orderCreatedAt!),
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
            if (delivery.isCancelled)
              _Banner(
                color: Colors.red,
                icon: Icons.cancel_outlined,
                text: receipt.exists
                    ? 'SDRG membatalkan pesanan ini. Stok yang sudah ditambahkan perlu dikembalikan.'
                    : 'SDRG membatalkan pesanan ini sebelum diterima. Tidak ada stok yang perlu diubah.',
              )
            else if (isRevision)
              const _Banner(
                color: Colors.orange,
                icon: Icons.edit_outlined,
                text: 'Pesanan SDRG berubah. Hanya selisihnya yang akan diterapkan.',
              ),
            const SizedBox(height: 10),
            ...resolved.map((line) => _LineRow(line: line, onLink: onLink)),
            if (resolution.hasFractional) ...[
              const SizedBox(height: 8),
              _Banner(
                color: Colors.red,
                icon: Icons.warning_amber_rounded,
                text:
                    'Jumlah tidak bulat: ${resolution.fractional.entries.map((e) => '${resolution.names[e.key] ?? e.key} ${e.value}').join(', ')}. Stok POS hanya menerima bilangan bulat.',
              ),
            ],
            const SizedBox(height: 12),
            if (needsDecision)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        busy ? null : () => onDeferReversal(delivery, receipt),
                    child: const Text('Catat saja'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: busy ? null : () => onAccept(delivery, receipt),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.undo),
                    label: const Text('Kembalikan stok'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              )
            else if (canAccept)
              // Nothing to do here: SdrgAutoAcceptService applies this on its
              // own. "Proses sekarang" is a fallback, not a required step.
              Row(
                children: [
                  if (busy) ...[
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text('Memproses…',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ] else ...[
                    Icon(Icons.autorenew, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isRevision
                            ? 'Perubahan akan diterapkan otomatis.'
                            : 'Stok akan ditambahkan otomatis.',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ),
                    TextButton(
                      onPressed: () => onAccept(delivery, receipt),
                      child: const Text('Proses sekarang'),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  final SdrgResolvedLine line;
  final Future<void> Function(SdrgDeliveryLine line) onLink;

  const _LineRow({required this.line, required this.onLink});

  @override
  Widget build(BuildContext context) {
    final blocked = line.block != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            blocked ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: blocked ? Colors.orange.shade800 : _kGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_qty(line.line.baseQty)} ${line.line.baseUnit} · ${line.line.productName}',
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
                if (line.block == SdrgLineBlock.unmapped)
                  Text('Belum ditautkan ke bahan Inventory',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.orange.shade800))
                else if (line.block == SdrgLineBlock.unitDrift)
                  Text(
                      'Satuan SDRG berubah dari "${line.link?.sdrgBaseUnit}" menjadi "${line.line.baseUnit}". Tautkan ulang untuk memastikan.',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.orange.shade800))
                else if (line.link != null)
                  Text(
                      '→ ${line.link!.inventoryItemName}'
                      '${line.link!.source == SdrgLinkSource.sdrg ? ' · ditautkan di SDRG' : ''}',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (blocked)
            TextButton(
              onPressed: () => onLink(line.line),
              child: const Text('Tautkan…'),
            ),
        ],
      ),
    );
  }
}

class _SettledTile extends StatelessWidget {
  final SdrgDelivery delivery;
  final SdrgDeliveryReceipt receipt;

  const _SettledTile({required this.delivery, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final pendingReversal =
        receipt.state == SdrgReceiptState.reversalPending;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        pendingReversal ? Icons.report_problem_outlined : Icons.check_circle,
        size: 18,
        color: pendingReversal ? Colors.orange.shade800 : _kGreen,
      ),
      title: Text(delivery.orderId,
          style: GoogleFonts.poppins(fontSize: 13)),
      subtitle: Text(
        pendingReversal
            ? 'Dibatalkan SDRG, stok belum disesuaikan'
            : receipt.state == SdrgReceiptState.reversed
                ? 'Dibatalkan, stok sudah dikembalikan'
                : 'Diterima (revisi ${receipt.acceptedRevision})',
        style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final MaterialColor color;
  final IconData icon;
  final String text;

  const _Banner({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    GoogleFonts.poppins(fontSize: 12, color: color.shade900)),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Belum ada pengiriman dari SDRG.',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(
              'Penjualan lunas SDRG ke Canteen375 akan muncul di sini.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineCard extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _OfflineCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Tidak dapat terhubung ke SDRG.',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text(
              'Tab lain tetap dapat digunakan seperti biasa.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupNeededCard extends StatelessWidget {
  const _SetupNeededCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Sambungan SDRG belum diaktifkan.',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text(
              'Akun jembatan SDRG perlu dibuat dan diisi di SdrgBridgeService sebelum fitur ini dapat digunakan.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
