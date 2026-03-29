# Self-Order System Documentation

This document explains the technical architecture and Firestore data structures for the **Self-Ordering System**, allowing members to place orders via their own app for counter payment and kitchen fulfillment.

## 1. Core Workflow

1.  **Placement**: Member places an order via the Member App.
2.  **Storage**: Order is saved to the `SelfOrders` collection with status `Unpaid`.
3.  **POS Detection**: The POS app listens to real-time updates and notifies the cashier.
4.  **Payment**: Customer pays at the counter. Cashier confirms the order.
5.  **Fulfillment**: Order is converted into a regular `DailyOrder` and pushed to the **Orders-To-Be-Served** app.

---

## 2. Firestore Storage Strategy

### Primary Collection
**Path**: `/Canteens/canteen375/SelfOrders/{orderId}`

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | String | Unique Firestore Document ID |
| `userId` | String | The Firebase UID of the member |
| `memberName` | String | Display name of the member |
| `shortCode` | String | 4-5 character code for customer identifying (e.g., "A1B2") |
| `status` | String | `Unpaid`, `Processing`, `Paid`, `Declined` |
| `timestamp` | Timestamp | When the order was placed |
| `processedAt` | Timestamp | When the cashier confirmed/declined (Added later) |
| `subtotal` | Number | Total price of items |
| `takeAwayFee` | Number | Fixed packaging fee if applicable |
| `total` | Number | Final payable amount (`subtotal + takeAwayFee`) |
| `declineReason`| String | Optional reason if order is rejected |

### Sub-structure: `orderItems` (List)
Each item in the `orderItems` array follows this schema:

```json
{
  "namaPesanan": "Nasi Goreng Special",
  "harga": 25000,
  "dineInQuantity": 1,
  "takeAwayQuantity": 0,
  "selectedOptions": [
    {"name": "Level Pedas", "value": "Pedas Banget"},
    {"name": "Ekstra", "value": "Telor Mata Sapi"}
  ]
}
```

---

## 3. Order Lifecycle Statuses

-   **`Unpaid`**: The initial state. Visible on the POS "Self Orders" tab.
-   **`Processing`**: Cashier has clicked the order and is currently handling payment. This prevents other cashiers from double-processing the same customer.
-   **`Paid`**: Payment successful. The order is now locked and archived.
-   **`Declined`**: Order rejected (e.g., item out of stock). Member is notified in their app.

---

## 4. Integration with Main POS Logic

When a cashier marks a Self-Order as **Paid** in `OrderConfirmationService.dart`, the system performs these automatic steps:

1.  **Stock Deduction**: Checks `InventoryService` to reduce ingredients based on the selected items.
2.  **Transaction Record**: Creates a standard entry in `/DailyTransaction/{YYYY-MM-DD}/DailyOrders/`.
3.  **Financial Totals**: Increments `totalCash`, `totalQris`, or `totalOnline` in the day's record.
4.  **Kitchen Routing**: Pushes the order to the kitchen system (another app or separate collection depends on setup).

---

## 5. Implementation Files

-   **Model**: [SelfOrder.dart](file:///Users/fajrulnuha/Documents/point_of_sales_app_v3/point_of_sales_app_v3/lib/Models/SelfOrder.dart)
-   **Logic**: [SelfOrderService.dart](file:///Users/fajrulnuha/Documents/point_of_sales_app_v3/point_of_sales_app_v3/lib/Services/SelfOrderService.dart)
-   **Processing**: [OrderConfirmationService.dart](file:///Users/fajrulnuha/Documents/point_of_sales_app_v3/point_of_sales_app_v3/lib/Services/OrderConfirmationService.dart)
