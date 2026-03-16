# Ingredient-Based Inventory System - Implementation Summary

## Overview
This document describes the implementation of an ingredient-based inventory system where menu items can require multiple inventory items (ingredients), and the availability of menu items is determined by the availability of their ingredients.

## Key Features

### 1. Many-to-Many Relationship
- **Menu Item → Inventory Items**: Each menu item can require multiple ingredients
- **Inventory Item → Menu Items**: Each ingredient can be used in multiple menu items
- Example: "Mie Rendang" requires both "Mie" and "Telur" ingredients

### 2. Real-Time Stock Validation
- ✅ **When clicking on a menu item**: Validates before adding to cart
- ✅ **When incrementing quantities**: Validates before allowing increment
- ✅ **Before checkout**: Final validation before processing order
- ✅ **During order processing**: Atomic stock deduction

### 3. User-Friendly Error Messages
- Shows exactly which ingredient is insufficient
- Shows how many portions are available
- Prevents orders that exceed available stock

## Implementation Details

### Data Model

#### `InventoryItem` (Classes/Inventory.dart)
```dart
class InventoryItem {
  String id;
  String name;
  int stock;
  String unit; // e.g., "pcs", "kg", "liter"
}
```

#### `MenuIngredient` (Classes/Inventory.dart)
```dart
class MenuIngredient {
  String inventoryItemId;      // Reference to inventory item
  String inventoryItemName;    // Cached name for display
  int quantityNeeded;          // Amount needed per portion
}
```

#### `MenuObject` (Classes/Menu.dart)
```dart
class MenuObject {
  String id;
  String namaMenu;
  int harga;
  bool isMakanan;
  String imagePath;
  String category;
  List<MenuIngredient> ingredients;  // NEW: List of required ingredients
}
```

### Services

#### `InventoryService` (Services/InventoryService.dart)

**Key Methods:**

1. **`checkMenuAvailability(MenuObject menu, int quantity)`**
   - Checks if enough ingredients are available for the requested quantity
   - Returns `MenuAvailability` with detailed information
   - Example: If "Mie Rendang" needs 1 Mie and 2 Telur per portion, checks if ordering 5 portions is possible

2. **`deductIngredients(MenuObject menu, int quantity)`**
   - Atomically deducts ingredients from stock using Firebase batch writes
   - Only called after successful order processing
   - Example: Ordering 3 "Mie Rendang" deducts 3 Mie and 6 Telur

3. **`getInventoryStream()`**
   - Provides real-time updates of inventory items
   - Used in the AddOrEditMenu dialog to show current stock

### UI Components

#### `AddOrEditMenu` (BottomSheets/AddOrEditMenu.dart)
- **Ingredient Management Dialog**: Allows selecting ingredients and setting quantities
- Shows real-time stock levels for each ingredient
- Supports adding/removing/adjusting ingredient quantities

#### `MenuGridWidget` (Widgets/MenuGridWidget.dart)
- Shows visual indicators for menu availability
- Displays "HABIS" (out of stock) overlay when ingredients are insufficient
- Shows ingredient status badge (green "OK" or red "X")

#### `OrderListWidget` (Widgets/OrderListWidget.dart)
- Increment/decrement buttons with real-time validation
- Shows appropriate error messages when stock is insufficient

### Order Flow with Validation

```
1. User clicks menu item
   ↓
2. Check stock availability (addToOrder)
   ↓
3. If available → Add to cart
   If not → Show error message
   ↓
4. User increments quantity
   ↓
5. Check stock availability (incrementDineIn/incrementTakeAway)
   ↓
6. If available → Increment
   If not → Show error message
   ↓
7. User clicks "Buy" button
   ↓
8. Final validation (OrderConfirmationService)
   ↓
9. If available → Process order & deduct stock
   If not → Show error & abort
```

### Stock Validation Points

1. **Initial Add (`addToOrder`)**
   ```dart
   Future<void> addToOrder(MenuObject menu, bool isTakeAway) async {
     // Calculate new quantity
     final availability = await inventoryService.checkMenuAvailability(menu, newQuantity);
     if (!availability.isAvailable) {
       showError(availability.message);
       return;
     }
     // Add to order...
   }
   ```

2. **Increment Quantity (`incrementDineIn`/`incrementTakeAway`)**
   ```dart
   Future<void> incrementDineIn(int index) async {
     final totalNewQuantity = newDineIn + currentTakeAway;
     final availability = await inventoryService.checkMenuAvailability(menu, totalNewQuantity);
     if (!availability.isAvailable) {
       showError(availability.message);
       return;
     }
     // Increment...
   }
   ```

3. **Final Checkout (`OrderConfirmationService._processOrder`)**
   ```dart
   for (var pesanan in pesananList) {
     final availability = await inventoryService.checkMenuAvailability(menu, quantity);
     if (!availability.isAvailable) {
       showError(availability.message);
       return; // Abort entire order
     }
   }
   // Process order and deduct stock...
   ```

## Example Scenarios

### Scenario 1: Simple Ingredient Check
- **Menu**: "Es Kopi" requires 2 "Kopi Bubuk"
- **Inventory**: 10 "Kopi Bubuk" in stock
- **Order**: Customer tries to order 6 "Es Kopi"
- **Calculation**: 6 × 2 = 12 needed, but only 10 available
- **Result**: ❌ Error shown: "Insufficient Kopi Bubuk (need 12, have 10)"

### Scenario 2: Multiple Ingredients
- **Menu**: "Mie Rendang" requires 1 "Mie" and 2 "Telur"
- **Inventory**: 20 "Mie", 15 "Telur"
- **Order**: Customer tries to order 10 "Mie Rendang"
- **Calculation**: 
  - Mie: 10 × 1 = 10 needed ✅ (20 available)
  - Telur: 10 × 2 = 20 needed ❌ (only 15 available)
- **Result**: ❌ Error shown: "Insufficient Telur (need 20, have 15)"

### Scenario 3: Successful Order
- **Menu**: "Kopi Panas" requires 1 "Kopi Bubuk"
- **Inventory**: 50 "Kopi Bubuk"
- **Order**: Customer orders 3 "Kopi Panas"
- **Result**: ✅ Order successful, 3 "Kopi Bubuk" deducted

## Database Structure

### Firestore Collections

```
Canteens/canteen375
├── MenuCollection/
│   ├── {menuId}/
│   │   ├── namaMenu: "Mie Rendang"
│   │   ├── harga: 15000
│   │   ├── category: "Mie"
│   │   └── ingredients: [
│   │       {
│   │         inventoryItemId: "abc123",
│   │         inventoryItemName: "Mie",
│   │         quantityNeeded: 1
│   │       },
│   │       {
│   │         inventoryItemId: "def456",
│   │         inventoryItemName: "Telur",
│   │         quantityNeeded: 2
│   │       }
│   │     ]
│   └── ...
└── Inventory/
    ├── abc123/
    │   ├── name: "Mie"
    │   ├── stock: 50
    │   └── unit: "pcs"
    ├── def456/
    │   ├── name: "Telur"
    │   ├── stock: 100
    │   └── unit: "pcs"
    └── ...
```

## Testing the Implementation

### Test Case 1: Menu Without Ingredients
- Create a menu item without ingredients
- Should always be available
- No stock deduction on order

### Test Case 2: Menu With Sufficient Stock
- Create a menu with ingredients
- Ensure all ingredients have sufficient stock
- Order should succeed
- Stock should be deducted correctly

### Test Case 3: Menu With Insufficient Stock
- Create a menu with ingredients
- Set one ingredient's stock to be insufficient
- Try to order more than available
- Should show error message and prevent order

### Test Case 4: Multiple Orders
- Order item A (uses ingredient X)
- Order item B (also uses ingredient X)
- Total usage should not exceed stock
- Should prevent when combined usage exceeds stock

### 4. Perishable Item Management (NEW)
- **Perishable Flag**: Items can be marked as `isPerishable: true`.
- **End of Day Workflow**: 
  - User can manually trigger "End of Day" to record leftover waste.
  - System automatically resets perishable stock to 0 at the start of a new day if the user forgot.
- **Waste Tracking**: Leftover stock is recorded as `stockWasted` in the daily logs.

### 5. Daily Stock Logging for Data Science (NEW)
- **Collection**: `Canteens/{canteenId}/DailyStockLogs/`
- **Document ID**: `YYYY-MM-DD_{inventoryItemId}`
- **Metrics Tracked**:
  - `startingStock`: Quantities at the start of the day.
  - `stockAdded`: Total restocks during the day.
  - `stockUsed`: Total consumed by orders.
  - `stockWasted`: Total discarded (perishables).
  - `endingStock`: Quantities at the end of the day.
- **Goal**: Enable future prediction models to optimize buying patterns.

## Implementation Details

### Data Model Updates
... (existing details) +
```dart
class DailyStockLog {
  int startingStock;
  int stockAdded;
  int stockUsed;
  int stockWasted;
  int endingStock;
}
```

### Flow for Perishables
1. **Manual Reset**: User opens moonlight icon dialog -> Inputs waste -> Stock set to 0.
2. **Automated Catch-up**: App Init -> If Today != LastResetDate -> Reset all perishables -> Log as waste.

## Benefits of New Features
1. **Operational Hygiene**: Ensures fresh ingredients are used daily.
2. **Waste Audit**: Identify which ingredients are frequently overbought.
3. **Forecasting Ready**: Structured historical data for model training.

## Future Enhancements

Potential improvements:

1. **Bulk Inventory Management**: Add/update multiple ingredients at once
2. **Low Stock Alerts**: Notify when ingredients are running low
3. **Auto-Reorder**: Automatically suggest reorder quantities
4. **Recipe Scaling**: Adjust ingredient quantities when changing portion sizes
5. **Ingredient Categories**: Group ingredients by type (beverages, dry goods, fresh produce)
6. **Expiration Tracking**: Track expiration dates for perishable ingredients
7. **Cost Tracking**: Calculate menu item costs based on ingredient prices

## Conclusion

The ingredient-based inventory system successfully implements:
- ✅ Many-to-many relationships between menu items and inventory items
- ✅ Real-time stock validation at multiple points
- ✅ Prevention of orders exceeding available stock
- ✅ Clear, user-friendly error messages
- ✅ Atomic stock deduction during order processing

This ensures accurate inventory management and prevents overselling while providing a smooth user experience.
