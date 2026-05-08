# Separation of Financial Reports from System Sales

This plan outlines the architectural overhaul to decouple Cashflow/Financial data from System Sales data. By creating dedicated `FinancialReport` collections, we ensure that `DailyTransaction` (and Monthly/Yearly) remains an immutable, accurate reflection of what the POS system processed, while all cash tracking, discrepancies, and anchors are handled strictly in the financial ledger.

## User Review Required

> [!WARNING]
> **POS App Dependency**
> This refactoring will change the database schema that the Dashboard expects for cashflow. Because the POS app is responsible for writing the "End of Day" closing data, **you must update the POS App** to start writing to `DailyFinancialReport` instead of appending actuals/discrepancies to `DailyTransaction`. 
> 
> Until the POS app is updated to match this new schema, the Dashboard's cashflow page will only show data that we explicitly migrate, and new days will not appear correctly.

## Proposed New Schema (Contract for POS)

The POS should write to `DailyFinancialReport` (and optionally `MonthlyFinancialReport` / `YearlyFinancialReport` if you want aggregates, though the dashboard can aggregate daily reports dynamically for cashflow).

**Collection: `DailyFinancialReport`**
```typescript
{
  date: string;          // "YYYY-MM-DD"
  month: string;         // "YYYY-MM" (for querying)
  
  // Snapshot of system sales at closing
  systemSalesCash: number;
  systemSalesQris: number;
  systemSalesOnline: number;
  
  // Cashier inputted actuals
  actualCash: number;
  actualQris: number;
  actualOnline: number;
  
  // POS calculated differences
  discrepancyCash: number;
  discrepancyQris: number;
  discrepancyOnline: number;
  
  // Running balances (updated by POS or Dashboard)
  closingCash: number;
  closingQris: number;
  closingOnline: number;
  
  // Confirmation state (Dashboard managed)
  isDiscrepancyConfirmed?: boolean;
  
  // Anchor state (Dashboard managed)
  anchorCash?: number;
  anchorQris?: number;
  anchorOnline?: number;
}
```

## Proposed Changes

---

### Dashboard Refactoring (`src/utils/cashflowUtils.ts`)

#### [MODIFY] `cashflowUtils.ts`
- **Rename & Update Fetchers**: Change `fetchDailyTransactionsForMonth` to `fetchDailyFinancialReportsForMonth`. It will query the `DailyFinancialReport` collection instead of `DailyTransaction`.
- **Refactor `confirmDiscrepancy`**: 
  - Will update `DailyFinancialReport` to set `isDiscrepancyConfirmed: true`.
  - **CRITICAL CHANGE**: Will entirely **REMOVE** the logic that increments/decrements `total`, `subTotal`, `totalCash`, etc., in `DailyTransaction`, `MonthlyTransaction`, and `YearlyTransaction`.
- **Refactor `rejectDiscrepancy`**: 
  - Will update the `actual*` and `discrepancy*` fields inside `DailyFinancialReport`.
  - Will remove the logic that alters `total` fields.
- **Refactor `anchorBalance` / `undoAnchor`**:
  - Will target the `DailyFinancialReport` collection.
- **Update Row Builder (`buildCashflowRows`)**:
  - Will map `systemSalesCash` (from the new report) to the "Sales" row instead of reading `totalCash - confirmedDeltaCash`.

### Dashboard Cashflow Page

#### [MODIFY] `src/app/cashflow/page.tsx`
- Update all variable names and function calls to reflect `FinancialReport` instead of `DailyTransaction` (e.g., `transactions` -> `reports`).
- Update tooltip texts that previously warned the user about "updating the total sales value", as confirming discrepancies will now strictly be a ledger acknowledgment.

### Migration Script

#### [NEW] `src/utils/migration/migrateFinancialData.ts` (or an Admin UI button)
- I will create a one-off utility function (which we can trigger via a temporary button in the Dashboard's Testing Mode, or I can run directly via script) to copy the current month's financial data from `DailyTransaction` into the new `DailyFinancialReport` collection.
- **Migration Logic**:
  - Loop through `DailyTransaction` for the current month.
  - Create a new `DailyFinancialReport` doc.
  - Copy `totalCash` -> `systemSalesCash`.
  - Copy `actualCash`, `discrepancyCash`, `closingCash`, etc.
  - Preserve `isDiscrepancyConfirmed` and `anchor` states.

## Verification Plan

### Automated/Manual Verification
1. **Migration Execution**: Run the migration script and verify that the `DailyFinancialReport` collection is populated correctly with the current month's data.
2. **Cashflow Page Load**: Navigate to `/cashflow` and ensure the table, balances, and rows render identically to how they did before, but now reading from the new collection.
3. **Discrepancy Flow**: Test confirming and overriding a discrepancy. Verify that the `DailyTransaction` document's `total` remains completely untouched, while the `DailyFinancialReport` reflects the confirmation.
4. **Anchor Flow**: Test adding and undoing an anchor balance. Verify it writes to `DailyFinancialReport`.
