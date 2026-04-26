# Payment Method Split Feature

## Problem
Currently, a transaction only supports a single payment method (`Cash`, `QRIS`, or `Online`). When a customer pays using two methods (e.g., part Cash + part QRIS), the cashier is forced to pick one, causing `DailyTransaction` accumulators (`totalCash`, `totalQris`, `totalOnline`) to be inaccurate. The owner must then manually overwrite the data from the backend.

## Proposed Solution
Add a **"Split Payment"** toggle that allows the cashier to enter amounts for two separate payment methods. The total of both parts must equal the transaction total.

---

## Proposed Changes

### 1. UI — All Three Confirmation Dialogs

Three dialog widgets need the same split-payment UI upgrade:

#### [MODIFY] [OrderConfirmationService.dart](file:///d:/Projects/point_of_sales_app_v3/lib/Services/OrderConfirmationService.dart)

**State additions** (in `_OrderConfirmationDialogState`, `_SelfOrderConfirmationDialogState`, `_OpenBillSettlementDialogState`):
```dart
bool _isSplitPayment = false;
int _splitQrisAmount = 0;        // QRIS portion entered by cashier
// Cash portion is auto-calculated: displayTotal - _splitQrisAmount
TextEditingController _splitQrisController = TextEditingController();
```

**UI changes for payment method section** (all 3 dialogs):
- The payment method chips become: `Cash`, `QRIS`, `Online`, **`Cash + QRIS`** (the split option).
- When `Cash + QRIS` is selected:
  - The split is **always Cash + QRIS** — no further method selection needed.
  - Show an input field labeled "Jumlah QRIS (Rp)" for the QRIS portion.
  - Auto-display the remaining Cash amount: `Cash = displayTotal - splitQrisAmount`.
  - **Do NOT auto-fill** the `uangYangDiterima` field (unlike selecting single QRIS, which does auto-fill).
  - Show the `Uang yang diterima` field for the cashier to enter the physical cash received.
- When `Cash`, `QRIS`, or `Online` is selected: existing single-payment behavior (QRIS/Online auto-fills `uangYangDiterima`, Cash does not).
- When nothing is selected: no payment fields shown (unchanged).

**Validation on confirm:**
- `_splitQrisAmount` must be > 0 and < `displayTotal`.
- Cash portion = `displayTotal - _splitQrisAmount` (auto-calculated, must be > 0).
- `uangYangDiterima` >= `displayTotal` (unchanged).

**Dialog return data — new fields:**
```dart
// Single payment (unchanged)
'paymentMethod': _selectedPaymentMethod,   // e.g. 'Cash'

// Split payment (new — always Cash+QRIS)
'isSplitPayment': true,
'paymentMethod': 'Cash/QRIS',
'splitCashAmount': 15000,
'splitQrisAmount': 10000,
```

---

### 2. Backend — Financial Writes (4 Processing Methods)

Four methods write to `DailyTransaction` / `MonthlyTransaction` / `YearlyTransaction`:

1. `_processOrder` (line ~806)
2. `_processSelfOrder` (line ~384)
3. `_processOpenBillSettlement` (line ~1740)
4. `OpenBillService.settleBill` (writes the `paymentMethod` on the Status doc)

**Current pattern (single payment):**
```dart
if (transactionMethod == 'Cash') {
  map['totalCash'] = FieldValue.increment(totalHarga);
} else if (transactionMethod == 'QRIS') {
  map['totalQris'] = FieldValue.increment(totalHarga);
} else if (transactionMethod == 'Online') {
  map['totalOnline'] = FieldValue.increment(totalHarga);
}
```

**New pattern (split-aware):**
```dart
if (isSplitPayment) {
  // Increment each accumulator with its respective split amount
  _incrementPaymentAccumulator(map, 'Cash', splitCashAmount);
  _incrementPaymentAccumulator(map, 'QRIS', splitQrisAmount);
} else {
  _incrementPaymentAccumulator(map, transactionMethod!, totalHarga);
}
```

Where `_incrementPaymentAccumulator` is a small helper:
```dart
static void _incrementPaymentAccumulator(Map<String, dynamic> map, String method, int amount) {
  if (method == 'Cash') {
    map['totalCash'] = FieldValue.increment(amount);
  } else if (method == 'QRIS') {
    map['totalQris'] = FieldValue.increment(amount);
  } else if (method == 'Online') {
    map['totalOnline'] = FieldValue.increment(amount);
  }
}
```

**Status doc `paymentMethod` field:** For split payments, store as `"Cash/QRIS"` (slash-separated) so the transaction history can display it. Also add two new fields:
```dart
mapStatus['paymentMethod'] = 'Cash/QRIS';
mapStatus['isSplitPayment'] = true;
mapStatus['splitDetails'] = {
  'cashAmount': 15000,
  'qrisAmount': 10000,
};
```

---

### 3. OpenBillService — settleBill

#### [MODIFY] [OpenBillService.dart](file:///d:/Projects/point_of_sales_app_v3/lib/Services/OpenBillService.dart)

Add optional split payment parameters to `settleBill()`:
```dart
Future<void> settleBill({
  // ... existing params ...
  bool isSplitPayment = false,        // NEW
  Map<String, dynamic>? splitDetails,  // NEW
}) async {
  batch.update(statusRef, {
    // ... existing fields ...
    'paymentMethod': paymentMethod,
    if (isSplitPayment) 'isSplitPayment': true,
    if (splitDetails != null) 'splitDetails': splitDetails,
  });
}
```

---

### 4. Parameter Threading

All intermediate method signatures need new optional parameters threaded through:

| Method | New Parameters |
|--------|---------------|
| `showOrderConfirmationDialog` → `_processOrder` | `isSplitPayment`, `splitCashAmount`, `splitQrisAmount` |
| `showSelfOrderConfirmationDialog` → `_processSelfOrder` | Same |
| `showOpenBillSettlementDialog` → `_processOpenBillSettlement` → `OpenBillService.settleBill` | Same |

---

## User Review Required

> [!IMPORTANT]
> **Firestore schema addition**: The `Status` docs will gain two new optional fields: `isSplitPayment` (bool) and `splitDetails` (map). These are additive and backward-compatible — existing docs without these fields are treated as single-payment transactions.

> [!IMPORTANT]
> **No new Firestore collections or indexes required.** The `DailyTransaction` accumulators (`totalCash`, `totalQris`, `totalOnline`) continue to work as-is — we simply increment two of them instead of one.

> [!NOTE]
> The `FinancialReportBottomSheet` reads `totalCash`, `totalQris`, `totalOnline` from `DailyTransaction`. Since the increments are correct per-method, **no changes** are needed there.

---

## Design Decisions

> [!NOTE]
> **Split is always Cash + QRIS.** Per user feedback, the only real-world split scenario is Cash + QRIS. No method selection UI needed — just a single "Cash + QRIS" chip option. This keeps it fast for cashiers.

---

## Verification Plan

### Automated Tests
- `flutter analyze` — ensure no compile errors.

### Manual Verification
- Launch the app and verify the 3 dialog flows:
  1. Normal order → single payment → financial writes correct.
  2. Normal order → split payment → both accumulators increment by correct amounts.
  3. Self-order confirmation → split payment → same.
  4. Open Bill settlement → split payment → same.
- Check `DailyTransaction` document in Firestore (testing mode) after a split-payment transaction and confirm `totalCash` and `totalQris` reflect the split amounts.
