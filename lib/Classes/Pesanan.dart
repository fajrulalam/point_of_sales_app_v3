class PesananObject {
  final String namaPesanan;
  final int harga;
  int dineInQuantity;
  int takeAwayQuantity;
  bool viaAssociationRules; // Track if item was added via recommendation

  PesananObject({
    required this.namaPesanan,
    required this.harga,
    this.dineInQuantity = 0,
    this.takeAwayQuantity = 0,
    this.viaAssociationRules = false,
  });

  // Helper getters:
  int get totalQuantity => dineInQuantity + takeAwayQuantity;
  int get subtotal => totalQuantity * harga;
}
