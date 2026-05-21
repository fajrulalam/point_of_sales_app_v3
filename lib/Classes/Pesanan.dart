class SelectedOption {
  final String groupId;
  final String optionId;
  final String groupName;
  final String optionName;
  final int priceAdjustment;

  SelectedOption({
    this.groupId = '',
    this.optionId = '',
    required this.groupName,
    required this.optionName,
    this.priceAdjustment = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'optionId': optionId,
      'groupName': groupName,
      'optionName': optionName,
      'priceAdjustment': priceAdjustment,
    };
  }

  factory SelectedOption.fromMap(Map<String, dynamic> map) {
    return SelectedOption(
      groupId: map['groupId'] ?? '',
      optionId: map['optionId'] ?? '',
      groupName: map['groupName'] ?? '',
      optionName: map['optionName'] ?? '',
      priceAdjustment: map['priceAdjustment'] ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectedOption &&
          groupId == other.groupId &&
          optionId == other.optionId &&
          groupName == other.groupName &&
          optionName == other.optionName &&
          priceAdjustment == other.priceAdjustment;

  @override
  int get hashCode =>
      groupId.hashCode ^
      optionId.hashCode ^
      groupName.hashCode ^
      optionName.hashCode ^
      priceAdjustment.hashCode;
}

class PesananObject {
  final String menuItemId;
  final String namaPesanan;
  final int harga;
  int dineInQuantity;
  int takeAwayQuantity;
  List<SelectedOption> selectedOptions;
  String? customerNote;

  PesananObject({
    this.menuItemId = '',
    required this.namaPesanan,
    required this.harga,
    this.dineInQuantity = 0,
    this.takeAwayQuantity = 0,
    this.selectedOptions = const [],
    this.customerNote,
  });

  int get totalQuantity => dineInQuantity + takeAwayQuantity;
  int get optionsTotal =>
      selectedOptions.fold(0, (sum, o) => sum + o.priceAdjustment);
  int get effectivePrice => harga + optionsTotal;
  int get subtotal => totalQuantity * effectivePrice;

  /// Unique key combining item name + sorted selected options for deduplication.
  /// Two PesananObjects with the same name but different options are distinct.
  String get orderKey {
    final base = menuItemId.isNotEmpty ? menuItemId : namaPesanan;
    if (selectedOptions.isEmpty) return base;
    final optionKeys = selectedOptions
        .map((o) => '${o.groupName}:${o.optionName}')
        .toList()
      ..sort();
    return '$base|${optionKeys.join(',')}';
  }
}
