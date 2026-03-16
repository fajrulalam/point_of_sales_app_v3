class PesananObject {
  final String namaPesanan;
  final int harga;
  int dineInQuantity;
  int takeAwayQuantity;

  PesananObject({
    required this.namaPesanan,
    required this.harga,
    this.dineInQuantity = 0,
    this.takeAwayQuantity = 0,
  });

  // Helper getters:
  int get totalQuantity => dineInQuantity + takeAwayQuantity;
  int get subtotal => totalQuantity * harga;
}
