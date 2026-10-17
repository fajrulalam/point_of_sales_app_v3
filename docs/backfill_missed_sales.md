# Backfilling missed sales

Use this when a sale happened on an earlier day but was never entered in the
POS. `scripts/backfill_order.js` adds it to that day's sales records without
going through the till.

> **Still the same day, and the end-of-day closing isn't done yet?** Don't
> backfill. Enter the sale in the app as normal.

Don't fake it by setting the device's date back. The app takes the order time
from the Firebase server clock but picks the day's sales record from the device
clock, so a backdated device splits one sale across two dates. It also triggers
the live side effects: stock deduction, a kitchen-queue order and a queue number.

## What a backfill changes

| Record | What happens |
|---|---|
| `DailyTransaction/{date}` | `total`, `subTotal`, `takeAwayFee`, the payment totals (`totalCash` / `totalQris` / `totalOnline`) and each item's count go up. Created if that day has no sales yet. |
| `MonthlyTransaction/{yyyy-MM}` and `YearlyTransaction/{yyyy}` | The same increases. |
| `DailyFinancialReport`, `MonthlyFinancialReport`, `YearlyFinancialReport` | Only if that day already has an end-of-day closing **and** the money was counted in it: `systemSales*` go up and `discrepancy*` go down by the same amount. Closing balances never change. See [The end-of-day closing](#the-end-of-day-closing). |
| `Canteens/canteen375/Orders/backfill-sale--…` | Audit record marked `isBackfill: true`: what was added, why, when it happened and when it was entered. It also stops the same backfill from being applied twice. |
| `memberProgramOperations/backfill-sale--…` | The same "not a member" marker every non-member sale leaves. |

Not touched:

- **The kitchen queue (`Status`) and the queue number.** Served orders are not
  kept one by one, so a backfill lives only in the totals and the audit record.
- **Stock.** The dry run lists any ingredients the items use. If stock matters,
  correct it on the Inventory screen.
- **Member points, vouchers and B2B voucher programs.** Backfills are for
  non-member sales paid by cash, QRIS or online.

## One-time setup

- Node.js, plus the Cloud Functions packages: `cd functions && npm install`.
- The service account key
  `point-of-sales-app-25e2b-firebase-adminsdk-isjye-3ddd9cdd88.json` in the
  project root. It is gitignored; never commit it. If you create a new key,
  update `KEY_PATH` at the top of the script.

## Steps

1. **Collect the facts:** the date, roughly what time, each item and quantity,
   the price charged, any packaging fee and the payment method. If that day
   already has an end-of-day closing, also find out whether this money was in
   the cash or QRIS counted at closing.
2. **Copy the template**, naming it after the date and what was sold:
   ```
   cp scripts/backfills/TEMPLATE.js scripts/backfills/2026-10-02-es-teh.js
   ```
3. **Fill it in** (see the fields below).
4. **Dry run.** Nothing is written:
   ```
   node scripts/backfill_order.js scripts/backfills/2026-10-02-es-teh.js
   ```
   Every figure is shown as before → after. Each should rise by exactly this
   sale.
5. **Apply:**
   ```
   node scripts/backfill_order.js scripts/backfills/2026-10-02-es-teh.js --apply
   ```
   It prints the new totals when done.
6. **Keep the file and commit it.** `scripts/backfills/` is the record of every
   correction.

## The config fields

| Field | What to put |
|---|---|
| `date` | The day the sale happened, `YYYY-MM-DD` (WIB). |
| `time` | Roughly when, `HH:mm` (WIB). Kept for the record only. |
| `items` | One entry per menu item: `{ menuName, quantity }`. `menuName` must match the menu exactly, including capitals and dots; if it doesn't, the script suggests close names. Add `unitPrice` only if the price charged differs from today's menu price. |
| `takeAwayFee` | Packaging fee charged on the order, or `0`. |
| `paymentMethod` | `'Cash'`, `'QRIS'`, `'Online'` or `'Cash + QRIS'`. |
| `qrisAmount` | Only for `'Cash + QRIS'`: the QRIS part. The rest counts as cash. |
| `moneyWasCountedInClosing` | Only needed if that day already has an end-of-day closing. See below. |
| `reason` | A short note. It is saved in the audit record. |

Example: two Es Teh and two Risol Mayo taken away with a Rp 2.000 packaging fee,
Rp 10.000 paid by QRIS and the rest in cash, on a day whose closing counted the
money:

```js
module.exports = {
  date: '2026-10-02',
  time: '13:30',
  items: [
    { menuName: 'Es Teh', quantity: 2 },
    { menuName: 'Risol Mayo', quantity: 2 },
  ],
  takeAwayFee: 2000,
  paymentMethod: 'Cash + QRIS',
  qrisAmount: 10000,
  moneyWasCountedInClosing: true,
  reason: 'Cashier forgot to enter it during the lunch rush.',
};
```

## The end-of-day closing

The daily financial report made at closing compares what the till should have
(`systemSales*`) with what was actually counted (`actual*`). The difference is
the discrepancy. The cashflow page builds its running balance from the counted
amounts.

| Situation | `moneyWasCountedInClosing` | Result |
|---|---|---|
| That day has no closing. | leave `null` | Sales totals are fixed. The cashflow page has no row for that day, so its balance doesn't include this money. |
| There is a closing and the money was counted in it. This is the usual case: the till held more than the system expected, so the closing shows a surplus of about this sale's amount. | `true` | `systemSales*` go up and `discrepancy*` go down, usually to about 0. The cashflow balance was already right. |
| There is a closing, but the money was not counted in it. | `false` | The closing is left as it is. The cashflow balance still doesn't include this money. |

Not sure which? Run the dry run. If that day has a closing, it shows the
counted amount, the system amount and the discrepancy for the payment method.
A surplus about the size of the sale means `true`.

In the first and last cases the cashflow balance stays short by this sale.
Fixing that means raising the closing balance of that day and of every later
day, because each day's balance builds on the one before. The script does not
do this; handle it deliberately if the cashflow balance matters.

## When the script refuses

| Message | What to do |
|---|---|
| `Fix …` followed by a list | The config still has a placeholder or an invalid value. Correct the fields listed. |
| `No menu named exactly …` | Copy the name exactly from the suggestion or from the app. |
| `Set moneyWasCountedInClosing …` | That day has a closing. Choose `true` or `false` as described above. |
| `Another backfill already exists for …` | Check that the one listed isn't this same sale. If it is a different sale, add `--force`. |
| `The closing discrepancy … was already confirmed on the dashboard` | Older dashboard versions add confirmed discrepancies into the sales totals. If that day's sales total already includes this sale, stop. If not, add `--force`. |
| `This exact backfill was already applied` | Nothing to do. Running the same file again never adds the sale twice. |

A `NOTE` about the menu price or stock ingredients is not a refusal. Just check
it matches what really happened.

## Several forgotten sales

- **Same day, one payment method:** put all the items in one file.
- **Same day, cash and QRIS:** one file with `'Cash + QRIS'`, with the total
  QRIS amount in `qrisAmount`.
- **Same day, other mixes (for example online plus cash):** one file per
  payment method. The second file needs `--force` because of the same-day check.
- **Different days:** one file per day.

## Undoing a backfill

There is no undo command. In the Firebase console:

1. Open the audit record `Canteens/canteen375/Orders/backfill-sale--…`. Its
   `sale` field lists exactly what was added: the items, `total`, `payments`,
   `takeAwayFee` and `closingAdjusted`.
2. Subtract those amounts from `DailyTransaction/{date}`,
   `MonthlyTransaction/{yyyy-MM}` and `YearlyTransaction/{yyyy}`. The fields
   are `total`, `subTotal` (the total minus `takeAwayFee`), `takeAwayFee`, the
   payment totals and each item's count.
3. If `closingAdjusted` is `true`, reverse the three financial report docs too:
   lower `systemSales*` and raise `discrepancy*` by each payment amount.
4. Delete the audit record and the `memberProgramOperations` doc with the same
   id.

The first backfill (2026-09-25, 50 × voucher 15.000) was made with an earlier
version of the script. Its audit record has a simpler `sale` field: one
`menuName`, `quantity` and `unitPrice` instead of an `items` list.
