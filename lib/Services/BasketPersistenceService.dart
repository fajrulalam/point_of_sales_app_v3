import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:point_of_sales_app_v3/Classes/Pesanan.dart';
import 'package:point_of_sales_app_v3/Services/TestingModeService.dart';

/// Encapsulates the entire in-progress checkout session state.
class BasketDraft {
  final List<PesananObject> items;
  final bool isTakeAway;
  final String customerName;
  final String uangYangDiterima;
  final String? selectedMemberId;
  final bool isEditMode;
  final String? editDocumentId;
  final Map<String, dynamic>? editOriginalData;
  final bool isSelfOrderMode;
  final Map<String, dynamic>? currentSelfOrder;
  final DateTime savedAt;

  BasketDraft({
    required this.items,
    this.isTakeAway = false,
    this.customerName = '',
    this.uangYangDiterima = '',
    this.selectedMemberId,
    this.isEditMode = false,
    this.editDocumentId,
    this.editOriginalData,
    this.isSelfOrderMode = false,
    this.currentSelfOrder,
    required this.savedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'items': items.map((i) => i.toMap()).toList(),
      'isTakeAway': isTakeAway,
      'customerName': customerName,
      'uangYangDiterima': uangYangDiterima,
      'selectedMemberId': selectedMemberId,
      'isEditMode': isEditMode,
      'editDocumentId': editDocumentId,
      'editOriginalData': editOriginalData,
      'isSelfOrderMode': isSelfOrderMode,
      'currentSelfOrder': currentSelfOrder,
      'savedAt': savedAt.toIso8601String(),
    };
  }

  factory BasketDraft.fromMap(Map<String, dynamic> map) {
    return BasketDraft(
      items: (map['items'] as List<dynamic>? ?? [])
          .map((i) => PesananObject.fromMap(Map<String, dynamic>.from(i as Map)))
          .toList(),
      isTakeAway: map['isTakeAway'] == true,
      customerName: map['customerName']?.toString() ?? '',
      uangYangDiterima: map['uangYangDiterima']?.toString() ?? '',
      selectedMemberId: map['selectedMemberId']?.toString(),
      isEditMode: map['isEditMode'] == true,
      editDocumentId: map['editDocumentId']?.toString(),
      editOriginalData: map['editOriginalData'] != null
          ? Map<String, dynamic>.from(map['editOriginalData'] as Map)
          : null,
      isSelfOrderMode: map['isSelfOrderMode'] == true,
      currentSelfOrder: map['currentSelfOrder'] != null
          ? Map<String, dynamic>.from(map['currentSelfOrder'] as Map)
          : null,
      savedAt: map['savedAt'] != null
          ? DateTime.tryParse(map['savedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Manages persisting and recovering in-progress basket drafts from local storage.
class BasketPersistenceService {
  static const int maxDraftAgeHours = 12;

  static String _storageKey() {
    return Col.testingMode.value ? 'testing_pos_basket_draft' : 'pos_basket_draft';
  }

  /// Persist the given basket draft to local storage.
  static Future<void> saveDraft(BasketDraft draft) async {
    try {
      if (draft.items.isEmpty && !draft.isEditMode && !draft.isSelfOrderMode) {
        await clearDraft();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(draft.toMap());
      await prefs.setString(_storageKey(), jsonString);
    } catch (e) {
      print('⚠️ [BasketPersistenceService] Failed to save basket draft: $e');
    }
  }

  /// Recover any previously stored draft. Returns null if no draft exists
  /// or if the draft has exceeded the maximum expiration duration (12 hours).
  static Future<BasketDraft?> loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey());
      if (jsonString == null || jsonString.isEmpty) {
        return null;
      }

      final Map<String, dynamic> decoded = jsonDecode(jsonString);
      final draft = BasketDraft.fromMap(decoded);

      // Verify expiration
      final ageInHours = DateTime.now().difference(draft.savedAt).inHours;
      if (ageInHours >= maxDraftAgeHours) {
        print('🕒 [BasketPersistenceService] Expired draft ($ageInHours hours old) discarded.');
        await clearDraft();
        return null;
      }

      return draft;
    } catch (e) {
      print('⚠️ [BasketPersistenceService] Failed to load basket draft: $e');
      return null;
    }
  }

  /// Clear the persisted basket draft upon order completion or deliberate cancellation.
  static Future<void> clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey());
    } catch (e) {
      print('⚠️ [BasketPersistenceService] Failed to clear draft: $e');
    }
  }
}
