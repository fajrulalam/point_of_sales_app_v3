// Copy to scripts/backfills/<date>-<short-name>.js, fill in, then follow
// docs/backfill_missed_sales.md. Keep the file after applying; it is the record.
module.exports = {
  date: 'YYYY-MM-DD', // WIB day the sale really happened
  time: 'HH:mm', // WIB time, roughly when it happened
  items: [
    { menuName: 'exact menu name', quantity: 1 },
    // { menuName: 'Es Teh', quantity: 2, unitPrice: 3000 }, // unitPrice only if the price charged differs from today's menu price
  ],
  takeAwayFee: 0, // packaging fee charged on the order, if any
  paymentMethod: 'QRIS', // 'Cash' | 'QRIS' | 'Online' | 'Cash + QRIS'
  qrisAmount: 0, // only for 'Cash + QRIS': the QRIS part; the rest is cash
  moneyWasCountedInClosing: null, // only needed if that day already has an end-of-day closing: true / false
  reason: 'Forgot to enter it at the till.',
};
