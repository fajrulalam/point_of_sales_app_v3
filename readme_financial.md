# 💰 Financial System Architecture & General Ledger Blueprint

This document acts as the master blueprint for the financial engineering of the Canteen 375 ERP ecosystem. Future AI Agents and Developers reading this document must adhere strictly to the separation of concerns outlined below to prevent destructive mathematical anomalies when building out subsequent features, particularly the Manager Dashboard App.

---

## 🛑 The Core Golden Rule: Separation of Accounting Layers

Do not mistake the Cashier App for an Accountant's workstation. Financial logic in this ecosystem is strictly isolated into two mutually exclusive environments:

### 1. Shift Reconciliation (The POS Application)
Used securely by front-of-house cashiers at the end of their shift.
- Its **sole objective** is to mathematically audit the physical cash sitting inside the metal drawer against the POS software's daily recorded operations.
- **Scope of Expenditures:** strictly minor "Petty Cash" anomalies (e.g., Rp 20.000 for emergency Tisu, Rp 15.000 for emergency ice delivery).
- **Golden Logic:** The physical money input into the UI by the cashier must be matched against `Net Cash`. 
  - Formula: `(System Gross Cash - Total Cash Petty Expenses) = Expected Physical Remainder`.

### 2. General Ledger Accounting (The Pending Dashboard Application)
Designed for Managers, Stakeholders, and automated Profit & Loss (P&L) generation.
- Its **sole objective** is to calculate absolute commercial profitability for given months/years.
- **Scope of Expenditures:** Employee wages, Monthly building rent, Massive wholesale resupply invoices (e.g., buying 50 kg of raw ingredients from a farm).
- **Golden Logic:** These massive expenditures will rapidly eclipse the POS drawer's daily income. Therefore, these transactions are inherently paid identically via Business Bank Accounts or the Back-Office Master Safe. They are never deducted from the Daily Transactions pipeline!

---

## 🗄️ Firestore Database Architecture Blueprint

To support this separated architecture seamlessly across multiple frontends (POS App vs Dashboard App), the `DailyFinancialReport` ecosystem MUST be structured as follows.

### A. The Core Daily Net Ledger (`DailyFinancialReport`)

**Path:** `/DailyFinancialReport/{YYYY-MM-DD}`

This document aggregates the final performance of the POS terminal for exactly that date.

```json
{
  // 1. Gross Incoming Sales (Recorded cleanly by OrderConfirmationService)
  "grossCash": 850000,
  "grossQris": 200000,
  "grossOnline": 0,
  
  // 2. Localized Shift Expenditures (Aggregated dynamically via POS BottomSheet)
  "expensesCash": 50000, // E.g., Emergency Tisu
  "expensesQris": 0,
  "expensesOnline": 0,
  
  // 3. Mathematical Net Expectations (Calculated purely by system formulas)
  "netExpectedCash": 800000, 
  "netExpectedQris": 200000,
  "netExpectedOnline": 0,
  
  // 4. Physical Count Logs (What the cashier physically held and inputted in the UI)
  "inputCash": 800000,
  "inputQris": 200000,
  "inputOnline": 0,

  // 5. Final Audit Discrepancy (A perfectly balanced drawer evaluates all three to strictly 0)
  "discrepancyCash": 0, 
  "discrepancyQris": 0,
  "discrepancyOnline": 0, // Always 0; delta is auto-classified below

  // 6. Food Delivery Aggregator Commission (auto-calculated: grossOnline - inputOnline)
  "platformCommission": 100000, // GrabFood/GoFood/ShopeeFood combined cut
  
  "timestamp": "serverTimestamp" // Firestore intrinsic timeline lock
}
```

### B. The Expenditure Engine (Subcollection Routing)

**Path:** `/DailyFinancialReport/{YYYY-MM-DD}/Expenses/{UUID}`

**CRITICAL DEVELOPMENT NOTE FOR FUTURE AI:** Absolutely *never* store daily expenditures as an Array inside the master document!
To properly generate sweeping Monthly Dashboard charts, the expenses must exist as uncoupled, indexable sub-documents. This enables the Dashboard App to run aggressive `collectionGroup('Expenses')` functions to instantly calculate metrics like *"Total Tisu spending in Q4"*.

```json
{
  "category": "Gaji Karyawan (Employee Wages)",
  "totalAmount": 5000000,
  
  // Crucial Attribute: Allows split-payments across multiple accounts!
  // E.g., Paying 5jt using 3jt Physical Cash and 2jt QRIS transfer.
  "sources": {
    "Cash": 3000000,
    "QRIS": 2000000,
    "Online": 0
  },
  
  "timestamp": "serverTimestamp",
  // Optional Tracking Traceability
  "authorizedBy": "Manager_Fajrul",
  "recipient": "Budi" 
}
```

## 🚀 Headstart Roadmap for Future Development
When preparing to upgrade the `FinancialReportBottomSheet.dart` inside the current POS environment:

1. Scrap the current `.map` arrays execution block that evaluates generic expenditures.
2. Upgrade the UI array (`_expenses`) model to explicitly force the user to select the `sourceAccount` (Dropdown).
3. Overhaul the `_ValidationDialog` math algorithms to exclusively compare `input` vs `netExpected`. Gross computations must remain strictly invisible from the physical counting operations!
