# 💰 Financial System Architecture & General Ledger Blueprint

This document acts as the master blueprint for the financial engineering of the Canteen 375 ERP ecosystem. Future AI Agents and Developers reading this document must adhere strictly to the separation of concerns outlined below to prevent destructive mathematical anomalies.

---

## 🛑 The Core Golden Rule: Separation of Accounting Layers

Financial logic in this ecosystem is strictly isolated into two environments:

### 1. Shift Reconciliation (POS Application)
Used by cashiers at the end of their shift to audit the physical drawer.
- **Objective:** Match physical cash/QRIS against recorded operations.
- **Formulas:** 
  - `Net Expected Cash = (Total Cash Sales - Total Cash Expenses)`
  - `Net Expected QRIS = (Total QRIS Sales - Total QRIS Expenses)`
- **Discrepancy Resolution:** Any delta between `Net Expected` and `Actual Input` is recorded as a discrepancy for audit.

### 2. General Ledger Accounting (Dashboard & Analytics)
Designed for Managers and Stakeholders for P&L generation.
- **Scale:** Handles large expenditures (wages, rent, bulk supplies).
- **Separation:** POS "Petty Cash" expenses are tracked daily, while large back-office expenses are decoupled from the daily drawer reconciliation.

---

## 🧪 Testing Mode & Prefixing (CRITICAL)

To ensure safety during development and testing, the application implements a **Global Prefixing System**.

- **Detection:** The `Col.name('CollectionName')` helper is used throughout the codebase.
- **Behavior:** When **Testing Mode** is enabled (persisted in SharedPreferences), every root collection name is prefixed with `zTesting_`.
- **Scope:** This includes `DailyTransaction`, `Status`, `Members`, `Expenses`, `vouchers`, etc.
- **Safety:** AI Agents MUST use `Col.name()` for all Firestore collection references to avoid polluting production data.

---

## 🗄️ Firestore Database Architecture

### A. The Daily Ledger (`DailyTransaction`)

**Path:** `/DailyTransaction/{YYYY-MM-DD}` (Prefixed as `zTesting_DailyTransaction` in testing mode)

This document acts as both the live aggregator for shift sales and the final audit report.

```json
{
  // --- Live Accumulators (Incremented by OrderConfirmationService) ---
  "total": 1050000,
  "totalCash": 850000,
  "totalQris": 200000,
  "totalOnline": 0,
  "subTotal": 1030000, // Food/Drink only
  "takeAwayFee": 20000, // Recalculated at settlement for Open Bills
  
  // --- Final Audit Fields (Added by FinancialReportBottomSheet) ---
  "grossCash": 850000,
  "grossQris": 200000,
  "grossOnline": 0,
  "expensesCash": 50000,
  "actualCash": 800000, // User input
  "discrepancyCash": 0,
  "platformCommission": 0, // Delta for Online orders
  
  "timestamp": "serverTimestamp"
}
```

### B. Transaction Fields & Methods

Individual orders in the `Status` collection use two primary fields to track flow:

1. **`transactionMethod`**:
   - `Normal`: Regular immediate checkout.
   - `Open Bill`: Order is kept open (unpaid) until later settlement.
   - `Self Order`: Orders originating from the self-service web/app.
2. **`paymentMethod`**:
   - Initial state for Open Bills: `null`.
   - Final state upon checkout: `Cash`, `QRIS`, or `Online`.

---

## 🧾 Open Bill Settlement Flow

1. **Creation**: Status doc is created with `transactionMethod: 'Open Bill'`, `isClosed: false`, and `paymentMethod: null`. No `DailyTransaction` write occurs yet.
2. **Settlement**: 
   - `DailyTransaction` accumulators (`totalCash`, `totalQris`, etc.) are incremented.
   - Status doc is updated: `isClosed: true`, `paymentMethod: 'Cash|QRIS|Online'`, and `settledAt` timestamp is set.
   - Inventory and member points are processed in the same atomic batch.

---

## 🚀 Future Roadmap & Constraints

1. **Expenditure Subcollections**: Currently using a flat `Expenses` collection. Scaling may require subcollections within `DailyTransaction` for massive volume.
2. **Commission Logic**: The `platformCommission` logic is currently calculated as `grossOnline - actualOnline`. This should be reviewed if third-party aggregator APIs are integrated.
3. **Closing Balances**: The system maintains `closingCash/Qris/Online` for running saldo across dates to detect cumulative leakages.
