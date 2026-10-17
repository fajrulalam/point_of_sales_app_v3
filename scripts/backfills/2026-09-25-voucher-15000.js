// APPLIED on 2026-09-27 with the first version of the script, whose audit record is
// Canteens/canteen375/Orders/backfill-sale--2026-09-25-750000-QRIS--voucher_15_000_50_15000
// Kept as the record. Re-running is blocked because a backfill already exists for this date.
module.exports = {
  date: '2026-09-25',
  time: '12:00',
  items: [{ menuName: 'voucher 15.000', quantity: 50 }],
  takeAwayFee: 0,
  paymentMethod: 'QRIS',
  qrisAmount: 0,
  moneyWasCountedInClosing: null, // that day had no closing, so the cashflow page does not include this Rp 750.000
  reason: 'Sale missed at the till on 2026-09-25; entered afterwards by scripts/backfill_order.js.',
};
