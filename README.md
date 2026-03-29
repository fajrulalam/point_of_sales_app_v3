# 🏪 Canteen 375: Point of Sales (POS) & ERP System

Welcome to the comprehensive documentation for the **Canteen 375 POS Architecture**. This application goes far beyond a standard cash register—it acts as a localized Enterprise Resource Planning (ERP) engine, seamlessly integrating live stock reduction, open billing (tabs), automated supplier restocking algorithms, and offline-capable customer loyalty programs.

---

## 🧠 Core Engine: `OrderConfirmationService.dart`

At the absolute center of the application is the `OrderConfirmationService`. This is the single source of truth for finalizing payments, securing atomic WriteBatches to Firebase, and distributing updates across the entire app ecosystem.

### How it Works (The Checkout Flow)
1. **Data Aggregation:** The service receives the final shopping cart (`List<PesananObject>`), loops through the raw items, and identifies their root `MenuObject` blueprints.
2. **Dynamic Menu Modifiers:** It cross-references the cart with the `OptionGroupService` to see if the user selected complex modifiers (e.g., "Less Sugar," "Extra Egg"). It aggregates the price and ingredient differences dynamically.
3. **Atomic Financial Logging:** It spins up a Firestore `WriteBatch`. It safely queues incremental updates (`FieldValue.increment()`) for three crucial records simultaneously:
   - `DailyTransaction`
   - `MonthlyTransaction`
   - `YearlyTransaction`
4. **Kitchen Routing:** It pushes the finalized document into the `/Canteens/{canteenId}/Status` collection, immediately notifying securely mounted kitchen TV displays that an order is "Serving" or "Done".
5. **Voucher Validation & Integration:** Analyzes whether the inputted code is a POS campaign voucher or an `e-santren` (external) voucher. It claims the voucher atomically rigidly within the same `WriteBatch` to completely avoid zero-day network drop exploits.
6. **Execution:** It runs `await batch.commit()`. Due to atomic properties, if any sub-system fails (e.g., stock is somehow locked), the *entire* cart fails, guaranteeing mathematically perfect accounting data with zero phantom transactions.
7. **Hardware Handoff:** Finally, it loops the finalized aggregate text to the physical Sunmi thermal printer via localized Bluetooth/Internal endpoints.

---

## 🔗 The 10 Major System Linkages

The app functions through highly uncoupled micro-services that all report back to or are commanded by the `OrderConfirmationService`.

### 1. Inventory & Restocking Engine (`InventoryService` & `ShoppingService`)
* **Linkage:** When `OrderConfirmationService` is about to commit a batch, it hands the raw cart data to `InventoryService.batchDeductAggregatedIngredients`. 
* **Mechanics:** The Inventory service maps the raw items and unique `inventoryItemId`s, doing the math to deduct `-40 grams` of sugar and `-1` unit of egg gracefully. Conversely, the `ShoppingService` allows managers to purchase new supplier stock and intelligently add those units back to the same `inventoryItemId`.

### 2. Pay-Later Ecosystem (`OpenBillService` & `LiveTabsScreen`)
* **Linkage:** Instead of immediately paying, `OrderConfirmationService` can route the cart payload directly to `OpenBillService.chargeToTab()`.
* **Mechanics:** Bypasses instant cash generation and instead logs the transaction under a verified Customer Member ID, bounded dynamically by an adjustable `Credit Limit` pulled from the system Settings.

### 3. CRM, Points, & Vouchers (`MemberService`)
* **Linkage:** Triggers instantly upon checkout completion.
* **Mechanics:** Offline-cached (`DatabaseHelper`) profiles track member transactions. `OrderConfirmationService` mathematically increments member loyalty points, updates the real-time Competition Leaderboard documents, and calculates periodic cashback campaigns.

### 4. Catalog & Options Architecture (`MenuManagementWidget`)
* **Linkage:** Provides the structural constraints for the checkout.
* **Mechanics:** Allows admins to nest infinite ingredients inside Option Groups, rigidly locking them internally by their `inventoryItemId` so that stock deduction cannot be spoofed by string typos.

### 5. Asynchronous Gateway (`SelfOrderService`)
* **Linkage:** Acts as a feeder system to the core POS.
* **Mechanics:** Pushes remote, external orders from customer phones/tablets onto the POS terminal's `LiveTabsScreen` as an "Unpaid" queue, allowing the cashier to review mathematically perfect carts before manually handing them off to `OrderConfirmationService`.

### 6. Automated Housekeeping (`EndOfDayService`)
* **Mechanics:** An isolated supervisor script. Checks daily timestamps and intelligently nullifies stock values for specific strictly "Perishable" ingredients to ensure that yesterday's unsold pastries aren't accidentally sold today.

### 7. Kitchen Status Routing (`Status`)
* **Mechanics:** Listens to checkout triggers. When the receipt prints, a listener dynamically renders the order queue for cooks to aggressively track output bottlenecks.

### 8. Authentication & Rules (Firestore SecOps)
* **Mechanics:** The backbone preventing catastrophic data wipes. Dictates that standard Cashiers can only *append* to Daily Transactions and Open Bills, while restricting root metadata (like Menu Pricing and Credit Limits) purely to Super Admins.

### 9. Hardware Link (`HomeController`)
* **Mechanics:** Monitors live states (`printerIsConnected`). Overrides error alerts when Bluetooth cuts out, actively feeding `OrderConfirmationService` the capability to cleanly bypass receipt generation entirely if requested (e.g., Open Tab increments).

### 10. Machine Learning Upselling (`RecommendationService` - *Dormant*)
* **Linkage:** A secondary AI calculation script intended to read the shopping cart proactively and parse logical pairings to increase average basket size dynamically during checkout.
